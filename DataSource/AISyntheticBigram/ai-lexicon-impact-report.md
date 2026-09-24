# AI lexicon impact on Smart Mandarin bigrams

All variants use the three bootstrap corpora, typing feedback, and the 1,650-article corpus. Only the lexical sources change.

## Full model

| Variant | Words | New words | Bigram rows | Text pairs | Added pairs | Lost pairs | Tokens | DB size | Size change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| current McBopomofo + project supplemental | 107,385 | 0 | 668,698 | 420,820 | 0 | 0 | 1,309,158 | 41.31 MiB | +0.00 MiB |
| preserve counts: anime | 109,582 | 2,197 | 668,732 | 420,867 | 149 | 102 | 1,308,866 | 41.49 MiB | +0.18 MiB |
| preserve counts: other 28 | 110,001 | 2,616 | 668,777 | 421,105 | 990 | 705 | 1,307,985 | 41.55 MiB | +0.24 MiB |
| preserve counts: all 29 | 112,191 | 4,806 | 668,808 | 421,154 | 1,134 | 800 | 1,307,696 | 41.72 MiB | +0.41 MiB |
| direct merge: anime | 109,582 | 2,197 | 668,732 | 420,867 | 149 | 102 | 1,308,866 | 41.49 MiB | +0.18 MiB |
| direct merge: other 28 | 110,001 | 2,616 | 668,777 | 421,105 | 990 | 705 | 1,307,985 | 41.55 MiB | +0.24 MiB |
| direct merge: all 29 | 112,191 | 4,806 | 668,808 | 421,154 | 1,134 | 800 | 1,307,696 | 41.72 MiB | +0.41 MiB |

Preserving McBopomofo counts and directly applying the AI counts produce identical results here. The AI counts are not high enough to replace existing McBopomofo counts; the observed changes come from added words or readings.

## Held-out articles 1,551–1,650

Each row segments the held-out block with the same lexicon as its training model, so pair denominators can differ.

| Variant | Held-out lexical pairs | Covered | Coverage | Change from current |
| --- | ---: | ---: | ---: | ---: |
| current McBopomofo + project supplemental | 41,998 | 23,357 | 55.615% | +0.000 pp |
| preserve counts: anime | 41,995 | 23,352 | 55.607% | -0.008 pp |
| preserve counts: other 28 | 41,996 | 23,334 | 55.562% | -0.052 pp |
| preserve counts: all 29 | 41,993 | 23,328 | 55.552% | -0.062 pp |
| direct merge: anime | 41,995 | 23,352 | 55.607% | -0.008 pp |
| direct merge: other 28 | 41,996 | 23,334 | 55.562% | -0.052 pp |
| direct merge: all 29 | 41,993 | 23,328 | 55.552% | -0.062 pp |

## Dictionary use in the 1,650 articles

Surface matches count only entries absent from the current McBopomofo plus project supplemental vocabulary.

| Lexicon group | Entries | New entries | New entries seen | Entry coverage | Occurrences |
| --- | ---: | ---: | ---: | ---: | ---: |
| anime | 2,533 | 2,197 | 43 | 1.96% | 1,211 |
| other_28 | 3,755 | 2,616 | 104 | 3.98% | 1,524 |
| all_29 | 6,262 | 4,806 | 147 | 3.06% | 2,735 |

## Anime assessment

- Anime contributes 2,197 words absent from the current vocabulary, but only 43 (1.96%) appear in the 1,650 general typing articles.
- The most frequent new surface match is `到我` (871 occurrences), an incomplete fragment derived from a work title. Surface occurrence does not mean the segmenter selects it, but it shows that title fragments can compete in ordinary text.
- New anime words that actually participate in the most changed pair contexts include `小豪` (13), `借物` (11), `小傑` (11), `白川` (11), `小玲` (9), `小珊` (8), `相信你` (6), `露易絲` (5). Examples of collapsed ordinary pairs include `約／成 → 約成`, `借／物 → 借物`, `物／主 → 物主`, and `任務／完成 → 任務完成`.
- Count-preserving anime merge changes 251 text-pair identities while growing the database by 0.18 MiB. Its held-out coverage change is -0.008 percentage points.
- Direct anime merge gives the same 251 changed pair identities and -0.008-point coverage change, confirming that count overwrite is not the cause in this dataset.
- Keep anime as an opt-in domain lexicon unless incomplete title fragments and generic phrases receive a dedicated review.

## Recommendation

Do not merge all 29 collections into the core Smart Mandarin vocabulary as-is. Review the 104 non-anime new entries that actually occur in the 1,650 articles, then test a compact allowlist and candidate ordering. Keep anime separate and opt-in: most of its new vocabulary is unseen in general typing text, while title fragments can create frequent false phrase boundaries.
