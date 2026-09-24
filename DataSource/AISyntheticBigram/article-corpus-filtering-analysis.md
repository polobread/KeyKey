# Article corpus filtering experiment

Exact duplicates are compared with conservative near-duplicate filtering (normalized-character 5-gram Jaccard >= 0.86, length ratio >= 0.90).

## Full 1,650-article database

| Variant | Corpus lines | Removed lines | Text pairs | Pairs retained | SQLite rows | DB size | Size saved |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| raw | 46,749 | 0 | 420,714 | 100.000% | 668,529 | 41.30 MiB | 0.00 MiB |
| exact dedup | 41,040 | 5,709 | 420,713 | 100.000% | 668,527 | 41.30 MiB | 0.00 MiB |
| near dedup | 41,003 | 5,746 | 420,711 | 99.999% | 668,523 | 41.30 MiB | 0.00 MiB |

## Held-out articles 1,551–1,650

Training uses articles 1–1,500. The held-out block contains 41,999 lexical pairs.

| Training variant | Covered pairs | Coverage | Change from raw |
| --- | ---: | ---: | ---: |
| raw | 23,357 | 55.613% | +0.000 pp |
| exact dedup | 23,357 | 55.613% | +0.000 pp |
| near dedup | 23,357 | 55.613% | +0.000 pp |

## Result

- Exact line deduplication removes 5,709 repeated lines, but saves only 0.00 MiB because the production cooker already caps every synthetic pair at one observation.
- Conservative near deduplication removes 37 additional lines and saves 0.00 MiB relative to raw.
- Near deduplication retains 99.999% of text pairs and changes held-out coverage by +0.000 percentage points.
- Filtering repeated paragraphs does not materially solve database growth; selecting a smaller article snapshot or pruning low-value bigram rows is more effective.
