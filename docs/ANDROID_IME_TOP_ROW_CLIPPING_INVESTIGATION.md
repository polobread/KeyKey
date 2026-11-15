# Android 直式鍵盤第一排遮擋調查

2026-11-15 更新。第一排遮擋仍待在實機捕捉，後續從下方的視窗蒐證繼續。

使用者回報在 Pixel 11 直式使用，開啟「整合底部控制鍵」一段時間後，宿主 App 的內容會遮住輸入法第一排約一半。出現後跨 App 持續，Google 搜尋及 Chrome 都會遇到。調整直式鍵盤上緣高度無法恢復。關閉整合後底部留白明顯變大，再開啟整合可恢復正常。

## 已驗證的行為

以 PR #121 合併後的 `master`（`63a42ae1d`）在 Android 17／API 37 觸控模擬器測試，關閉外接鍵盤模擬。

- 4 項既有 instrumented tests 通過，涵蓋系統控制列隱藏與恢復、收起再叫出、旋轉、反覆切換整合及父視窗退讓。
- 直式在 Google 搜尋、Android 設定搜尋與 Debug 測試輸入欄位之間切換 23 次，共開啟鍵盤 24 次。同一 IME 行程和視窗持續使用，24 次的 IME 視窗框與回報給 App 的 inset 範圍一致，未出現第一排遮擋。Chrome 停在首次使用畫面，未納入這次切換測試。
- 同一個測試欄位中，關閉整合時系統控制列恢復，宿主配置的 IME 高度由 1,062 px 增至 1,110 px（此裝置為 16 dp），按鍵區自身的量測高度沒有增加。重新開啟後 IME 高度回到 1,062 px。這只驗證切換開關造成的正常變化，長時間後的遮擋仍待捕捉。

## 待驗證的原因

Android 16 起，服務用 `captionHideRequested` 追蹤隱藏系統控制列的請求。長時間重用 IME 視窗時，實際的控制列可見性、目前控制權或 inset 可能已變動，服務記著的請求狀態卻仍有效。另一個待驗證的原因是 IME 視窗框、實際鍵盤內容與宿主收到的 IME 上緣沒有同步。手動調高度只改鍵盤量測，整合開關還會重新處理底部空間與控制列請求。故障當下的視窗資料才能判定是哪一條路徑。

實作入口在 `BopomofoImeService.updateKeyboardBottomControls` 附近的系統控制列處理，以及 `BopomofoKeyboardView` 的底部空間與量測。測試入口為 `IntegratedBottomControlsInstrumentedTest` 和 `KeyboardBottomSpaceInstrumentedTest`。

## 下次發生時的蒐證

保留同一個 App、輸入欄位和直式方向。依序記錄「第一排被遮住」、「關閉整合」、「重新開啟整合」三個狀態。第一份資料要在切換開關之前取得。

- 每個狀態擷取鍵盤截圖及 `adb shell dumpsys window -a windows`、`adb shell dumpsys window -a displays`、`adb shell dumpsys input_method`。
- 比對可見第一排、IME 視窗框、IME inset source 的上緣與可見性、系統控制列與導覽列 inset，以及 IME input／layering／control target。同步記錄 Android 版本、IME 版本、使用中的 App 與是否仍為同一個 IME 行程。
