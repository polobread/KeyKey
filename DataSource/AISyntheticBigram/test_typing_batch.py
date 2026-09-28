import importlib.util
from collections import Counter
import json
import math
from pathlib import Path
import tempfile
import unittest

import typing_cost as t
from typing_batch import (aggregate_character_corrections, common_correction_totals, comparison,
                          compare_common_character_versions, compare_ranked_character_versions,
                          evaluated_action_comparison,
                          partition_articles, sample_articles,
                          load_ranked_character_words, write_comparison)

spec = importlib.util.spec_from_file_location("sweep_prior", t.ROOT / "sweep-bigram-prior.py")
sweep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sweep)
summary_spec = importlib.util.spec_from_file_location(
    "summarize_unigram", t.ROOT / "summarize-unigram-experiment.py")
unigram_summary = importlib.util.module_from_spec(summary_spec)
summary_spec.loader.exec_module(unigram_summary)
iterative_spec = importlib.util.spec_from_file_location(
    "build_iterative_unigram", t.ROOT / "build-iterative-unigram.py")
iterative_unigram = importlib.util.module_from_spec(iterative_spec)
iterative_spec.loader.exec_module(iterative_unigram)
character_spec = importlib.util.spec_from_file_location(
    "build_character_aware_unigram", t.ROOT / "build-character-aware-unigram.py")
character_unigram = importlib.util.module_from_spec(character_spec)
character_spec.loader.exec_module(character_unigram)
pruned_spec = importlib.util.spec_from_file_location(
    "build_pruned_unigram", t.ROOT / "build-pruned-unigram.py")
pruned_unigram = importlib.util.module_from_spec(pruned_spec)
pruned_spec.loader.exec_module(pruned_unigram)
length_spec = importlib.util.spec_from_file_location(
    "build_length_aware_unigram", t.ROOT / "build-length-aware-unigram.py")
length_unigram = importlib.util.module_from_spec(length_spec)
length_spec.loader.exec_module(length_unigram)
external_spec = importlib.util.spec_from_file_location(
    "benchmark_external_writing_prompts", t.ROOT / "benchmark-external-writing-prompts.py")
external_prompts = importlib.util.module_from_spec(external_spec)
external_spec.loader.exec_module(external_prompts)
tiered_spec = importlib.util.spec_from_file_location(
    "build_tiered_homophone_unigram", t.ROOT / "build-tiered-homophone-unigram.py")
tiered_unigram = importlib.util.module_from_spec(tiered_spec)
tiered_spec.loader.exec_module(tiered_unigram)
calibration_spec = importlib.util.spec_from_file_location(
    "calibrate_ranked_unigram", t.ROOT / "calibrate-ranked-unigram.py")
ranked_calibration = importlib.util.module_from_spec(calibration_spec)
calibration_spec.loader.exec_module(ranked_calibration)


class BatchTests(unittest.TestCase):
    def test_ranked_calibration_reorders_only_the_habitual_basic_reading(self):
        rows = [
            (1, "q1", "甲", -3.0), (2, "q1", "乙", -2.0), (3, "q1", "丙", -1.0),
            (4, "q2", "甲", -4.0), (5, "q2", "丁", -2.5),
        ]
        ranks = {"甲": {"rank": 1, "query": "q1"}, "乙": {"rank": 101, "query": "q1"}}
        updates, groups = ranked_calibration.calibrated_assignments(rows, ranks, rank_limit=100)
        self.assertEqual(dict((rowid, probability) for probability, rowid in updates),
                         {1: -1.0, 2: -3.0, 3: -2.0})
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]["query"], "q1")
        guarded_updates, guarded_groups = ranked_calibration.calibrated_assignments(
            rows, ranks, rank_limit=100, protected_characters={"乙"})
        self.assertEqual(guarded_updates, [])
        self.assertEqual(guarded_groups, [])

    def test_tiered_homophone_blend_applies_one_weight_to_the_whole_query_group(self):
        order = ["甲", "乙", "丙", "甲乙"]
        public = {"甲": 90, "乙": 10, "丙": 40, "甲乙": 60}
        project = {"甲": 10, "乙": 90, "丙": 40, "甲乙": 60}
        queries = {"甲": {"q1"}, "乙": {"q1"}, "丙": {"q2"}}
        anchored, affected = tiered_unigram.tiered_blend(
            order, project, public, queries, {"q1"}, 0.10, 0.25, 10_000_000)
        default, _ = tiered_unigram.tiered_blend(
            order, project, public, queries, {"q1"}, 0.25, 0.25, 10_000_000)
        self.assertEqual(affected, {"甲", "乙"})
        self.assertGreater(anchored["甲"], default["甲"])
        self.assertLess(anchored["乙"], default["乙"])
        prioritized, _ = tiered_unigram.tiered_blend(
            order, project, public, queries, {"q1"}, 0.20, 0.25, 10_000_000,
            basic_characters={"甲"}, competitor_weight=0.05)
        same_weight, _ = tiered_unigram.tiered_blend(
            order, project, public, queries, {"q1"}, 0.20, 0.25, 10_000_000,
            basic_characters={"甲"}, competitor_weight=0.20)
        self.assertGreater(prioritized["甲"], same_weight["甲"])
        self.assertLess(prioritized["乙"], same_weight["乙"])
        self.assertEqual(tiered_unigram.normalize_reading("˙ㄉㄜ"), "ㄉㄜ˙")

    def test_external_prompt_content_scope_excludes_instruction_boilerplate(self):
        row = {
            "title": "標題", "scenario": "情境", "requirements": ["固定要求"],
            "language_requirements": ["固定語言要求"],
        }
        self.assertEqual(external_prompts.compose(row, "content"), "標題\n情境")
        self.assertEqual(external_prompts.compose(row, "full"),
                         "標題\n情境\n固定要求\n固定語言要求")

    def test_chatgpt_ranked_character_indicator_has_1500_unique_typeable_han(self):
        words = load_ranked_character_words()
        self.assertEqual(len(words), 1500)
        self.assertEqual(len({row["character"] for row in words}), 1500)
        self.assertEqual(words[0]["character"], "的")
        self.assertEqual(words[0]["reading"], "ㄉㄜ˙")
        self.assertEqual(words[-1]["character"], "姐")
        self.assertEqual(words[99]["group"], "0001–0100")
        self.assertEqual(words[100]["group"], "0101–0300")
        with t.connect(t.DEFAULT_DB) as database:
            missing = [row for row in words if database.execute(
                'SELECT 1 FROM "Mandarin-bpmf-cin" WHERE value=? AND key=? LIMIT 1',
                (row["character"], t.query_for_reading(row["reading"]))).fetchone() is None]
        self.assertEqual(missing, [])

    def test_character_prior_uses_one_global_weight_and_increases_character_mass(self):
        order = ["甲", "乙", "甲乙"]
        base = {"甲": 10, "乙": 10, "甲乙": 80}
        result = character_unigram.blend_character_prior(
            order, base, Counter({"甲": 9, "乙": 1}), 0.10, 1_000_000)
        self.assertAlmostEqual(sum(result.values()), 1_000_000, delta=2)
        self.assertGreater((result["甲"] + result["乙"]) / sum(result.values()), 0.20)
        self.assertGreater(result["甲"], result["乙"])

    def test_pruning_keeps_every_globally_supported_vocabulary_class(self):
        order = ["甲", "甲乙", "乙丙", "丁戊", "專詞"]
        kept, removed, reasons = pruned_unigram.select_vocabulary(
            order, {"乙丙": 4}, {"甲乙"}, {"專詞"})
        self.assertEqual(kept, ["甲", "甲乙", "乙丙", "專詞"])
        self.assertEqual(removed, ["丁戊"])
        self.assertEqual(reasons["single_character"], 1)
        self.assertEqual(reasons["observed_in_training"], 1)
        self.assertEqual(reasons["positive_public_count"], 1)
        self.assertEqual(reasons["project_supplement"], 1)

    def test_length_aware_distribution_preserves_phrase_and_character_mass(self):
        order = ["甲", "乙", "丙", "甲乙"]
        counts = {"甲": 20, "乙": 10, "丙": 3, "甲乙": 67}
        result, report = length_unigram.restore_public_character_distribution(
            order, counts, {"甲": 1, "乙": 3, "丙": 0})
        self.assertEqual(result["甲乙"], 67)
        self.assertEqual(sum(result[word] for word in ("甲", "乙", "丙")), 33)
        self.assertGreater(result["乙"], result["甲"])
        self.assertGreaterEqual(result["丙"], 1)
        self.assertEqual(report["character_mass_before"], report["character_mass_after"])

    def test_common_character_indicator_rejects_concentrated_improvement(self):
        indicator = {
            "occurrences": 1000,
            "character_groups": {"甲組": ["甲", "乙"], "乙組": ["丙"]},
            "versions": {
                "before": {
                    "corrected_characters": 30, "corrections_per_10000_occurrences": 300,
                    "by_character": {"甲": 10, "乙": 10, "丙": 10},
                    "by_group": {"甲組": 20, "乙組": 10},
                },
                "after": {
                    "corrected_characters": 22, "corrections_per_10000_occurrences": 220,
                    "by_character": {"甲": 0, "乙": 11, "丙": 11},
                    "by_group": {"甲組": 11, "乙組": 11},
                },
            },
        }
        result = compare_common_character_versions(indicator, "before", "after")
        self.assertEqual(result["common_character_corrections_delta"], -8)
        self.assertEqual(result["common_character_regressed"], 2)
        self.assertFalse(result["common_character_indicator_passes"])

    def test_ranked_character_gate_ignores_rare_tail_regression(self):
        indicator = {
            "occurrences": 100,
            "character_groups": {
                "0001–0100": ["甲", "乙"], "0101–0300": [], "0301–0600": [],
                "0601–1000": [], "1001–1500": ["丙"],
            },
            "versions": {
                "before": {"corrected_characters": 21, "corrections_per_10000_occurrences": 2100,
                           "by_character": {"甲": 10, "乙": 10, "丙": 1},
                           "by_group": {"0001–0100": 20, "0101–0300": 0, "0301–0600": 0,
                                        "0601–1000": 0, "1001–1500": 1}},
                "after": {"corrected_characters": 17, "corrections_per_10000_occurrences": 1700,
                          "by_character": {"甲": 5, "乙": 5, "丙": 7},
                          "by_group": {"0001–0100": 10, "0101–0300": 0, "0301–0600": 0,
                                       "0601–1000": 0, "1001–1500": 7}},
            },
        }
        result = compare_ranked_character_versions(indicator, "before", "after")
        self.assertTrue(result["ranked_character_indicator_passes"])
        self.assertEqual(result["ranked_character_gate_regressed"], 0)
        self.assertEqual(result["ranked_character_regressed"], 1)

    def test_ranked_character_gate_evaluates_general_characters(self):
        indicator = {
            "occurrences": 100,
            "character_groups": {
                "0001–0100": ["甲", "乙"], "0101–0300": ["丙"], "0301–0600": [],
                "0601–1000": [], "1001–1500": [],
            },
            "versions": {
                "before": {"corrected_characters": 21, "corrections_per_10000_occurrences": 2100,
                           "by_character": {"甲": 10, "乙": 10, "丙": 1},
                           "by_group": {"0001–0100": 20, "0101–0300": 1, "0301–0600": 0,
                                        "0601–1000": 0, "1001–1500": 0}},
                "after": {"corrected_characters": 17, "corrections_per_10000_occurrences": 1700,
                          "by_character": {"甲": 5, "乙": 5, "丙": 7},
                          "by_group": {"0001–0100": 10, "0101–0300": 7, "0301–0600": 0,
                                       "0601–1000": 0, "1001–1500": 0}},
            },
        }
        result = compare_ranked_character_versions(indicator, "before", "after")
        self.assertTrue(result["ranked_character_basic_passes"])
        self.assertFalse(result["general_character_indicator_passes"])
        self.assertFalse(result["ranked_character_indicator_passes"])

    def test_common_character_indicator_counts_characters_and_phrase_selections_separately(self):
        report = {
            "character_correction_summary": [
                {"character": "是", "changes": 2, "events": 1, "sources": []},
                {"character": "和", "changes": 1, "events": 1, "sources": []},
                {"character": "龘", "changes": 5, "events": 5, "sources": []},
            ],
            "correction_summary": [
                {"changes": [{"from": "事", "to": "是"}, {"from": "合", "to": "和"}],
                 "events": 1, "actions": 2},
                {"changes": [{"from": "龍", "to": "龘"}], "events": 5, "actions": 10},
            ],
        }
        self.assertEqual(common_correction_totals([report], {"是", "和"}), {
            "corrected_characters": 3, "selection_events": 1, "selection_actions": 2,
        })

    def test_evaluation_scope_excludes_rare_characters_and_specialist_source(self):
        def report(rows):
            return {"correction_summary": rows}
        sample = {"articles": [
            {"source_version": "v2"}, {"source_version": "v3"}, {"source_version": "v4"},
        ]}
        before = [
            report([{"changes": [{"to": "甲"}], "events": 1, "actions": 4},
                    {"changes": [{"to": "龘"}], "events": 1, "actions": 9}]),
            report([{"changes": [{"to": "甲"}], "events": 1, "actions": 4}]),
            report([{"changes": [{"to": "甲"}], "events": 1, "actions": 100}]),
        ]
        after = [
            report([{"changes": [{"to": "甲"}], "events": 1, "actions": 2},
                    {"changes": [{"to": "龘"}], "events": 1, "actions": 20}]),
            report([{"changes": [{"to": "甲"}], "events": 1, "actions": 4}]),
            report([]),
        ]
        result = evaluated_action_comparison(sample, before, after, {"甲"})
        self.assertEqual(result["evaluated_actions_before"], 8)
        self.assertEqual(result["evaluated_actions_after"], 6)
        self.assertEqual(result["evaluated_improved_articles"], 1)
        self.assertEqual(result["evaluated_unchanged_articles"], 1)
        self.assertEqual(result["evaluated_regressed_articles"], 0)
        self.assertEqual(result["evaluated_source_deltas"], {"v2": -2, "v3": 0})
        self.assertEqual(result["evaluated_category_deltas"], {"<unknown>": -2})
        self.assertFalse(result["evaluated_article_improvement_passes"])
        self.assertTrue(result["evaluated_article_regression_passes"])
        self.assertFalse(result["evaluated_source_passes"])

    def test_character_corrections_are_aggregated_by_target_character(self):
        reports = [
            {"character_correction_summary": [
                {"character": "再", "changes": 2, "events": 1,
                 "sources": [{"from": "在", "changes": 2}]},
            ]},
            {"character_correction_summary": [
                {"character": "再", "changes": 1, "events": 1,
                 "sources": [{"from": "載", "changes": 1}]},
            ]},
        ]
        self.assertEqual(aggregate_character_corrections(reports), [{
            "character": "再", "changes": 3, "events": 2, "articles": 2,
            "sources": [{"from": "在", "changes": 2}, {"from": "載", "changes": 1}],
        }])

    def test_total_reduction_never_hides_an_article_regression(self):
        def report(n):
            return {"total_actions": n, "syllables": 10, "corrections": 1}
        before = list(map(report, [100, 100]))
        comparison_result = comparison(before, list(map(report, [80, 101])))
        self.assertEqual(comparison_result["delta"], -19)
        self.assertEqual(comparison_result["regressed_articles"], 1)
        self.assertFalse(comparison_result["passes"])
        self.assertTrue(comparison(before, list(map(report, [80, 100])))["passes"])

    def test_fixed_random_sample_is_unique_reproducible_and_frozen(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "sample.json"
            rows, first = sample_articles(50, 20260926, manifest)
            _, second = sample_articles(50, 20260926, manifest)
            self.assertEqual(first, second)
            self.assertEqual(len({row["prompt_id"] for row in rows}), 50)
            self.assertEqual(first["population"], 2300)
            self.assertEqual(rows[0]["prompt_id"], "tw-typing-00299")
            with self.assertRaisesRegex(ValueError, "Frozen sample differs"):
                sample_articles(50, 123, manifest)

    def test_partition_is_reproducible_disjoint_and_exhaustive(self):
        groups, first = partition_articles(20260926, 800, 750)
        _, second = partition_articles(20260926, 800, 750)
        self.assertEqual(first, second)
        identifiers = {name: {row["prompt_id"] for row in rows} for name, rows in groups.items()}
        self.assertEqual({name: len(rows) for name, rows in identifiers.items()},
                         {"training": 800, "validation": 750, "test": 750})
        self.assertFalse(identifiers["training"] & identifiers["validation"])
        self.assertFalse(identifiers["training"] & identifiers["test"])
        self.assertFalse(identifiers["validation"] & identifiers["test"])
        self.assertEqual(len(set().union(*identifiers.values())), 2300)

    def test_partition_rejects_non_exhaustive_sizes(self):
        with self.assertRaisesRegex(ValueError, "partition all 2300"):
            partition_articles(20260926, 800, 700)

    def test_unigram_stability_checks_source_groups_not_just_total(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "comparison.json"
            articles = []
            _, sample = sample_articles(10, 777)
            deltas = [-10] * 8 + [1, 1]
            sources = ["v2"] * 8 + ["v3"] * 2
            for index, (delta, source) in enumerate(zip(deltas, sources)):
                sample["articles"][index]["source_version"] = source
                sample["articles"][index]["category"] = f"category-{index}"
                articles.append({
                    "id": sample["articles"][index]["id"],
                    "source_version": source, "category": f"category-{index}",
                    "results": {
                        "mc-bopomofo-control": {
                            "total_actions": 100,
                            "correction_summary": [{"changes": [{"from": "地", "to": "的"}],
                                                    "events": 1, "actions": 10}],
                        },
                        "candidate": {
                            "total_actions": 100 + delta,
                            "correction_summary": [{"changes": [{"from": "地", "to": "的"}],
                                                    "events": 1, "actions": 10 + delta}],
                        },
                    },
                })
            payload = {
                "sample": sample,
                "comparisons": {"candidate": {
                    "before": 1000, "after": 922, "delta": -78,
                    "reduction_percent": 7.8, "improved_articles": 8,
                    "unchanged_articles": 0, "regressed_articles": 2,
                    "worst_regression": 1, "saved_actions": 80,
                    "added_actions": 2, "passes": False, "syllables": 10,
                    "corrections_before": 10, "corrections_after": 2,
                }},
                "articles": articles,
            }
            path.write_text(json.dumps(payload), encoding="utf-8")
            result = unigram_summary.cohort(path, "candidate")
            self.assertFalse(result["stable"])
            self.assertEqual(next(row for row in result["source_versions"]
                                  if row["name"] == "v3")["delta"], 2)

    def test_iterative_segmenter_uses_model_probability_and_unknown_boundaries(self):
        phrase = iterative_unigram.segment_run(
            "甲乙", {"甲": math.log10(0.4), "乙": math.log10(0.4), "甲乙": math.log10(0.2)})
        self.assertEqual(phrase, ("甲乙",))
        unknown = iterative_unigram.segment_run(
            "甲龘乙", {"甲": math.log10(0.5), "乙": math.log10(0.5)})
        self.assertEqual(unknown, ("甲", None, "乙"))

    def test_incomplete_comparison_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "every sampled article"):
            write_comparison(Path("unused"), {"articles": [{}, {}], "count": 2},
                             {"a": Path("unused")}, {"a": []}, t.Policy(), t.DEFAULT_DB)

    def test_global_prior_reconstruction_matches_cooker_formula(self):
        with tempfile.TemporaryDirectory() as directory:
            base, result = Path(directory) / "base.db", Path(directory) / "result.db"
            old, new, outgoing, p_word, p_eos = 1000, 250, 3, 0.01, 0.1
            backoff = math.log10(old / (old + outgoing))
            with t.writable_db(base) as db:
                db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff); CREATE TABLE bigrams(qstring,previous,current,probability);")
                db.executemany("INSERT INTO unigrams VALUES(?,?,?,?)", [
                    ("!", "", 0, backoff), ("$", "", 0, 0), ("*", "", -99, 0),
                    ("aa", "甲", math.log10(p_word), backoff)])
                db.executemany("INSERT INTO bigrams VALUES(?,?,?,?)", [
                    ("! aa", "", "甲", math.log10((0.5 + old * p_word) / (outgoing + old))),
                    ("aa $", "甲", "", math.log10((1 + old * p_eos) / (outgoing + old)))])
            before = t.sha256(base)
            metadata = sweep.reweight(base, result, new)
            self.assertEqual(metadata["unigram_probabilities_changed"], 0)
            with t.connect(result) as db:
                self.assertAlmostEqual(db.execute("SELECT probability FROM bigrams WHERE current='甲'").fetchone()[0],
                                       math.log10((0.5 + new * p_word) / (outgoing + new)), places=12)
                self.assertAlmostEqual(db.execute("SELECT probability FROM bigrams WHERE current=''").fetchone()[0],
                                       math.log10((1 + new * p_eos) / (outgoing + new)), places=12)
                self.assertAlmostEqual(db.execute("SELECT backoff FROM unigrams WHERE current='甲'").fetchone()[0],
                                       math.log10(new / (outgoing + new)), places=12)
            self.assertEqual(t.sha256(base), before)
            identity = Path(directory) / "identity.db"
            sweep.reweight(base, identity, old)
            with t.connect(identity) as a, t.connect(base) as b:
                self.assertEqual(a.execute("SELECT * FROM bigrams").fetchall(), b.execute("SELECT * FROM bigrams").fetchall())


if __name__ == "__main__":
    unittest.main()
