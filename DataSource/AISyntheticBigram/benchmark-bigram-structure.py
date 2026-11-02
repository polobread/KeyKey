#!/usr/bin/env python3
"""Compare structural Bigram candidates on the complete, fixed v5 regression set.

This set has already been inspected during model development; it is not a new
blind holdout. Every model uses the same frozen readings and a fresh process per
article. Raw traces are written only to the explicitly selected output directory.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict
import json
import hashlib
from pathlib import Path

from typing_cost import (DEFAULT_DB, REPO, Lexicon, Policy, build_engine,
                         load_document, resolve_version, sha256, write_json)
from typing_cost_filter import (DEFAULT_COUNTS, POLICY as ZERO_COUNT_POLICY,
                                exclude_zero_count_actions, load_zero_count_characters)
from typing_batch import (aggregate_character_corrections, common_correction_totals,
                          common_corrections_by_character, comparison, evaluate_articles,
                          load_common_characters, load_ranked_character_words)


def summarize(reports):
    ranked = load_ranked_character_words()
    groups = {
        "core83": load_common_characters(),
        "basic100": {r["character"] for r in ranked if r["rank"] <= 100},
        "general101_1000": {r["character"] for r in ranked if 100 < r["rank"] <= 1000},
    }
    return {
        "total_actions": sum(r["total_actions"] for r in reports),
        "correction_actions": sum(r["correction_actions"] for r in reports),
        "tiers": {name: {**common_correction_totals(reports, chars),
                         "by_character": common_corrections_by_character(reports, chars)}
                  for name, chars in groups.items()},
        "character_corrections": aggregate_character_corrections(reports),
    }


def run(models, output, reference=DEFAULT_DB, jobs=8,
        zero_frequency_counts=None, source_traces=None):
    directory = REPO / "DataSource/AISyntheticArticles/typing-articles-v5-seed"
    paths = sorted(directory.glob("tw-corpus-*.md"))
    if len(paths) < 131 or [path.name for path in paths] != [f"tw-corpus-{i:04d}.md" for i in range(1, len(paths) + 1)]:
        raise ValueError("validation corpus must be contiguous and include tw-corpus-0131.md")
    policy = Policy()
    engine = build_engine()
    lexicon = Lexicon(reference)
    documents = [load_document(path, lexicon) for path in paths]
    identifiers = [path.stem for path in paths]
    frozen_inputs = [{"id": identifier, "blocks": document}
                     for identifier, document in zip(identifiers, documents)]
    input_digest = hashlib.sha256(json.dumps(
        frozen_inputs, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    identity = {
        "articles": [{"id": path.stem, "sha256": sha256(path)} for path in paths],
        "reference_sha256": sha256(reference), "policy": asdict(policy),
        "engine_sha256": sha256(engine),
        "reading_overrides_sha256": sha256(Path(__file__).with_name("reading-overrides.tsv")),
        "evaluator_sha256": sha256(Path(__file__).with_name("typing_cost.py")),
        "reading_frequency_policy": "phrase_and_manual_first; single_character_max_table_count; reference_score_breaks_ties",
        "reading_frequency_source_sha256": sha256(lexicon.reading_frequency_source) if lexicon.reading_frequency_source else None,
        "frozen_inputs_sha256": input_digest,
    }
    zero_characters = None
    if zero_frequency_counts is not None:
        zero_characters = load_zero_count_characters(zero_frequency_counts)
        identity["zero_frequency_exclusion"] = {
            **ZERO_COUNT_POLICY, "source_sha256": sha256(zero_frequency_counts),
            "filter_sha256": sha256(Path(__file__).with_name("typing_cost_filter.py")),
        }
    if source_traces is not None and zero_characters is None:
        raise ValueError("Source trace accounting requires zero-frequency exclusion")
    output.mkdir(parents=True, exist_ok=True)
    write_json(output / "frozen-inputs.json", {
        "identity": identity, "articles": frozen_inputs,
        "role": "One shared pronunciation/segmentation input for every before/after model",
    })
    reports, summaries = {}, {}
    for label, database in models.items():
        expected = {**identity, "database_sha256": sha256(database), "version": label}
        raw_data = None
        if source_traces is not None:
            raw_trace = source_traces / f"{label}-trace.json"
            raw_data = json.loads(raw_trace.read_text(encoding="utf-8"))
            raw_expected = {key: value for key, value in expected.items()
                            if key != "zero_frequency_exclusion"}
            if raw_data.get("identity") != raw_expected or len(raw_data.get("reports", [])) != len(paths):
                raise ValueError(f"Unfiltered trace provenance changed: {raw_trace}")
            expected["unfiltered_trace_sha256"] = sha256(raw_trace)
        trace = output / f"{label}-trace.json"
        if trace.exists():
            data = json.loads(trace.read_text(encoding="utf-8"))
            if data.get("identity") != expected or len(data.get("reports", [])) != len(paths):
                raise ValueError(f"Trace provenance changed: {trace}; use a fresh output directory")
            reports[label] = data["reports"]
        else:
            reports[label] = (raw_data["reports"] if raw_data is not None else
                              evaluate_articles(documents, database, policy, identifiers, label, jobs))
            if zero_characters is not None:
                reports[label] = [exclude_zero_count_actions(report, document, zero_characters)
                                  for report, document in zip(reports[label], documents)]
            write_json(trace, {"identity": expected, "reports": reports[label]})
        summaries[label] = summarize(reports[label])
        print(json.dumps({label: {k: v for k, v in summaries[label].items()
                                 if k != "character_corrections" and k != "tiers"}}, ensure_ascii=False), flush=True)
    baseline = next(iter(models))
    comparisons = {}
    for label in list(models)[1:]:
        delta = comparison(reports[baseline], reports[label])
        delta["tiers"] = {}
        for name, old in summaries[baseline]["tiers"].items():
            new = summaries[label]["tiers"][name]
            changes = [{"character": c, "before": old["by_character"][c],
                        "after": new["by_character"][c],
                        "delta": new["by_character"][c] - old["by_character"][c]}
                       for c in old["by_character"]
                       if new["by_character"][c] != old["by_character"][c]]
            delta["tiers"][name] = {
                "before": old["corrected_characters"], "after": new["corrected_characters"],
                "delta": new["corrected_characters"] - old["corrected_characters"],
                "character_changes": sorted(changes, key=lambda r: (r["delta"], r["character"])),
            }
        delta["articles"] = [{"id": identifier, "delta": b["total_actions"] - a["total_actions"]}
                             for identifier, a, b in zip(identifiers, reports[baseline], reports[label])]
        comparisons[label] = delta
    result = {"role": "fixed regression set; previously inspected, not blind holdout",
              "identity": identity, "baseline": baseline, "summaries": summaries,
              "comparisons": comparisons}
    write_json(output / "comparison.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("models", nargs="+", help="LABEL=DATABASE or LABEL=current/unigram; baseline first")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--reference-db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--exclude-zero-frequency-characters", action="store_true",
                        help="retain input/context; exclude zero-count target phonetic and correction costs")
    parser.add_argument("--character-counts", type=Path, default=DEFAULT_COUNTS)
    parser.add_argument("--rescore-from", type=Path,
                        help="reuse hash-verified unfiltered traces to apply cost exclusion without replay")
    args = parser.parse_args()
    if args.rescore_from and not args.exclude_zero_frequency_characters:
        parser.error("--rescore-from requires --exclude-zero-frequency-characters")
    if args.rescore_from and args.rescore_from.resolve() == args.output.resolve():
        parser.error("rescore output must differ from the unfiltered trace directory")
    models = {}
    for value in args.models:
        label, version = value.split("=", 1)
        if not label or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for c in label) or label in models:
            parser.error("model labels must be unique filename-safe names")
        models[label] = resolve_version(version)
    run(models, args.output, args.reference_db, args.jobs,
        args.character_counts if args.exclude_zero_frequency_characters else None,
        args.rescore_from)


if __name__ == "__main__":
    main()
