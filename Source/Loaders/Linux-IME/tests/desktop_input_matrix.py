#!/usr/bin/env python3
"""Execute the portable desktop input contracts in real, isolated X11 hosts."""
import copy
import ctypes
import hashlib
import json
import os
import sqlite3
from pathlib import Path
import subprocess
import sys
import time

import fcitx5_e2e_config as config

ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/desktop_input/cases.json"
PREFERENCES = {
    "smart.use_bigrams": "Phonetic/SmartMandarin/UseBigrams",
    "learning.candidate_overrides": "Phonetic/SmartMandarin/LearnCandidateOverrides",
    "learning.bigrams": "Phonetic/SmartMandarin/LearnBigrams",
    "learning.user_phrases": "UserPhrases/UseUserPhrases",
    "smart.shift_always_uppercase": "Phonetic/SmartMandarin/ShiftKeyAlwaysCommitUppercaseCharacters",
    "behaviors.ignore_caps_lock_in_chinese": "General/IgnoreCapsLockInChinese",
    "smart.clear_composing_with_escape": "Phonetic/SmartMandarin/ClearComposingTextWithEsc",
    "smart.space_opens_candidates": "Phonetic/SmartMandarin/ShowCandidateListWithSpace",
    "smart.selection_returns_to_end": "Phonetic/SmartMandarin/SelectionReturnsToEnd",
    "smart.candidate_cursor_at_end": "Phonetic/SmartMandarin/CandidateCursorAtEndOfTargetBlock",
    "smart.max_completed_syllables": "Phonetic/SmartMandarin/ComposingTextBufferSize",
    "smart.candidate_selection_keys": "Phonetic/SmartMandarin/CandidateSelectionKeys",
    "traditional_selection_keys": "Phonetic/TraditionalSelectionKeys",
    "table.maximum_radical_length": "Cangjie/MaximumRadicalLength",
    "table.query_at_maximum": "Cangjie/ShouldCommitAtMaximumRadicalLength",
    "table.clear_on_error": "Cangjie/ClearOnError",
    "table.realtime": "Cangjie/ComposeWhileTyping",
    "table.prefix": "Cangjie/PrefixCandidates",
    "table.wildcard.one": "Cangjie/MatchOneChar",
    "table.wildcard.many": "Cangjie/MatchZeroOrMoreChar",
}
HOSTS = {"GTK3": "KEYKEY_E2E_HOST", "GTK4": "KEYKEY_E2E_GTK4_HOST", "QT6": "KEYKEY_E2E_QT6_HOST"}


def command(*args, check=True):
    return subprocess.run(args, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=check, timeout=15).stdout.strip()


def dbus(method, *args):
    return command("gdbus", "call", "--session", "--dest", "org.fcitx.Fcitx5",
                   "--object-path", "/controller", "--method",
                   "org.fcitx.Fcitx.Controller1." + method, *args)


class Matrix:
    def __init__(self):
        self.out = Path(os.environ["KEYKEY_E2E_ARTIFACT_DIR"])
        self.fixture = config.read_json(FIXTURE)
        model = Path(os.environ["CHICHI77_KEYKEY_DATA_DIR"]) / "smart-mandarin.db"
        self.model_sha256 = hashlib.sha256(model.read_bytes()).hexdigest()
        if self.model_sha256 != self.fixture["model_sha256"]:
            raise ValueError("Model differs from the shared desktop case fixture")
        self.profile = os.environ.get("KEYKEY_E2E_DESKTOP_PROFILE", self.fixture["default_profile"])
        if self.profile not in self.fixture["profiles"]:
            raise ValueError("Unknown desktop test profile: " + self.profile)
        self.results = []
        self.hosts = []
        self.trace_path = None
        self.expected = None
        self.x11 = ctypes.CDLL("libX11.so.6")
        self.x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.x11.XOpenDisplay.restype = ctypes.c_void_p
        self.x11.XQueryKeymap.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        self.x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
        self.display = self.x11.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError("Cannot inspect private X11 key state")

    def trace(self, **data):
        if self.trace_path:
            with self.trace_path.open("a") as stream:
                stream.write(json.dumps({"monotonic": time.monotonic(), **data}, ensure_ascii=False) + "\n")

    def keyboard(self):
        keymap = ctypes.create_string_buffer(32)
        self.x11.XQueryKeymap(self.display, keymap)
        pressed = [i * 8 + bit for i, byte in enumerate(keymap.raw)
                   for bit in range(8) if byte & (1 << bit)]
        return {"pressed_keycodes": pressed,
                "focus": command("xdotool", "getwindowfocus", check=False),
                "xset": command("xset", "q")}

    def gate(self, phase):
        actual = config.live_config()
        result = config.check(self.expected, actual, config.read_json(config.BASELINE))
        self.gate_index += 1
        config.write_json(self.case_dir / f"config-{self.gate_index:03d}-{phase}.json", result)
        if result["differences"]:
            raise AssertionError("Settings differ: " + json.dumps(result["differences"]))

    def configure(self, case):
        self.expected = copy.deepcopy(config.read_json(config.BASELINE))
        prefs = {**self.fixture["baseline"], **self.fixture["profiles"][self.profile], **case["preferences"]}
        method = prefs["method"]
        self.engine = "chichi77-keykey-" + (method if method in ("cangjie", "simplex") else "bopomofo")
        changes = [f"{PREFERENCES[k]}={v}" for k, v in prefs.items() if k in PREFERENCES]
        changes.append("Phonetic/BopomofoMode=" + ("Traditional" if method == "traditional" else "Smart"))
        config.apply_changes(self.expected, changes)
        config.write_json(self.case_dir / "expected-config.json", self.expected)
        config.write_ini(Path(os.environ["XDG_CONFIG_HOME"]) / "fcitx5/conf/chichi77-keykey.conf", self.expected)
        dbus("ReloadAddonConfig", "chichi77-keykey")
        self.gate("reload")
        self.reset_learning()

    def reset_learning(self):
        if os.environ.get("CHICHI77_KEYKEY_GUANYINMA_USER_DB"):
            raise RuntimeError("The matrix must not reset an external user DB")
        runtime = Path(os.environ["KEYKEY_E2E_RUNTIME_ROOT"]).resolve()
        database = (Path(os.environ["XDG_DATA_HOME"]) / "chichi77-keykey/guanyinma-user.db").resolve()
        if not database.is_relative_to(runtime):
            raise RuntimeError("Learning DB is outside the private test runtime")

        def snapshot():
            if not database.exists():
                return None
            with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as connection:
                return {table: connection.execute("SELECT COUNT(*) FROM " + table).fetchone()[0]
                        for table in ("user_candidate_override_cache", "user_bigram_cache",
                                      "user_unigrams", "table_learning")}

        before = snapshot()
        result = subprocess.run(
            [os.environ.get("KEYKEY_E2E_PHRASE_CLI", "keykey-smart-phrases"), "reset-learning"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        after = snapshot()
        config.write_json(self.case_dir / "reset-learning.json", {
            "database": str(database), "before": before, "after": after,
            "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr,
        })
        if result.returncode != 0 or after is None or any(
                after[table] != 0 for table in ("user_candidate_override_cache", "user_bigram_cache")):
            raise AssertionError("Learning reset failed; see reset-learning.json")
        if before is not None and any(after[table] != before[table]
                                      for table in ("user_unigrams", "table_learning")):
            raise AssertionError("Learning reset changed user phrases or table learning")

    def host(self, toolkit, name):
        directory = self.case_dir / name
        directory.mkdir()
        env = {**os.environ, "KEYKEY_E2E_CASE_DIR": str(directory),
               "KEYKEY_E2E_SCENARIO": "hold", "KEYKEY_E2E_WINDOW_TITLE": "desktop-matrix-" + name}
        log = (directory / "host.log").open("w")
        process = subprocess.Popen([os.environ[HOSTS[toolkit]]], env=env, stdout=log, stderr=log)
        host = {"process": process, "dir": directory, "log": log}
        self.hosts.append(host)
        end = time.monotonic() + 10
        while time.monotonic() < end:
            windows = command("xdotool", "search", "--onlyvisible", "--pid", str(process.pid), check=False).splitlines()
            if windows:
                host["window"] = windows[-1]
                self.focus(host)
                return host
            if process.poll() is not None:
                raise RuntimeError("Host exited before creating its window")
            time.sleep(0.04)
        raise TimeoutError("No host window")

    def focus(self, host, engine=None):
        command("xdotool", "windowfocus", "--sync", host["window"])
        # Focus the actual editor as well as its top-level window.
        command("xdotool", "mousemove", "--window", host["window"], "240", "75", "click", "1")
        # As in the existing cross-App harness: X11 focus precedes toolkit
        # dispatch and the new context's asynchronous Fcitx FocusIn request.
        time.sleep(0.1)
        engine = engine or self.engine
        command("fcitx5-remote", "-o")
        end = time.monotonic() + 3
        while time.monotonic() < end:
            command("fcitx5-remote", "-s", engine)
            state = command("fcitx5-remote")
            if command("fcitx5-remote", "-n") == engine and (engine == "keyboard-us" or state == "2"):
                self.trace(action="focus", window=host["window"], engine=engine)
                return
            time.sleep(0.04)
        raise AssertionError("Engine did not activate")

    def send(self, host, keys):
        self.gate("pre-input")
        before = self.keyboard()
        before["fcitx_state"] = command("fcitx5-remote")
        before["engine"] = command("fcitx5-remote", "-n")
        self.trace(action="keys", keys=keys, before=before)
        if before["engine"] != self.engine or (self.engine != "keyboard-us" and before["fcitx_state"] != "2"):
            raise AssertionError("Fcitx is not active for the intended host before injection")
        if before["pressed_keycodes"]:
            raise AssertionError("Keys remain pressed before injection")
        if before["focus"] != host["window"]:
            raise AssertionError("Host lost focus before injection")
        if keys:
            command("xdotool", "key", "--delay", os.environ.get("KEYKEY_E2E_KEY_DELAY_MS", "35"), *keys)
        after = self.keyboard()
        self.trace(action="keys-finished", after=after)
        if after["pressed_keycodes"]:
            raise AssertionError("Injected keys were not released")

    def state(self, host):
        result = {"text": "", "preedit": ""}
        path = host["dir"] / "events.jsonl"
        if path.exists():
            for line in path.read_text().splitlines():
                event = json.loads(line)
                for key in result:
                    if event["type"] in (key, "first-" + key):
                        result[key] = event["value"]
        return result

    def checkpoint(self, host, expected):
        end = time.monotonic() + 2
        while True:
            current = self.state(host)
            valid = all(current[k] == v for k, v in expected.items() if k in current)
            if "combined" in expected:
                valid &= current["text"] + current["preedit"] == expected["combined"]
            if expected.get("committed_nonempty"):
                valid &= bool(current["text"])
            if "max_preedit" in expected:
                valid &= len(current["preedit"]) <= expected["max_preedit"]
            if valid or time.monotonic() >= end:
                break
            time.sleep(0.03)
        self.trace(action="checkpoint", expected=expected, actual=current, passed=bool(valid))
        if not valid:
            raise AssertionError(f"Expected {expected}; observed {current}")

    def cleanup_hosts(self):
        for host in self.hosts:
            process = host["process"]
            (host["dir"] / "close-now").touch()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=3)
            host["log"].close()
        self.hosts = []

    def run_case(self, toolkit, case, round_number=1):
        name = f"{toolkit}-{case['id']}-{round_number:03d}"
        self.case_dir = self.out / "cases" / name
        self.case_dir.mkdir(parents=True)
        self.trace_path = self.case_dir / "automation.jsonl"
        self.gate_index = 0
        result = {"case": case["id"], "category": case["category"], "toolkit": toolkit,
                  "round": round_number, "profile": self.profile, "status": "passed"}
        started = time.monotonic()
        try:
            self.configure(case)
            if case["category"] == "control":
                self.engine = "keyboard-us"
            host = self.host(toolkit, "app-a")
            self.trace(action="start", keyboard=self.keyboard())
            if case.get("scenario") == "focus":
                self.send(host, list("su3cl3"))
                self.checkpoint(host, {"text": "", "preedit": "你好"})
                other = self.host(toolkit, "app-b")
                self.checkpoint(host, {"text": "你好", "preedit": ""})
                self.send(other, list("su3") + ["Return"])
                self.checkpoint(other, {"text": "你", "preedit": ""})
                self.focus(host)
                self.checkpoint(host, {"text": "你好", "preedit": ""})
            else:
                for step in case["steps"]:
                    self.send(host, step["keys"])
                    self.checkpoint(host, step["expect"])
            self.trace(action="end", keyboard=self.keyboard())
        except Exception as error:
            result.update(status="failed", error=str(error))
            self.trace(action="failure", error=str(error), keyboard=self.keyboard())
        finally:
            self.cleanup_hosts()
            # Retire a failed case's physical state only after preserving it.
            command("xdotool", "keyup", "Shift_L", "Shift_R", "Control_L", "Control_R", "Alt_L", "Alt_R", check=False)
            if "Caps Lock:   on" in command("xset", "q"):
                command("xdotool", "key", "Caps_Lock")
        result.update(seconds=round(time.monotonic() - started, 3), config_checks=self.gate_index)
        config.write_json(self.case_dir / "result.json", result)
        self.results.append(result)
        config.write_json(self.out / "matrix-results.json", self.results)
        print(f"{len(self.results)} {name}: {result['status']}" + (": " + result["error"] if "error" in result else ""), flush=True)

    def run(self):
        if os.environ.get("KEYKEY_E2E_SESSION_MODE", "managed") != "managed":
            raise RuntimeError("Matrix may only use its private managed display")
        config.write_json(self.out / "shared-cases.json", self.fixture)
        categories = os.environ.get("KEYKEY_E2E_DESKTOP_CATEGORIES", "settings,boundary,stability").split(",")
        toolkits = os.environ.get("KEYKEY_E2E_DESKTOP_TOOLKITS", "GTK3,GTK4,QT6").split(",")
        rounds = int(os.environ.get("KEYKEY_E2E_DESKTOP_ROUNDS", str(self.fixture["stability_rounds"])))
        if not categories or set(categories) - {"settings", "boundary", "stability"}:
            raise ValueError("Unknown or empty desktop test categories")
        if not toolkits or set(toolkits) - HOSTS.keys() or rounds < 1:
            raise ValueError("Unknown host toolkit or invalid round count")
        config.write_json(self.out / "matrix-run.json", {
            "profile": self.profile, "categories": categories, "toolkits": toolkits,
            "rounds": rounds, "key_delay_ms": int(os.environ.get("KEYKEY_E2E_KEY_DELAY_MS", "35")),
            "model_sha256": self.model_sha256,
        })
        for toolkit in toolkits:
            # A real keyboard-US control confirms the host receives literal keys.
            control = {"id": "CONTROL-KEYBOARD-US", "category": "control", "preferences": {},
                       "steps": [{"keys": list("su3cl3"), "expect": {"text": "su3cl3", "preedit": ""}}]}
            self.run_case(toolkit, control)
            for case in self.fixture["cases"]:
                if case["category"] not in categories:
                    continue
                for index in range(1, (rounds if case["category"] == "stability" else 1) + 1):
                    self.run_case(toolkit, case, index)
        self.x11.XCloseDisplay(self.display)
        return int(any(r["status"] != "passed" for r in self.results))


if __name__ == "__main__":
    sys.exit(Matrix().run())
