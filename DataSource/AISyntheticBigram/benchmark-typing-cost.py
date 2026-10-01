#!/usr/bin/env python3
"""Compare full, fixed random article samples; never hide per-article regressions."""
import argparse
import json
import sqlite3
import subprocess
from typing_cost import DEFAULT_DB, Policy, resolve_version, sha256, write_json
from typing_batch import sample_articles, prepare_articles, evaluate_articles, write_comparison
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("versions", nargs="+", help="baseline first, then candidates")
    parser.add_argument("--count", type=int, default=50)
    parser.add_argument("--seed", type=int, default=20260926)
    parser.add_argument("--reference-db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--output", type=Path, required=True, help="new result directory")
    args = parser.parse_args()
    try:
        if len(args.versions) < 2 or len(set(args.versions)) != len(args.versions):
            raise ValueError("Supply at least two distinct model versions")
        args.output.mkdir(parents=True, exist_ok=True)
        articles, sample = sample_articles(args.count, args.seed, args.output / "sample.json")
        _, documents = prepare_articles(articles, args.reference_db)
        versions = {name: resolve_version(name) for name in args.versions}
        policy = Policy()
        reports = {}
        for i, (name, database) in enumerate(versions.items()):
            reports[name] = evaluate_articles(documents, database, policy, [a["id"] for a in sample["articles"]], name)
            write_json(args.output / f"traces-{i}.json", {"version": name, "database_sha256": sha256(database), "reports": reports[name]})
        result = write_comparison(args.output / "comparison.json", sample, versions, reports, policy, args.reference_db)
        print(json.dumps(result["comparisons"], ensure_ascii=False, indent=2))
    except (ValueError, OSError, sqlite3.Error, subprocess.SubprocessError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
