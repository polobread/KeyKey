#!/usr/bin/env python3
"""Check that two live GNOME clients keep separate Fcitx input states."""

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
HOST_DIR = VM["HOST_DIR"]
MODES = VM["MODES"]
guest = VM["guest"]
session_command = VM["session_command"]
Qmp = VM["Qmp"]


def host_events(case_dir):
    return [json.loads(line) for line in guest(f"cat {case_dir}/events.jsonl").splitlines()]


def wait_event(case_dir, event_type, value, minimum=1):
    observed = []
    for _ in range(60):
        try:
            observed = host_events(case_dir)
        except RuntimeError:
            pass
        if sum(event.get("type") == event_type and event.get("value") == value
               for event in observed) >= minimum:
            return observed
        time.sleep(0.2)
    raise RuntimeError(f"Missing {event_type}={value!r} in {case_dir}: {observed}")


def start_host(mode, unit, case_dir):
    guest(f"mkdir -p {shlex.quote(case_dir)} && rm -f -- " +
          " ".join(shlex.quote(f"{case_dir}/{name}")
                   for name in ("events.jsonl", "host-events.log", "final.txt", "close-now")))
    command = [
        "systemd-run", "--user", f"--unit={unit}", "--collect",
        "--property=Type=exec", f"--setenv={mode.backend}",
        *(["--setenv=GTK_IM_MODULE=fcitx"] if mode.gtk_module == "fcitx" else []),
        f"--setenv=KEYKEY_E2E_CASE_DIR={case_dir}",
        "--setenv=KEYKEY_E2E_SCENARIO=hold",
        f"--setenv=KEYKEY_E2E_WINDOW_TITLE={unit}",
        *(["/usr/bin/env", "-u", "GTK_IM_MODULE"]
          if mode.gtk_module == "unset" else []),
        f"{HOST_DIR}/keykey_linux_{mode.host}_e2e_host",
    ]
    session_command(shlex.join(command))
    wait_event(case_dir, "focus", "in")


def select_engine(name):
    current = session_command("fcitx5-remote -o; "
                              f"fcitx5-remote -s {shlex.quote(name)}; "
                              "fcitx5-remote -n")
    if not current or current.splitlines()[-1] != name:
        raise RuntimeError(f"Could not select {name}: {current!r}")


def run_phase(qmp, mode_name, phase):
    mode = MODES[mode_name]
    positive = phase == "positive"
    engine = "chichi77-keykey-bopomofo" if positive else "keyboard-us"
    expected_a = "ａｂ中" if positive else "ab5j/ 1"
    expected_b = "文" if positive else "jp61"
    root = f"/tmp/keykey-gnome-multi-app/{mode_name}/{phase}"
    dirs = {name: f"{root}/{name}" for name in ("app-a", "app-b")}
    units = {name: f"keykey-multi-{mode_name}-{phase}-{name}-{int(time.time())}"
             for name in dirs}
    launched = []
    try:
        launched.append("app-a")
        start_host(mode, units["app-a"], dirs["app-a"])
        select_engine(engine)
        if positive:
            qmp.keys(("ctrl-backslash", "shift-spc", "a"))
            wait_event(dirs["app-a"], "text", "ａ")
        else:
            qmp.keys(("a",))
            wait_event(dirs["app-a"], "text", "a")

        launched.append("app-b")
        start_host(mode, units["app-b"], dirs["app-b"])
        wait_event(dirs["app-a"], "focus", "out")
        select_engine(engine)
        qmp.keys(("j", "p", "6", "1"))
        wait_event(dirs["app-b"], "text", expected_b)

        previous_focuses = sum(event.get("type") == "focus" and
                               event.get("value") == "in"
                               for event in host_events(dirs["app-a"]))
        switched = False
        for _ in range(3):
            qmp.keys(("alt-esc",))
            try:
                wait_event(dirs["app-a"], "focus", "in", previous_focuses + 1)
                switched = True
                break
            except RuntimeError:
                pass
        if not switched:
            raise RuntimeError("GNOME did not return focus to app A")
        select_engine(engine)
        if positive:
            qmp.keys(("b",))
            wait_event(dirs["app-a"], "text", "ａｂ")
            qmp.keys(("shift-spc", "ctrl-backslash", "5", "j", "slash",
                      "spc", "1"))
        else:
            qmp.keys(("b", "5", "j", "slash", "spc", "1"))
        wait_event(dirs["app-a"], "text", expected_a)

        for name in launched:
            state = session_command(
                f"systemctl --user is-active {shlex.quote(units[name])}.service")
            if state != "active":
                raise RuntimeError(f"{name} exited before both live clients were checked")
        guest("touch " + " ".join(shlex.quote(f"{dirs[name]}/close-now")
                                   for name in launched))
        for name, expected in (("app-a", expected_a), ("app-b", expected_b)):
            VM["wait_file"](dirs[name], "final.txt")
            final = guest(f"cat {dirs[name]}/final.txt")
            if final != expected:
                raise RuntimeError(f"{name} final text {final!r}, expected {expected!r}")
        print(f"{mode_name}/{phase}: {expected_a}|{expected_b}", flush=True)
        return {"mode": mode_name, "phase": phase, "status": "passed",
                "app_a": expected_a, "app_b": expected_b,
                "events": {name: host_events(dirs[name]) for name in launched}}
    finally:
        for name in launched:
            session_command(f"systemctl --user stop {shlex.quote(units[name])}.service || true")


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
    desktop_settings = VM["prepare_desktop"]()
    try:
        VM["apply_config"](VM["CASES"]["T01-standard"])
        with Qmp() as qmp:
            for mode in modes:
                for phase in phases:
                    try:
                        evidence["results"].append(run_phase(qmp, mode, phase))
                    except Exception as error:
                        evidence["results"].append({"mode": mode, "phase": phase,
                                                    "status": "failed", "error": str(error)})
                        print(f"{mode}/{phase}: failed: {error}",
                              file=sys.stderr, flush=True)
                        try:
                            VM["check_guest"]()
                        except Exception as session_error:
                            raise RuntimeError(
                                f"GNOME session ended during {mode}/{phase}: "
                                f"{session_error}") from error
        failures = [item for item in evidence["results"] if item["status"] == "failed"]
        if failures:
            raise RuntimeError(f"{len(failures)} multi-app phase(s) failed")
    except Exception as error:
        evidence["failure"] = str(error)
        raise
    finally:
        errors = []
        for name, action in (
            ("config", lambda: VM["restore_config"](prior_config)),
            ("engine", lambda: VM["restore_engine"](original_engine, original_state)),
            ("desktop", lambda: VM["restore_desktop"](desktop_settings)),
        ):
            try:
                action()
            except Exception as error:
                errors.append(f"{name}: {error}")
        if errors:
            evidence["restore_errors"] = errors
        report = json.dumps(evidence, ensure_ascii=False, indent=2) + "\n"
        path = VM_DIR / "gnome-multi-app-last.json"
        path.write_text(report)
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
        (VM_DIR / f"gnome-multi-app-{stamp}.json").write_text(report)
        if errors:
            raise RuntimeError("Failed to restore guest state: " + "; ".join(errors))
    print(f"Passed {len(evidence['results'])} multi-app phases; {path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
