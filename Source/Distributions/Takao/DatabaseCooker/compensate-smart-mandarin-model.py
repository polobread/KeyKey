#!/usr/bin/env python3
"""Build a bounded-evidence candidate from a verified source; never overwrite it."""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
from pathlib import Path
import sqlite3
import tempfile

from bigram_compensation import compensate, document_frequencies
from smart_mandarin_model import connect_readonly, file_sha256, semantic_sha256, validate_schema


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--max-log-lift", type=float, default=1.0)
    parser.add_argument("--prior", type=float, default=1000.0)
    args = parser.parse_args()
    if not math.isfinite(args.prior) or args.prior <= 0 or not math.isfinite(args.max_log_lift) or not 0 <= args.max_log_lift <= 6:
        parser.error("prior must be positive and finite; max-log-lift must be between 0 and 6")
    if args.output.exists() or args.output.resolve() == args.source.resolve():
        parser.error("choose a new candidate path; existing files are never overwritten")
    spec = importlib.util.spec_from_file_location(
        "finalizer", Path(__file__).with_name("finalize-smart-mandarin-model.py"))
    finalizer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(finalizer)
    articles, sources = finalizer.load_training(finalizer.DEFAULT_TRAINING)
    source_digest = file_sha256(args.source)
    with connect_readonly(args.source) as source:
        validate_schema(source)
        probabilities = finalizer.word_probabilities(source)
        frequencies = document_frequencies(articles, probabilities)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=args.output.parent) as temporary:
            candidate = Path(temporary) / "candidate.db"
            with sqlite3.connect(candidate) as target:
                source.backup(target)
                result = compensate(target, frequencies, args.prior, args.max_log_lift)
                if target.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                    raise ValueError("candidate integrity check failed")
            # Exclusive creation protects against an output appearing during
            # the potentially long corpus pass.
            args.output.hardlink_to(candidate)
    if file_sha256(args.source) != source_digest:
        raise ValueError("source database changed during cooking")
    result.update({"status": "experimental; requires full regression and new holdout",
                   "source_sha256": source_digest, "training": sources,
                   "transform_sha256": file_sha256(Path(__file__).with_name("bigram_compensation.py")),
                   "database_sha256": file_sha256(args.output),
                   "semantic_sha256": semantic_sha256(args.output)})
    args.output.with_suffix(".json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
