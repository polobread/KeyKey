"""Evidence-limited, normalized Bigram cooking over a fixed unigram vocabulary.

Unlike a fixed pseudo-count per observed pair, a bounded likelihood ratio cannot
give an arbitrarily large bonus to a rare homophone. All supported transitions
and missing-edge backoffs share the same context denominator. No character list
or validation corrections enter this transformation.
"""
from __future__ import annotations

from collections import Counter
from functools import lru_cache
import importlib.util
import math
from pathlib import Path


@lru_cache(maxsize=1)
def finalizer():
    spec = importlib.util.spec_from_file_location(
        "finalizer", Path(__file__).with_name("finalize-smart-mandarin-model.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sequences(text, probabilities):
    # Punctuation, whitespace and unknown characters are boundaries. In natural
    # articles whitespace is not a license to join runs across punctuation.
    module = finalizer()
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        for run in module.HAN_RUN.findall(line):
            sequence = []
            for word in module.segment(run, probabilities) + [None]:
                if word is None:
                    if sequence:
                        yield sequence
                    sequence = []
                else:
                    sequence.append(word)


def document_frequencies(articles, probabilities):
    result = Counter()
    for article in articles:
        pairs = set()
        for words in sequences(article["text"], probabilities):
            pairs.update(zip([""] + words, words))
        result.update(pairs)
    return result


def bounded_observation(df, unigram_mass, word_mass, prior, max_log_lift):
    if not all(math.isfinite(x) for x in (df, unigram_mass, word_mass, prior, max_log_lift)):
        raise ValueError("parameters must be finite")
    if df < 0 or not 0 < unigram_mass <= word_mass or prior <= 0 or not 0 <= max_log_lift <= 6:
        raise ValueError("invalid evidence, mass, prior or maximum lift")
    evidence = math.log2(1 + df) * unigram_mass / word_mass
    ceiling = prior * unigram_mass * math.expm1(max_log_lift * math.log(10))
    return min(evidence, ceiling)


def compensate(database, frequencies, prior=1000.0, max_log_lift=1.0):
    """Mutate only an explicit candidate copy, retaining vocabulary and row IDs.

    observation = min(log2(1+DF) * reading_share,
                      prior * P_unigram * (10**max_log_lift - 1))
    Z(h) = prior * sum_unigram_mass + sum_observation(h)
    P(w|h) = (prior * P_unigram(w) + observation) / Z(h)
    backoff(h) = log10(prior / Z(h))

    End-of-buffer is not an observed sentence boundary during live typing.
    Existing terminal edges use the same fallback as missing terminal edges;
    neither gets a synthetic sentence-ending bonus.
    """
    unigrams = list(database.execute("SELECT rowid,* FROM unigrams ORDER BY rowid"))
    probabilities = {(q, text): p for _, q, text, p, _ in unigrams}
    if len(probabilities) != len(unigrams):
        raise ValueError("duplicate unigram identity")
    word_mass = Counter()
    for (_, text), probability in probabilities.items():
        if text:
            word_mass[text] += 10 ** probability
    # Supplements can raise the total slightly above one. Account for their
    # actual mass rather than silently assuming the input is still normalized.
    background_mass = math.fsum(word_mass.values())
    if not math.isfinite(background_mass) or background_mass <= 0:
        raise ValueError("invalid unigram background mass")
    bigrams = list(database.execute("SELECT rowid,* FROM bigrams ORDER BY rowid"))
    outgoing = Counter()
    observations = {}
    seen = set()
    capped = unsupported = 0
    for rowid, query, previous, current, old in bigrams:
        pq, cq = query.split(" ")
        key = (pq, cq, previous, current)
        if key in seen:
            raise ValueError("duplicate bigram identity")
        seen.add(key)
        if (pq, previous) not in probabilities or (cq, current) not in probabilities:
            raise ValueError("bigram endpoint missing from unigrams")
        if cq == "$":
            continue
        mass = 10 ** probabilities[(cq, current)]
        df = frequencies[(previous, current)]
        observation = bounded_observation(df, mass, word_mass[current], prior, max_log_lift)
        capped += observation < math.log2(1 + df) * mass / word_mass[current] - 1e-12
        unsupported += df == 0
        observations[rowid] = observation
        outgoing[(pq, previous)] += observation
    updates = []
    for rowid, query, previous, current, old in bigrams:
        pq, cq = query.split(" ")
        if cq == "$":
            probability = -math.log10(background_mass + outgoing[(pq, previous)] / prior)
        else:
            probability = math.log10((prior * 10 ** probabilities[(cq, current)] + observations[rowid])
                                     / (prior * background_mass + outgoing[(pq, previous)]))
        updates.append((probability, rowid))
    database.executemany("UPDATE bigrams SET probability=? WHERE rowid=?", updates)
    database.executemany("UPDATE unigrams SET backoff=? WHERE rowid=?", [
        (-math.log10(background_mass + outgoing[(q, text)] / prior) if q != "$" and q != "*" else 0.0, rowid)
        for rowid, q, text, _, _ in unigrams
    ])
    return {"prior": prior, "max_log_lift": max_log_lift,
            "unigram_background_mass": background_mass,
            "bigram_rows": len(bigrams), "capped_rows": capped,
            "unsupported_rows": unsupported, "unigram_probabilities_changed": 0,
            "terminal_score": "same as missing-edge backoff; no sentence-ending bonus"}
