# v1.3.1 好打注音模型

這一版把語言模型固定為一份預先產生且已驗證的
`Source/Distributions/Takao/CookedDatabase/KeyKey.db`。macOS、iOS、Android、Windows、
Linux 都直接驗證並複製相同檔案；平台建置不再各自執行 cooker。

## 建模範圍

- Bigram 建模資料固定為 `typing-articles-v2.jsonl`、`v3.jsonl`、`v4.jsonl`，合計
  2,300 篇。先前的 800／750／750 切分只是這批資料的子集，不再作為獨立評估。
- 驗證資料固定為 `typing-articles-v5-seed/tw-corpus-0001.md` 至 `0130.md`；
  `chat.md` 不是文章，不納入。驗證集有 92,889 個漢字，與訓練集沒有完全相同的文章或
  20 字以上段落。
- 每篇、每個模型都啟動全新引擎程序，關閉學習，避免前一篇的選字記憶影響下一篇。
- 動作計算採 5 音節穩定、10 音節組字範圍、每頁 8 個候選及點選。第一個音節穩定後
  若仍錯誤，選字與翻頁都計入動作。

## 選定調整

以既有小麥注音資料庫作為基準，只調整已有的 885,627 筆 Bigram 機率。每個詞對的證據為
`1 + log2(max(1, 出現該詞對的文章數))`，文章內重複不會無限放大。為避免 Bigram 讓基本字
排序退步，122 個基本／常用字涵蓋的 191 個讀音保留基準 Bigram，共保護 208,222 筆；
所有 unigram backoff 也維持基準值。

單字 unigram 不調整。另有 7 個跨多篇有穩定改善的常用詞補充：每週、做法、回覆、櫃檯、
客服、每人、留到。每個詞只提高到同音競爭詞之上 1 次，內容與審核依據在
`common-unigram-supplement.tsv`。

臺灣 2012～2026 搜尋熱門詞來源共有 550 詞，檔內沒有重複。與正式資料庫比對後，393 個
既有詞剔除，不重複加權；缺少的 157 詞加入 `search-trend-unigram.tsv`。詞頻採 2,300 篇
中的精確出現次數，最高 100；沒有出現的詞只給最低詞頻 1。完整去重與讀音依據保留在
`search-trend-unigram-review.tsv`。`新冠肺炎、載具、長照、個資、個資外洩` 使用臺灣慣用
讀音覆寫，其餘以本地 McBopomofo／KeyKey 資料組合。

## 固定 130 篇結果

| 指標 | 正式對照 | v1.3.1 選定模型 | 差異 |
|---|---:|---:|---:|
| 總動作 | 331,619 | 331,062 | -557 |
| 額外修正動作 | 11,000 | 10,443 | -557 |

130 篇中 97 篇改善、19 篇相同、14 篇退步；改善篇省下 623 次，退步篇增加 66 次，
淨減 557 次。選定模型的基本字修正為 1,269 次，一般字修正為 2,319 次。罕見字、專業詞
與專有名詞不列入基本字目標，因為這些內容本來就較適合由使用者學習改善。

熱門詞層相對加入前再少 6 次動作：3 篇改善、127 篇不變、0 篇退步。157 組讀音中，
正式組句引擎原本已有 111 組可直接組成目標；加入後為 136 組，其餘仍依保守詞頻留在
候選中，沒有為了讓每個熱門詞都變第一名而壓過原候選。

完整語料摘要、評估策略與結果在 `typing-articles-v5-manifest.json`；模型來源、資料列數與
雜湊在 `smart-mandarin-model-manifest.json`。正式資料庫 SHA-256 為
`28b18de318ac13eece6a0631c92d5e468c8bb4c5eeba11283287493b81bcc252`。

## 維護流程

一般平台建置只需執行：

```sh
make -C Source/Distributions/Takao/DatabaseCooker
python3 Source/Distributions/Takao/DatabaseCooker/verify-shared-database-wiring.py
```

第一個命令現在只驗證已提交的資料庫，不會重建。若完整分析後要重現本候選，先取得
SHA-256 為 `c29d06c7a9586641f8a261a0ab97042d3f843879b65b35248d8b650f42a1cc92`
的正式基準資料庫，再對複本明確執行：

```sh
python3 Source/Distributions/Takao/DatabaseCooker/finalize-smart-mandarin-model.py \
  /path/to/candidate.db --report /path/to/candidate-report.json
```

候選必須重新跑固定 130 篇的獨立測驗並看整體分布；不能根據單篇錯誤逐筆補詞。通過後
才更新正式 `KeyKey.db` 與 manifest 的內容雜湊。
