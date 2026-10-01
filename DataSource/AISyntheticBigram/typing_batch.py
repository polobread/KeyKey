"""Fixed random article cohorts and per-article non-regression checks."""
from dataclasses import asdict
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
import csv
import hashlib
import json
from pathlib import Path
import random
import sys

from typing_cost import (CACHE, ROOT, Lexicon, Policy, evaluate, han, load_document,
                         query_for_reading, sha256, write_json)


ARTICLE_SOURCES = ((2, 1650), (3, 350), (4, 300))
COMMON_CHARACTER_WORDS = ROOT / "common-single-character-words.tsv"
RANKED_CHARACTER_WORDS = ROOT / "common-single-character-pronunciations-1500.tsv"
BASIC_CHARACTER_RANK_MAX = 100
GENERAL_CHARACTER_RANK_MAX = 1000
# v4 was generated to exercise lexicon-directed vocabulary, including engineering,
# semiconductor, medical, legal, and other specialist terms. Keep it as a diagnostic
# source instead of allowing specialist cold-start cost to select the base model.
EVALUATED_SOURCE_VERSIONS = frozenset(("v2", "v3"))


def load_population():
    pool, sources = [], []
    for version, expected_count in ARTICLE_SOURCES:
        path = ROOT.parent / "AISyntheticArticles" / f"typing-articles-v{version}.jsonl"
        rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
        prefix, width = ("tw-typing-", 5) if version == 2 else (f"tw-typing-v{version}-", 3)
        expected = [f"{prefix}{i:0{width}d}" for i in range(1, expected_count + 1)]
        if [row["prompt_id"] for row in rows] != expected:
            raise ValueError(f"{path}: article count/IDs differ from the 2300-article population")
        pool.extend({**row, "source_version": f"v{version}"} for row in rows)
        sources.append({"file": path.name, "sha256": sha256(path), "articles": len(rows)})
    return pool, sources


def article_descriptor(row):
    return {"id": row["prompt_id"], "title": row["title"], "source_version": row["source_version"],
            "category": row["category"], "text_sha256": hashlib.sha256(row["text"].encode()).hexdigest()}


def sample_articles(count=50, seed=20260926, manifest=None):
    pool, sources = load_population()
    if not 1 <= count <= len(pool):
        raise ValueError("count must be between 1 and 2300")
    picked = random.Random(seed).sample(pool, count)
    result = {"population": len(pool), "count": count, "seed": seed,
              "method": "Python random.Random(seed).sample; without replacement; exact full article bodies",
              "sources": sources, "articles": [article_descriptor(row) for row in picked]}
    if manifest:
        if manifest.exists():
            if json.loads(manifest.read_text(encoding="utf-8")) != result:
                raise ValueError(f"Frozen sample differs: {manifest}; never silently resample")
        else:
            write_json(manifest, result)  # Written before observing any scores.
    return picked, result


def partition_articles(seed=20260926, training_count=800, cohort_count=750, manifest=None):
    pool, sources = load_population()
    if training_count < 1 or cohort_count < 1 or training_count + 2 * cohort_count != len(pool):
        raise ValueError("training_count + two cohort_count values must partition all 2300 articles")
    shuffled = random.Random(seed).sample(pool, len(pool))
    groups = {
        "training": shuffled[:training_count],
        "validation": shuffled[training_count:training_count + cohort_count],
        "test": shuffled[training_count + cohort_count:],
    }
    roles = {"training": "model training only", "validation": "analysis and global parameter selection",
             "test": "final holdout; never inspect before model selection"}
    result = {"population": len(pool), "seed": seed,
              "method": "Python random.Random(seed).sample over all 2300 articles; disjoint exhaustive partition",
              "sources": sources, "cohorts": {
                  name: {"role": roles[name], "count": len(rows),
                         "articles": [article_descriptor(row) for row in rows]}
                  for name, rows in groups.items()}}
    if manifest:
        if manifest.exists():
            if json.loads(manifest.read_text(encoding="utf-8")) != result:
                raise ValueError(f"Frozen partition differs: {manifest}; never silently repartition")
        else:
            write_json(manifest, result)
    return groups, result


def cohort_manifest(partition, name):
    cohort = partition["cohorts"][name]
    return {"population": partition["population"], "count": cohort["count"], "seed": partition["seed"],
            "method": partition["method"], "role": cohort["role"], "cohort": name,
            "sources": partition["sources"], "articles": cohort["articles"]}


def load_manifest_articles(manifest):
    pool, sources = load_population()
    if manifest.get("population") != len(pool) or manifest.get("sources") != sources:
        raise ValueError("Frozen manifest does not match the current 2300-article population")
    if manifest.get("count") != len(manifest.get("articles", [])):
        raise ValueError("Frozen manifest count is incomplete")
    by_id = {row["prompt_id"]: row for row in pool}
    identifiers = [row["id"] for row in manifest["articles"]]
    if len(set(identifiers)) != len(identifiers) or not set(identifiers) <= set(by_id):
        raise ValueError("Frozen manifest has duplicate or unknown article IDs")
    articles = [by_id[identifier] for identifier in identifiers]
    if [article_descriptor(row) for row in articles] != manifest["articles"]:
        raise ValueError("Frozen manifest article metadata or content hash changed")
    return articles


def prepare_articles(articles, reference, input_database=None):
    lexicon = Lexicon(reference, input_database)
    directory = CACHE / "article-inputs"
    directory.mkdir(parents=True, exist_ok=True)
    prepared = []
    for article in articles:
        text = article["text"]
        digest = hashlib.sha256(text.encode()).hexdigest()
        path = directory / f"{article['prompt_id']}-{digest[:12]}.txt"
        path.write_text(text, encoding="utf-8")
        try:
            document = load_document(path, lexicon)
        except ValueError as error:
            raise ValueError(f"{article['prompt_id']}: {error}") from error
        prepared.append(document)
    return lexicon, prepared


def evaluate_articles(documents, database, policy, ids, label, jobs=1):
    if len(documents) != len(ids) or not documents:
        raise ValueError("All sampled article IDs must have a complete document")
    def run_one(index):
        document, identifier = documents[index], ids[index]
        try:
            return evaluate(document, database, policy)
        except ValueError as error:
            raise ValueError(f"{label} {identifier}: {error}") from error
    if jobs < 1:
        raise ValueError("jobs must be at least one")
    reports = [None] * len(documents)
    completed = 0
    if jobs == 1:
        for index in range(len(documents)):
            reports[index] = run_one(index)
            completed += 1
            if completed % 10 == 0 or completed == len(documents):
                print(f"{label}: {completed}/{len(documents)} articles", file=sys.stderr, flush=True)
        return reports
    with ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = {executor.submit(run_one, index): index for index in range(len(documents))}
        for future in as_completed(futures):
            reports[futures[future]] = future.result()
            completed += 1
            if completed % 25 == 0 or completed == len(documents):
                print(f"{label}: {completed}/{len(documents)} articles", file=sys.stderr, flush=True)
    return reports


def comparison(before, after):
    if len(before) != len(after) or not before:
        raise ValueError("Both versions must cover the same nonempty sample")
    deltas = [b["total_actions"] - a["total_actions"] for a, b in zip(before, after)]
    old, new = sum(r["total_actions"] for r in before), sum(r["total_actions"] for r in after)
    def all_character_corrections(report):
        if "character_correction_summary" in report:
            return sum(row["changes"] for row in report["character_correction_summary"])
        return sum(len(row["changes"]) * row["events"] for row in report.get("correction_summary", []))
    old_character_corrections = sum(all_character_corrections(report) for report in before)
    new_character_corrections = sum(all_character_corrections(report) for report in after)
    return {"before": old, "after": new, "delta": new - old, "reduction_percent": 100 * (old - new) / old,
            "improved_articles": sum(d < 0 for d in deltas), "unchanged_articles": sum(d == 0 for d in deltas),
            "regressed_articles": sum(d > 0 for d in deltas), "worst_regression": max(0, max(deltas)),
            "saved_actions": sum(-d for d in deltas if d < 0), "added_actions": sum(d for d in deltas if d > 0),
            "passes": new < old and all(d <= 0 for d in deltas),
            "syllables": sum(r["syllables"] for r in before),
            "corrections_before": sum(r["corrections"] for r in before),
            "corrections_after": sum(r["corrections"] for r in after),
            "character_corrections_before": old_character_corrections,
            "character_corrections_after": new_character_corrections}


def aggregate_character_corrections(reports):
    """Combine per-article character substitutions without attributing action cost twice."""
    grouped = {}
    for article_index, report in enumerate(reports):
        for row in report.get("character_correction_summary", []):
            character = row["character"]
            combined = grouped.setdefault(character, {
                "character": character, "changes": 0, "events": 0, "articles": set(), "sources": {},
            })
            combined["changes"] += row["changes"]
            combined["events"] += row["events"]
            combined["articles"].add(article_index)
            for source in row["sources"]:
                combined["sources"][source["from"]] = combined["sources"].get(source["from"], 0) + source["changes"]
    result = []
    for row in grouped.values():
        result.append({
            **{key: value for key, value in row.items() if key not in ("articles", "sources")},
            "articles": len(row["articles"]),
            "sources": [{"from": source, "changes": changes}
                        for source, changes in sorted(row["sources"].items(), key=lambda item: (-item[1], item[0]))],
        })
    return sorted(result, key=lambda row: (-row["changes"], row["character"]))


def load_common_character_words(path=COMMON_CHARACTER_WORDS):
    words = []
    seen = set()
    for number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 3 or len(fields[0]) != 1 or fields[0] in seen:
            raise ValueError(f"{path}:{number}: invalid common single-character word")
        seen.add(fields[0])
        words.append({"character": fields[0], "reading": fields[1], "group": fields[2]})
    if not words:
        raise ValueError(f"{path}: common character list is empty")
    return words


def load_common_characters(path=COMMON_CHARACTER_WORDS):
    return frozenset(row["character"] for row in load_common_character_words(path))


def common_correction_totals(reports, characters):
    """Count corrected basic characters and involved paid selections."""
    corrected = selection_events = selection_actions = 0
    for report in reports:
        if "character_correction_summary" in report:
            corrected += sum(row["changes"] for row in report["character_correction_summary"]
                             if row["character"] in characters)
        if "correction_summary" in report:
            for row in report["correction_summary"]:
                selected_changes = [change for change in row["changes"] if change["to"] in characters]
                corrected += (0 if "character_correction_summary" in report else
                              len(selected_changes) * row["events"])
                if selected_changes:
                    selection_events += row["events"]
                    selection_actions += row.get("actions", 0)
        elif "character_correction_summary" in report:
            # Older/custom reports without the event summary can overcount one
            # phrase selection across multiple target characters. Current reports
            # always take the exact event-level branch above.
            selection_events += sum(row["events"] for row in report["character_correction_summary"]
                                    if row["character"] in characters)
    return {"corrected_characters": corrected, "selection_events": selection_events,
            "selection_actions": selection_actions}


def common_corrections_by_character(reports, characters):
    counts = Counter({character: 0 for character in characters})
    for report in reports:
        if "character_correction_summary" in report:
            for row in report["character_correction_summary"]:
                if row["character"] in characters:
                    counts[row["character"]] += row["changes"]
        else:
            for row in report.get("correction_summary", []):
                for change in row["changes"]:
                    if change["to"] in characters:
                        counts[change["to"]] += row["events"]
    return dict(counts)


def character_indicator(sample, reports, words, path, definition, source_versions=None,
                        article_texts=None):
    characters = frozenset(row["character"] for row in words)
    characters_by_group = defaultdict(list)
    for row in words:
        characters_by_group[row["group"]].append(row["character"])
    if article_texts is None:
        population, _ = load_population()
        by_id = {row["prompt_id"]: row["text"] for row in population}
    else:
        by_id = article_texts
    if len(sample.get("articles", [])) != sample.get("count"):
        raise ValueError("Cannot calculate character indicator for an incomplete sample")
    selected = [index for index, row in enumerate(sample["articles"])
                if source_versions is None or row["source_version"] in source_versions]
    identifiers = [sample["articles"][index]["id"] for index in selected]
    if any(identifier not in by_id for identifier in identifiers):
        raise ValueError("Cannot calculate character indicator without every selected article text")
    if not selected:
        raise ValueError("Character indicator has no articles in its evaluation source scope")
    occurrences = sum(character in characters for identifier in identifiers for character in by_id[identifier])
    if not occurrences:
        raise ValueError("Common-character indicator has no occurrences in this sample")
    versions = {}
    for name, version_reports in reports.items():
        scoped_reports = [version_reports[index] for index in selected]
        totals = common_correction_totals(scoped_reports, characters)
        by_character = common_corrections_by_character(scoped_reports, characters)
        versions[name] = {
            **totals,
            "corrections_per_10000_occurrences": 10_000 * totals["corrected_characters"] / occurrences,
            "by_character": by_character,
            "by_group": {group: sum(by_character[character] for character in group_characters)
                         for group, group_characters in sorted(characters_by_group.items())},
        }
    return {
        "definition": definition,
        "word_list": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
        "word_list_sha256": sha256(path),
        "characters": len(characters),
        "source_versions": sorted(source_versions) if source_versions is not None else "all",
        "articles": len(selected),
        "character_groups": {group: group_characters
                             for group, group_characters in sorted(characters_by_group.items())},
        "occurrences": occurrences,
        "versions": versions,
    }


def common_character_indicator(sample, reports, path=COMMON_CHARACTER_WORDS, source_versions=None,
                               article_texts=None):
    return character_indicator(
        sample, reports, load_common_character_words(path), path,
        "Manual selection of a ChatGPT-curated core one-character word is an intelligence failure indicator; lower and broader improvement is better",
        source_versions, article_texts)


def load_ranked_character_words(path=RANKED_CHARACTER_WORDS):
    with path.open(encoding="utf-8-sig", newline="") as source:
        rows = list(csv.DictReader(source, delimiter="\t"))
    expected_fields = ["排名", "單字", "習慣讀音", "字典音", "破音字音", "全部收錄音", "判定依據", "資料來源"]
    if not rows or list(rows[0]) != expected_fields:
        raise ValueError(f"{path}: unexpected pronunciation TSV columns")
    characters = [row["單字"] for row in rows]
    if (len(rows) != 1500 or [int(row["排名"]) for row in rows] != list(range(1, 1501))
            or len(set(characters)) != len(characters)
            or any(len(character) != 1 or not han(character) for character in characters)):
        raise ValueError(f"{path}: expected ranks 1..1500 and unique single Han characters")
    bands = ((100, "0001–0100"), (300, "0101–0300"), (600, "0301–0600"),
             (1000, "0601–1000"), (1500, "1001–1500"))
    result = []
    for rank, row in enumerate(rows, 1):
        character = row["單字"]
        habitual = row["習慣讀音"].strip()
        habitual = habitual[1:] + "˙" if habitual.startswith("˙") else habitual
        query_for_reading(habitual)
        group = next(label for limit, label in bands if rank <= limit)
        result.append({
            "character": character, "reading": habitual, "group": group, "rank": rank,
            "dictionary_reading": row["字典音"], "alternate_readings": row["破音字音"],
            "all_recorded_readings": row["全部收錄音"], "rationale": row["判定依據"],
            "claimed_source": row["資料來源"],
        })
    return result


def ranked_character_indicator(sample, reports, path=RANKED_CHARACTER_WORDS, source_versions=None,
                               article_texts=None):
    return character_indicator(
        sample, reports, load_ranked_character_words(path), path,
        "Manual selection of one of 1,500 ChatGPT-ranked Traditional Chinese single characters is an intelligence failure indicator; lower and broader improvement is better",
        source_versions, article_texts)


def compare_common_character_versions(indicator, baseline, candidate):
    before = indicator["versions"][baseline]
    after = indicator["versions"][candidate]
    active = [character for character in before["by_character"]
              if before["by_character"][character] or after["by_character"][character]]
    deltas = {character: after["by_character"][character] - before["by_character"][character]
              for character in active}
    groups = []
    for group, group_characters in indicator["character_groups"].items():
        group_active = [character for character in group_characters
                        if before["by_character"][character] or after["by_character"][character]]
        group_deltas = [after["by_character"][character] - before["by_character"][character]
                        for character in group_active]
        groups.append({
            "name": group,
            "before": before["by_group"][group],
            "after": after["by_group"][group],
            "delta": after["by_group"][group] - before["by_group"][group],
            "active": len(group_active),
            "improved": sum(delta < 0 for delta in group_deltas),
            "unchanged": sum(delta == 0 for delta in group_deltas),
            "regressed": sum(delta > 0 for delta in group_deltas),
            "regressed_share": (sum(delta > 0 for delta in group_deltas) / len(group_active)
                                if group_active else 0),
        })
    regressed = sum(delta > 0 for delta in deltas.values())
    active_count = len(active)
    nonregressed_group_share = sum(row["delta"] <= 0 for row in groups) / len(groups)
    return {
        "common_character_occurrences": indicator["occurrences"],
        "common_character_corrections_before": before["corrected_characters"],
        "common_character_corrections_after": after["corrected_characters"],
        "common_character_corrections_delta": after["corrected_characters"] - before["corrected_characters"],
        "common_character_rate_before": before["corrections_per_10000_occurrences"],
        "common_character_rate_after": after["corrections_per_10000_occurrences"],
        "common_character_active": active_count,
        "common_character_improved": sum(delta < 0 for delta in deltas.values()),
        "common_character_unchanged": sum(delta == 0 for delta in deltas.values()),
        "common_character_regressed": regressed,
        "common_character_regressed_share": regressed / active_count if active_count else 0,
        "common_character_groups": groups,
        "common_character_nonregressed_group_share": nonregressed_group_share,
        "common_character_indicator_passes": (
            after["corrected_characters"] < before["corrected_characters"]
            and (regressed / active_count if active_count else 0) <= 0.20
            and nonregressed_group_share >= 0.90
        ),
    }


def prefixed_character_comparison(indicator, baseline, candidate, prefix):
    result = compare_common_character_versions(indicator, baseline, candidate)
    return {key.replace("common_character_", prefix): value for key, value in result.items()}


def compare_ranked_character_versions(indicator, baseline, candidate):
    """Prioritize ranks 1–100, stabilize 101–1000, and exclude the rare tail."""
    result = prefixed_character_comparison(indicator, baseline, candidate, "ranked_character_")
    before = indicator["versions"][baseline]["by_character"]
    after = indicator["versions"][candidate]["by_character"]
    gated = indicator["character_groups"]["0001–0100"]
    active = [character for character in gated if before[character] or after[character]]
    improved = sum(after[character] < before[character] for character in active)
    unchanged = sum(after[character] == before[character] for character in active)
    regressed = sum(after[character] > before[character] for character in active)
    before_total = sum(before[character] for character in gated)
    after_total = sum(after[character] for character in gated)
    regressed_share = regressed / len(active) if active else 0
    general = [character for group in ("0101–0300", "0301–0600", "0601–1000")
               for character in indicator["character_groups"][group]]
    general_active = [character for character in general if before[character] or after[character]]
    general_improved = sum(after[character] < before[character] for character in general_active)
    general_unchanged = sum(after[character] == before[character] for character in general_active)
    general_regressed = sum(after[character] > before[character] for character in general_active)
    general_before = sum(before[character] for character in general)
    general_after = sum(after[character] for character in general)
    general_regressed_share = general_regressed / len(general_active) if general_active else 0
    basic_passes = after_total < before_total and regressed_share <= 0.20
    general_passes = general_after <= general_before and general_regressed_share <= 0.20
    result.update({
        "ranked_character_gate_scope": "basic ranks 1–100; general ranks 101–1000; rare ranks 1001–1500 excluded",
        "ranked_character_gate_corrections_before": before_total,
        "ranked_character_gate_corrections_after": after_total,
        "ranked_character_gate_active": len(active),
        "ranked_character_gate_improved": improved,
        "ranked_character_gate_unchanged": unchanged,
        "ranked_character_gate_regressed": regressed,
        "ranked_character_gate_regressed_share": regressed_share,
        "ranked_character_basic_passes": basic_passes,
        "general_character_corrections_before": general_before,
        "general_character_corrections_after": general_after,
        "general_character_active": len(general_active),
        "general_character_improved": general_improved,
        "general_character_unchanged": general_unchanged,
        "general_character_regressed": general_regressed,
        "general_character_regressed_share": general_regressed_share,
        "general_character_indicator_passes": general_passes,
        "excluded_rare_character_scope": "ranks 1001–1500 and characters outside the ranked list",
        "ranked_character_indicator_passes": basic_passes and general_passes,
    })
    return result


def correction_actions_for_characters(report, characters):
    """Count paid selection actions once when an event fixes any in-scope character."""
    return sum(row.get("actions", 0) for row in report.get("correction_summary", [])
               if any(change["to"] in characters for change in row["changes"]))


def evaluated_action_comparison(sample, before, after, characters,
                                source_versions=EVALUATED_SOURCE_VERSIONS):
    """Compare only common/general-character corrections in non-specialist sources."""
    if len(before) != len(after) or len(before) != len(sample["articles"]):
        raise ValueError("Evaluation-scope comparison requires every sampled article")
    selected = [index for index, row in enumerate(sample["articles"])
                if row["source_version"] in source_versions]
    old = [correction_actions_for_characters(before[index], characters) for index in selected]
    new = [correction_actions_for_characters(after[index], characters) for index in selected]
    deltas = [candidate - baseline for baseline, candidate in zip(old, new)]
    saved = sum(-delta for delta in deltas if delta < 0)
    added = sum(delta for delta in deltas if delta > 0)
    source_deltas = defaultdict(list)
    category_deltas = defaultdict(list)
    for index, delta in zip(selected, deltas):
        descriptor = sample["articles"][index]
        source_deltas[descriptor["source_version"]].append(delta)
        category_deltas[descriptor.get("category", "<unknown>")].append(delta)
    improved = sum(delta < 0 for delta in deltas)
    regressed = sum(delta > 0 for delta in deltas)
    category_nonregressed_share = (sum(sum(group) <= 0 for group in category_deltas.values())
                                   / len(category_deltas))
    action_total_passes = sum(new) < sum(old)
    article_improvement_passes = improved / len(deltas) >= 0.80
    article_regression_passes = regressed / len(deltas) <= 0.20
    savings_ratio_passes = added == 0 or saved >= 10 * added
    source_passes = all(sum(group) < 0 for group in source_deltas.values())
    category_passes = category_nonregressed_share >= 0.90
    passes = all((action_total_passes, article_improvement_passes, article_regression_passes,
                  savings_ratio_passes, source_passes, category_passes))
    excluded_sources = sorted({row["source_version"] for row in sample["articles"]}
                              - set(source_versions))
    excluded_note = (f"; excluded sources {','.join(excluded_sources)}" if excluded_sources else "")
    return {
        "evaluated_scope": (
            f"ranked characters 1–{GENERAL_CHARACTER_RANK_MAX} in "
            f"sources {','.join(sorted(source_versions))}{excluded_note}; rare/unranked characters excluded"),
        "evaluated_articles": len(selected),
        "evaluated_actions_before": sum(old),
        "evaluated_actions_after": sum(new),
        "evaluated_actions_delta": sum(new) - sum(old),
        "evaluated_improved_articles": improved,
        "evaluated_unchanged_articles": sum(delta == 0 for delta in deltas),
        "evaluated_regressed_articles": regressed,
        "evaluated_saved_actions": saved,
        "evaluated_added_actions": added,
        "evaluated_source_deltas": {name: sum(group) for name, group in sorted(source_deltas.items())},
        "evaluated_category_deltas": {name: sum(group) for name, group in sorted(category_deltas.items())},
        "evaluated_category_nonregressed_share": category_nonregressed_share,
        "evaluated_action_total_passes": action_total_passes,
        "evaluated_article_improvement_passes": article_improvement_passes,
        "evaluated_article_regression_passes": article_regression_passes,
        "evaluated_savings_ratio_passes": savings_ratio_passes,
        "evaluated_source_passes": source_passes,
        "evaluated_category_passes": category_passes,
        "evaluated_actions_passes": passes,
    }


def write_comparison(path, sample, versions, reports, policy, reference, *, article_texts=None,
                     evaluation_source_versions=EVALUATED_SOURCE_VERSIONS):
    if len(sample["articles"]) != sample["count"] or any(len(reports[name]) != sample["count"] for name in versions):
        raise ValueError("Every version must have a result for every sampled article")
    baseline = next(iter(versions))
    common_indicator = common_character_indicator(
        sample, reports, source_versions=evaluation_source_versions, article_texts=article_texts)
    ranked_indicator = ranked_character_indicator(
        sample, reports, source_versions=evaluation_source_versions, article_texts=article_texts)
    evaluated_characters = frozenset(
        row["character"] for row in load_ranked_character_words()
        if row["rank"] <= GENERAL_CHARACTER_RANK_MAX)
    result = {"sample": sample, "policy": asdict(policy), "reference_sha256": sha256(reference),
              "independence": "Fresh process for every article/version; all learning disabled",
              "scope": sample.get(
                  "scope", "Sampled from the existing 2300 training-corpus articles; not an unseen-corpus generalization test"),
              "versions": {name: {"database_sha256": sha256(db),
                                  "character_correction_summary": aggregate_character_corrections(reports[name])}
                           for name, db in versions.items()},
              "comparisons": {name: comparison(reports[baseline], reports[name]) for name in versions if name != baseline},
              "indicators": {"common_single_character_words": common_indicator,
                             "ranked_single_character_words_1500": ranked_indicator},
              "articles": []}
    for name, row in result["comparisons"].items():
        row.update(compare_common_character_versions(common_indicator, baseline, name))
        row.update(compare_ranked_character_versions(ranked_indicator, baseline, name))
        row.update(evaluated_action_comparison(
            sample, reports[baseline], reports[name], evaluated_characters,
            source_versions=evaluation_source_versions))
        row["passes"] = (row["evaluated_actions_passes"] and row["common_character_indicator_passes"]
                         and row["ranked_character_indicator_passes"])
    for i, article in enumerate(sample["articles"]):
        result["articles"].append({**article, "results": {name: {key: value for key, value in reports[name][i].items()
                                                                 if key not in ("errors", "policy")} for name in versions}})
    write_json(path, result)
    lines = ["# Random article typing benchmark", "", f"Seed: {sample['seed']}; {sample['count']} / {sample['population']} full articles.",
             "", "Each article/version uses a fresh engine with learning disabled. "
             + sample.get("corpus_relation", "These texts are already part of the model corpus."),
             "", "Acceptance scope is recorded in the comparison. At least 80% of scoped articles improve, at most 20% regress, savings are at least 10× additions, every evaluated source improves, and at least 90% of categories do not regress.", "",
             "| Version | All actions | Evaluated correction actions | Improved / same / regressed | Core 83 | Basic top 100 | General 101–1000 | Pass |",
             "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |"]
    for name, row in result["comparisons"].items():
        lines.append(
            f"| {name} | {row['before']}→{row['after']} | "
            f"{row['evaluated_actions_before']}→{row['evaluated_actions_after']} | "
            f"{row['evaluated_improved_articles']} / {row['evaluated_unchanged_articles']} / {row['evaluated_regressed_articles']} | "
            f"{row['common_character_corrections_before']}→{row['common_character_corrections_after']} | "
            f"{row['ranked_character_gate_corrections_before']}→{row['ranked_character_gate_corrections_after']} | "
            f"{row['general_character_corrections_before']}→{row['general_character_corrections_after']} | {row['passes']} |")
    lines += ["", "| Article | " + " | ".join(versions) + " |", "| --- | " + " | ".join("---:" for _ in versions) + " |"]
    for row in result["articles"]:
        lines.append(f"| {row['id']} | " + " | ".join(str(row["results"][name]["total_actions"]) for name in versions) + " |")
    path.with_suffix(".md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return result
