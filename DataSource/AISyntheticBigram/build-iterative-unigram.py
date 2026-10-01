#!/usr/bin/env python3
"""Generate project unigram counts by repeated Viterbi segmentation and recounting."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path

from typing_batch import load_manifest_articles
from typing_cost import REPO, sha256, write_json


MAX_WORD_LENGTH = 7
HAN_RUN = __import__("re").compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+")
BASE_COUNTS = REPO / "DataSource/McBopomofo/phrase.occ"


def read_counts(path: Path, *, allow_zero=False, replace_duplicates=False,
                skip_out_of_range=False) -> tuple[list[str], dict[str, int]]:
    order, counts = [], {}
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        fields = raw.split()
        minimum = 0 if allow_zero else 1
        if len(fields) != 2 or not fields[1].isdigit() or int(fields[1]) < minimum:
            raise ValueError(f"{path}:{line_number}: expected WORD count >= {minimum}")
        word = fields[0]
        if word in counts:
            if not replace_duplicates:
                raise ValueError(f"{path}:{line_number}: duplicate word {word!r}")
            counts[word] = int(fields[1])
            continue
        if not 1 <= len(word) <= MAX_WORD_LENGTH:
            if skip_out_of_range:
                continue
            raise ValueError(f"{path}:{line_number}: word length outside 1..{MAX_WORD_LENGTH}")
        order.append(word)
        counts[word] = int(fields[1])
    if not counts:
        raise ValueError("Initial unigram file is empty")
    return order, counts


def blend_counts(order: list[str], project_counts: dict[str, int],
                 prior_counts: dict[str, int], project_weight: float, scale: int):
    if not 0 < project_weight < 1:
        raise ValueError("project_weight must be strictly between zero and one")
    if scale < 1_000_000:
        raise ValueError("scale must be at least one million")
    project_total = sum(project_counts.values())
    normalized_prior = {word: prior_counts.get(word, 1) for word in order}
    prior_total = sum(normalized_prior.values())
    blended = {}
    for word in order:
        probability = (
            project_weight * project_counts[word] / project_total
            + (1 - project_weight) * normalized_prior[word] / prior_total
        )
        blended[word] = max(1, round(probability * scale))
    return blended


def segment_run(run: str, log_probabilities: dict[str, float]) -> tuple[str | None, ...]:
    size = len(run)
    scores = [-math.inf] * (size + 1)
    paths: list[tuple[str | None, ...] | None] = [None] * (size + 1)
    scores[0], paths[0] = 0.0, ()
    for position in range(size):
        if paths[position] is None:
            continue
        matched = False
        for length in range(1, min(MAX_WORD_LENGTH, size - position) + 1):
            word = run[position:position + length]
            probability = log_probabilities.get(word)
            if probability is None:
                continue
            matched = True
            end = position + length
            score = scores[position] + probability
            if score > scores[end]:
                scores[end] = score
                paths[end] = paths[position] + (word,)
        if not matched and scores[position] > scores[position + 1]:
            scores[position + 1] = scores[position]
            paths[position + 1] = paths[position] + (None,)
    return paths[size] or ()


def segment_corpus(runs: list[str], counts: dict[str, int]):
    total = sum(counts.values())
    probabilities = {word: math.log10(count / total) for word, count in counts.items()}
    segmentations, observed = [], Counter()
    digest = hashlib.sha256()
    tokens = unknown = 0
    corpus_score = 0.0
    for run in runs:
        segmentation = segment_run(run, probabilities)
        segmentations.append(segmentation)
        for token in segmentation:
            digest.update((token or "<UNK>").encode("utf-8"))
            digest.update(b"\0")
            if token is None:
                unknown += 1
            else:
                observed[token] += 1
                tokens += 1
                corpus_score += probabilities[token]
        digest.update(b"\n")
    return segmentations, observed, {
        "segmentation_sha256": digest.hexdigest(),
        "tokens": tokens,
        "unknown_characters": unknown,
        "observed_vocabulary_entries": len(observed),
        "corpus_log10_score_under_input_counts": corpus_score,
    }


def build(training_manifest: Path, initial_counts: Path, output: Path,
          floor: int = 1, max_iterations: int = 10, prior_counts_path: Path = BASE_COUNTS,
          project_weight: float = 0.75, scale: int = 100_000_000):
    if floor < 1:
        raise ValueError("floor must be at least one")
    if max_iterations < 1:
        raise ValueError("max_iterations must be at least one")
    manifest = json.loads(training_manifest.read_text(encoding="utf-8"))
    if manifest.get("cohort") != "training" or manifest.get("role") != "model training only":
        raise ValueError("Expected the frozen training cohort manifest")
    articles = load_manifest_articles(manifest)
    runs = [run for article in articles for run in HAN_RUN.findall(article["text"])]
    order, counts = read_counts(initial_counts)
    _, prior_counts = read_counts(
        prior_counts_path, allow_zero=True, replace_duplicates=True, skip_out_of_range=True)
    history, previous_segmentations = [], None
    converged = False
    for iteration in range(1, max_iterations + 1):
        segmentations, observed, metrics = segment_corpus(runs, counts)
        changed_runs = (len(runs) if previous_segmentations is None else
                        sum(before != after for before, after in zip(previous_segmentations, segmentations)))
        raw_project_counts = {word: max(floor, observed[word]) for word in order}
        next_counts = blend_counts(order, raw_project_counts, prior_counts, project_weight, scale)
        row = {
            "iteration": iteration,
            "changed_runs_from_previous_iteration": changed_runs,
            "raw_project_total_count": sum(raw_project_counts.values()),
            "blended_output_total_count": sum(next_counts.values()),
            "unobserved_entries_at_floor": sum(observed[word] == 0 for word in order),
            **metrics,
        }
        history.append(row)
        if previous_segmentations is not None and changed_runs == 0:
            converged = True
            counts = next_counts
            break
        previous_segmentations = segmentations
        counts = next_counts
    content = "\n".join(f"{word} {counts[word]}" for word in order) + "\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content, encoding="utf-8")
    report = {
        "method": "hard-EM-style repeated Viterbi segmentation and occurrence recounting",
        "training_manifest": str(training_manifest),
        "training_manifest_sha256": sha256(training_manifest),
        "training_articles": len(articles),
        "han_runs": len(runs),
        "han_characters": sum(map(len, runs)),
        "initial_counts": {"file": str(initial_counts), "sha256": sha256(initial_counts)},
        "public_prior": {"file": str(prior_counts_path), "sha256": sha256(prior_counts_path)},
        "project_weight": project_weight,
        "public_prior_weight": 1 - project_weight,
        "integer_scale": scale,
        "floor": floor,
        "max_iterations": max_iterations,
        "iterations_run": len(history),
        "converged": converged,
        "history": history,
        "output": {
            "file": output.name,
            "sha256": hashlib.sha256(content.encode()).hexdigest(),
            "vocabulary_entries": len(order),
            "total_count": sum(counts.values()),
        },
        "scope": (
            "Only the frozen 800-article training cohort and the global initial model are used; "
            "no validation/test text, article IDs, errors, or word-specific patches are inputs."
        ),
    }
    write_json(output.with_suffix(".report.json"), report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--training", type=Path, required=True)
    parser.add_argument("--initial-counts", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--floor", type=int, default=1)
    parser.add_argument("--max-iterations", type=int, default=10)
    parser.add_argument("--prior-counts", type=Path, default=BASE_COUNTS)
    parser.add_argument("--project-weight", type=float, default=0.75)
    parser.add_argument("--scale", type=int, default=100_000_000)
    args = parser.parse_args()
    try:
        if args.output.exists() or args.output.with_suffix(".report.json").exists():
            raise ValueError("Refuse to overwrite an existing iterative unigram experiment")
        report = build(args.training, args.initial_counts, args.output, args.floor, args.max_iterations,
                       args.prior_counts, args.project_weight, args.scale)
        print(json.dumps(report, ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
