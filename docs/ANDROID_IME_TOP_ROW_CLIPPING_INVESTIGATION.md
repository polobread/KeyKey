# Android 直式鍵盤第一排遮擋調查

2026-11-17 更新。Pixel 11 已捕捉異常，Android 17 模擬器重現並驗證 1.5.2 修正。實機短測通過，長時間使用仍待觀察。

使用者回報在 Pixel 11 直式使用，開啟「整合底部控制鍵」一段時間後，宿主 App 的內容會遮住輸入法第一排約一半。出現後跨 App 持續，Google 搜尋及 Chrome 都會遇到。調整直式鍵盤上緣高度無法恢復。關閉整合後底部留白明顯變大，再開啟整合可恢復正常。

## 11 月 15 日的初步驗證

以 PR #121 合併後的 `master`（`63a42ae1d`）在 Android 17／API 37 觸控模擬器測試，關閉外接鍵盤模擬。

- 4 項既有 instrumented tests 通過，涵蓋系統控制列隱藏與恢復、收起再叫出、旋轉、反覆切換整合及父視窗退讓。
- 直式在 Google 搜尋、Android 設定搜尋與 Debug 測試輸入欄位之間切換 23 次，共開啟鍵盤 24 次。同一 IME 行程和視窗持續使用，24 次的 IME 視窗框與回報給 App 的 inset 範圍一致，未出現第一排遮擋。Chrome 停在首次使用畫面，未納入這次切換測試。
- 同一個測試欄位中，關閉整合時系統控制列恢復，宿主配置的 IME 高度由 1,062 px 增至 1,110 px（此裝置為 16 dp），按鍵區自身的量測高度沒有增加。重新開啟後 IME 高度回到 1,062 px。該次只驗證了切換開關造成的正常變化。

## 實機蒐證與重現

Pixel 11（Android 17）在同一 LINE 欄位使用 1.5.1。故障時 IME 視窗高 866 px，關閉整合為 971 px，重新開啟後為 929 px。底部手勢導覽列一直是 63 px（24 dp）。兩次開啟整合時，後續按鍵排在相同位置。

在相同解析度與密度的模擬器，收起鍵盤、旋轉，再打開鍵盤即可重現直式 866 px 的視窗。當下鍵盤已量到 929 px，外層仍用 866 px 配置，貼底後鍵盤上緣落在視窗頂端以上 63 px。這段重現步驟可用來驗證修正，平常使用時出現故障的觸發條件仍待觀察。

## Android 1.5.2 修正與驗證

- 由 `KeyboardInputView` 處理導覽列空間。容器收到的底部 inset 為零時，依目前的視窗位置與可見導覽列計算實際重疊，避免重複算入父層已保留的空間。
- 如果系統以舊高度配置視窗，先讓按鍵完整落在目前視窗內，再請系統重排一次。`BopomofoImeService` 在整合觸控鍵盤重新顯示時也會要求更新 inset。
- Android 17 模擬器的直式手動重現流程回到 929 px，組字列完整。橫式收起後重開為 604 px，持續顯示時旋轉為 667 px，兩種畫面按鍵均完整。
- `IntegratedBottomControlsInstrumentedTest` 和 `KeyboardBottomSpaceInstrumentedTest` 在手勢與三鍵導覽各通過 19 項，涵蓋旋轉、第一排顯示與實際點選、遺失 inset、過短視窗，以及設定頁高度預覽。
- Pixel 11 以 USB 覆蓋安裝 1.5.2 後，LINE 與 Chrome 的第一排可見且可點選。USB 記錄的最後一次直式視窗高度為 929 px。

## 下次發生時的蒐證

保留同一個 App、輸入欄位和直式方向。依序記錄「第一排被遮住」、「關閉整合」、「重新開啟整合」三個狀態。第一份資料要在切換開關之前取得。

- 每個狀態擷取鍵盤截圖及 `adb shell dumpsys window -a windows`、`adb shell dumpsys window -a displays`、`adb shell dumpsys input_method`。
- 比對可見第一排、IME 視窗框、IME inset source 的上緣與可見性、系統控制列與導覽列 inset，以及 IME input／layering／control target。同步記錄 Android 版本、IME 版本、使用中的 App 與是否仍為同一個 IME 行程。
