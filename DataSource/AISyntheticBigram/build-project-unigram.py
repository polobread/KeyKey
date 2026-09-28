#!/usr/bin/env python3
"""Build project-owned unigram counts from training articles, excluding a frozen test cohort."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

from typing_cost import REPO, ROOT, sha256, write_json


ARTICLE_ROOT = ROOT.parent / "AISyntheticArticles"
BASE_COUNTS = REPO / "DataSource/McBopomofo/phrase.occ"
SUPPLEMENTS = (ROOT / "supplemental-lexicon.tsv", ROOT / "numeric-unit-lexicon.tsv")
SOURCES = ((2, 1650), (3, 350), (4, 300))
HAN_RUN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+")
MAX_WORD_LENGTH = 7


def load_population() -> tuple[list[dict], list[dict]]:
    population, sources = [], []
    for version, expected_count in SOURCES:
        path = ARTICLE_ROOT / f"typing-articles-v{version}.jsonl"
        rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
        prefix, width = ("tw-typing-", 5) if version == 2 else (f"tw-typing-v{version}-", 3)
        expected = [f"{prefix}{i:0{width}d}" for i in range(1, expected_count + 1)]
        if [row.get("prompt_id") for row in rows] != expected:
            raise ValueError(f"{path}: expected {expected_count} contiguous article IDs")
        population.extend(rows)
        sources.append({"file": path.name, "articles": len(rows), "sha256": sha256(path)})
    return population, sources


def load_vocabulary() -> tuple[list[str], dict]:
    order, seen = [], set()
    for raw in BASE_COUNTS.read_text(encoding="utf-8").splitlines():
        fields = raw.split()
        if len(fields) != 2 or not fields[1].isdigit() or not 1 <= len(fields[0]) <= MAX_WORD_LENGTH:
            continue
        if fields[0] not in seen:
            seen.add(fields[0])
            order.append(fields[0])
    supplement_rows = 0
    for path in SUPPLEMENTS:
        for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not raw.strip() or raw.startswith("詞\t"):
                continue
            fields = raw.split("\t")
            if len(fields) < 3 or not fields[1].isdigit():
                raise ValueError(f"{path}:{line_number}: invalid supplemental lexicon row")
            word = fields[0]
            if not 1 <= len(word) <= MAX_WORD_LENGTH:
                continue
            supplement_rows += 1
            if word not in seen:
                seen.add(word)
                order.append(word)
    return order, {"base_file": str(BASE_COUNTS.relative_to(REPO)), "base_sha256": sha256(BASE_COUNTS),
                   "supplements": [{"file": str(path.relative_to(REPO)), "sha256": sha256(path)} for path in SUPPLEMENTS],
                   "vocabulary_entries": len(order), "supplement_rows": supplement_rows}


def corpus_lines(text: str) -> list[str]:
    result = []
    for raw in text.splitlines():
        line = re.sub(r"^(?:#{1,6}|>|[-*+])\s*", "", raw.strip())
        if HAN_RUN.search(line):
            result.append(line)
    return result


def build_counts(articles: list[dict], vocabulary: list[str], method: str, floor: int) -> tuple[Counter, dict]:
    allowed = set(vocabulary)
    counts = Counter()
    han_characters = runs = substring_matches = 0
    for article in articles:
        article_words = Counter()
        for run in HAN_RUN.findall(article["text"]):
            runs += 1
            han_characters += len(run)
            for start in range(len(run)):
                for length in range(1, min(MAX_WORD_LENGTH, len(run) - start) + 1):
                    word = run[start:start + length]
                    if word in allowed:
                        article_words[word] += 1
        substring_matches += sum(article_words.values())
        if method == "occurrence":
            counts.update(article_words)
        elif method == "document-frequency":
            counts.update(article_words.keys())
        else:
            raise ValueError(f"Unknown method: {method}")
    observed = len(counts)
    for word in vocabulary:
        if counts[word] < floor:
            counts[word] = floor
    return counts, {"method": method, "floor": floor, "training_articles": len(articles),
                    "han_characters": han_characters, "han_runs": runs,
                    "raw_substring_matches": substring_matches, "observed_vocabulary_entries": observed,
                    "unobserved_entries_at_floor": len(vocabulary) - observed,
                    "total_output_count": sum(counts.values())}


def write_article_corpus(path: Path, articles: list[dict]) -> dict:
    output, seen = ["# Training article corpus; frozen test cohort excluded."], set()
    raw_lines = kept_lines = 0
    for article in articles:
        kept = []
        for line in corpus_lines(article["text"]):
            raw_lines += 1
            if line in seen:
                continue
            seen.add(line)
            kept.append(line)
            kept_lines += 1
        if kept:
            output.append(f"# {article['prompt_id']}")
            output.extend(kept)
    content = "\n".join(output) + "\n"
    path.write_text(content, encoding="utf-8")
    return {"file": path.name, "sha256": hashlib.sha256(content.encode()).hexdigest(),
            "raw_lines": raw_lines, "kept_lines": kept_lines, "duplicate_lines_removed": raw_lines - kept_lines}


def build(manifest_path: Path, output: Path, method: str, floor: int,
          manifest_is_training: bool = False) -> dict:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    selected = [row["id"] for row in manifest["articles"]]
    if len(selected) != manifest.get("count") or len(set(selected)) != len(selected):
        raise ValueError("Article manifest has missing or duplicate article IDs")
    population, sources = load_population()
    population_ids = {row["prompt_id"] for row in population}
    if not set(selected) <= population_ids:
        raise ValueError("Manifest contains an article outside the 2300-article population")
    if manifest_is_training:
        by_id = {row["prompt_id"]: row for row in population}
        training = [by_id[identifier] for identifier in selected]
        excluded = [row["prompt_id"] for row in population if row["prompt_id"] not in set(selected)]
    else:
        excluded = selected
        training = [row for row in population if row["prompt_id"] not in set(excluded)]
    vocabulary, vocabulary_report = load_vocabulary()
    counts, count_report = build_counts(training, vocabulary, method, floor)
    output.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"{word} {counts[word]}" for word in vocabulary]
    content = "\n".join(lines) + "\n"
    output.write_text(content, encoding="utf-8")
    corpus_path = output.with_suffix(".corpus.txt")
    corpus_report = write_article_corpus(corpus_path, training)
    report = {"purpose": "Project-owned unigram counts; vocabulary/readings remain separately sourced",
              "method": method, "population_articles": len(population), "training_articles": len(training),
              "excluded_articles": excluded,
              "article_manifest": str(manifest_path),
              "article_manifest_role": "training inclusion list" if manifest_is_training else "test exclusion list",
              "article_manifest_sha256": sha256(manifest_path), "article_sources": sources,
              "vocabulary": vocabulary_report, "counts": count_report,
              "output": {"file": output.name, "sha256": hashlib.sha256(content.encode()).hexdigest()},
              "training_corpus": corpus_report,
              "limitations": [
                  "Counts enumerate every known dictionary substring in raw Han runs; this is not supervised word segmentation.",
                  "A floor retains the existing vocabulary but is a project policy, not an observed frequency.",
                  "Only the frozen training cohort contributes to these counts and the paired bigram corpus."]}
    write_json(output.with_suffix(".report.json"), report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    manifests = parser.add_mutually_exclusive_group(required=True)
    manifests.add_argument("--training", type=Path,
                           help="frozen manifest whose articles are the complete training set")
    manifests.add_argument("--sample", type=Path,
                           help="legacy frozen manifest whose articles are excluded from training")
    parser.add_argument("--method", choices=("occurrence", "document-frequency"), required=True)
    parser.add_argument("--floor", type=int, default=1)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.floor < 1:
            raise ValueError("floor must be at least one")
        if args.output.exists() or args.output.with_suffix(".report.json").exists() or args.output.with_suffix(".corpus.txt").exists():
            raise ValueError("Refuse to overwrite an existing unigram experiment")
        report = build(args.training or args.sample, args.output, args.method, args.floor,
                       manifest_is_training=bool(args.training))
        print(json.dumps(report, ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
