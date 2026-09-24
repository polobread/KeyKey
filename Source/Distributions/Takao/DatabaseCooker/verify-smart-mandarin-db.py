#!/usr/bin/env python3
"""Verify the Smart Mandarin database snapshot used by version 1.2.10."""

import sqlite3
import sys
from pathlib import Path


EXPECTED_BIGRAM_ROWS = 885_614


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

    print(f"Smart Mandarin database verified: {bigram_rows} bigrams ({path})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
