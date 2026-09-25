# 好打注音功能恢復稽核

本文件比對下列來源：

- Yahoo KeyKey 1.1.2528 原始碼：`../yahoo/KeyKey-master/YahooKeyKey-Source-1.1.2528`
- 目前開發分支：`v1.3.0`
- macOS 實際 Release target：`Takao (Loader OSX-IMK)`

## 已恢復

### 好打注音引擎與資料庫

- 將 `SmartMandarin` 放回 macOS 輸入法清單。
- 新安裝且尚未設定主要輸入法時，預設使用 `SmartMandarin`。
- 恢復 `unigrams`、`bigrams` schema 與資料庫 cooking。
- 使用 McBopomofo 詞彙、專案補充詞及合成 bigram 語料。
- 偏好設定重新列出「好打注音」。

### 詞彙編輯工具

Yahoo 1.1.2528 的 `TakaoPhrases.m` 有 `launchEditor:`。重建版本保留了 header 宣告、
三個語系 XIB 的按鈕連線，以及套件內的 `PhraseEditor.app`，但刪除了 method 實作，
所以「啟動詞彙編輯工具」按鈕無法工作。

目前已恢復 `launchEditor:`：

- 優先開啟與 `Preferences.app` 同層的 `PhraseEditor.app`。
- 以新版 bundle identifier 作為備援啟動方式。
- 若安裝內容缺少 PhraseEditor，顯示在地化錯誤訊息。
- 好打注音啟用時，輸入法選單直接顯示「編輯自訂詞…」，不必先打開偏好設定。

詞彙編輯資料路徑也已補強：

- 所有列表操作改用排序後的 offset 尋址，不再假設 SQLite rowid 永遠連續。
- 找不到合法讀音時略過新增或修改，避免空陣列越界。
- 損壞或字數不符的讀音資料不再開啟會越界的編輯 sheet。
- 多音字讀音組合保留詞頻最高的前 256 組，避免長詞產生組合爆炸而卡住介面。
- 移除查讀音時殘留的逐字除錯輸出。

### 學習紀錄重設

舊版只有連按十一回 `Ctrl+2` 的隱藏除錯捷徑，會清除所有 cache，並不適合作為一般功能。
目前在好打注音選單提供「重設好打注音學習紀錄…」：

- 操作前顯示確認視窗。
- 只刪除 `user_bigram_cache` 與 `user_candidate_override_cache`。
- 保留 `user_unigrams` 內的自訂詞。
- 先結束目前組字並儲存待寫學習，再以 transaction 清除兩張表。
- 下一輪載入前先清空記憶體 user cache，避免已刪資料被舊 cache 帶回。

## 原始碼仍保留，詞庫恢復後可繼續使用

- 候選選字覆寫學習：`user_candidate_override_cache`
- 相鄰詞學習：`user_bigram_cache`
- Shift 加方向鍵選取組字區文字，再按 Enter 加入使用者詞庫
- 詞彙編輯器的新增、刪除、修改詞彙與修改讀音
- 使用者詞庫文字檔匯入與匯出
- 注音鍵盤配置、選字鍵、組字區長度、Space 顯示候選與 Esc 清除選項
- 關聯詞功能與分類詞庫選擇

## 與好打注音詞庫無直接關係的舊功能

- Yahoo 線上字典依賴已停止的網路服務。
- Yahoo 自動更新、追蹤、遠端 OneKey 與罐頭訊息依賴已停止的伺服器。
- MobileMe／iDisk 詞庫備份依賴 Apple 已停止的服務。
- Ctrl+2 連按十一回清除全部 cache 是開發除錯捷徑，並非一般使用者功能。
- 字數統計、字根反查與詞彙轉換原本屬於獨立 Extra Modules 安裝包，不是因
  SmartMandarin 詞庫缺失而停用。

上述網路服務與獨立外掛不列入本次好打注音詞庫恢復範圍。

## 驗證

- 三個語系的 `launchEditor:` XIB action 都有對應實作。
- 三份 `Localizable.strings` 均通過 `plutil -lint`。
- macOS arm64 Release target 建置成功。
- Release app 內包含 `Contents/SharedSupport/PhraseEditor.app`。
- PhraseEditor bundle identifier 為
  `io.github.polobread.inputmethod.chichi77.PhraseEditor`。
- 三個語系的輸入法選單字串通過 `plutil -lint`。
- macOS arm64 Release app（含 PhraseEditor）在 Xcode 27 完整建置成功。
