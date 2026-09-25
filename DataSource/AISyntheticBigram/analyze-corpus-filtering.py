#!/usr/bin/env python3
"""Compare raw, exact-deduplicated, and near-deduplicated article corpora."""

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
SUPPLEMENTAL_LEXICON = ROOT / "supplemental-lexicon.tsv"
BOOTSTRAP = [ROOT / f"corpus-v{number}.txt" for number in (1, 2, 3)]
ARTICLES = ROOT.parent / "AISyntheticArticles" / "typing-articles-v2.jsonl"
OUTPUT_JSON = ROOT / "article-corpus-filtering-analysis.json"
OUTPUT_MD = ROOT / "article-corpus-filtering-analysis.md"


def corpus_lines(text: str) -> list[str]:
    result = []
    for raw in text.splitlines():
        line = re.sub(r"^(?:#{1,6}|>|[-*+])\s*", "", raw.strip())
        if re.search(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", line):
            result.append(line)
    return result


def run_cooker(name: str, corpora: list[Path], work: Path) -> tuple[Path, dict]:
    sql_path = work / f"{name}.sql"
    command = [
        "ruby", "-E", "UTF-8", str(COOKER), str(COUNTS), str(MAPPINGS),
        str(BPMF_CIN), "--lexicon", str(SUPPLEMENTAL_LEXICON),
        *(str(path) for path in corpora),
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
    return sql_path, {key: int(value) for key, value in match.groupdict().items()}


def build_database(name: str, sql_path: Path, work: Path) -> Path:
    path = work / f"{name}.db"
    connection = sqlite3.connect(path)
    connection.executescript(
        "PRAGMA page_size=8192;"
        "CREATE TABLE unigrams (qstring, current, probability, backoff);"
        "CREATE TABLE bigrams (qstring, previous, current, probability);"
    )
    connection.executescript(sql_path.read_text(encoding="utf-8"))
    connection.executescript(
        "CREATE INDEX unigrams_index ON unigrams(qstring);"
        "CREATE INDEX unigrams_current_index ON unigrams(current);"
        "CREATE INDEX bigrams_index ON bigrams(qstring);"
    )
    connection.commit()
    connection.close()
    return path


def text_pairs(path: Path, lexical_only: bool = False) -> set[tuple[str, str]]:
    connection = sqlite3.connect(path)
    query = "SELECT DISTINCT previous, current FROM bigrams"
    if lexical_only:
        query += " WHERE previous <> '' AND current <> ''"
    result = set(connection.execute(query))
    connection.close()
    return result


def metrics(path: Path) -> dict:
    connection = sqlite3.connect(path)
    result = {
        "integrity_check": connection.execute("PRAGMA integrity_check").fetchone()[0],
        "bigram_rows": connection.execute("SELECT count(*) FROM bigrams").fetchone()[0],
        "text_bigram_pairs": connection.execute(
            "SELECT count(*) FROM (SELECT DISTINCT previous, current FROM bigrams)"
        ).fetchone()[0],
        "lexical_text_bigram_pairs": connection.execute(
            "SELECT count(*) FROM (SELECT DISTINCT previous, current FROM bigrams WHERE previous <> '' AND current <> '')"
        ).fetchone()[0],
        "database_bytes": path.stat().st_size,
        "database_mib": path.stat().st_size / 1024 / 1024,
    }
    connection.close()
    return result


def markdown(report: dict) -> str:
    lines = [
        "# Article corpus filtering experiment",
        "",
        "Exact duplicates are compared with conservative near-duplicate filtering (normalized-character 5-gram Jaccard >= 0.86, length ratio >= 0.90).",
        "",
        "## Full 1,650-article database",
        "",
        "| Variant | Corpus lines | Removed lines | Text pairs | Pairs retained | SQLite rows | DB size | Size saved |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in report["full_1650"]:
        lines.append(
            f"| {row['variant']} | {row['corpus_lines']:,} | {row['removed_lines']:,} | "
            f"{row['text_bigram_pairs']:,} | {row['pair_retention_percent']:.3f}% | "
            f"{row['bigram_rows']:,} | {row['database_mib']:.2f} MiB | {row['size_saved_mib']:.2f} MiB |"
        )
    lines.extend([
        "",
        "## Held-out articles 1,551–1,650",
        "",
        "Training uses articles 1–1,500. The held-out block contains "
        f"{report['heldout_1551_1650']['lexical_pairs']:,} lexical pairs.",
        "",
        "| Training variant | Covered pairs | Coverage | Change from raw |",
        "| --- | ---: | ---: | ---: |",
    ])
    for row in report["heldout_1551_1650"]["variants"]:
        lines.append(
            f"| {row['variant']} | {row['covered_pairs']:,} | {row['coverage_percent']:.3f}% | "
            f"{row['coverage_change_percentage_points']:+.3f} pp |"
        )
    lines.extend([
        "",
        "## Result",
        "",
        f"- Exact line deduplication removes {report['summary']['exact_lines_removed']:,} repeated lines, but saves only "
        f"{report['summary']['exact_size_saved_mib']:.2f} MiB because the production cooker already caps every synthetic pair at one observation.",
        f"- Conservative near deduplication removes {report['summary']['near_lines_removed']:,} additional lines and saves "
        f"{report['summary']['near_size_saved_mib']:.2f} MiB relative to raw.",
        f"- Near deduplication retains {report['summary']['near_pair_retention_percent']:.3f}% of text pairs and changes held-out coverage by "
        f"{report['summary']['near_coverage_change_percentage_points']:+.3f} percentage points.",
        "- Filtering repeated paragraphs does not materially solve database growth; selecting a smaller article snapshot or pruning low-value bigram rows is more effective.",
        "",
    ])
    return "\n".join(lines)


def main() -> None:
    corpora = {
        "raw1500": ROOT / "article-corpus-1500.txt",
        "exact1500": ROOT / "article-corpus-1500-exact-dedup.txt",
        "near1500": ROOT / "article-corpus-1500-near-dedup.txt",
        "raw1650": ROOT / "article-corpus-1650.txt",
        "exact1650": ROOT / "article-corpus-1650-exact-dedup.txt",
        "near1650": ROOT / "article-corpus-1650-near-dedup.txt",
    }
    missing = [path for path in [COOKER, COUNTS, MAPPINGS, BPMF_CIN, SUPPLEMENTAL_LEXICON, ARTICLES, *BOOTSTRAP, *corpora.values()] if not path.exists()]
    if missing:
        raise SystemExit("missing inputs: " + ", ".join(map(str, missing)))

    articles = [json.loads(line) for line in ARTICLES.read_text(encoding="utf-8").splitlines() if line.strip()]
    filter_report = json.loads((ROOT / "article-corpus-filtering-report.json").read_text(encoding="utf-8"))
    filter_by_count = {row["articles"]: row for row in filter_report["snapshots"]}

    with tempfile.TemporaryDirectory(prefix="keykey-corpus-filtering-") as temp:
        work = Path(temp)
        heldout = work / "heldout-1551-1650.txt"
        heldout_lines = ["# Held-out articles 1551-1650."]
        for article in articles[1550:1650]:
            heldout_lines.append(f"# {article['prompt_id']}")
            heldout_lines.extend(corpus_lines(article["text"]))
        heldout.write_text("\n".join(heldout_lines) + "\n", encoding="utf-8")

        configurations = {name: BOOTSTRAP + [path] for name, path in corpora.items()}
        configurations["heldout"] = [heldout]
        stats = {}
        databases = {}
        for name, paths in configurations.items():
            sql_path, stats[name] = run_cooker(name, paths, work)
            databases[name] = build_database(name, sql_path, work)

        db_metrics = {name: metrics(path) for name, path in databases.items()}
        raw_full_pairs = text_pairs(databases["raw1650"])
        full = []
        for variant, name, line_count in (
            ("raw", "raw1650", filter_by_count[1650]["raw_lines"]),
            ("exact dedup", "exact1650", filter_by_count[1650]["exact_lines"]),
            ("near dedup", "near1650", filter_by_count[1650]["near_dedup_lines"]),
        ):
            pairs = text_pairs(databases[name])
            row = {
                "variant": variant,
                "corpus_lines": line_count,
                "removed_lines": filter_by_count[1650]["raw_lines"] - line_count,
                **stats[name],
                **db_metrics[name],
                "pair_retention_percent": len(pairs & raw_full_pairs) / len(raw_full_pairs) * 100,
                "pairs_missing_vs_raw": len(raw_full_pairs - pairs),
                "size_saved_bytes": db_metrics["raw1650"]["database_bytes"] - db_metrics[name]["database_bytes"],
                "size_saved_mib": (db_metrics["raw1650"]["database_bytes"] - db_metrics[name]["database_bytes"]) / 1024 / 1024,
            }
            full.append(row)

        heldout_pairs = text_pairs(databases["heldout"], lexical_only=True)
        heldout_variants = []
        raw_covered = len(text_pairs(databases["raw1500"], lexical_only=True) & heldout_pairs)
        raw_coverage = raw_covered / len(heldout_pairs) * 100
        for variant, name in (("raw", "raw1500"), ("exact dedup", "exact1500"), ("near dedup", "near1500")):
            covered = len(text_pairs(databases[name], lexical_only=True) & heldout_pairs)
            coverage = covered / len(heldout_pairs) * 100
            heldout_variants.append({
                "variant": variant,
                "covered_pairs": covered,
                "coverage_percent": coverage,
                "coverage_change_percentage_points": coverage - raw_coverage,
            })

        full_by_variant = {row["variant"]: row for row in full}
        heldout_by_variant = {row["variant"]: row for row in heldout_variants}
        report = {
            "method": {
                "pair_count_cap": 1,
                "near_duplicate_thresholds": filter_by_count[1650]["near_thresholds"],
            },
            "full_1650": full,
            "heldout_1551_1650": {"lexical_pairs": len(heldout_pairs), "variants": heldout_variants},
            "summary": {
                "exact_lines_removed": full_by_variant["exact dedup"]["removed_lines"],
                "near_lines_removed": full_by_variant["near dedup"]["removed_lines"] - full_by_variant["exact dedup"]["removed_lines"],
                "exact_size_saved_mib": full_by_variant["exact dedup"]["size_saved_mib"],
                "near_size_saved_mib": full_by_variant["near dedup"]["size_saved_mib"],
                "near_pair_retention_percent": full_by_variant["near dedup"]["pair_retention_percent"],
                "near_coverage_change_percentage_points": heldout_by_variant["near dedup"]["coverage_change_percentage_points"],
            },
        }

    OUTPUT_JSON.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    OUTPUT_MD.write_text(markdown(report), encoding="utf-8")
    print(json.dumps(report["summary"], ensure_ascii=False))


if __name__ == "__main__":
    main()
