#!/usr/bin/env python3
"""Check two live input contexts in GNOME Wayland and XWayland VM clients."""

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
VncPointer = VM["VncPointer"]
read_ppm = VM["read_ppm"]
MODES = VM["MODES"]
HOST_DIR = VM["HOST_DIR"]

FOCUS_EVENTS = (
    "first-preedit=ㄓ;first-preedit=ㄓㄨ;first-preedit=ㄓㄨㄥ;"
    "first-preedit=;second-preedit=ㄨ;second-preedit=ㄨㄣ;"
    "second-preedit=ㄨㄣˊ;second-text=文;first-preedit=ㄓ;"
    "first-preedit=ㄓㄨ;first-preedit=ㄓㄨㄥ"
)
AT_SPI_FIELDS = r'''
import gi
import json
import sys
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi

def fields(node, depth=0):
    if depth > 20 or node.get_child_count() > 50:
        return []
    found = []
    if node.get_role_name() in ("text", "entry"):
        rect = Atspi.Component.get_extents(node, Atspi.CoordType.SCREEN)
        if rect.width > 30 and rect.height > 10:
            found.append({"role": node.get_role_name(), "name": node.get_name(),
                          "x": rect.x, "y": rect.y,
                          "width": rect.width, "height": rect.height})
    for index in range(node.get_child_count()):
        found.extend(fields(node.get_child_at_index(index), depth + 1))
    return found

desktop = Atspi.get_desktop(0)
for index in range(desktop.get_child_count()):
    app = desktop.get_child_at_index(index)
    for window_index in range(app.get_child_count()):
        window = app.get_child_at_index(window_index)
        if sys.argv[1] == window.get_name():
            text_fields = fields(window)
            if len(text_fields) != 2:
                continue
            rect = Atspi.Component.get_extents(window, Atspi.CoordType.SCREEN)
            print(json.dumps({"app": app.get_name(), "window": window.get_name(),
                              "window_bounds": [rect.x, rect.y, rect.width, rect.height],
                              "fields": text_fields}, ensure_ascii=False))
            sys.exit(0)
sys.exit(2)
'''


def find_fields(title):
    command = ("DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
               "/usr/bin/python3 -c " + shlex.quote(AT_SPI_FIELDS) + " "
               + shlex.quote(title))
    last = None
    for _ in range(50):
        try:
            last = json.loads(guest(command))
            fields = sorted(last["fields"], key=lambda item: item["y"])
            if len(fields) == 2:
                return fields, last
        except RuntimeError:
            pass
        time.sleep(0.2)
    raise RuntimeError(f"Could not identify two text fields for {title}: {last}")


def select_engine(name):
    selected = session_command("fcitx5-remote -o; "
                               f"fcitx5-remote -s {shlex.quote(name)}; "
                               "fcitx5-remote -n")
    if not selected or selected.splitlines()[-1] != name:
        raise RuntimeError(f"Engine {name} not active: {selected!r}")


def window_origin(screenshot, first_field):
    width, height, pixels = read_ppm(screenshot)
    best = (0, 0, 0)
    for y in range(30, min(height, 600)):
        start = None
        for x in range(50, width - 50):
            offset = (y * width + x) * 3
            red, green, blue = pixels[offset:offset + 3]
            blue_border = blue > red + 40 and blue > green + 15 and blue > 100
            if blue_border and start is None:
                start = x
            if not blue_border and start is not None:
                if x - start > best[0]:
                    best = (x - start, start, y)
                start = None
    run_length, left, top = best
    if run_length < first_field["width"] * 0.6:
        raise RuntimeError(f"Could not locate focused field in {screenshot}: {best}")
    return left - first_field["x"], top - first_field["y"]


def gtk4_window_origin(screenshot):
    width, height, pixels = read_ppm(screenshot)
    for y in range(40, min(height, 350)):
        matches = []
        for x in range(50, width - 50):
            offset = (y * width + x) * 3
            red, green, blue = pixels[offset:offset + 3]
            if (215 <= red <= 225 and 212 <= green <= 222 and
                    208 <= blue <= 220 and abs(red - green - 3) < 4):
                matches.append(x)
        if len(matches) > 400 and max(matches) - min(matches) > 600:
            top = y
            row = top + 2
            matches = []
            for x in range(50, width - 50):
                offset = (row * width + x) * 3
                red, green, blue = pixels[offset:offset + 3]
                if (215 <= red <= 225 and 212 <= green <= 222 and
                        208 <= blue <= 220 and abs(red - green - 3) < 4):
                    matches.append(x)
            if matches:
                return min(matches), top
    raise RuntimeError(f"Could not locate GTK4 title bar in {screenshot}")


def read_center(case_dir, field):
    x, y = map(int, guest(f"cat {case_dir}/{field}-center.txt").split())
    return x, y


def click_field(qmp, pointer, center, origin):
    x = origin[0] + center[0]
    y = origin[1] + center[1]
    qmp.move_pointer(x, y, pointer.width, pointer.height)
    time.sleep(0.15)
    pointer.click(x, y)
    return [x, y]


def run_stage(qmp, mode_name, phase):
    mode = MODES[mode_name]
    case_dir = f"/tmp/keykey-gnome-focus/{mode_name}/{phase}"
    unit = f"keykey-focus-{mode_name}-{phase}-{int(time.time())}"
    title = unit
    positive = phase == "positive"
    raw_on_blur = positive and (mode.gtk_module == "fcitx" or mode.host == "qt6")
    first, second = (("ㄓㄨㄥ中" if raw_on_blur else "中"), "文") \
        if positive else ("5j/ 1", "jp61")
    guest(f"mkdir -p {case_dir}; rm -f {case_dir}/{{final.txt,events.jsonl,host-events.log}}")
    launch = [
        "systemd-run", "--user", f"--unit={unit}", "--collect",
        "--property=Type=exec", f"--setenv={mode.backend}",
        *(["--setenv=GTK_IM_MODULE=fcitx"] if mode.gtk_module == "fcitx" else []),
        f"--setenv=KEYKEY_E2E_CASE_DIR={case_dir}",
        "--setenv=KEYKEY_E2E_SCENARIO=focus",
        f"--setenv=KEYKEY_E2E_WINDOW_TITLE={title}",
        f"--setenv=KEYKEY_E2E_EXPECTED_FIRST={first}",
        f"--setenv=KEYKEY_E2E_EXPECTED_SECOND={second}",
        f"--setenv=KEYKEY_E2E_REQUIRED_EVENTS={FOCUS_EVENTS if positive else ''}",
        *(["/usr/bin/env", "-u", "GTK_IM_MODULE"]
          if mode.gtk_module == "unset" else []),
        f"{HOST_DIR}/keykey_linux_{mode.host}_e2e_host",
    ]
    try:
        session_command(shlex.join(launch))
        screenshot = VM_DIR / f"focus-{mode_name}-{phase}-before.ppm"
        VM["wait_file"](case_dir, "first-center.txt")
        VM["wait_file"](case_dir, "second-center.txt")
        time.sleep(1.5)
        qmp.screenshot(screenshot)
        centers = [read_center(case_dir, name) for name in ("first", "second")]
        if mode.host == "gtk4":
            accessible = {"window": title, "fields": [],
                          "coordinate_source": "GTK4 title bar and host centers"}
            origin = gtk4_window_origin(screenshot)
        else:
            fields, accessible = find_fields(title)
            field_offset = window_origin(screenshot, fields[0])
            first_screen_center = (
                field_offset[0] + fields[0]["x"] + fields[0]["width"] // 2,
                field_offset[1] + fields[0]["y"] + fields[0]["height"] // 2,
            )
            origin = (first_screen_center[0] - centers[0][0],
                      first_screen_center[1] - centers[0][1])
        print(f"{mode_name}/{phase}: origin={origin} centers={centers} "
              f"window={accessible.get('window_bounds')}", flush=True)
        select_engine("chichi77-keykey-bopomofo" if positive else "keyboard-us")
        with VncPointer() as pointer:
            if positive:
                qmp.keys(("5", "j", "slash", "spc"))
                second_click = click_field(qmp, pointer, centers[1], origin)
                select_engine("chichi77-keykey-bopomofo")
                qmp.keys(("j", "p", "6", "1"))
                first_click = click_field(qmp, pointer, centers[0], origin)
                select_engine("chichi77-keykey-bopomofo")
                qmp.keys(("5", "j", "slash", "spc", "1"))
            else:
                qmp.keys(("5", "j", "slash", "spc", "1"))
                second_click = click_field(qmp, pointer, centers[1], origin)
                select_engine("keyboard-us")
                qmp.keys(("j", "p", "6", "1"))
                first_click = None
        VM["wait_file"](case_dir, "final.txt")
        final = guest(f"cat {case_dir}/final.txt")
        if final != f"{first}\t{second}":
            raise RuntimeError(f"Unexpected field text in {mode_name}/{phase}: {final!r}")
        events = guest(f"cat {case_dir}/host-events.log")
        if "result=passed" not in events:
            raise RuntimeError(f"Host did not pass {mode_name}/{phase}: {events}")
        if positive and ("first-text=ㄓㄨㄥ\n" in events) != raw_on_blur:
            raise RuntimeError(f"Unexpected focus-out preedit commit in "
                               f"{mode_name}/{phase}: {events}")
        print(f"{mode_name}/{phase}: {first}|{second}", flush=True)
        return {"mode": mode_name, "phase": phase, "status": "passed",
                "accessibility": accessible, "second_click": second_click,
                "first_click": first_click, "events": events.splitlines(),
                "raw_preedit_on_blur": raw_on_blur}
    finally:
        session_command(f"systemctl --user stop {shlex.quote(unit)}.service || true")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", action="append", choices=MODES)
    parser.add_argument("--phase", action="append", choices=("positive", "negative"))
    args = parser.parse_args()
    modes = args.mode or list(MODES)
    phases = args.phase or ("positive", "negative")
    evidence = {"environment": VM["check_guest"](), "results": []}
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
            for mode in modes:
                for phase in phases:
                    try:
                        evidence["results"].append(run_stage(qmp, mode, phase))
                    except Exception as error:
                        evidence["results"].append({"mode": mode, "phase": phase,
                                                    "status": "failed",
                                                    "error": str(error)})
                        print(f"{mode}/{phase}: failed: {error}",
                              file=sys.stderr, flush=True)
        failures = [item for item in evidence["results"]
                    if item["status"] == "failed"]
        if failures:
            raise RuntimeError(f"{len(failures)} focus case(s) failed")
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
        path = VM_DIR / "gnome-focus-last.json"
        path.write_text(report)
        timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
        (VM_DIR / f"gnome-focus-{timestamp}.json").write_text(report)
        if restore_errors:
            raise RuntimeError("Failed to restore guest state: " + "; ".join(restore_errors))
    print(f"Passed {len(evidence['results'])} focus phases; {path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
