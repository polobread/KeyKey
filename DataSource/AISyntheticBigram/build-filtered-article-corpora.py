#!/usr/bin/env python3
"""Build exact- and near-deduplicated article corpora for LM experiments."""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ARTICLES = ROOT.parent / "AISyntheticArticles" / "typing-articles-v2.jsonl"
COUNTS = (1500, 1650)
HAN_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
NORMALIZE_RE = re.compile(r"[^\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaffA-Za-z0-9]")
SHINGLE_SIZE = 5
MIN_NEAR_CHARS = 40
NEAR_JACCARD = 0.86
MIN_LENGTH_RATIO = 0.90
MINHASH_COUNT = 16
MINHASH_BAND_SIZE = 2
PRIME = (1 << 61) - 1


def corpus_lines(text: str) -> list[str]:
    lines = []
    for raw in text.splitlines():
        line = raw.strip()
        line = re.sub(r"^(?:#{1,6}|>|[-*+])\s*", "", line)
        if HAN_RE.search(line):
            lines.append(line)
    return lines


def normalized(text: str) -> str:
    value = unicodedata.normalize("NFKC", text).lower()
    return NORMALIZE_RE.sub("", value)


def shingles(value: str) -> frozenset[str]:
    if len(value) <= SHINGLE_SIZE:
        return frozenset((value,))
    return frozenset(value[index:index + SHINGLE_SIZE] for index in range(len(value) - SHINGLE_SIZE + 1))


def shingle_hash(value: str) -> int:
    return int.from_bytes(hashlib.blake2b(value.encode("utf-8"), digest_size=8).digest(), "big") % PRIME


MINHASH_PARAMETERS = tuple(
    (
        int.from_bytes(hashlib.blake2b(f"a-{index}".encode(), digest_size=8).digest(), "big") % (PRIME - 1) + 1,
        int.from_bytes(hashlib.blake2b(f"b-{index}".encode(), digest_size=8).digest(), "big") % PRIME,
    )
    for index in range(MINHASH_COUNT)
)


def minhash(values: frozenset[str]) -> tuple[int, ...]:
    base = [shingle_hash(value) for value in values]
    return tuple(min((a * item + b) % PRIME for item in base) for a, b in MINHASH_PARAMETERS)


def bands(signature: tuple[int, ...]):
    for offset in range(0, len(signature), MINHASH_BAND_SIZE):
        yield offset // MINHASH_BAND_SIZE, signature[offset:offset + MINHASH_BAND_SIZE]


def jaccard(left: frozenset[str], right: frozenset[str]) -> float:
    return len(left & right) / len(left | right)


def filter_lines(articles: list[dict]) -> tuple[list[tuple[str, str]], list[tuple[str, str]], dict]:
    exact_seen: dict[str, int] = {}
    exact_lines: list[tuple[str, str]] = []
    near_lines: list[tuple[str, str]] = []
    near_norms: list[str] = []
    near_shingles: list[frozenset[str] | None] = []
    buckets: dict[tuple[int, tuple[int, ...]], list[int]] = defaultdict(list)
    raw_count = 0
    exact_removed = 0
    near_removed = 0
    examples = []

    for article in articles:
        article_id = article["prompt_id"]
        for line in corpus_lines(article["text"]):
            raw_count += 1
            norm = normalized(line)
            if not norm:
                continue
            if norm in exact_seen:
                exact_removed += 1
                continue
            exact_seen[norm] = raw_count
            exact_lines.append((article_id, line))

            if len(norm) < MIN_NEAR_CHARS:
                near_lines.append((article_id, line))
                near_norms.append(norm)
                near_shingles.append(None)
                continue

            values = shingles(norm)
            signature = minhash(values)
            candidate_indexes: set[int] = set()
            for band in bands(signature):
                candidate_indexes.update(buckets.get(band, ()))

            matched_index = None
            for candidate_index in candidate_indexes:
                candidate_norm = near_norms[candidate_index]
                ratio = min(len(norm), len(candidate_norm)) / max(len(norm), len(candidate_norm))
                if ratio < MIN_LENGTH_RATIO:
                    continue
                candidate_shingles = near_shingles[candidate_index]
                if candidate_shingles is not None and jaccard(values, candidate_shingles) >= NEAR_JACCARD:
                    matched_index = candidate_index
                    break

            if matched_index is not None:
                near_removed += 1
                if len(examples) < 20:
                    examples.append({
                        "removed_article": article_id,
                        "removed": line,
                        "kept_article": near_lines[matched_index][0],
                        "kept": near_lines[matched_index][1],
                        "jaccard": jaccard(values, near_shingles[matched_index]),
                    })
                continue

            index = len(near_lines)
            near_lines.append((article_id, line))
            near_norms.append(norm)
            near_shingles.append(values)
            for band in bands(signature):
                buckets[band].append(index)

    return exact_lines, near_lines, {
        "raw_lines": raw_count,
        "exact_lines": len(exact_lines),
        "near_dedup_lines": len(near_lines),
        "exact_duplicates_removed": exact_removed,
        "near_duplicates_removed_after_exact": near_removed,
        "exact_removed_percent": exact_removed / raw_count * 100,
        "total_removed_percent": (raw_count - len(near_lines)) / raw_count * 100,
        "near_thresholds": {
            "minimum_normalized_characters": MIN_NEAR_CHARS,
            "shingle_size": SHINGLE_SIZE,
            "minimum_length_ratio": MIN_LENGTH_RATIO,
            "minimum_jaccard": NEAR_JACCARD,
        },
        "near_duplicate_examples": examples,
    }


def write_corpus(path: Path, variant: str, count: int, lines: list[tuple[str, str]]) -> dict:
    output = [
        f"# {variant} article corpus for bigram filtering analysis.",
        f"# Source: tw-typing-00001 through tw-typing-{count:05d}.",
    ]
    last_article = None
    for article_id, line in lines:
        if article_id != last_article:
            output.append(f"# {article_id}")
            last_article = article_id
        output.append(line)
    data = "\n".join(output) + "\n"
    path.write_text(data, encoding="utf-8")
    return {"file": path.name, "lines": len(lines), "bytes": len(data.encode()), "sha256": hashlib.sha256(data.encode()).hexdigest()}


def main() -> None:
    articles = [json.loads(line) for line in ARTICLES.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(articles) < max(COUNTS):
        raise SystemExit(f"need {max(COUNTS)} articles, found {len(articles)}")
    report = {"source": str(ARTICLES), "snapshots": []}
    for count in COUNTS:
        exact, near, stats = filter_lines(articles[:count])
        exact_path = ROOT / f"article-corpus-{count}-exact-dedup.txt"
        near_path = ROOT / f"article-corpus-{count}-near-dedup.txt"
        report["snapshots"].append({
            "articles": count,
            **stats,
            "exact_corpus": write_corpus(exact_path, "Exact-deduplicated", count, exact),
            "near_dedup_corpus": write_corpus(near_path, "Near-deduplicated", count, near),
        })
    report_path = ROOT / "article-corpus-filtering-report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"snapshots": [{k: v for k, v in row.items() if k not in {"near_duplicate_examples"}} for row in report["snapshots"]]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
