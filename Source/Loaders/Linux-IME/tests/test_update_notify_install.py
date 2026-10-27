#!/usr/bin/env python3
"""Installed Fcitx button + autostart integration, in an isolated X11 session.

Run after installing into a test container, never a user's live Fcitx session:
dbus-run-session -- xvfb-run -a python3 tests/test_update_notify_install.py
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

import pyatspi
from gi.repository import Gio, GLib

from fcitx5_config_ui_driver import (descendants, wait_for_application,
                                    wait_for_node, click_node, wait_for_state,
                                    capture_window)
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import update_notify as updates


def main():
    processes = []
    information_pid = None
    title = "琦琦輸入法 — 關於與更新"
    with tempfile.TemporaryDirectory(prefix="keykey-update-install-") as directory:
        root = Path(directory)
        os.environ.update(XDG_CONFIG_HOME=str(root / "config"),
                          XDG_STATE_HOME=str(root / "state"),
                          XDG_DATA_HOME=str(root / "data"),
                          XDG_RUNTIME_DIR=str(root / "runtime"),
                          QT_LINUX_ACCESSIBILITY_ALWAYS_ON="1")
        (root / "runtime").mkdir(mode=0o700)
        subprocess.run(["dbus-update-activation-environment", "DISPLAY", "XAUTHORITY", "XDG_CONFIG_HOME",
                        "XDG_DATA_HOME", "XDG_RUNTIME_DIR", "QT_LINUX_ACCESSIBILITY_ALWAYS_ON"], check=True)
        config = root / "config/fcitx5"
        config.mkdir(parents=True)
        shutil.copyfile(Path(__file__).parent / "fixtures/fcitx5-profile", config / "profile")
        helper = shutil.which("keykey-update-notify")
        assert helper, "Installed notification helper is missing"
        autostart = Path("/etc/xdg/autostart/org.chichi77.KeyKey.UpdateNotification.desktop")
        assert f'Exec="{helper}" --background' in autostart.read_text()
        assert updates.preferences() == {"enabled": True, "include_beta": False}
        state_path = updates.state_home() / "chichi77-keykey/update-notification.json"
        updates.save_json(state_path, {"last_attempt": time.time()})  # Keep default-on startup offline.
        try:
            initial = subprocess.Popen([helper, "--background"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            processes.append(initial)
            time.sleep(1)
            assert initial.poll() is None, initial.communicate()
            initial.terminate()
            initial.communicate(timeout=5)
            updates.set_preferences(False, False, helper)
            state_path.unlink()
            subprocess.run([helper, "--background"], check=True, timeout=5)
            assert not state_path.exists(), "Saved opt-out startup wrote check state"
            processes.append(subprocess.Popen(["fcitx5"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                reply = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                      "org.freedesktop.DBus", "NameHasOwner",
                                      GLib.Variant("(s)", ("org.fcitx.Fcitx5",)),
                                      None, Gio.DBusCallFlags.NONE, 2000, None)
                if reply.unpack()[0]:
                    break
                time.sleep(0.05)
            assert reply.unpack()[0], "Fcitx did not register on the isolated bus"
            qt_log = open(root / "configtool.log", "w")
            processes.append(subprocess.Popen(["fcitx5-config-qt"], stdout=qt_log, stderr=qt_log))
            desktop = pyatspi.Registry.getDesktop(0)
            try:
                app = wait_for_application(desktop, "fcitx5-config-qt")
            except RuntimeError:
                qt_log.flush()
                print((root / "configtool.log").read_text())
                raise
            item = wait_for_node(app, "list item", "chichi77 KeyKey Bopomofo")
            click_node(item)
            wait_for_state(item, pyatspi.STATE_SELECTED, True)
            click_node(wait_for_node(app, "push button", "Configure"))
            dialog = wait_for_node(app, "dialog", "chichi77 KeyKey Bopomofo")
            # ExternalOptions share the same Configure button name. Select the
            # update row explicitly so the preceding About entry is not opened.
            # This still exercises the real generated option and installed helper.
            update_row = wait_for_node(dialog, "filler", "檢查更新:")
            button = wait_for_node(update_row, "push button", "Configure")
            click_node(button)
            deadline = time.monotonic() + 10
            window = None
            while time.monotonic() < deadline:
                for application in desktop:
                    for node in descendants(application):
                        if node.name == title and node.getRoleName() == "frame":
                            window = node
                            break
                if window:
                    break
                time.sleep(0.05)
            assert window, "Fcitx update button did not launch the installed helper"
            checkbox = wait_for_node(window, "check box", "每週檢查新版並通知（登入桌面後）")
            assert not checkbox.getState().contains(pyatspi.STATE_CHECKED)
            assert not state_path.exists(), "Opening the opted-out UI performed a network check"
            # Both foreground launchers select tabs in the same information
            # window; the background notifier has its own independent lifecycle.
            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            reply = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                  "org.freedesktop.DBus", "GetConnectionUnixProcessID",
                                  GLib.Variant("(s)", ("org.chichi77.KeyKey.Information",)),
                                  None, Gio.DBusCallFlags.NONE, 2000, None)
            information_pid = reply.unpack()[0]
            subprocess.run([shutil.which("keykey-about")], check=True, timeout=5)
            wait_for_state(wait_for_node(window, "page tab", "關於"), pyatspi.STATE_SELECTED, True)
            wait_for_node(window, "label", "琦琦輸入法")
            artifacts = os.environ.get("KEYKEY_SETTINGS_ARTIFACT_DIR")
            if artifacts:
                Path(artifacts).mkdir(parents=True, exist_ok=True)
                time.sleep(0.15)
                capture_window(title, Path(artifacts) / "installed-about")
            updates.set_preferences(True, False, helper)
            updates.save_json(updates.state_home() / "chichi77-keykey/update-notification.json",
                              {"last_attempt": time.time()})  # Keep the test offline.
            background = subprocess.Popen([helper, "--background"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            processes.append(background)
            time.sleep(1)
            assert background.poll() is None, background.communicate()
            secondary = subprocess.run([helper], capture_output=True, timeout=5)
            assert secondary.returncode == 0, secondary.stderr.decode()
            assert background.poll() is None, "Second launch replaced the background instance"
            reply = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                  "org.freedesktop.DBus", "GetConnectionUnixProcessID",
                                  GLib.Variant("(s)", ("org.chichi77.KeyKey.Information",)),
                                  None, Gio.DBusCallFlags.NONE, 2000, None)
            assert reply.unpack()[0] == information_pid, "Foreground launchers opened another information window"
            wait_for_state(wait_for_node(window, "page tab", "檢查更新"), pyatspi.STATE_SELECTED, True)
            checkbox = wait_for_node(window, "check box", "每週檢查新版並通知（登入桌面後）")
            wait_for_state(checkbox, pyatspi.STATE_CHECKED, True)
            if artifacts:
                time.sleep(0.15)
                capture_window(title, Path(artifacts) / "installed-updates")
            print("PASS: native Fcitx entry, shared two-tab About/Updates window, saved opt-out and background lifecycle")
        finally:
            if information_pid is not None:
                try:
                    os.kill(information_pid, 15)
                except ProcessLookupError:
                    pass
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=5)
            if "qt_log" in locals():
                qt_log.close()


if __name__ == "__main__":
    main()
