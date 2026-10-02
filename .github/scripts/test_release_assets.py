import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_assets", Path(__file__).with_name("release-assets.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def packages(self, platform):
        prefix = "chichi77-KeyKey-1.3.1"
        names = {
            "macos": [f"{prefix}-macos-arm64.pkg.zip"],
            "windows": [f"{prefix}-windows-x64.zip", f"{prefix}-windows-x86.zip",
                        f"{prefix}-windows-x64-setup.unsigned.exe"],
            "linux": ["chichi77-keykey-data_1.3.1-1+ubuntu24.04_all.deb",
                      "fcitx5-chichi77-keykey_1.3.1-1+ubuntu24.04_amd64.deb",
                      "gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_all.deb",
                      "gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_source.tar.gz"],
        }[platform]
        for name in names:
            path = self.root / name
            path.write_bytes(name.encode())
            if platform != "linux":
                path.with_name(name + ".sha256").write_text(f"{release.digest(path)}  {name}\n")
        if platform == "linux":
            (self.root / "SHA256SUMS").write_text("".join(
                f"{release.digest(self.root / name)}  ./{name}\n" for name in names))
        return names

    def test_published_release_and_manual_recovery_targets(self):
        self.assertEqual(release.release_tag("release", "v1.3.1", "", "1.3.1"), "v1.3.1")
        self.assertEqual(release.release_tag("workflow_dispatch", "", "v1.3.1", "1.3.1"), "v1.3.1")
        self.assertEqual(release.release_tag("workflow_dispatch", "", "", "1.3.1"), "")
        for event, tag, requested in (("release", "v1.3.0", ""), ("release", "", ""),
                                      ("workflow_dispatch", "", "v1.3.0"), ("push", "v1.3.1", "")):
            with self.assertRaises(ValueError):
                release.release_tag(event, tag, requested, "1.3.1")

    def test_all_platform_checksums_and_unrelated_assets(self):
        for platform, count in (("macos", 2), ("windows", 6), ("linux", 5)):
            with self.subTest(platform=platform):
                self.packages(platform)
                (self.root / "unrelated-release-asset.zip").write_bytes(b"keep")
                paths = release.verified_assets(self.root, platform, "1.3.1")
                self.assertEqual(len(paths), count)
                self.assertNotIn("unrelated-release-asset.zip", [p.name for p in paths])

    def test_corrupted_missing_and_duplicate_checksum_assets_fail(self):
        names = self.packages("macos")
        package = self.root / names[0]
        package.write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            release.verified_assets(self.root, "macos", "1.3.1")
        self.packages("macos")
        checksum = self.root / (names[0] + ".sha256")
        checksum.write_text(checksum.read_text() * 2)
        with self.assertRaisesRegex(ValueError, "duplicate"):
            release.verified_assets(self.root, "macos", "1.3.1")
        package.unlink()
        with self.assertRaisesRegex(ValueError, "missing/empty"):
            release.verified_assets(self.root, "macos", "1.3.1")

    def test_draft_or_missing_release_cannot_be_published(self):
        with patch.object(release, "output", return_value=json.dumps(
                dict(tagName="v1.3.1", isDraft=True, url="https://example.invalid/release"))):
            with self.assertRaisesRegex(ValueError, "publish the matching"):
                release.verify_release("v1.3.1", "owner/repo")

    def test_artifact_only_resolution_never_queries_a_release(self):
        with patch.dict(os.environ, {"GITHUB_EVENT_NAME": "workflow_dispatch", "REQUESTED_RELEASE_TAG": "",
                                     "GITHUB_OUTPUT": str(self.root / "outputs")}), \
             patch.object(release, "output", return_value="source-sha"), \
             patch.object(release, "verify_release") as verify:
            release.resolve("1.3.1")
            verify.assert_not_called()
        self.assertIn("publish_release=false", (self.root / "outputs").read_text())

    def test_recovery_overwrites_only_platform_assets_and_records_actual_source(self):
        names = self.packages("macos")
        env = dict(RELEASE_TAG="v1.3.1", GITHUB_REPOSITORY="owner/repo", BUILD_SOURCE_SHA="fixed-sha",
                   RELEASE_TAG_SHA="tag-sha", GITHUB_SERVER_URL="https://github.com", GITHUB_RUN_ID="123",
                   GITHUB_RUN_ATTEMPT="2", GITHUB_STEP_SUMMARY=str(self.root / "summary"))
        with patch.dict(os.environ, env), \
             patch.object(release, "verify_release", return_value="https://github.com/owner/repo/releases/tag/v1.3.1"), \
             patch.object(release, "output", return_value="fixed-sha"), \
             patch.object(release, "tag_commit", return_value="tag-sha"), \
             patch.object(release.subprocess, "run") as run:
            release.publish("macos", "1.3.1", self.root)
            args = run.call_args.args[0]
            self.assertEqual(args[:7], ["gh", "release", "upload", "v1.3.1", "--repo", "owner/repo", "--clobber"])
            self.assertEqual(len(args[7:]), 3)
            self.assertIn(str(self.root / names[0]), args)
            info = json.loads((self.root / "chichi77-KeyKey-1.3.1-macos-build-info.json").read_text())
            self.assertEqual((info["source_sha"], info["tag_sha"]), ("fixed-sha", "tag-sha"))
            run.reset_mock()
            (self.root / names[0]).write_bytes(b"corrupt")
            with self.assertRaises(ValueError):
                release.publish("macos", "1.3.1", self.root)
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
