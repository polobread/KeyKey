# CIN 多讀音單字詞頻對應

依傳統注音 CIN 的同音候選順位，為有正詞頻的多讀音單字產生「字＋讀音」替代詞頻表，
供模型調整前檢查。已作為 cooker 預設啟用、可明確關閉的額外來源；尚未重建或採用正式模型。

程式不開啟資料庫、不執行 cooker、不改原始詞庫、正式 DB、模型 manifest 或使用者學習資料。

## 檔案與來源

| 檔案 | 用途 |
| --- | --- |
| [build-cin-character-reading-frequencies.py](build-cin-character-reading-frequencies.py) | 僅使用 Python 標準函式庫的計算程式 |
| [cin-character-reading-frequencies.tsv](cin-character-reading-frequencies.tsv) | 依 CIN 順序輸出的字音詞頻對應 |
| [cin-character-reading-frequencies-report.json](cin-character-reading-frequencies-report.json) | 公式、參數、統計、來源與產物 SHA-256、去重紀錄 |
| [test_cin_character_reading_frequencies.py](test_cin_character_reading_frequencies.py) | 讀音分離、順位、上限、去重、零詞頻與符號排除測試 |

輸入來源：

- [bpmf-ext.cin](../../Source/DataTables/bpmf-ext.cin)：讀取 `%keyname` 與 `%chardef`，
  取得按鍵碼、字、注音及同讀音內的原始順位。
- [phrase.occ](../McBopomofo/phrase.occ)：讀取整字來源詞頻，未提供逐讀音實際次數。

只輸出有兩個以上不同標準讀音、且來源詞頻大於零的單字。不同按鍵碼若轉為同一字音，
只保留首次出現的位置；例如「賊」的 `yk6` 與 `yk6y` 都轉成 `>C`。

## 計算規則

每個讀音各自依 CIN 順序掃描：

1. 單讀音字維持整字來源詞頻，只作比較基準，不寫入輸出表。
2. 多讀音字若前面沒有可比較的正詞頻候選，保留完整整字來源詞頻。
3. 否則，`target_count = min(source_count, ratio × 前面候選最低計算詞頻)`。
4. 已校正的多讀音字也參與後續的最低值比較。
5. 零詞頻、缺詞頻、注音符號與聲調不作限制來源；原始 CIN 順位仍包含這些位置。

預設 `ratio = 0.9`，可指定其他大於零、小於一的十進位數。計算採用 Decimal，保留正小數，
不把低於一的詞頻四捨五入成零。這些數值是取代式模型權重，不能再加到原詞頻上。

例如 ㄏㄨˇ 的原始順序是虎、琥、滸、唬、許：

| 字音 | CIN順位 | 整字來源詞頻 | 計算詞頻 | 說明 |
| --- | ---: | ---: | ---: | --- |
| 虎／ㄏㄨˇ | 1 | 1,227 | 1,227 | 第一位保留 |
| 許／ㄏㄨˇ | 5 | 13,105 | 26.1 | 前面最低值是滸的 29；29 × 0.9 |
| 許／ㄒㄩˇ | 1 | 13,105 | 13,105 | 另一讀音分開處理，第一位保留 |

琥、滸、唬在此來源中是單讀音字，分別維持 33、29、74；這張表不強制改變它們彼此的順位。
CIN 第一位與「第一個可比較的正詞頻候選」不同，見 `cin_rank`、`positive_rank`。

## 產生與驗證

需要 Python 3.10 以上。從儲存庫根目錄執行：

```sh
python3 -B DataSource/CINReadingFrequency/build-cin-character-reading-frequencies.py

python3 -B -m unittest discover \
  -s DataSource/CINReadingFrequency \
  -p 'test_cin_character_reading_frequencies.py' -v
```

預設將 TSV 與 JSON 寫回本目錄。輸入未變時，TSV 可重現為完全相同的 bytes。
改用其他參數時，先寫入獨立產物目錄以便比較：

```sh
python3 -B DataSource/CINReadingFrequency/build-cin-character-reading-frequencies.py \
  --ratio 0.8 \
  --output Installer/local-builds/cin-reading-review/frequencies.tsv \
  --report Installer/local-builds/cin-reading-review/report.json
```

另可用 `--cin`、`--counts` 指定來源。程式拒絕用輸出覆蓋來源檔，並將實際來源與自身雜湊寫入報告。

## TSV 欄位

| 欄位 | 意義 |
| --- | --- |
| `character` | 單字 |
| `reading` | 標準注音顯示 |
| `qstring` | 模型的兩字元讀音編碼，區分大小寫 |
| `cin_rank` | 此讀音內，去除重複字音後的 CIN 原始順位，從 1 起算 |
| `positive_rank` | 排除零詞頻、缺詞頻與注音符號後的正詞頻順位 |
| `source_count` | 原始整字詞頻，不是逐讀音實際次數 |
| `target_count` | 此字音的計算後替代詞頻 |
| `reading_count` | 該字在 CIN 中的不同標準讀音數 |
| `cin_code`、`cin_line` | 首次出現的 CIN 按鍵碼與來源行號 |
| `limit_character`、`limit_cin_rank` | 提供前面最低值的候選及其 CIN 順位 |
| `limit_count` | 限制來源的計算詞頻，可能已被前面的候選降權 |
| `count_cap` | `limit_count × ratio` |
| `adjustment` | `capped` 降權；`cin_first` 原始第一位；`first_positive` 前面無有效比較值；`source_lower` 原詞頻已低於上限 |

## 統計與解讀

目前來源產生 1,720 個多讀音單字、3,863 筆字音，涵蓋 1,132 個讀音群。
2,203 筆降權、1,660 筆保留來源詞頻；有一筆相同字音按鍵別名去重。完整統計及來源版本以 JSON 雜湊為準。

CIN 順位不是實際讀音使用比例。本規則沒有在同一字的多個讀音間重新分配總量：
例如「行」四個讀音都在各自 CIN 第一位，因此都保留完整整字詞頻；
「和／ㄏㄢˋ」也因第一位而保留 38,150，會高於「漢」的 3,065。
不能據此宣稱已改善正式模型的候選、預設組字或動作數。

## 接入 cooker

專案重建入口與 Ruby cooker 預設啟用本表。這是額外、可關閉的來源，不修改 `phrase.occ`；
未列出的字音仍使用原本的讀音權重估算。

```sh
# 標準重建：預設讀取本表（此命令會重建並執行完整回歸）
python3 -B Source/Distributions/Takao/DatabaseCooker/rebuild-keykey-db.py \
  --output Installer/local-builds/keykey-rebuild

# 不使用本表，沿用原讀音權重估算
python3 -B Source/Distributions/Takao/DatabaseCooker/rebuild-keykey-db.py \
  --output Installer/local-builds/keykey-rebuild-original \
  --no-cin-reading-frequencies
```

`--cin-reading-frequencies PATH` 可改用 checkout 內另一張同格式表。Ruby cooker 支援同名參數，
直接執行時須把選項放在語料路徑之前。Make 的 `rebuild-custom` 可設
`CIN_READING_FREQUENCIES=` 關閉，未設定則沿用本表。沒有 repo 身分判斷或本機 Git 設定。

套用順序：

1. 讀取正常來源與 CIN，計算原本的讀音權重。
2. 驗證本表的字、注音、qstring、CIN 順位、原始詞頻；資料過期、重複、非正或非有限值會中止。
3. 指定字音改用 `target_count / source_count` 作讀音計分權重；不重新分配到其他讀音。
4. Unigram 使用 `log10(target_count / unigram_total_count)`；總分母保持來源整字總量。
5. Bigram 的背景機率及讀音觀測分配使用同一個新權重；不只改候選清單或單一句首邊。
6. finalize 以這份 Unigram 重算 Bigram，並在處理前後檢查表內詞頻沒有被覆寫。
7. 模型 manifest 記錄啟用來源、筆數及 SHA-256；關閉時不引用本表。

舊算法的固定首選字檢查只適用於未受本表影響的讀音；全部讀音仍須通過
CIN 首選存在性、讀音數量、來源詞頻、內容雜湊與完整性驗證。

原有基本字保護流程仍保留，但還原使用的是「已套用本表」的初次 cooker Bigram。
Actions 同樣預設啟用，產物只提交到工作分支並建立 PR，由維護者 review／merge。

目前只完成接線與隔離小型測試；正式 DB 尚未以本表重建，也未完成本表的 131 篇回歸。


## 授權

本目錄原創程式、測試、文件及可授權的原創資料整理採用
[MIT License](LICENSE.txt)，Copyright (c) 2026 Chui-Ping Cheng。
來源資料保留各自授權；McBopomofo 的 MIT 聲明與 CIN 的 Public Domain 來源標示見
[THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt)。
