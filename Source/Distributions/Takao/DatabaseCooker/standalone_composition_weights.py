"""Apply the reviewed Smart Mandarin weights after the normal model cook."""
from __future__ import annotations

import json
import math
from pathlib import Path


COLUMNS = {
    "unigrams": (("qstring", "current"), ("probability", "backoff")),
    "bigrams": (("qstring", "previous", "current"), ("probability",)),
}


def valid_scores(values, size):
    return (isinstance(values, list) and len(values) == size
            and all(type(value) in (float, int) and math.isfinite(value) and value <= 0
                    for value in values))


def load(path, total):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    reviewed_total = data.get("unigram_total_count")
    if (data.get("format") != 1 or any(type(value) not in (int, float) or not math.isfinite(value) or value <= 0
                                      for value in (reviewed_total, total))):
        raise ValueError(f"{path}: invalid weight format or unigram total")
    for table, (keys, scores) in COLUMNS.items():
        entries = data.get(table)
        if not isinstance(entries, list) or not entries:
            raise ValueError(f"{path}: expected {table} weights")
        seen = set()
        for entry in entries:
            key, before, after = entry["key"], entry["before"], entry["after"]
            if (not isinstance(key, list) or len(key) != len(keys)
                    or not all(isinstance(value, str) for value in key) or not key[0] or not key[-1]
                    or tuple(key) in seen
                    or (before is not None and not valid_scores(before, len(scores)))
                    or not valid_scores(after, len(scores))):
                raise ValueError(f"{path}: invalid or duplicate {table} weight {entry!r}")
            if table == "bigrams" and (not key[0].startswith("! ") or key[1] != ""):
                raise ValueError(f"{path}: expected a sentence-start Bigram {key!r}")
            seen.add(tuple(key))
    if total != reviewed_total:
        # Keep the reviewed effective counts when the rebuilt model denominator changes.
        shift = math.log10(reviewed_total) - math.log10(total)
        for entry in data["unigrams"]:
            entry["after"][0] += shift
            if not valid_scores(entry["after"], 2):
                raise ValueError(f"{path}: rebuilt unigram total is too small for {entry['key']!r}")
    return data


def matching_scores(actual, expected):
    return all(math.isclose(a, b, rel_tol=0, abs_tol=1e-12) for a, b in zip(actual, expected))


def apply(database, weights):
    """Retain existing rowids and insert new rows in the reviewed order."""
    with database:
        for table, (keys, scores) in COLUMNS.items():
            where = " AND ".join(f"{key}=?" for key in keys)
            select = f"SELECT rowid FROM {table} WHERE {where}"
            values = ",".join("?" for _ in (*keys, *scores))
            insert = f"INSERT INTO {table} ({','.join((*keys, *scores))}) VALUES ({values})"
            assignments = ",".join(f"{score}=?" for score in scores)
            update = f"UPDATE {table} SET {assignments} WHERE rowid=?"
            for entry in weights[table]:
                key, after = entry["key"], entry["after"]
                current = database.execute(select, key).fetchall()
                if len(current) > 1:
                    raise ValueError(f"duplicate {table} rows for {key!r}")
                if current:
                    database.execute(update, [*after, current[0][0]])
                else:
                    database.execute(insert, [*key, *after])


def verify(database, weights):
    for table, (keys, scores) in COLUMNS.items():
        where = " AND ".join(f"{key}=?" for key in keys)
        select = f"SELECT {','.join(scores)} FROM {table} WHERE {where}"
        for entry in weights[table]:
            rows = database.execute(select, entry["key"]).fetchall()
            if len(rows) != 1 or not matching_scores(rows[0], entry["after"]):
                raise ValueError(f"{table} weight differs from the reviewed value for {entry['key']!r}")
