#!/usr/bin/env python3
"""Build JSONL samples and a reproducible token report.

Exact token counts require tiktoken and the o200k_base encoding data. The
package may be supplied through PYTHONPATH; it is intentionally not vendored.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PROMPTS = ROOT / "writing-prompts-v1.jsonl"
SAMPLE_DIR = ROOT / "article-samples-v1"
SAMPLES_JSONL = ROOT / "article-samples-v1.jsonl"
REPORT_JSON = ROOT / "article-samples-token-report.json"
REPORT_MD = ROOT / "article-samples-token-report.md"
SAMPLE_IDS = ("tw-writing-0001", "tw-writing-0002", "tw-writing-0004")
SYSTEM_TEXT = (
    "請依下列作文任務寫一篇完整的台灣繁體中文文章。"
    "只輸出正文，不加標題、前言、字數說明或後記。"
    "完整遵守 requirements、language_requirements 與 avoid。"
)


def compact_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def visible_chars(text: str) -> int:
    return len(re.sub(r"\s", "", text))


def han_chars(text: str) -> int:
    return len(re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", text))


def load_prompts() -> dict[str, dict]:
    records = {}
    with PROMPTS.open(encoding="utf-8") as stream:
        for line in stream:
            record = json.loads(line)
            if record["id"] in SAMPLE_IDS:
                records[record["id"]] = record
    missing = set(SAMPLE_IDS) - records.keys()
    if missing:
        raise SystemExit(f"Missing prompts: {sorted(missing)}")
    return records


def read_article(sample_id: str) -> tuple[str, str]:
    path = SAMPLE_DIR / f"{sample_id}.md"
    raw = path.read_text(encoding="utf-8").strip()
    first, separator, body = raw.partition("\n")
    if not separator or not first.startswith("# "):
        raise SystemExit(f"Expected Markdown title in {path}")
    return first[2:].strip(), body.strip()


def get_encoder():
    try:
        import tiktoken
    except ImportError as error:
        raise SystemExit(
            "tiktoken is required for exact counts. Example: "
            "PYTHONPATH=/tmp/keykey-tokenizer /usr/bin/python3 "
            "analyze-article-samples.py"
        ) from error
    return tiktoken.get_encoding("o200k_base")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--encoding",
        default="o200k_base",
        choices=("o200k_base",),
        help="Tokenizer encoding used for reproducible counts.",
    )
    args = parser.parse_args()
    encoder = get_encoder()
    prompts = load_prompts()
    samples = []
    report_rows = []

    for sample_id in SAMPLE_IDS:
        assignment = prompts[sample_id]
        title, body = read_article(sample_id)
        if title != assignment["title"]:
            raise SystemExit(f"Title mismatch for {sample_id}: {title}")

        user_text = compact_json(assignment)
        input_text = SYSTEM_TEXT + "\n" + user_text
        input_tokens = len(encoder.encode(input_text))
        output_tokens = len(encoder.encode(body))
        accepted_min, accepted_max = assignment["accepted_char_range"]
        body_han_chars = han_chars(body)
        if not accepted_min <= body_han_chars <= accepted_max:
            raise SystemExit(
                f"{sample_id} has {body_han_chars} Han chars; expected "
                f"{accepted_min}-{accepted_max}"
            )
        sample = {
            "id": f"{sample_id}-sample-v1",
            "prompt_id": sample_id,
            "title": title,
            "era": assignment["era"],
            "genre": assignment["genre"],
            "text": body,
        }
        samples.append(sample)
        report_rows.append(
            {
                "prompt_id": sample_id,
                "title": title,
                "visible_chars": visible_chars(body),
                "han_chars": body_han_chars,
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "total_tokens": input_tokens + output_tokens,
                "prompt_sha256": sha256(input_text),
                "output_sha256": sha256(body),
            }
        )

    SAMPLES_JSONL.write_text(
        "".join(compact_json(sample) + "\n" for sample in samples), encoding="utf-8"
    )
    totals = {
        key: sum(row[key] for row in report_rows)
        for key in ("visible_chars", "han_chars", "input_tokens", "output_tokens", "total_tokens")
    }
    report = {
        "scope": "Three saved article samples only",
        "encoding": args.encoding,
        "counting_method": (
            "input_tokens encode SYSTEM_TEXT + newline + compact prompt JSON; "
            "output_tokens encode article body only. Chat wrappers, tool calls, "
            "hidden context, reasoning, retries, and account billing are excluded."
        ),
        "system_text": SYSTEM_TEXT,
        "rows": report_rows,
        "totals": totals,
    }
    REPORT_JSON.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Article sample token report",
        "",
        f"Tokenizer: `{args.encoding}`",
        "",
        (
            "These are reproducible counts for the saved generation prompt and article "
            "body. They are not Codex account usage or billable API usage. Chat wrappers, "
            "tool calls, hidden context, reasoning, and retries are not included."
        ),
        "",
        "| Prompt | Title | Visible chars | Han chars | Input tokens | Output tokens | Total |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in report_rows:
        lines.append(
            f"| {row['prompt_id']} | {row['title']} | {row['visible_chars']:,} | "
            f"{row['han_chars']:,} | {row['input_tokens']:,} | "
            f"{row['output_tokens']:,} | {row['total_tokens']:,} |"
        )
    lines.extend(
        [
            f"| **Total** |  | **{totals['visible_chars']:,}** | **{totals['han_chars']:,}** | "
            f"**{totals['input_tokens']:,}** | **{totals['output_tokens']:,}** | "
            f"**{totals['total_tokens']:,}** |",
            "",
            "## Reproduce",
            "",
            "```sh",
            "PYTHONPATH=/tmp/keykey-tokenizer /usr/bin/python3 analyze-article-samples.py",
            "```",
            "",
        ]
    )
    REPORT_MD.write_text("\n".join(lines), encoding="utf-8")

    for row in report_rows:
        accepted = prompts[row["prompt_id"]]["accepted_char_range"]
        print(
            f"{row['prompt_id']}: {row['visible_chars']} visible chars, "
            f"{row['han_chars']} Han chars, {row['output_tokens']} output tokens; "
            f"target range {accepted[0]}-{accepted[1]}"
        )
    print(compact_json(totals))


if __name__ == "__main__":
    main()
