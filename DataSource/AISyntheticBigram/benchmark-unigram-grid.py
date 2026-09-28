#!/usr/bin/env python3
"""Evaluate globally generated unigram count files against the paired baseline."""
import argparse
import importlib.util
import json
from pathlib import Path
import sqlite3
import subprocess

from typing_cost import DEFAULT_DB, Policy, sha256, write_json
from typing_batch import load_manifest_articles, prepare_articles, evaluate_articles, write_comparison


ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("project_unigram_benchmark", ROOT / "benchmark-project-unigram.py")
project_benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(project_benchmark)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--sample", type=Path, required=True)
    parser.add_argument("--reference-db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--run-name", default="grid")
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--baseline-trace", type=Path,
                        help="reuse an immutable complete baseline trace for this exact cohort")
    parser.add_argument("--reuse-trace", action="append", default=[], metavar="LABEL=TRACE",
                        help="reuse a complete immutable trace for any model in this run")
    parser.add_argument("variants", nargs="*", help="LABEL=COUNTS_FILE")
    args = parser.parse_args()
    try:
        sample = json.loads(args.sample.read_text(encoding="utf-8"))
        articles = load_manifest_articles(sample)
        baseline = args.directory / "mc-bopomofo-control.db"
        corpus = args.directory / "project-occurrence.corpus.txt"
        if not corpus.exists():
            raise ValueError("Run build-project-unigram.py first")
        versions = {"mc-bopomofo-control": baseline}
        build_path = args.directory / "grid-builds.json"
        builds = json.loads(build_path.read_text(encoding="utf-8")) if build_path.exists() else {}
        if baseline.exists():
            if "mc-bopomofo-control" not in builds or sha256(baseline) != builds["mc-bopomofo-control"].get("database_sha256"):
                raise ValueError("Existing baseline has no matching immutable build record")
        else:
            builds["mc-bopomofo-control"] = project_benchmark.build_model(
                args.reference_db, project_benchmark.BASE_COUNTS, corpus, baseline, False)
            write_json(build_path, builds)
        for argument in args.variants:
            if "=" not in argument:
                raise ValueError(f"Expected LABEL=COUNTS_FILE: {argument}")
            label, raw_path = argument.split("=", 1)
            if not label or label in versions:
                raise ValueError(f"Duplicate or empty label: {label!r}")
            counts = Path(raw_path)
            database = args.directory / f"{label}.db"
            if database.exists():
                record = builds.get(label, {})
                if (record.get("counts_sha256") != sha256(counts)
                        or record.get("article_corpus_sha256") != sha256(corpus)
                        or record.get("database_sha256") != sha256(database)):
                    raise ValueError(f"Existing model has no matching immutable build record: {label}")
            else:
                builds[label] = project_benchmark.build_model(
                    args.reference_db, counts, corpus, database, True)
            versions[label] = database
            write_json(build_path, builds)
        _, documents = prepare_articles(articles, args.reference_db, baseline)
        identifiers = [row["id"] for row in sample["articles"]]
        policy = Policy()
        reports = {}
        if args.baseline_trace:
            baseline_trace = json.loads(args.baseline_trace.read_text(encoding="utf-8"))
            if (baseline_trace.get("version") != "mc-bopomofo-control"
                    or baseline_trace.get("database_sha256") != sha256(baseline)
                    or len(baseline_trace.get("reports", [])) != sample["count"]):
                raise ValueError("Baseline trace does not match this model and complete cohort")
            reports["mc-bopomofo-control"] = baseline_trace["reports"]
        for argument in args.reuse_trace:
            if "=" not in argument:
                raise ValueError(f"Expected LABEL=TRACE: {argument}")
            label, raw_path = argument.split("=", 1)
            if label not in versions or label in reports:
                raise ValueError(f"Trace label is absent or duplicated: {label!r}")
            trace = json.loads(Path(raw_path).read_text(encoding="utf-8"))
            if (trace.get("version") != label
                    or trace.get("database_sha256") != sha256(versions[label])
                    or len(trace.get("reports", [])) != sample["count"]):
                raise ValueError(f"Reused trace does not match model and complete cohort: {label}")
            reports[label] = trace["reports"]
        for index, (label, database) in enumerate(versions.items()):
            if label in reports:
                continue
            reports[label] = evaluate_articles(documents, database, policy, identifiers, label, args.jobs)
            write_json(args.directory / f"{args.run_name}-traces-{index}.json",
                       {"version": label, "database_sha256": sha256(database), "reports": reports[label]})
        result = write_comparison(args.directory / f"{args.run_name}-comparison.json",
                                  sample, versions, reports, policy, args.reference_db)
        eligible = [(row["evaluated_actions_after"], name)
                    for name, row in result["comparisons"].items() if row["passes"]]
        selection = {"selected": min(eligible)[1] if eligible else "mc-bopomofo-control",
                     "rule": ("lower correction actions for basic/general characters in v2/v3, stable article/source/category "
                              "distribution, improved basic characters, and stable general characters; "
                              "rare/unranked characters and v4 specialist text are diagnostic only"),
                     "sample_role": "validation: mixture strength was selected after seeing this cohort",
                     "requires_new_holdout": bool(eligible)}
        write_json(args.directory / f"{args.run_name}-selection.json", selection)
        print(json.dumps({"comparisons": result["comparisons"], **selection}, ensure_ascii=False, indent=2))
    except (ValueError, OSError, sqlite3.Error, subprocess.SubprocessError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
