# Versioned article bigram impact

Each stage uses the same three bootstrap corpora, typing feedback, McBopomofo vocabulary, project supplemental lexicon, and enumerated number-unit lexicon. The article corpus removes only identical lines; each synthetic text pair counts once.

| Articles | Bigram rows | Distinct text pairs | Added pairs | Lost pairs | Minimal DB | DB change |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,650 | 670,811 | 420,835 | 0 | 0 | 41.48 MiB | +0.00 MiB |
| 2,000 | 767,091 | 483,142 | 62,307 | 0 | 46.37 MiB | +4.89 MiB |
| 2,300 | 885,614 | 560,140 | 76,998 | 0 | 52.47 MiB | +6.10 MiB |

The figures measure stored adjacent-word coverage and database size. Candidate-order quality still requires typing evaluation.
