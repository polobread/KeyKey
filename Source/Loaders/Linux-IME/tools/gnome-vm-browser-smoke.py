#!/usr/bin/env python3
"""Type through installed browsers into a local web page in the GNOME VM."""

import argparse
import base64
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
guest = VM["guest"]
session_command = VM["session_command"]
Qmp = VM["Qmp"]
PORT = 18764
ARTIFACT_DIR = "/tmp/keykey-gnome-browser"
FIELDS = ("textarea", "input", "contenteditable")
MODES = {
    "firefox-wayland": ("firefox", "wayland", "fcitx"),
    "firefox-bridge": ("firefox", "wayland", "unset"),
    "epiphany-wayland": ("epiphany", "wayland", "fcitx"),
    "epiphany-bridge": ("epiphany", "wayland", "unset"),
    "epiphany-xwayland": ("epiphany", "x11", "fcitx"),
}


def start_fixture():
    source = Path(__file__).with_name("gnome-vm-browser-fixture.py")
    encoded = base64.b64encode(source.read_bytes()).decode()
    guest(f"mkdir -p {HOST_DIR}; printf %s {shlex.quote(encoded)} | "
          f"base64 -d > {HOST_DIR}/browser-fixture.py")
    unit = f"keykey-browser-fixture-{int(time.time())}"
    command = ["systemd-run", "--user", f"--unit={unit}", "--collect",
               "--property=Type=exec", "/usr/bin/python3",
               f"{HOST_DIR}/browser-fixture.py", ARTIFACT_DIR,
               "--port", str(PORT)]
    session_command(shlex.join(command))
    for _ in range(50):
        try:
            guest(f"curl -fsS http://127.0.0.1:{PORT}/ | "
                  "grep -Fq 'Browser typing field'")
            return unit
        except RuntimeError:
            time.sleep(0.2)
    raise RuntimeError("Browser fixture server did not start")


def events_for(case):
    return [json.loads(line) for line in
            guest(f"cat {ARTIFACT_DIR}/{case}.jsonl").splitlines()]


def wait_event(case, event, value=None):
    observed = []
    for _ in range(120):
        try:
            observed = events_for(case)
        except RuntimeError:
            pass
        if any(item.get("event") == event and item.get("focused") and
               (value is None or item.get("value") == value)
               for item in observed):
            return observed
        time.sleep(0.25)
    raise RuntimeError(f"Browser DOM did not report {event}={value!r}: {observed}")


def firefox_scopes():
    output = session_command(
        "systemctl --user --no-legend --plain --no-pager list-units "
        "'snap.firefox.firefox-*.scope'")
    return {line.split()[0] for line in output.splitlines()
            if line.startswith("snap.firefox.firefox-")}


def run_mode(qmp, mode_name, field):
    browser, backend, module = MODES[mode_name]
    case = f"{mode_name}-{field}"
    unit = f"keykey-browser-{case}-{int(time.time())}"
    guest(f"mkdir -p {ARTIFACT_DIR}; rm -f -- {ARTIFACT_DIR}/{case}.jsonl")
    url = f"http://127.0.0.1:{PORT}/?case={case}&field={field}"
    launch = ["systemd-run", "--user", f"--unit={unit}", "--collect",
              "--property=Type=exec"]
    previous_scopes = firefox_scopes() if browser == "firefox" else set()
    if browser == "firefox":
        launch.extend(("--setenv=MOZ_ENABLE_WAYLAND=1",
                       "--setenv=GDK_BACKEND=wayland"))
        binary = "/snap/bin/firefox"
    else:
        launch.append(f"--setenv=GDK_BACKEND={backend}")
        binary = "/usr/bin/epiphany"
    if module == "fcitx":
        launch.append("--setenv=GTK_IM_MODULE=fcitx")
    if module == "unset":
        launch.extend(("/usr/bin/env", "-u", "GTK_IM_MODULE"))
    launch.append(binary)
    if browser == "firefox":
        profile = f"/home/keykey/snap/firefox/common/keykey-gnome-{mode_name}-{int(time.time())}"
        guest(f"mkdir -p {profile}")
        launch.extend(("--no-remote", "--profile", profile))
    else:
        profile = f"{ARTIFACT_DIR}/profile-{case}-{int(time.time())}"
        launch.extend(("--private-instance",
                       f"--profile={profile}"))
    launch.extend(("--new-window", url))
    started = False
    try:
        session_command(shlex.join(launch))
        started = True
        wait_event(case, "ready", "")
        time.sleep(0.75)
        ready = VM_DIR / f"browser-{case}-ready.ppm"
        qmp.screenshot(ready)
        session_command("fcitx5-remote -o; fcitx5-remote -s keyboard-us")
        qmp.keys(("x", "backspace"))
        wait_event(case, "input", "x")
        wait_event(case, "input", "")
        selected = session_command("fcitx5-remote -o; "
                                   "fcitx5-remote -s chichi77-keykey-bopomofo; "
                                   "fcitx5-remote -n")
        if not selected or selected.splitlines()[-1] != "chichi77-keykey-bopomofo":
            raise RuntimeError(f"KeyKey not active in {mode_name}: {selected!r}")
        before = VM_DIR / f"browser-{case}-before.ppm"
        candidate = VM_DIR / f"browser-{case}-candidate.ppm"
        qmp.screenshot(before)
        qmp.keys(("5", "j", "slash", "spc"))
        time.sleep(0.5)
        qmp.screenshot(candidate)
        qmp.keys(("1",))
        wait_event(case, "input", "中")
        selected = session_command("fcitx5-remote -s keyboard-us; fcitx5-remote -n")
        if not selected or selected.splitlines()[-1] != "keyboard-us":
            raise RuntimeError(f"keyboard-us not active in {mode_name}: {selected!r}")
        qmp.keys(("ctrl-a", "backspace", "5", "j", "slash", "spc", "1"))
        observed = wait_event(case, "input", "5j/ 1")
        print(f"{case}: 中 + keyboard-us literal control", flush=True)
        return {"mode": mode_name, "field": field, "status": "passed",
                "browser": browser, "backend": backend, "module": module,
                "events": observed, "candidate_screenshot": str(candidate)}
    finally:
        if started:
            qmp.keys(("ctrl-q",))
            time.sleep(0.5)
            session_command(f"systemctl --user stop {shlex.quote(unit)}.service || true")
        if browser == "firefox":
            for _ in range(30):
                if not firefox_scopes() - previous_scopes:
                    break
                time.sleep(0.2)
            else:
                raise RuntimeError(f"Firefox Snap scope remained; profile kept: {profile}")
        guest(f"rm -rf -- {shlex.quote(profile)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", action="append", choices=MODES)
    parser.add_argument("--field", action="append", choices=FIELDS)
    args = parser.parse_args()
    modes = args.mode or list(MODES)
    fields = args.field or FIELDS
    evidence = {"environment": VM["check_guest"](), "results": [],
                "firefox": guest("snap list firefox 2>/dev/null || true"),
                "epiphany": guest("dpkg-query -W epiphany-browser 2>/dev/null || true")}
    original_engine = session_command("fcitx5-remote -n")
    original_state = session_command("fcitx5-remote; true")
    prior_config = VM["read_config"]()
    desktop_settings = VM["prepare_desktop"]()
    epiphany_prompt = session_command("gsettings get org.gnome.Epiphany ask-for-default")
    fixture_unit = None
    try:
        session_command("gsettings set org.gnome.Epiphany ask-for-default false")
        VM["apply_config"](VM["CASES"]["T01-standard"])
        fixture_unit = start_fixture()
        with Qmp() as qmp:
            for mode in modes:
                for field in fields:
                    try:
                        evidence["results"].append(run_mode(qmp, mode, field))
                    except Exception as error:
                        evidence["results"].append({"mode": mode, "field": field,
                                                    "status": "failed",
                                                    "error": str(error)})
                        print(f"{mode}/{field}: failed: {error}", file=sys.stderr,
                              flush=True)
                        try:
                            VM["check_guest"]()
                        except Exception as session_error:
                            raise RuntimeError(f"GNOME session ended: {session_error}") from error
        failed = [item for item in evidence["results"] if item["status"] == "failed"]
        if failed:
            raise RuntimeError(f"{len(failed)} browser field/mode case(s) failed")
    except Exception as error:
        evidence["failure"] = str(error)
        raise
    finally:
        errors = []
        if fixture_unit:
            try:
                session_command(f"systemctl --user stop {shlex.quote(fixture_unit)}.service || true")
            except Exception as error:
                errors.append(f"fixture: {error}")
        for name, action in (
            ("config", lambda: VM["restore_config"](prior_config)),
            ("engine", lambda: VM["restore_engine"](original_engine, original_state)),
            ("desktop", lambda: VM["restore_desktop"](desktop_settings)),
            ("epiphany", lambda: session_command(
                "gsettings set org.gnome.Epiphany ask-for-default "
                f"{shlex.quote(epiphany_prompt)}")),
        ):
            try:
                action()
            except Exception as error:
                errors.append(f"{name}: {error}")
        if errors:
            evidence["restore_errors"] = errors
        report = json.dumps(evidence, ensure_ascii=False, indent=2) + "\n"
        path = VM_DIR / "gnome-browser-last.json"
        path.write_text(report)
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
        (VM_DIR / f"gnome-browser-{stamp}.json").write_text(report)
        if errors:
            raise RuntimeError("Failed to restore guest state: " + "; ".join(errors))
    print(f"Passed {len(evidence['results'])} browser field/mode cases; {path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
