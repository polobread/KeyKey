#!/usr/bin/env python3
"""Build and compare project-owned unigram counts on the frozen 50-article holdout."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile

from typing_cost import DEFAULT_DB, REPO, ROOT, Policy, connect, sha256, writable_db, write_json
from typing_batch import sample_articles, prepare_articles, evaluate_articles, write_comparison


COOKER_DIR = REPO / "Source/Distributions/Takao/DatabaseCooker"
COOKER = COOKER_DIR / "SmartMandarinCooker.rb"
MAPPINGS = REPO / "DataSource/McBopomofo/BPMFMappings.txt"
BPMF_CIN = COOKER_DIR / "Intermediates/bpmf-ext-absorder.cin"
BASE_COUNTS = REPO / "DataSource/McBopomofo/phrase.occ"
SUPPLEMENTS = (ROOT / "supplemental-lexicon.tsv", ROOT / "numeric-unit-lexicon.tsv")
BOOTSTRAP = tuple(ROOT / f"corpus-v{number}.txt" for number in (1, 2, 3))
FEEDBACK = ROOT / "corpus-typing-feedback.txt"


def build_model(source_db: Path, counts: Path, article_corpus: Path, destination: Path,
                preserve_supplement_counts: bool) -> dict:
    if destination.exists():
        raise ValueError(f"Refuse to overwrite model: {destination}")
    required = (source_db, counts, article_corpus, COOKER, MAPPINGS, BPMF_CIN, *SUPPLEMENTS, *BOOTSTRAP, FEEDBACK)
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise ValueError(f"Missing model source: {', '.join(missing)}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    option = "--lexicon-preserve-counts" if preserve_supplement_counts else "--lexicon"
    with tempfile.TemporaryDirectory(dir=destination.parent) as directory:
        work = Path(directory)
        sql = work / "model.sql"
        command = ["ruby", "-E", "UTF-8", str(COOKER.resolve()), str(counts.resolve()),
                   str(MAPPINGS.resolve()), str(BPMF_CIN.resolve()), option, str(SUPPLEMENTS[0].resolve()),
                   option, str(SUPPLEMENTS[1].resolve()), *(str(path.resolve()) for path in BOOTSTRAP),
                   str(FEEDBACK.resolve()), str(article_corpus.resolve())]
        with sql.open("wb") as output:
            result = subprocess.run(command, cwd=COOKER_DIR, stdout=output, stderr=subprocess.PIPE)
        log = result.stderr.decode("utf-8", errors="replace")
        if result.returncode:
            raise ValueError(f"SmartMandarinCooker failed: {log}")
        match = re.search(
            r"(?P<unigram_rows>\d+) unigrams from (?P<words>\d+) words; "
            r"(?P<bigram_rows>\d+) bigrams from (?P<sentences>\d+) sentences and "
            r"(?P<tokens>\d+) tokens; prior strength (?P<prior>\d+), pair count capped at (?P<cap>\d+), "
            r"(?P<clipped>\d+) repeated occurrences clipped; (?P<supplemental>\d+) supplemental lexicon entries, "
            r"(?P<skipped>\d+) invalid supplemental entries skipped", log)
        if not match:
            raise ValueError(f"Cannot parse cooker result: {log}")
        temporary = work / destination.name
        shutil.copy2(source_db, temporary)
        with writable_db(temporary) as db:
            db.execute("DELETE FROM unigrams")
            db.execute("DELETE FROM bigrams")
            db.commit()
        with sql.open("rb") as source:
            load = subprocess.run(["sqlite3", str(temporary)], stdin=source, stderr=subprocess.PIPE)
        if load.returncode:
            raise ValueError(f"SQLite model load failed: {load.stderr.decode('utf-8', errors='replace')}")
        with connect(temporary) as db:
            integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
            unigram_rows = db.execute("SELECT count(*) FROM unigrams").fetchone()[0]
            bigram_rows = db.execute("SELECT count(*) FROM bigrams").fetchone()[0]
        metrics = {key: int(value) for key, value in match.groupdict().items()}
        # Cooker diagnostic counts lexical rows; the DB also has UNK/BOS/EOS.
        if integrity != "ok" or unigram_rows != metrics["unigram_rows"] + 3 or bigram_rows != metrics["bigram_rows"]:
            raise ValueError(
                "Built model failed verification: "
                f"integrity={integrity!r}, unigrams actual/log={unigram_rows}/{metrics['unigram_rows']}, "
                f"bigrams actual/log={bigram_rows}/{metrics['bigram_rows']}")
        temporary.replace(destination)
    return {**metrics, "counts_file": str(counts), "counts_sha256": sha256(counts),
            "article_corpus": str(article_corpus), "article_corpus_sha256": sha256(article_corpus),
            "supplement_count_policy": "preserve generated counts" if preserve_supplement_counts else "project supplements may raise counts",
            "database_sha256": sha256(destination), "database_bytes": destination.stat().st_size}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True,
                        help="directory produced by build-project-unigram.py")
    parser.add_argument("--sample", type=Path, required=True)
    parser.add_argument("--reference-db", type=Path, default=DEFAULT_DB)
    args = parser.parse_args()
    try:
        sample = json.loads(args.sample.read_text(encoding="utf-8"))
        articles, regenerated = sample_articles(sample["count"], sample["seed"])
        if regenerated != sample:
            raise ValueError("Frozen test sample does not match the current 2300-article population")
        occurrence = args.directory / "project-occurrence.occ"
        document_frequency = args.directory / "project-document-frequency.occ"
        corpus = args.directory / "project-occurrence.corpus.txt"
        if sha256(corpus) != sha256(args.directory / "project-document-frequency.corpus.txt"):
            raise ValueError("Project unigram variants must use the same 2250-article training corpus")
        reports = [json.loads(path.read_text(encoding="utf-8")) for path in
                   (occurrence.with_suffix(".report.json"), document_frequency.with_suffix(".report.json"))]
        if any(row["sample_manifest_sha256"] != sha256(args.sample) for row in reports):
            raise ValueError("Unigram counts were not built against this frozen sample")
        models = {
            "mc-bopomofo-control": (BASE_COUNTS, False),
            "project-occurrence": (occurrence, True),
            "project-document-frequency": (document_frequency, True),
        }
        built, versions = {}, {}
        for name, (counts, preserve) in models.items():
            database = args.directory / f"{name}.db"
            print(f"Building {name}", file=sys.stderr, flush=True)
            built[name] = build_model(args.reference_db, counts, corpus, database, preserve)
            versions[name] = database
            write_json(args.directory / "model-builds.json", built)
        _, documents = prepare_articles(articles, args.reference_db)
        identifiers = [row["id"] for row in sample["articles"]]
        policy = Policy()
        scores = {}
        for index, (name, database) in enumerate(versions.items()):
            scores[name] = evaluate_articles(documents, database, policy, identifiers, name)
            write_json(args.directory / f"traces-{index}.json",
                       {"version": name, "database_sha256": sha256(database), "reports": scores[name]})
        result = write_comparison(args.directory / "comparison.json", sample, versions, scores, policy, args.reference_db)
        result["training"] = {"articles": 2250, "test_articles": 50,
                              "test_leakage": "Frozen 50 excluded from project counts and all three paired bigram models",
                              "controlled": "Same vocabulary/readings, bootstrap, feedback, article corpus and cooker parameters; unigram counts differ"}
        write_json(args.directory / "comparison.json", result)
        eligible = [(row["evaluated_actions_after"], name)
                    for name, row in result["comparisons"].items() if row["passes"]]
        selection = {"selected": min(eligible)[1] if eligible else "mc-bopomofo-control",
                     "rule": ("lower correction actions for basic/general characters in v2/v3, stable article/source/category "
                              "distribution, improved basic characters, and stable general characters"),
                     "formal_replacement": False,
                     "reason": "Experimental corpus-derived counts require broader held-out corpora and five-platform validation before replacement."}
        write_json(args.directory / "selection.json", selection)
        print(json.dumps({"comparisons": result["comparisons"], **selection}, ensure_ascii=False, indent=2))
    except (ValueError, OSError, sqlite3.Error, subprocess.SubprocessError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
