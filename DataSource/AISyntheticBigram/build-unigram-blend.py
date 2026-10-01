#!/usr/bin/env python3
"""Create a global Bayesian-style blend of frozen public prior and project counts."""
import argparse
import hashlib
import json
from pathlib import Path

from typing_cost import REPO, sha256, write_json


BASE = REPO / "DataSource/McBopomofo/phrase.occ"


def read_counts(path: Path, *, allow_zero=False, replace_duplicates=False):
    order, counts = [], {}
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        fields = raw.split()
        minimum = 0 if allow_zero else 1
        if len(fields) != 2 or not fields[1].isdigit() or int(fields[1]) < minimum:
            kind = "NONNEGATIVE_COUNT" if allow_zero else "POSITIVE_COUNT"
            raise ValueError(f"{path}:{line_number}: expected WORD {kind}")
        if fields[0] in counts:
            if not replace_duplicates:
                raise ValueError(f"{path}:{line_number}: duplicate word {fields[0]!r}")
        else:
            order.append(fields[0])
        counts[fields[0]] = int(fields[1])
    return order, counts


def build(project: Path, output: Path, project_weight: float, scale: int):
    if not 0 < project_weight < 1:
        raise ValueError("project weight must be strictly between zero and one")
    if scale < 1_000_000:
        raise ValueError("scale must be at least one million to retain rare vocabulary")
    order, project_counts = read_counts(project)
    # Match SmartMandarinCooker: zero-count rows are ignored and a later
    # duplicate occurrence replaces an earlier one.
    _, raw_base = read_counts(BASE, allow_zero=True, replace_duplicates=True)
    base_counts = {word: raw_base.get(word, 1) for word in order}
    base_total, project_total = sum(base_counts.values()), sum(project_counts.values())
    counts = {}
    for word in order:
        probability = ((1 - project_weight) * base_counts[word] / base_total
                       + project_weight * project_counts[word] / project_total)
        counts[word] = max(1, round(probability * scale))
    content = "\n".join(f"{word} {counts[word]}" for word in order) + "\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content, encoding="utf-8")
    report = {"method": "global normalized probability blend", "project_weight": project_weight,
              "public_prior_weight": 1 - project_weight, "integer_scale": scale,
              "vocabulary_entries": len(order), "base_total_before_normalization": base_total,
              "project_total_before_normalization": project_total, "output_total": sum(counts.values()),
              "base": {"file": str(BASE.relative_to(REPO)), "sha256": sha256(BASE)},
              "project": {"file": str(project), "sha256": sha256(project)},
              "output": {"file": output.name, "sha256": hashlib.sha256(content.encode()).hexdigest()},
              "scope": "One global mixture coefficient; no article IDs, errors or word-specific rules."}
    write_json(output.with_suffix(".report.json"), report)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--project-weight", type=float, required=True)
    parser.add_argument("--scale", type=int, default=100_000_000)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.output.exists() or args.output.with_suffix(".report.json").exists():
            raise ValueError("Refuse to overwrite an existing blend")
        print(json.dumps(build(args.project, args.output, args.project_weight, args.scale), ensure_ascii=False, indent=2))
    except (ValueError, OSError) as error:
        parser.exit(2, f"error: {error}\n")
