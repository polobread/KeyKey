#!/usr/bin/env python3
"""Exercise shared GTK information panels in an isolated display; no network."""
import os
from pathlib import Path
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import about_gui
import update_notify as updates
import update_notify_gui
from test_update_notify import feed
from test_update_notify_gui import pump

Gtk = update_notify_gui.Gtk


class InfoPanelTests(unittest.TestCase):
    executable = "/usr/local/bin/keykey-update-notify"

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.environment = patch.dict(os.environ, {
            "XDG_CONFIG_HOME": temporary.name + "/config",
            "XDG_STATE_HOME": temporary.name + "/state",
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)
        process_patch = patch("subprocess.Popen")
        self.popen = process_patch.start()
        self.addCleanup(process_patch.stop)
        updates.set_preferences(False, False, self.executable)
        self.preferences_path = updates.config_home() / "chichi77-keykey/update-notification.json"
        self.autostart_path = updates.config_home() / "autostart/org.chichi77.KeyKey.UpdateNotification.desktop"
        self.state_path = updates.state_home() / "chichi77-keykey/update-notification.json"
        updates.save_json(self.state_path, {"last_attempt": 0})
        self.requests = []
        self.sync_calls = []
        self.releases = ["1.3.2"]
        self.block = None
        self.parent = Gtk.Window(title="Shared-panel test host")
        self.parent.show_all()
        self.addCleanup(self.parent.destroy)

    def snapshot(self):
        return {
            str(path): (path.read_bytes(), path.stat().st_mtime_ns) if path.exists() else None
            for path in (self.preferences_path, self.autostart_path, self.state_path)
        }

    def get(self, url):
        self.requests.append(url)
        if url not in updates.FEEDS.values():
            raise AssertionError("Unexpected update URL: " + url)
        if self.block is not None:
            self.block.wait(2)
        return feed(*self.releases, architectures=("amd64", "arm64"))

    def panel(self, timeout=updates.CHECK_TIMEOUT):
        panel = update_notify_gui.create_embedded_panel(
            "1.3.1", "FreeBSD", self.executable, self.parent,
            get=self.get, timeout=timeout, sync_preferences=self.sync_calls.append)
        self.assertIsInstance(panel, Gtk.Box)
        self.addCleanup(panel.dispose)
        self.parent.add(panel)
        self.parent.show_all()
        return panel

    def test_about_panel_reuses_host_without_another_window(self):
        before = set(Gtk.Window.list_toplevels())
        panel = about_gui.create_panel("1.3.1")
        self.assertIsInstance(panel, Gtk.Widget)
        self.addCleanup(panel.destroy)
        self.parent.add(panel)
        self.parent.show_all()
        labels = []

        def visit(widget):
            if isinstance(widget, Gtk.Label):
                labels.append(widget.get_text())
            if isinstance(widget, Gtk.Container):
                for child in widget.get_children():
                    visit(child)

        visit(panel)
        self.assertIn("版本 1.3.1", labels)
        self.assertEqual(set(Gtk.Window.list_toplevels()), before)

    def test_open_saved_page_has_no_network_helper_or_file_changes(self):
        before = self.snapshot()
        panel = self.panel()
        controller = panel.controller
        self.assertFalse(controller.enabled.get_active())
        self.assertFalse(controller.beta.get_active())
        self.assertFalse(controller.get_is_registered())
        self.assertIsNone(controller.timer)
        self.assertFalse(controller.timer_held)
        self.assertEqual(self.requests, [])
        self.assertEqual(self.sync_calls, [])
        self.popen.assert_not_called()
        self.assertEqual(self.snapshot(), before)

    def test_open_fresh_page_does_not_create_default_preferences_or_timer(self):
        self.preferences_path.unlink()
        self.state_path.unlink()
        before = self.snapshot()
        panel = self.panel()
        self.assertTrue(panel.controller.enabled.get_active())
        self.assertFalse(panel.controller.beta.get_active())
        self.assertIsNone(panel.controller.timer)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.requests, [])
        self.assertEqual(self.sync_calls, [])
        self.popen.assert_not_called()

    def test_refresh_reads_preferences_without_saving_or_starting_helper(self):
        panel = self.panel()
        updates.set_preferences(True, True, self.executable)
        before = self.snapshot()
        panel.refresh()
        self.assertTrue(panel.controller.enabled.get_active())
        self.assertTrue(panel.controller.beta.get_active())
        self.assertIsNone(panel.controller.timer)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.sync_calls, [])
        self.assertEqual(self.requests, [])
        self.popen.assert_not_called()

    def test_manual_check_reuses_controller_and_parent_for_download(self):
        panel = self.panel()
        controller = panel.controller
        with patch.object(controller, "send_notification") as notify:
            controller.check_button.emit("clicked")
            pump(lambda: not controller.busy)
            self.assertEqual(self.requests, [updates.FEEDS["stable"]])
            self.assertEqual(controller.result["version"], "1.3.2")
            self.assertIn("1.3.2", controller.status.get_text())
            notify.assert_not_called()
        with patch("update_notify_gui.Gtk.show_uri_on_window") as open_uri:
            controller.download_button.emit("clicked")
            self.assertIs(open_uri.call_args.args[0], self.parent)
            self.assertEqual(open_uri.call_args.args[1], updates.RELEASES + "/tag/v1.3.2")
        self.assertFalse(updates.preferences()["enabled"])
        self.assertEqual(self.sync_calls, [])

    def test_manual_timeout_can_retry_and_ignores_expired_completion(self):
        gate = self.block = threading.Event()
        self.addCleanup(gate.set)
        panel = self.panel(timeout=0.04)
        controller = panel.controller
        controller.check(True)
        pump(lambda: bool(self.requests))
        expired = controller.active_check
        pump(lambda: not controller.busy)
        self.assertIn("逾時", controller.status.get_text())
        self.assertTrue(controller.check_cancelled.is_set())
        self.assertTrue(controller.check_button.get_sensitive())
        self.assertEqual(len(self.requests), 1)
        self.block = None
        self.releases = []
        controller.check_timeout_seconds = 2
        controller.check(True)
        pump(lambda: not controller.busy)
        self.assertIn("沒有較新", controller.status.get_text())
        controller.checked({"version": "99.0.0"}, False, True, expired)
        self.assertIsNone(controller.result)
        self.assertIn("沒有較新", controller.status.get_text())
        gate.set()

    def test_dispose_cancels_manual_work_without_destroying_parent(self):
        gate = self.block = threading.Event()
        self.addCleanup(gate.set)
        panel = self.panel()
        controller = panel.controller
        controller.check(True)
        pump(lambda: bool(self.requests))
        expired = controller.active_check
        panel.dispose()
        panel.dispose()
        self.assertTrue(controller.check_cancelled.is_set())
        self.assertFalse(controller.busy)
        self.assertIsNone(controller.check_timeout)
        self.assertTrue(self.parent.get_visible())
        controller.checked({"version": "99.0.0"}, False, True, expired)
        self.assertIsNone(controller.result)
        before = self.snapshot()
        controller.check(True)
        self.assertEqual(len(self.requests), 1)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.sync_calls, [])
        gate.set()

    def test_checkbox_changes_sync_background_but_save_failure_does_not(self):
        panel = self.panel()
        controller = panel.controller
        controller.enabled.set_active(True)
        self.assertEqual(updates.preferences(), {"enabled": True, "include_beta": False})
        self.assertTrue(self.autostart_path.exists())
        controller.beta.set_active(True)
        controller.enabled.set_active(False)
        self.assertEqual(updates.preferences(), {"enabled": False, "include_beta": True})
        self.assertFalse(self.autostart_path.exists())
        self.assertEqual(self.sync_calls, [[self.executable, "--reload-preferences"]] * 3)
        self.assertIsNone(controller.timer)
        self.assertFalse(controller.timer_held)
        with patch("update_notify.set_preferences", side_effect=PermissionError):
            controller.enabled.set_active(True)
        self.assertFalse(controller.enabled.get_active())
        self.assertEqual(len(self.sync_calls), 3)
        self.assertIn("無法儲存", controller.status.get_text())
        self.assertEqual(self.requests, [])
        self.popen.assert_not_called()

    def test_information_window_reuses_two_tabs_and_keeps_manual_check_when_switching(self):
        before = self.snapshot()
        initial_windows = set(Gtk.Window.list_toplevels())
        app = about_gui.Application(
            "1.3.1", "FreeBSD", self.executable, get=self.get,
            sync_preferences=self.sync_calls.append)
        app.set_flags(update_notify_gui.Gio.ApplicationFlags.HANDLES_COMMAND_LINE |
                      update_notify_gui.Gio.ApplicationFlags.NON_UNIQUE)
        app.register(None)
        self.addCleanup(app.quit)
        self.addCleanup(lambda: app.window.destroy() if app.window else None)
        command = lambda section: SimpleNamespace(
            get_arguments=lambda: ["keykey-info-test", "--section", section])
        self.assertEqual(app.do_command_line(command("about")), 0)
        window, notebook = app.window, app.notebook
        self.assertEqual(notebook.get_n_pages(), 2)
        self.assertEqual([notebook.get_tab_label_text(notebook.get_nth_page(index))
                          for index in range(2)], ["關於", "檢查更新"])
        self.assertEqual(notebook.get_current_page(), 0)
        self.assertEqual(set(Gtk.Window.list_toplevels()) - initial_windows, {window})
        self.assertEqual(app.do_command_line(command("updates")), 0)
        self.assertIs(app.window, window)
        self.assertIs(app.notebook, notebook)
        self.assertEqual(notebook.get_current_page(), 1)
        self.assertEqual(self.requests, [])
        self.assertEqual(self.sync_calls, [])
        self.assertEqual(self.snapshot(), before)
        self.popen.assert_not_called()

        gate = self.block = threading.Event()
        self.addCleanup(gate.set)
        controller = app.updates_panel.controller
        controller.check(True)
        pump(lambda: len(self.requests) == 1)
        token = controller.active_check
        app.select_section("about")
        self.assertTrue(controller.busy)
        self.assertEqual(notebook.get_current_page(), 0)
        app.do_command_line(command("updates"))
        self.assertIs(app.updates_panel.controller, controller)
        self.assertEqual(controller.active_check, token)
        self.assertEqual(len(self.requests), 1)
        gate.set()
        pump(lambda: not controller.busy)
        self.assertEqual(controller.result["version"], "1.3.2")

        gate = self.block = threading.Event()
        self.addCleanup(gate.set)
        controller.check(True)
        pump(lambda: len(self.requests) == 2)
        token = controller.active_check
        window.destroy()
        self.assertIsNone(app.window)
        self.assertTrue(controller.disposed)
        self.assertFalse(controller.busy)
        controller.checked({"version": "99.0.0"}, False, True, token)
        self.assertIsNone(controller.result)
        gate.set()

    def test_public_wrappers_route_foreground_to_information_and_keep_background_service(self):
        tools = Path(__file__).resolve().parents[1] / "tools"

        def launch(name, *arguments):
            path = tools / name
            source = path.read_text().replace("@KEYKEY_UPDATE_VERSION@", "1.3.1")
            source = source.replace("@CMAKE_SYSTEM_NAME@", "FreeBSD")
            source = source.replace("@CMAKE_INSTALL_FULL_BINDIR@", "/usr/local/bin")
            source = source.replace("@CMAKE_INSTALL_FULL_DATADIR@", "/usr/local/share")
            with patch.object(sys, "argv", [name, *arguments]), \
                    patch.object(sys, "path", list(sys.path)):
                exec(compile(source, str(path), "exec"), {"__file__": str(path)})

        for name, section in (("keykey-about.in", "about"),
                              ("keykey-update-notify.in", "updates")):
            with self.subTest(entry=name), patch.object(about_gui, "main") as foreground, \
                    patch.object(update_notify_gui, "main") as background:
                before = self.snapshot()
                launch(name)
                foreground.assert_called_once_with("1.3.1", "FreeBSD", self.executable,
                                                    section=section)
                background.assert_not_called()
                self.assertEqual(self.snapshot(), before)
        with patch.object(about_gui, "main") as foreground, \
                patch.object(update_notify_gui, "main") as background:
            launch("keykey-update-notify.in", "--background")
            background.assert_not_called()  # Saved opt-out does not start GTK.
            launch("keykey-update-notify.in", "--reload-preferences")
            background.assert_called_once_with("1.3.1", "FreeBSD", self.executable)
            foreground.assert_not_called()


if __name__ == "__main__":
    unittest.main()
