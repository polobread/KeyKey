# Linux 自動化打字與發布驗收計畫

狀態：測試設計，尚無 Linux 測試執行結果。搭配
[開發計畫](LINUX_DEVELOPMENT_PLAN.md)；以下腳本、fixtures 與測試程式待實作。

Linux 首版目標為 1.2.8。功能驗收範圍是 F01–F11、F16；使用者已排除 F12–F15，
不測算式、自訂詞管理、CIN／外掛管理與一點通／獨立通知窗。原 T13 退役，保留其他
測試編號；完整 suite 指 T01–T12、T14–T15。F05 內建關聯詞與分類開關仍須驗證。

**主要環境：Ubuntu Desktop 24.04 LTS + Fcitx 5 + GNOME，x86_64。**
這一組須有最完整的打字、視窗、App、sandbox、安裝與穩定性測試；先完成此組
再擴充其他環境。IBus 在相同 Ubuntu 版本上的結果與 Fcitx 分開計算。

## 1. 什麼才算「真的打出文字」

至少要走過這條路徑：

```text
鍵盤 press/release → 桌面輸入路徑 → IBus / Fcitx 5
  → Linux engine → preedit / candidate / commit
  → GTK / Qt / 瀏覽器的實際文字欄位 → 讀取欄位內容核對
```

不能用呼叫 engine 得到字串、D-Bus 直接 commit、剪貼簿貼上、DOM `.value`／`fill()`、
JavaScript `KeyboardEvent` 或 toolkit `setText()` 取代 E2E。
瀏覽器自動化可讀取結果與做 assertion，但不能直接灌入預期中文字。
QTest／adapter test frontend 的鍵盤合成是否經過 OS IME 不可假設，預設只算整合測試。

測試必須同時檢查：

- 每步按鍵、press/release／修飾鍵、framework active engine 與 client context。
- 組字中文字／注音、候選文字與順序、反白／頁次、顯示／隱藏及焦點。
- 真正 App 文件的精確 Unicode 文字、cursor／selection、commit 次數；
  不能只檢查 engine log 或「畫面看起來有一個字」。
- 停用琦琦、改成英文鍵盤後重送相同鍵序，不應得到同樣中文字。
  負控制若仍成功，表示測試繞過 IME，整條 E2E 無效。

## 2. 五層測試

| 層級 | 驗證內容 | 可用環境 | 不能取代什麼 |
|---|---|---|---|
| L1 engine/data | 狀態機、表格語意、排序、filter、Unicode、設定、資料生成 | 各 distro container／原生 CPU runner，CTest + ASan/UBSan | framework、桌面、安裝 |
| L2 adapter contract | key 處理、commit/preedit、lookup table、properties、reset/focus、雙 context | 獨立 session D-Bus、IBus test client、Fcitx TestFrontend | 真 App 與 OS 鍵盤路徑 |
| L3 installed X11 E2E | 套件安裝後，在 GTK/Qt 編輯器逐鍵組字與選字 | Xvfb + window manager + D-Bus + 框架；XTest/xdotool 送鍵 | native Wayland |
| L4 desktop Wayland E2E | 優先 Ubuntu 24.04 GNOME/Fcitx 5；另測 GNOME/IBus、Plasma/Fcitx；native Wayland／XWayland、popup/focus | hosted runner 內 QEMU 完整 distro guest，優先 KVM | 其他 compositor、實體 GPU／周邊 |
| L5 app/UI/package | 實際應用程式、sandbox、視窗、安裝升級、持久化與版本 | 對應 distro desktop guest；必要項目補實機 | 未測組合的支援保證 |

Fcitx 官方的 [TestFrontend](https://github.com/fcitx/fcitx5/blob/master/testing/testfrontend/testfrontend.cpp)
可供 L2 參考；[IBus engine 原始碼](https://github.com/ibus/ibus/blob/main/src/ibusengine.c)
提供事件／結果契約。兩者都不是已證實的 L4。

## 3. 鍵盤注入、host app 與證據

### X11

使用真實 test host 視窗，在它取得 focus 且 engine 啟用後，以 XTest／xdotool
傳送固定實體鍵序。禁止 `xdotool type 中文`；傳的是注音／字根鍵與選字鍵。
按下與放開的 modifiers 成對，案例結束釋放所有鍵。採輪詢狀態與有界 timeout，
不要依賴固定長 sleep；啟動、焦點或面板未就緒應直接失敗。

### Wayland

P0 首選 QEMU 的 `input-send-event` 或 `send-key`，注入 guest 的虛擬鍵盤，
讓事件經過 guest compositor 與 IME。QMP 管理 socket 只留在 runner 本機，
不暴露網路。[QEMU QMP 文件](https://www.qemu.org/docs/master/interop/qemu-qmp-ref.html)
定義這些 guest 輸入指令；能發出指令不代表實際 IME 已收到，仍須上述正負控制證明。

記錄 `XDG_SESSION_TYPE`、compositor、framework、toolkit backend／plugin、
程式版本與實際啟動參數；確認被測視窗確實用 Wayland，而非偷偷 fallback X11。
native Wayland 與 XWayland 分開報告。`xdotool` 不當成 native Wayland 注入器。
Nested GNOME／KWin 可做較快子集合，完整 guest 為首版 release 優先驗證方式。

### Test hosts

- 建 GTK 3、GTK 4 與 Qt 6 最小原生編輯器：單行、多行、兩欄位、密碼、唯讀、
  selection、caret 移動與視窗縮放。Qt 5 以仍有可安裝套件的目標作相容性案例。
- Host 透過 toolkit 正常 IM context 收字，只讀回 buffer、cursor、selection，
  並記錄收到的 preedit／commit 訊號。診斷介面沒有「設定目標文字」或直接 commit API。
- 外部 App 優先以 AT-SPI／DOM 讀取文字；無法讀取時，在 App 正常「儲存」後比對 UTF-8
  檔案。避免依 OCR 作唯一文字驗證。可讀性不足的案例標 blocked，不降級成截圖成功。
- Engine 詳細事件 log 為測試 build opt-in，正式版預設不記錄輸入內容；只記錄測試字串，
  不收集開發者的真實剪貼簿、檔案或密碼。

### 每個案例的產物

輸出 `result.json`、JUnit XML、逐步 `events.jsonl`、App 實際文字、關鍵狀態截圖；
失敗另加錄影、框架／compositor／guest journal 與 focus tree。
JSON 至少含：test ID、F IDs、git SHA、套件 SHA-256、來源資料 hash、distro、arch、
session、framework、App/version/backend、config、steps、expected、actual、狀態、耗時。
用 `always()` 保存失敗證據，CI artifacts 初始保留 7 天；正式發布保留摘要及 checksum。
完整輸出需可從 workflow summary 找到，不能只留「Test passed」一行。

## 4. Golden fixtures 與具體按鍵案例

固定乾淨使用者設定、US 實體鍵盤、注音 Standard、關聯詞初始關閉、動態頻率清空，
以及字表的 commit hash。要測學習／關聯詞時才另外開啟。

真實資料錨點已在目前 `.cin` 確認：`bpmf-ext.cin` 的 `5j/` 第一項為「中」；
`cj-ext.cin` 與 `simplex-ext.cin` 的 `a` 前兩項為「日／曰」，`l` 有「中」。
這只證明資料內容，**不是現行 macOS 按鍵流程已實測**；P0 要凍結 Space、候選
數字鍵等時機，再產生不含模糊分支的 golden。

建議 scenario schema：`id / method / layout / config / dataHash / steps[]`，
每步含 `press/release`、待達成狀態、精確 preedit/candidates/selection/page/commit
及 host text。預期值來自 macOS baseline 與人工核對的資料，不由被測 Linux 引擎
自動生成。小型合成字表只用於邊界單元測試，正式 E2E 必用實際封裝資料。

| ID | 流程 | 必要 assertion |
|---|---|---|
| T01 | 注音依序 `5` → `j` → `/` → Space → 選「中」 | reading 為 `ㄓ` → `ㄓㄨ` → `ㄓㄨㄥ`；選字後 App 精確為「中」、preedit 清空、只 commit 一次；凍結選字鍵索引 |
| T02 | 五種注音布局各自打同一組已驗證音節 | 不同鍵序得到相同文字；含二／三／四／輕聲、複用鍵布局及漢語拼音不完整輸入 |
| T03 | reading 中 Backspace／Esc；有候選時 Backspace／Esc；空白狀態再按 | 每個階段清除／保留行為符合 golden，沒有殘留注音或誤刪 App 已提交文字 |
| T04 | 倉頡 `a` → Space → 選「日」；改選第二候選「曰」 | 字根 preedit、候選次序與 host 文本精確符合；滿碼／邊打邊找／錯誤處理／頻率選項另有 cases |
| T05 | 簡易 `a` → Space → 選「曰」；輸入另一組真實頭尾碼 | 多候選、選字、分頁與兩碼流程；與倉頡使用各自的表及限制 |
| T06 | 打開大於一頁的真實候選；方向鍵、Space、PageUp/Down、數字、Enter、滑鼠選字 | 前後頁、末頁、邊界不越界，反白與 commit 同字，直橫兩種樣式都覆蓋 |
| T07 | 開啟分類 → 提交字 → Shift 選關聯詞 → 接續；全部關閉後重打 | host 是原字加「後綴」，不重複前字；順序／去重／分類保存與停用正確，fixture 固定具體詞與來源 |
| T08 | 中文／英文、Shift/CapsLock、全半形、數字、標點、繁轉簡、注音修正 | 比對精確 code points；全形案例包含 `Ａｚ０９！～　`；filter 組合順序有測試 |
| T09 | 組字／候選／關聯詞時送 Ctrl/Alt/Super 快捷鍵、repeat、press/release | 未配置快捷鍵交給 App；無重複提交、卡住 modifiers 或意外清空；依 macOS 基線記錄合法差異 |
| T10 | 在兩欄位、兩 App 切 focus；有候選時關閉 client；框架重啟／重新登入 | 不串字、不提交到另一 App；preedit 和 panel 生命週期正確；恢復後仍可輸入 |
| T11 | 移 caret、選一段字後組字／替換、滑鼠移 selection；密碼／唯讀欄位 | 不沿用舊 context、沒有錯位刪字；密碼依 content-purpose 關閉學習／關聯詞／敏感 log；唯讀無修改 |
| T12 | 設定 UI 切直橫、比例、配色、聲音、布局、內建關聯詞分類；開符號面板點選／取消 | 即時套用、縮放後 click hit test 一致；關閉／再開及重登入保存；符號送回原欄位且只一次；不出現 F12–F15 選單或佔位 UI |
| T14 | 套件安裝→三 engine 註冊→實打字→升級→再打字→移除→重裝 | ELF deps、UI／資料存在、設定／學習頻率保留、無重複註冊或殘留自啟；無自動改預設框架 |
| T15 | 密集連打、長候選、延伸漢字／Emoji 資料、locale 切換、兩 context 交錯 | 無 UTF 截斷、死鎖、串字、崩潰與無界記憶體成長；連打結果逐字一致 |

所有未知的精確預期值在 P0 補齊，標 `pending-baseline`，不先寫 always-pass test。
F12–F15 是核定排除，不列 `pending-baseline` 或 skip；原 T13 不納入測試總數。

## 5. 桌面與應用程式矩陣

測試矩陣以機器可讀的 `ci/support-matrix.json` 管理並生成文件摘要。
欄位至少為 distro、arch、desktop、session、framework、app/backend、suite、
required/preview、一般／歷史維護狀態與對應 image digest。release 用同一份矩陣，
避免漏掉某種輸入法或中間 OS 版本；相容窗定義見開發計畫第 2 節。

另加 `priority` 欄位：Ubuntu 24.04 GNOME + Fcitx 5 為 `primary`，其餘既定正式
組合為 `compatibility`。此欄位控制開發順序與平日測試深度，不移除四年相容要求。

### 主要環境完整驗收

Ubuntu 24.04 + Fcitx 5 必須具備以下獨立結果，所有功能均限核定的 F01–F11、F16：

1. GNOME X11、GNOME Wayland + native client、GNOME Wayland + XWayland client
   三條路徑；各自安裝正式待驗 `.deb`，核對 Fcitx process 與 addon，記錄 panel
   provider。GNOME 的 IBus protocol bridge 與本專案 IBus engine 必須明確區分。
2. 全部 14 個有效 T cases，在 GTK3／GTK4／Qt6 hosts 跑完；共通案例覆蓋三種
   輸入法，模式專屬案例依其定義執行（如 T02 的五種配置屬注音），適用性在矩陣
   明列，不列為 skipped。加 Qt5 client 相容測試。五種注音布局、一般／關聯選字、標點與 filters 都要有
   中間狀態、精確 App 文字及負控制，按鍵釋放／長按／焦點／selection 亦包含。
3. Firefox、Chromium、Electron editor、LibreOffice Writer、終端機文字編輯各跑
   適用的完整輸入與焦點流程；瀏覽器補單行、多行、contenteditable，以及 native
   Wayland／XWayland。無對應控制項的案例要在 host 中有證據，不用全列 skip 代替。
4. Snap Firefox、Flatpak GTK editor、Flatpak Qt editor，使用真實 confinement
   與受控 runtime，驗證三種輸入法、preedit／候選、滑鼠選字、符號回送、切焦點。
5. 設定、符號、關於、語系與鍵盤可及性；直橫候選 × 全部比例 × 配色的完整
   組合 sweep，含四邊游標、字型裁切、hit test、虛擬混合 DPI。自訂色用固定
   代表值驗證保存與呈現，避免把無限色值當成可窮舉矩陣。
6. 乾淨安裝、三 engine 加入／切換、重新登入、Fcitx 重啟、升級、移除與重裝，
   設定／學習頻率保留；客戶端意外關閉、密集連打、長時間重複切換與恢復。
7. 每項保留 App 文字、event trace、截圖與失敗錄影；整合問題優先在此環境重現。
   PR 跑完整 typing suite 與所有功能的 UI 操作；每日／發布跑上述所有 App、
   sandbox、視覺組合與壓力項目。主環境結果不得因其他平台成功而被覆蓋。

若 Wayland panel 需額外 Shell 整合，先依開發計畫 P0 決議固定支援的組合及依賴，
再將之列為 required。主要環境有必測未完成時阻擋正式發布。

### 正式 x86_64 桌面列（每列都要測三種輸入法）

| 環境 | 最低 native host | 附加路徑 |
|---|---|---|
| **Ubuntu 24.04 GNOME / Fcitx 5（主要）** | GTK3、GTK4、Qt6、Qt5；X11／native Wayland／XWayland 分開 | 完整驗收清單；所有 App／sandbox／UI／安裝與穩定性 |
| Ubuntu 22.04 GNOME / IBus | GTK3、GTK4、Qt6.2；Wayland 與 X11 分開 | 最低依賴／API 基線、XWayland host |
| Ubuntu 24.04 GNOME / IBus（次要相容） | GTK3、GTK4、Qt6；Wayland 與 X11 分開 | Wayland session 中的 XWayland host |
| Ubuntu 26.04 GNOME / IBus | GTK3、GTK4、Qt6；Wayland | XWayland host |
| Debian 12、13 Plasma / Fcitx 5（各自一列） | GTK3、GTK4、Qt6；Wayland | XWayland host；Plasma 5／6 差異 |
| Debian 12、13 Xfce / Fcitx 5（各自一列） | GTK3、GTK4、Qt6；X11 | 桌面原生安裝與重登入 |
| Fedora 43 GNOME / IBus | GTK3、GTK4、Qt6；Wayland | XWayland host |
| Fedora 44 GNOME / IBus | GTK3、GTK4、Qt6；Wayland | XWayland host |
| Fedora 44 Plasma / Fcitx 5 | GTK3、GTK4、Qt6；Wayland | XWayland host |
| Ubuntu 22.10、23.04、23.10、24.10、25.04、25.10（各自一列） | 該版 GTK3、GTK4、Qt6；GNOME Wayland / IBus | 歷史 guest、XWayland host、安裝後打字 |
| Fedora 36、37、38、39、40、41、42（各自一列） | 該版 GTK3、GTK4、Qt6；GNOME Wayland / IBus | 歷史 guest、XWayland host；36 是最低 Fedora 基線 |

上表範圍共 20 個 distro/version，表格合併顯示不表示合併測試。
每個版本另跑 IBus 與 Fcitx 的 installed X11 slice；以 Xvfb／可用的輕量 WM
驗證兩 adapter 真正被目標套件載入。最舊、最新通過不替代中間 18 版的結果。
歷史列與一般列同樣要求三輸入法和功能測試；差別是來源快照、網路隔離與平日頻率。

若目標 distro 不提供某 toolkit，必須更新矩陣理由與替代 App，不任意下載來源不明的
runtime。不同 toolkit/backend 的 preedit 呈現差異可記錄，但文字結果不放寬。

### 代表性真實 App

- 所有正式桌面列：至少一個發行版原生 GUI editor，以及 Firefox 的單行、多行、
  contenteditable。原生測試 hosts 跑完整 T01–T12、T14–T15；一般 App 最少 T01、T04、T05、
  T06、T07、T08、T10、T11。
- Ubuntu 22.04／26.04 GNOME 與 Fedora 36 GNOME／44 Plasma：加 Chromium、Electron editor、
  LibreOffice Writer、終端機內一般文字編輯；Qt 5 相容性視可安裝性補上。
  瀏覽器／Electron 在 native Wayland 與 XWayland 各跑一次，記錄真實 backend。
- Ubuntu 24.04 GNOME + Fcitx 5 依上節完整驗收，涵蓋所有上述 App、Snap 與
  Flatpak，不能因本節把它省寫在代表列中而少跑。
- Ubuntu 22.04／24.04／26.04 LTS：Snap Firefox（完整 snapd/systemd guest，驗證 confinement 未被關閉）；
  Debian 13 Plasma 與 Fedora 44 GNOME：至少一個 Flatpak GTK editor 和一個 Qt editor。
  固定 app/runtime revision，確認 sandbox 內外 IM module／D-Bus 路徑。
  普通 container 裝套件的測試不能冒充 Snap 桌面相容性。
- 其他 App／交叉框架組合列 compatibility，不以一次成功推論所有 Linux App 都支援。

EOL 列使用當年可執行的 App/runtime 快照和 localhost 測試頁，不硬裝要求新版
glibc 的最新瀏覽器。軟體來源不可得時保留缺口／阻擋相容宣告，不把「只有舊 App」
說成支援所有現在的 App，也不把歷史系統相容說成仍有上游安全更新。

### ARM64 升格

完整版本矩陣的 aarch64 build／L1／package install 至少在同架構 runner/container 執行；
不要把 x86 的結果掛到 ARM64。先標 preview；某個 ARM64 distro 要升格，需在
其同架構 guest／受控裝置重跑對應正式桌面列、兩 adapter contract 與套件升級。
QEMU 跨架構可補 smoke，但需明確標記 emulation，不能當成實體效能驗證。

## 6. 視窗與持久化驗收

- 畫面比例至少 system、75%、100%、200%、225%、350%；所有設定值在 L1 驗證，
  完整視覺 sweep 放 nightly。測候選在四邊、長字、最後一頁、視窗移動、最大化、
  虛擬雙螢幕不同 scaling、符號面板開啟時換 App。
- 預設／自訂色與 light/dark、繁中／簡中／英文，驗證文字未裁切、按鍵角標與頁碼
  可讀、按鈕可及性角色與名稱、Tab 順序。截圖 diff 固定字型與環境並設定合理容差；
  文字提交 assertion 不使用模糊容差。畫面 baseline 更新須人工 review，不能自動批准。
- 特別測 Wayland popup 定位與不搶焦點；自訂 window 無法被 compositor 正確定位時
  應失敗／列明限制，不能只把字型縮小到看得見就算通過。
- 真實多螢幕熱插拔、實體鍵盤、Orca 朗讀等另列人工 smoke。報告區分
  `automated-virtual`／`manual-physical`，未做的標未測，不換算成自動化百分比。
- 學習頻率、設定跨 engine restart／session restart／套件升級保存；
  schema 舊版、資料庫唯讀、檔案損毀、遷移途中失敗均可恢復且不覆寫原檔。

## 7. CI 速度、安全與發布門檻

### 執行分配

- PR／主分支 push：Ubuntu 24.04 + Fcitx 5 設 required job，三條 session 路徑
  各跑完整 T01–T12、T14–T15，包含三輸入法、所有功能 UI 操作與套件生命週期。
  可分片並行；主環境不能只有最小 Wayland 四案例或放進輪替。
- PR：L1 全部，兩 adapter L2；Ubuntu 22.04／26.04、Fedora 36／44、Debian 12
  最舊／最新邊界 build，並在最舊 Ubuntu／Fedora 跑兩 adapter installed X11 slices；
  P0 通過後加舊 GNOME、新 GNOME 與 Plasma 的最小 Wayland T01/T04/T05/T10。
- Nightly：7 個一般版本列完整 scenarios、代表性 Apps、UI sweep、sandbox、
  升級／移除與壓力；13 個歷史版本分組每日輪替，preview 結果分欄。
  Ubuntu 24.04 + Fcitx 5 固定每天跑「主要環境完整驗收」的全部 App／sandbox／
  視覺組合，另列專屬 summary，不參加輪替。
- Weekly／手動完整：20 版本全部重跑，包含歷史列的完整功能／App／安裝測試；
  歷史環境不是永遠只留首次成功結果。PR 更動 compat／最低依賴時加跑受影響歷史列。
- Release：同 SHA／同一批待發布套件重跑 20 版本完整矩陣及 package lifecycle，
  不只依賴 PR quick suite。首版無舊 Linux release 時，以受控舊 schema／套件 fixture
  做遷移測試並註明；第二版起必測真實前版 → 新版。
- P0 每條桌面路徑至少連續三次全新 session 成功並通過負控制，再納入 required。
  失敗重試保留首次結果；不能把 flaky 測試無限重跑到綠。穩定性數據形成後調整
  timeout／切片，先不承諾所有 workflow 幾分鐘內完成。

### 工具與套件檢查

規劃採用 CTest、ASan/UBSan、clang-tidy、ShellCheck、actionlint、lintian、rpmlint；
只掃 Linux 與相關新檔，避免舊 `ExternalLibraries/UnitTest++/UnitTest++` 循環 symlink。
Sanitizers 先在相容 host 跑，其他目標至少執行正常 tests；未跑 sanitizer 要單列。
所有 package 以乾淨環境驗證 architecture、dependency resolution、data hash、
desktop metadata／XML、license、無缺少 `.so`、無 repo/build 絕對路徑洩漏。
加上最低 glibc／GLIBCXX symbol version 與 framework API 檢查，防止新 runner
編出的 binary 意外要求較新系統。container 只能驗證 userspace，舊 kernel／桌面
相容用對應 guest；不要把 host 的新桌面當成舊 distro 桌面。

VM runner 僅使用隔離測試帳號與固定測試字串；不在 PR 開金鑰／簽章／release token。
Guest image 來源、checksum、安裝套件版本與安裝腳本全部可審計；cache 不保存個人
資料或具寫入權限的永久登入環境。Runner 初始化不清除 repo 外的任意資料夾。

### Release 必須全部滿足

- [ ] Ubuntu 24.04 + Fcitx 5 的主要環境完整驗收全綠；三種 session 路徑、三輸入法、
      所有核定功能／App／sandbox／UI／套件生命週期與穩定性皆有證據。
- [ ] 三輸入法、兩 adapter、正式 distro／桌面列皆有結果，必測案例無 skip。
- [ ] 近四年每個版本（含歷史列）有 installed-package 真打字證據，最低依賴未被
      無意提高；一般／EOL 相容標示與實際 OS 安全維護狀態分開。
- [ ] App 精確文字與中間輸入流程通過，且正／負控制都符合預期。
- [ ] 待發布套件本身通過乾淨安裝與打字，不用 build tree 取代 installed artifact。
- [ ] F01–F11、F16 有證據或經使用者接受的具體差異；F12–F15 明列排除，
      沒有加入對應功能入口，也不把排除項計為測試 skip 或未完成。
- [ ] 原生 Wayland／XWayland、ARM64 preview／正式、虛擬／實體結果清楚分開。
- [ ] Workflow summary 可追溯 SHA、套件、環境、逐案例結果、截圖與失敗記錄。
- [ ] 新套件未變更使用者預設框架，升級保留個人資料，授權與 checksum 齊全。

若 hosted desktop gate 失敗，保留已完成的 L1–L3，記錄 blocker 並回報；
不得把 L4 名稱改成 smoke、隱藏 failed job，再把同一版本標為全平台正式支援。
