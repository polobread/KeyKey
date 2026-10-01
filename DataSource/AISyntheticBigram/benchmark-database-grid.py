#!/usr/bin/env python3
"""Compare already-built language-model databases on one frozen article sample."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sqlite3

from typing_batch import (evaluate_articles, load_manifest_articles, prepare_articles,
                          write_comparison)
from typing_cost import DEFAULT_DB, Policy, sha256, write_json


def parse_model(value):
    if "=" not in value:
        raise ValueError(f"Expected LABEL=DATABASE: {value}")
    label, raw_path = value.split("=", 1)
    if not label or not raw_path:
        raise ValueError(f"Expected LABEL=DATABASE: {value}")
    return label, Path(raw_path)


def load_trace(path, label, database, count):
    trace = json.loads(path.read_text(encoding="utf-8"))
    if (trace.get("version") != label or trace.get("database_sha256") != sha256(database)
            or len(trace.get("reports", [])) != count):
        raise ValueError(f"Trace does not match {label}, database, and complete cohort: {path}")
    return trace["reports"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", type=Path, required=True)
    parser.add_argument("--reference-db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--baseline", required=True, metavar="LABEL=DATABASE")
    parser.add_argument("--baseline-trace", type=Path)
    parser.add_argument("--reuse-trace", action="append", default=[], metavar="LABEL=TRACE")
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("models", nargs="+", metavar="LABEL=DATABASE")
    args = parser.parse_args()
    try:
        sample = json.loads(args.sample.read_text(encoding="utf-8"))
        baseline_label, baseline_database = parse_model(args.baseline)
        versions = {baseline_label: baseline_database}
        for value in args.models:
            label, database = parse_model(value)
            if label in versions:
                raise ValueError(f"Duplicate model label: {label}")
            versions[label] = database
        for label, database in versions.items():
            if not database.is_file():
                raise ValueError(f"Missing database for {label}: {database}")
        articles = load_manifest_articles(sample)
        _, documents = prepare_articles(articles, args.reference_db, baseline_database)
        identifiers = [row["id"] for row in sample["articles"]]
        reports = {}
        if args.baseline_trace:
            reports[baseline_label] = load_trace(
                args.baseline_trace, baseline_label, baseline_database, sample["count"])
        for value in args.reuse_trace:
            label, path = parse_model(value)
            if label not in versions or label in reports:
                raise ValueError(f"Trace label is absent or duplicated: {label}")
            reports[label] = load_trace(path, label, versions[label], sample["count"])
        args.output.mkdir(parents=True, exist_ok=True)
        for index, (label, database) in enumerate(versions.items()):
            if label in reports:
                continue
            reports[label] = evaluate_articles(
                documents, database, Policy(), identifiers, label, args.jobs)
            write_json(args.output / f"traces-{index}.json", {
                "version": label, "database_sha256": sha256(database), "reports": reports[label]})
        result = write_comparison(
            args.output / "comparison.json", sample, versions, reports, Policy(), args.reference_db)
        eligible = [(row["evaluated_actions_after"], label)
                    for label, row in result["comparisons"].items() if row["passes"]]
        selection = {
            "selected": min(eligible)[1] if eligible else baseline_label,
            "sample_role": "validation; selection requires a new disjoint holdout",
            "requires_new_holdout": bool(eligible),
        }
        write_json(args.output / "selection.json", selection)
        print(json.dumps({"comparisons": result["comparisons"], **selection},
                         ensure_ascii=False, indent=2))
    except (ValueError, OSError, sqlite3.Error, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
