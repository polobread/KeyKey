# 合併 master 後重建共用詞庫

Workflow：`.github/workflows/rebuild-keykey-db.yml`。
只接受 `pull_request_target.closed` 且 `merged == true`、目標分支為 `master`，並且 PR
改動至少一個下列來源。開 PR、更新 PR、關閉但未合併、直接 push 或修改其他檔案都不重建。

| 可編輯來源 | 用途 |
| --- | --- |
| `DataSource/chichi77Collection/phrase.*.tsv` | 分類詞庫原詞、讀音、分類與來源詞頻 |
| `DataSource/AssociatedPhraseCollectionNames.tsv` | 關聯詞分類顯示名稱 |
| `DataSource/AISyntheticBigram/common-unigram-supplement.tsv` | 經審閱的常用詞補償 |
| `DataSource/AISyntheticBigram/common-phrase-unigram.tsv` | 完整詞補充，例如舊的 |
| `DataSource/AISyntheticBigram/search-trend-unigram-source.txt` | 搜尋詞原始清單，目前 550 詞 |
| `DataSource/AISyntheticBigram/search-trend-reading-overrides.tsv` | 搜尋詞慣用讀音 |
| `DataSource/AISyntheticBigram/collection-unigram-overrides.tsv` | 分類詞中文化／特殊讀音 |

`collection-unigram.tsv`、`search-trend-unigram.tsv`、manifest、DB 與回歸報告是產物，
不作觸發來源，也不要直接編輯產物取代上述來源。此設計避免產物回存後再次觸發重建。

## 建置範圍、去重與候選降權

每次从 McBopomofo `phrase.occ`、`BPMFMappings.txt`、來源 CIN 及既有小型補充詞表
重建 Unigram。固定 Git commit `63a5a33beb5a24a23c91cd74d5ff021c65affde2` 的 DB
只提供其他輸入法／服務資料表和固定 benchmark 讀音參考；其 Unigram、Bigram 均清空重建。
不需要舊 `c29d06c7…` 暫存 DB，也不沿用前次自訂詞，刪除來源詞不會殘留在模型中。

依序處理搜尋詞、經審閱的完整詞補充與分類詞。搜尋數量和分類檔案數量不寫死。
特殊詞先依 `collection-unigram-overrides.tsv` 中文化，再以完整詞文字去重。
小麥／既有詞優先，其次搜尋來源、分類檔名順序；既有詞不因分類來源重複而加分。
不可編碼的新讀音會使建置失敗，需在來源或覆寫表修正，不自動猜讀音。

`unigram_collisions.py` 使用小麥正詞頻、可編碼的 1–7 字詞作為碰撞基準，聲調必須相同：

1. 完整詞讀音相同、文字不同：保留為低順位候選，例如「桐人」排在「同人、同仁、瞳仁」後。
2. 雙方任意連續兩字讀音相同、文字不同：記錄衝突。新詞本身只有兩字時降權；
   三字以上完整詞只記錄片段重疊，不因片段而刪除或額外降權。
   例如「亞絲娜／亞斯」、「刀劍神域／神諭」保留完整詞，可以在完整讀音時勝過拆字組合。
3. 同字同音共用片段不算衝突；小麥詞頻 0 不納入基準。不把兩個獨立單字任意組成衝突詞。

`custom-unigram-excluded.tsv` 保存去重後未重複加入的來源列：`existing`、`duplicate`。
`custom-unigram-downranked.tsv` 保存保留且降權的同音詞；
`custom-unigram-partial-overlaps.tsv` 保存長詞的兩字部分重疊診斷。每個衝突對象各列一行，
含來源檔與行號、原詞、中文化詞、完整讀音、衝突片段位置（從 1 起算）、小麥完整詞、
讀音、片段及詞頻；因此清單行數不等於詞數。
搜尋與分類採用清單分別為 `search-trend-unigram.tsv`、`collection-unigram.tsv`。
關聯詞表仍依原分類來源維護；本過濾規則針對自動組句 Unigram。

普通 collection 新詞使用詞頻 1；搜尋詞頻依 2,300 篇的出現次數，範圍 1–100。
`SmartMandarinCooker.rb` 使用過濾後普通詞及 v2/v3/v4 共 2,300 篇建模，
再套用既有 document-frequency、基本字保護與常用詞補償公式。
131 篇驗證文章不參與 Bigram 建模。

動漫詞與需降權的碰撞詞於普通詞與 Bigram 都完成後才加入，不參與斷詞、讀音證據或
Bigram 邊。其詞頻最多為 0.01，且分數至少比既有完整同音詞低 2 個 log10 單位（100 倍）。
沒有完整同音詞時不設拆詞分數上限，讓「亞絲娜」「刀劍神域」可由完整讀音命中。
`target_count` 記錄最終浮點等效詞頻。低分只影響預設排序，保留候選供使用者主動選字學習。
既有小麥詞即使出現在動漫來源，也保留原詞條。

三份人名來源 `phrase.people-contemporary.tsv`、`phrase.people-oldnews.tsv`、
`phrase.people-history.tsv` 的新增詞同樣於 Bigram 完成後才加入 Unigram，
不影響訓練斷詞、讀音證據或 Bigram 邊。普通人名詞頻至多 1，碰撞／動漫人名至多 0.01。
分類為「人名…」或來源符合 `phrase.people-*.tsv` 都適用；同一人名若先從搜尋詞加入，
仍按人名規則處理。已在小麥的同文字人名保留既有詞條，不重複加分。

McBopomofo、CIN、補充詞表、v2/v3/v4、保護字、cooker 程式與本 workflow 的合併變更
也會觸發重建。回歸用的 `typing_cost.py`、`typing-engine.cpp` 與其引擎來源／標頭
變更也適用。公式或上游詞频改動仍須通過驗證；不是保證每次來源變更都會發布。

## 驗證與回存

安裝依賴後先編譯回歸用輸入引擎，編譯成功才開始 cooker，後續回歸共用同一編譯快取。
每次建立獨立候選，驗證 SQLite、採用清單、來源雜湊、低順位候選分數與無 Bigram 邊，
再跑完整 131 篇固定回歸。文章間不共享學習，讀音參考固定。
總動作增加至多 30 次可採用；超過 30 次不採用。個別文章、核心／基本字變化只列診斷。
驗證集至少包含 0001–0131，之後加入連續編號文章也會納入；排除 chat.md。
此為固定回歸，不宣稱是新盲測。

通過門檻後將 DB、採用／去重／降權／部分重疊清單、來源雜湊、cooker 報告、完整回歸結果、v5 最新紀錄、
Android 快取檔名及各平台模型列數一起 commit 回 master。不存 DB artifact、不另開 PR。
只 stage `generated-files.json` 列出的檔案；一般平台 build 仍只驗證與複製共用 DB。

超過 30 次時仍成功產生 `rebuild-review/latest.json`、完整比較、候選採用／排除清單
及 cooker 報告，僅將這些 review 檔 commit 回 master。原 DB、manifest、正式清單、
Android cache 及平台列數不動。驗證器以拒用報告中的原 DB 雜湊與當前來源雜湊綁定
「來源已改、模型未採用」狀態，因此舊 DB 仍可建置；再改來源而未重建則驗證失敗。

只有已合併事件的 job 取得 `contents: write`，checkout 已合併後的 master，不執行
未合併 PR head。推送前檢查 master 沒有前進，並使用非強制 push。
若 master 前進或分支保護禁止 bot 推送，明確失敗，需重跑或由管理者調整授權。

## 本機執行

需要完整 Git 歷史、Python 3.10+、Ruby、C++17 compiler 與 SQLite 開發套件。
必須指定尚不存在的輸出目錄：

```sh
python3 -B Source/Distributions/Takao/DatabaseCooker/rebuild-keykey-db.py \
  --output /tmp/keykey-rebuild --jobs 8

# 驗證完成後才把產物更新到目前 checkout
python3 -B Source/Distributions/Takao/DatabaseCooker/rebuild-keykey-db.py \
  --output /tmp/keykey-rebuild-to-checkout --jobs 8 --max-regression-actions 30 --apply
```

也可使用 `make -C Source/Distributions/Takao/DatabaseCooker rebuild-custom OUTPUT=/tmp/keykey-rebuild`。
`--apply` 只更新 `generated-files.json` 中列出的產物，不 commit、push 或變更遠端。

## 本次結果

第 131 篇由使用者新增，只供驗證，與訓練沒有整篇或 20 字以上相同段落。
舊「碰撞即刪整詞」規則造成 131 篇 +69，其中第 131 篇 +65，因此未採用。
改為保留同音低順位候選後，131 篇相對原 `573f733b…` DB 為
333,550 → 333,566（+16）；8 篇改善、116 篇相同、7 篇退步，通過 30 次門檻。
第 131 篇從原先 +65 降為 +16，剩餘差異是低分「亞絲娜」需要 8 次整詞選取，
每次點開候選與選字共 2 次動作。完整詞可選，但低分仍可能使拆字路徑成為預設。

接著將三份人名的新詞移至訓練後加入，131 篇全部不變（333,566 → 333,566）。
最終 DB 為 `1ffa53b37c8293b705d9bc0afafa24096d5ad53d35f971be1235beb17c59e2a1`，
119,159 Unigram、883,372 Bigram；分類新增 4,765 詞、搜尋新增 157 詞。
動漫新增 2,209 詞；三份人名 314 筆中 304 筆已存在，10 筆訓練後加入。
碰撞詞保留較後候選，去重與降權名單分開保存。

[最新人名調整差異](../DataSource/AISyntheticBigram/rebuild-review/latest.json)及
[第 131 篇歷次分析](../DataSource/AISyntheticBigram/rebuild-review/tw-corpus-0131-analysis.json)。
本機完成來源 cooker、固定回歸、閾值與寫檔分流測試、workflow 語法檢查；
[首次遠端重建](https://github.com/polobread/KeyKey/actions/runs/36967861944)
通過 27 項 cooker 測試，但 Ubuntu 編譯回歸引擎時誤用 Windows 標頭而中止，未回存產物。
已補上 Linux 的 POSIX 標頭與時間戳處理，並加入 cooker 前的編譯步驟。
修正已在 Ubuntu 24.04 驗證編譯、快取重用及「可以／有趣」輸入，macOS 引擎編譯也通過；
完整 131 篇回歸留給合併後的 workflow，不額外追加平台／模擬器驗證。

GitHub 事件條件依 [官方 merge 事件說明](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#running-your-pull_request-workflow-when-a-pull-request-merges)。
