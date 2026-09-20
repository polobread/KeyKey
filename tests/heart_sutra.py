#!/usr/bin/env python3
"""Shared, full-length functional typing oracle for the five input methods."""

from __future__ import annotations

import argparse
import difflib
from pathlib import Path
import sys
import unicodedata


ROOT = Path(__file__).resolve().parent
FIXTURE = ROOT / "heart-sutra.annotated.txt"
DICTIONARY = ROOT.parent / "Source/DataTables/bpmf-ext.cin"
PLATFORMS = ("macos", "windows", "android", "ios", "linux")
PUNCTUATION = frozenset("，。、；：？！「」『』（）")
TONE_MARKS = frozenset("ˊˇˋ˙")


def is_reading(value: str) -> bool:
    return bool(value) and all(
        "\u3105" <= character <= "\u3129" or character in TONE_MARKS
        for character in value
    )


def parse_fixture(source: str) -> tuple[str, list[tuple[str, str]]]:
    lines: list[str] = []
    pairs: list[tuple[str, str]] = []
    for line_number, line in enumerate(source.splitlines(), 1):
        if not line.strip():
            lines.append("")
            continue
        tokens = line.split()
        if len(tokens) % 2:
            raise ValueError(f"line {line_number}: reading/character pair is incomplete")
        output: list[str] = []
        for index in range(0, len(tokens), 2):
            reading, target = tokens[index:index + 2]
            if not is_reading(reading):
                raise ValueError(f"line {line_number}: invalid Bopomofo reading {reading!r}")
            if not target or not ("\u3400" <= target[0] <= "\u9fff"):
                raise ValueError(f"line {line_number}: invalid target character {target!r}")
            if any(character not in PUNCTUATION for character in target[1:]):
                raise ValueError(f"line {line_number}: unexpected text after {target[0]}")
            output.append(target)
            pairs.append((reading, target[0]))
        lines.append("".join(output))
    if len(pairs) < 250:
        raise ValueError(f"fixture is too short: only {len(pairs)} syllables")
    return "\n".join(lines) + "\n", pairs


def candidate_positions(pairs: list[tuple[str, str]]) -> list[int]:
    key_map: dict[str, str] = {}
    entries: dict[str, list[str]] = {}
    section = ""
    for raw_line in DICTIONARY.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line == "%keyname  begin":
            section = "keys"
            continue
        if line == "%keyname  end":
            section = ""
            continue
        if line == "%chardef  begin":
            section = "characters"
            continue
        if line == "%chardef  end":
            break
        columns = line.split()
        if section == "keys" and len(columns) == 2:
            key_map[columns[1]] = columns[0]
        elif section == "characters" and len(columns) >= 2:
            entries.setdefault(columns[0], []).append(columns[1])
    missing = []
    positions = []
    for reading, character in pairs:
        key = "".join(key_map[symbol] for symbol in reading)
        candidates = entries.get(key, [])
        if character not in candidates:
            missing.append((reading, character))
        else:
            positions.append(candidates.index(character) + 1)
    if missing:
        print(f"FAIL dictionary: {len(missing)} missing readings", file=sys.stderr)
        for reading, character in sorted(set(missing)):
            print(f"  {reading} {character}", file=sys.stderr)
        raise ValueError("the shared CIN cannot type the whole fixture")
    return positions


def check_positions(
    expected_pairs: list[tuple[str, str]], expected_positions: list[int],
    path: Path, platform: str,
) -> bool:
    rows = [line.split("\t") for line in path.read_text(encoding="utf-8").splitlines()]
    if len(rows) != len(expected_pairs):
        print(
            f"FAIL {platform} positions: expected {len(expected_pairs)} rows, got {len(rows)}",
            file=sys.stderr,
        )
        return False
    for index, (row, (reading, character), expected_rank) in enumerate(
        zip(rows, expected_pairs, expected_positions), 1
    ):
        if len(row) != 4 or row[:3] != [str(index), reading, character]:
            print(f"FAIL {platform} positions: row {index} has a wrong index or reading", file=sys.stderr)
            return False
        if not row[3].isdigit() or int(row[3]) != expected_rank:
            print(
                f"FAIL {platform} positions: row {index} {reading} {character}: "
                f"expected rank {expected_rank}, observed {row[3]!r}",
                file=sys.stderr,
            )
            return False
    print(f"PASS {platform} positions: all {len(rows)} candidate ranks match the shared CIN")
    return True


def compact(value: str) -> str:
    """Ignore editor line wrapping, but preserve every character and punctuation mark."""
    return "".join(
        character for character in unicodedata.normalize("NFC", value)
        if not character.isspace()
    )


def compare(expected: str, actual: str, platform: str) -> bool:
    expected_text, actual_text = compact(expected), compact(actual)
    if expected_text == actual_text:
        print(f"PASS {platform}: {len(expected_text)} characters and marks match")
        return True
    print(
        f"FAIL {platform}: expected {len(expected_text)} characters and marks, "
        f"received {len(actual_text)}",
        file=sys.stderr,
    )
    difference = difflib.SequenceMatcher(None, expected_text, actual_text, autojunk=False)
    for tag, left_start, left_end, right_start, right_end in difference.get_opcodes():
        if tag == "equal":
            continue
        print(
            f"  {tag} at expected position {left_start + 1}: "
            f"{expected_text[left_start:left_end]!r} -> "
            f"{actual_text[right_start:right_end]!r}",
            file=sys.stderr,
        )
        break
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("render", help="print the expected Chinese text")
    commands.add_parser("check-dictionary", help="check each reading against the shared CIN")
    commands.add_parser("plan", help="print reading, target, and expected candidate rank")
    commands.add_parser("template", help="print a blank 268-row observed-rank form")
    single = commands.add_parser("check", help="check one platform's typed capture")
    single.add_argument("platform", choices=PLATFORMS)
    single.add_argument("capture", type=Path)
    single.add_argument("positions", type=Path)
    all_platforms = commands.add_parser("check-all", help="require all five captures")
    all_platforms.add_argument("capture_directory", type=Path)
    args = parser.parse_args()

    try:
        expected, pairs = parse_fixture(FIXTURE.read_text(encoding="utf-8"))
        positions = candidate_positions(pairs)
        if args.command == "render":
            sys.stdout.write(expected)
            print(f"{len(pairs)} annotated syllables", file=sys.stderr)
            return 0
        if args.command == "check-dictionary":
            print(f"PASS dictionary: all {len(pairs)} annotated readings are present")
            return 0
        if args.command == "plan":
            print("#\treading\ttarget\texpected-rank")
            for number, ((reading, character), rank) in enumerate(zip(pairs, positions), 1):
                print(f"{number}\t{reading}\t{character}\t{rank}")
            return 0
        if args.command == "template":
            for number, (reading, character) in enumerate(pairs, 1):
                print(f"{number}\t{reading}\t{character}\t?")
            return 0
        if args.command == "check":
            text_ok = compare(
                expected, args.capture.read_text(encoding="utf-8"), args.platform
            )
            positions_ok = check_positions(pairs, positions, args.positions, args.platform)
            return 0 if text_ok and positions_ok else 1
        passed = True
        for platform in PLATFORMS:
            capture = args.capture_directory / f"{platform}.txt"
            position_capture = args.capture_directory / f"{platform}.positions.tsv"
            if not capture.is_file() or not position_capture.is_file():
                print(f"MISSING {platform}: {capture} or {position_capture}", file=sys.stderr)
                passed = False
                continue
            text_ok = compare(expected, capture.read_text(encoding="utf-8"), platform)
            positions_ok = check_positions(pairs, positions, position_capture, platform)
            passed = text_ok and positions_ok and passed
        return 0 if passed else 1
    except (OSError, UnicodeError, ValueError) as error:
        print(f"heart-sutra: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
