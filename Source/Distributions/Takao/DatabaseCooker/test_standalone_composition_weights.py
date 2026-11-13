"""Verify the weight cook preserves row order and effective word counts."""
import json
import math
from pathlib import Path
import sqlite3
import tempfile
import unittest

from standalone_composition_weights import apply, load, verify


class StandaloneCompositionWeightsTests(unittest.TestCase):
    def setUp(self):
        self.database = sqlite3.connect(":memory:")
        self.addCleanup(self.database.close)
        self.database.executescript("""
            CREATE TABLE unigrams(qstring,current,probability,backoff);
            CREATE TABLE bigrams(qstring,previous,current,probability);
            INSERT INTO unigrams VALUES ('A0','失',-5.0,-0.5);
            INSERT INTO bigrams VALUES ('! A0','','失',-4.0);
        """)
        self.weights = {
            "format": 1, "unigram_total_count": 100,
            "unigrams": [
                {"key": ["A0", "失"], "before": [-5, -0.5], "after": [-2, -0.5]},
                {"key": ["A0B0", "失誤"], "before": None, "after": [-3, 0]},
                {"key": ["A0C0", "失去"], "before": None, "after": [-3, 0]},
            ],
            "bigrams": [
                {"key": ["! A0", "", "失"], "before": [-4], "after": [-2]},
                {"key": ["! B0", "", "疵"], "before": None, "after": [-3]},
            ],
        }

    def test_update_preserves_rowids_and_inserts_follow_the_source_order(self):
        apply(self.database, self.weights)
        verify(self.database, self.weights)
        self.assertEqual(self.database.execute("SELECT rowid,current FROM unigrams ORDER BY rowid").fetchall(),
                         [(1, "失"), (2, "失誤"), (3, "失去")])
        self.assertEqual(self.database.execute("SELECT rowid,current FROM bigrams ORDER BY rowid").fetchall(),
                         [(1, "失"), (2, "疵")])
        self.database.execute("UPDATE unigrams SET probability=-9 WHERE qstring='A0'")
        with self.assertRaisesRegex(ValueError, "reviewed value"):
            verify(self.database, self.weights)

    def test_rebuild_accepts_changed_scores_and_row_presence(self):
        self.database.executescript("""
            UPDATE unigrams SET probability=-7, backoff=-1 WHERE qstring='A0';
            INSERT INTO unigrams VALUES ('A0B0','失誤',-10,0);
            DELETE FROM bigrams WHERE qstring='! A0';
        """)
        apply(self.database, self.weights)
        verify(self.database, self.weights)
        self.assertEqual(self.database.execute("SELECT rowid,current,probability FROM unigrams ORDER BY rowid").fetchall(),
                         [(1, "失", -2), (2, "失誤", -3), (3, "失去", -3)])
        self.assertEqual(self.database.execute("SELECT current,probability FROM bigrams ORDER BY rowid").fetchall(),
                         [("失", -2), ("疵", -3)])

    def test_duplicate_db_key_rolls_back_earlier_updates(self):
        self.database.executescript("INSERT INTO bigrams VALUES ('! A0','','失',-6);")
        with self.assertRaisesRegex(ValueError, "duplicate bigrams rows"):
            apply(self.database, self.weights)
        self.assertEqual(self.database.execute("SELECT current,probability FROM unigrams").fetchall(),
                         [("失", -5)])
        self.assertEqual(self.database.execute("SELECT current,probability FROM bigrams ORDER BY rowid").fetchall(),
                         [("失", -4), ("失", -6)])

    def test_new_denominator_preserves_unigram_counts_without_changing_bigrams(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "weights.json"
            path.write_text(json.dumps(self.weights))
            changed = load(path, 200)
            for original, normalized in zip(self.weights["unigrams"], changed["unigrams"]):
                self.assertAlmostEqual(10 ** normalized["after"][0] * 200,
                                       10 ** original["after"][0] * 100)
                self.assertEqual(normalized["before"], original["before"])
                self.assertEqual(normalized["after"][1], original["after"][1])
            self.assertEqual(changed["bigrams"], self.weights["bigrams"])
            apply(self.database, changed)
            verify(self.database, changed)

    def test_source_rejects_an_invalid_denominator_or_duplicate_key(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "weights.json"
            path.write_text(json.dumps(self.weights))
            for total in (0, -1, math.inf, True):
                with self.subTest(total=total), self.assertRaisesRegex(ValueError, "unigram total"):
                    load(path, total)
            self.assertEqual(load(path, 100), self.weights)
            self.weights["unigrams"].append(self.weights["unigrams"][0])
            path.write_text(json.dumps(self.weights))
            with self.assertRaisesRegex(ValueError, "duplicate"):
                load(path, 100)


if __name__ == "__main__":
    unittest.main()
