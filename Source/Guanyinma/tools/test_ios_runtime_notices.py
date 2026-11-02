"""Notice loss/incorrect dependency selection would affect shipped attribution."""
import unittest
from ios_runtime_notices import Catalog, runtime_packages

MIT = """Permission is hereby granted, free of charge, to any person obtaining a copy
of this software. THE SOFTWARE IS PROVIDED AS IS. DEALINGS IN THE SOFTWARE."""


class NoticeTests(unittest.TestCase):
    def test_deduplication_retains_both_copyrights_and_full_terms(self):
        catalog = Catalog()
        catalog.component("a", "A", "MIT", [("A/LICENSE", "Copyright Alice\n" + MIT)], "A")
        catalog.component("b", "B", "MIT", [("B/LICENSE", "Copyright Bob\n" + MIT.replace("\n", " "))], "B")
        self.assertEqual(len(catalog.licenses), 1)
        self.assertEqual(catalog.components[0]["licenseIDs"], catalog.components[1]["licenseIDs"])
        self.assertIn("Copyright Alice", catalog.components[0]["attribution"])
        self.assertIn("Copyright Bob", catalog.components[1]["attribution"])
        self.assertEqual(next(iter(catalog.licenses.values()))["text"], MIT)

    def test_compound_document_retains_scope_and_every_notice(self):
        catalog = Catalog()
        text = "First source, Copyright Alice\n" + MIT + "\nSecond source, Copyright Bob\n" + MIT
        catalog.component("compound", "Compound", "MIT", [("LICENSE", text)], "source")
        self.assertEqual(len(catalog.licenses), 1)
        self.assertIn("First source, Copyright Alice", catalog.components[0]["attribution"])
        self.assertIn("Second source, Copyright Bob", catalog.components[0]["attribution"])
        self.assertEqual(next(iter(catalog.licenses.values()))["text"], MIT)

    def test_build_test_and_proc_macro_dependencies_are_not_runtime(self):
        packages = [{"id": n, "name": n, "targets": [{"kind": ["proc-macro" if n == "derive" else "lib"]}]}
                    for n in ["root", "runtime", "build", "test", "derive", "macro-helper"]]
        def dep(name, kind=None):
            return {"pkg": name, "dep_kinds": [{"kind": kind}]}
        nodes = [{"id": p["id"], "deps": []} for p in packages]
        nodes[0]["deps"] = [dep("runtime"), dep("build", "build"), dep("test", "dev"), dep("derive")]
        nodes[4]["deps"] = [dep("macro-helper")]
        metadata = {"packages": packages, "resolve": {"root": "root", "nodes": nodes}}
        self.assertEqual(set(runtime_packages(metadata)), {"root", "runtime"})

    def test_unknown_notice_is_preserved_without_rewriting(self):
        catalog = Catalog()
        text = "Special source notice\nCopyright Holder\nAll bespoke conditions must remain."
        catalog.component("custom", "Custom", "custom", [("NOTICE", text)], "source")
        self.assertEqual(next(iter(catalog.licenses.values()))["text"], text)
        self.assertTrue(catalog.components[0]["sources"][0]["sha256"])


if __name__ == "__main__":
    unittest.main()
