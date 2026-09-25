#!/usr/bin/env python3
"""Validate saved article bodies, including Taiwan-specific word usage."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PROMPTS = ROOT / "typing-prompts-v2.jsonl"
SEED_DIR = ROOT / "typing-articles-v2-seed"
CHINA_CATEGORY = "中國繁中地名與旅行"

# Keep this list to usages that are strongly diagnostic in ordinary Taiwanese
# writing. Context-sensitive words such as「質量」、「支持」and「項目」still
# require editorial review and are deliberately not rejected here.
NON_TAIWAN_TERMS = {
    "早上好": "早安",
    "上午好": "早安",
    "下午好": "午安",
    "晚上好": "晚安",
    "視頻": "影片",
    "軟件": "軟體",
    "硬件": "硬體",
    "打印": "列印／印刷",
    "默認": "預設",
    "公交": "公車／大眾運輸",
    "出租車": "計程車",
    "網約車": "叫車服務",
    "外賣": "外送",
    "快遞小哥": "宅配人員",
    "小區": "社區",
    "物業": "社區管理／管理公司",
    "渠道": "管道／通路",
    "文檔": "文件",
    "郵箱": "電子郵件信箱／信箱",
    "短信": "簡訊",
    "屏幕": "螢幕",
    "鼠標": "滑鼠",
    "攝像頭": "攝影機／鏡頭",
    "網絡": "網路",
    "文件夾": "資料夾",
    "內存": "記憶體",
    "芯片": "晶片",
    "搜索": "搜尋",
    "信息": "資訊／訊息",
    "服務器": "伺服器",
    "土豆": "馬鈴薯",
    "西紅柿": "番茄",
    "方便麵": "泡麵",
    "充電寶": "行動電源",
    "二維碼": "QR Code／QR 碼",
    "報銷": "報帳／核銷",
    "質量問題": "品質問題",
}

CONTEXT_PATTERNS = {
    r"登陸(?:帳號|系統|網站|平台|應用程式)": "登入",
    r"(?:保存|存儲)(?:檔案|文件|資料|設定)": "儲存",
    r"在線(?!上)": "線上／在線上",
    r"用戶(?!端)": "使用者",
    # Avoid false positives across word boundaries such as「適合同行者」or
    # 「配合同學」while still catching contractual use of the PRC-preferred term.
    r"(?:簽訂|簽署|履行|解除|終止|違反|審閱|修改|草擬|買賣|租賃|勞動|採購|服務)合同|合同(?:書|內容|條款|關係|雙方|到期|有效|無效|糾紛|爭議|責任|解除|終止|約定|法)": "合約／契約",
}


def han_chars(text: str) -> int:
    return len(re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", text))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--end", type=int, default=700)
    parser.add_argument("--allow-missing", action="store_true")
    args = parser.parse_args()
    if args.start < 1 or args.end < args.start:
        raise SystemExit("invalid article range")

    prompts = {
        int(row["id"].rsplit("-", 1)[1]): row
        for row in (
            json.loads(line)
            for line in PROMPTS.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    }
    failures: list[str] = []
    checked = 0
    missing = 0
    hashes: dict[str, int] = {}

    for number in range(args.start, args.end + 1):
        prompt = prompts[number]
        path = SEED_DIR / f"{prompt['id']}.md"
        if not path.exists():
            missing += 1
            if not args.allow_missing:
                failures.append(f"{prompt['id']}: missing file")
            continue
        checked += 1
        raw = path.read_text(encoding="utf-8").strip()
        first, separator, body = raw.partition("\n")
        body = body.strip()
        if not separator or first != f"# {prompt['title']}":
            failures.append(f"{prompt['id']}: title mismatch")
        count = han_chars(body)
        minimum, maximum = prompt["accepted_char_range"]
        if not minimum <= count <= maximum:
            failures.append(
                f"{prompt['id']}: {count} Han characters outside {minimum}-{maximum}"
            )
        for entity in prompt.get("named_entities", []):
            if entity not in body:
                failures.append(f"{prompt['id']}: missing named entity {entity!r}")

        digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
        if digest in hashes:
            failures.append(
                f"{prompt['id']}: duplicate body of tw-typing-{hashes[digest]:05d}"
            )
        else:
            hashes[digest] = number

        if prompt["category"] != CHINA_CATEGORY:
            for term, replacement in NON_TAIWAN_TERMS.items():
                if term in body:
                    failures.append(
                        f"{prompt['id']}: non-Taiwan usage {term!r}; prefer {replacement}"
                    )
            for pattern, replacement in CONTEXT_PATTERNS.items():
                match = re.search(pattern, body)
                if match:
                    failures.append(
                        f"{prompt['id']}: non-Taiwan usage {match.group(0)!r}; prefer {replacement}"
                    )

    summary = {"checked": checked, "missing": missing, "failures": len(failures)}
    print(json.dumps(summary, ensure_ascii=False))
    if failures:
        print("\n".join(failures))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
