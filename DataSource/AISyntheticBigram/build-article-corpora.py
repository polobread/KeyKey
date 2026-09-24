#!/usr/bin/env python3
"""Build cumulative SmartMandarin corpora from accepted synthetic articles."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ARTICLES = ROOT.parent / "AISyntheticArticles" / "typing-articles-v2.jsonl"
SNAPSHOTS = (100, 200, 300, 400, 450, 500, 700, 900, 1100, 1300, 1500, 1650)


def corpus_lines(text: str) -> list[str]:
    lines = []
    for raw in text.splitlines():
        line = raw.strip()
        line = re.sub(r"^(?:#{1,6}|>|[-*+])\s*", "", line)
        if not re.search(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", line):
            continue
        lines.append(line)
    return lines


def write_snapshot(articles: list[dict], count: int) -> dict:
    path = ROOT / f"article-corpus-{count}.txt"
    output = [
        "# Generated from accepted AISyntheticArticles bodies.",
        f"# Cumulative snapshot: tw-typing-00001 through tw-typing-{count:05d}.",
    ]
    line_count = 0
    han_count = 0
    for article in articles[:count]:
        output.append(f"# {article['prompt_id']}")
        lines = corpus_lines(article["text"])
        output.extend(lines)
        line_count += len(lines)
        han_count += sum(len(re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", line)) for line in lines)
    data = "\n".join(output) + "\n"
    path.write_text(data, encoding="utf-8")
    return {
        "articles": count,
        "source_first": articles[0]["prompt_id"],
        "source_last": articles[count - 1]["prompt_id"],
        "corpus_lines": line_count,
        "han_chars": han_count,
        "bytes": len(data.encode("utf-8")),
        "sha256": hashlib.sha256(data.encode("utf-8")).hexdigest(),
        "file": path.name,
    }


def main() -> None:
    articles = [json.loads(line) for line in ARTICLES.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(articles) < max(SNAPSHOTS):
        raise SystemExit(f"need at least {max(SNAPSHOTS)} accepted articles, found {len(articles)}")
    expected = [f"tw-typing-{number:05d}" for number in range(1, max(SNAPSHOTS) + 1)]
    actual = [article["prompt_id"] for article in articles[: max(SNAPSHOTS)]]
    if actual != expected:
        raise SystemExit(
            f"accepted articles are not a contiguous 1-{max(SNAPSHOTS)} sequence"
        )
    report = {"source": str(ARTICLES.relative_to(ROOT.parent.parent)), "snapshots": []}
    for count in SNAPSHOTS:
        report["snapshots"].append(write_snapshot(articles, count))
    report_path = ROOT / "article-corpus-build-report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
