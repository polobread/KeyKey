#!/usr/bin/env python3
"""Apply the user-reviewed whole-phrase supplement to a new candidate copy."""
import argparse
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile

from phrase_unigram_supplement import apply
from smart_mandarin_model import connect_readonly, file_sha256, semantic_sha256, validate_schema

ROOT = Path(__file__).resolve().parents[4]
DATA = ROOT / "DataSource/AISyntheticBigram"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--supplement", type=Path, default=DATA / "common-phrase-unigram.tsv")
    args = parser.parse_args()
    if args.output.exists() or args.output.resolve() == args.source.resolve():
        parser.error("choose a new output path; never overwrite a model")
    manifest = json.loads((DATA / "smart-mandarin-model-manifest.json").read_text(encoding="utf-8"))
    original_hash = file_sha256(args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output.parent) as temporary:
        candidate = Path(temporary) / "candidate.db"
        with closing(connect_readonly(args.source)) as source, closing(sqlite3.connect(candidate)) as target:
            validate_schema(source)
            source.backup(target)
            with target:
                entries = apply(target, args.supplement, manifest["unigram_total_count"])
            if target.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                raise ValueError("candidate integrity check failed")
        if file_sha256(args.source) != original_hash:
            raise ValueError("source changed while applying overlay")
        args.output.hardlink_to(candidate)
    report = {"source_sha256": original_hash, "database_sha256": file_sha256(args.output),
              "semantic_sha256": semantic_sha256(args.output),
              "supplement_sha256": file_sha256(args.supplement), "entries": entries}
    args.output.with_suffix(".json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
