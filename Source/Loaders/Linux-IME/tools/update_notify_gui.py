"""Out-of-process GTK notification UI; never loaded into a typing host."""

import fcntl
import platform
import math
import subprocess
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


def build_panel(controller, parent):
    """Build the updater controls for either its own window or a settings page."""
    controller.window = parent
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=20)
    box.pack_start(Gtk.Label(label=f"目前版本：{controller.current}", xalign=0), False, False, 0)
    policy = ("新版通知顯示上游版本。請透過 ports／pkg 更新；\n"
              "套件庫可能較晚上架。" if controller.system == "FreeBSD" else
              "只檢查並通知新版，不預先下載。按下「開啟官方下載頁」後，由您下載並透過套件管理器安裝。")
    box.pack_start(Gtk.Label(label=policy, xalign=0, wrap=True), False, False, 0)
    controller.status = Gtk.Label(label="按下「檢查新版」開始檢查。", xalign=0, wrap=True)
    box.pack_start(controller.status, False, False, 0)
    controller.enabled = Gtk.CheckButton(label="每週檢查新版並通知（登入桌面後）")
    controller.enabled.set_tooltip_text("上次檢查已滿 7 天時，啟動 10 分鐘後檢查；持續執行時每 7 天一次。")
    controller.enabled.set_active(controller.settings["enabled"])
    controller.beta = Gtk.CheckButton(label="也通知 beta 測試版")
    controller.beta.set_active(controller.settings["include_beta"])
    for widget in (controller.enabled, controller.beta):
        widget.connect("toggled", controller.preferences_changed)
        box.pack_start(widget, False, False, 0)
    box.pack_start(Gtk.Label(
        label="通知選項變更後立即儲存。", xalign=0, wrap=True),
        False, False, 0)
    row = Gtk.Box(spacing=10)
    controller.check_button = Gtk.Button(label="檢查新版")
    controller.check_button.connect("clicked", lambda *_: controller.check(manual=True))
    controller.download_button = Gtk.Button(label="開啟官方下載頁")
    controller.download_button.connect("clicked", lambda *_: controller.open_download())
    row.add(controller.check_button)
    row.add(controller.download_button)
    box.pack_start(row, False, False, 0)
    controller.refresh_buttons()
    return box


class Application(Gtk.Application):
    def __init__(self, current, system, executable, get=updates.fetch,
                 timeout=updates.CHECK_TIMEOUT):
        super().__init__(application_id="org.chichi77.KeyKey.UpdateNotification",
                         flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        updates.version_key(current)
        self.current, self.system, self.executable = current, system, executable
        self.get = get
        self.check_timeout_seconds = timeout
        self.check_timeout = None
        self.check_generation = 0
        self.active_check = None
        self.check_cancelled = None
        self.manual_check = False
        self.window = None
        self.busy = False
        self.timer = None
        self.timer_held = False
        self.not_before = time.time() + 600
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
        arguments = command_line.get_arguments()
        if "--reload-preferences" in arguments:
            self.reload_preferences()
        elif "--background" not in arguments:
            self.activate()
        elif self.settings["enabled"]:
            self.update_timer()
        return 0

    def do_activate(self):
        if self.window:
            self.window.present()
            return
        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title("琦琦輸入法更新通知")
        self.window.set_default_size(480, 280)
        self.window.connect("destroy", self.window_closed)
        self.window.add(build_panel(self, self.window))
        self.window.show_all()

    def window_closed(self, *_):
        self.window = None
        if self.busy and self.manual_check:
            self.check_cancelled.set()
            self.checked(None, True, True, self.active_check)

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
        if enabled and not self.settings["enabled"]:
            self.not_before = time.time() + 600
        self.settings = {"enabled": enabled, "include_beta": beta}
        self.result = None
        self.update_timer()

    def refresh_preference_widgets(self):
        if not self.window:
            return
        for widget, value in ((self.enabled, self.settings["enabled"]),
                              (self.beta, self.settings["include_beta"])):
            widget.handler_block_by_func(self.preferences_changed)
            try:
                widget.set_active(value)
            finally:
                widget.handler_unblock_by_func(self.preferences_changed)

    def reload_preferences(self):
        settings = updates.preferences()
        if settings["enabled"] and not self.settings["enabled"]:
            self.not_before = time.time() + 600
        self.settings = settings
        self.result = None
        self.refresh_preference_widgets()
        self.merge_persisted_state()
        self.update_timer()

    def merge_persisted_state(self):
        # Settings and the background helper can both write this metadata. Keep
        # newer attempts/notices from either process, including an in-memory
        # notice whose previous save failed, instead of rewriting an old cache.
        saved = updates.load_json(self.state_path)
        merged = dict(self.state)
        merged.update(saved)
        now = time.time()
        attempts = [state.get("last_attempt") for state in (self.state, saved)]
        attempts = [value for value in attempts if isinstance(value, (int, float))
                    and math.isfinite(value) and 0 <= value <= now]
        if attempts:
            merged["last_attempt"] = max(attempts)
        notices = set()
        for state in (self.state, saved):
            notices.update(self.notification_history(state))
        merged["notified_versions"] = sorted(notices, key=updates.version_key)
        if notices:
            # Retain the legacy marker for metadata compatibility, but exact
            # version history governs deduplication across stable/beta channels.
            merged["last_notified"] = max(notices, key=updates.version_key)
        self.state = merged

    def save_state(self):
        # Serialize read/merge/replace across the embedded and background
        # processes. Atomic JSON replacement alone does not prevent lost updates.
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        with (self.state_path.parent / ".update-notification.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.merge_persisted_state()
            updates.save_json(self.state_path, self.state)

    @staticmethod
    def notification_history(state):
        values = state.get("notified_versions", [])
        values = list(values) if isinstance(values, list) else []
        values.append(state.get("last_notified"))
        history = set()
        for value in values:
            try:
                updates.version_key(value)
                history.add(value)
            except (TypeError, ValueError):
                pass
        return history

    def already_notified(self, version):
        return version in self.notification_history(self.state)

    def saved_notification_consent(self, version):
        # Info-window consent is written in another process; forwarding its
        # reload command is asynchronous and is not authority to send a notice.
        settings = updates.preferences()
        if settings != self.settings:
            if settings["enabled"] and not self.settings["enabled"]:
                self.not_before = time.time() + 600
            self.settings = settings
            self.refresh_preference_widgets()
            self.update_timer()
        return bool(version and settings["enabled"] and
                    (settings["include_beta"] or updates.version_key(version)[3]))

    def update_timer(self):
        if self.timer is not None:
            GLib.source_remove(self.timer)
            self.timer = None
        if self.settings["enabled"]:
            if not self.timer_held:
                self.hold()
                self.timer_held = True
            delay = updates.next_check_delay(self.state, self.not_before)
            self.timer = GLib.timeout_add_seconds(math.ceil(delay), self.periodic)
        elif self.timer_held:
            self.timer_held = False
            self.release()
            self.withdraw_notification("update")

    def periodic(self):
        if self.timer is not None:
            GLib.source_remove(self.timer)
            self.timer = None
        self.merge_persisted_state()
        now = time.time()
        if self.settings["enabled"] and now >= self.not_before and updates.due(self.state, now):
            self.not_before = now + updates.INTERVAL
            if not self.busy:
                self.check(manual=False)
        self.update_timer()
        return GLib.SOURCE_REMOVE

    def check(self, manual):
        if self.busy or (not manual and not self.settings["enabled"]):
            return
        # Persist attempts before network activity: failures do not hammer GitHub.
        self.state["last_attempt"] = time.time()
        if self.timer_held:
            self.update_timer()
        try:
            self.save_state()
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
        self.check_generation += 1
        generation = self.active_check = self.check_generation
        cancelled = self.check_cancelled = threading.Event()
        self.manual_check = manual
        self.check_timeout = GLib.timeout_add(max(1, int(self.check_timeout_seconds * 1000)),
                                             self.check_expired, generation, manual)

        def work():
            try:
                result = updates.latest_release(self.current, self.system,
                                                platform.machine(), beta, self.get,
                                                self.check_timeout_seconds, cancelled)
                error = False
            except TimeoutError:
                result, error = None, "timeout"
            except Exception:
                # An unexpected worker error must also release the UI's busy
                # state; no worker exception should leave checks disabled.
                result, error = None, True
            GLib.idle_add(self.checked, result, error, manual, generation)

        threading.Thread(target=work, daemon=True).start()

    def check_expired(self, generation, manual):
        if generation != self.active_check:
            return GLib.SOURCE_REMOVE
        self.check_timeout = None
        self.check_cancelled.set()
        return self.checked(None, True, manual, generation, timed_out=True)

    def checked(self, result, error, manual, generation, timed_out=False):
        if generation != self.active_check:
            return GLib.SOURCE_REMOVE
        self.active_check = None
        if self.check_timeout is not None:
            GLib.source_remove(self.check_timeout)
            self.check_timeout = None
        self.busy = False
        self.result = result
        timed_out = timed_out or error == "timeout"
        if self.window:
            text = ("檢查更新逾時（10 秒）；請稍後按「檢查新版」再試。" if timed_out else
                    "檢查失敗，請確認網路連線後再試。" if error else
                    f"發現上游新版：{result['version']}" if result else
                    "目前沒有較新的可用版本。")
            self.status.set_text(text)
        consent = False
        if not manual:
            self.merge_persisted_state()
            consent = self.saved_notification_consent(result["version"] if result else None)
        if (result and not manual and consent and
                not self.already_notified(result["version"]) and
                notification_available() and
                self.saved_notification_consent(result["version"])):
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
            history = self.notification_history(self.state)
            history.add(result["version"])
            self.state["notified_versions"] = sorted(history, key=updates.version_key)
            try:
                self.save_state()
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


class EmbeddedController(Application):
    """A foreground view of the shared checker, without application lifecycle."""
    def __init__(self, current, system, executable, parent, get, timeout,
                 sync_preferences=None):
        super().__init__(current, system, executable, get, timeout)
        self.window = parent
        self.disposed = False
        self.sync_preferences = sync_preferences or self.start_background_reload

    @staticmethod
    def start_background_reload(arguments):
        return subprocess.Popen(arguments, stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                close_fds=True, start_new_session=True)

    def hold(self):
        pass

    def release(self):
        pass

    def activate(self):
        if not self.disposed and self.window:
            self.window.present()

    def update_timer(self):
        # Only preferences_changed calls this in an embedded view. The actual
        # background Application retains the timer after Settings is closed.
        if self.disposed:
            return
        try:
            self.sync_preferences([self.executable, "--reload-preferences"])
        except OSError:
            self.status.set_text("設定已儲存，但無法同步背景通知；下次登入桌面時會套用。")

    def periodic(self):
        return GLib.SOURCE_REMOVE

    def check(self, manual):
        if not self.disposed and manual:
            super().check(manual=True)

    def preferences_changed(self, *_):
        if not self.disposed:
            super().preferences_changed()

    def open_download(self, version=None):
        if not self.disposed:
            super().open_download(version)

    def refresh(self):
        """Refresh consent controls without writes, helper launches or HTTP."""
        if not self.disposed:
            self.settings = updates.preferences()
            self.refresh_preference_widgets()

    def dispose(self, *_):
        if self.disposed:
            return
        self.disposed = True
        self.window_closed()


def create_embedded_panel(current, system, executable, parent, get=updates.fetch,
                          timeout=updates.CHECK_TIMEOUT, sync_preferences=None):
    controller = EmbeddedController(current, system, executable, parent, get,
                                    timeout, sync_preferences)
    panel = build_panel(controller, parent)
    panel.controller = controller
    panel.dispose = controller.dispose
    panel.refresh = controller.refresh
    panel.connect("destroy", controller.dispose)
    return panel


def main(current, system, executable):
    # A saved opt-out exits before starting GTK or contacting any service.
    if ("--background" in sys.argv and "--reload-preferences" not in sys.argv and
            not updates.preferences()["enabled"]):
        return
    Application(current, system, executable).run(sys.argv)
