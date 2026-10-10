# Windows v1.3.2 功能分支驗證

2026-10-04，以 `c44a3a5eb06703381eb37f2ec82a3e698ec0db9f` 為基底，在本機 `v1.3.2` 開發。
當時產品版號維持 1.3.1；尚未 push、發布、註冊或替換使用者已安裝的輸入法。
本文件依日期保留各輪證據；目前 Windows 已升至 1.3.2，最新版本與封裝驗證見文末。

## 已實作

- 好打注音進階設定：空白開候選、候選目標在游標前／後、8 個唯一可輸入 ASCII 鍵、10–20 音節。
  留空候選鍵沿用許氏／倚天26／其餘配置原預設。非法 profile 值由 Windows adapter 收斂。
  UI 在任何設定寫入前驗證所有新值；下一次輸入保留舊組字後才使用新設定。
- 讀音輔助：唯讀正式 DB 完整詞優先、逐字選單與人工修改、缺字提示。
  每次最多 64 Unicode code points、每字與完整詞各最多 32 讀音，不展開笛卡兒積。
  Native snapshot 有明確 free、buffer 容量包含 NUL，空查詢與 DB 錯誤可區分。
  存詞沿用既有 rowid、去重與音節數驗證，不改模型或既有個人資料。
- 符號表：原生不啟動 WPF CLR、非啟用面板、17 分類／733 Buttons／74 Messages。
  從原 plist 在各 build directory 生成並內嵌，共 807 個完整字串。
  選取經 TSF edit session 先完成組字再插入；保留全半形，取消與焦點生命週期使回呼失效。
- 簡體輸出：一般提交、長句擠出、模式切換、失焦保字與符號使用同一文件輸出轉換。
  組字／候選／學習維持繁體；組字快照保留其開始時的輸出設定，後續輸入使用新值。
  只對漢字使用既有 OVOFHanConvert 表，標點／英文／數字／emoji 維持原樣。
  UI 直接發佈 TSF 全域狀態，桌面採用受限宿主的新狀態後保存設定；測試 profile 使用獨立 GUID。
  字表授權與來源通知包含在 ZIP。

## 本機環境與命令

Windows 11（SDK 10.0.26100.0，目標 10.0.26200），Visual Studio 18 Community、.NET 10 SDK。
CMake／CTest 使用 Visual Studio 內附版本，Python 使用 Codex bundled Python 3.12.14。
以 `windows-x64-vs2026` 與 `windows-x86` configure/build presets 建置；x64 額外 clean-first
排除既存 object，建置／測試全程使用隔離 profile。TSF broker 在 sandbox token 下拒絕
臨時 compartment 寫入，需在 sandbox 外執行隔離回歸；不觸及正式使用者 GUID。

```powershell
cmake --preset windows-x64-vs2026 -DPython3_EXECUTABLE=<bundled-python>
cmake --preset windows-x86 -DPython3_EXECUTABLE=<bundled-python>
cmake --build --preset windows-x64-vs2026-release
cmake --build --preset windows-x86-release
ctest --test-dir out/build/x64-vs2026 -C Release --output-on-failure
ctest --test-dir out/build/x86 -C Release --output-on-failure
dotnet run --project SettingsModern.UiTests --configuration Release -p:KeyKeyRuntimeDirectory=<fresh-x64-Release>
dotnet publish SettingsModern.UiTests --runtime win-x86 --self-contained true --output out/ui-tests-x86
# 將新 x86 backend 與正式 DB 複製到隔離 test runtime，再執行 SettingsModern.UiTests.exe。
./Validate-Frontend.ps1
python ../../Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py ../../Distributions/Takao/CookedDatabase/KeyKey.db
python ../../Distributions/Takao/DatabaseCooker/verify-shared-database-wiring.py
./Package-Windows.ps1 -BuildDirectory out/build/x64-vs2026 -X86BuildDirectory out/build/x86
./Package-Windows.ps1 -BuildDirectory out/build/x64-vs2026 -X86BuildDirectory out/build/x86 -Architecture x86
python Packaging/verify-package.py out/package/chichi77-KeyKey-1.3.1-windows-x64.zip out/package/chichi77-KeyKey-1.3.1-windows-x86.zip
```

## 驗證結果

兩架構完整建置成功。既有 engine／candidate／table、TSF interface／工作列／隔離 registration、
deployment、共享輸入法與 AppContainer 回歸通過。
最後 x64 CTest **28／28** 通過（10.86 秒）、x86 **27／27** 通過（8.25 秒）；
x86 自含 WPF 測試另行通過。四種輸入法均以「車」確認引擎維持繁體、共用輸出得到「车」。
TSF mock 行為測試在兩架構通過一般提交、長句前段／繁體 preedit、舊狀態保字、
同步鎖拒絕後的延後提交、失焦、符號輸出、舊回呼與 read／write 失敗不截斷。
進階 engine 測試包含非數字鍵選字、許氏／倚天26自動候選鍵、非法設定收斂、
12 音節的完整詞段擠出、19 音節全句保存及組字中修改設定。
原有固定長句測試確認預設第10／11音節和全文不遺失／重複。

WPF 真實控制項與 native backend 在 x64、x86 均通過：非法值零寫入、保存後重開、
讀音完整詞／破音字／缺字／補充平面漢字／長詞、人工讀音保留、rowid／去重／重新讀取，
以及 P/Invoke sizing／容量不足不截斷／無效索引／釋放契約。
原生設定持久化測試在兩架構通過快速開關、未來 mtime、XML escaping、其他設定與 array 保留。

符號面板在 x64、x86 通過完整807項、長顏文字、滑鼠選取不奪焦點、翻頁、單次回呼、
取消、owner 銷毀後重新開啟。簡體共享隔離 GUID 在 x64、x86 的跨程序與 AppContainer、
以及 x64→x86 子程序通過。轉換測試確認原標點寬度、emoji 與補充平面字保持。

正式 DB 與新 build runtime copy 都保持 SHA-256
`8fc3aead36cefd16a77c0a0d4319f7a305fb712b752db09396c8ac2bd4ebbfdb`；
119,159 Unigram、883,372 Bigram，完整性及五 frontend wiring 驗證通過。
本機原 checkout 部分文字檔有 CRLF 與既有 `eol=lf` attributes 不一致，僅落盤回 LF
即通過既有來源雜湊 gate；這些檔案與 HEAD bytes 相符且無來源 diff。

## 產物與未驗證界線

開發 DLL、settings、backend、部署程式及測試在
`Source/Loaders/Windows-TSF/out/build/x64-vs2026/Release`、`out/build/x86/Release`。
x86 自含 WPF 測試在 `out/ui-tests-x86`；ZIP 在 `out/package`，維持 1.3.1 檔名以反映未升產品版號。
所有 build、測試記錄與 ZIP 都是 ignored 產物。
x64 ZIP verifier 通過 15 個 payload 檔案，x86 通過 14 個；逐檔 SHA／PE 架構／正式 DB／
設定指南與 HanConvert 授權通知皆核對。打包時依 CMake generator 選擇同一 runtime directory，
避免 Visual Studio 的新 Release DLL 與 build root 殘留舊 DB 混包。
NSIS Store 腳本同步相同 runtime 選擇與通知，但本輪未建置或驗收 Store EXE。

Mock TSF edit-session 行為、引擎、真實 WPF 控制項、broker compartment、原生面板與已安裝版本
是不同證據層級。本輪沒有替換已安裝版本，未驗收新 DLL 在 Notepad／Search／Word／Edge／
Windows Terminal 的真實文字宿主、x86 實際宿主、高 DPI、多螢幕、Windows 10、secure desktop
或實機焦點／長句組字行為。發布前仍需在隔離 VM／測試機完成這些項目；
本輪原始碼與自動測試不等於已安裝產品或全面實機驗收。

## 2026-10-05：Windows 符號表升級

- 工作列的原生 TSF 選單與桌面 fallback 選單皆依「半形／全形、簡體中文輸出、分隔線、
  符號表、輸入法設定」排列；原有選單 ID、勾選狀態與切換行為保留。
- 符號表改用原生分類下拉；依 plist 的 `IsSymbolButtonList` 旗標保留 16 個格狀分類與
  1 個顏文字清單，共 807 項。生成器只讀 iOS 引擎的 `emojis` 陣列保留 90 個完整字串的
  原順序，再從 Windows 專用 `SymbolEmojiSupplement.json` 加入 110 個常用 emoji。
  合計 18 類／1,007 項；記錄三份來源 SHA-256，CMake 追蹤三份來源，不改手機、共用 plist 或 DB。
  合併 200 項以 ordinal 字串比較驗證唯一性，不使用文化排序比較 Unicode emoji。
  缺少陣列、重複項目與不支援的跳脫格式皆明確失敗，三種負控制已確認拒絕。
- 格狀按鈕最多十欄，工作區／DPI 決定每頁容量；初始 96 DPI 常用符號為十欄四列。
  顏文字整列顯示並插入完整 Text。Emoji 共 200 個，一般大小每頁 40 個、五頁，
  小工作區／DPI 下頁數隨容量調整。
- 標題列可拖曳而不取得焦點；同一 SymbolPanel／輸入服務生命週期記住最後拖動位置，
  不寫入設定、不跨 App／重啟保存，重開與 DPI 變更時限制於可用工作區。
- 下拉選單的 nested loop 以 generation 與獨立 lifetime token 防止 hide、owner 銷毀或整個
  面板析構後套用過期結果。選字仍一次送字後關閉，由既有 TSF context 檢查確保原輸入宿主。

兩架構 MSVC/Ninja 原生 targets 已 clean-first 重建，選定 CTest 各 **14／14** 通過：
x64 1.58 秒、x86 1.79 秒。涵蓋面板、兩條工作列選單順序、TSF 輸出／候選版面回復、
偏好設定、數字鍵盤、注音、Esc、倉頡／簡易與候選狀態。
面板測試先確認 `GetFocus()==host`，真正展開原生 popup，透過 popup 的 WM_CHAR
type-to-select 選取唯一 Emoji 項並取消／切換，確認宿主焦點不變；不使用 SendInput 或改動
使用者鍵盤／游標。另涵蓋 Emoji 所有頁面、代理對及 variation selector、完整顏文字、
單次回呼、拖動／重開位置、工作區限制、小面板、模擬 150% DPI、popup 中 hide／owner
destroy／panel delete，以及 Esc／關閉取消。TSF 行為仍屬隔離宿主及 mock 驗證。

本輪發現本機 Ninja 的 MSVC showIncludes 前綴被 code-page 解碼破壞，標頭依賴為零，
增量建置曾混入舊 TextService object 並使 TSF 測試崩潰。CMake 現在只對 MSVC/Ninja 探測
原始前綴並使用 `MsvcCompiler.py`，正規化 ANSI／UTF-8 前綴與 include 路徑；保留其餘診斷、
compiler exit code 與既有 launcher 鏈，其他 generator 不變。兩架構 `ninja -t deps`
皆確認 TextService object 有 15 個依賴，明列 `SymbolPanel.h`／`TextService.h`，clean-first
後上述 TSF 崩潰消除。轉接亦已確認退出碼 7、原診斷及非 ASCII include 路徑轉換。

原生 PrintWindow 畫面在 `Source/Loaders/Windows-TSF/out/symbol-panel-visuals/`，
包含 symbols-light、emoji-light、kaomoji-light、symbols-150dpi 與 dark／contrast palette。
符號、emoji、顏文字、150% 字型及暗色畫面已人工視覺核對；dark／contrast 是測試調色盤，
不能當成實際切換 Windows 系統主題或高對比的驗收。已安裝 TIP、Firefox／其他文字宿主、
實際跨螢幕／DPI 操作與 Windows 10 仍待實機驗證，沒有安裝或切換使用者目前輸入法。

### 彩色 Emoji 與重繪補驗

Emoji 儲存完整 UTF-16 字串，首次繪製時才建立 Direct2D software DC render target 及
DirectWrite Segoe UI Emoji 格式，以 `ENABLE_COLOR_FONT` 繪製系統彩色字型。字號為 25 DIP，
綁定按鈕文字內框並只換算一次 DPI；其餘面板保留 GDI。高對比及渲染失敗時重填背景並
回退單色，失敗 target 有有限重建次數，不逐格無限重試。字形取決於作業系統字型版本。
API 依據為 Microsoft [color fonts](https://learn.microsoft.com/en-us/windows/win32/directwrite/color-fonts)
與 [Direct2D／GDI interoperation](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-and-gdi-interoperation-overview)。

本次 x64／x86 正式 DLL 與三個受影響的原生測試 targets 均建置成功；兩架構循序執行
原先 14 項原生回歸各 **14／14** 通過（x64 6.31 秒、x86 6.00 秒），另各執行帶輸出目錄
的面板測試，驗證實際彩色與單色 fallback 像素。未重跑未修改的 WPF 或其他平台。
測試搜尋原生 menu 時枚舉並限制當前 thread，避免兩架構同時開啟選單時找到另一個程序的 menu。

原生渲染產物在 `Source/Loaders/Windows-TSF/out/emoji-color-visuals/`（x86 在同名 `-x86` 目錄）：
五頁 emoji、暗色 palette、模擬 150% DPI、高對比旗標的 GDI fallback，以及分類反白圖。
原生 PrintWindow 的第一格像素要求超過 100 個高度飽和像素，確認實際多色字形；fallback
另要求可見字形像素並驗證包含 variation selector 的完整文字選取。五頁、多色表情／心形／
動物／食物／交通物件及暗色／150% DPI 已視覺核對，沒有使用外部 emoji 圖片。

自繪只接受本面板的 ODT_BUTTON，並以 SaveDC／RestoreDC 還原字型、文字色及背景模式；
WM_PAINT 亦還原 DC。測試檢查分類／符號／彩色 emoji 的 selected／unselected 狀態後，
caller DC 狀態不變。每架構另反覆 20 次真實原生 popup，重繪三個反白分類後取消，驗證
標籤完整、沒有提早選取且 `GetFocus()==host`。此處沒有重現使用者偶發「反白後文字消失」；
DC 狀態修正及本機重繪通過不能證明該實機症狀已消除，仍需使用者宿主複測。

本機新版 unsigned 安裝包為
`Source/Loaders/Windows-TSF/out/store-package/chichi77-KeyKey-1.3.1-windows-x64-setup-color-emoji-20261005.unsigned.exe`，
91,336,864 bytes，SHA-256 `4fb9ff485c8efa71842c0be1ea3f528e2bc74ce75aeab8cea047892070c880c4`。
解包已核對 15 項 manifest 與 7 項建置／來源檔案，簽章狀態為 NotSigned，產品版號仍為
1.3.1，正式 DB 不變；未安裝或切換使用者輸入法。先前 first-three／symbols 安裝包保留。

## 2026-10-06：TSF 輸入順序、切換與取消收尾

修正前以隔離 COM 宿主確認三個問題：`StartComposition` 回傳 `S_OK` 但 composition 為
空值會繼續解參照；TSF 取消模式提交而未執行 edit session 時留下 pending 狀態；第一個
按鍵等待非同步 session，第二個同步按鍵插隊，全形英文輸入 `1`、`2` 得到 `２１`。

同一服務現在以單一 FIFO 排定按鍵、模式切換、提交與符號插入，只對隊頭要求 edit session。
每項作業持有原 context、世代及唯一身分；未執行 session 的析構會取消自己的作業，
過期或重複回呼不能清除新作業。切換快照在先前按鍵完成後取得，使用原組字的輸出策略，
送出可見中文及未完成注音／字根後才發布模式、引擎與工作列狀態；失敗保留原模式及組字。
待處理期間的一般可輸入字元加入佇列，包括即將切至半形英文的字母；快捷鍵及導覽鍵
維持不攔截。引擎結果及成功寫入的 range／caret／結束階段被保留，送字重試不重新處理
同一引擎按鍵，也不因寫入後的選取失敗重複插字。拒絕建立組字時先不修改引擎。

Windows controlled context 固定其已生效的方法，避免另一服務改全域 primary 後，舊按鍵
被 loader generation 換成新方法。新方法的 context 準備成功才替換舊 context；指定方法
的檔案設定會在建立／啟用前實際載入，不只標記 dirty。外部使用者資料版本變化時，
立即同步好打注音模組，再允許舊 context 停止，避免非 primary 方法寫回已重設的學習快取。
UI／focus／key 查詢使用有效與預計狀態，內部設定刷新保留中英文模式，尚未發布的顯式
選擇不被觀察到的舊設定撤銷。候選定位 session 取消也只清除其相符的待定位世代。

隔離 `KeyKeyTsfOutputBehaviorTest` 使用真實引擎，涵蓋五模式 **20 個有向切換、68 個適用
狀態**：四個中文來源各測空組字、未完成讀音／字根、中文加未完成讀音／字根、候選開啟；
英文來源測空組字。另測句中游標／選字、快速好打→倉頡→英文、排隊按鍵→英文→`a,b`、
全形 `1`→符號 `❤️`→`2`、同步及非同步空 composition 拒絕後重試、提交失敗、取消、
重複／過期回呼、同欄位游標變更、成功插入後 `SetSelection` 失敗重試，以及同世代候選
定位取消後重試。假宿主保留所有排隊 sessions，沒有以單一欄位覆蓋舊 session。

設定生命週期回歸另確認：全域 primary 為倉頡時，controlled 好打 context 在啟用前採用
新許氏配置及空白開候選設定；快取確實曾保存的學習測試先做正控制，再由另一 connection
清除學習資料，退役非 primary 好打 context 後資料仍為空。測試使用隔離 profile／使用者
資料庫，不修改正式共用詞庫或正式使用者設定。

另加入相同檔案時間的設定內容變更回歸：先啟用標準注音設定，再寫入許氏設定並還原原
`file_time`。模組 revision 現在只在具名實際載入後更新，避免 core 依 mtime 跳過讀取時，
Windows wrapper 卻把新內容記作已採用。測試由真實 controlled context 確認許氏讀音、
空白開候選與許氏選字鍵，沒有以 signature 字串相等代替實際引擎行為。
兩架構重新建置後，`KeyKeyTsfOutputCommitBehavior` 各 **1／1** 通過（x64 0.42 秒、
x86 0.44 秒）；verbose 紀錄為 `out/tsf-same-mtime-{x64,x86}-targeted.log`，同時包含
前述 20 個切換／68 個狀態、具名載入及學習重設退役的實際結果。

### Owned popup 空白框

已重現宿主呼叫 `ShowOwnedPopups(owner,FALSE)` 暫時隱藏候選窗時，`IsWindowVisible`
為 false，原 hide 跳過隱藏但清除內容；Windows 之後恢復 owned popups 使空白框重新出現。
只補 `SW_HIDE` 仍不能清除 Windows 的待還原狀態。候選窗與符號表現在辨識邏輯顯示狀態，
在此取消路徑退役待還原 HWND。`KeyKeyPopupLifecycle` 原生測試已在 x64／x86 通過相同
hide／取消／restore 序列，並驗證重開、owner 關閉及正常取消。這只確認上述生命週期原因；
其他白塊與分類 hover 文字消失未證明同因或已修復。

### 候選窗置頂白框追查（2026-10-10）

使用者回報 Codex 與其他程式也可能留下全白候選框，曾長時間置頂遮住其他程式；
新輸入有時可使它消失。本機唯讀檢查找到 Codex 與 Edge 的候選 HWND，兩者載入同一
已安裝 `1.3.2-a873207e4f84` DLL；開始追查時 DLL 雜湊與當時本機 x64 建置相同。
抓取狀態時視窗為隱藏，後續確認邏輯顯示旗標也為 false、候選向量已清空；GDI／USER
物件數低於資源限制，沒有偵測到 Ghost 視窗。使用者之後回報白框消失，所以未取得
白框持續可見當下的完整訊息序列，不能斷言它一定是宿主還原或 DWM 殘影。

原有 x64／x86 原生 popup 探針均通過正常取消、owned popup 暫時隱藏／還原及晚到
`WM_SHOWWINDOW` 的檢查，未重現使用者此次問題。新實作改為候選窗每次取消均銷毀
HWND，移除「普通隱藏仍重用已清空置頂 HWND」的路徑；只保留字型供下次候選使用。
銷毀失敗時仍盡力隱藏並取消置頂，同時保留 HWND 以便後續重試。符號表行為未在本次變更。

新增原生回歸要求普通取消、重複取消與已排入的還原訊息均不保留舊候選 HWND，並驗證
新候選仍可建立視窗、正常顯示、維持字型與焦點。候選視窗本身另記錄 show／hide／paint、
`WM_SHOWWINDOW`、`WM_WINDOWPOSCHANGED` 及 `WM_NCDESTROY`，以 HWND 與物件識別
串起後續實機事件；不記錄候選文字。此處是防禦性生命週期修正，尚未替換已安裝版本或
證明 Codex／Edge 的間歇白框已消失。

使用者另提出開機初期載入較慢時可能較易發生，尚未確認相關性。原生回歸另保留首次
`WM_PAINT` 的待繪區域、不處理訊息就取消，驗證 HWND 已銷毀，下一輪候選仍可重建並
完成繪製。這涵蓋首次繪製延遲時的取消，不等同實際開機／Codex 載入情境驗證。

本次變更已重建 x64／x86 DLL；兩架構各通過 `KeyKeyPopupLifecycle`、
`KeyKeyTsfOutputCommitBehavior` 與 `KeyKeyTsfSystemTrayModes` 三項受影響原生回歸。
本節測試與下節先前完整回歸分開記錄；未將此次三項結果當成重跑完整 27 項。

同日產生未簽署本機測試安裝檔
`chichi77-KeyKey-1.3.2-windows-x64-setup-candidate-fix-20261010.unsigned.exe`。
解開 EXE 後驗證 17 個 manifest 檔案雜湊，並核對八項 DLL／EXE／DB 與建置來源一致；
產品版本為 1.3.2，共用 DB 雜湊不變。此步僅產生與檢驗安裝檔，未執行安裝。

同日提供測試安裝檔後，使用者回報「目前沒有」，表示當下暫未再出現白框；尚未核對
實際安裝版本與宿主載入的 DLL，不作為已修復驗收。使用者強調此問題過去已發生多次，
且上次連符號表也曾發生白框。追查範圍須同時包含候選窗與符號表，保留全白視窗長時間
置頂、遮擋其他程式，以及新輸入有時使其消失等症狀。符號表白框與分類 hover 消字是
分別回報的症狀，不能混為同一問題；目前也未證明符號表與候選窗白框具有相同原因。
後續需觀察開機初期、跨程式切換與兩類 popup 的生命週期，不能因暫未再現就結案。

### Windows 診斷記錄開關（2026-10-10）

依使用者最終要求，設定一般頁僅提供「啟用診斷記錄」一個開關，不提供天數選項；
所有建置（含 GitHub Actions）預設關閉。勾選並套用後固定記錄 3 天，到期自動停止。
`diagnostics.plist` 獨立保存 UTC 起訖時間，關閉設定或重新開機不延長期限，套用其他
設定也不更新期限。宿主至多每秒重讀一次設定，每筆記錄前檢查期限；設定視窗會於
到期時顯示開關關閉，不需設定視窗持續執行才能停止寫入。

TSF Trace、引擎 OutputDebugString、舊模組 logger 與部署記錄均依有效期限控制。
預設／手動關閉／已到期時不建立或追加 log；安裝狀態與錯誤碼仍可顯示。
`%TEMP%\KeyKeyTsf.log` 每檔最多 10 MiB，僅保留一份同容量 `.1` 備份，共最多 20 MiB；
共用同一 Temp 路徑的宿主以具名 mutex 協調，忙碌時跳過記錄，不阻塞打字等待鎖。
`Deployment.log` 每次追加前檢查 1 MiB 上限。一般診斷已停止時不清除舊檔；舊檔不會
繼續變大，重新開啟記錄時套用容量限制。先前的 candidate-fix 測試 EXE 未因此改變。

驗證：x64／x86 各 8 項受影響原生測試通過，包含新診斷開關／期限／容量測試、
候選窗生命週期、TSF output、工作列、注音／數字鍵盤與兩種 Esc 行為。兩架構 WPF
隔離測試均通過單一開關、套用、重開、期限保留、到期關閉與未儲存保護；.NET 設定
往返測試通過，部署回歸 31 項通過。GitHub Actions 增加設定／部署測試入口，未執行
遠端 workflow 或替換實際安裝版本。

另產生新版未簽署測試 EXE
`chichi77-KeyKey-1.3.2-windows-x64-setup-diagnostics-20261010.unsigned.exe`，
大小 92,282,819 bytes，SHA-256 為
`5f6bee0b724e50038626036c7b27050aec446917d053b5fe76d37ff6fceb4b50`。
解開後 17 個 manifest 檔案均通過雜湊驗證，八項 DLL／EXE／DB 與建置來源一致；
套件未附 `diagnostics.plist`，不預先啟用診斷。此新版含前述候選窗修正，產品版本仍為
1.3.2，僅打包與檢驗，未自動安裝。

### 證據與界線

本輪以 MSVC／Ninja 重建兩架構正式 DLL、設定後端及受影響的原生測試。完整原生回歸的
驗證共 **x64 27／27、x86 27／27** 通過，包括 EngineAdvanced 各設定、TableInput、
CandidateKeyStateMachine、TSF output／工作列／候選版面、數字鍵盤及 PopupLifecycle。
最終 r3 建置分兩階段執行：沙箱各通過 25 項（x64 8.51 秒、x86 9.06 秒）；FrontendPreferences
隔離檔案寫入與 Registration 隔離 HKCU 建立被沙箱阻擋，再以一般使用者權限只重跑兩項，
各 **2／2** 通過（x64 0.22 秒、x86 0.24 秒）。沒有把第一次的權限失敗記作通過。
紀錄為 `out/tsf-ordering-20261006-r3-{x64,x86}-tests.log` 及各架構 `-isolated-retry.log`。
新加入的有向切換、觀察同步、具名設定與 learning reset retirement 回歸均包含在上述兩
架構的測試結果。未重跑未變更的 .NET deployment／WPF 或其他平台。

收尾補上設定 revision 查詢的空 policy 防護：runtime 找不到 DB 時不讀取尚未初始化的
policy。兩架構重新連結全部 17 個原生建置 targets 後，以獨立的 `out/missing-db-x64`、
`out/missing-db-x86` 執行 probe；兩目錄都沒有 `KeyKey.db`，兩種方法的設定 signature
均為空，controlled engine 無法建立但未崩潰，退出碼皆為 0。紀錄為
`out/missing-db-{x64,x86}-result.log`；未移動或修改正式 DB。

失焦、欄位移除、宿主取消，以及尚無組字的待處理按鍵期間移動游標會取消未執行按鍵，
不重播到新欄位或新游標；因此不能宣稱任何宿主操作都不漏字。仍存在的舊欄位只盡力結束
組字，銷毀後不能保證寫回。共用模組欄位未做完整設定快照隔離，送字重試不回滾已發生
的候選／學習決策。隔離 COM、原生 popup、真實引擎與 broker 測試是各自的證據層級，
未安裝這一輪輸入法；Firefox、Office、Win+Space 與使用者遇到的間歇顯示問題仍待實機驗收。

### 最終測試安裝包

`out/store-package/chichi77-KeyKey-1.3.1-windows-x64-setup-tsf-ordering-20261006-r3.unsigned.exe`
為本輪審查與回歸完成後的封裝，91,368,931 bytes；SHA-256 為
`c490d072e8a288ca2bb7ff6a7b4bb0bbbd760201307580efbc3a41b613b10705`。
解包核對 15 項 manifest 與 7 項建置／來源檔案，簽章為 NotSigned，產品版號維持 1.3.1。
包內兩種位元數 DLL 均與最後建置一致，共用詞庫 SHA-256 仍為
`8fc3aead36cefd16a77c0a0d4319f7a305fb712b752db09396c8ac2bd4ebbfdb`。
僅完成封裝與解包驗證，未執行安裝；未交付的兩個中間封裝已移除，以免誤裝。

## Windows 1.3.2 版號與最新封裝（2026-10-06）

依使用者要求，僅 Windows 產品升至 1.3.2；CMake、ZIP 打包預設、設定專案與可見 footer
均已同步。Windows workflow 改從 Windows CMake 讀取版號；README 標題明列各平台版本，
且尾端仍為 1.3.1，維持 macOS、iOS、Android、Linux workflow 的既有解析相容性。
實際執行 Windows metadata 版本檢查及 `Validate-Frontend.ps1` 均通過。

x64、x86 正式 DLL、設定與部署程式依序建置成功，記錄為
`out/version-132-{x64,x86}-build.log`。本次只更新版號與相關文件／workflow，
輸入邏輯沿用上輪已驗證版本；未重跑上輪完整原生回歸。
x64 的 .NET DeploymentTransactions、SettingsPreferences、SettingsWpfControls
全部 **3／3** 通過，總計 11.19 秒，記錄為 `out/windows-v132-dotnet-tests.log`。
WPF 使用隔離設定並建構實際控制項，未開啟桌面視窗或改動使用者設定。

最新未簽章安裝檔為
`out/store-package/chichi77-KeyKey-1.3.2-windows-x64-setup-windows-v132-20261006.unsigned.exe`，
91,366,839 bytes；SHA-256 為
`a709753c0697342f8cdb25f7effafbee96da1c1f4d816004991e399fa5dec35b`。
解包驗證 manifest 版本 1.3.2、x64、Signed=false，15 項內容雜湊及 7 項建置／來源比對均通過。
安裝程式的可見 FileVersion／ProductVersion 為 1.3.2；兩架構 TSF DLL、設定及部署 EXE
的 FileVersion 均為 1.3.2.0。設定後端與註冊工具原本未帶版本資源，改以檔案雜湊核對來源。
簽章狀態為 NotSigned，記錄為 `out/windows-v132-package-verification.log`。

四份既有 macOS plist、iOS project、Android Gradle、Linux CMake 與正式 DB 共 8 檔
均與升版前 SHA-256 相同；其他平台產品及共用模型仍為 1.3.1。
正式 DB SHA-256 仍為
`8fc3aead36cefd16a77c0a0d4319f7a305fb712b752db09396c8ac2bd4ebbfdb`。
本輪未安裝或發布；前述 Firefox、Office、Win+Space 與偶發顯示問題的實機驗收界線仍適用。

## 符號表捲動、Emoji 快取與共用大小設定（2026-10-10）

同一分類的項目一次建立，以原生垂直捲軸與滑鼠滾輪瀏覽，移除上一頁／下一頁及頁碼。
18 個分類、1,007 項與原始字串順序維持不變；200 個 Emoji 不再分為五頁。
捲動只移動內容容器，保留項目 HWND；切換分類才更換項目，同分類重開重用控制項及字型。
字型、Emoji、格子及視窗尺寸共用 `CandidateWindowScalePercent`。候選窗與符號表使用同一
縮放計算；固定 125% 及「跟隨 Windows」皆可套用，重新開啟會讀取最新設定，跨螢幕 DPI
變更時重新計算並限制於工作區。

彩色 Emoji 只 rasterize 可見項目，以字串、尺寸、DPI 及前景／背景色快取最多 256 張 DIB；
重繪使用 BitBlt，DPI 或主題改變時清除不適用的快取。高對比／渲染不可用時保留 GDI fallback。
隔離 x64 Release 探針在本機量到舊版重開與重繪 74–82 ms，新版 9.35–11.94 ms。
首次切換加繪製仍約 298 ms：新版可見 60 項，舊版可見 40 項，且仍有系統字型初始化，
不能據此宣稱首次開啟加速。量測程式與紀錄位於 ignored `out/symbol-scroll/`。

x64 CTest 8／8、x86 受影響原生 CTest 6／6 通過；兩架構隔離 WPF 測試通過。
首次 x64 整批執行曾有一次原生分類選單未開啟；獨立執行、兩架構畫面測試及 x64 整批
重跑均通過，未以移除該檢查處理。原生符號表測試以獨立 profile 驗證全分類順序、200 項
完整性、捲到最後一項的插入、滾輪、控制項重用、快取重繪、125%／Windows 縮放、DPI、
宿主焦點、拖曳、分類選單反白及取消／銷毀。生命週期、TSF output、工作列、偏好設定與
診斷測試亦通過。渲染產物位於 `out/symbol-scroll/visuals-{x64,x86}/`；125% 的符號與
彩色 Emoji、末尾項目、顏文字及高對比 fallback 已視覺核對。

本機未簽署測試安裝檔為
`out/store-package/chichi77-KeyKey-1.3.2-windows-x64-setup-symbol-scroll-20261010.unsigned.exe`，
92,281,419 bytes，SHA-256 為
`b58db6baa408826e71e84399459bd9273465b4edfdeb9bdded5f88ab90d2c411`。
解包核對 17 項 manifest 雜湊及八項建置／來源比對通過；版本為 1.3.2、NotSigned，兩架構
TSF DLL 與最新建置一致，共用 DB 仍為正式固定雜湊，未預先啟用診斷。
本輪只建置、渲染及解包驗證，未安裝或發布；使用者遇到的間歇白框仍待新版文字宿主實測。

### 捲軸黑塊與位置不易辨識修正（2026-10-10）

使用者實機截圖回報捲軸上下出現黑色方塊，內容捲動時難以看出滑塊跟著移動。
原生位置數值測試顯示首尾位置仍會改變，故不能只檢查 `nPos` 就判定顯示正確。
改以獨立的 `ScrollBar` 子控制項取代內容視窗的非客戶區捲軸；滑塊範圍、頁面大小、
位置及拖曳通知統一使用 `SB_CTL`。控制項停用 visual style overlay，持續呈現完整滑塊
及箭頭，仍使用 Windows 系統色彩。沒有 Tab stop，且滑鼠啟用與滾輪不切換宿主焦點。

兩架構測試啟用 Common Controls v6 宿主 activation context，確認首尾滑塊幾何及實際像素
都改變、上下箭頭沒有整塊黑色填滿，直接操作原生箭頭與滾輪仍保留輸入欄位焦點，
分頁通知與內容位置同步。原生控制項以提供 DC 的 `WM_PAINT` 輸出測試圖；先初始化
畫布，避免未繪區域造成假通過，再將捲軸圖合成至完整面板圖。首尾圖、125%、Emoji、
顏文字與高對比 fallback 已核對，產物為 `out/symbol-scroll/visuals-scrollfix-{x64,x86}/`。

x64／x86 各 4／4 受影響 CTest 通過，涵蓋符號表、popup 生命週期、TSF 插入及工作列。
未改動桌面游標或使用 SendInput；實際滑鼠拖曳由使用者在新版文字宿主確認。
未完整重現原宿主黑塊的觸發條件，也未把它判定為之前候選窗／符號表置頂白框的同一原因。

最終未簽署測試包為
`out/store-package/chichi77-KeyKey-1.3.2-windows-x64-setup-scrollbar-fix-20261010-r2.unsigned.exe`，
92,279,249 bytes，SHA-256 為
`b39d734ac98488f2d3450961b775ff9f693cbbbefa7c057fffef0217860350dc`。
解包 17 項 manifest、八項建置／來源比對及正式 DB 固定雜湊均通過；版本仍為 1.3.2。
僅產生並驗證安裝檔，未安裝或發布。

### x64／x86 共用資料與白框假設檢查（2026-10-10）

依使用者提出的跨位元數型態不一致假設，檢查 TSF frontend 的 IPC、共用檔案及視窗狀態。
候選窗與符號表為各 TextService 的程序內成員，沒有跨程序共享其物件、候選向量、GDI
資源或原始 C++ 指標的路徑。SharedInputMethod 及 SharedOutputState 經 TSF global
compartment 傳遞 `VARIANT VT_I4` 的方法 ID／1、2 狀態；接收端檢查型態及有效值，
沒有用 `size_t`、原始 VARIANT 記憶體或指標作為跨架構資料格式。診斷共用 UTF-8 文字
log，具名 mutex 只協調寫入；設定使用 XML plist，學習資料使用 SQLite 的文字及數值欄位。

重新建置兩架構共用狀態測試，以獨立 GUID 實測 x64→x86 及 x86→x64：兩方向的四種
輸入法選擇、子程序實際組字與回傳狀態均通過；兩方向簡繁狀態交換亦通過，共四組。
沒有啟用真實 TIP、切換使用者正在使用的輸入法或改動使用者 profile；此結果不能代替
跨 App 視窗焦點與回呼時序的驗證，也不能排除非共用記憶體路徑的記憶體錯誤。

另找到與位元數無關的共用寫入風險：`PVPropertyList::WritePlist` 直接以 `"w"` 開啟目的
檔再寫入，缺少暫存檔替換與跨程序協調；loader／module 初始化及保存會呼叫此路徑。
即使兩邊都是 x64，同時保存也可能讓讀者看到短暫不完整 XML，或由較舊的設定快照覆蓋
較新的欄位。現代設定程式及 SaveSimplifiedOutputPreference 已使用暫存檔替換，但仍需
留意讀改寫間的競爭。這是靜態程式碼發現的風險，尚未重現它造成設定損壞或白框，
本輪未修改五平台共用框架。

白框症狀仍優先追查失焦取消、owned popup 還原、過期回呼及升級後宿主保留舊 DLL；
後續須將白框的 PID／位元數／實際 DLL 路徑與顯示、取消、重繪事件對應，不能僅憑跨
App 切換或兩種架構共用目錄就判定為型態錯誤。未核對本輪所有實際宿主載入的 DLL。

### 多宿主共用資料保護（2026-10-10）

依後續要求加入寫入保護。Windows TSF CMake 的 `KEYKEY_WINDOWS_SHARED_DATA` 才啟用
共用框架內的新路徑；macOS／其他 frontend 保留原路徑，正式模型不變。

- 原生 loader／module plist 與 C# 設定、診斷及設定遷移共用每檔案具名 mutex。
  檔案先完整寫入同目錄暫存檔並 flush，再 replace；讀取使用 share-delete。
  原生保存比較本地與基線，只合併本宿主改動且磁碟尚未改動的欄位；同欄位衝突保留
  磁碟新值，未改動欄位及陣列維持。損壞／不可讀的現有檔案不以預設值覆寫。
  原生鎖等待上限 250 ms，失敗不承認快照已保存；設定 App 上限 5 秒並回報失敗。
  App 的 Apply 仍保存明確提交的設定值，不提供多視窗逐欄位編輯合併 UI。
- Windows plist 解析序列化共用靜態字串緩衝區，並檢查 Expat 解析失敗，避免多執行緒
  混入文字或接受未完成 XML。診斷 session 已啟用時不由另一設定程序延長三天期限。
- SQLite 學習快取只以交易寫入本宿主 pending 項目，不再全表刪除後回存舊快照。
  任一步失敗 rollback 並保留 pending；修改過的快取表維持至多 200 筆。
  清除／匯入與 generation 更新在同一交易；保存前取得 userdb 寫鎖並檢查 generation，
  已過期宿主清除待寫入資料並載入新快取，避免把已清除或匯入的資料覆蓋回舊內容。
- 測試發現 `sqlite3_open16` 在設定先建立使用者 DB 時預設 UTF-16，無法 attach 到正式
  UTF-8 model。新建 DB 在建立資料表前指定 UTF-8；現有資料不直接轉碼或刪除。

兩架構原生 CTest 各 29／29 通過；設定 plist 七組、WPF x64／x86 控制項與 31 項隔離部署
測試通過。另以獨立 profile 實測 x64→x86、x86→x64 的同檔 60 次並行保存及 SQLite
各宿主學習保存，兩方向均保留兩方資料。x64／x86 各與 C# 程序並行寫入亦通過，並
由 C# 持有鎖確認原生保存會等待逾時、不改檔，釋放後可保存，驗證兩種實作的鎖名稱
相同。新增 `KeyKeySharedDataProtectionTest` 涵蓋過期快照／同鍵衝突、保留陣列、損壞
XML 保留、鎖逾時重試、八條解析執行緒、atomic replacement 讀者、busy rollback／重試、
清除／匯入 generation、同鍵新選擇不被舊快取覆蓋、容量及實際 `integrity_check=ok`。
GitHub Actions 加入兩方向與兩組原生／managed 配對；本機通過不代表遠端已執行。

本次未證明共用寫入就是白框原因。升級後舊宿主尚未卸載的 DLL 不會遵守新鎖或
generation，因此需登出再登入讓宿主全數載入新版；仍需文字宿主實測白框與焦點時序。

未簽署測試安裝檔為
`out/store-package/chichi77-KeyKey-1.3.2-windows-x64-setup-shared-data-20261010.unsigned.exe`，
92,277,528 bytes，SHA-256 為
`c27ad4f528f4a694aa6f0fb4109a609f944bb115a9402a2621b0f25624c2cca7`。
解包核對 17 項 manifest、八項建置／來源比對、1.3.2 版本、NotSigned 及正式 DB 固定
雜湊均通過，含兩架構新版 TSF 與先前符號表捲軸修正；未安裝或發布。
