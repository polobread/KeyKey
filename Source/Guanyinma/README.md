# Guanyinma

Guanyinma 是 **chichi77 KeyKey／琦琦輸入法**（英文簡稱 **KeyKey**） 的新共用 Rust 核心，工作目錄為 `Source/Guanyinma`。目前完成唯讀資料層、C ABI、注音解析與四種輸入法的共用 session；好打注音組句、候選排序、手動選詞與組字邊界以 macOS Manjusri 為準。使用者詞庫、候選偏好、Bigram 與字表學習已接入獨立資料層；原生接合依[實作計畫](../../docs/GUANYINMA_IMPLEMENTATION_PLAN.md)進行。

macOS FE 已提供同一 App 的雙核心建置與一般設定切換，預設選原 Manjusri／Generic，沿用既有 PV 候選與文字管線。組字與候選完成後才由新輸入切換 delegate，並保留建立 session 前回退。建置、原生隔離測試、使用者資料及限制見 [macOS 接合文件](../../docs/GUANYINMA_MACOS_ADAPTER.md)；真正 IMK 宿主與其他平台接合仍待驗證。

## 目前提供

- Rust `ModelDatabase`：傳統注音、倉頡與簡易的完整 exact-match 字表查詢；好打注音 Unigram／Bigram 原始列。
- 低階資料查詢的五種來源均保留 `rowid` 原始順序與合法空字串，不套用候選排序、去重、詞跨度或 mobile 的 64 筆上限。
- 關聯詞查詢、分類排序與去重使用獨立唯讀 API；候選窗與按鍵仍由 FE 負責。
- 注音解析支援標準、許氏、倚天、倚天 26 鍵與漢語拼音；以 macOS Formosa／OpenVanilla 為行為來源。
- `InputSession` 提供四種輸入法的編輯、完整候選、分頁、選字、標點、模式切換及全半形；倉頡另支援 wildcard／前綴與即時候選。每次操作回傳獨立快照與該次 host effects。
- 好打注音 walker 保留 Manjusri 的 BOS／EOS、Bigram／backoff、八音節詞跨度、別名、嚴格分數與原順序的平手處理；手動選詞只固定選中詞段，不提交整句。
- SQLite 以唯讀旗標開啟既存一般檔案，檢查必要 schema、隱含 rowid 與查詢結果型別；缺檔不會建立新資料庫。
- `rlib`、`staticlib`、`cdylib` 三種 Cargo 產物；C／C++ 入口見 [guanyinma.h](include/guanyinma.h)。

資料路徑由呼叫端傳入，不內嵌個人路徑、不複製或重建模型。儲存庫正式來源為 [KeyKey.db](../Distributions/Takao/CookedDatabase/KeyKey.db)。內容雜湊與正式資料完整性仍由既有 [DatabaseCooker 驗證工具](../Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py)負責；Guanyinma 的 open 是執行期 schema／唯讀檢查。

低階查詢仍使用既有字表 code／模型 qstring，例如倉頡 `a`、傳統注音 `\O`。輸入操作則使用下述 session API。macOS、iOS 與 Android 已提供同一 FE 的雙核心建置；iOS 預設選 Swift、Android 預設選 Java 原核心，見 [iOS 接合文件](../../docs/GUANYINMA_IOS_ADAPTER.md)與 [Android 接合文件](../../docs/GUANYINMA_ANDROID_ADAPTER.md)。其他 frontend 的 Guanyinma 接合仍另列階段五。

## 測試範圍與分工

核心專注**無 UI 的公開介面與行為契約**，以 unit／整合及真實 C consumer 驗證四法、排序、學習、10～20 音節、設定與語意操作、快照／effects、callback 與資料生命週期。這些共用規則在核心集中測完；六個 FE 另測自己的事件／設定映射、原生文字座標、一次性宿主交易、字型服務及儲存接合。

Rust 測試在原生 runner 或無視窗的目標模擬器執行，不啟動 FE、不選取系統輸入來源。`GUANYINMA_TEST_MODEL_PATH` 可指定測試程序看得到的共用 DB 複本；省略時使用儲存庫正式 DB。模型維持唯讀，使用者資料只寫隔離暫存。跨目標建置須經 runner 真正執行測試；只有 build／`--no-run` 時只能記為「已編譯、未執行」。

UI 只在各平台 FE 接合時保留少量（數十個）自動化冒煙案例，不逐項重跑核心矩陣。核心工作不占用使用者桌面、不反覆切換其輸入法，也不把大量 FE 端到端驗收當成交付門檻。完整宿主／安裝驗收屬各平台的獨立工作。

CI 的權責固定如下；本機核心開發仍可直接執行後面的獨立測試入口：

| 負責入口 | 範圍 |
|---|---|
| `guanyinma-core.yml` | 完整 Rust unit／整合、C ABI consumer、六平台核心行為與生命週期測試，以及核心格式／警告檢查 |
| 各平台 FE／建置／發布 workflow | 直接依鎖定工具鏈及 `Cargo.lock` 編譯、連結核心；只跑少量載入／session、設定或事件映射、一次送字及釋放的串接冒煙，再完成該平台原有工作 |

平台 workflow 不執行 Guanyinma 的整套 `cargo test`、`tools/test-core.py` 或完整 C ABI driver，也不轉呼叫完整核心 workflow。核心的排序、學習及組字邊界矩陣集中在核心 workflow；FE 的少量測試只驗證原生接合。後續新增平台接合依此分工小幅加入。


## 建置與局部驗證

從本目錄執行；rustup 會讀取 [rust-toolchain.toml](rust-toolchain.toml)。Cargo 依賴固定於 [Cargo.lock](Cargo.lock)。

```sh
cargo build --locked --release
cargo test --locked
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
python3 tests/run_c_abi_test.py --release
```

C consumer driver 需要 Python 3、C11 compiler 與目標平台的 C linker，支援 Unix compiler 及 Windows MSVC。它編譯真實 C 程式連結 library，測試 ABI、所有權、UTF-8、含非 ASCII 字元的使用者 DB 路徑與 copy-out 契約，並核對正式 DB 前後 SHA-256 一致。可用 `CC`、`--cc-json` 或 `--cargo` 指定工具。

預設使用系統 SQLite，開發檔與 runtime 至少需 SQLite 3.34.1。選擇隨核心編譯的 SQLite：

```sh
cargo build --locked --release --features bundled-sqlite
cargo test --locked --features bundled-sqlite
python3 tests/run_c_abi_test.py --release --bundled-sqlite
```

`bundled-sqlite` 編譯 SQLite 程式庫，不生成或 cooker `KeyKey.db`。Android 使用 bundled provider；Windows 單核心的 Rust 與原生 FE 也共用這份 provider 和靜態 CRT，避免 WinSQLite x86 stdcall 與標準 SQLite cdecl 混用，見 [Windows 接合](../../docs/GUANYINMA_WINDOWS_ADAPTER.md)。接進既有 frontend 時要核對 SQLite／CRT 連結及符號，避免重複 provider。六平台原生產物與宿主整合需各自建置及驗收，Mac 上的測試不能代替其他平台。

## 跨平台無 UI 測試入口

[tools/test-core.py](tools/test-core.py) 集中執行 Rust unit／整合測試及真實 C consumer，預設使用 Release；JSON 報告保存實際目標、執行結果、測試數及模型前後雜湊：

```sh
python3 tools/test-core.py --sqlite-provider system --report target/core-system.json
python3 tools/test-core.py --sqlite-provider bundled --report target/core-bundled.json
```

`--model /path/to/KeyKey.db` 可指定唯讀模型複本，亦可用 `GUANYINMA_TEST_MODEL_PATH`。`--cargo` 接受執行檔路徑；`--cc-json` 與 `--runner-json` 接受 JSON argv 陣列，讓含空白的工具路徑不經 shell 拆解。跨目標使用 `--target` 與對應 runner；SDK／linker 由呼叫端設定，CI 的設定入口在 [tools/ci/configure.py](tools/ci/configure.py)。

`--build-only` 只編譯，報告為 `built_not_executed`、`executed: false`，不能當作 runtime 通過。未提供 runner 的非本機目標會拒絕 runtime 測試。`--skip-c-abi` 明確縮小本次範圍；六平台 CI 不使用這個選項。runner 必須執行原測試 binary、保留失敗 exit code，並為 C consumer 帶回實際使用的使用者 DB，不能以傳輸成功代替測試成功。

新增的 [Guanyinma Core workflow](../../.github/workflows/guanyinma-core.yml) 僅處理核心相關路徑，不修改既有平台建置或發布 workflow。六個 matrix 項目共用同一入口，CI helpers 需要 Python 3.11 以上：

| 目標 | 執行環境 | SQLite |
|---|---|---|
| Linux | Ubuntu 原生程序 | system |
| macOS | macOS 原生程序 | system |
| Windows | Windows／MSVC 原生程序 | bundled |
| FreeBSD | FreeBSD VM 原生程序 | system |
| iOS | CI 自建的無視窗 Simulator，由 `simctl spawn` 執行 | system SDK |
| Android | CI 無視窗 emulator，由 `adb` 執行 | bundled |

每項都執行 Rust 測試及 C consumer，附上 JSON 證據；只有成功執行的目標才算驗證。iOS job 只清理自己建立的 Simulator。這些工具不建置 FE、不連接使用者已安裝的輸入法，也不執行 functional baseline。

Android 的 `adb shell` domain 受 [AOSP SELinux 規則](https://android.googlesource.com/platform/system/sepolicy/+/refs/heads/android16-qpr2-release/private/shell.te) 限制，不能建立 hard link。使用者資料保護測試只有在 Android 實際回傳 `PermissionDenied`、程序確認為 `u:r:shell:*` 且別名檔未生成時，才記錄 hardlink fixture 無法執行；其他建立錯誤仍使測試失敗。其餘模型原路徑、symlink、模型複本、非 Guanyinma 資料庫拒絕與原檔不變檢查繼續執行。能建立 hard link 的環境一律實測別名拒絕；Android shell 的通過結果不代表已實測 hardlink。需要檢視 fixture 診斷時，對該測試使用 `--nocapture` 或 `--show-output`。

## 無 UI code coverage

核心正式 Rust 程式碼的行涵蓋率維持 **92% 以上**。參考門檻使用原生 macOS／system SQLite 的 debug instrumentation（本機基準為 arm64），執行既有 Rust unit／整合與真實 C consumer。
只計算 `src/` 的可執行行，動態排除 inline `#[cfg(test)]` item、測試與第三方依賴；
不以物理總行數為分母，也不將 region coverage 當作 branch coverage。

先在本機準備鎖定工具鏈的 `llvm-tools-preview` 元件，再從 repository root 執行：

```sh
python3 Source/Guanyinma/tools/test-coverage.py --offline \
  --report-dir Source/Guanyinma/target/coverage
```

工具支援 `--cargo /path/to/cargo`、`--sqlite-provider system|bundled` 與
`--minimum-line-coverage 92`；不自行下載工具。每次使用獨立 target 和新 profiles，
輸出 `coverage-summary.json`、各檔未覆蓋行、原始 LCOV、排除測試後 LCOV、來源雜湊及 Git 差異。
未達門檻或無法確認測試排除範圍時回傳失敗。CI 只在 `guanyinma-core.yml` 的 macOS
項目量測這個門檻；其他平台仍執行各自的原生核心測試，不能由這個百分比推定六平台覆蓋率。

補測試以實際行為、錯誤處理與資料原子性為準，不為追求 100% 製造不可能狀態；
functional baseline 仍只供手動遷移參考，不參與 coverage 或 gate。

## 關聯詞查詢

`ModelDatabase::associated_phrases`／`guanyinma_database_associated_phrases` 查詢共用
`KeyKey.db` 的 `associated_phrases`。查詢與 session 無關，不建立可寫詞庫；C ABI
接受嚴格 JSON，回傳既有 `GuanyinmaResult`：

```json
{"head":"你","collections":["anime","McBopomofo"],"omit_empty_suffixes":false}
```

結果為 `kind: "associated_phrases"`、`key: "你"`、`rows: ["的名字", ...]`，
`row_count` 是完整候選數。依指定分類順序合併，同來源多筆資料採 `rowid` 最後一筆；
分類內沿用資料列順序，完全相同的字串只保留首次出現。不調整詞頻、不裁切頁數，
也不做空白修整、正規化或字型過濾。空分類陣列表示停用，不能回復成預設分類。

預設逗號拆分保留前導／中間空項並省略最後空項，與 macOS 舊實作一致；
`omit_empty_suffixes: true` 保留 iOS 原本省略所有空項的行為。
`ModelDatabase::associated_collections`／`guanyinma_database_associated_collections`
接受 `{"order":"display"}` 或 `{"order":"source"}`；依 `sortorder`、指定欄位、
`rowid` 排列，回傳 `source`、`display`、`sort_order`。這是排序行為選項，沒有 OS 分支。
兩張關聯詞表按查詢需要驗證，不擴張原有五張必要模型表的 open 契約。

macOS／Windows 的 Rust 路徑將查詢委派到此 API，原核心仍使用舊查詢；路由依實際
運作中的核心。iOS Rust 路徑以同一份 DB 查詢，設定來源的分類選擇每次即時讀取。
候選窗、顯示時機、單字輸入限制、送字、按鍵、翻頁與選字操作留在 frontend。
設定頁的分類清單與詞數載入仍維持既有流程；新的 metadata API 可供後續接合。
Android 的 `.kki` 索引及 Linux／FreeBSD 的分類文字檔仍沿用原解析／查詢路徑；
本項沒有把它們改成共用 DB，避免變更既有字頻門檻、補充漢字與排除規則。
公開 Rust `merge_associated_rows` 可供後續既有資料來源接合時共用相同合併規則。

普通 unit／C ABI 測試涵蓋分類換序、重複詞、同來源覆蓋、空分類、空項政策、
綁定參數、無效資料與結果生命週期。這些測試不讀取 functional baseline。

macOS 的聚焦接線測試使用實際 adapter／OpenVanilla filter 與記憶體候選面板，
不建立視窗、不連已安裝 IMK：

```sh
python3 Source/Loaders/OSX-IMK/Tests/run-associated-phrase-tests.py \
  --library /absolute/path/to/libguanyinma.a
```

iOS 使用既有 `tools/test-ios-swift-package.sh`，可用 `--filter` 選出
`GuanyinmaAssociatedPhraseStoreTests` 及 `associatedQueryUsesModelWhileOverlayAndKeysStayInFrontend`。
這是 macOS host 的 Swift／C ABI 證據，不代替 iOS 實機或 Windows 原生驗證。

## 共用讀音 codec

`reading_codec` 提供不開 DB／session 的 `encode_reading`、`decode_reading`，
由共用 `BopomofoSyllable` 轉換注音文字與兩 byte query key。C ABI 的
`guanyinma_reading_codec` 接受嚴格 JSON，沿用 `GuanyinmaResult` 的 copy-out／close 契約：

```json
{"operation":"encode","reading":"ㄋㄧˇ,ㄏㄠˇ"}
```

結果包含 `kind: "reading_codec"`、`qstring`、`reading` 與 `syllable_count`，
`row_count` 為音節數。Encode 結果的 `reading` 是正規化後的文字；Decode 的
`qstring` 保留輸入原文，`odd_tail: "ignore"` 只影響顯示與音節數。

| 選項 | 行為 |
|---|---|
| Encode `separator` | `comma` 或六種 ASCII 空白的 `whitespace` |
| Encode `components` | `replace_known` 忽略未知字元、同類元件後者覆蓋；`unique_known` 拒絕未知與同類重複 |
| Encode `empty`／`require_phonetic` | `skip`／`reject` 決定空音節；另可要求必須有聲母、介音或韻母 |
| Decode `separator` | `comma` 或 `space` |
| Decode `query` | `canonical` 要求合法範圍；`printable_modulo` 保留舊可列印 overflow key 的元件折回行為 |
| Decode `odd_tail`／`omit_leading_empty` | `reject`／`ignore` 決定奇數尾 byte；另可依累積文字省略前導空音節分隔符 |

預設保留既有 comma composed-text 契約，包括 tone-only、未知字元與同類覆蓋；
MJSR 入口仍另驗證「encode／decode 必須與原文完全相同」及文字 scalar 數。
不重現舊 C++ 對負數 order 的未定義行為，無效 bytes 安全回報錯誤。

目前 macOS 的 Rust 詞庫／MJSR 讀音、Windows Rust 詞庫與 Linux／FreeBSD 詞庫工具
已呼叫此 ABI；舊核心路徑仍保留。iOS／Android 的鍵盤字母、聲調自動切音節等
彈性詞庫輸入語法尚未改接，不能將本項視為六平台的 codec 接線全部完成。
原生檔案與舊加密容器解碼維持 frontend 權責。

下列普通無 UI 對照直接使用目前 Formosa／Manjusri 原始碼，沒有讀取 functional baseline；
在 repository root 執行，`--library` 指向本次相同 SQLite provider 的 staticlib：

```sh
python3 Source/Loaders/OSX-IMK/Tests/run-reading-codec-tests.py \
  --library /absolute/path/to/libguanyinma.a
```

## 行為、狀態與 frontend

核心不依 OS 名稱分支。六平台現有 frontend 是事件、設定與宿主文字操作的接合參考；演算法疑義以 macOS Manjusri／Formosa／OpenVanilla 為主要來源，其他核心的歷史差異保留在手動參考資料中。

`SessionConfig.profile` 的 `desktop`／`touch` 表示互動方式，各平台都能選擇；它們決定候選鍵與觸控預設，並非 OS 對照表。核心維護中英模式、全半形、未完成讀音／字根、候選／頁面／反白等狀態；前端使用原生能力顯示及送字。

`SessionConfig.behaviors` 可逐項設定，`set_behaviors` 操作可在執行中替換整組設定，不提交或清除現有組字；省略欄位使用下列核心預設：

| 行為 | 核心預設 | 效果 |
|---|---|---|
| `ignore_caps_lock_in_chinese` | `false` | 中文模式下，未按 Shift 的 ASCII 大小寫字母均作相同字根／注音輸入；英文及明確 Shift 字元保留 frontend 傳入的文字 |
| `literal_keypad` | `true` | 實際數字鍵盤字元先提交可見組字，再送出該字元，避免進入注音或候選選字；關閉時走一般輸入流程 |

快捷鍵辨識與綁定屬於 FE。核心提供成對的明確設定與切換操作：

| 目的 | 指定狀態 | 切換目前狀態 |
|---|---|---|
| 全形／半形 | `set_full_width { enabled: true/false }` | `toggle_full_width` |
| 英文／中文 | `set_english { enabled: true/false }` | `toggle_english` |

`set_full_width(true)` 指定全形、`false` 指定半形，保持讀音、組字、候選、游標；重複指定不反向切換。`set_english(true)` 指定英文、`false` 指定中文；真正改變中英模式時先保留／送出可見組字，同值設定不重複送字。核心收到 Shift+Space 只按一般 Space 輸入處理，不自行切換寬度。需要此快捷鍵的 FE 解析後改送 `toggle_full_width`，不需要的 FE 可沿用自己的按鍵行為。

`set_profile { profile: "touch" | "desktop" }` 可更新互動分類，保留現有讀音、組字、候選與游標，不送出文字。宿主文字策略改變前仍由 FE 完成舊交易；組字上限及擠字時機另透過 `set_smart_options` 指定。此操作不辨識 OS 或硬體裝置。

平台預設留在 frontend。Windows 沿用既有「忽略 Caps Lock」預設開啟，其他平台預設關閉；這些選擇只轉成上述行為值，不建立 OS 專用核心。單按 Shift 的啟用設定、300ms 按放判定、組合鍵取消與生命週期重設沿用現有 frontend，判定成功送一次 `toggle_english`，或由 FE 算好目標後送 `set_english`。切換會先保留可見組字；macOS 先完成宿主保留交易，再送指定模式。`set_english` 可重複呼叫而不重複送字。

`character.text` 是 frontend 傳入的一個非控制 Unicode scalar；特殊鍵使用 `key`。實體鍵位、Shift 字元與英文大小寫仍由 frontend 翻譯。`modifiers.num_lock` 是全域鎖定狀態，不影響主鍵盤；`modifiers.keypad` 才表示實際數字鍵盤來源。NumLock 關閉後的導航／刪除用特殊鍵事件傳入，不偽造數字字元。Ctrl／Alt／Command 數字鍵盤組合及 key release 不送字。

倉頡前綴候選共用 `Source/Shared/CangjieRankingData.h` 與 `CangjieUnicodeData.h`，Cargo 只在 OUT_DIR 產生 Rust 常數；exact 字碼在前，再依既有排名補最多 36 字。wildcard 保留完整來源順序，不套用前綴上限。原生候選視窗交由 frontend。

FE 以 `guanyinma_session_open_with_candidate_filter` 注入自己的字型／編碼能力；Rust 介面為 `InputSession::open_with_candidate_filter` 與 `CandidateFilter::new`。C callback 型別為 `int32_t (GUANYINMA_CALL *)(void *context, const uint8_t *text, size_t text_length)`：同步收到有效 UTF-8 span，回傳 0 拒絕、任何非 0 值接受。核心在四種輸入法查詢後、單候選自動提交、前綴最多 36 字、分頁與選字學習之前過濾；好打注音在 Unigram、自訂詞與 Bigram 的 current 節點建立 graph 前套用，BOS／EOS 邊界除外。低階 database query 與直接輸入的文字不受此過濾影響。關閉回呼（NULL）與原 `guanyinma_session_open` 接受全部的行為相同，context 會被忽略。

callback 的文字只在該次呼叫有效，不含尾端 NUL；不可保存指標、拋出例外／unwind 或重入同一 session。函式與 context 由呼叫端持有到 session close，能力判斷在此期間須保持一致；每次 open／session operation 在呼叫執行緒同步執行回呼。session 互斥不保證其他 session 共用 context 的安全，FE 必須自行同步。callback／context 不進入 JSON、使用者資料或備份。六大平台各自接上原生字型／編碼服務，核心不建立 OS 分支；macOS、Windows、iOS、Android 與 Linux Fcitx 5 已有各自的原生 adapter；實際桌面／裝置與 FreeBSD 原生雙核心驗證仍各自記錄，Linux 接合入口見 [adapter 說明](../../docs/GUANYINMA_LINUX_ADAPTER.md)。

## 好打注音的行為與座標

`method: "smart"` 使用共用 Manjusri walker。`SessionConfig.smart` 與 `set_smart_options` 接受下列設定；它們由 FE 選擇，與 OS 無關。執行中替換設定會關閉候選，保留讀音、游標及手動選詞；評分設定變更時重算組句，不送字。省略欄位回到預設值。

| 設定 | 預設 | 行為 |
|---|---|---|
| `shift_always_uppercase` | `false` | 明確 Shift 英文字元強制大寫；實體鍵盤到文字的轉譯仍由 FE 處理 |
| `use_bigrams` | `true` | 啟用 Bigram 與前文 backoff；關閉時以 Unigram 評分 |
| `max_completed_syllables` | `10` | 組字音節上限，**10～20 可選** |
| `shift_at_limit` | `false` | 關閉時超過上限才擠字；開啟時到達上限就擠字 |
| `space_opens_candidates` | `true` | 空白鍵開候選；關閉時在組字中插入空白 |
| `candidate_cursor_at_end` | `false` | 開啟時找結尾在游標的候選；關閉時找覆蓋游標位置的候選 |
| `selection_returns_to_end` | `false` | 選字後回句尾，後續輸入接句尾；關閉時保留主要來源的選字游標行為 |
| `clear_composing_with_escape` | `false` | 無未完成讀音時，Esc 是否清除整句 |
| `candidate_selection_keys` | `null` | 預設八鍵，依注音配置使用 `12345678`、`asdfzxcv` 或 `asdfjkl;` |

例如 `max_completed_syllables: 10, shift_at_limit: false` 保留十個已完成音節，第十一個完成才擠出；相同上限搭配 `shift_at_limit: true` 可保留既有九／十邊界。擠字一律移出最前方完整詞段並固定下一詞段，必要時連同開頭半形空白移出；送出後的前段不在可編輯 graph 內。上限二十使用同一規則。

`open_candidates.index` 是零起算的已完成讀音位置；`set_cursor.index` 是讀音之間的游標，範圍 `0..=readings.len()`。`close_candidates` 只關閉候選並保留組字與游標。`select.index` 仍是當頁索引，快照中的 `candidate_spans` 提供完整候選的讀音跨度與 query，`segments` 提供目前詞段與分數。

好打注音快照的 `composition` 是已完成的組句，`reading`／`phonetic` 是未完成讀音，`visible_text` 將讀音插入組字游標。`cursor` 以 `visible_text` 的 Unicode scalar 計數；`reading_cursor`、`readings`、詞段及候選跨度使用讀音座標。FE 負責轉換 UTF-16 或原生文字範圍。

`use_bigrams` 是共用模型行為，可對應 Android 現有的上下文選字開關；預設仍使用 Manjusri 的完整上下文評分。切換保留可見的未完成讀音與手動選詞，使用既有節點重新計算路徑，保留上下文快取供再次啟用。

目前原生設定與核心欄位對應如下；FE 讀取各自既有偏好並明確傳入值，不依平台名稱推導核心規則：

| 現有設定／行為 | Guanyinma 入口 |
|---|---|
| `ComposingTextBufferSize` | `smart.max_completed_syllables`，10～20 |
| 實體十／十一、觸控九／十擠字時機 | `smart.shift_at_limit`，可搭配上限十 |
| `ShowCandidateListWithSpace`、`smartSpaceSelectsCandidates` | `smart.space_opens_candidates` |
| `CandidateCursorAtEndOfTargetBlock` | `smart.candidate_cursor_at_end` |
| 選詞後後續輸入接句尾 | `smart.selection_returns_to_end` |
| `CandidateSelectionKeys`／固定 1–9 | `smart.candidate_selection_keys` |
| `ClearComposingTextWithEsc` | `smart.clear_composing_with_escape` |
| `smart_bigram_enabled` | `smart.use_bigrams` |
| `IgnoreCapsLockInChinese` | `behaviors.ignore_caps_lock_in_chinese` |
| 真正的數字鍵盤輸入 | `modifiers.keypad` 與 `behaviors.literal_keypad` |
| 單按 Shift／中英切換按鈕 | FE 辨識後送 `toggle_english` 或 `set_english` |

同名快捷鍵不代表同一操作，例如 Ctrl+反斜線在 macOS 切換中文輸入法，Windows／Linux 則切換中英；由 FE 轉成正確的共用操作。字型／編碼能力過濾與繁簡輸出、視窗、聲音、更新及偏好儲存維持原生接合範圍；使用者資料透過下述共用介面管理，不把舊儲存格式直接當成核心行為。

手動選詞先固定目前 graph；是否另記候選偏好及相鄰詞關係，由 `learning` 行為設定決定。共享正式模型一律唯讀。

## macOS 設定與行為對照

完整對照表與驗證入口見 [macOS 四種輸入法行為覆蓋](../../docs/GUANYINMA_MACOS_BEHAVIOR_COVERAGE.md)。注音配置支援原生名稱與舊配置別名；未知編碼依原核心正規化為系統字型判斷。倉頡／簡易的進階行為由 `TableOptions` 指定：

| 欄位 | 省略時 | 用途 |
|---|---|---|
| `maximum_radical_length` | 倉頡 5、簡易 2 | 明確碼長 1～128 |
| `space_as_first_selection_key` | `false` | Space 作第一候選鍵，其餘候選鍵依序後移 |
| `space_commits_first_on_single_page` | 倉頡開、簡易關 | 單頁 Space 選第一候選；關閉時沿用翻頁 |
| `wildcards` | 倉頡 `?`／`*`、簡易停用 | `one`／`many` 可選非空白 ASCII 字元；明確 `null` 可分別停用 |

簡易缺省 `clear_on_error` 為關；即時候選開啟時不清錯碼。只有明確選字才增加學習，輸入下一字根而隱式送出反白候選不記成偏好。`direct_text` 是原生直接文字事件的語意操作：傳統注音／字表按原核心取代未完成字根，好打注音按單一 graph 區塊插入；這與生命週期的 `finish` 操作不同。

好打注音可圈選最多六個已完成讀音，快照 `marked_phrase` 提供讀音範圍及 Unicode scalar 文字範圍。確認時原子新增目前 graph 產生的詞條，`effects.phrase_feedback` 回報文字及是否新增，不提交整句。既有詞只回報未新增；跨 session 更新使圈選失效時拒絕舊確認，不按舊位置新增另一個詞。圈選可包含原生 graph 的標點／直接文字 query；外部手動詞庫編輯仍使用原本的標準注音驗證。

## 使用者詞庫與學習

FE 可傳 `user_database` 指定獨立的 Guanyinma SQLite 檔。未指定時只建立 session 私有的記憶體資料庫。核心不搜尋平台使用者目錄；正式 `KeyKey.db`、其 symlink／hardlink 不能當成可寫使用者檔，既有非 Guanyinma 檔案不會原地改版或修復。

`SessionConfig.learning` 與 `set_learning_options` 分開控制讀取自訂詞與寫入學習：

| 欄位 | 核心預設 | 用途 |
|---|---|---|
| `user_phrases` | `true` | 組句查詢合併使用者詞；管理操作仍可新增、修改、刪除 |
| `candidate_overrides` | `false` | 記住明確選取的好打注音候選，最多 200 個 query |
| `bigrams` | `false` | 記住明確選詞與前一詞段的相鄰關係，最多 200 組 query |
| `table_learning` | `false` | 開放字表選字學習，另須該方法的 `learn_selection` 啟用 |

`TableOptions.learn_selection` 的倉頡預設為開、簡易為關；只有全域 `table_learning` 也開啟時才寫入。FE 依現有設定明確提供選擇，核心沒有 OS 預設分支。

學習採 macOS Manjusri／Generic 的觸發規則：

- 明確選取當時非首位的好打候選會記住偏好；明確選取當時首位則移除既有偏好。此處指已受偏好排序影響的「當時首位」。
- 自動組句、直接確認與擠字不建立候選偏好。標點、passthrough、控制符號及注音符號不記成文字偏好。
- 相鄰詞學習只在明確選詞後觸發，不包含 BOS／特殊目標；關閉 `smart.use_bigrams` 時暫停新相鄰詞學習，保留舊資料。
- 倉頡／簡易只增加非首位且屬完整字碼的候選計數；前綴補充候選不記。順位依計數遞減，同分保留首次記錄順序。
- 新自訂詞使用正式模型的最高 Unigram 分數（零時為 -1e-7）與 UNK backoff；不改正式詞頻。

每次 apply 將本次 delta 原子保存。模型查詢、資料驗證及快照準備在提交前完成；寫入失敗會恢復 session，不回傳可重複套用的送字效果。不同 session／程序只合併本次變更，不回存整份舊快照；reset generation 防止舊學習復活。`save_learning` 是明確 checkpoint，close／Drop 不隱式寫入。跨程序同步後若候選文字與跨度相同，保留頁面與反白；若候選已改變，該次舊候選操作回傳 beep 並關閉候選，不以舊索引選新字或直接送出整句。

管理操作使用嚴格 JSON：

```json
{"type":"add_user_phrase","qstring":"0_0_","text":"士事"}
{"type":"update_user_phrase","qstring":"0_0_","text":"士事","new_qstring":"0_0_","new_text":"事士"}
{"type":"remove_user_phrase","qstring":"0_0_","text":"事士"}
{"type":"replace_user_phrases","phrases":[]}
{"type":"reset_learning"}
{"type":"reset_method_learning","method":"smart"}
{"type":"save_learning"}
```

新增／編輯接受 1～8 個文字與對應的完整二位 qstring 讀音；既有正式詞或相同自訂詞不重複新增。編輯一次提交舊詞移除與新詞加入，失敗保留舊詞。`reset_learning` 保留自訂詞；`reset_method_learning` 可只重設好打注音、倉頡或簡易，保留其他方法的學習。

`replace_user_phrases` 接受完整 `Unigram` 列（`qstring`、`current`、`probability`、`backoff`），先驗證整批，再原子替換自訂詞，包括來源已刪除的詞；保留所有學習與 generation。空陣列清除自訂詞，相同順序與內容為 no-op。它供 FE 同步自己的詞庫發布，不隱含匯入其他核心資料。

舊 SQLite 資料需明確 `import_legacy_user_data`，來源始終唯讀，輸出存入不同的 Guanyinma 使用者資料庫。支援既有 `user_unigrams`、候選偏好／Bigram cache 與 Generic `user_frequency`；Generic 匯入須另傳 `method: "cangjie"` 或 `"simplex"`。只替換來源所涵蓋的學習範圍，保留其他輸入法與既有自訂詞；不刪除來源、不中途覆寫唯一副本。加密或未知 schema 會回報錯誤，交由 FE 先匯出相容資料。

Rust `InputSession::user_data()` 與 C `guanyinma_session_user_data` 提供一致、獨立擁有的完整資料快照，供詞庫編輯與匯出，不產生 host effects。一般輸入快照的 `user_data` 只包含 generation／revision 與數量摘要，避免每鍵複製整份詞庫到 FE。

## 可攜使用者封存

`UserArchive::from_snapshot` 產生完整資料備份，排除本機 generation／revision；不含平台路徑或 SQL。共用格式為：

```json
{
  "format": "guanyinma_user_data",
  "schema_version": 1,
  "phrases": [],
  "smart": { "overrides": [], "bigrams": [] },
  "table": []
}
```

`phrases` 的列使用 Unigram 欄位，`smart` 使用既有候選偏好／Bigram 列，`table` 使用含 method/code/current/count 的字表學習列。所有欄位嚴格解碼，未知欄位、重複鍵、非有限數字及超過快取上限的資料會失敗。

`import_user_data` 接受 `archive` 物件，透過既有預覽與原子交易提交。自訂詞合併且保留同讀音／同文字既有詞的分數；`smart` 或 `table` 缺少／null 時保留該域，明確提供（包括空陣列）則替換該域。學習替換推進目的地的世代，防止舊 session 學習回存；不匯入來源的本機 epoch。無效資料或寫入失敗不產生部分提交或 host effects。

純 C ABI `guanyinma_user_archive_validate` 在不開 DB／session、不碰檔案的情況下驗證原始 UTF-8 JSON，讓 FE 在解碼容器與匯出前沿用同一契約。實際匯入時再次驗證。macOS FE 另提供檔案讀寫、原子匯出及舊 MJSR 容器解碼，見 [macOS 接合文件](../../docs/GUANYINMA_MACOS_ADAPTER.md)；這些平台工作不進入共用引擎。

## C ABI 契約

- `guanyinma_abi_version` 回傳 ABI 版本；與產品版號分開。
- database/session open、query/apply 回傳 Rust 擁有的 opaque handle，使用配對的 `*_close(&handle)` 釋放並將該 slot 清空；同一個已清空 slot 可重複 close。不得使用或再次釋放其舊副本。
- result 是獨立不可變快照，原 DB／session 關閉後仍有效。
- JSON 與 error 字串複製到呼叫端配置的 buffer；先用 null／零容量取得需求，`required` 包含結尾 NUL。容量不足不寫入部分內容。
- 路徑／鍵為 UTF-8 byte span，拒絕內嵌 NUL、無效 UTF-8 及超長 span；指標可讀寫性、對齊、有效生命週期與不重疊仍由呼叫端負責。
- 同 DB 的 query、同 session 的操作各由 Rust mutex 序列處理；close 不得與讀取或其他 close 同時執行。不可變 result 可並行讀取。
- 可回復的 Rust panic 留在邊界內，回傳狀態及 thread-local 診斷；abort、OOM、無效呼叫端指標不屬可回復錯誤。
- 不提供任意 SQL、任意 table name 或模型寫入；使用者資料寫入限於上述受驗證的共用操作。

低階查詢 JSON 包含 `schema_version`、`kind`、`key`、`rows`；資料表 rows 是字串，Unigram／Bigram rows 保留原欄位與分數。

session open 接受 UTF-8 設定 JSON（空 span 使用預設）。例如由 frontend 開啟所需行為：

```json
{"method":"traditional","profile":"desktop","layout":"standard","behaviors":{"ignore_caps_lock_in_chinese":true,"literal_keypad":true}}
```

apply 接受帶有 `type` 的嚴格 JSON；未知欄位、無效文字與超出範圍的選字索引均回傳錯誤並保留狀態：

```json
{"type":"character","text":"s"}
{"type":"character","text":"2","modifiers":{"keypad":true,"num_lock":true}}
{"type":"key","key":"space"}
{"type":"select","index":0}
{"type":"set_behaviors","behaviors":{"ignore_caps_lock_in_chinese":false,"literal_keypad":true}}
{"type":"toggle_english"}
```

其他操作包含 `page`、`move_highlight`、`open_candidates`、`close_candidates`、`set_cursor`、`set_smart_options`、`set_method`、`set_layout`、`set_table_options`、`set_english`、`finish`、`reset`。設定／快照欄位與完整鍵名見 [engine.rs](src/engine.rs)；C 呼叫例見 [c_abi_smoke.c](tests/c_abi_smoke.c)。

session result 包含 `composition`、底層 `phonetic`／`code`、完整 `candidates`、當頁 `displayed_candidates`、頁面與反白、中英／全半形／行為設定，以及 `effects`（`commit`、`handled`、`beep`、`delete_backward`、`send_return`、`discard_composition`）。游標以 Unicode scalar 計數，frontend 需轉為自己的 UTF-16 或宿主範圍。`snapshot` 沒有新的 effects，避免重複送字；session result 的 row count 是完整候選數。

## 驗證用途與授權

本目錄的單元／整合／C ABI 測試只驗證新核心的實作契約。既有 [functional baseline](../../docs/CROSS_PLATFORM_CORE_FUNCTIONAL_TESTS.md) 僅供遷移至 Guanyinma 及核心升級時手動參考，不加入日常驗證、CI gate 或發布門檻。

手動差異工具必須明確指定 library 與報告路徑，輸出只供人工遷移審查；不會更新舊基準，也不由 Cargo／CI 自動執行：

```sh
python3 tools/compare_migration_phase2.py \
  --library target/release/libguanyinma.dylib \
  --report target/migration-phase2-macos.json
```

上述階段二工具仍保留原範圍；第三階段可明確執行 `tools/compare_migration_phase3.py` 並傳入相同的 `--library`、`--report` 參數。它保留階段三範圍，學習／保存仍具名跳過。第四階段使用 `tools/compare_migration_phase4.py`，除 `--library`／`--report` 外必須提供全新或空的 `--scratch`，為每個案例建立隔離的使用者檔；不修改凍結參考資料，也不加入日常驗證。舊原生六位小數序列化與新資料完整浮點精度的差異會另外列為報告註記，不改寫來源或降低新資料精度。

原創 Guanyinma 程式與測試適用 [MIT](LICENSE.txt)；舊碼衍生移植、模型及 Cargo 第三方依賴維持各自授權，詳見 [LICENSING.md](../../LICENSING.md) 及 [THIRD-PARTY-NOTICES.md](../../THIRD-PARTY-NOTICES.md)。
