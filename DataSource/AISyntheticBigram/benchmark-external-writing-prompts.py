#!/usr/bin/env python3
"""Evaluate a locked unigram candidate on unused Traditional Chinese writing prompts."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import random
import sys

from typing_batch import evaluate_articles, write_comparison
from typing_cost import CACHE, DEFAULT_DB, Lexicon, Policy, load_document, sha256, write_json


ROOT = Path(__file__).resolve().parent
PROMPTS = ROOT.parent / "AISyntheticArticles" / "writing-prompts-v1.jsonl"
SOURCE_VERSION = "writing-prompts-v1"


def compose(row, text_scope="content"):
    fields = [row["title"], row["scenario"]]
    if text_scope == "full":
        fields += [*row.get("requirements", ()), *row.get("language_requirements", ())]
    return "\n".join(value.strip() for value in fields if value.strip())


def load_population(path=PROMPTS, text_scope="content"):
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    expected = [f"tw-writing-{index:04d}" for index in range(1, 3001)]
    if [row.get("id") for row in rows] != expected:
        raise ValueError(f"{path}: expected 3,000 contiguous writing prompt IDs")
    return [{**row, "text": compose(row, text_scope)} for row in rows]


def prepare_eligible(rows, reference, input_database):
    lexicon = Lexicon(reference, input_database)
    directory = CACHE / "external-writing-prompts"
    directory.mkdir(parents=True, exist_ok=True)
    eligible, excluded = [], []
    for index, row in enumerate(rows, 1):
        digest = hashlib.sha256(row["text"].encode()).hexdigest()
        path = directory / f"{row['id']}-{digest[:12]}.txt"
        path.write_text(row["text"], encoding="utf-8")
        try:
            document = load_document(path, lexicon)
        except ValueError as error:
            excluded.append({"id": row["id"], "reason": str(error)})
        else:
            eligible.append((row, document))
        if index % 500 == 0:
            print(f"preflight: {index}/{len(rows)} prompts", file=sys.stderr, flush=True)
    return eligible, excluded


def descriptor(row, source_version):
    return {
        "id": row["id"], "title": row["title"], "source_version": source_version,
        "category": row["genre"], "text_sha256": hashlib.sha256(row["text"].encode()).hexdigest(),
    }


def write_summary(prefix, sample, comparison, baseline, candidate, comparison_path,
                  candidate_label="blend-025-pruned"):
    category_deltas = comparison["evaluated_category_deltas"]
    nonregressed_categories = sum(delta <= 0 for delta in category_deltas.values())
    gates = {
        "evaluated_action_total": comparison["evaluated_action_total_passes"],
        "article_improvement_share": comparison["evaluated_article_improvement_passes"],
        "article_regression_share": comparison["evaluated_article_regression_passes"],
        "savings_to_additions_ratio": comparison["evaluated_savings_ratio_passes"],
        "source_totals": comparison["evaluated_source_passes"],
        "category_nonregression_share": comparison["evaluated_category_passes"],
        "core_83": comparison["common_character_indicator_passes"],
        "basic_top_100": comparison["ranked_character_basic_passes"],
        "general_101_1000": comparison["general_character_indicator_passes"],
    }
    failed_gates = [name for name, passed in gates.items() if not passed]
    text_description = ("titles and scenarios only" if sample["text_scope"] == "content"
                        else "titles, scenarios, and repeated instruction templates")
    methodology_note = (
        "This primary diagnostic removes the repeated instruction fields, but titles and scenarios "
        "are short generated prompt descriptions rather than full natural articles."
        if sample["text_scope"] == "content" else
        "This secondary stress run includes five instruction lines repeated in 749 of 750 samples; "
        "its distribution metrics are dominated by boilerplate and are not treated as natural-text evidence.")
    summary = {
        "experiment": f"locked {candidate_label} unigram on external writing prompts",
        "text_scope": sample["text_scope"],
        "candidate_locked_before_scoring": True,
        "methodology_note": methodology_note,
        "source": sample["sources"][0],
        "sample": {
            "population": sample["population"], "eligible": sample["eligible_population"],
            "sampling_pool": sample.get("sampling_pool", sample["eligible_population"]),
            "excluded": sample["preflight"]["excluded"], "selected": sample["count"],
            "seed": sample["seed"], "method": sample["method"],
            "excluded_samples": sample.get("excluded_samples", []),
        },
        "independence": "Fresh process for every prompt/version; learning and user caches disabled",
        "models": {
            "baseline": {"name": "mc-bopomofo-control", "sha256": sha256(baseline)},
            "candidate": {"name": candidate_label, "sha256": sha256(candidate)},
        },
        "comparison_file": str(comparison_path),
        "metrics": {
            "all_actions": {"before": comparison["before"], "after": comparison["after"],
                            "delta": comparison["delta"]},
            "evaluated_actions": {
                "scope": comparison["evaluated_scope"],
                "before": comparison["evaluated_actions_before"],
                "after": comparison["evaluated_actions_after"],
                "delta": comparison["evaluated_actions_delta"],
                "improved_prompts": comparison["evaluated_improved_articles"],
                "unchanged_prompts": comparison["evaluated_unchanged_articles"],
                "regressed_prompts": comparison["evaluated_regressed_articles"],
                "saved": comparison["evaluated_saved_actions"],
                "added": comparison["evaluated_added_actions"],
            },
            "core_83": {
                "before": comparison["common_character_corrections_before"],
                "after": comparison["common_character_corrections_after"],
                "active": comparison["common_character_active"],
                "regressed": comparison["common_character_regressed"],
                "regressed_share": comparison["common_character_regressed_share"],
            },
            "basic_top_100": {
                "before": comparison["ranked_character_gate_corrections_before"],
                "after": comparison["ranked_character_gate_corrections_after"],
                "active": comparison["ranked_character_gate_active"],
                "regressed": comparison["ranked_character_gate_regressed"],
                "regressed_share": comparison["ranked_character_gate_regressed_share"],
            },
            "general_101_1000": {
                "before": comparison["general_character_corrections_before"],
                "after": comparison["general_character_corrections_after"],
                "active": comparison["general_character_active"],
                "regressed": comparison["general_character_regressed"],
                "regressed_share": comparison["general_character_regressed_share"],
            },
            "categories": {
                "deltas": category_deltas, "nonregressed": nonregressed_categories,
                "total": len(category_deltas),
                "nonregressed_share": comparison["evaluated_category_nonregressed_share"],
            },
        },
        "gates": gates,
        "failed_gates": failed_gates,
        "diagnostic_passes": comparison["passes"],
        "production_decision": "Unchanged; keep mc-bopomofo-control",
        "reason": (f"The external diagnostic fails fixed gates: {', '.join(failed_gates)}."
                   if failed_gates else
                   "The external diagnostic passes; a full natural-article holdout is still required."),
    }
    json_path = prefix.with_suffix(".json")
    md_path = prefix.with_suffix(".md")
    write_json(json_path, summary)
    evaluated = summary["metrics"]["evaluated_actions"]
    saved_ratio = evaluated["saved"] / evaluated["added"] if evaluated["added"] else float("inf")
    lines = [
        "# External writing-prompt unigram diagnostic", "",
        (f"Production model: **mc-bopomofo-control**; external diagnostic pass: "
         f"**{comparison['passes']}**."), "",
        (f"Seed {sample['seed']} selected {sample['count']} prompts without replacement from a "
         f"{sample.get('sampling_pool', sample['eligible_population'])}-prompt pool after exclusions; "
         f"{sample['eligible_population']} / {sample['population']} prompts were preflight-typeable. "
         f"This run uses {text_description}. The prompt bodies were unused by unigram and paired-bigram "
         "training, and the candidate "
         "was locked before this score was read."), "",
        methodology_note, "",
        "Every prompt/version ran in a fresh process with learning and user caches disabled. "
        "Rare ranks 1001–1500 and unranked characters are excluded from the decision.", "",
        "| Metric | Result | Fixed gate | Pass |", "| --- | ---: | ---: | --- |",
        (f"| Evaluated actions | {evaluated['before']:,}→{evaluated['after']:,} "
         f"({evaluated['delta']:+,}) | must decrease | {gates['evaluated_action_total']} |"),
        (f"| Improved prompts | {evaluated['improved_prompts']}/{sample['count']} "
         f"({evaluated['improved_prompts'] / sample['count']:.1%}) | ≥80% | "
         f"{gates['article_improvement_share']} |"),
        (f"| Regressed prompts | {evaluated['regressed_prompts']}/{sample['count']} "
         f"({evaluated['regressed_prompts'] / sample['count']:.1%}) | ≤20% | "
         f"{gates['article_regression_share']} |"),
        (f"| Saved / added actions | {evaluated['saved']:,}/{evaluated['added']:,} "
         f"({saved_ratio:.2f}×) | ≥10× | {gates['savings_to_additions_ratio']} |"),
        (f"| Nonregressed categories | {nonregressed_categories}/{len(category_deltas)} "
         f"({comparison['evaluated_category_nonregressed_share']:.1%}) | ≥90% | "
         f"{gates['category_nonregression_share']} |"),
        (f"| Core 83 corrections | {comparison['common_character_corrections_before']:,}→"
         f"{comparison['common_character_corrections_after']:,}; regressed "
         f"{comparison['common_character_regressed']}/{comparison['common_character_active']} | "
         "decrease; ≤20% regress; ≥90% groups nonregress | "
         f"{gates['core_83']} |"),
        (f"| Basic top 100 corrections | {comparison['ranked_character_gate_corrections_before']:,}→"
         f"{comparison['ranked_character_gate_corrections_after']:,}; regressed "
         f"{comparison['ranked_character_gate_regressed']}/{comparison['ranked_character_gate_active']} | "
         f"decrease; ≤20% regress | {gates['basic_top_100']} |"),
        (f"| General 101–1000 corrections | {comparison['general_character_corrections_before']:,}→"
         f"{comparison['general_character_corrections_after']:,}; regressed "
         f"{comparison['general_character_regressed']}/{comparison['general_character_active']} | "
         f"do not increase; ≤20% regress | {gates['general_101_1000']} |"),
        "", "## Category deltas", "", "Negative is better.", "",
        "| Category | Evaluated action delta |", "| --- | ---: |",
    ]
    lines.extend(f"| {name} | {delta:+,} |" for name, delta in category_deltas.items())
    conclusion = (
        "The external diagnostic fails overall. Evaluated correction cost falls, but the fixed "
        f"gates fail for {', '.join(failed_gates)}. Savings are {saved_ratio:.2f} times the added actions."
        if failed_gates else
        "The candidate passes this short-prompt external diagnostic. This corpus is not a substitute for "
        "a full natural-article holdout."
    )
    lines += ["", conclusion + " The production database is unchanged.", ""]
    md_path.write_text("\n".join(lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--candidate-label", default="blend-025-pruned")
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--reference-db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--count", type=int, default=750)
    parser.add_argument("--seed", type=int, default=20260927)
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--text-scope", choices=("content", "full"), default="content",
                        help="content uses title+scenario; full also includes repeated instruction templates")
    parser.add_argument("--exclude-sample", type=Path, action="append", default=[],
                        help="exclude every prompt ID recorded in another frozen sample manifest")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summary-prefix", type=Path)
    args = parser.parse_args()
    try:
        rows = load_population(text_scope=args.text_scope)
        source_version = (SOURCE_VERSION if args.text_scope == "full"
                          else f"{SOURCE_VERSION}-content")
        if args.summary_prefix is None:
            suffix = "-full" if args.text_scope == "full" else ""
            args.summary_prefix = ROOT / f"external-writing-prompts{suffix}-results"
        eligible, excluded = prepare_eligible(rows, args.reference_db, args.baseline)
        excluded_ids = set()
        excluded_manifests = []
        for path in args.exclude_sample:
            prior = json.loads(path.read_text(encoding="utf-8"))
            ids = {row["id"] for row in prior.get("articles", [])}
            if len(ids) != len(prior.get("articles", [])):
                raise ValueError(f"Excluded sample has duplicate or missing IDs: {path}")
            excluded_ids.update(ids)
            excluded_manifests.append({"file": str(path), "sha256": sha256(path), "ids": len(ids)})
        pool = [(row, document) for row, document in eligible if row["id"] not in excluded_ids]
        if not 1 <= args.count <= len(pool):
            raise ValueError("Requested sample exceeds the typeable external prompt population")
        picked = random.Random(args.seed).sample(pool, args.count)
        selected_rows = [row for row, _ in picked]
        documents = [document for _, document in picked]
        sample = {
            "population": len(rows), "eligible_population": len(eligible), "count": args.count,
            "sampling_pool": len(pool),
            "seed": args.seed,
            "text_scope": args.text_scope,
            "method": "Python random.Random(seed).sample over preflight-typeable prompts; without replacement",
            "role": "external diagnostic for a candidate locked before this corpus was scored",
            "scope": (
                "Unused Traditional Chinese writing-prompt titles and scenarios; none of these prompt "
                "bodies entered the 800-article unigram or paired bigram training corpus."
                if args.text_scope == "content" else
                "Unused Traditional Chinese writing instructions including repeated templates; none of "
                "these prompt bodies entered the 800-article unigram or paired bigram training corpus."),
            "corpus_relation": "These writing-prompt bodies were not part of unigram or bigram model training.",
            "sources": [{"file": str(PROMPTS.relative_to(ROOT.parent.parent)),
                         "sha256": sha256(PROMPTS), "prompts": len(rows)}],
            "preflight": {"eligible": len(eligible), "excluded": len(excluded),
                          "excluded_rows": excluded},
            "excluded_samples": excluded_manifests,
            "articles": [descriptor(row, source_version) for row in selected_rows],
        }
        args.output.mkdir(parents=True, exist_ok=True)
        manifest = args.output / "sample.json"
        if manifest.exists():
            if json.loads(manifest.read_text(encoding="utf-8")) != sample:
                raise ValueError("Frozen external sample differs; never silently resample")
        else:
            write_json(manifest, sample)
        versions = {"mc-bopomofo-control": args.baseline, args.candidate_label: args.candidate}
        identifiers = [row["id"] for row in selected_rows]
        reports = {}
        for index, (name, database) in enumerate(versions.items()):
            trace_path = args.output / f"traces-{index}.json"
            if trace_path.exists():
                trace = json.loads(trace_path.read_text(encoding="utf-8"))
                if (trace.get("version") != name or trace.get("database_sha256") != sha256(database)
                        or len(trace.get("reports", [])) != args.count):
                    raise ValueError(f"Existing external trace does not match {name}")
                reports[name] = trace["reports"]
            else:
                reports[name] = evaluate_articles(documents, database, Policy(), identifiers, name, args.jobs)
                write_json(trace_path, {"version": name, "database_sha256": sha256(database),
                                        "reports": reports[name]})
        texts = {row["id"]: row["text"] for row in selected_rows}
        result = write_comparison(
            args.output / "comparison.json", sample, versions, reports, Policy(), args.reference_db,
            article_texts=texts, evaluation_source_versions=frozenset((source_version,)))
        comparison = result["comparisons"][args.candidate_label]
        write_summary(args.summary_prefix, sample, comparison, args.baseline, args.candidate,
                      args.output / "comparison.json", args.candidate_label)
        write_json(args.output / "selection.json", {
            "candidate_locked_before_scoring": True,
            "candidate": args.candidate_label,
            "diagnostic_passes": comparison["passes"],
            "production_decision": "unchanged; a full natural-article holdout is required",
        })
        print(json.dumps({
            "sample": args.count, "eligible_population": len(eligible),
            "comparison": comparison,
        }, ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
