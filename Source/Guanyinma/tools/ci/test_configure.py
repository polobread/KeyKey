"""CI tool selection contracts; no compiler or target runtime is executed."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("guanyinma_ci_configure", Path(__file__).with_name("configure.py"))
CONFIGURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONFIGURE)


class WindowsToolSelectionTests(unittest.TestCase):
    def test_windows_uses_linker_adjacent_to_msvc_even_when_git_link_is_on_path(self):
        with tempfile.TemporaryDirectory(prefix="guanyinma-msvc-tools-") as directory:
            root = Path(directory).resolve()
            msvc = root / "Visual Studio tools"
            git = root / "Git" / "usr" / "bin"
            msvc.mkdir()
            git.mkdir(parents=True)
            compiler = msvc / "cl.exe"
            linker = msvc / "link.exe"
            for file in (compiler, linker, git / "link.exe"):
                file.write_bytes(b"tool-selection fixture, never executed")

            def which(name):
                # A generic link.exe lookup would select Git and must never occur.
                self.assertIn(name, ("cl.exe", "cl"))
                return str(compiler)

            with mock.patch.object(CONFIGURE.sys, "platform", "win32"), \
                 mock.patch.object(CONFIGURE.shutil, "which", side_effect=which), \
                 mock.patch.dict(os.environ, {"PATH": str(git) + os.pathsep + str(msvc)}, clear=True), \
                 mock.patch.dict(CONFIGURE.OUTPUT_VALUES, {}, clear=True):
                CONFIGURE.native(argparse.Namespace(sqlite_provider="bundled"))
                self.assertEqual(os.environ["CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER"], str(linker))
                self.assertEqual(os.environ["CC"], str(compiler))
                self.assertEqual(os.environ["PATH"].split(os.pathsep), [str(msvc), str(git), str(msvc)])
                self.assertEqual(json.loads(CONFIGURE.OUTPUT_VALUES["cc_json"]), [str(compiler)])

    def test_windows_missing_msvc_linker_never_falls_back_to_git_link(self):
        with tempfile.TemporaryDirectory(prefix="guanyinma-msvc-missing-") as directory:
            compiler = Path(directory) / "cl.exe"
            compiler.write_bytes(b"tool-selection fixture, never executed")
            with mock.patch.object(CONFIGURE.sys, "platform", "win32"), \
                 mock.patch.object(CONFIGURE.shutil, "which", return_value=str(compiler)), \
                 mock.patch.dict(os.environ, {}, clear=True):
                with self.assertRaisesRegex(RuntimeError, "adjacent to cl.exe"):
                    CONFIGURE.native(argparse.Namespace(sqlite_provider="bundled"))
                self.assertNotIn("CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER", os.environ)


if __name__ == "__main__":
    unittest.main()
