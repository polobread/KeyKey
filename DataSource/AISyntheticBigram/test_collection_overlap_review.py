import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("overlap_review", Path(__file__).with_name("review-collection-unigram-overlap.py"))
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


class ReadingPathTests(unittest.TestCase):
    def test_split_only_excludes_stronger_full_phrase(self):
        index = {"aa": [("甲", -2)], "bb": [("乙", -3)], "aabb": [("甲乙", -1)]}
        self.assertEqual(review.best_path("aabb", index), (-1, ["甲乙"]))
        self.assertEqual(review.best_path("aabb", index, True), (-5, ["甲", "乙"]))

    def test_best_path_considers_all_reading_candidates_and_segmentations(self):
        index = {"aa": [("甲", -4), ("乙", -1)], "bb": [("丙", -2)], "cc": [("丁", -2)],
                 "bbcc": [("丙丁", -1)]}
        self.assertEqual(review.best_path("aabbcc", index), (-2, ["乙", "丙丁"]))

    def test_missing_reading_does_not_invent_a_competitor(self):
        score, words = review.best_path("aabb", {"aa": [("甲", -1)]})
        self.assertEqual(score, float("-inf"))
        self.assertEqual(words, [])


if __name__ == "__main__":
    unittest.main()
