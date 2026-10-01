#!/usr/bin/env python3
"""Verify the fixed 130-article Smart Mandarin holdout and leakage boundary."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parent
DEFAULT_ARTICLES = ROOT / "typing-articles-v5-seed"
DEFAULT_MANIFEST = ROOT / "typing-articles-v5-manifest.json"
TRAINING = tuple(ROOT / f"typing-articles-v{version}.jsonl" for version in (2, 3, 4))
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\U00020000-\U000323af]")
NORMALIZED_HAN = re.compile(r"[^\u3400-\u9fff]")


def normalize(text: str) -> str:
    return NORMALIZED_HAN.sub("", text)


def inspect(article_dir: Path) -> dict[str, object]:
    paths = sorted(article_dir.glob("tw-corpus-*.md"))
    expected_names = [f"tw-corpus-{number:04d}.md" for number in range(1, 131)]
    if [path.name for path in paths] != expected_names:
        raise ValueError(f"{article_dir}: expected tw-corpus-0001.md through tw-corpus-0130.md")
    texts = [path.read_text(encoding="utf-8") for path in paths]
    if any(not text.strip() for text in texts):
        raise ValueError(f"{article_dir}: validation articles must not be empty")

    digest = hashlib.sha256()
    for path, text in zip(paths, texts):
        digest.update(path.name.encode("utf-8") + b"\0")
        digest.update(text.encode("utf-8") + b"\0")

    training_rows = []
    training_sources = []
    expected_counts = (1650, 350, 300)
    for path, expected_count in zip(TRAINING, expected_counts):
        rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
        if len(rows) != expected_count:
            raise ValueError(f"{path}: expected {expected_count} articles")
        training_rows.extend(rows)
        training_sources.append({
            "file": path.name,
            "articles": len(rows),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        })

    training_hashes = {
        hashlib.sha256(normalize(row["text"]).encode("utf-8")).hexdigest()
        for row in training_rows
    }
    validation_hashes = [
        hashlib.sha256(normalize(text).encode("utf-8")).hexdigest()
        for text in texts
    ]
    training_paragraphs = {
        normalized
        for row in training_rows
        for paragraph in row["text"].splitlines()
        if len(normalized := normalize(paragraph)) >= 20
    }
    validation_paragraphs = [
        normalized
        for text in texts
        for paragraph in text.splitlines()
        if len(normalized := normalize(paragraph)) >= 20
    ]
    leakage = {
        "exact_document_overlap": sum(value in training_hashes for value in validation_hashes),
        "duplicate_validation_documents": len(validation_hashes) - len(set(validation_hashes)),
        "exact_paragraph_overlap": sum(
            value in training_paragraphs for value in validation_paragraphs
        ),
    }
    if any(leakage.values()):
        raise ValueError(f"training/validation leakage detected: {leakage}")
    return {
        "article_count": len(paths),
        "first_article": paths[0].name,
        "last_article": paths[-1].name,
        "utf8_bytes": sum(len(text.encode("utf-8")) for text in texts),
        "han_characters": sum(bool(HAN.fullmatch(character)) for text in texts for character in text),
        "combined_sha256": digest.hexdigest(),
        "training_sources": training_sources,
        "leakage_checks": leakage,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--articles", type=Path, default=DEFAULT_ARTICLES)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()
    try:
        actual = inspect(args.articles)
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        expected = manifest["corpus"]
        if actual != expected:
            raise ValueError(
                "validation corpus differs from manifest:\n"
                + json.dumps({"expected": expected, "actual": actual}, ensure_ascii=False, indent=2)
            )
        print(json.dumps({"status": "ok", **actual}, ensure_ascii=False, indent=2))
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
