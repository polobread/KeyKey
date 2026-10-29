# Guanyinma macOS 接合

macOS 四種輸入法固定使用 Guanyinma Rust 核心，沿用既有原生 FE、模組識別字、候選窗與文字管線。產品不編譯 Manjusri／Generic 輸入引擎，不提供核心選單、建置開關或失敗回退。舊來源與 functional baseline 僅供明確手動的遷移參考；各平台宿主及正式安裝驗收分別記錄。

## 建置

標準 `Takao-macOS.xcconfig` 與 OSX-IMK target 必須編譯、連結 Rust。請依 [BUILDING.md](../BUILDING.md) 準備鎖定的 Rust 工具鏈、Xcode 與 OpenSSL。

```sh
# CARGO 可指定已安裝的 cargo executable；工具鏈由 crate 固定。
# 依賴已快取時加 KEYKEY_GUANYINMA_OFFLINE=1。
(cd Source && xcodebuild -project Takao.xcodeproj \
  -target 'Takao (Loader OSX-IMK)' -configuration Release \
  -xcconfig Takao-macOS.xcconfig \
  CODE_SIGNING_ALLOWED=NO build)
```

建置腳本在 Xcode 的 derived 目錄產生 Rust staticlib 與完整 runtime notices，使用 SDK 的系統 SQLite；不 cooker、不改正式 DB、不將 archive 存入原始碼。App 的 `Contents/Resources/GuanyinmaNotices.txt` 隨包保留核心、依賴及來源授權。現有架構設定為 arm64；腳本也能對應 x86_64，但 Intel 工具鏈、依賴與產物仍須另驗證。

舊 `UseGuanyinmaCore` 偏好不再讀寫，即使保存為 `NO` 也不影響單核心產品。舊使用者資料檔不自動開啟、改寫或刪除；需要搬移資料時，使用明確的 MJSR 匯入。

這是 Guanyinma 工作分支的建置狀態，不代表已發布版本已變更。建置與 ZIP 不代替簽章、安裝或實際文字宿主驗收。

## 安裝程式

標準版本沿用 [macOS Installer 流程](../Installer/README.md#local-guanyinma-installer)：
以標準 macOS xcconfig 建置同一個 App，再執行 `Installer/build.sh APP_PATH`。產物為
真正的 `chichi77KeyKey.pkg` 及 `.pkg.zip`，包含標準安裝腳本與
`KeyKeyInputSourceTool`，安裝位置固定為
`/Library/Input Methods/chichi77 KeyKey.app`。

本機流程會將 staged App 及 helper 重新做 ad hoc 簽章；未提供 Developer ID
與 notarization 時，PKG 不宣稱正式簽章或公證。驗證須展開實際 PKG，核對 payload
的 Rust 程式、版本、DB、腳本、helper、relocation policy 及簽章。展開驗包與
實際安裝／IMK 文字宿主驗收分開。

## Session 與設定生命週期

四種輸入法直接由 `GuanyinmaCreateModulePackage` 建立 Rust context。設定快照由 adapter 擁有；更新等待原生讀音、組字、候選及尚待宿主接收的 commit 都完成後才採用，不重播事件。clear、deactivate 及候選回呼沿用既有 FE 交易規則。

詞庫管理固定使用 Guanyinma store。詞庫編輯器仍以快照與 backend token 檢查請求，舊 Manjusri token、未知 token 或無效內容在修改前拒絕；儲存失敗不改寫舊 profile。

## 原生流程與資料

`GuanyinmaMacAdapter` 提供好打注音、傳統注音、倉頡與簡易的獨立 module，保留正式模組識別字、名稱及 PV sandwich。輸入狀態、組句、候選排序與學習經 C ABI 執行；候選視窗、快捷鍵辨識、組字送出、關聯詞互動及 around／output filters 留在 FE。關聯詞查詢、分類順序與去重固定透過唯讀 Rust C ABI；提供 query provider 時不開啟舊 SQL 查詢。macOS 的單按 Shift 中英切換仍由 controller 保留組字後切換模式。

讀取共用 `KeyKey.db`，使用者詞庫與學習固定另存於 loader writable 目錄下的 `GuanyinmaUserData.db`。不自動匯入舊資料。好打注音詞庫編輯、保存與重設只操作 Rust store；重設只清好打學習，保留自訂詞與其他方法學習。開啟／寫入失敗會回報失敗，不回退舊資料庫。

既有匯入／匯出命令接到同一個 Guanyinma store：

- **匯出**為版本化的 Guanyinma JSON，完整保存自訂詞、好打候選偏好／Bigram 與字表學習；不輸出本機 generation／revision。目標以同目錄私有暫存檔完整寫入、同步後原子替換，失敗保留原備份。
- **匯入**接受這份 JSON，或舊版 `MJSR version 1.0.0` 封存。先完整解析並經共用核心驗證，再以一次 `import_user_data` 交易提交。自訂詞依讀音與文字合併，已有詞的分數不覆寫；來源明確提供的學習範圍會替換，缺少／null 的範圍保留。
- MJSR 只有自訂詞且沒有 learning section 時保留既有學習；有完整 section 時只替換好打注音學習，保留倉頡／簡易。CRLF 可讀；壞行、壞數字、重複鍵、壞十六進位、截斷或無法解碼的 cache 都整份失敗。
- MJSR 的內嵌 SQLite 可由現有 macOS 匯出程式產生加密內容。FE 使用系統 SQLite、原有 `mjsrexport` 格式金鑰及唯讀 attachment，在私有暫存目錄解碼；Rust 只接收已驗證的共用資料，不加入 Apple codec 或 OS 判斷。未知 provider／加密格式會回報失敗，不降成只匯入文字。

匯出保護共用模型、Guanyinma store、已知舊版使用者 DB 及其 hardlink／symlink 別名，不用備份覆蓋唯一資料副本；舊資料不會自動匯入。一般封存上限 64 MiB，MJSR 內嵌資料庫上限 32 MiB。新的 JSON 可完整表達字表學習，因此此入口不另輸出會遺漏字表資料的舊 MJSR 格式。原核心的可寫 SQLite 管理入口已移除；此封存相容入口只在使用者明確匯入時讀取來源。

macOS controller 在 PV 派送前辨識真正數字鍵盤事件；只在候選清單屬於目前 Rust session 時，暫時解除原生候選鍵攔截，讓核心的直接送字行為收到事件。主鍵盤數字及其他模組候選不受影響，這項橋接留在 FE。

四種輸入法以 `guanyinma_session_open_with_candidate_filter` 接上原有 `OVEncodingService`。空的 `UseCharactersSupportedByEncoding` 使用系統字型可顯示性；`UTF-8`／`BIG-5` 使用既有編碼判斷。Guanyinma 在完整碼、wildcard、前綴補充及好打組句取用資料時過濾，並依實際可用候選計算分頁、索引、單候選送字與學習；前綴先過濾才計入最多 36 字。FE 不在畫面階段另刪候選。「竹大」在三個完整碼字無法顯示時，前綴的「喬」因此成為第二候選。

可顯示性是六平台共用的接受文字回呼，Rust 不依 OS、字型名稱或固定罕字範圍判定。政策及快取只屬目前 session；字型／編碼選擇改變時，FE 在既有安全切換邊界建立新 session。回呼的原生物件由 adapter 持有到 session 關閉，不輸出至設定 JSON 或使用者備份。

候選 panel 的索引是完整清單索引；adapter 驗證文字與索引後轉換為核心當頁索引。共用核心已包含跨 session 候選變更的拒絕規則。文字游標使用 Unicode scalar，FE 繼續以 `PVCombinedUTF16TextBuffer` 轉成宿主 UTF-16 座標。

設定先複製為獨立快照，不借用可能被 plist reload 釋放的 dictionary。既有組字存在時延後套用新設定；成功建立的 Rust session 發生錯誤時保留最後可見狀態並提示，不重播事件。

## 行為接口與設定對照

四法的設定、事件分類及普通驗證範圍見 [macOS 行為覆蓋表](GUANYINMA_MACOS_BEHAVIOR_COVERAGE.md)。快捷鍵由 FE 先辨識；核心提供 `set_full_width`／`toggle_full_width`、`set_english`／`toggle_english` 等語意操作。明確 setter 使用 `enabled: true/false`，同值不反向切換。macOS Shift+Space 依原生 Space 規則處理，不在核心內切全半形；角括號翻頁也沿用 PV 的按鍵綁定，核心翻頁使用 `page`。

macOS 中英模式由 FE 保留交易後同步到相符的 active Rust session。相同模式是無副作用的快速操作；焦點返回及中文事件派送前再次同步，防止另一 context 保留舊模式。宿主拒絕送字時不變更核心；核心設定失敗時不虛報成功、不重播已送文字。既有全半形／繁簡 output filters 仍由同一原生 FE 管線管理。

好打注音圈選加詞包含 scalar 反白、三語提示及原子新增。直接文字、候選 non-panel 事件與 Caps Lock 的 macOS 相容轉譯留在 FE；例如舊傳統注音 Caps 特殊鍵的原始控制字元輸出不擴張共用 `direct_text` API 的可接受字元。

## 錯誤處理

五種注音配置與原生別名、Shift 強制大寫、字表碼長、wildcard、空白選字及既有半形／混合標點皆映射至共用行為。未知編碼沿用既有預設，正規化為系統字型判斷；倉頡舊 UI 的已知缺表預設正規化為原字表。任意額外標點覆寫表、無效選字鍵、超出 10～20 的好打組字長度或不合法字表參數會明確回報，不靜默換設定或切到舊核心。

共用模型或使用者資料無法開啟時，context 回報診斷並阻止把中文事件送進舊引擎。執行中的 Rust session 發生錯誤或新設定無法建立 session 時，保留目前可見狀態並回報，不重播事件。

## 驗證入口與證據界線

CI 的完整 Guanyinma 核心測試統一在 `guanyinma-core.yml`。`package-macos.yml` 準備鎖定工具鏈、必須連入 Rust，依既有 Xcode build phase 編譯／連結核心並核對隨包 notices；平台 PR 與打包只選 `--suite integration` 的 FE 接合測試。以下 adapter 工具供接合開發依改動選用；歷史原生來源對照須明確手動執行，不將整套加入平台 workflow。

Rust 核心日常驗證使用 [跨平台無 UI 入口](../Source/Guanyinma/README.md#跨平台無-ui-測試入口)。以下是 macOS FE adapter 的獨立驗證，依接合改動選擇受影響項目；使用真正的 adapter、PV buffer、候選 panel 與隔離使用者 DB，不啟動已安裝 IMK、不讀實際偏好或 profile：

```sh
python3 Source/Loaders/OSX-IMK/Tests/run-guanyinma-tests.py --cargo /path/to/cargo
# 已快取依賴時可加 --offline。
# 需要較完整的本機 FE adapter／archive 契約時，加 --suite all。
# 使用已建置的 archive 可略過 Cargo：
python3 Source/Loaders/OSX-IMK/Tests/run-guanyinma-tests.py \
  --library Source/Guanyinma/target/release/libguanyinma.a
# 倉頡缺字過濾（隔離使用者資料）
python3 Source/Loaders/OSX-IMK/Tests/run-guanyinma-glyph-tests.py --library /path/to/libguanyinma.a
python3 Source/Loaders/OSX-IMK/Tests/run-input-mode-tests.py
```

設定視窗的下列自動化只在 FE 設定 UI 有改動時執行，使用隔離偏好與服務，涵蓋三語視窗、工具列、啟動順序及分頁；不列為 Rust 核心日常驗證：

```sh
python3 Source/Loaders/OSX-IMK/Tests/run-general-preferences-window-tests.py
```

普通無 UI 接合測試涵蓋四法識別字、設定、建立 session、候選、一次送字與釋放；較完整的 adapter／archive 契約另涵蓋分頁選字、學習重開、詞庫管理、主鍵盤／數字鍵盤、全半形、未完成讀音與 Emoji 座標。MJSR 相容使用獨立格式 fixture，驗證完整 JSON 往返、分域匯入、壞檔／鎖定失敗的原子性及失敗保留原備份，不在日常重新編譯舊輸入引擎。

真正原始碼 oracle（含舊 MJSR exporter 與四法來源）需傳入 `--migration-reference` 才能手動執行；它不屬普通測試、CI 或發布驗收。例如：

```sh
python3 Source/Loaders/OSX-IMK/Tests/run-guanyinma-native-behavior-tests.py \
  --migration-reference --library /path/to/libguanyinma.a
```

測試前後核對正式 DB 內容未變。真實文字宿主、App 切換、候選窗滑鼠、簽章／安裝與發布仍須分別驗證；隔離測試及 unsigned source build 不代替這些層級。

[functional baseline](CROSS_PLATFORM_CORE_FUNCTIONAL_TESTS.md) 仍只供遷移／升級時明確手動參考，沒有加入上述測試、日常 CI 或發布驗收。

真正 TIS／IMKServer／Cocoa 文字宿主的隔離測試入口與還原規則見 [IMK 宿主測試](GUANYINMA_MACOS_IMK_HOST_TEST.md)。它與 unit／mock client、正式安裝包驗證是不同層級。

## 共用讀音轉換

Rust 詞庫的讀音顯示／編輯、單字讀音反查結果的轉換，以及 MJSR 讀音驗證，透過
`GuanyinmaMacReadingCodec.h` 呼叫共用無狀態 `guanyinma_reading_codec`。
MJSR 的 canonical 往返、Unicode scalar 字數及數值驗證規則保留。
容器、特殊 SQLite 解碼與檔案保護繼續由 frontend 負責。
手動 codec 原生來源對照入口見 [核心 README](../Source/Guanyinma/README.md#共用讀音-codec)。
