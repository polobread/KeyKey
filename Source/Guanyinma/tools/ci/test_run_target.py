"""Transport unit tests. Fake commands never boot a device or replace target CI."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("guanyinma_ci_target", Path(__file__).with_name("run-target.py"))
TARGET = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TARGET)


class FakeAdb:
    def __init__(self, *, mutate_model=False, create_user=True, exit_code=0):
        self.files = {}
        self.commands = []
        self.mutate_model = mutate_model
        self.create_user = create_user
        self.exit_code = exit_code
        self.execution_argv = None

    def __call__(self, argv, **kwargs):
        self.commands.append(argv)
        operation = argv[3]
        if operation == "push":
            self.files[argv[5]] = Path(argv[4]).read_bytes()
        elif operation == "pull":
            Path(argv[5]).write_bytes(self.files[argv[4]])
        elif operation == "shell":
            command = shlex.split(argv[4])
            if command[:2] == ["toybox", "sha256sum"]:
                path = command[2]
                if path not in self.files:
                    return subprocess.CompletedProcess(argv, 1, b"", b"missing")
                value = hashlib.sha256(self.files[path]).hexdigest()
                return subprocess.CompletedProcess(argv, 0, (value + "  " + path).encode(), b"")
            if command[:2] == ["test", "-f"]:
                return subprocess.CompletedProcess(argv, 0 if command[2] in self.files else 1, b"", b"")
            if command[0] == "env":
                self.execution_argv = command
                environment = dict(part.split("=", 1) for part in command[1:] if "=" in part)
                if self.create_user and "GUANYINMA_TEST_USER_DATABASE_PATH" in environment:
                    self.files[environment["GUANYINMA_TEST_USER_DATABASE_PATH"]] = b"SQLite test database bytes"
                if self.mutate_model:
                    self.files[environment["GUANYINMA_TEST_MODEL_PATH"]] = b"changed"
                return subprocess.CompletedProcess(argv, self.exit_code, b"target output\n", b"")
        return subprocess.CompletedProcess(argv, 0, b"", b"")


class TargetTransportTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="guanyinma-transport-unit-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.model = self.root / "模型 fixture.db"
        self.model.write_bytes(b"read-only model bytes")
        self.binary = self.root / "test binary"
        self.binary.write_bytes(b"target executable bytes")
        self.user = self.root / "使用者 資料.db"
        self.library = self.root / "library"
        self.library.mkdir()
        (self.library / "libguanyinma.so").write_bytes(b"target shared library")
        self.environment = mock.patch.dict(os.environ, {
            "GUANYINMA_TEST_MODEL_PATH": str(self.model),
            "GUANYINMA_TEST_NATIVE_LIBRARY_DIR": str(self.library),
            "GUANYINMA_TEST_USER_DATABASE_PATH": str(self.user),
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def android_args(self):
        return argparse.Namespace(adb="adb", serial="emulator-test", remote_root="/data/local/tmp/guanyinma-core-unit",
                                  executable=self.binary, arguments=[str(self.model), str(self.user), "literal; no-shell-evaluation"], timeout=30)

    def test_android_remaps_unicode_database_and_pulls_real_bytes(self):
        fake = FakeAdb()
        report = {}
        with mock.patch.object(TARGET, "command", side_effect=fake), mock.patch.object(TARGET, "forward"):
            self.assertEqual(TARGET.run_android(self.android_args(), report), 0)
        self.assertEqual(self.user.read_bytes(), b"SQLite test database bytes")
        self.assertEqual(report["model_sha256_before"], report["model_sha256_after"])
        self.assertEqual(report["staged_libraries"], ["libguanyinma.so"])
        self.assertTrue(report["executed"])
        self.assertIn("literal; no-shell-evaluation", fake.execution_argv)
        self.assertIn(report["model_remote_path"], fake.execution_argv)
        self.assertEqual(len(report["pulled_user_database_files"]), 1)
        self.assertIn("使用者 資料.db", report["pulled_user_database_files"][0]["remote_path"])

    def test_android_model_mutation_fails_even_when_test_returns_zero(self):
        with mock.patch.object(TARGET, "command", side_effect=FakeAdb(mutate_model=True)), mock.patch.object(TARGET, "forward"):
            with self.assertRaisesRegex(TARGET.TransportError, "model changed"):
                TARGET.run_android(self.android_args(), {})

    def test_android_missing_unicode_database_cannot_pass(self):
        with mock.patch.object(TARGET, "command", side_effect=FakeAdb(create_user=False)), mock.patch.object(TARGET, "forward"):
            with self.assertRaisesRegex(TARGET.TransportError, "Unicode user database"):
                TARGET.run_android(self.android_args(), {})

    def test_android_preserves_target_failure_status(self):
        report = {}
        with mock.patch.object(TARGET, "command", side_effect=FakeAdb(exit_code=7)), mock.patch.object(TARGET, "forward"):
            self.assertEqual(TARGET.run_android(self.android_args(), report), 7)
        self.assertEqual(report["test_returncode"], 7)

    def test_android_rejects_unscoped_remote_paths_before_transport(self):
        args = self.android_args()
        for path in ("/data/local/tmp", "/data/local/tmp/guanyinma-core-../other", "/sdcard/guanyinma-core-test"):
            args.remote_root = path
            with mock.patch.object(TARGET, "command") as command:
                with self.assertRaises(TARGET.TransportError):
                    TARGET.run_android(args, {})
                command.assert_not_called()

    def test_ios_forwards_child_environment_and_test_exit_status(self):
        calls = []
        def fake(argv, **kwargs):
            calls.append((argv, kwargs))
            return subprocess.CompletedProcess(argv, 9 if "spawn" in argv else 0, b"output", b"")
        report = {}
        args = argparse.Namespace(executable=self.binary, device="owned-test-device", arguments=["--test-threads=1"], timeout=30)
        with mock.patch.object(TARGET, "command", side_effect=fake), mock.patch.object(TARGET, "forward"):
            self.assertEqual(TARGET.run_ios(args, report), 9)
        spawn = [call for call in calls if "spawn" in call[0]][0]
        self.assertEqual(spawn[0][:4], ["xcrun", "simctl", "spawn", "owned-test-device"])
        self.assertEqual(spawn[1]["env"]["SIMCTL_CHILD_GUANYINMA_TEST_MODEL_PATH"], str(self.model.resolve()))
        self.assertEqual(spawn[1]["env"]["SIMCTL_CHILD_GUANYINMA_TEST_USER_DATABASE_PATH"], str(self.user))
        self.assertEqual(report["test_returncode"], 9)
        self.assertEqual(report["model_sha256_before"], report["model_sha256_after"])


if __name__ == "__main__":
    unittest.main()
