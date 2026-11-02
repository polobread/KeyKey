# 舊 Swift 核心遷移參考

`CoreFunctionalTests.swift` 保留原先 Swift 核心的手動採樣來源，僅供搭配移除舊核心前的 Git revision 及已凍結的 `tests/fixtures/core-functional/` 閱讀比較。

它不屬於目前 Swift Package、Xcode 產品或普通測試 target，不能用目前的 Guanyinma 輸出覆寫舊基準，也不加入 CI 或發布驗收。需要重現原始行為時，請在隔離的舊 revision checkout 使用原 recorder 與原核心。
