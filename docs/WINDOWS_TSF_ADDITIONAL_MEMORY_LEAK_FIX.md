# Windows TSF 額外記憶體與符號表修正

本輪排除 `WINDOWS_TSF_MEMORY_SAFETY_REVIEW.md` 已查過的缺陷，修正另行確認的兩個問題，
並依使用者新提供的白框截圖調整符號表取消生命週期，後續另補上四處共用資源釋放。
本批依使用者要求提交至 `v1.3.2` 工作分支；Windows 產品版號仍為 1.3.2。
前一輪 agent 只建置及封裝、未安裝或註冊 TIP；使用者隨後已回報安裝該修正版並重新登入。

## 外部注音字表所有權

Windows `OVIMSmartMandarin::initialize` 配置的 `Mandarin-bpmf-cin` 字表由模型接管。
`LanguageModel` 新增明確的 `ownsExternalTable` 參數與 RAII owner；析構先釋放字表，再釋放
有所有權的 DB connection。參數預設 false，維持評測工具及其他既有呼叫端自行管理字表的行為。
只有 Windows 好打注音呼叫端傳入 true；macOS 既有呼叫行為保持不變。

回歸驗證 100 次 owned 模型建立／析構，每次字表恰好析構一次；borrowed 字表在模型析構後仍由
呼叫端管理。這修正每次引擎重建遺留的子物件，與舊文件中整個 runtime 缺乏清理入口的問題不同。

## DB 持續拒絕寫入時的待存容量

Windows 兩份 pending map 各有獨立的最近使用順序，容量與對應學習 cache 一致，皆為 200 個
不同 qstring。更新已有項目會移到最近端，刪除標記同樣計入容量；超量淘汰最舊的未存學習。
這是忙碌或持續寫入失敗時的有界保留策略：超量的舊學習可被丟棄，不影響文字輸入或使用者詞條。
成功保存及 reset/import generation 改變時，同時清空 pending map 與順序記錄。

回歸以第二個真實 WinSQLite connection 持有 writer lock，加入 1,000 個不同項目並持續更新
重複項目及刪除標記。每次檢查兩個 map 各不超過 200，順序記錄與 map 大小相等；失敗儲存不
宣稱成功，解除 lock 後保存最新值與刪除，捨棄最舊項目，DB 行數維持上限，pending 與順序歸零。
另保留跨程序設定／學習合併、reset/import 防舊資料回寫及 integrity_check 的既有回歸。

## 新白框事件與符號表取消

使用者回報無特別操作且白框持續存在，第二張截圖顯示矩形約 440×430。
唯讀系統快照在 ChatGPT pid 6600 找到 `chichi77.KeyKey.TSF.SymbolPanel`，HWND `0x70694`，
owner `0x50596`，rect `(639,429,1079,859)`，尺寸恰為 440×430，但 `IsWindowVisible` 為 false。
同一快照沒有可見的 KeyKey 候選窗。已載入 DLL 是
`C:\Program Files\chichi77 KeyKey\1.3.2-3e0151c5a05c\KeyKeyTsf_x64.dll`，
SHA-256 `52e65a5975eb6cc6098121cdf0d31f088126d5e9612ac5727e5206271441885e`。

使用者接著從工作列重新開啟符號表並按 ×，確認白框消失。關閉後的唯讀快照仍找到同一
`0x70694`、同一 owner 與同一 440×430 rect，且 visibility=false：舊版正常關閉確實保留
該 HWND，重新顯示／關閉會刷新這個表面。快照分別保存為 `white-window-before-close.txt` 與
`white-window-after-close.txt`。這是此次實機事件與符號表生命週期相符的額外證據。

使用者再回報白框自行復發，截圖同時有安裝程式視窗，並指出可能發生於安裝過程。
此次唯讀快照仍為同一 `0x70694`、owner、440×430 尺寸及 visibility=false，ChatGPT 行程
仍載入上述舊路徑與舊 DLL 雜湊。記錄為 `white-window-recurrence-20261011.txt`、
`white-recurrence-details-20261011.txt` 及 `white-recurrence-KeyKeyTsf-20261011.log`。
安裝視窗／焦點變化是待追查的觸發條件，沒有捕捉到最初變白那一刻的訊息，不能據此確認因果。
這次只保存診斷快照，依使用者指示不再執行測試。

這支持隱藏符號表／合成表面殘留的方向，尚未直接證明 DWM 白色像素屬於該 HWND，也未捕捉最初
觸發事件。現場快照及原診斷 log 保留在忽略的 `out/tsf-review/`，不提交執行紀錄。

符號表取消現在一律 DestroyWindow，不再保留正常隱藏的 HWND。子控制項隨父視窗銷毀，
字型、適用的 emoji bitmap cache、分類、DPI 與完成拖曳的位置保留，重新開啟時建立新視窗。
捲動仍重用活躍面板控制項。DestroyWindow 失敗時先移除 topmost／可見狀態，保留 handle 供重試。
診斷開啟時增加 create/show/hide/visibility/paint/destroy 記錄，含 HWND、owner、分類索引、
控制項數、generation 與矩形，不記錄輸入或符號文字。

原生回歸涵蓋普通關閉後 HWND 不存在、舊 handle 無法重新置頂或接收點擊、延遲 owner restore
訊息不能還原已取消面板、重開繪製、位置／字型保留、emoji／顏文字完整選取、捲動、DPI、失焦、
分類選單內取消、owner／服務銷毀與 IME SHOW/HIDE/CHANGE 事件。

## 使用者安裝後的追加修正（2026-10-11）

使用者要求繼續修記憶體洩漏，白框若再出現才另行追查，當時維持不追加測試；
之後使用者改為要求「跑測試」，追加驗證結果見下節。
本批依程式碼所有權及釋放路徑確認四處問題，與前述已測修正分開記錄：

- `OVSQLiteConnection::Open`：`sqlite3_open` 出錯仍可能配置 connection，舊版直接回傳 0，
  遺失 native handle。現在先初始化為 0，出錯時關閉非空 handle。契約亦載於本地
  `Source/ExternalLibraries/sqlite/sqlite3.h` 的開啟 DB 說明；Windows 實際使用 SDK WinSQLite。
- 舊 `UserPhrase.db` 搬移：`fetch` statement 沒有 delete，讀取結束後仍阻止 `sqlite3_close`，
  wrapper 析構後也失去 connection。現在在讀取迴圈結束後釋放 statement，再關閉及移除舊 DB。
  只有存在舊詞庫且成功 prepare 的搬移路徑觸發，不能當作一般每次按鍵的洩漏。
- `PVModuleManager`：`moduleAtIndex` 建立的新模組在排除名單分支沒有刪除；析構也只刪除
  已初始化模組。現在排除時立即刪除，manager 析構時刪除所有持有模組，僅已初始化模組
  呼叫 finalize。Windows loader 會讀取 `ExcludedModules`；正常啟動通常會初始化其餘已知模組。
- plist 解析器：原有 static `new string` 未釋放，DLL 重載遺留 string 及容量；DLL 常駐時也
  保留上次解析的文字容量。改為 parser instance 的 string，成功、解析錯誤或例外返回後均
  隨 parser 析構回收。既有 Windows 解析 mutex 與損壞設定拒絕邏輯保留。

以上是 Windows 所連結共用框架的修正，也會影響其他使用相同程式碼的平台；沒有改詞庫或產品版號。
修正當時不跑 ctest、ASan、原生探針或實機 UI 操作，只有程式碼釋放路徑的證據。
Release x64、x86 的 `KeyKeyTsf` 與 `KeyKeySettingsBackend` 均建置成功，`git diff --check` 通過。
當時只建置產品 targets，未建立或執行新增測試；紀錄在忽略的
`out/tsf-review/build-leak-followup-{x64,x86}-ninja.log`。
這四處不包含在使用者剛安裝的 `memory-symbol-fix-20261011` 安裝檔中。

## 追加測試（2026-10-11，使用者要求恢復測試）

新增 `KeyKeyMemoryResources` 原生回歸，連結 Windows 產品使用的共用核心及 SDK WinSQLite。
所有檔案在獨立 profile，沒有修改使用者詞庫或註冊／安裝 TIP：

- 先以不存在的父目錄確認 native 開檔失敗仍配置非空 handle，再重複 256 次 wrapper 開檔失敗。
  每次結束後 `sqlite3_memory_used()` 均回到初始值；Release／ASan、x64／x86 都是 0 → 0 bytes。
- 以真正的 `OVIMSmartMandarin::moduleInitialize` 跑 20 次舊 `UserPhrase.db` 搬移。
  每次確認匯入詞條值保留、舊檔已移除、模組／DB 析構後 SQLite 配置回到基線（0 → 0），
  並可獨占開啟新使用者 DB，確認沒有遺留檔案 handle。
- 100 次建立／銷毀 module manager，每次包括被排除、未使用、初始化成功及初始化失敗四種模組。
  四個物件均恰好析構一次；只有曾執行初始化的兩個物件呼叫 finalize，被排除者立即釋放。
- 100 次解析 65,536-byte 文字、巢狀 dict／array 與 XML escape，接著拒絕截斷 XML，再解析新文字。
  既有 `KeyKeySharedDataProtection` 另覆蓋八執行緒解析、損壞設定保留及原子檔案讀寫。
  解析測試確認行為與 ASan 記憶體安全，不提供所有 C++ heap 配置的精確洩漏數量。

| 選定回歸 | x64 | x86 |
|---|---|---|
| Release | 單次 21/21 | 首次 20/21；符號選單獨立重跑 1/1，21 個案例均曾通過 |
| ASan | 單次 5/5 | 單次 5/5 |

Release 包含新資源回歸、共享資料、DLL 卸載、popup／符號／TSF 送字、注音／表格輸入、
進階設定及候選狀態。ASan 五項為資源、共享資料、popup、TSF 送字及符號表，沒有 ASan 錯誤。
ASan 不執行 instrumented DLL 卸載；Release 兩架構仍各完成 10 次 DLL 重載及 20 次 runtime 清理／重建。

x86 Release 首次符號案例失敗於 `Native category popup did not open`；獨立重跑通過，
首次失敗原因尚未確認，不宣稱整批初次全數通過，也不把它當作記憶體洩漏證據。
UI 測試按架構依序執行。需要原子設定替換的回歸及 ASan 建置使用一般使用者環境，
其餘 Release 編譯在沙箱完成。`git diff --check` 通過。

紀錄在忽略的 `out/tsf-review/`：`leak-tests-{x64,x86}-ninja.log`、
`leak-tests-symbol-x86-isolated.log`、`leak-tests-{x64,x86}-asan.log`、
`leak-tests-detail-x64-ninja.log`、`leak-tests-detail-{x64,x86}-asan.log`，
以及 `leak-tests-build-{x64,x86}-{ninja,asan}.log`。
這次沒有重打安裝檔；目前已安裝版本仍不包含此批四處追加修正。

## 前一輪驗證記錄（不包含上述追加四處）

Release x64、x86 建置成功。各架構選定的 20 項回歸分批通過：第一批 18 項通過，
共享資料測試因沙箱原子設定檔替換受阻，以一般使用者權限在隨機暫存 profile 重跑通過；
符號測試因舊斷言假設已關閉控制項仍存在而失敗，更新為要求舊 HWND 已退役後重跑通過。
符號測試及 popup lifecycle 最終各 2/2 通過。未把第一批結果描述成一次 20/20。

入口：`KeyKeySharedDataProtection`、`KeyKeyPopupLifecycle`、`KeyKeySymbolPanelResourcesAndFocus`、
`KeyKeyModuleLifetime`、`KeyKeyTsfOutputCommitBehavior`，另覆蓋全部選定 engine/table/candidate 回歸。
執行紀錄：`additional-fix-release-{x64,x86}.log`、`additional-fix-shared-{x64,x86}.log`、
`additional-fix-symbol-{x64,x86}.log`，皆在 `Source/Loaders/Windows-TSF/out/tsf-review/`。

ASan x86 選定 4/4 通過；x64 三項通過，分類選單測試在兩架構共用桌面並行時沒有開啟，
單獨重跑該項通過，合計四個選定案例通過。沒有 ASan 錯誤報告，不把它解讀成完整 heap 洩漏證明。
ASan 編譯在沙箱遇到 MSVC C1902/PDB 錯誤，改於一般使用者環境完成；各測試仍使用隔離 profile。
ASan 記錄為 `additional-fix-asan-{x64,x86}.log` 及 `additional-fix-asan-symbol-x64.log`。
原始碼／隔離測試不等於已安裝版本或實際 App 驗收，
上述測試執行時尚未安裝修正版；其後使用者已回報更新及重新登入，白框等待使用者回報是否復發。
