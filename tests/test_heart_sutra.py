import io
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
import tempfile
import unittest

from heart_sutra import (
    FIXTURE,
    candidate_positions,
    check_positions,
    compare,
    parse_fixture,
)


class HeartSutraOracleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expected, cls.pairs = parse_fixture(FIXTURE.read_text(encoding="utf-8"))
        cls.positions = candidate_positions(cls.pairs)

    def test_full_passage_and_second_page_candidate(self):
        self.assertEqual(len(self.pairs), 268)
        self.assertTrue(self.expected.startswith("般若波羅蜜多心經"))
        self.assertTrue(self.expected.rstrip().endswith("菩提薩婆訶。"))
        self.assertEqual(self.positions[self.pairs.index(("ㄅㄛ", "波"))], 18)

    def test_prefix_cannot_pass_as_full_capture(self):
        with redirect_stderr(io.StringIO()):
            self.assertFalse(compare(self.expected, "般若波羅蜜多心經", "macos"))

    def test_missing_and_wrong_rank_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "positions.tsv"
            rows = [
                f"{index}\t{reading}\t{character}\t{rank}"
                for index, ((reading, character), rank)
                in enumerate(zip(self.pairs, self.positions), 1)
            ]
            path.write_text("\n".join(rows) + "\n", encoding="utf-8")
            with redirect_stdout(io.StringIO()):
                self.assertTrue(check_positions(self.pairs, self.positions, path, "macos"))
            with redirect_stderr(io.StringIO()):
                path.write_text("\n".join(rows[:-1]) + "\n", encoding="utf-8")
                self.assertFalse(check_positions(self.pairs, self.positions, path, "macos"))
                rows[0] = rows[0].rsplit("\t", 1)[0] + "\t999"
                path.write_text("\n".join(rows) + "\n", encoding="utf-8")
                self.assertFalse(check_positions(self.pairs, self.positions, path, "macos"))


if __name__ == "__main__":
    unittest.main()
