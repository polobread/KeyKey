import json
from pathlib import Path
import tempfile
import unittest

from smart_mandarin_model import file_sha256, verify_source_hashes


class PendingRebuildTests(unittest.TestCase):
    def test_old_model_is_buildable_only_for_exact_documented_rejected_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = root / "DataSource/AISyntheticBigram"
            data.mkdir(parents=True)
            names = ["protected.txt", "common.tsv", "search.txt", "accepted.tsv", "review.tsv", "search-trend-reading-overrides.tsv"]
            for name in names: (data / name).write_text("old")
            sources = {"training_articles": [],
                "protected_characters": {"file": "protected.txt", "sha256": file_sha256(data / "protected.txt")},
                "unigram_supplement": {"file": "common.tsv", "sha256": file_sha256(data / "common.tsv")},
                "search_trend_unigram": {"source_file": "search.txt", "source_sha256": file_sha256(data / "search.txt"),
                    "file": "accepted.tsv", "sha256": file_sha256(data / "accepted.tsv"),
                    "review_file": "review.tsv", "review_sha256": file_sha256(data / "review.tsv"),
                    "reading_overrides_sha256": file_sha256(data / "search-trend-reading-overrides.tsv")}}
            manifest = {"sources": sources, "canonical_database_sha256": "old-db-sha"}
            path = data / "manifest.json"
            (data / "search.txt").write_text("new words rejected by the benchmark")
            with self.assertRaises(ValueError): verify_source_hashes(manifest, path)
            audit = data / "rebuild-review/latest.json"
            audit.parent.mkdir()
            review = {"decision": "rejected", "before_sha256": "old-db-sha",
                "inputs": {"DataSource/AISyntheticBigram/search.txt": file_sha256(data / "search.txt")}}
            audit.write_text(json.dumps(review))
            self.assertTrue(verify_source_hashes(manifest, path))
            review["before_sha256"] = "some-other-db"
            audit.write_text(json.dumps(review))
            with self.assertRaises(ValueError): verify_source_hashes(manifest, path)
            review["before_sha256"] = "old-db-sha"
            audit.write_text(json.dumps(review))
            (data / "search.txt").write_text("another unreviewed edit")
            with self.assertRaisesRegex(ValueError, "changed since rejected"):
                verify_source_hashes(manifest, path)


if __name__ == "__main__":
    unittest.main()
