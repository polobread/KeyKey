#!/usr/bin/env python3
"""Measure the incremental bigram effect of the v3 and v4 article sets."""

from __future__ import annotations

import json
import re
import sqlite3
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
COOKER_DIR = REPO / "Source" / "Distributions" / "Takao" / "DatabaseCooker"
COOKER = COOKER_DIR / "SmartMandarinCooker.rb"
COUNTS = REPO / "DataSource" / "McBopomofo" / "phrase.occ"
MAPPINGS = REPO / "DataSource" / "McBopomofo" / "BPMFMappings.txt"
BPMF_CIN = COOKER_DIR / "Intermediates" / "bpmf-ext-absorder.cin"
SUPPLEMENTAL = ROOT / "supplemental-lexicon.tsv"
NUMERIC_UNITS = ROOT / "numeric-unit-lexicon.tsv"
BOOTSTRAP = [ROOT / f"corpus-v{number}.txt" for number in (1, 2, 3)]
FEEDBACK = ROOT / "corpus-typing-feedback.txt"
CORPUS = ROOT / "article-corpus-2300-exact-dedup.txt"
OUTPUT_JSON = ROOT / "versioned-article-bigram-impact.json"
OUTPUT_MD = ROOT / "versioned-article-bigram-impact.md"
STAGES = (("v2", 1650), ("v2_v3", 2000), ("v2_v3_v4", 2300))


def corpus_snapshots(work: Path) -> dict[str, Path]:
    lines = CORPUS.read_text(encoding="utf-8").splitlines()
    boundaries = {
        "v2": "# tw-typing-v3-001",
        "v2_v3": "# tw-typing-v4-001",
    }
    snapshots = {}
    for name, _ in STAGES:
        stop = lines.index(boundaries[name]) if name in boundaries else len(lines)
        path = work / f"{name}.txt"
        path.write_text("\n".join(lines[:stop]) + "\n", encoding="utf-8")
        snapshots[name] = path
    return snapshots


def build_model(name: str, corpus: Path, work: Path) -> tuple[Path, dict]:
    sql_path = work / f"{name}.sql"
    command = [
        "ruby", "-E", "UTF-8", str(COOKER), str(COUNTS), str(MAPPINGS),
        str(BPMF_CIN), "--lexicon", str(SUPPLEMENTAL), "--lexicon", str(NUMERIC_UNITS),
        *(str(path) for path in BOOTSTRAP), str(FEEDBACK), str(corpus),
    ]
    with sql_path.open("wb") as output:
        result = subprocess.run(command, cwd=COOKER_DIR, stdout=output, stderr=subprocess.PIPE, check=True)
    log = result.stderr.decode("utf-8")
    match = re.search(
        r"(?P<unigrams>\d+) unigrams from (?P<words>\d+) words; "
        r"(?P<bigram_rows>\d+) bigrams from (?P<sentences>\d+) sentences and "
        r"(?P<tokens>\d+) tokens;.*? (?P<clipped>\d+) repeated occurrences clipped",
        log,
    )
    if not match:
        raise SystemExit(f"cannot parse cooker output for {name}: {log}")

    db_path = work / f"{name}.db"
    connection = sqlite3.connect(db_path)
    connection.executescript(
        "PRAGMA page_size=8192;"
        "CREATE TABLE unigrams (qstring, current, probability, backoff);"
        "CREATE TABLE bigrams (qstring, previous, current, probability);"
    )
    connection.close()
    with sql_path.open("rb") as input_file:
        subprocess.run(["sqlite3", str(db_path)], stdin=input_file, check=True)
    connection = sqlite3.connect(db_path)
    connection.executescript(
        "CREATE INDEX unigrams_index ON unigrams(qstring);"
        "CREATE INDEX unigrams_current_index ON unigrams(current);"
        "CREATE INDEX bigrams_index ON bigrams(qstring);"
    )
    metrics = {
        **{key: int(value) for key, value in match.groupdict().items()},
        "integrity_check": connection.execute("PRAGMA integrity_check").fetchone()[0],
        "text_pairs": connection.execute(
            "SELECT count(*) FROM (SELECT DISTINCT previous, current FROM bigrams)"
        ).fetchone()[0],
        "database_bytes": db_path.stat().st_size,
    }
    connection.close()
    if metrics["integrity_check"] != "ok":
        raise SystemExit(f"integrity check failed for {name}")
    return db_path, metrics


def pair_difference(older: Path, newer: Path) -> tuple[int, int]:
    connection = sqlite3.connect(newer)
    connection.execute("ATTACH DATABASE ? AS older", (str(older),))
    added = connection.execute(
        "SELECT count(*) FROM (SELECT previous,current FROM main.bigrams "
        "EXCEPT SELECT previous,current FROM older.bigrams)"
    ).fetchone()[0]
    lost = connection.execute(
        "SELECT count(*) FROM (SELECT previous,current FROM older.bigrams "
        "EXCEPT SELECT previous,current FROM main.bigrams)"
    ).fetchone()[0]
    connection.close()
    return added, lost


def markdown(report: dict) -> str:
    lines = [
        "# Versioned article bigram impact",
        "",
        "Each stage uses the same three bootstrap corpora, typing feedback, "
        "McBopomofo vocabulary, project supplemental lexicon, and enumerated number-unit lexicon. "
        "The article corpus removes only identical lines; each synthetic text pair counts once.",
        "",
        "| Articles | Bigram rows | Distinct text pairs | Added pairs | Lost pairs | Minimal DB | DB change |",
        "| ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in report["stages"]:
        lines.append(
            f"| {row['articles']:,} | {row['bigram_rows']:,} | {row['text_pairs']:,} | "
            f"{row['added_pairs']:,} | {row['lost_pairs']:,} | "
            f"{row['database_bytes'] / 1048576:.2f} MiB | "
            f"{row['database_change_bytes'] / 1048576:+.2f} MiB |"
        )
    lines.extend([
        "",
        "The figures measure stored adjacent-word coverage and database size. "
        "Candidate-order quality still requires typing evaluation.",
        "",
    ])
    return "\n".join(lines)


def main() -> None:
    required = [COOKER, COUNTS, MAPPINGS, BPMF_CIN, SUPPLEMENTAL, NUMERIC_UNITS, *BOOTSTRAP, FEEDBACK, CORPUS]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise SystemExit("missing inputs: " + ", ".join(missing))
    with tempfile.TemporaryDirectory(prefix="keykey-versioned-bigram-") as temp:
        work = Path(temp)
        corpora = corpus_snapshots(work)
        databases = {}
        rows = []
        for name, articles in STAGES:
            database, metrics = build_model(name, corpora[name], work)
            databases[name] = database
            rows.append({"stage": name, "articles": articles, **metrics})
        for index, row in enumerate(rows):
            if index == 0:
                row.update({"added_pairs": 0, "lost_pairs": 0, "database_change_bytes": 0})
                continue
            older = rows[index - 1]
            added, lost = pair_difference(databases[older["stage"]], databases[row["stage"]])
            row.update({
                "added_pairs": added,
                "lost_pairs": lost,
                "database_change_bytes": row["database_bytes"] - older["database_bytes"],
            })
        report = {"corpus_file": CORPUS.name, "stages": rows}
        OUTPUT_JSON.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        OUTPUT_MD.write_text(markdown(report), encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
