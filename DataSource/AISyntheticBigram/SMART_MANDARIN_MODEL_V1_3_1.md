# v1.3.1 好打注音模型

這一版把語言模型固定為一份預先產生且已驗證的
`Source/Distributions/Takao/CookedDatabase/KeyKey.db`。macOS、iOS、Android、Windows、
Linux 與 FreeBSD 都直接驗證並複製相同檔案；平台建置不再各自執行 cooker。

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

## 固定 130 篇結果

| 指標 | 正式對照 | v1.3.1 選定模型 | 差異 |
|---|---:|---:|---:|
| 總動作 | 331,619 | 331,068 | -551 |
| 額外修正動作 | 11,000 | 10,449 | -551 |

130 篇中 97 篇改善、19 篇相同、14 篇退步；改善篇省下 617 次，退步篇增加 66 次，
淨減 551 次。選定模型的基本字修正為 1,270 次，一般字修正為 2,320 次。罕見字、專業詞
與專有名詞不列入基本字目標，因為這些內容本來就較適合由使用者學習改善。

完整語料摘要、評估策略與結果在 `typing-articles-v5-manifest.json`；模型來源、資料列數與
雜湊在 `smart-mandarin-model-manifest.json`。正式資料庫 SHA-256 為
`bde6ff987670ce45845e9d57f90b081265dffac06ddc1a6d7d0660b234e43809`。

## 維護流程

一般平台建置只需執行：

```sh
make -C Source/Distributions/Takao/DatabaseCooker
python3 Source/Distributions/Takao/DatabaseCooker/verify-shared-database-wiring.py
```

第一個命令現在只驗證已提交的資料庫，不會重建。若完整分析後要建立新候選，先複製當時
的基準資料庫，再對複本明確執行：

```sh
python3 Source/Distributions/Takao/DatabaseCooker/finalize-smart-mandarin-model.py \
  /path/to/candidate.db --report /path/to/candidate-report.json
```

候選必須重新跑固定 130 篇的獨立測驗並看整體分布；不能根據單篇錯誤逐筆補詞。通過後
才更新正式 `KeyKey.db` 與 manifest 的內容雜湊。
