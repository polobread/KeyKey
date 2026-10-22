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
- 好打注音的隱藏第二列補齊十二個控制項：左側為上一頁、候選 1–5，右側為候選 6–9、
  下一頁、「×」關閉候選。關閉只收起候選、恢復數字列，保留組字、已選字與未完成讀音；
  後續輸入仍接在句尾。完整與窄版分離保留原十一格候選列。
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
   保留在本機產物目錄。跨開闔時的未完成讀音、句中候選與第九／十音節邊界仍需另測；
   單一顯示器內的旋轉測試不能代替內外螢幕交接。

```sh
keykey_duo_id="YOUR_DUO_SIMULATOR_UDID"
xcodebuild test -project Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj \
  -scheme 'chichi77 KeyKey' -testPlan KeyKeyFunctional \
  -destination "platform=iOS Simulator,id=$keykey_duo_id" \
  -derivedDataPath Installer/local-builds/ios-duo \
  -only-testing:KeyKeyUITests/KeyKeyUITests/testKeyboardLayoutAtCurrentPose \
  -only-testing:KeyKeyUITests/KeyKeyUITests/testSplitSmartPagingAtCurrentPoseKeepsUnfinishedReading \
  -only-testing:KeyKeyUITests/KeyKeyUITests/testSplitSmartNineTenSyllableBoundaryAtCurrentPose \
  -only-testing:KeyKeyUITests/KeyKeyUITests/testWideSplitSmartCandidateRowHasTwelveControls \
  -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=YES
```

使用本機模擬器簽署以保留 App Group entitlement；`CODE_SIGNING_ALLOWED=NO` 的
產物能執行，但不適合用來驗證 App Group 的診斷開關傳遞。

上例為寬版內螢幕的固定姿態組合；外螢幕移除最後的十二格案例。所有案例都要求
真正啟用 extension，沒有把啟用失敗標成 skip：

- `testSplitSmartPagingAtCurrentPoseKeepsUnfinishedReading`：帶著未完成讀音開啟候選
  第二頁，核對候選目標、中央空隙與左右鍵寬；寬版使用六／六格、窄版使用五／六格。
  關閉後完成原讀音、接續句尾、刪字，重開候選回到第一頁。
- `testSplitSmartNineTenSyllableBoundaryAtCurrentPose`：九個完成音節後輸入第十個的
  聲母，切換完整／分離，再完成第十音節。檢查宿主保有十字、組字區仍只有九個
  可選音節；連續 Backspace 清除九字後，已擠出的第一字保留，仍可繼續輸入與送出。
- `testSplitSmartPagingRotationKeepsUnfinishedReading` 與
  `testSplitSmartNineTenSyllableBoundaryAndDeletion` 另外要求自動反覆切換四方向，
  包含倒置；iOS 27.1 Simulator 每次必須從 App 探針讀到符合要求的實際介面方向。
  指令有回報成功但畫面未旋轉時會 fail，不能用核心按鍵仍可點來替代旋轉驗收。
  本輪 Duo 的這兩項未通過，應由 Device Hub 實際旋轉後逐姿態跑固定姿態組合。

展開內螢幕後，另外依序執行：

- `testWideSplitSmartCandidateRowHasTwelveControls`：十二格候選的左右對齊、關閉候選後
  保留組字與句尾輸入、完整／分離切換及固定鍵盤高度。
- `testWideSplitPunctuationCompositionCellsAndDismissal`：四個標點、左六右五的組字格、
  好打注音／英文／傳統注音收鍵盤與繼續輸入。
- `testWideSplitInputModeSwitchControls`：地球鍵長按選單與點按切換、組字交接及切回。
- `testWideSplitInputModeSingleTapFromEmptyField` 與
  `testWideSplitInputModeSingleTapWithComposition`：不先開清單，分別從空欄位與「你好」組字
  直接單點地球，檢查宿主存活、組字保留與切回，避免混合兩種觸發條件。

上述寬版案例要求可用的分離鍵盤；在窄版執行會失敗，不會跳過。
分開執行可以保留收鍵盤結果，避免系統輸入法切換失敗中斷前一項驗證。

### 診斷工具

`SimulatorGeometryProbe.swift` 僅編譯於 Debug simulator，且需要 Swift 6.4 以上與
執行中的 iOS 27.1 以上。App 明確帶入 `-KeyKeyGeometryProbe` 才啟用；一般啟動會
清除診斷開關。extension 下次載入時唯讀 App Group 開關。Release 與實機不包含此工具。
`testKeyboardLayoutAtCurrentPose` 會自動設定啟動參數。

App 與 extension 各自在自己的 `Documents/geometry-probe.jsonl` 記錄 bounds、
safe area、size class、實際 interface orientation、reserved regions 與 hinge 回呼次數；
App 探針直接掛在 UIWindow 時也讀取該視窗的 scene，並記錄所屬螢幕 bounds 與 scale。
這些診斷不記錄鍵值、讀音或輸入文字。
原始紀錄、截圖與 `.xcresult` 放在 `Installer/local-builds/ios-duo/`，不提交。

Debug 輸入欄位頁另支援 `-KeyKeyFocusDefaultField`，在頁面出現後讓「一般文字」欄位
成為 first responder，保留人工測試工作階段，不依賴 XCUITest 等待倒數。此參數不會
模擬觸控，也不保證 Duo 將鍵盤連到正確顯示器；必要時仍須在 Device Hub 再點一次欄位。

```sh
xcrun simctl launch --terminate-running-process "$keykey_duo_id" \
  io.github.polobread.inputmethod.chichi77.ios \
  -KeyKeyInputFieldTest -KeyKeyGeometryProbe -KeyKeyFocusDefaultField
```

Debug simulator 另支援 `-KeyKeyNativeKeyboardOnly`：透過公開
`application(_:shouldAllowExtensionPointIdentifier:)` 拒絕 `.keyboard` extension point，
讓同一宿主僅使用系統鍵盤，畫面會明確顯示「系統鍵盤對照」。一般啟動與 Release 不受影響。
`testNativeKeyboardSwitchAtCurrentPoseWithoutExtension` 確認此標記、處理系統首次使用提示，
從清單選「繁體注音」並檢查「ㄅ」鍵，且保存每個 `XCUIScreen.screens` 的畫面；只出現
鍵盤教學提示不算完成切換。對照後須再次確認系統設定的啟用鍵盤清單，換版後若琦琦項目
遺失，先跑 `test00KeyboardOptInIsConfigured` 由設定 UI 恢復，不直接寫入系統偏好。
半開內螢幕的根視窗中央正好是折線區；Settings 導航改在右側列表內滑動，尋找「一般」
時則使用左側列表，避免把無效滑動誤認為找不到鍵盤設定。這項 opt-in 已在同一半開
測試機通過（25.039 秒，`partial-open-optin-pane-scrolling.xcresult`），且再次讀取確認
琦琦在啟用清單中。鍵盤清單優先直接點選，失敗才使用舊模擬器所需的拖曳回退；
不點擊被 sheet 擋住的宿主背景標題。寬版固定姿態案例聚焦或取消清單時，點輸入框
右側四分之一位置，避免置中 sheet 的輸入框中心也落在折線；取消後另要求系統鍵盤清單
真正消失，不能僅以另一個按鍵仍可點判定已關閉。

跨開闔的地球鍵需保留同一宿主與組字，不能每次重啟 App 後才測。Xcode 27.2 的
`UseDestinationArtifacts` 在本機實測拒絕 iOS Simulator（要求 iOS device），因此本機
一次性 `testGlobeAfterManualDuoPostureHandoff` 在同一 UI 測試內等候姿態操作，最多
30 分鐘；確認 App hinge 事件增加、回到半開後，才聚焦原欄位並自動點地球。交接後不先
切換原生鍵盤，以免重設要調查的狀態。一次性來源 `ui-tests-manual-pose-globe.swift`、
初始畫面 `manual-globe-handoff-ready.png` 與結果 `partial-open-manual-pose-globe-handoff.xcresult`
保留於本機產物目錄，未納入正常測試來源；尚待姿態操作與結果，不能列為通過。

## 驗證範圍

目前十二欄寬版分離配置的驗證：

- 完整 Swift engine 181 tests 通過；新增關閉候選回歸涵蓋已選字、翻頁、重開候選、
  句尾接續、未完成讀音，以及傳統／實體鍵盤模式不受影響。
- iOS 26.5 iPad 的 `testWideSplitSmartCandidateRowHasTwelveControls` 通過，實際驗證
  左右各六格、最後一格「×」可點、關閉後恢復數字列且文字不變、繼續輸入及
  完整／分離切換；過程中鍵盤高度固定。截圖位於本機產物
  `Installer/local-builds/ios-duo/twelve-slot-candidates-ipad.png`。
- `KeyboardPresentationTests` 三項通過，涵蓋 314–820 pt 的列幾何、設定保存，
  以及 600–820 pt 十二欄等寬、左六右五加收鍵盤位置、有／無地球鍵的底列比例。
- Duo 展開內螢幕的 `testManualSplitKeyboardPreservesCompositionAndPersists` 通過，
  包含新十二欄配置、底列比例、收鍵盤鍵可點、未完成讀音、候選、左右空白鍵、
  Backspace、英文／數字輸入與跨宿主工作階段保存。舊測試只在旋轉指令後核對按鍵，
  未確認介面方向，不能把這部分列為已完成的旋轉驗收。
- iOS 26.5 iPad 的 `testWideSplitPunctuationCompositionCellsAndDismissal` 通過；
  四個標點、組字格、好打注音／英文／傳統注音收鍵盤及保留文字均已實際操作。
  英文狀態標籤置於控制鍵後方，傳統注音在請求收鍵盤前先讓 marked-text 提交送到宿主。
- iOS 26.5 iPad 的 `testWideSplitInputModeSwitchControls` 通過：長按列出系統鍵盤清單，
  點按切換、切回琦琦後文字仍為「你好」，宿主維持前景執行。
  `testMultiCharacterAssociationsDoNotResizeKeyboard` 亦通過，候選「的名字」不改變按鍵 frame。
- Duo 仍須執行新版十二格候選列、完整收鍵盤與地球鍵流程；iPad 結果不能代替 Duo 驗收。
- 全新 `KeyKey iOS 27.1 Six Column Duo` 已通過鍵盤設定 opt-in、外螢幕的基本尺寸
  與「你好」輸入（extension 452 × 330 pt、下安全區 2 pt），以及手動完整／分離與設定保存。
  新增候選翻頁、未完成讀音、句尾接續與九／十音節／刪除流程，亦曾在外螢幕通過。
  加上實際方向斷言後，兩個嚴格旋轉案例皆 fail：XCUITest 回報方向已變，但 App 的
  `interfaceOrientation` 仍為 portrait，視窗仍為 466 × 678。因此前述流程通過只算固定
  姿態的輸入證據，不算左右橫向或倒置驗收。嚴格失敗結果為本機
  `four-direction-duo-outer-verified.xcresult`。
- 同一新 Duo 半開約 128° 時，App 為 951 × 669 pt、regular／regular、有效折線
  `(455.5, 0, 40, 669)`；extension 行程已啟動，卻仍取得 466 × 678 pt、compact／regular。
  單側輸入頁可能本來就較窄，因此另讀 scene 的 `screenBounds` 核對：App 所屬螢幕
  為 951 × 669，extension 所屬螢幕為 466 × 678，實際位於不同顯示器。聚焦畫面有
  游標、沒有軟體鍵盤，固定姿態四項全部停在啟用前，不能算十二格候選、長組字或
  地球鍵測試通過。重啟該模擬器的 extension 與輸入服務後，單項啟用仍 fail。
  同姿態冷啟動後，單項啟用仍 fail。結果為本機 `partial-open-duo-core.xcresult`、
  `partial-open-duo-keyboard-service-recovery.xcresult` 與 `partial-open-duo-cold-layout.xcresult`；
  聚焦內螢幕截圖為 `partial-open-focused-field.png`。一次性人工恢復探針等待 120 秒，
  仍未讀到軟體鍵盤（`partial-open-duo-manual-keyboard-recovery.xcresult`）。之後使用者
  確認操作 Device Hub 軟體鍵盤開關，App 仍有游標而沒有鍵盤；在 Device Hub 重新點擊
  同一個「一般文字」欄位後，鍵盤才出現。extension 隨即回報內螢幕 951 × 669 pt、
  view／window 801 × 330 pt、下安全區 18 pt、regular／regular，仍無 hinge 回呼，
  `needsInputModeSwitchKey` 仍為 false。畫面為 `partial-open-after-user-retap.png`。
  這只證明人工重新點擊恢復當次連線，不能視為已修復自動測試的顯示器歸屬問題。
  螢幕歸屬結果為 `partial-open-duo-screen-routing.xcresult`，原始資料已複製至本機
  `partial-open-app-geometry.jsonl` 與 `partial-open-extension-geometry.jsonl`，避免重新安裝
  測試產物時更換 container 而遺失。
- 新測試機在上述半開、已顯示鍵盤的狀態，使用者點按地球鍵後，宿主 App 再次 SIGABRT，
  extension 行程仍在。報告為 `chichi77 KeyKey-2026-10-23-015232.ips`，例外原因為
  `NSRangeException`、索引 58 超過陣列範圍 0–57。堆疊經過
  `UIKeyboardLayoutStar activationIndicatorView`、`UIKeyboardImpl updateLayout` 與
  `setInputModeToNextInPreferredListWithExecutionContext:`，與舊測試機兩份地球鍵報告的
  系統鍵盤路徑相同。畫面與報告已保留於本機產物目錄。這證明可在新測試機重現，
  尚不足以判定成因；Apple DTS 確認的是上述 false 屬性回報，未確認這個當機。
  宿主視窗錯配與地球鍵 SIGABRT 都仍須追查，尚未宣告修復。
- 同一半開測試機的地球鍵對照：延後到下一個 main loop 呼叫公開
  `advanceToNextInputMode()` 仍讓宿主當機，兩份報告為
  `chichi77 KeyKey-2026-10-23-022226.000.ips`／`022226.ips`，與標準 API 的堆疊相同；
  限定寬版修正 `needsInputModeSwitchKey` getter 的實驗也無效。兩種修改均已撤回，
  不能列為正式修補。標準完整鍵盤亦由自動測試重現長按清單取消後單點的當機，結果為
  `partial-open-standard-globe-direct-picker.xcresult`，報告 `023135.ips`；屬性對照結果為
  `partial-open-property-globe-probe.xcresult`，報告 `023248.ips`。
- 純系統鍵盤對照確實切到繁體注音、找到「ㄅ」鍵且宿主保持前景，通過 15.515 秒，
  結果為 `partial-open-native-only-zhuyin-switch.xcresult`。不載入 KeyKeyEngine、沒有組字
  交接或完整鍵盤版面的最小 extension，從空欄位單點地球後亦可點原生注音鍵，通過
  25.000 秒（`partial-open-minimal-globe-verified.xcresult`）。最小版加入「你好」與
  長按清單取消後，測試停在最小按鈕已不可點，未執行下一次單點；不能將它列為已重現
  同一當機。這些對照縮小調查範圍，未證明完整鍵盤正常，也未證明是所有第三方鍵盤的
  系統缺陷。一次性最小來源與測試保留於本機產物目錄，不納入正式 extension。
- 恢復有效 opt-in 後，完整原版鍵盤的純單點測試兩項均通過：空欄位 50.932 秒、
  「你好」組字 39.969 秒（`partial-open-single-tap-valid-optin.xcresult`）。輸入框的
  點擊另改至右側四分之一位置，避開半開折線後，再次通過 37.159／40.131 秒
  （`partial-open-single-tap-away-from-fold.xcresult`）。兩輪都包含切回琦琦與宿主存活，
  有組字時檢查文字保留。這是同一約 128° 固定姿態的結果，尚未驗證跨開闔後不再發生；
  先前人工與自動當機報告仍有效，不能把測試手勢修正當成產品修補。加上清單真正
  關閉斷言後的標準案例，本輪在啟用前失敗，未執行清單流程
  （`partial-open-picker-dismissal-away-from-fold.xcresult`），仍不能列為已驗收。
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
