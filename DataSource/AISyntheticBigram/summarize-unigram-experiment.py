#!/usr/bin/env python3
"""Apply distribution-level stability rules to validation and blind unigram cohorts."""
import argparse
from collections import defaultdict
import json
from pathlib import Path

from typing_cost import sha256, write_json
from typing_batch import (EVALUATED_SOURCE_VERSIONS, GENERAL_CHARACTER_RANK_MAX,
                          common_character_indicator, compare_common_character_versions,
                          compare_ranked_character_versions, correction_actions_for_characters,
                          evaluated_action_comparison, load_ranked_character_words,
                          ranked_character_indicator)


def common_metrics(result, baseline, variant):
    reports = {
        name: [article["results"][name] for article in result["articles"]]
        for name in (baseline, variant)
    }
    indicator = common_character_indicator(
        result["sample"], reports, source_versions=EVALUATED_SOURCE_VERSIONS)
    ranked = ranked_character_indicator(
        result["sample"], reports, source_versions=EVALUATED_SOURCE_VERSIONS)
    return {
        **compare_common_character_versions(indicator, baseline, variant),
        **compare_ranked_character_versions(ranked, baseline, variant),
    }


def evaluated_characters():
    return frozenset(row["character"] for row in load_ranked_character_words()
                     if row["rank"] <= GENERAL_CHARACTER_RANK_MAX)


def evaluated_metrics(result, baseline, variant):
    reports = {
        name: [article["results"][name] for article in result["articles"]]
        for name in (baseline, variant)
    }
    return evaluated_action_comparison(
        result["sample"], reports[baseline], reports[variant], evaluated_characters())


def grouped(result, variant, field, baseline="mc-bopomofo-control"):
    groups = defaultdict(list)
    for article in result["articles"]:
        before = article["results"][baseline]["total_actions"]
        after = article["results"][variant]["total_actions"]
        groups[article[field]].append(after - before)
    return [{
        "name": name, "articles": len(deltas), "delta": sum(deltas),
        "improved": sum(value < 0 for value in deltas),
        "unchanged": sum(value == 0 for value in deltas),
        "regressed": sum(value > 0 for value in deltas),
        "worst_regression": max(0, max(deltas)),
    } for name, deltas in sorted(groups.items())]


def evaluated_grouped(result, variant, field, baseline="mc-bopomofo-control"):
    characters = evaluated_characters()
    groups = defaultdict(list)
    for article in result["articles"]:
        if article["source_version"] not in EVALUATED_SOURCE_VERSIONS:
            continue
        before = correction_actions_for_characters(article["results"][baseline], characters)
        after = correction_actions_for_characters(article["results"][variant], characters)
        groups[article[field]].append(after - before)
    return [{
        "name": name, "articles": len(deltas), "delta": sum(deltas),
        "improved": sum(value < 0 for value in deltas),
        "unchanged": sum(value == 0 for value in deltas),
        "regressed": sum(value > 0 for value in deltas),
        "worst_regression": max(0, max(deltas)),
    } for name, deltas in sorted(groups.items())]


def cohort(path, variant):
    result = json.loads(path.read_text(encoding="utf-8"))
    comparison = result["comparisons"][variant]
    count = result["sample"]["count"]
    sources = evaluated_grouped(result, variant, "source_version")
    categories = evaluated_grouped(result, variant, "category")
    evaluated = evaluated_metrics(result, "mc-bopomofo-control", variant)
    saved = evaluated["evaluated_saved_actions"]
    added = evaluated["evaluated_added_actions"]
    metrics = {
        "comparison_file": str(path),
        "comparison_sha256": sha256(path),
        **comparison,
        **evaluated,
        "improved_share": evaluated["evaluated_improved_articles"] / evaluated["evaluated_articles"],
        "regressed_share": evaluated["evaluated_regressed_articles"] / evaluated["evaluated_articles"],
        "saved_to_added_ratio": None if added == 0 else saved / added,
        "source_versions": sources,
        "categories": categories,
        "improved_category_share": sum(row["delta"] <= 0 for row in categories) / len(categories),
        **common_metrics(result, "mc-bopomofo-control", variant),
    }
    metrics["stable"] = (
        metrics["evaluated_actions_delta"] < 0
        and metrics["improved_share"] >= 0.80
        and metrics["regressed_share"] <= 0.20
        and (added == 0 or saved >= 10 * added)
        and all(row["delta"] < 0 for row in sources)
        and metrics["improved_category_share"] >= 0.90
        and metrics["common_character_indicator_passes"]
        and metrics["ranked_character_indicator_passes"]
    )
    return metrics


def pairwise_cohort(path, baseline, variant):
    result = json.loads(path.read_text(encoding="utf-8"))
    rows = result["articles"]
    total_deltas = [article["results"][variant]["total_actions"]
                    - article["results"][baseline]["total_actions"] for article in rows]
    before = sum(article["results"][baseline]["total_actions"] for article in rows)
    after = sum(article["results"][variant]["total_actions"] for article in rows)
    sources = evaluated_grouped(result, variant, "source_version", baseline)
    categories = evaluated_grouped(result, variant, "category", baseline)
    evaluated = evaluated_metrics(result, baseline, variant)
    saved, added = evaluated["evaluated_saved_actions"], evaluated["evaluated_added_actions"]
    common = common_metrics(result, baseline, variant)
    metrics = {
        "comparison_file": str(path), "comparison_sha256": sha256(path),
        "baseline": baseline, "variant": variant,
        "before": before, "after": after, "delta": after - before,
        "reduction_percent": 100 * (before - after) / before,
        "improved_articles": sum(value < 0 for value in total_deltas),
        "unchanged_articles": sum(value == 0 for value in total_deltas),
        "regressed_articles": sum(value > 0 for value in total_deltas),
        "worst_regression": max(0, max(total_deltas)),
        "saved_actions": sum(-value for value in total_deltas if value < 0),
        "added_actions": sum(value for value in total_deltas if value > 0),
        **evaluated,
        "corrections_before": sum(article["results"][baseline]["corrections"] for article in rows),
        "corrections_after": sum(article["results"][variant]["corrections"] for article in rows),
        **common,
        "improved_share": evaluated["evaluated_improved_articles"] / evaluated["evaluated_articles"],
        "regressed_share": evaluated["evaluated_regressed_articles"] / evaluated["evaluated_articles"],
        "saved_to_added_ratio": None if added == 0 else saved / added,
        "source_versions": sources, "categories": categories,
        "improved_category_share": sum(row["delta"] <= 0 for row in categories) / len(categories),
    }
    metrics["stable"] = (
        metrics["evaluated_actions_delta"] < 0
        and metrics["improved_share"] >= 0.80
        and metrics["regressed_share"] <= 0.20
        and (added == 0 or saved >= 10 * added)
        and all(row["delta"] < 0 for row in sources)
        and metrics["improved_category_share"] >= 0.90
        and metrics.get("common_character_indicator_passes", True)
        and metrics.get("ranked_character_indicator_passes", True)
    )
    return metrics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validation", type=Path, required=True)
    parser.add_argument("--test", type=Path, required=True)
    parser.add_argument("--variant", default="blend-075")
    parser.add_argument("--previous-variant")
    parser.add_argument("--second-role", choices=("final_test", "confirmation"), default="final_test")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        validation = cohort(args.validation, args.variant)
        second = cohort(args.test, args.variant)
        relative = None
        if args.previous_variant:
            relative = {
                "validation": pairwise_cohort(args.validation, args.previous_variant, args.variant),
                args.second_role: pairwise_cohort(args.test, args.previous_variant, args.variant),
            }
        accepted = validation["stable"] and second["stable"] and (
            relative is None or all(row["stable"] for row in relative.values()))
        result = {
            "selected": args.variant if accepted else "mc-bopomofo-control",
            "accepted": accepted,
            "rule": {
                "aggregate": (
                    "correction actions for ranked characters 1–1000 in v2/v3 must fall in both cohorts; "
                    "v4 specialist text and rare/unranked characters are diagnostic only"),
                "articles": "at least 80% improve and at most 20% regress within the evaluated scope",
                "magnitude": "saved actions must be at least 10 times added actions",
                "sources": "both evaluated v2/v3 source groups must improve",
                "categories": "at least 90% of evaluated v2/v3 category groups must improve or remain unchanged",
                "basic_characters": (
                    "corrections must decrease, at most 20% of active basic characters may regress, "
                    "and at least 90% of semantic groups must not regress"),
                "ranked_characters": (
                    "ranks 1–100 must improve; ranks 101–1000 must not worsen; ranks 1001–1500 are excluded"),
                "exceptions": "no article IDs, error words, or word-specific score patches",
            },
            "validation": validation,
            args.second_role: second,
            "relative_to_previous": relative,
            "attribution": (
                "Control and candidate use the same frozen 800-article bigram corpus, vocabulary, "
                "readings, cooker, and typing policy. The candidate changes unigram counts globally."
            ),
        }
        write_json(args.output, result)
        lines = [
            "# Project unigram decision", "",
            f"Selected: **{result['selected']}**; accepted: **{accepted}**.", "",
            "| Cohort | All actions | Evaluated correction actions | Evaluated improved / same / regressed | Core 83 | Basic top 100 | General 101–1000 | Stable |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
        ]
        for name, row in (("validation", validation), (args.second_role.replace("_", " "), second)):
            lines.append(
                f"| {name} | {row['before']:,}→{row['after']:,} | "
                f"{row['evaluated_actions_before']:,}→{row['evaluated_actions_after']:,} | "
                f"{row['evaluated_improved_articles']} / {row['evaluated_unchanged_articles']} / {row['evaluated_regressed_articles']} | "
                f"{row['common_character_corrections_before']:,}→{row['common_character_corrections_after']:,} | "
                f"{row['ranked_character_gate_corrections_before']:,}→{row['ranked_character_gate_corrections_after']:,} | "
                f"{row['general_character_corrections_before']:,}→{row['general_character_corrections_after']:,} | "
                f"{row['stable']} |")
        lines += ["", "The 800 training articles and both 750-article cohorts are disjoint.",
                  "Both models use the same 800-article bigram corpus; this comparison isolates the unigram source.",
                  "The v4 lexicon-directed source and rare/unranked characters remain in diagnostics but cannot accept or reject a model."]
        if args.second_role == "final_test":
            lines.append("The final-test cohort was not used to choose the global unigram method or weight.")
        else:
            lines.append(
                "The confirmation cohort was previously used to evaluate the predecessor; it is not a fresh blind test for this version.")
        if relative:
            lines += ["", f"Relative to **{args.previous_variant}**:", "",
                      "| Cohort | All actions | Evaluated correction actions | Core 83 | Basic top 100 | General 101–1000 | Stable |",
                      "| --- | ---: | ---: | ---: | ---: | ---: | --- |"]
            for name, row in relative.items():
                lines.append(
                    f"| {name.replace('_', ' ')} | {row['before']:,}→{row['after']:,} | "
                    f"{row['evaluated_actions_before']:,}→{row['evaluated_actions_after']:,} | "
                    f"{row['common_character_corrections_before']:,}→{row['common_character_corrections_after']:,} | "
                    f"{row['ranked_character_gate_corrections_before']:,}→{row['ranked_character_gate_corrections_after']:,} | "
                    f"{row['general_character_corrections_before']:,}→{row['general_character_corrections_after']:,} | "
                    f"{row['stable']} |")
        args.output.with_suffix(".md").write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(json.dumps({"selected": result["selected"], "accepted": accepted,
                          "validation_delta": validation["delta"],
                          f"{args.second_role}_delta": second["delta"]}, ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, TypeError, ZeroDivisionError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
