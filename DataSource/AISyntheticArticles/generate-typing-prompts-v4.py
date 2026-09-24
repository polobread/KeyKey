#!/usr/bin/env python3
"""Build 300 vocabulary-guided v4 assignments from a 6,000-word pool."""

from __future__ import annotations

from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import random
import re
import unicodedata


SEED = 20260926
ARTICLE_COUNT = 300
POOL_SIZE = 6000
TERMS_PER_ARTICLE = 30
REQUIRED_TERMS_PER_ARTICLE = 15
EXPECTED_COLLECTION_ROWS = 4012
EXPECTED_COLLECTION_TERMS = 3758
SEMANTIC_GROUP_KINDS = {"同義近義", "同義衍生"}
MCB_MIN_COUNT = 100

ROOT = Path(__file__).resolve().parent
DATA_ROOT = ROOT.parent
REPO = DATA_ROOT.parent
MCB_COUNTS = DATA_ROOT / "McBopomofo" / "phrase.occ"
MCB_MAPPINGS = DATA_ROOT / "McBopomofo" / "BPMFMappings.txt"
COLLECTION_ROOT = DATA_ROOT / "chichi77Collection"
ANIME = COLLECTION_ROOT / "phrase.anime.tsv"

OUTPUT = ROOT / "typing-prompts-v4.jsonl"
STATS = ROOT / "typing-prompts-v4-stats.json"
PLAN = ROOT / "typing-prompts-v4-plan.md"
PREVIEW = ROOT / "typing-prompts-v4-preview.md"
ASSIGNMENTS = ROOT / "typing-prompts-v4-term-assignments.tsv"


NON_TAIWAN_FRAGMENTS = {
    "早上好", "上午好", "下午好", "晚上好", "視頻", "軟件", "硬件", "打印", "默認",
    "公交", "出租車", "網約車", "外賣", "快遞小哥", "小區", "物業", "渠道", "文檔",
    "郵箱", "短信", "屏幕", "鼠標", "攝像頭", "網絡", "文件夾", "內存", "芯片", "搜索",
    "服務器", "土豆", "西紅柿", "方便麵", "充電寶", "二維碼", "質量問題",
}


# These are deliberately small and reviewable. They keep clear synonyms,
# spelling variants, and very close everyday alternatives in one base bundle.
SYNONYM_SEEDS = {
    "資料資訊數據": ["資料", "資訊", "數據"],
    "方法方式作法": ["方法", "方式", "作法", "做法"],
    "計畫規劃方案": ["計畫", "規劃", "方案"],
    "目標目的": ["目標", "目的"],
    "影響衝擊": ["影響", "衝擊"],
    "改善改進優化": ["改善", "改進", "優化"],
    "建立建置": ["建立", "建置"],
    "修改修正更改調整": ["修改", "修正", "更改", "調整"],
    "檢查查核稽核": ["檢查", "查核", "稽核"],
    "調查查證": ["調查", "查證"],
    "測試試驗檢測": ["測試", "試驗", "檢測"],
    "停止中止終止": ["停止", "中止", "終止"],
    "支持支援": ["支持", "支援"],
    "回覆回應": ["回覆", "回應"],
    "記錄紀錄": ["記錄", "紀錄"],
    "合約契約": ["合約", "契約"],
    "產品商品": ["產品", "商品"],
    "顧客客戶消費者": ["顧客", "客戶", "消費者"],
    "店家商家業者": ["店家", "商家", "業者"],
    "廠商供應商": ["廠商", "供應商"],
    "成本費用支出": ["成本", "費用", "支出"],
    "收益營收收入": ["收益", "營收", "收入"],
    "運送配送": ["運送", "配送"],
    "安全防護保障": ["安全", "防護", "保障"],
    "風險危害威脅": ["風險", "危害", "威脅"],
    "錯誤故障異常": ["錯誤", "故障", "異常"],
    "修理維修修復": ["修理", "維修", "修復"],
    "教師老師": ["教師", "老師"],
    "學生學員": ["學生", "學員"],
    "課程課堂": ["課程", "課堂"],
    "房屋住宅住家": ["房屋", "住宅", "住家"],
    "工作職務作業": ["工作", "職務", "作業"],
    "員工職員同仁": ["員工", "職員", "同仁"],
    "經理主管": ["經理", "主管"],
    "法律法規規定": ["法律", "法規", "規定"],
    "申請申辦": ["申請", "申辦"],
    "違法違規": ["違法", "違規"],
    "生氣憤怒不滿": ["生氣", "憤怒", "不滿"],
    "難過悲傷傷心": ["難過", "悲傷", "傷心"],
    "擔心憂慮焦慮": ["擔心", "憂慮", "焦慮"],
    "開心高興快樂": ["開心", "高興", "快樂"],
    "幫助協助": ["幫助", "協助"],
    "鼓勵勉勵": ["鼓勵", "勉勵"],
    "照顧照料": ["照顧", "照料"],
    "醫生醫師": ["醫生", "醫師"],
    "藥物藥品": ["藥物", "藥品"],
    "病人患者": ["病人", "患者"],
    "疾病病症": ["疾病", "病症"],
    "生產製造": ["生產", "製造"],
    "工廠工場": ["工廠", "工場"],
    "農民農友": ["農民", "農友"],
    "食品食物": ["食品", "食物"],
    "環境生態": ["環境", "生態"],
    "能源電力": ["能源", "電力"],
    "車輛汽車": ["車輛", "汽車"],
    "旅行旅遊": ["旅行", "旅遊"],
    "飯店旅館": ["飯店", "旅館"],
    "地點位置": ["地點", "位置"],
    "顯示呈現": ["顯示", "呈現"],
    "刪除移除": ["刪除", "移除"],
    "儲存保存": ["儲存", "保存"],
    "下載擷取": ["下載", "擷取"],
    "程式軟體": ["程式", "軟體"],
    "影像影片視訊": ["影像", "影片", "視訊"],
    "自行車腳踏車單車": ["自行車", "腳踏車", "單車"],
    "公車巴士": ["公車", "巴士"],
    "存貨庫存": ["存貨", "庫存"],
    "太陽能太陽光電": ["太陽能", "太陽光電"],
    "訓練培訓": ["訓練", "培訓"],
    "分析解析": ["分析", "解析"],
    "監控監測": ["監控", "監測"],
    "設定設置": ["設定", "設置"],
    "處理辦理": ["處理", "辦理"],
    "說明解釋": ["說明", "解釋"],
}


DOMAIN_BY_SOURCE = {
    "agriculture-food": "農業食品",
    "ai-data-science": "數位科技",
    "biotech-pharma": "醫療生技",
    "business": "商業管理",
    "chinese": "語文人文",
    "civil-engineering": "工程製造",
    "education": "教育社會",
    "electronics": "電子半導體",
    "energy-environment": "科學環境",
    "finance": "商業管理",
    "general": "日常生活",
    "government": "政府法律",
    "history": "歷史人物",
    "industrial-engineering": "工程製造",
    "law": "政府法律",
    "manufacturing": "工程製造",
    "materials-chemistry": "科學環境",
    "media-design": "媒體設計",
    "medicine": "醫療生技",
    "network-security": "數位科技",
    "people-contemporary": "歷史人物",
    "people-history": "歷史人物",
    "people-oldnews": "歷史人物",
    "psychology-society": "教育社會",
    "science": "科學環境",
    "semiconductor": "電子半導體",
    "software": "數位科技",
    "transport-logistics": "交通物流",
    "mcbopomofo": "日常生活",
}


DOMAIN_FRAMES = {
    "農業食品": [
        ("產地與加工現場的工作討論", "工作群組", "多人討論", "農友、技師與品管人員", "自然直接"),
        ("食品安全與消費疑問", "客服問答", "問答與追問", "消費者與業者", "耐心說明"),
        ("農業技術課程的案例分享", "課堂討論", "講解與提問", "講師與學員", "客氣清楚"),
    ],
    "數位科技": [
        ("系統開發與故障排查", "工作聊天軟體", "工作討論串", "工程師與產品人員", "簡短俐落"),
        ("資安事件或資料流程檢討", "事故檢討會議", "紀錄與追問", "技術團隊與主管", "正式謹慎"),
        ("使用者詢問技術功能", "技術問答", "問題與回覆", "使用者與技術人員", "耐心說明"),
    ],
    "醫療生技": [
        ("醫療團隊討論案例與流程", "專業會議", "討論與紀錄", "醫療人員與研究人員", "正式謹慎"),
        ("衛教內容的編寫與修訂", "共享文件", "文件與批註", "編輯與專業顧問", "耐心說明"),
        ("生技研究專案的工作往返", "電子郵件", "郵件串", "研究團隊與合作單位", "客氣克制"),
    ],
    "商業管理": [
        ("營運會議討論成本與風險", "會議紀錄", "發言與決議", "主管與跨部門同仁", "正式謹慎"),
        ("客戶需求與方案協商", "電子郵件", "郵件往返", "公司與客戶", "客氣克制"),
        ("團隊檢討流程與績效", "工作聊天軟體", "工作討論串", "主管與部屬", "自然直接"),
    ],
    "語文人文": [
        ("讀書會比較詞義與寫法", "讀書會紀錄", "討論與摘記", "讀者與主持人", "耐心說明"),
        ("編輯修改文章用字", "共享文件", "文章與批註", "作者與編輯", "客氣克制"),
        ("課堂討論作品與時代背景", "課堂討論", "提問與回應", "師生", "自然直接"),
    ],
    "工程製造": [
        ("工程現場檢討設計與施工", "工程會議", "紀錄與追問", "工程師與現場人員", "正式謹慎"),
        ("製造異常與品質問題排查", "工作群組", "事故討論串", "製程、設備與品管人員", "急迫但清楚"),
        ("採購規格與驗收條件核對", "電子郵件", "文件往返", "採購與供應商", "客氣克制"),
    ],
    "教育社會": [
        ("校園輔導與學習情境討論", "教師群組", "多人討論", "教師、家長與輔導人員", "溫和謹慎"),
        ("社會議題的公開討論", "社群討論", "貼文與留言", "居民與不同立場參與者", "自然直接"),
        ("研究訪談與觀察紀錄整理", "共享文件", "紀錄與批註", "研究者與受訪者", "正式謹慎"),
    ],
    "電子半導體": [
        ("產品開發與量測結果檢討", "研發會議", "討論與紀錄", "研發、測試與製程人員", "正式謹慎"),
        ("設備異常與零件問題排查", "工作聊天軟體", "工作討論串", "工程師與設備人員", "急迫但清楚"),
        ("技術規格與客戶需求核對", "電子郵件", "郵件往返", "技術團隊與客戶", "客氣克制"),
    ],
    "科學環境": [
        ("研究團隊討論實驗與觀測", "研究會議", "紀錄與追問", "研究人員與學生", "正式謹慎"),
        ("環境議題的居民說明會", "公開會議", "發言與回應", "居民、專家與承辦人", "耐心說明"),
        ("科普文章的編輯討論", "共享文件", "文章與批註", "作者與科學編輯", "自然直接"),
    ],
    "政府法律": [
        ("公文與案件資料的內部討論", "簽辦文件", "擬辦與批註", "承辦人與主管", "正式謹慎"),
        ("契約或權利爭議的書面往返", "正式書信", "主張與回覆", "當事人與專業人員", "客氣克制"),
        ("政策草案的公眾意見討論", "公共論壇", "貼文與回應", "居民與承辦單位", "自然直接"),
    ],
    "歷史人物": [
        ("地方文史展覽的資料整理", "編輯會議", "討論與紀錄", "文史工作者與編輯", "正式謹慎"),
        ("歷史課堂比較人物與事件", "課堂討論", "提問與回應", "師生", "耐心說明"),
        ("舊報刊與人物資料的查證", "研究筆記", "摘記與批註", "研究者與館員", "客氣克制"),
    ],
    "媒體設計": [
        ("設計提案與視覺方向討論", "工作群組", "提案與回饋", "設計師、編輯與客戶", "自然直接"),
        ("內容製作與發布流程檢討", "製作會議", "討論與紀錄", "企劃、設計與製作人員", "簡短俐落"),
        ("作品評論與修改建議", "共享文件", "作品與批註", "創作者與審稿者", "客氣克制"),
    ],
    "交通物流": [
        ("運輸調度與配送異常協調", "工作群組", "多人討論", "調度、駕駛與客服", "急迫但清楚"),
        ("交通規劃與乘客需求討論", "公開會議", "發言與回應", "乘客、業者與承辦人", "耐心說明"),
        ("倉儲與供應鏈流程檢討", "會議紀錄", "發言與決議", "物流與營運人員", "正式謹慎"),
    ],
    "日常生活": [
        ("家人朋友協調生活安排", "通訊軟體群組", "多人對話", "家人與朋友", "自然直接"),
        ("消費與服務問題的實際對話", "客服文字對談", "客服紀錄", "顧客與業者", "客氣克制"),
        ("社群上分享經驗與不同看法", "社群留言", "貼文與留言", "網友與發文者", "輕鬆自然"),
    ],
}


def stable_int(value: str) -> int:
    return int.from_bytes(hashlib.sha256(value.encode("utf-8")).digest()[:8], "big")


def stable_uniform(value: str) -> float:
    return (stable_int(value) + 1) / (2**64 + 1)


def all_han(word: str) -> bool:
    return bool(re.fullmatch(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+", word))


def canonical_collection_term(word: str) -> str:
    """Normalize duplicate Latin-width/case variants in categorized lexicons."""
    return unicodedata.normalize("NFKC", word).upper()


def valid_collection_term(word: str) -> bool:
    """Apply the public collection's Han-first, 2–5-code-point contract."""
    return (
        2 <= len(word) <= 5
        and bool(re.match(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", word))
        and word == canonical_collection_term(word)
    )


def taiwan_compatible(word: str) -> bool:
    return not any(fragment in word for fragment in NON_TAIWAN_FRAGMENTS)


def load_mcbopomofo() -> dict[str, int]:
    counts = {}
    for line in MCB_COUNTS.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) != 2 or not fields[1].isdigit():
            continue
        word, raw_count = fields
        if 2 <= len(word) <= 5 and all_han(word) and taiwan_compatible(word) and int(raw_count) > 0:
            counts[word] = int(raw_count)
    mapped = set()
    for line in MCB_MAPPINGS.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if not fields:
            continue
        word, readings = fields[0], fields[1:]
        if word in counts and len(readings) == len(word):
            mapped.add(word)
    return {word: count for word, count in counts.items() if word in mapped}


def load_ai_lexicons() -> tuple[dict[str, dict], dict[str, dict]]:
    paths = sorted(COLLECTION_ROOT.glob("phrase.*.tsv"))
    if len(paths) != 29 or ANIME not in paths:
        raise ValueError(f"expected 29 categorized lexicons including anime, found {len(paths)}")
    by_word: dict[str, dict] = {}
    by_source: dict[str, dict] = {}
    for path in paths:
        if path == ANIME:
            continue
        source = path.stem.removeprefix("phrase.")
        source_terms = {}
        for line in path.read_text(encoding="utf-8").splitlines():
            fields = line.split("\t")
            if len(fields) < 3 or not fields[1].isdigit():
                continue
            word, raw_count, reading = fields[:3]
            # The 28 source lexicons are included in full after their public
            # Han-first structural contract. Lowercase/full-width Latin
            # duplicates resolve to the existing uppercase ASCII spelling.
            # Taiwan wording checks apply to generated prose and to the extra
            # McBopomofo sample, not to this fixed set.
            if not valid_collection_term(word):
                continue
            label = fields[3] if len(fields) > 3 else source
            row = {"word": word, "count": int(raw_count), "reading": reading, "label": label, "source": source}
            source_terms[word] = row
            entry = by_word.setdefault(word, {"word": word, "count": int(raw_count), "readings": set(), "sources": set(), "labels": set()})
            entry["count"] = max(entry["count"], int(raw_count))
            entry["readings"].add(reading)
            entry["sources"].add(source)
            entry["labels"].add(label)
        by_source[source] = source_terms
    if len(by_source) != 28:
        raise ValueError(f"expected 28 non-anime lexicons, found {len(by_source)}")
    valid_rows = sum(len(terms) for terms in by_source.values())
    if valid_rows != EXPECTED_COLLECTION_ROWS or len(by_word) != EXPECTED_COLLECTION_TERMS:
        raise ValueError(
            "categorized lexicon inventory changed: "
            f"rows={valid_rows} (expected {EXPECTED_COLLECTION_ROWS}), "
            f"unique={len(by_word)} (expected {EXPECTED_COLLECTION_TERMS})"
        )
    return by_word, by_source


def select_pool(mcb: dict[str, int], ai: dict[str, dict]) -> dict[str, dict]:
    pool = {}
    for word, entry in ai.items():
        pool[word] = {
            "word": word,
            "count": max(entry["count"], mcb.get(word, 0)),
            "sources": sorted(entry["sources"] | ({"mcbopomofo"} if word in mcb else set())),
            "labels": sorted(entry["labels"]),
            "ai_only": word not in mcb,
        }
    needed = POOL_SIZE - len(pool)
    if needed < 0:
        raise ValueError(f"AI lexicons already exceed pool size: {len(pool)}")
    candidates = []
    for word, count in mcb.items():
        if word in pool or count < MCB_MIN_COUNT or (len(word) == 2 and word.endswith("的")):
            continue
        weight = count ** 0.8
        key = -math.log(stable_uniform(f"{SEED}:mcb:{word}")) / weight
        candidates.append((key, word, count))
    if len(candidates) < needed:
        raise ValueError(f"not enough McBopomofo candidates: {len(candidates)} < {needed}")
    for _, word, count in sorted(candidates)[:needed]:
        pool[word] = {"word": word, "count": count, "sources": ["mcbopomofo"], "labels": ["小麥注音"], "ai_only": False}
    if len(pool) != POOL_SIZE:
        raise AssertionError(len(pool))
    return pool


def term_domain(entry: dict) -> str:
    domains = [DOMAIN_BY_SOURCE[source] for source in entry["sources"] if source != "mcbopomofo"]
    return Counter(domains).most_common(1)[0][0] if domains else "日常生活"


def build_groups(pool: dict[str, dict]) -> list[dict]:
    alias_by_word = {}
    for name, words in SYNONYM_SEEDS.items():
        for word in words:
            if word in alias_by_word:
                raise ValueError(f"word appears in two synonym seeds: {word}")
            alias_by_word[word] = name

    # Extend the same reviewed substitutions to compound terms. For example,
    # 成本預測／費用預測 share one auditable signature. Greedy assignment is
    # deterministic and prevents a term from entering two semantic groups.
    variant_candidates: dict[tuple[str, str], set[str]] = defaultdict(set)
    for word in pool:
        if word in alias_by_word:
            continue
        for name, alternatives in SYNONYM_SEEDS.items():
            for alternative in alternatives:
                if len(alternative) >= 2 and word.count(alternative) == 1:
                    signature = word.replace(alternative, "{同義詞}")
                    variant_candidates[(name, signature)].add(word)
    variant_assignment = {}
    ranked_variants = sorted(
        ((key, words) for key, words in variant_candidates.items() if len(words) > 1),
        key=lambda item: (-len(item[1]), stable_int(f"{SEED}:variant:{item[0][0]}:{item[0][1]}")),
    )
    for (name, signature), words in ranked_variants:
        available = sorted(
            (word for word in words if word not in variant_assignment),
            key=lambda word: stable_int(f"{SEED}:variant-word:{name}:{signature}:{word}"),
        )
        if len(available) < 2:
            continue
        group_name = f"{name}:{signature}"
        for word in available:
            variant_assignment[word] = group_name

    bigram_documents = Counter()
    for word in pool:
        bigram_documents.update(set(word[index:index + 2] for index in range(len(word) - 1)))

    grouped: dict[tuple[str, str], list[str]] = defaultdict(list)
    kinds = {}
    for word, entry in pool.items():
        domain = term_domain(entry)
        if word in alias_by_word:
            key = ("同義近義", alias_by_word[word])
        elif word in variant_assignment:
            key = ("同義衍生", variant_assignment[word])
        else:
            candidates = [
                part for part in set(word[index:index + 2] for index in range(len(word) - 1))
                if 2 <= bigram_documents[part] <= 24
            ]
            if candidates:
                part = min(candidates, key=lambda value: (bigram_documents[value], stable_int(f"{SEED}:part:{word}:{value}")))
                key = ("概念詞族", f"{domain}:{part}")
            else:
                key = ("單詞", word)
        grouped[key].append(word)
        kinds[key] = key[0]

    result = []
    for (kind, name), words in grouped.items():
        words.sort(key=lambda word: stable_int(f"{SEED}:group:{name}:{word}"))
        # Large morphological families are related but are not asserted to be
        # synonyms. Smaller chunks preserve locality and remain easy to pack.
        chunk_size = 30 if kind in SEMANTIC_GROUP_KINDS else 12
        for index in range(0, len(words), chunk_size):
            chunk = words[index:index + chunk_size]
            domains = Counter(term_domain(pool[word]) for word in chunk)
            result.append({
                "kind": kind,
                "name": name if index == 0 else f"{name}:{index // chunk_size + 1}",
                "domain": domains.most_common(1)[0][0],
                "terms": chunk,
            })
    return result


def pack_base_bundles(groups: list[dict], pool: dict[str, dict]) -> list[dict]:
    bin_count = POOL_SIZE // TERMS_PER_ARTICLE
    domain_terms = Counter()
    for group in groups:
        domain_terms[group["domain"]] += len(group["terms"])

    # Give each bundle a target domain. Hamilton allocation keeps the total at
    # exactly 200 while matching the pool's domain mix as closely as possible.
    domain_bins = {domain: count // TERMS_PER_ARTICLE for domain, count in domain_terms.items()}
    remaining_bins = bin_count - sum(domain_bins.values())
    remainders = sorted(
        domain_terms,
        key=lambda domain: (
            domain_terms[domain] % TERMS_PER_ARTICLE,
            stable_int(f"{SEED}:domain-bin:{domain}"),
        ),
        reverse=True,
    )
    for domain in remainders[:remaining_bins]:
        domain_bins[domain] += 1

    bins = []
    for domain in sorted(domain_bins):
        for _ in range(domain_bins[domain]):
            bins.append({"terms": [], "groups": [], "domains": Counter(), "target_domain": domain})
    if len(bins) != bin_count:
        raise AssertionError((len(bins), bin_count))
    multi = [group for group in groups if len(group["terms"]) > 1]
    singles = [group for group in groups if len(group["terms"]) == 1]
    multi.sort(key=lambda group: (-len(group["terms"]), stable_int(f"{SEED}:pack:{group['name']}")))
    singles.sort(key=lambda group: stable_int(f"{SEED}:single:{group['name']}"))

    def place(group: dict) -> None:
        size = len(group["terms"])
        candidates = [index for index, bundle in enumerate(bins) if len(bundle["terms"]) + size <= TERMS_PER_ARTICLE]
        if not candidates and group["kind"] not in SEMANTIC_GROUP_KINDS and size > 1:
            for word in group["terms"]:
                place({"kind": "單詞", "name": word, "domain": group["domain"], "terms": [word]})
            return
        if not candidates:
            raise ValueError(f"cannot keep synonym group together: {group['name']} ({size})")
        index = max(
            candidates,
            key=lambda candidate: (
                bins[candidate]["target_domain"] == group["domain"],
                bins[candidate]["domains"][group["domain"]],
                len(bins[candidate]["terms"]),
                stable_int(f"{SEED}:bin:{group['name']}:{candidate}"),
            ),
        )
        bins[index]["terms"].extend(group["terms"])
        bins[index]["groups"].append(group)
        bins[index]["domains"][group["domain"]] += size

    for group in multi:
        place(group)
    for group in singles:
        place(group)

    def split_required_halves(bundle: dict, bundle_index: int) -> tuple[list[str], list[str]]:
        ordered_groups = sorted(
            bundle["groups"],
            key=lambda group: stable_int(f"{SEED}:half-group:{bundle_index}:{group['name']}"),
        )

        def subset_for_half(units: list[list[str]]) -> set[int] | None:
            reachable: dict[int, tuple[int, ...]] = {0: ()}
            for unit_index, unit in enumerate(units):
                for total, selected in sorted(list(reachable.items()), reverse=True):
                    next_total = total + len(unit)
                    if next_total <= REQUIRED_TERMS_PER_ARTICLE and next_total not in reachable:
                        reachable[next_total] = selected + (unit_index,)
            selected = reachable.get(REQUIRED_TERMS_PER_ARTICLE)
            return set(selected) if selected is not None else None

        units = [list(group["terms"]) for group in ordered_groups]
        selected = subset_for_half(units)
        if selected is None:
            # Preserve explicit synonym groups, but allow a broader concept
            # family to straddle the two complementary 15-term articles.
            units = []
            for group in ordered_groups:
                if group["kind"] in SEMANTIC_GROUP_KINDS:
                    units.append(list(group["terms"]))
                else:
                    units.extend([[word] for word in group["terms"]])
            selected = subset_for_half(units)
        if selected is None:
            raise ValueError(f"cannot split base bundle {bundle_index} into two 15-term halves")
        first = [word for unit_index, unit in enumerate(units) if unit_index in selected for word in unit]
        second = [word for unit_index, unit in enumerate(units) if unit_index not in selected for word in unit]
        first.sort(key=lambda word: stable_int(f"{SEED}:half-a:{bundle_index}:{word}"))
        second.sort(key=lambda word: stable_int(f"{SEED}:half-b:{bundle_index}:{word}"))
        return first, second

    for index, bundle in enumerate(bins, 1):
        if len(bundle["terms"]) != TERMS_PER_ARTICLE:
            raise ValueError(f"base bundle {index} has {len(bundle['terms'])} terms")
        if len(set(bundle["terms"])) != TERMS_PER_ARTICLE:
            raise ValueError(f"base bundle {index} contains duplicate terms")
        bundle["base_bundle"] = index
        bundle["domain"] = bundle["target_domain"]
        bundle["terms"].sort(key=lambda word: stable_int(f"{SEED}:bundle:{index}:{word}"))
        bundle["required_a"], bundle["required_b"] = split_required_halves(bundle, index)
    return bins


def expand_article_specs(base_bundles: list[dict], pool: dict[str, dict]) -> list[dict]:
    # Duplicate half the base bundles. The second article requires the other
    # 15 terms, so 4,500 distinct pool terms are guaranteed to reach prose.
    scored = []
    for bundle in base_bundles:
        second_half_ai_only = sum(pool[word]["ai_only"] for word in bundle["required_b"])
        score = second_half_ai_only * 10_000 + stable_int(f"{SEED}:duplicate:{bundle['base_bundle']}") % 10_000
        scored.append((score, bundle["base_bundle"]))
    duplicated = {index for _, index in sorted(scored, reverse=True)[:100]}

    specs = []
    for bundle in base_bundles:
        specs.append({"bundle": bundle, "variant": "A", "required": bundle["required_a"], "optional": bundle["required_b"]})
        if bundle["base_bundle"] in duplicated:
            specs.append({"bundle": bundle, "variant": "B", "required": bundle["required_b"], "optional": bundle["required_a"]})
    if len(specs) != ARTICLE_COUNT:
        raise AssertionError(len(specs))
    random.Random(SEED).shuffle(specs)
    return specs


def build_prompt(sequence: int, spec: dict, pool: dict[str, dict]) -> dict:
    bundle = spec["bundle"]
    domain = bundle["domain"]
    frames = DOMAIN_FRAMES[domain]
    frame = frames[stable_int(f"{SEED}:frame:{sequence}:{spec['variant']}:{bundle['base_bundle']}") % len(frames)]
    activity, channel, output_form, relationship, tone = frame
    required = list(spec["required"])
    optional = list(spec["optional"])
    assigned = required + optional
    assigned.sort(key=lambda word: stable_int(f"{SEED}:assigned:{sequence}:{word}"))
    group_rows = []
    for group in bundle["groups"]:
        selected = [word for word in group["terms"] if word in assigned]
        if len(selected) > 1:
            group_rows.append({"kind": group["kind"], "name": group["name"], "terms": selected})
    source_counts = Counter(source for word in assigned for source in pool[word]["sources"] if source != "mcbopomofo")
    main_sources = [name for name, _ in source_counts.most_common(4)] or ["mcbopomofo"]
    title = f"{domain}詞群的{activity}（v4-{sequence:03d}）"
    return {
        "id": f"tw-typing-v4-{sequence:03d}",
        "version": "v4",
        "title": title,
        "category": f"詞庫導向／{domain}",
        "target_chars": 1200,
        "accepted_char_range": [1050, 1350],
        "era": "2020-2026",
        "region": "台灣",
        "channel": channel,
        "output_form": output_form,
        "relationship": relationship,
        "tone": tone,
        "activity": activity,
        "base_bundle": bundle["base_bundle"],
        "bundle_variant": spec["variant"],
        "lexicon_sources": main_sources,
        "assigned_terms": assigned,
        "required_terms": required,
        "optional_terms": optional,
        "term_groups": group_rows,
        "scenario": f"以現代台灣的{activity}為主軸，透過{channel}呈現{relationship}真正可能寫出的文字。文章以{tone}為主要語氣，並把指定詞彙放進有因果與上下文的句子。",
        "requirements": [
            f"正文總長約一千二百字，形式為{output_form}。",
            "完整且逐字使用 required_terms 的十五個詞，每個至少一次；可以使用 optional_terms，但不要求全部出現。",
            "不得把指定詞彙集中抄成清單、標籤、括號串或詞語接龍；同一句原則上不超過三個指定詞。",
            "同義、近義與同概念詞已盡量放在同一篇；若同時使用，應依語境呈現自然差別，不得只做機械替換。",
            "專業詞必須放在合理工作、學習或生活情境；不確定的細節可以用人物提問、查證或保留態度呈現。",
            "涉及醫療、法律、公共政策、人物或歷史時，不捏造診斷、法條、即時政策、統計數字、引言或人物私事。",
            "使用台灣繁體中文與台灣慣用語，保留對話、追問、不同意見及自然長短句。",
            "結尾須符合事件本身，可以未解決或只得到局部結論，不得固定寫成心得總結。",
        ],
        "avoid": ["不得混入簡體字或中國大陸慣用語", "不得為塞詞而改變詞義", "不得複製百科式定義", "不得捏造可變資訊", "不得使用固定人工智慧結語"],
        "evaluation": ["十五個必用詞是否逐字出現", "詞義與搭配是否自然", "同義近義詞是否放在可比較的上下文", "是否像台灣使用者會輸入的文字", "是否避免清單式塞詞"],
        "weight_class": "experimental",
    }


def validate(prompts: list[dict], pool: dict[str, dict], base_bundles: list[dict]) -> None:
    if len(prompts) != ARTICLE_COUNT:
        raise ValueError(f"expected {ARTICLE_COUNT} prompts, got {len(prompts)}")
    if len(pool) != POOL_SIZE:
        raise ValueError(f"expected {POOL_SIZE} pool terms, got {len(pool)}")
    if len(base_bundles) != 200:
        raise ValueError(f"expected 200 base bundles, got {len(base_bundles)}")
    if len({item["id"] for item in prompts}) != ARTICLE_COUNT or len({item["title"] for item in prompts}) != ARTICLE_COUNT:
        raise ValueError("duplicate prompt id or title")
    assigned_slots = sum(len(item["assigned_terms"]) for item in prompts)
    required_slots = sum(len(item["required_terms"]) for item in prompts)
    if assigned_slots != 9000 or required_slots != 4500:
        raise ValueError(f"slot mismatch: assigned={assigned_slots}, required={required_slots}")
    for item in prompts:
        if len(item["assigned_terms"]) != 30 or len(set(item["assigned_terms"])) != 30:
            raise ValueError(f"invalid assigned terms: {item['id']}")
        if len(item["required_terms"]) != 15 or not set(item["required_terms"]) <= set(item["assigned_terms"]):
            raise ValueError(f"invalid required terms: {item['id']}")
    if set(word for item in prompts for word in item["assigned_terms"]) != set(pool):
        raise ValueError("not every pool term was assigned")
    if len(set(word for item in prompts for word in item["required_terms"])) != 4500:
        raise ValueError("required terms are not globally unique")
    if any("anime" in item["lexicon_sources"] for item in prompts):
        raise ValueError("anime lexicon leaked into v4")
    bundle_by_term = {}
    for bundle in base_bundles:
        for term in bundle["terms"]:
            bundle_by_term[term] = bundle["base_bundle"]
    for name, words in SYNONYM_SEEDS.items():
        selected = [word for word in words if word in pool]
        if len(selected) > 1 and len({bundle_by_term[word] for word in selected}) != 1:
            raise ValueError(f"synonym group split across bundles: {name} / {selected}")
        if len(selected) > 1:
            bundle = base_bundles[bundle_by_term[selected[0]] - 1]
            if not (set(selected) <= set(bundle["required_a"]) or set(selected) <= set(bundle["required_b"])):
                raise ValueError(f"synonym group split across required halves: {name} / {selected}")
    for bundle in base_bundles:
        for group in bundle["groups"]:
            if group["kind"] in SEMANTIC_GROUP_KINDS and len(group["terms"]) > 1:
                terms = set(group["terms"])
                if not (terms <= set(bundle["required_a"]) or terms <= set(bundle["required_b"])):
                    raise ValueError(f"semantic group split across required halves: {group['name']}")


def write_assignments(prompts: list[dict], pool: dict[str, dict], group_lookup: dict[str, tuple[str, str]]) -> None:
    lines = ["prompt_id\tbase_bundle\trole\tword\tsources\tgroup_kind\tgroup_name"]
    for prompt in prompts:
        required = set(prompt["required_terms"])
        for word in prompt["assigned_terms"]:
            kind, name = group_lookup[word]
            lines.append("\t".join([
                prompt["id"], str(prompt["base_bundle"]), "required" if word in required else "optional", word,
                ",".join(pool[word]["sources"]), kind, name,
            ]))
    ASSIGNMENTS.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_plan(stats: dict) -> None:
    lines = [
        "# AI 繁中輸入語料 v4：6,000 詞／300 篇規劃",
        "",
        "v4 是獨立的詞庫導向實驗集。來源包含小麥注音與 28 個分類詞庫，明確排除 `phrase.anime.tsv`。",
        "",
        "## 詞池與文章配額",
        "",
        f"- 不重複候選詞池：{stats['pool']['unique_terms']:,} 詞。",
        f"- 28 個非動漫分類詞庫共有 {stats['pool']['categorized_lexicon_rows']:,} 筆有效列；正規化大小寫／全半形並跨庫去重後，全部納入 {stats['pool']['ai_terms']:,} 個不同詞，其中 {stats['pool']['ai_only_terms']:,} 詞不在小麥詞表。",
        f"- 另外抽入小麥注音專屬詞：{stats['pool']['mcb_only_terms']:,} 詞。",
        "- 共 300 篇，每篇 30 個不同候選詞，形成 9,000 個詞槽。",
        "- 每篇預先指定其中 15 個為必用詞，共 4,500 個必用詞槽，而且 4,500 個詞彼此不重複。",
        "- 6,000 詞都至少分配一次；其中 3,000 詞分配兩次，另外 3,000 詞分配一次。",
        "",
        "## 同義與概念分組",
        "",
        f"- 人工可審核的同義／近義種子共 {stats['groups']['seed_group_count']} 組，實際命中 {stats['groups']['matched_seed_groups']} 組。",
        f"- 同一批替換關係另命中 {stats['groups']['derived_synonym_group_count']} 組複合詞，例如「成本預測／費用預測」。",
        f"- 另以共同雙字核心與來源領域建立 {stats['groups']['concept_family_count']:,} 個概念詞族。",
        "- 明確同義／近義組與其複合詞視為不可拆分單位，驗證器會阻止它們被分到不同 base bundle 或不同 15 詞半組。",
        "- 同概念詞族會盡量同篇，但只標為相關詞，不宣稱它們語義完全相同。",
        "",
        "## 分配方式",
        "",
        "先把 6,000 詞裝成 200 個各 30 詞的 base bundle，再挑 100 組做第二篇不同情境。第一篇使用 A 組 15 詞，第二篇使用互補的 B 組 15 詞，因此重複 bundle 不會重複要求同一批詞。",
        "",
        f"小麥注音專屬詞先限定 phrase.occ 詞頻至少 {MCB_MIN_COUNT}，再採固定 seed 的詞頻加權隨機抽樣（權重為 count^0.8）；所有輸出可由產生器完全重現。",
        "",
        "## 領域分布",
        "",
        "| 領域 | 篇數 |",
        "| --- | ---: |",
        *[f"| {name} | {count} |" for name, count in stats["domain_counts"].items()],
        "",
        "## 生成要求",
        "",
        "- 正文約 1,200 字，15 個必用詞必須逐字出現。",
        "- 不得把詞彙抄成清單、括號串或詞語接龍，同一句原則上不超過三個指定詞。",
        "- 同義與近義詞若同時使用，要在自然上下文中呈現差異。",
        "- 技術、醫療、法律、政策、歷史與人物內容不得捏造事實、法條、診斷、數字或引言。",
        "- 全部使用現代台灣繁體中文；v4 專注詞彙搭配，不另外承擔 v2／v3 的年代比例。",
        "",
        "目前只建立題目與詞彙分配，尚未產生 300 篇正文。",
        "",
    ]
    PLAN.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    mcb = load_mcbopomofo()
    ai, by_source = load_ai_lexicons()
    pool = select_pool(mcb, ai)
    groups = build_groups(pool)
    base_bundles = pack_base_bundles(groups, pool)
    specs = expand_article_specs(base_bundles, pool)
    prompts = [build_prompt(index, spec, pool) for index, spec in enumerate(specs, 1)]
    validate(prompts, pool, base_bundles)

    with OUTPUT.open("w", encoding="utf-8") as stream:
        for prompt in prompts:
            stream.write(json.dumps(prompt, ensure_ascii=False, separators=(",", ":")) + "\n")

    group_lookup = {}
    for group in groups:
        for word in group["terms"]:
            group_lookup[word] = (group["kind"], group["name"])
    write_assignments(prompts, pool, group_lookup)

    assigned_usage = Counter(word for prompt in prompts for word in prompt["assigned_terms"])
    required_usage = Counter(word for prompt in prompts for word in prompt["required_terms"])
    matched_seed_groups = sum(sum(word in pool for word in words) > 1 for words in SYNONYM_SEEDS.values())
    stats = {
        "version": "v4",
        "articles": ARTICLE_COUNT,
        "terms_per_article": TERMS_PER_ARTICLE,
        "required_terms_per_article": REQUIRED_TERMS_PER_ARTICLE,
        "assigned_slots": sum(assigned_usage.values()),
        "required_slots": sum(required_usage.values()),
        "unique_required_terms": len(required_usage),
        "pool": {
            "unique_terms": len(pool),
            "categorized_lexicon_rows": sum(len(terms) for terms in by_source.values()),
            "ai_terms": len(ai),
            "ai_only_terms": sum(entry["ai_only"] for entry in pool.values()),
            "mcb_only_terms": sum(entry["sources"] == ["mcbopomofo"] for entry in pool.values()),
            "mcb_eligible_candidates": len(mcb),
            "assigned_once": sum(count == 1 for count in assigned_usage.values()),
            "assigned_twice": sum(count == 2 for count in assigned_usage.values()),
            "minimum_assignment_count": min(assigned_usage.values()),
            "maximum_assignment_count": max(assigned_usage.values()),
        },
        "sources": {
            "mcbopomofo": str(MCB_COUNTS.relative_to(REPO)),
            "non_anime_lexicons": [path.name for path in sorted(COLLECTION_ROOT.glob("phrase.*.tsv")) if path != ANIME],
            "excluded": ANIME.name,
            "source_term_counts": {source: len(terms) for source, terms in sorted(by_source.items())},
        },
        "groups": {
            "seed_group_count": len(SYNONYM_SEEDS),
            "matched_seed_groups": matched_seed_groups,
            "synonym_group_count": sum(group["kind"] == "同義近義" and len(group["terms"]) > 1 for group in groups),
            "derived_synonym_group_count": sum(group["kind"] == "同義衍生" and len(group["terms"]) > 1 for group in groups),
            "concept_family_count": sum(group["kind"] == "概念詞族" and len(group["terms"]) > 1 for group in groups),
            "singleton_count": sum(len(group["terms"]) == 1 for group in groups),
        },
        "domain_counts": dict(Counter(prompt["category"].removeprefix("詞庫導向／") for prompt in prompts).most_common()),
        "channel_counts": dict(Counter(prompt["channel"] for prompt in prompts).most_common()),
        "base_bundles": len(base_bundles),
        "duplicated_bundles": sum(Counter(prompt["base_bundle"] for prompt in prompts).values()) - len(base_bundles),
        "unique_titles": len({prompt["title"] for prompt in prompts}),
    }
    STATS.write_text(json.dumps(stats, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_plan(stats)

    preview_indexes = []
    for domain in DOMAIN_FRAMES:
        match = next((index for index, prompt in enumerate(prompts) if prompt["category"] == f"詞庫導向／{domain}"), None)
        if match is not None:
            preview_indexes.append(match)
    lines = ["# Typing prompt v4 preview", "", "完整資料集為 `typing-prompts-v4.jsonl`。", ""]
    for index in preview_indexes:
        prompt = prompts[index]
        lines.extend([
            f"## {prompt['id']}｜{prompt['title']}", "",
            f"- 領域：{prompt['category']}", f"- 媒介：{prompt['channel']}", f"- 形式：{prompt['output_form']}",
            f"- 詞源：{', '.join(prompt['lexicon_sources'])}", f"- Base bundle：{prompt['base_bundle']} / {prompt['bundle_variant']}",
            f"- 必用 15 詞：{'、'.join(prompt['required_terms'])}", f"- 可選 15 詞：{'、'.join(prompt['optional_terms'])}",
            f"- 情境：{prompt['scenario']}", "- 必寫要求：", *[f"  - {value}" for value in prompt["requirements"]], "",
        ])
    PREVIEW.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")

    print(json.dumps({
        "articles": len(prompts), "pool_terms": len(pool), "assigned_slots": stats["assigned_slots"],
        "required_slots": stats["required_slots"], "unique_required_terms": stats["unique_required_terms"],
        "ai_terms": stats["pool"]["ai_terms"], "mcb_only_terms": stats["pool"]["mcb_only_terms"],
        "matched_synonym_groups": stats["groups"]["matched_seed_groups"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
