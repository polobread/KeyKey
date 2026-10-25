# Guanyinma iOS 接合

KeyKey 的 iOS 鍵盤 extension 與容器 App 實體鍵盤編輯器共用同一套 frontend，可選 Swift 原核心或 Guanyinma Rust 核心。新安裝與無效偏好預設使用 Swift；這是 iOS 原有的 Swift 引擎，不是 Manjusri。其他平台的接合與宿主驗證須各自完成。

## 共用介面與核心選擇

`KeyKeyEngine` 的 `InputEngine` 定義按鍵、候選、組字與宿主效果介面。`BopomofoEngine` 保留 Swift 實作，`GuanyinmaInputEngine` 經正式 C ABI 呼叫 Rust，`DualCoreInputEngine` 代理目前使用的核心。UIKit 控制項、輸入欄位政策、硬體快捷鍵辨識、關聯詞與符號介面留在 iOS frontend；adapter 不另寫注音解析、walker 或候選排序。

核心偏好使用 `InputCoreSettings`：

```swift
let settings = InputCoreSettings(sharedDefaults: sharedDefaults)
settings.setCore(.guanyinma)
let preferred = settings.core
```

它沿用 `KeyboardPreferenceStore` 的每項設定 revision。容器 App 設定頁以 `writesShared: true` 寫入 App Group；鍵盤與編輯器自己的修改留在各自的偏好。較新的 App revision 才覆蓋該項私有值，其他設定的變更不會清除核心選擇。

選項位於容器 App「輸入法設定」、鍵盤「設」頁，以及實體鍵盤編輯器的輸入法選單。偏好與實際使用核心分別由 `requestedCore`、`activeCore` 表示；無法開啟 Rust 時顯示 `coreError`，保留已存在的核心處理目前輸入。

## 宿主效果與切換邊界

`requestCore(_:)` 只提出切換要求。代理須等到下列狀態全部完成，才使用新核心：

- 沒有組字或未完成讀音。
- 沒有候選互動，包括 frontend 的符號／關聯詞候選。
- 前次回傳的文字、刪除及 Return 已由原宿主處理。

frontend 先把 `BopomofoEngine.Result` 套用到原宿主，再呼叫 `acknowledgeHostEffects()`。不得先切核心後重新播放按鍵、重送整句，或把尚未套用的效果留給新核心。重複生命週期交接須保持冪等。

觸控好打注音已把完成文字插入宿主，`TouchSmartHostTextState` 只追蹤仍可替換的尾段。換核前須用舊核心結果完成該尾段；不能把同一段文字再次插入。傳統注音等模式則沿用 `UITextDocumentProxy` 的 marked text。延後的 marked 更新與宿主變動回呼須使用 generation 防止舊工作套到新核心或新欄位。

實體鍵盤編輯器處理自己的文字區與游標。`InputEngine` 提供的 UTF-16 caret 是給 UIKit 的位置；Rust scalar 位置的轉換由 adapter 處理。

## 候選可顯示性與組字範圍

兩核心都使用 `CandidateGlyphSupport.shared.canDisplay` 的 CoreText 字型判斷。Rust adapter 將它傳給 `guanyinma_session_open_with_candidate_filter`，並持有 callback context 到 session 關閉。過濾發生在核心候選、排序、分頁與好打 graph 之前；frontend 不另外刪除畫面候選，避免數字鍵與分頁索引錯位。字型快取只存在記憶體。

觸控與實體鍵盤由 FE 設定行為，而非 Rust 判斷 OS：

| 輸入入口 | Rust profile | 音節上限與擠字 | 選字後位置 |
|---|---|---|---|
| 鍵盤 extension | `touch` | `max_completed_syllables = 10`、`shift_at_limit = true`；第十音節擠出前方完整詞段，維持九個可修改音節 | 回句尾 |
| App 實體鍵盤編輯器 | `desktop` | 同樣上限十、`shift_at_limit = false`；第十一音節才擠出完整詞段 | 保留編輯位置 |

已擠出的文字不再接受候選或 Backspace 修改。候選每頁沿用 iOS 的九格；倉頡即時候選／前綴選字維持虛擬與實體兩組設定。快捷鍵與半／全形辨識由 FE 處理，核心接收語意操作。

## 共用模型與私有資料

模型仍是 `Source/Distributions/Takao/CookedDatabase/KeyKey.db`，由 Xcode 複製到 `Keyboard.appex`；容器 App 唯讀使用該 extension 內的同一份檔案。建置只驗證與複製，不 cooker、不因切核心改模型。

App Group 固定為 `group.io.github.polobread.inputmethod.chichi77.ios`。維持 `RequestsOpenAccess = false`：App 發布自訂詞，extension 只讀取，學習資料留在各自沙箱。

| 檔案 | 位置與權責 |
|---|---|
| `UserPhrase.db` | App Group；Swift 自訂詞，由容器 App 管理、extension 唯讀 |
| `SmartMandarinLearning.db` | 各入口私有 Application Support；Swift 好打注音學習 |
| `GuanyinmaUserPhrase.db` | App Group；Guanyinma 專用自訂詞，由 App 的 FE 詞庫工具管理、extension 唯讀 |
| `GuanyinmaPhraseBridge.db` | 各入口私有 Application Support；FE 詞庫工具所需的獨立資料檔，不作 Rust 引擎的學習來源 |
| `GuanyinmaUser.db` | 各入口私有 Application Support；Rust 自訂詞快照、選字與 Bigram 等核心資料 |

App 與 extension 的私有 Application Support 是不同目錄；相同檔名不代表共享學習。Guanyinma 不自動匯入 Swift 自訂詞、倉頡排序偏好或學習。FE 只從 Guanyinma 專用詞庫讀取完整詞條快照，再以 `replace_user_phrases` 原子同步到私有 Rust DB，讓 App 的刪除與編輯也能反映，同時保留該入口自己的學習。

自訂詞管理頁在開啟時固定 `InputCore`，標題與所有 CRUD／匯入／匯出使用同一核心；之後其他畫面改核心偏好，不會讓舊詞庫列改到另一個核心。現有 `MJSR version 1.0.0` 自訂詞段落仍由 FE 工具匯入／匯出，不隱含轉移加密學習資料。Rust 詞庫的匯出檔名為 `KeyKey-Guanyinma-UserPhrases.mjsr`。

學習重設也依核心分派。`KeyboardLearningResetRequest(core:)` 為兩核心保存獨立的要求與已套用標記；重設成功才消耗要求，儲存失敗保留重試。Swift 沿用原偏好鍵；Rust 使用獨立鍵。App 的 Rust 重設呼叫 `GuanyinmaInputEngine.resetLearning(modelURL:userDatabaseURL:)`，鍵盤使用自己的私有 DB 執行要求，自訂詞保留。

## 建置與少量串接驗證

`KeyKeyEngine` 的 C target `CGuanyinma` 匯入共用 `guanyinma.h`；Swift adapter 透過它連結靜態 `libguanyinma.a`。Xcode 的 `Guanyinma Core` aggregate target 先執行 `Source/Guanyinma/tools/build-ios-core.sh`，App、extension 與測試 target 再從 `$(BUILT_PRODUCTS_DIR)/Guanyinma/$(PLATFORM_NAME)` 連結同一份產物。

建置主機須有 Xcode、`Source/Guanyinma/rust-toolchain.toml` 指定的 Rust toolchain，以及實際架構需要的標準函式庫 target：`aarch64-apple-ios`（裝置）、`aarch64-apple-ios-sim`（Apple Silicon simulator）、`x86_64-apple-ios`（Intel simulator）。腳本依平台／架構選 target，只做 `cargo build --lib`，不開啟模擬器或執行核心測試。SQLite 連結 Apple SDK 的系統版本，與既有 Swift SQLite 共用 provider。

Xcode Cloud 的 `ci_scripts/ci_post_clone.sh` 要求建置環境事先提供 `rustup`，可由 `PATH` 或既有 `CARGO_HOME/bin` 找到。hook 只透過該工具準備版控指定的 toolchain 與上述三個 iOS 標準函式庫 target，再驗證共用模型；不下載並執行遠端 shell 安裝器，也不自行安裝 `rustup`。未預備 `rustup` 的環境會明確失敗，因此不能把本機編譯視為全新 Xcode Cloud 環境已可建置。GitHub 的 iOS 封裝流程使用獨立的 pinned toolchain Action 準備相同輸入。

在儲存庫根目錄，可只編譯 simulator 產物：

```sh
xcodebuild -project Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj \
  -scheme "chichi77 KeyKey" -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

在 Mac 執行少量 Swift 串接／設定測試，先由 wrapper 準備 host 架構的 Rust 靜態庫：

```sh
bash Source/Guanyinma/tools/test-ios-swift-package.sh --filter InputCoreSettingsTests
bash Source/Guanyinma/tools/test-ios-swift-package.sh --filter GuanyinmaIntegrationTests
```

`KEYKEY_GUANYINMA_HOST_BUILD_DIR` 可指定 host 產物目錄，`KEYKEY_SWIFT_PACKAGE_PATH` 可選擇其他依賴 `KeyKeyEngine` 的本地 package。`CARGO`、`CARGO_HOME`、`RUSTUP_HOME` 沿用呼叫端；已備妥 toolchain、targets 與依賴時，可設 `KEYKEY_GUANYINMA_OFFLINE=1` 禁止 Cargo 取網路。wrapper 只準備核心建置與執行所指定的 Swift tests，不轉呼叫完整 Rust／C ABI 測試。

CI 完整核心驗證只由 [Guanyinma Core workflow](../.github/workflows/guanyinma-core.yml) 負責；iOS workflow 直接編譯／連結核心，僅保留少量 frontend 串接冒煙。iOS 封裝只選 `GuanyinmaIntegrationTests|InputCoreSettingsTests`；既有 Swift 演算法測試仍可由本機 wrapper 依修改選跑。冒煙涵蓋雙核心選擇、安全邊界、基本輸入／候選與獨立資料，不重新做一套 Rust 行為回歸。一般 Swift 測試不讀遷移 functional baseline。

原始碼接合、host Swift 冒煙、iOS 裝置／simulator 編譯，以及真正 keyboard extension 宿主輸入是不同證據。編譯或 Mac package tests 不代表 extension、實機或商店版本已完成驗收；本文件不以測試通過數取代驗收紀錄。
