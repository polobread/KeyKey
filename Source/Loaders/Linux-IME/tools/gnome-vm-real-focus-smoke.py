#!/usr/bin/env python3
"""Exercise focus changes between real GNOME editors with active KeyKey preedit."""

import argparse
import datetime
import json
import runpy
import shlex
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent
VM = runpy.run_path(str(ROOT / "gnome-vm-wayland-smoke.py"))
APPS = runpy.run_path(str(ROOT / "gnome-vm-real-app-smoke.py"))
VM_DIR = VM["VM_DIR"]
session_command = VM["session_command"]
guest = VM["guest"]


def select_engine(name):
    selected = session_command("fcitx5-remote -o; "
                               f"fcitx5-remote -s {shlex.quote(name)}; "
                               "fcitx5-remote -n")
    if not selected or selected.splitlines()[-1] != name:
        raise RuntimeError(f"Engine {name} not active: {selected!r}")


def launch_editor(app, backend, module, unit, document):
    guest(f": > {shlex.quote(document)}")
    command = APPS["APPS"][app][1:]
    launch = [
        "systemd-run", "--user", f"--unit={unit}", "--collect",
        "--property=Type=exec", f"--setenv=GDK_BACKEND={backend}",
        *(["--setenv=GTK_IM_MODULE=fcitx"] if module == "direct" else []),
        *(["/usr/bin/env", "-u", "GTK_IM_MODULE"] if module == "bridge" else []),
        *command, document,
    ]
    session_command(shlex.join(launch))
    return APPS["wait_app"](app, Path(document).name, "")


def run_case(qmp, backend, module):
    second_app = "gnome-text-editor" if module == "direct" else "gedit"
    stamp = int(time.time())
    first_unit = f"keykey-real-focus-gedit-{backend}-{module}-{stamp}"
    second_unit = f"keykey-real-focus-second-{backend}-{module}-{stamp}"
    first_doc = f"/tmp/{first_unit}.txt"
    second_doc = f"/tmp/{second_unit}.txt"
    try:
        first_start = launch_editor(
            "gedit", backend, module, first_unit, first_doc)
        second_start = launch_editor(
            second_app, backend, module, second_unit, second_doc)
        qmp.keys(("alt-tab",))
        APPS["wait_app"]("gedit", Path(first_doc).name)
        select_engine("chichi77-keykey-bopomofo")
        qmp.keys(("5", "j", "slash"))
        first_reading = APPS["read_app"]("gedit", Path(first_doc).name)
        qmp.keys(("alt-tab",))
        APPS["wait_app"](second_app, Path(second_doc).name)
        first_after_blur = APPS["read_app"]("gedit", Path(first_doc).name)
        expected_blur = "ㄓㄨㄥ" if module == "direct" else ""
        if first_after_blur["text"] != expected_blur:
            raise RuntimeError(f"Unexpected real gedit blur result: {first_after_blur}")
        select_engine("chichi77-keykey-bopomofo")
        qmp.keys(("j", "p", "6", "1"))
        second_commit = APPS["wait_app"](
            second_app, Path(second_doc).name, "文")
        qmp.keys(("alt-tab",))
        APPS["wait_app"]("gedit", Path(first_doc).name)
        select_engine("chichi77-keykey-bopomofo")
        qmp.keys(("5", "j", "slash", "spc", "1"))
        first_commit = APPS["wait_app"](
            "gedit", Path(first_doc).name, first_after_blur["text"] + "中")
        select_engine("keyboard-us")
        qmp.keys(("ctrl-a", "backspace", "5", "j", "slash", "spc", "1"))
        first_literal = APPS["wait_app"](
            "gedit", Path(first_doc).name, "5j/ 1")
        qmp.keys(("alt-tab",))
        APPS["wait_app"](second_app, Path(second_doc).name)
        select_engine("keyboard-us")
        qmp.keys(("ctrl-a", "backspace", "5", "j", "slash", "spc", "1"))
        second_literal = APPS["wait_app"](
            second_app, Path(second_doc).name, "5j/ 1")
        result = {"backend": backend, "input_path": module,
                  "second_app": second_app, "status": "passed",
                  "first_start": first_start, "second_start": second_start,
                  "first_reading": first_reading,
                  "first_after_blur": first_after_blur,
                  "first_commit": first_commit, "second_commit": second_commit,
                  "first_literal": first_literal, "second_literal": second_literal}
        print(f"{backend}/{module}: passed blur={first_after_blur['text']!r}, "
              f"gedit and {second_app} committed Chinese and literal control",
              flush=True)
        return result
    finally:
        for unit in (second_unit, first_unit):
            session_command(f"systemctl --user stop {shlex.quote(unit)}.service || true")
        guest(f"rm -f -- {shlex.quote(first_doc)} {shlex.quote(second_doc)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", action="append", choices=("wayland", "x11"))
    parser.add_argument("--input-path", action="append", choices=("direct", "bridge"))
    args = parser.parse_args()
    backends = args.backend or ("wayland", "x11")
    paths = args.input_path or ("direct", "bridge")
    evidence = {"environment": VM["check_guest"](), "results": [],
                "candidate_panel": VM["candidate_panel_state"]()}
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
        with VM["Qmp"]() as qmp:
            for backend in backends:
                for path in paths:
                    if backend == "x11" and path == "bridge":
                        continue
                    try:
                        evidence["results"].append(run_case(qmp, backend, path))
                    except Exception as error:
                        evidence["results"].append({
                            "backend": backend, "input_path": path,
                            "status": "failed", "error": str(error)})
                        print(f"{backend}/{path}: failed: {error}",
                              file=sys.stderr, flush=True)
                        VM["check_guest"]()
        failures = [item for item in evidence["results"] if item["status"] == "failed"]
        if failures:
            raise RuntimeError(f"{len(failures)} real focus case(s) failed")
    except Exception as error:
        evidence["failure"] = str(error)
        raise
    finally:
        errors = []
        for name, action in (("config", lambda: VM["restore_config"](prior_config)),
                             ("engine", lambda: VM["restore_engine"](
                                 original_engine, original_state)),
                             ("accessibility", lambda: session_command(
                                 "gsettings set org.gnome.desktop.interface "
                                 "toolkit-accessibility "
                                 + shlex.quote(original_accessibility))),
                             ("desktop", lambda: VM["restore_desktop"](
                                 desktop_settings))):
            try:
                action()
            except Exception as error:
                errors.append(f"{name}: {error}")
        if errors:
            evidence["restore_errors"] = errors
        path = VM_DIR / "gnome-real-focus-last.json"
        path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
        timestamp = datetime.datetime.now(datetime.timezone.utc).strftime(
            "%Y%m%d-%H%M%S")
        (VM_DIR / f"gnome-real-focus-{timestamp}.json").write_text(
            json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
        if errors:
            raise RuntimeError("Failed to restore guest state: " + "; ".join(errors))
    print(f"Passed {len(evidence['results'])} real focus cases; {path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
