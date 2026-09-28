#!/usr/bin/env python3
"""Shared Smart Mandarin model validation and semantic fingerprint helpers."""
from __future__ import annotations

import hashlib
import json
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


def verify_source_hashes(manifest: dict[str, object], manifest_path: Path) -> None:
    bigram = manifest_path.resolve().parent
    articles = bigram.parent / "AISyntheticArticles"
    sources = manifest["sources"]
    checks = []
    for row in sources["training_articles"]:
        checks.append((articles / row["file"], row["sha256"]))
    for key in ("protected_characters", "unigram_supplement"):
        row = sources[key]
        checks.append((bigram / row["file"], row["sha256"]))
    trend = sources["search_trend_unigram"]
    checks.extend((
        (bigram / trend["source_file"], trend["source_sha256"]),
        (bigram / trend["file"], trend["sha256"]),
        (bigram / trend["review_file"], trend["review_sha256"]),
        (bigram / "search-trend-reading-overrides.tsv", trend["reading_overrides_sha256"]),
    ))
    for path, expected in checks:
        actual = file_sha256(path)
        if actual != expected:
            raise ValueError(f"{path}: SHA-256 {actual}; expected {expected}")


def verify_manifest(path: Path, manifest_path: Path) -> dict[str, object]:
    manifest = load_manifest(manifest_path)
    verify_source_hashes(manifest, manifest_path)
    with connect_readonly(path) as database:
        validate_schema(database)
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
