#!/usr/bin/env python3
"""Freeze disjoint 800/750/750 article cohorts for unigram work."""
import argparse
import json
from pathlib import Path

from typing_batch import cohort_manifest, partition_articles
from typing_cost import write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=20260926)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        args.output.mkdir(parents=True, exist_ok=True)
        partition_path = args.output / "partition.json"
        _, partition = partition_articles(args.seed, 800, 750, partition_path)
        for name in ("training", "validation", "test"):
            path = args.output / f"{name}.json"
            expected = cohort_manifest(partition, name)
            if path.exists() and json.loads(path.read_text(encoding="utf-8")) != expected:
                raise ValueError(f"Frozen cohort differs: {path}")
            if not path.exists():
                write_json(path, expected)
        print(json.dumps({
            "partition": str(partition_path),
            "seed": args.seed,
            "training": 800,
            "validation": 750,
            "test": 750,
        }, ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
