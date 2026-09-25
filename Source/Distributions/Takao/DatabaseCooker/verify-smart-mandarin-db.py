#!/usr/bin/env python3
"""Verify the Smart Mandarin database snapshot used by version 1.3.0."""

import sqlite3
import sys
from pathlib import Path


EXPECTED_BIGRAM_ROWS = 885_627
EXPECTED_SINGLE_SYLLABLE_READINGS = 1_345
EXPECTED_SINGLE_SYLLABLES = {
    "L_": ("ㄅㄨˋ", "不"),
    "ac": ("ㄌㄧㄝˋ", "列"),
    "8_": ("ㄇㄧˋ", "密"),
    "@j": ("ㄧㄣˋ", "印"),
    "Qd": ("ㄉㄞˋ", "代"),
    "IJ": ("ㄏㄨㄢˊ", "環"),
    "1_": ("ㄖˋ", "日"),
    "\\O": ("ㄋㄧˇ", "你"),
    "Dd": ("ㄒㄩㄝˋ", "血"),
    "6C": ("ㄏㄜˊ", "和"),
    "{h": ("ㄏㄢˋ", "漢"),
}


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <database>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1]).resolve()
    if not path.is_file():
        print(f"Smart Mandarin database is missing: {path}", file=sys.stderr)
        return 1

    try:
        with sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True) as database:
            bigram_rows = database.execute("SELECT COUNT(*) FROM bigrams").fetchone()[0]
            integrity = database.execute("PRAGMA integrity_check").fetchone()[0]
            first_candidates = {
                query: database.execute(
                    "SELECT current FROM unigrams WHERE qstring = ? "
                    "ORDER BY probability DESC, rowid LIMIT 1",
                    (query,),
                ).fetchone()
                for query in EXPECTED_SINGLE_SYLLABLES
            }
            # Audit every single-syllable reading, not only the hand-picked
            # examples below. A first choice must exist in the phonetic table
            # for the same reading; otherwise it cannot be selected reliably
            # across the desktop and mobile implementations.
            all_first_candidates = database.execute(
                "SELECT qstring, current FROM ("
                "SELECT qstring, current, ROW_NUMBER() OVER ("
                "PARTITION BY qstring ORDER BY probability DESC, rowid"
                ") AS rank FROM unigrams "
                "WHERE length(qstring) = 2 AND length(current) = 1"
                ") WHERE rank = 1"
            ).fetchall()
            missing_phonetic_entries = [
                (query, candidate)
                for query, candidate in all_first_candidates
                if database.execute(
                    'SELECT 1 FROM "Mandarin-bpmf-cin" '
                    'WHERE key = ? AND value = ? LIMIT 1',
                    (query, candidate),
                ).fetchone() is None
            ]
    except sqlite3.Error as error:
        print(f"Unable to verify Smart Mandarin database {path}: {error}", file=sys.stderr)
        return 1

    if bigram_rows != EXPECTED_BIGRAM_ROWS or integrity != "ok":
        print(
            f"Smart Mandarin database {path}: {bigram_rows} bigrams, "
            f"integrity={integrity}; expected {EXPECTED_BIGRAM_ROWS} and ok",
            file=sys.stderr,
        )
        return 1

    for query, (reading, expected) in EXPECTED_SINGLE_SYLLABLES.items():
        row = first_candidates[query]
        actual = row[0] if row else None
        if actual != expected:
            print(
                f"Smart Mandarin {reading}: first candidate {actual!r}; "
                f"expected {expected!r}",
                file=sys.stderr,
            )
            return 1

    if (len(all_first_candidates) != EXPECTED_SINGLE_SYLLABLE_READINGS
            or missing_phonetic_entries):
        print(
            f"Smart Mandarin single-syllable audit: "
            f"{len(all_first_candidates)} readings, "
            f"{len(missing_phonetic_entries)} first choices missing from CIN; "
            f"expected {EXPECTED_SINGLE_SYLLABLE_READINGS} readings; "
            f"examples: {missing_phonetic_entries[:5]}",
            file=sys.stderr,
        )
        return 1

    print(
        f"Smart Mandarin database verified: {bigram_rows} bigrams, "
        f"{len(all_first_candidates)} first syllables ({path})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
