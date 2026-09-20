#!/usr/bin/env python3
"""Run the complete Heart Sutra through installed macOS IMK in TextEdit.

Run locally on the development Mac after selecting KeyKey and turning off all
association phrase collections. Every syllable is physically keyed, and each
selected character is checked against TextEdit's live accessibility text.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys
import time

from heart_sutra import FIXTURE, candidate_positions, parse_fixture


KEY_CODES = {
    **dict(zip("abcdefghijklmnopqrstuvwxyz", [
        0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46,
        45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6,
    ])),
    **dict(zip("0123456789", [29, 18, 19, 20, 21, 23, 22, 26, 28, 25])),
    ",": 43, "-": 27, ".": 47, "/": 44, ";": 41,
}
PUNCTUATION_KEY_CODES = {"，": 43, "。": 47, "、": 39, "；": 41}


def keymap() -> dict[str, str]:
    dictionary = FIXTURE.parent.parent / "Source/DataTables/bpmf-ext.cin"
    mapping: dict[str, str] = {}
    section = False
    for line in dictionary.read_text(encoding="utf-8").splitlines():
        if line.strip() == "%keyname  begin":
            section = True
        elif line.strip() == "%keyname  end":
            break
        elif section:
            columns = line.split()
            if len(columns) == 2:
                mapping[columns[1]] = columns[0]
    return mapping


def quoted(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def chunks() -> list[tuple[str, list[str]]]:
    _, pairs = parse_fixture(FIXTURE.read_text(encoding="utf-8"))
    ranks = candidate_positions(pairs)
    targets = [
        tokens[index + 1]
        for line in FIXTURE.read_text(encoding="utf-8").splitlines()
        for tokens in [line.split()]
        for index in range(0, len(tokens), 2)
    ]
    assert len(pairs) == len(ranks) == len(targets) == 268
    symbols = keymap()
    result: list[tuple[str, list[str]]] = []
    prefix = ""
    for start in range(0, len(pairs), 30):
        end = min(start + 30, len(pairs))
        rows: list[str] = []
        lines = [
            'tell application "System Events"',
            '  if (name of (first application process whose frontmost is true)) is not "TextEdit" then error "TextEdit lost focus"',
            f"  set expectedText to {quoted(prefix)}",
            '  if value of text area 1 of scroll area 1 of window 1 of process "TextEdit" is not expectedText then error "Wrong starting prefix"',
        ]
        for index in range(start, end):
            reading, character = pairs[index]
            target = targets[index]
            rank = ranks[index]
            for key in "".join(symbols[symbol] for symbol in reading):
                lines.append(f"  key code {KEY_CODES[key]}")
            if not any(mark in reading for mark in "ˊˇˋ˙"):
                lines.append("  key code 49")
            lines.append("  delay 0.04")
            for _ in range((rank - 1) // 9):
                lines.append("  key code 49")
            slot = (rank - 1) % 9 + 1
            if rank == 1:
                lines.append(
                    '  if (count of windows of process "chichi77 KeyKey") > 0 '
                    f"then key code {KEY_CODES[str(slot)]}"
                )
            else:
                lines.append(f"  key code {KEY_CODES[str(slot)]}")
            lines += [
                "  delay 0.03",
                '  if (count of windows of process "chichi77 KeyKey") is not 0 '
                f'then error "Candidate panel stayed open after syllable {index + 1}"',
                f"  set expectedText to expectedText & {quoted(character)}",
                '  if value of text area 1 of scroll area 1 of window 1 of process "TextEdit" '
                f'is not expectedText then error "Mismatch at syllable {index + 1}: {reading} {character}, rank {rank}"',
            ]
            prefix += character
            for mark in target[1:]:
                lines += [
                    f"  key code {PUNCTUATION_KEY_CODES[mark]} using control down",
                    f"  set expectedText to expectedText & {quoted(mark)}",
                    '  if value of text area 1 of scroll area 1 of window 1 of process "TextEdit" '
                    f'is not expectedText then error "Punctuation mismatch after syllable {index + 1}"',
                ]
                prefix += mark
            rows.append(f"{index + 1}\t{reading}\t{character}\t{rank}")
        lines += ["  return expectedText", "end tell"]
        result.append(("\n".join(lines) + "\n", rows))
    return result


def run() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--generate-only", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    generated = chunks()
    scripts = []
    for index, (source, _) in enumerate(generated, 1):
        path = output / f"macos-heart-sutra-{index:02d}.applescript"
        path.write_text(source, encoding="utf-8")
        subprocess.run(["osacompile", "-o", str(output / f"compiled-{index:02d}.scpt"), str(path)], check=True)
        scripts.append(path)
    if args.generate_only:
        print(f"PASS: generated and compiled {len(scripts)} AppleScript batches")
        return 0

    # Preserve the developer's settings. The required setup is checked rather
    # than changed, so a failed run cannot leave the machine reconfigured.
    setting = subprocess.run([
        "defaults", "read", "io.github.polobread.chichi77.AssociatedPhrase",
        "EnabledCollections",
    ], capture_output=True, text=True)
    if setting.returncode or setting.stdout.strip():
        parser.error("turn off every association phrase collection before running this test")
    app = Path("/Library/Input Methods/chichi77 KeyKey.app")
    if not app.is_dir():
        parser.error(f"input method was not installed: {app}")
    swift_cache = output / "swift-module-cache"
    swift_cache.mkdir(exist_ok=True)
    import os
    environment = dict(os.environ)
    environment["CLANG_MODULE_CACHE_PATH"] = str(swift_cache)
    environment["SWIFT_MODULE_CACHE_PATH"] = str(swift_cache)
    subprocess.run(["swift", str(Path(__file__).with_name("current_macos_input.swift"))],
                   check=True, env=environment)
    subprocess.run(["open", "-a", "TextEdit"], check=True)
    time.sleep(2)
    subprocess.run(["osascript", "-e", 'tell application "System Events" to set frontmost of process "TextEdit" to true',
                    "-e", 'tell application "System Events" to keystroke "n" using command down'], check=True)
    time.sleep(1)

    observed_rows: list[str] = []
    captured = ""
    for index, (script, (_, rows)) in enumerate(zip(scripts, generated), 1):
        result = subprocess.run(["osascript", str(script)], capture_output=True, text=True)
        if result.returncode:
            print(result.stderr, file=sys.stderr)
            print(f"FAIL macOS batch {index}; {len(observed_rows)} syllables verified", file=sys.stderr)
            return 1
        captured = result.stdout.rstrip("\n")
        observed_rows.extend(rows)
        print(f"PASS macOS batch {index}: {len(observed_rows)}/268 syllables", flush=True)
    (output / "macos.txt").write_text(captured + "\n", encoding="utf-8")
    (output / "macos.positions.tsv").write_text("\n".join(observed_rows) + "\n", encoding="utf-8")
    return subprocess.run([
        sys.executable, str(FIXTURE.parent / "heart_sutra.py"), "check", "macos",
        str(output / "macos.txt"), str(output / "macos.positions.tsv"),
    ]).returncode


if __name__ == "__main__":
    raise SystemExit(run())
