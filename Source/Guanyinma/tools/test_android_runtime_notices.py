import io
import json
import unittest
import zipfile
from android_runtime_notices import vendor_notices
from mobile_runtime_notices import Catalog


class AndroidNoticeTests(unittest.TestCase):
    def test_vendor_offsets_are_bytes_and_keep_unicode_copyright(self):
        prefix = "前綴\n".encode()
        body = "Copyright © 著作權人\nComplete license conditions."
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            archive.writestr("third_party_licenses.txt", prefix + body.encode())
            archive.writestr("third_party_licenses.json", json.dumps({"component": {"start": len(prefix), "length": len(body.encode())}}))
        with zipfile.ZipFile(data) as archive:
            self.assertEqual(vendor_notices(archive), {"component": body})

    def test_truncated_vendor_license_is_rejected(self):
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            archive.writestr("third_party_licenses.txt", "short")
            archive.writestr("third_party_licenses.json", json.dumps({"component": {"start": 1, "length": 100}}))
        with zipfile.ZipFile(data) as archive:
            with self.assertRaises(RuntimeError):
                vendor_notices(archive)

    def test_apache_terms_and_large_notices_share_without_losing_owners_or_exceptions(self):
        catalog = Catalog(include_equal_rules=True)
        terms = "Apache License\nVersion 2.0, January 2004\nFull original conditions.\nEND OF TERMS AND CONDITIONS"
        common = "Required shared upstream notice. " * 40
        for owner in ["Alice", "Bob"]:
            catalog.component(owner, owner, "Apache-2.0", [(owner, "Copyright " + owner + "\n" + terms),
                              ("upstream", common + "\n" + terms + "\nLLVM exception must remain.")], owner)
        shared = set(catalog.components[0]["licenseIDs"]) & set(catalog.components[1]["licenseIDs"])
        self.assertTrue(any(catalog.licenses[k]["text"] == terms for k in shared))
        self.assertTrue(any(catalog.licenses[k]["text"] == common.strip() for k in shared))
        for component, owner in zip(catalog.components, ["Alice", "Bob"]):
            text = component["attribution"] + "\n" + "\n".join(catalog.licenses[k]["text"] for k in component["licenseIDs"])
            self.assertIn("Copyright " + owner, text)
            self.assertIn("LLVM exception must remain.", text)
            self.assertIn(terms, text)


if __name__ == "__main__":
    unittest.main()
