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
