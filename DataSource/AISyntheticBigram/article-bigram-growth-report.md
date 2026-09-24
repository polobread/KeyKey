# Synthetic article bigram growth experiment

The experiment uses the production `SmartMandarinCooker.rb`, the three existing bootstrap corpora, and cumulative article snapshots listed below. Synthetic text bigrams remain capped at one observation each with unigram prior strength 1,000.

## Growth

| Articles | Segmented sequences | Tokens | SQLite bigram rows | Distinct text pairs | New pairs vs baseline | New pairs in this block | New pairs/article | DB increase |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 27,356 | 205,554 | 87,239 | 52,201 | 48,129 | 48,129 | 481.3 | 3.95 MiB |
| 200 | 44,032 | 276,756 | 145,617 | 87,841 | 83,769 | 35,640 | 356.4 | 6.88 MiB |
| 300 | 60,202 | 349,336 | 190,384 | 115,016 | 110,944 | 27,175 | 271.8 | 9.11 MiB |
| 400 | 75,986 | 419,315 | 236,661 | 143,797 | 139,725 | 28,781 | 287.8 | 11.46 MiB |
| 450 | 83,782 | 453,953 | 259,199 | 157,676 | 153,604 | 13,879 | 277.6 | 12.59 MiB |
| 500 | 91,226 | 488,926 | 281,033 | 171,493 | 167,421 | 13,817 | 276.3 | 13.69 MiB |
| 700 | 123,275 | 633,606 | 365,513 | 224,507 | 220,435 | 53,014 | 265.1 | 17.96 MiB |
| 900 | 155,085 | 773,390 | 435,157 | 269,227 | 265,155 | 44,720 | 223.6 | 21.52 MiB |
| 1100 | 186,607 | 913,392 | 502,984 | 312,916 | 308,844 | 43,689 | 218.4 | 24.97 MiB |
| 1300 | 218,738 | 1,058,550 | 566,384 | 353,867 | 349,795 | 40,951 | 204.8 | 28.20 MiB |
| 1500 | 250,470 | 1,200,181 | 626,015 | 392,583 | 388,511 | 38,716 | 193.6 | 31.26 MiB |
| 1650 | 274,339 | 1,308,908 | 668,529 | 420,714 | 416,642 | 28,131 | 187.5 | 33.45 MiB |

## Held-out lexical-pair coverage

### Articles 201–300

This block contains 35,174 distinct lexical text bigrams after production segmentation.

| Training corpus | Covered pairs | Coverage |
| --- | ---: | ---: |
| existing bootstrap | 447 | 1.27% |
| bootstrap + first 100 articles | 6,806 | 19.35% |
| bootstrap + first 200 articles | 9,645 | 27.42% |
| bootstrap + first 300 articles (in sample) | 35,174 | 100.00% |
| bootstrap + first 400 articles (in sample) | 35,174 | 100.00% |
| bootstrap + first 450 articles (in sample) | 35,174 | 100.00% |
| bootstrap + first 500 articles (in sample) | 35,174 | 100.00% |
| bootstrap + first 700 articles (in sample) | 35,174 | 100.00% |
| bootstrap + first 900 articles (in sample) | 35,174 | 100.00% |
| bootstrap + first 1100 articles (in sample) | 35,174 | 100.00% |
| bootstrap + first 1300 articles (in sample) | 35,174 | 100.00% |
| bootstrap + first 1500 articles (in sample) | 35,174 | 100.00% |
| bootstrap + first 1650 articles (in sample) | 35,174 | 100.00% |

### Articles 1551–1650

This block contains 41,999 distinct lexical text bigrams after production segmentation.

| Training corpus | Covered pairs | Coverage |
| --- | ---: | ---: |
| existing bootstrap | 537 | 1.28% |
| bootstrap + first 100 articles | 7,696 | 18.32% |
| bootstrap + first 200 articles | 11,104 | 26.44% |
| bootstrap + first 300 articles | 13,129 | 31.26% |
| bootstrap + first 400 articles | 14,951 | 35.60% |
| bootstrap + first 450 articles | 15,714 | 37.42% |
| bootstrap + first 500 articles | 16,391 | 39.03% |
| bootstrap + first 700 articles | 18,594 | 44.27% |
| bootstrap + first 900 articles | 20,172 | 48.03% |
| bootstrap + first 1100 articles | 21,436 | 51.04% |
| bootstrap + first 1300 articles | 22,512 | 53.60% |
| bootstrap + first 1500 articles | 23,357 | 55.61% |
| bootstrap + first 1650 articles (in sample) | 41,999 | 100.00% |

## Explicit-pair score lift

The multiplier compares a newly explicit lexical bigram with the same model's unigram-plus-backoff score. It measures local language-model influence, not end-to-end candidate accuracy.

| Added article block | New reading-expanded rows measured | Median score lift | Median probability multiplier | P10–P90 log10 lift |
| --- | ---: | ---: | ---: | ---: |
| 1–100 | 74,117 | 0.862 | 7.3× | 0.112–2.481 |
| 101–200 | 55,429 | 1.001 | 10.0× | 0.129–2.536 |
| 201–300 | 42,977 | 1.026 | 10.6× | 0.158–2.607 |
| 301–400 | 44,593 | 1.037 | 10.9× | 0.164–2.592 |
| 401–450 | 21,762 | 1.075 | 11.9× | 0.164–2.683 |
| 451–500 | 21,168 | 1.112 | 13.0× | 0.165–2.656 |
| 501–700 | 82,098 | 1.149 | 14.1× | 0.165–2.683 |
| 701–900 | 67,942 | 1.218 | 16.5× | 0.168–2.722 |
| 901–1100 | 66,192 | 1.240 | 17.4× | 0.167–2.753 |
| 1101–1300 | 62,197 | 1.209 | 16.2× | 0.179–2.732 |
| 1301–1500 | 58,391 | 1.258 | 18.1× | 0.184–2.775 |
| 1501–1650 | 41,865 | 1.291 | 19.5× | 0.189–2.753 |

## Interpretation

- The first 100 articles add 48,129 text pairs.
- Coverage of unseen articles 201–300 rises from 1.27% with the existing bootstrap corpus to 19.35% after 100 articles and 27.42% after 200 articles.
- Results at 300 articles and above are in-sample for articles 201–300, so their inclusion is not reported as generalization.
- Moving from 1500 to 1650 articles adds 28,131 distinct text pairs and 42,514 reading-expanded SQLite rows; the database grows by another 2.19 MiB.
- Moving from 500 to 700 articles adds 53,014 distinct text pairs, 84,480 reading-expanded rows, and 4.27 MiB. Coverage of held-out articles 1,551–1,650 rises by 5.25 percentage points.
- A power-law fit over blocks 501–1,650 estimates about 2,982 articles before marginal yield falls below 150 new text pairs per article, and about 9,903 before it falls below 100. These are planning estimates rather than a stopping guarantee.
- Pair coverage and score lift do not prove better candidate ordering. A/B typing tests on held-out keystroke sequences remain necessary before enabling an article snapshot in the shipping database.
