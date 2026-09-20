#!/usr/bin/env python3
"""Verify pointer replacement, password input, and read-only fields in the GNOME VM."""

import argparse
import datetime
import json
import runpy
import shlex
import sys
import time
from pathlib import Path


FOCUS = runpy.run_path(str(Path(__file__).with_name("gnome-vm-focus-smoke.py")))
VM = FOCUS["VM"]
VM_DIR = VM["VM_DIR"]
HOST_DIR = VM["HOST_DIR"]
MODES = VM["MODES"]
guest = VM["guest"]
session_command = VM["session_command"]
Qmp = VM["Qmp"]
VncPointer = VM["VncPointer"]
read_center = FOCUS["read_center"]
click_field = FOCUS["click_field"]
find_fields = FOCUS["find_fields"]
window_origin = FOCUS["window_origin"]
gtk4_window_origin = FOCUS["gtk4_window_origin"]
select_engine = FOCUS["select_engine"]


def wait_selection(case_dir, expected):
    observed = ""
    for _ in range(50):
        try:
            observed = guest(f"cat {case_dir}/first-selection-state.txt")
        except RuntimeError:
            pass
        if observed == expected:
            return
        time.sleep(0.2)
    raise RuntimeError(f"Pointer state {observed!r}, expected {expected!r}")


def read_point(case_dir, filename):
    x, y = map(int, guest(f"cat {case_dir}/{filename}").split())
    return x, y


def gtk4_content_origin(screenshot, title_origin):
    width, height, pixels = VM["read_ppm"](screenshot)
    left, top = title_origin
    probe_x = left + 25
    for y in range(top + 25, min(top + 70, height)):
        offset = (y * width + probe_x) * 3
        red, green, blue = pixels[offset:offset + 3]
        if min(red, green, blue) >= 240 and max(red, green, blue) - min(red, green, blue) < 5:
            for x in range(left, max(left - 15, 0), -1):
                edge = (y * width + x) * 3
                if pixels[edge] < 180:
                    return x, y
    raise RuntimeError(f"Could not locate GTK4 content edge in {screenshot}")


def run_stage(qmp, mode_name, phase):
    mode = MODES[mode_name]
    positive = phase != "negative"
    extended = phase == "extended"
    first = ("甲中中丙" if extended else "甲中丙") if positive else "甲5j/ 1丙"
    second = "rup 1!"
    third = "唯讀"
    case_dir = f"/tmp/keykey-gnome-editing/{mode_name}/{phase}"
    unit = f"keykey-edit-{mode_name}-{phase}-{int(time.time())}"
    required = "first-selection=1:2;"
    if extended:
        required += "first-text=甲中丙;first-preedit=ㄓ;first-text=甲中中丙;"
    else:
        required += f"first-text={first};"
    required += f"second-text={second};third-focus=in;third-key-press=1"
    artifacts = ("final.txt", "events.jsonl", "host-events.log",
                 "first-center.txt", "second-center.txt", "third-center.txt",
                 "first-selection-start.txt", "first-selection-end.txt",
                 "first-selection-state.txt")
    guest(f"mkdir -p {shlex.quote(case_dir)} && rm -f -- " +
          " ".join(shlex.quote(f"{case_dir}/{name}") for name in artifacts))
    launch = [
        "systemd-run", "--user", f"--unit={unit}", "--collect",
        "--property=Type=exec", f"--setenv={mode.backend}",
        *(["--setenv=GTK_IM_MODULE=fcitx"] if mode.gtk_module == "fcitx" else []),
        f"--setenv=KEYKEY_E2E_CASE_DIR={case_dir}",
        "--setenv=KEYKEY_E2E_SCENARIO=editing",
        f"--setenv=KEYKEY_E2E_WINDOW_TITLE={unit}",
        f"--setenv=KEYKEY_E2E_EXPECTED_FIRST={first}",
        f"--setenv=KEYKEY_E2E_EXPECTED_SECOND={second}",
        f"--setenv=KEYKEY_E2E_EXPECTED_THIRD={third}",
        f"--setenv=KEYKEY_E2E_REQUIRED_EVENTS={required}",
        *(["/usr/bin/env", "-u", "GTK_IM_MODULE"]
          if mode.gtk_module == "unset" else []),
        f"{HOST_DIR}/keykey_linux_{mode.host}_e2e_host",
    ]
    try:
        session_command(shlex.join(launch))
        for file in ("first-center.txt", "second-center.txt", "third-center.txt",
                     "first-selection-start.txt", "first-selection-end.txt"):
            VM["wait_file"](case_dir, file)
        time.sleep(1.5)
        screenshot = VM_DIR / f"editing-{mode_name}-{phase}-before.ppm"
        qmp.screenshot(screenshot)
        centers = [read_center(case_dir, name)
                   for name in ("first", "second", "third")]
        if mode.host == "gtk4":
            origin = gtk4_window_origin(screenshot)
            coordinate_source = "GTK4 title bar"
            if mode.backend == "GDK_BACKEND=x11":
                origin = gtk4_content_origin(screenshot, origin)
                coordinate_source = "GTK4 X11 content edge"
        else:
            fields, accessible = find_fields(unit, 1)
            field_offset = window_origin(screenshot, fields[0])
            first_screen_center = (
                field_offset[0] + fields[0]["x"] + fields[0]["width"] // 2,
                field_offset[1] + fields[0]["y"] + fields[0]["height"] // 2,
            )
            origin = (first_screen_center[0] - centers[0][0],
                      first_screen_center[1] - centers[0][1])
            coordinate_source = accessible["app"]
        print(f"{mode_name}/{phase}: origin={origin} centers={centers}", flush=True)
        select_engine("chichi77-keykey-bopomofo" if positive else "keyboard-us")
        start = read_point(case_dir, "first-selection-start.txt")
        end = read_point(case_dir, "first-selection-end.txt")
        start_screen = (origin[0] + start[0], origin[1] + start[1])
        end_screen = (origin[0] + end[0], origin[1] + end[1])
        with VncPointer() as pointer:
            # GtkEntry may select all three characters on its initial focus.
            # Clear that selection with a single click in the empty part of
            # the field before measuring the actual pointer drag.
            click_field(qmp, pointer, centers[0], origin)
            wait_selection(case_dir, "cursor:3")
            pointer.drag(qmp, start_screen, end_screen)
            wait_selection(case_dir, "1:2")
            qmp.keys(("5", "j", "slash", "spc", "1"))
            if extended:
                qmp.keys(("home", "right", "5", "j", "left", "right",
                          "home", "end", "pgup", "pgdn", "delete", "tab", "shift-left",
                          "shift-right", "shift-tab", "slash", "spc", "1"))
            second_click = click_field(qmp, pointer, centers[1], origin)
            qmp.keys(("r", "u", "p", "spc", "1", "shift-1"))
            third_click = click_field(qmp, pointer, centers[2], origin)
            qmp.keys(("1",))
        VM["wait_file"](case_dir, "final.txt")
        final = guest(f"cat {case_dir}/final.txt")
        expected = f"{first}\t{second}\t{third}"
        if final != expected:
            raise RuntimeError(f"Unexpected editing fields: {final!r}, expected {expected!r}")
        events = guest(f"cat {case_dir}/host-events.log")
        if "result=passed" not in events:
            raise RuntimeError(f"Host did not pass {mode_name}/{phase}: {events}")
        if any(line.startswith(("second-preedit=", "third-preedit="))
               for line in events.splitlines()):
            raise RuntimeError(f"Sensitive or read-only field received preedit: {events}")
        print(f"{mode_name}/{phase}: {first}|{second}|{third}", flush=True)
        return {"mode": mode_name, "phase": phase, "status": "passed",
                "origin": origin, "coordinate_source": coordinate_source,
                "drag": [start_screen, end_screen],
                "second_click": second_click, "third_click": third_click,
                "events": events.splitlines()}
    finally:
        session_command(f"systemctl --user stop {shlex.quote(unit)}.service || true")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", action="append", choices=MODES)
    parser.add_argument("--phase", action="append",
                        choices=("positive", "negative", "extended"))
    args = parser.parse_args()
    modes = args.mode or list(MODES)
    phases = args.phase or ("positive", "negative")
    evidence = {"environment": VM["check_guest"](),
                "candidate_panel": VM["candidate_panel_state"](), "results": []}
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
                        try:
                            VM["check_guest"]()
                        except Exception as session_error:
                            raise RuntimeError(
                                f"GNOME session ended during {mode}/{phase}: "
                                f"{session_error}") from error
        failures = [item for item in evidence["results"]
                    if item["status"] == "failed"]
        if failures:
            raise RuntimeError(f"{len(failures)} editing case(s) failed")
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
        path = VM_DIR / "gnome-editing-last.json"
        path.write_text(report)
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
        (VM_DIR / f"gnome-editing-{stamp}.json").write_text(report)
        if restore_errors:
            raise RuntimeError("Failed to restore guest state: " + "; ".join(restore_errors))
    print(f"Passed {len(evidence['results'])} editing phases; {path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
