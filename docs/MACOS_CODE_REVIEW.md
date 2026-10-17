# macOS 程式碼與資料庫檢查 — 2026-09-20

檢查基準：`v1.2.9`、`9b2bf4a`。範圍包含 OSX-IMK 的事件與候選窗、
loader 的資料庫生命週期、共用 SQLite wrapper、關聯詞查詢、macOS cooker，
以及五平台的資料載入、功能與相容性。以下第 1–3 項記錄的是修復前的問題；
本次已修正其 macOS 程式碼；系統安裝的 1.2.9 app UUID 已與測試包一致，
但尚未確認執行中的輸入法是否已重新載入。

**修復驗證：** arm64 Release target 編譯及靜態分析通過；從修正後原始碼擷取詞彙讀取
方法的隔離 probe 連續讀 1,000 次後，未結束 statement 為 0、statement
bytes 為 0、`sqlite3_close` 回 `SQLITE_OK`。候選窗幾何測試涵蓋 350%、
中心／邊緣／第二螢幕與直式最後一列捲動，均通過。仍需在實際 IMK
以 350% 及多螢幕操作檢查文字、捲動條、滑鼠命中與長時間 leak／footprint。
整個舊 target 的靜態分析仍對其他未修改位置提出 warning，不能據此宣稱
所有 macOS 程式碼都沒有洩漏；本次修正的兩個 attributed string 位置已不再報警。

**舊截圖追查：** 使用者確認「第 1、2 列消失、底部留白」發生於先前版本。
實際 controller／NIB 的隔離 AppKit 測試，新版在 100%、200%、350% 及倍率切換後
首列垂直範圍正常，200% 離屏渲染可見第 1–9 列；舊 `a3b838f` 在首次 200%
及 100%／150%／200% 切換也未重現。使用者指出截圖周圍文字大小正常，
故不應將 200% 當作主要原因。不能把本次
螢幕邊界修正等同於此截圖案例已驗收；仍需重現原始操作序列及實際 IMK 行為。
測試使用正式視窗類別，僅替換顏色偏好讀取、送鍵與顯示到前景的副作用。
後續已將直式候選調整為先設定 window frame／content bounds，再排子視圖、
選取、校正捲動，最後重畫；同頁保留合法捲動，只有反白列變更才自動揭露，
換頁／換內容／隱藏重開歸零。
隔離測試在 100% 注入舊 table 高度與 offset 可恢復頂端，大字級有捲軸時
手動捲動與鍵盤反白末列均正常；仍需實際輸入法內驗收舊截圖操作。

**綜合結論：目前優先修復洩漏、量測長時間快取成長，保留資料庫格式。**
縮小 db 主要節省安裝空間，不能等比例減少 RAM；此 Mac 的 SQLite page cache
在廣泛讀音測試約 2.67 MiB，512 KiB 建議預算約降到 0.61 MiB，與整個行程
55.1 MiB 是不同量測範圍。沒有理由僅為檔案瘦身先牽動五平台資料格式。

## 可確認的問題

### 1. [P2] 直式候選每次重畫都洩漏 attributed string

位置：`Source/Loaders/OSX-IMK/CVVerticalCandidateController.mm:213–230`。

每個候選以 `alloc/init` 建立 `NSAttributedString *c`，放入 dictionary 後沒有
平衡原始的 +1 ownership。下一次清空 `_candidateArray` 只能釋放 dictionary
的引用，原始引用會留下；每次九個候選的重畫就新增九個無法回收的物件。
選字、翻頁與更新反白均可進入這條路徑。現已在 dictionary 留住物件後
release 原始引用。

同類問題亦存在於 `CVNotifyController.m:96–104` 的通知文字 `a`。
兩個位置均由 Clang Static Analyzer 的 `osx.cocoa.RetainCount` 確認；
通知文字現亦於計算尺寸後 release。

目前已安裝的 **1.2.8** 行程 PID 9844，從 9 月 17 日啟動至本次檢查：

- `vmmap -summary` 的 physical footprint 為 55.1 MiB，peak 58.7 MiB。
- `leaks -nocontext` 找到 78,961 個洩漏配置，共 3,156,320 bytes（3.01 MiB）。
- 其中 18,631 個 `NSConcreteAttributedString` root leak 與其附屬配置，
  合計 2,978,416 bytes（2.84 MiB）。

這是現有行程的實際洩漏證據，物件類型與上述程式碼一致；沒有 allocation
stack，不能把全部洩漏或整個 55.1 MiB footprint 都歸給某一個方法，也不能
將此當成已跑過 1.2.9 的完整 runtime 測試。

### 2. [P2] 詞彙編輯器讀取每列時遺漏 finalize，連線也無法正常關閉

位置：`Source/Loaders/OSX-IMK/OpenVanillaLoader.mm:673–684`。

`userPhraseDBDictionaryAtRow:` 配置 `OVSQLiteStatement *select` 後直接 return，
缺少 `delete select`。`PhraseEditor/OSX/PEController.m:533` 的 table data source
會在顯示、重畫與捲動時呼叫此方法，因此同一列也會不斷產生新 statement。
這發生在輸入法 loader 行程，而不只是在編輯器行程。

`OVSQLiteConnection` destructor（`OVSQLiteWrapper.h:125–128`）又忽略
`sqlite3_close()` 的失敗；存在尚未 finalize 的 statement 時，save 所呼叫的
delete connection 也無法回收該連線。

驗證：從現有檔案原樣擷取這個方法，在暫存 Objective-C++ probe 中注入一列
`user_unigrams`，只以 stub 取代與資源 ownership 無關的注音顯示轉換。
呼叫 1,000 次並逐次 drain autorelease pool 後：

```text
outstanding_statements=1000
statement_bytes=3552352
close_result=5 (SQLITE_BUSY)
```

probe 自行 finalize 所有 statement 後，未結束 statement 數回到零。
現已使用 `std::unique_ptr` 管理 statement，並處理 prepare 失敗。
修復前後均為隔離的
方法／wrapper 重現，沒有操作使用者的實際詞彙資料庫。

### 3. [P2] 大比例候選窗超出螢幕，部分候選與控制項無法使用

位置：`Source/Loaders/OSX-IMK/CVVerticalCandidateController.mm:272–293`；
橫式控制器亦採相同的邊界處理方式。

預設 18pt 候選字、九列時，直式窗高為 `(18 + 6 + 2) × 9 + 40 = 274pt`，
350% 後為 **959pt**。可視高度 900pt 的顯示器已放不下。
程式只調整 origin，沒有限制窗高或讓內容捲動；底部空間不足時改到游標上方，
也沒有再次檢查上緣。以 visible frame `(0,0,1440,900)`、游標 `(700,450)`、
文字行高 20pt 為例，現有算式給出的 window y 範圍為 470–1429pt。

這是修復前的原始碼幾何推導。現在兩種候選窗共用可視範圍定位；橫式窗在
寬／高超界時降低實際縮放，直式窗則保留一列與控制項所需比例、限制視口
高度，讓過長頁面可捲動並顯示反白列。仍未進行實體 Mac 的視覺與滑鼠驗收。

## KeyKey.db 的空間來源

以當前來源重新 cook 到暫存目錄，與原先 9 月 17 日的資料庫逐表核對。
字典資料、順序、重複條目與其他內容一致；只有 cooker 產生的兩個 service
timestamp 更新。原始資料庫沒有修改。

目前資料庫為 **10,289,152 bytes（9.812 MiB）**，page size 8,192、
page count 1,256、freelist count 0，`integrity_check=ok`。

| 資料及其索引 | 大約占用 |
|---|---:|
| 注音 | 3.87 MiB |
| 倉頡 | 3.58 MiB |
| 簡易 | 1.61 MiB |
| 全部 30 個關聯詞庫 | 0.65 MiB |
| 其他表、索引、schema | 0.11 MiB |

前三者合計占 **92.3%**。刪掉分類關聯詞不是主要節省來源。
三份字表合計 244,575 列，重複 key/value 配對只有 13 列；不值得為去重改變
既有候選順序或內容。注音與倉頡的 value index 提供反查，不能只因體積大
就從共用完整資料庫刪除。注音反查亦用於 macOS loader 的詞彙讀音查詢；
僅提供注音與關聯詞的平台可另做產物分流，但不列為本次記憶體優化首要工作。

## 已做的資料庫副本實驗

| 方案 | 檔案大小 | 比原版減少 | 產品修改範圍 |
|---|---:|---:|---|
| 原版 | 9.812 MiB | — | — |
| 原 schema，8 KiB page，VACUUM | 9.180 MiB | 6.45% | cooker 收尾 |
| 原 schema，4 KiB page，VACUUM | 9.141 MiB | 6.85% | cooker schema／收尾 |
| 原 schema，2 KiB page，VACUUM | 9.197 MiB | 6.27% | 沒有優於 4 KiB |
| 三份字表改 `(key, ordinal)` 主鍵、WITHOUT ROWID | 7.352 MiB | 25.08% | cooker、macOS／iOS reader、Windows SQLite 相容性 |
| 每 key 保存有序候選陣列，另保留反查表 | 6.613 MiB | 32.60% | 資料格式與查詢／解碼重整 |

所有副本通過 `integrity_check`。前三個 VACUUM 方案逐表驗證全部內容與原順序。
WITHOUT ROWID 方案保留原 rowid 為明確 ordinal，逐列重建比對全部字表，
並保留注音／倉頡反查索引。陣列方案使用 UTF-8 JSON，逐 key 比對所有候選、
重複值與反查序列；尚未驗證倉頡 wildcard 的全域順序，也未量其解碼成本。
因此 6.613 MiB 是格式可行性結果，尚非可直接替換的產品資料庫。

iOS `CandidateStore.swift:15` 明確使用 `ORDER BY rowid`；改 WITHOUT ROWID
會使現有 SQL 失敗，必須同步改成 ordinal。macOS 的共用
`OVSQLiteDatabaseService.h` 目前也沒有明確指定候選順序，調整 schema／索引前
需把順序契約寫進查詢。Windows 雖另有 cooker，但也使用該共用 reader 與
同一份 `Schema.sql`，並內建 SQLite 3.6.11；不能直接套用 WITHOUT ROWID。

SQLite 說明：
[VACUUM](https://www.sqlite.org/lang_vacuum.html) 會壓實表與索引，沒有 freelist
也可能節省空間；未使用 INTEGER PRIMARY KEY 的隱含 rowid 可能重編，
所以 cook 後必須驗證候選順序。
[WITHOUT ROWID](https://www.sqlite.org/withoutrowid.html) 可減少重複 B-tree
資料，但需要調整依賴 rowid 的查詢。

## 記憶體與查詢成本

既有 macOS app 的 `otool -L` 確認連結 `/usr/lib/libsqlite3.dylib`，
未使用 repository 內的歷史 SQLite 3.6.11。使用本機系統 SQLite 3.54.0
連結的 C++ probe 量到 `cache_size=2000`、`mmap_size=0`。
原版 8 KiB page 對應建議快取上限 15.625 MiB，按需配置，並非啟動時讀入
整份資料庫。Mac 實際行程的 footprint 也不能由 db 檔案大小推算。

probe 模擬每次查詢 prepare、bind、step、複製候選字串、finalize，先用 32 個
分散讀音重複查詢 3,200 次，再將全部 1,523 個二字元讀音查詢三輪。
每個設定以獨立行程重跑三次；下表 latency 取三次結果的中位數。
這是本機已暖機的資料層測量，不包含 IMK、UI、真實鍵盤與冷啟動 I/O。

| 配置 | 32 個讀音後 cache | 全讀音後 cache | 全讀音查詢 median / p95 |
|---|---:|---:|---:|
| 原版／預設 2000 pages | 0.533 MiB | 2.668 MiB | 19.38 / 33.17 μs |
| 原版／cache_size=-512 | 0.533 MiB | 0.613 MiB | 21.08 / 35.33 μs |
| 4 KiB + VACUUM／預設 | 0.296 MiB | 2.537 MiB | 19.08 / 33.29 μs |
| 4 KiB + VACUUM／cache_size=-512 | 0.296 MiB | 0.628 MiB | 19.04 / 34.00 μs |
| WITHOUT ROWID／cache_size=-512 | 0.167 MiB | 0.628 MiB | 18.17 / 29.63 μs |

所有被測配置的候選內容／順序 checksum 一致。Cache 數字來自
`sqlite3_db_status(SQLITE_DBSTATUS_CACHE_USED)`；本機系統 SQLite 的全域
`sqlite3_memory_used()` 回傳 0，不能據此聲稱沒有配置記憶體。

[`PRAGMA cache_size=-512`](https://www.sqlite.org/pragma.html#pragma_cache_size)
表示約 512 KiB 的建議頁面預算，只在該連線期間有效；實際配置還含管理成本，
因此不是 512 KiB 的硬性 heap 上限。這也不限制候選 C++ vector、AppKit
物件或其他資料庫連線。

512 KiB 僅為此次 Mac 的測試點，不是五平台通用設定。ownership
修正已完成，仍須量測長時間成長；cache 是否值得調整由實際 workload 決定。
當下約 55 MiB 的行程用量不可能僅靠縮小 db 就等比例下降；VACUUM、4 KiB
及 schema 變更保留作為後續選項。

## 五平台的記憶體取捨

應共用原始字詞資料及順序驗證規則，依平台實際功能決定載入及快取策略。
macOS 的 cache 測量不能代表其他平台；目前不統一改資料格式。

| 平台 | 現行使用情況 | 優先調查／改善 | 驗收重點 |
|---|---|---|---|
| macOS | 系統 SQLite，完整 db 按頁查詢；IMK 常駐 | attributed-string／statement 洩漏已修，實測修正前後的長時間記憶體成長 | 候選反覆重畫、詞彙編輯 save／close、切換 App；保留注音、倉頡／簡易、wildcard、反查及關聯詞 |
| Windows | SQLite 3.6.11；TSF DLL 每個 host process 各有 runtime | 量多 App 合計用量及各連線 cache，不能直接搬用新版 SQLite pragma | x86／x64 host、Traditional Mandarin＋關聯詞、設定程式及原生 cooker |
| iOS | 系統 SQLite；extension 內一份 db，容器編輯器也讀同檔 | Swift 候選 cache 隨讀音增加，需量多讀音及記憶體壓力 | extension 與容器分別量；軟／硬體鍵盤、反覆叫出、全部詞庫、低記憶體裝置 |
| Android | 不讀 db；`.kki` bytes＋索引，查過的候選解碼後快取 | 解碼 cache 成長、載入時暫時複製、冷啟動及 GC | Pixel C／Android 8、全開／全關詞庫、切換欄位及六個 API 等級 AVD |
| Linux | 不讀 db；Fcitx 5 啟動時把 CIN／詞庫解析成 C++ maps | 量字典常駐成本，評估未使用字典／詞庫延後載入或預編譯 | Ubuntu 24.04 GNOME amd64 的 Fcitx 行程；注音、倉頡／簡易、繁簡轉換、關聯詞及切換延遲 |

### Windows：相容性已實測，暫緩格式變更

`Windows-TSF/CMakeLists.txt:40` 直接編譯 repo 的 SQLite 3.6.11；
`DatabaseCooker.cpp:590` 讀取共用 `Schema.sql`。
`KeyKeyEngine.cpp:185–189` 的 runtime 為行程內 singleton，各 host 不共用
C++ runtime／SQLite page cache。關聯詞模組使用該 runtime 既有連線。

直接用 repo amalgamation 在 Mac 編譯隔離 C probe，結果：

- 原版 db 與下述 4 KiB 注音副本均 `integrity_check=ok`、注音 98,336 列。
- WITHOUT ROWID 副本讀 schema 回 `SQLITE_CORRUPT (11)`：
  `malformed database schema ... near "WITHOUT": syntax error`。
- `cache_size=-512` 再讀回 **512 pages**；8 KiB page 為 4 MiB、
  4 KiB page 為 2 MiB 的建議預算，並不是 512 KiB。

這證明 SQL 格式／pragma 差異，未代替 Windows DLL 建置或效能測量。
[WITHOUT ROWID 要求 3.8.2 以上](https://www.sqlite.org/withoutrowid.html)，
[負數 cache_size 的 KiB 意義從 3.7.10 才開始](https://www.sqlite.org/pragma.html#pragma_cache_size)。
日後設定 cache 應由平台處理，或按實際 page size 換算正數頁數；不要將
`-512` 直接放入共用 wrapper。SQLite 升級應獨立驗證，無須綁在首波記憶體修正。

### iOS／Android：application cache 不受 SQLite cache 限制

- iOS `CandidateStore.swift:10–11,36–40` 的 `[String:[String]]` 沒有淘汰
  機制，會保留查過的候選，直到 store 結束生命週期。這是可達的快取，
  應量測多讀音後的實際成本，再決定有成本上限的 LRU／壓力時清理。
  現有 `MemoryProbe.swift` 的 10,000 次查詢只重複同一讀音與字首，不能
  驗證此種成長。`AssociatedPhraseStore.byHeadCharacter` 實際按來源數量
  快取 statement，變更設定會清除，不能誤判成每個字首都有一份 statement。
- Android `IndexedDictionary.java:30–32,75–92` 同時保留原始 byte[] 與
  已解碼的 Java 字串 cache，也沒有淘汰機制。`load():41–68` 的
  ByteArrayOutputStream 到 byte[]、以及索引 `Map.copyOf` 有暫時配置成本；
  應區分啟動峰值、穩態 heap 及 GC。主注音索引在 `onCreate` 同步載入，
  關聯詞才走背景 executor。`AssociatedPhraseDictionary.load` 已只載入
  啟用的詞庫，全關時回 empty，應保留此策略。

iOS 容器與 extension 雖共用一份打包檔，各自行程仍有獨立 SQLite cache／
Swift 物件。Mac probe 不能代表實機 extension 的限制；不要假定所有
iPhone／iOS 都有同一個固定記憶體上限。以上是原始碼確認的快取行為，
尚未證明它們在實機造成記憶體壓力或終止。

### Linux：保留既有共享，量測啟動載入

`fcitx5_engine.cpp:232–240` 一次載入注音、倉頡、簡易、標點、繁簡對照及
全部關聯詞。`cin_dictionary.h` 使用 `unordered_map<string,vector<string>>`；
`associated_phrase_dictionary.cpp:330–404` 解析各個 collection 並常駐保存。
關閉某個詞庫的候選顯示不會省去這份解析與配置。不同注音鍵盤 engine 已以
`shared_ptr` 共用字典，不能錯算為每個鍵盤都複製一份。

延後載入也可能把成本移到第一次切換，須量 Fcitx 主迴圈停頓及功能切換，
再決定是否值得改；`KeyKey.db` 的 VACUUM 對 Linux 沒有直接作用。

### 留存的空間實驗：不是目前優先的 RAM 修正

iOS SQL 僅使用注音、關聯詞及分類名稱表；Windows package 現階段只註冊
Traditional Mandarin＋關聯詞，設定程式讀分類名稱，標點回退查注音表。
兩個現行 frontend 未發現注音 value-to-key 反查的消費者。

從本次 Mac cooker 的完整 db 建立副本，保留上述三表及小型
`prepopulated_service_data`，刪去其他輸入法表後採 4 KiB＋VACUUM：

| 注音產物副本 | 大小 | 比原完整 db 減少 |
|---|---:|---:|
| 保留注音反查索引 | 4.254 MiB | 56.65% |
| 不含未使用的注音反查索引 | 3.082 MiB | 68.59% |

完整保留 98,336 列注音／符號、7,231 列關聯詞及 30 個分類；逐表按 rowid
比對全部內容，另逐一比對 1,677 個 key 的候選序列，均一致。
但原先未查過的倉頡頁通常就未讀入 SQLite cache，不能把省下的 6.73 MiB
檔案空間全算成 RAM 收益。因此依目前需求保留此實驗，暫不改打包或格式。

若日後需要減少下載／安裝體積，才考慮明確的功能 profile 與獨立輸出路徑；
不能讓 iOS CI 覆蓋共用 db 而移除 macOS 所需功能。Windows 原生 cooker 另做
ANALYZE，正式體積及相容性須從其入口驗證，此處不是 Windows 發布包測量。

### 尚待執行的跨平台驗收

記憶體改動應比較冷啟動、暖機首鍵／p95、多讀音、詞庫全開／全關與長時間
成長。macOS 驗完整輸入法組合及詞彙編輯；iOS 分開驗 extension／容器；
Windows 驗 x86／x64 多 host；Android 按既有 API 26、28、30、33、35、37
六台 AVD 計畫及 Pixel C／Android 8 實機需求；Linux 驗目前發布範圍
Ubuntu 24.04 GNOME amd64。這些不能由單台 Mac 的資料層 probe 取代，
也不算此次已完成的五平台測試。

## 本次驗證與留存

- 原始碼檢查、事件控制器、直／橫候選與通知的 Clang analyzer。
- 既有 1.2.8 行程的 `vmmap` 摘要與不顯示物件內容的 `leaks`。
- 從當前來源 cook 新 db；五個副本的 integrity 與資料內容核對。
- 系統 SQLite 查詢／cache probe，以及詞彙查詢 statement 生命週期 probe。
- 五平台建置／查詢／快取路徑檢查，兩個注音副本及 SQLite 3.6.11 相容性 probe。
- 修復後 arm64 Release target 編譯及靜態分析、詞彙 statement probe、幾何／捲動測試。
- 未部署、未重啟使用者輸入法，未跑五平台完整 UI／裝置／發布測試。

暫存實驗目錄：`/private/tmp/keykey-macos-review-20260920/`。
內含 `compare_databases.py`、`database-results.json`、`sqlite_probe.cpp`、
`sqlite-probe-results.json`、`phrase_statement_probe.mm`、`platform_profiles.py`、
`platform-profile-results.json`、`legacy_sqlite_probe.c`、`legacy-sqlite-results.txt`
與 analyzer／leaks logs。
暫存內容不進版控，可依上述參數重新建立。
