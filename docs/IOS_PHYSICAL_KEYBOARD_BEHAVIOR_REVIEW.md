# iOS App 實體鍵盤編輯器行為與驗證

## 範圍與結論

本輪先對照 Android 的候選、Delete、Enter、旋轉組字及候選視窗生命週期，再經使用者明確同意，
修正 iOS App 的右側候選規則與 Forward Delete。產品修改只在 `codex/ios-iphone-duo-adaptation`。
調查基底為 `a4b7fa485f3fab9511ce4836d0b81fd98b55e0ac`，調查報告提交為 `d27340b57`；
舊 iOS 對照為 Rust 遷移前的 `185f5dcde4722100879055fdd8285ad9eee2088d`。

此處只指容器 App 前景的實體鍵盤編輯器；iOS 鍵盤 extension 不接收一般 USB／藍牙鍵盤事件。
本輪使用隔離的 iPhone 16 Plus／iOS 26.5（23F77）Simulator，未操作或重新安裝實體 iPhone。

## 右側候選：恢復遷移前規則

遷移後 `smartConfiguration()` 的實體 `candidate_cursor_at_end = true`，搭配
`openSmartCandidates()` 的 `max(0, readingCursor - 1)`，讓「你｜好」的候選目標變成左側「你」。
舊 iOS `BopomofoEngine.showHardwareSmartCandidates()` 與 macOS 預設均以右側為目標，句尾才取最後一字。

[GuanyinmaInputEngine.swift](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/GuanyinmaInputEngine.swift)
現在固定 `candidate_cursor_at_end = false`，明確索引改為 `min(readingCursor, readings.count - 1)`。
實體選字後仍停在所選詞末端，可以接續插入；觸控選字後回句尾的政策保留。

回歸流程為「你好」→左移至「你｜好」→下鍵開候選→數字選「郝」→旋轉直橫式→開關操作說明→輸入「ㄇㄚ」→Enter，
預期並核對「你郝媽」；下一次普通 Enter 只加入一個換行。
候選可以先列涵蓋游標的長詞，測試會找「郝」的實際可見編號，不假設它固定是第二項，也不改模型排序。

其他實體 SmartOptions 的上限 10、`shift_at_limit = false`、`selection_returns_to_end = false` 已正確映射。
未傳的 Bigram、Esc 全清與 Shift 強制大寫，在 Rust 都有 `true / false / false` 預設；未找到缺少預設值的證據。

## Forward Delete：補齊既有缺口

舊 iOS 與遷移後原先都沒有 HID `0x4C` 入口，屬既有功能缺口。
[HardwareKeyboardKey.swift](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/HardwareKeyboardKey.swift)
現在將它映射成 `forwardDelete`，由 `InputEngine.deleteForward()` 經 wrapper 送 Rust 既有 Delete 語意。

[編輯器](../Source/Loaders/iOS-Keyboard/ContainerApp/HardwareKeyboardEditorViewController.swift)
依按鍵前的狀態分配責任：有組字時交由核心修改；沒有組字時，在 App 自有的 `committedText` 游標右側刪一個 Swift Character。
刪空最後一個組字不會在同一次按鍵中繼續刪除後方已確認文字。候選開啟或有未完成讀音時沿用核心既有拒絕規則，
不跳過組字直接刪 App 文字。已確認文字按完整字素刪除，包含變體選擇符 Emoji。

Forward Delete 和 Backspace 各自追蹤按住狀態與重複刪除計時器；避免系統重複 Down 與計時器同時刪除。
Up、Cancelled、失去 responder、離開畫面、App 進入背景及鍵盤斷線都會停止對應計時器。

## 驗證方式與工具界線

Swift host 的 `GuanyinmaIntegrationTests`、`HardwareKeyboardKeyTests`、`BackspaceRepeaterTests`
使用真 Rust C ABI，**33 項、3 個 suite 通過**。涵蓋句首／句中／句尾候選與刪除、選字後續輸入、
刪空最後讀音、未完成讀音／開啟候選的保留、HID 映射及共用長按節奏。
這是 macOS host 證據，不能代替 iOS runtime。

iPhone 16 Plus／iOS 26.5 的最終 UI 回歸為 **8 項通過、0 失敗、0 略過**：

| 案例 | 核對內容 |
|---|---|
| `testHardwareEditorRightHandSelectionSurvivesRotationAndRefocus` | 右側候選、候選開啟時 Delete、數字選字、旋轉／說明視窗返回後續打、組字 Enter 與普通換行 |
| `testHardwareEditorForwardDeleteKeepsCompositionAndRemovesLastReading` | 句中右刪後接續、刪空最後讀音不復活、不誤刪已確認後文、未完成讀音保留 |
| `testHardwareEditorForwardDeleteRemovesCommittedGraphemes` | 英文右刪、句尾不誤刪、`✌️` 完整字素、刪後游標位置 |
| `testHardwareEditorModeWidthAndFunctionButtonsKeepSmartText` | 模式／全半形／功能鍵保留文字 |
| `testHardwareKeyboardEditorLandscapeColumns` | 橫式候選與編輯器版面 |
| `testSharedSpaceSelectionAndIndependentDownArrow` | 共用空白政策與獨立下鍵開候選 |
| `testSmokeHardwareKeyboardEditorOpens` | 原有編輯器送鍵與候選冒煙 |
| `testTableMethodsInHardwareEditorAndSingleRowControls` | 倉頡／簡易與既有候選操作 |

App 與 extension 均以相同來源建置成功；本輪不更動 Rust 或模型。
嵌入的 `KeyKey.db` 與共用來源 SHA-256 相同：
`cbe2e1018842797610b71a4f4b479332aa4508b32df629dd0ad7fa8075ee6c7c`。

在此 iOS 26.5 Simulator，XCTest 的字串 Forward Delete／Return API 雖可呼叫，實際不會到達非文字 responder；
暫時事件追蹤確認一般字母與方向鍵有到達、這兩鍵沒有到達，產品診斷碼已移除。
因此新增 host-only 的 [SimulatorHIDSender.m](../Source/Loaders/iOS-Keyboard/Tests/SimulatorHIDSender.m)
與 [with-simulator-hid.py](../Source/Loaders/iOS-Keyboard/Tests/with-simulator-hid.py)，
用目前 Xcode 的 SimulatorKit 向精確選定的已開機 SimDevice 送完整按下／放開，Delete 為 HID `0x4C`、Return 為 `0x28`。

helper 不發 macOS 全域鍵盤事件、不選其他 Simulator 或手機；原生工具、私有 API 與 loopback 只供 host 測試，
不連入 App／extension。傳輸成功仍須搭配 UI 文字結果，不能只看 transport ACK。
`run-simulator-tests.sh` 的 functional／functional-host 模式會準備 bridge，且不接受略過；
直接 Xcode 未準備 bridge 時，三項依賴它的測試明確略過。用法見 [iOS README](../Source/Loaders/iOS-Keyboard/README.md#ui-測試分流)。

## 與 Android 不同的項目與未涵蓋範圍

- App 使用非文字 `HardwareKeyboardCaptureView` 接事件，以 `committedText` 前段、引擎組字及後段重畫 UITextView；
  不用 Android InputConnection／composing span，旋轉只重排既有 view。
- 候選是固定九個 UIButton，沒有獨立 UIWindow／浮窗 owner；未找到 Android 殘留多浮窗的同型路徑。
- Enter 沒有第二條 UIKeyCommand／GCKeyboard 送字路徑，輸出 view 不可編輯／選取，不會由原生文字欄位導航下一欄。
  本輪以真 HID 按放確認組字與普通換行，未把 Android 的 Up 修正直接套用。
- 未驗收真正 USB／藍牙傳輸、實體長按 Enter／選字數字，亦不把 Simulator 結果當成 extension 或實體 iPhone 驗收。

## 本機證據

主要 checkout 的 `Installer/local-builds/ios-physical-review-20261106/` 保存建置與測試產物，不提交：

- `investigation.json`、`existing-swift-tests.log`、`existing-host-tests.xcresult`：修正前的來源與既有測試。
- `approved-engine-tests.log`：33 項聚焦 host 測試。
- `final-host-tests.xcresult`、`final-host-tests.log`、`final-ui-summary.json`、`final-ui-tests.json`：最終 8 項 UI 回歸。
- `final-verification.json`：來源檔、實際 App debug dylib／嵌入 DB 雜湊與結果對照。
- `final-hid/simulator-hid-events.log`：精確裝置與每次完整按放事件。

初次擴充 UI 的失敗來自固定候選順位假設及 XCTest 特殊鍵未送達，已修正測試方法；
未以異常紀錄自行新增產品修正，也未改字庫、詞頻或候選排序。
