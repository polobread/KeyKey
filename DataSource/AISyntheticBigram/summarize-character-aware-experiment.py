#!/usr/bin/env python3
"""Write a compact decision record for the global raw-character prior grid."""
import argparse
import json
from pathlib import Path

from typing_cost import sha256, write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("comparison", type=Path)
    parser.add_argument("--baseline", default="iterative-v2")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        payload = json.loads(args.comparison.read_text(encoding="utf-8"))
        baseline_actions = sum(
            row["results"][args.baseline]["total_actions"] for row in payload["articles"])
        rows = []
        for name, comparison in payload["comparisons"].items():
            if not name.startswith("character-aware-"):
                continue
            rows.append({
                "name": name,
                "character_weight": int(name.rsplit("-", 1)[1]) / 1000,
                "actions": comparison["after"],
                "delta_vs_mc_bopomofo": comparison["delta"],
                "delta_vs_iterative_v2": comparison["after"] - baseline_actions,
                "evaluated_actions": comparison["evaluated_actions_after"],
                "improved_articles": comparison["improved_articles"],
                "unchanged_articles": comparison["unchanged_articles"],
                "regressed_articles": comparison["regressed_articles"],
                "core_83": {
                    "corrections": comparison["common_character_corrections_after"],
                    "active": comparison["common_character_active"],
                    "improved": comparison["common_character_improved"],
                    "unchanged": comparison["common_character_unchanged"],
                    "regressed": comparison["common_character_regressed"],
                    "regressed_share": comparison["common_character_regressed_share"],
                    "nonregressed_group_share": comparison["common_character_nonregressed_group_share"],
                    "passes": comparison["common_character_indicator_passes"],
                },
                "ranked_1500": {
                    "corrections": comparison["ranked_character_corrections_after"],
                    "active": comparison["ranked_character_active"],
                    "improved": comparison["ranked_character_improved"],
                    "unchanged": comparison["ranked_character_unchanged"],
                    "regressed": comparison["ranked_character_regressed"],
                    "regressed_share": comparison["ranked_character_regressed_share"],
                    "nonregressed_group_share": comparison["ranked_character_nonregressed_group_share"],
                    "gate_scope": comparison["ranked_character_gate_scope"],
                    "gate_corrections": comparison["ranked_character_gate_corrections_after"],
                    "gate_active": comparison["ranked_character_gate_active"],
                    "gate_improved": comparison["ranked_character_gate_improved"],
                    "gate_unchanged": comparison["ranked_character_gate_unchanged"],
                    "gate_regressed": comparison["ranked_character_gate_regressed"],
                    "gate_regressed_share": comparison["ranked_character_gate_regressed_share"],
                    "general_corrections": comparison["general_character_corrections_after"],
                    "general_active": comparison["general_character_active"],
                    "general_regressed": comparison["general_character_regressed"],
                    "general_regressed_share": comparison["general_character_regressed_share"],
                    "general_passes": comparison["general_character_indicator_passes"],
                    "passes": comparison["ranked_character_indicator_passes"],
                },
                "accepted": comparison["common_character_indicator_passes"]
                            and comparison["ranked_character_indicator_passes"],
            })
        if not rows:
            raise ValueError("Comparison has no character-aware variants")
        accepted = [row for row in rows if row["accepted"]]
        result = {
            "method": "one global raw-character probability interpolation coefficient",
            "training": "only the frozen 800-article cohort",
            "validation": "one frozen 750-article cohort",
            "comparison_file": str(args.comparison),
            "comparison_sha256": sha256(args.comparison),
            "baseline": {"name": args.baseline, "actions": baseline_actions},
            "prespecified_weights": [row["character_weight"] for row in rows],
            "variants": rows,
            "selected": min(accepted, key=lambda row: row["actions"])["name"] if accepted else None,
            "accepted": bool(accepted),
            "second_cohort_run": False,
            "decision": (
                "Rejected on validation: every weight spread regressions across too many basic and general "
                "characters. Rare/unranked characters and v4 specialist text did not decide the result. "
                "The second cohort was not used to rescue parameters."
            ),
        }
        write_json(args.output, result)
        lines = [
            "# Character-aware unigram experiment", "",
            "A single global raw-character prior was added to every one-character unigram. The model used only",
            "the frozen 800 training articles; neither character audit supplied word-specific weights.", "",
            "| Weight | All actions | Evaluated actions | Δ vs v2 | Core 83 corrections | Core regressed | Basic top-100 | Basic regressed | General 101–1000 | General regressed | Rare/full diagnostic | Accepted |",
            "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
        ]
        for row in rows:
            core, ranked = row["core_83"], row["ranked_1500"]
            lines.append(
                f"| {row['character_weight']:.1%} | {row['actions']:,} | {row['evaluated_actions']:,} | {row['delta_vs_iterative_v2']:+,} | "
                f"{core['corrections']:,} | {core['regressed']}/{core['active']} ({core['regressed_share']:.1%}) | "
                f"{ranked['gate_corrections']:,} | {ranked['gate_regressed']}/{ranked['gate_active']} ({ranked['gate_regressed_share']:.1%}) | "
                f"{ranked['general_corrections']:,} | {ranked['general_regressed']}/{ranked['general_active']} ({ranked['general_regressed_share']:.1%}) | "
                f"{ranked['corrections']:,}; {ranked['regressed']}/{ranked['active']} | "
                f"{row['accepted']} |")
        lines += ["", "**Decision:** rejected. No variant passed either character breadth gate, so the second 750-article cohort was not run.", ""]
        args.output.with_suffix(".md").write_text("\n".join(lines), encoding="utf-8")
        print(json.dumps({"selected": result["selected"], "accepted": result["accepted"]}, ensure_ascii=False))
    except (ValueError, OSError, KeyError, TypeError, ZeroDivisionError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
