#!/usr/bin/env python3
"""Import all 29 collections into a new DB copy, skipping existing words."""
import argparse
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile

from collection_unigram_supplement import apply, source_records, load_overrides, write_list
from smart_mandarin_model import connect_readonly, file_sha256, semantic_sha256, validate_schema
from unigram_collisions import write_exclusions
from rebuild_model import add_convenience_words

ROOT = Path(__file__).resolve().parents[4]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--frequency-policy", choices=("minimum", "source"), default="minimum")
    args = parser.parse_args()
    report_path = args.output.with_suffix(".json")
    list_path = args.output.with_suffix(".tsv")
    excluded_path = args.output.with_suffix(".excluded.tsv")
    downranked_path = args.output.with_suffix(".downranked.tsv")
    partial_path = args.output.with_suffix(".partial-overlaps.tsv")
    if any(path.exists() for path in (args.output, report_path, list_path, excluded_path, downranked_path, partial_path)) or args.output.resolve() == args.source.resolve():
        parser.error("output database and report must be new paths")
    paths = sorted((ROOT / "DataSource/chichi77Collection").glob("phrase.*.tsv"))
    if not paths:
        raise ValueError("no collection sources")
    sources = source_records(paths)
    override_path = ROOT / "DataSource/AISyntheticBigram/collection-unigram-overrides.tsv"
    override_hash = file_sha256(override_path)
    overrides = load_overrides(override_path)
    manifest = json.loads((ROOT / "DataSource/AISyntheticBigram/smart-mandarin-model-manifest.json").read_text())
    original_hash = file_sha256(args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output.parent) as temporary:
        candidate = Path(temporary) / "candidate.db"
        with closing(connect_readonly(args.source)) as source, closing(sqlite3.connect(candidate)) as target:
            validate_schema(source)
            source.backup(target)
            with target:
                result = apply(target, paths, manifest["unigram_total_count"], overrides, args.frequency_policy)
                if result["totals"]["rejected"]:
                    raise ValueError(f"unresolved collection readings: {result['rejected']}")
                downranked_words = {row["word"] for row in result["downranked"]}
                convenience = [row for row in result["inserted_entries"] if row["category"] == "動漫" or row["file"] == "phrase.anime.tsv" or row["word"] in downranked_words]
                low_ranked_words = {row["word"] for row in convenience}
                people = [row for row in result["inserted_entries"] if row["word"] not in low_ranked_words and (row["category"].startswith("人名") or row["file"].startswith("phrase.people-"))]
                target.executemany("DELETE FROM unigrams WHERE current=?", [(row["word"],) for row in people])
                target.executemany("DELETE FROM unigrams WHERE current=?", [(row["word"],) for row in convenience])
            if target.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                raise ValueError("candidate integrity check failed")
        add_convenience_words(candidate, people, manifest["unigram_total_count"], maximum_count=1)
        add_convenience_words(candidate, convenience, manifest["unigram_total_count"])
        if file_sha256(args.source) != original_hash or source_records(paths) != sources or file_sha256(override_path) != override_hash:
            raise ValueError("source changed during import")
        args.output.hardlink_to(candidate)
    write_list(list_path, result.pop("inserted_entries"))
    write_exclusions(excluded_path, result.pop("exclusions"))
    write_exclusions(downranked_path, result.pop("downranked"))
    write_exclusions(partial_path, result.pop("partial_overlaps"))
    report = {"source_sha256": original_hash, "database_sha256": file_sha256(args.output),
              "semantic_sha256": semantic_sha256(args.output), "sources": sources,
              "overrides_file": override_path.name, "overrides_sha256": override_hash,
              "list_file": list_path.name, "list_sha256": file_sha256(list_path),
              "excluded_file": excluded_path.name, "excluded_sha256": file_sha256(excluded_path),
              "downranked_file": downranked_path.name, "downranked_sha256": file_sha256(downranked_path),
              "partial_overlaps_file": partial_path.name, "partial_overlaps_sha256": file_sha256(partial_path),
              "unigram_total_count": manifest["unigram_total_count"], **result}
    with report_path.open("x", encoding="utf-8") as output:
        json.dump(report, output, ensure_ascii=False, indent=2)
        output.write("\n")
    print(json.dumps({key: report[key] for key in ("database_sha256", "semantic_sha256", "totals")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
