"""Accounting regression tests: keep context and shared event costs intact."""
from copy import deepcopy
from pathlib import Path
import tempfile
import unittest

import typing_cost as t
from typing_cost_filter import exclude_zero_count_actions, load_zero_count_characters


class ZeroFrequencyCostTests(unittest.TestCase):
    def setUp(self):
        self.jia, self.yi = map(t.query_for_reading, ("ㄐㄧㄚˇ", "ㄧˇ"))
        self.document = [{"han": True, "text": "甲乙", "queries": [self.jia, self.yi]}]

    def report(self, mixed=False):
        changes = ([{"index": 0, "from": "假", "to": "甲"}] if mixed else [])
        changes.append({"index": 1, "from": "以", "to": "乙"})
        event = {"block": 0, "changes": changes, "candidate_rank": 9,
                 "actions": {"target_clicks": 1, "candidate_selections": 1, "page_turns": 1},
                 "action_count": 3}
        cost, summary, characters = t.summarize_corrections([event])
        actions = {"phonetic_keys": t.key_count(self.jia) + t.key_count(self.yi),
                   "literal_keys": 0, "commit_keys": 1,
                   "target_clicks": 1, "candidate_selections": 1, "page_turns": 1}
        return {"total_actions": sum(actions.values()), "actions": actions,
                "syllables": 2, "corrections": 1, "correction_actions": cost,
                "correction_summary": summary, "character_correction_summary": characters,
                "errors": [event], "policy": {}}

    def test_zero_only_correction_removes_full_event_and_own_keys(self):
        raw = self.report()
        result = exclude_zero_count_actions(raw, self.document, {"乙"})
        self.assertEqual(result["total_actions"], raw["total_actions"] - t.key_count(self.yi) - 3)
        self.assertEqual(result["correction_actions"], 0)
        self.assertEqual(result["actions"]["page_turns"], 0)
        self.assertEqual(result["actions"]["commit_keys"], 1)
        self.assertEqual(result["counted_syllables"], 1)
        self.assertEqual(result["syllables"], 2)

    def test_mixed_word_event_keeps_whole_cost_for_nonzero_target(self):
        result = exclude_zero_count_actions(self.report(mixed=True), self.document, {"乙"})
        self.assertEqual(result["correction_actions"], 3)
        self.assertEqual(result["errors"][0]["changes"], [{"index": 0, "from": "假", "to": "甲"}])
        self.assertEqual([r["character"] for r in result["character_correction_summary"]], ["甲"])

    def test_every_target_zero_keeps_context_commit(self):
        result = exclude_zero_count_actions(self.report(), self.document, {"甲", "乙"})
        self.assertEqual(result["total_actions"], 1)
        self.assertEqual(result["counted_syllables"], 0)

    def test_input_and_unfiltered_report_are_not_mutated(self):
        raw = self.report(mixed=True)
        original, doc = deepcopy(raw), deepcopy(self.document)
        result = exclude_zero_count_actions(raw, self.document, {"乙"})
        self.assertEqual(raw, original)
        self.assertEqual(self.document, doc)
        self.assertEqual(result["zero_frequency_exclusion"]["positions"][0]["index"], 1)

    def test_missing_or_positive_character_keeps_its_cost(self):
        raw = self.report()
        result = exclude_zero_count_actions(raw, self.document, set())
        for key in ("actions", "errors", "total_actions", "character_correction_summary"):
            self.assertEqual(result[key], raw[key])

    def test_cannot_apply_exclusion_twice(self):
        result = exclude_zero_count_actions(self.report(), self.document, {"乙"})
        with self.assertRaisesRegex(ValueError, "already"):
            exclude_zero_count_actions(result, self.document, {"乙"})

    def test_changed_input_is_rejected(self):
        document = deepcopy(self.document)
        document[0]["text"] = "甲丙"
        with self.assertRaisesRegex(ValueError, "target differs"):
            exclude_zero_count_actions(self.report(), document, {"乙"})

    def test_zero_source_is_exact_and_last_row_wins(self):
        with tempfile.TemporaryDirectory() as name:
            path = Path(name) / "counts"
            path.write_text("甲 0\n乙 0.000001\n丙 0\n丙 1\n丁戊 0\n", encoding="utf-8")
            self.assertEqual(load_zero_count_characters(path), {"甲"})

    def test_invalid_count_is_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            path = Path(name) / "counts"
            for value in ("NaN", "-1", "Infinity", "bad"):
                path.write_text("甲 " + value + "\n", encoding="utf-8")
                with self.assertRaises(ValueError):
                    load_zero_count_characters(path)


if __name__ == "__main__":
    unittest.main()
