# iOS 切換輸入法後的鍵盤上緣留白

2026-11-15 已透過 Feedback Assistant 提交 [FB25579507](https://feedbackassistant.apple.com/feedback/25579507)，並請 Apple 參考開發者回報的相關案例 [FB21449121](https://developer.apple.com/forums/thread/843093)。本案留待後續處理。回報包含 iPhone 16 Plus 在 Safari 的切換前後截圖、17 點量測和圓角調整結果。網頁送出時略過額外的系統診斷檔（sysdiagnose）。

## 實機重現與暫時恢復

環境為 iPhone 16 Plus、iOS 27.2.1（24B156）、琦琦輸入法 1.5.1（build 1），使用直式 Safari 的網址／搜尋欄位。

1. 在同一欄位叫出琦琦，記錄鍵盤頂端和首排組字格位置。
2. 透過地球鍵切到 Apple 的「繁體注音」，再切回琦琦。琦琦上方多出圓角灰帶，約 51 個像素（3 倍顯示倍率下約 17 pt）。首排組字格在兩張 1290 × 2796 px 截圖都從原圖 y=1659 開始。
3. 保持同一欄位，切到 Apple 系統「表情符號」，再切回琦琦。實測灰帶消失，Safari 可繼續使用。從 App 切換器完整關閉 Safari 再重開也能恢復。

琦琦測試版曾將鍵盤背景的左右上角及第一排最左、最右格的外側上角改成圓角。實機覆蓋安裝後，切換繁體注音仍會出現灰帶，Safari 被占用的空間也未回收。圓角改動屬外觀調整。

## 模擬器對照

三台裝置使用同一個測試 App 的 `UITextField`，固定焦點並加上 44 pt 的 `inputAccessoryView`。以宿主的 `keyboardLayoutGuide` 和鍵盤尺寸通知同步量測。表格數字為每次回到琦琦時的宿主鍵盤區高度。

| Runtime／裝置 | 初始琦琦 | 經繁體注音切回 | 經表情符號切回 |
|---|---:|---:|---:|
| iOS 17.0／iPhone 12 | 449 pt | 449 pt | 449 pt |
| iOS 18.6（22G86）／iPhone 15 | 449 pt | 449 pt | 449 pt |
| iOS 26.5（23F77）／iPhone 17 Pro | 449 pt | 466 pt | 449 pt |

iOS 17.0 和 18.6 在上述測試欄位都未重現。iOS 26.5 的宿主鍵盤框從 `[0, 425, 402, 449]` 移至 `[0, 408, 402, 466]`，底邊同在 y=874。五個對照時點中，琦琦 extension 自己的視窗保持 402 × 330 pt、安全區為零，且沒有收到可用來辨識這 17 pt 的 UIKit 鍵盤尺寸通知。受影響時打開「調整鍵盤高度」再取消，宿主高度依序為 466 → 598 → 466 pt，灰帶仍在。沒有附加工具列的對照欄位也曾跑過繁體注音切換，該次宿主高度維持 422 pt。

目前量測顯示，額外空間出現在 iOS 配置給宿主的鍵盤容器。沒有找到能按狀態回收這段空間的公開 API。直接固定減少 17 pt 也會縮小未出現灰帶時的鍵盤。

## 後續驗證

- 查看 FB25579507 的更新。若 Apple 需要 sysdiagnose，在 iPhone 16 Plus 的 Safari 重現當下收集。
- 若有新版 iOS 或 Apple 提供可測方案，重跑 Safari 實機及附加工具列的 UIKit 欄位。比對初始、繁體注音切回、表情符號切回三個狀態的宿主上緣、琦琦視窗尺寸和首末排座標。
- 驗收時，切回琦琦後應恢復同一欄位原本的鍵盤容器高度，按鍵仍可正常觸及。

iOS 17.0／18.6 測試副本的裝置資料留在外接 SSD 的 `ios-simulator/default/Devices`。原始截圖、送出的裁切圖及量測保存在本機建置產物目錄 `Installer/local-builds/ios-keyboard-switch-insets-20261115/`，其中 `apple-feedback-attachments/` 為回報附件，`ios17-feedback-control/`、`ios18-lab/`、`extension-signal-lab/` 及 `height-renegotiation-lab/` 保留測試結果。
