# Guanyinma iOS 接合

KeyKey 的 iOS 鍵盤 extension 與容器 App 實體鍵盤編輯器固定使用 Guanyinma Rust 單核心。產品不再建置 Swift 的注音解析、組句 walker、候選排序或學習引擎，也不提供核心選擇及失敗回退。舊 `inputCore` 偏好不影響目前引擎；原有舊資料檔保留，不自動匯入、改寫或刪除。

## Frontend 與宿主邊界

`KeyKeyEngine` Swift package 是 frontend 介面與正式 C ABI adapter。`KeyboardInput` 只提供鍵盤模式、宿主 effects 與既有符號／Emoji palette；`InputEngine` 定義 frontend 契約。`KeyboardInputEngine` 必須成功建立唯一的 `GuanyinmaInputEngine`，無法讀模型或使用者資料時會丟出錯誤，UIKit 顯示失敗，不改用另一引擎。

UIKit 的欄位政策、鍵盤面、按鍵辨識、候選窗、符號表、UTF-16 座標和 document proxy 仍留在 FE。Guanyinma 負責四種輸入法的解析、組句、排序、選字、學習與資料交易。`BopomofoKeyboardLayout` 與 `StandardBopomofoLayout` 僅保留鍵帽、按鍵分類與 FE 標點對應，沒有注音狀態機或許氏消歧。

`KeyboardInputEngine` 保留前次 host effects 是否已被原宿主接受的狀態。FE 只有在文字／刪除／Return 成功套用後才呼叫 `acknowledgeHostEffects()`；詞庫 publication 同步等待組字、候選與待送效果都完成，不重播按鍵或宿主 effects。觸控組字使用既有 `TouchSmartHostTextState` 與 `DocumentMutationGuard`；App 實體編輯器使用自有 `committedText`、插入游標與核心組字重畫輸出，再以 UTF-16 caret 定位游標；輸出 UITextView 不可編輯／選取，不使用原生 marked-text range。生命週期的重複回呼不得重複送字。

觸控採 `touch` 行為：十音節達上限時擠出完整前詞段，保留九個可修改音節。App 實體鍵盤編輯器採 `desktop`：第十一個完整音節才擠字。核心不判斷 iOS 或裝置種類；FE 提供行為設定、候選選字鍵、空白鍵選字、字表選項及標準／許氏配置。

## App 實體選字與右側刪除

實體好打注音固定 `candidate_cursor_at_end = false`、`selection_returns_to_end = false`，
`openSmartCandidates()` 明確取 `min(readingCursor, readings.count - 1)`，與舊 iOS／macOS 的右側目標一致。
選字後停在所選詞末端；觸控仍在選字後回到可編輯句尾。

`StandardHardwareKeyMapper` 將 HID `0x4C` 映射為 `forwardDelete`，經共用 `InputEngine.deleteForward()`／wrapper 送 Rust 既有 Delete。
有組字時，只有核心修改讀音／候選狀態；沒有組字時，controller 在自己的 `committedText` 插入位置右刪一個 Swift Character。
刪除前先記錄是否有組字，避免核心刪空後又誤刪後方已確認文字。空組字的 engine Delete 回傳 update，不借用向左刪除的 host effect。

Forward Delete 與 Backspace 都追蹤按住的 HID usage，避免系統重複 Down 和前端計時器同時刪除；放開、取消、resign、離開 App 或鍵盤斷線會停止對應計時器。
這是 App 前景編輯器接合，不代表 extension 能接管其他 App 的外接鍵盤。

## 候選字型與關聯詞

`CandidateGlyphSupport` 使用 CoreText 的實際 glyph／fallback 判斷。候選 callback 經 `guanyinma_session_open_with_candidate_filter` 在排序、分頁與好打 graph 建立前過濾；UI 不另刪候選或改編號。候選快取只存在程序記憶體。

`AssociatedPhraseStore` 只持有設定頁 collection metadata 和當下啟用來源。adapter 將它接成 `GuanyinmaAssociatedPhraseStore`，關聯詞查詢、分類順序與去重皆經共用唯讀 C ABI，並保留省略空候選的原行為。啟用來源以 closure 在每次查詢讀取，設定變更不用改寫核心或重建候選窗。

## 模型、自訂詞與學習

App 與 extension 共用 keyboard extension bundle 內唯一一份正式共用 `Source/Distributions/Takao/CookedDatabase/KeyKey.db`。建置只驗證與複製，不 cooker、不更改詞頻。Rust 使用 Apple 系統 SQLite，與 FE 的唯讀 metadata／publication connection 共用 provider，不連結 bundled SQLite。

| 資料 | 位置與權責 |
|---|---|
| 共用模型 | extension bundle 的唯一 `KeyKey.db`，App 讀同一檔案、全程唯讀 |
| 自訂詞 publication | App Group 的 `GuanyinmaUserPhrase.db`，只有 App 寫入 |
| 鍵盤 Rust 自訂詞複本與學習 | extension 私有 `GuanyinmaUser.db` |
| App 實體編輯器的 Rust 自訂詞複本與學習 | App 私有 `GuanyinmaUser.db` |
| 舊 Swift 自訂詞與學習 | 既有舊檔保留，不自動開啟或遷移 |

`SharedPhrasePublication` 是 App Group 的薄自訂詞 CRUD／交換層，不保存候選偏好、Bigram 或倉頡學習。App 可新增、編輯、刪除與交換 MJSR 明文自訂詞；讀音欄的標準鍵位與分隔符先由 FE 正規化，再由 Guanyinma reading codec 驗證、編碼與解碼，不保留另一套音節打包器。

extension 以唯讀 connection 取得完整 publication 快照，再透過 Rust `replace_user_phrases` 原子更新自己的詞庫。缺少 publication 與讀取錯誤不當成空詞庫；無來源保留已有複本，壞檔／型別錯誤會回報且不清除私人自訂詞。有效的空 publication 才明確清空已發布詞條，且保留學習。

維持 `RequestsOpenAccess = false`：鍵盤不要求完整取用、不連網、不寫 App Group；鍵盤和實體編輯器學習各自獨立。重設只經 Rust 清好打學習，保留自訂詞與其他方法學習；App Group 重設通知固定使用 Guanyinma request key，成功後才記錄 applied revision。MJSR 加密學習區塊不匯入，也不自動搬移舊 Swift 學習。

## 建置與少量串接驗證

Xcode App 與 extension 都依賴 `Guanyinma Core` aggregate target。`build-ios-core.sh` 依鎖定 toolchain／Cargo.lock 建立對應 Apple 架構的靜態庫；Rust 是必要建置依賴，沒有停用核心的 build flag。Rust／C ABI declarations 經 `CGuanyinma` module 連結，native targets 保留 Apple SQLite／iconv 系統連結。

腳本同時產生 `GuanyinmaNotices.txt` 與 `GuanyinmaNotices.json`，App 與 extension 各自複製相同檔案至 bundle。容器 App 使用 JSON 元件目錄，點入閱讀各元件署名與完整條款；相同條款只儲存一次，各元件保留獨立署名及原始文件 SHA-256。文字檔同樣以元件索引與共用條款組成，供離線查核。

### iOS 授權範圍與重現

建置前須備妥同一鎖定 Rust 工具鏈的 `rust-src`（Xcode Cloud 與 iOS packaging workflow 會準備）：

```sh
rustup component add rust-src --toolchain "$(sed -nE 's/^channel = "([^"]+)"/\1/p' Source/Guanyinma/rust-toolchain.toml)"
python3 Source/Guanyinma/tools/test_ios_runtime_notices.py
```

- 專案來源保留 Yahoo BSD、原創 frontend／Guanyinma MIT、Formosa／OpenVanilla 衍生聲明、Unicode，以及 McBopomofo、AI 原創資料與 chichi77Collection 詞庫來源。不同來源的著作權、適用範圍及完整條款均保留；不重訂授權。
- Cargo 使用 `--locked --no-default-features --filter-platform` 的 normal 執行期相依；排除 dev、build、proc-macro 及其專用相依。建置期程式產生的本專案原創資料與來源授權仍按前一項保留。
- Rust 標準庫使用本次 iOS `libguanyinma.a` archive 成員的 crate 名稱與 hash，對照相同 target 的 sysroot rlib；再依同版本 `rust-src/library/Cargo.lock` 與 vendored 原始授權取完整聲明。這是靜態庫的元件範圍，未嘗試依連結器函式層級 dead stripping 刪除聲明。
- `compiler-builtins` 的 MIT／Apache＋LLVM exception 及其直接納入的 libm 原始授權另外保留；`std_detect` 與 Rust in-tree 的 backtrace、Crossbeam、Unicode 署名亦保留。僅排除官方清單中明確的 Fuchsia 專屬來源例外；未知標準庫元件、缺少原始授權、版本／archive 不吻合會中止建置。
- iOS 使用系統 SQLite、iconv／libunwind，不隨 App 散布這些系統實作；記錄 SQLite 來源，不打包 Android NDK、桌面 Sparkle／WinSparkle／OpenSSL、Windows HanConvert 或整套 Rust 授權目錄。
- 去重只忽略空白差異；MIT／BSD 完整本文可共用，周圍署名、適用說明與特例原文分開保留。不能用 SPDX 名稱或網頁連結取代所需全文。其他平台仍沿用原本的授權產物流程。

每次建置旁邊的 `GuanyinmaNotices.audit.json` 保存 target 成員、標準庫元件、Cargo 執行期清單與 Rust source lock 雜湊，屬建置產物、不提交。`verify-testflight-archive.sh` 核對 App／extension 目錄一致、條款引用與內容雜湊、必要來源及建置工具排除；更新 Rust／Cargo 相依時須重看這份範圍和產物。

依據：[Rust COPYRIGHT](https://github.com/rust-lang/rust/blob/main/COPYRIGHT)、[Rust MIT](https://github.com/rust-lang/rust/blob/main/LICENSE-MIT)、[Apache 2.0 第 4 條](https://www.apache.org/licenses/LICENSE-2.0)。實際文件以本次鎖定工具鏈與 Cargo source 為準。

```sh
# 聚焦 FE 串接：真 Rust／C ABI，無 UIKit 或 Simulator.app
bash Source/Guanyinma/tools/test-ios-swift-package.sh --filter GuanyinmaIntegrationTests
bash Source/Guanyinma/tools/test-ios-swift-package.sh --filter SharedPhrasePublicationTests

# 完整 FE unit suite，仍不啟動 UI
bash Source/Guanyinma/tools/test-ios-swift-package.sh

# App 與 extension 編譯，不代表 simulator runtime 或裝置驗收
xcodebuild -project Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj \
  -scheme 'chichi77 KeyKey' -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

`MemoryProbe` 明確選用：設定 `KEYKEY_IOS_MEMORY_PROBE=1` 並指定該 suite 才執行真 Rust adapter 的長迴圈記憶體量測；一般測試不執行。容器購買流程另由既有 package 使用同一 host wrapper 測試。

App 的右側候選與 Forward Delete UI 回歸使用 `run-simulator-tests.sh --functional-host`；其中 Delete／Return 由 host-only Simulator HID helper 送完整按放事件，UI 再核對實際文字結果。工具範圍與直接 Xcode 用法見 [iOS README](../Source/Loaders/iOS-Keyboard/README.md#ui-測試分流)，行為與驗證證據見 [iOS 實體編輯器調查](IOS_PHYSICAL_KEYBOARD_BEHAVIOR_REVIEW.md)。

完整核心演算法與六平台 Rust／C consumer 矩陣只由 `guanyinma-core.yml` 負責。iOS workflow 直接建置核心並只跑少量 FE smoke，不重複核心完整矩陣。Swift host 測試、iOS Simulator／device 交叉編譯、無視窗 iOS 核心 runtime 及真正 keyboard extension 宿主是不同證據層級。

## 遷移參考

`MigrationReference/CoreFunctionalTests.swift` 原封保留舊 Swift 核心的手動 recorder，已移出 Swift Package 的 test target。重現時需搭配移除舊核心前的 revision，不採樣新 Rust 來覆寫既有凍結資料。functional baseline 仍只供人工遷移／升級參考，不是普通測試、CI 或發布 gate。
