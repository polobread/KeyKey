"""Exercise real Ruby cooking on isolated fixtures; never cook the shared DB."""
import csv
import importlib.util
import json
import math
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from collections import Counter
from contextlib import closing
from unittest.mock import patch

from cin_reading_frequencies import load, verify_unigrams
from phrase_unigram_supplement import query_for_reading

COOKER = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("cin_test_finalizer", COOKER / "finalize-smart-mandarin-model.py")
finalizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(finalizer)


@unittest.skipUnless(shutil.which("ruby"), "Ruby is required")
class CinCookerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.hu, self.xu, self.hu1 = map(query_for_reading, ("ㄏㄨˇ", "ㄒㄩˇ", "ㄏㄨ"))
        self.counts, self.mapping, self.cin, self.corpus = [self.root / name for name in ("phrase.occ", "mapping.txt", "absolute.cin", "corpus.txt")]
        self.counts.write_text("虎 1227\n琥 33\n滸 29\n唬 74\n許 13105\n", encoding="utf-8")
        self.mapping.write_text("", encoding="utf-8")
        self.cin.write_text("%chardef begin\n" +
            "".join(f"{self.hu} {w}\n" for w in "虎琥滸唬許") +
            f"{self.xu} 許\n{self.hu1} 虎\n%chardef end\n", encoding="utf-8")
        self.corpus.write_text("許\n虎\n許 虎\n虎 許\n", encoding="utf-8")
        self.table = self.root / "frequencies.tsv"
        self.entries = [
            {"character": "許", "reading": "ㄏㄨˇ", "qstring": self.hu, "cin_rank": "5", "source_count": "13105", "target_count": "26.1"},
            {"character": "許", "reading": "ㄒㄩˇ", "qstring": self.xu, "cin_rank": "1", "source_count": "13105", "target_count": "13105"},
            {"character": "虎", "reading": "ㄏㄨˇ", "qstring": self.hu, "cin_rank": "1", "source_count": "1227", "target_count": "1227"},
        ]
        self.write_table(self.entries)

    def write_table(self, entries):
        with self.table.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=self.entries[0].keys(), delimiter="\t", lineterminator="\n")
            writer.writeheader()
            writer.writerows(entries)

    def run_cooker(self, source=None, extra=None, name="model", check=True):
        report = self.root / (name + ".json")
        options = extra if extra is not None else ["--cin-reading-frequencies", str(self.table)]
        process = subprocess.run(
            ["ruby", "-E", "UTF-8", str(source or COOKER / "SmartMandarinCooker.rb"),
             str(self.counts), str(self.mapping), str(self.cin), *options, "--report", str(report), str(self.corpus)],
            capture_output=True, text=True, encoding="utf-8")
        if not check:
            return process
        self.assertEqual(process.returncode, 0, process.stderr)
        database = self.root / (name + ".db")
        with closing(sqlite3.connect(database)) as db:
            db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff);"
                             "CREATE TABLE bigrams(qstring,previous,current,probability);")
            db.executescript(process.stdout)
        return database, json.loads(report.read_text(encoding="utf-8"))

    def test_enabled_counts_change_unigrams_and_every_incoming_reading_bigram(self):
        old, before = self.run_cooker(extra=["--no-cin-reading-frequencies"], name="old")
        new, after = self.run_cooker()
        self.assertNotIn("cin_reading_frequencies", before)
        self.assertEqual(after["cin_reading_frequencies"]["entries"], 3)
        self.assertEqual(before["unigram_total_count"], after["unigram_total_count"])
        total = after["unigram_total_count"]
        with closing(sqlite3.connect(old)) as a, closing(sqlite3.connect(new)) as b:
            verify_unigrams(b, load(self.table), total)
            for q, target in [(self.hu, 26.1), (self.xu, 13105)]:
                expected_delta = math.log10(target / (13105 / 2))
                edges = a.execute(
                    "SELECT qstring,previous,current,probability FROM bigrams WHERE current='許'").fetchall()
                for query, previous, current, old_score in edges:
                    if query.split(" ")[1] != q:
                        continue
                    new_score = b.execute("SELECT probability FROM bigrams WHERE qstring=? AND previous=? AND current=?",
                                         (query, previous, current)).fetchone()[0]
                    self.assertAlmostEqual(new_score - old_score, expected_delta, places=12)
            # No redistribution to an unlisted sibling reading.
            self.assertEqual(a.execute("SELECT * FROM unigrams WHERE qstring=?", (self.hu1,)).fetchall(),
                             b.execute("SELECT * FROM unigrams WHERE qstring=?", (self.hu1,)).fetchall())
            for q in (self.hu, self.xu):
                self.assertEqual(a.execute("SELECT * FROM bigrams WHERE qstring=?", (q + " $",)).fetchall(),
                                 b.execute("SELECT * FROM bigrams WHERE qstring=?", (q + " $",)).fetchall())

    def test_default_is_enabled_and_explicit_disable_uses_old_estimator(self):
        # Reproduce the relative source layout without touching repository data.
        script = self.root / "repo/Source/Distributions/Takao/DatabaseCooker/SmartMandarinCooker.rb"
        script.parent.mkdir(parents=True)
        script.write_bytes((COOKER / "SmartMandarinCooker.rb").read_bytes())
        table = self.root / "repo/DataSource/CINReadingFrequency/cin-character-reading-frequencies.tsv"
        table.parent.mkdir(parents=True)
        table.write_bytes(self.table.read_bytes())
        database, report = self.run_cooker(source=script, extra=[], name="default")
        with closing(sqlite3.connect(database)) as db:
            verify_unigrams(db, load(self.table), report["unigram_total_count"])
        _, disabled = self.run_cooker(source=script, extra=["--no-cin-reading-frequencies"], name="disabled")
        self.assertNotIn("cin_reading_frequencies", disabled)

    def test_bad_source_counts_ranks_duplicates_and_nonfinite_weights_fail_before_sql(self):
        for field, value in [("source_count", "13104"), ("cin_rank", "4"), ("qstring", self.xu),
                             ("reading", "ㄏㄏㄨˇ"), ("target_count", "0"), ("target_count", "NaN"),
                             ("target_count", "Infinity"), ("target_count", "20000")]:
            with self.subTest(field=field, value=value):
                entries = [dict(row) for row in self.entries]
                entries[0][field] = value
                self.write_table(entries)
                result = self.run_cooker(check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
        self.write_table(self.entries + [self.entries[0]])
        self.assertNotEqual(self.run_cooker(check=False).returncode, 0)

    def test_finalizer_preserves_optional_counts_with_and_without_protected_queries(self):
        for protected in ("他", "虎"):
            with self.subTest(protected=protected):
                model, report = self.run_cooker(name="final-" + protected)
                with closing(sqlite3.connect(model)) as db:
                    raw = dict(db.execute("SELECT qstring,probability FROM bigrams WHERE previous='' AND current='許'"))
                manifest = self.root / "manifest.json"
                manifest.write_text(json.dumps({"format": 1, "unigram_total_count": report["unigram_total_count"], "sources": {}}))
                protected_path = self.root / "protected.txt"
                protected_path.write_text(protected, encoding="utf-8")
                paths = tuple(self.root / f"v{i}.jsonl" for i in (2, 3, 4))
                for path in paths:
                    path.write_text("{}\n")
                frequencies = Counter({("", "許"): 4, ("", "虎"): 1, ("許", "虎"): 1,
                                       ("虎", "許"): 1, ("許", ""): 1, ("虎", ""): 1})
                with patch.object(finalizer, "load_training", return_value=([{"text": "許 虎"}], [])), \
                     patch.object(finalizer, "load_supplement", return_value=[]), \
                     patch.object(finalizer, "load_search_trend", return_value=[]), \
                     patch.object(finalizer, "article_document_frequency", return_value=frequencies):
                    finalizer.finalize(model, paths, protected_path, self.table, self.table,
                                       self.counts, manifest, cin_reading_frequencies=self.table)
                with closing(sqlite3.connect(model)) as db:
                    verify_unigrams(db, load(self.table), report["unigram_total_count"])
                    actual = db.execute("SELECT probability FROM bigrams WHERE qstring=? AND previous='' AND current='許'",
                                        ("! " + self.hu,)).fetchone()[0]
                    if protected == "虎":
                        self.assertEqual(actual, raw["! " + self.hu])
                    else:
                        background = 26.1 / report["unigram_total_count"]
                        observation = 3 * 26.1 / (13105 + 26.1)
                        self.assertAlmostEqual(actual, math.log10((observation + 1000 * background) / 1004), places=12)


class CinSourceValidationTests(unittest.TestCase):
    def test_current_table_loads_and_verifier_rejects_a_changed_unigram(self):
        from cin_reading_frequencies import DEFAULT_SOURCE
        entries = load(DEFAULT_SOURCE)
        self.assertEqual(len(entries), 3863)
        with closing(sqlite3.connect(":memory:")) as db:
            db.execute("CREATE TABLE unigrams(qstring,current,probability)")
            db.executemany("INSERT INTO unigrams VALUES(?,?,?)",
                           [(r["qstring"], r["character"], math.log10(r["target_count"]/1000000)) for r in entries])
            verify_unigrams(db, entries, 1000000)
            db.execute("UPDATE unigrams SET probability=0 WHERE current='許'")
            with self.assertRaises(ValueError):
                verify_unigrams(db, entries, 1000000)



class CinPipelineTests(unittest.TestCase):

    def test_verifier_keeps_old_first_choice_rule_only_when_source_is_disabled(self):
        import io
        from contextlib import redirect_stdout, redirect_stderr
        spec = importlib.util.spec_from_file_location("cin_test_verifier", COOKER / "verify-smart-mandarin-db.py")
        verifier = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(verifier)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model, manifest, table = root / "model.db", root / "manifest.json", root / "source.tsv"
            query = query_for_reading("ㄏㄢˋ")
            with closing(sqlite3.connect(model)) as db:
                db.executescript('CREATE TABLE unigrams(qstring,current,probability,backoff);'
                                 'CREATE TABLE bigrams(qstring,previous,current,probability);'
                                 'CREATE TABLE "Mandarin-bpmf-cin"(key,value);')
                db.executemany("INSERT INTO unigrams VALUES(?,?,?,0)", [(query, "和", -1), (query, "漢", -2)])
                db.executemany('INSERT INTO "Mandarin-bpmf-cin" VALUES(?,?)', [(query, "和"), (query, "漢")])
                db.commit()
            table.write_text("character\treading\tqstring\tcin_rank\tsource_count\ttarget_count\n"
                             f"和\tㄏㄢˋ\t{query}\t1\t38150\t38150\n", encoding="utf-8")
            for enabled, expected_status in [(False, 1), (True, 0)]:
                sources = {"cin_reading_frequencies": {"file": table.name}} if enabled else {}
                manifest.write_text(json.dumps({"format": 1, "sources": sources}))
                with patch.object(verifier, "MODEL_MANIFEST", manifest), \
                     patch.object(verifier, "EXPECTED_SINGLE_SYLLABLES", {query: ("ㄏㄢˋ", "漢")}), \
                     patch.object(verifier, "EXPECTED_SINGLE_SYLLABLE_READINGS", 1), \
                     patch.object(verifier, "verify_manifest", return_value={"rows": {"bigrams": 0}, "semantic_sha256": "fixture"}), \
                     patch.object(sys, "argv", ["verify", str(model)]), \
                     redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                    self.assertEqual(verifier.main(), expected_status)

    def test_python_cook_forwards_default_custom_and_disabled_source(self):
        import rebuild_model
        from cin_reading_frequencies import DEFAULT_SOURCE
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = root / "model.db"
            with closing(sqlite3.connect(model)) as db:
                db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff);"
                                 "CREATE TABLE bigrams(qstring,previous,current,probability);")
            def fake_run(command, stdout, check):
                stdout.write("BEGIN; COMMIT;")
                report = Path(command[command.index("--report") + 1])
                report.write_text(json.dumps({"unigram_total_count": 10}))
            for source in (DEFAULT_SOURCE, root / "custom.tsv", None):
                with self.subTest(source=source), patch.object(rebuild_model.subprocess, "run", side_effect=fake_run) as run:
                    rebuild_model.cook(model, root / "cin", root / "work", cin_reading_frequencies=source)
                    command = run.call_args.args[0]
                    if source is None:
                        self.assertIn("--no-cin-reading-frequencies", command)
                        self.assertNotIn("--cin-reading-frequencies", command)
                    else:
                        self.assertEqual(command[command.index("--cin-reading-frequencies") + 1], str(source))

    def test_manifest_checks_enabled_source_but_ignores_it_when_disabled(self):
        from smart_mandarin_model import verify_source_hashes, file_sha256
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = root / "DataSource/AISyntheticBigram"
            data.mkdir(parents=True)
            for name in ("base.txt", "search-trend-reading-overrides.tsv"):
                (data / name).write_text("base")
            digest = file_sha256(data / "base.txt")
            sources = {
                "training_articles": [],
                "protected_characters": {"file": "base.txt", "sha256": digest},
                "unigram_supplement": {"file": "base.txt", "sha256": digest},
                "search_trend_unigram": {
                    "source_file": "base.txt", "source_sha256": digest,
                    "file": "base.txt", "sha256": digest,
                    "review_file": "base.txt", "review_sha256": digest,
                    "reading_overrides_sha256": digest,
                },
            }
            optional = root / "DataSource/CINReadingFrequency/counts.tsv"
            optional.parent.mkdir()
            optional.write_text("original")
            sources["cin_reading_frequencies"] = {
                "file": "../CINReadingFrequency/counts.tsv",
                "sha256": file_sha256(optional), "entries": 1,
            }
            manifest = {"sources": sources}
            self.assertEqual(verify_source_hashes(manifest, data / "manifest.json"), {})
            optional.write_text("changed")
            with self.assertRaises(ValueError):
                verify_source_hashes(manifest, data / "manifest.json")
            del sources["cin_reading_frequencies"]
            self.assertEqual(verify_source_hashes(manifest, data / "manifest.json"), {})

if __name__ == "__main__":
    unittest.main()
