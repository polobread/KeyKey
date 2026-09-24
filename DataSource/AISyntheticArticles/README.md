# AI synthetic article assignments

This directory contains writing assignments only. It does not contain generated
article prose and does not invoke a local or remote language model.

Run `python3 generate-writing-prompts.py` to reproduce
`writing-prompts-v1.jsonl` and the smaller Markdown preview. Every JSONL record
contains an era, genre, unique title, target length, point of view, scenario,
required aspects, language constraints, exclusions, and evaluation criteria.

The dataset contains 3,000 assignments of about 1,200 Traditional Chinese
characters each. Exactly 1,500 assignments cover 1997–2026, so the most recent
30 years account for 50 percent of the plan. The remaining half provides
historical variety without claiming that the generated assignments or future
articles are primary historical sources.

## Era distribution

| Era | Assignments | Share |
| --- | ---: | ---: |
| 1926–1945 | 300 | 10% |
| 1946–1969 | 360 | 12% |
| 1970–1989 | 540 | 18% |
| 1990–1996 | 300 | 10% |
| 1997–2009 | 450 | 15% |
| 2010–2019 | 450 | 15% |
| 2020–2026 | 600 | 20% |

Before article generation, review the prompt set for factual framing,
anachronisms, repetitive titles, and genre balance. Future article generation
must write to a separate versioned JSONL file so prompt review remains
independent from prose review.

## Three-article sample

`article-samples-v1/` contains three complete prose samples selected from the
assignment set. `analyze-article-samples.py` validates their titles, exports
`article-samples-v1.jsonl`, and writes character and `o200k_base` token counts
to `article-samples-token-report.json` and `.md`.

Token counts cover a compact, saved generation prompt and the article body.
They deliberately exclude chat wrappers, hidden context, reasoning, tool calls,
retries, and billing/account usage, which this repository cannot observe.

## Typing-situation prompt set v2

`generate-typing-prompts-v2.py` produces 10,000 assignments centered on text
people might actually type: everyday coordination, work, arguments, comfort,
encouragement, service disputes, law and policy, casual joking, accommodation,
food and entertainment, product names, Taiwan landmarks, and Traditional
Chinese names for international attractions.

The international-name assignments are deliberately limited to 650 total:
200 for Japan, 100 for the United States, 100 for China, 100 for Europe, and
150 covering other countries. These use Taiwan Traditional Chinese names and
remain separate categories so their contribution can be weighted later.

Exactly 7,000 assignments cover 1997–2026. The recent 30 years therefore make
up 70 percent of v2. The older 30 percent uses era-compatible letters, notes,
documents, bulletin-board posts, and other written channels. V1 remains intact
for comparison.

| Era | V2 assignments | Share |
| --- | ---: | ---: |
| 1926–1945 | 500 | 5% |
| 1946–1969 | 800 | 8% |
| 1970–1989 | 1,100 | 11% |
| 1990–1996 | 600 | 6% |
| 1997–2009 | 1,800 | 18% |
| 2010–2019 | 2,200 | 22% |
| 2020–2026 | 3,000 | 30% |

Run `python3 generate-typing-prompts-v2.py` to reproduce:

- `typing-prompts-v2.jsonl`
- `typing-prompts-v2-preview.md`
- `typing-prompts-v2-stats.json`

## V2 article generation

The first 1,650 accepted article bodies are saved in
`typing-articles-v2-seed/`. Run
`python3 validate-article-seeds.py --start 1 --end 1650` to check exact titles,
the 1,050–1,350 Han-character range, named entities, duplicate bodies, and a
curated set of non-Taiwan usages. Taiwan wording is mandatory except for the
explicit `中國繁中地名與旅行` category. Run
`python3 import-article-batch-results.py` to validate and consolidate them.
The current consolidated `typing-articles-v2.jsonl` contains 1,650 valid
Codex-authored articles, zero rejected articles, and no API-token usage.

`build-article-batches.py` can convert unfinished v2 prompts into 500-request
OpenAI Batch API JSONL files. It defaults to `gpt-6-luna` with reasoning set to
`none` and skips completed articles. `openai-batch-client.py` submits one file at a time,
checks its status, and downloads its result. It requires `OPENAI_API_KEY` in
the environment and never writes the key to disk.

After downloading one or more output files, pass them to
`import-article-batch-results.py`. The importer maps results by `custom_id`,
checks the 1,050–1,350 Han-character range, separates rejected output, and
records exact API usage returned with successful responses.

## Typing-test feedback

Real-world typing tests identified official-document and legal wording as an
important source of candidate contexts. Legal, policy, official-document, and
formal-document assignments should naturally vary expressions around `擬`,
`研擬`, `擬定`, `擬具`, `擬辦`, `涉`, `涉及`, `涉嫌`, `涉案`, `嚴查`,
`查辦`, `相關規定`, and `相關資料`. They should also preserve varied natural
contexts for the connectors `又`, `和`, and `與`. These terms are contextual
guidance rather than per-article quotas; forcing the same phrase into every
article would reduce bigram diversity.

The user-reported `蝦皮購物` brand term is stored as a complete lexical entry in
`../AISyntheticBigram/supplemental-lexicon.tsv`. Its order, seller, chat,
delivery, convenience-store pickup, return, refund, invoice, and customer
service contexts live in `../AISyntheticBigram/corpus-typing-feedback.txt`.
The categorized associated-phrase collection also contains the complete term.

## Gap-filling prompt set v3

`generate-typing-prompts-v3.py` produces a separate 350-assignment supplement;
it does not change the v2 prompts or the accepted v2 article bodies. The design
is based on `typing-articles-v2-attribute-report.md` and concentrates on work
discussion, official and legal documents, emotional dialogue, colloquial humor,
short messages, customer-service disputes, and mixed Chinese/Latin/numeric
input.

V3 keeps 1997–2026 at exactly 70 percent. Its tone quotas are conditioned on
the topic rather than chosen uniformly. It also contains 95 short-message
packets, 75 formal documents, 120 unresolved or partially resolved outcomes,
110 assignments with an explicit mixed-input feature, and eight assignments
that require natural `蝦皮購物` contexts.

Run `python3 generate-typing-prompts-v3.py` to reproduce:

- `typing-prompts-v3.jsonl`
- `typing-prompts-v3-preview.md`
- `typing-prompts-v3-stats.json`
- `typing-prompts-v3-plan.md`

V3's 350 validated articles live in `typing-articles-v3-seed/` and are exported
to `typing-articles-v3.jsonl`, separate from the 1,650 accepted v2 bodies.
Validate a completed range with
`python3 validate-versioned-articles.py --version 3 --start 1 --end 350`.
Use `--allow-missing` while drafting. The validator checks titles, per-prompt
lengths, required entities, Taiwan usage, and duplicate bodies. The complete
350-article set can be reproduced with `--write-jsonl`.

## Vocabulary-guided prompt set v4

`generate-typing-prompts-v4.py` builds 300 modern Taiwan writing assignments
from a fixed pool of 6,000 distinct terms. The pool includes every one of the
3,758 distinct terms represented by the 4,012 valid rows in the 28 categorized
lexicons other than `phrase.anime.tsv`; the remaining 2,242 terms are selected
from McBopomofo with deterministic frequency-weighted sampling.

The generator first places explicit synonym and near-synonym sets together,
then keeps terms sharing a useful two-character concept core together where
possible. It packs the pool into 200 base bundles of 30 terms. One hundred
bundles receive a complementary second assignment, producing 300 assignments
and 9,000 assigned-term slots. Each assignment designates 15 required terms;
the two assignments sharing a bundle use opposite halves. Explicit synonym
sets never split across bundles or required halves.

Run `python3 generate-typing-prompts-v4.py` to reproduce:

- `typing-prompts-v4.jsonl`
- `typing-prompts-v4-preview.md`
- `typing-prompts-v4-stats.json`
- `typing-prompts-v4-plan.md`
- `typing-prompts-v4-term-assignments.tsv`

V4's 300 validated articles live in `typing-articles-v4-seed/` and are exported
to `typing-articles-v4.jsonl`. Validate the complete set with
`python3 validate-versioned-articles.py --version 4 --start 1 --end 300`.
`--write-jsonl` reproduces the export after all 300 articles pass. Every
article uses its 15 required terms in context and meets its prompt's character
range. The v2, v3, and v4 exports feed the versioned Smart Mandarin bigram
corpus built by `../AISyntheticBigram/build-versioned-article-corpus.py`.
