# 好打注音動作數評測

這組工具以實際的 `OVIMSmartMandarin.h`／`ManjusriComposer` 離線重播文章，量測輸入注音、確認、修正選字與翻頁需要的動作數。從 KeyKey 儲存庫根目錄執行；需要 Python 3.10 以上、C++17 編譯器及 SQLite 開發函式庫。

## 單篇量測

```sh
python3 DataSource/AISyntheticBigram/measure-typing-cost.py 文章.txt current
```

標準輸出的第一行是總動作數，後面列出額外修正動作總數、畫面錯字到正確字的修正次數與動作數，以及逐字修正摘要。例如：

```text
879
額外修正動作數: 16
界→借: 1 次修正，2 個動作
在→再: 1 次修正，2 個動作
逐字修正次數:
借: 1 字次（界→借 1 次；涉及 1 次選字）
再: 1 字次（在→再 1 次；涉及 1 次選字）
```

同一次選詞若修正多個字，只計一次選詞成本。`--report` 產生的 JSON 會保存 `correction_actions`、`correction_summary`、`character_correction_summary`，以及每次錯誤的 `before`、`after`、`changes`、候選順位與 `action_count`。

```sh
python3 DataSource/AISyntheticBigram/measure-typing-cost.py 文章.txt current \
  --settle 5 --buffer 10 --page-size 8 \
  --report /tmp/typing-report.json
python3 DataSource/AISyntheticBigram/measure-typing-cost.py 文章.txt /tmp/候選模型.db
```

版本參數可用 `current`、`unigram`、`bootstrap`、`articles-N`、`v2`、`v4`、共用 schema 的 `.db` 路徑，或版本 manifest `.json`。`project-unigram-v1` 與 `project-unigram-v2` 只用來重現已淘汰的 800／750／750 unigram 實驗，不是目前 bigram 的建模或驗收來源。

## 每篇都是獨立測驗

每次 `evaluate()` 都啟動全新的 C++ 行程並重新載入模型。`useUserTable`、`useUserBigramCache`、`useUserCandidateOverrideCache` 全部關閉，SQLite 使用 `query_only=ON`，不讀寫使用者學習資料。每段中文字開始時也會清空 composer。

同一段組字內保留剛選好的字，才能模擬改字後繼續輸入；這個狀態不會帶到下一段、下一篇或下一次測試。磁碟快取只包含編譯好的測試 adapter 與由固定來源建立的模型，不包含選字記憶。

## 動作定義

| 動作 | 計數 |
| --- | --- |
| 輸入注音 | 每個注音符號一鍵，聲調鍵另計；第一聲確認空白也算一鍵 |
| 非漢字 | 每個 Unicode 字元一個直接輸入動作，包括標點、空白、英數與換行 |
| 完成一段中文字 | Enter 確認一次；標點、空白、英數或換行會切段 |
| 點字模式 | 點目標並開候選一次、每次翻頁一次、選定候選一次 |
| 鍵盤模式 | Left、Down、PageDown、數字選字與必要的 End 分別計一次 |

預設每頁 8 個候選。第 1–8 個不用翻頁，第 9–16 個翻一次，依此類推。候選順序直接取自引擎，包含詞組。

`--settle 5` 表示輸入包含目標字在內的 5 個音節後檢查該字；結尾不足 5 音節的部分仍會檢查。每次只把已輸入讀音交給引擎，不預看文章後文。已檢查的字若後來再變錯，會再次計算修正。

`--buffer 10` 對應好打注音約 9–10 字的可修正範圍。插入第 11 個音節前會檢查最前方完整詞，再呼叫正式 composer 的 `shift()`。這是固定的離線操作成本模型，不代表各平台 UI 的實機逐鍵時間。

修正策略先找能符合原文的候選，再選動作較少者；同成本時優先較長詞，最後依候選順位決定。它不會選擇會拆掉先前手動修正詞組的重疊候選，避免重複修正迴圈。

## 正式資料範圍

- Bigram 以 2,300 篇 `typing-articles-v2`、`v3`、`v4` 建模。
- 固定驗證集是 `DataSource/AISyntheticArticles/typing-articles-v5-seed/` 的 130 篇 Markdown，排除 `chat.md`。
- 隨機抽 50 篇只用於探索問題分布，不能取代固定 130 篇驗收。
- 800／750／750 是已結束的 unigram 實驗切分，不再用來判斷 bigram。

完整正式模型來源、保護規則與 130 篇結果見 [SMART_MANDARIN_MODEL_V1_3_1.md](SMART_MANDARIN_MODEL_V1_3_1.md)。

Bigram 只能在有限組字窗內改善上下文，因此驗收先看基本字是否減少修正，再看一般字整體穩定性：

- 核心 83 字和常見程度前 100 名是基本字指標。
- 第 101–1,000 名是一般字穩定性指標。
- 第 1,001–1,500 名、清單外罕見字、專業詞與專有名詞保留在診斷報告，不列入主要驗收分數。

`common-single-character-words.tsv` 是核心單字清單；`common-single-character-pronunciations-1500.tsv` 是依臺灣常見書面與對話使用整理的 1,500 字分層資料。這些清單用來分析，不可直接變成逐字加權或針對錯字補丁。

模型調整必須先看整批文章的錯誤分布，再訂一條可套用全體資料的規則。不得看一篇改一篇、為單一 bigram 邊加特例，或只以少數文章下降宣稱改善。正式候選至少要比較：總動作、修正動作、改善／持平／退步篇數、節省／新增動作，以及基本字和一般字的分層結果。

## 讀音

純文字會由 `--reference-db` 指定的固定 unigram 詞庫斷詞及選讀音，預設使用 current。比較不同模型時要共用同一份 reference DB，避免把讀音變化誤算成模型差異。

需要明確指定破音字時可用 JSONL；`readings` 數量必須等於 `text` 中的漢字數，非漢字不用附讀音：

```json
{"text":"銀行行員。","readings":["ㄧㄣˊ","ㄏㄤˊ","ㄏㄤˊ","ㄩㄢˊ"]}
```

一般讀音以本機 KeyKey 資料與臺灣使用者慣用注音為主。`reading-overrides.tsv` 保存人工確認的輸入慣例，`reading-review.tsv` 保存疑義與查核結果。先依常見臺灣語境判斷，仍有疑問或本機資料衝突時才逐詞查教育部辭典，不批次抓取網站。

## 批次診斷

隨機 50 篇比較可用：

```sh
python3 DataSource/AISyntheticBigram/benchmark-typing-cost.py \
  current /tmp/候選模型.db \
  --seed 20260926 --count 50 --output /tmp/keykey-random50
python3 DataSource/AISyntheticBigram/analyze-typing-benchmark.py \
  /tmp/keykey-random50
```

`benchmark-database-grid.py`、`benchmark-unigram-grid.py`、`sweep-bigram-prior.py` 可比較一組預先定義的全域候選。`analyze-common-single-characters.py` 與 `analyze-common-character-order.py` 用來定位常見字的直接 unigram 順位、斷詞或上下文問題。`repair-typing-bigram.py` 只保留作局部診斷，不是正式模型修復流程。

所有產生的資料庫、逐篇報告、實驗摘要、API 執行紀錄與編譯快取都應寫到 `/tmp` 或忽略的 `typing-benchmarks/`、`versions/`、`.typing-cache/`；這些過程檔不提交。Git 只保存可重現的程式、固定輸入、正式模型 manifest 與最終驗證結論。

## 測試

```sh
python3 -m unittest discover \
  -s DataSource/AISyntheticBigram -p 'test_typing_*.py' -v
python3 -B Source/Distributions/Takao/DatabaseCooker/verify-shared-database-wiring.py
python3 -B DataSource/AISyntheticArticles/verify-typing-articles-v5.py
```

第一次執行測試會自動編譯小型 C++ adapter；輸出位於忽略的 `.typing-cache/`。
