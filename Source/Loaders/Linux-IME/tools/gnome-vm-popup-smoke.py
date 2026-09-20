#!/usr/bin/env python3
"""Check GNOME Wayland candidate geometry at desktop edges and on two displays."""

import argparse
import datetime
import json
import runpy
import shlex
import sys
import time
from pathlib import Path


VM = runpy.run_path(str(Path(__file__).with_name("gnome-vm-wayland-smoke.py")))
MULTI = runpy.run_path(str(Path(__file__).with_name("gnome-vm-multi-app-smoke.py")))
VM_DIR = VM["VM_DIR"]
MODES = VM["MODES"]
guest = VM["guest"]
session_command = VM["session_command"]
Qmp = VM["Qmp"]
VncPointer = VM["VncPointer"]
read_ppm = VM["read_ppm"]


def focused_entry_bounds(screenshot):
    width, height, pixels = read_ppm(screenshot)
    runs = []
    for y in range(30, height - 25):
        start = None
        for x in range(65, width - 10):
            offset = (y * width + x) * 3
            red, green, blue = pixels[offset:offset + 3]
            accent = red < 100 and green > 80 and blue > 140 and blue > green + 30
            if accent and start is None:
                start = x
            elif not accent and start is not None:
                if x - start >= 250:
                    runs.append((start, y, x))
                start = None
        if start is not None and width - 10 - start >= 250:
            runs.append((start, y, width - 10))
    if not runs:
        raise RuntimeError(f"No focused entry border found in {screenshot}")
    widest = max(runs, key=lambda run: run[2] - run[0])
    same_entry = [run for run in runs if abs(run[0] - widest[0]) <= 3
                  and abs(run[2] - widest[2]) <= 3]
    return widest[0], min(run[1] for run in same_entry), widest[2], \
        max(run[1] for run in same_entry) + 1


def visible_window_bounds(screenshot):
    width, height, pixels = read_ppm(screenshot)
    runs = []
    for y in range(30, height - 10):
        start = None
        for x in range(65, width - 10):
            offset = (y * width + x) * 3
            red, green, blue = pixels[offset:offset + 3]
            light = min(red, green, blue) > 190 and \
                max(red, green, blue) - min(red, green, blue) < 45
            if light and start is None:
                start = x
            elif not light and start is not None:
                if 400 <= x - start <= 700:
                    runs.append((start, y, x))
                start = None
        if start is not None and 400 <= width - 10 - start <= 700:
            runs.append((start, y, width - 10))
    if not runs:
        raise RuntimeError(f"No test client window found in {screenshot}")
    reference = max(runs, key=lambda row: sum(
        abs(other[0] - row[0]) <= 4 and abs(other[2] - row[2]) <= 4
        for other in runs))
    matching = [row for row in runs if abs(row[0] - reference[0]) <= 4
                and abs(row[2] - reference[2]) <= 4]
    return min(row[0] for row in matching), min(row[1] for row in matching), \
        max(row[2] for row in matching), max(row[1] for row in matching) + 1


def run_position(qmp, mode_name, position, mouse):
    mode = MODES[mode_name]
    case_dir = f"/tmp/keykey-gnome-popup/{mode_name}/{position}"
    unit = f"keykey-popup-{mode_name}-{position}-{int(time.time())}"
    try:
        MULTI["start_host"](mode, unit, case_dir)
        prefix = ""
        if position.endswith("right"):
            MULTI["select_engine"]("keyboard-us")
            for _ in range(60):
                qmp.call("human-monitor-command", {"command-line": "sendkey x"})
                time.sleep(0.03)
            time.sleep(0.2)
            events = MULTI["host_events"](case_dir)
            texts = [event["value"] for event in events if event["type"] == "text"]
            prefix = texts[-1] if texts else ""
            if len(prefix) < 30 or set(prefix) != {"x"}:
                raise RuntimeError(f"Right-edge caret prefix was not typed: {prefix!r}")
        MULTI["select_engine"]("chichi77-keykey-bopomofo")
        with VncPointer() as pointer:
            size = (pointer.width, pointer.height)
            before = VM_DIR / f"popup-{mode_name}-{position}-before.ppm"
            moved = VM_DIR / f"popup-{mode_name}-{position}-moved.ppm"
            qmp.screenshot(before)
            left, top, right, bottom = visible_window_bounds(before)
            target_left = 75 if position.endswith("left") else pointer.width - (right - left) - 8
            target_top = 32 if position.startswith("top") else pointer.height - (bottom - top) - 30
            start = ((left + right) // 2, top + 18)
            end = (start[0] + target_left - left, start[1] + target_top - top)
            if mode.backend in ("GDK_BACKEND=x11", "QT_QPA_PLATFORM=xcb"):
                qmp.move_pointer(*start, *size)
                time.sleep(0.1)
                qmp.keys(("alt-f7",))
                qmp.move_pointer(*end, *size)
                time.sleep(0.3)
                qmp.keys(("ret",))
            else:
                pointer.drag(qmp, start, end)
            time.sleep(0.5)
            qmp.screenshot(moved)
            moved_window = visible_window_bounds(moved)
            moved_entry = None if mode.host == "gtk4" else focused_entry_bounds(moved)
            reached_vertical_edge = (abs(moved_window[1] - target_top) <= 35
                                     if position.startswith("top") else
                                     moved_window[3] >= pointer.height - 100)
            if abs(moved_window[0] - target_left) > 35 or not reached_vertical_edge:
                raise RuntimeError(f"Window did not reach {position}: {moved_window}, "
                                   f"target=({target_left}, {target_top})")
            if mode.backend in ("GDK_BACKEND=x11", "QT_QPA_PLATFORM=xcb"):
                field_x = moved_window[2] - 18 if prefix else moved_window[0] + 35
                field_y = (moved_entry[1] + moved_entry[3]) // 2 if moved_entry else \
                    moved_window[1] + 75
                pointer.click(field_x, field_y)
                if prefix:
                    qmp.keys(("end",))
                time.sleep(0.2)
                qmp.screenshot(moved)
            qmp.keys(("5", "j", "slash", "spc"))
            time.sleep(0.5)
            candidate = VM_DIR / f"popup-{mode_name}-{position}-candidate.ppm"
            qmp.screenshot(candidate)
            geometry_errors = []
            bounds = None
            try:
                bounds, resolution = VM["find_candidate_popup"](moved, candidate)
            except RuntimeError as error:
                geometry_errors.append(str(error))
                resolution = size
            if bounds:
                popup_left, popup_top, popup_right, popup_bottom = bounds
                if popup_left <= 0 or popup_top <= 0 or \
                        popup_right >= size[0] or popup_bottom >= size[1]:
                    geometry_errors.append("Candidate touches or crosses a screen edge")
                if popup_bottom - popup_top < 200:
                    geometry_errors.append("Nine-row candidate list is vertically clipped")
                if moved_entry and position.endswith("right") and \
                        popup_right < moved_entry[2] - 90:
                    geometry_errors.append("Candidate is detached from the right-edge caret")
                if moved_entry and position.endswith("left") and \
                        popup_left > moved_entry[0] + 90:
                    geometry_errors.append("Candidate is detached from the left-edge caret")
                if position.startswith("top") and moved_entry and \
                        popup_top < moved_entry[3] - 5:
                    geometry_errors.append("Top-edge popup overlaps the input field")
                if position.startswith("bottom") and moved_entry and \
                        popup_bottom > moved_entry[1] + 5:
                    geometry_errors.append("Bottom-edge popup did not flip above the input field")
                if moved_entry and min(popup_right, moved_entry[2]) - \
                        max(popup_left, moved_entry[0]) > 5 and \
                        min(popup_bottom, moved_entry[3]) - \
                        max(popup_top, moved_entry[1]) > 5:
                    geometry_errors.append("Candidate covers the focused input field")
            selected_character = "中"
            click = None
            if mouse and bounds:
                click = ((bounds[0] + bounds[2]) // 2,
                         bounds[1] + (bounds[3] - bounds[1]) // 6)
                qmp.move_pointer(*click, *size)
                time.sleep(0.1)
                pointer.click(*click)
                selected_character = "鐘"
            else:
                qmp.keys(("1",))
            MULTI["wait_event"](case_dir, "text", prefix + selected_character)
            cleared = VM_DIR / f"popup-{mode_name}-{position}-cleared.ppm"
            time.sleep(0.5)
            qmp.screenshot(cleared)
            if bounds:
                candidate_pixels = VM["changed_pixels"](moved, candidate, bounds)
                cleared_pixels = VM["changed_pixels"](candidate, cleared, bounds)
                if candidate_pixels < 100 or cleared_pixels < candidate_pixels * 0.6:
                    geometry_errors.append("Candidate did not clear after selection: "
                                           f"{cleared_pixels}/{candidate_pixels} pixels")
            MULTI["select_engine"]("keyboard-us")
            qmp.keys(("ctrl-a", "backspace", "5", "j", "slash", "spc", "1"))
            MULTI["wait_event"](case_dir, "text", "5j/ 1")
            guest(f"touch {shlex.quote(case_dir + '/close-now')}")
            VM["wait_file"](case_dir, "final.txt")
            result = {"mode": mode_name, "position": position,
                    "status": "failed" if geometry_errors else "passed",
                    "bounds": bounds, "resolution": resolution, "prefix_length": len(prefix),
                    "window_bounds": moved_window, "entry_bounds": moved_entry,
                    "geometry_errors": geometry_errors, "click": click,
                    "moved_screenshot": str(moved), "candidate_screenshot": str(candidate),
                    "cleared_screenshot": str(cleared)}
            print(f"{mode_name}/{position}: {result['status']} "
                  f"entry={moved_entry} popup={bounds} {geometry_errors}", flush=True)
            return result
    finally:
        session_command(f"systemctl --user stop {shlex.quote(unit)}.service || true")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", action="append", choices=MODES)
    parser.add_argument("--position", action="append", choices=(
        "top-left", "top-right", "bottom-left", "bottom-right"))
    parser.add_argument("--mouse", action="store_true",
                        help="Click the second candidate through the VM pointer")
    parser.add_argument("--panel", choices=("kimpanel", "classic-ui"),
                        help="Require the intended candidate panel provider")
    args = parser.parse_args()
    modes = args.mode or list(MODES)
    positions = args.position or ("top-left", "top-right", "bottom-left", "bottom-right")
    evidence = {"environment": VM["check_guest"](), "results": [],
                "candidate_panel": VM["candidate_panel_state"]()}
    if args.panel and evidence["candidate_panel"]["provider"] != args.panel:
        raise RuntimeError(f"Expected {args.panel} candidate panel, got "
                           f"{evidence['candidate_panel']['provider']}")
    original_engine = session_command("fcitx5-remote -n")
    original_state = session_command("fcitx5-remote; true")
    prior_config = VM["read_config"]()
    desktop_settings = VM["prepare_desktop"]()
    try:
        VM["apply_config"](VM["CASES"]["T01-standard"])
        with Qmp() as qmp:
            for mode in modes:
                for position in positions:
                    try:
                        evidence["results"].append(run_position(
                            qmp, mode, position, args.mouse))
                    except Exception as error:
                        evidence["results"].append({"mode": mode, "position": position,
                                                    "status": "failed", "error": str(error)})
                        print(f"{mode}/{position}: failed: {error}", file=sys.stderr,
                              flush=True)
                        VM["check_guest"]()
        failures = [result for result in evidence["results"]
                    if result["status"] == "failed"]
        if failures:
            raise RuntimeError(f"{len(failures)} popup case(s) failed")
    except Exception as error:
        evidence["failure"] = str(error)
        raise
    finally:
        errors = []
        for name, action in (("config", lambda: VM["restore_config"](prior_config)),
                             ("engine", lambda: VM["restore_engine"](
                                 original_engine, original_state)),
                             ("desktop", lambda: VM["restore_desktop"](desktop_settings))):
            try:
                action()
            except Exception as error:
                errors.append(f"{name}: {error}")
        if errors:
            evidence["restore_errors"] = errors
        path = VM_DIR / "gnome-popup-last.json"
        path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
        (VM_DIR / f"gnome-popup-{stamp}.json").write_text(
            json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
        if errors:
            raise RuntimeError("Failed to restore guest state: " + "; ".join(errors))
    print(f"Passed {len(evidence['results'])} popup cases; {path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
