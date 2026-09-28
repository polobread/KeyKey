#!/usr/bin/env python3
"""Prune globally unsupported multi-character entries from a unigram count file."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from typing_batch import load_manifest_articles
from typing_cost import ROOT, sha256, write_json


BASE_COUNTS = ROOT.parent / "McBopomofo" / "phrase.occ"
SUPPLEMENTS = (ROOT / "supplemental-lexicon.tsv", ROOT / "numeric-unit-lexicon.tsv")
MAX_WORD_LENGTH = 7
HAN_RUN = __import__("re").compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+")


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


def load_supplement_words(paths=SUPPLEMENTS):
    words = set()
    for path in paths:
        for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not raw.strip() or raw.startswith("詞\t"):
                continue
            fields = raw.split("\t")
            if len(fields) < 3 or not fields[1].isdigit():
                raise ValueError(f"{path}:{line_number}: invalid supplemental lexicon row")
            if 1 <= len(fields[0]) <= MAX_WORD_LENGTH:
                words.add(fields[0])
    return words


def observed_vocabulary(articles, vocabulary):
    """Find raw training substrings without using validation text or model errors."""
    allowed = set(vocabulary)
    observed = set()
    for article in articles:
        for run in HAN_RUN.findall(article["text"]):
            for start in range(len(run)):
                for length in range(2, min(MAX_WORD_LENGTH, len(run) - start) + 1):
                    word = run[start:start + length]
                    if word in allowed:
                        observed.add(word)
    return observed


def select_vocabulary(order, public_counts, observed, supplements):
    kept, removed, reasons = [], [], Counter()
    for word in order:
        matched = []
        if len(word) == 1:
            matched.append("single_character")
        if public_counts.get(word, 0) > 0:
            matched.append("positive_public_count")
        if word in observed:
            matched.append("observed_in_training")
        if word in supplements:
            matched.append("project_supplement")
        if matched:
            kept.append(word)
            reasons.update(matched)
        else:
            removed.append(word)
    return kept, removed, reasons


def build(training_manifest: Path, input_counts: Path, output: Path,
          public_counts_path: Path = BASE_COUNTS, supplement_paths=SUPPLEMENTS):
    manifest = json.loads(training_manifest.read_text(encoding="utf-8"))
    if manifest.get("cohort") != "training" or manifest.get("role") != "model training only":
        raise ValueError("Expected the frozen training cohort manifest")
    articles = load_manifest_articles(manifest)
    order, counts = read_counts(input_counts)
    _, public_counts = read_counts(
        public_counts_path, allow_zero=True, replace_duplicates=True, skip_out_of_range=True)
    supplements = load_supplement_words(supplement_paths)
    observed = observed_vocabulary(articles, order)
    kept, removed, reasons = select_vocabulary(order, public_counts, observed, supplements)
    if any(len(word) == 1 for word in removed):
        raise ValueError("Pruning policy removed a single-character entry")
    if supplements.intersection(order).difference(kept):
        raise ValueError("Pruning policy removed a project supplement")
    if observed.difference(kept):
        raise ValueError("Pruning policy removed vocabulary observed in training")
    content = "\n".join(f"{word} {counts[word]}" for word in kept) + "\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content, encoding="utf-8")
    removed_lengths = Counter(map(len, removed))
    report = {
        "method": (
            "Keep every single character, every word with positive public McBopomofo count, "
            "every raw substring observed in the frozen 800 training articles, and every KeyKey supplement; "
            "remove only unsupported zero-count multi-character entries."),
        "training_manifest": str(training_manifest),
        "training_manifest_sha256": sha256(training_manifest),
        "training_articles": len(articles),
        "input": {"file": str(input_counts), "sha256": sha256(input_counts),
                  "entries": len(order), "total_count": sum(counts.values())},
        "public_counts": {"file": str(public_counts_path), "sha256": sha256(public_counts_path)},
        "supplements": [{"file": str(path), "sha256": sha256(path)} for path in supplement_paths],
        "observed_multi_character_entries": len(observed),
        "supplement_entries": len(supplements),
        "keep_reason_matches": dict(sorted(reasons.items())),
        "kept_entries": len(kept),
        "removed_entries": len(removed),
        "removed_by_length": {str(length): count for length, count in sorted(removed_lengths.items())},
        "removed_count_mass": sum(counts[word] for word in removed),
        "output": {"file": str(output), "sha256": hashlib.sha256(content.encode()).hexdigest(),
                   "entries": len(kept), "total_count": sum(counts[word] for word in kept)},
        "scope": (
            "The rule was fixed from vocabulary provenance before validation scoring. It uses no validation/test "
            "article text, IDs, corrections, ranked-character list, or word-specific error patches."),
    }
    write_json(output.with_suffix(".report.json"), report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--training", type=Path, required=True)
    parser.add_argument("--input-counts", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--public-counts", type=Path, default=BASE_COUNTS)
    args = parser.parse_args()
    try:
        if args.output.exists() or args.output.with_suffix(".report.json").exists():
            raise ValueError("Refuse to overwrite an existing pruning experiment")
        report = build(args.training, args.input_counts, args.output, args.public_counts)
        print(json.dumps(report, ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
