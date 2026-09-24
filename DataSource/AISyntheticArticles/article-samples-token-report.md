# Article sample token report

Tokenizer: `o200k_base`

These are reproducible counts for the saved generation prompt and article body. They are not Codex account usage or billable API usage. Chat wrappers, tool calls, hidden context, reasoning, and retries are not included.

| Prompt | Title | Visible chars | Han chars | Input tokens | Output tokens | Total |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| tw-writing-0001 | 月台邊的舊布包 | 1,334 | 1,179 | 435 | 1,360 | 1,795 |
| tw-writing-0002 | 掌心裡的教室：手機與學生學習 | 1,463 | 1,325 | 356 | 1,302 | 1,658 |
| tw-writing-0004 | 期待的重量：現代父母與子女之間 | 1,548 | 1,350 | 363 | 1,410 | 1,773 |
| **Total** |  | **4,345** | **3,854** | **1,154** | **4,072** | **5,226** |

## Reproduce

```sh
PYTHONPATH=/tmp/keykey-tokenizer /usr/bin/python3 analyze-article-samples.py
```
