"""Optional CIN-derived replacement counts. Original code, MIT, Chui-Ping Cheng."""
from __future__ import annotations

import csv
import math
from pathlib import Path
from phrase_unigram_supplement import query_for_reading

DEFAULT_SOURCE = Path(__file__).resolve().parents[4] / "DataSource/CINReadingFrequency/cin-character-reading-frequencies.tsv"
REQUIRED = {"character", "reading", "qstring", "cin_rank", "source_count", "target_count"}


def load(path):
    with Path(path).open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if not REQUIRED.issubset(reader.fieldnames or ()) or len(reader.fieldnames) != len(set(reader.fieldnames)):
            raise ValueError(f"{path}: missing or duplicate CIN frequency columns")
        entries, seen = [], set()
        for line, row in enumerate(reader, 2):
            if None in row or any(row.get(key) is None for key in REQUIRED):
                raise ValueError(f"{path}:{line}: incomplete CIN frequency row")
            word, query = row["character"], row["qstring"]
            if len(word) != 1 or query_for_reading(row["reading"]) != query:
                raise ValueError(f"{path}:{line}: character/reading/qstring mismatch")
            if not row["source_count"].isascii() or not row["source_count"].isdigit() or int(row["source_count"]) <= 0:
                raise ValueError(f"{path}:{line}: source_count must be a positive integer")
            if not row["cin_rank"].isascii() or not row["cin_rank"].isdigit() or int(row["cin_rank"]) <= 0:
                raise ValueError(f"{path}:{line}: cin_rank must be a positive integer")
            target = float(row["target_count"])
            if not math.isfinite(target) or not 0 < target <= int(row["source_count"]):
                raise ValueError(f"{path}:{line}: target_count must be finite, positive and <= source_count")
            if (word, query) in seen:
                raise ValueError(f"{path}:{line}: duplicate character/reading")
            seen.add((word, query))
            entries.append({**row, "target_count": target})
    if not entries:
        raise ValueError(f"{path}: empty CIN frequency table")
    return entries


def verify_unigrams(database, entries, total):
    if not math.isfinite(total) or total <= 0:
        raise ValueError("invalid unigram total")
    for row in entries:
        actual = database.execute(
            "SELECT probability FROM unigrams WHERE qstring=? AND current=?",
            (row["qstring"], row["character"])).fetchall()
        expected = math.log10(row["target_count"] / total)
        if len(actual) != 1 or not math.isclose(actual[0][0], expected, rel_tol=0, abs_tol=1e-12):
            raise ValueError(f"CIN frequency not preserved: {row['character']}/{row['reading']}")
