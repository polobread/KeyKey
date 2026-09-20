#!/usr/bin/env python3
"""Verify candidate placement after moving a live client to a second GNOME monitor."""

import argparse
import datetime
import json
import runpy
import shlex
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent
VM = runpy.run_path(str(ROOT / "gnome-vm-wayland-smoke.py"))
POPUP = runpy.run_path(str(ROOT / "gnome-vm-popup-smoke.py"))
MULTI = runpy.run_path(str(ROOT / "gnome-vm-multi-app-smoke.py"))
VM_DIR = VM["VM_DIR"]
MODES = VM["MODES"]
guest = VM["guest"]
session_command = VM["session_command"]


def display_layout(layout):
    source = (ROOT / "gnome-vm-displays.py").read_text()
    result = subprocess.run(VM["SSH"] + ["/usr/bin/python3", "-", layout],
                            input=source, text=True, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(f"GNOME display {layout}: {result.stderr}{result.stdout}")
    return json.loads(result.stdout)


def moved_window_bounds(before, moved):
    width, height, previous = VM["read_ppm"](before)
    new_width, new_height, current = VM["read_ppm"](moved)
    if (width, height) != (new_width, new_height):
        raise RuntimeError("Second monitor resolution changed during window move")
    rows = []
    for y in range(height):
        changed = []
        for x in range(width):
            offset = (y * width + x) * 3
            if sum(abs(previous[offset + channel] - current[offset + channel])
                   for channel in range(3)) > 60:
                changed.append(x)
        if len(changed) >= 100:
            rows.append((y, min(changed), max(changed)))
    if len(rows) < 60:
        raise RuntimeError("Client window did not move to the second monitor")
    return min(row[1] for row in rows), rows[0][0], \
        max(row[2] for row in rows) + 1, rows[-1][0] + 1


def gtk4_preedit_bounds(screenshot, window):
    width, _, pixels = VM["read_ppm"](screenshot)
    points = []
    for y in range(window[1], window[3]):
        for x in range(window[0], window[2]):
            offset = (y * width + x) * 3
            red, green, blue = pixels[offset:offset + 3]
            if 70 < red < 220 and green > red + 25 and blue > red + 35:
                points.append((x, y))
    if len(points) < 10:
        return None
    return min(x for x, _ in points), min(y for _, y in points), \
        max(x for x, _ in points) + 1, max(y for _, y in points) + 1


def run_mode(qmp, mode_name, layout):
    mode = MODES[mode_name]
    case_dir = f"/tmp/keykey-gnome-multimonitor/{layout}/{mode_name}"
    unit = f"keykey-dual-{layout}-{mode_name}-{int(time.time())}"
    stem = f"multimonitor-{layout}-{mode_name}"
    try:
        MULTI["start_host"](mode, unit, case_dir)
        MULTI["select_engine"]("chichi77-keykey-bopomofo")
        first_before = VM_DIR / f"{stem}-first-before.ppm"
        second_before = VM_DIR / f"{stem}-second-before.ppm"
        qmp.screenshot(first_before)
        qmp.screenshot(second_before, head=1)
        qmp.keys(("meta_l-shift-right",))
        time.sleep(1.0)
        first_moved = VM_DIR / f"{stem}-first-moved.ppm"
        second_moved = VM_DIR / f"{stem}-second-moved.ppm"
        qmp.screenshot(first_moved)
        qmp.screenshot(second_moved, head=1)
        window = moved_window_bounds(second_before, second_moved)
        second_size = VM["read_ppm"](second_moved)[:2]
        if window[1] > second_size[1] // 2:
            raise RuntimeError(f"Window landed outside the upper display test area: "
                               f"{window} on {second_size}")
        entry = None if mode.host == "gtk4" else POPUP["focused_entry_bounds"](
            second_moved)
        qmp.keys(("5", "j", "slash", "spc"))
        candidate = VM_DIR / f"{stem}-second-candidate.ppm"
        first_candidate = VM_DIR / f"{stem}-first-candidate.ppm"
        errors = []
        bounds = None
        first_bounds = None
        for _ in range(4):
            time.sleep(0.5)
            qmp.screenshot(candidate, head=1)
            qmp.screenshot(first_candidate)
            try:
                bounds, _ = VM["find_candidate_popup"](second_moved, candidate)
                break
            except RuntimeError:
                try:
                    first_bounds, _ = VM["find_candidate_popup"](
                        first_moved, first_candidate)
                    break
                except RuntimeError:
                    pass
        size = VM["read_ppm"](candidate)[:2]
        preedit = gtk4_preedit_bounds(candidate, window) if mode.host == "gtk4" else None
        if not bounds:
            errors.append(f"Candidate appeared on the first monitor: {first_bounds}"
                          if first_bounds else "Candidate is not visible on either monitor")
        if bounds:
            left, top, right, bottom = bounds
            if left <= 0 or top <= 0 or right >= size[0] or bottom >= size[1]:
                errors.append("Candidate touches or crosses the second monitor edge")
            if right < window[0] - 60 or left > window[2] + 60 or \
                    top > window[3] + 60 or bottom < window[1] - 300:
                errors.append("Candidate is detached from the second-monitor client")
            if (entry and abs(left - entry[0]) > 75) or \
                    (preedit and abs(left - preedit[0]) > 75) or \
                    (not entry and not preedit and left > window[0] + 90):
                errors.append("Candidate is detached from this test host's input caret")
            if entry and min(right, entry[2]) - max(left, entry[0]) > 5 and \
                    min(bottom, entry[3]) - max(top, entry[1]) > 5:
                errors.append("Candidate covers the focused input field")
        qmp.keys(("1",))
        MULTI["wait_event"](case_dir, "text", "中")
        MULTI["select_engine"]("keyboard-us")
        qmp.keys(("ctrl-a", "backspace", "5", "j", "slash", "spc", "1"))
        MULTI["wait_event"](case_dir, "text", "5j/ 1")
        guest(f"touch {shlex.quote(case_dir + '/close-now')}")
        VM["wait_file"](case_dir, "final.txt")
        result = {"layout": layout, "mode": mode_name,
                  "status": "failed" if errors else "passed", "errors": errors,
                  "window_bounds": window, "entry_bounds": entry,
                  "preedit_bounds": preedit,
                  "candidate_bounds": bounds,
                  "second_resolution": size,
                  "first_before": str(first_before), "first_moved": str(first_moved),
                  "first_candidate": str(first_candidate),
                  "second_before": str(second_before), "second_moved": str(second_moved),
                  "second_candidate": str(candidate)}
        print(f"{layout}/{mode_name}: {result['status']} "
              f"window={window} candidate={bounds} {errors}", flush=True)
        return result
    finally:
        session_command(f"systemctl --user stop {shlex.quote(unit)}.service || true")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", action="append", choices=MODES)
    parser.add_argument("--layout", action="append", choices=("dual", "dual-mixed"))
    args = parser.parse_args()
    modes = args.mode or list(MODES)
    layouts = args.layout or ("dual", "dual-mixed")
    evidence = {"environment": VM["check_guest"](), "results": [],
                "kimpanel_bus_owner": session_command(
                    "gdbus call --session --dest org.freedesktop.DBus "
                    "--object-path /org/freedesktop/DBus "
                    "--method org.freedesktop.DBus.NameHasOwner org.kde.impanel")}
    state = display_layout("show")
    if "Virtual-2" not in state["monitors"]:
        raise RuntimeError("GNOME does not see Virtual-2; connect the second "
                           "DRM output and restart GDM as described in the VM guide")
    evidence["original_displays"] = state
    original_layout = ("single" if len(state["logical"]) == 1 else
                       "dual-mixed" if state["logical"][1]["scale"] == 2.0 else
                       "dual")
    original_engine = session_command("fcitx5-remote -n")
    original_state = session_command("fcitx5-remote; true")
    prior_config = VM["read_config"]()
    desktop_settings = VM["prepare_desktop"]()
    try:
        VM["apply_config"](VM["CASES"]["T01-standard"])
        with VM["Qmp"]() as qmp:
            for layout in layouts:
                evidence.setdefault("layouts", []).append(display_layout(layout))
                for mode in modes:
                    try:
                        evidence["results"].append(run_mode(qmp, mode, layout))
                    except Exception as error:
                        evidence["results"].append({"layout": layout, "mode": mode,
                                                    "status": "failed", "error": str(error)})
                        print(f"{layout}/{mode}: failed: {error}", file=sys.stderr,
                              flush=True)
                        VM["check_guest"]()
        failures = [item for item in evidence["results"] if item["status"] == "failed"]
        if failures:
            raise RuntimeError(f"{len(failures)} multi-monitor case(s) failed")
    except Exception as error:
        evidence["failure"] = str(error)
        raise
    finally:
        errors = []
        for name, action in (("config", lambda: VM["restore_config"](prior_config)),
                             ("engine", lambda: VM["restore_engine"](
                                 original_engine, original_state)),
                             ("desktop", lambda: VM["restore_desktop"](desktop_settings)),
                             ("displays", lambda: display_layout(original_layout))):
            try:
                action()
            except Exception as error:
                errors.append(f"{name}: {error}")
        if errors:
            evidence["restore_errors"] = errors
        path = VM_DIR / "gnome-multimonitor-last.json"
        path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
        (VM_DIR / f"gnome-multimonitor-{stamp}.json").write_text(
            json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
        if errors:
            raise RuntimeError("Failed to restore guest state: " + "; ".join(errors))
    print(f"Passed {len(evidence['results'])} multi-monitor cases; {path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
