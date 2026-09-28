#!/usr/bin/env python3
"""Audit common one-character words in paired typing benchmark results."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

from typing_batch import load_population
from typing_cost import connect, query_for_reading, sha256, write_json


ROOT = Path(__file__).resolve().parent


def load_words(path):
    rows = []
    seen = set()
    for number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        columns = line.split("\t")
        if len(columns) != 3 or len(columns[0]) != 1:
            raise ValueError(f"{path}:{number}: expected one character, reading, and group")
        character, reading, group = columns
        if character in seen:
            raise ValueError(f"{path}:{number}: duplicate character {character!r}")
        query_for_reading(reading)
        seen.add(character)
        rows.append({"character": character, "reading": reading, "group": group})
    if not rows:
        raise ValueError(f"{path}: empty word list")
    return rows


def unigram_ranks(database, words):
    result = {}
    with connect(database) as db:
        for word in words:
            query = query_for_reading(word["reading"])
            candidates = db.execute(
                "SELECT current, probability FROM unigrams WHERE qstring=? "
                "ORDER BY probability DESC, rowid", (query,)).fetchall()
            matches = [(index + 1, probability) for index, (text, probability) in enumerate(candidates)
                       if text == word["character"]]
            if len(matches) != 1:
                raise ValueError(
                    f"{database}: {word['character']} {word['reading']} has {len(matches)} exact unigram rows")
            rank, probability = matches[0]
            result[word["character"]] = {
                "rank": rank, "probability": probability, "candidates": len(candidates),
            }
    return result


def correction_counts(payload, model, selected):
    changes = Counter()
    events = Counter()
    articles = defaultdict(set)
    sources = defaultdict(Counter)
    for article in payload["articles"]:
        summary = article["results"][model].get("correction_summary", [])
        for row in summary:
            targets_in_event = set()
            for change in row["changes"]:
                target = change["to"]
                if target not in selected:
                    continue
                changes[target] += row["events"]
                sources[target][change["from"]] += row["events"]
                articles[target].add(article["id"])
                targets_in_event.add(target)
            for target in targets_in_event:
                events[target] += row["events"]
    return {character: {
        "changes": changes[character],
        "events": events[character],
        "articles": len(articles[character]),
        "sources": [{"from": source, "changes": count}
                    for source, count in sources[character].most_common()],
    } for character in selected}


def occurrence_counts(payload, article_text, selected):
    counts = Counter()
    for article in payload["articles"]:
        counts.update(character for character in article_text[article["id"]] if character in selected)
    return dict(counts)


def build_report(words, control_db, candidate_db, comparisons, control_name, candidate_name):
    selected = {row["character"] for row in words}
    population, _ = load_population()
    article_text = {row["prompt_id"]: row["text"] for row in population}
    ranks = {
        control_name: unigram_ranks(control_db, words),
        candidate_name: unigram_ranks(candidate_db, words),
    }
    cohorts = []
    for path in comparisons:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if control_name not in payload["versions"] or candidate_name not in payload["versions"]:
            raise ValueError(f"{path}: missing {control_name!r} or {candidate_name!r}")
        cohorts.append({
            "name": payload["sample"].get("cohort", path.stem),
            "comparison_file": str(path),
            "comparison_sha256": sha256(path),
            "articles": len(payload["articles"]),
            "occurrences": occurrence_counts(payload, article_text, selected),
            "corrections": {
                control_name: correction_counts(payload, control_name, selected),
                candidate_name: correction_counts(payload, candidate_name, selected),
            },
        })
    entries = []
    for word in words:
        character = word["character"]
        entries.append({
            **word,
            "unigrams": {name: ranks[name][character] for name in ranks},
            "cohorts": [{
                "name": cohort["name"],
                "occurrences": cohort["occurrences"].get(character, 0),
                control_name: cohort["corrections"][control_name][character],
                candidate_name: cohort["corrections"][candidate_name][character],
            } for cohort in cohorts],
        })
    return {
        "purpose": "ChatGPT-curated common one-character word audit; diagnostic only, never a per-word tuning rule",
        "models": {
            control_name: {"database": str(control_db), "sha256": sha256(control_db)},
            candidate_name: {"database": str(candidate_db), "sha256": sha256(candidate_db)},
        },
        "cohorts": [{key: value for key, value in cohort.items()
                     if key not in ("occurrences", "corrections")} for cohort in cohorts],
        "entries": entries,
    }


def write_markdown(path, report, control_name, candidate_name):
    lines = [
        "# 常用中文單字診斷", "",
        "這是由 ChatGPT 依臺灣書面與對話用法整理的單字稽核層，只用來找全域模型問題；",
        "不會依個別字直接改詞頻。修正數以正確目標字逐字計算，詞組選字的動作成本仍只計一次。", "",
        f"比較模型：`{control_name}` 與 `{candidate_name}`。", "",
    ]
    cohort_names = [row["name"] for row in report["cohorts"]]
    header = ["字", "讀音", "類別", "小麥順位", "v2 順位"]
    for cohort in cohort_names:
        header.extend([f"{cohort} 出現", f"{cohort} 小麥→v2 修正字次"])
    lines += ["| " + " | ".join(header) + " |",
              "| " + " | ".join(["---", "---", "---"] + ["---:"] * (len(header) - 3)) + " |"]
    totals = {name: {"occurrences": 0, control_name: 0, candidate_name: 0} for name in cohort_names}
    for row in report["entries"]:
        cells = [row["character"], row["reading"], row["group"],
                 str(row["unigrams"][control_name]["rank"]), str(row["unigrams"][candidate_name]["rank"])]
        for cohort in row["cohorts"]:
            before = cohort[control_name]["changes"]
            after = cohort[candidate_name]["changes"]
            cells.extend([str(cohort["occurrences"]), f"{before}→{after}"])
            totals[cohort["name"]]["occurrences"] += cohort["occurrences"]
            totals[cohort["name"]][control_name] += before
            totals[cohort["name"]][candidate_name] += after
        lines.append("| " + " | ".join(cells) + " |")
    lines += ["", "## 合計", ""]
    for name in cohort_names:
        total = totals[name]
        delta = total[candidate_name] - total[control_name]
        lines.append(f"- `{name}`：清單中字共出現 {total['occurrences']:,} 次；修正字次 "
                     f"{total[control_name]:,}→{total[candidate_name]:,}（{delta:+,}）。")
        rows = [next(cohort for cohort in entry["cohorts"] if cohort["name"] == name)
                for entry in report["entries"]]
        active = [row for row in rows
                  if row[control_name]["changes"] or row[candidate_name]["changes"]]
        deltas = [row[candidate_name]["changes"] - row[control_name]["changes"] for row in active]
        groups = {}
        for entry, row in zip(report["entries"], rows):
            before, after = groups.setdefault(entry["group"], [0, 0])
            groups[entry["group"]] = [before + row[control_name]["changes"],
                                      after + row[candidate_name]["changes"]]
        lines.append(f"  - 實際發生修正的 {len(active)} 字中：{sum(delta < 0 for delta in deltas)} 字改善、"
                     f"{sum(delta == 0 for delta in deltas)} 字相同、{sum(delta > 0 for delta in deltas)} 字退步。")
        lines.append(f"  - 九個類別中有 {sum(after <= before for before, after in groups.values())} 類不退步、"
                     f"{sum(after > before for before, after in groups.values())} 類退步。")
    lines += ["", "目前 v2 的總修正字次下降，但改善集中在少數字；依基本字分布指標不通過模型驗收。"]
    lines += ["", "候選順位只檢查該字的指定慣用讀音。多音字的其他用法需由文章固定讀音另行判斷。", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="分析常用單字的 unigram 順位與實際逐字修正次數。")
    parser.add_argument("--control-db", type=Path, required=True)
    parser.add_argument("--candidate-db", type=Path, required=True)
    parser.add_argument("--comparison", type=Path, action="append", required=True)
    parser.add_argument("--control-name", default="mc-bopomofo-control")
    parser.add_argument("--candidate-name", default="iterative-v2")
    parser.add_argument("--words", type=Path, default=ROOT / "common-single-character-words.tsv")
    parser.add_argument("--output", type=Path, default=ROOT / "common-single-character-analysis-v2.json")
    args = parser.parse_args()
    report = build_report(load_words(args.words), args.control_db, args.candidate_db, args.comparison,
                          args.control_name, args.candidate_name)
    write_json(args.output, report)
    write_markdown(args.output.with_suffix(".md"), report, args.control_name, args.candidate_name)
    print(args.output)


if __name__ == "__main__":
    main()
