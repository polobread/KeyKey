# Guanyinma 核心遷移專用行為基準

產品名稱維持 **chichi77 KeyKey／琦琦輸入法**（英文簡稱 **KeyKey**）；**Guanyinma** 是新的 Rust 共用核心，用來取代 Manjusri 與各平台既有核心。這份語料與快照只供遷移至 Guanyinma 或其後續核心升級時參考現有行為、檢視差異。**不作為日常驗證、CI gate、預設 CTest 或發布驗收。** 原有各平台測試流程維持既有用途。


Guanyinma 的演算法疑義以 macOS Manjusri／Formosa／OpenVanilla 為主要來源；其他平台觀測用於理解差異與原生 frontend 接合。明確新增的行為按共用行為設定處理，不在核心建立 OS 特例。階段二可手動執行 [compare_migration_phase2.py](../Source/Guanyinma/tools/compare_migration_phase2.py)，只比較已移植的桌面案例；好打注音與學習明列跳過。第三階段使用 [compare_migration_phase3.py](../Source/Guanyinma/tools/compare_migration_phase3.py)，納入好打注音並具名標示尚需學習／保存的案例；不覆寫凍結觀測。
入口 [run_core_functional.py](../tests/run_core_functional.py) 必須明確指定 `--capture` 或 `--compare`。不帶動作會停止並顯示用法；缺少基準時不會自動建立，既有基準也不會自動覆寫。

## 覆蓋範圍

共用語料 [migration-scenarios.tsv](../tests/fixtures/core-functional/migration-scenarios.tsv) 包含 **111 個情境、650 個操作**，涵蓋四種中文輸入法。桌面與 Unix 執行其中 59 個 hardware 情境、340 個操作，明確跳過 52 個 touch 情境、310 個操作；Swift／Android 執行兩種 profile 全部情境。

| 輸入法 | 行為 | 候選與學習 |
|---|---|---|
| 好打注音 | 確認／取消、未完成讀音、退格、句內空白、游標、改選後追加、標點、許氏／標準、方法切換、觸控九／十及實體十／十一音節長句 | 完整候選次序與翻頁、單字／上下文／完整詞跨度改選、自動確認與取消、單字學習後擠字、重開保存、重設 |
| 傳統注音 | 聲調與空白完成、連續選字、未完成讀音、退格／Esc／Enter、標點、許氏、切換 | 多頁完整候選、明確選字、重開及重設後的現有排序／學習政策 |
| 倉頡 | 一至五碼、續打、即時候選、前綴依賴、根碼刪除、錯碼清除／保留、單／多碼萬用字元、三種標點設定、擴展字、切換 | 完整字碼／前綴與萬用字元的實際順序；動態頻率啟閉、改選、重開保存及重設 |
| 簡易 | 單碼／雙碼、滿碼續打、退格、錯碼、即時候選、標點、切換 | 完整候選順序與翻頁；選字後、重開及重設後的現有學習政策 |

這裡記錄的是現有行為，包括已知差異，不預先認定所有平台應該一樣。例如 Unix 的傳統注音／倉頡／簡易目前不會由該核心寫入選字學習；不為了共用測試補出新功能。Unix 不支援的 dynamic／punctuation 設定以 capability／unsupported 標記記錄。

每個 case 建立隔離的學習 DB／偏好設定。選字學習使用正式引擎與真正可寫資料庫；`REOPEN` 保留該 case 的學習，`RESET_LEARNING` 清除該 case 的學習後再觀察。跨 case 不共享記憶。

## 現有核心介面與錄製層

| 平台 | 現有介面 | 本基準使用 |
|---|---|---|
| macOS | OpenVanilla module/context、文字 buffer、候選服務 | 真實 Smart／Traditional／Generic 模組；不載入已安裝 IMK |
| Windows | `KeyKeyEngineSession.handleKey()` → `EngineResult`，下層使用桌面模組 | 手動 target 使用桌面模組與 Windows table subclass；原生 Windows 快照須在 Windows 另錄 |
| iOS | Swift `BopomofoEngine` 與 Store／資料來源介面 | 真實 SQLite／字表／隔離 UserDefaults，Swift Package 在 Mac 錄製 |
| Android | Java `BopomofoEngine` 與 Store | 真實 APK 字表／模型 asset、SQLite 及隔離 SharedPreferences，專用模擬器 instrumentation |
| Linux／FreeBSD | `Engine.processKey()` → `EngineResult` | 真實 Unix engine／CIN／模型；不載入 Fcitx |

模型主資料唯讀。Android 從當次 APK asset 複製測試專用模型，避免安裝快取影響；桌面可寫資料只附加於隔離 profile。

桌面 Smart 為錄製學習資料及明確 `REOPEN` 會呼叫現有強制 checkpoint，繞過正常保存節流；這固定的是學習內容／排序及可保存性，**不代表產品正常儲存延遲已被測量**。桌面 `learning` 欄只輸出當前輸入法的資料，其餘方法的隔離檔仍保留。各方法設定在切換／重開時分別保存。

主候選語料明確不載入關聯詞建議來源。介面、輸入法宿主與鍵盤 UI 的預設設定不由此錄製器推定。

## 快照與凍結基準

[pre-rust](../tests/fixtures/core-functional/pre-rust) 中每個 backend 的 JSON 包含：

- 引擎來源 commit、實際原始碼／recorder 的 SHA-256 指紋、模型與語料 hash、執行環境。
- 每個操作的 case／step／profile／輸入法、操作與參數。
- 累計送字、組字、讀音、游標及其單位、反白與頁碼。
- **全部頁面的候選陣列，保留原次序**，不是只驗證第一名、第一頁或成員集合。
- 實際學習的 override、Bigram、自訂 Unigram 與 table frequency 邏輯列；不含隨機路徑、時間或不穩定 rowid。

游標／可取得狀態各平台不同，快照明列單位；Unix 的私有讀音狀態無公開介面，記為 null 並標註 capability。讀取完整候選時使用狀態副本或暫時翻頁再恢復，不用選字來探測清單。

目前已凍結以下觀測：

| backend | 觀測環境 | 每次情境／快照 | 兩次觀測 |
|---|---|---|---|
| [desktop](../tests/fixtures/core-functional/pre-rust/desktop.json) | macOS 27.0.1 arm64，Apple Clang，桌面模組 | 59／340 | 相同 |
| [unix](../tests/fixtures/core-functional/pre-rust/unix.json) | 同一 Mac 上執行 Unix engine | 59／340 | 相同 |
| [swift](../tests/fixtures/core-functional/pre-rust/swift.json) | macOS 27.0.1，Apple Swift 6.4.2 | 111／650 | 23 個快照只有候選順序不同 |
| [android](../tests/fixtures/core-functional/pre-rust/android.json) | Android 11／API 30／arm64-v8a，隔離 AVD | 111／650 | 相同 |

Swift 的兩次原始順序都保留，`observed_variation` 明列變動位置；沒有設定固定 hash seed、替候選排序或修改核心。比較時，各檢查點可比對已觀察到的版本。**兩次觀測不是同分排序所有可能結果的完整集合**；新差異仍應人工判斷，不能據此聲稱舊核心在該處有固定順序。

原生 Windows 尚未擷取專屬基準，不能以 Mac 桌面快照代替 Windows table subclass。Unix 快照也不代表 Linux／FreeBSD 作業系統、套件或 Fcitx 宿主驗收。

## 僅在 Rust 遷移時手動使用

比較現有實作或 Rust adapter 輸出的 JSONL：

```sh
python3 tests/run_core_functional.py --compare \
  --trace desktop=/tmp/rust-desktop.jsonl \
  --report /tmp/rust-migration-diff.json
```

trace 必須覆蓋同一份語料的所有適用操作與完整快照。工具檢查語料／模型指紋、操作順序及資料格式，再列出每個快照改變的欄位；候選差異包含第一個改變的位置與前後內容，學習差異保留邏輯列。

exit 0 表示在已觀測版本內無差異，exit 1 表示有差異待檢視，exit 2 表示輸入／工具錯誤。這些狀態供遷移人工審閱，不是日常或發布阻擋條件。不要將比較指令加進一般 CI。

需要重播現有核心時，Mac 可明確指定 backend；C++ binary 與隔離使用者資料使用暫存目錄：

```sh
python3 tests/run_core_functional.py --compare --backend desktop --backend unix
python3 tests/run_core_functional.py --compare --backend swift
```

首次擷取到新目錄，或匯入 native recorder 的兩次觀測：

```sh
python3 tests/run_core_functional.py --capture --backend desktop \
  --baseline-dir /tmp/new-rust-reference

python3 tests/run_core_functional.py --capture --backend android \
  --trace android=/tmp/android-first.jsonl \
  --trace android=/tmp/android-second.jsonl \
  --environment 'android=專用模擬器的實際 OS、API、ABI、工具鏈' \
  --baseline-dir /tmp/new-rust-reference
```

原地重錄需要額外明確指定 `--replace-baseline`，並審查差異。不能為了讓 Rust 比較通過而直接更新舊基準。

Live capture 預設使用兩個全新隔離環境，live compare 預設一次，可用 `--samples` 調整。相同觀測會去重，仍保留 `capture_runs`。工具需 Python 3.10+、C++17、SQLite；Mac Unix engine 另連 iconv，Swift 使用 Apple SQLite module。C++ compiler 可由 `CXX` 指定。

## 原生 recorder 的明確啟用方式

Windows 與 Unix 的 `KEYKEY_BUILD_MIGRATION_BASELINE` 預設 OFF，target 標示 `EXCLUDE_FROM_ALL`；**沒有 CTest 註冊，也不是日常 check 的依賴**。

Windows 在既有 CMake configure 上明確啟用，手動建置 `KeyKeyCoreMigrationBaseline`，再以以下參數執行；目前此 target 在 `BUILD_TESTING=ON` 區段：

```text
KeyKeyCoreMigrationBaseline.exe DATABASE FIXTURE OWNED_SCRATCH TRACE.jsonl
```

Unix 明確啟用後手動建置 `keykey_unix_migration_baseline`：

```text
keykey_unix_migration_baseline FIXTURE DATABASE BPMF_CIN OWNED_SCRATCH TRACE.jsonl
```

scratch 必須為空或不存在，由工具建立自己的 case 子目錄；不得指向真實使用者輸入法資料。錄製完成後輸出的 JSONL 可用 `--trace windows=...`／`--trace unix=...` 匯入。原生作業系統未錄製就不建立其假基準。

Swift 的 `CoreFunctionalTests` 預設 skipped；只有設定 `KEYKEY_MIGRATION_BASELINE=1` 才進行 DB／fixture 存取。手動 runner 會設定 `KEYKEY_CORE_FUNCTIONAL_FIXTURE`、`KEYKEY_MIGRATION_TRACE`、`KEYKEY_MIGRATION_SCRATCH`，指定該 suite。

Android 的 recorder 預設以 Assume 跳過；僅在專用模擬器上明確傳入參數：

```sh
adb -s emulator-SERIAL shell am instrument -w \
  -e migrationBaseline true \
  -e class tw.chichi77.keykey.android.CoreFunctionalInstrumentedTest \
  tw.chichi77.keykey.android.test/androidx.test.runner.AndroidJUnitRunner
adb -s emulator-SERIAL exec-out run-as tw.chichi77.keykey.android \
  cat cache/core-migration-trace.jsonl > /tmp/android-reference.jsonl
```

前置為依 Android 既有流程建置並安裝 debug／androidTest APK；`emulator-SERIAL` 須換成專用模擬器。正式模型從當次 APK 讀取，學習及偏好設定只使用隨機建立的測試專用區域，執行後清除；trace 另行匯出。不要對日常使用中的手機執行安裝／錄製。

## 語料格式與邊界

五個 literal-tab 欄位為 `case、profile、method、operation、argument`；空參數仍保留最後一欄。case 列連續且不可改變 profile／初始 method。`#` 開頭為註解。

操作為 `TYPE`、`KEY`、`OPEN`、`SELECT`、`OPTION`、`METHOD`、`REOPEN`、`RESET_LEARNING`。TYPE 逐鍵呼叫核心，但只在列末記錄快照；需要逐鍵觀察時拆列。OPEN 使用從零起算的讀音位置；SELECT 依文字搜尋完整候選並透過真實選字入口選取。OPTION 的已知能力缺口要明列，未知拼字必須失敗。

REOPEN／RESET_LEARNING 要求組字已結束，保留累計送字與各輸入法設定。METHOD 經既有結束組字流程或桌面 adapter 的可見文字保留契約切換，不把四套引擎硬改成一致。

凍結快照是明確指定的遷移參考 fixture，可版本控制；暫存 JSONL、scratch DB、AVD、APK、編譯及執行紀錄仍是產物，不提交。候選與學習快照衍生自既有程式及詞庫，授權範圍沿用 [LICENSING.md](../LICENSING.md) 與原資料聲明，不因錄製而重新授權。

本基準不涵蓋 IMK／TSF edit session、document proxy／InputConnection、Fcitx X11／Wayland 宿主回呼、UI 字型、關聯詞建議、使用者資料升級遷移或 131 篇打字成本。這些原有驗證不可被本基準取代，也不因這份 Rust 參考資料而自動擴大日常測試範圍。

實作：[desktop recorder](../tests/desktop_smart_functional.cpp)、[Unix recorder](../Source/Loaders/Linux-IME/tests/shared_core_functional.cpp)、[Swift recorder](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Tests/KeyKeyEngineTests/CoreFunctionalTests.swift)、[Android recorder](../Source/Loaders/Android-IME/app/src/androidTest/java/tw/chichi77/keykey/android/CoreFunctionalInstrumentedTest.java)。架構方向見 [Rust 共用核心評估](CROSS_PLATFORM_RUST_CORE_ASSESSMENT.md)。
