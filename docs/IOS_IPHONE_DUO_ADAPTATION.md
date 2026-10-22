# iPhone Duo 鍵盤適配與驗證

本文件記錄 iOS 鍵盤的尺寸適配依據與驗證入口。這是 keyboard extension 的第一階段適配，
不等於完整 iOS A–K、實機或 App Store 發布驗收。

## 已採用的行為

- 以水平、垂直 size class 選擇鍵盤尺寸。Duo 內螢幕仍是 `.phone`，regular width
  採用既有 820 pt 內容上限；較窄的視窗由 Auto Layout 自然縮小。compact height 保留短版。
- 鍵盤與「設」面板逐邊遵守自己的 safe area；不把宿主 App 的右側 84 pt 套進 extension。
- 不因幾何、safe area 或 trait 變更重建引擎、重設組字或重複送字。
- 切換輸入法按鍵仍依 `needsInputModeSwitchKey` 決定，不按硬體型號猜測。
- 未收到折疊資訊時，不把寬版視窗當成半折，也不自行推算折線。預設使用完整鍵盤，
  使用者可在鍵盤「設 → 鍵盤外觀」手動選擇「完整／左右分離」。選擇保存在 extension
  自己的偏好設定，不需完整取用，也不依折疊狀態自動更換。

## 手動分離鍵盤

- 四列按鍵、組字列及候選列都分成左五格、右六格；兩半等寬，中央空隙為可用內容寬度的
  10%，最多 80 pt。這是手動外觀選擇，不表示空隙對準系統折線。
- 功能列依按鍵權重分配，每半各有一個空白鍵，兩者送出相同動作；完整模式只顯示原空白鍵。
- 在外螢幕、窄視窗與橫向短版也保留使用者選擇，中央空隙隨寬度縮小。鍵盤高度不因外觀改變。
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
本 runtime 回報 extension 的 `needsInputModeSwitchKey = false`；不據此改寫其他
runtime 或實機應有的行為，仍需另驗系統切換入口。

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

### 診斷工具

`SimulatorGeometryProbe.swift` 僅編譯於 Debug simulator，且需要 Swift 6.4 以上與
執行中的 iOS 27.1 以上。App 明確帶入 `-KeyKeyGeometryProbe` 才啟用；一般啟動會
清除診斷開關。extension 下次載入時唯讀 App Group 開關。Release 與實機不包含此工具。
`testKeyboardLayoutAtCurrentPose` 會自動設定啟動參數。

App 與 extension 各自在自己的 `Documents/geometry-probe.jsonl` 記錄 bounds、
safe area、size class、reserved regions 與 hinge 回呼次數；不記錄鍵值、讀音或輸入文字。
原始紀錄、截圖與 `.xcresult` 放在 `Installer/local-builds/ios-duo/`，不提交。

## 驗證範圍

- Swift engine：177 tests 通過，包含 regular-width phone 的尺寸選擇、分離列幾何與設定保存。
  幾何案例涵蓋 314–820 pt、有／無地球鍵與加權功能列。
- Duo extension：全開橫／直向、書本／桌面半折、外螢幕橫／直向共六種姿態的
  `testKeyboardLayoutAtCurrentPose` 全數通過，無 skip；實際按鍵可點且「你好」輸入正確。
- 同一欄位的六段跨姿態連續輸入實驗通過，最終累積六次「你好」，無漏字或重複。
- Duo 多字關聯候選「的名字」出現及選取後，按鍵 frame 保持不變的既有回歸通過。
  測試改為針對鍵盤設定列表慢速捲動，避免短視窗的慣性捲動跳過目標開關。
- iOS 17.0 iPhone 12、iOS 26.5 iPad：各兩項測試通過（鍵盤設定 opt-in、
  實際 extension 的按鍵／寬度／輸入），無 skip。這是共用版面變更的針對性回歸。
- 手動完整／分離切換：iOS 27.1 Duo 外螢幕及展開的內螢幕、iOS 26.5 iPad 的真正 extension
  通過未完成讀音、候選目標與空隙、雙空白鍵、Backspace、英文／數字輸入、旋轉及跨宿主
  工作階段的偏好保存。Duo 內螢幕驗證時的 extension 為 801 × 330 pt、下安全區 18 pt；
  本輪使用 `KeyKey iOS 27.1 Manual Split Duo`，分離鍵盤內螢幕截圖保留於本機
  `Installer/local-builds/ios-duo/manual-split-duo-inner.png`。
- iOS 17.0 iPhone 12 亦通過手動切換的組字／候選保留、雙空白鍵及偏好保存。
  以上是本功能的針對性測試，未重新宣稱完整五機 A–K 或真實 App 的驗收。
- 仍須依 [iOS Simulator 測試計畫](IOS_SIMULATOR_TEST_PLAN.md) 完成既有五機 A–K、
  真實宿主、分割畫面、VoiceOver、字型與淺深色，以及 Duo 實機驗收。

## Apple 依據

- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)
- [Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/)
- [第三方鍵盤切換鍵的 DTS 回覆](https://developer.apple.com/forums/thread/849736)
