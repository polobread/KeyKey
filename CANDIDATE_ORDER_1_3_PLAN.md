# 琦琦注音 1.3.x 跨平台候選字順位計畫

> 狀態：參考計畫（未排入版本、未承諾實作）
> 建立日期：2026-09-21
> 適用範圍：macOS、Windows、Linux、Android、iOS 的傳統注音候選字
> 本文件本身不改變 1.2.9 或任何既有版本的執行行為。

## 1. 決策摘要

若未來實作 1.3.x，候選字順序要成為一份**固定、可版本化、與字型無關**的資料，而不是
由各平台當下能不能顯示某個字來決定。

核心原則如下：

1. macOS 使用者已習慣的候選順序是主要基準。
2. Windows「ㄅ半」既有候選順序是第二基準，只補入 macOS 基準沒有的候選，不能插隊或
   改變 macOS 既有順位。
3. Android、iOS、Linux、Windows 或 macOS 缺少字型時，該候選仍須保留在同一個順位；
   畫面顯示缺字方框即可。
4. 使用者安裝可顯示該字的字型後，同一順位應直接恢復正常字形；候選數量、編號、分頁和
   其他候選順位都不能改變。
5. 所有平台使用同一份版本化候選資料與同一個合併演算法，並提供可選的候選模式。
6. Big5 只可保留為明確標示的舊系統相容模式，不能再用來判斷一般模式的候選內容。

這項工作的優先順序是「保護肌肉記憶」高於「隱藏缺字」。若字型不足，寧可看到方框，
也不能讓後面的字往前補位。

## 2. 目標與非目標

### 2.1 目標

- 同一候選模式、同一資料版本、同一讀音，在五個平台產生完全相同的 Unicode 字串序列。
- macOS 主序列與 Windows 輔助序列有可追溯、不可無聲變更的快照。
- 字型安裝、系統更新、App 使用的字型、輸出欄位及 Big5 converter 不影響候選順位。
- 候選資料、模式演算法與查詢順序均可用自動測試驗證。
- 保留 `bpmf.cin`、`bpmf-ext.cin` 的歷史原貌，不重排、不清理、不以新版 Unicode 正規化
  悄悄改字。

### 2.2 非目標

- 不在這份計畫中承諾 1.3.x 一定開發或決定時程。
- 不改變智慧選字、使用者學習、詞頻學習或關聯詞的排名邏輯。
- 不以「所有平台都能畫出來」作為候選字是否存在的條件。
- 不把舊 Windows IMM 當成未來產品目標；它只可作為歷史順位的取樣來源。實作目標仍是
  Windows TSF。
- 不藉此修正看似錯字、異體字、重複字或六組歷史例外；任何資料修訂必須另案處理。

## 3. 現有資料的歷史與不可破壞性

### 3.1 `bpmf-*.cin` 一開始怎麼來的

`Source/DataTables/bpmf-ext.cin` 的檔頭記載，它是由 opendesktop.org.tw 的
`phone.cin` 修訂而成，納入 CNS 11643 與 Unicode 可相容字，並調整部分標點，授權為
Public Domain。

現有公開資料能支持以下歷史脈絡：

- 2008 年 OpenVanilla 社群討論提到 `bpmf-ext.cin`、`cj-ext.cin` 是由
  opendesktop.org.tw 全字庫 CIN 改製，目標是納入數萬個 CNS 字；同一討論也已出現
  部分應用程式或字型無法正確顯示、版面異常的問題。
- KeyKey 的公開原始碼說明其建立在 OpenVanilla 上，注音對應資料依據中央研究院語料；
  但目前找不到一份可證明每一讀音內所有候選順位是如何逐字計算的權威文件。
- 2012 年 libchewing 討論明確記錄 GNU/Linux 上許多 `phone.cin` 字元不能正確顯示，
  因而以人工／Pango 過濾，並另外保存完整 CNS 11643 資料 patch。這證明「原始資料仍在，
  執行階段因顯示能力而少字」是當時已知的處理方式。

所以，現有順序應視為長期累積的歷史相容資料，不應重新用現代字頻或 Unicode code point
排序來「重建」。

### 3.2 現有檔案沒有在本專案內被刪字或重排

下列三個檔案，從 Yahoo 於 2012 年匯入的初始原始碼到目前版本，內容為 byte-for-byte
相同；2026 年的變更只有路徑搬移：

| 檔案 | 目前 SHA-256 |
| --- | --- |
| `bpmf.cin` | `ea999e843d99c96bfd185b49939865849a1d8004dc5725722a2cf5ac042aff94` |
| `bpmf-ext.cin` | `f7c05229355ad39a0ef7806db85723709380099c24d3cb787f3eb01d49e29589` |
| `bpmf-punctuations.cin` | `5eb470548b071642d94328e8763ad1fea5ba6c1fc360b394d9fe8d6d14291f1` |

三份檔案目前都是無 BOM、LF 換行的 UTF-8 文字，並能完整通過 UTF-8 解碼；它們不是
Big5 檔案。Big5／CP950／HKSCS 只出現在執行階段的舊編碼相容判定，不是來源資料的儲存
格式。因此這項計畫不需轉碼或改寫三份 CIN；仍以原始 bytes 與上述 hash 保護它們。

這表示「以前看得到、後來消失」不是這三份來源檔在本 repo 被刪字造成的；主要原因是不同
平台、字型或 encoding service 在候選送到畫面前做了過濾。

### 3.3 基礎表與全字表的關係

目前資料量：

| 資料 | 候選列數 | 讀音 key 數 |
| --- | ---: | ---: |
| `bpmf.cin` | 14,149 | 1,323 |
| `bpmf-ext.cin` | 97,925 | 1,541 |

在 `bpmf.cin` 的 1,323 個讀音中，有 1,317 個讀音的完整候選序列，都是
`bpmf-ext.cin` 同一讀音的精確前綴；`bpmf-ext.cin` 另有 218 個讀音只存在於全字表。
這顯示當初的主要設計是保留常用字順位，再把罕見字接在後面，而不是重新洗牌。

只有六組既存歷史例外，且至少自 2012 年即已如此：

| 讀音 key | 例外摘要 |
| --- | --- |
| `1o` | 全字表在第 10 位插入 `唄` |
| `204` | 基礎表的 `殫` 在全字表對應位置缺少 |
| `ao6` | 從第 11 位開始不同，例如 `酶` 移到較後面 |
| `c/6` | 從第 8 位開始不同，例如 `鴴` 移到較後面 |
| `fu6` | 基礎表的 `墘` 在全字表對應位置缺少 |
| `u6` | 第 18 位有 `彞`／`彝` 差異，後段另有插入 |

這六組例外必須被 golden test 固定；不能在候選模式專案內順手「修正」。

## 4. 現況問題

### 4.1 五平台實際共用全字表，但顯示政策不同

目前 Android 的 Gradle cooker、iOS／macOS 的 `KeyKey.db` cooker、Windows native
cooker 和 Linux loader，主要都使用 `bpmf-ext.cin`；一般候選消失並不是因為 Android
或 iOS 換了一份較小的來源表。

桌面共用的 `OVIMTraditionalMandarin::queryAndCompose` 會先取得候選，再依設定呼叫：

- `stringSupportedByEncoding`；或
- `stringSupportedBySystem`。

結果是候選陣列先被刪除，再編號及分頁，後面的字就會向前移：

- macOS 依指定／fallback 字型的 glyph coverage 建立不支援清單，另排除 PUA 及大於
  `U+2FFFF` 的 code point。
- Windows TSF 的 system support 檢查目前全部回傳 true，但 Big5 選項會走 CP950。
- Linux 有 Big5-HKSCS 過濾選項；歷史上通常可選擇使用全部 Unicode。
- Android、iOS 目前不做同一套過濾，因此可看到缺字方框，也會與已過濾平台產生不同
  順位。

這種做法會讓同一份原始資料在平台、OS 版本或字型安裝狀態不同時得到不同順位，不適合
需要長期肌肉記憶的輸入法。

### 4.2 資料庫查詢尚未把順序寫成正式契約

舊桌面共用 SQLite 查詢是 `SELECT value FROM table WHERE key = ...`，沒有
`ORDER BY`。目前 query plan 常因索引及插入順序而恰好依 rowid 回傳，但 SQL 不保證這個
行為。iOS 已明確使用 `ORDER BY rowid`；Android 的 `LinkedHashMap`／`ArrayList` 與
Linux vector 則保留解析順序。

若要把順位當相容性承諾，不能繼續依賴「目前剛好如此」。

### 4.3 不同國家／地區的使用者會得到不同顯示結果

同一份 Unicode 候選資料，在不同國家／地區的實際使用感受可能不同。差異不是由使用者
所在的地理位置直接決定，而是由裝置銷售版本、OS／發行版、語言與地區設定、OEM 預裝
內容、已安裝字型、字型 fallback 順序，以及候選窗與目標 App 所使用的繪字技術共同決定。

- macOS／iOS 的 CoreText fallback 會參考可用字型及語言偏好；macOS 另有可下載及
  使用者安裝的字型，系統更新也可能增修字型。iOS 的系統字型會隨版本改變，App 或文件
  安裝的字型也不保證輸入法 extension 或每個目標 App 都以相同方式採用。
- Windows 的預裝與選用字型會隨系統語言功能而不同；繁體中文補充字型可包含
  `MingLiU_HKSCS` 等字型。GDI、DirectWrite、瀏覽器與不同 App 的 fallback／font linking
  結果可能不同。目前 TSF 候選窗使用 GDI `DrawTextW`，須和輸入後的目標 App 分開驗證。
- Android 的 fallback chain 由 AOSP、OS 版本及 OEM 共同決定，同版 Android 的不同品牌、
  市場機型也可能有不同 coverage。Android 12 起平台可在不更新完整 OS 的情況下更新受信任
  的系統字型，但不代表所有裝置會取得同一套罕字字型。
- Linux 沒有跨發行版一致的預裝字型集合；Ubuntu 可由 `fonts-noto-cjk` 等套件提供 CJK
  coverage，Fontconfig／Pango 再依字元、語言及使用者設定選擇 fallback。套件、桌面環境與
  App toolkit 都可能改變結果。

因此台灣繁中、香港繁中、日文、韓文與英文環境可能顯示不同地區字形，也可能有不同的
缺字集合。這種差異只允許影響畫出的 glyph；候選 Unicode 字串、數量、編號、分頁、選取
索引與提交結果仍須一致。未來 OS、OEM、Linux 套件或使用者安裝的字型增加 coverage 時，
原 slot 應直接由缺字方框變成可讀 glyph，不能因而新增、刪除或重排候選。

現有 macOS `CVEncodingService` 只以 `STHeiti`（失敗時 `AppleGothic` 或 system font）這一支
字型的 `coveredCharacterSet` 建立不支援清單，並硬排除部分 PUA 與 `U+2FFFF` 以上字元；
這不是整個 CoreText fallback chain 的實際能力。即使使用者另裝字型，候選也可能先被
琦琦刪除。正式實作必須移除這項 membership 過濾，不能改成另一套動態 coverage 過濾。

`bpmf-ext.cin` 另含大量 PUA 候選。PUA 的字義不由 Unicode 指定，只有安裝與原始資料採用
相同私用對應的字型才會得到預期 glyph；一般系統日後增加標準 Unicode 漢字，不保證能
補上舊 PUA，使用不同私用約定的字型甚至可能畫出另一個字。PUA 測試必須同時記錄 code
point、預期 glyph 來源與字型版本，不能只記錄「有方框／沒有方框」。

## 5. 不可變順位契約

1. 每個候選模式由 `profile version + reading key + ordinal + exact Unicode string`
   定義。
2. 候選 membership、相對順序、候選數量與分頁，不可讀取 glyph coverage、系統字型、
   encoding converter 或 app 輸入欄位來決定。
3. 缺字時仍保留原 Unicode 字串；不能替換為 `U+FFFD`，也不能刪除。
4. 字型變更只允許重畫或重建 font fallback；不能重新產生候選陣列。
5. 同一 profile version 在所有平台須輸出相同 digest。
6. 任何順位資料變更都要有新 profile version、變更摘要、migration 決策與人工審查；
   不得跟著字型、OS 或 Unicode library 更新而靜默改變。
7. `bpmf.cin`、`bpmf-ext.cin`、`bpmf-punctuations.cin` 的上述 hash 列入 CI 保護。

## 6. 建議候選模式

### 6.1 一般設定頁顯示的模式

| 模式 | 順序定義 | 建議用途 |
| --- | --- | --- |
| **macOS 優先＋Windows ㄅ半補充** | macOS 凍結序列在前，再附加 Windows 序列中尚未出現的字；各自內部相對順序不變 | 建議預設；符合本計畫的主要產品方向 |
| **僅 macOS 既有順序** | 精確使用凍結的 macOS 參考序列 | 完全延續 macOS 肌肉記憶 |
| **僅 Windows ㄅ半既有順序** | 精確使用凍結的 Windows 參考序列 | Windows 舊使用者遷移 |
| **傳統基礎表** | 精確使用 `bpmf.cin` | 只要傳統常用候選、但仍固定跨平台順位 |

設定說明應明確寫出：所有模式都保留固定順位；裝置沒有字型時會顯示缺字方框。

### 6.2 進階／參考模式

| 模式 | 順序定義 |
| --- | --- |
| **完整字庫：macOS → Windows →其餘** | macOS 序列、Windows 未重複補充、其餘 `bpmf-ext.cin` 候選依原始相對順序附加 |
| **完整歷史原始順序** | 精確使用 `bpmf-ext.cin`；供研究、診斷及完整取字 |
| **Big5 相容（舊系統）** | 由專案內版本化的固定 Big5 字集 map 取交集；只為舊資料交換，不代表系統能否顯示 |

進階模式是否直接放在一般設定頁，留待實作前的產品決策；至少應能由進階設定或診斷工具
選用，不能讓模式數量妨礙主要使用者理解。

建議儲存一個 enum，而不是多個可互相衝突的開關：

```text
CandidateOrderMode =
  macWindows | macOS | windows | base | fullTiered | rawExtended | legacyBig5
```

不再提供會改變 membership 的「只顯示系統支援字」開關。若保留類似選項，只能是畫面
提示，例如標示可能缺字，不能刪候選或改順位。

## 7. 參考序列的凍結方法

### 7.1 先確認基準環境

開發前必須由使用者確認兩個可接受的實際基準：

1. macOS：哪一版 KeyKey、macOS、候選設定、字型狀態代表「目前正確」。
2. Windows ㄅ半：哪一版程式、Windows、候選設定代表「輔助基準」。

不能只由目前 source 推測，也不能只根據一張 `ㄏㄚ` 截圖。要從真實參考 build 匯出
全部 1,541 組讀音的候選序列。

### 7.2 保存格式

建議建立不可變資料工件：

```text
macos-bopomofo-profile-v1
windows-bopomofo-profile-v1
```

每份工件都應包含：

- 參考程式版本、commit、OS 與設定。
- 來源 CIN hash。
- 每個 reading key 的 exact Unicode 候選序列。
- 工件 schema version、整體 SHA-256 與產生工具版本。
- 可供人工查看的差異報告，以及機器可讀的資料。

若驗證後確定 macOS／Windows 只是在 `bpmf-ext.cin` 上做 membership 過濾、從未重排，
可以把 profile 壓縮為固定 code point／字串集合；只要任何讀音出現重排、去重或非單字候選，
就必須保存逐讀音的完整 sequence／rank，不能假設只有集合差異。

### 7.3 確定性的合併演算法

以 `macOS 優先＋Windows ㄅ半補充` 為例：

```text
result = []
依序加入 macOS profile 的每個候選
依序加入 Windows profile 中尚未存在 result 的候選
```

`完整字庫：macOS → Windows →其餘` 再執行：

```text
依序加入 bpmf-ext.cin 中尚未存在 result 的候選
```

去重以 exact Unicode string 為準，第一次出現者保留。第一版不要自動做 NFC／NFKC、
異體字合併、字形相似合併或 Unicode code point 排序，避免無意改寫歷史內容。

## 8. 儲存與查詢設計

在做任何模式 UI 前，先把順位變成 schema 層級的明確資料：

```text
candidate_profile(profile_id, version, digest, ...)
candidate(reading_key, profile_id, ordinal, value)
UNIQUE(reading_key, profile_id, ordinal)
```

所有平台查詢都必須明確 `ORDER BY ordinal`。短期可用 `ORDER BY rowid` 固定舊資料庫，
但正式 profile 應有自己的 `ordinal`，不能把 SQLite 實作細節當產品契約。

建置階段由同一個 deterministic generator：

1. 驗證三份歷史 CIN 的 hash。
2. 讀入並驗證參考 profiles。
3. 依模式規格產生 ordered rows。
4. 寫入 ordinal 與 profile metadata。
5. 產生所有 reading key 的 golden digest。
6. 讓 Android、iOS、macOS、Windows、Linux 使用相同工件或從相同工件建庫。

`convert-bpmf-cin.rb` 可繼續做讀音 key 表示轉換，但須有測試證明它不改變候選行順序。

## 9. 五平台工作項目

### 9.1 共用核心／資料

- 新增 profile schema、產生器、manifest、hash 與差異報告。
- 為全部 1,541 個讀音產生各模式 golden sequence／digest。
- 將 `bpmf-punctuations.cin` 與一般注音候選分開處理；標點／控制列保留其來源順序。
- 關聯詞結果不可依 glyph support 刪除；缺字同樣保留字串及位置。

### 9.2 macOS

- 先以實際正確版本匯出 `macos-bopomofo-profile-v1`。
- 移除候選 membership 對 `CVEncodingService` 字型 coverage 的依賴。
- 保留 CoreText／系統 font fallback 作為繪製工作；禁止它改變候選內容。
- PUA 或 supplementary-plane 字元若沒有 glyph，就顯示缺字方框，不刪除。

### 9.3 Windows

- 從使用者認可的「ㄅ半」參考環境匯出完整 profile。
- TSF 查詢明確依 ordinal 排序。
- CP950 僅供可選的 `legacyBig5` profile；一般模式不能走 CP950 過濾。
- 參考資料可以來自舊 IMM，但新功能只落在 TSF。

### 9.4 Linux

- 移除固定候選模式對系統 `iconv` Big5-HKSCS 版本的依賴。
- Fcitx 候選 vector 完整保留 profile 次序與字串。
- 在不同桌面字型、X11／Wayland 下驗證：只能改變 glyph，不能改變序列。

### 9.5 Android

- 將目前 parser 的穩定順序提升為明確 ordinal/profile 契約。
- 候選 view 對 tofu、supplementary-plane、variation sequence 做壓力測試。
- 不以 `Paint.hasGlyph` 等 API 刪除候選。
- Android 8（API 26）與最新版都要比對同一 profile digest。

### 9.6 iOS

- 將目前 `ORDER BY rowid` 遷移為 `ORDER BY ordinal`。
- UIKit/CoreText font fallback 只負責繪製，不介入候選 query。
- 實機與 Simulator 都要驗證缺字時 slot、頁碼與選取索引不變。

## 10. Big5 的定位

不能沿用各平台現有的 Big5 判定作為共同標準，因為它們實際不是同一份 repertoire：

- Windows 使用 CP950。
- macOS 使用特定版本的 Big5-HKSCS converter。
- Linux 使用發行版提供的 `iconv` Big5-HKSCS。

這些 converter 會隨實作、版本與 HKSCS revision 不同而產生不同可表示集合。Big5 也不能
表示完整 Unicode/CNS 資料，與「螢幕現在有沒有 glyph」更是兩件不同的事。

若產品仍需要舊資料交換相容性：

1. 在 repo 內保存一份有明確來源、版本與 hash 的共同 mapping snapshot。
2. 可評估以 WHATWG Big5 index 作為跨平台一致的起點，但採用前仍須核對產品預期的
   CP950／HKSCS 差異。
3. 五平台一律讀同一 mapping，不呼叫 native converter 決定 membership。
4. 模式名稱明寫「舊系統相容」，不能稱為「可顯示字」或設為新安裝預設。

HKSCS-2008 之後新增字元只配置 ISO/IEC 10646 code point 的政策，也進一步說明未來完整
字集應以 Unicode 為主，而不是繼續把 Big5 當總體候選標準。

## 11. 設定、升級與執行中切換

- 模式值須跨版本穩定，不以顯示文字當 storage key。
- 是否讓既有使用者自動遷移到 `macWindows`，或保留其舊行為，需在實作前決定並寫
  migration test；本計畫不先替使用者做不可逆選擇。
- 模式切換時若正在組字或顯示候選窗，應先結束／取消現有候選 transaction，再用新模式
  重新查詢，並把選取 index 安全重設；不能讓舊 index 套到新陣列。
- 設定頁應顯示 profile 版本；診斷資訊可另顯示 manifest digest，方便跨平台回報。
- 更換或安裝字型時只重畫畫面，不寫入 candidate mode，也不產生新的 profile。

## 12. 驗證與發布門檻

### 12.1 資料測試

- 三個歷史 CIN hash 完全吻合。
- 每個 profile 的 manifest、schema version 與 SHA-256 完全吻合。
- 每個模式的 1,541 組 reading key 都有 golden sequence 或明確空集合。
- 六組歷史例外有獨立 regression test。
- 合併演算法保持各來源相對順序，且 exact string 去重結果可重現。
- 所有 SQL 查詢都明確依 ordinal 排序。

### 12.2 跨平台一致性

五個平台各自匯出：

```text
profile id + profile version + reading key + ordered candidate strings
```

同模式的整體 digest 必須完全一致。測試要涵蓋全部讀音，不能只驗 `ㄏㄚ` 或幾張截圖。

### 12.3 缺字與字型變更

以可控制字型的測試環境，對同一批罕見字分別模擬：

1. glyph 不可用：畫面可顯示缺字方框。
2. 安裝／啟用支援字型：原 slot 顯示正確 glyph。

兩次測試的 candidate count、Unicode strings、absolute ordinal、頁數、頁內位置與 commit
結果必須完全相同；只有畫素輸出可不同。

### 12.4 國家／地區與語言環境矩陣

字型驗收不能只跑開發機的台灣繁中環境。每個支援平台至少選擇可實際取得的下列環境，
記錄 OS build、裝置／OEM、系統語言、地區、偏好語言順序、已安裝或可下載字型、App
toolkit 與最後實際採用的 fallback font：

- 台灣繁中（`zh-TW`）與香港繁中（`zh-HK`）。
- 日文（`ja-JP`）與韓文（`ko-KR`）。
- 英文系統但未額外安裝東亞補充字型，以及安裝補充字型後的對照。
- Android 至少一台 Google／AOSP 基準與一台不同 OEM／市場機型；Linux 至少 Ubuntu
  預設安裝與安裝 `fonts-noto-cjk` 後的對照。

同一批測試字應包含常用繁體字、台港日韓共用但地區字形不同的漢字、CJK Extension
supplementary-plane 字、HKSCS／全字庫罕字、variation sequence 及已知來源的 PUA。
候選窗與提交後的目標 App 要分開截取結果，因為兩者可能使用不同 rendering stack。

驗收產物分成兩層：Unicode sequence／digest 是跨環境必須相同的硬門檻；glyph、fallback
font 與 tofu 清單是環境相關的診斷資料。語言或字型變更前後，只允許第二層改變。

### 12.5 UI 與輸入測試

- 候選標籤、翻頁、點選／數字鍵選取與提交字串一致。
- supplementary-plane、PUA、variation selector、組合字串與無 glyph 候選不造成 index
  位移或 crash。
- 組字期間切換模式不沿用 stale candidate index。
- 關聯詞與標點不做 glyph-based filtering。
- 大型 profile 的啟動時間、查詢延遲、記憶體與套件大小在發布預算內。

### 12.6 最低端到端環境

- macOS：經確認的歷史基準版本，加上當前支援版本。
- Windows 11：TSF；另用歷史環境只做 Windows ㄅ半 profile 對照。
- Android：API 26 與當前支援最新版。
- iOS：iOS 17 與當前支援最新版，Simulator 加實機。
- Ubuntu 24.04 GNOME：Fcitx 5，X11 與 Wayland。

發布前必須保存五平台相同 profile 的 digest、候選匯出檔、版本環境與缺字前後測試證據。

## 13. 建議實作階段

### Phase 0 — 基準確認（未確認前不可寫排序邏輯）

- 由使用者指定正確的 macOS 與 Windows ㄅ半參考 build／設定。
- 建立可匯出全部讀音候選的只讀診斷工具。
- 凍結兩份 v1 profiles，人工抽查並保存完整差異報告。

### Phase 1 — 順位基礎設施

- 加入 profile schema、ordinal、manifest、generator 及全讀音 golden tests。
- 先修正桌面 SQLite 無 `ORDER BY` 的風險。
- 讓五平台在不新增設定 UI 的情況下可讀同一個測試 profile，確認 digest 一致。

### Phase 2 — macOS 主、Windows 輔模式

- 實作 `macWindows`、`macOS`、`windows`、`base`。
- 徹底分離候選 membership 與 glyph rendering。
- 加入設定、migration、組字中切換保護與診斷資訊。

### Phase 3 — 完整及 legacy 模式

- 視需要加入 `fullTiered`、`rawExtended`。
- 只有在 mapping snapshot 與相容需求確認後才加入 `legacyBig5`。

### Phase 4 — 跨平台驗收與漸進發布

- 跑全部資料、缺字、UI、效能與五平台端到端門檻。
- 先以可回退的 beta／測試版觀察，禁止無 migration 地覆蓋候選 profile。

## 14. 實作前仍需決定

1. 哪個 macOS build、設定及字型環境是主基準？
2. 「Windows ㄅ半」確切指哪一個程式版本與模式？
3. macOS／Windows profile 是單純 membership 差異，還是有逐讀音重排／去重？
4. 一般設定只顯示四個主要模式，還是連完整／Big5 模式一起顯示？
5. 既有使用者升級時採新預設，或保留舊設定直到自行選擇？
6. 若保留 Big5，相容目標是 WHATWG Big5、CP950、某版 HKSCS，或另外定義的聯集／交集？
7. profile 更新政策及審核人是誰？是否只允許 major/minor 版本變更？
8. 候選窗是否由產品自帶一套可追溯、可授權散布的罕字 fallback font，還是只依賴各平台
   系統與使用者字型並接受 tofu？若自帶字型，涵蓋哪些標準 Unicode 字、是否包含已確認
   對應的 PUA，以及五平台 extension／套件大小與授權限制都要另案評估。

建議答案是：六組歷史例外原樣保留；一般 UI 先顯示四種模式；Big5 與完整原始序列放進
進階設定；但最終仍需在真正開發前由產品決策確認。

## 15. 明確禁止事項

- 不直接編輯、重新排序或「清理」三份 CIN 來達成模式。
- 不從字型 coverage 推導固定候選 profile。
- 不讓 OS、已安裝字型或 native Big5 converter 改變一般模式的 membership。
- 不依賴沒有 `ORDER BY` 的資料庫回傳順序。
- 不把不能畫出的字改成 `U+FFFD` 或空字串。
- 不以一個讀音、一張截圖或單一平台肉眼觀察宣稱跨平台一致。
- 不在沒有新 profile version 與 migration 說明時改動已發布順位。
- 不把這份計畫視為 1.3.x 發布承諾。

## 16. 參考資料

- 專案內歷史資料：`Source/DataTables/bpmf.cin`、`bpmf-ext.cin`、
  `bpmf-punctuations.cin`
- [Yahoo KeyKey 公開原始碼](https://github.com/Yi-Kai/KeyKey)
- [2008 OpenVanilla／全字庫 CIN 討論](https://www.pczone.com.tw/vbb3/thread/41/124690/5/)
- [2012 libchewing：phone.cin 與 GNU/Linux 顯示過濾討論](https://groups.google.com/g/chewing-devel/c/ednwSjpwzJ8)
- [CNS11643 中文全字庫](https://www.cns11643.gov.tw/)
- [WHATWG Encoding Standard：Big5](https://encoding.spec.whatwg.org/)
- [香港政府 HKSCS-2016 文件](https://www.ogcio.gov.hk/en/our_work/business/tech_promotion/ccli/terms/doc/e_hkscs_2016.pdf)
- [Apple CoreText：依語言偏好取得 fallback cascade](https://developer.apple.com/documentation/coretext/ctfontcopydefaultcascadelistforlanguages(_:_:))
- [Apple：macOS 內建與可下載字型](https://support.apple.com/122869)
- [Microsoft：Windows 字型 fallback／font linking](https://learn.microsoft.com/en-us/globalization/fonts-layout/fonts)
- [Microsoft：Windows 語言相關補充字型](https://learn.microsoft.com/en-us/windows/deployment/windows-missing-fonts)
- [Android：系統字型與 custom fallback 更新](https://source.android.com/docs/core/fonts/custom-font-fallback)
- [Fontconfig：依 charset／lang 的字型比對](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html)
- [Unicode：Private-use characters FAQ](https://www.unicode.org/faq/private_use.html)
- [Noto CJK：台灣、香港、日本、韓國等語言／地區字型](https://github.com/notofonts/noto-cjk/blob/main/Sans/README.md)

以上外部資料用來說明歷史來源、字集與顯示問題；真正發布的順位仍必須由使用者認可的
macOS／Windows 實際基準匯出、凍結及測試，不能只由網路文件推算。
