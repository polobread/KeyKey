"""Out-of-process GTK notification UI; never loaded into a typing host."""

import platform
from http.client import HTTPException
import sys
import threading
import time

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk

import update_notify as updates


def notification_available():
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        names = set()
        for method in ("ListNames", "ListActivatableNames"):
            reply = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                  "org.freedesktop.DBus", method, None,
                                  GLib.VariantType.new("(as)"), Gio.DBusCallFlags.NONE,
                                  1000, None)
            names.update(reply.unpack()[0])
        return bool(names & {"org.freedesktop.Notifications", "org.gtk.Notifications"})
    except GLib.Error:
        return False


class Application(Gtk.Application):
    def __init__(self, current, system, executable, get=updates.fetch):
        super().__init__(application_id="org.chichi77.KeyKey.UpdateNotification",
                         flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        updates.version_key(current)
        self.current, self.system, self.executable = current, system, executable
        self.get = get
        self.window = None
        self.busy = False
        self.timer = None
        self.result = None
        self.settings = updates.preferences()
        self.state_path = updates.state_home() / "chichi77-keykey/update-notification.json"
        self.state = updates.load_json(self.state_path)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        action = Gio.SimpleAction.new("download", GLib.VariantType.new("s"))
        action.connect("activate", lambda action, value: self.open_download(value.get_string()))
        self.add_action(action)
        self.update_timer()

    def do_command_line(self, command_line):
        if "--background" not in command_line.get_arguments():
            self.activate()
        elif self.settings["enabled"]:
            self.periodic()
        return 0

    def do_activate(self):
        if self.window:
            self.window.present()
            return
        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title("琦琦輸入法更新通知")
        self.window.set_default_size(480, 280)
        self.window.connect("destroy", self.window_closed)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=20)
        self.window.add(box)
        box.pack_start(Gtk.Label(label=f"目前版本：{self.current}", xalign=0), False, False, 0)
        policy = ("新版通知顯示上游版本。請透過 ports／pkg 更新；\n"
                  "套件庫可能較晚上架。" if self.system == "FreeBSD" else
                  "只通知新版並開啟官方下載頁，由您選擇下載與安裝。")
        box.pack_start(Gtk.Label(label=policy, xalign=0, wrap=True), False, False, 0)
        self.status = Gtk.Label(label="按下「檢查新版」開始檢查。", xalign=0, wrap=True)
        box.pack_start(self.status, False, False, 0)
        self.enabled = Gtk.CheckButton(label="每日檢查新版並通知（登入桌面後）")
        self.enabled.set_active(self.settings["enabled"])
        self.beta = Gtk.CheckButton(label="也通知 beta 測試版")
        self.beta.set_active(self.settings["include_beta"])
        for widget in (self.enabled, self.beta):
            widget.connect("toggled", self.preferences_changed)
            box.pack_start(widget, False, False, 0)
        row = Gtk.Box(spacing=10)
        self.check_button = Gtk.Button(label="檢查新版")
        self.check_button.connect("clicked", lambda *_: self.check(manual=True))
        self.download_button = Gtk.Button(label="開啟官方下載頁")
        self.download_button.connect("clicked", lambda *_: self.open_download())
        row.add(self.check_button)
        row.add(self.download_button)
        box.pack_start(row, False, False, 0)
        self.window.show_all()
        self.refresh_buttons()

    def window_closed(self, *_):
        self.window = None

    def refresh_buttons(self):
        if self.window:
            self.check_button.set_sensitive(not self.busy)
            self.beta.set_sensitive(not self.busy)
            self.download_button.set_sensitive(not self.busy)

    def preferences_changed(self, *_):
        enabled, beta = self.enabled.get_active(), self.beta.get_active()
        try:
            updates.set_preferences(enabled, beta, self.executable)
        except OSError:
            self.status.set_text("無法儲存更新通知設定，請檢查設定目錄權限。")
            for widget, value in ((self.enabled, self.settings["enabled"]),
                                  (self.beta, self.settings["include_beta"])):
                widget.handler_block_by_func(self.preferences_changed)
                widget.set_active(value)
                widget.handler_unblock_by_func(self.preferences_changed)
            return
        self.settings = {"enabled": enabled, "include_beta": beta}
        self.result = None
        self.update_timer()
        if enabled:
            self.periodic()

    def update_timer(self):
        if self.settings["enabled"] and self.timer is None:
            self.hold()
            self.timer = GLib.timeout_add_seconds(60, self.periodic)
        elif not self.settings["enabled"] and self.timer is not None:
            GLib.source_remove(self.timer)
            self.timer = None
            self.release()
            self.withdraw_notification("update")

    def periodic(self):
        if self.settings["enabled"] and not self.busy and updates.due(self.state):
            self.check(manual=False)
        return GLib.SOURCE_CONTINUE

    def check(self, manual):
        if self.busy or (not manual and not self.settings["enabled"]):
            return
        # Persist attempts before network activity: failures do not hammer GitHub.
        self.state["last_attempt"] = time.time()
        try:
            updates.save_json(self.state_path, self.state)
        except OSError:
            if self.window:
                self.status.set_text("無法儲存檢查時間，請檢查設定目錄權限。")
            return
        self.busy = True
        self.result = None
        self.hold()
        self.refresh_buttons()
        if self.window:
            self.status.set_text("正在檢查新版…")
        beta = self.settings["include_beta"]

        def work():
            try:
                result = updates.latest_release(self.current, self.system,
                                                platform.machine(), beta, self.get)
                error = False
            except (OSError, ValueError, TypeError, KeyError, HTTPException):
                result, error = None, True
            GLib.idle_add(self.checked, result, error, manual)

        threading.Thread(target=work, daemon=True).start()

    def checked(self, result, error, manual):
        self.busy = False
        self.result = result
        if self.window:
            text = ("檢查失敗，請確認網路連線後再試。" if error else
                    f"發現上游新版：{result['version']}" if result else
                    "目前沒有較新的可用版本。")
            self.status.set_text(text)
        if (result and not manual and self.settings["enabled"] and
                self.state.get("last_notified") != result["version"] and
                notification_available()):
            notification = Gio.Notification.new("琦琦輸入法有新版")
            body = f"目前 {self.current}，上游新版 {result['version']}。"
            body += ("請透過 ports／pkg 更新，套件庫可能較晚上架。"
                     if self.system == "FreeBSD" else "開啟官方發行頁查看下載。")
            notification.set_body(body)
            target = GLib.Variant("s", result["version"])
            notification.set_default_action_and_target("app.download", target)
            notification.add_button_with_target("開啟官方發行頁", "app.download", target)
            self.send_notification("update", notification)
            self.state["last_notified"] = result["version"]
            try:
                updates.save_json(self.state_path, self.state)
            except OSError:
                pass  # In-memory deduplication still applies to this session.
        self.refresh_buttons()
        self.release()
        return GLib.SOURCE_REMOVE

    def open_download(self, version=None):
        if version is not None:
            try:
                updates.version_key(version)
            except ValueError:
                return
            # A notification keeps its exact release target even while another
            # check clears/replaces the current UI result.
            url = f"{updates.RELEASES}/tag/v{version}"
        else:
            url = self.result["url"] if self.result else updates.RELEASES
        try:
            Gtk.show_uri_on_window(self.window, url, Gtk.get_current_event_time())
        except GLib.Error:
            self.activate()
            self.status.set_text(f"無法開啟瀏覽器，請自行開啟：{url}")


def main(current, system, executable):
    # Default-off autostart must not require a display or contact any service.
    if "--background" in sys.argv and not updates.preferences()["enabled"]:
        return
    Application(current, system, executable).run(sys.argv)
