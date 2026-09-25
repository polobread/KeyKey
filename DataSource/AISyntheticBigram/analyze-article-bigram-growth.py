#!/usr/bin/env python3
"""Build and compare SmartMandarin bigrams at 100-article increments."""

from __future__ import annotations

import json
import math
import re
import sqlite3
import statistics
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
OUTPUT_JSON = ROOT / "article-bigram-growth-report.json"
OUTPUT_MD = ROOT / "article-bigram-growth-report.md"
SNAPSHOTS = (100, 200, 300, 400, 450, 500, 700, 900, 1100, 1300, 1500, 1650)
HELDOUT_RANGES = ((201, 300), (1551, 1650))


def corpus_lines(text: str) -> list[str]:
    lines = []
    for raw in text.splitlines():
        line = re.sub(r"^(?:#{1,6}|>|[-*+])\s*", "", raw.strip())
        if re.search(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", line):
            lines.append(line)
    return lines


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


def database_metrics(path: Path) -> dict:
    connection = sqlite3.connect(path)
    integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
    if integrity != "ok":
        raise SystemExit(f"SQLite integrity check failed for {path}: {integrity}")
    result = {
        "integrity_check": integrity,
        "bigram_rows": connection.execute("SELECT count(*) FROM bigrams").fetchone()[0],
        "text_bigram_pairs": connection.execute(
            "SELECT count(*) FROM (SELECT DISTINCT previous, current FROM bigrams)"
        ).fetchone()[0],
        "lexical_text_bigram_pairs": connection.execute(
            "SELECT count(*) FROM (SELECT DISTINCT previous, current FROM bigrams "
            "WHERE previous <> '' AND current <> '')"
        ).fetchone()[0],
        "predecessor_contexts": connection.execute(
            "SELECT count(DISTINCT previous) FROM bigrams WHERE previous <> ''"
        ).fetchone()[0],
        "database_bytes": path.stat().st_size,
    }
    connection.close()
    return result


def quantile(values: list[float], fraction: float) -> float:
    return values[min(len(values) - 1, round((len(values) - 1) * fraction))]


def power_law_projection(growth: list[dict]) -> dict:
    """Fit late-block marginal yield as y = coefficient * article^exponent."""
    samples = []
    previous_count = 0
    for row in growth:
        midpoint = (previous_count + row["articles"]) / 2
        if row["articles"] >= 700:
            samples.append((midpoint, row["marginal_new_pairs_per_article"]))
        previous_count = row["articles"]
    xs = [math.log(point) for point, _ in samples]
    ys = [math.log(value) for _, value in samples]
    mean_x = statistics.mean(xs)
    mean_y = statistics.mean(ys)
    exponent = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / sum(
        (x - mean_x) ** 2 for x in xs
    )
    intercept = mean_y - exponent * mean_x
    coefficient = math.exp(intercept)
    predictions = [intercept + exponent * x for x in xs]
    residual = sum((actual - predicted) ** 2 for actual, predicted in zip(ys, predictions))
    total = sum((actual - mean_y) ** 2 for actual in ys)
    thresholds = (175, 150, 125, 100)
    return {
        "model": "marginal_pairs_per_article = coefficient * article_count ^ exponent",
        "fit_blocks": ["501–700", "701–900", "901–1100", "1101–1300", "1301–1500", "1501–1650"],
        "coefficient": coefficient,
        "exponent": exponent,
        "r_squared_log_space": 1 - residual / total,
        "projections": [
            {
                "marginal_pairs_per_article": threshold,
                "projected_article_count": round((threshold / coefficient) ** (1 / exponent)),
            }
            for threshold in thresholds
        ],
        "warning": "Extrapolation from six late blocks; topic mix and filtering policy can change the curve.",
    }


def explicit_pair_boost(path: Path, prior_path: Path) -> dict:
    prior_connection = sqlite3.connect(prior_path)
    prior_rows = set(prior_connection.execute(
        "SELECT qstring, previous, current FROM bigrams WHERE previous <> '' AND current <> ''"
    ))
    prior_connection.close()

    connection = sqlite3.connect(path)
    unigrams = {
        (qstring, current): (probability, backoff)
        for qstring, current, probability, backoff in connection.execute(
            "SELECT qstring, current, probability, backoff FROM unigrams"
        )
    }
    values = []
    for qstring, previous, current, probability in connection.execute(
        "SELECT qstring, previous, current, probability FROM bigrams "
        "WHERE previous <> '' AND current <> ''"
    ):
        if (qstring, previous, current) in prior_rows:
            continue
        previous_qstring, current_qstring = qstring.split(" ", 1)
        previous_unigram = unigrams.get((previous_qstring, previous))
        current_unigram = unigrams.get((current_qstring, current))
        if not previous_unigram or not current_unigram:
            continue
        backoff_score = current_unigram[0] + previous_unigram[1]
        values.append(probability - backoff_score)
    connection.close()
    values.sort()
    return {
        "new_lexical_rows_measured": len(values),
        "median_log10_score_lift": statistics.median(values),
        "median_probability_multiplier": 10 ** statistics.median(values),
        "p10_log10_score_lift": quantile(values, 0.1),
        "p90_log10_score_lift": quantile(values, 0.9),
    }


def markdown(report: dict) -> str:
    lines = [
        "# Synthetic article bigram growth experiment",
        "",
        "The experiment uses the production `SmartMandarinCooker.rb`, the three existing bootstrap corpora, "
        "and cumulative article snapshots listed below. Synthetic text bigrams "
        "remain capped at one observation each with unigram prior strength 1,000.",
        "",
        "## Growth",
        "",
        "| Articles | Segmented sequences | Tokens | SQLite bigram rows | Distinct text pairs | New pairs vs baseline | New pairs in this block | New pairs/article | DB increase |",
        "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in report["growth"]:
        lines.append(
            f"| {row['articles']} | {row['sentences']:,} | {row['tokens']:,} | {row['bigram_rows']:,} | "
            f"{row['text_bigram_pairs']:,} | {row['new_pairs_vs_baseline']:,} | "
            f"{row['marginal_new_pairs']:,} | {row['marginal_new_pairs_per_article']:.1f} | "
            f"{row['database_increase_mib']:.2f} MiB |"
        )
    lines.extend(["", "## Held-out lexical-pair coverage"])
    for start, end in HELDOUT_RANGES:
        coverage = report[f"heldout_{start}_{end}_coverage"]
        lines.extend([
            "",
            f"### Articles {start}–{end}",
            "",
            f"This block contains {coverage['heldout_lexical_pairs']:,} distinct lexical text bigrams after production segmentation.",
            "",
            "| Training corpus | Covered pairs | Coverage |",
            "| --- | ---: | ---: |",
        ])
        for row in coverage["models"]:
            label = "existing bootstrap" if row["articles"] == 0 else f"bootstrap + first {row['articles']} articles"
            if row["in_sample"]:
                label += " (in sample)"
            lines.append(f"| {label} | {row['covered_pairs']:,} | {row['coverage_percent']:.2f}% |")
    lines.extend([
        "",
        "## Explicit-pair score lift",
        "",
        "The multiplier compares a newly explicit lexical bigram with the same model's unigram-plus-backoff score. "
        "It measures local language-model influence, not end-to-end candidate accuracy.",
        "",
        "| Added article block | New reading-expanded rows measured | Median score lift | Median probability multiplier | P10–P90 log10 lift |",
        "| --- | ---: | ---: | ---: | ---: |",
    ])
    for row in report["score_lift"]:
        lines.append(
            f"| {row['block']} | {row['new_lexical_rows_measured']:,} | "
            f"{row['median_log10_score_lift']:.3f} | {row['median_probability_multiplier']:.1f}× | "
            f"{row['p10_log10_score_lift']:.3f}–{row['p90_log10_score_lift']:.3f} |"
        )
    lines.extend([
        "",
        "## Interpretation",
        "",
        f"- The first 100 articles add {report['summary']['first_100_new_pairs']:,} text pairs.",
        f"- Coverage of unseen articles 201–300 rises from {report['summary']['baseline_heldout_coverage_percent']:.2f}% with the existing bootstrap corpus to "
        f"{report['summary']['after_100_heldout_coverage_percent']:.2f}% after 100 articles and {report['summary']['after_200_heldout_coverage_percent']:.2f}% after 200 articles.",
        "- Results at 300 articles and above are in-sample for articles 201–300, so their inclusion is not reported as generalization.",
        f"- Moving from {report['summary']['comparison_from_articles']} to {report['summary']['comparison_to_articles']} articles adds "
        f"{report['summary']['pairs_added_in_comparison']:,} distinct text pairs and "
        f"{report['summary']['rows_added_in_comparison']:,} reading-expanded SQLite rows; the database grows by another "
        f"{report['summary']['database_mib_added_in_comparison']:.2f} MiB.",
        f"- Moving from 500 to 700 articles adds {report['summary']['pairs_added_500_to_700']:,} distinct text pairs, "
        f"{report['summary']['rows_added_500_to_700']:,} reading-expanded rows, and {report['summary']['database_mib_added_500_to_700']:.2f} MiB. "
        f"Coverage of held-out articles 1,551–1,650 rises by {report['summary']['heldout_coverage_gain_500_to_700_pp']:.2f} percentage points.",
        f"- A power-law fit over blocks 501–1,650 estimates about {report['saturation_projection']['projections'][1]['projected_article_count']:,} articles before marginal yield falls below 150 new text pairs per article, "
        f"and about {report['saturation_projection']['projections'][3]['projected_article_count']:,} before it falls below 100. "
        "These are planning estimates rather than a stopping guarantee.",
        "- Pair coverage and score lift do not prove better candidate ordering. A/B typing tests on held-out keystroke sequences remain necessary before enabling an article snapshot in the shipping database.",
        "",
    ])
    return "\n".join(lines)


def main() -> None:
    missing = [path for path in [COOKER, COUNTS, MAPPINGS, BPMF_CIN, SUPPLEMENTAL_LEXICON, ARTICLES, *BOOTSTRAP] if not path.exists()]
    if missing:
        raise SystemExit("missing inputs: " + ", ".join(map(str, missing)))
    snapshots = {count: ROOT / f"article-corpus-{count}.txt" for count in SNAPSHOTS}
    if any(not path.exists() for path in snapshots.values()):
        raise SystemExit("run build-article-corpora.py first")

    articles = [json.loads(line) for line in ARTICLES.read_text(encoding="utf-8").splitlines() if line.strip()]
    with tempfile.TemporaryDirectory(prefix="keykey-article-bigram-") as temp:
        work = Path(temp)
        configurations = {
            "baseline": BOOTSTRAP,
            "plus100": BOOTSTRAP + [snapshots[100]],
            "plus200": BOOTSTRAP + [snapshots[200]],
        }
        configurations.update({
            f"plus{count}": BOOTSTRAP + [snapshots[count]] for count in SNAPSHOTS
        })
        for start, end in HELDOUT_RANGES:
            heldout_path = work / f"article-corpus-{start}-{end}.txt"
            heldout_lines = [f"# Held-out articles {start}-{end} for coverage analysis."]
            for article in articles[start - 1:end]:
                heldout_lines.append(f"# {article['prompt_id']}")
                heldout_lines.extend(corpus_lines(article["text"]))
            heldout_path.write_text("\n".join(heldout_lines) + "\n", encoding="utf-8")
            configurations[f"heldout{start}_{end}"] = [heldout_path]
        cooker_stats = {}
        databases = {}
        for name, corpora in configurations.items():
            sql_path, cooker_stats[name] = run_cooker(name, corpora, work)
            databases[name] = build_database(name, sql_path, work)

        metrics = {name: database_metrics(path) for name, path in databases.items()}
        baseline_pairs = text_pairs(databases["baseline"])
        baseline_size = metrics["baseline"]["database_bytes"]
        previous_pairs = baseline_pairs
        growth = []
        margins = []
        previous_count = 0
        for count in SNAPSHOTS:
            name = f"plus{count}"
            pairs = text_pairs(databases[name])
            marginal = len(pairs - previous_pairs)
            margins.append(marginal)
            block_articles = count - previous_count
            growth.append({
                "articles": count,
                **cooker_stats[name],
                **metrics[name],
                "new_pairs_vs_baseline": len(pairs - baseline_pairs),
                "marginal_new_pairs": marginal,
                "block_articles": block_articles,
                "marginal_new_pairs_per_article": marginal / block_articles,
                "database_increase_bytes": metrics[name]["database_bytes"] - baseline_size,
                "database_increase_mib": (metrics[name]["database_bytes"] - baseline_size) / 1024 / 1024,
            })
            previous_pairs = pairs
            previous_count = count

        coverage_reports = {}
        for start, end in HELDOUT_RANGES:
            heldout_pairs = text_pairs(databases[f"heldout{start}_{end}"], lexical_only=True)
            coverage_models = []
            for count, name in [(0, "baseline"), *((count, f"plus{count}") for count in SNAPSHOTS)]:
                pairs = text_pairs(databases[name], lexical_only=True)
                covered = len(pairs & heldout_pairs)
                coverage_models.append({
                    "articles": count,
                    "covered_pairs": covered,
                    "coverage": covered / len(heldout_pairs),
                    "coverage_percent": covered / len(heldout_pairs) * 100,
                    "in_sample": count >= end,
                })
            coverage_reports[f"heldout_{start}_{end}_coverage"] = {
                "heldout_articles": end - start + 1,
                "heldout_lexical_pairs": len(heldout_pairs),
                "models": coverage_models,
            }

        coverage_models = coverage_reports["heldout_201_300_coverage"]["models"]
        late_coverage_models = coverage_reports["heldout_1551_1650_coverage"]["models"]

        score_lift = []
        prior_count = 0
        for count in SNAPSHOTS:
            block = f"{prior_count + 1}–{count}"
            name = f"plus{count}"
            prior = "baseline" if prior_count == 0 else f"plus{prior_count}"
            score_lift.append({"block": block, **explicit_pair_boost(databases[name], databases[prior])})
            prior_count = count

        comparison_from, comparison_to = SNAPSHOTS[-2:]
        growth_by_count = {row["articles"]: row for row in growth}
        from_row = growth_by_count[comparison_from]
        to_row = growth_by_count[comparison_to]

        report = {
            "method": {
                "cooker": str(COOKER.relative_to(REPO)),
                "bootstrap_corpora": [str(path.relative_to(REPO)) for path in BOOTSTRAP],
                "article_snapshots": {str(count): str(path.relative_to(REPO)) for count, path in snapshots.items()},
                "bigram_prior_strength": 1000,
                "synthetic_pair_count_cap": 1,
            },
            "baseline": {**cooker_stats["baseline"], **metrics["baseline"]},
            "growth": growth,
            **coverage_reports,
            "score_lift": score_lift,
            "saturation_projection": power_law_projection(growth),
            "summary": {
                "first_100_new_pairs": margins[0],
                "baseline_heldout_coverage_percent": coverage_models[0]["coverage_percent"],
                "after_100_heldout_coverage_percent": coverage_models[1]["coverage_percent"],
                "after_200_heldout_coverage_percent": coverage_models[2]["coverage_percent"],
                "comparison_from_articles": comparison_from,
                "comparison_to_articles": comparison_to,
                "pairs_added_in_comparison": to_row["text_bigram_pairs"] - from_row["text_bigram_pairs"],
                "rows_added_in_comparison": to_row["bigram_rows"] - from_row["bigram_rows"],
                "database_mib_added_in_comparison": (
                    to_row["database_bytes"] - from_row["database_bytes"]
                ) / 1024 / 1024,
                "pairs_added_500_to_700": growth_by_count[700]["text_bigram_pairs"] - growth_by_count[500]["text_bigram_pairs"],
                "rows_added_500_to_700": growth_by_count[700]["bigram_rows"] - growth_by_count[500]["bigram_rows"],
                "database_mib_added_500_to_700": (
                    growth_by_count[700]["database_bytes"] - growth_by_count[500]["database_bytes"]
                ) / 1024 / 1024,
                "heldout_coverage_gain_500_to_700_pp": (
                    next(row["coverage_percent"] for row in late_coverage_models if row["articles"] == 700)
                    - next(row["coverage_percent"] for row in late_coverage_models if row["articles"] == 500)
                ),
            },
        }

    OUTPUT_JSON.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    OUTPUT_MD.write_text(markdown(report), encoding="utf-8")
    print(json.dumps(report["summary"], ensure_ascii=False))


if __name__ == "__main__":
    main()
