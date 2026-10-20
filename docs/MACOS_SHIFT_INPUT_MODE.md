# macOS 中英模式與 Shift 切換

macOS 1.3.3（未發布）新增獨立英文模式。好打注音、傳統注音、倉頡、簡易仍是四種中文輸入法；
英文模式不改寫選取的中文輸入法。Shift 可在英文與先前選取的中文輸入法之間切換。
英文模式的普通輸入交由目前 App 處理，輸入法選單亦可選英文或任一中文輸入法。

## 一般設定

- 「單按 Shift 切換中英文」預設開啟，左右 Shift 均可；設定鍵 `ToggleInputModeWithShift` 為字串 `true`／`false`。
- 「啟動時預設輸入模式」可選中文／英文，預設中文；設定鍵 `DefaultInputMode` 為 `Chinese`／`English`。

兩項與四種中文輸入法共用同一份 `io.github.polobread.chichi77.plist`。
缺少設定鍵的舊設定採用上述預設值，已保存的選擇保持不變。
啟動模式在 IMK 程序首次啟用時讀取一次；手動 Shift 或選單切換不改寫它。
變更啟動模式於下次啟動程序時生效；只切換 App／輸入法不保證會重啟程序。
關閉 Shift 功能不強制改變目前模式，仍可透過輸入法選單選擇中英文。

## 輸入行為

300 ms 內按下／放開同側 Shift、且未搭配其他鍵時切換一次。部分宿主會重複送達每個修飾鍵事件，
同側同狀態的重複事件不重新計時、不重新啟用已取消的手勢，也不多切換一次。
長按、其他修飾鍵、字母、方向鍵與左右 Shift 混用不觸發；啟用／停用 context 時清除舊手勢。
修飾鍵按下／放開均原樣放行，避免宿主保留 Shift 按住狀態。

切換模式或從選單選取中文輸入法前，將目前組字及游標處未完成讀音經原輸出設定送出，
成功後才清除引擎與候選，再改模式。宿主拒絕插入時保留原組字與模式；重入的送字操作不重複執行。
英文模式沿用系統鍵盤的 Shift 大小寫、Caps Lock 與 App 快捷鍵。

## 驗證入口

```sh
python3 Source/Loaders/OSX-IMK/Tests/run-input-mode-tests.py
python3 Source/Loaders/OSX-IMK/Tests/run-general-input-mode-tests.py
(cd Source && xcodebuild -project Takao.xcodeproj -target 'Takao (Loader OSX-IMK)' \
  -configuration Release -xcconfig Takao-macOS.xcconfig build)
```

隔離回歸檢查實際 controller 方法、buffer、一般設定保存與三語系既有 nib 幾何，使用暫存 profile，
不接觸已安裝 IMK 或使用者設定。這些測試不能代替實際文字宿主驗收。

實機須在 ChatGPT、TextEdit 與瀏覽器測四種中文輸入法與英文互切，涵蓋空組字、候選、未完成注音、
句中游標、Shift 大寫／選取、長按、左右混用、切換 App、輸入法選單及兩個設定的保存與啟動效果。
本機測試包與原已安裝 App 的還原包保存在 `Installer/local-builds/`，不得提交或覆寫已發布包。
先前的實驗標記與逐鍵診斷記錄已移除；不需要輸入監控或輔助使用權限。
