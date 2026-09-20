#!/usr/bin/env python3
"""Exercise candidate-client closure and Fcitx recovery in the GNOME VM."""

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


def addon_pid():
    result = guest("pid=$(pgrep -u keykey -x fcitx5 | tail -n 1); "
                   "test -n \"$pid\" && "
                   "grep -q /fcitx5/chichi77-keykey.so /proc/$pid/maps && echo $pid")
    return int(result)


def close_candidate_client(qmp, mode_name):
    mode = MODES[mode_name]
    case_dir = f"/tmp/keykey-gnome-recovery/{mode_name}/close"
    unit = f"keykey-close-{mode_name}-{int(time.time())}"
    guest(f"mkdir -p {shlex.quote(case_dir)} && rm -f -- " +
          " ".join(shlex.quote(f"{case_dir}/{name}")
                   for name in ("ready-to-close", "close-now", "final.txt",
                                "events.jsonl", "host-events.log")))
    command = [
        "systemd-run", "--user", f"--unit={unit}", "--collect",
        "--property=Type=exec", f"--setenv={mode.backend}",
        *(["--setenv=GTK_IM_MODULE=fcitx"] if mode.gtk_module == "fcitx" else []),
        f"--setenv=KEYKEY_E2E_CASE_DIR={case_dir}",
        "--setenv=KEYKEY_E2E_SCENARIO=close",
        "--setenv=KEYKEY_E2E_REQUIRED_PREEDITS=ㄓ,ㄓㄨ,ㄓㄨㄥ",
        f"--setenv=KEYKEY_E2E_WINDOW_TITLE={unit}",
        *(["/usr/bin/env", "-u", "GTK_IM_MODULE"]
          if mode.gtk_module == "unset" else []),
        f"{HOST_DIR}/keykey_linux_{mode.host}_e2e_host",
    ]
    launched = False
    try:
        session_command(shlex.join(command))
        launched = True
        time.sleep(1.5)
        selected = session_command("fcitx5-remote -o; "
                                   "fcitx5-remote -s chichi77-keykey-bopomofo; "
                                   "fcitx5-remote -n")
        if not selected or selected.splitlines()[-1] != "chichi77-keykey-bopomofo":
            raise RuntimeError(f"KeyKey engine inactive: {selected!r}")
        stem = f"T10-client-close-{mode_name}"
        before = VM_DIR / f"{stem}-before.ppm"
        candidate = VM_DIR / f"{stem}-candidate.ppm"
        qmp.screenshot(before)
        qmp.keys(("5", "j", "slash", "spc"))
        VM["wait_file"](case_dir, "ready-to-close")
        time.sleep(0.5)
        qmp.screenshot(candidate)
        bounds, resolution = VM["find_candidate_popup"](before, candidate)
        pid_before = addon_pid()
        guest(f"touch {case_dir}/close-now")
        VM["wait_file"](case_dir, "final.txt")
        final = guest(f"cat {case_dir}/final.txt")
        if final != "closed":
            raise RuntimeError(f"Candidate client did not close cleanly: {final!r}")
        if addon_pid() != pid_before:
            raise RuntimeError("Fcitx process restarted during client closure")
        events = guest(f"cat {case_dir}/host-events.log")
        if "result=passed" not in events:
            raise RuntimeError(f"Host failed while closing candidates: {events}")
        print(f"{mode_name}: active candidate client closed; addon PID {pid_before} survived",
              flush=True)
        return {"mode": mode_name, "status": "passed", "addon_pid": pid_before,
                "candidate_bounds": bounds, "resolution": resolution,
                "guest_artifact": case_dir, "events": events.splitlines()}
    finally:
        if launched:
            session_command(f"systemctl --user stop {shlex.quote(unit)}.service || true")


def dbus_owner():
    return session_command(
        "gdbus call --session --dest org.freedesktop.DBus "
        "--object-path /org/freedesktop/DBus "
        "--method org.freedesktop.DBus.GetNameOwner org.fcitx.Fcitx5")


def restart_fcitx():
    previous_owner = dbus_owner()
    previous_pid = addon_pid()
    session_command("gdbus call --session --dest org.fcitx.Fcitx5 "
                    "--object-path /controller "
                    "--method org.fcitx.Fcitx.Controller1.Restart")
    unit = f"keykey-fcitx-recovery-{int(time.time())}"
    session_command("systemd-run --user "
                    f"--unit={shlex.quote(unit)} --collect --property=Type=exec "
                    "/usr/bin/fcitx5 -r")
    current_owner = previous_owner
    for _ in range(80):
        try:
            current_owner = dbus_owner()
            if current_owner != previous_owner:
                VM["check_guest"]()
                return {"before_owner": previous_owner,
                        "after_owner": current_owner,
                        "before_pid": previous_pid, "after_pid": addon_pid(),
                        "unit": unit}
        except RuntimeError:
            pass
        time.sleep(0.25)
    raise RuntimeError(f"Fcitx did not reacquire D-Bus after restart: {current_owner}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", action="append", choices=MODES)
    parser.add_argument("--skip-restart", action="store_true",
                        help="Only check candidate-client closure and immediate recovery")
    parser.add_argument("--restart-only", action="store_true",
                        help="Restart Fcitx once and check new clients in selected modes")
    args = parser.parse_args()
    if args.skip_restart and args.restart_only:
        parser.error("--skip-restart and --restart-only cannot be combined")
    modes = args.mode or list(MODES)
    evidence = {"environment": VM["check_guest"](), "close": [],
                "immediate_recovery": [], "restart_recovery": []}
    original_engine = session_command("fcitx5-remote -n")
    original_state = session_command("fcitx5-remote; true")
    prior_config = VM["read_config"]()
    desktop_settings = VM["prepare_desktop"]()
    try:
        VM["apply_config"](VM["CASES"]["T01-standard"])
        with Qmp() as qmp:
            if not args.restart_only:
                for mode_name in modes:
                    evidence["close"].append(close_candidate_client(qmp, mode_name))
                    evidence["immediate_recovery"].append(
                        VM["run_case"](qmp, "T01-standard", mode_name))
            if not args.skip_restart:
                evidence["restart"] = restart_fcitx()
                for mode_name in modes:
                    evidence["restart_recovery"].append(
                        VM["run_case"](qmp, "T01-standard", mode_name))
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
        path = VM_DIR / "gnome-recovery-last.json"
        path.write_text(report)
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
        (VM_DIR / f"gnome-recovery-{stamp}.json").write_text(report)
        if errors:
            raise RuntimeError("Failed to restore guest state: " + "; ".join(errors))
    print(f"Closed candidates in {len(evidence['close'])} modes; "
          f"recovered after restart in {len(evidence['restart_recovery'])}; {path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
