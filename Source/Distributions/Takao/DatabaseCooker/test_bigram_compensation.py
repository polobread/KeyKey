"""Model invariants independent of the production vocabulary and error examples."""
from collections import Counter
import math
import sqlite3
import unittest

from bigram_compensation import bounded_observation, compensate, document_frequencies, sequences


class CompensationTests(unittest.TestCase):
    def fixture(self):
        db = sqlite3.connect(":memory:")
        self.addCleanup(db.close)
        db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff);"
                         "CREATE TABLE bigrams(qstring,previous,current,probability);")
        db.executemany("INSERT INTO unigrams VALUES(?,?,?,?)", [
            ("!", "", 0, 0), ("$", "", 0, 0), ("*", "", -99, 0),
            ("aa", "甲", math.log10(.1), -.8),
            ("bb", "乙", math.log10(.2), -.3),
            ("cc", "丙", math.log10(.7), -.9),
        ])
        db.executemany("INSERT INTO bigrams VALUES(?,?,?,?)", [
            ("! aa", "", "甲", -1), ("aa bb", "甲", "乙", -.2),
            ("aa cc", "甲", "丙", -.4), ("aa $", "甲", "", -.6),
            ("bb cc", "乙", "丙", -.7),
        ])
        return db

    def test_rare_reading_has_bounded_likelihood_ratio(self):
        for mass in (1e-12, 1e-6, .01):
            obs = bounded_observation(10000, mass, mass * 2, 1000, 2)
            self.assertLessEqual((1000 * mass + obs) / (1000 * mass), 100 + 1e-10)
        self.assertEqual(bounded_observation(0, .1, .2, 1000, 2), 0)

    def test_normalization_and_missing_edges_use_one_denominator(self):
        db = self.fixture()
        before = list(db.execute("SELECT qstring,current,probability FROM unigrams"))
        identities = list(db.execute("SELECT qstring,previous,current FROM bigrams"))
        compensate(db, Counter({("", "甲"): 100, ("甲", "乙"): 30, ("甲", "丙"): 4}), max_log_lift=2)
        backoff = db.execute("SELECT backoff FROM unigrams WHERE current='甲'").fetchone()[0]
        edges = dict(db.execute("SELECT current,probability FROM bigrams WHERE previous='甲' AND current<>''"))
        self.assertAlmostEqual(sum(10 ** p for p in edges.values()) + .1 * 10 ** backoff, 1)
        eos = db.execute("SELECT probability FROM bigrams WHERE qstring='aa $'").fetchone()[0]
        self.assertEqual(eos, backoff)
        self.assertEqual(before, list(db.execute("SELECT qstring,current,probability FROM unigrams")))
        self.assertEqual(identities, list(db.execute("SELECT qstring,previous,current FROM bigrams")))
        unsupported = db.execute("SELECT probability FROM bigrams WHERE qstring='bb cc'").fetchone()[0]
        self.assertAlmostEqual(unsupported, math.log10(.7))

    def test_document_repetition_and_boundaries_do_not_invent_evidence(self):
        probabilities = {c: -1 for c in "甲乙丙"}
        self.assertEqual(list(sequences("甲。 乙，丙", probabilities)), [["甲"], ["乙"], ["丙"]])
        self.assertEqual(list(sequences("甲丁乙", probabilities)), [["甲"], ["乙"]])
        counts = document_frequencies([{"text": "甲乙。甲乙。"}, {"text": "甲乙"}], probabilities)
        self.assertEqual(counts[("甲", "乙")], 2)

    def test_supplement_mass_is_included_in_the_denominator(self):
        db = self.fixture()
        db.execute("UPDATE unigrams SET probability=? WHERE current='丙'", (math.log10(.8),))
        compensate(db, Counter(), max_log_lift=2)
        backoff = db.execute("SELECT backoff FROM unigrams WHERE current='甲'").fetchone()[0]
        self.assertAlmostEqual(1.1 * 10 ** backoff, 1)

    def test_invalid_numeric_parameters_are_rejected(self):
        for prior, lift in [(0, 1), (-1, 1), (math.inf, 1), (1000, math.nan), (1000, -1)]:
            with self.assertRaises(ValueError):
                bounded_observation(1, .1, .2, prior, lift)


if __name__ == "__main__":
    unittest.main()
