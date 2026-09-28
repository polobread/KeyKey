#!/usr/bin/env python3
"""Diagnose individual basic characters that appear behind less-common homophones."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

from typing_cost import ROOT, connect, sha256, write_json


RANKED = ROOT / "common-single-character-pronunciations-1500.tsv"


def load_ranks(path=RANKED):
    result = {}
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line_number == 1:
            continue
        fields = raw.split("\t")
        if len(fields) < 3 or not fields[0].isdigit() or len(fields[1]) != 1:
            raise ValueError(f"{path}:{line_number}: invalid ranked-character row")
        result[fields[1]] = {"rank": int(fields[0]), "reading": fields[2]}
    if len(result) != 1500:
        raise ValueError(f"{path}: expected 1,500 unique characters")
    return result


def context_text(error, radius=8):
    index = error["index"] - error["offset"]
    start, end = max(0, index - radius), min(len(error["target"]), index + radius + 1)
    text = error["target"][start:end]
    local = index - start
    return text[:local] + "【" + text[local:local + 1] + "】" + text[local + 1:]


def unigram_order(db, query, target, wrong):
    rows = db.execute(
        "SELECT current,probability FROM unigrams WHERE qstring=? ORDER BY probability DESC,rowid", (query,)
    ).fetchall()
    positions = {}
    probabilities = {}
    for index, row in enumerate(rows, 1):
        positions.setdefault(row[0], index)
        probabilities.setdefault(row[0], row[1])
    return {
        "target_rank": positions.get(target), "wrong_rank": positions.get(wrong),
        "target_probability": probabilities.get(target), "wrong_probability": probabilities.get(wrong),
        "target_behind_wrong": (
            positions.get(target) is not None and positions.get(wrong) is not None
            and positions[target] > positions[wrong]
        ),
    }


def previous_segment(error):
    candidate = error["candidate"]
    start = candidate["start"]
    previous = next((segment for segment in error["segments_before"]
                     if segment["start"] + segment["length"] == start), None)
    if start == 0:
        previous = {"query": "!", "text": ""}
    return previous


def bigram_diagnosis(db, error, target):
    candidate = error["candidate"]
    previous = previous_segment(error)
    if not previous:
        return "segmentation_change"
    edge = db.execute(
        "SELECT probability FROM bigrams WHERE qstring=? AND previous=? AND current=?",
        (previous["query"] + " " + candidate["query"], previous["text"], target),
    ).fetchone()
    if not edge:
        return "desired_edge_missing"
    top = db.execute(
        "SELECT probability FROM unigrams WHERE qstring=? ORDER BY probability DESC,rowid LIMIT 1",
        (candidate["query"],),
    ).fetchone()
    backoff = db.execute(
        "SELECT backoff FROM unigrams WHERE qstring=? AND current=?",
        (previous["query"], previous["text"]),
    ).fetchone()
    if top and backoff and edge[0] <= top[0] + backoff[0]:
        return "desired_edge_weak"
    return "desired_edge_strong"


def analyze_cohort(label, sample_path, trace_path, database, ranks, rank_limit=100):
    sample = json.loads(sample_path.read_text(encoding="utf-8"))
    trace = json.loads(trace_path.read_text(encoding="utf-8"))
    if trace.get("database_sha256") != sha256(database):
        raise ValueError(f"{label}: trace/database hash mismatch")
    if len(trace.get("reports", [])) != sample.get("count") or len(sample.get("articles", [])) != sample.get("count"):
        raise ValueError(f"{label}: incomplete sample or trace")
    stats = defaultdict(lambda: {
        "corrections": 0, "actions_involved": 0, "page_turns": 0,
        "candidate_rank_total": 0, "candidate_rank_max": 0,
        "rarer_wrong_character_events": 0, "unigram_behind_wrong_events": 0,
        "rarer_wrong_and_unigram_behind_events": 0,
        "multi_character_candidate_events": 0, "articles": set(),
        "wrong_characters": Counter(), "bigram": Counter(),
        "direct_wrong_characters": Counter(), "direct_bigram": Counter(),
        "direct_missing_edges": Counter(), "examples": [],
    })
    with connect(database) as db:
        for descriptor, report in zip(sample["articles"], trace["reports"]):
            for error in report.get("errors", []):
                for change in error.get("changes", []):
                    target, wrong = change["to"], change["from"]
                    target_info = ranks.get(target)
                    if not target_info or target_info["rank"] > rank_limit:
                        continue
                    row = stats[target]
                    row["corrections"] += 1
                    row["actions_involved"] += error["action_count"]
                    row["page_turns"] += error["actions"]["page_turns"]
                    row["candidate_rank_total"] += error["candidate_rank"]
                    row["candidate_rank_max"] = max(row["candidate_rank_max"], error["candidate_rank"])
                    row["articles"].add(descriptor["id"])
                    row["wrong_characters"][wrong] += 1
                    wrong_rank = ranks.get(wrong, {}).get("rank")
                    wrong_is_rarer = wrong_rank is None or target_info["rank"] < wrong_rank
                    if wrong_is_rarer:
                        row["rarer_wrong_character_events"] += 1
                    order = None
                    bigram = "multi_character_candidate"
                    direct_order_failure = False
                    candidate = error["candidate"]
                    if candidate["length"] == 1 and candidate["text"] == target:
                        order = unigram_order(db, candidate["query"], target, wrong)
                        if order["target_behind_wrong"]:
                            row["unigram_behind_wrong_events"] += 1
                            if wrong_is_rarer:
                                row["rarer_wrong_and_unigram_behind_events"] += 1
                                direct_order_failure = True
                        bigram = bigram_diagnosis(db, error, target)
                    else:
                        row["multi_character_candidate_events"] += 1
                    row["bigram"][bigram] += 1
                    if direct_order_failure:
                        row["direct_wrong_characters"][wrong] += 1
                        row["direct_bigram"][bigram] += 1
                        if bigram == "desired_edge_missing":
                            previous = previous_segment(error)
                            if previous is not None:
                                previous_text = previous["text"] or "BOS"
                                row["direct_missing_edges"][(previous_text, target)] += 1
                    if len(row["examples"]) < 4:
                        row["examples"].append({
                            "article": descriptor["id"], "source": descriptor.get("source_version"),
                            "wrong": wrong, "wrong_rank": wrong_rank, "context": context_text(error),
                            "candidate_rank": error["candidate_rank"], "page_turns": error["actions"]["page_turns"],
                            "unigram": order, "bigram": bigram,
                        })
    characters = []
    for character, row in stats.items():
        corrections = row["corrections"]
        characters.append({
            "character": character, "rank": ranks[character]["rank"], "reading": ranks[character]["reading"],
            "corrections": corrections, "articles": len(row["articles"]),
            "actions_involved": row["actions_involved"], "page_turns": row["page_turns"],
            "average_candidate_rank": row["candidate_rank_total"] / corrections,
            "maximum_candidate_rank": row["candidate_rank_max"],
            "rarer_wrong_character_events": row["rarer_wrong_character_events"],
            "unigram_behind_wrong_events": row["unigram_behind_wrong_events"],
            "rarer_wrong_and_unigram_behind_events": row["rarer_wrong_and_unigram_behind_events"],
            "rarer_wrong_without_unigram_behind_events": (
                row["rarer_wrong_character_events"] - row["rarer_wrong_and_unigram_behind_events"]),
            "multi_character_candidate_events": row["multi_character_candidate_events"],
            "wrong_characters": [{"character": wrong, "rank": ranks.get(wrong, {}).get("rank"), "count": count}
                                 for wrong, count in row["wrong_characters"].most_common()],
            "direct_wrong_characters": [
                {"character": wrong, "rank": ranks.get(wrong, {}).get("rank"), "count": count}
                for wrong, count in row["direct_wrong_characters"].most_common()],
            "direct_bigram": dict(sorted(row["direct_bigram"].items())),
            "direct_missing_edges": [
                {"previous": previous, "target": target, "count": count}
                for (previous, target), count in row["direct_missing_edges"].most_common()],
            "bigram": dict(sorted(row["bigram"].items())), "examples": row["examples"],
        })
    characters.sort(key=lambda row: (-row["rarer_wrong_character_events"], -row["corrections"], row["rank"]))
    return {
        "label": label, "sample": str(sample_path), "sample_sha256": sha256(sample_path),
        "trace": str(trace_path), "trace_sha256": sha256(trace_path),
        "database": str(database), "database_sha256": sha256(database),
        "articles": sample["count"], "active_basic_characters": len(characters),
        "basic_character_corrections": sum(row["corrections"] for row in characters),
        "rarer_wrong_character_events": sum(row["rarer_wrong_character_events"] for row in characters),
        "unigram_behind_wrong_events": sum(row["unigram_behind_wrong_events"] for row in characters),
        "rarer_wrong_and_unigram_behind_events": sum(
            row["rarer_wrong_and_unigram_behind_events"] for row in characters),
        "characters": characters,
    }


def write_markdown(path, result):
    lines = ["# 常見字候選順位診斷", "",
             "只分析排名前 100 的目標字。`較少見錯字` 表示畫面先出的字排名較後或不在 1,500 字清單；"
             "`unigram 在後` 只計單字候選且模型內正確字順位低於錯字。"
             "`兩者交集` 才是「常見目標字被較少見同音字壓在後面」的直接證據。", "",
             "bigram 診斷依當時畫面的斷詞與實際修正候選計算；單字邊缺少不代表等價的多字詞一定不在模型中。", ""]
    for cohort in result["cohorts"]:
        lines += [f"## {cohort['label']}", "",
                  (f"{cohort['articles']} 篇；{cohort['active_basic_characters']} 個基本字發生 "
                   f"{cohort['basic_character_corrections']} 字次修正，其中 "
                   f"{cohort['rarer_wrong_character_events']} 次先出現較少見字，"
                   f"{cohort['unigram_behind_wrong_events']} 次可直接確認 unigram 排序在後；"
                   f"其中 {cohort['rarer_wrong_and_unigram_behind_events']} 次兩者同時成立。"), "",
                  "### 常見字在較少見字後面的直接證據", ""]
        direct_rows = [row for row in cohort["characters"]
                       if row["rarer_wrong_and_unigram_behind_events"]]
        direct_rows.sort(key=lambda row: (-row["rarer_wrong_and_unigram_behind_events"], row["rank"]))
        if direct_rows:
            lines += ["| 目標字 | 直接錯字／bigram 診斷 | 直接證據字次 | 較少見字先出但非 unigram 在後 |",
                      "| --- | --- | ---: | ---: |"]
            for row in direct_rows[:12]:
                wrong = "、".join(
                    f"{item['character']}({item['rank'] or '未列'}):{item['count']}"
                    for item in row["direct_wrong_characters"][:2])
                diagnosis = "、".join(
                    f"{name}:{count}" for name, count in row["direct_bigram"].items())
                missing = "、".join(
                    f"{item['previous']}→{item['target']}:{item['count']}"
                    for item in row["direct_missing_edges"][:3])
                detail = f"{wrong}<br>{diagnosis}"
                if missing:
                    detail += f"<br>缺少邊：{missing}"
                lines.append(
                    f"| {row['character']} | {detail} | "
                    f"{row['rarer_wrong_and_unigram_behind_events']} | "
                    f"{row['rarer_wrong_without_unigram_behind_events']} |")
        else:
            lines.append("本組沒有這類直接證據。")
        lines += ["", "### 完整基本字診斷", "",
                  "| 目標字 | 排名 | 修正字次／篇數 | 主要先出字 | 較少見錯字 | unigram 在後 | 兩者交集 | 候選平均／最遠 | bigram 診斷 |",
                  "| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- |"]
        for row in cohort["characters"]:
            wrong = "、".join(
                f"{item['character']}({item['rank'] or '未列'}):{item['count']}"
                for item in row["wrong_characters"][:3])
            bigram = "、".join(f"{name}:{count}" for name, count in row["bigram"].items())
            lines.append(
                f"| {row['character']} | {row['rank']} | {row['corrections']}／{row['articles']} | {wrong} | "
                f"{row['rarer_wrong_character_events']} | {row['unigram_behind_wrong_events']} | "
                f"{row['rarer_wrong_and_unigram_behind_events']} | "
                f"{row['average_candidate_rank']:.2f}／{row['maximum_candidate_rank']} | {bigram} |")
        lines += ["", "### 較少見字先出的例子", ""]
        examples = [(row, example) for row in cohort["characters"] for example in row["examples"]
                    if example["wrong_rank"] is None or row["rank"] < example["wrong_rank"]]
        for row, example in examples[:30]:
            lines.append(
                f"- `{row['character']}`（排名 {row['rank']}）：`{example['wrong']}`"
                f"（{example['wrong_rank'] or '未列'}）先出；{example['context']}；"
                f"候選第 {example['candidate_rank']}；{example['bigram']}。")
        lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cohort", nargs=4, action="append", required=True,
                        metavar=("LABEL", "SAMPLE", "TRACE", "DATABASE"))
    parser.add_argument("--rank-limit", type=int, default=100)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        ranks = load_ranks()
        cohorts = [analyze_cohort(label, Path(sample), Path(trace), Path(database), ranks, args.rank_limit)
                   for label, sample, trace, database in args.cohort]
        result = {
            "scope": f"independent per-event diagnosis for ranked target characters 1–{args.rank_limit}",
            "ranked_characters": {"file": str(RANKED), "sha256": sha256(RANKED)},
            "interpretation": (
                "Individual examples identify shared failure modes. They are not a word-specific patch list; "
                "any model change must still use a prespecified class or corpus rule and pass full-cohort gates. "
                "The bigram diagnosis follows the displayed segmentation and the actual correction candidate; "
                "a missing single-character edge does not prove that an equivalent multi-character token is absent."),
            "cohorts": cohorts,
        }
        write_json(args.output, result)
        write_markdown(args.output.with_suffix(".md"), result)
        print(json.dumps({row["label"]: {
            "basic_character_corrections": row["basic_character_corrections"],
            "rarer_wrong_character_events": row["rarer_wrong_character_events"],
            "unigram_behind_wrong_events": row["unigram_behind_wrong_events"],
        } for row in cohorts}, ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
