#!/usr/bin/env python3
"""Apply the selected document-frequency Bigram and common-word overlay."""
from __future__ import annotations

import argparse
from collections import Counter
import csv
import json
import math
import os
from pathlib import Path
import re
import shutil
import sqlite3

from smart_mandarin_model import file_sha256, load_manifest, semantic_sha256, validate_schema
from phrase_unigram_supplement import apply as apply_phrase_supplement
from collection_unigram_supplement import apply as apply_collections, verify_sources as verify_collections, load_overrides


ROOT = Path(__file__).resolve().parents[4]
DATA = ROOT / "DataSource"
BIGRAM = DATA / "AISyntheticBigram"
ARTICLES = DATA / "AISyntheticArticles"
DEFAULT_TRAINING = tuple(ARTICLES / f"typing-articles-v{version}.jsonl" for version in (2, 3, 4))
DEFAULT_PROTECTED = BIGRAM / "basic-bigram-protected-characters.txt"
DEFAULT_SUPPLEMENT = BIGRAM / "common-unigram-supplement.tsv"
DEFAULT_SEARCH_TREND = BIGRAM / "search-trend-unigram.tsv"
DEFAULT_COUNTS = DATA / "McBopomofo/phrase.occ"
DEFAULT_MANIFEST = BIGRAM / "smart-mandarin-model-manifest.json"
EXPECTED_ARTICLES = (1650, 350, 300)
MAX_PHRASE_LENGTH = 7
PRIOR = 1000.0
HAN_RUN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\U00020000-\U000323af]+")


def load_source_counts(path: Path) -> dict[str, int]:
    counts: dict[str, int] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        fields = raw.split()
        if len(fields) == 2 and fields[1].isdigit():
            counts[fields[0]] = int(fields[1])
    if not counts:
        raise ValueError(f"{path}: no source counts")
    return counts


def load_protected_characters(path: Path) -> frozenset[str]:
    characters = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("#"):
            continue
        characters.extend(character for character in raw if not character.isspace())
    if len(characters) != len(set(characters)) or not characters:
        raise ValueError(f"{path}: protected characters must be nonempty and unique")
    return frozenset(characters)


def absolute_query(syllable: str) -> str:
    consonants = " ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ"
    medials = " ㄧㄨㄩ"
    vowels = " ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ"
    tones = " ˊˇˋ˙"
    order = 0
    used: set[int] = set()
    for character in syllable:
        for group, (symbols, scale) in enumerate(
            ((consonants, 1), (medials, 22), (vowels, 88), (tones, 1232))
        ):
            if character in symbols and character != " ":
                if group in used:
                    raise ValueError(f"invalid Bopomofo syllable: {syllable!r}")
                used.add(group)
                order += symbols.index(character) * scale
                break
        else:
            raise ValueError(f"invalid Bopomofo syllable: {syllable!r}")
    if not used or not (used - {3}):
        raise ValueError(f"invalid Bopomofo syllable: {syllable!r}")
    return chr(48 + order % 79) + chr(48 + order // 79)


def load_supplement(path: Path, counts_path: Path) -> list[dict[str, object]]:
    source_counts = load_source_counts(counts_path)
    with path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source, delimiter="\t")
        required = {
            "word", "target_count", "reading", "source_count", "competitor",
            "competitor_count", "training_occurrences", "validation_improved_articles", "reason",
        }
        if set(reader.fieldnames or ()) != required:
            raise ValueError(f"{path}: unexpected columns")
        entries = []
        for number, row in enumerate(reader, 2):
            word, competitor = row["word"], row["competitor"]
            source_count = int(row["source_count"])
            target_count = int(row["target_count"])
            competitor_count = int(row["competitor_count"])
            if source_counts.get(word) != source_count:
                raise ValueError(f"{path}:{number}: source count changed for {word}")
            if source_counts.get(competitor) != competitor_count:
                raise ValueError(f"{path}:{number}: competitor count changed for {competitor}")
            if target_count != competitor_count + 1 or target_count <= source_count:
                raise ValueError(f"{path}:{number}: target must be competitor + 1")
            syllables = row["reading"].split()
            if len(syllables) != len(word):
                raise ValueError(f"{path}:{number}: reading length mismatch")
            entries.append({
                **row,
                "query": "".join(absolute_query(syllable) for syllable in syllables),
                "source_count": source_count,
                "target_count": target_count,
                "competitor_count": competitor_count,
            })
    if not entries:
        raise ValueError(f"{path}: no supplement entries")
    return entries


def load_search_trend(path: Path) -> list[dict[str, object]]:
    with path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source, delimiter="\t")
        if tuple(reader.fieldnames or ()) != ("詞", "詞頻", "注音"):
            raise ValueError(f"{path}: expected 詞、詞頻、注音 columns")
        entries = []
        seen = set()
        for number, row in enumerate(reader, 2):
            word = row["詞"]
            count = float(row["詞頻"])
            syllables = row["注音"].split()
            if not word or word in seen or count < 0 or len(syllables) != len(word):
                raise ValueError(f"{path}:{number}: invalid or duplicate search-trend row")
            seen.add(word)
            entries.append({
                "word": word,
                "count": count,
                "query": "".join(absolute_query(syllable) for syllable in syllables),
            })
    return entries


def load_training(paths: tuple[Path, ...]) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    if len(paths) != len(EXPECTED_ARTICLES):
        raise ValueError("exactly the v2, v3 and v4 article files are required")
    articles = []
    sources = []
    for path, expected in zip(paths, EXPECTED_ARTICLES):
        rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
        if len(rows) != expected or any(not isinstance(row.get("text"), str) for row in rows):
            raise ValueError(f"{path}: expected {expected} articles with text")
        articles.extend(rows)
        sources.append({"file": str(path), "articles": len(rows), "sha256": file_sha256(path)})
    if len(articles) != 2300:
        raise ValueError("training corpus must contain exactly 2,300 articles")
    return articles, sources


def word_probabilities(database: sqlite3.Connection) -> dict[str, float]:
    masses: dict[str, float] = Counter()
    for text, probability in database.execute(
        "SELECT current,probability FROM unigrams WHERE current != ''"
    ):
        masses[text] += 10 ** probability
    return {text: math.log10(mass) for text, mass in masses.items()}


def segment(run: str, probabilities: dict[str, float]) -> list[str | None]:
    scores = [-math.inf] * (len(run) + 1)
    paths: list[list[str | None] | None] = [None] * (len(run) + 1)
    scores[0], paths[0] = 0.0, []
    for position in range(len(run)):
        if paths[position] is None:
            continue
        matched = False
        for length in range(1, min(MAX_PHRASE_LENGTH, len(run) - position) + 1):
            word = run[position:position + length]
            if word not in probabilities:
                continue
            matched = True
            candidate = scores[position] + probabilities[word]
            if candidate > scores[position + length]:
                scores[position + length] = candidate
                paths[position + length] = paths[position] + [word]
        if not matched and scores[position] > scores[position + 1]:
            scores[position + 1] = scores[position]
            paths[position + 1] = paths[position] + [None]
    return paths[-1] or []


def line_sequences(line: str, probabilities: dict[str, float]) -> list[list[str]]:
    text = line.strip()
    if not text or text.startswith("#"):
        return []

    def split_boundaries(tokens: list[str | None]) -> list[list[str]]:
        result = []
        current = []
        for token in tokens + [None]:
            if token is None:
                if current:
                    result.append(current)
                    current = []
            else:
                current.append(token)
        return result

    if re.search(r"\s", text):
        tokens: list[str | None] = []
        for field in text.split():
            for run in HAN_RUN.findall(field):
                tokens.extend([run] if run in probabilities else segment(run, probabilities))
        return split_boundaries(tokens)
    return [
        sequence
        for run in HAN_RUN.findall(text)
        for sequence in split_boundaries(segment(run, probabilities))
        if sequence
    ]


def article_document_frequency(
    articles: list[dict[str, object]], probabilities: dict[str, float]
) -> Counter[tuple[str, str]]:
    frequencies: Counter[tuple[str, str]] = Counter()
    for article in articles:
        pairs = set()
        for line in article["text"].splitlines():
            for sequence in line_sequences(line, probabilities):
                pairs.update(zip([""] + sequence, sequence + [""]))
        frequencies.update(pairs)
    return frequencies


def infer_eos_background(database: sqlite3.Connection) -> float:
    unigrams = {
        (query, text): backoff
        for query, text, backoff in database.execute(
            "SELECT qstring,current,backoff FROM unigrams"
        )
    }
    values = []
    for query, previous, probability in database.execute(
        "SELECT qstring,previous,probability FROM bigrams WHERE current='' LIMIT 1000"
    ):
        previous_query = query.split(" ", 1)[0]
        outgoing = PRIOR * (10 ** (-unigrams[(previous_query, previous)]) - 1)
        values.append((10 ** probability * (outgoing + PRIOR) - 1.0) / PRIOR)
    if not values:
        raise ValueError("cannot infer EOS background probability")
    return sum(values) / len(values)


def verify_sources(manifest: dict[str, object], paths: tuple[Path, ...], protected: Path,
                   supplement: Path, search_trend: Path) -> None:
    expected = manifest.get("sources", {})
    actual_training = [
        {"file": path.name, "articles": count, "sha256": file_sha256(path)}
        for path, count in zip(paths, EXPECTED_ARTICLES)
    ]
    if expected.get("training_articles") and expected["training_articles"] != actual_training:
        raise ValueError("training article sources differ from the selected model manifest")
    for key, path in (("protected_characters", protected), ("unigram_supplement", supplement)):
        row = expected.get(key)
        if row and row.get("sha256") != file_sha256(path):
            raise ValueError(f"{path}: source hash differs from the selected model manifest")
    row = expected.get("search_trend_unigram")
    if row and row.get("sha256") != file_sha256(search_trend):
        raise ValueError(f"{search_trend}: source hash differs from the selected model manifest")


def finalize(database_path: Path, training_paths: tuple[Path, ...], protected_path: Path,
             supplement_path: Path, search_trend_path: Path, counts_path: Path,
             manifest_path: Path) -> dict[str, object]:
    if not database_path.is_file():
        raise ValueError(f"database does not exist: {database_path}")
    manifest = load_manifest(manifest_path)
    base_digest = file_sha256(database_path)
    expected_base_digest = manifest.get("base_database_sha256")
    if expected_base_digest and base_digest != expected_base_digest:
        raise ValueError(
            f"base database SHA-256 {base_digest}; expected {expected_base_digest}"
        )
    verify_sources(manifest, training_paths, protected_path, supplement_path, search_trend_path)
    phrase_source = manifest.get("sources", {}).get("phrase_unigram_supplement")
    phrase_path = manifest_path.parent / phrase_source["file"] if phrase_source else None
    if phrase_path and file_sha256(phrase_path) != phrase_source["sha256"]:
        raise ValueError("whole-phrase supplement differs from the selected manifest")
    collection_source = manifest.get("sources", {}).get("collection_unigram_supplement")
    collection_paths = sorted((ROOT / "DataSource/chichi77Collection").glob("phrase.*.tsv")) if collection_source else []
    if collection_source:
        verify_collections(collection_paths, collection_source["files"])
        override_path = manifest_path.parent / collection_source["overrides_file"]
        if file_sha256(override_path) != collection_source["overrides_sha256"]:
            raise ValueError("collection overrides differ from manifest")
        collection_overrides = load_overrides(override_path)
    articles, training_sources = load_training(training_paths)
    protected_characters = load_protected_characters(protected_path)
    supplement = load_supplement(supplement_path, counts_path)
    search_trend = load_search_trend(search_trend_path)
    unigram_total_count = manifest["unigram_total_count"]
    temporary = database_path.with_name(f".{database_path.name}.finalize-{os.getpid()}")
    if temporary.exists():
        temporary.unlink()
    shutil.copy2(database_path, temporary)
    try:
        with sqlite3.connect(temporary) as database:
            validate_schema(database)
            base_unigrams = list(database.execute(
                "SELECT qstring,current,probability,backoff FROM unigrams ORDER BY rowid"
            ))
            base_bigram_count = database.execute("SELECT count(*) FROM bigrams").fetchone()[0]
            probabilities = word_probabilities(database)
            frequencies = article_document_frequency(articles, probabilities)
            unigram_probability = {
                (query, text): probability
                for query, text, probability, _ in base_unigrams
            }
            word_mass: Counter[str] = Counter()
            for (query, text), probability in unigram_probability.items():
                if text:
                    word_mass[text] += 10 ** probability
            text_pairs = set(database.execute("SELECT DISTINCT previous,current FROM bigrams"))
            evidence = {
                pair: 1.0 + math.log2(max(1, frequencies[pair]))
                for pair in sorted(text_pairs)
            }
            outgoing: Counter[str] = Counter()
            for (previous, _), value in evidence.items():
                outgoing[previous] += value
            eos_background = infer_eos_background(database)
            updates = []
            for rowid, query, previous, current in database.execute(
                "SELECT rowid,qstring,previous,current FROM bigrams ORDER BY rowid"
            ):
                value = evidence[(previous, current)]
                current_query = query.split(" ", 1)[1]
                if current_query == "$":
                    background, observation = eos_background, value
                else:
                    background = 10 ** unigram_probability[(current_query, current)]
                    observation = value * background / word_mass[current]
                probability = math.log10(
                    (observation + PRIOR * background) / (outgoing[previous] + PRIOR)
                )
                updates.append((probability, rowid))
                if len(updates) == 50_000:
                    database.executemany("UPDATE bigrams SET probability=? WHERE rowid=?", updates)
                    updates.clear()
            if updates:
                database.executemany("UPDATE bigrams SET probability=? WHERE rowid=?", updates)
            database.executemany("UPDATE unigrams SET backoff=? WHERE rowid=?", [
                (
                    0.0 if not outgoing[text]
                    else math.log10(PRIOR / (outgoing[text] + PRIOR)),
                    rowid,
                )
                for rowid, text in database.execute("SELECT rowid,current FROM unigrams")
            ])
            database.commit()

            database.execute(
                "ATTACH DATABASE ? AS base",
                (database_path.resolve().as_uri() + "?mode=ro",),
            )
            protected_queries = {
                query for query, text in database.execute(
                    "SELECT qstring,current FROM base.unigrams"
                )
                if len(text) == 1 and text in protected_characters
            }
            database.execute("CREATE TEMP TABLE protected_queries(qstring TEXT PRIMARY KEY)")
            database.executemany(
                "INSERT INTO protected_queries VALUES (?)",
                ((query,) for query in protected_queries),
            )
            database.execute("""
                UPDATE main.bigrams
                SET probability = (
                    SELECT base.bigrams.probability FROM base.bigrams
                    WHERE base.bigrams.qstring = main.bigrams.qstring
                      AND base.bigrams.previous = main.bigrams.previous
                      AND base.bigrams.current = main.bigrams.current)
                WHERE substr(main.bigrams.qstring, instr(main.bigrams.qstring, ' ') + 1)
                      IN (SELECT qstring FROM protected_queries)
            """)
            protected_bigram_rows = database.execute("SELECT changes()").fetchone()[0]
            database.execute("""
                UPDATE main.unigrams
                SET backoff = (
                    SELECT base.unigrams.backoff FROM base.unigrams
                    WHERE base.unigrams.qstring = main.unigrams.qstring
                      AND base.unigrams.current = main.unigrams.current)
            """)
            for entry in supplement:
                bonus = math.log10(entry["target_count"] / entry["source_count"])
                cursor = database.execute(
                    "UPDATE main.unigrams SET probability=probability+? "
                    "WHERE qstring=? AND current=?",
                    (bonus, entry["query"], entry["word"]),
                )
                if cursor.rowcount != 1:
                    raise ValueError(f"expected one unigram row for {entry['word']}")
            search_trend_inserted = 0
            search_trend_existing = 0
            for entry in search_trend:
                if not entry["count"]:
                    continue
                probability = math.log10(entry["count"] / unigram_total_count)
                existing = database.execute(
                    "SELECT probability FROM main.unigrams WHERE qstring=? AND current=?",
                    (entry["query"], entry["word"]),
                ).fetchone()
                if existing is None:
                    database.execute(
                        "INSERT INTO main.unigrams(qstring,current,probability,backoff) "
                        "VALUES(?,?,?,0.0)",
                        (entry["query"], entry["word"], probability),
                    )
                    search_trend_inserted += 1
                elif not math.isclose(existing[0], probability, rel_tol=0.0, abs_tol=1e-12):
                    raise ValueError(f"search-trend probability changed for {entry['word']}")
                else:
                    search_trend_existing += 1
            phrase_entries = apply_phrase_supplement(database, phrase_path, unigram_total_count) if phrase_path else []
            collection_result = apply_collections(database, collection_paths, unigram_total_count,
                                                 collection_overrides, collection_source["frequency_policy"]) if collection_source else None
            if collection_result and collection_result["totals"]["rejected"]:
                raise ValueError("unresolved collection readings")
            database.commit()
            database.execute("DETACH DATABASE base")

            integrity = database.execute("PRAGMA integrity_check").fetchone()[0]
            rows = {
                "unigrams": database.execute("SELECT count(*) FROM unigrams").fetchone()[0],
                "bigrams": database.execute("SELECT count(*) FROM bigrams").fetchone()[0],
            }
            if integrity != "ok" or rows["bigrams"] != base_bigram_count:
                raise ValueError(f"finalized database failed checks: {integrity}, {rows}")
            changed_unigram_probabilities = len(supplement)

        digest = semantic_sha256(temporary)
        expected_digest = manifest.get("semantic_sha256")
        if expected_digest and digest != expected_digest:
            raise ValueError(
                f"final semantic SHA-256 {digest}; expected {expected_digest}"
            )
        os.replace(temporary, database_path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise

    bands = Counter()
    for pair in text_pairs:
        frequency = frequencies[pair]
        bands["zero"] += frequency == 0
        bands["one"] += frequency == 1
        bands["two_to_four"] += 2 <= frequency <= 4
        bands["five_plus"] += frequency >= 5
    return {
        "database": str(database_path),
        "base_database_sha256": base_digest,
        "database_sha256": file_sha256(database_path),
        "semantic_sha256": digest,
        "training_articles": len(articles),
        "training_sources": training_sources,
        "formula": "1 + log2(max(1, document_frequency))",
        "prior_strength": PRIOR,
        "document_frequency_bands": dict(bands),
        "protected_characters": len(protected_characters),
        "protected_queries": len(protected_queries),
        "protected_bigram_rows": protected_bigram_rows,
        "supplemented_unigrams": changed_unigram_probabilities,
        "search_trend_inserted": search_trend_inserted,
        "search_trend_existing": search_trend_existing,
        "whole_phrase_supplement": phrase_entries,
        "collection_supplement": collection_result,
        "unigram_backoffs_changed_vs_base": 0,
        "rows": rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("--training-articles", nargs=3, type=Path, default=DEFAULT_TRAINING)
    parser.add_argument("--protected-characters", type=Path, default=DEFAULT_PROTECTED)
    parser.add_argument("--supplement", type=Path, default=DEFAULT_SUPPLEMENT)
    parser.add_argument("--search-trend", type=Path, default=DEFAULT_SEARCH_TREND)
    parser.add_argument("--counts", type=Path, default=DEFAULT_COUNTS)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        report = finalize(
            args.database,
            tuple(args.training_articles),
            args.protected_characters,
            args.supplement,
            args.search_trend,
            args.counts,
            args.manifest,
        )
        value = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(value, encoding="utf-8")
        print(value, end="")
    except (OSError, ValueError, KeyError, TypeError, sqlite3.Error, json.JSONDecodeError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
