#!/usr/bin/env python3
"""Analyze era, topic, channel, tone, and text signals in accepted articles."""

from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parent
ARTICLES = ROOT / "typing-articles-v2.jsonl"
PROMPTS = ROOT / "typing-prompts-v2.jsonl"
PROMPT_STATS = ROOT / "typing-prompts-v2-stats.json"
OUTPUT_JSON = ROOT / "typing-articles-v2-attribute-report.json"
OUTPUT_MD = ROOT / "typing-articles-v2-attribute-report.md"


CHANNEL_GROUPS = {
    "私人書信": "私人溝通", "日記": "私人溝通", "家庭留言": "私人溝通", "電話留言": "私人溝通",
    "呼叫器留言": "私人溝通", "手機簡訊": "私人溝通", "即時通訊": "私人溝通", "通訊軟體私訊": "私人溝通",
    "通訊軟體群組": "群組對話", "工作聊天軟體": "工作協作", "電子郵件": "電子郵件", "共享文件": "工作協作",
    "公司備忘錄": "工作協作", "公司文件": "工作協作", "工作文件": "工作協作", "會議紀錄": "工作協作",
    "聯絡簿": "教育聯絡", "報刊投書": "公開討論", "讀者投書": "公開討論", "電子布告欄": "公開討論",
    "部落格留言": "公開討論", "社群貼文": "公開討論", "社群留言": "公開討論", "留言簿": "公開討論",
    "客服文字對談": "客服服務", "申請書": "正式文件", "公文草稿": "正式文件", "傳真往返": "正式文件",
    "旅行札記": "旅行書寫", "旅遊筆記": "旅行書寫", "搜尋與人工智慧提示": "搜尋／AI 提示",
}


# These are overlapping, transparent lexical indicators rather than a sentiment
# classifier. A document may contribute to several groups.
LEXICAL_SIGNALS = {
    "正向／感謝": ["謝謝", "感謝", "開心", "高興", "喜歡", "滿意", "幸福", "期待", "恭喜", "放心", "安心", "順利", "好消息", "值得", "珍惜", "溫暖", "感動"],
    "支持／安慰": ["加油", "支持", "陪你", "陪伴", "別擔心", "不用急", "慢慢來", "辛苦了", "沒關係", "理解", "體諒", "安慰", "鼓勵"],
    "焦慮／難過": ["擔心", "焦慮", "害怕", "難過", "失落", "失望", "委屈", "痛苦", "遺憾", "自責", "壓力", "緊張", "不安", "無奈", "後悔"],
    "生氣／衝突": ["生氣", "憤怒", "不滿", "抱怨", "爭吵", "爭執", "衝突", "誤會", "反對", "拒絕", "爭議", "不合理", "不能接受", "受不了"],
    "急迫": ["立刻", "馬上", "趕快", "儘快", "盡快", "緊急", "來不及", "截止", "最後期限", "務必"],
    "幽默口語": ["哈哈", "笑死", "傻眼", "太扯", "有夠", "是在哈囉", "幹話", "吐槽", "尷尬", "呵呵", "XD", "笑爛", "鬧", "梗"],
    "禮貌緩和": ["麻煩", "請問", "不好意思", "抱歉", "方便嗎", "可以嗎", "能否", "再請", "煩請", "謝謝您"],
    "正式／法律": ["依據", "規定", "契約", "合約", "權利", "義務", "責任", "申請", "陳情", "函復", "查證", "調查", "依法", "程序", "證據", "紀錄"],
}


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def distribution(values) -> list[dict]:
    counts = Counter(values)
    total = sum(counts.values())
    return [
        {"name": name, "count": count, "percent": count / total * 100}
        for name, count in counts.most_common()
    ]


def target_comparison(articles: list[dict], field: str, target_counts: dict, total_target: int) -> list[dict]:
    actual = Counter(article[field] for article in articles)
    total = len(articles)
    rows = []
    for name, target_count in target_counts.items():
        target_percent = target_count / total_target * 100
        count = actual[name]
        percent = count / total * 100
        rows.append({
            "name": name,
            "count": count,
            "percent": percent,
            "target_percent": target_percent,
            "difference_percentage_points": percent - target_percent,
            "difference_from_prorated_count": count - total * target_count / total_target,
        })
    return rows


def lexical_signal_report(articles: list[dict]) -> list[dict]:
    rows = []
    for name, words in LEXICAL_SIGNALS.items():
        documents = 0
        occurrences = 0
        for article in articles:
            count = sum(article["text"].count(word) for word in words)
            documents += count > 0
            occurrences += count
        rows.append({
            "name": name,
            "documents": documents,
            "document_percent": documents / len(articles) * 100,
            "occurrences": occurrences,
        })
    return rows


def repeated_sentence_report(articles: list[dict]) -> dict:
    frequencies = Counter()
    example_ids: dict[str, list[str]] = {}
    for article in articles:
        for sentence in re.split(r"[。！？!?\n]+", article["text"]):
            sentence = re.sub(r"\s+", "", sentence.strip())
            if len(sentence) < 12:
                continue
            frequencies[sentence] += 1
            example_ids.setdefault(sentence, []).append(article["prompt_id"])
    repeated = [(count, sentence) for sentence, count in frequencies.items() if count > 1]
    repeated.sort(reverse=True)
    total_occurrences = sum(frequencies.values())
    duplicate_occurrences = sum(count - 1 for count, _ in repeated)
    return {
        "sentence_occurrences": total_occurrences,
        "unique_sentences": len(frequencies),
        "repeated_sentence_types": len(repeated),
        "duplicate_occurrences": duplicate_occurrences,
        "duplicate_percent": duplicate_occurrences / total_occurrences * 100,
        "top_examples": [
            {"sentence": sentence, "count": count, "prompt_ids": example_ids[sentence]}
            for count, sentence in repeated[:10]
        ],
    }


def markdown_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    return [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---:" if index else "---" for index in range(len(headers))) + " |",
        *("| " + " | ".join(row) + " |" for row in rows),
    ]


def main() -> None:
    articles = read_jsonl(ARTICLES)
    prompts = {prompt["id"]: prompt for prompt in read_jsonl(PROMPTS)}
    targets = json.loads(PROMPT_STATS.read_text(encoding="utf-8"))
    joined = [(article, prompts[article["prompt_id"]]) for article in articles]
    total = len(articles)

    era_rows = sorted(
        target_comparison(articles, "era", targets["era_counts"], targets["total"]),
        key=lambda row: row["name"],
    )
    category_rows = target_comparison(articles, "category", targets["category_counts"], targets["total"])
    tone_rows = distribution(prompt["tone"] for _, prompt in joined)
    region_rows = distribution(prompt["region"] for _, prompt in joined)
    channel_rows = distribution(article["channel"] for article in articles)
    channel_group_rows = distribution(CHANNEL_GROUPS[article["channel"]] for article in articles)
    lexical_rows = lexical_signal_report(articles)
    repeated = repeated_sentence_report(articles)
    recent_count = sum(prompt["recent_30_years"] for _, prompt in joined)

    tone_signal_map = {
        "帶著不滿": "生氣／衝突",
        "急迫但清楚": "急迫",
        "溫和安慰": "支持／安慰",
        "輕鬆幽默": "幽默口語",
        "客氣克制": "禮貌緩和",
        "正式謹慎": "正式／法律",
    }
    tone_fidelity = []
    for tone, signal in tone_signal_map.items():
        selected = [article for article, prompt in joined if prompt["tone"] == tone]
        words = LEXICAL_SIGNALS[signal]
        matched = sum(any(word in article["text"] for word in words) for article in selected)
        tone_fidelity.append({
            "tone": tone,
            "signal": signal,
            "articles": len(selected),
            "matched": matched,
            "matched_percent": matched / len(selected) * 100,
        })

    text_feature_patterns = {
        "英文拉丁字母": r"[A-Za-z]",
        "阿拉伯數字": r"[0-9]",
        "網址": r"https?://|www\.",
        "Emoji": r"[\U0001F300-\U0001FAFF]",
        "注音符號": r"[ㄅ-ㄩˇˋ]",
        "阿拉伯數字金額": r"[$＄]\s*\d|\d+[萬千百]?元",
        "數字日期／時間": r"\d{1,4}[年/月.-]\d{1,2}|\d{1,2}[:：]\d{2}",
    }
    text_features = []
    for name, pattern in text_feature_patterns.items():
        count = sum(bool(re.search(pattern, article["text"], re.I)) for article in articles)
        text_features.append({"name": name, "count": count, "percent": count / total * 100})

    line_lengths = [
        len(line.strip())
        for article in articles
        for line in article["text"].splitlines()
        if line.strip() and line.strip() != "——"
    ]
    discourse_terms = {
        term: {
            "documents": sum(term in article["text"] for article in articles),
            "occurrences": sum(article["text"].count(term) for article in articles),
        }
        for term in ["最後", "原本", "這次", "確認", "回覆", "資料", "說明", "處理", "問題", "需要", "所以"]
    }

    report = {
        "articles": total,
        "han_chars": {
            "minimum": min(article["han_chars"] for article in articles),
            "average": sum(article["han_chars"] for article in articles) / total,
            "maximum": max(article["han_chars"] for article in articles),
        },
        "recent_30_years": {"count": recent_count, "percent": recent_count / total * 100, "target_percent": 70.0},
        "era_distribution": era_rows,
        "category_distribution": category_rows,
        "assigned_tone_distribution": tone_rows,
        "tone_signal_match": tone_fidelity,
        "lexical_signals": lexical_rows,
        "region_distribution": region_rows,
        "channel_distribution": channel_rows,
        "channel_group_distribution": channel_group_rows,
        "text_features": text_features,
        "line_lengths": {
            "count": len(line_lengths),
            "average": sum(line_lengths) / len(line_lengths),
            "median": sorted(line_lengths)[len(line_lengths) // 2],
            "at_most_10_chars": sum(length <= 10 for length in line_lengths),
            "at_most_10_chars_percent": sum(length <= 10 for length in line_lengths) / len(line_lengths) * 100,
        },
        "repeated_sentences": repeated,
        "common_discourse_terms": discourse_terms,
        "method": {
            "tone": "Assigned tone comes from the saved prompt metadata.",
            "lexical_signals": "Overlapping exact substring indicators; they are not exclusive sentiment labels or semantic classification.",
        },
    }
    OUTPUT_JSON.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    md = [
        "# 1,650 篇 AI 繁中語料屬性分析",
        "",
        "分析來源為 `typing-articles-v2.jsonl`，並以 `prompt_id` 接回 `typing-prompts-v2.jsonl` 的年代、情境、地區與指定語氣。",
        "",
        "## 摘要",
        "",
        f"- 共有 {total:,} 篇、約 {sum(article['han_chars'] for article in articles):,} 個漢字；每篇平均 {report['han_chars']['average']:.1f} 個漢字。",
        f"- 近 30 年（1997–2026）有 {recent_count:,} 篇，占 {recent_count / total:.2%}，非常接近 70% 目標。",
        "- 年代與大多數主題已接近一萬篇母體的規劃；目前最明顯的主題缺口是「工作討論與公事」，少於等比例期望 35 篇。",
        "- 指定語氣表面上很平均，但平均隨機分配讓語氣與主題不總是相稱；例如「社群吐槽與講幹話」只有少數被指定為輕鬆幽默。",
        "- 正文容易回到禮貌、確認、說明與處理的中性語氣。幽默、強烈口語、阿拉伯數字日期與金額、網址、Emoji 與中英混打明顯不足。",
        "- 完整句重複率低，但第 241–252 篇有一組跨文章共用句型，應在後續納入前移除或降低權重。",
        "",
        "## 年代分布",
        "",
        *markdown_table(
            ["年代", "篇數", "目前占比", "目標占比", "差距"],
            [[row["name"], f'{row["count"]:,}', f'{row["percent"]:.2f}%', f'{row["target_percent"]:.2f}%', f'{row["difference_percentage_points"]:+.2f} pp'] for row in era_rows],
        ),
        "",
        "年代分布沒有實質失衡。最大差距是 2020–2026 少 0.97 個百分點，仍在目前樣本前綴可接受的波動內。",
        "",
        "## 主題分布",
        "",
        *markdown_table(
            ["主題", "篇數", "目前占比", "目標占比", "差距"],
            [[row["name"], f'{row["count"]:,}', f'{row["percent"]:.2f}%', f'{row["target_percent"]:.2f}%', f'{row["difference_percentage_points"]:+.2f} pp'] for row in sorted(category_rows, key=lambda row: -row["percent"])],
        ),
        "",
        "「工作討論與公事」目前占 9.88%，比 12% 目標低 2.12 個百分點。其他單一主題差距都小於 0.7 個百分點。國際旅遊合計 125 篇、7.58%，略高於完整規劃的 6.5%，但仍是小比例。",
        "",
        "## 地區分布",
        "",
        *markdown_table(
            ["地區", "篇數", "占比"],
            [[row["name"], f'{row["count"]:,}', f'{row["percent"]:.2f}%'] for row in region_rows],
        ),
        "",
        "十個地區標籤各占 9.09% 至 11.76%，沒有明顯地理失衡。這裡量的是 prompt 地區標籤，不能證明正文含有足夠的在地地名、方言或地方生活細節。",
        "",
        "## 指定語氣與情感訊號",
        "",
        "### Prompt 指定語氣",
        "",
        *markdown_table(
            ["指定語氣", "篇數", "占比"],
            [[row["name"], f'{row["count"]:,}', f'{row["percent"]:.2f}%'] for row in tone_rows],
        ),
        "",
        "十種語氣各占約 9% 至 11%，分布很平均。這種平均是資料產生器的全域隨機結果，沒有依主題調整；例如 107 篇「社群吐槽與講幹話」中，只有 13 篇指定為輕鬆幽默，反而有 16 篇正式謹慎、17 篇耐心說明。",
        "",
        "### 正文詞彙訊號（可重疊）",
        "",
        *markdown_table(
            ["訊號", "含此訊號的文章", "文章占比", "詞次"],
            [[row["name"], f'{row["documents"]:,}', f'{row["document_percent"]:.1f}%', f'{row["occurrences"]:,}'] for row in lexical_rows],
        ),
        "",
        "這些是透明的關鍵詞檢查，不是互斥的情感分類。一篇文章可能同時含有感謝、焦慮與衝突；結果適合用來找缺口，不適合解讀成完整情緒標籤。",
        "",
        "### 指定語氣在正文中的可見度",
        "",
        *markdown_table(
            ["指定語氣", "檢查訊號", "文章數", "有明顯訊號", "命中率"],
            [[row["tone"], row["signal"], f'{row["articles"]:,}', f'{row["matched"]:,}', f'{row["matched_percent"]:.1f}%'] for row in tone_fidelity],
        ),
        "",
        "「帶著不滿」的辨識度最高；「輕鬆幽默」最容易在正文中被中性敘事稀釋。「溫和安慰」也有四成文章沒有出現這組最直接的支持詞。",
        "",
        "## 媒介與文字形態",
        "",
        *markdown_table(
            ["媒介群組", "篇數", "占比"],
            [[row["name"], f'{row["count"]:,}', f'{row["percent"]:.1f}%'] for row in channel_group_rows],
        ),
        "",
        f"全文共有 {len(line_lengths):,} 個非分隔線文字行，平均 {report['line_lengths']['average']:.1f} 字，中位數 {report['line_lengths']['median']} 字；只有 {report['line_lengths']['at_most_10_chars_percent']:.1f}% 不超過 10 字。雖然文章內含對話，整體仍偏長段落與整理後的文字。",
        "",
        *markdown_table(
            ["文字特徵", "文章數", "占比"],
            [[row["name"], f'{row["count"]:,}', f'{row["percent"]:.1f}%'] for row in text_features],
        ),
        "",
        "## 重複與模板化",
        "",
        f"長度至少 12 字的句子共 {repeated['sentence_occurrences']:,} 次，其中重複出現造成的額外次數為 {repeated['duplicate_occurrences']:,}，占 {repeated['duplicate_percent']:.3f}%。完整句重複率不高。",
        "",
        "但最常見的一組相同句各出現 12 次，集中在 `tw-typing-00241` 至 `tw-typing-00252`。這組會反覆使用「待確認」「留下可追蹤方式」「沉默不等於同意」等句型，是清楚可辨認的批次模板。",
        "",
        "另有明顯的敘事骨架偏好：『確認』出現在 89.0% 文章、『回覆』76.4%、『說明』66.1%、『處理』57.2%、『最後』59.2%。這些詞本身實用，但比例過高會把不同情境拉回同一種理性整理口吻。",
        "",
        "## 不足與調整順序",
        "",
        "1. **語氣應改成依主題加權。** 社群吐槽應多給輕鬆幽默、自然直接、帶著不滿；法律與公務多給正式謹慎、客氣克制；情緒人際則提高安慰、鼓勵、爭辯、界線與猶豫。保留少量反差即可，不宜十種平均。",
        "2. **補工作公事與正式公文。** 現有工作主題少 35 篇；所有文章中正式文件媒介只有 27 篇（1.64%），公文草稿只有 9 篇。後續應補會議決議、簽呈、公文回覆、陳情、契約往返、事故調查、勞資與租屋等自然用字。",
        "3. **增加真正的短訊息包。** 下一批可讓 20% 至 30% 直接輸出短訊息、搜尋詞、標題、表單欄位與多輪群組句子，不再用旁白串成 1,200 字文章。這會更貼近輸入法使用頻率。",
        "4. **補口語強度與不完美輸入。** 幽默口語只出現在 10.7% 文章，Emoji、注音語助詞、網址、阿拉伯數字日期與金額幾乎為零。可加入台灣常見的中英混打、數字、縮寫、標點、貼圖替代語與較激烈但自然的爭論。",
        "5. **削弱統一的理性結尾。** 減少每篇都確認、整理、留下紀錄、約定下一步；允許對話中止、已讀不回、誤會未解、情緒仍在、單純吐槽或只完成局部決定。",
        "6. **清理第 241–252 篇的共用句。** 對 bigram 資料庫大小影響很小，因既有 cooker 已限制合成 pair 的重複計數；但移除可改善語料風格多樣性與後續人工抽查品質。",
        "",
        "## 結論",
        "",
        "年代、地區與大類主題的基本盤已經合格，近 30 年 70% 的目標也有落實。下一階段最有價值的改進不是再平均擴寫同類長文，而是調整主題與語氣的條件分配，補短訊息、工作公事、正式文件、強烈口語及混合字元，並壓低『確認／回覆／說明／處理／最後』這套重複敘事骨架。",
        "",
    ]
    OUTPUT_MD.write_text("\n".join(md), encoding="utf-8")
    print(json.dumps({"articles": total, "json": str(OUTPUT_JSON), "markdown": str(OUTPUT_MD)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
