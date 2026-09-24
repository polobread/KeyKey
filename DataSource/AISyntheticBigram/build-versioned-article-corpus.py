#!/usr/bin/env python3
"""Combine validated article exports for the Smart Mandarin bigram cooker."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ARTICLE_ROOT = ROOT.parent / "AISyntheticArticles"
SOURCES = ((2, 1650), (3, 350), (4, 300))
OUTPUT = ROOT / "article-corpus-2300-exact-dedup.txt"
REPORT = ROOT / "article-corpus-2300-build-report.json"
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")


def corpus_lines(text: str) -> list[str]:
    lines = []
    for raw in text.splitlines():
        line = re.sub(r"^(?:#{1,6}|>|[-*+])\s*", "", raw.strip())
        if HAN.search(line):
            lines.append(line)
    return lines


def main() -> None:
    output = [
        "# Article corpus for Smart Mandarin bigrams.",
        "# Sources: v2 1-1650, v3 1-350, v4 1-300; identical lines kept once.",
    ]
    seen_lines: set[str] = set()
    source_stats = []

    for version, count in SOURCES:
        path = ARTICLE_ROOT / f"typing-articles-v{version}.jsonl"
        data = path.read_bytes()
        articles = [json.loads(line) for line in data.decode("utf-8").splitlines() if line.strip()]
        prefix = "tw-typing-" if version == 2 else f"tw-typing-v{version}-"
        width = 5 if version == 2 else 3
        expected = [f"{prefix}{number:0{width}d}" for number in range(1, count + 1)]
        if [article.get("prompt_id") for article in articles] != expected:
            raise SystemExit(f"{path.name}: expected exactly {count} contiguous article IDs")

        raw_lines = kept_lines = 0
        for article in articles:
            kept_for_article = []
            for line in corpus_lines(article["text"]):
                raw_lines += 1
                if line in seen_lines:
                    continue
                seen_lines.add(line)
                kept_for_article.append(line)
                kept_lines += 1
            if kept_for_article:
                output.append(f"# {article['prompt_id']}")
                output.extend(kept_for_article)

        source_stats.append({
            "version": f"v{version}",
            "articles": count,
            "source_file": path.name,
            "source_sha256": hashlib.sha256(data).hexdigest(),
            "raw_lines": raw_lines,
            "kept_lines": kept_lines,
            "identical_lines_removed": raw_lines - kept_lines,
        })

    content = "\n".join(output) + "\n"
    OUTPUT.write_text(content, encoding="utf-8")
    report = {
        "articles": sum(count for _, count in SOURCES),
        "raw_lines": sum(row["raw_lines"] for row in source_stats),
        "kept_lines": sum(row["kept_lines"] for row in source_stats),
        "identical_lines_removed": sum(row["identical_lines_removed"] for row in source_stats),
        "sources": source_stats,
        "corpus_file": OUTPUT.name,
        "corpus_bytes": len(content.encode("utf-8")),
        "corpus_sha256": hashlib.sha256(content.encode("utf-8")).hexdigest(),
    }
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
