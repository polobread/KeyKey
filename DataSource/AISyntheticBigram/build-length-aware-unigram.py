#!/usr/bin/env python3
"""Restore the public single-character distribution while keeping project phrase counts."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from typing_cost import ROOT, sha256, write_json


BASE_COUNTS = ROOT.parent / "McBopomofo" / "phrase.occ"
MAX_WORD_LENGTH = 7


def read_counts(path: Path, *, allow_zero=False, replace_duplicates=False,
                skip_out_of_range=False):
    order, counts = [], {}
    minimum = 0 if allow_zero else 1
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        fields = raw.split()
        if len(fields) != 2 or not fields[1].isdigit() or int(fields[1]) < minimum:
            raise ValueError(f"{path}:{line_number}: expected WORD count >= {minimum}")
        word = fields[0]
        if not 1 <= len(word) <= MAX_WORD_LENGTH:
            if skip_out_of_range:
                continue
            raise ValueError(f"{path}:{line_number}: word length outside 1..{MAX_WORD_LENGTH}")
        if word in counts:
            if not replace_duplicates:
                raise ValueError(f"{path}:{line_number}: duplicate word {word!r}")
            counts[word] = int(fields[1])
            continue
        order.append(word)
        counts[word] = int(fields[1])
    if not order:
        raise ValueError(f"{path}: count file is empty")
    return order, counts


def allocate_exact(weights, total, order):
    weight_total = sum(weights[word] for word in order)
    if total < len(order) or weight_total <= 0:
        raise ValueError("Single-character mass cannot provide a positive count for every entry")
    distributable = total - len(order)
    exact = {word: distributable * weights[word] / weight_total for word in order}
    result = {word: 1 + math.floor(exact[word]) for word in order}
    remainder = total - sum(result.values())
    ranked = sorted(order, key=lambda word: (-(exact[word] - math.floor(exact[word])), word))
    for word in ranked[:remainder]:
        result[word] += 1
    return result


def restore_public_character_distribution(order, counts, public_counts):
    characters = [word for word in order if len(word) == 1]
    character_mass = sum(counts[word] for word in characters)
    weights = {word: max(1, public_counts.get(word, 0)) for word in characters}
    redistributed = allocate_exact(weights, character_mass, characters)
    result = dict(counts)
    result.update(redistributed)
    return result, {
        "characters": len(characters),
        "character_mass_before": character_mass,
        "character_mass_after": sum(redistributed.values()),
        "multi_character_mass_before": sum(counts[word] for word in order if len(word) > 1),
        "multi_character_mass_after": sum(result[word] for word in order if len(word) > 1),
        "public_zero_count_characters_smoothed_to_weight_one": sum(public_counts.get(word, 0) == 0
                                                                    for word in characters),
    }


def build(input_counts: Path, output: Path, public_counts_path: Path = BASE_COUNTS):
    order, counts = read_counts(input_counts)
    _, public_counts = read_counts(
        public_counts_path, allow_zero=True, replace_duplicates=True, skip_out_of_range=True)
    result, metrics = restore_public_character_distribution(order, counts, public_counts)
    if any(result[word] != counts[word] for word in order if len(word) > 1):
        raise ValueError("Length-aware policy changed a multi-character count")
    if sum(result.values()) != sum(counts.values()):
        raise ValueError("Length-aware policy changed total unigram mass")
    content = "\n".join(f"{word} {result[word]}" for word in order) + "\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content, encoding="utf-8")
    report = {
        "method": (
            "Keep every multi-character project count unchanged. Preserve the total single-character mass, "
            "but distribute it globally in proportion to public McBopomofo single-character counts; use weight "
            "one only for public zero-count characters."),
        "input": {"file": str(input_counts), "sha256": sha256(input_counts),
                  "entries": len(order), "total_count": sum(counts.values())},
        "public_counts": {"file": str(public_counts_path), "sha256": sha256(public_counts_path)},
        **metrics,
        "output": {"file": str(output), "sha256": hashlib.sha256(content.encode()).hexdigest(),
                   "entries": len(order), "total_count": sum(result.values())},
        "scope": (
            "This is one word-length rule over the complete vocabulary. It uses no article IDs, validation/test "
            "text, correction reports, ranked-character list, or character-specific weights."),
    }
    write_json(output.with_suffix(".report.json"), report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-counts", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--public-counts", type=Path, default=BASE_COUNTS)
    args = parser.parse_args()
    try:
        if args.output.exists() or args.output.with_suffix(".report.json").exists():
            raise ValueError("Refuse to overwrite an existing length-aware experiment")
        report = build(args.input_counts, args.output, args.public_counts)
        print(json.dumps(report, ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
