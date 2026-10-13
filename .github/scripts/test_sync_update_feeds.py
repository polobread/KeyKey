import base64
from contextlib import nullcontext
import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("sync_feeds", Path(__file__).with_name("sync-update-feeds.py"))
mirror = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mirror)

RSS = b'<rss version="2.0"><channel><title>Test</title><link>https://example.invalid/release</link></channel></rss>'


class SyncFeedsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(RELEASE_MIRROR_BUCKET="example-downloads", RELEASE_MIRROR_DISTRIBUTION_ID="EDISTRIBUTION",
            RELEASE_MIRROR_BASE_URL="https://cdn.example.invalid/", GITHUB_STEP_SUMMARY=str(self.root / "summary"))
        self.objects = {}

    def fixture(self, name="macos-arm64.xml", data=RSS):
        path = self.root / name
        path.write_bytes(data)
        return path

    def fake_aws(self, *args):
        if args[:2] == ("s3api", "put-object"):
            key = args[args.index("--key") + 1]
            data = Path(args[args.index("--body") + 1]).read_bytes()
            self.objects[key] = data
            return dict(ChecksumSHA256=base64.b64encode(hashlib.sha256(data).digest()).decode())
        if args[:2] == ("s3api", "get-object"):
            Path(args[-1]).write_bytes(self.objects[args[args.index("--key") + 1]])
            return {}
        if args[:2] == ("cloudfront", "create-invalidation"):
            return dict(Invalidation=dict(Id="INVALIDATION1"))
        self.fail(f"unexpected AWS operation: {args}")

    def execute(self, aws=None, channel="stable", directory=None):
        with patch.dict(os.environ, self.env), patch.object(mirror, "aws", side_effect=aws or self.fake_aws) as calls, \
             patch.object(mirror.subprocess, "check_output", return_value="a" * 40), \
             patch.object(mirror.subprocess, "run") as wait, patch.object(mirror, "verify_cdn") as verify:
            mirror.sync(directory or self.root, channel)
            return calls, wait, verify

    def test_current_platform_feeds_validate_without_network(self):
        directory = Path(__file__).resolve().parents[2] / "update/stable"
        self.assertTrue({"macos-arm64.xml", "windows-x64.xml", "windows-x86.xml"}.issubset(
            {name for name, _ in mirror.feeds(directory)}))

    def test_existing_metadata_appcast_is_accepted_without_rewriting_its_bytes(self):
        path = Path(__file__).resolve().parents[2] / "update/metadata.py"
        metadata_spec = importlib.util.spec_from_file_location("metadata_for_feed_sync", path)
        metadata = importlib.util.module_from_spec(metadata_spec)
        metadata_spec.loader.exec_module(metadata)
        data = metadata.appcast(dict(target="macos-arm64", version="1.3.2", minimum_system_version="15.0.0",
            url="https://cdn.example.invalid/immutable.pkg.zip", size=1,
            ed25519_signature=base64.b64encode(bytes(64)).decode()))
        self.fixture(data=data)
        self.assertEqual(mirror.feeds(self.root), [("macos-arm64.xml", data)])

    def test_uploads_all_xml_only_to_exact_keys_and_verifies_before_invalidation(self):
        for name in ("windows-x64.xml", "macos-arm64.xml", "windows-x86.xml"):
            self.fixture(name)
        self.fixture("metadata.json", b"not an XML feed")
        self.fixture("installer.exe", b"never publish this")
        calls, wait, verify = self.execute()
        uploads = [call.args for call in calls.call_args_list if call.args[:2] == ("s3api", "put-object")]
        self.assertEqual(len(uploads), 3)
        for args in uploads:
            self.assertTrue(args[args.index("--key") + 1].startswith("keykey/update/stable/"))
            self.assertIn("application/rss+xml; charset=utf-8", args)
            self.assertIn(mirror.CACHE_CONTROL, args)
            self.assertIn("source-sha=" + "a" * 40, args)
        invalidation = calls.call_args_list[-1].args
        self.assertEqual(invalidation[invalidation.index("--paths") + 1:],
            ("/keykey/update/stable/macos-arm64.xml", "/keykey/update/stable/windows-x64.xml",
             "/keykey/update/stable/windows-x86.xml"))
        self.assertEqual(calls.call_count, 7)  # put/get for each file, then exact invalidation.
        self.assertIn("invalidation-completed", wait.call_args.args[0])
        self.assertEqual(verify.call_count, 3)
        self.assertEqual(verify.call_args_list[0].args,
            ("https://cdn.example.invalid/keykey/update/stable/macos-arm64.xml", RSS))
        self.assertIn("S3 and CDN bytes verified", (self.root / "summary").read_text())

    def test_beta_sync_is_isolated_and_all_channels_keep_exact_paths(self):
        for channel in ("stable", "beta"):
            directory = self.root / channel
            directory.mkdir()
            (directory / "macos-arm64.xml").write_bytes(RSS)
        calls, _, verify = self.execute(channel="beta", directory=self.root / "beta")
        self.assertEqual(set(self.objects), {"keykey/update/beta/macos-arm64.xml"})
        self.assertEqual(verify.call_args.args[0], "https://cdn.example.invalid/keykey/update/beta/macos-arm64.xml")
        self.objects.clear()
        calls, _, _ = self.execute(channel="all")
        self.assertEqual(set(self.objects), {"keykey/update/stable/macos-arm64.xml", "keykey/update/beta/macos-arm64.xml"})
        self.assertEqual(calls.call_args_list[-1].args[-2:],
            ("/keykey/update/stable/macos-arm64.xml", "/keykey/update/beta/macos-arm64.xml"))

    def test_beta_item_or_beta_asset_cannot_enter_stable(self):
        base = b'<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Test</title><item><sparkle:version>1.3.2b1</sparkle:version><enclosure url="https://example.invalid/v1.3.2-beta1/package.pkg.zip"/></item></channel></rss>'
        for data in (base, base.replace(b"1.3.2b1", b"1.3.2"),
                     base.replace(b"1.3.2b1", b"1.3.2").replace(b"-beta1", b"").replace(
                         b"</item>", b"<sparkle:shortVersionString>1.3.2-beta1</sparkle:shortVersionString></item>")):
            self.fixture(data=data)
            with self.assertRaisesRegex(ValueError, "cannot be published to stable"):
                mirror.feeds(self.root, "stable")
            self.assertTrue(mirror.feeds(self.root, "beta"))

    def test_invalid_beta_snapshot_prevents_stable_uploads_too(self):
        for channel, data in (("stable", RSS), ("beta", b"<broken>")):
            directory = self.root / channel
            directory.mkdir()
            (directory / "macos-arm64.xml").write_bytes(data)
        with patch.object(mirror, "aws") as calls, self.assertRaises(ET.ParseError):
            mirror.sync(self.root, "all")
        calls.assert_not_called()

    def test_invalid_xml_prevents_every_external_write(self):
        self.fixture()
        self.fixture("windows-x64.xml", b"<rss>")
        with patch.object(mirror, "aws") as calls:
            with self.assertRaises(ET.ParseError):
                mirror.sync(self.root)
            calls.assert_not_called()

    def test_empty_oversized_dtd_non_rss_duplicate_channels_and_unsafe_links_rejected(self):
        for data in (b"", b"x" * (mirror.MAX_SIZE + 1), b'<!DOCTYPE rss>' + RSS,
                     ('<!DOCTYPE rss>' + RSS.decode()).encode("utf-16"), b"<not-rss/>",
                     RSS.replace(b"</rss>", b"<channel/></rss>"),
                     RSS.replace(b"</link>", b"</link><link>https://example.invalid/second</link>"),
                     RSS.replace(b"https://example.invalid", b"http://example.invalid"),
                     RSS.replace(b"https://example.invalid", b"https://user:pass@example.invalid")):
            with self.subTest(data=data[:30]):
                self.fixture(data=data)
                with self.assertRaises((ValueError, UnicodeError)):
                    mirror.feeds(self.root)

    def test_symlinks_directories_and_unsafe_names_are_not_uploaded(self):
        path = self.fixture()
        link = self.root / "linked.xml"
        link.symlink_to(path)
        with self.assertRaisesRegex(ValueError, "unsafe feed"):
            mirror.feeds(self.root)
        link.unlink()
        bad = self.fixture("bad name.xml")
        with self.assertRaisesRegex(ValueError, "unsafe feed"):
            mirror.feeds(self.root)
        bad.unlink()
        (self.root / "folder.xml").mkdir()
        with self.assertRaisesRegex(ValueError, "unsafe feed"):
            mirror.feeds(self.root)

    def test_empty_directory_fails_without_deleting_remote_objects(self):
        with patch.object(mirror, "aws") as calls:
            with self.assertRaisesRegex(ValueError, "never deleted"):
                mirror.sync(self.root)
            calls.assert_not_called()

    def test_invalid_aws_destinations_fail_before_upload(self):
        self.fixture()
        for field, values in (("RELEASE_MIRROR_BUCKET", ("", "bucket/other", "--option")),
                              ("RELEASE_MIRROR_DISTRIBUTION_ID", ("", "id/other")),
                              ("RELEASE_MIRROR_BASE_URL", ("http://example.invalid", "https://user@example.invalid",
                                  "https://example.invalid/path", "https://example.invalid/?query=1", "https://example.invalid/#x"))):
            for value in values:
                with self.subTest(field=field, value=value), patch.dict(os.environ, dict(self.env, **{field:value})), \
                     patch.object(mirror, "aws") as calls:
                    with self.assertRaises(ValueError):
                        mirror.sync(self.root)
                    calls.assert_not_called()

    def test_bad_s3_checksum_or_readback_cannot_report_success_or_invalidate(self):
        self.fixture()
        def bad_checksum(*args):
            return dict(ChecksumSHA256="wrong")
        def bad_readback(*args):
            if args[:2] == ("s3api", "get-object"):
                Path(args[-1]).write_bytes(b"different object")
                return {}
            return self.fake_aws(*args)
        for fake in (bad_checksum, bad_readback):
            with self.subTest(fake=fake.__name__):
                with self.assertRaisesRegex(ValueError, "S3"):
                    self.execute(fake)
                self.assertFalse((self.root / "summary").exists())

    def test_failed_aws_command_never_reports_success(self):
        self.fixture()
        def denied(*args):
            raise subprocess.CalledProcessError(1, "aws")
        with self.assertRaises(subprocess.CalledProcessError):
            self.execute(denied)
        self.assertFalse((self.root / "summary").exists())

    def test_failed_invalidation_wait_or_cdn_verification_never_reports_success(self):
        self.fixture()
        with patch.dict(os.environ, self.env), patch.object(mirror, "aws", side_effect=self.fake_aws), \
             patch.object(mirror.subprocess, "check_output", return_value="a" * 40), \
             patch.object(mirror.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "aws")), \
             patch.object(mirror, "verify_cdn") as verify:
            with self.assertRaises(subprocess.CalledProcessError):
                mirror.sync(self.root)
            verify.assert_not_called()
        with patch.dict(os.environ, self.env), patch.object(mirror, "aws", side_effect=self.fake_aws), \
             patch.object(mirror.subprocess, "check_output", return_value="a" * 40), \
             patch.object(mirror.subprocess, "run"), \
             patch.object(mirror, "verify_cdn", side_effect=ValueError("CDN mismatch")):
            with self.assertRaisesRegex(ValueError, "CDN mismatch"):
                mirror.sync(self.root)
        self.assertFalse((self.root / "summary").exists())

    def test_cdn_verification_retries_errors_and_rejects_wrong_bytes_or_http_redirect(self):
        url = "https://cdn.example.invalid/keykey/update/stable/macos-arm64.xml"
        response = SimpleNamespace(geturl=lambda:url, read=lambda limit:RSS)
        with patch.object(mirror, "urlopen", side_effect=[OSError("offline"), nullcontext(response)]) as request, \
             patch.object(mirror.time, "sleep"):
            mirror.verify_cdn(url, RSS)
            self.assertEqual(request.call_count, 2)
        for final_url, data in ((url, b"old feed"), ("http://example.invalid", RSS)):
            def open_response(*args, **kwargs):
                return nullcontext(SimpleNamespace(geturl=lambda:final_url, read=lambda limit:data))
            with patch.object(mirror, "urlopen", side_effect=open_response), patch.object(mirror.time, "sleep"):
                with self.assertRaisesRegex(ValueError, "CDN bytes"):
                    mirror.verify_cdn(url, RSS)


if __name__ == "__main__":
    unittest.main()
