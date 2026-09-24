#!/usr/bin/env python3
"""Build OpenAI Batch API request files for unfinished v2 article prompts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PROMPTS = ROOT / "typing-prompts-v2.jsonl"
SEED_DIR = ROOT / "typing-articles-v2-seed"
DEFAULT_OUTPUT = ROOT / "article-batches-v2"

INSTRUCTIONS = """你是台灣繁體中文語料作者。請依輸入的 JSON 任務產生一份完整正文。

要求：
1. 只輸出正文，不輸出標題、JSON、前言、字數說明、分析或後記。
2. 正文漢字數必須落在 accepted_char_range，標點與空白不計入漢字數。
3. 完整遵守 scenario、requirements、language_requirements 與 avoid。
4. 保留指定媒介的自然節奏。對話可以有短句、省略、追問、改口與未立即回覆。
5. 指定 named_entities 時須使用正確名稱，不得虛構其票價、規格、營業時間或即時狀態。
6. 涉及法律、政策、醫療或公共事件時，區分人物主張、可確認事實與未知事項，不捏造法條、數字或引言。
7. 避免固定的「首先、其次、最後」結構、制式勵志結尾與每段相同句型。
8. 除非 category 明確為「中國繁中地名與旅行」，所有台灣場景必須嚴格使用台灣慣用語；例如稱呼老師用「老師晚安」，不用「老師晚上好」，並使用影片、軟體、硬體、列印、預設、公車、計程車、外送、社區、合約、訊息、文件、簡訊、螢幕、滑鼠、行動電源、QR Code、線上、使用者、伺服器、登入等台灣用詞。
9. 法律紛爭、政府政策、公文或正式文件情境，應自然涵蓋多樣的台灣公文法律搭配，例如擬、研擬、擬定、擬具、擬辦、涉、涉及、涉嫌、涉案、嚴查、查辦、相關規定與相關資料；並讓又、和、與等連接詞出現在自然且不同的相鄰語境，不得硬塞或重複固定句型。
"""


def compact_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def completed_prompt_ids() -> set[str]:
    completed = set()
    if SEED_DIR.exists():
        completed.update(path.stem for path in SEED_DIR.glob("tw-typing-*.md"))
    consolidated = ROOT / "typing-articles-v2.jsonl"
    if consolidated.exists():
        for line in consolidated.read_text(encoding="utf-8").splitlines():
            if line.strip():
                completed.add(json.loads(line)["prompt_id"])
    return completed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="gpt-6-luna")
    parser.add_argument("--reasoning-effort", default="none", choices=("none", "low", "medium", "high"))
    parser.add_argument("--chunk-size", type=int, default=500)
    parser.add_argument("--max-output-tokens", type=int, default=2500)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--include-completed", action="store_true")
    args = parser.parse_args()
    if args.chunk_size < 1:
        raise SystemExit("--chunk-size must be positive")

    prompts = [json.loads(line) for line in PROMPTS.read_text(encoding="utf-8").splitlines() if line.strip()]
    completed = set() if args.include_completed else completed_prompt_ids()
    pending = [item for item in prompts if item["id"] not in completed]
    args.output_dir.mkdir(parents=True, exist_ok=True)

    expected_names = set()
    chunk_rows = []
    for index, prompt in enumerate(pending):
        request = {
            "custom_id": prompt["id"],
            "method": "POST",
            "url": "/v1/responses",
            "body": {
                "model": args.model,
                "reasoning": {"effort": args.reasoning_effort},
                "instructions": INSTRUCTIONS,
                "input": compact_json(prompt),
                "max_output_tokens": args.max_output_tokens,
                "store": False,
            },
        }
        chunk_rows.append(request)
        if len(chunk_rows) == args.chunk_size or index == len(pending) - 1:
            chunk_number = (index // args.chunk_size) + 1
            name = f"requests-{chunk_number:03d}.jsonl"
            expected_names.add(name)
            path = args.output_dir / name
            path.write_text("".join(compact_json(row) + "\n" for row in chunk_rows), encoding="utf-8")
            chunk_rows = []

    stale = sorted(path.name for path in args.output_dir.glob("requests-*.jsonl") if path.name not in expected_names)
    if stale:
        raise SystemExit(f"stale request files need review: {stale}")

    manifest = {
        "endpoint": "/v1/responses",
        "model": args.model,
        "reasoning_effort": args.reasoning_effort,
        "max_output_tokens": args.max_output_tokens,
        "chunk_size": args.chunk_size,
        "total_prompts": len(prompts),
        "completed_skipped": len(completed),
        "pending_requests": len(pending),
        "batch_files": sorted(expected_names),
    }
    (args.output_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(compact_json(manifest))


if __name__ == "__main__":
    main()
