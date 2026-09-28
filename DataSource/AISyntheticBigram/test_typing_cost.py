"""Regression tests run against the real C++ composer, with controlled models."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import typing_cost as t

spec = importlib.util.spec_from_file_location("repair_typing_bigram", t.ROOT / "repair-typing-bigram.py")
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)


class TypingCostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        t.build_engine()

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.work = Path(self.directory.name)
        self.db = self.work / "base.db"
        self.yi, self.bing = t.query_for_reading("ㄧˇ"), t.query_for_reading("ㄅㄧㄥˇ")
        with t.writable_db(self.db) as db:
            db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff);"
                             "CREATE TABLE bigrams(qstring,previous,current,probability);"
                             "CREATE INDEX u ON unigrams(qstring); CREATE INDEX b ON bigrams(qstring);")
            db.executemany("INSERT INTO unigrams VALUES(?,?,?,?)",
                           [("!", "", 0, 0), ("$", "", 0, 0), ("*", "", -99, 0),
                            (self.yi, "以", -1, 0), (self.yi, "乙", -2, 0), (self.bing, "丙", -1, 0)])

    def document(self, text):
        path = self.work / "input.txt"
        path.write_text(text, encoding="utf-8")
        return t.load_document(path, t.Lexicon(self.db))

    def score(self, text, policy=t.Policy()):
        return t.evaluate(self.document(text), self.db, policy)

    def test_curated_taiwan_typing_reading_overrides_statistical_segmentation(self):
        token = t.Lexicon(t.DEFAULT_DB).segment("囉嗦")[0]
        self.assertEqual([t.reading(token["query"][i:i + 2]) for i in range(0, 4, 2)],
                         ["ㄌㄨㄛ", "ㄙㄨㄛ"])

    def test_keys_and_tail_correction(self):
        report = self.score("乙！A\n")
        self.assertEqual(report["actions"]["phonetic_keys"], 2)
        self.assertEqual(report["actions"]["literal_keys"], 3)
        self.assertEqual(report["actions"]["commit_keys"], 1)
        self.assertEqual(report["corrections"], 1)
        self.assertEqual(report["total_actions"], 8)
        self.assertEqual(report["correction_actions"], 2)
        self.assertEqual(report["correction_summary"], [{
            "changes": [{"from": "以", "to": "乙"}], "events": 1, "actions": 2,
        }])
        self.assertEqual(report["character_correction_summary"], [{
            "character": "乙", "changes": 1, "events": 1,
            "sources": [{"from": "以", "changes": 1}],
        }])
        self.assertEqual(report["errors"][0]["changes"], [{"index": 0, "from": "以", "to": "乙"}])

    def test_character_summary_counts_each_character_but_not_actions_twice(self):
        errors = [{
            "action_count": 2,
            "changes": [
                {"index": 0, "from": "以", "to": "乙"},
                {"index": 1, "from": "以", "to": "乙"},
                {"index": 2, "from": "兵", "to": "丙"},
            ],
        }]
        actions, events, characters = t.summarize_corrections(errors)
        self.assertEqual(actions, 2)
        self.assertEqual(events[0]["actions"], 2)
        self.assertEqual(characters, [
            {"character": "乙", "changes": 2, "events": 1,
             "sources": [{"from": "以", "changes": 2}]},
            {"character": "丙", "changes": 1, "events": 1,
             "sources": [{"from": "兵", "changes": 1}]},
        ])

    def test_page_boundaries(self):
        with t.writable_db(self.db) as db:
            db.execute("UPDATE unigrams SET probability=-30 WHERE current='乙'")
            db.executemany("INSERT INTO unigrams VALUES(?,?,?,0)", [(self.yi, word, -2 - i) for i, word in enumerate("已椅倚矣蟻苡迤")])
        report = self.score("乙")
        self.assertEqual(report["errors"][0]["candidate_rank"], 9)
        self.assertEqual(report["actions"]["page_turns"], 1)
        self.assertEqual(report["correction_actions"], 3)
        self.assertEqual(self.score("乙", t.Policy(page_size=4))["actions"]["page_turns"], 2)

    def test_delay_allows_phrase_to_resolve_without_future_leakage(self):
        with t.writable_db(self.db) as db:
            db.execute("INSERT INTO unigrams VALUES(?,?,?,0)", (self.yi + self.bing, "乙丙", -0.5))
        self.assertEqual(self.score("乙丙", t.Policy(settle=2))["corrections"], 0)
        self.assertEqual(self.score("乙丙", t.Policy(settle=1))["corrections"], 1)

    def test_correct_after_five_syllables_and_count_end_key(self):
        report = self.score("乙丙丙丙丙丙", t.Policy(interaction="keyboard"))
        error = report["errors"][0]
        self.assertEqual(error["entered"], 5)
        self.assertEqual(error["actions"]["cursor_keys"], 5)
        self.assertEqual(error["actions"]["candidate_open_keys"], 1)
        self.assertEqual(error["actions"]["resume_keys"], 1)

    def test_phrase_candidates_keep_real_rank_and_span(self):
        with t.writable_db(self.db) as db:
            db.executemany("INSERT INTO unigrams VALUES(?,?,?,0)",
                           [(self.yi + self.bing, "以丙", -0.1), (self.yi + self.bing, "乙丙", -0.2)])
        report = self.score("乙丙")
        self.assertEqual(report["corrections"], 1)
        self.assertEqual(report["errors"][0]["candidate"]["length"], 2)
        self.assertEqual(report["errors"][0]["candidate_rank"], 2)

    def test_long_composition_shift_and_no_cross_run_learning(self):
        first = self.score("乙" * 25)
        second = self.score("乙" * 25)
        self.assertEqual(first, second)
        self.assertEqual(first["corrections"], 25)
        self.assertEqual(first["total_actions"], 101)

    def test_a_b_a_isolation_and_no_database_writes(self):
        before = t.sha256(self.db)
        first = self.score("以")
        self.score("乙" * 20)
        self.assertEqual(first, self.score("以"))
        self.assertEqual(t.sha256(self.db), before)
        # Within a test, punctuation also discards the previous selection.
        self.assertEqual(self.score("乙，以")["corrections"], 1)

    def test_overlapping_corrections_do_not_cycle(self):
        qmen = t.query_for_reading("ㄇㄣˊ")
        with t.writable_db(self.db) as db:
            db.executemany("INSERT INTO unigrams VALUES(?,?,?,0)",
                           [(qmen, "們", -1), (qmen, "門", -2),
                            (self.yi + self.bing, "乙丙", -4),
                            (self.bing + qmen, "丙門", -0.5)])
        report = self.score("乙丙門")
        self.assertEqual(report["corrections"], 2)
        self.assertEqual([e["candidate"]["text"] for e in report["errors"]], ["乙丙", "門"])

    def test_late_change_is_rechecked(self):
        # 乙 was correct at the five-syllable checkpoint; a six-syllable
        # homophone phrase changes it later, which must incur a correction.
        with t.writable_db(self.db) as db:
            db.execute("UPDATE unigrams SET probability=-0.5 WHERE current='乙'")
            db.execute("INSERT INTO unigrams VALUES(?,?,?,0)", (self.yi + self.bing * 5, "以丙丙丙丙丙", -0.1))
        report = self.score("乙丙丙丙丙丙")
        self.assertEqual(report["corrections"], 1)
        self.assertEqual(report["errors"][0]["entered"], 6)

    def test_version_manifest_hash_and_source_errors(self):
        manifest = self.work / "version.json"
        t.write_json(manifest, {"database": "base.db", "database_sha256": t.sha256(self.db)})
        self.assertEqual(t.resolve_version(str(manifest)), self.db.resolve())
        t.write_json(manifest, {"database": "base.db", "database_sha256": "bad"})
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            t.resolve_version(str(manifest))
        with self.assertRaises(ValueError):
            t.resolve_version("does-not-exist")

    def test_punctuation_resets_composition_and_unknown_han_fails(self):
        self.assertEqual(self.score("乙，乙")["corrections"], 2)
        with self.assertRaises(ValueError):
            self.score("𠮷")
        with self.assertRaises(ValueError):
            self.score("")

    def test_explicit_reading_validation(self):
        path = self.work / "input.jsonl"
        path.write_text(json.dumps({"text": "乙丙", "readings": ["ㄧˇ"]}), encoding="utf-8")
        with self.assertRaises(ValueError):
            t.load_document(path, t.Lexicon(self.db))
        for invalid in ("ㄧㄧ", "ˇ", "", "ㄅa"):
            with self.assertRaises(ValueError):
                t.query_for_reading(invalid)
        for value in ("ㄧˇ", "ㄓ", "ㄨㄛˇ", "ㄩㄢˊ", "ㄉㄜ˙"):
            self.assertEqual(t.reading(t.query_for_reading(value)), value)

    def test_no_candidate_is_an_error_instead_of_free_success(self):
        document = self.document("乙")
        with t.writable_db(self.db) as db:
            db.execute("DELETE FROM unigrams WHERE current='乙'")
        with self.assertRaisesRegex(ValueError, "No selectable"):
            t.evaluate(document, self.db, t.Policy())

    def test_bundled_cin_fallback_is_counted_without_changing_unigrams(self):
        tai = t.query_for_reading("ㄊㄞˊ")
        with t.writable_db(self.db) as db:
            db.execute('CREATE TABLE "Mandarin-bpmf-cin"(key,value)')
            db.executemany('INSERT INTO "Mandarin-bpmf-cin" VALUES(?,?)', [(tai, "台"), (tai, "臺")])
        before = t.sha256(self.db)
        report = self.score("臺")
        self.assertEqual(report["syllables"], 1)
        self.assertEqual(report["corrections"], 1)
        self.assertEqual(report["errors"][0]["candidate_rank"], 2)
        self.assertEqual(t.sha256(self.db), before)

    def test_repair_improves_replays_and_preserves_source(self):
        before = t.sha256(self.db)
        output = self.work / "fixed.db"
        result = repair.tune(self.document("乙"), [], self.db, output, t.Lexicon(self.db), t.Policy(), 10, 2)
        self.assertTrue(result["improved"])
        self.assertEqual(result["before"]["total_actions"], 5)
        self.assertEqual(result["after"]["total_actions"], 3)
        self.assertEqual(t.sha256(self.db), before)
        patch = self.work / "patch.sql"
        repair.write_patch(patch, result["accepted"], before)
        replay = self.work / "replay.db"
        with t.connect(self.db) as source, t.writable_db(replay) as target:
            source.backup(target)
            target.executescript(patch.read_text())
            target.executescript(patch.read_text())  # idempotent
            self.assertEqual(target.execute("SELECT count(*) FROM bigrams").fetchone()[0], 1)
        self.assertEqual(t.evaluate(self.document("乙"), replay, t.Policy())["total_actions"], 3)

    def test_validation_regression_rejects_and_rolls_back(self):
        output = self.work / "fixed.db"
        result = repair.tune(self.document("乙"), [self.document("以")], self.db, output,
                             t.Lexicon(self.db), t.Policy(), 10, 2)
        self.assertFalse(result["improved"])
        self.assertEqual(result["before"], result["after"])
        self.assertEqual(result["guard_before"], result["guard_after"])
        with t.connect(output) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM bigrams").fetchone()[0], 0)

    def test_cli_prints_total_and_corrected_characters_and_rejects_invalid_options(self):
        article = self.work / "article.txt"
        article.write_text("乙", encoding="utf-8")
        command = [sys.executable, str(t.ROOT / "measure-typing-cost.py"), str(article), str(self.db), "--reference-db", str(self.db)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "5\n額外修正動作數: 2\n以→乙: 1 次修正，2 個動作\n"
                                        "逐字修正次數:\n乙: 1 字次（以→乙 1 次；涉及 1 次選字）\n")
        article.write_text("以", encoding="utf-8")
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "3\n額外修正動作數: 0\n額外修正: 無\n")
        result = subprocess.run(command + ["--settle", "0"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
