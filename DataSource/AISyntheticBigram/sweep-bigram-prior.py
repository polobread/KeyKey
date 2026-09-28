#!/usr/bin/env python3
"""Test an analysis-chosen GLOBAL prior grid, with no article-specific patches."""
import argparse
import json
import math
from pathlib import Path
import sqlite3
import subprocess
import sys

from typing_cost import DEFAULT_DB, Policy, connect, resolve_version, sha256, writable_db, write_json
from typing_batch import sample_articles, prepare_articles, evaluate_articles, write_comparison


def reweight(source: Path, destination: Path, prior: float, old_prior=1000.0):
    """Reconstruct the production cooker's additive smoothing sufficient statistics.

    backoff = log10(old_prior / (outgoing + old_prior))
    P(b|a) = (observed_reading_weight + old_prior * P(b)) / (outgoing + old_prior)

    Current cooker clips each distinct text pair at one. EOS has observation 1
    and its own prior probability; infer that common value from all EOS rows.
    No text, article identity or error list is accepted by this transformation.
    """
    if not math.isfinite(prior) or prior <= 0 or not math.isfinite(old_prior) or old_prior <= 0:
        raise ValueError("Prior strengths must be positive finite numbers")
    if destination.exists():
        raise ValueError(f"Refuse to overwrite model: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with connect(source) as original, writable_db(destination) as db:
        original.backup(db)
        if prior == old_prior:
            return {"prior": prior, "bigram_rows": db.execute("SELECT count(*) FROM bigrams").fetchone()[0]}
        unigrams = {}
        outgoing = {}
        updates = []
        for rowid, query, text, probability, backoff in db.execute("SELECT rowid,* FROM unigrams"):
            key = (query, text)
            if key in unigrams:
                raise ValueError("Ambiguous duplicate unigram in base model")
            unigrams[key] = probability
            count = old_prior * (10 ** (-backoff) - 1)
            if not math.isfinite(count) or abs(count - round(count)) > 0.0001 or count < -0.0001:
                raise ValueError("Base backoffs are incompatible with the declared cooker prior")
            count = round(count)
            outgoing[key] = count
            updates.append((math.log10(prior / (count + prior)), rowid))
        eos_base = None
        for query, previous, probability in db.execute("SELECT qstring,previous,probability FROM bigrams WHERE current=''"):
            prev_query, current_query = query.split(" ")
            if current_query != "$":
                raise ValueError("Unexpected empty-text bigram")
            implied = (10 ** probability * (outgoing[(prev_query, previous)] + old_prior) - 1) / old_prior
            if not 0 < implied <= 1 or (eos_base is not None and abs(implied - eos_base) > 1e-10):
                raise ValueError("EOS scores do not match capped-count production cooker")
            eos_base = implied
        changes = []
        # Collect before updating so no cursor ever observes partly transformed data.
        for rowid, query, previous, current, probability in db.execute("SELECT rowid,* FROM bigrams"):
            prev_query, current_query = query.split(" ")
            count = outgoing[(prev_query, previous)]
            background = eos_base if current_query == "$" else 10 ** unigrams[(current_query, current)]
            observation = 10 ** probability * (count + old_prior) - old_prior * background
            if not -1e-10 <= observation <= 1 + 1e-8:
                raise ValueError("Base bigrams do not match capped-count production cooker; use unmodified current DB")
            observation = max(0, observation)
            value = math.log10((observation + prior * background) / (count + prior))
            if not math.isfinite(value) or value > 1e-10:
                raise ValueError("Invalid transformed probability")
            changes.append((value, rowid))
        db.executemany("UPDATE bigrams SET probability=? WHERE rowid=?", changes)
        db.executemany("UPDATE unigrams SET backoff=? WHERE rowid=?", updates)
        db.commit()
        db.execute("ATTACH DATABASE ? AS original", (source.resolve().as_uri() + "?mode=ro",))
        for columns, table in (("qstring,current,probability", "unigrams"), ("qstring,previous,current", "bigrams")):
            for left, right in (("main", "original"), ("original", "main")):
                difference = db.execute(f"SELECT count(*) FROM (SELECT {columns} FROM {left}.{table} EXCEPT SELECT {columns} FROM {right}.{table})").fetchone()[0]
                if difference:
                    raise ValueError("Global transformation changed vocabulary, unigram probabilities or bigram identities")
        if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise ValueError("Transformed model failed integrity check")
    return {"old_prior": old_prior, "prior": prior, "bigram_rows": len(changes), "backoff_rows": len(updates),
            "unigram_probabilities_changed": 0, "bigram_identities_changed": 0, "eos_background_probability": eos_base}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("benchmark", type=Path, help="completed baseline benchmark containing analysis.json")
    parser.add_argument("--version", default="current")
    parser.add_argument("--reference-db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--priors", nargs="+", type=float, default=[750, 500, 250])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        analysis = json.loads((args.benchmark / "analysis.json").read_text(encoding="utf-8"))
        source = resolve_version(args.version)
        if sha256(source) != analysis["database_sha256"]:
            raise ValueError("Analyze this baseline before adjusting it")
        if args.output.exists():
            raise ValueError("Choose a new output directory; do not overwrite an experiment")
        args.output.mkdir(parents=True)
        original_sample = json.loads((args.benchmark / "sample.json").read_text(encoding="utf-8"))
        articles, sample = sample_articles(original_sample["count"], original_sample["seed"], args.output / "sample.json")
        if sample != original_sample:
            raise ValueError("Cohort changed")
        _, documents = prepare_articles(articles, args.reference_db)
        identifiers = [row["id"] for row in sample["articles"]]
        policy = Policy()
        # Re-evaluate baseline independently, instead of training on stale traces.
        versions = {args.version: source}
        reports = {args.version: evaluate_articles(documents, source, policy, identifiers, args.version)}
        write_json(args.output / "traces-0.json", {"version": args.version, "database_sha256": sha256(source), "reports": reports[args.version]})
        transforms = {}
        for i, prior in enumerate(args.priors, 1):
            label = f"prior-{prior:g}"
            path = args.output / f"{label}.db"
            print(f"Transforming every bigram and context backoff: prior={prior:g}", file=sys.stderr, flush=True)
            transforms[label] = reweight(source, path, prior)
            versions[label] = path
            reports[label] = evaluate_articles(documents, path, policy, identifiers, label)
            write_json(args.output / f"traces-{i}.json", {"version": label, "database_sha256": sha256(path), "reports": reports[label]})
            result = write_comparison(args.output / "comparison.json", sample, versions, reports, policy, args.reference_db)
            write_json(args.output / "transformations.json", transforms)
            print(json.dumps({label: result["comparisons"][label]}, ensure_ascii=False), file=sys.stderr, flush=True)
        eligible = [(row["evaluated_actions_after"], name)
                    for name, row in result["comparisons"].items() if row["passes"]]
        selection = {"selected": min(eligible)[1] if eligible else args.version,
                     "rule": "lowest aggregate actions among models with ZERO per-article regressions; otherwise retain baseline",
                     "article_specific_patches": False,
                     "reason": "All global models were assessed on the entire fixed sample, never tuned one article at a time."}
        write_json(args.output / "selection.json", selection)
        print(json.dumps({"comparisons": result["comparisons"], **selection}, ensure_ascii=False, indent=2))
    except (ValueError, OSError, sqlite3.Error, subprocess.SubprocessError, KeyError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
