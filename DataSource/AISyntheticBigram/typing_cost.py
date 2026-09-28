"""Reproducible typing-cost experiments using the production Manjusri engine."""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import asdict, dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
SOURCE = REPO / "Source"
DEFAULT_DB = SOURCE / "Distributions/Takao/CookedDatabase/KeyKey.db"
CACHE = ROOT / ".typing-cache"
READING_OVERRIDES = ROOT / "reading-overrides.tsv"
CONSONANTS = " ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ"
MEDIALS = " ㄧㄨㄩ"
VOWELS = " ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ"
TONES = " ˊˇˋ˙"


def sha256(path: Path) -> str:
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hashlib.sha256(source.read()).hexdigest()


class ClosingConnection(sqlite3.Connection):
    def __exit__(self, *args):
        try:
            return super().__exit__(*args)
        finally:
            self.close()


def writable_db(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(path, factory=ClosingConnection)


def connect(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True, factory=ClosingConnection)


def validate_db(path: Path) -> None:
    with connect(path) as db:
        for table, columns in (("unigrams", ["qstring", "current", "probability", "backoff"]),
                               ("bigrams", ["qstring", "previous", "current", "probability"])):
            actual = [row[1] for row in db.execute(f"PRAGMA table_info({table})")]
            if actual != columns:
                raise ValueError(f"{path}: requires shared KeyKey.db schema: {table} {columns}")
        if db.execute("SELECT count(*) FROM unigrams WHERE qstring IN ('!', '$', '*')").fetchone()[0] != 3:
            raise ValueError(f"{path}: missing BOS/EOS/UNK unigrams")


def resolve_version(version: str) -> Path:
    """DB path, named repair manifest, or a reproducible corpus snapshot."""
    if version == "current":
        validate_db(DEFAULT_DB)
        return DEFAULT_DB
    if version in ("project-unigram-v1", "project-unigram-v2"):
        return cook_maintained_unigram(version)
    candidate = Path(version).expanduser()
    if not candidate.exists():
        candidate = ROOT / "versions" / f"{version}.json"
    if candidate.is_file():
        if candidate.suffix == ".json":
            manifest = json.loads(candidate.read_text(encoding="utf-8"))
            path = candidate.parent / manifest["database"]
            if sha256(path) != manifest["database_sha256"]:
                raise ValueError(f"{candidate}: model hash mismatch")
        else:
            path = candidate
        validate_db(path)
        return path.resolve()
    if version == "unigram":
        CACHE.mkdir(exist_ok=True)
        path = CACHE / f"unigram-{sha256(DEFAULT_DB)[:16]}.db"
        if not path.exists():
            with tempfile.TemporaryDirectory(dir=CACHE) as directory:
                temporary = Path(directory) / "unigram.db"
                with connect(DEFAULT_DB) as source, writable_db(temporary) as target:
                    source.backup(target)
                    target.execute("DELETE FROM bigrams")
                temporary.replace(path)
        validate_db(path)
        return path
    counts = (100, 200, 300, 400, 450, 500, 700, 900, 1100, 1300, 1500, 1650, 2300)
    name = {"v2": "articles-1650", "v4": "articles-2300"}.get(version, version)
    corpus = []
    if name == "bootstrap" or name in {f"articles-{count}" for count in counts}:
        corpus = [ROOT / f"corpus-v{v}.txt" for v in (1, 2, 3)] + [ROOT / "corpus-typing-feedback.txt"]
        if name.startswith("articles-"):
            count = name.split("-")[1]
            corpus.append(ROOT / (f"article-corpus-{count}.txt" if count != "2300" else "article-corpus-2300-exact-dedup.txt"))
        return cook_snapshot(name, corpus)
    raise ValueError(
        f"Unknown bigram version {version!r}; use current, project-unigram-v1/v2, unigram, "
        "bootstrap, articles-N, a .db or repair .json")


def cook_maintained_unigram(version: str) -> Path:
    article_root = ROOT.parent / "AISyntheticArticles"
    cooker = SOURCE / "Distributions/Takao/DatabaseCooker"
    config = ROOT / ("maintained-unigram-v1.json" if version.endswith("v1") else "maintained-unigram.json")
    inputs = [
        config, ROOT / "reading-overrides.tsv",
        ROOT / "supplemental-lexicon.tsv", ROOT / "numeric-unit-lexicon.tsv",
        ROOT / "build-maintained-unigram.py", ROOT / "build-project-unigram.py",
        ROOT / "build-unigram-blend.py", ROOT / "build-iterative-unigram.py",
        ROOT / "benchmark-project-unigram.py",
        ROOT / "typing_batch.py", cooker / "SmartMandarinCooker.rb",
        cooker / "Intermediates/bpmf-ext-absorder.cin",
        REPO / "DataSource/McBopomofo/phrase.occ",
        REPO / "DataSource/McBopomofo/BPMFMappings.txt",
        *(ROOT / f"corpus-v{number}.txt" for number in (1, 2, 3)),
        ROOT / "corpus-typing-feedback.txt",
        *(article_root / f"typing-articles-v{number}.jsonl" for number in (2, 3, 4)),
    ]
    fingerprint = hashlib.sha256("".join(sha256(path) for path in inputs).encode()).hexdigest()[:16]
    directory = CACHE / f"{version}-{fingerprint}"
    target = directory / f"{version}.db"
    if not target.exists():
        CACHE.mkdir(exist_ok=True)
        print(f"Building {version} from its frozen 800-article training split…", file=sys.stderr)
        result = subprocess.run(
            [sys.executable, str(ROOT / "build-maintained-unigram.py"), "--output", str(directory),
             "--config", str(config)],
            capture_output=True, text=True)
        if result.returncode:
            raise ValueError(f"Maintained unigram build failed:\n{result.stderr}")
    validate_db(target)
    return target


def cook_snapshot(name: str, corpora: list[Path]) -> Path:
    cooker = SOURCE / "Distributions/Takao/DatabaseCooker"
    inputs = [cooker / "SmartMandarinCooker.rb", REPO / "DataSource/McBopomofo/phrase.occ",
              REPO / "DataSource/McBopomofo/BPMFMappings.txt", cooker / "Intermediates/bpmf-ext-absorder.cin",
              ROOT / "supplemental-lexicon.tsv", ROOT / "numeric-unit-lexicon.tsv", *corpora]
    fingerprint = hashlib.sha256("".join(sha256(p) for p in inputs).encode()).hexdigest()[:16]
    CACHE.mkdir(exist_ok=True)
    target = CACHE / f"{name}-{fingerprint}.db"
    if target.exists():
        validate_db(target)
        return target
    print(f"Building {name} with production cooker…", file=sys.stderr)
    with tempfile.TemporaryDirectory(dir=CACHE) as temporary:
        work = Path(temporary)
        sql = work / "model.sql"
        command = ["ruby", "-E", "UTF-8", *(str(p) for p in inputs[:4]),
                   "--lexicon", str(inputs[4]), "--lexicon", str(inputs[5]), *(str(p) for p in corpora)]
        with sql.open("wb") as output:
            result = subprocess.run(command, stdout=output, stderr=subprocess.PIPE)
        if result.returncode:
            raise ValueError(result.stderr.decode("utf-8", errors="replace"))
        path = work / "model.db"
        with writable_db(path) as db:
            db.executescript("CREATE TABLE unigrams(qstring,current,probability,backoff);"
                             "CREATE TABLE bigrams(qstring,previous,current,probability);")
            db.executescript(sql.read_text(encoding="utf-8"))
            db.executescript("CREATE INDEX unigrams_index ON unigrams(qstring);"
                             "CREATE INDEX unigrams_current_index ON unigrams(current);"
                             "CREATE INDEX bigrams_index ON bigrams(qstring);")
        validate_db(path)
        path.replace(target)
    return target


def build_engine() -> Path:
    framework = SOURCE / "Frameworks"
    headers = [framework / f"{name}/Headers" for name in ("OpenVanilla", "Formosa", "Manjusri")]
    module = SOURCE / "ModulePackages/OVIMMandarin"
    sources = [ROOT / "typing-engine.cpp", framework / "Manjusri/Source/Node.cpp", framework / "Formosa/Source/Mandarin.cpp"]
    dependencies = sources + [module / "OVIMSmartMandarin.h"] + [p for directory in headers for p in sorted(directory.glob("*.h"))]
    compiler = os.environ.get("CXX", "c++")
    fingerprint = hashlib.sha256((compiler + sys.platform + "".join(sha256(p) for p in dependencies)).encode()).hexdigest()[:16]
    target = CACHE / f"typing-engine-{fingerprint}"
    if target.exists():
        return target
    CACHE.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=CACHE) as directory:
        work = Path(directory)
        (work / "OpenVanilla").symlink_to(headers[0], target_is_directory=True)
        command = [compiler, "-std=c++17", "-O2", "-Wno-deprecated-declarations", "-DOV_USE_SQLITE",
                   *(f"-I{p}" for p in [work, module, *headers]), *(str(p) for p in sources),
                   "-lsqlite3", "-o", str(work / "engine")]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            raise ValueError(f"Native engine build failed (C++17 compiler and SQLite development headers required):\n{result.stderr}")
        (work / "engine").replace(target)
    return target


class Engine:
    def __init__(self, database: Path):
        self.process = subprocess.Popen([str(build_engine()), str(database.resolve())], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, text=True, encoding="utf-8", bufsize=1)

    def call(self, command: str, argument: str | int = ""):
        self.process.stdin.write(f"{command}\t{argument}\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline()
        if not line:
            raise ValueError("Native typing engine exited unexpectedly")
        result = json.loads(line)
        if isinstance(result, dict) and "error" in result:
            raise ValueError(result["error"])
        return result

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.process.stdin.close()
        self.process.stdout.close()
        self.process.wait(timeout=10)


def han(character: str) -> bool:
    return any(low <= ord(character) <= high for low, high in
               ((0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF), (0x20000, 0x323AF)))


def reading(query: str) -> str:
    if len(query) != 2 or any(not 48 <= ord(c) <= 126 for c in query):
        raise ValueError(f"Invalid syllable query: {query!r}")
    order = ord(query[0]) - 48 + (ord(query[1]) - 48) * 79
    if not 0 < order < 6160:
        raise ValueError(f"Invalid syllable query: {query!r}")
    return (CONSONANTS[order % 22] + MEDIALS[order // 22 % 4]
            + VOWELS[order // 88 % 14] + TONES[order // 1232]).replace(" ", "")


def query_for_reading(value: str) -> str:
    order = 0
    used = set()
    for character in value:
        for group, (symbols, scale) in enumerate(((CONSONANTS, 1), (MEDIALS, 22), (VOWELS, 88), (TONES, 1232))):
            if character != " " and character in symbols:
                if group in used:
                    raise ValueError(f"Invalid reading: {value}")
                used.add(group)
                order += symbols.index(character) * scale
                break
        else:
            raise ValueError(f"Invalid reading: {value}")
    query = chr(48 + order % 79) + chr(48 + order // 79)
    if not used or not (used - {3}) or reading(query) != value:
        raise ValueError(f"Invalid reading: {value}")
    return query


def key_count(query: str) -> int:
    value = reading(query)
    return len(value) + (0 if value[-1] in TONES[1:] else 1)


class Lexicon:
    """Freeze text→readings using a reference unigram model, never the tested bigrams."""
    def __init__(self, path: Path, input_path: Path | None = None):
        words = {}
        with connect(path) as db:
            for query, text, score in db.execute("SELECT qstring,current,probability FROM unigrams ORDER BY rowid"):
                if text and all(han(c) for c in text) and len(query) == 2 * len(text):
                    words.setdefault(text, []).append((query, score))
            if db.execute("SELECT 1 FROM sqlite_master WHERE name='Mandarin-bpmf-cin'").fetchone():
                unknown = db.execute("SELECT probability FROM unigrams WHERE qstring='*'").fetchone()[0]
                for query, text in db.execute('SELECT key,value FROM "Mandarin-bpmf-cin" ORDER BY rowid'):
                    if len(text) == 1 and han(text) and len(query) == 2:
                        entries = words.setdefault(text, [])
                        if not any(existing == query for existing, _ in entries):
                            entries.append((query, unknown))
        if READING_OVERRIDES.exists():
            for line_number, raw in enumerate(READING_OVERRIDES.read_text(encoding="utf-8").splitlines(), 1):
                if not raw.strip() or raw.startswith("詞\t"):
                    continue
                fields = raw.split("\t")
                if len(fields) < 2:
                    raise ValueError(f"{READING_OVERRIDES}:{line_number}: expected word and readings")
                word, readings = fields[:2]
                syllables = readings.split()
                if len(syllables) != len(word) or not word or not all(han(character) for character in word):
                    raise ValueError(f"{READING_OVERRIDES}:{line_number}: reading length does not match word")
                query = "".join(query_for_reading(value) for value in syllables)
                # A deliberate typing convention outranks statistical
                # segmentation, while the language model still retains every
                # alternative pronunciation.
                words.setdefault(word, []).insert(0, (query, 1.0))
        # The composer inserts one syllable at a time. Some dictionary phrases
        # contain a reading (usually a neutral tone) that has no standalone
        # syllable row, so that spelling cannot actually be entered. Exclude
        # those phrase readings when freezing the reference pronunciation and
        # let segmentation use a typeable character reading instead.
        if input_path is None:
            input_queries = {query for text, entries in words.items() if len(text) == 1
                             for query, _ in entries}
        else:
            with connect(input_path) as db:
                input_queries = {query for query, text in
                                 db.execute("SELECT qstring,current FROM unigrams WHERE length(current)=1")
                                 if len(query) == 2}
                if db.execute("SELECT 1 FROM sqlite_master WHERE name='Mandarin-bpmf-cin'").fetchone():
                    input_queries.update(query for query, in
                                         db.execute('SELECT key FROM "Mandarin-bpmf-cin" WHERE length(value)=1')
                                         if len(query) == 2)
        self.words = {
            text: [(query, score) for query, score in entries
                   if all(query[i:i + 2] in input_queries for i in range(0, len(query), 2))]
            for text, entries in words.items()
        }
        self.words = {text: entries for text, entries in self.words.items() if entries}
        self.max_length = max(map(len, self.words), default=1)

    def segment(self, text: str, queries: list[str] | None = None) -> list[dict]:
        best = [(float("-inf"), None)] * (len(text) + 1)
        best[0] = (0.0, None)
        for end in range(1, len(text) + 1):
            for start in range(max(0, end - self.max_length), end):
                word = text[start:end]
                for query, score in self.words.get(word, ()):
                    if queries is not None and query != "".join(queries[start:end]):
                        continue
                    total = best[start][0] + score
                    if total > best[end][0]:
                        best[end] = (total, {"start": start, "length": end - start, "text": word, "query": query})
        if best[-1][1] is None and text:
            raise ValueError(f"No dictionary reading for {text!r}; add a lexicon entry or supply valid annotated readings")
        result = []
        end = len(text)
        while end:
            token = best[end][1]
            result.append(token)
            end = token["start"]
        return result[::-1]


def load_document(path: Path, lexicon: Lexicon) -> list[dict]:
    """Plain UTF-8 text, or JSONL {text, readings: [one per Han character]}."""
    source = path.read_text(encoding="utf-8-sig")
    if not source.strip():
        raise ValueError(f"Empty article: {path}")
    if path.suffix == ".jsonl":
        records = [json.loads(line) for line in source.splitlines() if line.strip()]
    else:
        records = [{"text": source}]
    result = []
    for record_index, record in enumerate(records):
        text = record["text"]
        explicit = record.get("readings")
        if not isinstance(text, str) or (explicit is not None and (not isinstance(explicit, list) or len(explicit) != sum(han(c) for c in text))):
            raise ValueError(f"{path}: record {record_index + 1}: readings must match all Han characters")
        reading_index = 0
        for match in re.finditer(r"[\s\S]", text):
            # Group by script without treating spaces as invisible word boundaries.
            character = match.group()
            if result and result[-1]["record"] == record_index and result[-1]["han"] == han(character):
                result[-1]["text"] += character
            else:
                result.append({"text": character, "han": han(character), "record": record_index, "queries": []})
            if han(character) and explicit is not None:
                result[-1]["queries"].append(query_for_reading(explicit[reading_index]))
                reading_index += 1
    for block in result:
        if block["han"]:
            if not block["queries"]:
                tokens = lexicon.segment(block["text"])
                joined = "".join(token["query"] for token in tokens)
                block["queries"] = [joined[i:i + 2] for i in range(0, len(joined), 2)]
            block["tokens"] = lexicon.segment(block["text"], block["queries"])
    if not result or not any(block["text"].strip() for block in result):
        raise ValueError(f"Empty article: {path}")
    return result


@dataclass(frozen=True)
class Policy:
    settle: int = 5
    page_size: int = 8
    interaction: str = "click"
    buffer: int = 10

    def validate(self):
        if not 1 <= self.settle <= self.buffer <= 10:
            raise ValueError("Require 1 <= settle <= buffer <= 10")
        if self.page_size < 1:
            raise ValueError("page size must be positive")
        if self.interaction not in ("click", "keyboard"):
            raise ValueError("interaction must be click or keyboard")


def correction_cost(rank: int, candidate: dict, index: int, size: int, policy: Policy) -> dict:
    counts = {"target_clicks": 0, "cursor_keys": 0, "candidate_open_keys": 0,
              "page_turns": rank // policy.page_size, "candidate_selections": 1, "resume_keys": 0}
    if policy.interaction == "click":
        counts["target_clicks"] = 1  # Tap target and open the list in one gesture.
    else:
        counts["cursor_keys"] = size - index
        counts["candidate_open_keys"] = 1
        counts["resume_keys"] = int(candidate["start"] + candidate["length"] < size)  # End
    return counts


def summarize_corrections(errors: list[dict]) -> tuple[int, list[dict], list[dict]]:
    """Summarize paid selection events and individual corrected characters."""
    grouped: dict[tuple[tuple[str, str], ...], dict] = {}
    characters: dict[str, dict] = {}
    total = 0
    for error in errors:
        action_count = error["action_count"]
        total += action_count
        key = tuple((change["from"], change["to"]) for change in error["changes"])
        row = grouped.setdefault(key, {
            "changes": [{"from": source, "to": target} for source, target in key],
            "events": 0,
            "actions": 0,
        })
        row["events"] += 1
        row["actions"] += action_count
        targets_in_event = set()
        for change in error["changes"]:
            target = change["to"]
            character_row = characters.setdefault(target, {
                "character": target,
                "changes": 0,
                "events": 0,
                "sources": {},
            })
            character_row["changes"] += 1
            character_row["sources"][change["from"]] = character_row["sources"].get(change["from"], 0) + 1
            targets_in_event.add(target)
        for target in targets_in_event:
            characters[target]["events"] += 1
    character_rows = []
    for row in characters.values():
        character_rows.append({
            **{key: value for key, value in row.items() if key != "sources"},
            "sources": [{"from": source, "changes": changes}
                        for source, changes in sorted(row["sources"].items(), key=lambda item: (-item[1], item[0]))],
        })
    character_rows.sort(key=lambda row: (-row["changes"], row["character"]))
    return total, list(grouped.values()), character_rows


def format_evaluation(report: dict) -> str:
    """Keep the total on the first line, followed by correction costs."""
    lines = [str(report["total_actions"]), f"額外修正動作數: {report['correction_actions']}"]
    if not report["correction_summary"]:
        lines.append("額外修正: 無")
        return "\n".join(lines)
    for row in report["correction_summary"]:
        label = "、".join(f"{change['from']}→{change['to']}" for change in row["changes"])
        lines.append(f"{label}: {row['events']} 次修正，{row['actions']} 個動作")
    lines.append("逐字修正次數:")
    for row in report["character_correction_summary"]:
        sources = "、".join(f"{source['from']}→{row['character']} {source['changes']} 次"
                           for source in row["sources"])
        lines.append(f"{row['character']}: {row['changes']} 字次（{sources}；涉及 {row['events']} 次選字）")
    return "\n".join(lines)


def evaluate(document: list[dict], database: Path, policy: Policy) -> dict:
    policy.validate()
    counts = Counter({key: 0 for key in ("phonetic_keys", "literal_keys", "commit_keys", "target_clicks",
                                        "cursor_keys", "candidate_open_keys", "page_turns", "candidate_selections", "resume_keys")})
    errors = []
    syllables = 0
    with Engine(database) as engine:
        for block_index, block in enumerate(document):
            if not block["han"]:
                counts["literal_keys"] += len(block["text"])
                continue
            target, queries = block["text"], block["queries"]
            syllables += len(queries)
            engine.call("reset")
            offset = 0
            state = {"text": "", "segments": []}
            entered = 0
            selections = []

            def correct(limit: int):
                nonlocal state
                attempts = 0
                while True:
                    wanted = target[offset:entered]
                    if len(state["text"]) != len(wanted):
                        raise ValueError(f"Engine output length differs from readings in {wanted!r}")
                    wrong = [i for i in range(limit) if state["text"][i] != wanted[i]]
                    if not wrong:
                        return
                    attempts += 1
                    if attempts > 3 * len(wanted):
                        raise ValueError(f"Candidate corrections do not converge for {wanted!r}")
                    index = wrong[0]
                    candidates = engine.call("candidates", index)
                    choices = []
                    for rank, candidate in enumerate(candidates):
                        start, length = candidate["start"], candidate["length"]
                        if candidate["text"] != wanted[start:start + length]:
                            continue
                        absolute_start, absolute_end = offset + start, offset + start + length
                        # A partially overlapping word can cancel a previous override
                        # (e.g. 再出 → 出門 → 再出 forever). Keep prior explicit
                        # choices unless this candidate replaces their entire span.
                        if any(absolute_start < old_end and absolute_end > old_start and
                               not (absolute_start <= old_start and absolute_end >= old_end)
                               for old_start, old_end in selections):
                            continue
                        cost = correction_cost(rank, candidate, index, len(wanted), policy)
                        choices.append((sum(cost.values()), -length, rank, candidate, cost))
                    if not choices:
                        raise ValueError(f"No selectable candidate for {wanted[index]!r} ({reading(queries[offset + index])}); cannot report a successful typing cost")
                    _, _, rank, candidate, cost = min(choices, key=lambda item: item[:3])
                    before_text = state["text"]
                    before_segments = state["segments"]
                    counts.update(cost)
                    state = engine.call("select", rank)
                    changes = [
                        {"index": offset + position, "from": before, "to": expected}
                        for position, (before, after, expected) in enumerate(zip(before_text, state["text"], wanted))
                        if before != expected and after == expected
                    ]
                    if not changes:
                        raise ValueError(f"Candidate selection did not correct any target character in {wanted!r}")
                    errors.append({"block": block_index, "entered": entered, "offset": offset, "index": offset + index,
                                   "target": wanted, "before": before_text, "after": state["text"],
                                   "changes": changes, "candidate_rank": rank + 1, "candidate": candidate,
                                   "actions": cost, "action_count": sum(cost.values()),
                                   "segments_before": before_segments})
                    selections.append((offset + candidate["start"], offset + candidate["start"] + candidate["length"]))

            for entered, query in enumerate(queries, 1):
                counts["phonetic_keys"] += key_count(query)
                state = engine.call("insert", query)
                # Recheck aged characters too: late changes are never silently frozen.
                correct(max(0, entered - offset - policy.settle + 1))
                if entered - offset > policy.buffer:
                    # The production composer shifts a complete first word. Audit that
                    # whole word at the commit boundary, including younger syllables.
                    correct(state["segments"][0]["length"])
                    state = engine.call("shift")
                    popped = state["popped"]
                    if not popped or popped != target[offset:offset + len(popped)]:
                        raise ValueError("Committed text differs from target")
                    offset += len(popped)
            correct(entered - offset)  # No uncharged final tail.
            counts["commit_keys"] += 1
    correction_actions, correction_summary, character_correction_summary = summarize_corrections(errors)
    return {"total_actions": sum(counts.values()), "actions": dict(counts), "syllables": syllables,
            "corrections": len(errors), "correction_actions": correction_actions,
            "correction_summary": correction_summary,
            "character_correction_summary": character_correction_summary,
            "errors": errors, "policy": asdict(policy)}


def add_arguments(parser: argparse.ArgumentParser):
    parser.add_argument("article", type=Path, help="UTF-8 text or annotated JSONL")
    parser.add_argument("version", help="current / unigram / bootstrap / articles-N / .db / repair .json")
    parser.add_argument("--reference-db", type=Path, default=DEFAULT_DB, help="fixed text-to-reading dictionary shared by A/B runs")
    parser.add_argument("--settle", type=int, default=5, help="check a syllable when this many syllables including itself have arrived")
    parser.add_argument("--page-size", type=int, default=8)
    parser.add_argument("--interaction", choices=("click", "keyboard"), default="click")
    parser.add_argument("--buffer", type=int, default=10)


def policy_from(args) -> Policy:
    policy = Policy(args.settle, args.page_size, args.interaction, args.buffer)
    policy.validate()
    return policy


def write_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def evaluate_main():
    parser = argparse.ArgumentParser(description="量測好打注音動作數，並列出額外修正的字與動作數。")
    add_arguments(parser)
    parser.add_argument("--report", type=Path, help="optional JSON action breakdown and correction trace")
    args = parser.parse_args()
    try:
        policy = policy_from(args)
        database = resolve_version(args.version)
        if args.report and args.report.resolve() in {args.article.resolve(), database.resolve(), args.reference_db.resolve()}:
            raise ValueError("Report path must not overwrite the article or model")
        lexicon = Lexicon(args.reference_db)
        document = load_document(args.article, lexicon)
        report = evaluate(document, database, policy)
        report.update({"article": str(args.article), "article_sha256": sha256(args.article), "version": args.version,
                       "database_sha256": sha256(database), "reference_sha256": sha256(args.reference_db),
                       "engine": "production ManjusriComposer (macOS/Windows); offline action policy",
                       "readings": [{"text": b["text"], "readings": [reading(q) for q in b["queries"]]} for b in document if b["han"]]})
        if args.report:
            write_json(args.report, report)
        print(format_evaluation(report))
    except (ValueError, OSError, sqlite3.Error, subprocess.SubprocessError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")
