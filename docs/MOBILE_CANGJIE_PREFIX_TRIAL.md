# 手機倉頡前綴候選試用

此輪只提供 iOS／Android 虛擬鍵盤。桌面與手機實體鍵盤的前綴功能仍在[跨平台計畫](CANGJIE_PREFIX_CANDIDATES_PLAN.md)中，尚未接入。

## 試打方式

1. 切換倉頡，開啟「倉頡設定（虛擬鍵盤）」的「未打完也能選字」；新設定缺值預設開啟。既有「即時候選」的儲存選擇保留，前綴功能不要求它同時開啟。
2. 輸入「竹」：先看到完整碼候選，後面追加常用前綴字；「喬」尚未進入前 36 個前綴。
3. 再輸入「大」：第一頁即可點「喬」，不用再打剩餘三碼。實際順位會隨缺字過濾及既有完整碼學習而異。
4. 重新試「竹大口」及「竹大口月」：「喬」仍可選，後者只有「喬、䀉」（依系統字型支援過濾）。
5. 打完「竹大口月口」：只預覽「喬」，不因僅一字而自行送出。點選或 Enter 確認；空白維持單頁選首字、多頁翻頁。
6. 在前綴中刪碼、翻頁後繼續輸入，候選應重新查詢；不能保留已不符合的字。點選前綴後可直接開始下一個字。

完整碼維持原排序並一律在前，前綴才使用固定 1,500 字排名，未收錄字依字表列序補足。前綴去重、過濾缺字與標點／符號後最多 36 字；完整碼數量另計。要比較原行為，可關閉「未打完也能選字」，再依需要切換「即時候選」。

虛擬與實體的即時候選分開保存；新安裝實體即時候選預設關閉，舊選擇保留。本輪實體入口沒有新前綴開關。

## 開發驗證

- 排名資源：`python3 tests/generate_cangjie_ranking.py --check`，確認 Swift／Java 同源、1,500 個不同字及固定內容。
- Swift：`swift test --filter 'CangjiePrefixTests|TableInputTests'`，8 個相關測試通過，涵蓋實際 DB、逐碼、退格、萬用字元、學習隔離與 App Group 設定。
- iOS Simulator 26.5：3 個實際 UI 測試通過，涵蓋 extension 提前選「喬」、簡易與實體編輯器原流程；保留 HK 候選截圖於本機 xcresult。
- iOS Debug 實機 App 與 extension 簽署建置及實機安裝成功；實機觸控效果仍由使用者試用確認。
- Android：`lintDebug testDebugUnitTest assembleDebug assembleDebugAndroidTest` 通過；125 個 JVM 測試通過，API 33 模擬器的 4 個 SQLite／字型／設定裝置測試通過。
- Android 實際觸控 IME：在 debug 文字宿主輸入 HK，第一頁點「喬」，宿主內容驗證為「喬」。
- iOS extension 與 Android APK 包內 DB 的 SHA-256 均為 `8fc3aead36cefd16a77c0a0d4319f7a305fb712b752db09396c8ac2bd4ebbfdb`，與未修改的正式 DB 一致。
- 完整 `swift test`：23 個 suite 的 171 個 Swift Testing 測試及 4 個 XCTest 全部通過。
- 好打注音的 3 個長句邊界測試，以同一模型直接組句的結果核對逐鍵輸入、擠字與交接後的文字，不再把「玩／完」等同音字順位當成邊界驗收條件；仍檢查「請假」整詞擠出、觸控九／十與實體十／十一音節界線、19 音節全文完整，以及交接後不可重複送出。本輪未修改注音引擎或正式 DB。

本機建置產物與截圖放在 `Installer/local-builds/` 及 Android `app/build/`，不納入提交。iOS 開發版維持 1.3.5，Android 維持 1.3.6；這些驗證不代表商店正式版或其他平台已更新。
