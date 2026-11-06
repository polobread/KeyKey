# iOS App 實體鍵盤編輯器行為調查

## 範圍與結論

本輪對照 Android 已修正的選字、Delete、Enter、旋轉組字同步與候選視窗生命週期。
調查來源為 `a4b7fa485f3fab9511ce4836d0b81fd98b55e0ac`，舊 iOS 對照為 Rust 遷移前的
`185f5dcde4722100879055fdd8285ad9eee2088d`。未修改產品碼或新增／調整測試，未操作實體 iPhone。

確認兩項接合問題：實體候選目標由舊版右側變成左側，以及原本就缺少的 Forward Delete 入口。
其他 Android 問題不能直接套用到 iOS。既有測試通過不表示下列缺口已驗收。

此處的實體編輯器只指容器 App 前景的編輯功能；iOS 鍵盤 extension 不接收一般 USB／藍牙鍵盤事件。

## 候選方向：遷移後的回歸

[GuanyinmaInputEngine.swift](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/GuanyinmaInputEngine.swift)
的 `smartConfiguration()` 在實體模式設 `candidate_cursor_at_end = true`，`openSmartCandidates()` 又明確取
`max(0, readingCursor - 1)`。兩處與 Android 本輪修正前相同，將「你｜好」的候選目標落在左側「你」。

舊 iOS `BopomofoEngine.showHardwareSmartCandidates()` 使用 `min(smartCursor, smartReadings.count - 1)`，
在句中取右側、句尾取最後一字；選字後將游標放在所選範圍末端。macOS 現行預設也是右側規則。

預期重現流程為「你好」→左移成「你｜好」→下鍵開候選→選「郝」→輸入「ㄇㄚ」，結果應為「你郝媽」。
本輪以現行映射及舊版來源確認回歸，尚未新增專用 iOS runtime 案例來記錄這條完整流程。
修正時須同時處理方向選項及明確索引，保留觸控的選字後回句尾政策。

其他實體 SmartOptions 的上限 10、`shift_at_limit = false`、`selection_returns_to_end = false` 已正確映射。
未傳的 Bigram、Esc 全清與 Shift 強制大寫，在 Rust 都有 `true / false / false` 預設；未找到「Rust 功能缺預設值」的證據。

## Forward Delete：既有功能缺口

[HardwareKeyboardKey.swift](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/HardwareKeyboardKey.swift)
沒有 HID `0x4C` 的映射，enum 及
[InputEngine](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/InputEngine.swift)
也沒有右側刪除操作。
[編輯器](../Source/Loaders/iOS-Keyboard/ContainerApp/HardwareKeyboardEditorViewController.swift)
對未映射按鍵回傳未處理；輸出 UITextView 不可編輯／選取，沒有另一條原生文字刪除路徑。

舊 iOS 同樣未接此鍵，因此這是既有缺口，不是 Rust 遷移新增。
預期在「你｜好」按 Forward Delete 後得到「你」，繼續輸入不恢復已刪字。
若補實作，組字內應接 Rust 既有 Delete 語意，已確認文字則由 App 的 `committedText` 與插入游標右刪一個字素；
候選開啟及未完成讀音依核心既有規則處理。不能只補 HID 映射而漏掉已確認文字的刪除。

## 不可直接套用 Android 結論的項目

- 編輯器第一 responder 是非文字 `HardwareKeyboardCaptureView`。輸出由 `committedText` 前段、引擎組字、後段重新渲染，
  不使用 Android InputConnection／composing span；旋轉只重排既有 view，沒有相同的標記範圍遺失根因。
- 候選是固定九個 UIButton，沒有獨立 UIWindow／浮窗 owner；未找到 Android 重建鍵盤後殘留多窗的同型路徑。
- Enter Down 由 controller 處理；Up 除 Backspace 外仍傳 super，但這裡沒有原生文字欄位的下一欄導航。
  也未找到 UIKeyCommand／GCKeyboard 第二條送字路徑，不能僅以 Up 透傳判定有重複送字。
- 持續按住 Enter／選字數字是否會由 UIKit 重送 pressesBegan 尚未量測，只列待驗證；未當成產品缺陷。

## 已執行的既有驗證

Swift／真 Rust C ABI 的 `GuanyinmaIntegrationTests` 與 `HardwareKeyboardKeyTests` 共 **28 項通過**。
這是 macOS host Swift package 證據，不能代替 iOS runtime 或實體鍵盤傳輸驗收。

在新建隔離的 **iPhone 16 Plus／iOS 26.5（23F77）** 模擬器執行以下既有 UI 案例，**4 項通過、0 失敗、0 略過**：

- `testSmokeHardwareKeyboardEditorOpens`
- `testSharedSpaceSelectionAndIndependentDownArrow`
- `testHardwareEditorModeWidthAndFunctionButtonsKeepSmartText`
- `testHardwareKeyboardEditorLandscapeColumns`

它們涵蓋基本送鍵、單字候選與空白政策、模式／全半形／功能鍵保留文字及橫式候選版面。
未涵蓋句中候選方向、Forward Delete、帶組字跨旋轉與長按 Enter，不能以通過數字掩蓋缺少的案例。
本輪尚未新增這些測試，也未宣稱上述未覆蓋行為通過。

## 待核准的修改範圍與證據

已向使用者提出兩項具體修正確認：恢復實體候選右側規則、補組字與已確認文字的 Forward Delete，
並加入對應回歸與模擬器驗證。依 AGENTS 的新問題規則，取得明確同意後才修改產品與相關測試。

本機證據保存在 `Installer/local-builds/ios-physical-review-20261106/`：
`investigation.json` 保存來源與內容雜湊，`existing-swift-tests.log` 保存 host 測試結果，
`existing-host-tests.xcresult`、`ui-summary.json`、`ui-tests.json` 保存 iOS 模擬器結果。
