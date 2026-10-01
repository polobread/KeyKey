#!/usr/bin/env python3
"""Blend project counts with a stronger public prior for basic-character homophones."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from typing_cost import REPO, ROOT, query_for_reading, sha256, write_json


PUBLIC_COUNTS = REPO / "DataSource/McBopomofo/phrase.occ"
RANKED_CHARACTERS = ROOT / "common-single-character-pronunciations-1500.tsv"
BPMF_CIN = REPO / "Source/Distributions/Takao/DatabaseCooker/Intermediates/bpmf-ext-absorder.cin"


def read_counts(path, *, allow_zero=False, replace_duplicates=False):
    order, counts = [], {}
    minimum = 0 if allow_zero else 1
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        fields = raw.split()
        if len(fields) != 2 or not fields[1].isdigit() or int(fields[1]) < minimum:
            raise ValueError(f"{path}:{line_number}: expected WORD count >= {minimum}")
        word = fields[0]
        if word in counts:
            if not replace_duplicates:
                raise ValueError(f"{path}:{line_number}: duplicate word {word!r}")
            counts[word] = int(fields[1])
            continue
        order.append(word)
        counts[word] = int(fields[1])
    if not order:
        raise ValueError(f"{path}: empty count model")
    return order, counts


def normalize_reading(value):
    """Convert dictionary-style leading neutral tone to the engine's trailing form."""
    return value[1:] + "˙" if value.startswith("˙") else value


def load_basic_queries(path=RANKED_CHARACTERS, rank_limit=100):
    rows = []
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line_number == 1:
            continue
        fields = raw.split("\t")
        if len(fields) < 3 or not fields[0].isdigit() or len(fields[1]) != 1:
            raise ValueError(f"{path}:{line_number}: invalid ranked-character row")
        rank = int(fields[0])
        if rank <= rank_limit:
            rows.append((rank, fields[1], query_for_reading(normalize_reading(fields[2]))))
    if [rank for rank, _, _ in rows] != list(range(1, rank_limit + 1)):
        raise ValueError(f"{path}: expected contiguous ranks 1–{rank_limit}")
    return rows


def load_character_queries(path=BPMF_CIN):
    result = {}
    in_definitions = False
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("%chardef  begin"):
            in_definitions = True
            continue
        if raw.startswith("%chardef  end"):
            break
        if not in_definitions:
            continue
        fields = raw.split()
        if len(fields) == 2 and len(fields[1]) == 1:
            result.setdefault(fields[1], set()).add(fields[0])
    if not result:
        raise ValueError(f"{path}: no character queries")
    return result


def tiered_blend(order, project_counts, public_counts, character_queries, basic_queries,
                 basic_weight, default_weight, scale, *, basic_characters=None,
                 competitor_weight=None):
    competitor_weight = basic_weight if competitor_weight is None else competitor_weight
    basic_characters = set() if basic_characters is None else set(basic_characters)
    if not 0 <= competitor_weight <= basic_weight <= default_weight < 1:
        raise ValueError("Expected 0 <= competitor weight <= basic weight <= default weight < 1")
    if scale < 1_000_000:
        raise ValueError("scale must be at least one million")
    project_total = sum(project_counts[word] for word in order)
    public = {word: public_counts.get(word, 1) for word in order}
    public_total = sum(public.values())
    affected = {
        word for word in order
        if len(word) == 1 and character_queries.get(word, set()).intersection(basic_queries)
    }
    probabilities = {}
    for word in order:
        if word in basic_characters:
            weight = basic_weight
        elif word in affected:
            weight = competitor_weight
        else:
            weight = default_weight
        probabilities[word] = ((1 - weight) * public[word] / public_total
                               + weight * project_counts[word] / project_total)
    probability_total = sum(probabilities.values())
    counts = {word: max(1, round(probabilities[word] / probability_total * scale)) for word in order}
    return counts, affected


def build(project, output, basic_weight, default_weight=0.25, scale=100_000_000,
          public_counts_path=PUBLIC_COUNTS, ranked_path=RANKED_CHARACTERS, cin_path=BPMF_CIN,
          competitor_weight=None):
    order, project_counts = read_counts(project)
    _, public_counts = read_counts(public_counts_path, allow_zero=True, replace_duplicates=True)
    basic_rows = load_basic_queries(ranked_path)
    basic_characters = {character for _, character, _ in basic_rows}
    basic_queries = {query for _, _, query in basic_rows}
    character_queries = load_character_queries(cin_path)
    counts, affected = tiered_blend(
        order, project_counts, public_counts, character_queries, basic_queries,
        basic_weight, default_weight, scale, basic_characters=basic_characters,
        competitor_weight=competitor_weight)
    applied_competitor_weight = basic_weight if competitor_weight is None else competitor_weight
    competitors = affected - basic_characters
    content = "\n".join(f"{word} {counts[word]}" for word in order) + "\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content, encoding="utf-8")
    report = {
        "method": (
            "Normalized project/public blend with one lower project weight for every single-character "
            "candidate sharing a local Bopomofo query with any independently ranked top-100 character."
        ),
        "basic_homophone_project_weight": basic_weight,
        "nonbasic_homophone_competitor_project_weight": applied_competitor_weight,
        "default_project_weight": default_weight,
        "integer_scale": scale,
        "basic_rank_limit": 100,
        "basic_characters": len(basic_rows),
        "basic_queries": len(basic_queries),
        "affected_single_characters": len(affected),
        "affected_basic_characters": len(affected.intersection(basic_characters)),
        "affected_nonbasic_competitors": len(competitors),
        "affected_character_sha256": hashlib.sha256("".join(sorted(affected)).encode()).hexdigest(),
        "project": {"file": str(project), "sha256": sha256(project),
                    "entries": len(order), "total_count": sum(project_counts.values())},
        "public_counts": {"file": str(public_counts_path), "sha256": sha256(public_counts_path)},
        "ranked_characters": {"file": str(ranked_path), "sha256": sha256(ranked_path)},
        "bopomofo_mapping": {"file": str(cin_path), "sha256": sha256(cin_path)},
        "output": {"file": str(output), "sha256": hashlib.sha256(content.encode()).hexdigest(),
                   "entries": len(order), "total_count": sum(counts.values())},
        "scope": (
            "Weights and rank boundary are fixed by character class. The rule uses no evaluation article IDs, "
            "text, correction reports, target words, or character-specific score patches. Every ranked top-100 "
            "character and every nonbasic competitor class receive their respective global weight."
        ),
    }
    write_json(output.with_suffix(".report.json"), report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--basic-weight", type=float, required=True)
    parser.add_argument("--competitor-weight", type=float,
                        help="project weight for non-top-100 characters in affected homophone groups")
    parser.add_argument("--default-weight", type=float, default=0.25)
    parser.add_argument("--scale", type=int, default=100_000_000)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.output.exists() or args.output.with_suffix(".report.json").exists():
            raise ValueError("Refuse to overwrite an existing tiered-homophone experiment")
        print(json.dumps(build(args.project, args.output, args.basic_weight,
                               args.default_weight, args.scale,
                               competitor_weight=args.competitor_weight), ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
