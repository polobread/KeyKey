#!/usr/bin/env python3
"""Run with dbus-run-session -- xvfb-run -a python3 (no external network)."""
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from update_notify_gui import Application, Gio, GLib
import update_notify as updates


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
        self.block = None

    def get(self, url):
        self.requests.append(url)
        if self.block:
            self.block.wait(3)
        if self.releases is None:
            raise OSError("offline")
        return (json.dumps(self.releases).encode() if url == updates.API else
                b"project(KeyKeyLinux VERSION 1.3.2 LANGUAGES CXX)\n")

    def app(self, system="FreeBSD"):
        app = Application("1.3.1", system, "/usr/local/bin/keykey-update-notify", self.get)
        app.set_flags(Gio.ApplicationFlags.HANDLES_COMMAND_LINE | Gio.ApplicationFlags.NON_UNIQUE)
        app.register(None)
        self.addCleanup(app.quit)
        app.activate()
        self.addCleanup(lambda: app.window.destroy() if app.window else None)
        return app

    def new_release(self):
        self.releases = [{"tag_name": "v1.3.2", "draft": False, "prerelease": False, "assets": []}]

    def test_fresh_settings_start_weekly_timer_and_keep_beta_off(self):
        (updates.config_home() / "chichi77-keykey/update-notification.json").unlink()
        app = self.app()
        self.assertTrue(app.enabled.get_active())
        self.assertFalse(app.beta.get_active())
        self.assertIsNotNone(app.timer)
        self.assertEqual(self.requests, [])  # Opening the window is not a manual check.
        app.periodic()
        pump(lambda: not app.busy)
        self.assertEqual(self.requests, [updates.API])
        app.periodic()
        self.assertEqual(self.requests, [updates.API])  # Same-week attempts stay throttled.
        app.enabled.set_active(False)
        self.assertIsNone(app.timer)
        self.assertFalse(updates.preferences()["enabled"])

    def test_open_settings_does_not_contact_network(self):
        app = self.app()
        app.periodic()
        self.assertEqual(self.requests, [])
        self.assertFalse(app.enabled.get_active())
        self.assertIsNone(app.timer)

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
            pump(lambda: not app.busy)
            notify.assert_called_once()
            self.assertEqual(app.state["last_notified"], "1.3.2")
            requests = len(self.requests)
            app.periodic()
            self.assertEqual(len(self.requests), requests)
            app.state["last_attempt"] = 0
            app.periodic()
            pump(lambda: not app.busy)
            notify.assert_called_once()
            with patch("update_notify_gui.Gtk.show_uri_on_window") as open_uri:
                app.result = None
                app.lookup_action("download").activate(GLib.Variant("s", "1.3.2"))
                self.assertEqual(open_uri.call_args.args[1], updates.RELEASES + "/tag/v1.3.2")
            app.enabled.set_active(False)

    def test_missing_notification_daemon_does_not_consume_notice(self):
        self.new_release()
        app = self.app()
        with patch("update_notify_gui.notification_available", return_value=False), \
                patch.object(app, "send_notification") as notify:
            app.enabled.set_active(True)
            pump(lambda: not app.busy)
            notify.assert_not_called()
            self.assertNotIn("last_notified", app.state)
        app.enabled.set_active(False)

    def test_preference_save_failure_does_not_start_network(self):
        app = self.app()
        with patch("update_notify.set_preferences", side_effect=PermissionError):
            app.enabled.set_active(True)
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
