import math
from pathlib import Path
import sqlite3
import tempfile
import unittest

from phrase_unigram_supplement import apply, query_for_reading, strongest_competitor


class WholePhraseTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.addCleanup(self.db.close)
        self.db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff);"
                              "CREATE TABLE bigrams(qstring,previous,current,probability);")
        self.q1, self.q2 = query_for_reading("ㄐㄧㄡˋ"), query_for_reading("ㄉㄜ˙")
        self.db.executemany("INSERT INTO unigrams VALUES(?,?,?,?)", [
            (self.q1, "就", -1., -.2), (self.q1, "舊", -2., -.3), (self.q2, "的", -1., -.4)])
        self.db.execute("INSERT INTO bigrams VALUES(?,?,?,?)", (self.q1 + " " + self.q2, "舊", "的", -.1))
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "supplement.tsv"
        self.write(11)

    def write(self, count):
        self.path.write_text("word\ttarget_count\treading\ttraining_occurrences\ttraining_documents\treason\n"
                             f"舊的\t{count}\tㄐㄧㄡˋ ㄉㄜ˙\t40\t34\treviewed phrase\n", encoding="utf-8")

    def test_missing_phrase_beats_split_without_modifying_existing_data(self):
        unigrams = list(self.db.execute("SELECT * FROM unigrams"))
        bigrams = list(self.db.execute("SELECT * FROM bigrams"))
        result = apply(self.db, self.path, 1000)
        self.assertEqual(result[0]["status"], "inserted")
        phrase = self.db.execute("SELECT probability,backoff FROM unigrams WHERE current='舊的'").fetchone()
        self.assertGreater(phrase[0], strongest_competitor(self.db, self.q1 + self.q2, "舊的"))
        self.assertEqual(phrase[1], 0)
        self.assertEqual(unigrams, list(self.db.execute("SELECT * FROM unigrams WHERE current<>'舊的'")))
        self.assertEqual(bigrams, list(self.db.execute("SELECT * FROM bigrams")))
        self.assertEqual(apply(self.db, self.path, 1000)[0]["status"], "retained")
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM unigrams").fetchone()[0], 4)

    def test_changed_competitor_requires_review(self):
        self.db.execute("UPDATE unigrams SET probability=-.5 WHERE current='就'")
        with self.assertRaisesRegex(ValueError, "expected minimum"):
            apply(self.db, self.path, 1000)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM unigrams").fetchone()[0], 3)

    def test_existing_phrase_cannot_be_silently_boosted(self):
        self.db.execute("INSERT INTO unigrams VALUES(?,?,?,0)", (self.q1 + self.q2, "舊的", -3))
        with self.assertRaisesRegex(ValueError, "existing phrase changed"):
            apply(self.db, self.path, 1000)

    def test_invalid_reading_rejected(self):
        for reading in ("", "ˋ", "ㄐㄐ", "invalid"):
            with self.assertRaises(ValueError):
                query_for_reading(reading)


if __name__ == "__main__":
    unittest.main()
