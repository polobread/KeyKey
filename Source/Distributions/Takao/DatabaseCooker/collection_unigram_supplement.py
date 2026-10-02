"""Insert missing collection words without changing existing model rows."""
from collections import Counter
import csv
import math

from phrase_unigram_supplement import query_for_reading
from smart_mandarin_model import file_sha256


def source_records(paths):
    return [{"file": path.name, "sha256": file_sha256(path)} for path in sorted(paths)]


def verify_sources(paths, expected):
    if source_records(paths) != expected:
        raise ValueError("collection files differ from the selected model manifest")


def load_overrides(path):
    with path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source, delimiter="\t")
        if reader.fieldnames != ["source_word", "word", "reading", "reason"]:
            raise ValueError("invalid collection override columns")
        result = {}
        for row in reader:
            if row["source_word"] in result or not row["reason"]:
                raise ValueError("duplicate or undocumented collection override")
            if not 2 <= len(row["word"]) <= 7 or len(row["reading"].split()) != len(row["word"]):
                raise ValueError("override must preserve one syllable per output character")
            for syllable in row["reading"].split():
                query_for_reading(syllable)
            result[row["source_word"]] = row
        return result


def apply(database, paths, total_count, overrides=None, frequency_policy="minimum", collision_index=None):
    """Text deduplication: existing model wins, then first valid source row.

    Source filenames and row order define precedence. New entries default to
    count one; source frequency is retained in the audit, never summed or used
    to rescale existing unigrams. Unencodable rows are reported, never
    converted to guessed pronunciations.
    """
    if not isinstance(total_count, (int, float)) or not math.isfinite(total_count) or total_count <= 0:
        raise ValueError("total count must be positive and finite")
    if frequency_policy not in ("minimum", "source"):
        raise ValueError("unsupported collection frequency policy")
    from unigram_collisions import CollisionIndex
    collision_index = collision_index or CollisionIndex()
    overrides = overrides or {}
    existing = {row[0] for row in database.execute("SELECT current FROM unigrams")}
    seen, prepared, skipped, rejected, files, inserted, exclusions = set(), [], [], [], [], [], []
    partial_overlaps, downranked = [], []
    for path in sorted(paths):
        counts = Counter(rows=0, inserted=0, existing=0, duplicate=0, rejected=0, collision=0)
        with path.open(encoding="utf-8", newline="") as source:
            reader = csv.reader(source, delimiter="\t")
            if next(reader, [])[:4] != ["詞", "詞頻", "注音", "分類"]:
                raise ValueError(f"{path}: unexpected columns")
            for line, fields in enumerate(reader, 2):
                counts["rows"] += 1
                word = fields[0] if fields else ""
                item = {"file": path.name, "line": line, "word": word}
                if word in overrides:
                    entry = overrides[word]
                    item["source_word"] = word
                    word = entry["word"]
                    item["word"] = word
                    fields = [word, fields[1], entry["reading"], *fields[3:]]
                status = "existing" if word in existing or word in collision_index.words else "duplicate" if word in seen else None
                if status:
                    counts[status] += 1
                    skipped.append({**item, "reason": status})
                    exclusions.append(dict(source=path.name, line=line, source_word=item.get("source_word", word),
                                           word=word, reading=fields[2] if len(fields) > 2 else "",
                                           reason=status, conflict_word=word))
                    continue
                try:
                    if len(fields) < 4:
                        raise ValueError("missing columns")
                    count, syllables = int(fields[1]), fields[2].split()
                    if not 2 <= len(word) <= 7 or len(syllables) != len(word):
                        raise ValueError("word and syllable length mismatch or unsupported span")
                    if not 0 < count <= total_count:
                        raise ValueError("invalid frequency")
                    query = "".join(query_for_reading(value) for value in syllables)
                except ValueError as error:
                    counts["rejected"] += 1
                    rejected.append({**item, "reading": fields[2] if len(fields) > 2 else "",
                                     "reason": str(error)})
                    continue
                seen.add(word)
                conflicts = collision_index.ranking_conflicts(word, fields[2])
                if conflicts:
                    counts["collision"] += 1
                    downranked.extend(dict(source=path.name, line=line, source_word=item.get("source_word", word),
                                           word=word, reading=fields[2], **conflict) for conflict in conflicts)
                partial_overlaps.extend(dict(source=path.name, line=line, source_word=item.get("source_word", word),
                                             word=word, reading=fields[2], **conflict)
                                        for conflict in collision_index.conflicts(word, fields[2]) if conflict not in conflicts)
                target_count = 0.01 if conflicts or fields[3] == "動漫" or path.name == "phrase.anime.tsv" else count if frequency_policy == "source" else 1
                prepared.append((query, word, math.log10(target_count / total_count), 0.0))
                inserted.append({**item, "reading": fields[2], "target_count": target_count,
                                 "source_count": count, "category": fields[3]})
                counts["inserted"] += 1
        files.append({"file": path.name, **dict(counts)})
    # All source parsing completes before the first write. The caller owns the
    # transaction so this layer composes safely with the other supplements.
    database.executemany("INSERT INTO unigrams VALUES(?,?,?,?)", prepared)
    totals = {key: sum(row[key] for row in files)
              for key in ("rows", "inserted", "existing", "duplicate", "rejected", "collision")}
    return {"policy": "normalize reviewed Chinese aliases then skip by word text; existing model wins; first valid row in filename order wins; fixed base total; backoff zero",
            "frequency_policy": frequency_policy,
            "totals": totals, "files": files, "skipped": skipped, "rejected": rejected,
            "inserted_entries": inserted, "exclusions": exclusions, "partial_overlaps": partial_overlaps,
            "downranked": downranked}


LIST_FIELDS = ("word", "reading", "target_count", "source_count", "category", "file", "line", "source_word")


def write_list(path, entries):
    with path.open("x", encoding="utf-8", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=LIST_FIELDS, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(sorted(entries, key=lambda row: row["word"]))
