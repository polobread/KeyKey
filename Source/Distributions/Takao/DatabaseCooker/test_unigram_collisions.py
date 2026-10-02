from pathlib import Path
import math
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
import rebuild_model

from unigram_collisions import CollisionIndex
from rebuild_model import add_convenience_words, standard_cin_query
from phrase_unigram_supplement import query_for_reading


class CollisionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        counts, mappings = self.root / "counts", self.root / "mappings"
        counts.write_text("視線 100\n新視線 20\n示現 0\n甲乙丙 10\n")
        mappings.write_text("視線 ㄕˋ ㄒㄧㄢˋ\n新視線 ㄒㄧㄣ ㄕˋ ㄒㄧㄢˋ\n示現 ㄕˋ ㄒㄧㄢˋ\n甲乙丙 ㄐㄧㄚˇ ㄧˇ ㄅㄧㄥˇ\n")
        self.index = CollisionIndex(counts, mappings)

    def test_full_and_overlapping_two_character_conflicts_name_the_source(self):
        rows = self.index.conflicts("示現", "ㄕˋ ㄒㄧㄢˋ")
        self.assertTrue(any(r["reason"] == "full_homophone" and r["conflict_word"] == "視線" for r in rows))
        self.assertTrue(any(r["conflict_word"] == "新視線" and r["conflict_start"] == 2 for r in rows))
        rows = self.index.conflicts("義炳丁", "ㄧˇ ㄅㄧㄥˇ ㄉㄧㄥ")
        self.assertEqual([(r["span_text"], r["conflict_word"], r["conflict_text"]) for r in rows], [("義炳", "甲乙丙", "乙丙")])

    def test_same_text_single_syllable_and_different_tones_are_not_collisions(self):
        self.assertFalse(self.index.conflicts("視線圖", "ㄕˋ ㄒㄧㄢˋ ㄊㄨˊ"))
        self.assertFalse(self.index.conflicts("是新", "ㄕˋ ㄒㄧㄣ"))
        self.assertFalse(self.index.conflicts("示先", "ㄕˋ ㄒㄧㄢ"))
        self.assertNotIn("示現", self.index.words)
        self.assertTrue(self.index.ranking_conflicts("示現", "ㄕˋ ㄒㄧㄢˋ"))
        self.assertFalse(self.index.ranking_conflicts("新示現", "ㄒㄧㄣˊ ㄕˋ ㄒㄧㄢˋ"))
        self.assertTrue(self.index.conflicts("新示現", "ㄒㄧㄣˊ ㄕˋ ㄒㄧㄢˋ"))

    def test_cin_matches_last_component_wins_and_tone_only_symbols(self):
        self.assertEqual(standard_cin_query("ㄐㄧˊㄧ"), query_for_reading("ㄐㄧˊ"))
        self.assertEqual(standard_cin_query("ˇ"), chr(48 + 2464 % 79) + chr(48 + 2464 // 79))

    def test_anime_is_low_frequency_but_complete_reading_can_beat_split_without_bigram_changes(self):
        path = self.root / "model.db"
        with sqlite3.connect(path) as db:
            db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff); CREATE TABLE bigrams(qstring,previous,current,probability);")
            for word, reading in (("甲", "ㄐㄧㄚˇ"), ("乙", "ㄧˇ"), ("丙", "ㄅㄧㄥˇ")):
                db.execute("INSERT INTO unigrams VALUES(?,?,?,0)", (query_for_reading(reading), word, -5))
            db.execute("INSERT INTO bigrams VALUES('sample','甲','乙',-3)")
        entries = [dict(word="賈以炳", reading="ㄐㄧㄚˇ ㄧˇ ㄅㄧㄥˇ", target_count=0.01)]
        add_convenience_words(path, entries, 1000)
        with sqlite3.connect(path) as db:
            self.assertEqual(db.execute("SELECT probability,backoff FROM unigrams WHERE current='賈以炳'").fetchone(), (-5, 0))
            self.assertEqual(db.execute("SELECT * FROM bigrams").fetchall(), [('sample', '甲', '乙', -3)])
            self.assertEqual(db.execute("SELECT COUNT(*) FROM unigrams WHERE probability=-5 AND current<>'賈以炳'").fetchone()[0], 3)
        self.assertAlmostEqual(math.log10(entries[0]["target_count"] / 1000), -5)

    def test_complete_homophone_is_retained_below_all_existing_words(self):
        path = self.root / "homophones.db"
        query = query_for_reading("ㄊㄨㄥˊ") + query_for_reading("ㄖㄣˊ")
        with sqlite3.connect(path) as db:
            db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff); CREATE TABLE bigrams(qstring,previous,current,probability);")
            db.executemany("INSERT INTO unigrams VALUES(?,?,?,0)", [(query, "同人", -3), (query, "瞳仁", -8)])
        entries = [dict(word="桐人", reading="ㄊㄨㄥˊ ㄖㄣˊ", target_count=0.01)]
        add_convenience_words(path, entries, 1000)
        with sqlite3.connect(path) as db:
            self.assertEqual(db.execute("SELECT current,probability FROM unigrams ORDER BY probability DESC").fetchall(),
                             [("同人", -3), ("瞳仁", -8), ("桐人", -10)])
            self.assertEqual(db.execute("SELECT COUNT(*) FROM bigrams").fetchone()[0], 0)
        self.assertAlmostEqual(entries[0]["target_count"], 1e-7)

    def test_personal_name_is_added_after_training_without_corpus_frequency_boost(self):
        path = self.root / "people.db"
        with sqlite3.connect(path) as db:
            db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff); CREATE TABLE bigrams(qstring,previous,current,probability); INSERT INTO bigrams VALUES('original','甲','乙',-3);")
        entries = [dict(word="甲乙丙", reading="ㄐㄧㄚˇ ㄧˇ ㄅㄧㄥˇ", target_count=100)]
        add_convenience_words(path, entries, 1000, maximum_count=1)
        with sqlite3.connect(path) as db:
            self.assertEqual(db.execute("SELECT probability,backoff FROM unigrams WHERE current='甲乙丙'").fetchone(), (-3, 0))
            self.assertEqual(db.execute("SELECT * FROM bigrams").fetchall(), [('original', '甲', '乙', -3)])

    def test_cooker_rebuilds_both_tables_and_does_not_keep_deleted_source_words(self):
        data = self.root / "DataSource/McBopomofo"
        data.mkdir(parents=True)
        counts = data / "phrase.occ"
        counts.write_text("甲 20\n乙 10\n丙 10\n")
        (data / "BPMFMappings.txt").write_text("甲 ㄐㄧㄚˇ\n乙 ㄧˇ\n丙 ㄅㄧㄥˇ\n")
        for name in ("supplemental-lexicon.tsv", "numeric-unit-lexicon.tsv"):
            (self.root / name).write_text("")
        cin, corpus, path = self.root / "bpmf.cin", self.root / "corpus", self.root / "recook.db"
        cin.write_text("%chardef begin\n%chardef end\n")
        corpus.write_text("甲 乙\n")
        with sqlite3.connect(path) as db:
            db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff); CREATE TABLE bigrams(qstring,previous,current,probability); INSERT INTO unigrams VALUES('stale','舊來源',-2,0);")
        with patch.object(rebuild_model, "ROOT", self.root), patch.object(rebuild_model, "DATA", self.root):
            rebuild_model.cook(path, cin, self.root / "first", corpus=corpus)
            counts.write_text("甲 20\n丙 10\n")
            corpus.write_text("甲 丙\n")
            rebuild_model.cook(path, cin, self.root / "second", corpus=corpus)
        with sqlite3.connect(path) as db:
            self.assertFalse(db.execute("SELECT 1 FROM unigrams WHERE current IN ('乙','舊來源')").fetchall())
            self.assertFalse(db.execute("SELECT 1 FROM bigrams WHERE current='乙' OR previous='乙'").fetchall())
            self.assertTrue(db.execute("SELECT 1 FROM bigrams WHERE previous='甲' AND current='丙'").fetchall())


if __name__ == "__main__":
    unittest.main()
