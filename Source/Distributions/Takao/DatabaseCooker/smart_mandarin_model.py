#!/usr/bin/env python3
"""Shared Smart Mandarin model validation and semantic fingerprint helpers."""
from __future__ import annotations

import hashlib
import json
import csv
import math
from pathlib import Path
import sqlite3


TABLES = {
    "unigrams": ("qstring", "current", "probability", "backoff"),
    "bigrams": ("qstring", "previous", "current", "probability"),
}


def file_sha256(path: Path) -> str:
    with path.open("rb") as source:
        if hasattr(hashlib, "file_digest"):
            return hashlib.file_digest(source, "sha256").hexdigest()
        return hashlib.sha256(source.read()).hexdigest()


def connect_readonly(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)


def validate_schema(database: sqlite3.Connection) -> None:
    for table, expected in TABLES.items():
        actual = tuple(row[1] for row in database.execute(f"PRAGMA table_info({table})"))
        if actual != expected:
            raise ValueError(f"invalid {table} schema: {actual}; expected {expected}")


def _fingerprint_value(value: object) -> bytes:
    if isinstance(value, float):
        # Ruby and Python libm can differ below meaningful model precision.
        # Eleven significant digits still detects score changes far smaller
        # than any candidate-order margin observed in this model.
        value = format(value, ".11g")
    elif value is None:
        value = ""
    data = str(value).encode("utf-8")
    return len(data).to_bytes(8, "big") + data


def semantic_sha256(path: Path) -> str:
    digest = hashlib.sha256(b"KeyKey Smart Mandarin semantic model v1\0")
    with connect_readonly(path) as database:
        validate_schema(database)
        queries = {
            "unigrams": (
                "SELECT qstring,current,probability,backoff FROM unigrams "
                "ORDER BY qstring,current,probability,backoff"
            ),
            "bigrams": (
                "SELECT qstring,previous,current,probability FROM bigrams "
                "ORDER BY qstring,previous,current,probability"
            ),
        }
        for table in ("unigrams", "bigrams"):
            digest.update(table.encode("ascii") + b"\0")
            for row in database.execute(queries[table]):
                for value in row:
                    digest.update(_fingerprint_value(value))
    return digest.hexdigest()


def load_manifest(path: Path) -> dict[str, object]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("format") != 1:
        raise ValueError(f"{path}: unsupported model manifest format")
    return manifest


def verify_source_hashes(manifest: dict[str, object], manifest_path: Path) -> dict[str, str]:
    bigram = manifest_path.resolve().parent
    articles = bigram.parent / "AISyntheticArticles"
    sources = manifest["sources"]
    # A reviewed over-threshold rebuild can leave new editable sources beside
    # the previous verified DB. Bind that exception to both the exact old DB
    # and every current source hash; later edits require another rebuild.
    pending_inputs = {}
    review_path = bigram / "rebuild-review/latest.json"
    if review_path.is_file():
        review = json.loads(review_path.read_text(encoding="utf-8"))
        if (review.get("decision") == "rejected"
                and review.get("before_sha256") == manifest.get("canonical_database_sha256")):
            pending_inputs = review["inputs"]
            for relative, expected in pending_inputs.items():
                if file_sha256(bigram.parent.parent / relative) != expected:
                    raise ValueError(f"source changed since rejected rebuild: {relative}")
    checks = []
    for row in sources["training_articles"]:
        checks.append((articles / row["file"], row["sha256"]))
    for key in ("protected_characters", "unigram_supplement"):
        row = sources[key]
        checks.append((bigram / row["file"], row["sha256"]))
    phrase = sources.get("phrase_unigram_supplement")
    if phrase:
        checks.append((bigram / phrase["file"], phrase["sha256"]))
        checks.append((bigram / phrase["validation_file"], phrase["validation_sha256"]))
    collection = sources.get("collection_unigram_supplement")
    if collection:
        from collection_unigram_supplement import source_records
        paths = sorted((bigram.parent / "chichi77Collection").glob("phrase.*.tsv"))
        if source_records(paths) != collection["files"]:
            current = {str(path.relative_to(bigram.parent.parent)): file_sha256(path) for path in paths}
            recorded = {path: digest for path, digest in pending_inputs.items()
                        if path.startswith("DataSource/chichi77Collection/phrase.")}
            if not pending_inputs or current != recorded:
                raise ValueError("collection sources differ from model and rejected-build evidence")
        checks.append((bigram / collection["report_file"], collection["report_sha256"]))
        checks.append((bigram / collection["validation_file"], collection["validation_sha256"]))
        checks.append((bigram / collection["overrides_file"], collection["overrides_sha256"]))
        checks.append((bigram / collection["list_file"], collection["list_sha256"]))
        checks.append((bigram / collection["skipped_file"], collection["skipped_sha256"]))
        checks.append((bigram / collection["search_presence_file"], collection["search_presence_sha256"]))
    trend = sources["search_trend_unigram"]
    rebuild = manifest.get("rebuild", {})
    for key in ("excluded", "downranked", "partial_overlaps", "cooker_report"):
        if key + "_file" in rebuild:
            checks.append((bigram / rebuild[key + "_file"], rebuild[key + "_sha256"]))
    if rebuild.get("cooker_report_file"):
        report = json.loads((bigram / rebuild["cooker_report_file"]).read_text(encoding="utf-8"))
        checks.extend((bigram.parent.parent / row["file"], row["sha256"]) for row in report["sources"])
    checks.extend((
        (bigram / trend["source_file"], trend["source_sha256"]),
        (bigram / trend["file"], trend["sha256"]),
        (bigram / trend["review_file"], trend["review_sha256"]),
        (bigram / "search-trend-reading-overrides.tsv", trend["reading_overrides_sha256"]),
    ))
    for path, expected in checks:
        actual = file_sha256(path)
        if actual != expected:
            relative = str(path.relative_to(bigram.parent.parent))
            if pending_inputs.get(relative) != actual:
                raise ValueError(f"{path}: SHA-256 {actual}; expected {expected}")
    return pending_inputs


def verify_manifest(path: Path, manifest_path: Path) -> dict[str, object]:
    manifest = load_manifest(manifest_path)
    pending_inputs = verify_source_hashes(manifest, manifest_path)
    with connect_readonly(path) as database:
        validate_schema(database)
        missing_phonetic = database.execute('''
            SELECT qstring,current FROM (
                SELECT qstring,current,ROW_NUMBER() OVER (
                    PARTITION BY qstring ORDER BY probability DESC,rowid) AS rank
                FROM unigrams WHERE length(qstring)=2 AND length(current)=1
            ) AS firsts WHERE rank=1 AND NOT EXISTS (
                SELECT 1 FROM "Mandarin-bpmf-cin" AS cin
                WHERE cin.key=firsts.qstring AND cin.value=firsts.current)
        ''').fetchall()
        if missing_phonetic:
            raise ValueError(f"single-syllable first choices missing from CIN: {missing_phonetic[:5]}")
        # All requested search terms must remain present even after subsequent
        # collection imports. Existing entries must not be inserted again.
        source = manifest_path.parent / manifest["sources"]["search_trend_unigram"]["source_file"]
        search_words = [line.strip() for line in source.read_text(encoding="utf-8").splitlines() if line.strip()]
        if pending_inputs:
            presence = manifest["sources"]["collection_unigram_supplement"]["search_presence_file"]
            with (manifest_path.parent / presence).open(encoding="utf-8") as stream:
                search_words = [row["word"] for row in csv.DictReader(stream, delimiter="\t")]
        expected_terms = manifest["sources"]["search_trend_unigram"]["source_terms"]
        if len(search_words) != expected_terms:
            raise ValueError(f"search trend source must contain {expected_terms} rows")
        existing = {row[0] for row in database.execute("SELECT current FROM unigrams")}
        missing = set(search_words) - existing
        rebuild = manifest.get("rebuild", {})
        if rebuild.get("excluded_file"):
            with (manifest_path.parent / rebuild["excluded_file"]).open(encoding="utf-8") as stream:
                exclusions = list(csv.DictReader(stream, delimiter="\t"))
            missing -= {row["word"] for row in exclusions if row["source"] == source.name
                        and row["reason"] in ("full_homophone", "two_character_homophone")}
        if missing:
            raise ValueError(f"search trend terms missing from unigrams: {sorted(missing)}")
        collection = manifest["sources"].get("collection_unigram_supplement")
        if collection:
            from phrase_unigram_supplement import query_for_reading
            with (manifest_path.parent / collection["list_file"]).open(encoding="utf-8") as source:
                entries = list(csv.DictReader(source, delimiter="\t"))
            if len(entries) != collection["inserted"] or len({row["word"] for row in entries}) != len(entries):
                raise ValueError("collection list count or uniqueness mismatch")
            for row in entries:
                query = "".join(query_for_reading(value) for value in row["reading"].split())
                matches = list(database.execute("SELECT probability,backoff FROM unigrams WHERE qstring=? AND current=?", (query, row["word"])))
                expected = math.log10(float(row["target_count"]) / manifest["unigram_total_count"])
                if len(matches) != 1 or not math.isclose(matches[0][0], expected, rel_tol=0, abs_tol=1e-12) or (not collection.get("cooked") and matches[0][1] != 0):
                    raise ValueError(f"collection list entry differs from DB: {row['word']}")
        if rebuild.get("cooker_report_file"):
            from unigram_collisions import CollisionIndex
            index = CollisionIndex(manifest_path.parent.parent / "McBopomofo/phrase.occ",
                                   manifest_path.parent.parent / "McBopomofo/BPMFMappings.txt")
            adopted = [(row["word"], row["reading"]) for row in entries] if collection else []
            trend = manifest["sources"]["search_trend_unigram"]
            with (manifest_path.parent / trend["file"]).open(encoding="utf-8") as stream:
                adopted.extend((row["詞"], row["注音"]) for row in csv.DictReader(stream, delimiter="\t"))
            if len(adopted) != len({word for word, _ in adopted}):
                raise ValueError("duplicate word across adopted custom sources")
            report = json.loads((manifest_path.parent / rebuild["cooker_report_file"]).read_text(encoding="utf-8"))
            convenience = report.get("convenience", report["anime"])
            convenience_words = {row["word"] for row in convenience}
            people_words = {row["word"] for row in report.get("people", [])}
            low_ranked_words = set(report.get("low_ranked_words", convenience_words))
            for word, reading in adopted:
                if not pending_inputs and word in index.words:
                    raise ValueError(f"custom word duplicates McBopomofo: {word}")
                if not pending_inputs and index.ranking_conflicts(word, reading) and word not in convenience_words:
                    raise ValueError(f"colliding custom word is not a low-ranked candidate: {word}")
            bigram_words = {word for pair in database.execute("SELECT DISTINCT previous,current FROM bigrams") for word in pair}
            for row in convenience:
                score = math.log10(float(row["target_count"]) / manifest["unigram_total_count"])
                actual = database.execute("SELECT probability,backoff,qstring FROM unigrams WHERE current=?", (row["word"],)).fetchall()
                if len(actual) != 1 or not math.isclose(actual[0][0], score, abs_tol=1e-12) or actual[0][1] != 0:
                    raise ValueError(f"convenience score mismatch: {row['word']}")
                limit = 1 if row["word"] in people_words and row["word"] not in low_ranked_words else 0.01
                if float(row["target_count"]) > limit:
                    raise ValueError(f"convenience word exceeds low-frequency limit: {row['word']}")
                for other, probability in database.execute("SELECT current,probability FROM unigrams WHERE qstring=?", (actual[0][2],)):
                    if other not in convenience_words and score > probability - 2.0 + 1e-12:
                        raise ValueError(f"convenience word outranks ordinary homophone: {row['word']} / {other}")
                if row["word"] in bigram_words:
                    raise ValueError(f"convenience word has Bigram edges: {row['word']}")
        integrity = database.execute("PRAGMA integrity_check").fetchone()[0]
        counts = {
            table: database.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
            for table in TABLES
        }
    expected_counts = {
        "unigrams": manifest["unigram_rows"],
        "bigrams": manifest["bigram_rows"],
    }
    if integrity != "ok" or counts != expected_counts:
        raise ValueError(
            f"{path}: integrity={integrity}, rows={counts}; expected {expected_counts}"
        )
    actual_digest = semantic_sha256(path)
    expected_digest = manifest.get("semantic_sha256")
    if expected_digest and actual_digest != expected_digest:
        raise ValueError(
            f"{path}: semantic SHA-256 {actual_digest}; expected {expected_digest}"
        )
    binary_digest = file_sha256(path)
    expected_binary_digest = manifest.get("canonical_database_sha256")
    if expected_binary_digest and binary_digest != expected_binary_digest:
        raise ValueError(
            f"{path}: file SHA-256 {binary_digest}; expected canonical {expected_binary_digest}"
        )
    return {
        "database": str(path),
        "integrity": integrity,
        "rows": counts,
        "database_sha256": binary_digest,
        "semantic_sha256": actual_digest,
    }
