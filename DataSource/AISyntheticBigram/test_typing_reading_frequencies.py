"""Frozen A/B readings prefer phrases/manual conventions over single-character counts."""
import csv
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import typing_cost as t

class ReadingFrequencyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.db, self.table = self.root / "ref.db", self.root / "counts.tsv"
        self.zhong, self.chong, self.yao = map(t.query_for_reading, ("ㄓㄨㄥˋ", "ㄔㄨㄥˊ", "ㄧㄠˋ"))
        with t.writable_db(self.db) as db:
            db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff);")
            db.executemany("INSERT INTO unigrams VALUES(?,?,?,0)", [
                ("*", "", -99), (self.zhong, "重", -1), (self.chong, "重", -3),
                (self.yao, "要", -1), (self.zhong + self.yao, "重要", -.1)])
        self.write_table(90, 100)

    def write_table(self, zhong, chong):
        with self.table.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
            writer.writerow(["character", "reading", "qstring", "cin_rank", "source_count", "target_count"])
            writer.writerow(["重", "ㄓㄨㄥˋ", self.zhong, 3, 100, zhong])
            writer.writerow(["重", "ㄔㄨㄥˊ", self.chong, 1, 100, chong])

    def lexicon(self, enabled=True):
        return t.Lexicon(self.db, reading_frequencies=self.table if enabled else None)

    def test_single_character_prefers_table_count(self):
        self.assertEqual(self.lexicon().segment("重")[0]["query"], self.chong)
        self.assertEqual(self.lexicon(False).segment("重")[0]["query"], self.zhong)

    def test_phrase_keeps_contextual_reading(self):
        self.assertEqual(self.lexicon().segment("重要")[0]["query"], self.zhong + self.yao)

    def test_manual_reading_precedes_table(self):
        path = self.root / "manual.tsv"
        path.write_text("詞\t注音\t理由\n重\tㄓㄨㄥˋ\tmanual\n", encoding="utf-8")
        with patch.object(t, "READING_OVERRIDES", path):
            self.assertEqual(self.lexicon().segment("重")[0]["query"], self.zhong)

    def test_equal_counts_keep_reference_preference(self):
        self.write_table(100, 100)
        self.assertEqual(self.lexicon().segment("重")[0]["query"], self.zhong)

    def test_explicit_article_reading_is_not_replaced(self):
        path = self.root / "article.jsonl"
        path.write_text(json.dumps({"text": "重", "readings": ["ㄓㄨㄥˋ"]}, ensure_ascii=False), encoding="utf-8")
        self.assertEqual(t.load_document(path, self.lexicon())[0]["queries"], [self.zhong])

    def test_only_typeable_readings_are_used(self):
        with t.writable_db(self.db) as db:
            db.execute("DELETE FROM unigrams WHERE qstring=?", (self.chong,))
        self.assertEqual(self.lexicon().segment("重")[0]["query"], self.zhong)

    def test_frozen_reference_is_independent_of_later_model_changes(self):
        path = self.root / "article.txt"
        path.write_text("重，重要", encoding="utf-8")
        reference = self.lexicon()
        before = t.load_document(path, reference)
        with t.writable_db(self.db) as db:
            db.execute("UPDATE unigrams SET probability=-100 WHERE qstring=?", (self.chong,))
        self.assertEqual(t.load_document(path, reference), before)
        self.assertEqual(before[0]["queries"], [self.chong])
        self.assertEqual(before[2]["queries"], [self.zhong, self.yao])

if __name__ == "__main__":
    unittest.main()
