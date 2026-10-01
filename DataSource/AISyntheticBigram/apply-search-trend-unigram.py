#!/usr/bin/env python3
"""Insert positive, deduplicated search-trend unigrams into a database copy."""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
import shutil
import sqlite3


HERE = Path(__file__).resolve().parent
DEFAULT_LEXICON = HERE / "search-trend-unigram.tsv"
DEFAULT_MANIFEST = HERE / "smart-mandarin-model-manifest.json"
CONSONANTS = " ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ"
MEDIALS = " ㄧㄨㄩ"
VOWELS = " ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ"
TONES = " ˊˇˋ˙"


def reading_for_query(query: str) -> str:
    order = ord(query[0]) - 48 + (ord(query[1]) - 48) * 79
    return (
        CONSONANTS[order % 22]
        + MEDIALS[order // 22 % 4]
        + VOWELS[order // 88 % 14]
        + TONES[order // 1232]
    ).replace(" ", "")


def query_for_reading(value: str) -> str:
    order = 0
    used = set()
    for character in value:
        for group, (symbols, scale) in enumerate(
            ((CONSONANTS, 1), (MEDIALS, 22), (VOWELS, 88), (TONES, 1232))
        ):
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


def load(path: Path) -> list[dict[str, object]]:
    with path.open(encoding="utf-8", newline="") as source:
        rows = list(csv.DictReader(source, delimiter="\t"))
    if not rows or tuple(rows[0]) != ("詞", "詞頻", "注音"):
        raise ValueError(f"{path}: expected 詞、詞頻、注音 columns")
    result = []
    seen = set()
    for number, row in enumerate(rows, 2):
        word = row["詞"]
        count = int(row["詞頻"])
        syllables = row["注音"].split()
        if not word or word in seen or count < 0 or len(syllables) != len(word):
            raise ValueError(f"{path}:{number}: invalid or duplicate row")
        seen.add(word)
        result.append({
            "word": word,
            "count": count,
            "reading": row["注音"],
            "query": "".join(query_for_reading(value) for value in syllables),
        })
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("--lexicon", type=Path, default=DEFAULT_LEXICON)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        if args.database.resolve() == args.output.resolve():
            raise ValueError("output must differ from the source database")
        entries = load(args.lexicon)
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        unigram_total_count = int(manifest["unigram_total_count"])
        args.output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.database, args.output)
        inserted = []
        zero = []
        with sqlite3.connect(args.output) as database:
            for entry in entries:
                if not entry["count"]:
                    zero.append(entry["word"])
                    continue
                if database.execute(
                    "SELECT 1 FROM unigrams WHERE current=? LIMIT 1", (entry["word"],)
                ).fetchone():
                    raise ValueError(f"duplicate unigram reached apply step: {entry['word']}")
                probability = math.log10(int(entry["count"]) / unigram_total_count)
                database.execute(
                    "INSERT INTO unigrams(qstring,current,probability,backoff) VALUES(?,?,?,0.0)",
                    (entry["query"], entry["word"], probability),
                )
                inserted.append({**entry, "probability": probability})
            integrity = database.execute("PRAGMA integrity_check").fetchone()[0]
            rows = {
                "unigrams": database.execute("SELECT count(*) FROM unigrams").fetchone()[0],
                "bigrams": database.execute("SELECT count(*) FROM bigrams").fetchone()[0],
            }
        if integrity != "ok":
            raise ValueError(f"output integrity check failed: {integrity}")
        report = {
            "source_database": str(args.database),
            "output_database": str(args.output),
            "unigram_total_count": unigram_total_count,
            "inserted": len(inserted),
            "zero_count_skipped": len(zero),
            "rows": rows,
            "entries": inserted,
            "zero_count_terms": zero,
        }
        text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        if args.report:
            args.report.write_text(text, encoding="utf-8")
        print(text, end="")
    except (OSError, ValueError, KeyError, TypeError, sqlite3.Error) as error:
        args.output.unlink(missing_ok=True)
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
