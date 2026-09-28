#!/usr/bin/env python3
"""Deduplicate, read, and conservatively score Taiwan search-trend terms."""
from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import re
import sqlite3


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
DEFAULT_SOURCE = HERE / "search-trend-unigram-source.txt"
DEFAULT_OUTPUT = HERE / "search-trend-unigram.tsv"
DEFAULT_REVIEW = HERE / "search-trend-unigram-review.tsv"
DEFAULT_REPORT = HERE / "search-trend-unigram-report.json"
DEFAULT_OVERRIDES = HERE / "search-trend-reading-overrides.tsv"
DEFAULT_DATABASE = ROOT / "Source/Distributions/Takao/CookedDatabase/KeyKey.db"
COUNTS = ROOT / "DataSource/McBopomofo/phrase.occ"
MAPPINGS = ROOT / "DataSource/McBopomofo/BPMFMappings.txt"
PROJECT_LEXICONS = (
    HERE / "supplemental-lexicon.tsv",
    HERE / "numeric-unit-lexicon.tsv",
)
TRAINING = tuple(
    ROOT / f"DataSource/AISyntheticArticles/typing-articles-v{version}.jsonl"
    for version in (2, 3, 4)
)
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+").fullmatch
CONSONANTS = " ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ"
MEDIALS = " ㄧㄨㄩ"
VOWELS = " ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ"
TONES = " ˊˇˋ˙"
MAX_COUNT = 100


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def reading(query: str) -> str:
    if len(query) != 2 or any(not 48 <= ord(value) <= 126 for value in query):
        raise ValueError(f"invalid absolute-order query {query!r}")
    order = ord(query[0]) - 48 + (ord(query[1]) - 48) * 79
    if not 0 < order < 6160:
        raise ValueError(f"invalid absolute-order query {query!r}")
    return (
        CONSONANTS[order % 22]
        + MEDIALS[order // 22 % 4]
        + VOWELS[order // 88 % 14]
        + TONES[order // 1232]
    ).replace(" ", "")


def load_terms(path: Path) -> list[str]:
    terms = [line.strip() for line in path.read_text(encoding="utf-8-sig").splitlines()]
    if not terms or any(not term or not HAN(term) or not 1 <= len(term) <= 7 for term in terms):
        raise ValueError(f"{path}: every line must be one 1-7 character Han term")
    if len(terms) != len(set(terms)):
        duplicates = sorted(term for term in set(terms) if terms.count(term) > 1)
        raise ValueError(f"{path}: duplicate terms: {duplicates}")
    return terms


def load_counts() -> dict[str, int]:
    result = {}
    for line in COUNTS.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1].isdigit():
            result[fields[0]] = int(fields[1])
    return result


def load_project_lexicon_words() -> set[str]:
    result = set()
    for path in PROJECT_LEXICONS:
        with path.open(encoding="utf-8", newline="") as source:
            for row in csv.reader(source, delimiter="\t"):
                if len(row) >= 2 and row[1].isdigit() and int(row[1]) > 0:
                    result.add(row[0])
    return result


def load_mappings() -> dict[str, list[list[str]]]:
    result: dict[str, list[list[str]]] = {}
    for line in MAPPINGS.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if fields and len(fields) - 1 == len(fields[0]):
            result.setdefault(fields[0], []).append(fields[1:])
    return result


def load_overrides(path: Path) -> dict[str, tuple[list[str], str]]:
    with path.open(encoding="utf-8", newline="") as source:
        rows = list(csv.DictReader(source, delimiter="\t"))
    result = {}
    for number, row in enumerate(rows, 2):
        word = row.get("word", "")
        values = row.get("reading", "").split()
        if not word or len(values) != len(word) or word in result:
            raise ValueError(f"{path}:{number}: invalid or duplicate override")
        result[word] = (values, row.get("reason", ""))
    return result


@dataclass(frozen=True)
class Token:
    start: int
    word: str
    query: str


class DatabaseLexicon:
    def __init__(self, path: Path, excluded_words: set[str]):
        self.words: dict[str, list[tuple[str, float]]] = {}
        with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as database:
            for query, word, probability in database.execute(
                "SELECT qstring,current,probability FROM unigrams ORDER BY rowid"
            ):
                if (word and word not in excluded_words and HAN(word)
                        and len(query) == 2 * len(word)):
                    self.words.setdefault(word, []).append((query, probability))
        self.max_length = max(map(len, self.words))

    def segment(self, text: str) -> list[Token]:
        best: list[tuple[float, Token | None]] = [(-math.inf, None)] * (len(text) + 1)
        best[0] = (0.0, None)
        for end in range(1, len(text) + 1):
            for start in range(max(0, end - self.max_length), end):
                for query, probability in self.words.get(text[start:end], ()):
                    score = best[start][0] + probability
                    if score > best[end][0]:
                        best[end] = (score, Token(start, text[start:end], query))
        if best[-1][1] is None:
            raise ValueError(f"cannot derive a local reading for {text}")
        result = []
        end = len(text)
        while end:
            token = best[end][1]
            assert token is not None
            result.append(token)
            end = token.start
        return result[::-1]


def training_texts() -> tuple[list[str], list[dict[str, object]]]:
    texts = []
    sources = []
    expected = (1650, 350, 300)
    for path, count in zip(TRAINING, expected):
        rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
        if len(rows) != count:
            raise ValueError(f"{path}: expected {count} articles")
        texts.extend(row["text"] for row in rows)
        sources.append({"file": path.name, "articles": count, "sha256": sha256(path)})
    return texts, sources


def write_tsv(path: Path, fieldnames: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=fieldnames, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--overrides", type=Path, default=DEFAULT_OVERRIDES)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--review", type=Path, default=DEFAULT_REVIEW)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument(
        "--minimum-count", type=int, choices=(0, 1), default=1,
        help="Use 1 to retain every deduplicated search term; 0 keeps corpus-unseen terms as audit-only rows",
    )
    args = parser.parse_args()
    try:
        terms = load_terms(args.source)
        source_counts = load_counts()
        base_words = {word for word, count in source_counts.items() if count > 0}
        base_words.update(load_project_lexicon_words())
        mappings = load_mappings()
        overrides = load_overrides(args.overrides)
        custom_words = set(terms) - base_words
        lexicon = DatabaseLexicon(args.database, custom_words)
        texts, sources = training_texts()
        custom = []
        review = []
        used_overrides = set()
        for term in terms:
            documents = sum(term in text for text in texts)
            occurrences = sum(text.count(term) for text in texts)
            if term in base_words:
                review.append({
                    "詞": term,
                    "處理": "既有詞，剔除重複",
                    "小麥詞頻": source_counts.get(term, ""),
                    "建模文章數": documents,
                    "建模出現次數": occurrences,
                    "自訂詞頻": "",
                    "注音": "",
                    "讀音來源": "既有 KeyKey.db",
                })
                continue
            if term in overrides:
                syllables, reason = overrides[term]
                reading_source = f"人工慣用讀音：{reason}"
                used_overrides.add(term)
            elif term in mappings:
                syllables = mappings[term][0]
                reading_source = "本地 McBopomofo BPMFMappings"
            else:
                tokens = lexicon.segment(term)
                query = "".join(token.query for token in tokens)
                syllables = [reading(query[index:index + 2]) for index in range(0, len(query), 2)]
                reading_source = "本地 KeyKey unigram 分詞：" + "+".join(token.word for token in tokens)
            count = min(MAX_COUNT, max(args.minimum_count, occurrences))
            custom.append({"詞": term, "詞頻": count, "注音": " ".join(syllables)})
            review.append({
                "詞": term,
                "處理": "新增" if count else "保留審核，詞頻 0",
                "小麥詞頻": source_counts.get(term, ""),
                "建模文章數": documents,
                "建模出現次數": occurrences,
                "自訂詞頻": count,
                "注音": " ".join(syllables),
                "讀音來源": reading_source,
            })
        unused = set(overrides) - used_overrides
        if unused:
            raise ValueError(f"unused reading overrides: {sorted(unused)}")
        write_tsv(args.output, ["詞", "詞頻", "注音"], custom)
        write_tsv(
            args.review,
            ["詞", "處理", "小麥詞頻", "建模文章數", "建模出現次數", "自訂詞頻", "注音", "讀音來源"],
            review,
        )
        report = {
            "format": 1,
            "source": {"file": args.source.name, "terms": len(terms), "sha256": sha256(args.source)},
            "database_sha256": sha256(args.database),
            "training_sources": sources,
            "frequency_policy": (
                f"min({MAX_COUNT}, max({args.minimum_count}, exact substring occurrences in all 2300 training articles))"
            ),
            "input_duplicates": 0,
            "existing_terms_removed": len(terms) - len(custom),
            "custom_terms": len(custom),
            "positive_custom_terms": sum(int(row["詞頻"]) > 0 for row in custom),
            "zero_count_review_terms": sum(int(row["詞頻"]) == 0 for row in custom),
            "reading_overrides": len(used_overrides),
            "output_sha256": sha256(args.output),
            "review_sha256": sha256(args.review),
        }
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, indent=2))
    except (OSError, ValueError, KeyError, TypeError, sqlite3.Error, json.JSONDecodeError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
