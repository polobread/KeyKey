# iPhone Duo 鍵盤適配與驗證

本文件記錄 iOS 鍵盤的尺寸適配依據與驗證入口。這是 keyboard extension 的第一階段適配，
不等於完整 iOS A–K、實機或 App Store 發布驗收。

## 已採用的行為

- 以水平、垂直 size class 選擇鍵盤尺寸。Duo 內螢幕仍是 `.phone`，regular width
  採用既有 820 pt 內容上限；較窄的視窗由 Auto Layout 自然縮小。compact height 保留短版。
- 鍵盤與「設」面板逐邊遵守自己的 safe area；不把宿主 App 的右側 84 pt 套進 extension。
- 不因幾何、safe area 或 trait 變更重建引擎、重設組字或重複送字。
- 宿主連線後更新 `needsInputModeSwitchKey`；同一地球按鈕保留系統點按／長按處理。
  iOS 27.1 的 regular-width、regular-height 寬版 iPhone 有已確認的 false 回報問題，
  此範圍額外提供地球鍵；其他版本與尺寸仍遵循系統屬性，不依硬體名稱判斷。
- 未收到折疊資訊時，不把寬版視窗當成半折，也不自行推算折線。預設使用完整鍵盤，
  使用者可在鍵盤「設 → 鍵盤外觀」手動選擇「完整／左右分離」。選擇保存在 extension
  自己的偏好設定，不需完整取用，也不依折疊狀態自動更換。

## 手動分離鍵盤

- 可用寬度至少 600 pt、非 compact height 的分離模式採左右各六個等寬按鍵；左半每列
  新增一格，依序為「，」「。」「、」「？」。較窄或橫向短版仍用原十一鍵位。
  中央空隙為可用內容寬度的 10%，最多 80 pt；不表示空隙對準系統折線。
- 組字區維持十一格，左六、右五；第十二個位置是「▼」收鍵盤控制鍵，不是第十二個組字格。
  候選仍為每頁九個，不增加引擎音節上限。英文與傳統注音也在該位置提供收鍵盤鍵。
- 寬版底列移除原逗號／句號：左側英／數、符、設、空白採 1.5 : 1.25 : 1.25 : 2，
  右側空白、刪除、確認採 2 : 2 : 2。若需要地球鍵，左側另保留權重 1 的獨立按鍵；
  其餘按鍵維持上述相對比例。兩個空白鍵送出相同動作，完整模式只顯示原空白鍵。
- 寬版分離移除底端額外 3 pt 邊距，按鍵貼齊 extension 自己的 safe-area 底緣。
  量測到的下安全區 18 pt 仍保留；不能因系統未顯示工具列就把它當成可用按鍵區。
- 「▼」先固定組字再呼叫 `dismissKeyboard()`；地球鍵先完成輸入交接，再交由
  `handleInputModeList(from:with:)` 處理點按切換與長按選單。
- 只重新配置既有按鍵的 frame，不重建引擎；開啟設定、切換外觀與關閉設定不結束組字。
  更換輸入法或注音鍵位仍由原本引擎的切換流程處理。
- `testManualSplitKeyboardPreservesCompositionAndPersists` 要求真正啟用 extension，檢查中央空隙、
  未完成注音、開啟候選時切換、左右空白鍵、Backspace、英文／數字輸入、旋轉，
  以及新宿主工作階段的設定保存。

## 實際量測

環境：2026-10-22，Xcode 27.2 beta 3（27B5038j）、iOS 27.1（24A94232），
專用 `KeyKey iOS 27.1 iPhone Duo`。App 使用 Debug「輸入欄位測試」；這個宿主在
內螢幕以 sheet 呈現，因此 extension 的尺寸不能視為所有 App 的固定尺寸。
所有數字都是 points，safe area 順序為上、左、下、右。

| 狀態 | App window | App safe area | extension view | extension safe area |
|---|---|---|---|---|
| 外螢幕 | 466 × 678 | 0 / 0 / 34 / 84 | 452 × 330 | 0 / 0 / 2 / 0 |
| 內螢幕橫向、全開 | 951 × 669 | 0 / 0 / 34 / 84 | 801 × 330 | 0 / 0 / 18 / 0 |
| 內螢幕橫向、書本半折 | 951 × 669 | 0 / 0 / 34 / 84 | 801 × 330 | 0 / 0 / 18 / 0 |
| 內螢幕直向、全開 | 669 × 951 | 82 / 0 / 34 / 0 | 655 × 330 | 0 / 0 / 0 / 0 |
| 內螢幕直向、桌面半折 | 669 × 951 | 82 / 0 / 34 / 0 | 655 × 321 | 0 / 0 / 0 / 0 |
| 外螢幕橫向 | 678 × 466 | 0 / 84 / 34 / 0 | 528 × 155 | 0 / 0 / 18 / 0 |

`UIHingeInteraction` 在 App 收到 closed、fullyOpen、partiallyOpen，且半折時
`reservedRegions(kind: .division)` 出現有效折線。橫向的 frame 是
`(455.5, 0, 40, 669)`，旋轉後為 `(0, 455.5, 669, 40)`；全開時同區域是 inactive。

真正的 extension 在 view 與 window 均未收到 hinge 回呼，division（包括 inactive）
及 occlusion 都是空陣列。此結果來自同一裝置、同一姿態、App 可收到回呼的對照量測，
不是只在 App 測試後推定。沒有資料表示「未知」，不能當成 fullyOpen。
本 runtime 回報 extension 的 `needsInputModeSwitchKey = false`。Apple DTS 已確認
這是 Duo 的錯誤回報（FB25073949），因此在上述有限範圍補上地球鍵；不擴大套用到
其他系統版本或一般窄版 iPhone。依據見下方 DTS 回覆，仍需實機驗收。

啟動與轉場中的零尺寸、暫時 safe area、settings 面板高度不列為穩定鍵盤尺寸。
本表是量測證據，不是程式內的裝置判斷表。

## 可重現入口

1. 在 Device Hub 選擇專用 Duo，透過 Closed、Partially Open、Open、Rotate Right
   操作姿態。截圖或單獨修改 framebuffer 尺寸不能替代真正的姿態切換。單輪 frame
   驗證期間不要手動改 Device Hub 姿態，以免把真實的幾何變更誤判為候選造成的位移。
2. 首次使用先跑 `test00KeyboardOptInIsConfigured`，確認鍵盤已經由設定加入。
3. 每種姿態執行 `testKeyboardLayoutAtCurrentPose`。這個測試要求真正的 extension；
   啟用失敗會 fail，不會 skip。它驗證核心按鍵可點、左右邊界與寬度上限、
   好打注音輸入「你好」、輸入後功能列位置穩定，並保留畫面 attachment。
4. 開闔／旋轉的連續輸入另測。這次以一次性 XCUITest 搭配 Device Hub 操作，
   在同一欄位依序切換全開、書本、直向、桌面、闔上、再次展開，每段輸入「你好」，
   逐段核對完整累積文字；已通過且沒有重複或遺失。實驗原始碼與 `handoff.xcresult`
   保留在本機產物目錄。未完成讀音、句中候選與第九／十音節邊界仍需另測。

```sh
keykey_duo_id="YOUR_DUO_SIMULATOR_UDID"
xcodebuild test -project Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj \
  -scheme 'chichi77 KeyKey' -testPlan KeyKeyFunctional \
  -destination "platform=iOS Simulator,id=$keykey_duo_id" \
  -derivedDataPath Installer/local-builds/ios-duo \
  -only-testing:KeyKeyUITests/KeyKeyUITests/testKeyboardLayoutAtCurrentPose \
  -only-testing:KeyKeyUITests/KeyKeyUITests/testManualSplitKeyboardPreservesCompositionAndPersists \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES
```

使用本機模擬器簽署以保留 App Group entitlement；`CODE_SIGNING_ALLOWED=NO` 的
產物能執行，但不適合用來驗證 App Group 的診斷開關傳遞。

展開內螢幕後，另外依序執行：

- `testWideSplitPunctuationCompositionCellsAndDismissal`：四個標點、左六右五的組字格、
  好打注音／英文／傳統注音收鍵盤與繼續輸入。
- `testWideSplitInputModeSwitchControls`：地球鍵長按選單與點按切換、組字交接及切回。

這兩項要求可用的寬版分離鍵盤；在窄版執行會失敗，不會跳過。
分開執行可以保留收鍵盤結果，避免系統輸入法切換失敗中斷前一項驗證。

### 診斷工具

`SimulatorGeometryProbe.swift` 僅編譯於 Debug simulator，且需要 Swift 6.4 以上與
執行中的 iOS 27.1 以上。App 明確帶入 `-KeyKeyGeometryProbe` 才啟用；一般啟動會
清除診斷開關。extension 下次載入時唯讀 App Group 開關。Release 與實機不包含此工具。
`testKeyboardLayoutAtCurrentPose` 會自動設定啟動參數。

App 與 extension 各自在自己的 `Documents/geometry-probe.jsonl` 記錄 bounds、
safe area、size class、reserved regions 與 hinge 回呼次數；不記錄鍵值、讀音或輸入文字。
原始紀錄、截圖與 `.xcresult` 放在 `Installer/local-builds/ios-duo/`，不提交。

## 驗證範圍

目前十二欄寬版分離配置的驗證：

- `KeyboardPresentationTests` 三項通過，涵蓋 314–820 pt 的列幾何、設定保存，
  以及 600–820 pt 十二欄等寬、左六右五加收鍵盤位置、有／無地球鍵的底列比例。
- Duo 展開內螢幕的 `testManualSplitKeyboardPreservesCompositionAndPersists` 通過，
  包含新十二欄配置、底列比例、收鍵盤鍵可點、未完成讀音、候選、左右空白鍵、
  Backspace、英文／數字輸入、旋轉與跨宿主工作階段保存。
- iOS 26.5 iPad 的 `testWideSplitPunctuationCompositionCellsAndDismissal` 通過；
  四個標點、組字格、好打注音／英文／傳統注音收鍵盤及保留文字均已實際操作。
  英文狀態標籤置於控制鍵後方，傳統注音在請求收鍵盤前先讓 marked-text 提交送到宿主。
- iOS 26.5 iPad 的 `testWideSplitInputModeSwitchControls` 通過：長按列出系統鍵盤清單，
  點按切換、切回琦琦後文字仍為「你好」，宿主維持前景執行。
  `testMultiCharacterAssociationsDoNotResizeKeyboard` 亦通過，候選「的名字」不改變按鍵 frame。
- Duo 仍須重跑完整收鍵盤與地球鍵流程；iPad 結果不能代替 Duo 驗收。
- 全新 `KeyKey iOS 27.1 Six Column Duo` 已通過鍵盤設定 opt-in 與外螢幕
  `testManualSplitKeyboardPreservesCompositionAndPersists`，兩項零失敗、無 skip。
  舊測試機手動切換地球鍵時，宿主 App 出現 SIGABRT；例外堆疊為
  `__NSArrayM getObjects:range:` → `UIKeyboardLayoutStar activationIndicatorView`，
  其後亦出現鍵盤未顯示。這項當機尚未宣告修復，仍需乾淨 Duo 內螢幕驗證。
- 本輪一般 iPhone 回歸尚未完成；不能沿用前版結果宣稱通過。

前版 `d498b2f0`／`771c31cb` 已驗證六種 Duo 姿態、同欄位跨姿態連續輸入、
iOS 17.0 iPhone 12 與 iOS 26.5 iPad，以及完整／十一欄分離切換。
前版完整 Swift engine 為 177 tests 通過。這些只作適配基線，不能代替本版新增配置驗證。
十二欄初次版面檢查使用 `KeyKey iOS 27.1 Manual Split Duo`；截圖保留於本機
`Installer/local-builds/ios-duo/six-column-duo-initial.png`。

仍須依 [iOS Simulator 測試計畫](IOS_SIMULATOR_TEST_PLAN.md) 完成既有五機 A–K、
真實宿主、分割畫面、VoiceOver、字型與淺深色，以及 Duo 實機驗收。

## Apple 依據

- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)
- [Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/)
- [第三方鍵盤切換鍵的 DTS 回覆](https://developer.apple.com/forums/thread/849736)
