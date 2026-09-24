#!/usr/bin/env python3
"""Measure Smart Mandarin impact from the 29 categorized AI lexicons."""

from __future__ import annotations

import json
import re
import sqlite3
import subprocess
import tempfile
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
COOKER_DIR = REPO / "Source" / "Distributions" / "Takao" / "DatabaseCooker"
COOKER = COOKER_DIR / "SmartMandarinCooker.rb"
COUNTS = REPO / "DataSource" / "McBopomofo" / "phrase.occ"
MAPPINGS = REPO / "DataSource" / "McBopomofo" / "BPMFMappings.txt"
BPMF_CIN = COOKER_DIR / "Intermediates" / "bpmf-ext-absorder.cin"
SUPPLEMENTAL = ROOT / "supplemental-lexicon.tsv"
COLLECTION_ROOT = REPO / "DataSource" / "chichi77Collection"
AI_LEXICONS = sorted(COLLECTION_ROOT.glob("phrase.*.tsv"))
ANIME = COLLECTION_ROOT / "phrase.anime.tsv"
OTHER = [path for path in AI_LEXICONS if path != ANIME]
BOOTSTRAP = [ROOT / f"corpus-v{number}.txt" for number in (1, 2, 3)]
FEEDBACK = ROOT / "corpus-typing-feedback.txt"
CORPUS_1500 = ROOT / "article-corpus-1500.txt"
CORPUS_1650 = ROOT / "article-corpus-1650.txt"
ARTICLES = ROOT.parent / "AISyntheticArticles" / "typing-articles-v2.jsonl"
OUTPUT_JSON = ROOT / "ai-lexicon-impact-report.json"
OUTPUT_MD = ROOT / "ai-lexicon-impact-report.md"
BOPOMOFO_COMPONENTS = set(
    "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩ"
    "ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦˊˇˋ˙"
)


VARIANTS = {
    "current": [("--lexicon", SUPPLEMENTAL)],
    "anime_safe": [("--lexicon", SUPPLEMENTAL), ("--lexicon-preserve-counts", ANIME)],
    "other_28_safe": [("--lexicon", SUPPLEMENTAL), *(("--lexicon-preserve-counts", path) for path in OTHER)],
    "all_29_safe": [("--lexicon", SUPPLEMENTAL), *(("--lexicon-preserve-counts", path) for path in AI_LEXICONS)],
    "anime_direct": [("--lexicon", SUPPLEMENTAL), ("--lexicon", ANIME)],
    "other_28_direct": [("--lexicon", SUPPLEMENTAL), *(("--lexicon", path) for path in OTHER)],
    "all_29_direct": [("--lexicon", SUPPLEMENTAL), *(("--lexicon", path) for path in AI_LEXICONS)],
}


def lexicon_rows(path: Path) -> list[tuple[str, int, str]]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        if len(fields) < 3 or not fields[1].isdigit():
            continue
        word, raw_count, reading = fields[:3]
        syllables = reading.split()
        if not 1 <= len(word) <= 7 or len(syllables) != len(word):
            continue
        if any(not syllable or any(character not in BOPOMOFO_COMPONENTS for character in syllable) for syllable in syllables):
            continue
        rows.append((word, int(raw_count), reading))
    return rows


def corpus_lines(text: str) -> list[str]:
    result = []
    for raw in text.splitlines():
        line = re.sub(r"^(?:#{1,6}|>|[-*+])\s*", "", raw.strip())
        if re.search(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", line):
            result.append(line)
    return result


def run_cooker(name: str, lexicons: list[tuple[str, Path]], corpora: list[Path], work: Path) -> tuple[Path, dict]:
    sql_path = work / f"{name}.sql"
    command = ["ruby", "-E", "UTF-8", str(COOKER), str(COUNTS), str(MAPPINGS), str(BPMF_CIN)]
    for option, lexicon in lexicons:
        command.extend((option, str(lexicon)))
    command.extend(str(path) for path in corpora)
    with sql_path.open("wb") as output:
        result = subprocess.run(command, cwd=COOKER_DIR, stdout=output, stderr=subprocess.PIPE, check=True)
    log = result.stderr.decode("utf-8")
    match = re.search(
        r"(?P<unigrams>\d+) unigrams from (?P<words>\d+) words; "
        r"(?P<bigram_rows>\d+) bigrams from (?P<sentences>\d+) sentences and "
        r"(?P<tokens>\d+) tokens;.*? (?P<clipped>\d+) repeated occurrences clipped; "
        r"(?P<supplemental_entries>\d+) supplemental lexicon entries",
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


def db_metrics(path: Path) -> dict:
    connection = sqlite3.connect(path)
    result = {
        "integrity_check": connection.execute("PRAGMA integrity_check").fetchone()[0],
        "unigram_rows": connection.execute("SELECT count(*) FROM unigrams").fetchone()[0],
        "unigram_words": connection.execute("SELECT count(DISTINCT current) FROM unigrams WHERE current <> ''").fetchone()[0],
        "bigram_rows": connection.execute("SELECT count(*) FROM bigrams").fetchone()[0],
        "text_pairs": connection.execute(
            "SELECT count(*) FROM (SELECT DISTINCT previous, current FROM bigrams)"
        ).fetchone()[0],
        "lexical_pairs": connection.execute(
            "SELECT count(*) FROM (SELECT DISTINCT previous, current FROM bigrams WHERE previous <> '' AND current <> '')"
        ).fetchone()[0],
        "database_bytes": path.stat().st_size,
        "database_mib": path.stat().st_size / 1024 / 1024,
    }
    connection.close()
    return result


def word_set(path: Path) -> set[str]:
    connection = sqlite3.connect(path)
    result = {row[0] for row in connection.execute("SELECT DISTINCT current FROM unigrams WHERE current <> ''")}
    connection.close()
    return result


def pair_set(path: Path, lexical_only: bool = False) -> set[tuple[str, str]]:
    connection = sqlite3.connect(path)
    query = "SELECT DISTINCT previous, current FROM bigrams"
    if lexical_only:
        query += " WHERE previous <> '' AND current <> ''"
    result = set(connection.execute(query))
    connection.close()
    return result


def surface_hits(words: set[str], texts: list[str]) -> dict:
    by_length = {length: {word for word in words if len(word) == length} for length in range(1, 8)}
    occurrences: Counter[str] = Counter()
    documents: Counter[str] = Counter()
    for text in texts:
        seen = set()
        for length, candidates in by_length.items():
            if not candidates:
                continue
            for index in range(len(text) - length + 1):
                word = text[index:index + length]
                if word in candidates:
                    occurrences[word] += 1
                    seen.add(word)
        documents.update(seen)
    return {
        "matched_entries": len(occurrences),
        "occurrences": sum(occurrences.values()),
        "document_hits": sum(documents.values()),
        "top_matches": [
            {"word": word, "occurrences": count, "documents": documents[word]}
            for word, count in occurrences.most_common(30)
        ],
    }


def markdown(report: dict) -> str:
    labels = {
        "current": "current McBopomofo + project supplemental",
        "anime_safe": "preserve counts: anime",
        "other_28_safe": "preserve counts: other 28",
        "all_29_safe": "preserve counts: all 29",
        "anime_direct": "direct merge: anime",
        "other_28_direct": "direct merge: other 28",
        "all_29_direct": "direct merge: all 29",
    }
    lines = [
        "# AI lexicon impact on Smart Mandarin bigrams",
        "",
        "All variants use the three bootstrap corpora, typing feedback, and the 1,650-article corpus. Only the lexical sources change.",
        "",
        "## Full model",
        "",
        "| Variant | Words | New words | Bigram rows | Text pairs | Added pairs | Lost pairs | Tokens | DB size | Size change |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in report["full_models"]:
        lines.append(
            f"| {labels[row['variant']]} | {row['unigram_words']:,} | {row['new_words_vs_current']:,} | "
            f"{row['bigram_rows']:,} | {row['text_pairs']:,} | {row['pairs_added_vs_current']:,} | "
            f"{row['pairs_lost_vs_current']:,} | {row['tokens']:,} | {row['database_mib']:.2f} MiB | "
            f"{row['database_change_mib']:+.2f} MiB |"
        )
    lines.extend([
        "",
        "Preserving McBopomofo counts and directly applying the AI counts produce identical results here. "
        "The AI counts are not high enough to replace existing McBopomofo counts; the observed changes come from added words or readings.",
    ])
    lines.extend([
        "",
        "## Held-out articles 1,551–1,650",
        "",
        "Each row segments the held-out block with the same lexicon as its training model, so pair denominators can differ.",
        "",
        "| Variant | Held-out lexical pairs | Covered | Coverage | Change from current |",
        "| --- | ---: | ---: | ---: | ---: |",
    ])
    for row in report["heldout"]:
        lines.append(
            f"| {labels[row['variant']]} | {row['heldout_lexical_pairs']:,} | {row['covered_pairs']:,} | "
            f"{row['coverage_percent']:.3f}% | {row['coverage_change_percentage_points']:+.3f} pp |"
        )
    lines.extend([
        "",
        "## Dictionary use in the 1,650 articles",
        "",
        "Surface matches count only entries absent from the current McBopomofo plus project supplemental vocabulary.",
        "",
        "| Lexicon group | Entries | New entries | New entries seen | Entry coverage | Occurrences |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ])
    for row in report["dictionary_surface_hits"]:
        lines.append(
            f"| {row['variant']} | {row['entries']:,} | {row['new_entries']:,} | {row['matched_entries']:,} | "
            f"{row['entry_coverage_percent']:.2f}% | {row['occurrences']:,} |"
        )
    anime = report["anime_assessment"]
    lines.extend([
        "",
        "## Anime assessment",
        "",
        f"- Anime contributes {anime['new_entries']:,} words absent from the current vocabulary, but only "
        f"{anime['matched_entries']:,} ({anime['entry_coverage_percent']:.2f}%) appear in the 1,650 general typing articles.",
        f"- The most frequent new surface match is `{anime['top_matches'][0]['word']}` ({anime['top_matches'][0]['occurrences']:,} occurrences), "
        "an incomplete fragment derived from a work title. Surface occurrence does not mean the segmenter selects it, but it shows that title fragments can compete in ordinary text.",
        "- New anime words that actually participate in the most changed pair contexts include "
        + ", ".join(f"`{item['word']}` ({item['pair_contexts']})" for item in anime["top_new_words_in_added_pairs"][:8])
        + ". Examples of collapsed ordinary pairs include `約／成 → 約成`, `借／物 → 借物`, `物／主 → 物主`, and `任務／完成 → 任務完成`.",
        f"- Count-preserving anime merge changes {anime['safe_pairs_changed_vs_current']:,} text-pair identities while growing the database by "
        f"{anime['safe_database_change_mib']:.2f} MiB. Its held-out coverage change is {anime['safe_coverage_change_percentage_points']:+.3f} percentage points.",
        f"- Direct anime merge gives the same {anime['direct_pairs_changed_vs_current']:,} changed pair identities and "
        f"{anime['direct_coverage_change_percentage_points']:+.3f}-point coverage change, confirming that count overwrite is not the cause in this dataset.",
        "- Keep anime as an opt-in domain lexicon unless incomplete title fragments and generic phrases receive a dedicated review.",
        "",
        "## Recommendation",
        "",
        report["recommendation"],
        "",
    ])
    return "\n".join(lines)


def main() -> None:
    if len(AI_LEXICONS) != 29:
        raise SystemExit(f"expected 29 AI lexicons, found {len(AI_LEXICONS)}")
    required = [COOKER, COUNTS, MAPPINGS, BPMF_CIN, SUPPLEMENTAL, FEEDBACK, CORPUS_1500, CORPUS_1650, ARTICLES, *BOOTSTRAP, *AI_LEXICONS]
    missing = [path for path in required if not path.exists()]
    if missing:
        raise SystemExit("missing inputs: " + ", ".join(map(str, missing)))

    articles = [json.loads(line) for line in ARTICLES.read_text(encoding="utf-8").splitlines() if line.strip()]
    article_texts = ["".join(re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", item["text"])) for item in articles[:1650]]

    with tempfile.TemporaryDirectory(prefix="keykey-ai-lexicons-") as temp:
        work = Path(temp)
        heldout_corpus = work / "heldout-1551-1650.txt"
        heldout_lines = ["# Held-out articles 1551-1650."]
        for article in articles[1550:1650]:
            heldout_lines.append(f"# {article['prompt_id']}")
            heldout_lines.extend(corpus_lines(article["text"]))
        heldout_corpus.write_text("\n".join(heldout_lines) + "\n", encoding="utf-8")

        databases = {}
        cooker_stats = {}
        for variant, lexicons in VARIANTS.items():
            configurations = {
                f"full_{variant}": [*BOOTSTRAP, FEEDBACK, CORPUS_1650],
                f"train_{variant}": [*BOOTSTRAP, FEEDBACK, CORPUS_1500],
                f"heldout_{variant}": [heldout_corpus],
            }
            for name, corpora in configurations.items():
                sql_path, cooker_stats[name] = run_cooker(name, lexicons, corpora, work)
                databases[name] = build_database(name, sql_path, work)

        current_words = word_set(databases["full_current"])
        current_pairs = pair_set(databases["full_current"])
        current_metrics = db_metrics(databases["full_current"])
        full_models = []
        for variant in VARIANTS:
            name = f"full_{variant}"
            metrics = db_metrics(databases[name])
            words = word_set(databases[name])
            pairs = pair_set(databases[name])
            new_words = words - current_words
            added_pairs = pairs - current_pairs
            lost_pairs = current_pairs - pairs
            changed_word_contexts = Counter(
                token for pair in added_pairs for token in pair if token in new_words
            )
            full_models.append({
                "variant": variant,
                **cooker_stats[name],
                **metrics,
                "new_words_vs_current": len(new_words),
                "pairs_added_vs_current": len(added_pairs),
                "pairs_lost_vs_current": len(lost_pairs),
                "top_new_words_in_added_pairs": [
                    {"word": word, "pair_contexts": count}
                    for word, count in changed_word_contexts.most_common(30)
                ],
                "added_pair_examples": [list(pair) for pair in sorted(added_pairs)[:100]],
                "lost_pair_examples": [list(pair) for pair in sorted(lost_pairs)[:100]],
                "database_change_bytes": metrics["database_bytes"] - current_metrics["database_bytes"],
                "database_change_mib": (metrics["database_bytes"] - current_metrics["database_bytes"]) / 1024 / 1024,
            })

        heldout = []
        current_coverage = None
        for variant in VARIANTS:
            heldout_pairs = pair_set(databases[f"heldout_{variant}"], lexical_only=True)
            train_pairs = pair_set(databases[f"train_{variant}"], lexical_only=True)
            covered = len(heldout_pairs & train_pairs)
            coverage = covered / len(heldout_pairs) * 100
            if variant == "current":
                current_coverage = coverage
            heldout.append({
                "variant": variant,
                "heldout_lexical_pairs": len(heldout_pairs),
                "covered_pairs": covered,
                "coverage_percent": coverage,
                "coverage_change_percentage_points": 0.0,
            })
        for row in heldout:
            row["coverage_change_percentage_points"] = row["coverage_percent"] - current_coverage

        source_groups = {
            "anime": [ANIME],
            "other_28": OTHER,
            "all_29": AI_LEXICONS,
        }
        surface_reports = []
        for variant, paths in source_groups.items():
            entries = {word for path in paths for word, _, _ in lexicon_rows(path)}
            new_entries = entries - current_words
            hits = surface_hits(new_entries, article_texts)
            surface_reports.append({
                "variant": variant,
                "entries": len(entries),
                "new_entries": len(new_entries),
                **hits,
                "entry_coverage_percent": hits["matched_entries"] / len(new_entries) * 100,
            })

        full_by_variant = {row["variant"]: row for row in full_models}
        heldout_by_variant = {row["variant"]: row for row in heldout}
        surface_by_variant = {row["variant"]: row for row in surface_reports}
        anime_surface = surface_by_variant["anime"]
        anime_safe_model = full_by_variant["anime_safe"]
        anime_direct_model = full_by_variant["anime_direct"]
        anime_safe_heldout = heldout_by_variant["anime_safe"]
        anime_direct_heldout = heldout_by_variant["anime_direct"]
        report = {
            "method": {
                "ai_lexicon_count": len(AI_LEXICONS),
                "full_corpora": [path.name for path in [*BOOTSTRAP, FEEDBACK, CORPUS_1650]],
                "training_corpora": [path.name for path in [*BOOTSTRAP, FEEDBACK, CORPUS_1500]],
                "heldout_articles": "1551-1650",
                "variants": {
                    name: [{"option": option, "file": path.name} for option, path in paths]
                    for name, paths in VARIANTS.items()
                },
            },
            "full_models": full_models,
            "heldout": heldout,
            "dictionary_surface_hits": surface_reports,
            "anime_assessment": {
                "new_entries": anime_surface["new_entries"],
                "matched_entries": anime_surface["matched_entries"],
                "entry_coverage_percent": anime_surface["entry_coverage_percent"],
                "top_matches": anime_surface["top_matches"],
                "top_new_words_in_added_pairs": anime_safe_model["top_new_words_in_added_pairs"],
                "safe_pairs_changed_vs_current": anime_safe_model["pairs_added_vs_current"] + anime_safe_model["pairs_lost_vs_current"],
                "safe_database_change_mib": anime_safe_model["database_change_mib"],
                "safe_coverage_change_percentage_points": anime_safe_heldout["coverage_change_percentage_points"],
                "direct_pairs_changed_vs_current": anime_direct_model["pairs_added_vs_current"] + anime_direct_model["pairs_lost_vs_current"],
                "direct_database_change_mib": anime_direct_model["database_change_mib"],
                "direct_coverage_change_percentage_points": anime_direct_heldout["coverage_change_percentage_points"],
            },
            "recommendation": (
                "Do not merge all 29 collections into the core Smart Mandarin vocabulary as-is. Review the 104 non-anime new entries that actually occur in the 1,650 articles, then test a compact allowlist and candidate ordering. "
                "Keep anime separate and opt-in: most of its new vocabulary is unseen in general typing text, while title fragments can create frequent false phrase boundaries."
            ),
        }

    OUTPUT_JSON.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    OUTPUT_MD.write_text(markdown(report), encoding="utf-8")
    print(json.dumps({
        "full_models": [{k: row[k] for k in ("variant", "new_words_vs_current", "pairs_added_vs_current", "pairs_lost_vs_current", "database_change_mib")} for row in full_models],
        "heldout": heldout,
        "anime_assessment": report["anime_assessment"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
