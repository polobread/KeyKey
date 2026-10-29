# Guanyinma：KeyKey 六平台 Rust 共用核心評估

評估日期：2026-10-25。原始碼基準：`master`／`origin/master` 的 `892c4746`。
本文件保留重寫前架構與跨平台共用核心的工程評估；現行單核心與雙核心接合以 [實作計畫](GUANYINMA_IMPLEMENTATION_PLAN.md) 及各平台 adapter 文件為準，下方舊核心盤點不代表目前產品依賴。效能與成本數字仍屬待原型校準的估算。`Source/Guanyinma` 已提供 Rust C ABI、唯讀資料層、注音解析與四種輸入法 session（含好打注音組句、候選、邊界與學習）；各平台封裝及宿主驗收分別記錄。

產品名稱維持 **chichi77 KeyKey／琦琦輸入法**（英文簡稱 **KeyKey**）。新核心代號為 **Guanyinma**，使用 Rust 實作，作為 KeyKey 內的共用核心模組；目標取代 macOS／Windows 的 Manjusri、iOS Swift 核心、Android Java 核心及 Linux／FreeBSD C++ 核心。各平台原生 frontend 改接 Guanyinma。核心工作目錄使用 Guanyinma 名稱。

目前實作決策以 [實作計畫](GUANYINMA_IMPLEMENTATION_PLAN.md) 為準：演算法疑義以 macOS Manjusri／Formosa／OpenVanilla 為主要來源；其他平台既有核心與 frontend 用於接合參考。核心依可開關的行為與狀態分類，平台預設與原生事件辨識留在 frontend；本評估原先列出的相容策略是風險分析，不代表逐 OS 建立核心分支。

## 結論與建議

**技術上可行，長期值得朝共用核心收斂；建議先投入有停止條件的概念驗證，再決定是否全面遷移。**

適合的目標是：一套 Rust 輸入核心，加上目前五個原生 frontend，服務 Windows、macOS、iOS、Android、Linux、FreeBSD 六平台。Linux／FreeBSD 仍共用 Fcitx 5 接合層。共用的是演算法、組字狀態及資料語意；各 OS／CPU 仍分別編譯，無法共用一個二進位檔。

最主要收益是讓組句、候選、選字學習及邊界修正只維護一次，並用同一組案例驗證。Rust 可降低安全 Rust 範圍內的記憶體錯誤風險，但不會自動修好 TSF、IMK、InputConnection、document proxy 或 Fcitx 的生命週期問題，也不能先宣稱效能或記憶體一定改善。

目前產品已支援六平台並正式發布，全面切換的主要成本是行為相容與平台驗收。Guanyinma 分支的 Windows、iOS、Android、Linux／FreeBSD 已直接使用 Rust 單核心；macOS 仍保留雙核心。正式發布及宿主驗收狀態以各平台文件為準。

## 原生 frontend 與共用核心接合

| 平台 | 現有核心及接合點 | 遷移時保留 |
|---|---|---|
| macOS | `OVIMSmartMandarin`＋Manjusri＋PlainVanilla，經 `OSX-IMK` 接宿主 | Objective-C++ IMK、候選視窗、設定與安裝／簽章 |
| Windows | `KeyKeyEngine.cpp` 包裝同一套桌面模組，`TextService.cpp` 接 TSF | COM／TSF、edit session、原生候選窗、WPF 設定及簽章 |
| iOS | Swift `BopomofoEngine`、`SmartMandarinStore`；引擎 Swift Package 不依賴 UIKit | Swift App／extension、document proxy、App Group 與介面 |
| Android | Java `BopomofoEngine`、`SmartMandarinStore` | Java IME service、InputConnection、鍵盤及設定 UI |
| Linux | Guanyinma Rust session，C++ Fcitx 5 adapter | C++ Fcitx addon、GTK／GNOME 整合、套件流程 |
| FreeBSD | 同一 Guanyinma Rust session 及 Fcitx adapter | ports／pkg、prefix 路徑、FreeBSD 實機驗收 |

現有可重用資產：

- 五個 frontend 已使用同一份預製 `KeyKey.db`，不需要因 Rust 改模型或 cooker。
- iOS／Android 已有 `SmartMandarinSource` 抽象，可先替換 Store，保留上層操作流程。
- Linux／FreeBSD 已接上共用 Rust session；C++ 僅負責 Fcitx 與原生服務。
- 倉頡已有 `Source/Shared/CangjiePrefix.h`、排名／Unicode 資料及跨平台 fixture，可作為後續共用規則的基礎。
- 現有離線動作數工具使用桌面 Manjusri；它是可比較的參考實作，尚不是六平台共同測試介面。

## 最大風險是既有語意差異

以下保留桌面與行動原核心的行為分析；Linux／FreeBSD 使用 Guanyinma 的共用語意，無獨立 walker。

| 差異 | 本次觀察 | Rust 遷移要求 |
|---|---|---|
| BOS／EOS 與 backoff | 桌面使用 Manjusri graph；Swift／Java walker 首詞 fallback 直接採 unigram，單音節另有 EOS 不重排處理 | 先實作明確的桌面與行動的行為設定；不可默認某套能直接取代其餘實作 |
| 學習 Bigram | 桌面 `findBigrams` 命中讀音組的使用者 cache 時直接回傳該列；其餘 Store 依前後文字比對學習值 | 將匹配範圍、覆蓋規則、容量與失效時機納入規格 |
| Unigram 取樣 | Swift／Java SQL 有 `ORDER BY probability DESC LIMIT 64` | 不能在移植時順便統一截斷數；須先列出對候選及路徑的實際影響 |
| 同分排序 | 桌面保留 rowid 來源次序並使用 stable sort；Swift 有 Dictionary 走訪，其他實作也使用不同容器 | 指定可重現次序並建立同分案例；新 tie-break 造成的差異要單獨列報 |
| 自訂詞合併 | Swift／Java 依文字合併 | 定義同詞、同讀音、不同分數的覆蓋及去重規則 |
| 組字視窗 | 桌面／一般實體鍵盤預設十／十一音節；觸控九／十；Windows 另有既有組字長度設定 | 以能力／操作模式帶入規則；保留設定值與各平台預設 |
| 宿主文字 | 手機觸控已把中文字寫入宿主，維護可替換尾段；桌面通常維護 preedit／marked composition | 核心輸出文字意圖，原生層掌握真正的宿主範圍及回呼 |
| 候選與符號 | 頁容量、方向鍵、選字鍵、符號是否留在同一組字圖已有差異 | 候選內容與跨度共用，頁容量及互動規則明確配置；功能缺口逐項追蹤 |

特別注意：目前 Swift 與 Java 的 `learnConfirmedComposition` 都是無操作，註解明訂確認自動猜測／擠字不代表使用者偏好。不能因舊平台文件曾描述確認時學習，就在 Rust 恢復這項行為。

評分策略可在過渡期保留有限、具名的相容模式。長期若要統一排序，應另開模型／行為變更提案，執行完整比較；不能讓 Rust 核心累積任意平台特例。

## 建議共用範圍

| 模組 | 建議 | 原因／邊界 |
|---|---|---|
| 注音音節、標準／許氏等鍵盤映射、讀音編碼 | 共用 | 純邏輯，適合單元測試與跨平台案例 |
| Unigram／Bigram 查詢、walker、候選跨度、改選與擠字 | 優先共用 | 目前重複最多，模型與邊界修正可集中 |
| 選字學習、自訂詞合併、cache 語意 | 共用邏輯，分階段接管儲存 | 要先保留各平台既有資料與跨程序更新 |
| 傳統注音、倉頡、簡易、前綴候選、關聯詞 | 第二階段共用 | 「只換好打 Store」仍未消除上層 Engine 的重複 |
| 全半形、簡體輸出轉換 | 可共用純轉換 | 學習與內部候選仍使用繁體；保留來源授權及現有語意 |
| 字型是否能顯示候選 | 平台提供能力，核心使用過濾結果 | 不宜讓 Rust 直接依賴所有平台的字型 API |
| 觸控鍵盤、候選視窗、Emoji／符號面板 UI | 保留原生 | 和 OS 介面、字型、可用性整合密切相關 |
| TSF／IMK／Fcitx、document proxy／InputConnection | 保留原生 | 每個宿主的組字與回呼契約不同 |
| 設定 UI、付款、更新器、安裝與簽章 | 保留原生 | 不是輸入演算法共用的必要範圍 |

建議模組關係：

```text
IMK / TSF / Swift App與extension / Java IME / Fcitx (Linux與FreeBSD)
             │ 原生平台 adapter：事件、文字範圍、回呼、設定
             ▼
        C ABI（Android 外加薄 JNI 包裝）
             ▼
 Rust session／輸入操作狀態機 ── policy：觸控／實體／相容行為
             ▼
 注音／字表規則＋候選／walker＋學習規則
             ▼
 唯讀正式模型＋可替換的使用者資料儲存介面
```

核心適合用一般同步函式及標準函式庫，不需為這項工作引入非同步 runtime 或獨立常駐服務。先把跨語言呼叫集中在「一次輸入操作 → 一份結果」，避免每個候選、每條 Bigram 都跨 JNI／Swift 呼叫。

## FFI、文字與狀態契約

建議以小型、版本化 C ABI 作為共通邊界，提供 create／destroy、process、select、finish、snapshot 等操作；輸出包含 preedit、候選文字與跨度、游標、送字及學習意圖。這是建議介面方向，尚非定案 API。

- 用 opaque handle 代表 session；結果採不可變快照、明確長度及配對釋放函式。避免跨邊界傳 Rust `String`／`Vec`、C++ STL 或用另一語言的 allocator 釋放。
- Rust 內部保留安全封裝，unsafe 集中於 FFI。驗證參數、生命週期及結果版本；C ABI 不讓 panic／外語例外穿越。採 unwind 並攔截 panic 時須使該 session 失效；若採 abort，必須接受它可能終止所在宿主程序，不能把兩者混稱安全回復。
- 每個輸入 context 獨立 session，序列處理操作；模型可共用唯讀資料，但 SQLite connection／cache 的執行緒使用須另訂。TSF 的多宿主程序不能依賴同一個全域 Rust instance。
- API 明確區分「讀音索引／跨度」「UTF-8 byte offset」「Unicode scalar」「UTF-16 code unit」與使用者感知字元。核心可用讀音索引定位詞，文字快照帶轉換資訊，adapter 依 OS API 換算。
- Swift `Character` 的 grapheme 與 Rust `chars()` 不等價；CJK 擴展字、變體選擇符、Emoji ZWJ 及組合字元必須有回歸案例。JNI 的 Modified UTF-8 也不能直接當標準 UTF-8。
- 核心提出的送字／替換是待套用操作。原生層處理 TSF edit session 拒絕、宿主拒絕／部分修改及重複回呼；以 operation ID／generation 防止舊回呼清掉新組字。
- 對能回報結果的宿主採 prepare／acknowledge 或等價交易設計；無可靠確認的 iOS proxy 路徑使用現有 mutation guard／失效策略。宿主失敗時不可先把未送出的詞永久從核心移除，或重新送出已成功的文字。
- 學習只根據明確選字，與快照產生分離；正式 DB 唯讀。使用者資料暫沿用原 schema／路徑，再逐平台評估交由 Rust 管理。

Rust 官方 FFI 文件也明訂 raw pointer 及外部函式仍有安全責任；Android 官方建議縮小 JNI 邊界與資料轉換次數。參考 [Rust FFI](https://doc.rust-lang.org/nomicon/ffi.html)、[Android JNI tips](https://developer.android.com/ndk/guides/jni-tips)。

## 六平台工具鏈與封裝

下列是工程可行性與建議產物，並非本次已成功建置的結果。Rust 官方提供相關 target，Tier 2 不保證每次都執行 target 上的測試，仍需專案自己的驗收。

| 平台 | 初期 target／產物方向 | 主要新增工作 |
|---|---|---|
| macOS | `aarch64-apple-darwin`；staticlib 連進現有 App | 接 Xcode target、deployment target、符號／崩潰追蹤；目前正式建置為 arm64，不因 Rust 自動擴增 Intel 支援 |
| Windows | `x86_64-pc-windows-msvc`、`i686-pc-windows-msvc`；staticlib 連進 TSF DLL | CMake／MSVC CRT 相容、x86 calling convention、兩種位元與 DLL 卸載生命週期 |
| iOS | `aarch64-apple-ios`、`aarch64-apple-ios-sim`；依建置方式提供 staticlib／XCFramework | App 與 extension 分別連結、Swift C module、Xcode Cloud 安裝固定工具鏈、extension 冷啟動與記憶體 |
| Android | `aarch64-linux-android`，另依現有裝置／測試需求決定 x86_64、armeabi-v7a 等 ABI；JNI `.so` | Gradle＋NDK＋Cargo、AAB ABI 覆蓋、載入失敗處理、ELF／ZIP 對齊、原生崩潰符號 |
| Linux | `x86_64-unknown-linux-gnu`；staticlib 連入 Fcitx addon | 在最低支援 Ubuntu 環境建置／驗證 glibc；保留 staged install、X11／Wayland 驗收 |
| FreeBSD | `x86_64-unknown-freebsd`；原生建置並接相同 Fcitx addon | ports 的 Rust／Cargo 依賴與可離線重現來源、prefix、SQLite／iconv 連結及實機測試 |

Android 現有建置檔未配置自己的 NDK／Rust 引擎。加入 Rust 會新增原生程式封裝責任，16 KB page size 相容必須列為切換門檻；不能只確認 Java unit test 或 `cargo build` 通過。

Apple 可考慮 static library 包成 XCFramework；實機與 Simulator 切片不能混為同一 target。FreeBSD 與 Linux 共用原始碼，仍分開建置及測試。

工具鏈應固定 Rust 版本、Cargo.lock、NDK／Xcode 環境及相依來源，納入 CI cache 與可重現來源記錄。Linux／FreeBSD 優先使用套件系統 SQLite；Apple／Windows／Android 的 SQLite 提供方式在原型比較後定案，避免重複靜態／動態連結同名符號。

官方依據：[Rust target 列表](https://doc.rust-lang.org/rustc/platform-support.html)、[iOS target](https://doc.rust-lang.org/rustc/platform-support/apple-ios.html)、[FreeBSD target](https://doc.rust-lang.org/rustc/platform-support/freebsd.html)、[Android 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes)、[Apple XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)。

## 資料、學習與授權

模型維持目前預製 `KeyKey.db`：119,159 Unigram、883,372 Bigram，檔案 SHA-256 為 `8fc3aead36cefd16a77c0a0d4319f7a305fb712b752db09396c8ac2bd4ebbfdb`。這些數值來自本次讀取的模型 manifest；不是本次重新執行完整 DB 驗證的結果。

Rust 遷移沿用現有 schema 與驗證入口，不在平台 build cooker。Android 仍核對私有 DB 快取與 asset；Windows 仍確保 DB 部署不依賴 DLL 是否重新連結。

使用者詞庫與學習資料要保留自訂詞、讀音、分數及 cache 行為。先隔離測試 fixture，再驗證舊資料讀入、重設、跨程序更新、寫入失敗及回退到舊引擎；若 schema 日後改變，另做可回復遷移，不在切換核心時直接覆寫唯一副本。

依 [LICENSING.md](../LICENSING.md)，參考／翻譯 Yahoo、Manjusri 或既有模組的衍生實作須保留其適用聲明；換語言不代表重新取得 MIT 授權。原創 Rust 範圍、Unicode 資料、詞庫與新增 crates 應在授權地圖及二進位 notices 中明列。

## 方案比較

| 方案 | 短期成本 | 長期維護 | 判斷 |
|---|---|---|---|
| 維持四套核心，補共同案例 | 最低 | 修正仍需多次移植，容易再分歧 | 可作準備階段，難以達到真正共用 |
| 抽成現代 C++ 共用核心 | 中高 | 同樣能收斂演算法；仍須處理 Swift／JNI／ABI | 必須保留為實際替代方案，不能只因 Rust 新就排除 |
| Rust 共用核心＋原生 adapter | 高 | 可集中邏輯、測試與資料規則；新增 Cargo／FFI 維護 | 建議先做原型，確認收益與團隊維護能力 |
| Rust 重寫所有 OS 接合與 UI | 最高 | 仍需 COM、ObjC、JNI、Fcitx 綁定 | 現階段沒有足夠產品收益支持此範圍 |

與「共用現代 C++」相比，Rust 額外價值主要是記憶體安全、狀態／錯誤建模及相依工具；消除四套重複本身不是 Rust 專屬優勢。效能、大小與迭代速度要用同一工作負載測量。

## 分階段遷移與粗估

以下是供決策的粗估人週，前提為一位熟悉本庫且能維護 Rust／FFI 的全職工程師，可使用六平台 SDK 與測試設備。未經原型校準，區間不是承諾，也不包含商店審核及外部等待。

| 階段 | 可交付結果與退出條件 | 粗估 |
|---|---|---|
| 0：行為盤點與原型 | 固定逐操作 trace、Store 原型、C ABI、Swift／JNI 最小真實連結；六平台工具鏈探針 | 2–4 人週 |
| 1：好打注音核心 | 唯讀模型、相容評分、候選／跨度、學習規則；固定 131 篇與各舊引擎差異報告 | 4–6 人週 |
| 2：完整輸入狀態機 | 注音讀音與配置、傳統注音、倉頡／簡易、關聯詞、組字編輯與兩種視窗政策 | 4–7 人週 |
| 3：五 frontend 接合 | 六平台宿主流程、使用者資料相容、建置／CI／封裝與平台回退 | 6–9 人週 |
| 4：驗收及逐平台切換 | 實機／宿主矩陣、長時間測試、效能／記憶體比較與正式發布準備 | 4–6 人週 |

合計約 **20–32 人週**；單人順序完成約 **5–8 個月**量級，外部等待另計。只做 Store 原型可限縮在前 2–4 人週，但不能稱為六平台共用核心完成。人力不足或主要目標只是一次性修正時，維持現況並加共同案例更划算。

接合順序建議先用 Linux／FreeBSD 驗證原生核心及套件能力，同時及早做 Swift／JNI 連結以暴露手機工具鏈成本；再接 iOS／Android，最後處理耦合 PlainVanilla 的 macOS／Windows。正式啟用順序依平台驗收結果決定。完整桌面功能如符號節點、組字選取新增詞及輸出 filter 在切換前要有功能對照表。

## 驗證與採用門檻

### 1. 行為正確性

建立同一格式的逐操作 trace，由仍在使用的原核心及 Rust 各自產生：

- 記錄讀音、未完成音節、文字、詞段／跨度、游標、完整候選次序、送字、已固定前綴及學習副作用。相容策略相同時要求可重現；已知平台差異單獨列入預期。
- 覆蓋標準／許氏、無聲調完成、無候選、詞跨度 override、句中選字後繼續句尾輸入、退格／Delete／Esc、空白與符號、切模式／切宿主、重複生命週期回呼。
- 固定 19 音節句「請假要去哪裡玩呢去海邊因為那裡有比基尼」檢查第 10、11、19 音節；觸控維持九／十，實體預設十／十一，學過「假」仍整詞擠出，無漏字／重複字。
- Android 雙排選字模式走觸控政策；iOS 實體鍵盤只驗證容器 App 前景，不把 extension 引擎測試當外接鍵盤宿主驗證。
- 既有倉頡 `tests/fixtures/mobile-table-input/cases.tsv` 與桌面案例繼續執行，包含即時候選、前綴 36 字、完整碼優先、五碼等待確認及設定相斥。
- 另跑舊使用者資料 fixture、多程序刷新、session 釋放、過期結果與失敗重試；確認預設輸出及擠字不新增學習。

### 2. 固定 131 篇動作數

沿用目前固定文章、固定語境讀音、每篇全新程序，關閉 user table、Bigram learning 與 candidate override；保留 settle 5、buffer 10、每頁 8 候選的正式操作模型。

現有工具只驅動 Manjusri，需新增 Rust adapter 並先證明兩邊的「開候選、翻頁、選字、擠字」計數等價。完整列出總動作、額外修正動作、逐字成本、各文章及基本／一般字差異，不以歷史 130 篇數字當這次新測量。

純移植的目標是相容模式下 **零未解釋差異**。儲存庫「至多增加 30 次」是目前自訂詞／模型採用規則，不能直接用來豁免引擎重寫的文字遺失、候選改變或學習差異。若另提統一排序／模型變更，再依最新規範做完整評估；不得把固定回歸集宣稱新盲測。

### 3. 效能與資源

在同裝置、同模型、同輸入操作及 release 設定下，量冷啟動／載庫、每鍵 P50／P95／P99、開候選、長文、學習寫入、峰值／穩態記憶體、安裝大小與 CPU。區分 Rust 演算法時間、FFI 轉換及真正宿主延遲。

原型先建立現況基線，再定數值門檻；建議先以 P95、峰值記憶體及冷啟動「不出現超過 10% 且可重現的退步」作調查線，最終依實際互動體感與裝置資源決策。此數字是提案，並非測量結果或現行產品規範。iOS extension 重啟／記憶體壓力與 Android 低階裝置需獨立驗證。

### 4. 平台與交付

`cargo test` 通過後仍須各平台 build、artifact 及宿主驗收：Windows x64／x86 TSF 及多宿主、macOS IMK 安裝版、iOS App／extension 與實機、Android SQLite instrumentation／既有 AVD 矩陣／實體鍵盤、Linux staged install／X11／GNOME Wayland、FreeBSD 原生 build／ports／Xfce。

FFI 增加 malformed input、Unicode、重複 destroy／過期結果等必要防護測試；原生邊界搭配適用 sanitizer，Rust 純核心可加入 fuzz／性質測試。模型 hash、平台產物內 DB、簽章與來源記錄仍逐層檢查。

## 概念驗證的決策點

建議先核定「階段 0 的範圍與時間上限」，不要一次承諾全面重寫。通過條件為：

1. 確認四套演算法的差異能以少量、可測的相容策略表達，沒有尚未理解的送字或學習副作用。
2. 六平台工具鏈可連結，Swift 與 JNI 至少有真實最小呼叫；Linux／FreeBSD 原生載入成功。
3. 代表性逐操作案例可比對，131 篇完整執行流程可用；未達完整比對前不切正式引擎。
4. 手機記憶體、冷啟動、JNI 成本與套件大小沒有使方案失去價值的退步。
5. 維護者能接受長期維護 Cargo、相依來源、FFI 及六平台 CI；現代 C++ 替代方案已比較。

若差異只能靠大量平台分支維持、手機原生封裝成本過高，或行為比較無法穩定重現，先停止擴大範圍，保留可重用的規格、fixture 與測試介面。

## 原始碼與現行規範入口

- [桌面好打注音模組](../Source/ModulePackages/OVIMMandarin/OVIMSmartMandarin.cpp)、[Manjusri Graph](../Source/Frameworks/Manjusri/Headers/Graph.h)、[LanguageModel](../Source/Frameworks/Manjusri/Headers/LanguageModel.h)。
- [Windows Engine](../Source/Loaders/Windows-TSF/KeyKeyEngine.cpp)、[Windows 開發與測試](../Source/Loaders/Windows-TSF/README.md)。
- [Swift Rust adapter](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/GuanyinmaInputEngine.swift)、[觸控尾段狀態](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/TouchSmartHostTextState.swift)、[mutation guard](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/DocumentMutationGuard.swift)。
- [Java Rust adapter](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/GuanyinmaInputEngine.java)、[Android 建置](../Source/Loaders/Android-IME/app/build.gradle.kts)。
- [Linux／FreeBSD Guanyinma 接合](GUANYINMA_LINUX_ADAPTER.md)、[Fcitx CMake](../Source/Loaders/Linux-IME/CMakeLists.txt)。
- [實體鍵盤邊界案例](SMART_MANDARIN_PHYSICAL_KEYBOARD_HANDOFF.md)，現況須核對程式碼。
- [正式模型 manifest](../DataSource/AISyntheticBigram/smart-mandarin-model-manifest.json)、[動作數定義](../DataSource/AISyntheticBigram/TYPING_COST.md)、[AGENTS](../AGENTS.md)、[BUILDING](../BUILDING.md)。

## Rust 遷移專用行為基準

仍在使用的原核心四種輸入法、完整候選排序與選字學習已建立[手動遷移基準](CROSS_PLATFORM_CORE_FUNCTIONAL_TESTS.md)。這份資料僅供 Rust 重寫／升級時參考與人工比較，不接入平時驗證、CI gate 或發布驗收；既有平台差異及已觀察到的不穩定排序均保留。
