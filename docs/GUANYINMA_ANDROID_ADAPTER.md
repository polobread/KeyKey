# Guanyinma Android 接合

KeyKey Android 的四種輸入法固定使用 Guanyinma Rust 核心。原有 Java 輸入演算法、walker、排序、可寫學習庫、核心切換與失敗回退均已移除；舊 `input_core` 偏好不影響執行路徑。Java 保留 Android frontend、宿主文字交易與格式轉換，不再提供另一套輸入引擎。

## 共用 frontend 與宿主交易

`BopomofoImeService` 使用 `HostInputEngine` 包裝唯一的 `GuanyinmaInputEngine`。`InputEngine` 定義 FE 的按鍵、候選、組字、模式及宿主效果資料；`GuanyinmaInputEngine` 只轉換 FE 狀態與 C ABI，不另寫注音解析、walker 或排序。虛擬鍵盤、實體鍵盤與浮動候選使用同一份 frontend 狀態。

`HostInputEngine` 只處理宿主效果的所有權：原 `InputConnection` 接受本次文字、刪除、Return 與 `discardComposingText` 後，Service 才 `acknowledgeHostEffects()`。有待確認的效果時不接受下一筆輸入；沒有宿主、宿主已更換或拒絕交易時不重播，於真正新宿主邊界明確 `abandonHostEffects()`，清除前個欄位狀態並保留 FE 中英、暫時英文、Shift 與全半形政策。重複生命週期回呼不重送整句。

核心或模型無法開啟時明確回報失敗，停用該 session；不建立空字庫引擎、不回退 Java。之後重新進入文字欄位可重新建立 Rust session。清除舊宿主狀態失敗時關閉該 session，避免把舊組字送到新欄位。Service 銷毀時關閉核心、停止背景關聯詞載入、取消 callback 並關閉浮動窗。

## 三種互動 profile 與宿主文字

profile 由 frontend 的實際互動方式決定，Rust 不判斷 Android OS 或鍵盤裝置：

| 輸入入口 | Rust profile | 組字邊界／宿主策略 |
|---|---|---|
| 虛擬觸控鍵盤 | `touch` | 上限十、`shift_at_limit = true`；第十音節擠出完整前段，保留九個可修改音節 |
| 一般實體鍵盤，包括浮動候選 | `desktop` | 上限十、`shift_at_limit = false`；第十一音節擠出完整前段，使用宿主 composing range 與句中游標 |
| 實體鍵盤「好打注音雙排選字」 | `touch` | 只在不使用浮動候選窗且選項開啟時生效，沿觸控九／十音節及 host-text 策略 |

Service 先以舊策略完成組字，才改變實體／雙排 profile。硬體快捷鍵與半／全形辨識留在 FE，核心接收語意操作。倉頡候選選項仍有虛擬／實體兩組設定，每頁沿 Android 的九格候選。

觸控策略由 `TouchSmartHostTextState` 追蹤已插入宿主的可修改尾段；擠出的前段不再被 Backspace 或選詞修改。普通實體策略使用 `setComposingText` 與 UTF-16 caret。Service 保留 `onUpdateSelection` 自有回呼分類與 generation，避免延遲的舊 commit callback 清除新組字；真正的新欄位會清除舊宿主狀態。

## JNI、字型與 FE 資料

`GuanyinmaNative` 是唯一 JNI transport：`open(modelPath, configJson, predicate)` 取得 session，`apply`／`snapshot`／`userData` 回傳正式 C ABI JSON，`close` 冪等。Java 文字嚴格編成標準 UTF-8 `byte[]`，結果與候選 callback 也使用標準 UTF-8；不使用 JNI modified UTF-8 傳補充平面字。

native handle 使用獨立 token registry，Java 物件不持有可任意解參照的裸指標。每個 session 持有 predicate／bridge global references，關閉時釋放；同步 callback 禁止重入或關閉同一 session。字型 callback 拋出例外時保留 cause，該 session 進入只能關閉的失敗狀態；普通無效操作仍由核心原子拒絕。

`CandidateGlyphSupport.shared().canDisplay` 沿用 Android `Paint.hasGlyph` 與字素／fallback 判斷，透過 `guanyinma_session_open_with_candidate_filter` 在候選、排序、分頁與好打 graph 之前過濾。虛擬、實體與浮動候選使用同一結果；UI 不另外刪字或重算選字索引。快取只在記憶體，不寫入偏好或備份。

`InputEngine.Result`／`InputMode` 是原生 FE 資料契約；符號、Emoji、鍵帽標籤與輸出寬度工具也留在 FE。關聯詞的 `.kki` 格式與分類載入沿用既有資料來源；它們不是中文輸入核心的字表、組句或學習替代品。建置不再封裝舊 `bpmf-index.kki` 或 CIN 輸入字表。

## 模型與使用者資料

四種輸入法共用 APK 的正式 `KeyKey.db` asset。`SharedModelDatabase.install(Context)` 安裝到 no-backup 目錄，以內容 SHA-256 驗證快取；模型唯讀，不 cooker、不改詞頻。

| 資料 | 位置與權責 |
|---|---|
| 自訂詞、Smart 與 table 學習 | `files/GuanyinmaUser.db`，只透過 Guanyinma C ABI 管理 |
| 共用模型 | no-backup 內的 hash 命名 DB，只供唯讀 |
| 舊 Java 詞庫及 `table_learning` 偏好 | 保留原檔／原值；不再開啟、寫入、自動匯入或刪除 |

App 與 IME 位於同一應用程式沙箱，虛擬／實體入口共用 Rust 使用者資料。`UserPhraseRepository.open(context)` 永遠建立 `GuanyinmaUserData`；詞庫列 token 對應完整 query／文字，失效列必須重新載入。不存在核心選擇 Intent、偏好或列路由。

MJSR 自訂詞段落由 FE 的 `UserPhraseArchive`／`PhraseReadingCodec` 轉換；這個薄 codec 只處理既有詞庫檔的注音／標準鍵位語法，不用於輸入事件，也不含 Hsu 或組句狀態機。壞列、重複列沿既有規則略過，不讀加密學習段。Rust 將完整有效詞條組成一次 `import_user_data`，省略 `smart`／`table` scope 以保留既有學習；核心拒絕時不留下部分資料。匯出檔名為 `KeyKey-Guanyinma-UserPhrases.mjsr`。這是明確自訂詞交換，不是 Java 學習自動遷移。

每次成功 CRUD／匯入／重設會發出既有 Guanyinma 資料通知，Service 更新資料並讓過期候選失效。設定頁重設使用 `reset_method_learning` 的 `smart` 範圍，保留自訂詞與 table learning。

「啟用 Bigram 組句」同時設定 Rust 的 `smart.use_bigrams` 與 Bigram 學習行為；關閉時不查模型或已學習 Bigram，也暫停相鄰詞學習。重新開啟後可繼續使用原有資料。

## 建置與少量串接驗證

需要完整 JDK 17 以上（含 `javac` 與 JNI headers）、Android SDK 36.1／Build Tools 36.0.0、Python 3.11 以上、NDK `27.2.12479018`、CMake `3.22.1`，以及版控固定的 Rust toolchain 與 Android targets。

| APK ABI | Rust target |
|---|---|
| `arm64-v8a` | `aarch64-linux-android` |
| `armeabi-v7a` | `armv7-linux-androideabi` |
| `x86_64` | `x86_64-linux-android` |
| `x86` | `i686-linux-android` |

Gradle 的 `buildGuanyinmaAndroid` 以 bundled SQLite 編譯四個 Rust 靜態庫，AGP CMake 再與薄 `guanyinma_jni.cpp` 連為 `libkeykey_guanyinma.so`。C++ runtime 靜態連結，Rust／SQLite 內部 symbols 隱藏，保留 JNI exports 與 16 KiB LOAD alignment。腳本只做建置，不呼叫核心全套測試、不啟動模擬器。

```sh
cd Source/Loaders/Android-IME
./gradlew lintDebug testDebugUnitTest assembleDebug assembleDebugAndroidTest
./gradlew testDebugUnitTest --tests '*GuanyinmaNativeTest' \
  --tests '*GuanyinmaIntegrationTest' --tests '*GuanyinmaUserDataTest' --tests '*UserPhraseArchiveTest'
python3 tools/verify-guanyinma-smoke.py app/build/test-results/testDebugUnitTest
```

Windows 使用 `gradlew.bat`，host JNI 需要 MSVC C++；macOS 使用 Xcode clang，Linux 使用 C++17 compiler。可用 `PYTHON3` 指定 Python executable；Rust/Cargo 沿環境設定。`KEYKEY_GUANYINMA_OFFLINE=1` 要求依賴與 targets 已備妥。

JVM tests 的 `buildGuanyinmaHostJNI` 建立目前主機架構的真 JNI library。聚焦 smoke 驗證四法接合、設定映射、一次性宿主效果、無回退失敗、字型 callback、使用者資料權責與釋放；不是 Android ABI runtime 證據。專用 smoke 必須實際執行，不能把全部略過當成通過。

完整 Rust／C consumer 矩陣只由 [Guanyinma Core workflow](../.github/workflows/guanyinma-core.yml) 負責，平台 workflow 直接編譯核心，只跑少量 FE 串接。舊 Java 核心專屬矩陣不再編譯；凍結的 functional baseline 仍保留作手動遷移參考，重新擷取舊核心需使用保留該實作的 Git revision，不在日常／CI／發布 gate 執行。

host JVM JNI、APK 四 ABI 編譯、Android runtime 與真正 IME 宿主輸入是不同證據層級；此文件不宣稱裝置／UI、Play 發布或其他平台已完成驗收。
