import math
from pathlib import Path
import sqlite3
import tempfile
import unittest

from phrase_unigram_supplement import POST_TRAINING, apply, query_for_reading, strongest_competitor, verify_post_training


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

    def test_post_training_entries_preserve_reviewed_counts_without_bigrams(self):
        header, pre_training = self.path.read_text(encoding="utf-8").splitlines()
        self.path.write_text(f"{header}\tstage\n{pre_training}\tpre-training\n"
                             "舊了\t306\tㄐㄧㄡˋ ㄌㄜ˙\t4\t3\treviewed phrase\tpost-training\n",
                             encoding="utf-8")
        bigrams = self.db.execute("SELECT * FROM bigrams").fetchall()
        self.assertEqual([row["word"] for row in apply(self.db, self.path, 1000)], ["舊的"])
        self.assertIsNone(self.db.execute("SELECT 1 FROM unigrams WHERE current='舊了'").fetchone())
        result = apply(self.db, self.path, 1000, stage=POST_TRAINING)
        self.assertEqual([row["word"] for row in result], ["舊了"])
        self.assertEqual(self.db.execute("SELECT probability,backoff FROM unigrams WHERE current='舊了'").fetchone(),
                         (math.log10(306 / 1000), 0.0))
        self.assertEqual(self.db.execute("SELECT * FROM bigrams").fetchall(), bigrams)
        verify_post_training(self.db, self.path, 1000, 1)
        phrase_query = self.q1 + query_for_reading("ㄌㄜ˙")
        self.db.execute("INSERT INTO bigrams VALUES(?,?,?,?)", (f"! {phrase_query}", "", "舊了", -.1))
        with self.assertRaisesRegex(ValueError, "has a Bigram edge"):
            verify_post_training(self.db, self.path, 1000, 1)

    def test_post_training_alternate_reading_preserves_existing_reading_and_edges(self):
        header = self.path.read_text(encoding="utf-8").splitlines()[0]
        self.path.write_text(f"{header}\tstage\n"
                             "不想\t10\tㄅㄨˊ ㄒㄧㄤˇ\t4\t3\treviewed reading\tpost-training\n",
                             encoding="utf-8")
        final = query_for_reading("ㄒㄧㄤˇ")
        canonical = query_for_reading("ㄅㄨˋ") + final
        alternate = query_for_reading("ㄅㄨˊ") + final
        canonical_row = (canonical, "不想", -2., -.3)
        canonical_edge = (f"! {canonical}", "", "不想", -.4)
        self.db.execute("INSERT INTO unigrams VALUES(?,?,?,?)", canonical_row)
        self.db.execute("INSERT INTO bigrams VALUES(?,?,?,?)", canonical_edge)

        apply(self.db, self.path, 1000, stage=POST_TRAINING)
        verify_post_training(self.db, self.path, 1000, 1)
        self.assertCountEqual(self.db.execute("SELECT * FROM unigrams WHERE current='不想'").fetchall(),
                              [canonical_row, (alternate, "不想", -2., 0.)])
        self.assertEqual(self.db.execute("SELECT * FROM bigrams WHERE current='不想'").fetchall(),
                         [canonical_edge])
        for edge in [(f"! {alternate}", "", "不想", -.4),
                     (f"{alternate} {self.q2}", "不想", "的", -.4)]:
            with self.subTest(edge=edge):
                self.db.execute("INSERT INTO bigrams VALUES(?,?,?,?)", edge)
                with self.assertRaisesRegex(ValueError, "has a Bigram edge"):
                    verify_post_training(self.db, self.path, 1000, 1)
                self.db.execute("DELETE FROM bigrams WHERE qstring=?", (edge[0],))

    def test_no_training_occurrences_allowed_only_for_post_training_additions(self):
        header = self.path.read_text(encoding="utf-8").splitlines()[0]
        for stage, occurrences, documents in ((POST_TRAINING, 0, 0),
                                              ("pre-training", 0, 0),
                                              (POST_TRAINING, 1, 0)):
            with self.subTest(stage=stage, occurrences=occurrences, documents=documents):
                self.path.write_text(f"{header}\tstage\n"
                                     f"舊的\t11\tㄐㄧㄡˋ ㄉㄜ˙\t{occurrences}\t{documents}\trequested phrase\t{stage}\n",
                                     encoding="utf-8")
                if (stage, occurrences, documents) == (POST_TRAINING, 0, 0):
                    self.assertEqual(apply(self.db, self.path, 1000, stage=stage)[0]["status"], "inserted")
                    verify_post_training(self.db, self.path, 1000, 1)
                else:
                    with self.assertRaisesRegex(ValueError, "missing evidence"):
                        apply(self.db, self.path, 1000, stage=stage)

    def test_reviewed_reweight_updates_only_the_existing_reading_probability(self):
        header = self.path.read_text(encoding="utf-8").splitlines()[0]
        self.path.write_text(f"{header}\tstage\taction\n"
                             "十個\t296\tㄕˊ ㄍㄜˋ\t38\t37\treviewed count\tpost-training\treweight\n",
                             encoding="utf-8")
        query = query_for_reading("ㄕˊ") + query_for_reading("ㄍㄜˋ")
        other = query_for_reading("ㄕˊ") + query_for_reading("ㄍㄜ˙")
        with self.assertRaisesRegex(ValueError, "expected an existing phrase to reweight"):
            apply(self.db, self.path, 1000, stage=POST_TRAINING)
        self.db.executemany("INSERT INTO unigrams VALUES(?,?,?,?)",
                            [(query, "十個", -3., -.2), (other, "十個", -4., -.2)])
        edge = (f"! {query}", "", "十個", -.4)
        self.db.execute("INSERT INTO bigrams VALUES(?,?,?,?)", edge)
        result = apply(self.db, self.path, 1000, stage=POST_TRAINING)
        self.assertEqual(result[0]["status"], "reweighted")
        self.assertCountEqual(self.db.execute("SELECT * FROM unigrams WHERE current='十個'").fetchall(),
                              [(query, "十個", math.log10(.296), -.2), (other, "十個", -4., -.2)])
        self.assertEqual(self.db.execute("SELECT * FROM bigrams WHERE current='十個'").fetchall(), [edge])
        verify_post_training(self.db, self.path, 1000, 1)

    def test_invalid_stage_rejected_before_applying_any_entry(self):
        header, phrase = self.path.read_text(encoding="utf-8").splitlines()
        self.path.write_text(f"{header}\tstage\n{phrase}\ttraining\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "invalid phrase supplement stage"):
            apply(self.db, self.path, 1000)
        self.assertIsNone(self.db.execute("SELECT 1 FROM unigrams WHERE current='舊的'").fetchone())

    def test_invalid_reading_rejected(self):
        for reading in ("", "ˋ", "ㄐㄐ", "invalid"):
            with self.assertRaises(ValueError):
                query_for_reading(reading)


if __name__ == "__main__":
    unittest.main()
