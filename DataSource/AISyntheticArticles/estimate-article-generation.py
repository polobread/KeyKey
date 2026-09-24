#!/usr/bin/env python3
"""Estimate v2 generation tokens with the o200k_base tokenizer."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPORT = ROOT / "typing-articles-v2-token-estimate.json"


def main() -> None:
    try:
        import tiktoken
    except ImportError as error:
        raise SystemExit("Install tiktoken or add it to PYTHONPATH to run this estimate") from error
    encoder = tiktoken.get_encoding("o200k_base")
    input_tokens = 0
    request_count = 0
    for path in sorted((ROOT / "article-batches-v2").glob("requests-*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            row = json.loads(line)
            body = row["body"]
            input_tokens += len(encoder.encode(body["instructions"] + "\n" + body["input"]))
            request_count += 1

    seed_tokens = []
    for line in (ROOT / "typing-articles-v2.jsonl").read_text(encoding="utf-8").splitlines():
        article = json.loads(line)
        if article["source"] == "codex-seed":
            seed_tokens.append(len(encoder.encode(article["text"])))
    mean_output = sum(seed_tokens) / len(seed_tokens)
    report = {
        "encoding": "o200k_base",
        "method": "Input encodes saved instructions plus compact prompt JSON; projected output uses the mean of accepted seed bodies.",
        "pending_requests": request_count,
        "estimated_pending_input_tokens": input_tokens,
        "mean_input_tokens_per_request": input_tokens / request_count,
        "seed_output_tokens": seed_tokens,
        "mean_seed_output_tokens": mean_output,
        "projected_output_tokens_for_10000": round(mean_output * 10_000),
        "limitations": "API wrappers and model behavior can change actual usage. Final usage must come from Batch API response usage fields.",
    }
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
