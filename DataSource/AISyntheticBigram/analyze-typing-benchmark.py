#!/usr/bin/env python3
"""Analyze the entire cohort before choosing global model experiments."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

from typing_cost import connect, resolve_version, sha256, write_json


def analyze(directory: Path, database: Path, sample_path: Path | None = None,
            trace_path: Path | None = None, output_name: str = "analysis"):
    sample_path = sample_path or directory / "sample.json"
    trace_path = trace_path or directory / "traces-0.json"
    sample = json.loads(sample_path.read_text(encoding="utf-8"))
    trace = json.loads(trace_path.read_text(encoding="utf-8"))
    if trace["database_sha256"] != sha256(database):
        raise ValueError("Analysis database does not match the measured baseline")
    if len(trace["reports"]) != sample["count"]:
        raise ValueError("Incomplete sample; do not analyze a silently reduced cohort")
    actions, classification, edge_stats, lengths = Counter(), Counter(), Counter(), Counter()
    confusions, affected, selected = Counter(), defaultdict(set), Counter()
    ranks, edge_deficits = Counter(), []
    with connect(database) as db:
        for article, report in zip(sample["articles"], trace["reports"]):
            actions.update(report["actions"])
            for error in report["errors"]:
                index = error["index"] - error["offset"]
                confusion = error["before"][index] + " → " + error["target"][index]
                confusions[confusion] += 1
                affected[confusion].add(article["id"])
                candidate = error["candidate"]
                selected[candidate["text"]] += 1
                lengths[candidate["length"]] += 1
                ranks[error["candidate_rank"]] += 1
                rows = db.execute("SELECT current,probability FROM unigrams WHERE qstring=? ORDER BY probability DESC,rowid", (candidate["query"],)).fetchall()
                if candidate["text"] not in [row[0] for row in rows]:
                    classification["external_cin_only"] += 1
                elif rows[0][0] == candidate["text"]:
                    classification["target_is_first_unigram"] += 1
                else:
                    classification["target_is_not_first_unigram"] += 1
                start = candidate["start"]
                previous = next((segment for segment in error["segments_before"]
                                 if segment["start"] + segment["length"] == start), None)
                if start == 0:
                    previous = {"query": "!", "text": ""}
                if not previous:
                    edge_stats["requires_segmentation_change"] += 1
                    continue
                edge = db.execute("SELECT probability FROM bigrams WHERE qstring=? AND previous=? AND current=?",
                                  (previous["query"] + " " + candidate["query"], previous["text"], candidate["text"])).fetchone()
                if not edge:
                    edge_stats["desired_edge_missing"] += 1
                    continue
                edge_stats["desired_edge_exists"] += 1
                backoff = db.execute("SELECT backoff FROM unigrams WHERE qstring=? AND current=?",
                                     (previous["query"], previous["text"])).fetchone()
                if rows and backoff:
                    difference = edge[0] - rows[0][1] - backoff[0]
                    edge_stats["desired_edge_beats_unigram_backoff" if difference > 0 else "desired_edge_loses_to_unigram_backoff"] += 1
                    edge_deficits.append(difference)
    result = {"sample_count": sample["count"], "sample_seed": sample["seed"], "database_sha256": sha256(database),
              "syllables": sum(r["syllables"] for r in trace["reports"]), "actions": dict(actions),
              "total_actions": sum(actions.values()), "corrections": sum(confusions.values()),
              "correction_actions": actions["target_clicks"] + actions["candidate_selections"] + actions["page_turns"],
              "classification": dict(classification), "edge_stats": dict(edge_stats),
              "candidate_lengths": dict(lengths), "candidate_ranks": dict(sorted(ranks.items())),
              "confusions": [{"confusion": text, "count": count, "articles": len(affected[text]),
                               "article_ids": sorted(affected[text])} for text, count in confusions.most_common()],
              "selected_words": dict(selected.most_common()),
              "interpretation": [
                  "Analyze aggregate patterns, never prescribe a per-article edge patch.",
                  "Edge checks use the actual preceding displayed segment at correction time; segmentation changes form a separate category.",
                  "An existing desired edge below unigram+backoff motivates a GLOBAL smoothing-prior experiment; it does not prove that increasing its weight will improve the final path.",
                  "Test a small prespecified grid of prior strengths on the whole cohort. Recompute context backoffs coherently; keep vocabulary, readings, unigram probabilities and bigram identities fixed.",
                  "Use this random cohort only for diagnosis. Run the selected global rule on the fixed 130-article validation set and report every improved, unchanged and regressed article.",
                  "Do not repair regressions with article-specific exceptions."]}
    write_json(directory / f"{output_name}.json", result)
    lines = [f"# {sample['count']} 篇整體錯誤分析", "", f"固定抽樣種子 {sample['seed']}；完整測量 {sample['count']} 篇、{result['syllables']:,} 音節。", "",
             f"原版總動作 {result['total_actions']:,}；{result['corrections']:,} 次選字修正，共 {result['correction_actions']:,} 個修正動作。", "",
             "## 跨文章的共同錯誤", "", "| 畫面 → 原文 | 次數 | 涉及篇數 |", "| --- | ---: | ---: |"]
    for row in result["confusions"][:20]:
        lines.append(f"| {row['confusion']} | {row['count']} | {row['articles']} |")
    lines += ["", "## 模型診斷", "",
              f"- {classification['target_is_not_first_unigram']} 次的目標不是該讀音的 unigram 首選；{classification['target_is_first_unigram']} 次目標本來是首選；{classification['external_cin_only']} 次只存在於 CIN 備援字表。",
              f"- {edge_stats['desired_edge_exists']} 次能在實際前詞上下文找到正確 bigram，其中 {edge_stats['desired_edge_loses_to_unigram_backoff']} 次仍輸給 unigram 加 backoff。",
              f"- {edge_stats['desired_edge_missing']} 次沒有該上下文的正確 bigram；{edge_stats['requires_segmentation_change']} 次需要改變詞段切分，無法直接對照同一條邊。",
              "- 在／再等雙向錯誤，以及只集中少數文章的人名，不能靠全面提高某一個字的基本詞頻處理。",
              "", "## 使用方式", "",
              "這份隨機樣本只用來找跨文章的共同原因，不產生逐篇、逐字或逐詞例外。先依完整分布訂一條全域規則，再以固定 130 篇 v5 seed 驗證，並分開報告基本字、一般字及每篇退步。"]
    (directory / f"{output_name}.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--version", default="current")
    parser.add_argument("--sample", type=Path)
    parser.add_argument("--trace", type=Path)
    parser.add_argument("--output-name", default="analysis")
    args = parser.parse_args()
    result = analyze(args.directory, resolve_version(args.version), args.sample, args.trace, args.output_name)
    print(json.dumps({key: result[key] for key in ("total_actions", "corrections", "classification", "edge_stats")}, ensure_ascii=False, indent=2))
