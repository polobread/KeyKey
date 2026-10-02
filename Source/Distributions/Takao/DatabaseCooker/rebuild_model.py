"""Source-based cooker stages. A seed DB supplies only non-language-model tables."""
import csv
import json
import math
from pathlib import Path
import sqlite3
import subprocess

from phrase_unigram_supplement import query_for_reading

ROOT = Path(__file__).resolve().parents[4]
COOKER = Path(__file__).resolve().parent
DATA = ROOT / "DataSource/AISyntheticBigram"


def standard_cin_query(syllable):
    # Match Mandarin.h StandardLayout and BPMF::operator+=: the last key in
    # each component group wins (the upstream CIN has e.g. repeated medials).
    order = 0
    for symbols, scale in ((" ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ", 1),
                           (" ㄧㄨㄩ", 22), (" ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ", 88),
                           (" ˊˇˋ˙", 1232)):
        matches = [s for s in syllable if s in symbols and s != " "]
        if matches: order += symbols.index(matches[-1]) * scale
    return chr(48 + order % 79) + chr(48 + order // 79)


def write_lexicon(path, entries):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("詞", "詞頻", "注音"))
        for row in entries:
            writer.writerow((row["word"], row["target_count"], row["reading"]))


def make_cin(path):
    """Convert the checked-in standard-layout CIN without native Ruby extensions."""
    keys, inside_keys, inside_chars = {}, False, False
    lines = ["%chardef begin"]
    for line in (ROOT / "Source/DataTables/bpmf-ext.cin").read_text().splitlines():
        parts = line.split()
        if parts == ["%keyname", "begin"]: inside_keys = True; continue
        if parts == ["%keyname", "end"]: inside_keys = False; continue
        if parts == ["%chardef", "begin"]: inside_chars = True; continue
        if parts == ["%chardef", "end"]: inside_chars = False; continue
        if len(parts) != 2: continue
        if inside_keys: keys[parts[0]] = parts[1]
        if inside_chars:
            syllable = "".join(keys[key] for key in parts[0])
            query = standard_cin_query(syllable)
            lines.append(query + " " + parts[1])
    lines.append("%chardef end")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def cook(database, cin, work, custom=None, corpus=None):
    sql, report = work.with_suffix(".sql"), work.with_suffix(".json")
    command = ["ruby", "-E", "UTF-8", str(COOKER / "SmartMandarinCooker.rb"),
               str(ROOT / "DataSource/McBopomofo/phrase.occ"),
               str(ROOT / "DataSource/McBopomofo/BPMFMappings.txt"), str(cin), "--report", str(report)]
    for name in ("supplemental-lexicon.tsv", "numeric-unit-lexicon.tsv"):
        command.extend(("--lexicon", str(DATA / name)))
    if custom: command.extend(("--lexicon-preserve-counts", str(custom)))
    # Only the 2,300 training articles supply Bigram observations. Evaluation
    # articles and old feedback/template corpora cannot leak into training.
    if corpus: command.append(str(corpus))
    with sql.open("w", encoding="utf-8") as stream:
        subprocess.run(command, stdout=stream, check=True)
    with sqlite3.connect(database) as db:
        db.execute("DELETE FROM bigrams")
        db.execute("DELETE FROM unigrams")
        db.commit()
        db.executescript(sql.read_text(encoding="utf-8"))
    return json.loads(report.read_text())


def add_convenience_words(database, entries, total, maximum_count=0.01):
    """Post-training Unigrams: no training influence or Bigram edges.

    Anime / collisions use count <=0.01; ordinary personal names use <=1.
    Rank below existing complete homophones without a split-path floor.
    """
    with sqlite3.connect(database) as db:
        prepared = []
        for row in entries:
            query = "".join(query_for_reading(s) for s in row["reading"].split())
            if db.execute("SELECT 1 FROM unigrams WHERE current=?", (row["word"],)).fetchone():
                raise ValueError(f"duplicate convenience word: {row['word']}")
            count = min(maximum_count, row["target_count"])
            score = math.log10(count / total)
            competitors = db.execute("SELECT MIN(probability) FROM unigrams WHERE qstring=?", (query,)).fetchone()[0]
            if competitors is not None:
                score = min(score, competitors - 2.0)
            row["target_count"] = min(count, total * 10 ** score)
            prepared.append((query, row["word"], score, 0.0))
        db.executemany("INSERT INTO unigrams VALUES(?,?,?,?)", prepared)
