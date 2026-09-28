#!/usr/bin/env python3
"""Verify that a cooked database contains the selected cross-platform LM."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sqlite3

from smart_mandarin_model import verify_manifest


ROOT = Path(__file__).resolve().parents[4]
DEFAULT_MANIFEST = (
    ROOT / "DataSource/AISyntheticBigram/smart-mandarin-model-manifest.json"
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()
    try:
        print(json.dumps(
            verify_manifest(args.database, args.manifest),
            ensure_ascii=False,
            indent=2,
        ))
    except (OSError, ValueError, KeyError, TypeError, sqlite3.Error) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
