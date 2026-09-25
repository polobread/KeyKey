#!/usr/bin/env python3
"""Import OpenAI Batch API results and validate generated article bodies."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PROMPTS = ROOT / "typing-prompts-v2.jsonl"
SEED_DIR = ROOT / "typing-articles-v2-seed"
OUTPUT = ROOT / "typing-articles-v2.jsonl"
REJECTED = ROOT / "typing-articles-v2-rejected.jsonl"
REPORT = ROOT / "typing-articles-v2-generation-report.json"


def compact_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def han_chars(text: str) -> int:
    return len(re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", text))


def extract_response_text(body: dict) -> str:
    pieces = []
    for item in body.get("output", []):
        if item.get("type") != "message":
            continue
        for content in item.get("content", []):
            if content.get("type") == "output_text" and content.get("text"):
                pieces.append(content["text"])
    return "\n".join(pieces).strip()


def read_seed(prompt: dict) -> dict | None:
    path = SEED_DIR / f"{prompt['id']}.md"
    if not path.exists():
        return None
    raw = path.read_text(encoding="utf-8").strip()
    first, separator, body = raw.partition("\n")
    if not separator or first != f"# {prompt['title']}":
        raise SystemExit(f"seed title mismatch: {path}")
    return {
        "prompt_id": prompt["id"], "title": prompt["title"], "era": prompt["era"],
        "category": prompt["category"], "channel": prompt["channel"],
        "output_form": prompt["output_form"], "text": body.strip(), "source": "codex-seed",
        "model": None, "usage": None,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("results", nargs="*", type=Path, help="Batch output JSONL files")
    args = parser.parse_args()
    prompt_list = [json.loads(line) for line in PROMPTS.read_text(encoding="utf-8").splitlines() if line.strip()]
    prompts = {item["id"]: item for item in prompt_list}
    candidates = {}
    errors = []

    for path in args.results:
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip():
                continue
            row = json.loads(line)
            prompt_id = row.get("custom_id")
            if prompt_id not in prompts:
                errors.append({"file": str(path), "line": line_number, "error": "unknown custom_id", "custom_id": prompt_id})
                continue
            if row.get("error") or not row.get("response") or row["response"].get("status_code") != 200:
                errors.append({"file": str(path), "line": line_number, "custom_id": prompt_id, "error": row.get("error") or row.get("response")})
                continue
            if prompt_id in candidates:
                raise SystemExit(f"duplicate batch result for {prompt_id}")
            body = row["response"]["body"]
            text = extract_response_text(body)
            candidates[prompt_id] = {
                "prompt_id": prompt_id, "title": prompts[prompt_id]["title"], "era": prompts[prompt_id]["era"],
                "category": prompts[prompt_id]["category"], "channel": prompts[prompt_id]["channel"],
                "output_form": prompts[prompt_id]["output_form"], "text": text, "source": "openai-batch",
                "model": body.get("model"), "usage": body.get("usage"),
            }

    for prompt in prompt_list:
        seed = read_seed(prompt)
        if seed:
            candidates.setdefault(prompt["id"], seed)

    valid = []
    rejected = []
    usage_totals = {"input_tokens": 0, "output_tokens": 0, "total_tokens": 0}
    for prompt in prompt_list:
        article = candidates.get(prompt["id"])
        if not article:
            continue
        article["han_chars"] = han_chars(article["text"])
        minimum, maximum = prompt["accepted_char_range"]
        reasons = []
        if not article["text"]:
            reasons.append("empty output")
        if not minimum <= article["han_chars"] <= maximum:
            reasons.append(f"Han character count {article['han_chars']} outside {minimum}-{maximum}")
        first_line = article["text"].splitlines()[0].strip() if article["text"] else ""
        if first_line in {prompt["title"], f"# {prompt['title']}"}:
            reasons.append("output repeats title")
        if reasons:
            rejected.append({**article, "reasons": reasons})
            continue
        valid.append(article)
        if article["usage"]:
            for key in usage_totals:
                usage_totals[key] += int(article["usage"].get(key, 0) or 0)

    OUTPUT.write_text("".join(compact_json(item) + "\n" for item in valid), encoding="utf-8")
    REJECTED.write_text("".join(compact_json(item) + "\n" for item in rejected), encoding="utf-8")
    report = {
        "prompt_count": len(prompt_list), "valid_articles": len(valid), "rejected_articles": len(rejected),
        "missing_articles": len(prompt_list) - len(valid) - len(rejected), "batch_errors": errors,
        "api_usage_for_valid_articles": usage_totals,
    }
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
