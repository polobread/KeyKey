# Bigram 與學習機制結構檢查（2026-10-02）

後續使用者另要求匯入全部分類詞庫；以下記錄的是前一階段分析。
目前詞庫 SHA-256 已更新為 `573f733b2affa857058d162745afaed2f4ba9605484febf124c72455cf815a75`。
新增 4,765 詞及使用者接受的回歸差異，見
[完整自訂 Unigram 清單](../DataSource/AISyntheticBigram/COLLECTION_UNIGRAM_IMPORT.md)。

本輪在 `bigram` 分支進行。依使用者明確指定，在共用 DB 加入完整 Unigram 詞「舊的」，
「新的」保留既有詞頻。更新後 SHA-256：
`8f1cb45f51fb2c27abfafd7bcd3b27b5999177805abff98ad35a599f398796f4`。
所有 Bigram 與既有 Unigram 列均不變。學習修正另行驗證；全域 Bigram 候選未採用。
修改尚未發布或安裝至使用者手機。

## 使用者案例與重現範圍

- 使用者確認 iOS 重置學習後「可以」「有趣」正常；Android 1.3.1 重置後，
  在新的空白輸入框輸入「ㄎㄜˇ ㄧˇ」也顯示「可以」。
- 正式 C++、Swift、Android walker 的乾淨模型都得到「可以」。原 Swift walker
  只需先記住單字「已」，就會將「可以」拆成「可已」；本輪測試先確認這項失敗再修正。
- 「舊的→就的」在原 1.3.1 C++ 的乾淨 Bigram 與純 Unigram 均可重現。原 DB 沒有
  「舊的」詞條；「舊」的 log10 機率是 -3.8710，「就」是 -2.4818，後者約為前者
  24.5 倍。不能將此例歸因於 Bigram 把正確的 Unigram 改壞。
- 「嘿呀」在純 Unigram 也輸出「黑壓」。以「ㄏㄢˋ」輸入「和」時，Unigram 本就把
  「漢」排在前面；以「ㄏㄜˊ」輸入則不同。「個字／各自」涉及讀音與詞段競爭，
  不能只比較「個／各」兩個單字。這些問題沒有用逐字加權或新增特例處理。
- 最初的「可倚」與「有去」缺少完整上下文及當時學習資料，未宣稱已精確重現。

## 舊版對照與五平台結果

對照來源：`~/polobread/yahoo/KeyKey-master/YahooKeyKey-Source-1.1.2528`。
比較 `OVIMSmartMandarin.h` 的 `chooseCandidate`、`Graph.h` 的
`overrideNodeCandidate`、`Node.h` 的 `adjustScoreWithSelection`，以及
`LanguageModel.h` 的快取讀寫。

| 平台 | 修改前的觸發 | 單字學習分數 | 本輪處理／證據 |
| --- | --- | --- | --- |
| 舊 Yahoo KeyKey | 主動選字，重組後記錄真正相鄰的前詞→所選詞 | 移動候選順位並調整 BOS 候選；保留單字本身分數 | 基準原始碼檢查 |
| macOS | 共用舊版 Manjusri，主動選字時記錄 | 與舊版相同，沒有三個新 walker 的全域 `0` 分單字提升 | 原始碼對照；本輪未變更此路徑 |
| Windows | 與 macOS 共用 Manjusri | 同上 | 原始碼對照；未做 Windows 文字宿主實機驗證 |
| iOS | 選字，另在確認／組字擠出時學整段詞對 | 所選讀音的單字機率與 transition 都可升為 `0` | 移除自動整句學習；將偏好限制在同讀音原有最高 Unigram 分數；Swift 真實 walker 回歸 |
| Android | 與 iOS 相同；關閉 Bigram 時不記錄詞對 | 與 iOS 相同 | 相同修正；API 26 模擬器使用 Android SQLite 與正式 DB 回歸 |
| Linux | 主動選字、重組後取實際前詞 | transition 升為 `0` | 保留觸發與前詞選取，限制單字偏好分數；C++ 獨立引擎回歸 |

### 確認的問題

1. **把自動猜測當成偏好。** iOS／Android 原本在確認及長句擠字時呼叫
   `learnConfirmedComposition`，將當時整個組字區的詞对寫成 `0` 分。
   組字尾段甚至仍可能是暫時猜測。舊版沒有這個觸發。
2. **单字偏好破壞詞段成本。** iOS／Android／Linux 的 `0` 分提升，讓本來需要支付
   單字機率成本的路徑變得過強。例如學過「已」即可壓過完整詞「可以」。
3. **正式模型的加分與 backoff 不是同一套統計。** 舊 cooker 使用每個文字詞對最多
   一次的加性觀察，低頻詞的相對增益沒有上限。finalizer 再調整跨文章證據，但還原
   全部 backoff，並對部分讀音還原舊 Bigram，因此不能視為一個統一正規化的模型。
   這是結構性風險，並不表示每一筆改動都一定造成輸入退步。

### 學習修正

- 確認文字／擠字不再把自動猜測寫成詞對；保留明確選字的學習。
- 三個新 walker 對已學單字，只提升到同一讀音原有最高 Unigram 分數的下一個
  浮點值，最高為 `0`，不再另外將 transition 或候選分數一律改為 `0`。
  在候選中保留偏好，同时讓字詞路徑仍支付原本量級的成本。
- 當次手動選字仍是硬性限制。例如明確在組字中選「已」，仍能輸出「可已」。
- 重設後恢復正常；自訂詞保存。沒有修改使用者目前的學習資料庫。
- 先前的「請／假」擠字回歸仍保留人工拆詞 fixture，同時新增確認現在的自然組句
  保持「請假」完整，避免把舊的過度加分行為寫成必須保留的測試期待。

### 尚存的學習差異

- 舊 Manjusri 兩種偏好快取各有預設 200 筆容量；三個新 walker 的 SQL 學習表沒有
  同樣的容量淘汰。舊版 `DataCache` 本身也有重複鍵消耗佇列位置的特性，不能把它
  當成正確 LRU 原樣搬過來。本輪沒有新增淘汰策略。
- 明確選字的相鄰詞記憶仍採強制偏好。新 walker 保存 `0` 分；舊版使用資料庫中的
  最高 Unigram 分數，目前共用 DB 的 BOS／EOS 為 `0`。這和單字全域提升是兩件事。
- 既有錯誤詞對仍可能影響輸入；此次停止新增隱含整句記憶，不自動清除既有資料。
- 三個新 walker 在查詢時讀取學習表；macOS 重設會觸發模組同步、清空記憶體快取
  再載入，Windows 另以 `userdb.data_version` 偵測跨程序更動。這些重設路徑的
  原始碼沒有顯示要保留學習表中的舊列。使用者的兩個手機乾淨輸入結果也已一致。

## 已採用的完整詞補償

使用者指定將「舊的、新的」當完整詞處理。補充來源為
`DataSource/AISyntheticBigram/common-phrase-unigram.tsv`，不修改 McBopomofo 原始資料。
「舊的」在訓練語料出現 40 次、分布於 34 篇；採用補償詞頻 1715，這是超過同讀音
最佳替代 Unigram 路徑「就／的」所需的最小整數。「新的」原有詞頻 1761 已足夠，
因此保留原值。補償詞頻是排序門檻，不是聲稱語料真的出現 1715 次。

工具先驗證整份補充表，再寫入新 DB 副本；來源分數變動時要求重新檢查，防止靜默加權。
SQL 雙向差集確認：只新增一列「舊的」，既有 114,392 列 Unigram 與 885,627 列
Bigram 完全相同。finalizer 同步套用此補充層，Android 快取名稱同步更新。
共用 C++ 引擎移除全部 Bigram 後，兩組讀音仍直接得到完整詞「舊的」「新的」。

固定 130 篇總動作 **331,062 → 331,058**、修正動作 **10,443 → 10,439**；
2 篇各改善 2 動作、128 篇相同、0 篇退步。核心 83 字和基本 100 字不變，
一般字修正 2319 → 2317。完整來源雜湊與逐篇結果保存在
`DataSource/AISyntheticBigram/whole-phrase-unigram-validation.json`。

## Cooker 實驗（未採用）

新增獨立命令 `compensate-smart-mandarin-model.py`，只產生候選副本。
一般平台建置仍只驗證與複製正式 DB。訓練仍只用 v2／v3／v4 共 2,300 篇，
使用者案例、130 篇驗證錯誤及基本字清單都不進入建模公式。

令 `p(w)` 為既有讀音的 Unigram 機率，`df(h,w)` 為訓練文章出現該詞對的篇數：

```text
e(h,w) = min(log2(1 + df(h,w)) × reading_share(w),
             prior × p(w) × (10^max_log_lift - 1))
Z(h) = prior × sum_unigram_mass + sum_w e(h,w)
P(w|h) = (prior × p(w) + e(h,w)) / Z(h)
backoff(h) = log10(prior / Z(h))
```

相同文章內重複不會增加篇數；標點、空白與未知字切開詞對。
没有跨文章證據的既有邊退回同一套 backoff。保留全部 Unigram 分數、詞彙、
Bigram 身分與列數。補充詞造成的實際 Unigram 總質量
`1.0000544582818813` 也納入分母。EOS 採用缺邊時相同的 backoff，
不把當下組字尾端當成完整句尾證據。

### 固定 130 篇

先重跑目前模型與純 Unigram，再測全域候選。每篇／每個模型使用獨立 C++ 程序，
關閉學習，共用固定讀音，使用 settle=5、buffer=10、每頁八候選的動作模型。
這 130 篇已用於先前研發，本次視為回歸集，**不是新的盲測**。

| 模型 | 總動作 | 修正動作 | 核心 83 字修正 | 基本 100 字修正 | 一般 101–1000 字修正 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 原 1.3.1 模型 | 331,062 | 10,443 | 1,104 | 1,269 | 2,319 |
| 純 Unigram | 334,120 | 13,501 | 1,264 | 1,517 | 3,179 |
| 上限 10 倍初步候選 | 331,528 | 10,909 | 1,046 | 1,180 | 2,413 |
| 上限 100 倍、prior=1000、完整正規化 | 330,923 | 10,304 | 1,065 | 1,197 | 2,293 |

100 倍候選為 71 篇改善、22 篇相同、37 篇退步；節省 367 動作、新增 228 動作，
最差單篇增加 23。核心字仍有「也、像、得、比」各多修 1 次、「那」多 2 次、
「再」多 6 次。總分雖改善，尚不能據此採用。
「舊」在全組修正由 40 次減至 36 次，但單獨「舊的」仍輸出「就的」。
另測 prior=100、上限 100 倍，總動作 331,490、修正 10,871，比原模型多 428 動作，未採用。

最終 prior=1000 候選 SHA-256：
`f16f57c2dcd2b52e40ab003accb10f372a98f317ef3b40954de7bf67c81d43e5`。
完整逐篇、逐字、動作報告在忽略目錄
`DataSource/AISyntheticBigram/typing-benchmarks/structure-20261002/`。
另保存候選建模參數、訓練檔雜湊、模型雜湊及產生程式雜湊。

採用前仍須處理退步分布，使用新的完整自然文章 holdout，並對各平台 walker
另做模型驗證；三平台的學習與完整詞回歸不能代替全域 Bigram 候選驗收。

## 重跑

從儲存庫根目錄執行，候選輸出必須是尚不存在的新路徑。下列命令會以目前完整詞補充後的
DB 產生新實驗；若要重現上表，須改用 SHA-256 為 `28b18de318ac13eece6a0631c92d5e468c8bb4c5eeba11283287493b81bcc252`
的原 1.3.1 DB，並將 benchmark 的 `--reference-db` 固定為該原 DB。

```sh
python3 -B Source/Distributions/Takao/DatabaseCooker/compensate-smart-mandarin-model.py \
  Source/Distributions/Takao/CookedDatabase/KeyKey.db \
  /tmp/keykey-bounded.db --max-log-lift 2 --prior 1000
python3 -B DataSource/AISyntheticBigram/benchmark-bigram-structure.py \
  current=current unigram=unigram bounded=/tmp/keykey-bounded.db \
  --output /tmp/keykey-structure-validation --jobs 8
```

trace 重用會檢查文章內容、reference DB、候選 DB、引擎、評測程式、讀音覆寫及
動作策略的雜湊／內容，避免把不同來源的舊 benchmark 混用。

## 驗證

- Swift 全套：151 個 Swift Testing 測試通過，另有 XCTest 測試通過。
- Android：112 個單元測試通過；API 26 模擬器的 9 個 Bigram instrumentation 測試通過。
- Linux：Clang 直接建置獨立 C++ 引擎，`--smart-only` 測試通過。
  不等同 Fcitx、X11、Wayland 實機驗證。
- Cooker 新增 9 個測試通過；既有 typing 評測 40 個測試通過。
- 正式 DB 完整性、內容雜湊與五平台共用資料庫 wiring 驗證通過。
- macOS／Windows 共用的學習路徑本輪只做原始碼比較，未變更及重新安裝宿主。
