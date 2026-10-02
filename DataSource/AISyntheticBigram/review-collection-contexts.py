#!/usr/bin/env python3
"""Test individual collection-word removal in regressed, fixed-trace contexts."""
import argparse
import csv
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile

from typing_cost import DEFAULT_DB, Engine, Lexicon, Policy, evaluate, load_document, query_for_reading, sha256

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "DataSource/AISyntheticBigram"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--traces", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    before_trace = json.loads((args.traces / "before-trace.json").read_text())
    after_trace = json.loads((args.traces / "collections-trace.json").read_text())
    db_hash = sha256(DEFAULT_DB)
    if after_trace["identity"]["database_sha256"] != db_hash:
        raise ValueError("trace was generated from another current DB")
    for trace in (before_trace, after_trace):
        if trace["identity"]["reference_sha256"] != sha256(args.reference):
            raise ValueError("trace reference differs from selected reference")
    lexicon = Lexicon(args.reference)
    entries = list(csv.DictReader((DATA / "collection-unigram.tsv").open(), delimiter="\t"))
    index = {}
    for row in entries:
        index.setdefault("".join(query_for_reading(x) for x in row["reading"].split()), []).append(row["word"])
    records = []
    with tempfile.TemporaryDirectory(prefix="keykey-overlap-ablation-") as temporary:
        copies = {}
        for article, (old, new) in enumerate(zip(before_trace["reports"], after_trace["reports"]), 1):
            if new["total_actions"] <= old["total_actions"]:
                continue
            path = ROOT / f"DataSource/AISyntheticArticles/typing-articles-v5-seed/tw-corpus-{article:04d}.md"
            if sha256(path) != after_trace["identity"]["articles"][article - 1]["sha256"]:
                raise ValueError("article content changed")
            document = load_document(path, lexicon)
            old_errors = {json.dumps(row, sort_keys=True) for row in old["errors"]}
            blocks = {row["block"] for row in new["errors"] if json.dumps(row, sort_keys=True) not in old_errors}
            for block_index in sorted(blocks):
                block = document[block_index]
                hits = {}
                for start in range(len(block["queries"])):
                    for end in range(start + 2, min(start + 7, len(block["queries"])) + 1):
                        for word in index.get("".join(block["queries"][start:end]), []):
                            hits[word] = block["text"][start:end]
                old_cost = evaluate([block], args.before, Policy())["correction_actions"]
                new_cost = evaluate([block], DEFAULT_DB, Policy())["correction_actions"]
                for word, overlap in hits.items():
                    if word not in copies:
                        candidate = Path(temporary) / f"{len(copies)}.db"
                        shutil.copyfile(DEFAULT_DB, candidate)
                        with sqlite3.connect(candidate) as db:
                            if db.execute("DELETE FROM unigrams WHERE current=?", (word,)).rowcount != 1:
                                raise ValueError(f"expected one new unigram: {word}")
                        copies[word] = candidate
                    cost = evaluate([block], copies[word], Policy())["correction_actions"]
                    records.append(dict(word=word, article=f"tw-corpus-{article:04d}", block=block_index,
                        context=block["text"], overlap_text=overlap, before_correction_actions=old_cost,
                        after_correction_actions=new_cost, without_word_correction_actions=cost,
                        removed_word_saves=new_cost-cost, block_regression=new_cost-old_cost))
    if not records:
        raise ValueError("no regressed-context candidates found")
    with args.output.open("w", newline="", encoding="utf-8") as target:
        writer = csv.DictWriter(target, fieldnames=list(records[0]), delimiter="\t", lineterminator="\n")
        writer.writeheader(); writer.writerows(records)
    if sha256(DEFAULT_DB) != db_hash:
        raise ValueError("current DB changed during review")
    metadata = {"database_sha256": db_hash, "before_sha256": sha256(args.before),
                "reference_sha256": sha256(args.reference),
                "before_trace_sha256": sha256(args.traces / "before-trace.json"),
                "after_trace_sha256": sha256(args.traces / "collections-trace.json"),
                "script_sha256": sha256(Path(__file__)), "result_sha256": sha256(args.output),
                "scope": "individual word ablation in changed blocks of regressed articles; not a full corpus deletion recommendation"}
    args.output.with_suffix(".json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    print(f"Reviewed {len(records)} word/context pairs")


if __name__ == "__main__":
    main()
