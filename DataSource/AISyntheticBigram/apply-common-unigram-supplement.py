#!/usr/bin/env python3
"""Apply the reviewed common-word unigram overlay to a copy of KeyKey.db."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import shutil
import sqlite3

ROOT = Path(__file__).resolve().parent
DEFAULT_SUPPLEMENT = ROOT / "common-unigram-supplement.tsv"
DEFAULT_COUNTS = ROOT.parent / "McBopomofo" / "phrase.occ"
CONSONANTS = " ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ"
MEDIALS = " ㄧㄨㄩ"
VOWELS = " ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ"
TONES = " ˊˇˋ˙"


def sha256(path: Path) -> str:
    with path.open("rb") as source:
        if hasattr(hashlib, "file_digest"):
            return hashlib.file_digest(source, "sha256").hexdigest()
        return hashlib.sha256(source.read()).hexdigest()


def reading_for_query(query: str) -> str:
    if len(query) != 2 or any(not 48 <= ord(character) <= 126 for character in query):
        raise ValueError(f"invalid syllable query: {query!r}")
    order = ord(query[0]) - 48 + (ord(query[1]) - 48) * 79
    if not 0 < order < 6160:
        raise ValueError(f"invalid syllable query: {query!r}")
    return (
        CONSONANTS[order % 22]
        + MEDIALS[order // 22 % 4]
        + VOWELS[order // 88 % 14]
        + TONES[order // 1232]
    ).replace(" ", "")


def query_for_reading(value: str) -> str:
    order = 0
    used: set[int] = set()
    groups = ((CONSONANTS, 1), (MEDIALS, 22), (VOWELS, 88), (TONES, 1232))
    for character in value:
        for group, (symbols, scale) in enumerate(groups):
            if character != " " and character in symbols:
                if group in used:
                    raise ValueError(f"invalid reading: {value}")
                used.add(group)
                order += symbols.index(character) * scale
                break
        else:
            raise ValueError(f"invalid reading: {value}")
    query = chr(48 + order % 79) + chr(48 + order // 79)
    if not used or not (used - {3}) or reading_for_query(query) != value:
        raise ValueError(f"invalid reading: {value}")
    return query


def validate_db(path: Path) -> None:
    uri = path.resolve().as_uri() + "?mode=ro"
    with sqlite3.connect(uri, uri=True) as db:
        expected = {
            "unigrams": ["qstring", "current", "probability", "backoff"],
            "bigrams": ["qstring", "previous", "current", "probability"],
        }
        for table, columns in expected.items():
            actual = [row[1] for row in db.execute(f"PRAGMA table_info({table})")]
            if actual != columns:
                raise ValueError(f"{path}: requires shared KeyKey.db schema: {table} {columns}")
        special = db.execute(
            "SELECT count(*) FROM unigrams WHERE qstring IN ('!', '$', '*')"
        ).fetchone()[0]
        if special != 3:
            raise ValueError(f"{path}: missing BOS/EOS/UNK unigrams")


def load_counts(path: Path) -> dict[str, int]:
    counts: dict[str, int] = {}
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        fields = raw.split()
        if len(fields) != 2 or not fields[1].isdigit():
            continue
        word, raw_count = fields
        # Match SmartMandarinCooker.rb: if the upstream file contains a
        # duplicate spelling, the later occurrence is the effective count.
        counts[word] = int(raw_count)
    if not counts:
        raise ValueError(f"{path}: no occurrence counts")
    return counts


def load_supplement(path: Path, source_counts: dict[str, int]) -> list[dict[str, object]]:
    with path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source, delimiter="\t")
        required = {
            "word", "reading", "source_count", "target_count", "competitor",
            "competitor_count", "training_occurrences", "validation_improved_articles", "reason",
        }
        if set(reader.fieldnames or ()) != required:
            raise ValueError(f"{path}: expected columns {sorted(required)}")
        entries = []
        seen_words: set[str] = set()
        for line_number, row in enumerate(reader, 2):
            word = row["word"]
            competitor = row["competitor"]
            if not word or word in seen_words:
                raise ValueError(f"{path}:{line_number}: empty or duplicate word {word!r}")
            seen_words.add(word)
            syllables = row["reading"].split()
            if len(syllables) != len(word):
                raise ValueError(f"{path}:{line_number}: reading length does not match {word!r}")
            try:
                source_count = int(row["source_count"])
                target_count = int(row["target_count"])
                competitor_count = int(row["competitor_count"])
                training_occurrences = int(row["training_occurrences"])
                improved_articles = int(row["validation_improved_articles"])
            except ValueError as error:
                raise ValueError(f"{path}:{line_number}: counts must be integers") from error
            if min(source_count, target_count, competitor_count, training_occurrences, improved_articles) < 1:
                raise ValueError(f"{path}:{line_number}: counts must be positive")
            if source_counts.get(word) != source_count:
                raise ValueError(
                    f"{path}:{line_number}: {word} source count changed from {source_count} "
                    f"to {source_counts.get(word)}; analyze again before applying the overlay"
                )
            if source_counts.get(competitor) != competitor_count:
                raise ValueError(
                    f"{path}:{line_number}: {competitor} count changed from {competitor_count} "
                    f"to {source_counts.get(competitor)}; analyze again before applying the overlay"
                )
            if target_count != competitor_count + 1 or target_count <= source_count:
                raise ValueError(
                    f"{path}:{line_number}: target must be exactly one above the reviewed competitor"
                )
            query = "".join(query_for_reading(syllable) for syllable in syllables)
            entries.append({
                "word": word,
                "reading": row["reading"],
                "query": query,
                "source_count": source_count,
                "target_count": target_count,
                "competitor": competitor,
                "competitor_count": competitor_count,
                "training_occurrences": training_occurrences,
                "validation_improved_articles": improved_articles,
                "reason": row["reason"],
            })
    if not entries:
        raise ValueError(f"{path}: no supplement entries")
    return entries


def symmetric_difference_count(db: sqlite3.Connection, columns: str, table: str) -> int:
    return sum(
        db.execute(
            f"SELECT count(*) FROM (SELECT {columns} FROM {left}.{table} "
            f"EXCEPT SELECT {columns} FROM {right}.{table})"
        ).fetchone()[0]
        for left, right in (("main", "original"), ("original", "main"))
    )


def apply(source: Path, output: Path, supplement: Path, counts_path: Path) -> dict[str, object]:
    validate_db(source)
    if source.resolve() == output.resolve():
        raise ValueError("source and output databases must differ")
    report_path = output.with_suffix(".supplement-report.json")
    if output.exists() or report_path.exists():
        raise ValueError("refuse to overwrite an existing output or report")

    entries = load_supplement(supplement, load_counts(counts_path))
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, output)
    applied = []
    try:
        with sqlite3.connect(output) as db:
            for entry in entries:
                rows = db.execute(
                    "SELECT rowid, probability, backoff FROM unigrams WHERE qstring=? AND current=?",
                    (entry["query"], entry["word"]),
                ).fetchall()
                if len(rows) != 1:
                    raise ValueError(
                        f"database has {len(rows)} unigram rows for {entry['word']!r} and its reviewed reading"
                    )
                rowid, before, backoff = rows[0]
                bonus = math.log10(entry["target_count"] / entry["source_count"])
                after = before + bonus
                db.execute("UPDATE unigrams SET probability=? WHERE rowid=?", (after, rowid))
                applied.append({
                    **entry,
                    "probability_before": before,
                    "probability_bonus": bonus,
                    "probability_after": after,
                    "backoff": backoff,
                })
            db.commit()
            db.execute("ATTACH DATABASE ? AS original", (source.resolve().as_uri() + "?mode=ro",))
            if symmetric_difference_count(db, "qstring,current,backoff", "unigrams"):
                raise ValueError("overlay changed unigram identities or backoff values")
            if symmetric_difference_count(db, "qstring,previous,current,probability", "bigrams"):
                raise ValueError("overlay changed bigrams")
            changed_probabilities = db.execute(
                "SELECT count(*) FROM main.unigrams AS m JOIN original.unigrams AS o "
                "ON m.qstring=o.qstring AND m.current=o.current WHERE m.probability != o.probability"
            ).fetchone()[0]
            if changed_probabilities != len(applied):
                raise ValueError(
                    f"expected {len(applied)} changed unigram probabilities, found {changed_probabilities}"
                )
            if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                raise ValueError("output database failed integrity check")
    except Exception:
        output.unlink(missing_ok=True)
        raise

    report = {
        "method": (
            "Raise each reviewed common phrase only to one occurrence above its same-reading competitor. "
            "McBopomofo source files, unigram backoffs, and every bigram remain unchanged."
        ),
        "source": {"file": str(source), "sha256": sha256(source)},
        "supplement": {"file": str(supplement), "sha256": sha256(supplement)},
        "occurrence_source": {"file": str(counts_path), "sha256": sha256(counts_path)},
        "changed_unigram_probabilities": len(applied),
        "changed_unigram_backoffs": 0,
        "changed_bigrams": 0,
        "entries": applied,
        "output": {"file": str(output), "sha256": sha256(output)},
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="source KeyKey.db; it is never modified")
    parser.add_argument("--output", type=Path, required=True, help="new database path")
    parser.add_argument("--supplement", type=Path, default=DEFAULT_SUPPLEMENT)
    parser.add_argument("--counts", type=Path, default=DEFAULT_COUNTS)
    args = parser.parse_args()
    try:
        report = apply(args.source, args.output, args.supplement, args.counts)
        print(json.dumps({
            "changed_unigram_probabilities": report["changed_unigram_probabilities"],
            "changed_unigram_backoffs": report["changed_unigram_backoffs"],
            "changed_bigrams": report["changed_bigrams"],
            "output": report["output"],
        }, ensure_ascii=False, indent=2))
    except (ValueError, OSError, sqlite3.Error, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
