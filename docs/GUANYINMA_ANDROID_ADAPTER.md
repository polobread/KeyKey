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

旋轉或重新啟動同一輸入欄位時，Android 可能已結束舊 composing span，但 frontend 仍保留組字。`onStartInput(restarting = true)` 經 `restoreMarkedComposition()` 讀取目前 `ExtractedText`，以 `startOffset` 換算既有組字範圍，核對完整文字及範圍內的折疊選取；不接受局部更新、缺少快照或文字不符。確認後只以 `setComposingRegion` 重新掛上原範圍，並恢復核心的 UTF-16 caret，不重送組字文字，也不採用 configuration replay 可能過時的 `EditorInfo.initialSelStart`。這次操作列為自有 selection 更新，避免回呼再次確認或清空原組字；觸控 host-text 尾段維持原流程。

無法驗證或重新接續時，Service 結束宿主標記、abandon 舊核心效果並清除 frontend 組字快取，保留 App 現有文字，不把舊組字追加到未知範圍；真正的新宿主仍走原有清除邊界。宿主標記無法結束時維持交易失敗狀態，等待重新進入欄位。Android 遠端 `InputConnection` 的操作 boolean 不等於宿主實際回傳值；下述失敗回歸驗證的是缺少／不符文字快照的安全退路，不宣稱已涵蓋宿主無聲忽略 `setComposingRegion` 的情境。

一般實體好打注音固定 `candidate_cursor_at_end = false`、`selection_returns_to_end = false`：候選從游標右側開始，句尾以最後一字為目標，選字後游標位於所選詞後方。`openSmartCandidates()` 的明確索引同樣使用 `min(reading_cursor, readings.length - 1)`，不能只修改選項卻沿用左側索引。觸控及實體雙排仍在選字後回到可編輯句尾；「使用空白鍵選字」沿用 Android 已存偏好及預設關閉，不因對齊游標規則改寫。Esc 清除整句與 Shift 強制大寫的核心選項明確設為關閉。

實體 `KEYCODE_FORWARD_DEL` 在有組字時經 `InputEngine.deleteForward()`／`HostInputEngine` 送到 Rust 既有 `Delete`，保留核心對未完成讀音、候選及句尾的拒絕規則；沒有組字時交回宿主處理普通 Delete。成功刪除最後一字時，adapter 回傳 `discardComposingText`，讓 Service 用空字串替換標記範圍；單呼叫 Android `finishComposingText()` 會保留舊字，不能代表刪除已完成。

實體 Enter／數字鍵盤 Enter 的 Down 由 IME 處理後，Service 也消耗對應的 Up。若核心要求普通 Return，只向原宿主送一次合成 Down／Up；此配對所有權須跨越因 Return 造成的欄位切換，不能在 `onFinishInput()` 提前清除。候選中的 Enter 維持按住不重複選字，放開時一起清除候選按鍵狀態；不因這項配對改變普通 Enter 的長按行為。

浮動候選窗由目前鍵盤 view 持有。`onCreateInputView()` 在覆寫 owner 前必須關閉舊窗並取消其 token 重試；`onConfigurationChanged()` 在 framework 重建 view 前先關閉浮窗、取消游標座標重試並清除舊 anchor，再以新 view 重建。隱藏、旋轉、重開或切換排列後最多保留目前的一個浮窗；這是 Android 視窗生命週期契約，不在 Rust 核心管理。

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

`PhysicalKeyboardRegressionInstrumentedTest` 為明確啟用的 Android runtime／宿主回歸，涵蓋候選目標、Delete 後接續輸入、Enter 按放、四法基本送字，以及垂直浮窗／水平浮窗／底部候選的直橫式、旋轉與重開。專用 restart 案例另檢查有前後文、句中游標及未完成讀音時重複重啟的冪等行為，並以 debug 宿主提供 null／文字不符快照，確認不重播舊組字。測試會修改設定及學習資料，只能在可丟棄且啟用硬體鍵盤的專用模擬器，以 `keykey.isolatedDevice=true` 執行；未給此參數會略過，不能算通過。各案例使用全新 App 資料，執行入口見 [Android README](../Source/Loaders/Android-IME/README.md#建置)。輸入事件經 InputDispatcher 注入，只驗證 Android 事件與宿主接合，不能替代真正 USB／藍牙鍵盤的傳輸及修飾鍵實測。

## 授權元件目錄

Android 與 iOS 共用 `Source/Guanyinma/tools/mobile_runtime_notices.py` 的 schema 與全文去重方式。`generateGuanyinmaNotices` 在四個 ABI 的 Rust archive 完成後才執行；建置環境須有鎖定工具鏈同版本的 `rust-src`。`Guanyinma-Notices.json` 與文字索引放進 APK／AAB，`Guanyinma-Notices.audit.json` 只留在 build reports，不打包、不提交。

- Rust normal 執行期相依與各 ABI archive／sysroot rlib 的 crate 名稱及 hash 必須吻合，排除建置／測試／proc-macro 工具。標準庫與 compiler-builtins／libm 的完整來源聲明依同版 rust-src 取得；保留 Rust、Crossbeam、Unicode 署名，不打包整份 `COPYRIGHT-library.html` 或整套 Rust 授權目錄。
- Android 使用 bundled SQLite，核對每個 archive 的 sqlite3 object 並保留實際 amalgamation 版本及 public-domain disclaimer。JNI 沿用靜態 libc++／libc++abi／libunwind 與 compiler-rt；聲明從實際 NDK NOTICE 中識別 runtime 區段，排除 OpenMP、編譯器工具等無關項目。libunwind 聲明取自 NDK 記錄的 LLVM base revision，原文與 SHA-256 固定；NDK 來源變更需重新核對。
- Java 相依取 Gradle 已解析的 Debug／Release runtime artifact 聯集（本次兩者相同），不含 androidTest／host unit 依賴。`android-runtime-license-review.json` 保存實際版本的官方 POM URL、雜湊、授權與必要的父 POM 繼承。優先保留 artifact 內附 LICENSE／NOTICE；已核對為 Apache-2.0 且無內附聲明的包共用完整標準條款。未知版本或授權來源中止建置，不以套件名稱猜測。
- Google Billing／Play Services 的混淆／內含程式無法僅靠 class 名稱證明沒有某個第三方來源，保留原廠該 artifact 隨附的完整第三方聲明。其相同條款及長篇聲明以文字雜湊共用，各 runtime 元件保留自己的引用和來源雜湊。這些屬 Android Java／Google 元件，不混入 Rust 標準庫條目。
- 專案、Yahoo、Formosa／OpenVanilla、Unicode 與詞庫來源沿用既有原始署名。去重只忽略空白差異，不重寫條件、例外或著作權；依元件範圍保留，不推測連結器函式層級 dead stripping 的授權結果。

核對入口：

```sh
python3 Source/Guanyinma/tools/test_ios_runtime_notices.py
python3 Source/Guanyinma/tools/test_android_runtime_notices.py
python3 Source/Guanyinma/tools/verify-android-runtime-notices.py PATH_TO_APK_OR_AAB
```

Python 測試檢查原廠 byte-offset 聲明、Unicode 署名及共用條款／例外不遺失；APK／AAB 驗證檢查實際元件、完整引用、內容雜湊與 Rust 無關清單排除。Android UI 測試另從主畫面進入，實際閱讀 Yahoo 與 Rust 條目、搜尋必要署名並返回。iOS 共用程式重構後須核對既有目錄及文字輸出一致，不以 Android 檢查替代 iOS 宿主驗證。

依據：[Android NDK C++ runtime](https://developer.android.com/ndk/guides/cpp-support)、[Apache 2.0 第 4 條](https://www.apache.org/licenses/LICENSE-2.0)、各 artifact 原廠 POM 及完整內附聲明。LLVM libunwind 原文來源為 `https://raw.githubusercontent.com/llvm/llvm-project/3c92011b600bdf70424e2547594dd461fe411a41/libunwind/LICENSE.TXT`。
