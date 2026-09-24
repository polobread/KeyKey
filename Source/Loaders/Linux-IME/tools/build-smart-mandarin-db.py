#!/usr/bin/env python3
"""Cook Linux's read-only Smart Mandarin model from shared source data."""

import math
import os
from pathlib import Path
import re
import sqlite3
import sys
import tempfile

MAX_PHRASE_LENGTH = 7
PRIOR = 1000.0
COMPONENTS = {
    **dict(zip("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ", range(1, 22))),
    "ㄧ": 0x20, "ㄨ": 0x40, "ㄩ": 0x60,
    **dict(zip("ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ", range(0x80, 0x701, 0x80))),
    "ˊ": 0x800, "ˇ": 0x1000, "ˋ": 0x1800, "˙": 0x2000,
}
HAN = re.compile(r"[\u3007\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff"
                 r"\U00020000-\U0002fa1f]+")
ASCII_SPACE = re.compile(r"[ \t\r\n\f\v]+")


def absolute_key(symbols):
    value = 0
    for symbol in symbols:
        if symbol not in COMPONENTS:
            return None
        value |= COMPONENTS[symbol]
    if value == 0:
        return None
    order = ((value & 0x1f) + ((value & 0x60) >> 5) * 22
             + ((value & 0x780) >> 7) * 88
             + ((value & 0x3800) >> 11) * 1232)
    return chr(48 + order % 79) + chr(48 + order // 79)


def read_lexicon(counts_path, mappings_path, cin_path, lexicon_paths):
    counts = {}
    with counts_path.open(encoding="utf-8") as source:
        for line in source:
            fields = line.split()
            if len(fields) >= 2 and fields[1].isdigit() and 1 <= len(fields[0]) <= MAX_PHRASE_LENGTH:
                count = int(fields[1])
                if count > 0:
                    counts[fields[0]] = count
    readings = {}
    with mappings_path.open(encoding="utf-8") as source:
        for line in source:
            fields = line.split()
            if not fields or fields[0] not in counts or len(fields[1:]) != len(fields[0]):
                continue
            keys = [absolute_key(syllable) for syllable in fields[1:]]
            if all(keys):
                readings.setdefault(fields[0], {})["".join(keys)] = None

    names = {}
    section = None
    with cin_path.open(encoding="utf-8") as source:
        for line in source:
            fields = line.split()
            if len(fields) >= 2 and fields[0] == "%keyname":
                section = None if fields[1] == "end" else "keyname"
            elif len(fields) >= 2 and fields[0] == "%chardef":
                section = None if fields[1] == "end" else "chardef"
            elif section == "keyname" and len(fields) == 2:
                names[fields[0]] = fields[1]
            elif section == "chardef" and len(fields) >= 2:
                word = fields[1]
                if len(word) == 1 and word in counts:
                    symbols = "".join(names.get(key, "") for key in fields[0])
                    key = absolute_key(symbols)
                    if key:
                        readings.setdefault(word, {})[key] = None

    for lexicon_path in lexicon_paths:
        with lexicon_path.open(encoding="utf-8") as source:
            for line in source:
                fields = line.rstrip("\n").split("\t")
                if len(fields) < 3 or not fields[1].isdigit():
                    continue
                word, raw_count, raw_reading = fields[:3]
                syllables = raw_reading.split()
                if not (1 <= len(word) <= MAX_PHRASE_LENGTH and
                        len(syllables) == len(word) and int(raw_count) > 0):
                    continue
                keys = [absolute_key(syllable) for syllable in syllables]
                if not all(keys):
                    continue
                counts[word] = max(counts.get(word, 0), int(raw_count))
                readings.setdefault(word, {})["".join(keys)] = None

    readings = {word: keys for word, keys in readings.items() if keys}
    total = sum(counts[word] for word in readings)
    if total == 0:
        raise ValueError("No usable Smart Mandarin readings")
    probabilities = {word: math.log10(counts[word] / total) for word in readings}
    return counts, readings, probabilities, total


def segment_run(run, readings, probabilities):
    scores = [-math.inf] * (len(run) + 1)
    paths = [None] * (len(run) + 1)
    scores[0], paths[0] = 0.0, []
    for position in range(len(run)):
        if paths[position] is None:
            continue
        matched = False
        for length in range(1, min(MAX_PHRASE_LENGTH, len(run) - position) + 1):
            word = run[position:position + length]
            if word not in readings:
                continue
            matched = True
            end = position + length
            score = scores[position] + probabilities[word]
            if score > scores[end]:
                scores[end] = score
                paths[end] = paths[position] + [word]
        if not matched and scores[position] > scores[position + 1]:
            scores[position + 1] = scores[position]
            paths[position + 1] = paths[position] + [None]
    return paths[-1] or []


def sentence_sequences(line, readings, probabilities):
    text = line.strip(" \t\r\n\f\v")
    if not text or text.startswith("#"):
        return []
    if ASCII_SPACE.search(text):
        tokens = []
        for field in ASCII_SPACE.split(text):
            for run in HAN.findall(field):
                tokens.extend([run] if run in readings else
                              segment_run(run, readings, probabilities))
        sequences, current = [], []
        for token in tokens + [None]:
            if token is None:
                if current:
                    sequences.append(current)
                    current = []
            else:
                current.append(token)
        return sequences
    return [[token for token in segment_run(run, readings, probabilities)
             if token is not None] for run in HAN.findall(text)]


def read_bigrams(corpora, readings, probabilities):
    pairs, outgoing = {}, {}
    sentences = tokens = 0
    for corpus in corpora:
        with corpus.open(encoding="utf-8") as source:
            for line in source:
                for sequence in sentence_sequences(line, readings, probabilities):
                    if not sequence:
                        continue
                    sentences += 1
                    tokens += len(sequence)
                    sequence = ["<s>", *sequence, "</s>"]
                    for previous, current in zip(sequence, sequence[1:]):
                        pair = (previous, current)
                        if pair not in pairs:
                            pairs[pair] = 1
                            outgoing[previous] = outgoing.get(previous, 0) + 1
    if corpora and sentences == 0:
        raise ValueError("No usable Smart Mandarin corpus sentences")
    return pairs, outgoing, sentences, tokens


def write_database(path, counts, readings, probabilities, total,
                   pairs, outgoing, sentences, tokens):
    database = sqlite3.connect(path)
    database.executescript("""
        CREATE TABLE unigrams (qstring TEXT, current TEXT,
                               probability REAL, backoff REAL);
        CREATE TABLE bigrams (qstring TEXT, previous TEXT,
                              current TEXT, probability REAL);
    """)

    def backoff(word):
        count = outgoing.get(word, 0)
        return 0.0 if count == 0 else math.log10(PRIOR / (count + PRIOR))

    with database:
        database.executemany("INSERT INTO unigrams VALUES (?, ?, ?, ?)",
                             [("*", "", -99.0, 0.0),
                              ("!", "", 0.0, backoff("<s>")),
                              ("$", "", 0.0, 0.0)])
        database.executemany("INSERT INTO unigrams VALUES (?, ?, ?, ?)",
            ((query, word, probabilities[word] - math.log10(len(keys)), backoff(word))
             for word, keys in readings.items() for query in keys))

        def bigram_rows():
            for (previous, current), count in pairs.items():
                previous_keys = ["!"] if previous == "<s>" else readings[previous]
                current_keys = ["$"] if current == "</s>" else readings[current]
                previous_text = "" if previous == "<s>" else previous
                current_text = "" if current == "</s>" else current
                base = (sentences / (tokens + sentences) if current == "</s>"
                        else counts[current] / total / len(current_keys))
                conditional = ((count / len(current_keys) + PRIOR * base) /
                               (outgoing[previous] + PRIOR))
                probability = math.log10(conditional)
                for previous_query in previous_keys:
                    for current_query in current_keys:
                        yield (previous_query + " " + current_query,
                               previous_text, current_text, probability)

        database.executemany("INSERT INTO bigrams VALUES (?, ?, ?, ?)",
                             bigram_rows())
    database.executescript("""
        CREATE INDEX unigrams_query ON unigrams(qstring);
        CREATE INDEX bigrams_query ON bigrams(qstring, previous, current);
    """)
    if database.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise ValueError("Smart Mandarin database integrity check failed")
    unigram_count = database.execute("SELECT COUNT(*) FROM unigrams").fetchone()[0]
    bigram_count = database.execute("SELECT COUNT(*) FROM bigrams").fetchone()[0]
    database.close()
    if bigram_count != 885_614:
        raise ValueError(f"Expected 885614 bigrams, found {bigram_count}")
    print(f"Smart Mandarin: {unigram_count} unigrams, {bigram_count} bigrams, "
          f"{sentences} sentences", file=sys.stderr)


def main():
    output = Path(sys.argv[1])
    cin, counts_path, mappings_path = map(Path, sys.argv[2:5])
    lexicon_paths = list(map(Path, sys.argv[5:7]))
    corpora = list(map(Path, sys.argv[7:]))
    if len(lexicon_paths) != 2 or not corpora:
        raise SystemExit("Expected two lexicons and at least one corpus")
    counts, readings, probabilities, total = read_lexicon(
        counts_path, mappings_path, cin, lexicon_paths)
    pairs, outgoing, sentences, tokens = read_bigrams(
        corpora, readings, probabilities)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as work:
        database_path = Path(work) / "smart-mandarin.db"
        write_database(database_path, counts, readings, probabilities,
                       total, pairs, outgoing, sentences, tokens)
        os.replace(database_path, output)


if __name__ == "__main__":
    main()
