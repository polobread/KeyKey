#!/usr/bin/env python3
"""Enforce ranked basic-character priority within each single-character reading group."""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path
import shutil
import sqlite3

from typing_cost import ROOT, query_for_reading, sha256, write_json


RANKED = ROOT / "common-single-character-pronunciations-1500.tsv"
PROTECTED = ROOT / "common-single-character-words.tsv"


def load_ranks(path=RANKED):
    ranks = {}
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line_number == 1:
            continue
        fields = raw.split("\t")
        if len(fields) < 3 or not fields[0].isdigit() or len(fields[1]) != 1:
            raise ValueError(f"{path}:{line_number}: invalid ranked-character row")
        reading = fields[2]
        if reading.startswith("˙"):
            reading = reading[1:] + "˙"
        ranks[fields[1]] = {"rank": int(fields[0]), "query": query_for_reading(reading)}
    if sorted(row["rank"] for row in ranks.values()) != list(range(1, 1501)):
        raise ValueError(f"{path}: expected ranks 1–1,500 exactly once")
    return ranks


def load_protected_characters(path=PROTECTED):
    result = set()
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw or raw.startswith("#"):
            continue
        fields = raw.split("\t")
        if len(fields) < 2 or len(fields[0]) != 1:
            raise ValueError(f"{path}:{line_number}: invalid protected-character row")
        result.add(fields[0])
    if not result:
        raise ValueError(f"{path}: no protected characters")
    return result


def calibrated_assignments(rows, ranks, rank_limit=100, minimum_source_probability=-4.0,
                           protected_characters=frozenset()):
    """Return rowid/probability changes while preserving each query's probability multiset."""
    groups = defaultdict(list)
    for rowid, query, current, probability in rows:
        if len(current) == 1:
            groups[query].append((rowid, current, probability))
    updates, group_reports = [], []
    for query, candidates in groups.items():
        basics = [row for row in candidates
                  if ranks.get(row[1], {}).get("rank", 1501) <= rank_limit
                  and ranks[row[1]]["query"] == query
                  and row[2] >= minimum_source_probability]
        if not basics or len(candidates) < 2:
            continue
        competitors = [row for row in candidates if row not in basics]
        if any(row[1] in protected_characters for row in competitors):
            continue
        desired = sorted(basics, key=lambda row: (ranks[row[1]]["rank"], row[0]))
        desired += sorted(competitors, key=lambda row: (-row[2], row[0]))
        probabilities = sorted((row[2] for row in candidates), reverse=True)
        changes = []
        for row, probability in zip(desired, probabilities):
            if row[2] != probability:
                updates.append((probability, row[0]))
                changes.append({
                    "character": row[1], "rank": ranks.get(row[1], {}).get("rank"),
                    "before": row[2], "after": probability,
                })
        if changes:
            group_reports.append({"query": query, "candidates": len(candidates), "changes": changes})
    return updates, group_reports


def build(source, output, ranked_path=RANKED, rank_limit=100, minimum_source_probability=-4.0,
          protected_path=PROTECTED):
    if output.exists() or output.with_suffix(".report.json").exists():
        raise ValueError("Refuse to overwrite an existing ranked-unigram calibration")
    if source.resolve() == output.resolve():
        raise ValueError("Source and output databases must differ")
    ranks = load_ranks(ranked_path)
    protected_characters = load_protected_characters(protected_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, output)
    try:
        with sqlite3.connect(output) as db:
            rows = db.execute("SELECT rowid,qstring,current,probability FROM unigrams").fetchall()
            habitual_probabilities = {(current, query): probability
                                      for _, query, current, probability in rows if len(current) == 1}
            updates, groups = calibrated_assignments(
                rows, ranks, rank_limit, minimum_source_probability, protected_characters)
            db.executemany("UPDATE unigrams SET probability=? WHERE rowid=?", updates)
            integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
            if integrity != "ok":
                raise ValueError(f"calibrated database integrity check failed: {integrity}")
    except Exception:
        output.unlink(missing_ok=True)
        raise
    ranked_audit = []
    for character, info in sorted(ranks.items(), key=lambda item: item[1]["rank"]):
        if info["rank"] > rank_limit:
            break
        probability = habitual_probabilities.get((character, info["query"]))
        ranked_audit.append({
            "character": character, "rank": info["rank"], "query": info["query"],
            "source_probability": probability,
            "eligible": probability is not None and probability >= minimum_source_probability,
        })
    report = {
        "method": (
            "Within every Bopomofo query containing a ranked top-character that also clears the fixed "
            "source-probability floor, assign the existing single-character probability values in rank "
            "order: eligible ranked 1–limit characters first, then all other characters in their previous "
            "probability order. Skip a query if this would demote an independently curated core character. "
            "The probability multiset for each query is preserved; multi-character entries, backoff values, "
            "and bigrams are unchanged."
        ),
        "rank_limit": rank_limit,
        "minimum_source_probability": minimum_source_probability,
        "source": {"file": str(source), "sha256": sha256(source)},
        "ranked_characters": {"file": str(ranked_path), "sha256": sha256(ranked_path)},
        "protected_characters": {
            "file": str(protected_path), "sha256": sha256(protected_path),
            "count": len(protected_characters),
        },
        "changed_query_groups": len(groups),
        "changed_rows": len(updates),
        "ranked_character_audit": ranked_audit,
        "ineligible_ranked_characters": [row for row in ranked_audit if not row["eligible"]],
        "groups": groups,
        "output": {"file": str(output), "sha256": sha256(output)},
        "scope": (
            "The rule uses only the independently supplied 1,500-character rank and database reading "
            "groups at each character's supplied habitual reading. A ranked character must also clear "
            "the fixed source-model probability floor, which prevents rare orthographic variants from "
            "being promoted solely because the supplied list ranks them too highly. A query group is skipped "
            "if calibration would demote any independently curated core character. The rule does not read "
            "evaluation text, article IDs, correction traces, or error pairs."
        ),
    }
    write_json(output.with_suffix(".report.json"), report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--ranked", type=Path, default=RANKED)
    parser.add_argument("--protected", type=Path, default=PROTECTED)
    parser.add_argument("--rank-limit", type=int, default=100)
    parser.add_argument("--minimum-source-probability", type=float, default=-4.0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if not 1 <= args.rank_limit <= 1500:
            raise ValueError("rank-limit must be between 1 and 1,500")
        report = build(args.source, args.output, args.ranked, args.rank_limit,
                       args.minimum_source_probability, args.protected)
        print(json.dumps({key: report[key] for key in (
            "rank_limit", "minimum_source_probability", "changed_query_groups", "changed_rows", "output")},
            ensure_ascii=False, indent=2))
    except (ValueError, OSError, sqlite3.Error, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
