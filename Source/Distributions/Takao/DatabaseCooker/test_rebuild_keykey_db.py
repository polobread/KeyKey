import importlib.util
import json
from pathlib import Path
import sqlite3
import unittest
import tempfile
from unittest.mock import patch

from phrase_unigram_supplement import query_for_reading

spec = importlib.util.spec_from_file_location("rebuild", Path(__file__).with_name("rebuild-keykey-db.py"))
rebuild = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rebuild)


class RebuildTests(unittest.TestCase):
    def publication_fixture(self, tree, *, engine="old-engine", evaluator="old-evaluator",
                            sort_keys=False, rejected=False):
        data = rebuild.DATA
        delta = 31 if rejected else 0
        comparison = {
            "identity": {"engine_sha256": engine, "evaluator_sha256": evaluator,
                         "policy": {"syllables": 10}, "frozen_inputs_sha256": "fixed-input"},
            "summaries": {"before": {"total_actions": 100},
                          "rebuilt": {"total_actions": 100 + delta,
                                      "tiers": {"basic100": {"by_character": {"你": 2, "我": 1}}}}},
            "comparisons": {"rebuilt": {"before": 100, "after": 100 + delta, "delta": delta,
                                        "articles": [{"id": "one", "delta": delta},
                                                     {"id": "two", "delta": 0}]}},
        }
        reports = {
            data / "collection-unigram-validation.json": comparison,
            data / "rebuild-review/comparison.json": comparison,
            data / "rebuild-review/latest.json": {
                "decision": "rejected" if rejected else "adopted",
                "candidate_sha256": "candidate", "inputs": {"phrases.tsv": "source-one"},
                "regression": comparison["comparisons"]["rebuilt"],
            },
            data / "collection-unigram-import.json": {"z": 0, "a": {"second": 2, "first": 1}},
            data / "custom-unigram-cooker-report.json": {"policy": "original", "counts": {"z": 0, "a": 1}},
        }
        for path, value in reports.items():
            (tree / path).parent.mkdir(parents=True, exist_ok=True)
            (tree / path).write_text(json.dumps(value, ensure_ascii=False, sort_keys=sort_keys))
        manifest = {"sources": {"collection_unigram_supplement": {}}, "rebuild": {}}
        for owner, key, filename in (
            (manifest["sources"]["collection_unigram_supplement"], "validation", "collection-unigram-validation.json"),
            (manifest["sources"]["collection_unigram_supplement"], "report", "collection-unigram-import.json"),
            (manifest["rebuild"], "cooker_report", "custom-unigram-cooker-report.json"),
        ):
            owner[key + "_file"] = filename
            owner[key + "_sha256"] = rebuild.file_sha256(tree / data / filename)
        manifest_path = data / "smart-mandarin-model-manifest.json"
        (tree / manifest_path).write_text(json.dumps(manifest, sort_keys=sort_keys))
        (tree / rebuild.DB).parent.mkdir(parents=True, exist_ok=True)
        (tree / rebuild.DB).write_bytes(b"same database")
        model_files = [str(rebuild.DB), str(manifest_path),
                       *(str(path) for path in reports if "rebuild-review" not in path.parts)]
        audit_files = [str(path) for path in reports if "rebuild-review" in path.parts]
        return model_files, audit_files

    def change_json(self, tree, relative, change):
        path = tree / relative
        value = json.loads(path.read_text())
        change(value)
        path.write_text(json.dumps(value, ensure_ascii=False))

    def test_order_and_execution_provenance_are_noop_with_linked_manifest_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            root, stage = Path(directory) / "repo", Path(directory) / "stage"
            model, audit = self.publication_fixture(root)
            self.publication_fixture(stage, engine="new-engine", evaluator="new-evaluator", sort_keys=True)
            before = {name: (root / name).read_bytes() for name in model + audit}
            decision = rebuild.publication_decision({"delta": 0})
            plan = rebuild.publication_plan(stage, root, model, audit, decision)
            self.assertFalse(plan["publication_needed"])
            self.assertEqual(plan["files"], [])
            self.assertEqual(plan["substantive_files"], [])
            self.assertRegex(plan["publication_fingerprint"], r"^[a-f0-9]{64}$")
            self.assertEqual(rebuild.publish_files(stage, root, model, audit, decision, apply=True), [])
            self.assertEqual(before, {name: (root / name).read_bytes() for name in model + audit})
            self.publication_fixture(stage, engine="third-engine", evaluator="third-evaluator")
            self.assertEqual(rebuild.publication_plan(stage, root, model, audit, decision)["publication_fingerprint"],
                             plan["publication_fingerprint"])

    def test_database_change_is_published_even_when_total_delta_is_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            root, stage = Path(directory) / "repo", Path(directory) / "stage"
            model, audit = self.publication_fixture(root)
            self.publication_fixture(stage)
            decision = rebuild.publication_decision({"delta": 0})
            previous = rebuild.publication_plan(stage, root, model, audit, decision)
            (stage / rebuild.DB).write_bytes(b"a genuinely different model")
            plan = rebuild.publication_plan(stage, root, model, audit, decision)
            self.assertTrue(plan["publication_needed"])
            self.assertIn(str(rebuild.DB), plan["substantive_files"])
            self.assertEqual(plan["files"], sorted(model + audit))
            self.assertNotEqual(plan["publication_fingerprint"], previous["publication_fingerprint"])

    def test_offsetting_article_or_character_changes_still_require_review(self):
        for field in ("articles", "characters", "policy", "baseline"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                root, stage = Path(directory) / "repo", Path(directory) / "stage"
                model, audit = self.publication_fixture(root)
                self.publication_fixture(stage)
                def change(value):
                    if field == "articles":
                        value["comparisons"]["rebuilt"]["articles"] = [
                            {"id": "one", "delta": 1}, {"id": "two", "delta": -1}]
                    elif field == "characters":
                        value["summaries"]["rebuilt"]["tiers"]["basic100"]["by_character"] = {"你": 1, "我": 2}
                    elif field == "policy":
                        value["identity"]["policy"]["syllables"] = 11
                    else:
                        value["comparisons"]["rebuilt"]["before"] = 101
                self.change_json(stage, rebuild.DATA / "rebuild-review/comparison.json", change)
                plan = rebuild.publication_plan(stage, root, model, audit, rebuild.publication_decision({"delta": 0}))
                self.assertTrue(plan["publication_needed"])

    def test_new_source_evidence_is_substantive_when_model_and_actions_match(self):
        with tempfile.TemporaryDirectory() as directory:
            root, stage = Path(directory) / "repo", Path(directory) / "stage"
            model, audit = self.publication_fixture(root)
            self.publication_fixture(stage)
            self.change_json(stage, rebuild.DATA / "rebuild-review/latest.json",
                             lambda value: value["inputs"].update({"phrases.tsv": "new-source"}))
            plan = rebuild.publication_plan(stage, root, model, audit, rebuild.publication_decision({"delta": 0}))
            self.assertTrue(plan["publication_needed"])
            self.assertEqual(plan["substantive_files"], [str(rebuild.DATA / "rebuild-review/latest.json")])

    def test_identical_rejection_is_noop_and_new_rejection_only_publishes_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            root, stage = Path(directory) / "repo", Path(directory) / "stage"
            model, audit = self.publication_fixture(root, rejected=True)
            self.publication_fixture(stage, rejected=True, engine="new-engine", sort_keys=True)
            decision = rebuild.publication_decision({"delta": 31})
            self.assertFalse(rebuild.publication_plan(stage, root, model, audit, decision)["publication_needed"])
            self.change_json(stage, rebuild.DATA / "rebuild-review/latest.json",
                             lambda value: value.update({"reason": "a new rejected source"}))
            (stage / rebuild.DB).write_bytes(b"rejected candidate")
            files = rebuild.publish_files(stage, root, model, audit, decision, apply=True)
            self.assertEqual(files, sorted(audit))
            self.assertEqual((root / rebuild.DB).read_bytes(), b"same database")

    def test_manifest_normalization_never_hides_an_invalid_hash_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            root, stage = Path(directory) / "repo", Path(directory) / "stage"
            model, audit = self.publication_fixture(root)
            self.publication_fixture(stage)
            self.change_json(stage, rebuild.DATA / "smart-mandarin-model-manifest.json",
                             lambda value: value["sources"]["collection_unigram_supplement"].update(
                                 {"validation_sha256": "0" * 64}))
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                rebuild.publication_plan(stage, root, model, audit, rebuild.publication_decision({"delta": 0}))

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

    def test_rebuild_uses_filtered_score_and_keeps_full_score_diagnostic(self):
        for filtered, full, expected in ((30, 31, "adopted"), (31, 0, "rejected")):
            with self.subTest(filtered=filtered, full=full), tempfile.TemporaryDirectory() as directory:
                output = Path(directory)
                evidence = {"comparisons": {"rebuilt": {
                    "delta": filtered, "passes": False, "unfiltered": {"delta": full},
                }}}
                (output / "comparison.json").write_text(json.dumps(evidence))
                with patch.object(rebuild.subprocess, "run") as run:
                    comparison, delta, decision = rebuild.evaluate_rebuild(
                        Path("checked-in.db"), Path("candidate.db"), Path("reference.db"), output, 8, 30)
                command = run.call_args.args[0]
                self.assertTrue(run.call_args.kwargs["check"])
                self.assertIn("before=checked-in.db", command)
                self.assertIn("rebuilt=candidate.db", command)
                self.assertIn("--exclude-person-names", command)
                self.assertEqual(command[command.index("--exclude-characters") + 1], "她他時十")
                self.assertEqual(decision["decision"], expected)
                self.assertEqual(decision["delta_actions"], filtered)
                self.assertEqual(delta["passes"], expected == "adopted")
                self.assertEqual(delta["unfiltered"], {"delta": full})
                self.assertIs(delta, comparison["comparisons"]["rebuilt"])

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

    def test_android_model_upgrade_changes_cache_and_hash_and_preserves_previous_cache(self):
        old_hash, new_hash = "1" * 64, "2" * 64
        old_name = f"KeyKey-smart-{old_hash[:16]}.db"
        source = (f'static final String INSTALLED_NAME = "{old_name}";\n'
                  'private static final String[] PREVIOUS_INSTALLED_NAMES = {\n'
                  '    "older.db"\n};\n'
                  f'private static final String EXPECTED_SHA256 =\n    "{old_hash}";\n')
        updated = rebuild.android_model_metadata(source, new_hash)
        self.assertIn(f'INSTALLED_NAME = "KeyKey-smart-{new_hash[:16]}.db"', updated)
        self.assertIn(f'EXPECTED_SHA256 =\n    "{new_hash}"', updated)
        self.assertIn(f'PREVIOUS_INSTALLED_NAMES = {{\n            "{old_name}",', updated)
        self.assertIn('"older.db"', updated)
        self.assertNotIn(new_hash, source)
        self.assertEqual(rebuild.android_model_metadata(updated, new_hash), updated)

    def test_android_model_rollback_does_not_clean_up_the_selected_cache(self):
        current_hash, previous_hash = "1" * 64, "2" * 64
        current_name = f"KeyKey-smart-{current_hash[:16]}.db"
        previous_name = f"KeyKey-smart-{previous_hash[:16]}.db"
        source = (f'static final String INSTALLED_NAME = "{current_name}";\n'
                  'private static final String[] PREVIOUS_INSTALLED_NAMES = {\n'
                  f'    "{previous_name}", "old.db", "old.db"\n}};\n'
                  f'private static final String EXPECTED_SHA256 = "{current_hash}";\n')
        updated = rebuild.android_model_metadata(source, previous_hash)
        self.assertEqual(updated.count(f'"{previous_name}"'), 1)
        self.assertEqual(updated.count('"old.db"'), 1)
        self.assertIn(f'PREVIOUS_INSTALLED_NAMES = {{\n            "{current_name}",', updated)

    def test_android_model_metadata_rejects_incomplete_or_ambiguous_installer(self):
        source = ('static final String INSTALLED_NAME = "old.db";\n'
                  'private static final String[] PREVIOUS_INSTALLED_NAMES = {};\n'
                  f'private static final String EXPECTED_SHA256 = "{"1" * 64}";\n')
        for broken in (source.replace("EXPECTED_SHA256", "OLD_HASH"),
                       source.replace("PREVIOUS_INSTALLED_NAMES", "OLD_NAMES"),
                       source + 'static final String INSTALLED_NAME = "duplicate.db";'):
            with self.subTest(source=broken), self.assertRaises(ValueError):
                rebuild.android_model_metadata(broken, "2" * 64)
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            rebuild.android_model_metadata(source, "not a hash")

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
