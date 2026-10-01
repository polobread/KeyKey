#!/usr/bin/env python3
"""Add one global raw-character prior to a trained word unigram model."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

from typing_batch import load_manifest_articles
from typing_cost import sha256, write_json


HAN_RUN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+")


def read_counts(path):
    order, counts = [], {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        fields = line.split()
        if len(fields) != 2 or not fields[1].isdigit() or int(fields[1]) < 1 or fields[0] in counts:
            raise ValueError(f"{path}:{number}: expected unique WORD POSITIVE_COUNT")
        order.append(fields[0])
        counts[fields[0]] = int(fields[1])
    if not counts:
        raise ValueError(f"{path}: empty count model")
    return order, counts


def blend_character_prior(order, base_counts, character_counts, weight, scale):
    if not 0 < weight < 1:
        raise ValueError("character weight must be strictly between zero and one")
    if scale < 1_000_000:
        raise ValueError("scale must be at least one million")
    single_characters = [word for word in order if len(word) == 1]
    if not single_characters:
        raise ValueError("count model has no single-character entries")
    smoothed_characters = {character: max(1, character_counts[character])
                           for character in single_characters}
    base_total = sum(base_counts.values())
    character_total = sum(smoothed_characters.values())
    output = {}
    for word in order:
        probability = (1 - weight) * base_counts[word] / base_total
        if len(word) == 1:
            probability += weight * smoothed_characters[word] / character_total
        output[word] = max(1, round(probability * scale))
    return output


def build(training_manifest, base, output, weight, scale=100_000_000):
    manifest = json.loads(training_manifest.read_text(encoding="utf-8"))
    if manifest.get("cohort") != "training" or manifest.get("role") != "model training only":
        raise ValueError("Expected the frozen training cohort manifest")
    articles = load_manifest_articles(manifest)
    character_counts = Counter(character for article in articles
                               for run in HAN_RUN.findall(article["text"])
                               for character in run)
    order, base_counts = read_counts(base)
    counts = blend_character_prior(order, base_counts, character_counts, weight, scale)
    content = "\n".join(f"{word} {counts[word]}" for word in order) + "\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content, encoding="utf-8")
    base_character_mass = sum(count for word, count in base_counts.items() if len(word) == 1) / sum(base_counts.values())
    output_character_mass = sum(count for word, count in counts.items() if len(word) == 1) / sum(counts.values())
    report = {
        "method": "global interpolation with raw single-character frequency",
        "character_weight": weight,
        "word_model_weight": 1 - weight,
        "integer_scale": scale,
        "training_manifest": str(training_manifest),
        "training_manifest_sha256": sha256(training_manifest),
        "training_articles": len(articles),
        "training_han_characters": sum(character_counts.values()),
        "base": {"file": str(base), "sha256": sha256(base), "character_probability_mass": base_character_mass},
        "output": {"file": str(output), "sha256": hashlib.sha256(content.encode()).hexdigest(),
                   "entries": len(counts), "total_count": sum(counts.values()),
                   "character_probability_mass": output_character_mass},
        "scope": (
            "The same coefficient applies to every one-character vocabulary entry. Only raw character counts "
            "from the frozen 800-article training cohort are used; the common-character audit and both 750-article "
            "cohorts are not model inputs."
        ),
    }
    write_json(output.with_suffix(".report.json"), report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--training", type=Path, required=True)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--character-weight", type=float, required=True)
    parser.add_argument("--scale", type=int, default=100_000_000)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.output.exists() or args.output.with_suffix(".report.json").exists():
            raise ValueError("Refuse to overwrite an existing character-aware experiment")
        print(json.dumps(build(args.training, args.base, args.output, args.character_weight, args.scale),
                         ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
