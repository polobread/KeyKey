# Guanyinma 核心實作計畫

驗證分工固定為：核心在跨平台建置中執行無 UI 的公開介面／行為契約測試；原生 runner 或無視窗模擬器實際執行才算通過，純交叉編譯另列未執行。六平台 FE 各自測接合差異與少量 UI 自動化冒煙，不重跑整套核心矩陣，不將大量桌面／實機操作作為核心交付門檻。核心開發不占用使用者桌面或反覆切換其輸入法。

CI 完整核心驗證只由 `guanyinma-core.yml` 負責；其他平台 workflow 直接編譯／連結 Guanyinma，只新增少量 FE 串接冒煙，不重跑或轉呼叫整套核心測試。平台工作沿用既有建置及發布結構，本機核心開發可使用獨立測試入口。

Guanyinma 是 chichi77 KeyKey／琦琦輸入法（英文簡稱 KeyKey）內的 Rust 共用核心，目錄固定為 `Source/Guanyinma`。現有產品名稱、平台版本與原生 frontend 維持既有來源。

## 階段一：資料層與 C ABI

本階段提供 Rust crate、固定工具鏈／依賴、C／C++ header、owned query result 與 thread-local 錯誤契約。唯讀存取正式共用 DB 中的傳統注音、倉頡、簡易、Unigram、Bigram 五種資料來源。

這是四種輸入法共用的基礎，尚未提供完整輸入引擎。字表原始列不等於 UI 候選排序；好打注音的組句、BOS／EOS、backoff、override 與學習策略需要另外移植。禁止因查詢層成立就宣稱已與四套舊核心等價。

局部檢查入口與使用範例見 [核心 README](../Source/Guanyinma/README.md)。正式模型驗證仍沿用既有工具，Cargo build 不 cooker、不修改模型。

## 階段二：解析與三種輸入狀態機

已提供五種注音配置解析，以及傳統注音、倉頡、簡易的共用 session；涵蓋完整候選與頁面、選字、字根編輯、倉頡 wildcard／即時／前綴候選、標點、組字保留、中英與全半形狀態。Rust 與 C ABI 共用同一組操作與快照。共用 `KeyKey.db` 維持唯讀。

行為主要來源為 macOS Manjusri／Formosa／OpenVanilla；其他平台原生核心用於理解既有接合與差異，不各自建立演算法分支。核心按行為分類，不依 OS 名稱判斷。前端可設定 `behaviors.ignore_caps_lock_in_chinese`、`behaviors.literal_keypad`，並在執行中替換設定；全域 NumLock 與實際數字鍵盤來源分開。中英模式是核心狀態；單按 Shift 的啟用、按放與組合鍵辨識沿用六平台既有 frontend，成功後送一次語意切換操作。平台預設值由各 frontend 提供。

局部 unit／整合測試及真實 C consumer 驗證新核心契約，不讀取凍結的 functional baseline。另提供明確手動呼叫的階段二差異工具，僅比較本階段已實作的 macOS 桌面語料；後續階段案例明列跳過。入口見核心 README。

第二階段沒有涵蓋下述好打注音；選字學習及原生 frontend 接合仍另列階段。字型過濾、宿主交易、生命週期、原生設定 UI 與平台包裝仍按原有邊界處理。

## 階段三：好打注音組句、候選與邊界

已移植 macOS Manjusri graph／Node／LanguageModel 的唯讀組句規則：BOS／EOS、Unigram／Bigram／backoff、別名、八音節詞跨度、平手順序、完整候選與讀音跨度、選詞覆寫、插刪及重新組句。`walker.rs` 負責模型與路徑，`smart.rs` 負責可複製的組字狀態，既有 Rust／C ABI session 提供統一操作。

FE 以 `SmartOptions` 設定 Bigram 上下文評分、空白鍵、候選目標方向、選詞後游標、Esc 與音節邊界；`max_completed_syllables` 為 **10～20 可選**，`shift_at_limit` 區分到達／超過上限才擠字。上限十搭配不同時機可表達既有十／十一及九／十邊界。移出第一個完整詞段時固定下一詞段，已送前段不再受游標、選字或刪除影響。

快照分開提供已完成組句、未完成讀音、可見文字、文字游標與讀音游標、完整候選與詞段跨度，FE 將這些資料轉成原生顯示和文字交易。候選開關與游標移動有明確操作，不依賴 OS 名稱。

普通 unit／整合／C ABI 測試涵蓋合成分數與失敗復原、真實 DB 候選、選詞與編輯、五種注音配置、十／十一／十九音節完整句及二十音節邊界。原生來源的單次對照與 functional baseline 比較只在移植時明確執行，結果存忽略的 build 目錄。

各平台設定盤點後已將 Android 的 Bigram 開關表達為共用 `use_bigrams`，預設開啟；關閉時同時停用 Bigram 與前文 backoff，切換時保留讀音、游標與手動選詞並立即重算。現有偏好到共用欄位的對照見核心 README；視窗、快捷鍵辨識及偏好儲存仍由 FE 處理。

這一階段只固定目前 graph 中的選詞，沒有匯入或保存使用者學習。既有核心因先前選字而改變後續輸入偏好的案例屬階段四；保留原觀測與具名跳過原因，不假裝已等價。

## 階段四：使用者詞庫與學習保存

已提供 `learning.rs` 的 FE 行為設定、`user_store.rs` 的獨立 SQLite 資料層，並接入 Smart graph、字表、Rust session 與 C ABI。支援自訂詞新增／編輯／刪除、候選偏好、明確選詞的相鄰關係、字表完整候選計數、重開、保存與重設；讀取自訂詞與各種學習可獨立開關。

主要來源仍為 macOS Manjusri／Generic：候選偏好調整當前 query 的排序與原分數，明確選取當時首位會移除快取；自動確認與擠字不產生偏好。字表只記非首位完整候選，計數同分保留原記錄順序。偏好與相鄰關係快取各保留最近 200 個 query。

使用者資料依 FE 提供的路徑另存；預設 session 私有記憶體，不碰實際平台 profile。每次 apply 原子提交 delta，失敗恢復輸入狀態且沒有送字結果。跨程序合併本次變更，generation 重設可廢棄舊學習；候選同步按完整文字與跨度比對，保留相同視圖或拒絕失效索引，避免誤選與舊候選回復迴圈。明確詞庫編輯與匯入遇到世代變更會有限重試。reset 保留自訂詞，close 不隱式保存。

舊資料只做明確、唯讀、異檔匯入：Mac Smart 三種使用者表與 Generic 頻率資料皆有入口；依來源範圍替換學習，保留其他輸入法及既有詞。不原地升級、刪除或覆寫唯一舊副本。其他原生儲存格式的轉換由第五階段 FE 接合處理，未知／加密 schema 保留原檔並回報錯誤。

普通 unit／整合／C ABI 驗證使用隔離資料，涵蓋同 session 重用、重開、正確學習觸發、設定切換、自訂詞管理、計數順位、失敗回復、兩個 writer 合併與重設隔離。完整功能基準仍只供本次遷移明確手動比較。

Windows 檔案身分檢查後端仍需 Windows 原生驗證；本機檔案測試不能替代六平台工具鏈與宿主驗收。

## 共用候選可顯示性接口

`CandidateFilter`／`guanyinma_session_open_with_candidate_filter` 讓六平台 FE 提供可接受文字的判斷，四種輸入法沿用同一契約。字表完整碼、wildcard 與前綴先過濾再計算候選、36 字補充上限、分頁及學習；好打注音在 Unigram、自訂詞及 Bigram current 進入 graph 前過濾。原始 DB 查詢保留來源列，未提供 callback 時維持全部接受。固定政策由 session 擁有，變更時由 FE 在保留組字後建立新 session，不在可見候選中途改寫索引。

macOS 已接回既有 `OVEncodingService` 的系統字型／編碼服務。iOS 已接 CoreText、Android 已接 Paint、Windows 已接 DirectWrite fallback／字集服務；Linux／FreeBSD 接 Guanyinma 時仍須接上原生能力判斷，並各自驗證平台實際字型及宿主；共用接口與本機測試不代表其餘 frontend 已接好。普通 unit、C consumer 與原生隔離對照測試驗證此契約，不讀取遷移 baseline。

## 階段五：原生 frontend 接合（進行中）

macOS 四種輸入法直接透過 Guanyinma package 建立 Rust session，保留既有 PV 候選／文字／輸出管線及獨立使用者資料管理。產品不編譯 Manjusri／Generic 輸入引擎，不提供核心選單、建置開關或失敗回退。設定更新等待組字、候選及待送 commit 完成；失敗保留目前可見狀態並回報，不重播事件。原生設定快照自行擁有資料，避免 plist reload 的借用生命週期問題。正式打包使用鎖定 Rust 工具鏈、少量 FE integration smoke 與隨包 runtime notices。

已接上完整 Guanyinma JSON 備份與舊 MJSR 封存匯入；FE 解碼舊容器，核心只接收版本化資料，以原子交易合併自訂詞並替換來源提供的學習範圍。備份排除本機世代資料，匯出失敗保留原檔。建置、隔離測試與錯誤處理見 [macOS 接合文件](GUANYINMA_MACOS_ADAPTER.md)。真正 IMK 文字宿主與安裝驗收、其餘 frontend 的接合仍待完成；不將此里程碑視為六平台遷移完成。

iOS 同一 FE 的觸控 extension 與 App 實體鍵盤編輯器固定使用 Guanyinma 單核心，移除舊 Swift 解析、walker、排序與學習引擎，以及核心設定／切換／失敗回退。Swift 保留 FE 型別、原生字型 callback、宿主交易與 App Group 自訂詞發布；extension 唯讀同步發布詞條，學習保存在私有 Rust DB。Xcode 必須編譯／連結 Rust 靜態庫；完整核心 CI 集中驗證，iOS 僅做少量串接冒煙。建置、資料權責及驗證層級見 [iOS 接合文件](GUANYINMA_IOS_ADAPTER.md)。

Android 同一 IME service 固定使用 Guanyinma 單核心，移除舊 Java 解析、walker、排序、學習引擎與核心設定／切換／失敗回退。Java 保留 FE 型別、宿主交易、關聯詞及明確詞條交換的薄轉換。四個 ABI 必須編譯 Rust 靜態庫並連入 UTF-8 JNI；App 與 IME 讀同一份經內容雜湊驗證的模型，使用者資料固定在 Guanyinma DB，舊檔不自動改刪。觸控／普通實體／實體雙排的行為與宿主交易由 FE 分派，核心互動分類可用 `set_profile` 更新。責任與分層驗證見 [Android 接合文件](GUANYINMA_ANDROID_ADAPTER.md)。

Windows 同一 TSF FE 的四種輸入法固定使用 Guanyinma，移除 Manjusri／Generic 產品核心、一般設定的核心選單及失敗回退。DirectWrite 候選 callback、獨立 Guanyinma 詞庫與明確唯讀匯入仍由 FE 接合；宿主 retained effects 沿用既有有序交易佇列。x64／x86 靜態 Rust 與原生 FE 共用鎖定 bundled SQLite；完整核心 CI 不在 Windows workflow 重跑。責任與分層驗證見 [Windows 接合文件](GUANYINMA_WINDOWS_ADAPTER.md)。

Linux／FreeBSD Fcitx 5 已轉為 Guanyinma 單核心開發；Legacy C++ walker、排序、可寫學習庫及核心切換路徑已移除。前端保留原生字型、事件、宿主效果、關聯詞及輸出轉換，並補齊桌面偏好與圖形詞庫工具。Linux 使用者資料只使用 Guanyinma 格式，不再支援舊 Linux C++ 資料讀寫或匯入；既有舊檔不自動刪除。接合與聚焦驗證見 [Linux adapter 說明](GUANYINMA_LINUX_ADAPTER.md)。GNOME Wayland／XWayland、FreeBSD 原生及正式安裝驗收各自記錄。

四法逐項設定與 native 事件對照集中於 [macOS 行為覆蓋表](GUANYINMA_MACOS_BEHAVIOR_COVERAGE.md)。核心的全半形、中英文提供明確設定及切換操作，FE 決定快捷鍵綁定；圈選加詞、直接文字與進階字表設定沿用同一個共用 session／C ABI。實際 IMK 宿主以 [隔離測試流程](GUANYINMA_MACOS_IMK_HOST_TEST.md) 驗證，不把 core 或 adapter 通過等同於宿主完成。

## 後續逐步移植

| 階段 | 交付範圍 | 完成判定 |
|---|---|---|
| 五 | 五個 frontend 接合，服務六平台 | 原生 build、產物 DB／版本／簽章及真正文字宿主各自驗收；六平台以 Guanyinma 單核心交付 |

接合工作依實際受影響範圍建置／測試。Windows 的 TSF、macOS IMK、iOS document proxy、Android InputConnection、Fcitx X11／Wayland 維持原生邊界；C ABI 不代替宿主文字交易或生命週期。

## 遷移參考的界線

[functional baseline](CROSS_PLATFORM_CORE_FUNCTIONAL_TESTS.md) 保存既有四套核心的四種輸入法、完整候選順序與選字學習，也保留平台差異及已觀測到的不穩定排序。只在遷移／升級時明確擷取與比較，供人工審查差異。

macOS 桌面觀測作主要行為參考，其他平台觀測保留作差異診斷；已明確指定的新行為以使用者決策為準。

不得將它接進日常驗證、預設 CTest、CI gate 或發布驗收，也不得為了比較通過而自動覆寫舊基準。Guanyinma 新增的普通單元／ABI 測試與這份遷移資料分開。

## 尚待各平台定案

SQLite provider、靜態／動態連結、MSVC CRT、Android NDK／16 KB 對齊、Apple 切片／extension 資源、Linux／FreeBSD 套件依賴，會隨各 adapter 接合處理。當前 crate 同時提供系統及 `bundled-sqlite` 建置方式，尚不代表六平台 native toolchain 或正式包裝均已完成。

原創 Rust 模組依 [授權地圖](../LICENSING.md) 適用 MIT；從 Yahoo／OpenVanilla／Manjusri 衍生的實作保留原適用聲明，換語言不會改變來源授權。
