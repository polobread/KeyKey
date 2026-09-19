# Linux 原生版開發與交接計畫

狀態：開發中。已建立第一段 Linux-only 引擎、Fcitx 5 外掛、container scripts 與
`linux-ci.yml`、五種 Windows 傳統注音鍵盤配置、候選鍵盤導覽、標點／符號候選切片、
`Shift+Space` 全／半形、ASCII 全形對映、繁轉簡單字與注音 Big5-HKSCS 候選 filter 切片、
L3 X11/GTK 3、GTK 4、Qt 6 各自適用的第一階段完整真實輸入矩陣與
Ubuntu 22.04／24.04 開發用 Debian 套件；Ubuntu 24.04 的隔離 GNOME X11 session
另已通過 76 個不重啟桌面 Fcitx 的 GTK 3／GTK 4／Qt 6 真實輸入案例。尚未完成
完整登入生命週期、完整視窗、IBus 或正式發布套件。2026-09-20 的 GNOME Wayland
KVM guest 已以 20 案 × 8 條 native Wayland／XWayland 的逐鍵與滑鼠矩陣通過
160/160；真實 gedit 四條路徑通過，GNOME Text Editor 的直接 Fcitx
Wayland／XWayland 通過，
但另兩條 GTK Wayland IM 路徑無 active input context，仍須處理。後續
T11 編輯欄位以 GNOME Shell crash 前 21/24、恢復 session 後 3/3 完成；
T12 符號表真滑鼠八路徑 8/8 通過。T10 兩個同時存活 App 的直接 Fcitx
六路徑 12/12 通過，GTK 預設 Wayland bridge 則共用單一 IBus context，
未達跨 App 模式隔離；候選中關閉 client 與新 client 恢復八路徑 8/8、
Fcitx 新 PID 後重跑 T01 八路徑亦 8/8。明確 GDM 登出登入後新 session
的 T01／T06 真滑鼠各八路徑共 16/16 通過，完整 App／視窗與穩定性尚待驗收。

盤點日期：2026-09-12；原始碼基線：`13696ef`；產品版號來源：`README.md` 標題。

Linux 首版目標：**1.2.8**，自此版起納入 Linux 支援；需完成下列實作與驗收後才可
對外宣告已支援。目前四平台版號已同步至 1.2.8；Linux 已有開發中的 staged install
與 `.deb`，但缺少完整功能、桌面矩陣與 release gate，仍不是可正式發布的套件。

接手順序：[AGENTS.md](AGENTS.md) → [BUILDING.md](BUILDING.md) → 本檔 →
[LINUX_TEST_PLAN.md](LINUX_TEST_PLAN.md)。本計畫取代「Linux 只比照行動版注音」的範圍。

## 1. 已確定的產品方向

- Linux 採原生實作，第一階段以 Windows TSF **目前實際可用的全部功能與設定**為
  功能基準；包含 Standard、ETen、ETen26、Hsu、Hanyu Pinyin 五種傳統注音布局。
- **主要支援環境為 Ubuntu Desktop 24.04 LTS + Fcitx 5**，以預設 GNOME 桌面
  作為主要驗收環境，X11、native Wayland 與 XWayland 都要完整測試。功能開發、
  問題修正與自動化覆蓋優先落在這一組，完整範圍見測試計畫的「主要環境完整驗收」。
- 使用者已排除 F12–F15：迷你計算機、自訂詞／詞庫管理、通用表格／外掛設定、
  一點通與提示／通知視窗。不開發、不加選單或佔位 UI，也不列為 Linux 驗收缺口。
  F05 內建關聯詞與分類開關、F11 符號面板及 F16 設定／關於仍保留。
- 2026-09-13 最新決定改以 Windows 全功能對標取代「只做 Standard」：F02 四種額外
  注音布局與布局設定維持第一階段支援。Linux 已完成但 Windows 沒有的 F03 倉頡、
  F04 簡易與繁轉簡切片不特別移除，保留日後擴充能力，但不列為第一階段 blocker。
  候選學習／動態頻率及注音自動修正仍不開發，其他平台既有功能不更動。
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

## 3. 第一階段範圍與行為對照：實際入口優先

下表是原始碼盤點，不是實機驗收紀錄。接手固定先查 macOS
OSX-IMK、PlainVanilla 與實際模組事件流，再查 Windows TSF 原始碼並對當前
build 操作錄影；逐項記錄觸發按鍵、設定預設值、中間狀態與最終文字，
形成 `docs/parity.md`。兩平台不同時明列差異，不從 Windows 反推 macOS。
範圍內每列須有「macOS 行為來源／Windows 交叉檢查與操作證據／Linux
對應／測試 ID／差異／狀態」。
第一階段必備範圍為 F01–F02、F05–F11，以及 F16 中 Windows 現有的設定與語系部分。
新增發現先確認是否為 Windows runtime 實際提供的功能，不因舊原始碼存在就擴張範圍。

| ID | 功能與視窗 | 已確認的原始碼入口 | Linux 交付要求 |
|---|---|---|---|
| F01 | Standard 傳統注音 | `OSX-IMK/OpenVanillaController.mm`、`OVIMTraditionalMandarin.cpp`、`PlainVanilla/PVLoaderSystem.h`；再查 `Windows-TSF/KeyKeyEngine.cpp` | Standard 單音節 reading、聲調鍵立即查詢／單一候選直接提交、選字、刪除、取消、逐音節連續輸入、錯誤鍵保護與 BIG-5 篩選設定；排序與提交時機先對照 macOS，再交叉檢查 Windows |
| F02 | 其他四種注音配置 | `OVIMTraditionalMandarin.cpp`；再查 `Windows-TSF/SettingsApp.cpp` | ETen、ETen26、Hsu、Hanyu Pinyin 與持久化布局選單；和 Standard 使用相同聲調即時查詢、候選、連續輸入、錯誤處理及桌面驗收 |
| F03 | 倉頡 | `OSX/TakaoCangjie.m`、`OVIMGeneric`、`cj-ext.cin` | 不在 Windows 第一階段基線；保留既有 Linux 垂直切片、註冊、測試與可擴充架構 |
| F04 | 簡易（Simplex） | `OSX/TakaoSimplex.m`、`OVIMGeneric`、`simplex-ext.cin` | 不在 Windows 第一階段基線；保留既有 Linux 垂直切片、註冊、測試與可擴充架構 |
| F05 | 關聯詞與分類詞庫 | `OVAFAssociatedPhrase.cpp`；再查 `Windows-TSF/KeyKeyEngine.cpp`、`SettingsApp.cpp` | 提交後顯示後綴、Shift 選詞、接續、去重、來源順序、30 套分類開關及全部關閉；行為先對照 macOS，再交叉檢查 Windows |
| F06 | 直／橫候選窗 | `PlainVanilla/PVCandidate.h`、`PVLoaderSystem.h`；再查 `Windows-TSF/CandidateWindow.cpp`、`CandidateStateTest.cpp` | 選字鍵角標、方向鍵反白、Enter、滑鼠選字、循環翻頁、空列表、焦點保留、關聯詞樣式 |
| F07 | 比例與配色 | `OSX-IMK/OpenVanillaController.mm`、`CVHorizontalCandidateController.mm`、`CVVerticalCandidateController.mm`、`PreferenceApplications/OSX/TakaoGlobal.m`；再查 `Windows-TSF/CandidateWindow.cpp`、`SettingsApp.cpp` | 跟隨系統及 Windows 現有 75%–350% 比例選項；預設／紫、綠、黃、紅反白色，驗證 Fcitx 可達的對等呈現 |
| F08 | 一般設定與切換 | `OSX-IMK/OpenVanillaController.mm`；再查 `Windows-TSF/TextService.cpp`、`LangBarButton.cpp`、`SettingsApp.cpp` | 中文／英文、全／半形狀態、Ctrl+反斜線與單按 Shift、錯誤提示聲、即時套用及重登入保存；以 Fcitx 原生 action／設定提供對等入口 |
| F09 | 全／半形與既有繁轉簡擴充 | `OSX-IMK/OpenVanillaController.mm`、`OVOFFullWidthCharacter.cpp`；再查 `Windows-TSF/TextService.cpp`與 Linux `tc2sc.cin` | 第一階段對標 Windows 的 Shift+Space 與狀態呈現；已完成的 Linux 繁轉簡切片保留，不拆除其資料或 filter 架構 |
| F10 | 注音標點 | `OVIMTraditionalMandarin.cpp`、注音標點 `.cin` | 五布局的直接／組合鍵標點與英文混輸，不能吞掉未配置的應用程式快捷鍵；注音自動修正不在 Windows runtime |
| F11 | Windows 符號列表 | `OVIMTraditionalMandarin.cpp`、`Windows-TSF/KeyKeyEngine.cpp` | `Ctrl+0`／`Ctrl+1` 開啟內建符號候選、翻頁與鍵盤／滑鼠選取；macOS 額外顏文字／常用文字自訂窗不屬第一階段 |
| F16 | Windows 對應設定／語系 | `PreferenceApplications/OSX`；再查 `Windows-TSF/SettingsApp.cpp`、`TextService.cpp` | 一般／注音／關聯詞三頁設定、繁中註冊名稱、鍵盤操作與可及性；Linux 套件仍保留版本、授權及必要出處 |

非第一階段 Windows 對標項目保留原 ID，避免舊交接編號混淆，並保留日後擴充可能：

- 注音自動修正：Windows module package 未載入 correction module，因此不載入
  correction table、不提供開關，也不列為 F10 缺口。
- F03 倉頡、F04 簡易：Windows TSF 未提供，但已完成的 Linux engine、註冊與測試不
  拆除；目前作額外功能／回歸，不阻擋第一階段 Windows parity。
- F12 迷你計算機：不實作算式引擎、互動模式或其 Ctrl+9 入口。
- F13 自訂詞／詞庫管理：不實作使用者詞編輯、匯入、匯出或管理視窗；
  不排除 F05 的內建關聯詞資料與分類開關。候選學習另依 2026-09-13 決定排除。
- F14 通用表格與外掛設定：不提供使用者 CIN 安裝／管理、動態外掛與其設定；
  注音仍需解析產品內建 `.cin`，不能因此刪掉內部字表引擎。
- F15 一點通、提示／通知視窗：不實作一點通服務、獨立提示窗或通知視窗。
  輸入必要的 preedit／候選窗屬 F01／F06，設定欄位的基本錯誤提示仍在原視窗內呈現。

以上項目不需為第一階段建立 Windows 對等實作，但也不得為了縮減驗收而刪除已完成的
Linux 功能、擴充介面或四個既有平台中的任何相關功能。

路徑縮寫：`OSX-IMK/` 在 `Source/Loaders/`；`OSX/` 在
`Source/PreferenceApplications/`；模組在 `Source/ModulePackages/`；字表在
`Source/DataTables/`。P0 須把簡寫補成可點選的完整來源連結與當時 commit。

Windows 設定直接列出 Standard、ETen、ETen26、Hsu、Hanyu Pinyin 五種注音配置；
Linux 應維持五值設定與相同行為，不需複製 macOS 的隱藏選單方式。

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

1. macOS 現行 OSX-IMK loader、PlainVanilla、實際模組與真實操作：行為、
   事件歸屬與預設值先以這條路徑為比對來源。
2. Windows TSF 現行 loader、設定 UI、模組與真實操作：用於交叉檢查
   macOS 結果並劃定第一階段功能範圍；與 macOS 不同時明列平台差異。
3. Android Java 原生 `BopomofoEngine`、`BopomofoReading`、`CinDictionary`、
   `AssociatedPhraseDictionary`：狀態機與直接讀資料的參考。
4. iOS Swift `KeyKeyEngine/Sources/KeyKeyEngine`：原生引擎、候選、Unicode、
   實體鍵盤與測試參考；不將 Swift package 改成 Linux 共用核心。

macOS 已有但 Windows TSF 未提供的功能，不因此自動擴張第一階段範圍或
升格為 blocker。

禁止修改：`Source/Frameworks/`、既有 `Source/ModulePackages/`、四平台 loader、
現有字表／詞庫內容、既有 cooker、四平台 workflow。若發現資料錯誤，另列 issue／
交接，不借 Linux 工作順便改動。可新增 Linux 目錄、Linux workflow，並更新必要的
根目錄建置／授權／支援說明。CI 檢查 Linux 目標無舊核心 include/link dependency。

例外僅限使用者明確要求的共用版號更新：1.2.8 的既有四平台 version metadata
依 AGENTS 同步，不包含任何舊引擎、UI 功能、資料或 workflow 行為變更。

### 資料與授權

- 必要唯讀來源至少涵蓋 `bpmf-ext.cin`、`bpmf-punctuations.cin`、
  `DataSource/McBopomofo/phrase.occ`、公開分類詞庫及分類顯示名稱。
  繁簡映射、符號／常用文字表也要列入來源 manifest；不建立使用者詞匯入格式。
  既有額外切片仍會讀 `cj-ext.cin`／`simplex-ext.cin`；目前不繼續開發、
  不作第一階段 blocker，但保留實作與擴充結構。
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
CI 已在 run `34742072894` 通過基本 source gate；`/usr`／
任意自訂 prefix 的實際打字、升級／重裝及其餘 active Ubuntu 尚未完成，所以
T14-SOURCE 與 P4／P5 不標成全部通過。

2026-09-20 Ubuntu 24.04 local amd64 再完成三種原始碼真安裝：`/usr/local`、
`/usr`、含空白路徑與自訂 libdir／datadir 的 prefix。每組核對 Fcitx 5 實際載入
的 addon 路徑，並以 GTK3／GTK4／Qt6 通過 82 個非設定視窗 X11 真打字案例後依
manifest 卸載；自訂 prefix 的無關 sentinel 在移除後仍在，重裝後三套 toolkit
的 T01 亦通過。`/usr`／自訂 prefix 在乾淨的一次性 container 跑，因長駐
dev container 先前的 staged gate 已留下 `/usr` KeyKey 檔案，覆寫保護會拒絕
混用。跨版本 source 升級、22.04 對等系統安裝、其他 active Ubuntu 與
GNOME／Wayland 仍未完成。

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
| `.github/workflows/linux-ci.yml` | PR、主分支 push、手動 | PR 只跑 Ubuntu 24.04 build、unit、staged install 與 GTK3/Fcitx T01 真打字 smoke；合併進 `master` 後及手動執行才跑 sanitizer、source gate、Ubuntu 22.04 最低 API、完整 hosted X11 typing／UI 與套件生命週期 |
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
10. 為擴大的四年矩陣設定 `max-parallel`、分片與產物去重；PR 固定只跑
    Ubuntu 24.04 + Fcitx 5 smoke，完整 hosted 回歸移到合併後的 `master` push。
    歷史版本只在相容性相關的手動指定、主分支完整 gate 或 release 執行，不設定
    自動輪替。這個分流不能降低 release 的逐版本實際打字門檻，或省略中間版本來
    節省 release CI 時間。
11. 原始碼入口實作後，在既有 Linux CI／package workflow 納入第 5.1 節的
    configure／make 與 tarball 重建檢查；依測試計畫分配 PR 與 release 覆蓋，
    與 Ninja／原生套件結果分開呈現，不以其中一條路徑的成功代替另一條。

### Hosted Wayland 可行性 gate

- 優先 QEMU 完整 guest：systemd + session D-Bus + 真 GNOME Shell／KWin +
  distro 原生框架，以軟體繪圖與虛擬鍵盤執行。探測 `/dev/kvm` 可用性，不假設
  每種 host／架構都有 nested virtualization。TCG 備援也要量測成本與 timeout。
- 2026-09-20 本機 WSL2 Ubuntu 24.04 已在正常使用者行程確認 KVM API 12，
  QEMU 8.2.2／OVMF 可啟動官方 Ubuntu 24.04.5 cloud image。完整 GDM
  自動登入的 GNOME Shell 46 session 為 active Wayland，Fcitx 5.1.7 maps
  確認載入系統安裝的 KeyKey addon、Wayland 與 IBus frontend；QMP 真實鍵盤
  注入在 GTK3、GTK4、Qt6 原生 Wayland 各完成 T01，GTK3／GTK4 另在未設
  `GTK_IM_MODULE` 下通過，同樣包含 preedit／「中」／英文負控制，合計 5/5。
  後續擴成 20 案 × 八條 toolkit/backend 路徑，完整一次執行 160/160 通過，
  加入五布局、候選直／橫鍵盤導覽、第二列真滑鼠點擊與畫面清除、關聯詞、
  全形／簡體、快捷鍵與符號表；
  各案都有 `keyboard-us` literal 負控制。真實 gedit 四條路徑及 GNOME Text
  Editor 直接 Fcitx Wayland／XWayland 路徑通過；Text Editor 在未設
  `GTK_IM_MODULE` 及明設 `wayland` 時均沒有 active input context，不能以
  synthetic GTK4 host 的 bridge 成功取代真 App 結論。GDM display-manager
  restart 後新 session 的 T01／T06 滑鼠 16/16 通過。
  同 guest 的 T10 兩欄焦點正負控制 16/16 通過；六條直接 Fcitx 路徑
  失焦會提交原始「ㄓㄨㄥ」，兩條 GTK 原生未設 `GTK_IM_MODULE` 路徑則清除
  preedit。這是觀測到的平台路徑差異，不能寫成 Windows focus-out parity
  已完成。後續兩個同時存活 App 的直接 Fcitx 六路徑 12/12 通過，
  GTK 預設 Wayland bridge 兩條路徑則共用 IBus input context，正向隔離
  0/2；client 關閉與 Fcitx 新 PID 恢復各八路徑 8/8。明確登出登入後
  T01／T06 16/16；T11 指標替換／密碼／唯讀與 T12 符號真滑鼠亦已實跑。
  Firefox Snap native Wayland 兩路徑與 Epiphany native Wayland／XWayland
  三路徑，跨多行、單行與 `contenteditable` 真正 DOM 欄位 15/15 通過。
  Firefox Snap XWayland 在此 VM
  無法開啟 display，仍屬缺口。
  最小桌面套件選錯 Netplan renderer 的 guest 重啟故障已修正；VM 停止後
  重新啟動，SSH、Wayland login、Fcitx addon 與五案再次恢復／全過。
  重建流程見 `Source/Loaders/Linux-IME/docs/gnome-wayland-vm.md`。受限行程的
  `nodev` `/dev` 與 QMP socket 權限不能用來判定一般 WSL host 能力；
  popup 邊界／多螢幕、完整 focus／多 App 矩陣、其他瀏覽器操作與
  hosted runner 仍待驗證。
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
build 亦已通過。Ubuntu 24.04 x86_64 另以 Xvfb、獨立 D-Bus、Fcitx 5 與 GTK 3／GTK 4／
Qt 6 hosts 完成八十三個 installed-addon L3 X11 流程：Standard T01 鍵序選出「中」，
五種注音配置的 T02 鍵序皆以二、三、四、輕聲選出「麻馬罵嘛」，
並在第一個 reading 中以裸 `\` 與 `Ctrl+C` 驗證無效鍵／快捷鍵不破壞組字，
漢語拼音另清除不完整 `zh`；倉頡 `a` 選「日」，另驗證直接標點、查無碼清除與
單一候選提交為「，用」，並以 `a?`／`a*` 萬用字元提交「昌日」；簡易 `a`
選第二候選「曰」，另驗證兩碼自動候選、連續
輸入、單一候選及標點候選為「明銖䍤、」；並以 PageDown、Down、Enter 從注音第二頁
選出「妐」，再以真實滑鼠點擊展開後的 Fcitx 直式候選第二列選出「鐘」；
`Shift+Space` 全形流程提交精確 `Ａ！～　`；Big-5 限制開啟時從
`ㄝˋ` 過濾後候選選出 `𤦩`；繁轉簡開啟時逐字選出
真實候選「臺灣」並提交「台湾」；另以 `Ctrl+0`
開啟真實標點表並按 `1` 選出「，」，再以真實滑鼠點第一列後接 `!` 得到「，!」；
六個關聯詞流程以 `Shift+1` 驗證基本詞庫
「今天」、history-only「臺灣史」、全部關閉後的「臺!」，以及舊逗號設定
migration 後的「中程計畫」；第五案再從 Fcitx D-Bus `SetConfig` 寫入 government-only，
確認 INI 落盤、重啟 Fcitx 並讀回後仍輸出「中程計畫」；第六案以 AT-SPI 找到
`fcitx5-config-qt` 的輸入法與核取方塊，實際點選只開 agriculture-food、保存並重啟後
逐鍵輸出「作物育種」，同時保存切換前後截圖。各案都有 `keyboard-us` 負控制，
並確認執行中 Fcitx process 載入 staged `.so`。真正安裝的 Ubuntu 24.04 `.deb`
最近一次 package 證據在 `1.2.8~preview1` 初裝與升級狀態各跑八十二個非設定視窗案例，
移除後重裝則跑全部八十三案，含一個設定視窗操作案；套件 dependency、
資料 hash、移除殘檔與使用者設定保留也一併通過。
套件同時核對 debhelper/lintian、ELF dependency、架構、版本、安裝清單、資料 hash、
授權檔與使用者設定保留。Ubuntu 22.04 的對應 `.deb` 亦已在 Fcitx 5.0.14 userspace
建置，並於乾淨 runtime container 通過安裝、移除、重裝及相同的非桌面套件檢查。
倉頡與簡易已有字根 preedit、基本候選等垂直切片，倉頡另有 `?`／`*` 萬用字元；
兩者雖不在 Windows 第一階段基線，既有功能、註冊與測試均保留作額外功能與後續擴充。
T02 已覆蓋五配置的二、三、四、輕聲；各聲調鍵會依 macOS 行為立即開候選，
再以 Windows 交叉檢查，不需再按
Space，並覆蓋漢語拼音不完整輸入退格；五配置也都依相同參考順序驗證 reading 中
裸 `\` 被吃掉並提示錯誤、`Ctrl+C` 放行，兩者之後仍能完成選字。五種配置皆屬 Windows
對標範圍。2026-09-13 已在 Linux engine 補上五布局候選開啟時直接開始下一音節，以及
無效鍵／查無候選保留 reading 並回報錯誤提示訊號；Fcitx→GTK3 新增「中文」連續輸入
與 `=`／`Ctrl+C` 錯誤恢復兩案並使完整 X11 suite 達 24/24。Fcitx adapter 已把
錯誤訊號接到 XDG `bell-window-system` 事件音效，預設開啟並可由原生設定關閉；設定
視窗測試會關閉、保存並在重啟後讀回。Xvfb 沒有桌面音訊 session，是否真正可聽仍待
Ubuntu 24.04 GNOME 驗收。
F08 中英模式也已補上 Fcitx 5 adapter：每個 input context 保留中／英狀態與
狀態標籤，預設以 `Ctrl+\` 或 300 ms 內單按 Shift 切換，轉英文時放棄現有
composition；英文半形交回 App，英文全形仍由輸入法轉換。X11 案例覆蓋
Ctrl 快捷鍵來回、Shift 短按／長按、Caps Lock、全／半形與有 reading 時切換；
`ToggleInputMethodWithControlBackslash` 的 Fcitx 原生核取方塊、INI／D-Bus 保存與
重啟讀回也已實測。完整 warm `ci/dev.sh verify` 為 CTest 2/2、X11 26/26；
Ubuntu 22.04 的 Fcitx 5.0.14 最低 API 建置及 configure／GNU Make source gate 同步通過。
F06 候選方向已使用 Ubuntu 22.04／24.04 皆提供的 `CandidateLayoutHint`：原生設定預設
Vertical，可切 Horizontal，並套用到每一份 Fcitx candidate list。AT-SPI 設定案例已
實際切成 Horizontal、保存、重啟後由 D-Bus 讀回，接著在該 hint 下完成「作物育種」
候選流程；完整 X11 suite 維持 26/26，更新後的 Ubuntu 24.04 `.deb` lifecycle 亦為
初裝 25/25、升級 25/25、重裝 26/26。Xvfb classic-ui 的頂層 window geometry 無法可靠
代表候選內容，因此尚未把寬高當成方向證據，仍須 GNOME／Wayland popup 畫面驗收。
F07 的比例與反白色由 Fcitx UI/theme 決定，Ubuntu 22.04／24.04 的 input-method addon
API 沒有 per-IME scale/color；若不能接受平台差異，後續須另作 custom UI addon，不能
加入不會生效的假設定。

F07 專屬 renderer 暫列下列 TODO，實作路線尚未決定：

1. 先做 architecture spike，比較「單一、相容 Fcitx 5.0.14 的 UI addon」與
   「Fcitx 5.0.24+ per-context callback 加 22.04 相容層」；不得以修改 Classic UI
   全域 `Font`／DPI 作為琦琦注音專屬功能。
2. 凍結 renderer contract：只接受 engine 已產生的 preedit、候選、反白、頁面、
   layout 與 click callback，不在 UI 重作注音選字邏輯；定義關窗、context 銷毀及
   Fcitx 重啟時的資源生命週期。
3. 實作與 macOS／Windows 相同的 system、75、90、100、125、150、175、200、225、
   250、300、350%，把 system DPI、字型、padding、圖示、視窗 geometry 與 pointer
   hit area 一起縮放，並固定 rounding 規則。
4. 完成直式／橫式候選、一般候選／關聯詞／符號表、頁面控制、鍵盤反白與滑鼠選字；
   候選消失不可重現 WSLg 殘影 workaround，也不可加入 sleep 或重複 commit。
5. 分別完成 GNOME X11、XWayland、native Wayland 的游標定位、四邊避讓、不搶焦點、
   虛擬混合 DPI、多螢幕與多 input context；不能以 XWayland 結果代替 native Wayland。
6. 把比例放進 Fcitx 原生設定 schema，驗證預設值、舊設定 migration、D-Bus 保存、
   Fcitx／desktop session 重啟、套件升級與移除；renderer 未可用前不顯示無作用選項。
7. 新增 L1 geometry／rounding／hit-test 測試與 GTK3／GTK4／Qt6 installed-addon E2E；
   至少覆蓋 system、75、100、200、225、350%、直／橫、四邊位置與 click golden，
   完整比例 × 配色視覺 sweep 留給手動完整／release gate。
8. 盤點新增 UI protocol／graphics dependency、Ubuntu 22.04 ABI、Debian package、授權
   與可維護成本；若需引用 Fcitx Classic UI 原始碼，先處理 LGPL 邊界再實作。

T03 編輯／取消邊界已先依 macOS `OpenVanillaController`、`OVIMTraditionalMandarin`
與 PlainVanilla candidate flow 固定，再以 Windows `KeyKeyEngine` 交叉檢查：空狀態
Backspace／Escape 交還 App，reading Backspace 逐音退回，reading
Escape 清空；候選 Backspace 關窗並只刪最後一音，候選 Escape 清掉整個 reading。
L1 已覆蓋全部狀態，新增 installed-addon X11/GTK3 案例以同一欄位完成空狀態刪字、兩種
Backspace 與兩種 Escape 後只提交「中文麻」。完整 `ci/dev.sh verify` 為 CTest 2/2、
X11 27/27；Ubuntu 24.04 `.deb` lifecycle 為初裝 26/26、升級 26/26、重裝 27/27。
T09 也已先依 macOS 事件流固定、再以 Windows 交叉檢查：一般
Ctrl／Alt／Super 與 Ctrl+方向鍵不由注音引擎
處理，key release 不可選字或重複提交；關聯詞在 modified key press 時關閉後放行，release
則不改狀態。L1 已覆蓋 reading、一般候選與關聯詞的 press／release／repeat；新增
installed-addon X11/GTK3 案例長按 `Ctrl+\` 一秒只切換一次，並在 reading／候選中送
Ctrl+C、Alt+F 後精確提交 `x中文`；長按後先在正負控制都以 `Ctrl+A`／Backspace 清除
X11 repeat 時序可能留下的裸反斜線，負控制固定為 `x5j/ 1jp61`。這項測試曾實際抓到 X11
repeat key-down 沒有 Fcitx `Repeat` state 而反覆切換的問題，現以實體 backslash
press/release latch 修正；先放 Ctrl 所觸發的裸 backslash 重送也會持續被抑制到 key-up。
更新後完整驗證為 CTest 2/2、X11 28/28；Ubuntu 24.04
`.deb` lifecycle 為初裝 27/27、升級 27/27、重裝 28/28。Super 與 compositor 全域
快捷鍵仍須在 GNOME 驗證，不能由無 window manager 的 Xvfb 代替。
T10 的 local X11/GTK3 context lifecycle 也已建立：同一 client 的兩個 `GtkEntry`
在第一欄候選開啟時，依 host 回報的實際 widget geometry 以 XTest 滑鼠點擊第二欄，
使第一欄候選失焦後清除 preedit；第二欄獨立選出「文」，再以 Shift+Tab 切回
第一欄先證明舊候選未殘留，再選出「中」。另一段在候選開啟時讓 client 走 GTK 正常
關閉流程，確認 Fcitx 與 staged addon 仍存活，重啟 Fcitx 後再由新 client 選出「中」；
每段都有 `keyboard-us` literal control。不同 input context 依 Fcitx 的 share-input-state
設定可能各自記住 active engine，測試在每次跨 context 後明確切換並輪詢，不把框架
策略誤判為 KeyKey 狀態外洩。兩個同時存活的獨立 App 已由下列 2026-09-15 切片補上，
GNOME 登出登入與 Wayland 仍待桌面驗收。加入此案例後的完整 warm gate 為 CTest 2/2、
X11 29/29；Ubuntu 24.04
package lifecycle 亦已以真正安裝的套件通過初裝 28/28、升級 28/28、重裝 29/29。
2026-09-15 再新增兩個同時存活的獨立 GTK3 process。行為調查先看 macOS：
`deactivateServer:` 在失焦時 commit composing buffer 後清理；再看 Windows TSF：
document manager 失焦會 abandon 並非同步終止 composition，兩邊對 active preedit 沒有
單一共同語意。local Xvfb/Fcitx 5/GTK3 診斷也證實 App A 的 `ㄓㄨㄥ` client preedit
在切到 App B 時被 GTK 提交，切回後再選字會得到 `ㄓㄨㄥ中`，因此不以 addon workaround
假裝成 Windows。正式 multi-App isolation 在空 composition 切焦點：App A 切到英文全形
輸出 `ａ`，App B 仍以預設中文半形輸出「文」，切回 App A 後確認保留自己的模式並完成
`ａｂ中`；兩個 App 在受控關閉前皆仍存活。`keyboard-us` 負控制為
`ab5j/ 1|jp61`。targeted T10、完整 warm gate（CTest 2/2、X11 33/33）與 Ubuntu 24.04
package lifecycle（preview 初裝 32/32、release 升級 32/32、重裝後 33/33）均通過。
active preedit、GNOME 登出登入、GTK4／Qt／瀏覽器與 Wayland 仍待桌面驗收。
T11 的 local X11/GTK3 編輯與欄位安全邊界也已擴充：先依 macOS OSX-IMK、
TraditionalMandarin 與 PlainVanilla 的事件流固定行為，再以 Windows TSF 交叉確認。
reading 中未帶 Ctrl／Alt／Super 的方向、Home／End、PageUp／PageDown、Delete／Tab
及其 Shift 變體會保留 reading、提示錯誤且不移動 App caret／selection；一般候選的
Home／End 可跳首尾，無效候選編輯鍵也不漏入 App。真鍵盤流程在「甲乙丙」中間組字，
送完上述按鍵仍原位提交「中」，並驗證既有單字可由候選替換，精確得到
「甲中中丙」；切入
`GTK_INPUT_PURPOSE_PASSWORD` 後，Fcitx 依 capability 自動切回 `keyboard-us`，完整
鍵序只產生 literal `rup 1!`，不允許強制選回自訂輸入法或顯示關聯詞；不可編輯欄位
收到完整注音鍵序後仍保持「唯讀」。正向與 `keyboard-us` 負控制皆通過，adapter 對
其他 frontend 可能傳入的 `Password`／`Sensitive` capability 另防禦性清除關聯詞。
加入此案例後完整 warm gate 為 CTest 2/2、X11 30/30，Ubuntu 22.04 Fcitx 5.0.14
build／CTest／staging 亦通過；Ubuntu 24.04 `.deb` lifecycle 的 preview 初裝與 release
升級各為 29/29，移除／重裝後含設定視窗為 30/30，dependency、資料 hash、移除與設定
sentinel 亦全數通過。
2026-09-15 同一 T11 案例再補 App committed text 的真實指標 selection。比對仍先查
macOS：`OpenVanillaController`／PlainVanilla 在外部強制結束 composition 時可提交
residue 後清理；再查 Windows TSF，selection 離開追蹤範圍時會放棄並非同步終止舊
composition，因此不把 active composition 的指標行為假定為相同。本切片固定兩邊共同
且無歧義的路徑：GTK host 從 Pango layout 產生第二字左右 hit point，XTest 先清除初始
全選、再拖曳選取「乙」，精確觀測 selection `1:2`，由注音候選替換後得到「甲中丙」；
接續原有 active-reading 編輯鍵回歸後最終仍為「甲中中丙」。`keyboard-us` 負控制使用
相同指標選取只得到 literal「甲5j/ 1丙」。targeted T11 與完整 warm gate 均通過，後者
為 CTest 2/2、X11 32/32；本次只改測試覆蓋，未重跑 package lifecycle。active
composition 期間以指標改 selection、GTK4／Qt／瀏覽器、GNOME 與 Wayland 仍待驗收。
2026-09-15 建立第一段 GTK4 client coverage。行為調查仍先查 macOS：
`OVIMTraditionalMandarin` 選字後寫入 committed text，OSX-IMK loader 隨即以
`commitComposition`／`insertText` 送進 App；再查 Windows TSF，engine snapshot 交由
`updateComposition` 呼叫 `commitText`，同一按鍵流程更新或隱藏候選。兩邊對 Standard
T01 的逐音 preedit、選字提交及清空順序一致。新增最小 GTK4 `GtkText` host，透過實體
XTest 鍵序與已安裝 Fcitx 5 addon 精確觀測 `ㄓ` → `ㄓㄨ` → `ㄓㄨㄥ` →「中」，切回
`keyboard-us` 後相同鍵序得到 literal `5j/ 1`。targeted 案例與完整 warm gate 均通過，
後者為 CTest 2/2、X11 34/34；Ubuntu 24.04 package lifecycle 的 preview 初裝、release
升級各通過 33/33，移除／重裝後含設定視窗通過 34/34。這一個 T01 切片完成當時，
GTK4 T02–T12、GNOME 與 native Wayland／XWayland 仍待驗收。
同日再把 GTK4 擴充至完整五布局 T02。比對順序維持 macOS
`OVIMTraditionalMandarin` 的 `combineKey`／tone marker 立即查詢與候選流程在先，再看
Windows TSF 的相同共用 module 及五項設定值；兩邊都保留 reading 中的無效鍵提示，且
讓 Ctrl／Alt App shortcut 通過。GTK4 `GtkText` 以 Standard、ETen、ETen26、Hsu、
Hanyu Pinyin 真實輸入四聲／輕聲「麻馬罵嘛」，同時核對複用鍵中間態、不完整 `zh`
退格、裸 `\` 與 `Ctrl+C` 邊界。五個 targeted 案例與完整 warm gate 均通過，後者為
CTest 2/2、X11 39/39；Ubuntu 24.04 package lifecycle 的 preview 初裝、release 升級
各通過 38/38，移除／重裝後含設定視窗通過 39/39。GTK4 T03–T12、GNOME 與 native
Wayland／XWayland 仍待驗收。
同日再完成 GTK4 T03 編輯／取消邊界。先查 macOS
`OVIMTraditionalMandarinContext::handleBackspace`、`handleKey` 與 PlainVanilla candidate
cancel flow，再查 Windows TSF `wantsKey`、`isPotentialKey` 與
snapshot/updateComposition。兩邊共同行為是空狀態交回 Backspace／Escape，reading
Backspace 只刪最後一個注音成分、reading Escape 清空，一般候選 Backspace 先關窗
再刪一音，候選 Escape 則取消整段 reading。GTK4 `GtkText` 以和 GTK3 相同的
真實鍵序跑完所有邊界，只提交「中文麻」，並有 `keyboard-us` 負控制。targeted
T03、完整 warm gate（CTest 2/2、X11 40/40）及 Ubuntu 24.04 package lifecycle
（preview 初裝 39/39、release 升級 39/39、移除／重裝後含設定視窗 40/40）均通過。
Windows 對標的 GTK4 T06–T12、GNOME 與 native Wayland／XWayland 仍待驗收；T04／T05
為保留的 Linux 擴充，不是 1.2.8 第一階段 blocker。
同日再完成 GTK4 T06 候選導覽。先查 macOS `PVCandidate.h` 與兩種 candidate
controller：直式由 Up／Down 移動反白、Left／Right 翻頁，橫式則交換兩組方向鍵角色，
滑鼠索引會換成選字鍵；再查 Windows TSF `CandidateWindow.cpp` 與
`CandidateStateTest.cpp`，確認橫式只改自繪窗排列，底層仍使用直式鍵盤語意，且目前
沒有滑鼠按鍵選字訊息。Linux 第一階段因此在兩種畫面都維持 Windows 的 Up／Down
反白、Left／Right／PageUp／PageDown／Space 翻頁，同時保留 Fcitx 原生滑鼠 callback
作為額外能力。GTK4 新增直式鍵盤、直式滑鼠與橫式完整鍵盤三案：前兩案分別選出
「妐」與「鐘」，橫式依序送 End、Home、PageDown、PageUp、Right、Left、Space、Down、
Enter 後選出「妐」，每案都有 `keyboard-us` 負控制。targeted 三案、完整 warm gate
（CTest 2/2、X11 43/43）與 Ubuntu 24.04 package lifecycle（preview 初裝 42/42、
release 升級 42/42、移除／重裝後含設定視窗 43/43）均通過。Windows 對標的 GTK4
T07–T12、GNOME X11／XWayland／native Wayland 的候選畫面、位置與點擊仍待驗收。
同日再完成 GTK4 T07 關聯詞鍵盤與設定流程。先查 macOS
`OVAFAssociatedPhraseContext` 與 PlainVanilla around-filter：單字先 commit，候選只放
headless 後綴，`Shift+1–9` 選取後綴；再查 Windows TSF `KeyKeyEngine` 對同一模組的
啟用與設定同步，本段語意一致，且兩邊關聯詞窗都不走一般候選的滑鼠控制。GTK4
`GtkText` 新增預設 McBopomofo「今天」、history-only「臺灣史」、全部停用「臺!」、
舊逗號設定遷移「中程計畫」與 D-Bus 寫入／重啟／讀回後「中程計畫」五案，每案均有
`keyboard-us` 負控制。targeted 五案、完整 warm gate（CTest 2/2、X11 48/48）及
Ubuntu 24.04 package lifecycle（preview 初裝 47/47、release 升級 47/47、移除／重裝後
含設定視窗 48/48）均通過。GTK4 T08–T12、GNOME 與 native Wayland／XWayland 仍待
驗收；關聯詞滑鼠依既有平台差異不列 macOS／Windows 對標要求。
同日再完成 GTK4 T08 中英文、全半形與繁轉簡。先查 macOS
`OpenVanillaController.mm`、TraditionalMandarin 與 output-filter 流程：`Ctrl+\` 會
輪替內建輸入法，單按 Shift 不切換內部中英文，全形選單快捷鍵為
Command+Shift+Space；再查 Windows TSF `TextService.cpp`／`SettingsApp.cpp`，其內部
中文／英文模式、可停用 `Ctrl+\`、固定 Ctrl+Space、短按 Shift、Shift+Space 全半形
與 Caps Lock 才是本階段對標，繁轉簡則與 macOS 一樣在輸出階段套用。GTK4 新增四個
真實鍵序案例，精確提交中英模式 `5j/aBａ！　文abcde麻`、停用快捷鍵 `翁ㄓ`、全形
`Ａ！～　` 與繁轉簡 `台湾`，每案均有 `keyboard-us` 負控制。停用快捷鍵的同一 engine
pass-through 在 GTK3 得到 `ㄓ翁`、GTK4 `GtkText` 得到 `翁ㄓ`：兩者都由 client 提交
active preedit，但 GTK4 將後續 commit 插在其前，故不在 addon 內強制統一。targeted
四案、完整 warm gate（CTest 2/2、X11 52/52）與 Ubuntu 24.04 package lifecycle
（preview 初裝 51/51、release 升級 51/51、移除／重裝後含設定視窗 52/52）均通過。
GTK4 T09–T12、GNOME 與 native Wayland／XWayland 仍待驗收。
同日再完成 GTK4 T09 修飾鍵、repeat 與 key-up 邊界。先查 macOS
`OpenVanillaController.mm` 與 TraditionalMandarin candidate flow：Command、一般
Ctrl／Option shortcut 在 loader 層交回 App，只有已處理的 key-down 才配對吃掉 key-up；
再查 Windows TSF `TextService.cpp`／`KeyKeyEngine.cpp`，一般 Ctrl／Alt 同樣在送入
engine 前放行，普通 key-up 不吃，只有短按 Shift 另有切換語意。Linux 的 X11 長按
`Ctrl+\` 可能收到未標 Repeat 的重送 key-down，因此沿用實體 backslash press/release
latch，沒有把這項平台差異反推成 macOS／Windows 行為。GTK4 `GtkText` 以和 GTK3
相同的真實鍵序長按一秒、清除可能殘留的裸反斜線、切回中文，並在 reading／候選中送
Ctrl+C／Alt+F，精確提交 `x中文`；`keyboard-us` 負控制為 `x5j/ 1jp61`。targeted 案、
完整 warm gate（CTest 2/2、X11 53/53）與 Ubuntu 24.04 package lifecycle（preview
初裝 52/52、release 升級 52/52、移除／重裝後含設定視窗 53/53）均通過。Super 仍只在
L1，GTK4 T10–T12、GNOME 與 native Wayland／XWayland 尚待驗收。
同日再完成 GTK4 T10 input-context 與 client lifecycle。先查 macOS
`OpenVanillaController` 的 per-controller context、失焦 commit 及清理，再查 Windows
TSF `TextService.cpp` 的 document-manager／context 失焦 `abandonComposition()`；兩者
對 active composition 的語意不同，因此本段沿用既有共同邊界，不在 addon 內強制統一。
GTK4 `GtkText` 以和 GTK3 相同的實體鍵序驗證同 App 兩欄各自提交 `中|文`、候選中關閉
client 後 Fcitx/addon 仍存活、重啟 Fcitx 後新 client 再提交「中」，以及兩個同時存活
App 各自保留英文全形與中文半形狀態，精確得到 `ａｂ中|文`；兩案都有
`keyboard-us` 負控制。GTK4 失焦會短暫以 `changed` 回報 client preedit，切回後清除，
最終 buffer 與 context 狀態仍正確。兩欄改為左右排列以免候選 popup 覆蓋第二欄；
runner 也從最新 ID 起逐一嘗試同名可見 X11 視窗，排除快速重開的殘留 ID。targeted
兩案、完整 warm gate（CTest 2/2、X11 55/55）與 Ubuntu 24.04 package lifecycle
（preview 初裝 54/54、release 升級 54/54、移除／重裝後含設定視窗 55/55）均通過。
GTK4 T11–T12、GNOME X11／XWayland／native Wayland、Qt／瀏覽器及桌面登出登入仍待驗收。
2026-09-16 依「補測試一次成批完成」的要求，把剩餘 GTK4 T11–T12 與 Qt6 第一階段
X11 client 矩陣合併完成。每一類行為仍先查 macOS OSX-IMK／PlainVanilla／
TraditionalMandarin，再以 Windows TSF 交叉確認；兩者不同時不強行統一 client 語意。
GTK4 新增 committed-text 指標選取、候選替換、active-reading 編輯鍵、密碼／唯讀及
符號候選鍵盤／滑鼠流程。Qt6 以獨立 Widgets host 重跑適用的 T01–T03、T06–T12
共 25 案，包含五布局、直／橫候選、五個關聯詞設定路徑、中英／全形／繁轉簡、
兩 context、兩 App、client／Fcitx 復原、selection、密碼、唯讀多行與符號表。
Qt6 password frontend 會保留 active engine 名稱但不產生 preedit，只送 literal；
內建 read-only widget 在 focus 後不穩定發布停用狀態，因此測試 host 依 Qt 平台契約讓
`Qt::ImEnabled` query 回傳 false，Fcitx 核心即放行按鍵，沒有改 KeyKey addon。
Qt6 對 disabled `Ctrl+\` 的 active-preedit 插入順序與 `Alt+F` 是否產生 `f` 亦採
toolkit-specific golden。Qt targeted 25/25、完整 warm gate（CTest 2/2、X11 83/83）
與 Ubuntu 24.04 package lifecycle（preview 初裝 82/82、release 升級 82/82、
移除／重裝後含設定視窗 83/83）均通過。GNOME X11／XWayland／native Wayland、瀏覽器、Qt5、active-preedit 跨 App
與桌面登出登入仍待驗收。
2026-09-16 將同一組逐鍵 host 接到隔離 GNOME Shell 46／Mutter／TigerVNC X11
session，新增 existing-session runner。它核對實際 window manager、系統安裝 addon、
Classic UI panel、套件版本與 binary hash，並以 client PID 排除同名 Mutter 外框；
76 個不重啟桌面 Fcitx 的案例在 GTK3／GTK4／Qt6 全數通過，且每案都有
`keyboard-us` 負控制。其餘三個 Fcitx process-restart persistence、設定視窗
persistence 及三個 input-context recovery 案仍由 managed Xvfb／package gate 驗證；
完整登入生命週期、popup 畫面 sweep、音訊、真實外部 App、XWayland 與 native Wayland
尚未完成，不能把這筆結果寫成完整 GNOME 發布驗收。
2026-09-14 將同一 release-candidate 套件實裝到 WSL2 Ubuntu 24.04.4 後，使用者已在
WSLg XWayland 的 GTK3 gedit 經 Fcitx 5.1.7 確認中文輸入；終止候選後約一秒的視窗殘影
已對應到 `microsoft/wslg#1495` 的已知 `UnmapWindow` 顯示問題，不是 KeyKey commit 或
候選 state 延遲，故不以 engine workaround 處理，也不把此結果當作 GNOME popup 驗收。
同日新增獨立 GNOME Shell／TigerVNC X11 與 localhost noVNC 診斷桌面，沿用同一
已安裝 addon。三次「快樂」與十次「ㄎ」連打皆在約 4–7 ms 觀察到候選隱藏，
兩個候選區域的約 59 ms 畫面已清除且半秒後像素一致，英文負控制通過。這補上
隔離 GNOME X11 的局部證據；同日使用者在瀏覽器端確認問題解決、試打成功。
後續在 Windows／WSL 提供人工試打時優先使用
[固定交接流程](Source/Loaders/Linux-IME/docs/manual-desktop.md)，版控 launcher 位於
`tools/manual-desktop/`。完整 GNOME session 及 native Wayland 仍未完成，詳細量測
邊界見測試計畫。
先前的 container／WSLg 單窗測試不具備完整 GNOME session；新增的獨立 X11 診斷也
尚未完成 P0 所要求的 native Wayland／XWayland、完整桌面/App、popup 與 hosted
runner 實證。
2026-09-15 先檢查 macOS 候選控制器：滑鼠點列後會換算選字鍵，再走 PlainVanilla
`CandidateChosen` 與 TraditionalMandarin commit；接著檢查 Windows TSF 的自繪
`CandidateWindow`，目前只有鍵盤導覽、繪製、DPI 與 `WM_MOUSEACTIVATE`，沒有
`WM_LBUTTONDOWN`／`WM_LBUTTONUP` 選字處理，故兩平台實際行為不同。Linux 保留 Fcitx
原生 `CandidateWord::select` callback 的滑鼠能力，新增
`T06-X11-GTK3-CANDIDATE-MOUSE`：先鎖定 Vertical，等待 `Fcitx5 Input Window` 從
暫態 1×1／preedit-only geometry 展開成九列候選，再以 XTest 點第二列，精確 commit
「鐘」；`keyboard-us` 負控制仍為 `5j/ `。更新後 warm gate 為 CTest 2/2、X11 31/31；
Ubuntu 24.04 package lifecycle 的 preview 初裝與 release 升級各為 30/30，移除／重裝
後含設定視窗為 31/31。這是 Xvfb/classic-ui 的功能證據；GNOME X11、XWayland、native
Wayland 的 popup 位置、畫面與點擊仍須桌面驗收，不能將 F06 標為完整 parity。
同日繼續先查 macOS：TraditionalMandarin 的一般／標點候選會
`yieldToCandidateEventHandler()`，因此候選控制器允許滑鼠選取；AssociatedPhrase
只 show panel 而不 yield，橫式控制器明確設為不可點，直式 table delegate 也拒絕
selection change。再查 Windows TSF，`Ctrl+0`／`Ctrl+1` 會開符號表，但同一自繪
`CandidateWindow` 仍沒有 mouse-button 訊息。因此關聯詞滑鼠不是 macOS／Windows
對標要求，Linux 的 Fcitx 原生 callback 行為暫保留但不宣稱已驗收。符號表則新增
`T12-X11-GTK3-SYMBOL-LIST-MOUSE`，以 `Ctrl+0` 開表、XTest 點第一列，再輸入 `!`，
精確得到「，!」，`keyboard-us` 負控制只得到 `!`。完整 warm gate 為 CTest 2/2、
X11 32/32；Ubuntu 24.04 package lifecycle 的 preview 初裝與 release 升級各為
31/31，移除／重裝後含設定視窗為 32/32。這項滑鼠支援是 Linux 保留的原生額外能力；
GNOME X11、XWayland、native Wayland 的符號窗畫面／位置／點擊仍待驗收。

| 階段 | 工作 | 出場條件 |
|---|---|---|
| P0：證據與風險先行 | 先驗證 Ubuntu 24.04 GNOME + Fcitx 5 的 addon、popup、Qt 回送、三種 session 路徑與 hosted 注入；凍結 Windows TSF baseline，盤點 Ubuntu 版本與最低依賴 | 主環境真 host app 收到測試字、負控制符合預期、addon 身分正確；Ubuntu 22.04 最低 API 與 GNOME 差異有結論 |
| P1：Linux 引擎骨架與資料 | CMake、授權、native 資料工具、context 契約、Windows 五種注音布局 | 不需 GUI 可跑 CTest；真實資料 golden、Unicode／生命週期測試通過，無舊核心 link |
| P2：Windows 注音功能與 filter | 五布局逐音節連續輸入、錯誤處理、內建關聯詞、標點、Big-5、全半形；保留既有繁轉簡擴充 | F01–F02、F05、F08–F10 對應測試通過；不能到此就宣稱 Windows 全功能 parity |
| P3：完整 Ubuntu 桌面整合 | 完成 Ubuntu 24.04 + Fcitx 5 的 Windows 對標功能／視窗／App／sandbox 驗收，再完成 Ubuntu 內其他 adapter 路徑 | 主環境符合測試計畫完整驗收；F01–F02、F05–F11、F16 的 Windows 對應狀態明確；GTK/Qt 真打字與視窗流程通過；既有額外功能不拆除 |
| P4：Ubuntu 多版本與安裝 | Ubuntu 近四年矩陣原生 `.deb`、ARM64 preview、乾淨安裝／升級／移除；configure／make 原始碼入口與 source tarball | 9 個 Ubuntu 版本的套件與原始碼安裝路徑皆有正確 dependency、data、授權；source tarball 可獨立重建，安裝後從系統選到注音並打字 |
| P5：Ubuntu CI 與首版驗收 | Ubuntu workflows、release gate、sandbox／應用程式矩陣、文件 | 同一 SHA 的 Ubuntu 正式矩陣全綠且證據齊全；preview 不混入正式保證；由使用者確認可接受差異後發布 |
| P6：其他發行版 TODO | Ubuntu 完成後再做 Debian 12／13 與 Fedora 36–44 的 adapter、DEB／RPM、桌面與 CI | 各家族重新確認仍在近四年範圍，逐列升格為 active；不得用 Ubuntu ELF binary 直接重包 |

總完成條件：

- [ ] 除核定的版號 metadata 更新外，未改動禁止範圍；四個既有平台的行為與發布路徑保持不變。
- [ ] Windows 五種傳統注音布局在兩 adapter 都可用；F01–F02、F05–F11、F16 的
      Windows 對應功能／視窗逐列有驗收結果。
- [ ] Ubuntu 24.04 GNOME + Fcitx 5 通過最完整測試，X11／native Wayland／XWayland、
      所有核定功能、App／sandbox／UI、安裝升級及穩定性皆有獨立證據。
- [ ] 五布局及布局選單保留；F03／F04 與既有繁轉簡擴充不因第一階段縮減而拆除。
      候選學習／動態頻率、注音自動修正、F12–F15 不作為 Windows parity 缺口。
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
