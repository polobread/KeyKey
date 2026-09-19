#!/usr/bin/env python3
"""Type into installed GNOME editors in the Wayland VM and read their text via AT-SPI."""

import argparse
import datetime
import json
import runpy
import shlex
import sys
import time
from pathlib import Path


VM = runpy.run_path(str(Path(__file__).with_name("gnome-vm-wayland-smoke.py")))
VM_DIR = VM["VM_DIR"]
guest = VM["guest"]
session_command = VM["session_command"]
Qmp = VM["Qmp"]

APPS = {
    "gedit": ("gtk3", "/usr/bin/gedit", "--standalone", "--new-window"),
    "gnome-text-editor": ("gtk4", "/usr/bin/gnome-text-editor", "--standalone",
                          "--ignore-session", "--new-window"),
}
MODES = {
    "wayland": ("GDK_BACKEND=wayland", "fcitx"),
    "bridge": ("GDK_BACKEND=wayland", "unset"),
    "wayland-im": ("GDK_BACKEND=wayland", "wayland"),
    "xwayland": ("GDK_BACKEND=x11", "fcitx"),
}
AT_SPI_READ = r'''
import gi
import json
import sys
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi

def find_document(node, depth=0):
    if node.get_role_name() == "text" and not node.get_name():
        return node
    if depth >= 20 or node.get_child_count() > 50:
        return None
    for index in range(node.get_child_count()):
        found = find_document(node.get_child_at_index(index), depth + 1)
        if found is not None:
            return found
    return None

desktop = Atspi.get_desktop(0)
for index in range(desktop.get_child_count()):
    application = desktop.get_child_at_index(index)
    if application.get_name() != sys.argv[1]:
        continue
    for window_index in range(application.get_child_count()):
        window = application.get_child_at_index(window_index)
        if sys.argv[2] not in window.get_name():
            continue
        document = find_document(window)
        if document is not None:
            print(json.dumps({
                "window": window.get_name(),
                "text": Atspi.Text.get_text(
                    document, 0, Atspi.Text.get_character_count(document)),
                "focused": document.get_state_set().contains(Atspi.StateType.FOCUSED),
            }, ensure_ascii=False))
            sys.exit(0)
sys.exit(2)
'''


def read_app(app, document_name):
    command = ("DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
               "/usr/bin/python3 -c " + shlex.quote(AT_SPI_READ) + " "
               + shlex.quote(app) + " " + shlex.quote(document_name))
    return json.loads(guest(command))


def wait_app(app, document_name, expected=None):
    last = None
    for _ in range(50):
        try:
            last = read_app(app, document_name)
            if last["focused"] and (expected is None or last["text"] == expected):
                return last
        except RuntimeError:
            pass
        time.sleep(0.2)
    raise RuntimeError(f"{app} document did not reach {expected!r}: {last}")


def inspect_app(unit, app, document_name):
    pid = session_command("systemctl --user show --property=MainPID --value "
                          + shlex.quote(unit + ".service"))
    details = {"pid": pid, "document": read_app(app, document_name),
               "fcitx_status": session_command("fcitx5-remote; true")}
    if pid.isdecimal() and pid != "0":
        details["environment"] = guest(
            f"tr '\\0' '\\n' < /proc/{pid}/environ | "
            "grep -E '^(GDK_BACKEND|GTK_IM_MODULE|WAYLAND_DISPLAY|"
            "XDG_SESSION_TYPE)=' || true")
        details["libraries"] = guest(
            f"grep -E 'im-fcitx|im-wayland|libwayland-client|libX11' "
            f"/proc/{pid}/maps | awk '{{print $6}}' | sort -u || true")
    return details


def run_app(qmp, app, mode):
    toolkit, *command = APPS[app]
    backend, gtk_module = MODES[mode]
    unit = f"keykey-real-{app}-{mode}-{int(time.time())}"
    document = f"/tmp/{unit}.txt"
    guest(f": > {shlex.quote(document)}")
    launch = [
        "systemd-run", "--user", f"--unit={unit}", "--collect",
        "--property=Type=exec", f"--setenv={backend}",
        *([f"--setenv=GTK_IM_MODULE={gtk_module}"]
          if gtk_module != "unset" else []),
        *(["/usr/bin/env", "-u", "GTK_IM_MODULE"] if gtk_module == "unset" else []),
        *command,
        document,
    ]
    try:
        session_command(shlex.join(launch))
        before = wait_app(app, Path(document).name, "")
        qmp.keys(("x", "backspace"))
        wait_app(app, Path(document).name, "")
        selected = session_command("fcitx5-remote -o; "
                                   "fcitx5-remote -s chichi77-keykey-bopomofo; "
                                   "fcitx5-remote -n")
        diagnostic = inspect_app(unit, app, Path(document).name)
        if not selected or selected.splitlines()[-1] != "chichi77-keykey-bopomofo":
            raise RuntimeError(f"KeyKey not active in {app}/{mode}: "
                               f"engine={selected!r}, diagnostic={diagnostic!r}")
        qmp.keys(("5", "j", "slash", "spc", "1"))
        positive = wait_app(app, Path(document).name, "中")
        selected = session_command("fcitx5-remote -s keyboard-us; fcitx5-remote -n")
        if not selected or selected.splitlines()[-1] != "keyboard-us":
            raise RuntimeError(f"keyboard-us not active in {app}/{mode}: {selected}")
        qmp.keys(("ctrl-a", "backspace", "5", "j", "slash", "spc", "1"))
        negative = wait_app(app, Path(document).name, "5j/ 1")
        print(f"{app}/{mode}: 中 + keyboard-us literal control", flush=True)
        return {"app": app, "toolkit": toolkit, "mode": mode, "status": "passed",
                "initial": before, "positive": positive, "negative": negative,
                "diagnostic": diagnostic}
    finally:
        session_command(f"systemctl --user stop {shlex.quote(unit)}.service || true")
        guest(f"rm -f -- {shlex.quote(document)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", action="append", choices=APPS)
    parser.add_argument("--mode", action="append", choices=MODES)
    args = parser.parse_args()
    apps = args.app or list(APPS)
    modes = args.mode or list(MODES)
    evidence = {"environment": VM["check_guest"](), "results": []}
    evidence["guest_packages"] = guest(
        "dpkg-query -W -f='${binary:Package}=${Version}\\n' "
        "gedit gnome-text-editor libgtk-4-1 fcitx5-frontend-gtk4")
    original_engine = session_command("fcitx5-remote -n")
    original_state = session_command("fcitx5-remote; true")
    prior_config = VM["read_config"]()
    original_accessibility = session_command(
        "gsettings get org.gnome.desktop.interface toolkit-accessibility")
    desktop_settings = VM["prepare_desktop"]()
    try:
        session_command("gsettings set org.gnome.desktop.interface "
                        "toolkit-accessibility true")
        VM["apply_config"](VM["CASES"]["T01-standard"])
        with Qmp() as qmp:
            for app in apps:
                for mode in modes:
                    try:
                        evidence["results"].append(run_app(qmp, app, mode))
                    except Exception as error:
                        evidence["results"].append({
                            "app": app, "mode": mode, "status": "failed",
                            "error": str(error),
                        })
                        print(f"{app}/{mode}: failed: {error}", file=sys.stderr,
                              flush=True)
            failures = [result for result in evidence["results"]
                        if result["status"] == "failed"]
            if failures:
                raise RuntimeError(f"{len(failures)} real App case(s) failed")
    except Exception as error:
        evidence["failure"] = str(error)
        raise
    finally:
        restore_errors = []
        for name, action in (
            ("config", lambda: VM["restore_config"](prior_config)),
            ("engine", lambda: VM["restore_engine"](original_engine,
                                                      original_state)),
            ("accessibility", lambda: session_command(
                "gsettings set org.gnome.desktop.interface toolkit-accessibility "
                + shlex.quote(original_accessibility))),
            ("desktop", lambda: VM["restore_desktop"](desktop_settings)),
        ):
            try:
                action()
            except Exception as error:
                restore_errors.append(f"{name}: {error}")
        if restore_errors:
            evidence["restore_errors"] = restore_errors
        report = json.dumps(evidence, ensure_ascii=False, indent=2) + "\n"
        path = VM_DIR / "gnome-real-app-last.json"
        path.write_text(report)
        timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
        (VM_DIR / f"gnome-real-app-{timestamp}.json").write_text(report)
        if restore_errors:
            raise RuntimeError("Failed to restore guest state: " + "; ".join(restore_errors))
    print(f"Passed {len(evidence['results'])} real App cases; {path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
