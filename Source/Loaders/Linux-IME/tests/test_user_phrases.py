"""Phrase editor integration; optional widget smoke runs on a private display."""
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from user_phrases import PhraseBackend, PhraseError, create_window

GUI = "--gui" in sys.argv
arguments = [argument for argument in sys.argv[1:] if argument != "--gui"]
CLI, MODEL = arguments[:2] if len(arguments) >= 2 else (None, None)
sys.argv = [sys.argv[0]]


class BackendTests(unittest.TestCase):
    def test_missing_cli_is_reported_without_shell_execution(self):
        with self.assertRaises(PhraseError):
            PhraseBackend("/nonexistent/keykey-smart-phrases").rows()

    def test_invalid_data_does_not_become_an_empty_successful_list(self):
        backend = PhraseBackend()
        for content in ('{"error":"broken"}', '[{"text":"詞語"}]', '[null]'):
            with patch.object(backend, "run", return_value=content):
                with self.assertRaises(PhraseError):
                    backend.rows()

    @unittest.skipUnless(CLI and MODEL, "CLI and model arguments required")
    def test_editor_backend_reads_real_core_json_and_reading_choices(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "model").mkdir()
            (root / "model/smart-mandarin.db").symlink_to(Path(MODEL).resolve())
            env = dict(os.environ, CHICHI77_KEYKEY_DATA_DIR=str(root / "model"),
                       XDG_DATA_HOME=str(root / "data"),
                       CHICHI77_KEYKEY_GUANYINMA_USER_DB=str(root / "user.db"))
            backend = PhraseBackend(Path(CLI).resolve(), env)
            self.assertEqual(backend.rows(), [])
            choices = backend.readings("你好")
            self.assertIn("ㄋㄧˇ ㄏㄠˇ", choices)
            backend.run("add", "琦琦星", "ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ")
            self.assertIn(("琦琦星", "ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ"), backend.rows())


@unittest.skipUnless(GUI and CLI and MODEL, "Run --gui CLI MODEL under a private display")
class WidgetTests(unittest.TestCase):
    def setUp(self):
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import GLib, Gtk
        self.GLib, self.Gtk = GLib, Gtk
        ready, _ = Gtk.init_check([])
        self.assertTrue(ready, "A private display is required")
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        (root / "model").mkdir()
        (root / "model/smart-mandarin.db").symlink_to(Path(MODEL).resolve())
        env = dict(os.environ, CHICHI77_KEYKEY_DATA_DIR=str(root / "model"),
                   XDG_DATA_HOME=str(root / "data"),
                   CHICHI77_KEYKEY_GUANYINMA_USER_DB=str(root / "user.db"))
        self.backend = PhraseBackend(Path(CLI).resolve(), env)
        self.notifications = []
        self.window = create_window(self.backend, lambda: self.notifications.append(True))
        self.window.show_all()
        self.wait(lambda: not self.window.busy)

    def wait(self, predicate):
        deadline = time.monotonic() + 15
        context = self.GLib.MainContext.default()
        while time.monotonic() < deadline:
            while context.pending():
                context.iteration(False)
            if predicate():
                return
            time.sleep(0.01)
        self.fail("Editor operation did not complete")

    def tearDown(self):
        if self.window.editor:
            self.window.editor.destroy()
        self.window.destroy()
        context = self.GLib.MainContext.default()
        while context.pending():
            context.iteration(False)
        self.temporary.cleanup()

    def test_add_lookup_edit_error_and_delete_through_widgets(self):
        self.window.add_button.clicked()
        editor = self.window.editor
        editor.phrase.set_text("你好")
        editor.lookup.clicked()
        self.wait(lambda: editor.lookup.get_sensitive())
        self.assertIn("ㄋㄧˇ ㄏㄠˇ", editor.reading.get_child().get_text())
        editor.phrase.set_text("琦琦星")
        editor.reading.get_child().set_text("ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ")
        editor.response(self.Gtk.ResponseType.OK)
        self.wait(lambda: self.window.editor is None and not self.window.busy)
        self.assertEqual([tuple(row) for row in self.window.store], [("琦琦星", "ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ")])
        self.window.view.get_selection().select_path(self.Gtk.TreePath.new_from_indices([0]))
        self.window.edit_button.clicked()
        editor = self.window.editor
        editor.reading.get_child().set_text("ㄋㄧˇ")
        editor.response(self.Gtk.ResponseType.OK)
        self.wait(lambda: editor.get_widget_for_response(self.Gtk.ResponseType.OK).get_sensitive())
        self.assertIs(self.window.editor, editor)
        self.assertTrue(editor.message.get_text())
        self.assertEqual(self.backend.rows(), [("琦琦星", "ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ")])
        editor.phrase.set_text("琦琦光")
        editor.reading.get_child().set_text("ㄑㄧˊ ㄑㄧˊ ㄍㄨㄤ")
        editor.response(self.Gtk.ResponseType.OK)
        self.wait(lambda: self.window.editor is None and not self.window.busy)
        self.assertEqual(self.backend.rows(), [("琦琦光", "ㄑㄧˊ ㄑㄧˊ ㄍㄨㄤ")])
        self.window.view.get_selection().select_path(self.Gtk.TreePath.new_from_indices([0]))
        self.window.remove_button.clicked()
        dialogs = [window for window in self.Gtk.Window.list_toplevels() if isinstance(window, self.Gtk.MessageDialog)]
        self.assertEqual(len(dialogs), 1)
        dialogs[0].response(self.Gtk.ResponseType.OK)
        self.wait(lambda: not self.window.busy)
        self.assertEqual(self.backend.rows(), [])
        self.assertEqual(len(self.notifications), 3)

    def test_read_failure_preserves_visible_rows(self):
        self.backend.run("add", "琦琦星", "ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ")
        self.window.refresh()
        self.wait(lambda: not self.window.busy)
        with patch.object(self.backend, "rows", side_effect=PhraseError("讀取失敗")):
            self.window.refresh()
            self.wait(lambda: not self.window.busy)
        self.assertEqual([tuple(row) for row in self.window.store], [("琦琦星", "ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ")])
        self.assertIn("讀取失敗", self.window.status.get_text())

    def test_closing_editor_during_save_still_refreshes_main_list(self):
        self.window.add_button.clicked()
        editor = self.window.editor
        editor.phrase.set_text("琦琦星")
        editor.reading.get_child().set_text("ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ")
        started, proceed = threading.Event(), threading.Event()
        original = self.backend.run
        def delayed(*arguments):
            started.set()
            if not proceed.wait(5):
                raise PhraseError("測試操作逾時")
            return original(*arguments)
        with patch.object(self.backend, "run", side_effect=delayed):
            editor.response(self.Gtk.ResponseType.OK)
            self.wait(started.is_set)
            editor.destroy()
            proceed.set()
            self.wait(lambda: not self.window.busy)
        self.assertEqual([tuple(row) for row in self.window.store], [("琦琦星", "ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ")])
        self.assertEqual(len(self.notifications), 1)


if __name__ == "__main__":
    unittest.main()
