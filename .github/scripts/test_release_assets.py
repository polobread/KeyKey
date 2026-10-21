import importlib.util
import base64
import copy
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
import zipfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_assets", Path(__file__).with_name("release-assets.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def packages(self, platform, version="1.3.1"):
        prefix = f"chichi77-KeyKey-{version}"
        names = {
            "macos": [f"{prefix}-macos-arm64.pkg.zip"],
            "windows": [f"{prefix}-windows-x64.zip", f"{prefix}-windows-x86.zip",
                        f"{prefix}-windows-x64-setup.unsigned.exe"],
            "linux": [f"chichi77-keykey-data_{version}-1+ubuntu24.04_all.deb",
                      f"fcitx5-chichi77-keykey_{version}-1+ubuntu24.04_amd64.deb",
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
                f"{release.digest(self.root / name)}  ./{name}\n" for name in names), newline="\n")
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

    def test_linux_132_packages_and_release_tags(self):
        names = self.packages("linux", "1.3.2")
        paths = release.verified_assets(self.root, "linux", "1.3.2")
        self.assertEqual({path.name for path in paths}, set(names) | {"SHA256SUMS"})
        for tag in ("v1.3.2", "v1.3.2-beta1", "v1.3.2-beta2"):
            self.assertEqual(release.release_tag("release", tag, "", "1.3.2"), tag)
        with self.assertRaises(ValueError):
            release.release_tag("release", "v1.3.1", "", "1.3.2")

    def test_linux_publish_workflow_accepts_beta_and_preserves_asset_checks(self):
        repository = Path(__file__).resolve().parents[2]
        workflow = (repository / ".github/workflows/linux-ci.yml").read_text(encoding="utf-8")
        step = workflow.split("      - name: Verify version, package set, and checksums\n", 1)[1]
        script = textwrap.dedent(step.split("        run: |\n", 1)[1].split("      - name:", 1)[0])
        bash = (str(Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/bin/bash.exe")
                if os.name == "nt" else shutil.which("bash"))
        self.assertTrue(bash, "Bash is required to test the actual Linux publish step")
        # Use the same Python interpreter on Windows Git Bash and Linux.
        script = 'python3() { "' + Path(sys.executable).as_posix() + '" "$@"; }\n' + script
        names = self.packages("linux", "1.3.2")
        packages = self.root / "linux-packages"
        packages.mkdir()
        for name in names + ["SHA256SUMS"]:
            (self.root / name).replace(packages / name)
        source = self.root / "Source/Loaders/Linux-IME"
        source.mkdir(parents=True)
        (self.root / "README.md").write_text("# KeyKey 1.3.2\n")
        (self.root / "update").mkdir()
        shutil.copyfile(repository / "update/channels.py", self.root / "update/channels.py")
        cases = [("v1.3.2", "1.3.2", True), ("v1.3.2-beta1", "1.3.2", True),
                 ("v1.3.2-beta2", "1.3.2", True), ("v1.3.1-beta1", "1.3.2", False),
                 ("v1.3.2-beta0", "1.3.2", False), ("", "1.3.2", False),
                 ("v1.3.2-beta1", "1.3.1", False)]
        def run(tag):
            env = dict(os.environ, RELEASE_TAG=tag, RUNNER_TEMP=self.root.as_posix(),
                       GITHUB_ENV=(self.root / "env").as_posix())
            return subprocess.run([bash, "-c", script], cwd=self.root, env=env, capture_output=True, text=True)
        for tag, version, accepted in cases:
            with self.subTest(tag=tag, source=version):
                (source / "CMakeLists.txt").write_text(f"project(KeyKeyLinux VERSION {version} LANGUAGES CXX)\n")
                result = run(tag)
                self.assertEqual(result.returncode == 0, accepted, result.stdout + result.stderr)
        (source / "CMakeLists.txt").write_text("project(KeyKeyLinux VERSION 1.3.2 LANGUAGES CXX)\n")
        (packages / names[0]).write_bytes(b"tampered")
        self.assertNotEqual(run("v1.3.2-beta1").returncode, 0, "Beta publication accepted a corrupt package")

    def test_numbered_beta_tags_require_matching_prerelease(self):
        for tag in ("v1.3.2-beta1", "v1.3.2-beta2"):
            self.assertEqual(release.release_tag("release", tag, "", "1.3.2"), tag)
            self.assertEqual(release.release_tag("workflow_dispatch", "", tag, "1.3.2"), tag)
            with patch.object(release, "output", return_value=json.dumps(
                    dict(tagName=tag, isDraft=False, isPrerelease=True, url="https://example.invalid/beta"))):
                self.assertEqual(release.verify_release(tag, "owner/repo"), "https://example.invalid/beta")
        for tag, prerelease in (("v1.3.2-beta1", False), ("v1.3.2", True)):
            with patch.object(release, "output", return_value=json.dumps(
                    dict(tagName=tag, isDraft=False, isPrerelease=prerelease, url="https://example.invalid/release"))):
                with self.assertRaisesRegex(ValueError, "Pre-release"):
                    release.verify_release(tag, "owner/repo")

    def test_beta_resolution_records_channel_and_refuses_recovery(self):
        env = dict(GITHUB_EVENT_NAME="workflow_dispatch", REQUESTED_RELEASE_TAG="v1.3.2-beta2",
                   GITHUB_REPOSITORY="owner/repo", GITHUB_OUTPUT=str(self.root / "outputs"))
        with patch.dict(os.environ, env), patch.object(release, "output", return_value="a" * 40), \
             patch.object(release, "verify_release"), patch.object(release, "tag_commit", return_value="a" * 40):
            release.resolve("1.3.2")
        result = (self.root / "outputs").read_text()
        self.assertIn("release_version=1.3.2-beta2", result)
        self.assertIn("update_channel=beta", result)
        with patch.dict(os.environ, env), patch.object(release, "output", return_value="b" * 40), \
             patch.object(release, "verify_release"), patch.object(release, "tag_commit", return_value="a" * 40):
            with self.assertRaisesRegex(ValueError, "beta tag commit"):
                release.resolve("1.3.2")

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

    def test_mirror_uploads_only_verified_platform_assets_with_immutable_paths(self):
        names = self.packages("macos")
        info = self.root / "chichi77-KeyKey-1.3.1-macos-build-info.json"
        info.write_text(json.dumps(dict(
            platform="macos", version="1.3.1", release_tag="v1.3.1")))
        env = dict(RELEASE_TAG="v1.3.1", RELEASE_MIRROR_BUCKET="downloads-example",
                   RELEASE_MIRROR_DISTRIBUTION_ID="EDISTRIBUTION",
                   RELEASE_MIRROR_BASE_URL="https://downloads.example.com/",
                   GITHUB_STEP_SUMMARY=str(self.root / "summary"))
        with patch.dict(os.environ, env), patch.object(release.subprocess, "run") as run:
            release.mirror("macos", "1.3.1", self.root)

        self.assertEqual(run.call_count, 4)
        destinations = [call.args[0][4] for call in run.call_args_list[:3]]
        self.assertEqual(destinations, [
            f"s3://downloads-example/keykey/releases/download/v1.3.1/{names[0]}",
            f"s3://downloads-example/keykey/releases/download/v1.3.1/{names[0]}.sha256",
            "s3://downloads-example/keykey/releases/download/v1.3.1/"
            "chichi77-KeyKey-1.3.1-macos-build-info.json",
        ])
        for call in run.call_args_list[:3]:
            self.assertIn("public,max-age=0,s-maxage=31536000,must-revalidate", call.args[0])
        invalidation = run.call_args_list[3].args[0]
        self.assertEqual(invalidation[:5], [
            "aws", "cloudfront", "create-invalidation", "--distribution-id", "EDISTRIBUTION"])
        self.assertIn(f"/keykey/releases/download/v1.3.1/{names[0]}", invalidation)
        summary = (self.root / "summary").read_text()
        self.assertIn("https://downloads.example.com/keykey/releases/download/v1.3.1/", summary)

    def test_linux_mirror_links_encode_plus_without_changing_storage_keys(self):
        names = self.packages("linux", "1.3.2")
        info = self.root / "chichi77-KeyKey-1.3.2-linux-build-info.json"
        info.write_text(json.dumps(dict(
            platform="linux", version="1.3.2", release_tag="v1.3.2-beta1")))
        env = dict(RELEASE_TAG="v1.3.2-beta1", RELEASE_MIRROR_BUCKET="downloads-example",
                   RELEASE_MIRROR_DISTRIBUTION_ID="EDISTRIBUTION",
                   RELEASE_MIRROR_BASE_URL="https://downloads.example.com",
                   GITHUB_STEP_SUMMARY=str(self.root / "summary"))
        with patch.dict(os.environ, env), patch.object(release.subprocess, "run") as run:
            release.mirror("linux", "1.3.2", self.root)
        summary = (self.root / "summary").read_text()
        prefix = "keykey/releases/download/v1.3.2-beta1"
        destinations = [call.args[0][4] for call in run.call_args_list[:-1]]
        invalidation = run.call_args_list[-1].args[0]
        for name in names:
            # URLs need %2B, while AWS CLI keys and invalidation paths use the literal name.
            encoded = name.replace("+", "%2B")
            self.assertIn(f"[{name}](https://downloads.example.com/{prefix}/{encoded})", summary)
            self.assertIn(f"s3://downloads-example/{prefix}/{name}", destinations)
            self.assertIn(f"/{prefix}/{name}", invalidation)

    def test_mirror_rejects_mismatched_build_info_before_upload(self):
        self.packages("macos")
        info = self.root / "chichi77-KeyKey-1.3.1-macos-build-info.json"
        info.write_text(json.dumps(dict(
            platform="windows", version="1.3.1", release_tag="v1.3.1")))
        env = dict(RELEASE_TAG="v1.3.1", RELEASE_MIRROR_BUCKET="downloads-example",
                   RELEASE_MIRROR_DISTRIBUTION_ID="EDISTRIBUTION",
                   GITHUB_STEP_SUMMARY=str(self.root / "summary"))
        with patch.dict(os.environ, env), patch.object(release.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "does not match"):
                release.mirror("macos", "1.3.1", self.root)
            run.assert_not_called()


class ExistingLinuxMirrorTests(unittest.TestCase):
    setUp = ReleaseAssetsTests.setUp
    packages = ReleaseAssetsTests.packages

    def fixture(self):
        cmake = Path(__file__).resolve().parents[2] / "Source/Loaders/Linux-IME/CMakeLists.txt"
        self.version = release.re.search(r"project\(KeyKeyLinux VERSION (\d+\.\d+\.\d+)",
                                         cmake.read_text(encoding="utf-8")).group(1)
        self.source, self.run_id = "a" * 40, 123
        self.tag = "v" + self.version
        self.packages("linux", self.version)
        self.raw = self.root / "raw"
        self.raw.mkdir()
        for path in list(self.root.iterdir()):
            if path.is_file():
                path.replace(self.raw / path.name)
        (self.raw / "package.buildinfo").write_bytes(b"original build metadata")
        (self.raw / "package.changes").write_bytes(b"original package changes")
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as bundle:
            for path in self.raw.iterdir():
                bundle.writestr(path.name, path.read_bytes())
        self.archive = buffer.getvalue()
        self.identity = dict(run_id=self.run_id, id=456,
            name=f"linux-ubuntu-24.04-debian-packages-{self.source}",
            sha256=release.hashlib.sha256(self.archive).hexdigest(), size=len(self.archive))
        self.run = dict(id=self.run_id, repository=dict(full_name="polobread/KeyKey"),
            head_repository=dict(full_name="polobread/KeyKey"), path=".github/workflows/linux-ci.yml",
            event="release", head_sha=self.source, status="completed", conclusion="cancelled")
        self.artifact = dict(id=456, name=self.identity["name"], expired=False, size_in_bytes=len(self.archive),
            digest="sha256:" + self.identity["sha256"], workflow_run=dict(id=self.run_id, head_sha=self.source))
        self.report = dict(original=dict(repository="polobread/KeyKey", run_id=self.run_id, artifact_id=456,
            artifact_name=self.identity["name"], source_sha=self.source, archive_sha256=self.identity["sha256"],
            package_files={path.name: release.digest(path) for path in self.raw.iterdir()},
            product_rebuilt=False, tag_moved=False),
            lifecycle=dict(status="passed", version=f"{self.version}-1+ubuntu24.04", architecture="amd64"),
            x11=dict(status="passed", tests=["T01"]), case_results=dict(T01=dict(test="T01", status="passed")),
            notification_integration="passed", product_rebuilt=False, tag_moved=False)
        self.asset_paths = release.verified_assets(self.raw, "linux", self.version)
        self.payloads = {path.name: path.read_bytes() for path in self.asset_paths}
        self.info = dict(platform="linux", version=self.version, release_tag=self.tag, release_version=self.version,
            update_channel="stable", source_sha=self.source, tag_sha=self.source,
            run_url=f"https://github.com/polobread/KeyKey/actions/runs/{self.run_id}",
            original_run_conclusion="cancelled", product_rebuilt=False, original_artifact=self.identity,
            assets=[dict(name=path.name, size=path.stat().st_size, sha256=release.digest(path)) for path in self.asset_paths])
        self.refresh_publication()
        self.env = dict(GITHUB_REPOSITORY="polobread/KeyKey", GITHUB_REF="refs/heads/master",
            GITHUB_EVENT_NAME="workflow_dispatch", RELEASE_TAG=self.tag, RELEASE_MIRROR_BUCKET="downloads-example",
            RELEASE_MIRROR_DISTRIBUTION_ID="EDISTRIBUTION", RELEASE_MIRROR_BASE_URL="https://downloads.example.com",
            GITHUB_STEP_SUMMARY=str(self.root / "summary"))
        self.aws, self.downloads, self.objects = [], [], {}
        self.precondition, self.corrupt_readback, self.upload_error = False, False, False

    def refresh_publication(self):
        report_name = f"chichi77-KeyKey-{self.version}-linux-verification.json"
        self.payloads[report_name] = json.dumps(self.report).encode()
        self.approved = release.hashlib.sha256(self.payloads[report_name]).hexdigest()
        self.info["verification_report"] = dict(name=report_name, sha256=self.approved)
        self.payloads[f"chichi77-KeyKey-{self.version}-linux-build-info.json"] = json.dumps(self.info).encode()
        self.published = dict(tag_name=self.tag, draft=False, prerelease=False, assets=[
            dict(name=name, size=len(value), digest="sha256:" + release.hashlib.sha256(value).hexdigest())
            for name, value in self.payloads.items()])
        self.published["assets"].append(dict(name="untouched-windows.exe", size=1, digest="sha256:" + "f" * 64))

    def api(self, endpoint):
        if endpoint == f"actions/runs/{self.run_id}":
            return copy.deepcopy(self.run)
        if endpoint == f"actions/runs/{self.run_id}/artifacts?per_page=100":
            return dict(total_count=1, artifacts=[copy.deepcopy(self.artifact)])
        if endpoint == f"releases/tags/{self.tag}":
            return copy.deepcopy(self.published)
        raise AssertionError(endpoint)

    def process(self, args, **kwargs):
        if args[:2] == ["gh", "api"]:
            self.assertIn("actions/artifacts/456/zip", args[2])
            kwargs["stdout"].write(self.archive)
        elif args[:3] == ["gh", "release", "download"]:
            name = args[args.index("--pattern") + 1]
            self.downloads.append(name)
            (Path(args[args.index("--dir") + 1]) / name).write_bytes(self.payloads[name])
        elif args[0] == "aws":
            self.aws.append(args)
            if args[1:3] == ["s3api", "put-object"]:
                if self.upload_error:
                    return subprocess.CompletedProcess(args, 1, "", "(AccessDenied)")
                path = Path(args[args.index("--body") + 1])
                key = args[args.index("--key") + 1]
                self.objects[key] = path.read_bytes()
                if self.precondition:
                    return subprocess.CompletedProcess(args, 1, "", "(PreconditionFailed)")
                checksum = base64.b64encode(bytes.fromhex(release.digest(path))).decode()
                return subprocess.CompletedProcess(args, 0, json.dumps(dict(ChecksumSHA256=checksum)), "")
            if args[1:3] == ["s3api", "get-object"]:
                key = args[args.index("--key") + 1]
                Path(args[-2]).write_bytes(b"collision" if self.corrupt_readback else self.objects[key])
        else:
            raise AssertionError(args)
        return subprocess.CompletedProcess(args, 0, "", "")

    def execute(self, destination="recovery", approved=None):
        with patch.dict(os.environ, self.env), patch.object(release, "verify_release"), \
             patch.object(release, "tag_commit", return_value=self.source), \
             patch.object(release, "recovery_api", side_effect=self.api), \
             patch.object(release.subprocess, "run", side_effect=self.process), \
             patch.object(release, "output", return_value=json.dumps(dict(Invalidation=dict(Id="INV123")))), \
             patch.object(release, "verify_cdn_bytes") as cdn:
            release.mirror_existing_linux(self.version, self.root / destination, self.run_id,
                                          approved if approved is not None else self.approved)
            return cdn.call_args_list

    def test_existing_original_artifact_mirrors_only_seven_verified_assets(self):
        self.fixture()
        cdn = self.execute()
        puts = [args for args in self.aws if args[1:3] == ["s3api", "put-object"]]
        reads = [args for args in self.aws if args[1:3] == ["s3api", "get-object"]]
        self.assertEqual((len(puts), len(reads), len(cdn)), (7, 7, 7))
        self.assertEqual(set(self.downloads), set(self.payloads))
        for args in puts:
            self.assertEqual(args[args.index("--if-none-match") + 1], "*")
            self.assertIn("public,max-age=0,s-maxage=31536000,must-revalidate", args)
            self.assertIn(f"keykey/releases/download/{self.tag}/", args[args.index("--key") + 1])
        self.assertTrue(any("%2Bubuntu24.04" in call.args[0] for call in cdn))
        self.assertNotIn("untouched-windows", json.dumps(self.aws))
        self.assertIn("cancelled", json.dumps(self.info))

    def test_provenance_failures_have_no_aws_writes(self):
        self.fixture()
        cases = [lambda: self.env.update(GITHUB_REF="refs/heads/unreviewed"),
                 lambda: self.env.update(GITHUB_EVENT_NAME="pull_request"),
                 lambda: self.env.update(GITHUB_REPOSITORY="fork/KeyKey"),
                 lambda: self.run.update(head_sha="b" * 40),
                 lambda: self.run.update(event="pull_request"),
                 lambda: self.run.update(conclusion="failure"),
                 lambda: self.artifact.update(expired=True),
                 lambda: self.artifact.update(digest="sha256:" + "f" * 64),
                 lambda: self.artifact.update(size_in_bytes=1)]
        baseline = copy.deepcopy((self.env, self.run, self.artifact))
        for number, change in enumerate(cases):
            with self.subTest(case=number):
                self.env, self.run, self.artifact = copy.deepcopy(baseline)
                change()
                with self.assertRaises(ValueError):
                    self.execute(str(number))
                self.assertEqual(self.aws, [])

    def test_report_and_release_failures_have_no_aws_writes(self):
        self.fixture()
        baseline = copy.deepcopy((self.report, self.info, self.payloads))
        cases = [lambda: self.report["original"].update(source_sha="b" * 40),
                 lambda: self.report["original"]["package_files"].update({"unexpected": "a" * 64}),
                 lambda: self.report["lifecycle"].update(status="failed"),
                 lambda: self.report["case_results"]["T01"].update(status="failed"),
                 lambda: self.report["x11"].update(tests=["other"]),
                 lambda: self.report.update(notification_integration="failed"),
                 lambda: self.report.update(product_rebuilt=True),
                 lambda: self.info.update(tag_sha="b" * 40),
                 lambda: self.info.update(original_run_conclusion="success")]
        for number, change in enumerate(cases):
            with self.subTest(case=number):
                self.report, self.info, self.payloads = copy.deepcopy(baseline)
                change()
                self.refresh_publication()
                with self.assertRaises(ValueError):
                    self.execute(str(number))
                self.assertEqual(self.aws, [])
        self.report, self.info, self.payloads = copy.deepcopy(baseline)
        self.refresh_publication()
        with self.assertRaisesRegex(ValueError, "not approved"):
            self.execute("unapproved", approved="f" * 64)
        self.published["assets"][0]["digest"] = "sha256:" + "f" * 64
        with self.assertRaisesRegex(ValueError, "bytes differ"):
            self.execute("release-corrupt")
        self.assertEqual(self.aws, [])

    def test_existing_identical_s3_objects_pass_without_overwrite(self):
        self.fixture()
        self.precondition = True
        self.execute()
        self.assertEqual(len(self.objects), 7)
        self.assertFalse(any(args[1:3] == ["s3", "cp"] for args in self.aws))

    def test_s3_collision_or_access_denied_stops_before_invalidation(self):
        self.fixture()
        self.precondition, self.corrupt_readback = True, True
        with self.assertRaisesRegex(ValueError, "never overwrite"):
            self.execute("collision")
        self.assertEqual(len(self.aws), 2)
        self.aws.clear()
        self.upload_error = True
        with self.assertRaisesRegex(ValueError, "upload failed"):
            self.execute("access-denied")
        self.assertEqual(len(self.aws), 1)

    def test_cdn_stream_requires_complete_identical_https_bytes(self):
        path = self.root / "package"
        path.write_bytes(b"verified bytes")
        for payload, url, accepted in [(b"verified bytes", "https://cdn.example/p", True),
                (b"truncated", "https://cdn.example/p", False),
                (b"verified bytes", "http://cdn.example/p", False)]:
            with self.subTest(url=url, payload=payload):
                response = io.BytesIO(payload)
                response.geturl = lambda: url
                with patch.object(release, "urlopen", return_value=response):
                    if accepted:
                        release.verify_cdn_bytes("https://cdn.example/p", path)
                    else:
                        with self.assertRaises(ValueError):
                            release.verify_cdn_bytes("https://cdn.example/p", path)


if __name__ == "__main__":
    unittest.main()
