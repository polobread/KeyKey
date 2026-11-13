"""Reviewed whole-phrase additions; never alter existing words or Bigram rows."""
from __future__ import annotations

import csv
import math


PRE_TRAINING = "pre-training"
POST_TRAINING = "post-training"


def query_for_reading(reading):
    groups = ((" ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ", 1),
              (" ㄧㄨㄩ", 22), (" ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ", 88), (" ˊˇˋ˙", 1232))
    order, used = 0, set()
    for character in reading:
        for index, (symbols, scale) in enumerate(groups):
            if character != " " and character in symbols:
                if index in used:
                    raise ValueError(f"invalid reading: {reading}")
                used.add(index)
                order += symbols.index(character) * scale
                break
        else:
            raise ValueError(f"invalid reading: {reading}")
    if not used - {3}:
        raise ValueError(f"invalid reading: {reading}")
    return chr(48 + order % 79) + chr(48 + order // 79)


def strongest_competitor(database, query, word):
    """Best same-reading unigram path, including alternative tokenizations."""
    best = [-math.inf] * (len(query) // 2 + 1)
    best[0] = 0.0
    for end in range(1, len(best)):
        for start in range(end):
            for text, probability in database.execute(
                "SELECT current,probability FROM unigrams WHERE qstring=?",
                (query[start * 2:end * 2],),
            ):
                if start == 0 and end == len(best) - 1 and text == word:
                    continue
                best[end] = max(best[end], best[start] + probability)
    if not math.isfinite(best[-1]):
        raise ValueError(f"no competing input path for {word}")
    return best[-1]


def load(path, total_count, stage):
    if not isinstance(total_count, (int, float)) or not math.isfinite(total_count) or total_count <= 0:
        raise ValueError("total count must be a positive integer")
    if stage not in (PRE_TRAINING, POST_TRAINING):
        raise ValueError(f"unknown phrase supplement stage: {stage}")
    with path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source, delimiter="\t")
        expected = ("word", "target_count", "reading", "training_occurrences", "training_documents", "reason")
        if tuple(reader.fieldnames or ()) not in (expected, (*expected, "stage"), (*expected, "stage", "action")):
            raise ValueError(f"{path}: unexpected columns")
        entries = list(reader)
    if not entries:
        raise ValueError("empty phrase supplement")
    seen, selected = set(), []
    for entry in entries:
        word = entry["word"]
        syllables = entry["reading"].split()
        count = int(entry["target_count"])
        occurrences, documents = int(entry["training_occurrences"]), int(entry["training_documents"])
        entry_stage = entry.get("stage", PRE_TRAINING)
        action = entry.pop("action", "") or "add"
        if not 2 <= len(word) <= 7 or len(syllables) != len(word):
            raise ValueError(f"invalid phrase: {word}")
        if entry_stage not in (PRE_TRAINING, POST_TRAINING):
            raise ValueError(f"{word}: invalid phrase supplement stage {entry_stage!r}")
        has_training_evidence = 0 < documents <= occurrences
        explicit_addition = entry_stage == POST_TRAINING and documents == occurrences == 0
        if not 0 < count <= total_count or not (has_training_evidence or explicit_addition) or not entry["reason"]:
            raise ValueError(f"invalid count or missing evidence: {word}")
        query = "".join(query_for_reading(value) for value in syllables)
        if (query, word) in seen:
            raise ValueError(f"duplicate phrase reading: {word}")
        seen.add((query, word))
        if action == "reweight" and entry_stage == POST_TRAINING:
            entry["action"] = action
        elif action != "add":
            raise ValueError(f"{word}: invalid action for {entry_stage}: {action}")
        if entry_stage == stage:
            selected.append((entry, count, query, math.log10(count / total_count)))
    return selected


def apply(database, path, total_count, *, stage=PRE_TRAINING):
    prepared = []
    # Check all score floors against the original vocabulary before inserting.
    for entry, count, query, score in load(path, total_count, stage):
        word = entry["word"]
        existing = database.execute(
            "SELECT probability,backoff FROM unigrams WHERE qstring=? AND current=?", (query, word)
        ).fetchall()
        if entry.get("action") == "reweight":
            if len(existing) != 1:
                raise ValueError(f"expected an existing phrase to reweight: {word}")
            prepared.append((query, word, score, "reweighted", entry))
            continue
        if existing and (len(existing) != 1 or not math.isclose(existing[0][0], score, abs_tol=1e-12, rel_tol=0)):
            raise ValueError(f"existing phrase changed; review the overlay: {word}")
        if stage == PRE_TRAINING:
            minimum = math.floor(10 ** strongest_competitor(database, query, word) * total_count) + 1
            if existing and count < minimum:
                raise ValueError(f"existing phrase no longer outranks its competitor: {word}")
            if not existing and count != minimum:
                raise ValueError(f"{word}: expected minimum count {minimum}, got {count}; review the source model")
        elif existing and existing[0][1] != 0.0:
            raise ValueError(f"post-training phrase has existing Bigram backoff: {word}")
        prepared.append((query, word, score, "retained" if existing else "inserted", entry))
    for query, word, score, status, _ in prepared:
        if status == "inserted":
            database.execute("INSERT INTO unigrams VALUES(?,?,?,0.0)", (query, word, score))
        elif status == "reweighted":
            database.execute("UPDATE unigrams SET probability=? WHERE qstring=? AND current=?", (score, query, word))
    return [{**entry, "status": status, "probability": score}
            for _, _, score, status, entry in prepared]


def verify_post_training(database, path, total_count, expected_entries):
    entries = load(path, total_count, POST_TRAINING)
    if len(entries) != expected_entries:
        raise ValueError("post-training phrase count differs from the manifest")
    added_readings = set()
    for entry, _, query, score in entries:
        word = entry["word"]
        matches = database.execute(
            "SELECT probability,backoff FROM unigrams WHERE qstring=? AND current=?", (query, word)
        ).fetchall()
        if len(matches) != 1 or not math.isclose(matches[0][0], score, abs_tol=1e-12, rel_tol=0):
            raise ValueError(f"post-training phrase differs from DB: {word}")
        if entry.get("action") != "reweight":
            if matches[0][1] != 0.0:
                raise ValueError(f"post-training phrase has existing Bigram backoff: {word}")
            added_readings.add((query, word))
    if added_readings:
        words = sorted({word for _, word in added_readings})
        placeholders = ",".join("?" for _ in words)
        edges = database.execute(
            f"SELECT qstring,previous,current FROM bigrams WHERE previous IN ({placeholders}) OR current IN ({placeholders})",
            words + words,
        )
        for query, previous, current in edges:
            left, _, right = query.partition(" ")
            if (left, previous) in added_readings or (right, current) in added_readings:
                raise ValueError(f"post-training phrase has a Bigram edge: {(query, previous, current)}")
