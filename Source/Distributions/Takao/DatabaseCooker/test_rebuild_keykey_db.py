import importlib.util
from pathlib import Path
import sqlite3
import unittest
import tempfile

from phrase_unigram_supplement import query_for_reading

spec = importlib.util.spec_from_file_location("rebuild", Path(__file__).with_name("rebuild-keykey-db.py"))
rebuild = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rebuild)


class RebuildTests(unittest.TestCase):
    def test_rejected_publish_only_writes_audit_and_keeps_database_and_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root, stage = Path(directory) / "repo", Path(directory) / "stage"
            root.mkdir(); stage.mkdir()
            for name in ("KeyKey.db", "manifest.json", "cache.java"):
                (root / name).write_bytes(b"previous")
                (stage / name).write_bytes(b"candidate")
            (stage / "reason.json").write_text("over 30 actions")
            files = rebuild.publish_files(stage, root, ["KeyKey.db", "manifest.json", "cache.java"],
                ["reason.json"], rebuild.publication_decision({"delta": 31}), apply=True)
            self.assertEqual(files, ["reason.json"])
            self.assertEqual((root / "reason.json").read_text(), "over 30 actions")
            for name in ("KeyKey.db", "manifest.json", "cache.java"):
                self.assertEqual((root / name).read_bytes(), b"previous")

    def test_total_threshold_includes_thirty_and_rejects_thirty_one(self):
        for change in (-50, 0, 4, 30):
            self.assertEqual(rebuild.publication_decision({"delta": change})["decision"], "adopted")
        result = rebuild.publication_decision({"delta": 31})
        self.assertEqual(result["decision"], "rejected")
        self.assertIn("保留原 DB", result["reason"])

    def test_article_and_basic_diagnostics_do_not_override_user_total_threshold(self):
        delta = {"delta": 4, "regressed_articles": 6,
                 "tiers": {"basic100": {"character_changes": [{"character": "裡", "delta": 1}]}}}
        self.assertEqual(rebuild.publication_decision(delta)["decision"], "adopted")
        with self.assertRaises(ValueError):
            rebuild.publication_decision(delta, -1)

    def test_search_deduplicates_by_word_and_never_overwrites_existing_reading(self):
        with sqlite3.connect(":memory:") as db:
            db.execute("CREATE TABLE unigrams(qstring,current,probability,backoff)")
            db.execute("INSERT INTO unigrams VALUES('original','原詞',-2,-.2)")
            entries = [{"word": "原詞", "query": "other", "count": 99},
                       {"word": "新詞", "query": "new", "count": 1}]
            rebuild.apply_search(db, entries, 1000)
            rebuild.apply_search(db, entries, 1000)
            self.assertEqual(db.execute("SELECT * FROM unigrams").fetchall(),
                             [("original", "原詞", -2, -.2), ("new", "新詞", -3, 0)])


if __name__ == "__main__":
    unittest.main()
