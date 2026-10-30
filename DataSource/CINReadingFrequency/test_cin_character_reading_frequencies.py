"""The CIN-derived table affects only multi-reading positive-count characters."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from decimal import Decimal

spec = importlib.util.spec_from_file_location(
    "cin_frequency_builder", Path(__file__).with_name("build-cin-character-reading-frequencies.py"))
builder = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = builder
spec.loader.exec_module(builder)


class CinFrequencyTests(unittest.TestCase):
    def fixture(self, extra=""):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "sample.cin"
        path.write_text(
            "# Header tokens do not count as readings\n"
            "%keyname begin\nc ㄏ\nj ㄨ\nv ㄒ\nm ㄩ\n3 ˇ\n%keyname end\n"
            "%chardef begin\ncj3 虎\ncj3 琥\ncj3 滸\ncj3 唬\ncj3 許\n"
            "vm3 許\ncj 虎\n" + extra + "%chardef end\n", encoding="utf-8")
        return builder.load_cin(path)

    def test_all_readings_are_separate_and_sibling_first_choice_keeps_full_count(self):
        groups, readings, _ = self.fixture()
        counts = {"虎": 1227, "琥": 33, "滸": 29, "唬": 74, "許": 13105}
        rows, targets = builder.build_rows(groups, readings, counts, Decimal(".9"))
        self.assertEqual(targets, {"許", "虎"})
        by_key = {(r["character"], r["qstring"]): r for r in rows}
        hu = by_key[("許", "vO")]
        self.assertEqual((hu["cin_rank"], hu["target_count"]), (5, "26.1"))
        self.assertEqual((hu["limit_character"], hu["limit_count"]), ("滸", "29"))
        self.assertEqual(by_key[("許", "@P")]["target_count"], "13105")
        self.assertEqual(by_key[("虎", "vO")]["target_count"], "1227")
        self.assertTrue(all(r["character"] not in {"琥", "滸", "唬"} for r in rows))
        self.assertEqual(counts["許"], 13105)

    def test_duplicate_keyboard_codes_for_same_reading_keep_first_rank(self):
        groups, readings, duplicates = self.fixture("cj3c 許\n")
        self.assertEqual(len(duplicates), 1)
        self.assertEqual(len(readings["許"]), 2)
        self.assertEqual([r.character for r in groups["vO"]], ["虎", "琥", "滸", "唬", "許"])
        self.assertEqual(duplicates[0]["first_code"], "cj3")

    def test_zero_or_missing_predecessors_do_not_erase_a_positive_candidate(self):
        groups, readings, _ = self.fixture()
        rows, _ = builder.build_rows(groups, readings, {"許": 10, "虎": 0}, ".9")
        self.assertEqual({r["character"] for r in rows}, {"許"})
        hu = next(r for r in rows if r["qstring"] == "vO")
        self.assertEqual(hu["target_count"], "10")
        self.assertEqual(hu["positive_rank"], 1)
        self.assertEqual(hu["cin_rank"], 5)
        self.assertEqual(hu["adjustment"], "first_positive")

    def test_earlier_adjusted_multi_reading_candidate_also_caps_later_target(self):
        groups, readings, _ = self.fixture("vm3 虎\n")
        rows, _ = builder.build_rows(groups, readings, {"許": 10, "虎": 100}, ".9")
        sibling = {r["character"]: r for r in rows if r["qstring"] == "@P"}
        self.assertEqual(sibling["許"]["target_count"], "10")
        self.assertEqual(sibling["虎"]["target_count"], "9")

    def test_phonetic_symbol_keeps_its_cin_slot_but_does_not_cap_a_character(self):
        q1, reading1 = builder.query_for_code("-", {"-": "ㄦ"})
        q2, reading2 = builder.query_for_code("-3", {"-": "ㄦ", "3": "ˇ"})
        groups = {q1: [builder.Entry("ㄦ", q1, reading1, "-", 1),
                       builder.Entry("兒", q1, reading1, "-", 2)],
                  q2: [builder.Entry("兒", q2, reading2, "-3", 3)]}
        rows, _ = builder.build_rows(groups, {"ㄦ": {q1}, "兒": {q1, q2}},
                                     {"ㄦ": 7, "兒": 9194}, ".9")
        row = next(r for r in rows if r["qstring"] == q1)
        self.assertEqual(row["cin_rank"], 2)
        self.assertEqual(row["positive_rank"], 1)
        self.assertEqual(row["target_count"], "9194")

    def test_source_zero_then_positive_multiword_entry_does_not_block_single_characters(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "phrase.occ"
            path.write_text("亞美尼亞 0\n亞美尼亞 3\n許 13105\n", encoding="utf-8")
            counts = builder.load_counts(path)
            self.assertEqual(counts["許"], 13105)
            self.assertEqual(counts["亞美尼亞"], 3)

    def test_invalid_ratios_and_incomplete_codes_are_rejected(self):
        for value in ("0", "1", "-.1", "1.1", "NaN", "Infinity", "invalid"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                builder.parse_ratio(value)
        with self.assertRaisesRegex(ValueError, "unknown CIN key"):
            builder.query_for_code("?", {"c": "ㄏ"})


if __name__ == "__main__":
    unittest.main()
