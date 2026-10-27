#!/usr/bin/env python3
"""Run with dbus-run-session -- xvfb-run -a python3 (no external network)."""
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from update_notify_gui import Application, Gio, GLib
import update_notify_gui as gui
import update_notify as updates
from test_update_notify import feed


def pump(predicate, timeout=5):
    until = time.monotonic() + timeout
    while not predicate() and time.monotonic() < until:
        GLib.MainContext.default().iteration(False)
        time.sleep(0.005)
    if not predicate():
        raise AssertionError("GTK callback timed out")


class GuiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = patch.dict(os.environ, {"XDG_CONFIG_HOME": self.temp.name + "/config",
                                          "XDG_STATE_HOME": self.temp.name + "/state"})
        self.env.start()
        self.addCleanup(self.env.stop)
        updates.set_preferences(False, False, "/usr/local/bin/keykey-update-notify")
        self.requests = []
        self.releases = []
        self.betas = []
        self.block = None

    def get(self, url):
        self.requests.append(url)
        if self.block:
            self.block.wait(3)
        if self.releases is None:
            raise OSError("offline")
        if url not in updates.FEEDS.values():
            raise AssertionError("Unexpected update URL: " + url)
        return feed(*(self.betas if url == updates.FEEDS["beta"] else self.releases),
                    architectures=("amd64", "arm64"))

    def app(self, system="FreeBSD", current="1.3.1"):
        app = Application(current, system, "/usr/local/bin/keykey-update-notify", self.get)
        app.set_flags(Gio.ApplicationFlags.HANDLES_COMMAND_LINE | Gio.ApplicationFlags.NON_UNIQUE)
        app.register(None)
        self.addCleanup(app.quit)
        app.activate()
        self.addCleanup(lambda: app.window.destroy() if app.window else None)
        return app

    def new_release(self):
        self.releases = ["1.3.2"]

    def test_fresh_settings_start_weekly_timer_and_keep_beta_off(self):
        (updates.config_home() / "chichi77-keykey/update-notification.json").unlink()
        app = self.app()
        self.assertTrue(app.enabled.get_active())
        self.assertFalse(app.beta.get_active())
        self.assertIsNotNone(app.timer)
        self.assertEqual(self.requests, [])  # Opening the window is not a manual check.
        app.periodic()
        self.assertEqual(self.requests, [])  # The startup deadline has not arrived.
        app.not_before = time.time() - 1
        app.periodic()
        pump(lambda: not app.busy)
        self.assertEqual(self.requests, [updates.FEEDS["stable"]])
        app.periodic()
        self.assertEqual(self.requests, [updates.FEEDS["stable"]])  # Same-week attempts stay throttled.
        app.enabled.set_active(False)
        self.assertIsNone(app.timer)
        self.assertFalse(updates.preferences()["enabled"])

    def test_open_settings_does_not_contact_network(self):
        app = self.app()
        app.periodic()
        self.assertEqual(self.requests, [])
        self.assertFalse(app.enabled.get_active())
        self.assertIsNone(app.timer)

    def test_reload_command_refreshes_controls_without_writing_or_checking(self):
        app = self.app()
        updates.set_preferences(True, True, app.executable)
        path = updates.config_home() / "chichi77-keykey/update-notification.json"
        before = path.read_bytes(), path.stat().st_mtime_ns
        command = SimpleNamespace(get_arguments=lambda: [app.executable, "--reload-preferences"])
        with patch.object(app, "activate") as activate, \
                patch("update_notify.set_preferences") as save:
            self.assertEqual(app.do_command_line(command), 0)
            activate.assert_not_called()
            save.assert_not_called()
        self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), before)
        self.assertTrue(app.enabled.get_active())
        self.assertTrue(app.beta.get_active())
        self.assertIsNotNone(app.timer)
        self.assertEqual(self.requests, [])
        app.enabled.set_active(False)

    def test_reload_helper_survives_settings_close_and_stops_on_opt_out(self):
        tools = Path(__file__).resolve().parents[1] / "tools"
        environment = dict(os.environ, PYTHONPATH=str(tools))
        command = [sys.executable, "-c", "from update_notify_gui import main; "
                   "main('1.3.1', 'FreeBSD', '/usr/local/bin/keykey-update-notify')",
                   "--reload-preferences"]
        updates.set_preferences(True, False, "/usr/local/bin/keykey-update-notify")
        helper = subprocess.Popen(command, env=environment, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE)
        self.addCleanup(lambda: helper.terminate() if helper.poll() is None else None)
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

        def owns_name():
            if helper.poll() is not None:
                self.fail(str(helper.communicate()))
            return bus.call_sync(
                "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                "NameHasOwner", GLib.Variant("(s)", ("org.chichi77.KeyKey.UpdateNotification",)),
                None, Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]

        pump(owns_name)
        self.assertIsNone(helper.poll())
        state = updates.state_home() / "chichi77-keykey/update-notification.json"
        self.assertFalse(state.exists())
        updates.set_preferences(False, True, "/usr/local/bin/keykey-update-notify")
        forwarded = subprocess.run(command, env=environment, capture_output=True, timeout=5)
        self.assertEqual(forwarded.returncode, 0, forwarded.stderr)
        output = helper.communicate(timeout=5)
        self.assertEqual(helper.returncode, 0, output)
        self.assertFalse(state.exists())
        # A disabled helper with no existing instance has no window or hold and
        # exits normally; it does not open a foreground updater as a side effect.
        disabled = subprocess.run(command, env=environment, capture_output=True, timeout=5)
        self.assertEqual(disabled.returncode, 0, disabled.stderr)
        self.assertFalse(state.exists())

    def test_reload_flag_is_not_blocked_by_background_opt_out(self):
        arguments = ["helper", "--background", "--reload-preferences"]
        with patch.object(sys, "argv", arguments), patch.object(gui, "Application") as application:
            gui.main("1.3.1", "FreeBSD", "/usr/local/bin/keykey-update-notify")
            application.return_value.run.assert_called_once_with(arguments)

    def test_embedded_manual_attempt_defers_an_already_running_background_helper(self):
        app = self.app()
        app.enabled.set_active(True)
        app.not_before = time.time() - 1
        app.state["last_attempt"] = 0  # Cached before the settings window checks.
        sync_calls = []
        panel = gui.create_embedded_panel(
            "1.3.1", "FreeBSD", app.executable, app.window,
            get=self.get, sync_preferences=sync_calls.append)
        self.addCleanup(panel.dispose)
        panel.controller.check(True)
        pump(lambda: not panel.controller.busy)
        self.assertEqual(len(self.requests), 1)
        self.assertEqual(app.state["last_attempt"], 0)
        # An earlier background timer must inspect the shared persisted attempt,
        # rather than automatically performing another request from its old cache.
        app.periodic()
        self.assertFalse(app.busy)
        self.assertEqual(len(self.requests), 1)
        self.assertGreater(updates.next_check_delay(app.state, app.not_before),
                           updates.INTERVAL - 2)
        self.assertEqual(sync_calls, [])
        app.enabled.set_active(False)

    def test_stale_embedded_manual_check_preserves_newer_background_notice(self):
        state_path = updates.state_home() / "chichi77-keykey/update-notification.json"
        updates.save_json(state_path, {"last_attempt": 0, "last_notified": "1.3.0",
                                       "other_process": "old"})
        parent = gui.Gtk.Window()
        self.addCleanup(parent.destroy)
        panel = gui.create_embedded_panel(
            "1.3.1", "FreeBSD", "/usr/local/bin/keykey-update-notify", parent,
            get=self.get, sync_preferences=lambda _: self.fail("Unexpected helper launch"))
        self.addCleanup(panel.dispose)
        self.assertEqual(panel.controller.state["last_notified"], "1.3.0")
        updates.save_json(state_path, {"last_attempt": 0, "last_notified": "1.3.3",
                                       "other_process": "new"})
        self.new_release()
        started = time.time()
        panel.controller.check(True)
        pump(lambda: not panel.controller.busy)
        state = updates.load_json(state_path)
        self.assertEqual(state["last_notified"], "1.3.3")
        self.assertEqual(state["other_process"], "new")
        self.assertGreaterEqual(state["last_attempt"], started)
        self.assertEqual(panel.controller.result["version"], "1.3.2")

    def test_background_completion_preserves_another_controllers_newer_attempt(self):
        self.new_release()
        gate = self.block = threading.Event()
        self.addCleanup(gate.set)
        app = self.app()
        app.enabled.set_active(True)
        with patch("update_notify_gui.notification_available", return_value=True), \
                patch.object(app, "send_notification") as notify:
            app.check(False)
            pump(lambda: len(self.requests) == 1)
            first_attempt = app.state["last_attempt"]
            newer_attempt = time.time()
            self.assertGreater(newer_attempt, first_attempt)
            updates.save_json(app.state_path, {"last_attempt": newer_attempt,
                                               "last_notified": "1.3.1",
                                               "other_process": "new"})
            gate.set()
            pump(lambda: not app.busy)
            notify.assert_called_once()
        saved = updates.load_json(app.state_path)
        self.assertEqual(saved["last_attempt"], newer_attempt)
        self.assertEqual(saved["last_notified"], "1.3.2")
        self.assertEqual(saved["other_process"], "new")
        app.enabled.set_active(False)

    def test_failed_notice_save_retains_session_dedup_during_state_merge(self):
        self.new_release()
        app = self.app()
        app.enabled.set_active(True)
        save_json = updates.save_json

        def fail_notice(path, value):
            if path == app.state_path and value.get("last_notified") == "1.3.2":
                raise PermissionError("inert notification-state write failure")
            save_json(path, value)

        with patch("update_notify_gui.notification_available", return_value=True), \
                patch.object(app, "send_notification") as notify:
            with patch("update_notify.save_json", side_effect=fail_notice):
                app.check(False)
                pump(lambda: not app.busy)
            notify.assert_called_once()
            self.assertNotIn("last_notified", updates.load_json(app.state_path))
            self.assertEqual(app.state["last_notified"], "1.3.2")
            save_json(app.state_path, {"last_attempt": time.time(), "last_notified": "1.3.1"})
            app.check(False)
            pump(lambda: not app.busy)
            notify.assert_called_once()
        self.assertEqual(updates.load_json(app.state_path)["last_notified"], "1.3.2")
        app.enabled.set_active(False)

    def test_manual_check_and_download_action(self):
        self.new_release()
        app = self.app()
        app.check(True)
        pump(lambda: not app.busy)
        self.assertEqual(app.status.get_text(), "發現上游新版：1.3.2")
        with patch("update_notify_gui.Gtk.show_uri_on_window") as open_uri:
            app.open_download()
            self.assertEqual(open_uri.call_args.args[1], updates.RELEASES + "/tag/v1.3.2")
        self.assertFalse(updates.preferences()["enabled"])

    def test_linux_manual_check_uses_shared_feed(self):
        self.new_release()
        app = self.app(system="Linux")
        app.check(True)
        pump(lambda: not app.busy)
        self.assertEqual(self.requests, [updates.FEEDS["stable"]])
        self.assertEqual(app.result["version"], "1.3.2")
        with patch("update_notify_gui.Gtk.show_uri_on_window") as open_uri:
            app.open_download()
            self.assertEqual(open_uri.call_args.args[1], updates.RELEASES + "/tag/v1.3.2")

    def test_beta_checkbox_adds_only_the_reviewed_beta_feed(self):
        self.betas = ["1.3.2-beta10"]
        app = self.app()
        app.beta.set_active(True)
        self.assertEqual(self.requests, [])
        app.check(True)
        pump(lambda: not app.busy)
        self.assertEqual(self.requests, [updates.FEEDS["stable"], updates.FEEDS["beta"]])
        self.assertEqual(app.result["version"], "1.3.2-beta10")

    def test_offline_can_retry(self):
        self.releases = None
        app = self.app()
        app.check(True)
        pump(lambda: not app.busy)
        self.assertIn("檢查失敗", app.status.get_text())
        self.releases = []
        app.check(True)
        pump(lambda: not app.busy)
        self.assertIn("沒有較新", app.status.get_text())

    def test_timeout_is_async_and_late_result_cannot_replace_retry(self):
        self.new_release()
        self.block = threading.Event()
        app = self.app()
        app.check_timeout_seconds = 0.04
        app.check(True)
        pump(lambda: len(self.requests) == 1)
        first = app.active_check
        pump(lambda: not app.busy)
        self.assertIn("逾時", app.status.get_text())
        self.assertTrue(app.check_button.get_sensitive())
        self.assertEqual(len(self.requests), 1)  # No automatic retry.
        gate = self.block
        self.block = None
        self.releases = []
        app.check_timeout_seconds = 10
        app.check(True)
        pump(lambda: not app.busy)
        self.assertIn("沒有較新", app.status.get_text())
        app.checked({"version": "99.0.0", "url": updates.RELEASES}, False, True, first)
        self.assertIsNone(app.result)
        self.assertIn("沒有較新", app.status.get_text())
        gate.set()

    def test_closing_manual_check_retires_result(self):
        self.block = threading.Event()
        app = self.app()
        app.check(True)
        pump(lambda: len(self.requests) == 1)
        request = app.active_check
        app.window.destroy()
        self.assertFalse(app.busy)
        self.assertIsNone(app.check_timeout)
        app.checked({"version": "99.0.0"}, False, True, request)
        self.assertIsNone(app.result)
        self.block.set()

    def test_repeated_click_and_disable_inflight(self):
        self.new_release()
        self.block = threading.Event()
        app = self.app()
        with patch.object(app, "send_notification") as notify:
            app.enabled.set_active(True)
            app.not_before = time.time() - 1
            app.periodic()
            pump(lambda: len(self.requests) == 1)
            app.check(True)
            app.periodic()
            self.assertEqual(len(self.requests), 1)
            self.assertFalse(app.check_button.get_sensitive())
            app.enabled.set_active(False)
            self.block.set()
            pump(lambda: not app.busy)
            notify.assert_not_called()
            self.assertIsNone(app.timer)

    def test_weekly_deduplication_and_notification_action(self):
        self.new_release()
        app = self.app()
        with patch.object(app, "send_notification") as notify, \
                patch("update_notify_gui.notification_available", return_value=True):
            app.enabled.set_active(True)
            app.not_before = time.time() - 1
            app.periodic()
            pump(lambda: not app.busy)
            notify.assert_called_once()
            self.assertEqual(app.state["last_notified"], "1.3.2")
            requests = len(self.requests)
            app.periodic()
            self.assertEqual(len(self.requests), requests)
            app.state["last_attempt"] = 0
            app.not_before = time.time() - 1
            app.periodic()
            pump(lambda: not app.busy)
            notify.assert_called_once()
            with patch("update_notify_gui.Gtk.show_uri_on_window") as open_uri:
                app.result = None
                app.lookup_action("download").activate(GLib.Variant("s", "1.3.2"))
                self.assertEqual(open_uri.call_args.args[1], updates.RELEASES + "/tag/v1.3.2")
            app.enabled.set_active(False)

    def test_new_stable_below_notified_beta_is_announced_exactly_once(self):
        state_path = updates.state_home() / "chichi77-keykey/update-notification.json"
        updates.save_json(state_path, {"last_notified": "1.4.0-beta1", "last_attempt": 0})
        updates.set_preferences(True, False, "/usr/local/bin/keykey-update-notify")
        self.releases = ["1.3.9"]
        app = self.app(current="1.3.8")
        with patch.object(app, "send_notification") as notify, \
                patch("update_notify_gui.notification_available", return_value=True):
            app.check(False)
            pump(lambda: not app.busy)
            notify.assert_called_once()
            self.assertEqual(app.result["version"], "1.3.9")
            self.assertEqual(updates.load_json(state_path)["notified_versions"],
                             ["1.3.9", "1.4.0-beta1"])
            app.check(False)  # Exercise exact-version dedup independently of the weekly timer.
            pump(lambda: not app.busy)
            notify.assert_called_once()
        restarted = Application("1.3.8", "FreeBSD", app.executable, self.get)
        self.assertTrue(restarted.already_notified("1.3.9"))
        self.assertTrue(restarted.already_notified("1.4.0-beta1"))
        self.assertFalse(restarted.already_notified("1.3.10"))
        self.assertEqual(self.requests, [updates.FEEDS["stable"]] * 2)
        app.enabled.set_active(False)

    def test_disk_opt_out_blocks_inflight_background_notice_without_reload(self):
        self.new_release()
        gate = self.block = threading.Event()
        self.addCleanup(gate.set)
        app = self.app()
        app.enabled.set_active(True)
        with patch.object(app, "send_notification") as notify, \
                patch("update_notify_gui.notification_available", return_value=True):
            app.check(False)
            pump(lambda: len(self.requests) == 1)
            updates.set_preferences(False, False, app.executable)
            self.assertTrue(app.settings["enabled"])  # No reload command reached the helper.
            gate.set()
            pump(lambda: not app.busy)
            notify.assert_not_called()
        self.assertFalse(app.settings["enabled"])
        self.assertFalse(app.enabled.get_active())
        self.assertIsNone(app.timer)
        self.assertNotIn("1.3.2", updates.load_json(app.state_path)["notified_versions"])

    def test_disk_beta_opt_out_blocks_inflight_beta_notice_without_reload(self):
        self.betas = ["1.3.2-beta10"]
        gate = self.block = threading.Event()
        self.addCleanup(gate.set)
        app = self.app()
        app.enabled.set_active(True)
        app.beta.set_active(True)
        with patch.object(app, "send_notification") as notify, \
                patch("update_notify_gui.notification_available", return_value=True):
            app.check(False)
            pump(lambda: len(self.requests) == 1)
            updates.set_preferences(True, False, app.executable)
            self.assertTrue(app.settings["include_beta"])
            gate.set()
            pump(lambda: not app.busy)
            self.assertEqual(app.result["version"], "1.3.2-beta10")
            notify.assert_not_called()
        self.assertTrue(app.settings["enabled"])
        self.assertFalse(app.beta.get_active())
        self.assertNotIn("1.3.2-beta10", updates.load_json(app.state_path)["notified_versions"])
        app.enabled.set_active(False)

    def test_opt_out_during_notification_service_lookup_is_honored(self):
        self.new_release()
        app = self.app()
        app.enabled.set_active(True)

        def notification_service():
            updates.set_preferences(False, False, app.executable)
            return True

        with patch.object(app, "send_notification") as notify, \
                patch("update_notify_gui.notification_available", side_effect=notification_service):
            app.check(False)
            pump(lambda: not app.busy)
            notify.assert_not_called()
        self.assertFalse(app.settings["enabled"])
        self.assertIsNone(app.timer)

    def test_missing_notification_daemon_does_not_consume_notice(self):
        self.new_release()
        app = self.app()
        with patch("update_notify_gui.notification_available", return_value=False), \
                patch.object(app, "send_notification") as notify:
            app.enabled.set_active(True)
            app.not_before = time.time() - 1
            app.periodic()
            pump(lambda: not app.busy)
            notify.assert_not_called()
            self.assertNotIn("last_notified", app.state)
        app.enabled.set_active(False)

    def test_preference_save_failure_does_not_start_network(self):
        app = self.app()
        with patch("update_notify.set_preferences", side_effect=PermissionError):
            app.enabled.set_active(True)
            app.not_before = time.time() - 1
            app.periodic()
        self.assertFalse(app.enabled.get_active())
        self.assertEqual(self.requests, [])
        self.assertIsNone(app.timer)

    def test_freedesktop_notification_delivery_and_action(self):
        # An isolated real D-Bus server verifies Gio's fallback used by FreeBSD
        # desktops as well as non-GNOME Linux sessions.
        connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        connection.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                             "org.freedesktop.DBus", "RequestName",
                             GLib.Variant("(su)", ("org.freedesktop.Notifications", 0)),
                             None, Gio.DBusCallFlags.NONE, -1, None)
        interface = Gio.DBusNodeInfo.new_for_xml('''<node><interface name="org.freedesktop.Notifications">
          <method name="Notify"><arg type="s" direction="in"/><arg type="u" direction="in"/>
          <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/>
          <arg type="as" direction="in"/><arg type="a{sv}" direction="in"/><arg type="i" direction="in"/>
          <arg type="u" direction="out"/></method>
          <method name="GetCapabilities"><arg type="as" direction="out"/></method>
          <method name="GetServerInformation"><arg type="s" direction="out"/>
          <arg type="s" direction="out"/><arg type="s" direction="out"/><arg type="s" direction="out"/></method>
          <method name="CloseNotification"><arg type="u" direction="in"/></method>
          <signal name="ActionInvoked"><arg type="u"/><arg type="s"/></signal>
        </interface></node>''').interfaces[0]
        notices = []
        def method(conn, sender, path, iface, name, params, invocation):
            if name == "Notify":
                notices.append(params.unpack())
                invocation.return_value(GLib.Variant("(u)", (7,)))
            elif name == "GetCapabilities":
                invocation.return_value(GLib.Variant("(as)", (["actions", "body"],)))
            elif name == "GetServerInformation":
                invocation.return_value(GLib.Variant("(ssss)", ("Test", "KeyKey", "1", "1.2")))
            else:
                invocation.return_value(None)
        registration = connection.register_object("/org/freedesktop/Notifications", interface, method, None, None)
        self.addCleanup(connection.unregister_object, registration)
        self.new_release()
        app = self.app()
        app.enabled.set_active(True)
        app.not_before = time.time() - 1
        app.periodic()
        pump(lambda: bool(notices))
        self.assertIn("ports／pkg", notices[0][4])
        self.assertIn("1.3.2", notices[0][4])
        with patch("update_notify_gui.Gtk.show_uri_on_window") as open_uri:
            app.result = None
            connection.emit_signal(None, "/org/freedesktop/Notifications",
                                   "org.freedesktop.Notifications", "ActionInvoked",
                                   GLib.Variant("(us)", (7, "default")))
            pump(lambda: open_uri.called)
            self.assertEqual(open_uri.call_args.args[1], updates.RELEASES + "/tag/v1.3.2")
        app.enabled.set_active(False)

    def test_notification_action_rejects_invalid_version(self):
        app = self.app()
        with patch("update_notify_gui.Gtk.show_uri_on_window") as open_uri:
            app.lookup_action("download").activate(GLib.Variant("s", "../evil.invalid"))
            open_uri.assert_not_called()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        unittest.main()
    else:
        # Gio applications retain a process-wide registration until shutdown.
        # Give each case the real application lifecycle in its own process.
        failed = False
        for name in unittest.defaultTestLoader.getTestCaseNames(GuiTests):
            result = subprocess.run([sys.executable, __file__, "GuiTests." + name])
            failed |= result.returncode != 0
        sys.exit(int(failed))
