# Guanyinma Android 接合

KeyKey 的 Android IME 共用同一套 frontend，可選 Java 原核心或 Guanyinma Rust 核心。預設為 Java；缺少或未知偏好也回到 Java。這是 Android 既有 Java 引擎，不是 Manjusri；各平台的編譯與宿主驗證須分別完成。

## 共用 frontend 與切換

`BopomofoImeService` 持有 `DualCoreInputEngine`，透過 `InputEngine` 共用按鍵、候選、組字、模式及宿主效果。`BopomofoEngine` 保留 Java 實作；`GuanyinmaInputEngine` 只轉換 FE 狀態與 C ABI，不另寫注音解析、walker 或排序。虛擬鍵盤、實體鍵盤與浮動候選窗沿用同一份 frontend 狀態。

設定頁的「輸入核心」使用 `InputCoreSettings.KEY_CORE`，寫入既有 `ime_settings`。其 `InputCore` 值為 `JAVA`／`GUANYINMA`，儲存值為 `java`／`guanyinma`。核心選擇與好打注音／傳統注音／倉頡／簡易是兩個不同設定。

`requestedCore()` 表示偏好，`activeCore()` 表示實際核心。`requestCore()` 須等待組字、未完成讀音、候選與原宿主效果都完成；frontend 先處理 `Result` 的文字、刪除、Return 與 `discardComposingText`，再呼叫 `acknowledgeHostEffects()`。換核不重播按鍵或宿主效果，並保留中英／數字鍵面、暫時英文、Shift 與半／全形等 FE 狀態。Rust 無法開啟時保留原核心並顯示錯誤；實際核心與要求不同時不假裝切換成功。

`InputConnection` 不存在、已更換或拒絕文字操作時，不可 acknowledge 舊效果。Service 保留失敗狀態，直到新的輸入生命週期明確 `abandonHostEffects()`，避免把舊文字改送到新欄位。`onFinishInput`、`onFinishInputView` 與 `onWindowHidden` 可能重複交接；session 關閉由 Service 生命週期管理，不能在每個 callback 重複送整句。

## 三種互動 profile 與宿主文字

profile 由 frontend 的實際互動方式決定，Rust 不判斷 Android OS 或鍵盤裝置：

| 輸入入口 | Rust profile | 組字邊界／宿主策略 |
|---|---|---|
| 虛擬觸控鍵盤 | `touch` | 上限十、`shift_at_limit = true`；第十音節擠出完整前段，保留九個可修改音節 |
| 一般實體鍵盤，包括浮動候選 | `desktop` | 上限十、`shift_at_limit = false`；第十一音節擠出完整前段，使用宿主 composing range 與句中游標 |
| 實體鍵盤「好打注音雙排選字」 | `touch` | 只在不使用浮動候選窗且選項開啟時生效，沿觸控九／十音節及 host-text 策略 |

Service 先以舊策略完成組字，才改變實體／雙排 profile。硬體快捷鍵與半／全形辨識留在 FE，核心接收語意操作。倉頡候選選項仍有虛擬／實體兩組設定，每頁沿 Android 的九格候選。

觸控策略由 `TouchSmartHostTextState` 追蹤已插入宿主的可修改尾段；擠出的前段不再被 Backspace 或選詞修改。普通實體策略則使用 `setComposingText` 與 UTF-16 caret。Service 保留 `onUpdateSelection` 自有回呼分類與 generation，避免延遲的舊 commit callback 清除新組字；真正的新欄位會清除舊宿主狀態。

## JNI 與可顯示性

`GuanyinmaNative` 是唯一 JNI transport：`open(modelPath, configJson, predicate)` 取得 session，`apply`／`snapshot`／`userData` 回傳正式 C ABI JSON，`close` 冪等。Java 文字先嚴格編成標準 UTF-8 `byte[]`，結果與候選 callback 也使用標準 UTF-8；不使用 JNI modified UTF-8 傳補充平面字。

native handle 使用獨立 token registry，Java 物件不持有可任意解參照的裸指標。每個 session 持有 predicate／bridge global references，關閉時釋放；同步 callback 禁止重入或關閉同一 session。字型 callback 拋出例外時保留 cause，該 session 進入只能關閉的失敗狀態；普通無效操作仍由核心原子拒絕，不靜默吞掉錯誤。

`CandidateGlyphSupport.shared().canDisplay` 沿用 Android `Paint.hasGlyph` 與字素／fallback 判斷，透過 `guanyinma_session_open_with_candidate_filter` 在候選、排序、分頁與好打 graph 之前過濾。虛擬、實體與浮動候選使用同一結果，UI 不另外刪字或重新計算數字選字索引。快取只在記憶體，不寫入偏好或備份。

## 模型與使用者資料

Java 與 Rust 共用 APK 的正式 `KeyKey.db` asset。`SharedModelDatabase.install(Context)` 安裝到 no-backup 目錄的 `KeyKey-smart-8fc3aead36cefd16.db`；內容驗證依共用模型 SHA-256，模型安裝不依賴 Java walker 能否建立。兩核心都唯讀該實檔，不 cooker、不因核心切換改詞頻。

Android App 設定頁與 IME 在同一應用程式沙箱，虛擬／實體入口共用資料；不需要 iOS 的 App Group publication 橋接。

| 資料 | 位置與權責 |
|---|---|
| Java 自訂詞、好打注音學習 | `files/UserPhrase.db`，沿用 `SmartMandarinUserData` 原表與流程 |
| Java 倉頡排序 | 原私有 `table_learning` SharedPreferences |
| Rust 自訂詞、Smart 與 table 學習 | `files/GuanyinmaUser.db`，只透過 Guanyinma C ABI 管理 |
| 共用模型 | no-backup 內的 hash 命名 DB，只供唯讀 |

Guanyinma 不自動匯入或覆寫 Java 詞庫／學習。`UserPhraseRepository.open(context, core)` 固定綁定核心；Java repository 委派原工具，`GuanyinmaUserData` 以獨立 admin session 操作 Rust DB，不直接以 Android SQLite SQL 讀寫 Rust schema。

`UserPhrasesActivity` 在開啟時從 Intent 擷取核心，並在 Activity 重建時保留該值。標題、列 token、CRUD、匯入與匯出一直屬於同一 repository；其他頁面改偏好不會讓舊列寫到另一核心。Rust 的列 token 對應完整 query／文字；失效列必須重新讀取後編輯。

MJSR 自訂詞段落由 FE 解碼；壞列、重複列沿既有規則略過，不讀加密學習段。Rust 將完整有效詞條組成一次 `import_user_data`，省略 `smart`／`table` scope 以保留既有學習；核心拒絕時不留下部分資料。Rust 匯出檔名為 `KeyKey-Guanyinma-UserPhrases.mjsr`。這是自訂詞交換，不是自動遷移 Java 學習。

每次成功 CRUD／匯入／重設會發出 `input_core_user_data.<core>` 偏好通知，Service 依實際核心更新資料並讓過期候選失效。設定頁重設會固定確認時的核心；Rust 使用 `reset_method_learning` 的 `smart` 範圍，保留自訂詞與 table learning，Java 原檔維持原流程。

Android「啟用 Bigram 組句」開關須同時設定 Rust 的 `smart.use_bigrams` 與 Bigram 學習行為；關閉時不查模型或已學習 Bigram，也暫停相鄰詞學習。重新開啟後可繼續使用原有資料，無須刪除學習檔。

## 建置與少量串接驗證

建置需求沿 Android 專案：JDK 17 以上、Android SDK 36.1／Build Tools 36.0.0，另需 Python 3.11 以上、NDK `27.2.12479018`、CMake `3.22.1`，以及 `Source/Guanyinma/rust-toolchain.toml` 指定的 Rust toolchain 與 Android 標準函式庫 targets。

| APK ABI | Rust target |
|---|---|
| `arm64-v8a` | `aarch64-linux-android` |
| `armeabi-v7a` | `armv7-linux-androideabi` |
| `x86_64` | `x86_64-linux-android` |
| `x86` | `i686-linux-android` |

Gradle 的 `buildGuanyinmaAndroid` 呼叫 `Source/Guanyinma/tools/build-android-core.py`，以 bundled SQLite 建置各 ABI 的 Rust 靜態庫。AGP 的 CMake target 再把正式 C ABI 與 `guanyinma_jni.cpp` 連為 `libkeykey_guanyinma.so`。C++ runtime 靜態連結，Rust／SQLite 內部 symbols 隱藏，保留 JNI exports 與 16 KiB LOAD alignment。腳本只做建置，不呼叫 `cargo test`，也不啟動模擬器。

在儲存庫根目錄：

```sh
cd Source/Loaders/Android-IME
./gradlew assembleDebug
./gradlew testDebugUnitTest --tests '*GuanyinmaIntegrationTest' \
  --tests '*GuanyinmaUserDataTest' --tests '*UserPhraseArchiveTest'
```

Windows 使用 `gradlew.bat`；host JNI 編譯還需要可用的 MSVC C++ 開發環境。macOS 使用 Xcode clang，Linux 使用 C++17 compiler。可用 `PYTHON3` 指定 Python executable；Rust/Cargo 沿呼叫端環境，`KEYKEY_GUANYINMA_OFFLINE=1` 要求依賴與 targets 已備妥。

JVM tests 的 `buildGuanyinmaHostJNI` 先呼叫 `build-android-host-jni.py` 建立目前主機架構的真 JNI library，再傳入 `keykey.guanyinma.library` 與 `keykey.smart.database`。這些小型 smoke 走真 C ABI，驗證 FE 映射、安全換核、callback 與 repository 資料權責；不是 Android ABI 的執行證據。獨立 Java-only 執行未提供 native library 時可略過 JNI tests，專用 smoke 流程則必須提供 library／模型且實際執行，不能把全部略過當成通過。

完整 Rust／C consumer 行為矩陣只由 [Guanyinma Core workflow](../.github/workflows/guanyinma-core.yml) 負責。Android package／Play workflow 直接編譯核心，只保留少量 JNI／frontend 串接 smoke，不轉呼叫整套核心測試或遷移 functional baseline。

host JVM JNI、APK 四 ABI 編譯、Android runtime 與真正 IME 宿主輸入是不同證據層級。此文件記錄接合與建置契約，不宣稱裝置／UI、Play 發布或其他平台已完成驗收。
