"""Reviewed whole-phrase additions; never alter existing words or Bigram rows."""
from __future__ import annotations

import csv
import math


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


def apply(database, path, total_count):
    if not isinstance(total_count, (int, float)) or not math.isfinite(total_count) or total_count <= 0:
        raise ValueError("total count must be a positive integer")
    with path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source, delimiter="\t")
        expected = ("word", "target_count", "reading", "training_occurrences", "training_documents", "reason")
        if tuple(reader.fieldnames or ()) != expected:
            raise ValueError(f"{path}: unexpected columns")
        entries = list(reader)
    if not entries:
        raise ValueError("empty phrase supplement")
    seen, prepared = set(), []
    # Validate the complete overlay against the original vocabulary before
    # inserting anything. File order must not change its score floors.
    for entry in entries:
        word = entry["word"]
        syllables = entry["reading"].split()
        count = int(entry["target_count"])
        occurrences, documents = int(entry["training_occurrences"]), int(entry["training_documents"])
        if not 2 <= len(word) <= 7 or len(syllables) != len(word) or word in seen:
            raise ValueError(f"invalid or duplicate phrase: {word}")
        if not 0 < count <= total_count or not 0 < documents <= occurrences or not entry["reason"]:
            raise ValueError(f"invalid count or missing evidence: {word}")
        seen.add(word)
        query = "".join(query_for_reading(value) for value in syllables)
        score = math.log10(count / total_count)
        minimum = math.floor(10 ** strongest_competitor(database, query, word) * total_count) + 1
        existing = list(database.execute("SELECT probability FROM unigrams WHERE qstring=? AND current=?", (query, word)))
        if existing:
            if len(existing) != 1 or not math.isclose(existing[0][0], score, abs_tol=1e-12, rel_tol=0):
                raise ValueError(f"existing phrase changed; review the overlay: {word}")
            if count < minimum:
                raise ValueError(f"existing phrase no longer outranks its competitor: {word}")
        elif count != minimum:
            raise ValueError(f"{word}: expected minimum count {minimum}, got {count}; review the source model")
        prepared.append((query, word, score, bool(existing), entry))
    for query, word, score, existing, _ in prepared:
        if not existing:
            database.execute("INSERT INTO unigrams VALUES(?,?,?,0.0)", (query, word, score))
    return [{**entry, "status": "retained" if existing else "inserted", "probability": score}
            for _, _, score, existing, entry in prepared]
