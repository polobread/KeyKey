"""Deterministic McBopomofo homophone diagnostics, independent of learning."""
from collections import defaultdict
import csv
from pathlib import Path

from phrase_unigram_supplement import query_for_reading

ROOT = Path(__file__).resolve().parents[4]
FIELDS = ("source", "line", "source_word", "word", "reading", "reason",
          "span_start", "span_text", "span_reading", "conflict_word",
          "conflict_reading", "conflict_start", "conflict_text", "conflict_count")
POLICY = "mcp-homophones-retained-low-ranked-long-partial-diagnostic-v3"


class CollisionIndex:
    def __init__(self, counts_path=None, mappings_path=None):
        counts_path = counts_path or ROOT / "DataSource/McBopomofo/phrase.occ"
        mappings_path = mappings_path or ROOT / "DataSource/McBopomofo/BPMFMappings.txt"
        self.counts = {}
        for line in counts_path.read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[1].isdigit() and int(parts[1]) > 0 and 1 <= len(parts[0]) <= 7:
                self.counts[parts[0]] = int(parts[1])
        self.full, self.pairs = defaultdict(set), defaultdict(set)
        self.words = set()
        for line in mappings_path.read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if not parts or parts[0] not in self.counts or len(parts) - 1 != len(parts[0]):
                continue
            word, syllables = parts[0], parts[1:]
            queries = tuple(query_for_reading(s) for s in syllables)
            reading = " ".join(syllables)
            self.words.add(word)
            self.full[queries].add((word, reading, 0, word))
            for start in range(len(word) - 1):
                self.pairs[queries[start:start + 2]].add((word, reading, start, word[start:start + 2]))
        if not self.words:
            raise ValueError("no usable McBopomofo collision reference")

    def conflicts(self, word, reading):
        syllables = reading.split()
        if len(syllables) != len(word):
            raise ValueError("collision input must have one syllable per character")
        query = tuple(query_for_reading(s) for s in syllables)
        result = []
        spans = [("full_homophone", 0, len(word), self.full.get(query, ()))]
        spans.extend(("two_character_homophone", i, i + 2, self.pairs.get(query[i:i + 2], ()))
                     for i in range(len(word) - 1))
        for reason, start, end, matches in spans:
            for other, other_reading, offset, text in sorted(matches):
                if text == word[start:end]:
                    continue
                # A full two-character match already has a precise reason.
                if reason == "two_character_homophone" and len(word) == len(other) == 2:
                    continue
                result.append(dict(reason=reason, span_start=start + 1,
                    span_text=word[start:end], span_reading=" ".join(syllables[start:end]),
                    conflict_word=other, conflict_reading=other_reading,
                    conflict_start=offset + 1, conflict_text=text, conflict_count=self.counts[other]))
        return result

    def ranking_conflicts(self, word, reading):
        # A complete 3+ character word is not the same input as its internal
        # two-character overlap. Only full matches / two-character new words
        # need candidate-only downranking; no collision deletes a word.
        return [row for row in self.conflicts(word, reading)
                if row["reason"] == "full_homophone" or len(word) <= 2]


def write_exclusions(path, rows):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, FIELDS, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(sorted(rows, key=lambda r: (r["source"], int(r["line"]), r.get("reason", ""),
                                                    int(r.get("span_start") or 0), r.get("conflict_word", ""),
                                                    int(r.get("conflict_start") or 0), r.get("conflict_reading", ""))))
