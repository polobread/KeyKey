#!/usr/bin/env python3
"""Explicit E2E preferences and a live Fcitx configuration gate before input.

The reviewed fixture is the expectation. Never learn expectations from a live
configuration: GUI/writer scenarios declare their intended changes separately.
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys


BASELINE = Path(__file__).with_name("fixtures") / "fcitx5-e2e-baseline.json"
CONFIG_URI = "fcitx://config/inputmethod/chichi77-keykey-bopomofo"


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n",
                          encoding="utf-8")


def flatten(value, prefix=""):
    result = {}
    for key, item in value.items():
        path = f"{prefix}/{key}" if prefix else key
        if isinstance(item, dict):
            result.update(flatten(item, path))
        else:
            result[path] = item
    return result


def apply_changes(config, changes):
    for change in changes:
        path, value = change.split("=", 1)
        target = config
        keys = path.split("/")
        for key in keys[:-1]:
            target = target[key]
        if keys[-1] not in target or isinstance(target[keys[-1]], dict):
            raise ValueError(f"Unknown preference: {path}")
        target[keys[-1]] = value


def stored_config(config):
    # The native UI groups General/Phonetic/UserPhrases; INI keeps old paths.
    result = copy.deepcopy(config)
    for group in ("General", "Phonetic", "UserPhrases"):
        result.update(result.pop(group))
    return result


def write_ini(path, config):
    flat = flatten(stored_config(config))
    lines = [f"{key}={value}" for key, value in flat.items() if "/" not in key]
    sections = dict.fromkeys(key.rsplit("/", 1)[0] for key in flat if "/" in key)
    for section in sections:
        lines.extend(("", f"[{section}]"))
        lines.extend(f"{key.rsplit('/', 1)[1]}={value}" for key, value in flat.items()
                     if "/" in key and key.rsplit("/", 1)[0] == section)
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def variant(config):
    from gi.repository import GLib
    return GLib.Variant("a{sv}", {
        key: variant(value) if isinstance(value, dict) else GLib.Variant("s", value)
        for key, value in config.items()
    })


def live_config():
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    reply = bus.call_sync("org.fcitx.Fcitx5", "/controller",
                          "org.fcitx.Fcitx.Controller1", "GetConfig",
                          GLib.Variant("(s)", (CONFIG_URI,)), None,
                          Gio.DBusCallFlags.NONE, 10000, None)
    return reply.unpack()[0]


def check(expected, actual, baseline):
    wanted, observed = flatten(expected), flatten(actual)
    differences = []
    for key in sorted(wanted.keys() | observed.keys()):
        if key not in wanted:
            differences.append({"path": key, "error": "unreviewed-setting",
                                "actual": observed[key]})
        elif key not in observed:
            differences.append({"path": key, "error": "missing-setting",
                                "expected": wanted[key]})
        elif observed[key] != wanted[key]:
            differences.append({"path": key, "error": "value-mismatch",
                                "expected": wanted[key], "actual": observed[key]})
    base = flatten(baseline)
    return {
        "status": "failed" if differences else "passed",
        "setting_count": len(wanted),
        "expected_sha256": hashlib.sha256(json.dumps(
            expected, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
        "deviations_from_baseline": {k: v for k, v in wanted.items() if base.get(k) != v},
        "differences": differences, "expected": expected, "actual": actual,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "expect", "variant", "check"))
    parser.add_argument("--expected", required=True)
    parser.add_argument("--set", action="append", default=[])
    parser.add_argument("--collections")
    parser.add_argument("--ini")
    parser.add_argument("--output")
    parser.add_argument("--phase", default="pre-input")
    parser.add_argument("--case", default="setup")
    args = parser.parse_args()
    baseline = read_json(BASELINE)
    config = copy.deepcopy(baseline) if args.action == "prepare" else read_json(args.expected)
    apply_changes(config, args.set)
    if args.collections is not None:
        enabled = set(filter(None, args.collections.split(",")))
        unknown = enabled - config["AssociatedPhrases"].keys()
        if unknown:
            raise ValueError(f"Unknown collections: {sorted(unknown)}")
        config["AssociatedPhrases"] = {
            key: str(key in enabled) for key in config["AssociatedPhrases"]
        }
    if args.action in ("prepare", "expect"):
        write_json(args.expected, config)
        if args.ini:
            write_ini(args.ini, config)
    elif args.action == "variant":
        from gi.repository import GLib
        print(GLib.Variant("v", variant(stored_config(config))).print_(True))
    else:
        if not args.output:
            parser.error("check requires --output to preserve the readback evidence")
        result = check(config, live_config(), baseline)
        result.update(phase=args.phase, case=args.case)
        write_json(args.output, result)
        if result["differences"]:
            print(f"Fcitx configuration gate failed before input: {args.output}", file=sys.stderr)
            for difference in result["differences"]:
                print(json.dumps(difference, ensure_ascii=False), file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
