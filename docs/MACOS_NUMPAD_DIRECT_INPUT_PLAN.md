# macOS 數字鍵區直接輸入計畫

狀態：未實作，待未來開發。本次只記錄查證結果、預定行為與驗證範圍，不修改輸入法。
程式查證基準為 `68edbfac`；原始碼、隔離測試、安裝產物及實際宿主行為須分開驗證。

## 目標

右側數字鍵區獨立用來輸入數字，不當候選選字鍵，也不當注音鍵。
主鍵盤上排數字維持目前的注音、候選選字及快捷鍵用途。

有組字、未完成注音或開啟候選窗時，先保留目前顯示的文字及讀音，
再輸出右側數字或運算符；不得誤選候選、丟失讀音、重複送字或殘留舊候選。

## 目前查證

| 平台 | 原始碼行為 | 證據界線 |
| --- | --- | --- |
| Windows TSF | 數字鍵盤文字先於共用引擎處理；Num Lock 開啟的 `0–9`、小數點，以及 `+ - * /` 直接輸出。有組字時先合併可見文字與未完成讀音，不進候選選字路徑。 | 已有四種中文方法的回歸案例；本次只讀程式，未在 Windows 重跑或驗收已安裝版本。 |
| macOS IMK | 依實體鍵碼辨識右側 `0–9`、小數點與 `+ - * / =`，加上共用引擎的 `NumLock` 標記，但仍交給候選／模組處理。 | 共用候選層比對不區分該標記；隔離重現帶標記的右側 `1` 仍會選第一個候選。不是完整 macOS 宿主驗收。 |

Windows 的 `NumLock` 引擎標記只套在數字鍵盤事件，不把全域 Num Lock 狀態套到主鍵盤。
macOS 的同名標記在此處代表數字鍵區來源，不能直接理解成 Windows 的 Num Lock 開關狀態。

目前 macOS 在候選窗之外也因模組而異：傳統注音有未完成讀音時可能吃鍵並提示錯誤；
倉頡／簡易的數字鍵盤路徑可能清除字根。只加來源標記不足以完成直接輸入目標。

相關入口：

- [Windows 引擎分流與字元對映](../Source/Loaders/Windows-TSF/KeyKeyEngine.cpp)
- [Windows TSF 前端](../Source/Loaders/Windows-TSF/TextService.cpp)
- [Windows 數字鍵盤回歸](../Source/Loaders/Windows-TSF/EngineSmokeTest.cpp) 的 `TestNumpad`
- [macOS IMK 事件入口](../Source/Loaders/OSX-IMK/OpenVanillaController.mm) 的 `numKeys` 與 `handleEvent:client:`
- [共用按鍵比對](../Source/Frameworks/OpenVanilla/Headers/OVKey.h) 的 `operator==`
- [共用候選處理](../Source/Frameworks/PlainVanilla/Headers/PVCandidate.h) 的 `handleKeyEvent`

## 預定實作範圍

1. 在 macOS IMK frontend 依實體鍵碼及事件字元辨識右側數字鍵區，於進入候選與模組前分流。
   不依賴全域 `numericPad` 旗標辨識所有按鍵，避免將方向鍵等非數字鍵混入。
2. 分流只處理實際產生可列印數字／運算符的事件，涵蓋 `0–9`、小數點、`+ - * / =`。
   Ctrl／Option／Command 組合保留 App 快捷鍵；Shift 組合及外接鍵盤 Num Lock 關閉時，
   依實際事件保留導覽功能，不把非文字事件強制轉成數字。
3. 有組字時沿用 macOS 的文字保留流程，包含游標處未完成讀音及原輸出轉換設定。
   保留文字成功後才清理引擎、候選與暫時 UI，再輸出數字；宿主拒絕送字時不得遺失原輸入。
4. 數字輸出須正確成對處理 key-down／key-up、長按 repeat 與宿主重複回呼，並符合既有全半形設定。
5. 數字鍵區 Enter 維持目前確認語意；Num Lock／Clear 不當成數字。不連帶修改主鍵盤選字、
   Shift 中英切換、四種中文輸入法的核心規則或其他平台。

優先只改 macOS frontend，不全域修改 `OVKey::operator==` 或共用候選比對，
避免影響其他 frontend、既有修飾鍵及候選行為。詞庫、模型、版號及發布流程不在本計畫範圍內。

## 未來驗證與採用條件

- 隔離回歸須涵蓋真實 IMK 分流方法與候選路徑：右側數字輸出；主鍵盤同數字仍照常選字。
- 四種中文輸入法分別測空組字、未完成注音／字根、已完成組字、句中游標、候選及翻頁後候選。
  關聯詞候選與獨立英文模式另列案例，不能只從好打注音推定其他方法。
- 檢查十個數字、小數點與運算符，以及全半形、長按、組合鍵、Shift 模式切換和後續中文接續。
- 實際 Mac 數字鍵盤及 Windows 外接鍵盤分別驗證，記錄系統送達的鍵碼與字元；
  Num Lock／Clear、Num Lock 關閉導覽及小數點布局不可只由虛擬事件推定。
- macOS 建置與封裝後，在 TextEdit、ChatGPT 與瀏覽器文字框驗證：不誤選候選、無漏字／重字、
  未完成讀音保留、候選清理與後續輸入正常。原始碼／隔離回歸不能代替已安裝版本的宿主驗收。

文件階段僅檢查 diff 與連結，不執行建置、不改安裝內容。未來實作須另開工作分支，
保留可還原版本並經使用者 review 的 PR 合併；本文件不代表功能已完成或發布。
