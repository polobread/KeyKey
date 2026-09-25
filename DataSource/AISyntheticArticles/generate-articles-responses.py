#!/usr/bin/env python3
"""Generate validated article bodies with the OpenAI Responses API."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import re
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PROMPTS = ROOT / "typing-prompts-v2.jsonl"
SEED_DIR = ROOT / "typing-articles-v2-seed"
API_ROOT = "https://api.openai.com/v1"
DEFAULT_KEY_FILE = Path.home() / ".codex" / "openai_api.key"

INSTRUCTIONS = """你是台灣繁體中文語料作者。請依輸入的 JSON 任務產生一份完整正文。

要求：
1. 只輸出正文，不輸出標題、JSON、前言、字數說明、分析或後記。
2. 正文漢字數必須落在 accepted_char_range，標點與空白不計入漢字數；請以範圍中間值為目標。
3. 完整遵守 scenario、requirements、language_requirements 與 avoid。
4. 保留指定媒介的自然節奏。對話可以有短句、省略、追問、改口與未立即回覆。
5. 指定 named_entities 時須使用正確名稱，不得虛構其票價、規格、營業時間或即時狀態。
6. 涉及法律、政策、醫療或公共事件時，區分人物主張、可確認事實與未知事項，不捏造法條、數字或引言。
7. 避免固定的「首先、其次、最後」結構、制式勵志結尾、摘要式空話與每段相同句型。
8. 內容必須能作為輸入法語料，包含人物在指定情境下真正可能打出的自然句子。
9. 除非 category 明確為「中國繁中地名與旅行」，所有台灣場景必須嚴格使用台灣慣用語；例如稱呼老師用「老師晚安」，不用「老師晚上好」，並使用影片、軟體、硬體、列印、預設、公車、計程車、外送、社區、合約、訊息、文件、簡訊、螢幕、滑鼠、行動電源、QR Code、線上、使用者、伺服器、登入等台灣用詞。
10. 法律紛爭、政府政策、公文或正式文件情境，應自然涵蓋多樣的台灣公文法律搭配，例如擬、研擬、擬定、擬具、擬辦、涉、涉及、涉嫌、涉案、嚴查、查辦、相關規定與相關資料；並讓又、和、與等連接詞出現在自然且不同的相鄰語境，不得硬塞或重複固定句型。
"""

# 229–300: 50 Sol, 11 GPT-5.6 Terra, 7 Luna, 4 Astra.
ASTRA_IDS = {233, 246, 276, 293}
TERRA_IDS = {230, 239, 244, 250, 253, 257, 271, 272, 287, 288, 294}
LUNA_IDS = {229, 234, 242, 254, 261, 266, 269}

MODEL_CONFIG = {
    "gpt-6-astra": {"effort": "low"},
    "gpt-6-sol": {"effort": "low"},
    "gpt-6-luna": {"effort": "medium"},
    "gpt-5.6-terra": {"effort": "low"},
}


def compact_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def han_chars(text: str) -> int:
    return len(re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", text))


def route_model(number: int) -> str:
    if number in ASTRA_IDS:
        return "gpt-6-astra"
    if number in TERRA_IDS:
        return "gpt-5.6-terra"
    if number in LUNA_IDS:
        return "gpt-6-luna"
    return "gpt-6-sol"


def extract_text(response: dict) -> str:
    pieces = []
    for item in response.get("output", []):
        if item.get("type") != "message":
            continue
        for content in item.get("content", []):
            if content.get("type") == "output_text" and content.get("text"):
                pieces.append(content["text"])
    return "\n".join(pieces).strip()


def clean_text(text: str, title: str) -> str:
    text = text.strip()
    if text.startswith("```") and text.endswith("```"):
        lines = text.splitlines()
        text = "\n".join(lines[1:-1]).strip()
    lines = text.splitlines()
    if lines and lines[0].strip() in {title, f"# {title}", f"## {title}"}:
        text = "\n".join(lines[1:]).strip()
    return text


def validate(prompt: dict, text: str) -> list[str]:
    reasons = []
    count = han_chars(text)
    minimum, maximum = prompt["accepted_char_range"]
    if not text:
        reasons.append("empty output")
    if not minimum <= count <= maximum:
        reasons.append(f"Han character count {count} outside {minimum}-{maximum}")
    for entity in prompt.get("named_entities", []):
        if entity not in text:
            reasons.append(f"missing named entity: {entity}")
    if text.splitlines() and text.splitlines()[0].strip() in {prompt["title"], f"# {prompt['title']}", f"## {prompt['title']}"}:
        reasons.append("output repeats title")
    return reasons


def load_api_key(path: Path) -> str:
    value = path.expanduser().read_text(encoding="utf-8").strip()
    if not value.startswith("sk-"):
        raise SystemExit(f"API key file does not contain an sk- key: {path.expanduser()}")
    return value


def api_request(api_key: str, payload: dict, network_retries: int = 5) -> dict:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        API_ROOT + "/responses",
        data=data,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    for retry in range(network_retries):
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                return json.loads(response.read())
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            if "credit_balance_exhausted" in detail or "insufficient_quota" in detail:
                raise RuntimeError("OpenAI API credit balance is exhausted") from error
            if error.code not in {408, 409, 429, 500, 502, 503, 504} or retry == network_retries - 1:
                raise RuntimeError(f"OpenAI API HTTP {error.code}: {detail}") from error
        except (TimeoutError, urllib.error.URLError) as error:
            if retry == network_retries - 1:
                raise RuntimeError(f"OpenAI API network error: {error}") from error
        time.sleep(min(2 ** retry, 20))
    raise AssertionError("unreachable")


def write_jsonl(path: Path, row: dict, lock: threading.Lock) -> None:
    with lock:
        with path.open("a", encoding="utf-8") as stream:
            stream.write(compact_json(row) + "\n")


def generate_one(
    prompt: dict,
    api_key: str,
    run_dir: Path,
    max_attempts: int,
    lock: threading.Lock,
) -> dict:
    prompt_id = prompt["id"]
    number = int(prompt_id.rsplit("-", 1)[1])
    model = route_model(number)
    target = SEED_DIR / f"{prompt_id}.md"
    if target.exists():
        raw = target.read_text(encoding="utf-8").strip()
        first, separator, body = raw.partition("\n")
        if separator and first == f"# {prompt['title']}" and not validate(prompt, body.strip()):
            return {"prompt_id": prompt_id, "model": model, "status": "skipped-valid", "han_chars": han_chars(body)}

    prior_reasons = []
    for attempt in range(1, max_attempts + 1):
        retry_note = ""
        if prior_reasons:
            retry_note = (
                "\n上一次產生的正文未通過自動檢查：" + "；".join(prior_reasons) +
                "。請重新產生完整正文，不要只補片段；尤其要把漢字數控制在允收範圍中段。"
            )
        payload = {
            "model": model,
            "reasoning": {"effort": MODEL_CONFIG[model]["effort"]},
            "instructions": INSTRUCTIONS + retry_note,
            "input": compact_json(prompt),
            "max_output_tokens": 3600,
            "store": False,
        }
        response = api_request(api_key, payload)
        text = clean_text(extract_text(response), prompt["title"])
        reasons = validate(prompt, text)
        usage = response.get("usage") or {}
        row = {
            "prompt_id": prompt_id,
            "model": response.get("model", model),
            "requested_model": model,
            "reasoning_effort": MODEL_CONFIG[model]["effort"],
            "attempt": attempt,
            "response_id": response.get("id"),
            "response_status": response.get("status"),
            "han_chars": han_chars(text),
            "reasons": reasons,
            "usage": usage,
        }
        write_jsonl(run_dir / "usage.jsonl", row, lock)
        if not reasons and response.get("status") == "completed":
            target.write_text(f"# {prompt['title']}\n\n{text}\n", encoding="utf-8")
            return {"prompt_id": prompt_id, "model": model, "status": "generated", "han_chars": han_chars(text), "attempt": attempt}
        prior_reasons = reasons or [f"response status was {response.get('status')}"]

    failure = {"prompt_id": prompt_id, "model": model, "status": "failed", "reasons": prior_reasons}
    write_jsonl(run_dir / "failures.jsonl", failure, lock)
    return failure


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--start", type=int, required=True)
    parser.add_argument("--end", type=int, required=True)
    parser.add_argument("--ids", help="Optional comma-separated numeric IDs within the range")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--max-attempts", type=int, default=3)
    parser.add_argument("--api-key-file", type=Path, default=DEFAULT_KEY_FILE)
    args = parser.parse_args()
    if args.start > args.end or args.workers < 1 or args.max_attempts < 1:
        raise SystemExit("invalid range, worker count, or attempt count")

    selected = None
    if args.ids:
        selected = {int(value) for value in args.ids.split(",") if value.strip()}
    prompts = []
    for line in PROMPTS.read_text(encoding="utf-8").splitlines():
        prompt = json.loads(line)
        number = int(prompt["id"].rsplit("-", 1)[1])
        if args.start <= number <= args.end and (selected is None or number in selected):
            prompts.append(prompt)
    if not prompts:
        raise SystemExit("no prompts selected")

    run_dir = ROOT / "article-api-runs" / f"{args.start:05d}-{args.end:05d}"
    run_dir.mkdir(parents=True, exist_ok=True)
    counts = {}
    for prompt in prompts:
        model = route_model(int(prompt["id"].rsplit("-", 1)[1]))
        counts[model] = counts.get(model, 0) + 1
    manifest = {
        "start": args.start,
        "end": args.end,
        "selected_count": len(prompts),
        "model_counts": counts,
        "models": MODEL_CONFIG,
        "store": False,
        "max_attempts": args.max_attempts,
        "prompt_sha256": hashlib.sha256(PROMPTS.read_bytes()).hexdigest(),
    }
    (run_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    api_key = load_api_key(args.api_key_file)
    lock = threading.Lock()
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = [executor.submit(generate_one, prompt, api_key, run_dir, args.max_attempts, lock) for prompt in prompts]
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            print(compact_json(result), flush=True)

    summary = {
        "selected": len(prompts),
        "generated": sum(item["status"] == "generated" for item in results),
        "skipped_valid": sum(item["status"] == "skipped-valid" for item in results),
        "failed": sum(item["status"] == "failed" for item in results),
    }
    print(compact_json(summary))
    if summary["failed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
