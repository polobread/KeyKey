#!/usr/bin/env python3
"""Review collection pronunciation overlap without editing the shipped model."""
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
import argparse
import csv
import json
import math
from pathlib import Path
import sqlite3
import sys

from typing_cost import Engine, query_for_reading, sha256, build_engine

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "DataSource/AISyntheticBigram"
sys.path.insert(0, str(ROOT / "Source/Distributions/Takao/DatabaseCooker"))
from smart_mandarin_model import semantic_sha256


def best_path(query, index, split_only=False):
    """Maximum Unigram-score path; all candidates share the complete reading."""
    size = len(query) // 2
    best = [(-math.inf, []) for _ in range(size + 1)]
    best[0] = (0.0, [])
    for end in range(1, size + 1):
        for start in range(end):
            if split_only and start == 0 and end == size:
                continue
            for word, probability in index.get(query[start * 2:end * 2], []):
                score = best[start][0] + probability
                if score > best[end][0]:
                    best[end] = (score, best[start][1] + [word])
    return best[-1]


def write_tsv(path, rows, fields):
    with path.open("w", encoding="utf-8", newline="") as output:
        writer = csv.DictWriter(output, fields, delimiter="\t", lineterminator="\n", extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def probe(task):
    entry, before, after = task
    results = []
    queries = [query_for_reading(x) for x in entry["reading"].split()]
    for path in (before, after):
        # Fresh process per word/model, no learning or remembered selections.
        with Engine(path) as engine:
            for query in queries:
                state = engine.call("insert", query)
            candidates = engine.call("candidates", 0)
        results.append((state, candidates))
    (old, _), (new, candidates) = results
    return {"before_text": old["text"], "after_text": new["text"],
            "before_segments": "/".join(x["text"] for x in old["segments"]),
            "after_segments": "/".join(x["text"] for x in new["segments"]),
            "default_changed": old["text"] != new["text"],
            "new_word_default": new["text"] == entry["word"],
            "new_word_candidate_rank": next((i + 1 for i, row in enumerate(candidates) if row["text"] == entry["word"]), "")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=8)
    args = parser.parse_args()
    if args.output.exists() or args.work.exists():
        parser.error("output and work directories must be new")
    args.output.mkdir(parents=True)
    args.work.mkdir(parents=True)
    current = ROOT / "Source/Distributions/Takao/CookedDatabase/KeyKey.db"
    source_list = DATA / "collection-unigram.tsv"
    entries = list(csv.DictReader(source_list.open(encoding="utf-8"), delimiter="\t"))
    database_hash = sha256(current)
    before = args.work / "without-collection.db"
    with sqlite3.connect(current.resolve().as_uri() + "?mode=ro", uri=True) as source, sqlite3.connect(before) as target:
        source.backup(target)
        for row in entries:
            query = "".join(query_for_reading(x) for x in row["reading"].split())
            if target.execute("DELETE FROM unigrams WHERE qstring=? AND current=?", (query, row["word"])).rowcount != 1:
                raise ValueError(f"list and DB differ: {row['word']}")
    count_path = ROOT / "DataSource/McBopomofo/phrase.occ"
    mapping_path = ROOT / "DataSource/McBopomofo/BPMFMappings.txt"
    raw_counts, positive_counts = {}, {}
    for line in count_path.read_text().splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].isdigit():
            word, count = parts[0], int(parts[1])
            raw_counts[word] = count
            if count > 0 and len(word) <= 7:
                positive_counts[word] = count
    raw_mappings = defaultdict(set)
    for line in mapping_path.read_text().splitlines():
        parts = line.split()
        if not parts or len(parts) - 1 != len(parts[0]):
            continue
        query = "".join(query_for_reading(x) for x in parts[1:])
        raw_mappings[query].add(parts[0])
    baseline_rows = {}
    with sqlite3.connect(before) as db:
        for query, word, probability in db.execute("SELECT qstring,current,probability FROM unigrams"):
            baseline_rows[(query, word)] = probability
    # Only positive McBopomofo source entries that actually exist in the model
    # participate in the score comparison. Raw mappings are also retained.
    mc_index = defaultdict(list)
    for query, words in raw_mappings.items():
        for word in sorted(words):
            if word in positive_counts and (query, word) in baseline_rows:
                mc_index[query].append((word, baseline_rows[(query, word)]))
    total = json.loads((DATA / "smart-mandarin-model-manifest.json").read_text())["unigram_total_count"]
    all_rows, pairs = [], []
    for entry in entries:
        word, reading = entry["word"], entry["reading"]
        query = "".join(query_for_reading(x) for x in reading.split())
        new_score = math.log10(int(entry["target_count"]) / total)
        exact = sorted(mc_index.get(query, []), key=lambda r: (-r[1], r[0]))
        split_score, split = best_path(query, mc_index, True)
        best_score, best = best_path(query, mc_index)
        raw_same = sorted(raw_mappings.get(query, set()) - {word})
        row = {**entry, "new_log10_probability": round(new_score, 9),
               "mcp_same_text_source_count": raw_counts.get(word, "absent"),
               "mcp_exact_words": "|".join(w for w, _ in exact),
               "mcp_raw_mapping_words": "|".join(raw_same),
               "mcp_best_exact_score": round(exact[0][1], 9) if exact else "",
               "new_minus_best_exact": round(new_score - exact[0][1], 9) if exact else "",
               "mcp_best_split": "/".join(split),
               "new_minus_best_split": round(new_score - split_score, 9) if split else "",
               "mcp_best_path": "/".join(best),
               "new_minus_best_path": round(new_score - best_score, 9) if best else ""}
        all_rows.append(row)
        for competitor, probability in exact:
            pairs.append({"word": word, "reading": reading, "mcp_word": competitor,
                          "mcp_source_count": positive_counts[competitor],
                          "new_log10_probability": new_score, "mcp_log10_probability": probability,
                          "new_minus_mcp": new_score - probability,
                          "new_vs_mcp_ratio": 10 ** (new_score - probability), "category": entry["category"]})
    build_engine()
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for number, (row, result) in enumerate(zip(all_rows, pool.map(probe, [(e, before, current) for e in entries])), 1):
            row.update(result)
            if number % 500 == 0:
                print(f"{number}/{len(entries)} words probed", flush=True)
    exact_rows = [row for row in all_rows if row["mcp_exact_words"]]
    changed = [row for row in all_rows if row["default_changed"]]
    split_risks = [row for row in all_rows if row["mcp_best_split"] and row["new_minus_best_split"] >= 0]
    # Rank actual default changes first, then exact probability ties/outranking.
    exact_rows.sort(key=lambda r: (not r["default_changed"], -r["new_minus_best_exact"], r["word"]))
    changed.sort(key=lambda r: (not bool(r["mcp_exact_words"]), r["word"]))
    split_risks.sort(key=lambda r: (not r["default_changed"], -r["new_minus_best_split"], r["word"]))
    fields = ["word", "reading", "category", "target_count", "source_count", "mcp_same_text_source_count",
              "mcp_exact_words", "mcp_best_exact_score", "new_log10_probability", "new_minus_best_exact",
              "mcp_best_split", "new_minus_best_split", "mcp_best_path", "new_minus_best_path",
              "before_text", "after_text", "before_segments", "after_segments", "default_changed",
              "new_word_default", "new_word_candidate_rank", "mcp_raw_mapping_words", "file", "line", "source_word"]
    write_tsv(args.output / "all-4765.tsv", all_rows, fields)
    write_tsv(args.output / "exact-homophones.tsv", exact_rows, fields)
    write_tsv(args.output / "default-changes.tsv", changed, fields)
    write_tsv(args.output / "split-path-risks.tsv", split_risks, fields)
    write_tsv(args.output / "exact-pairs.tsv", pairs, list(pairs[0]) if pairs else ["word", "mcp_word"])
    summary = {"source_list_sha256": sha256(source_list), "database_sha256": database_hash,
               "without_collection_semantic_sha256": semantic_sha256(before),
               "mcp_counts_sha256": sha256(count_path), "mcp_mappings_sha256": sha256(mapping_path),
               "engine_sha256": sha256(build_engine()), "script_sha256": sha256(Path(__file__)),
               "words": len(all_rows), "exact_homophone_words": len(exact_rows), "exact_pairs": len(pairs),
               "exact_default_changes": sum(r["default_changed"] for r in exact_rows),
               "exact_top_ties_or_outranking": sum(r["new_minus_best_exact"] >= 0 for r in exact_rows),
               "isolated_default_changes": len(changed), "split_score_risks": len(split_risks),
               "method": "Source mappings and positive counts intersected with pre-import DB; scores retain actual reading weights. Fresh desktop engine per word/model, no learning. Isolated default changes are not proof of errors in context."}
    if sha256(current) != database_hash:
        raise ValueError("shipped DB changed during review")
    (args.output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
