#!/usr/bin/env python3
"""Exercise real Fcitx FocusOut phases on the runner's private D-Bus daemon.

Unlike the direct-state C++ fixture, this includes Fcitx's ReservedFirst preedit
commit. Capability 50 promises a client-side commit; this raw client checks only
that the server does not also commit it. No desktop or panel signals are injected.
"""

import argparse
import copy
import json
import os
from pathlib import Path
import time
from urllib.parse import unquote

from gi.repository import Gio, GLib

from fcitx5_e2e_config import (BASELINE, CONFIG_URI, check, live_config, read_json,
                              stored_config, variant, write_json)


IC = "org.fcitx.Fcitx.InputContext1"
CONTROLLER = "org.fcitx.Fcitx.Controller1"
ENGINE = "chichi77-keykey-bopomofo"
PHRASES = (
    ("nihao", "su3cl3", ("你好",)),
    ("fangzai", "z;4y945k41u0 ", ("放在這邊",)),
    ("long", "fu/3ru84ul4fm4s83xu3j06sk7fm4c931u0 ",
     ("請假要去哪裡玩呢去海邊", "請假要去哪裡完呢去海邊")),
)


def require_private_session():
    address = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
    if not address:
        raise RuntimeError("An explicit private DBUS_SESSION_BUS_ADDRESS is required")
    desktop_bus = Path(f"/run/user/{os.getuid()}/bus")
    for entry in address.split(";"):
        if entry.startswith("unix:"):
            attributes = dict(part.split("=", 1) for part in entry[5:].split(",")
                              if "=" in part)
            if Path(unquote(attributes.get("path", ""))).resolve() == desktop_bus:
                raise RuntimeError("Refusing the normal desktop session bus")
    for name, usual in (("XDG_CONFIG_HOME", ".config"),
                        ("XDG_DATA_HOME", ".local/share")):
        directory = os.environ.get(name, "")
        if not directory or not Path(directory).is_absolute():
            raise RuntimeError(f"An explicit private absolute {name} is required")
        resolved = Path(directory).resolve()
        if resolved == (Path.home() / usual).resolve():
            raise RuntimeError(f"Refusing the normal desktop {name}")
        runtime = os.environ.get("KEYKEY_E2E_RUNTIME_ROOT")
        if runtime and not resolved.is_relative_to(Path(runtime).resolve()):
            raise RuntimeError(f"{name} must be inside KEYKEY_E2E_RUNTIME_ROOT")


class Probe:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.phase, self.events, self.commits, self.preedits = "setup", [], {}, {}
        self.filter_id = self.bus.add_filter(self.wire, None)
        self.subscription = self.bus.signal_subscribe(
            "org.fcitx.Fcitx5", IC, None, None, None,
            Gio.DBusSignalFlags.NONE, self.signal, None)

    def log(self, kind, **values):
        self.events.append(dict(time_monotonic=time.monotonic(), phase=self.phase,
                                kind=kind, **values))

    def wire(self, connection, message, incoming, data):
        if (incoming and message.get_message_type() == Gio.DBusMessageType.SIGNAL
                and message.get_interface() == IC
                and message.get_member() in ("CommitString", "NotifyFocusOut")):
            self.log("wire", path=message.get_path(), member=message.get_member(),
                     sender=message.get_sender(), serial=message.get_serial(),
                     value=message.get_body().unpack() if message.get_body() else ())
        return message

    def signal(self, connection, sender, path, interface, member, params, data):
        if path not in self.commits:
            return
        values = params.unpack()
        if member == "CommitString":
            self.commits[path].append(values[0])
        elif member == "UpdateFormattedPreedit":
            self.preedits[path] = "".join(part[0] for part in values[0])

    @staticmethod
    def pump():
        context = GLib.MainContext.default()
        deadline = time.monotonic() + .025
        while time.monotonic() < deadline:
            while context.pending():
                context.iteration(False)
            time.sleep(.001)

    def call(self, path, interface, method, signature=None, values=()):
        if method in ("FocusIn", "FocusOut", "Reset", "SetCurrentIM"):
            self.log("call", path=path, method=method, values=values)
        result = self.bus.call_sync(
            "org.fcitx.Fcitx5", path, interface, method,
            GLib.Variant(signature, values) if signature else None,
            None, Gio.DBusCallFlags.NONE, 10000, None).unpack()
        if method in ("FocusIn", "FocusOut", "Reset", "SetCurrentIM"):
            self.log("return", path=path, method=method)
        self.pump()
        return result

    def controller(self, method, signature=None, values=()):
        return self.call("/controller", CONTROLLER, method, signature, values)

    def focus(self, path):
        self.call(path, IC, "FocusIn")
        self.controller("SetCurrentIM", "(s)", (ENGINE,))
        self.controller("Activate")

    def keys(self, path, keys):
        for key in keys:
            for release in (False, True):
                self.call(path, IC, "ProcessKeyEvent", "(uuubu)",
                          (ord(key), 0, 0, release, 0))

    def case(self, phrase, capability, action, iteration):
        name, keys, accepted = phrase
        self.phase = f"{action}-cap{capability}-{name}-{iteration}"
        path = self.call("/org/freedesktop/portal/inputmethod",
                         "org.fcitx.Fcitx.InputMethod1", "CreateInputContext",
                         "(a(ss))", ([("program", "keykey-focusout-regression")],))[0]
        self.commits[path], self.preedits[path] = [], ""
        start = len(self.events)
        result = dict(case=self.phase, path=path, capability=capability,
                      phrase=name, action=action, status="failed")
        try:
            self.call(path, IC, "SetCapability", "(t)", (capability,))
            self.focus(path)
            self.keys(path, keys)
            prefix = list(self.commits[path])
            assert prefix == (["請假"] if name == "long" else []), prefix
            tail = self.preedits[path]
            if capability:
                assert "".join(prefix) + tail in accepted, (prefix, tail)
            self.phase = result["case"] + "/deactivate"
            if action == "focusout":
                self.call(path, IC, "FocusOut")
            else:
                self.controller("SetCurrentIM", "(s)", ("keyboard-us",))
            emitted = self.commits[path][len(prefix):]
            result.update(prefix=prefix, client_preedit=tail, emitted=emitted)
            if action == "focusout" and capability == 50:
                assert emitted == [], emitted
            else:
                assert len(emitted) == 1, emitted
                assert "".join(self.commits[path]) in accepted, self.commits[path]
            self.phase = result["case"] + "/retire-and-new-input"
            finished = list(self.commits[path])
            self.call(path, IC, "FocusOut")
            self.call(path, IC, "FocusOut")
            self.call(path, IC, "Reset")
            assert self.commits[path] == finished, self.commits[path]
            self.focus(path)
            self.keys(path, "su3cl3")
            if capability:
                assert self.preedits[path] == "你好", self.preedits[path]
            # ProcessKeyEvent uses X keysyms, not ASCII control characters.
            self.call(path, IC, "ProcessKeyEvent", "(uuubu)", (0xff0d, 0, 0, False, 0))
            self.call(path, IC, "ProcessKeyEvent", "(uuubu)", (0xff0d, 0, 0, True, 0))
            assert self.commits[path][len(finished):] == ["你好"], self.commits[path]
            result["status"] = "passed"
        except AssertionError as error:
            result["error"] = str(error)
        finally:
            self.call(path, IC, "Reset")
            self.call(path, IC, "FocusOut")
            self.call(path, IC, "DestroyIC")
            wire = [event for event in self.events[start:]
                    if event["kind"] == "wire" and event["path"] == path
                    and event["member"] == "CommitString"]
            result["wire_commits"] = wire
            result["all_commits"] = self.commits[path]
            identities = {(event["sender"], event["serial"]) for event in wire}
            if len(wire) != len(identities) or len(wire) != len(self.commits[path]):
                result.update(status="failed", error="wire/subscription count mismatch")
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected", type=Path, required=True)
    parser.add_argument("--rounds", type=int, default=1)
    parser.add_argument("--capability", type=int, choices=(0, 18, 50), action="append")
    parser.add_argument("--focusout-only", action="store_true")
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error("--rounds must be positive")
    require_private_session()
    args.output.mkdir(parents=True, exist_ok=True)
    original, baseline = live_config(), read_json(BASELINE)
    before = check(read_json(args.expected), original, baseline)
    write_json(args.output / "config-before.json", before)
    assert before["status"] == "passed", before["differences"]
    temporary = copy.deepcopy(baseline)
    temporary["General"]["PlaySoundOnTypingError"] = "False"
    temporary["Phonetic"]["BopomofoMode"] = "Smart"
    temporary["Phonetic"]["SmartMandarin"].update(
        LearnCandidateOverrides="False", LearnBigrams="False")
    temporary["UserPhrases"]["UseUserPhrases"] = "False"
    probe, results = Probe(), []
    try:
        probe.controller("SetConfig", "(sv)", (CONFIG_URI, variant(stored_config(temporary))))
        gate = check(temporary, live_config(), baseline)
        write_json(args.output / "config-temporary.json", gate)
        assert gate["status"] == "passed", gate["differences"]
        for iteration in range(1, args.rounds + 1):
            for capability in args.capability or (18, 50, 0):
                for phrase in PHRASES:
                    results.append(probe.case(phrase, capability, "focusout", iteration))
            if not args.focusout_only:
                for phrase in PHRASES:
                    results.append(probe.case(phrase, 18, "switch-input-method", iteration))
    finally:
        probe.controller("SetConfig", "(sv)", (CONFIG_URI, variant(stored_config(original))))
        restored = check(original, live_config(), baseline)
        write_json(args.output / "config-restored.json", restored)
        write_json(args.output / "results.json", results)
        with (args.output / "events.jsonl").open("w", encoding="utf-8") as stream:
            for event in probe.events:
                stream.write(json.dumps(event, ensure_ascii=False) + "\n")
        probe.bus.signal_unsubscribe(probe.subscription)
        probe.bus.remove_filter(probe.filter_id)
    summary = dict(cases=len(results), passed=sum(r["status"] == "passed" for r in results),
                   failed=sum(r["status"] != "passed" for r in results),
                   settings_restored=restored["status"] == "passed",
                   setting_count=restored["setting_count"])
    write_json(args.output / "summary.json", summary)
    print(json.dumps(summary))
    return 0 if summary["failed"] == 0 and summary["settings_restored"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
