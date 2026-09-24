#!/usr/bin/env python3

"""Generate 10,000 deterministic Traditional Chinese training sentences."""

from pathlib import Path
import hashlib
import re
import runpy


GENERAL_MODIFIERS = [
    "通常 會",
    "多半 會",
    "也 會",
    "必要 時 會",
    "會 記得",
    "習慣 先",
    "往往 會",
    "有時 會",
    "最好 先",
    "會 依照 情況",
]

WEATHER_MODIFIERS = [
    "依照 預報",
    "目前 看來",
    "大致 上",
    "預計",
    "有時",
    "受到 季風 影響",
    "根據 最新 資料",
    "在 午後",
    "從 雷達 看來",
    "隨著 氣候 變化",
]

SAFETY_MODIFIERS = [
    "應該 立即",
    "務必",
    "要 先",
    "需要",
    "記得",
    "一定 要",
    "應當",
    "最好 立即",
    "必須",
    "可以 先",
]

CITY_MODIFIERS = [
    "通常",
    "有時",
    "往往",
    "看起來",
    "在 假日",
    "受到 天氣 影響 時",
    "對 遊客 來說",
    "從 當地 情況 看來",
    "在 活動 舉辦 時",
    "在 人潮 增加 時",
]

CAREFUL_MODIFIERS = [
    "應該 先",
    "最好 先",
    "需要",
    "務必",
    "可以 先",
    "記得",
    "通常 會",
    "會 再次",
    "要 仔細",
    "會 依照 規定",
]

MODIFIER_BANK_BY_TITLE = {
    "Rain and weather": WEATHER_MODIFIERS,
    "Emergency safety": SAFETY_MODIFIERS,
    "Taiwan city life": CITY_MODIFIERS,
    "Driving and cycling": CAREFUL_MODIFIERS,
    "Medical visits": CAREFUL_MODIFIERS,
    "Public services": CAREFUL_MODIFIERS,
    "Payments and banking": CAREFUL_MODIFIERS,
    "Account security": CAREFUL_MODIFIERS,
    "Customer support": CAREFUL_MODIFIERS,
}

LEADING_MODAL_WORDS = {"會", "可以", "應該", "要", "記得", "先"}


def remove_leading_modal(ending):
    fields = ending.split()
    while fields and fields[0] in LEADING_MODAL_WORDS:
        fields.pop(0)
    return " ".join(fields)


def corpus_sentences(path):
    return {
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }


def main():
    directory = Path(__file__).parent
    v2_namespace = runpy.run_path(str(directory / "generate-corpus-v2.py"))
    sections = v2_namespace["SECTIONS"]
    output = directory / "corpus-v3.txt"
    lines = []
    sentences = []

    for title, beginnings, endings in sections:
        modifiers = MODIFIER_BANK_BY_TITLE.get(title, GENERAL_MODIFIERS)
        if len(beginnings) != 5 or len(endings) != 5 or len(modifiers) != 10:
            raise ValueError(f"{title}: expected 5 beginnings, 5 endings, and 10 modifiers")

        section_sentences = []
        for beginning in beginnings:
            for ending in endings:
                action = remove_leading_modal(ending)
                for modifier in modifiers:
                    sentence = f"{beginning} {modifier} {action}"
                    han_length = len(re.findall(r"[\u3400-\u9fff]", sentence))
                    if not 10 <= han_length <= 45:
                        raise ValueError(f"{title}: sentence length {han_length}: {sentence}")
                    section_sentences.append(sentence)

        # A content hash provides deterministic interleaving without leaving
        # identical template beginnings next to one another in the corpus.
        section_sentences.sort(
            key=lambda sentence: hashlib.sha256(
                f"{title}\0{sentence}".encode("utf-8")
            ).digest()
        )
        lines.append(f"# {title}")
        sentences.extend(section_sentences)
        lines.extend(section_sentences)
        lines.append("")

    if len(sections) != 40 or len(sentences) != 10_000:
        raise ValueError(
            f"expected 40 sections and 10000 sentences, got {len(sections)} and {len(sentences)}"
        )
    if len(set(sentences)) != len(sentences):
        raise ValueError("generated corpus contains duplicate sentences")
    earlier_sentences = corpus_sentences(directory / "corpus-v1.txt")
    earlier_sentences.update(corpus_sentences(directory / "corpus-v2.txt"))
    overlap = earlier_sentences.intersection(sentences)
    if overlap:
        raise ValueError(f"generated corpus duplicates {len(overlap)} earlier sentences")

    output.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    print(f"wrote {len(sentences)} unique sentences to {output}")


if __name__ == "__main__":
    main()
