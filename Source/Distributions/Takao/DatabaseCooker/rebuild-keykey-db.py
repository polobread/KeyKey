#!/usr/bin/env python3
"""Rebuild McBopomofo + filtered custom Unigrams and cook Bigram from 2,300 articles.

Outputs are staged separately; publication requires complete regression checks.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys

from collection_unigram_supplement import apply as apply_collection, load_overrides, source_records, write_list
from phrase_unigram_supplement import (
    POST_TRAINING, apply as apply_phrases, load as load_phrases, query_for_reading,
)
from smart_mandarin_model import file_sha256, semantic_sha256, verify_manifest
from unigram_collisions import CollisionIndex, write_exclusions, POLICY
from rebuild_model import add_cin_readings, add_convenience_words, cook, make_cin, write_lexicon
from cin_reading_frequencies import DEFAULT_SOURCE as DEFAULT_CIN_FREQUENCIES, load as load_cin_frequencies
import standalone_composition_weights

ROOT = Path(__file__).resolve().parents[4]
COOKER = Path(__file__).resolve().parent
DATA = Path("DataSource/AISyntheticBigram")
EXCLUDED_REGRESSION_CHARACTERS = "她他時十"
REGIONAL_SOURCE_FREQUENCY_FILES = frozenset({
    "phrase.taiwan.tsv", "phrase.hongkong-macao.tsv", "phrase.china.tsv",
})
STANDALONE_WEIGHTS = Path("DataSource/CINReadingFrequency/standalone-composition-weights.json")
STANDALONE_SELECTION = Path("DataSource/CINReadingFrequency/standalone-composition-review.tsv")
DB = Path("Source/Distributions/Takao/CookedDatabase/KeyKey.db")
BASE_COMMIT = "63a5a33beb5a24a23c91cd74d5ff021c65affde2"
BASE_SHA = "28b18de318ac13eece6a0631c92d5e468c8bb4c5eeba11283287493b81bcc252"


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    sys.modules[name] = result
    spec.loader.exec_module(result)
    return result


def git_bytes(path):
    return subprocess.check_output(["git", "show", f"{BASE_COMMIT}:{path.as_posix()}"], cwd=ROOT)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def apply_search(db, entries, total):
    existing = {row[0] for row in db.execute("SELECT current FROM unigrams")}
    for row in entries:
        if row["word"] not in existing:
            db.execute("INSERT INTO unigrams VALUES(?,?,?,0)",
                       (row["query"], row["word"], math.log10(row["count"] / total)))
            existing.add(row["word"])


def publication_decision(delta, maximum=30):
    if maximum < 0:
        raise ValueError("maximum regression actions must be nonnegative")
    accepted = delta["delta"] <= maximum
    scoring = f"排除人名及「{'、'.join(EXCLUDED_REGRESSION_CHARACTERS)}」後，總動作差 {delta['delta']} 次"
    return {"decision": "adopted" if accepted else "rejected", "maximum_regression_actions": maximum,
            "delta_actions": delta["delta"],
            "reason": (f"{scoring}，未超過 {maximum} 次門檻" if accepted else
                       f"{scoring}，超過 {maximum} 次門檻，保留原 DB 並回存候選與原因")}


def evaluate_rebuild(baseline, database, reference, output, jobs, maximum):
    # Freeze one set of readings and replay each article once per model.
    subprocess.run([sys.executable, "-B", str(ROOT / DATA / "benchmark-bigram-structure.py"),
                    f"before={baseline}", f"rebuilt={database}", "--reference-db", str(reference),
                    "--exclude-person-names",
                    "--exclude-characters", EXCLUDED_REGRESSION_CHARACTERS,
                    "--output", str(output), "--jobs", str(jobs)], check=True)
    comparison = json.loads((output / "comparison.json").read_text())
    delta = comparison["comparisons"]["rebuilt"]
    decision = publication_decision(delta, maximum)
    delta["passes_strict_diagnostic"] = delta.pop("passes", None)
    delta["passes"] = decision["decision"] == "adopted"
    delta["maximum_regression_actions"] = maximum
    return comparison, delta, decision


def canonical_json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def publication_file_hash(tree, relative, cache):
    """Hash generated content, excluding only known report provenance noise.

    This signature is for deciding whether review is needed, not for validating
    the published model. Real manifests retain their original byte hashes.
    """
    if relative in cache:
        return cache[relative]
    path = tree / relative
    if not path.is_file():
        return None
    if path.suffix != ".json":
        digest = file_sha256(path)
    else:
        raw = path.read_bytes()
        try:
            value = json.loads(raw)
        except (json.JSONDecodeError, UnicodeDecodeError):
            # Invalid/non-JSON evidence is still a byte change, never a no-op.
            digest = hashlib.sha256(raw).hexdigest()
        else:
            if relative in (str(DATA / "collection-unigram-validation.json"),
                            str(DATA / "rebuild-review/comparison.json")):
                identity = value.get("identity", {})
                identity.pop("engine_sha256", None)
                identity.pop("evaluator_sha256", None)
            if relative == str(DATA / "smart-mandarin-model-manifest.json"):
                # These are the only generated JSON byte hashes in this
                # manifest. Normalize their content only after checking the
                # exact file/hash binding, so a broken manifest is not hidden.
                collection = value.get("sources", {}).get("collection_unigram_supplement", {})
                references = ((collection, "report", "collection-unigram-import.json"),
                              (collection, "validation", "collection-unigram-validation.json"),
                              (value.get("rebuild", {}), "cooker_report", "custom-unigram-cooker-report.json"))
                for owner, key, filename in references:
                    if key + "_sha256" not in owner:
                        continue
                    target = str(DATA / filename)
                    if owner.get(key + "_file") != filename or not (tree / target).is_file():
                        raise ValueError(f"invalid generated JSON reference: {relative}: {key}")
                    if owner[key + "_sha256"] != file_sha256(tree / target):
                        raise ValueError(f"generated JSON hash mismatch: {relative}: {key}")
                    owner[key + "_sha256"] = publication_file_hash(tree, target, cache)
            digest = hashlib.sha256(canonical_json(value)).hexdigest()
    cache[relative] = digest
    return digest


def publication_plan(stage, root, model_files, audit_files, decision):
    """Preserve a complete candidate, but publish only substantive changes.

    Never infer a no-op from the total action delta: equal totals can contain
    a new model, changed inputs, or offsetting article/character regressions.
    """
    if decision["decision"] not in ("adopted", "rejected"):
        raise ValueError("unknown publication decision")
    selected = sorted(set(model_files + audit_files if decision["decision"] == "adopted" else audit_files))
    if any(Path(name).is_absolute() or ".." in Path(name).parts for name in selected):
        raise ValueError("generated paths must be relative to the checkout")
    previous_cache, candidate_cache = {}, {}
    candidate = {name: publication_file_hash(stage, name, candidate_cache) for name in selected}
    if any(digest is None for digest in candidate.values()):
        raise ValueError("generated publication file is missing")
    changed = [name for name in selected
               if candidate[name] != publication_file_hash(root, name, previous_cache)]
    needed = bool(changed)
    fingerprint = hashlib.sha256(canonical_json({
        "format": 1, "decision": decision["decision"], "files": candidate,
    })).hexdigest()
    return {
        "publication_needed": needed,
        "publication_fingerprint": fingerprint,
        "publication_reason": ("Substantive generated changes require review." if needed else
                               "No substantive generated changes; JSON order and execution provenance do not require a PR."),
        "substantive_files": changed,
        "files": selected if needed else [],
    }


def publish_files(stage, root, model_files, audit_files, decision, apply=False):
    files = publication_plan(stage, root, model_files, audit_files, decision)["files"]
    if apply:
        for relative in files:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(stage / relative, target)
    return files


def android_model_metadata(source, db_hash):
    """Keep Android's content-addressed cache name and verifier hash together."""
    if re.fullmatch(r"[a-f0-9]{64}", db_hash) is None:
        raise ValueError("invalid Android model SHA-256")
    names = re.findall(r'INSTALLED_NAME\s*=\s*"([^"\n]+)"', source)
    if len(names) != 1:
        raise ValueError("cannot update Android model cache name")
    old_name = names[0]
    new_name = f"KeyKey-smart-{db_hash[:16]}.db"
    updated = re.sub(r'(INSTALLED_NAME\s*=\s*")[^"\n]+(")',
                     lambda match: match[1] + new_name + match[2], source)
    updated, matches = re.subn(r'(EXPECTED_SHA256\s*=\s*")[a-f0-9]{64}(")',
                               lambda match: match[1] + db_hash + match[2], updated)
    if matches != 1:
        raise ValueError("cannot update Android model verifier hash")
    if old_name != new_name:
        pattern = r'(PREVIOUS_INSTALLED_NAMES\s*=\s*\{)(.*?)(\})'
        histories = re.findall(pattern, updated, flags=re.DOTALL)
        if len(histories) != 1:
            raise ValueError("cannot update Android model cache history")
        history = histories[0][1]
        if re.sub(r'"[^"\n]+"|[\s,]', "", history):
            raise ValueError("invalid Android model cache history")
        previous = list(dict.fromkeys([old_name, *re.findall(r'"([^"\n]+)"', history)]))
        # A model rollback may select a name already in the cleanup list. Never
        # let the installer delete the model it has just verified and opened.
        previous = [name for name in previous if name != new_name]
        body = "\n" + "".join(f'            "{name}",\n' for name in previous) + "    "
        updated = re.sub(pattern, lambda match: match[1] + body + match[3], updated, flags=re.DOTALL)
    return updated


def rebuild_associations(db, paths, work):
    exclusions = work / "people-exclusions.txt"
    people = {row[0] for path in paths if path.name.startswith("phrase.people-")
              for row in list(csv.reader(path.open(encoding="utf-8"), delimiter="\t"))[1:]}
    exclusions.write_text("\n".join(sorted(people)) + "\n", encoding="utf-8")
    db.execute("DELETE FROM associated_phrases")
    db.execute("DELETE FROM collection_names")
    db.commit()
    for path in [ROOT / "DataSource/McBopomofo/phrase.occ", *paths]:
        name = "McBopomofo" if path.suffix == ".occ" else path.stem.removeprefix("phrase.")
        lm, sql = work / f"{name}.lm", work / f"{name}.sql"
        command = ["ruby", "-E", "UTF-8", str(COOKER / "phrase-occ-to-lm.rb"), str(path)]
        if name == "McBopomofo":
            command.append(str(exclusions))
        with lm.open("wb") as output:
            subprocess.run(command, stdout=output, check=True)
        subprocess.run(["ruby", "-E", "UTF-8", str(COOKER / "AssociatedPhraseCooker.rb"), str(lm), str(sql), name], check=True)
        db.executescript(sql.read_text(encoding="utf-8"))
        names = subprocess.check_output(["ruby", "-E", "UTF-8", str(COOKER / "collection-name.rb"), str(path), name,
                                         str(ROOT / "DataSource/AssociatedPhraseCollectionNames.tsv")], text=True)
        db.executescript(names)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="new staging directory")
    parser.add_argument("--apply", action="store_true", help="copy verified generated files into this checkout")
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--training-articles", nargs=3, type=Path, metavar=("V2", "V3", "V4"),
                        help="alternate v2, v3 and v4 training files for a staged experiment")
    cin_options = parser.add_mutually_exclusive_group()
    cin_options.add_argument("--cin-reading-frequencies", type=Path, default=DEFAULT_CIN_FREQUENCIES,
                             help="optional character/reading counts (enabled by default)")
    cin_options.add_argument("--no-cin-reading-frequencies", action="store_const",
                             const=None, dest="cin_reading_frequencies", help="use the original reading-weight estimator")
    parser.add_argument("--max-regression-actions", type=int, default=30, help="adopt when total action increase is at most this value; otherwise publish audit files only")
    args = parser.parse_args()
    if args.apply and args.training_articles:
        parser.error("--training-articles requires a staged rebuild without --apply")
    finalizer = module("rebuild_finalizer", COOKER / "finalize-smart-mandarin-model.py")
    training_paths = finalizer.DEFAULT_TRAINING
    if args.training_articles:
        training_paths = tuple(path.resolve() for path in args.training_articles)
        if [path.name for path in training_paths] != [path.name for path in finalizer.DEFAULT_TRAINING]:
            parser.error("--training-articles must use the original v2, v3 and v4 filenames in order")
    if args.max_regression_actions < 0:
        parser.error("--max-regression-actions must be nonnegative")
    cin_entries = []
    if args.cin_reading_frequencies is not None:
        args.cin_reading_frequencies = args.cin_reading_frequencies.resolve()
        if not args.cin_reading_frequencies.is_relative_to(ROOT):
            parser.error("CIN frequency source must be inside the checkout for reproducible manifests")
        cin_entries = load_cin_frequencies(args.cin_reading_frequencies)
    inspector = module("rebuild_validation_corpus", ROOT / "DataSource/AISyntheticArticles/verify-typing-articles-v5.py")
    validation_corpus = inspector.inspect(inspector.DEFAULT_ARTICLES)
    output = args.output.resolve()
    if output.exists():
        parser.error("output must not already exist")
    stage = output / "tree"
    data = stage / DATA
    data.mkdir(parents=True)
    database = stage / DB
    database.parent.mkdir(parents=True)
    baseline = output / "before.db"
    shutil.copyfile(ROOT / DB, baseline)
    original_hash = file_sha256(baseline)
    database.write_bytes(git_bytes(DB))
    if file_sha256(database) != BASE_SHA:
        raise ValueError("pinned base database hash mismatch")
    reference = output / "reference.db"
    shutil.copyfile(database, reference)
    manifest = json.loads((ROOT / DATA / "smart-mandarin-model-manifest.json").read_text())
    # The pinned DB provides CIN/other non-model tables and a stable benchmark
    # reading reference only. Both language-model tables are rebuilt from source.
    cin = output / "bpmf-absolute.cin"
    make_cin(cin)
    with sqlite3.connect(database) as db:
        add_cin_readings(db, cin)
    bootstrap = cook(database, cin, output / "bootstrap", cin_reading_frequencies=args.cin_reading_frequencies)
    total = int(bootstrap["unigram_total_count"])
    collision_index = CollisionIndex()
    subprocess.run([sys.executable, "-B", str(ROOT / DATA / "build-search-trend-unigram.py"),
                    "--database", str(database), "--output", str(data / "search-trend-unigram.tsv"),
                    "--review", str(data / "search-trend-unigram-review.tsv"),
                    "--report", str(data / "search-trend-unigram-report.json")], check=True)
    paths = sorted((ROOT / "DataSource/chichi77Collection").glob("phrase.*.tsv"))
    if not paths:
        raise ValueError("no collection files")
    phrase_path = ROOT / DATA / "common-phrase-unigram.tsv"
    use_reviewed_supplements = not args.training_articles and args.cin_reading_frequencies == DEFAULT_CIN_FREQUENCIES.resolve()
    reviewed_post_training = {
        (query, entry["word"]) for entry, _, query, _ in load_phrases(phrase_path, total, POST_TRAINING)
        if entry.get("action") != "reweight"
    } if use_reviewed_supplements else frozenset()
    overrides = load_overrides(ROOT / DATA / "collection-unigram-overrides.tsv")
    with sqlite3.connect(database) as db:
        apply_search(db, finalizer.load_search_trend(data / "search-trend-unigram.tsv"), total)
        # Explicitly reviewed common phrases remain separate from scraped words.
        phrases = apply_phrases(db, phrase_path, total)
        collection = apply_collection(db, paths, total, overrides, collision_index=collision_index,
                                      reviewed_post_training=reviewed_post_training,
                                      source_frequency_files=REGIONAL_SOURCE_FREQUENCY_FILES)
        if collection["rejected"]:
            raise ValueError(f"unresolved collection readings: {collection['rejected']}")
    anime_words, people_words = set(), set()
    for path in paths:
        for row in csv.DictReader(path.open(encoding="utf-8"), delimiter="\t"):
            if row["分類"] == "動漫" or path.name == "phrase.anime.tsv":
                anime_words.add(overrides.get(row["詞"], {}).get("word", row["詞"]))
            if row["分類"].startswith("人名") or path.name.startswith("phrase.people-"):
                people_words.add(overrides.get(row["詞"], {}).get("word", row["詞"]))
    search_entries = [dict(word=row["詞"], reading=row["注音"], target_count=float(row["詞頻"]))
                      for row in csv.DictReader((data / "search-trend-unigram.tsv").open(), delimiter="\t")]
    entries = collection["inserted_entries"]
    downranked = list(csv.DictReader((data / "search-trend-unigram-downranked.tsv").open(), delimiter="\t"))
    downranked.extend(collection.pop("downranked"))
    write_exclusions(data / "custom-unigram-downranked.tsv", downranked)
    low_ranked_words = anime_words | {row["word"] for row in downranked}
    convenience_words = low_ranked_words | people_words
    convenience = [row for row in [*search_entries, *entries] if row["word"] in convenience_words]
    ordinary = [row for row in [*search_entries, *entries] if row["word"] not in convenience_words]
    custom = output / "approved-training-lexicon.tsv"
    write_lexicon(custom, [*ordinary, *(row for row in phrases if row["status"] == "inserted")])
    # Recreate the training corpus in staging; never mutate a checked-in source
    # or read validation articles while choosing tokens / Bigram frequencies.
    builder = module("rebuild_article_corpus", ROOT / DATA / "build-versioned-article-corpus.py")
    builder.OUTPUT = output / "training-2300.txt"
    builder.REPORT = output / "training-2300.json"
    builder.main(training_paths)
    cooked = cook(database, cin, output / "cooked", custom, builder.OUTPUT,
                  cin_reading_frequencies=args.cin_reading_frequencies)
    total = cooked["unigram_total_count"]
    staged_search = output / "training-search.tsv"
    write_lexicon(staged_search, [row for row in search_entries if row["word"] not in convenience_words])
    stage_manifest = output / "finalizer-input.json"
    write_json(stage_manifest, {"format": 1, "unigram_total_count": total, "sources": {}})
    refinement = finalizer.finalize(database, training_paths,
        finalizer.DEFAULT_PROTECTED, finalizer.DEFAULT_SUPPLEMENT, staged_search,
        finalizer.DEFAULT_COUNTS, stage_manifest, cin_reading_frequencies=args.cin_reading_frequencies)
    refinement.pop("database", None)
    for source in refinement["training_sources"]:
        source["file"] = Path(source["file"]).name
    add_convenience_words(database, [row for row in convenience if row["word"] not in low_ranked_words], total, maximum_count=1)
    add_convenience_words(database, [row for row in convenience if row["word"] in low_ranked_words], total)
    collection["policy"] = "Chinese aliases; text deduplication; homophones retained below existing candidates; long partial overlaps diagnostic only; anime and colliding words added after training at count <=0.01; other personal names added after training at count <=1"
    write_lexicon(data / "search-trend-unigram.tsv", search_entries)
    weights_metadata = None
    post_training_phrases = []
    with sqlite3.connect(database) as db:
        if use_reviewed_supplements:
            weights_path = ROOT / STANDALONE_WEIGHTS
            weights_hash = file_sha256(weights_path)
            weights = standalone_composition_weights.load(weights_path, total)
            selection_hash = file_sha256(ROOT / STANDALONE_SELECTION)
            if weights["selection_sha256"] != selection_hash:
                raise ValueError("reviewed composition selections differ from the weight source")
            standalone_composition_weights.apply(db, weights)
            post_training_phrases = apply_phrases(db, phrase_path, total, stage=POST_TRAINING)
            cin_keys = {(row["qstring"], row["character"]) for row in cin_entries}
            weights_metadata = {
                "file": STANDALONE_WEIGHTS.as_posix(), "sha256": weights_hash,
                "selection_file": STANDALONE_SELECTION.as_posix(), "selection_sha256": selection_hash,
                "unigram_upserts": len(weights["unigrams"]), "bigram_upserts": len(weights["bigrams"]),
                "cin_overrides": sorted(cin_keys.intersection(tuple(row["key"]) for row in weights["unigrams"])),
            }
        rebuild_associations(db, paths, output)
        if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise ValueError("rebuilt database failed integrity check")
        rows = db.execute("SELECT (SELECT COUNT(*) FROM unigrams),(SELECT COUNT(*) FROM bigrams)").fetchone()
        single_syllable_readings = db.execute(
            "SELECT COUNT(DISTINCT qstring) FROM unigrams WHERE length(qstring)=2 AND length(current)=1"
        ).fetchone()[0]
        bigram_words = {word for pair in db.execute("SELECT DISTINCT previous,current FROM bigrams") for word in pair}
        if any(row["word"] in bigram_words for row in convenience):
            raise ValueError("convenience word leaked into Bigram training")
    exclusions = list(csv.DictReader((data / "search-trend-unigram-excluded.tsv").open(), delimiter="\t"))
    exclusions.extend(collection.pop("exclusions"))
    write_exclusions(data / "custom-unigram-excluded.tsv", exclusions)
    partial_overlaps = list(csv.DictReader((data / "search-trend-unigram-partial-overlaps.tsv").open(), delimiter="\t"))
    partial_overlaps.extend(collection.pop("partial_overlaps"))
    write_exclusions(data / "custom-unigram-partial-overlaps.tsv", partial_overlaps)
    source_paths = [ROOT / "DataSource/McBopomofo/phrase.occ", ROOT / "DataSource/McBopomofo/BPMFMappings.txt",
                    ROOT / "Source/DataTables/bpmf-ext.cin",
                    *(ROOT / DATA / name for name in ("supplemental-lexicon.tsv", "numeric-unit-lexicon.tsv"))]
    if args.cin_reading_frequencies is not None:
        source_paths.append(args.cin_reading_frequencies)
        expected = cooked["cin_reading_frequencies"]["sha256"]
        if bootstrap["cin_reading_frequencies"]["sha256"] != expected or file_sha256(args.cin_reading_frequencies) != expected:
            raise ValueError("CIN frequency source changed during rebuild")
    if weights_metadata is not None:
        source_paths.extend((ROOT / STANDALONE_WEIGHTS, ROOT / STANDALONE_SELECTION))
    write_json(data / "custom-unigram-cooker-report.json", {
        "policy": POLICY, "partial_span_characters": 2, "cooker": cooked,
        "sources": [{"file": str(path.relative_to(ROOT)), "sha256": file_sha256(path)} for path in source_paths],
        "training": json.loads(builder.REPORT.read_text()), "refinement": refinement,
        "anime_words": sum(row["word"] in anime_words for row in convenience),
        "anime_policy": "excluded from training; count <=0.01; 100x below existing complete homophones, without a split-path floor",
        "anime": [row for row in convenience if row["word"] in anime_words],
        "people_sources": [path.name for path in paths if path.name.startswith("phrase.people-")],
        "people_policy": "new personal names excluded from training; count <=1, or <=0.01 when anime / colliding; existing McBopomofo words unchanged",
        "people": [row for row in convenience if row["word"] in people_words],
        "people_words": sum(row["word"] in people_words for row in convenience),
        "low_ranked_words": sorted(row["word"] for row in convenience if row["word"] in low_ranked_words),
        "convenience": convenience, "convenience_words": len(convenience),
        "collision_rows": len(downranked),
        "partial_overlap_rows": len(partial_overlaps),
        "excluded_source_rows": len({(row["source"], row["line"]) for row in exclusions}),
    })
    digest = semantic_sha256(database)
    # Preserve bytes on a genuine no-op. SQLite page layout can otherwise
    # change even when all table contents remain the same.
    if digest == semantic_sha256(baseline):
        with sqlite3.connect(database) as db:
            db.execute("ATTACH DATABASE ? AS previous", (str(baseline),))
            same = all(not db.execute(f"SELECT COUNT(*) FROM (SELECT * FROM {a}.{table} EXCEPT SELECT * FROM {b}.{table})").fetchone()[0]
                       for table in ("associated_phrases", "collection_names", '"Mandarin-bpmf-cin"')
                       for a, b in (("main", "previous"), ("previous", "main")))
        if same:
            shutil.copyfile(baseline, database)
    db_hash = file_sha256(database)
    write_list(data / "collection-unigram.tsv", collection.pop("inserted_entries"))
    with (data / "collection-unigram-skipped.tsv").open("w", encoding="utf-8", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=("word", "reason", "file", "line", "source_word"), delimiter="\t", lineterminator="\n")
        writer.writeheader(); writer.writerows(collection["skipped"])
    search_source = ROOT / DATA / "search-trend-unigram-source.txt"
    with sqlite3.connect(database) as db, (data / "search-trend-unigram-presence.tsv").open("w", encoding="utf-8", newline="") as target:
        writer = csv.writer(target, delimiter="\t", lineterminator="\n")
        writer.writerow(("word", "status", "existing_readings", "action"))
        for word in search_source.read_text().splitlines():
            count = db.execute("SELECT COUNT(*) FROM unigrams WHERE current=?", (word,)).fetchone()[0]
            excluded = any(row["source"] == search_source.name and row["word"] == word for row in exclusions)
            if not count and not excluded: raise ValueError(f"unexplained missing search term: {word}")
            writer.writerow((word, "present" if count else "excluded", count,
                             "see custom-unigram-excluded.tsv" if excluded else "adopted"))
    write_json(data / "collection-unigram-import.json", {"database_sha256": db_hash, "semantic_sha256": digest,
               "base_commit": BASE_COMMIT, "sources": source_records(paths), "unigram_total_count": total, **collection})
    comparison, delta, decision = evaluate_rebuild(
        baseline, database, reference, output / "benchmark", args.jobs, args.max_regression_actions)
    comparison.update(database_sha256=db_hash, source_database_sha256=original_hash,
                      role="fixed rebuild regression against the checked-in DB")
    write_json(data / "collection-unigram-validation.json", comparison)
    sources = manifest["sources"]
    sources.pop("standalone_composition_weights", None)
    if weights_metadata is not None:
        sources["standalone_composition_weights"] = weights_metadata
    sources.pop("cin_reading_frequencies", None)
    if args.cin_reading_frequencies is not None:
        sources["cin_reading_frequencies"] = {
            "file": os.path.relpath(args.cin_reading_frequencies, ROOT / DATA),
            "sha256": cooked["cin_reading_frequencies"]["sha256"],
            "entries": cooked["cin_reading_frequencies"]["entries"],
        }
    sources["training_articles"] = refinement["training_sources"]
    sources["protected_characters"]["sha256"] = file_sha256(finalizer.DEFAULT_PROTECTED)
    for key, filename in (("unigram_supplement", "common-unigram-supplement.tsv"), ("phrase_unigram_supplement", "common-phrase-unigram.tsv")):
        sources[key]["sha256"] = file_sha256(ROOT / DATA / filename)
    phrase_entries = [*phrases, *post_training_phrases]
    sources["phrase_unigram_supplement"].update(
        entries=len(phrase_entries), inserted=sum(r["status"] == "inserted" for r in phrase_entries),
        retained=sum(r["status"] == "retained" for r in phrase_entries),
        reweighted=sum(r["status"] == "reweighted" for r in phrase_entries), pre_training_entries=len(phrases),
        post_training_entries=len(post_training_phrases),
        policy="Pre-training reviewed phrases use the minimum score above same-reading tokenizations and retain "
               "existing probabilities. Post-training reviewed phrases use explicit counts and preserve existing "
               "backoffs and Bigram edges without adding new edges.",
    )
    trend_report = json.loads((data / "search-trend-unigram-report.json").read_text())
    trend_report["output_sha256"] = file_sha256(data / "search-trend-unigram.tsv")
    write_json(data / "search-trend-unigram-report.json", trend_report)
    trend = sources["search_trend_unigram"]
    trend.update(source_terms=trend_report["source"]["terms"], source_sha256=file_sha256(search_source),
                 entries=trend_report["custom_terms"], existing_terms_removed=trend_report["existing_terms_removed"],
                 reading_overrides=trend_report["reading_overrides"], reading_overrides_sha256=file_sha256(ROOT / DATA / "search-trend-reading-overrides.tsv"),
                 sha256=file_sha256(data / "search-trend-unigram.tsv"), review_sha256=file_sha256(data / "search-trend-unigram-review.tsv"))
    c = sources["collection_unigram_supplement"]
    c.update(files=source_records(paths), source_rows=collection["totals"]["rows"], inserted=collection["totals"]["inserted"],
             existing_rows_skipped=collection["totals"]["existing"], duplicate_rows_skipped=collection["totals"]["duplicate"], rejected=0, collision_rows_excluded=0, collision_rows_downranked=collection["totals"]["collision"], cooked=True)
    c["source_frequency_files"] = collection["source_frequency_files"]
    c.pop("user_accepted_regression", None)
    for key in ("overrides", "list", "skipped", "search_presence", "report", "validation"):
        filename = c[key + "_file"]
        path = data / filename
        c[key + "_sha256"] = file_sha256(path if path.exists() else ROOT / DATA / filename)
    manifest.update(unigram_rows=rows[0], bigram_rows=rows[1], canonical_database_sha256=db_hash, semantic_sha256=digest,
                    description="McBopomofo with deduplicated custom Unigrams; source-cooked document-frequency Bigram; personal names, anime and homophone additions inserted after training", unigram_total_count=total,
                    single_syllable_readings=single_syllable_readings,
                    validation_articles=validation_corpus["article_count"])
    manifest["rebuild"] = {"seed_commit": BASE_COMMIT, "seed_database_sha256": BASE_SHA,
                           "policy": POLICY, "validation": "collection-unigram-validation.json",
                           "excluded_file": "custom-unigram-excluded.tsv",
                           "excluded_sha256": file_sha256(data / "custom-unigram-excluded.tsv"),
                           "downranked_file": "custom-unigram-downranked.tsv",
                           "downranked_sha256": file_sha256(data / "custom-unigram-downranked.tsv"),
                           "partial_overlaps_file": "custom-unigram-partial-overlaps.tsv",
                           "partial_overlaps_sha256": file_sha256(data / "custom-unigram-partial-overlaps.tsv"),
                           "cooker_report_file": "custom-unigram-cooker-report.json",
                           "cooker_report_sha256": file_sha256(data / "custom-unigram-cooker-report.json")}
    manifest["base_database_sha256"] = refinement["base_database_sha256"]
    write_json(data / "smart-mandarin-model-manifest.json", manifest)
    # Copy read-only source evidence only to the staging tree for validation.
    evidence = stage / "DataSource"
    for source_dir in ("chichi77Collection", "McBopomofo"):
        (evidence / source_dir).symlink_to(ROOT / "DataSource" / source_dir, target_is_directory=True)
    article_evidence = evidence / "AISyntheticArticles"
    article_evidence.mkdir()
    training_evidence = {path.name: path for path in training_paths}
    for source in (ROOT / "DataSource/AISyntheticArticles").iterdir():
        (article_evidence / source.name).symlink_to(
            training_evidence.get(source.name, source), target_is_directory=source.is_dir()
        )
    for source in (ROOT / DATA).iterdir():
        if source.is_file() and not (data / source.name).exists():
            (data / source.name).symlink_to(source)
    for source in source_paths:
        destination = stage / source.relative_to(ROOT)
        if not destination.exists():
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.symlink_to(source)
    verify_manifest(database, data / "smart-mandarin-model-manifest.json")
    v5_path = Path("DataSource/AISyntheticArticles/typing-articles-v5-manifest.json")
    v5 = json.loads((ROOT / v5_path).read_text())
    v5["corpus"] = validation_corpus
    v5["evaluation"]["latest_automated_rebuild"] = {
        "database_sha256": db_hash, "semantic_sha256": digest,
        "summary": {key: value for key, value in comparison["summaries"]["rebuilt"].items()
                    if key not in ("character_corrections", "tiers", "unfiltered")},
        "comparison": comparison["comparisons"]["rebuilt"],
        "report": "../AISyntheticBigram/collection-unigram-validation.json",
    }
    v5["evaluation"]["latest_rebuild_attempt"] = {
        **decision, "validation_articles": validation_corpus["article_count"],
        "before_sha256": original_hash, "candidate_sha256": db_hash,
        "comparison": delta, "report": "../AISyntheticBigram/rebuild-review/latest.json",
    }
    # AISyntheticArticles is linked only for source verification above. Keep
    # generated metadata separate so staging can never write through that link.
    v5_output = output / "generated-v5-manifest.json"
    write_json(v5_output, v5)
    android_path = Path("Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/SharedModelDatabase.java")
    android = android_model_metadata((ROOT / android_path).read_text(), db_hash)
    generated = [p for p in stage.rglob("*") if p.is_file() and not p.is_symlink()]
    android_output = stage / android_path
    android_output.parent.mkdir(parents=True, exist_ok=True)
    android_output.write_text(android)
    generated.append(android_output)
    generated_constants = [
        ("Source/Loaders/Android-IME/README.md", r"Bigram 恰為 [\d,]+ 筆", f"Bigram 恰為 {rows[1]:,} 筆"),
    ]
    for relative, pattern, replacement in generated_constants:
        source = ROOT / relative
        text, matches = re.subn(pattern, replacement, source.read_text())
        if matches != 1:
            raise ValueError(f"cannot update generated model metadata: {relative}")
        path = stage / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        generated.append(path)
    relative_files = sorted(str(p.relative_to(stage)) for p in generated)
    (stage / v5_path).unlink()
    shutil.copyfile(v5_output, stage / v5_path)
    relative_files.append(str(v5_path))
    agents_path = Path("AGENTS.md")
    agents = (ROOT / agents_path).read_text()
    agents = re.sub(r"正式資料庫有 \*\*[\d,]+ 筆 Unigram、[\d,]+ 筆 Bigram\*\*，SHA-256 為 `[a-f0-9]+`",
                    f"正式資料庫有 **{rows[0]:,} 筆 Unigram、{rows[1]:,} 筆 Bigram**，SHA-256 為 `{db_hash}`", agents)
    (stage / agents_path).write_text(agents)
    relative_files.append(str(agents_path))
    relative_files.sort()
    review_relative = DATA / "rebuild-review"
    review_dir = stage / review_relative
    review_dir.mkdir(parents=True)
    validation_paths = sorted(inspector.DEFAULT_ARTICLES.glob("tw-corpus-*.md"))
    input_paths = [*source_paths, *paths, *validation_paths,
        ROOT / "DataSource/AssociatedPhraseCollectionNames.tsv",
        *(ROOT / DATA / name for name in ("common-unigram-supplement.tsv", "common-phrase-unigram.tsv",
          "search-trend-unigram-source.txt", "search-trend-reading-overrides.tsv",
          "collection-unigram-overrides.tsv", "basic-bigram-protected-characters.txt"))]
    inputs = {str(path.relative_to(ROOT)): file_sha256(path) for path in input_paths}
    validation_sources = [{"id": path.stem, "sha256": inputs[str(path.relative_to(ROOT))]}
                          for path in validation_paths]
    if validation_sources != comparison["identity"]["articles"]:
        raise ValueError("validation articles changed during rebuild")
    inputs.update({str(path.relative_to(ROOT)): file_sha256(source)
                   for path, source in zip(finalizer.DEFAULT_TRAINING, training_paths)})
    review = {**decision, "validation_articles": validation_corpus["article_count"], "before_sha256": original_hash, "candidate_sha256": db_hash,
              "candidate_semantic_sha256": digest, "rows": rows, "source_totals": collection["totals"],
              "regression": delta, "inputs": inputs}
    write_json(review_dir / "latest.json", review)
    write_json(review_dir / "comparison.json", comparison)
    for name in ("collection-unigram.tsv", "search-trend-unigram.tsv", "custom-unigram-excluded.tsv", "custom-unigram-downranked.tsv", "custom-unigram-partial-overlaps.tsv", "custom-unigram-cooker-report.json"):
        shutil.copyfile(data / name, review_dir / name)
    audit_files = sorted(str(p.relative_to(stage)) for p in review_dir.iterdir())
    # Rejection never overwrites the canonical DB, model manifest, adopted lists,
    # Android cache name, or platform constants. Only review evidence is published.
    model_files = relative_files
    publication = publication_plan(stage, ROOT, model_files, audit_files, decision)
    relative_files = publication["files"]
    write_json(output / "generated-files.json", relative_files)
    write_json(output / "build-report.json", {**review, "database_sha256": db_hash,
               "semantic_sha256": digest, **publication})
    if args.apply:
        if file_sha256(ROOT / DB) != original_hash:
            raise ValueError("checked-in model changed during rebuild")
        publish_files(stage, ROOT, model_files, audit_files, decision, apply=True)
    print(json.dumps({"database_sha256": db_hash, "rows": rows, **decision,
                      "publication_needed": publication["publication_needed"],
                      "publication_reason": publication["publication_reason"], "applied": args.apply}))



if __name__ == "__main__":
    main()
