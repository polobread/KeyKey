from pathlib import Path
import sqlite3
import tempfile
import unittest

from collection_unigram_supplement import apply, source_records, verify_sources
from unigram_collisions import CollisionIndex


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        counts = self.root / "counts"
        mappings = self.root / "mappings"
        counts.write_text("新的 10\n")
        mappings.write_text("新的 ㄒㄧㄣ ㄉㄜ˙\n")
        self.index = CollisionIndex(counts, mappings)
        self.db = sqlite3.connect(":memory:")
        self.addCleanup(self.db.close)
        self.db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff);"
                              "CREATE TABLE bigrams(qstring,previous,current,probability);"
                              "INSERT INTO unigrams VALUES('old','新的',-2.0,-0.2);"
                              "INSERT INTO bigrams VALUES('old next','新','的',-1.0);")

    def source(self, name, rows):
        path = self.root / name
        path.write_text("詞\t詞頻\t注音\t分類\n" + rows, encoding="utf-8")
        return path

    def test_existing_text_and_cross_collection_duplicates_are_skipped(self):
        a = self.source("a.tsv", "新的\t99\tㄒㄧㄣ ㄉㄧˋ\t一般\n舊的\t10\tㄐㄧㄡˋ ㄉㄜ˙\t一般\n")
        b = self.source("b.tsv", "舊的\t50\tㄐㄧㄡˋ ㄉㄧˋ\t一般\n")
        old = list(self.db.execute("SELECT * FROM unigrams"))
        bigrams = list(self.db.execute("SELECT * FROM bigrams"))
        result = apply(self.db, [b, a], 1000, collision_index=self.index)
        self.assertEqual(result["totals"], dict(rows=3, inserted=1, existing=1, duplicate=1, rejected=0, collision=0))
        self.assertEqual(list(self.db.execute("SELECT * FROM unigrams WHERE current='新的'")), old)
        self.assertEqual(self.db.execute("SELECT probability,backoff FROM unigrams WHERE current='舊的'").fetchone(), (-3., 0.))
        self.assertEqual(list(self.db.execute("SELECT * FROM bigrams")), bigrams)
        self.assertEqual(apply(self.db, [a, b], 1000)["totals"]["inserted"], 0)

    def test_unencodable_readings_are_reported_and_not_inserted(self):
        a = self.source("a.tsv", "哆啦A夢\t16\tㄉㄨㄛ ㄌㄚ A ㄇㄥˋ\t動漫\n")
        result = apply(self.db, [a], 1000)
        self.assertEqual(result["totals"]["rejected"], 1)
        self.assertEqual(result["rejected"][0]["word"], "哆啦A夢")
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM unigrams").fetchone()[0], 1)

    def test_full_homophone_is_inserted_and_conflict_logged_without_exclusion(self):
        a = self.source("a.tsv", "心的\t10\tㄒㄧㄣ ㄉㄜ˙\t一般\n")
        result = apply(self.db, [a], 1000, collision_index=self.index)
        self.assertEqual(result["totals"]["inserted"], 1)
        self.assertEqual(result["totals"]["collision"], 1)
        self.assertFalse(result["exclusions"])
        self.assertEqual(result["downranked"][0]["conflict_word"], "新的")
        self.assertEqual(self.db.execute("SELECT probability FROM unigrams WHERE current='心的'").fetchone(), (-5,))

    def test_bad_header_does_not_partially_apply(self):
        a = self.source("a.tsv", "舊的\t10\tㄐㄧㄡˋ ㄉㄜ˙\t一般\n")
        b = self.root / "b.tsv"
        b.write_text("invalid\n")
        with self.assertRaisesRegex(ValueError, "unexpected columns"):
            apply(self.db, [a, b], 1000)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM unigrams").fetchone()[0], 1)

    def test_source_identity_changes_are_rejected(self):
        a = self.source("a.tsv", "")
        expected = source_records([a])
        verify_sources([a], expected)
        a.write_text("changed")
        with self.assertRaisesRegex(ValueError, "differ"):
            verify_sources([a], expected)

    def test_chinese_aliases_are_deduplicated_after_normalization(self):
        a = self.source("a.tsv", "新A\t10\tinvalid\t一般\n新Ａ\t20\tinvalid\t一般\n")
        overrides = {word: {"word": "新欸", "reading": "ㄒㄧㄣ ㄟ"} for word in ("新A", "新Ａ")}
        result = apply(self.db, [a], 1000, overrides, collision_index=self.index)
        self.assertEqual(result["totals"]["inserted"], 1)
        self.assertEqual(result["totals"]["duplicate"], 1)
        self.assertEqual(result["totals"]["rejected"], 0)
        self.assertEqual(self.db.execute("SELECT current FROM unigrams WHERE current<>'新的'").fetchall(), [("新欸",)])


if __name__ == "__main__":
    unittest.main()
