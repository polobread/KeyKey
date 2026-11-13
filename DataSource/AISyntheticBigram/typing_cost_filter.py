"""Exclude annotated target costs while preserving engine input and selections."""
from collections import Counter
from copy import deepcopy
from decimal import Decimal, InvalidOperation
from pathlib import Path

from typing_cost import han, key_count, summarize_corrections

DATA_SOURCE = Path(__file__).resolve().parents[1]
DEFAULT_COUNTS = DATA_SOURCE / "McBopomofo/phrase.occ"
POLICY = {
    "definition": "explicit single-character source count equals zero; last occurrence wins",
    "context": "preserve original text, readings, engine states and selections",
    "excluded": "phonetic keys; correction events whose corrected targets are all zero-count",
    "mixed_event": "keep full cost when any corrected target has positive or missing count",
    "retained": "literal keys and commits; missing counts; all positive fractional counts",
}


PERSON_NAME_POLICY = {
    "definition": "person-name spans at exact positions in each article",
    "context": POLICY["context"],
    "excluded": "phonetic keys; correction events whose corrected targets are all marked",
    "mixed_event": "keep full cost when any corrected target remains in scope",
    "retained": "literal keys and commits",
}


CHARACTER_POLICY = {
    **PERSON_NAME_POLICY,
    "definition": "explicitly listed Han characters at every target occurrence",
}


def load_zero_count_characters(path):
    counts = {}
    for number, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        parts = line.split()
        if not parts or line.lstrip().startswith("#"):
            continue
        try:
            if len(parts) != 2:
                raise ValueError
            count = Decimal(parts[1])
            if not count.is_finite() or count < 0:
                raise ValueError
        except (InvalidOperation, ValueError):
            raise ValueError(f"{path}:{number}: expected word and finite nonnegative count") from None
        counts[parts[0]] = count
    return {word for word, count in counts.items() if len(word) == 1 and han(word) and count == 0}


def character_positions(document, characters):
    return {(block_index, index)
            for block_index, block in enumerate(document) if block["han"]
            for index, character in enumerate(block["text"]) if character in characters}


zero_count_positions = character_positions


def exclude_zero_count_actions(report, document, zero_characters):
    return exclude_position_actions(report, document, zero_count_positions(document, zero_characters),
                                    "zero_frequency")


def exclude_position_actions(report, document, mask, kind):
    if "counted_syllables" in report:
        raise ValueError("Report already excludes target costs")
    result = deepcopy(report)
    positions = []
    for block_index, block in enumerate(document):
        if not block["han"]:
            continue
        if len(block["text"]) != len(block["queries"]):
            raise ValueError("Target text/readings length mismatch")
        for index, (character, query) in enumerate(zip(block["text"], block["queries"])):
            if (block_index, index) in mask:
                positions.append({"block": block_index, "index": index, "character": character,
                                  "query": query, "phonetic_keys": key_count(query)})
    if report["syllables"] != sum(len(b["queries"]) for b in document if b["han"]):
        raise ValueError("Report syllables differ from frozen document")
    if len(positions) != len(mask):
        raise ValueError("Excluded positions differ from frozen document")
    removed = Counter(phonetic_keys=sum(p["phonetic_keys"] for p in positions))
    kept_errors, excluded_events = [], []
    for event in result["errors"]:
        if not event["changes"] or event["action_count"] != sum(event["actions"].values()):
            raise ValueError("Invalid correction event")
        block_index = event["block"]
        for change in event["changes"]:
            if document[block_index]["text"][change["index"]] != change["to"]:
                raise ValueError("Correction target differs from frozen document")
        ignored = [c for c in event["changes"] if (block_index, c["index"]) in mask]
        kept = [c for c in event["changes"] if (block_index, c["index"]) not in mask]
        if not kept:
            removed.update(event["actions"])
            excluded_events.append(event)
        else:
            if ignored:
                event[f"excluded_{kind}_changes"] = ignored
                event["changes"] = kept
            kept_errors.append(event)
    if sum(e["action_count"] for e in report["errors"]) != report["correction_actions"]:
        raise ValueError("Raw correction totals differ from events")
    counts = dict(result["actions"])
    for key, value in removed.items():
        counts[key] -= value
        if counts[key] < 0:
            raise ValueError("Excluded costs exceed measured actions")
    correction_actions, summary, characters = summarize_corrections(kept_errors)
    if correction_actions != report["correction_actions"] - sum(e["action_count"] for e in excluded_events):
        raise ValueError("Correction accounting differs after exclusion")
    result.update(
        total_actions=sum(counts.values()), actions=counts, corrections=len(kept_errors),
        correction_actions=correction_actions, errors=kept_errors,
        correction_summary=summary, character_correction_summary=characters,
        counted_syllables=report["syllables"] - len(positions))
    result[f"{kind}_exclusion"] = {
        "positions": positions, "excluded_syllables": len(positions),
        "removed_actions": dict(removed), "removed_total_actions": sum(removed.values()),
        "excluded_correction_events": excluded_events,
        "unfiltered_total_actions": report["total_actions"],
        "unfiltered_correction_actions": report["correction_actions"],
    }
    return result


def unfiltered_metrics(report, kind):
    """Recover original diagnostics from a cost-filtered trace."""
    exclusion = report[f"{kind}_exclusion"]
    errors = list(exclusion["excluded_correction_events"])
    for event in report["errors"]:
        changes = event.get(f"excluded_{kind}_changes", [])
        errors.append({
            **event,
            "changes": sorted(event["changes"] + changes, key=lambda change: change["index"]),
        })
    correction_actions, summary, characters = summarize_corrections(errors)
    if correction_actions != exclusion["unfiltered_correction_actions"]:
        raise ValueError("Raw correction totals differ from excluded trace accounting")
    return {
        "total_actions": exclusion["unfiltered_total_actions"],
        "syllables": report["syllables"],
        "corrections": len(errors),
        "correction_actions": correction_actions,
        "correction_summary": summary,
        "character_correction_summary": characters,
    }
