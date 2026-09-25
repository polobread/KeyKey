# 傳統注音五平台處理檢查

對照本機 `v1.3.0` 原始碼；Linux 基準為 `2b5015e`。先追 macOS IMK、PlainVanilla 與 `OVIMTraditionalMandarin`，再核對 Windows TSF、iOS Swift 及 Android Java。這是原始碼對照加 Linux 整合測試，不代表另外四平台已經實機驗證。

## 確認的問題與修正

| 優先度 | 原本問題／觸發條件 | Linux 本輪處理與回歸 |
| --- | --- | --- |
| P1 | 傳統注音有讀音或候選時切換中英、輸入法、鍵盤配置／好打模式，`commitAndReset` 只處理好打而丟掉傳統內容 | 統一結束入口。有候選時送出目前頁面的反白字；未查詢或查無候選的讀音保留原文。聯想詞不自動選取；重複結束不重複送出；Esc 取消後不復活。沿用每個 context 的原引擎副本，先結束再換配置。 |
| P1 | 長按 Ctrl+\ 切換中英時，`toggleChineseMode` 清理狀態把剛設的按住旗標清掉；重複事件再次切換，可能留下反斜線候選 | 改成先完成切換，再記住實體按鍵仍按下；等放開才解除。以既有 T09 的一秒長按、先放 Ctrl 再放反斜線及後續輸入流程覆蓋 GTK3／GTK4／Qt6；GTK3／GTK4 得到 `x中文`，Qt 的 Alt+F 依宿主原有規則插入 f，預期 `xff中f文`。 |
| P2 | 橫排候選的左右鍵仍翻頁、上下鍵仍移反白 | Fcitx adapter 的方向轉換適用所有候選面板；橫排左右移反白、上下翻頁。直排、Home／End、PageUp／PageDown 保留。 |
| P2 | Space／Enter 查詢單一候選時還要求再選一次，聲調鍵卻直接送出 | 所有讀音完成方式均直接送出唯一候選。使用縮小字表隔離條件；目前完整字表的一聲多為多候選，不能聲稱這個 fixture 是實際「媽」的全部候選。 |
| P2 | 漏查一般標點及排列專屬標點，例如 `[` 沒有輸出 `「`、候選後 `!` 漏接續 | 先查 `_punctuation_<layout>_<key>` 再查通用表；注音鍵仍優先。完成候選後先送出反白字，再開標點候選／送出單一符號。未完成讀音時攔截標點並提示。 |
| P2 | 標點候選開啟時再次按 Ctrl 標點會覆蓋原候選 | 保留原候選並提示；沒有定義的 Ctrl／Alt／Super 快捷鍵交回宿主。候選中的 `<`／`>` 對齊桌面模組的翻頁快捷鍵。 |
| P2 | Fcitx 正規化的大寫字母被當成小寫注音，Shift 字母又可能穿過現有組字 | Shift／大寫／CapsLock 字母按字面輸出；有反白候選先確認，未完成讀音原文先送出，避免隱藏或丟字。另傳遞 CapsLock，涵蓋 CapsLock+Shift 的小寫事件。 |
| P2 | Big5 限制只過濾注音查詢、漏掉符號候選 | 符號也套用 Big5-HKSCS 過濾；剩一個直接送出、沒有結果則提示。使用含非 Big5 字元的獨立 fixture，不更動共用資料表。 |

新測試的具體情境包含：`ㄓㄨㄥ → 空白 → Down → !` 輸出「鐘！」；`{ → Down → Ctrl+, → a86 → 1` 保留符號選擇再輸出「《麻」；第二頁反白後切換輸入法送出「妐」；候選中切換好打再輸入得到「鐘你」。大小寫包含 Shift、CapsLock、CapsLock+Shift，以及未完成注音和已開候選兩種狀態。

## 行為對照

| 操作 | macOS | Windows | iOS | Android | Linux 修正後 |
| --- | --- | --- | --- | --- | --- |
| 音節完成 | 聲調／空白／Enter 查詢；唯一候選直接確認 | 同共用模組 | `query` 唯一候選直接確認 | `query` 唯一候選直接確認 | 三種完成方式一致 |
| 已有候選再打下一音 | 確認反白候選再開始下一音 | 同共用模組 | `commitFirstCandidateIfNeeded` 取目前頁第一字 | 同 iOS | 確認反白字；數字仍先當選字鍵 |
| Enter／數字／點候選 | 直接確認該候選 | 同共用模組與 TSF 面板 | 選擇候選；觸控直接點字 | 選擇候選；觸控直接點字 | 確認候選，不套用好打「選完仍組句」的規則 |
| Backspace／Esc | Backspace 關候選並刪一個讀音成分；Esc 清讀音 | 同模組 | 清候選並刪讀音；Esc 清組字 | 同 iOS | 保留這套傳統流程；符號候選 Backspace 只取消符號 |
| 候選方向／首尾 | 沿面板軸移反白、垂直於面板軸翻頁；Home／End 全列表首尾 | 同 PlainVanilla | App 實體編輯器自行分派；觸控點字／翻頁 | 浮動候選面板自行分派；觸控點字／翻頁 | 橫／直排分別處理，Home／End 跨頁 |
| 一般符號 | 共用表、排列覆寫、候選後可接符號；`< >` 可翻頁 | 同模組（Ctrl 路徑另見下列差異） | 觸控符號頁與少數實體快捷鍵 | 觸控符號頁與實體快捷鍵 | 採桌面表格及候選接續 |
| 應用程式快捷鍵 | 模組及面板有攔截條件 | TSF `wantsKey` 在 Ctrl／Alt 時先交回宿主 | 容器 App 在 Command／Option 等先交回 | service 在 Ctrl／Alt／Meta 時先交回，輸入法快捷鍵優先 | 保留既有宿主快捷鍵；已定義 Ctrl 標點由輸入法處理 |
| 中英／輸入法切換 | IMK 提交可見 combined buffer 再清理 | TSF `EndComposition(false)` 保留文字 | 傳統 `finishCompositionForModeSwitch` 清除；input handoff 特例僅限觸控好打 | 傳統模式回傳 discard；handoff 特例僅限觸控好打 | 確認反白候選或保留原讀音，聯想候選不送出 |
| 聯想詞 | 先送出單字；Shift+數字選後綴；普通新讀音關閉聯想 | 同模組 | 送出單字再顯示後綴；觸控點選 | 同 iOS；硬體 Shift+數字 | 維持既有後綴、分類、停用和隱私欄位處理 |
| 字集與繁簡 | 查詢後過濾；輸出過濾器處理繁簡 | 共用模組，encoding service 另實作 | 非同一套可配置桌面過濾器 | 非同一套可配置桌面過濾器 | 注音／符號均過濾 Big5，確認／切換均經輸出轉換 |

## 明確保留的差異

- Linux 傳統候選開啟後，底線仍顯示注音；macOS／Windows 的共用模組將讀音顯示換成第一個候選。Linux 切換時選擇目前反白字，所以不宣稱與桌面顯示文字完全相同。
- Shift 英文遇到未完成讀音，macOS 共用模組可清除讀音；Linux 本輪選擇先保留原文再輸出英文字母。例如 `ㄓ + A` 成為 `ㄓA`。手機 traditional 引擎先 lower-case 再判斷注音鍵，也不是這套桌面英文行為。
- Linux 固定九個數字候選鍵，與 iOS／Android 相近；macOS／Windows 傳統注音 Standard／ETen／拼音預設九鍵，許氏與倚天 26 鍵預設八個字母鍵，另可自訂。Linux 尚未提供這些選字鍵配置；本輪沒有改掉 Linux 既有數字選字契約。
- Linux 符號候選 Backspace 只取消符號，不連帶刪掉宿主上一字；macOS 模組的無讀音 Backspace 可能回傳未處理。這是保護宿主文字的既有差異。
- 分頁採 Linux 既有循環方式；桌面 PlainVanilla 可配置是否循環。詞庫排序、觸控符號頁與候選窗外觀不視為五平台完全相同。
- 原生 Wayland、任意第三方 App、未映射的 keypad／非 ASCII 直接文字事件，不能由 ASCII 引擎測試推定已完整驗證。Fcitx client reset 和 IM deactivation 是不同事件；reset 保持清理而不強制再送字，避免宿主已確認 preedit 後重複插入。

## 驗證與入口

- 引擎 CTest 包含所有注音排列、全字表讀音 round-trip、編輯、候選、聯想、字集／繁簡、倉頡／簡易與好打注音；新增 singleton、標點、切換、大小寫及字集回歸。
- 新增 `T01-X11-{GTK3,GTK4,QT6}-BOPOMOFO-TRADITIONAL-{PUNCTUATION,LITERAL,SWITCH,CONFIG}`，12 項已在隔離 Ubuntu 24.04 Xvfb／D-Bus 環境通過，並以相同鍵序的 keyboard-us 作負對照。
- 最終 fix6 套件的同一 addon 已完成 88/88 個 X11 回歸（四批彙整），包含 12 個新傳統案例及 16 個好打案例；另核對跨欄位、跨 App、敏感／唯讀與符號操作。測試工具的排列隔離與標點預期修正、一次 GTK4 負對照重跑詳記於套件 `VERIFICATION.md`。
- 每次 E2E 必須核對實際載入的 addon 路徑。套件版、安裝版與原始碼分別記錄；完整驗收清單及結果放在套件旁的 `VERIFICATION.md`、`e2e-result.json`。

參考程式：

- [macOS IMK](../../OSX-IMK/OpenVanillaController.mm)：`deactivateServer`、`commitComposition`。
- [共用傳統模組](../../../ModulePackages/OVIMMandarin/OVIMTraditionalMandarin.cpp)：`queryAndCompose`、`handleKey`、`candidateNonPanelKeyReceived`、`findPunctuationKey`；同目錄 `OVAFAssociatedPhrase.cpp`。
- [PlainVanilla 面板](../../../Frameworks/PlainVanilla/Headers/PVCandidate.h)、[事件分派](../../../Frameworks/PlainVanilla/Headers/PVLoaderSystem.h)。
- [Windows engine](../../Windows-TSF/KeyKeyEngine.cpp)：`wantsKey`、`handleKey`；同目錄 `TextService.cpp` 的 `endComposition`。
- [iOS engine](../../iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/BopomofoEngine.swift)：`character`、`query`、`finishCompositionForModeSwitch`；`ContainerApp/HardwareKeyboardEditorViewController.swift` 的按鍵分派。
- [Android engine](../../Android-IME/app/src/main/java/tw/chichi77/keykey/android/BopomofoEngine.java)：同名函式及 `BopomofoImeService.java` 的 `onKeyDown`。
- Linux：`engine/src/engine.cpp`、`adapters/fcitx5/fcitx5_engine.cpp`、`tests/engine_tests.cpp`、`ci/run-x11-e2e-session.sh`。
