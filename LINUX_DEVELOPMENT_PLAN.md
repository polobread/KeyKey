# Linux 原生版開發與交接計畫

狀態：開發中。已建立第一段 Linux-only 引擎、Fcitx 5 外掛、container scripts 與
`linux-ci.yml`、五種注音鍵盤配置／Fcitx 原生設定、候選鍵盤導覽、標點／符號候選切片、
`Shift+Space` 全／半形、ASCII 全形對映、繁轉簡單字與注音 Big5-HKSCS 候選 filter 切片、
L3 X11/GTK 3 真實輸入與
Ubuntu 22.04／24.04 開發用 Debian 套件；尚未完成 GNOME／Wayland、注音的
完整功能、完整視窗、IBus 或正式發布套件。

盤點日期：2026-09-12；原始碼基線：`13696ef`；產品版號來源：`README.md` 標題。

Linux 首版目標：**1.2.8**，自此版起納入 Linux 支援；需完成下列實作與驗收後才可
對外宣告已支援。目前四平台版號已同步至 1.2.8；Linux 已有開發中的 staged install
與 `.deb`，但缺少完整功能、桌面矩陣與 release gate，仍不是可正式發布的套件。

接手順序：[AGENTS.md](AGENTS.md) → [BUILDING.md](BUILDING.md) → 本檔 →
[LINUX_TEST_PLAN.md](LINUX_TEST_PLAN.md)。本計畫取代「Linux 只比照行動版注音」的範圍。

## 1. 已確定的產品方向

- Linux 採原生實作，以目前 macOS **範圍內實際可用的功能與視窗**為功能基準。
  2026-09-13 起首版只要求傳統注音；倉頡與簡易不再開發或列為發布條件。
- **主要支援環境為 Ubuntu Desktop 24.04 LTS + Fcitx 5**，以預設 GNOME 桌面
  作為主要驗收環境，X11、native Wayland 與 XWayland 都要完整測試。功能開發、
  問題修正與自動化覆蓋優先落在這一組，完整範圍見測試計畫的「主要環境完整驗收」。
- 使用者已排除 F12–F15：迷你計算機、自訂詞／詞庫管理、通用表格／外掛設定、
  一點通與提示／通知視窗。不開發、不加選單或佔位 UI，也不列為 Linux 驗收缺口。
  F05 內建關聯詞與分類開關、F11 符號面板及 F16 設定／關於仍保留。
- 2026-09-13 使用者另行排除 F03 倉頡、F04 簡易及 Linux 候選學習／動態頻率。
  已完成的垂直切片暫留作相容性回歸，但不再擴充、不列 parity 缺口或發布支援；
  其他平台既有功能不更動。
- 建立新的 Linux-only C++17 引擎、IBus adapter、Fcitx 5 addon，以及原生設定 UI。
  不用 Wine、Electron、WebView 或網頁輸入框包裝成輸入法。
- **不修改、不搬動、不連結既有 KeyKeyEngine 或 OpenVanilla 核心**。
  不把 Linux 支援塞回 macOS／Windows 共用 framework，也不要求四平台一起重構。
- 可唯讀使用既有字表、詞庫、素材及行為規格；資料來源與授權必須保留。
  IBus 與 Fcitx 5 共用「新寫的 Linux 引擎」，並非沿用舊跨平台引擎。
- 所有建置、打包、測試與發布檢查都設計成可由 GitHub Actions 啟動；優先使用
  GitHub-hosted runners，不預設要求維護者一直開著自己的 Linux 電腦。
- 先完成 Ubuntu 家族，再開始 Debian 與 Fedora；後兩者保留在版本矩陣作為明確
  TODO，但不阻擋 Ubuntu 1.2.8 的開發與驗收，也不先建立額外 CI job。
- Ubuntu 相容近四年版本，不限於最新版或上游仍在維護的版本。初始採 2022–2026 相容
  視窗，包含 Ubuntu 22.04 LTS；不能為方便使用新 API 而提高最低 OS 要求。
- 2026-09-13 新增原始碼建置交付要求：支援 `./configure → make → make install`，
  納入 P4／P5 與 Ubuntu 首版驗收。薄層入口與 local source gate 已實作，剩餘矩陣與
  發布測試要求見第 5.1 節。
- 本批版號、規劃與交接提交作為 1.2.8 開發起點；使用者已要求 commit 與 push。
  Linux workflow、目錄與指令入口均是後續實作項目；正式版本 tag 與套件發布在
  完成實作及驗收後另行執行。

## 2. 支援範圍：不能只看發行版名稱

要分開記錄：發行版／版本、CPU、桌面環境、X11／Wayland、輸入法框架、
應用程式 toolkit，以及 Snap／Flatpak 等 sandbox。
Ubuntu Desktop 是發行版的桌面產品；GNOME、KDE Plasma、Xfce 是另外一個維度。

### 近四年相容政策與首版目標

以 2026-09-12 規劃日起算，將「近四年」向前涵蓋到 2022 年的主要發行版本，
刻意保留稍早於精確 48 個月的 Ubuntu 22.04 LTS 與 Fedora 36，不只選 2024 以後。
以下保留完整版本盤點，不代表目前已支援。**目前 active release gate 只有 Ubuntu**：
先完成 Ubuntu 24.04 + Fcitx 5 的全部功能與桌面驗收，以 Ubuntu 22.04 檢查最低 API，
再完成其他 Ubuntu 版本。Debian／Fedora 是下一階段 TODO；在重新升格為 active 前
不納入 1.2.8 Ubuntu 發布阻擋條件。中途未達 active 矩陣的產物只能標成 preview。

| 階段 | 發行版家族 | 一般維護／LTS 相容列 | 歷史相容列（含 EOL） | 套件 |
|---|---|---|---|---|
| Active：先完成 | Ubuntu | 22.04、24.04、26.04 LTS | 22.10、23.04、23.10、24.10、25.04、25.10 | 每版獨立 `.deb` |
| Future TODO | Debian | 12、13 | 此時間窗沒有其他新的 major；11 初版為 2021，不列首版必要項 | 每版獨立 `.deb` |
| Future TODO | Fedora | 43、44 | 36、37、38、39、40、41、42 | 每版獨立 `.rpm` |

盤點共 **20 個 distro/version 目標**，其中目前 active 為 9 個 Ubuntu 版本，另有
11 個 Debian／Fedora future TODO。這是分期順序，不是宣告後兩者已支援。Ubuntu
非 LTS 也不直接漏掉；一般／歷史是 OS 維護狀態，不是琦琦功能等級，active 的
歷史列也必須安裝後真正打字，不能只有編譯成功。

- Ubuntu 24.04 的主要路徑是 GNOME + Fcitx 5，X11／native Wayland／XWayland
  皆屬必測；同版 IBus 保留為次要相容路徑。其他 Ubuntu 版本以 GNOME Wayland +
  IBus 為既定相容路徑；22.04 加 GNOME X11，其他舊版可用的 X11 路徑寫入矩陣。
  Debian 12／13 與 Fedora 36–44 的桌面／adapter 組合保留於 future TODO，待 Ubuntu
  release gate 完成後再凍結與實作，不消耗目前的 PR runner 額度。
- 第一階段正式桌面保證為 `x86_64`。完整版本矩陣同時建立 `aarch64` build／unit／
  package smoke jobs，但 ARM64 在完成同架構桌面打字驗證前標為 preview，
  不把交叉編譯成功當成正式支援。見測試計畫的 ARM64 升格條件。
- 每個發行版都建置兩個 adapter；正式桌面保證只涵蓋明列組合。
  **Ubuntu 24.04 GNOME + Fcitx 5 是主要正式目標**；其他未列的 GNOME + Fcitx 5、
  KDE + IBus 組合另列相容性測試，不暗示全部排列都測過。
- Arch Linux 提供 `PKGBUILD` 與 rolling CI 作為次級目標；固定每次測試的套件版本，
  不承諾永久相容某個舊 binary。Linux Mint、其他 Ubuntu 衍生版、openSUSE、
  wlroots 桌面待新增明確矩陣後再宣告支援。WSL 不是一般 Linux 桌面的替代驗證。
- 每次發布重新計算滾動 48 個月範圍，LTS 邊界可以向前延伸；新版本先驗證再加入，
  移除舊目標需列出日期、原因與遷移方式。**不能只因上游 EOL 就刪除仍在相容窗內
  的測試**，也不能只測最舊與最新，就宣稱中間版本都相容。
- Point release 以該系列受控的最新更新快照為驗證基準，記錄套件版本；不承諾每個
  未更新的 ISO 初版都測過。舊 kernel／driver 與套件更新程度仍須明列。

「相容舊版」不表示提供該 OS 的安全維護。EOL guest 使用官方 archive／可追溯
snapshot、checksum 與來源驗證，建置後限制網路，只測本機文件與 localhost 頁面，
不放 secrets、不登入帳號、不用舊瀏覽器瀏覽任意網站；發布說明提醒升級 OS。
找不到可驗證的 archive 或依賴時列 blocked，不能下載不明 binary 或跳過後標成功。

版本選擇依盤點日的 [Ubuntu 發行清單](https://wiki.ubuntu.com/Releases)、
[Debian 發行資訊](https://www.debian.org/releases/) 與
[Fedora 發行套件](https://packages.fedoraproject.org/pkgs/fedora-release/fedora-release/index.html)。
舊 Ubuntu 版本可核對 [官方 archive](https://old-releases.ubuntu.com/releases/)，
Fedora 36 的 2022 基線可核對 [官方 ChangeSet](https://fedoraproject.org/wiki/Releases/36/ChangeSet)。
實作啟動時重查各版 archive 可取得性，記錄變動，不直接使用浮動 `latest`
決定產品支援範圍。

### Binary 共用原則

| 產物 | 可否共用 |
|---|---|
| Linux 引擎原始碼與 UTF-8 資料來源 | 可供 Linux 兩個 adapter 與所有 CPU 建置使用 |
| 同版本／架構的 Linux 引擎內部靜態庫 | 可在同一 build 連入兩個 adapter，不另承諾公開 ABI |
| IBus executable 與 Fcitx 5 `.so` | 不同載入方式，不能互換 |
| x86_64 與 aarch64 ELF binary | 不能共用；各自建置與執行測試 |
| Ubuntu／Debian／Fedora binary | 不保證共用；glibc、libstdc++、Qt、框架 ABI／依賴需各自驗證 |
| X11 與 Wayland | 同一目標套件通常可共用，由框架整合；但兩條輸入路徑都要測 |
| macOS／Windows binary | 不能用於 Linux；同樣是 Unix 系統也不等於相同 GUI API 或 ABI |

架構無關資料可打成 Debian `all`／RPM `noarch`；若產生索引，格式必須明確定義
版本、byte order 與校驗，不能把 C++ 記憶體結構直接 dump 成跨平台資料庫。

## 3. macOS 功能對照：實際入口優先

下表是原始碼盤點，不是 macOS 實機驗收紀錄。接手先對當前 macOS build 操作錄影，
逐項記錄觸發按鍵、設定預設值、中間狀態與最終文字，形成 `docs/parity.md`。
範圍內每列須有「來源／macOS 操作證據／Linux 對應／測試 ID／差異／狀態」。
必備範圍為 F01–F02、F05–F11、F16，共 10 項。新增發現先記錄
是否屬於這些項目，不自動擴充到已排除功能。本檔的「完整 parity」均指此核定範圍。

| ID | 功能與視窗 | 已確認的原始碼入口 | Linux 交付要求 |
|---|---|---|---|
| F01 | 傳統注音 | `OSX-IMK/CVApplicationController.mm`、`OVIMMandarin` | 單音節 reading、聲調、選字、刪除、取消、連續輸入、Unicode／BIG-5 篩選設定；排序與提交時機對照 macOS |
| F02 | 五種注音配置 | `OSX/TakaoPhonetic.m`、`TakaoKeyboardLayoutPopUpButton.m` | 標準（Standard）、倚天（ETen）、漢語拼音、倚天26、許氏（Hsu）全部實作；含歧義消解與換配置 |
| F03 | 倉頡 | `OSX/TakaoCangjie.m`、`OVIMGeneric`、`cj-ext.cin` | **已排除**；既有 Linux 垂直切片只留相容性回歸，不再擴充或宣告支援 |
| F04 | 簡易（Simplex） | `OSX/TakaoSimplex.m`、`OVIMGeneric`、`simplex-ext.cin` | **已排除**；既有 Linux 垂直切片只留相容性回歸，不再擴充或宣告支援 |
| F05 | 關聯詞與分類詞庫 | `OVIMMandarin/OVAFAssociatedPhrase.cpp`、`OSX/TakaoPhraseCollections.m` | 提交後顯示後綴、Shift 選詞、接續、去重、來源順序、分類開關及全部關閉；實際作用的輸入模式依 macOS 驗證 |
| F06 | 直／橫候選窗 | `OSX-IMK/CVVerticalCandidateController.mm`、`CVHorizontalCandidateController.mm` | 選字鍵角標、方向鍵反白、Enter、滑鼠選字、翻頁、空列表、焦點保留、關聯詞樣式 |
| F07 | 比例與配色 | `OSX/TakaoGlobal.m`、候選 controller | 跟隨顯示器及 75/90/100/125/150/175/200/225/250/300/350%；預設及紫／綠／黃／紅／自訂色，對照實際 UI |
| F08 | 一般設定與切換 | `OSX/TakaoGlobal.m`、`OSX-IMK/OpenVanillaController.mm` | 模組顯示、Ctrl+反斜線切換、鍵盤配置、提示聲、熱鍵、即時套用與重新登入後保存；保留至少一個輸入法 |
| F09 | 全／半形與繁轉簡 | `OVOFFullWidthCharacter`、`OVOFHanConvert`、macOS menu | 相同輸出範圍及 filter 順序；字詞映射需對照，不能換一套轉換器就宣稱完全一致 |
| F10 | 注音修正與標點 | `OVAFBopomofoCorrection`、注音標點 `.cin` | 修正開關、全半形標點、組合鍵標點與英文混輸，不能吞掉未配置的應用程式快捷鍵 |
| F11 | 符號／顏文字／常用文字面板 | `OSX-IMK/CVSymbolController.mm`、`CVButtonViewController.mm`、`CVSmileyViewController.mm` | 使用已隨產品提供的分類資料；開關、切頁、點選後送回原輸入欄位，含焦點競態與取消 |
| F16 | 設定／關於／語系 | `OSX/TakaoPreference_Toolbar.m`、`OSX-IMK/CVAboutController.mm` | 原生設定視窗、版本、授權及必要出處；繁中／簡中／英文、鍵盤操作與可及性 |

已排除項目保留原 ID，避免舊交接編號混淆：

- F03 倉頡、F04 簡易：不再開發完整引擎、設定、filter 或桌面驗收；既有切片不視為
  1.2.8 支援承諾，是否從安裝產物移除須另有明確產品決定。
- F12 迷你計算機：不實作算式引擎、互動模式或其 Ctrl+9 入口。
- F13 自訂詞／詞庫管理：不實作使用者詞編輯、匯入、匯出或管理視窗；
  不排除 F05 的內建關聯詞資料與分類開關。候選學習另依 2026-09-13 決定排除。
- F14 通用表格與外掛設定：不提供使用者 CIN 安裝／管理、動態外掛與其設定；
  注音仍需解析產品內建 `.cin`，不能因此刪掉內部字表引擎。
- F15 一點通、提示／通知視窗：不實作一點通服務、獨立提示窗或通知視窗。
  輸入必要的 preedit／候選窗屬 F01／F06，設定欄位的基本錯誤提示仍在原視窗內呈現。

以上是使用者核定的排除，不需做 macOS 行為錄影或建立對等 Linux 實作。
不得因為原始碼存在而重新加入，也不刪除四個既有平台中的任何相關功能。

路徑縮寫：`OSX-IMK/` 在 `Source/Loaders/`；`OSX/` 在
`Source/PreferenceApplications/`；模組在 `Source/ModulePackages/`；字表在
`Source/DataTables/`。P0 須把簡寫補成可點選的完整來源連結與當時 commit。

注音配置有隱藏入口：macOS `TakaoKeyboardLayoutPopUpButton.m` 在按住
Command+Shift 展開選單時才顯示完整五種配置。Linux 應明列五種配置，不能因預設
選單只看到三種而漏做；也不需複製 macOS 設定顯示的既有缺陷。

需要明確區分的 legacy 項目：

- SmartMandarin 雖有程式碼，macOS `inputMethodsArray` 明確排除，所需語料未隨
  開源版提供。首版不虛構智慧整句注音支援，這不等於刪除現行可用功能。
- SC2TC 不能只憑原始碼列為現有功能；macOS menu 跳過此項，F09 的繁轉簡與
  全半形仍需驗證。涉及已排除的外掛、搜尋或一點通服務不再列為待移植功能。
- 更新採 Linux 套件升級流程，不移植舊 updater，不復活失效服務，不新增隱性
  網路請求或輸入內容上傳。其餘範圍內的 OS 差異需記錄對等操作與影響。

## 4. 原生架構與可修改邊界

建議新增以下獨立目錄；使用 CMake + CTest，開發 preset 採 Ninja；另提供第 5.1 節的
`configure`／GNU Make 入口，沿用同一組 CMake targets。Qt 6 Widgets 提供原生工具視窗。
Qt 只放在 UI 層，引擎不能依賴顯示伺服器、D-Bus 或 Qt widget。

最低依賴從最舊目標決定：例如 Ubuntu 22.04 的
[Qt 6.2.4 套件](https://packages.ubuntu.com/jammy-updates/libqt6core6) 要能編譯設定 UI。
P0 列出每個目標的 compiler、CMake、glibc／GLIBCXX、IBus、Fcitx、Qt、GTK 與
Wayland protocol 版本，形成最低 API 清單；不得默用 Qt 6.7+／新版 framework API。
版本差異放在 Linux 私有 adapter／compat 層，以編譯能力探測與 contract tests
隔離；舊版缺少 protocol 時提出已驗證的等價路徑與限制，不要求使用者升級 OS
或修改既有四平台引擎才可安裝。

```text
Source/Loaders/Linux-IME/
  CMakeLists.txt / CMakePresets.json / README.md / LICENSE.txt
  engine/                 Linux 專用 reading、表格引擎、候選及 filter
  data/                   資料 manifest、來源校驗與 Linux 自有索引工具
  adapters/ibus/          IBusEngine、component XML、注音 engine metadata
  adapters/fcitx5/        InputMethodEngine addon、三個 input method metadata
  ui/                     一般／輸入法／內建關聯詞設定、符號與關於視窗
  config/                 schema、預設值、遷移及 XDG 儲存
  tests/                  unit、adapter、GUI host、golden、typing scenarios
  packaging/debian/       debhelper 規則、split package manifest
  packaging/rpm/          spec
  packaging/arch/         PKGBUILD（次級）
  ci/                     目標環境、VM／session 啟動、打包／測試腳本
  docs/                   parity、支援矩陣、操作說明、已知差異
```

引擎介面契約：

- `processKey(event, context)` 輸入 normalized key／實體鍵位／modifiers／press-release，
  回傳 handled、preedit 與 cursor／attributes、候選 page／selection、commit、UI actions。
  非同步 UI 動作與文字提交分離；每個 input context 各自持有狀態。
- 定義 focus-in/out、reset、mode change、client destruction、surrounding-text changed
  的處理；標註 byte／Unicode scalar／UTF-16 的座標單位，禁止混用。
- Adapter 只翻譯框架事件與結果。核心選字／filter 順序不可各寫一份；兩者共用同一
  contract test。不能讓主程式顯示成功、候選點選卻沒有 commit 到 client。
- 框架處理與 OS 整合有關的中英切換；Linux 熱鍵可設定，先檢查 GNOME／KDE 衝突，
  不直接把所有 macOS Command 換成 Ctrl 或奪取 Super。保留 macOS 操作意圖與文件。
- 設定存 `$XDG_CONFIG_HOME/chichi77-keykey`，可重建索引存
  `$XDG_CACHE_HOME/chichi77-keykey`；未設變數時依 XDG 預設值。atomic write、
  schema version、損毀備援與升級備份必測。Linux 不建立候選學習資料。
- 候選窗優先使用框架支援的 panel；設定、符號與關於視窗用 Qt 原生實作。
  所有跨程序請求使用 session bus，限定同一使用者與仍有效的 client context；
  使用者換焦點後不可把符號插入另一個 App。

### Wayland 視窗是先驗證的設計風險

GNOME 的 IBus 候選面板由 Shell 呈現，engine 不一定能自行指定色彩、比例與排列；
Fcitx 的 panel／theme 也受 compositor 路徑限制。不能承諾單一 Qt 浮窗在所有 Wayland
桌面都能自由定位。[Fcitx 官方 Wayland 說明](https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland/en)
也區分 GNOME、KWin、toolkit 與 popup 路徑，部分瀏覽器說明有過時警告。

P0 必須驗證 F06／F07／F11：跟隨游標、四邊避讓、不搶焦點、滑鼠 commit、
縮放配色，先在 Ubuntu 24.04 GNOME + Fcitx 5 完成，再擴充其他路徑。
確認實際載入 `fcitx5-chichi77-keykey` addon；GNOME 整合可能使用 IBus protocol，
但不得把載入另一個 IBus engine 的結果當成 Fcitx addon 通過。記錄套件、process、
addon ID、client backend 與 panel provider，驗證登入後啟動、停用及重啟流程。
若需 Shell extension／Kimpanel，P0 記錄必要性、版本與相容範圍，再依本節的 UI
整合決議納入；不能把只在另一個桌面可用的 popup 當成 Ubuntu 主環境驗收。
若 GNOME 達不到 macOS 外觀功能，提出「受維護的 Shell 整合／
經驗證的替代呈現」與成本，經確認後才實作額外整合或接受差異。
不得默默用系統預設樣式取代需求，再宣稱完整 parity；也不能以 XWayland fallback
假冒原生 Wayland。這是可以先寫可用 engine、但不能先承諾完整 UI 的關卡。

### 參考優先序與禁止範圍

1. macOS 現行 loader、設定 UI、模組與真實操作：F01–F02、F05–F11、F16
   行為／預設值的權威基準。
2. Android Java 原生 `BopomofoEngine`、`BopomofoReading`、`CinDictionary`、
   `AssociatedPhraseDictionary`：狀態機與直接讀資料的參考。
3. iOS Swift `KeyKeyEngine/Sources/KeyKeyEngine`：原生引擎、候選、Unicode、
   實體鍵盤與測試參考；不將 Swift package 改成 Linux 共用核心。
4. Windows TSF：桌面生命週期、按鍵放行、選字窗／設定參考；不修改 Windows 引擎。

禁止修改：`Source/Frameworks/`、既有 `Source/ModulePackages/`、四平台 loader、
現有字表／詞庫內容、既有 cooker、四平台 workflow。若發現資料錯誤，另列 issue／
交接，不借 Linux 工作順便改動。可新增 Linux 目錄、Linux workflow，並更新必要的
根目錄建置／授權／支援說明。CI 檢查 Linux 目標無舊核心 include/link dependency。

例外僅限使用者明確要求的共用版號更新：1.2.8 的既有四平台 version metadata
依 AGENTS 同步，不包含任何舊引擎、UI 功能、資料或 workflow 行為變更。

### 資料與授權

- 必要唯讀來源至少涵蓋 `bpmf-ext.cin`、`bpmf-punctuations.cin`、
  `bopomofo-correction.cin`、
  `DataSource/McBopomofo/phrase.occ`、公開分類詞庫及分類顯示名稱。
  繁簡映射、符號／常用文字表也要列入來源 manifest；不建立使用者詞匯入格式。
  既有凍結切片仍會讀 `cj-ext.cin`／`simplex-ext.cin`，直到另有明確移除決定；
  這不構成繼續開發或發布支援要求。
- 新寫 Linux 資料解析／索引工具，不直接要求舊 macOS cooker 在 Linux 執行：
  它依賴 Formosa Ruby extension。可採 C++17 建置時生成的自有版本化 SQLite 索引，
  runtime 使用系統 SQLite；候選排序須有明確序號欄，不能依索引自然順序。
- 保存 `.cin` keyname／chardef／選字鍵／結束鍵等實際語意；檢查 CRLF、BOM、
  UTF-8、合法 `%` 字元列、重複項目、多字值、延伸漢字及不完整檔案。
- 對照 macOS cooker 的資料正規化、頻率門檻、人名 exclusion、去重與來源順序；
  Android 與 iOS 的近似實作不能自動當成 macOS 結果。生成 manifest 含來源 SHA-256、
  schema／工具版本／筆數，生成資料不提交進版控。
- 每種資料的授權隨套件安裝。全新 Linux 原創碼沿用專案目錄級授權方式，實作時
  更新 `LICENSING.md`；複製的舊碼／第三方資料仍保留原條款，不因新目錄而重新授權。

## 5. 套件與安裝方式

Source package 統一 `chichi77-keykey`；binary packages 採小寫、連字號命名：

| 套件 | 用途與依賴 |
|---|---|
| `chichi77-keykey-data` | 架構無關字表／索引及資料授權；兩 adapter 共用 |
| `ibus-chichi77-keykey` | IBus engine；依賴相容的 data 與發行版 IBus runtime |
| `fcitx5-chichi77-keykey` | Fcitx 5 addon；依賴相容的 data 與發行版 Fcitx runtime |
| `chichi77-keykey-settings` | Qt 6 設定（含內建關聯詞分類開關）、符號／關於視窗；兩 adapter 共用 |

完整安裝應包含 settings，避免安裝後面板按鈕失效；兩 adapter 可以同時安裝，
但一個 session 只選一套框架，不同時搶占輸入服務。套件不得自行切換使用者預設輸入法，
也不得全域覆寫 `GTK_IM_MODULE`／`QT_IM_MODULE` 等設定。

以 Linux 首版目標 `1.2.8` 為命名範例（尚未建置或發布）：

```text
fcitx5-chichi77-keykey_1.2.8-1+ubuntu24.04_amd64.deb
ibus-chichi77-keykey_1.2.8-1+ubuntu24.04_amd64.deb
ibus-chichi77-keykey_1.2.8-1+ubuntu22.04_amd64.deb
fcitx5-chichi77-keykey_1.2.8-1+ubuntu26.04_arm64.deb
chichi77-keykey-data_1.2.8-1+deb13_all.deb
ibus-chichi77-keykey-1.2.8-1.fc44.x86_64.rpm
ibus-chichi77-keykey-1.2.8-1.fc36.x86_64.rpm
fcitx5-chichi77-keykey-1.2.8-1.fc43.aarch64.rpm
chichi77-keykey-data-1.2.8-1.fc44.noarch.rpm
chichi77-keykey-1.2.8.tar.xz
```

- Debian 使用 debhelper／`dpkg-buildpackage`，Fedora 使用 spec／`rpmbuild`；
  依套件工具自動推導 ELF runtime dependencies，補上必要版本約束。
  [Debian control policy](https://www.debian.org/doc/debian-policy/ch-controlfields.html)
  定義套件名、版本、架構與依賴欄位；不能只把任意 zip 改副檔名。
- Fcitx addon 路徑由 framework CMake helpers／GNUInstallDirs 決定，不寫死
  `/usr/lib`；IBus XML 與 engine executable、desktop file、icon、AppStream metadata
  安裝到發行版標準位置並驗證。正式輸入法 ID 要與設定 migration 一起固定。
- 每個發行版／CPU 都在對應目標環境建置；不能從 Ubuntu build 複製 ELF 到 RPM。
  提供可從乾淨 source tarball 重建的資料及相對路徑，不依賴 repo 外的本機檔案。
- Release 直接提供原生套件、source tarball、SHA-256、依賴／資料 manifest 與授權。
  Arch recipe、Debian source package 與 source RPM 可隨相應工作完成一併提供。
- 首版不把 IME 本體包成 AppImage／Snap／Flatpak 來替代系統框架安裝；它們不是
  任意主機上可通用的 engine 安裝方案。**Snap／Flatpak 應用程式內能打字**則必須測。
- 安裝、升級、移除、重裝都測；移除程式保留設定與其他個人資料，刪個人資料需明確操作。
  APT／DNF repository、AUR／發行版官方收錄與簽章金鑰申請是另案，不自動對外發布。

### 5.1 原始碼編譯安裝：configure 與 make（基本入口已實作）

支援從乾淨 checkout 或發布的 source tarball，以傳統指令自行編譯及安裝。
`configure` 入口位於 `Source/Loaders/Linux-IME/`；tarball 保留必要的 monorepo
相對結構。下列介面已可執行：

```sh
cd Source/Loaders/Linux-IME
./configure --prefix=/usr
make -j2
make check
make DESTDIR="$PWD/out/source-stage" install
# 實際安裝到系統時，改用 sudo make install；解除安裝用 sudo make uninstall。
```

- 採薄層 `configure` 入口，以 CMake 的 `Unix Makefiles` generator 與同一組
  build／install 規則提供 GNU Make 介面；不另維護一套引擎或安裝清單。
  支援一般 source-directory 呼叫與獨立 build directory 的 `path/to/configure`；
  與現有 Ninja build cache 隔離，產生的 Makefile／cache 不提交 Git。
- 明列 CMake 3.22 以上、GNU Make、C++17 compiler、shell、pkg-config 及所選
  adapter／UI 的開發相依套件；此方式不要求 Ninja、Docker 或使用者自行執行
  Autoconf／Automake。提供 `--help`、`--prefix`、`--libdir`、`--datadir`，尊重
  `CXX`／`CPPFLAGS`／`CXXFLAGS`／`LDFLAGS`；相依缺失與未知參數在 configure 階段
  明確報錯。明確要求的 adapter 不得因缺少依賴而靜默略過。
- 支援 `make`、`make -jN`、`make check`（執行 CTest）、`make install`、
  `make uninstall`、`make clean`、`make distclean`。configure、build、check 與
  `DESTDIR` staging 均可由一般使用者執行；只有寫入受保護的系統安裝目錄才需提升權限。
  `clean` 保留配置供重建；`distclean` 只移除此入口產生的配置與建置產物。
- 預設 prefix 為 `/usr/local`，提供 `--prefix=/usr` 的發行版系統安裝範例。
  Fcitx addon／metadata、IBus component／executable、資料、UI 與授權須共同遵守
  安裝選項及架構目錄。configure 摘要列出實際目的地與框架搜尋設定；若自訂 prefix
  不在框架搜尋範圍，文件須給出已驗證的啟用方式，不能只因檔案複製成功就算可用。
  `DESTDIR` 僅作 staging 根目錄，不得寫入執行期資料路徑或 metadata。
- source tarball 必須包含 executable `configure`、CMake 規則、必要測試／腳本、
  全部唯讀字表／詞庫、Linux 資料及授權；安裝開發相依套件後可在無 `.git`、無
  原 checkout／build cache 且停用網路的目錄完成 configure／build／check／staging。
- 記錄安裝 manifest；解除安裝只處理此次安裝的檔案，保留使用者設定及
  其他程式的檔案。文件說明與 `.deb` 的衝突偵測及切換流程，避免互相覆寫；從
  原始碼安裝不自動切換預設輸入法。
- 首先在 Ubuntu 22.04／24.04 驗證，P4 擴至全部 active Ubuntu 版本；ARM64
  保持既有 preview 規則。P5 從同 SHA 的待發布 tarball 重建、安裝及實際打字，
  對應測試計畫 T14-SOURCE 子案例；完成後同步 BUILDING 與 Linux README 的正式指令。

2026-09-13 已完成 thin configure wrapper、source-directory／out-of-source Makefile、
`check`、manifest-based `uninstall`、`clean`／`distclean`、prefix／libdir／datadir、
環境編譯旗標、source tarball 產生與 Ubuntu 22.04／24.04 CI gate。Ubuntu 24.04
local amd64 container 已通過兩種 build、2/2 CTest、DESTDIR、含空白的自訂路徑、
重新 configure、卸載保留 sentinel、同一 commit 的 2.0 MB source tarball 在無 `.git`
與無 cache 的解壓目錄重建，以及預設 `/usr/local` 真安裝、設定明示 session 搜尋路徑
後的 Fcitx 5 → GTK 3 X11 注音逐鍵輸入與 manifest 卸載。Ubuntu 22.04 與 24.04 hosted
CI 仍待執行；`/usr`／
任意自訂 prefix 的實際打字、升級／重裝及其餘 active Ubuntu 尚未完成，所以
T14-SOURCE 與 P4／P5 不標成全部通過。

## 6. GitHub Actions 設計

結論：build、package、unit、adapter、X11 真實輸入可安排在 hosted runners；
GNOME／Plasma Wayland 以 hosted runner 內的完整 VM 為優先方案，須先實證穩定性。
Actions 可以編排全流程，不等於任意桌面／硬體都已被雲端驗證。

GitHub 提供版本化的 Linux x64／ARM64 runner labels，但不把 `ubuntu-latest`
當產品版本。以 `ubuntu-24.04`／`ubuntu-24.04-arm` 為初始 host；目標 distro
由 container／guest image 決定。26.04 runner 在盤點日仍列 preview，不拿它作
唯一 release host。資源、計費與可用性以
[GitHub runner 文件](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
為準；不要預先承諾固定耗時或零費用。

| 規劃檔案 | 觸發 | Jobs 與通過條件 |
|---|---|---|
| `.github/workflows/linux-ci.yml` | PR、主分支 push、手動 | 格式／靜態檢查、unit + sanitizers、兩 adapter contract；Ubuntu 24.04 + Fcitx 5 的三種 session 路徑跑完整 typing suite／UI 操作／安裝測試，其他目標跑回歸子集合 |
| `.github/workflows/linux-desktop-tests.yml` | 僅手動 `workflow_dispatch`（實作後才啟用） | 預設跑 Ubuntu 24.04 + Fcitx 5 的所有 App／sandbox／UI 組合與壓力；以手動輸入選擇完整 Ubuntu 版本矩陣或指定歷史版本，不設定每日／每週排程 |
| `.github/workflows/package-linux.yml` | `v*` tag、手動（實作後才啟用） | 版號檢查 → 9 個 Ubuntu 版本 × 兩 CPU 建置／打包 → 安裝測試 → 同 SHA active x86_64 桌面 release gate → manifest/checksum → publish；ARM64 另列 preview。Debian／Fedora 待 P6 再擴充 |

工作流約束：

1. 將可重用 build／test 邏輯放在 Linux `ci/` 腳本或 reusable workflow，YAML
   不複製三份測試；清楚提供本機可跑的同一入口。
2. PR 不用 secrets；預設 `contents: read`，只有受保護的 publish job 可寫 release。
   不以 `pull_request_target` 執行外來程式碼；第三方 actions pin 完整 commit SHA。
3. PR 用 concurrency 取消舊 run；release 不取消。矩陣收集全部結果，不因第一個
   失敗就遺失其他平台報告；每個 job 有 timeout 與清理程序。
4. 固定 distro image digest／guest checksum、資料 hash、toolkit 與套件版本；更新
   環境另開變更。cache key 包含 distro、arch、compiler、資料與 schema，不能跨 ABI 混用。
   舊 distro 跑在現行 runner 內的 container／guest，不依賴 GitHub 繼續提供舊
   `runs-on` label；VM 才能驗證舊 guest kernel 與桌面，container 共用 host kernel。
5. build 產物交給乾淨環境安裝後再跑 E2E；release 測試的是將發布的同一批套件，
   不是另外編的一份。不得沿用別的 SHA 或先前手動執行的綠燈。
6. workflow summary 分開呈現 build、unit、adapter、installed-package、X11、
   native Wayland、XWayland、sandbox、UI 的通過／失敗／未測。
   正式矩陣不准 `continue-on-error` 或用 skip 偽裝成功；ARM64 preview 與 Arch
   等非正式 job 的失敗也要可見。
7. 測試定義、結果格式、證據與 release gate 見 [測試計畫](LINUX_TEST_PLAN.md)。
   先量測 RAM、磁碟與耗時再決定 PR 子集合，不預估「自動化百分比」。
8. 沿用現有版號來源與 release 模式：tag 必須等於 `v` 加 README 版號；手動預設
   只產 artifacts，需要發布時驗證指定既有 tag。只附加 Linux assets，不覆蓋
   macOS／Windows／行動版產物，不自動建立 tag，不覆蓋同名既有 asset。
9. PR 觸發路徑包含 Linux 程式／測試／workflow，以及唯讀共用資料的變更；不能只
   監看 Linux 目錄而漏測新版詞庫。文件-only 變更可跑文件檢查，但需避免 required
   checks 永久 pending；手動桌面測試與 release 一律不因 path filter 跳過。
10. 為擴大的四年矩陣設定 `max-parallel`、分片與產物去重；PR 固定必測
    Ubuntu 24.04 + Fcitx 5 完整功能與最舊／最新邊界。歷史版本只在相容性相關 PR、
    手動指定或 release 執行，不設定自動輪替。主要環境不可只跑 smoke；也不能降低
    release 的逐版本實際打字門檻，或省略中間版本來節省 CI 時間。
11. 原始碼入口實作後，在既有 Linux CI／package workflow 納入第 5.1 節的
    configure／make 與 tarball 重建檢查；依測試計畫分配 PR 與 release 覆蓋，
    與 Ninja／原生套件結果分開呈現，不以其中一條路徑的成功代替另一條。

### Hosted Wayland 可行性 gate

- 優先 QEMU 完整 guest：systemd + session D-Bus + 真 GNOME Shell／KWin +
  distro 原生框架，以軟體繪圖與虛擬鍵盤執行。探測 `/dev/kvm` 可用性，不假設
  每種 host／架構都有 nested virtualization。TCG 備援也要量測成本與 timeout。
- Nested compositor 可先加速開發，但只有證明相同 protocol／panel／focus 路徑時，
  才能取代相應項目；Weston headless 不能代替 GNOME 或 Plasma 驗收。
- 若 hosted runners 無法可靠完成正式矩陣，記錄具體失敗及嘗試過的方案，向使用者
  提出較大 runner／受控 self-hosted runner／縮小正式宣告範圍的選擇。
  不擅自要求購機，不無聲降級為只跑 unit，也不能聲稱全部已在 hosted 完成。
- 實體 USB／藍牙、GPU driver、真實混合 DPI 多螢幕與真人可及性仍需補充驗證；
  VM 可測虛擬顯示／縮放，但報告必須區分虛擬與實體結果。

## 7. 分階段開發與驗收

每階段以可獨立 review 的變更交付，更新本節、`docs/parity.md` 與 AGENTS TODO。

2026-09-12 第一段垂直切片已完成 P1 的主要骨架：C++17 engine contract、每個 input
context 獨立狀態、嚴格 CIN reader、五種注音布局、Fcitx 原生布局設定，以及可載入的
Fcitx 5 addon。Rancher Desktop container 已在 Ubuntu 24.04（Fcitx 5.1.7）與 22.04
（Fcitx 5.0.14）x86_64 userspace 編譯、跑 CTest 並驗證 staged install；24.04 ARM64
build 亦已通過。Ubuntu 24.04 x86_64 另以 Xvfb、獨立 D-Bus、Fcitx 5 與 GTK 3 host
完成二十二個最小 installed-addon L3 X11 流程：Standard T01 鍵序選出「中」，
五種注音配置的 T02 鍵序皆以二、三、四、輕聲選出「麻馬罵嘛」，
漢語拼音並清除不完整 `zh`；倉頡 `a` 選「日」，另驗證直接標點、查無碼清除與
單一候選提交為「，用」，並以 `a?`／`a*` 萬用字元提交「昌日」；簡易 `a`
選第二候選「曰」，另驗證兩碼自動候選、連續
輸入、單一候選及標點候選為「明銖䍤、」；並以 PageDown、Down、Enter 從注音第二頁
選出「妐」；`Shift+Space` 全形流程提交精確 `Ａ！～　`；Big-5 限制開啟時從
`ㄝˋ` 過濾後候選選出 `𤦩`；繁轉簡開啟時逐字選出
真實候選「臺灣」並提交「台湾」；另以 `Ctrl+0`
開啟真實標點表並按 `1` 選出「，」；六個關聯詞流程以 `Shift+1` 驗證基本詞庫
「今天」、history-only「臺灣史」、全部關閉後的「臺!」，以及舊逗號設定
migration 後的「中程計畫」；第五案再從 Fcitx D-Bus `SetConfig` 寫入 government-only，
確認 INI 落盤、重啟 Fcitx 並讀回後仍輸出「中程計畫」；第六案以 AT-SPI 找到
`fcitx5-config-qt` 的輸入法與核取方塊，實際點選只開 agriculture-food、保存並重啟後
逐鍵輸出「作物育種」，同時保存切換前後截圖。各案都有 `keyboard-us` 負控制，
並確認執行中 Fcitx process 載入 staged `.so`。真正安裝的 Ubuntu 24.04 `.deb`
在 `1.2.8~preview1` 初裝與升級狀態各跑二十一個鍵盤案例，移除後重裝則跑全部二十二案；
套件同時核對 debhelper/lintian、ELF dependency、架構、版本、安裝清單、資料 hash、
授權檔與使用者設定保留。Ubuntu 22.04 的對應 `.deb` 亦已在 Fcitx 5.0.14 userspace
建置，並於乾淨 runtime container 通過安裝、移除、重裝及相同的非桌面套件檢查。
倉頡與簡易已有字根 preedit、基本候選等垂直切片，倉頡另有 `?`／`*` 萬用字元；
2026-09-13 起 F03／F04 已排除，這些只留作相容性回歸，不再擴充或宣告支援。
T02 已覆蓋五配置的二、三、四、輕聲
與漢語拼音不完整輸入退格，但更廣的錯誤輸入仍待 macOS baseline 與完整 E2E。
這不是 GNOME session；P0 所要求的 native Wayland／XWayland、完整桌面/App、popup
與 hosted runner 實證仍未完成。

| 階段 | 工作 | 出場條件 |
|---|---|---|
| P0：證據與風險先行 | 先驗證 Ubuntu 24.04 GNOME + Fcitx 5 的 addon、popup、Qt 回送、三種 session 路徑與 hosted 注入；凍結 macOS baseline，盤點 Ubuntu 版本與最低依賴 | 主環境真 host app 收到測試字、負控制符合預期、addon 身分正確；Ubuntu 22.04 最低 API 與 GNOME 差異有結論 |
| P1：Linux 引擎骨架與資料 | CMake、授權、native 資料工具、context 契約、五種注音布局 | 不需 GUI 可跑 CTest；真實資料 golden、Unicode／生命週期測試通過，無舊核心 link |
| P2：注音功能與 filter | 內建關聯詞、標點、全半形、繁轉簡、注音修正 | F01–F02、F05、F09–F10 對應測試通過；不能到此就宣稱核定範圍的完整 parity |
| P3：完整 Ubuntu 桌面整合 | 完成 Ubuntu 24.04 + Fcitx 5 全功能／視窗／App／sandbox 驗收，再完成 Ubuntu 內其他 adapter 路徑 | 主環境符合測試計畫完整驗收；F01–F02、F05–F11、F16 狀態明確；GTK/Qt 真打字與視窗流程通過；不加入已排除項目 |
| P4：Ubuntu 多版本與安裝 | Ubuntu 近四年矩陣原生 `.deb`、ARM64 preview、乾淨安裝／升級／移除；configure／make 原始碼入口與 source tarball | 9 個 Ubuntu 版本的套件與原始碼安裝路徑皆有正確 dependency、data、授權；source tarball 可獨立重建，安裝後從系統選到注音並打字 |
| P5：Ubuntu CI 與首版驗收 | Ubuntu workflows、release gate、sandbox／應用程式矩陣、文件 | 同一 SHA 的 Ubuntu 正式矩陣全綠且證據齊全；preview 不混入正式保證；由使用者確認可接受差異後發布 |
| P6：其他發行版 TODO | Ubuntu 完成後再做 Debian 12／13 與 Fedora 36–44 的 adapter、DEB／RPM、桌面與 CI | 各家族重新確認仍在近四年範圍，逐列升格為 active；不得用 Ubuntu ELF binary 直接重包 |

總完成條件：

- [ ] 除核定的版號 metadata 更新外，未改動禁止範圍；四個既有平台的行為與發布路徑保持不變。
- [ ] 注音在兩 adapter 都可用；F01–F02、F05–F11、F16 功能／視窗逐列有驗收結果。
- [ ] Ubuntu 24.04 GNOME + Fcitx 5 通過最完整測試，X11／native Wayland／XWayland、
      所有核定功能、App／sandbox／UI、安裝升級及穩定性皆有獨立證據。
- [ ] F03–F04、F12–F15 不作為未完成／待恢復項目；新 UI 不加入其選單或佔位。
- [ ] Ubuntu 近四年相容窗的每個版本／必要桌面組合通過已安裝套件的實際打字驗證，
      包含 EOL 歷史列，不只測最新版；Debian／Fedora 留在 P6 TODO，不阻擋此前的 Ubuntu 發布。
- [ ] PR／手動完整測試／release 都有可追溯報告，沒有「用寫入文字代替鍵盤」的假 E2E。
- [ ] 套件命名、版本、ABI、使用者資料保留、授權及安裝說明完整。
- [ ] 第 5.1 節 configure／make 入口與 T14-SOURCE 子案例完成；待發布 tarball
      可獨立重建、安裝及解除安裝，active Ubuntu 有原始碼安裝後的真實打字證據。
- [ ] 發布說明區分完整支援、preview、未測、已接受差異；未通過不標完成。

## 8. 接手第一輪工作

1. 重讀 AGENTS 與 BUILDING，確認工作樹與基線；保留無關未追蹤檔案。
2. 先做 Ubuntu 24.04 + Fcitx 5 的 P0；把尚未證實的 protocol、UI 能力與範圍內
   macOS 入口寫成可驗證項目，同時保留最舊版本的依賴約束。
3. 建立 Linux 私有的 parity／fixture／support-matrix 格式，將本計畫的 F 與測試 T ID
   對應；不要邊寫功能邊把預期值改成程式當下輸出。
4. P0 決議完成後才擴大引擎／視窗開發；按階段交付，不重構四平台。
5. 交接列出已完成、實際跑過的命令／workflow run／SHA、未測、卡住原因與下一步。
   本檔勾選僅以實際證據為準。
