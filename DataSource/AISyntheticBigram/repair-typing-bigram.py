#!/usr/bin/env python3
"""Tune an isolated bigram DB; accept only measured, non-regressing changes."""
from __future__ import annotations

import argparse
import math
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

from typing_cost import (Lexicon, add_arguments, connect, evaluate, load_document,
                         policy_from, resolve_version, sha256, writable_db, write_json)


def proposals(document: list[dict], report: dict, lexicon: Lexicon) -> list[tuple[str, str, str]]:
    """Only adjacent dictionary words around an observed correction, with BOS/EOS."""
    result = {}
    for error in sorted(report["errors"], key=lambda item: -sum(item["actions"].values())):
        block = document[error["block"]]
        offset, end = error["offset"], error["entered"]
        queries = block["queries"][offset:end]
        target = error["target"]
        selected = error["candidate"]
        first, last = selected["start"], selected["start"] + selected["length"]
        # Include both the reference segmentation and the actual selectable word.
        paths = [lexicon.segment(target, queries)]
        left = lexicon.segment(target[:first], queries[:first])
        right = lexicon.segment(target[last:], queries[last:])
        right = [{**token, "start": token["start"] + last} for token in right]
        paths.append([*left, selected, *right])
        for tokens in paths:
            bounded = [{"start": 0, "length": 0, "query": "!", "text": ""}, *tokens,
                       {"start": len(target), "length": 0, "query": "$", "text": ""}]
            for previous, current in zip(bounded, bounded[1:]):
                pair_start = previous["start"]
                pair_end = current["start"] + current["length"]
                if pair_start < last and pair_end > first:
                    key = (previous["query"] + " " + current["query"], previous["text"], current["text"])
                    result[key] = None
    return list(result)


def baseline_score(db: sqlite3.Connection, key: tuple[str, str, str]) -> tuple[list[tuple], float]:
    query, previous, current = key
    previous_query, current_query = query.split(" ")
    rows = db.execute("SELECT rowid,probability FROM bigrams WHERE qstring=? AND previous=? AND current=?", key).fetchall()
    prior = db.execute("SELECT backoff FROM unigrams WHERE qstring=? AND current=?", (previous_query, previous)).fetchone()
    unigram = db.execute("SELECT probability FROM unigrams WHERE qstring=? AND current=?", (current_query, current)).fetchone()
    if not prior or not unigram:
        raise ValueError(f"Repair refers to a word absent from the model: {key}")
    score = max([prior[0] + unigram[0], *(row[1] for row in rows)])
    # A proposed word must also compete with existing homophones for this edge.
    competitor = db.execute("SELECT MAX(probability) FROM bigrams WHERE qstring=? AND previous=?", (query, previous)).fetchone()[0]
    return rows, max(score, competitor if competitor is not None else score)


def set_score(db: sqlite3.Connection, key: tuple[str, str, str], value: float):
    cursor = db.execute("UPDATE bigrams SET probability=? WHERE qstring=? AND previous=? AND current=?", (value, *key))
    if not cursor.rowcount:
        db.execute("INSERT INTO bigrams(qstring,previous,current,probability) VALUES(?,?,?,?)", (*key, value))
    db.commit()


def restore_score(db: sqlite3.Connection, key: tuple[str, str, str], rows: list[tuple]):
    if rows:
        db.executemany("UPDATE bigrams SET probability=? WHERE rowid=?", [(value, rowid) for rowid, value in rows])
    else:
        db.execute("DELETE FROM bigrams WHERE qstring=? AND previous=? AND current=?", key)
    db.commit()


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def write_patch(path: Path, accepted: list[dict], base_hash: str):
    lines = ["-- Apply only to a copy of the recorded base database.", f"-- Base SHA-256: {base_hash}", "BEGIN;"]
    for item in accepted:
        query, previous, current = map(sql_literal, item["key"])
        score = repr(item["probability"])
        condition = f"qstring={query} AND previous={previous} AND current={current}"
        lines += [f"UPDATE bigrams SET probability={score} WHERE {condition};",
                  "INSERT INTO bigrams(qstring,previous,current,probability) "
                  f"SELECT {query},{previous},{current},{score} WHERE NOT EXISTS (SELECT 1 FROM bigrams WHERE {condition});"]
    lines += ["COMMIT;", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


def tune(document: list[dict], guard_documents: list[list[dict]], source: Path, destination: Path,
         lexicon: Lexicon, policy, max_trials: int, passes: int) -> dict:
    with connect(source) as original, writable_db(destination) as copy:
        original.backup(copy)
    baseline = evaluate(document, destination, policy)
    guards = [evaluate(doc, destination, policy)["total_actions"] for doc in guard_documents]
    current, guard_scores = baseline, guards[:]
    accepted, trials = [], 0
    with writable_db(destination) as db:
        for pass_index in range(passes):
            changed = False
            for key in proposals(document, current, lexicon):
                try:
                    rows, floor = baseline_score(db, key)
                except ValueError:
                    # A historical/custom model may lack a reference-dictionary
                    # phrase. Bigram repair must not invent an absent unigram.
                    continue
                for increase in (0.25, 0.5, 1.0, 2.0, 4.0):
                    if trials >= max_trials:
                        break
                    value = min(-0.000001, floor + increase)
                    if not math.isfinite(value) or (rows and value <= max(row[1] for row in rows)):
                        break
                    trials += 1
                    set_score(db, key, value)
                    try:
                        measured = evaluate(document, destination, policy)
                        measured_guards = []
                        if measured["total_actions"] < current["total_actions"]:
                            measured_guards = [evaluate(doc, destination, policy)["total_actions"] for doc in guard_documents]
                        keep = (measured["total_actions"] < current["total_actions"] and
                                all(after <= before for after, before in zip(measured_guards, guard_scores)))
                    except ValueError:
                        keep = False
                    if keep:
                        accepted.append({"key": key, "probability": value, "previous_rows": rows,
                                         "before": current["total_actions"], "after": measured["total_actions"],
                                         "guard_before": guard_scores, "guard_after": measured_guards})
                        print(f"Accepted {previous_label(key)}: {current['total_actions']} → {measured['total_actions']}", file=sys.stderr)
                        current, guard_scores = measured, measured_guards
                        changed = True
                        break
                    restore_score(db, key, rows)
                    if value == -0.000001:
                        break
                if trials >= max_trials:
                    break
            if not changed or trials >= max_trials or not current["errors"]:
                break
        if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise ValueError("Repaired database failed integrity check")
    final = evaluate(document, destination, policy)
    final_guards = [evaluate(doc, destination, policy)["total_actions"] for doc in guard_documents]
    if final["total_actions"] != current["total_actions"] or final_guards != guard_scores:
        raise ValueError("Independent final evaluation was not reproducible")
    return {"before": baseline, "after": final, "guard_before": guards, "guard_after": final_guards,
            "accepted": accepted, "trials": trials, "improved": final["total_actions"] < baseline["total_actions"]}


def previous_label(key):
    return f"{key[1] or '<BOS>'} → {key[2] or '<EOS>'}"


def main():
    parser = argparse.ArgumentParser(description="以動作數自動調整 bigram，輸出獨立模型；stdout 是修正後總動作數。")
    add_arguments(parser)
    parser.add_argument("--output", required=True, type=Path, help="new .db (also writes .json, .sql, .report.json)")
    parser.add_argument("--validation", action="append", default=[], type=Path, help="regression guard text, repeatable; never used for proposals")
    parser.add_argument("--max-trials", type=int, default=100)
    parser.add_argument("--passes", type=int, default=3)
    args = parser.parse_args()
    try:
        policy = policy_from(args)
        if args.max_trials < 1 or args.passes < 1:
            raise ValueError("max-trials and passes must be positive")
        output = args.output.resolve()
        if output.suffix != ".db":
            raise ValueError("output must have .db suffix")
        manifest_path, patch_path, report_path = output.with_suffix(".json"), output.with_suffix(".sql"), output.with_suffix(".report.json")
        for path in (output, manifest_path, patch_path, report_path):
            if path.exists():
                raise ValueError(f"Output already exists; choose a new version name: {path}")
        source = resolve_version(args.version)
        base_hash = sha256(source)
        lexicon = Lexicon(args.reference_db)
        document = load_document(args.article, lexicon)
        guards = [load_document(path, lexicon) for path in args.validation]
        if any(sha256(path) == sha256(args.article) for path in args.validation):
            raise ValueError("Validation must not be identical to training text")
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=output.parent) as directory:
            work = Path(directory)
            temporary = work / output.name
            report = tune(document, guards, source, temporary, lexicon, policy, args.max_trials, args.passes)
            report.update({"article": str(args.article), "article_sha256": sha256(args.article),
                           "reference_sha256": sha256(args.reference_db), "base_version": args.version,
                           "base_database_sha256": base_hash, "database_sha256": sha256(temporary),
                           "validation": [{"path": str(path), "sha256": sha256(path)} for path in args.validation],
                           "scope": "Training improvement only; validation guards participate in model selection, not an unbiased test set."})
            write_json(work / report_path.name, report)
            write_patch(work / patch_path.name, report["accepted"], base_hash)
            write_json(work / manifest_path.name, {"database": output.name, "database_sha256": sha256(temporary),
                                                   "base_database_sha256": base_hash, "policy": report["after"]["policy"],
                                                   "report": report_path.name, "patch": patch_path.name})
            for target in (output, report_path, patch_path, manifest_path):
                (work / target.name).replace(target)
        print(f"{report['before']['total_actions']} → {report['after']['total_actions']}; "
              f"{len(report['accepted'])} accepted, {report['trials']} trials. {output}", file=sys.stderr)
        print(report["after"]["total_actions"])
    except (ValueError, OSError, sqlite3.Error, subprocess.SubprocessError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
