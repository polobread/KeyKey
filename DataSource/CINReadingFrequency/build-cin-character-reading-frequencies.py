#!/usr/bin/env python3
"""Generate proposed counts for positive-frequency, multi-reading CIN characters.

No database is opened and no cooker is run. This table is not yet a model input.
Read only %chardef, canonicalize readings like rebuild_model.standard_cin_query,
and keep the first occurrence of each (character, qstring).

For each reading, scan CIN order. Single-reading characters retain their source
counts as anchors. A multi-reading character gets min(source_count,
ratio * minimum preceding positive candidate count), or its full source count
when there is no preceding positive candidate. Earlier adjusted multi-reading
counts participate in that minimum. Missing/zero counts and phonetic-symbol
candidates are not anchors (their CIN ranks are still retained).
The output contains replacement counts, never additive bonuses or observations.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import csv
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, localcontext
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
GROUPS = (
    (" ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ", 1),
    (" ㄧㄨㄩ", 22), (" ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ", 88), (" ˊˇˋ˙", 1232),
)
PHONETIC_SYMBOLS = frozenset("".join(symbols for symbols, _ in GROUPS).replace(" ", ""))
FIELDS = (
    "character", "reading", "qstring", "cin_rank", "positive_rank",
    "source_count", "target_count", "reading_count", "cin_code", "cin_line",
    "limit_character", "limit_cin_rank", "limit_count", "count_cap", "adjustment",
)


@dataclass(frozen=True)
class Entry:
    character: str
    query: str
    reading: str
    code: str
    line: int


def query_for_code(code, keys):
    try:
        glyphs = "".join(keys[key] for key in code)
    except KeyError as error:
        raise ValueError(f"unknown CIN key in {code!r}: {error}") from error
    order = 0
    parts = []
    # Last component wins, matching the current source CIN converter.
    for symbols, scale in GROUPS:
        matches = [glyph for glyph in glyphs if glyph != " " and glyph in symbols]
        component = matches[-1] if matches else ""
        parts.append(component)
        if component:
            order += symbols.index(component) * scale
    return chr(48 + order % 79) + chr(48 + order // 79), "".join(parts)


def load_cin(path):
    keys, groups, by_character = {}, {}, defaultdict(set)
    seen, duplicates = {}, []
    section = None
    for number, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        fields = line.split()
        if len(fields) == 2 and fields[0] in ("%keyname", "%chardef"):
            section = fields[0] if fields[1] == "begin" else None
            continue
        if len(fields) != 2 or line.lstrip().startswith("#"):
            continue
        if section == "%keyname":
            keys[fields[0]] = fields[1]
        elif section == "%chardef" and len(fields[1]) == 1:
            code, character = fields
            query, reading = query_for_code(code, keys)
            key = (character, query)
            if key in seen:
                duplicates.append({
                    "character": character, "qstring": query, "reading": reading,
                    "first_line": seen[key].line, "first_code": seen[key].code,
                    "duplicate_line": number, "duplicate_code": code,
                })
                continue
            entry = Entry(character, query, reading, code, number)
            seen[key] = entry
            groups.setdefault(query, []).append(entry)
            by_character[character].add(query)
    if not groups:
        raise ValueError(f"{path}: no CIN character definitions")
    return groups, by_character, duplicates


def load_counts(path):
    result = {}
    for number, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        fields = line.split()
        if not fields or line.lstrip().startswith("#"):
            continue
        if len(fields) != 2 or not fields[1].isascii() or not fields[1].isdigit():
            raise ValueError(f"{path}:{number}: expected word and nonnegative integer count")
        word, count = fields[0], int(fields[1])
        # Source consumers use the last occurrence (three multi-word entries
        # have a zero-count row followed by a positive-count row).
        result[word] = count
    return result


def parse_ratio(value):
    try:
        ratio = Decimal(value)
    except InvalidOperation as error:
        raise ValueError("ratio must be a finite decimal in (0, 1)") from error
    if not ratio.is_finite() or not 0 < ratio < 1:
        raise ValueError("ratio must be a finite decimal in (0, 1)")
    return ratio


def decimal_text(value):
    text = format(value, "f")
    return text.rstrip("0").rstrip(".") if "." in text else text


def build_rows(groups, by_character, counts, ratio):
    ratio = parse_ratio(str(ratio))
    targets = {character for character, queries in by_character.items()
               if len(queries) > 1 and counts.get(character, 0) > 0
               and character not in PHONETIC_SYMBOLS}
    rows = []
    with localcontext() as context:
        context.prec = 80
        for query, entries in groups.items():
            minimum = None
            positive_rank = 0
            for cin_rank, entry in enumerate(entries, 1):
                source_count = counts.get(entry.character, 0)
                if source_count <= 0 or entry.character in PHONETIC_SYMBOLS:
                    continue
                positive_rank += 1
                adjusted = Decimal(source_count)
                cap = minimum[0] * ratio if minimum else None
                is_target = entry.character in targets
                if is_target and cap is not None:
                    adjusted = min(adjusted, cap)
                if is_target:
                    rows.append({
                        "character": entry.character, "reading": entry.reading,
                        "qstring": query, "cin_rank": cin_rank, "positive_rank": positive_rank,
                        "source_count": source_count, "target_count": decimal_text(adjusted),
                        "reading_count": len(by_character[entry.character]),
                        "cin_code": entry.code, "cin_line": entry.line,
                        "limit_character": minimum[1] if minimum else "",
                        "limit_cin_rank": minimum[2] if minimum else "",
                        "limit_count": decimal_text(minimum[0]) if minimum else "",
                        "count_cap": decimal_text(cap) if cap is not None else "",
                        "adjustment": ("capped" if adjusted < source_count else
                                       "cin_first" if cin_rank == 1 else
                                       "first_positive" if minimum is None else "source_lower"),
                    })
                # Non-target single-reading characters keep their original count.
                if minimum is None or adjusted < minimum[0]:
                    minimum = (adjusted, entry.character, cin_rank)
    return rows, targets


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_name(path):
    path = Path(path).resolve()
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cin", type=Path, default=ROOT / "Source/DataTables/bpmf-ext.cin")
    parser.add_argument("--counts", type=Path, default=ROOT / "DataSource/McBopomofo/phrase.occ")
    parser.add_argument("--ratio", default="0.9",
                        help="cap below preceding minimum; default 0.9; must be in (0,1)")
    parser.add_argument("--output", type=Path, default=HERE / "cin-character-reading-frequencies.tsv")
    parser.add_argument("--report", type=Path, default=HERE / "cin-character-reading-frequencies-report.json")
    args = parser.parse_args()
    try:
        ratio = parse_ratio(args.ratio)
        sources = {args.cin.resolve(), args.counts.resolve(), Path(__file__).resolve()}
        if args.output.resolve() in sources or args.report.resolve() in sources or args.output.resolve() == args.report.resolve():
            raise ValueError("outputs must be distinct from each other and all source files")
        groups, by_character, duplicates = load_cin(args.cin)
        counts = load_counts(args.counts)
        rows, targets = build_rows(groups, by_character, counts, ratio)
    except ValueError as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    report = {
        "role": "proposed source-derived character/reading replacement counts; not cooked or adopted",
        "policy": "only positive-frequency multi-reading characters are outputs; single-reading peers "
                  "are unchanged anchors; target=min(source_count,ratio*minimum_preceding_positive_count); "
                  "first positive non-phonetic candidate retains full count; no redistribution",
        "ratio": decimal_text(ratio),
        "sources": [{"file": source_name(path), "sha256": sha256(path)}
                    for path in (args.cin, args.counts, Path(__file__))],
        "statistics": {
            "repeated_single_characters": sum(len(queries) > 1 for queries in by_character.values()),
            "positive_multi_reading_characters": len(targets),
            "output_character_reading_rows": len(rows),
            "reading_groups": len({row["qstring"] for row in rows}),
            "capped_rows": sum(row["adjustment"] == "capped" for row in rows),
            "source_count_retained_rows": sum(row["adjustment"] != "capped" for row in rows),
            "cin_first_rows": sum(row["cin_rank"] == 1 for row in rows),
            "first_positive_after_missing_or_zero_rows": sum(row["adjustment"] == "first_positive" for row in rows),
            "canonical_duplicate_rows_skipped": len(duplicates),
        },
        "phonetic_symbols_excluded_as_anchors": [
            {"character": character, "source_count": counts[character]}
            for character in sorted(by_character)
            if character in PHONETIC_SYMBOLS and counts.get(character, 0) > 0
        ],
        "canonical_duplicates": duplicates,
        "output": {"file": source_name(args.output), "sha256": sha256(args.output)},
        "limitations": [
            "CIN rank is a prior, not measured pronunciation frequency.",
            "Counts are replacement weights; do not add them to source counts.",
            "Only multi-reading targets are calibrated; the order among unchanged single-reading peers is not enforced.",
            "Missing/zero-frequency and phonetic-symbol predecessors do not cap positive candidates.",
            "No Unigram/Bigram, source count, model manifest or cooker behavior is changed.",
        ],
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["statistics"], ensure_ascii=False))


if __name__ == "__main__":
    main()
