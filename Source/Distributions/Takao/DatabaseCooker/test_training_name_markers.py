"""Verify name markers break Bigram adjacency in both training passes."""
from collections import Counter
import importlib.util
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import unittest


COOKER = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("training_finalizer", COOKER / "finalize-smart-mandarin-model.py")
finalizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(finalizer)

WORDS = "甲乙丙丁王小明"
PREFIX_SUFFIX = {("", "甲"), ("甲", "乙"), ("丙", "丁"), ("丁", "")}
UNMARKED = PREFIX_SUFFIX | {("乙", "丙")}
PUNCTUATED = PREFIX_SUFFIX | {("乙", ""), ("", "丙")}
BRACKETED = PUNCTUATED | {("", "王"), ("王", "小"), ("小", "明"), ("明", "")}
CASES = (
    ("甲乙〖王小明〗丙丁", PREFIX_SUFFIX),
    ("甲乙⟦王小明⟧丙丁", PREFIX_SUFFIX),
    ("甲 乙 〖王小明〗 ⟦王小明⟧ 丙 丁", PREFIX_SUFFIX),
    ("甲乙。〖王小明〗，丙丁", PUNCTUATED),
    ("甲乙丙丁", UNMARKED),
    ("甲乙［王小明］丙丁", BRACKETED),
    ("甲乙【王小明】丙丁", BRACKETED),
    ("〖王小明〗甲⟦王小明⟧乙〖王小明〗", set()),
)
MALFORMED = (
    "甲⟦王小明", "王小明⟧乙", "甲⟦⟧乙", "甲⟦　⟧乙", "甲⟦王⟦小明⟧⟧乙",
    "甲〖王小明", "王小明〗乙", "甲〖〗乙", "甲〖　〗乙", "甲〖王〖小明〗〗乙",
    "甲〖王小明⟧乙", "甲⟦王小明〗乙", "甲〖王⟦小明⟧〗乙", "甲⟦王〖小明〗⟧乙",
)


class NameMarkerTests(unittest.TestCase):
    def test_document_frequency_counts_only_pairs_outside_name(self):
        probabilities = dict.fromkeys(WORDS, -1.0)
        for text, expected in CASES:
            with self.subTest(text=text):
                articles = [{"text": f"{text}\n{text}"}, {"text": text}]
                self.assertEqual(finalizer.article_document_frequency(articles, probabilities),
                                 Counter({pair: 2 for pair in expected}))

    def test_document_frequency_rejects_malformed_markers_with_location(self):
        for text in MALFORMED:
            with self.subTest(text=text), self.assertRaisesRegex(
                ValueError, "tw-typing-00001:2: malformed personal-name marker"
            ):
                finalizer.article_document_frequency(
                    [{"prompt_id": "tw-typing-00001", "text": f"甲\n{text}"}], {}
                )

    @unittest.skipUnless(shutil.which("ruby"), "Ruby is required")
    def test_ruby_cooker_counts_only_pairs_outside_name(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            counts, mapping, cin, corpus = [root / name for name in ("counts", "mapping", "cin", "corpus")]
            counts.write_text("".join(f"{word} 10\n" for word in WORDS), encoding="utf-8")
            mapping.touch()
            cin.write_text("%chardef begin\n" + "".join(f"q{index} {word}\n"
                           for index, word in enumerate(WORDS)) + "%chardef end\n", encoding="utf-8")
            command = ["ruby", str(COOKER / "SmartMandarinCooker.rb"), str(counts), str(mapping), str(cin),
                       "--no-cin-reading-frequencies", str(corpus)]

            for text, expected in CASES:
                with self.subTest(text=text):
                    corpus.write_text(text + "\n", encoding="utf-8")
                    process = subprocess.run(command, capture_output=True, text=True, encoding="utf-8")
                    self.assertEqual(process.returncode, 0, process.stderr)
                    with sqlite3.connect(":memory:") as database:
                        database.executescript(
                            "CREATE TABLE unigrams(qstring,current,probability,backoff);"
                            "CREATE TABLE bigrams(qstring,previous,current,probability);"
                        )
                        database.executescript(process.stdout)
                        self.assertEqual(set(database.execute("SELECT previous,current FROM bigrams")), expected)
                    database.close()

            for text in MALFORMED:
                with self.subTest(text=text):
                    corpus.write_text(f"甲\n{text}\n", encoding="utf-8")
                    process = subprocess.run(command, capture_output=True, text=True, encoding="utf-8")
                    self.assertNotEqual(process.returncode, 0)
                    self.assertIn(f"{corpus}:2: malformed personal-name marker", process.stderr)
                    self.assertEqual(process.stdout, "")
