# Guanyinma macOS 四種輸入法行為覆蓋

本表以 macOS 的 Manjusri／Formosa／OpenVanilla 為行為來源，記錄固定使用 Guanyinma Rust 核心的 FE 接合。普通 unit、整合與原生 adapter 測試驗證目前公開介面契約；舊核心來源對照須明確指定 `--migration-reference`，`tests/fixtures/core-functional/` 也只作手動遷移參考，兩者均不作日常或發布 gate。來源 DB 維持唯讀，測試使用獨立使用者資料。

## 驗證分工

下表是共用介面及 macOS 設定映射的覆蓋清單，主要透過無 UI 的 Rust／C ABI／原生 context 對照驗證，不是逐項操作桌面的 UI 清單。核心測完共用規則後，六平台 FE 分別測事件、設定、座標、宿主 effects、字型及儲存接合；UI 只做少量自動化冒煙，不重複整套核心矩陣。核心工作不切換使用者的系統輸入法。

## 事件與操作邊界

macOS 先由 `OpenVanillaController.handleEvent` 收到 `NSEvent`，辨識宿主快捷鍵、實體鍵盤來源與單按 Shift，再經 PV 派送至輸入核心。FE 決定快捷鍵對應的行為，核心接受語意操作，不依 OS 名稱決定按鍵表。

| 行為 | 核心入口 | 保留規則 |
|---|---|---|
| 指定全形／半形 | `set_full_width {enabled:true/false}` | 不清讀音、組字、候選或游標；同值冪等 |
| 切換全半形 | `toggle_full_width` | 反轉寬度狀態，不自行綁 Shift+Space |
| 指定英文／中文 | `set_english {enabled:true/false}` | 模式改變時先保留／送出組字；同值不重送 |
| 切換中英文 | `toggle_english` | 使用同一個保留／送字流程 |
| 指定輸入法／配置 | `set_method`／`set_layout` | 保留舊可見輸入後改變狀態 |
| 完成輸入／清除 | `finish`／`reset` | 完成與丟棄是不同操作，不混用直接文字 |
| 開關候選、翻頁及選字 | `open_candidates`／`close_candidates`／`page`／`select` | 使用核心完整候選及當頁索引 |
| 原生直接文字 | `direct_text {text}` | 各法沿用原生直接文字事件規則 |

macOS 既有全半形及繁簡選單仍經共同的原生 output-filter 管線。核心全半形操作供 FE 明確選擇；Shift+Space 在核心只是一個帶 Shift 的 Space。單按 Shift 的 300ms 辨識及啟用選項留在 FE。中英模式在宿主保留交易成功後同步到 Rust session；焦點返回與中文事件進入前同步，避免跨 context 使用舊模式。宿主拒絕文字或核心設定失敗時不重送已送文字、不虛報模式已切換。

## 注音設定

| 原生設定 | 好打注音 | 傳統注音 | Guanyinma 接合 |
|---|---|---|---|
| `KeyboardLayout` | 五配置 | 五配置 | 標準、許氏、倚天、倚天 26、漢語拼音；接受 Formosa 名稱及舊別名 |
| `CandidateSelectionKeys` | 可設定；空值按配置預設 | 可設定；空值按配置預設 | FE 與核心分頁使用相同選字鍵 |
| `UseCharactersSupportedByEncoding` | 系統／UTF-8／Big5 | 系統／UTF-8／Big5 | FE 提供候選可用性；未知值按原核心回到系統判斷 |
| `ShowCandidateListWithSpace` | 對應 `space_opens_candidates` | 不適用 | Space 開候選或插空白；Caps Lock 路徑按原核心處理 |
| `CandidateCursorAtEndOfTargetBlock` | 對應 `candidate_cursor_at_end` | 不適用 | 候選目標與實際組字游標分開 |
| `ClearComposingTextWithEsc` | 對應 `clear_composing_with_escape` | 不適用 | 未完讀音先清讀音；整句清除依選項 |
| `ComposingTextBufferSize` | 10～20 | 不適用 | 完整詞段擠出，macOS 超過上限才擠字 |
| `ShiftKeyAlwaysCommitUppercaseCharacters` | 對應 `shift_always_uppercase` | 不適用 | FE 先完成 macOS 字元轉譯，核心處理明確大寫政策 |

`ClearComposingTextWithEscUserChoice` 是 Windows 舊設定遷移標記，不改 macOS 的 Esc 設定規則。無效選字鍵、壞資料路徑等須拒絕並回報；現有 session 遇到無效設定更新時保留最後有效設定，不切換另一個核心或靜默改成另一個有效設定。

## 倉頡與簡易設定

| 原生設定 | 倉頡／簡易接合 |
|---|---|
| `ComposeWhileTyping` | `realtime`；即時候選與錯碼清除互斥 |
| `PrefixCandidates` | 倉頡 `prefix`；完整碼在前，過濾後補最多 36 字 |
| `ClearReadingBufferAtCompositionError` | `clear_on_error`；未存值時兩法沿用舊引擎的開啟預設；簡易設定頁初始為關，已存 FE 值優先；即時候選時不清碼 |
| `ShouldCommitAtMaximumRadicalLength` | `query_at_maximum`；完整五碼前綴預覽不誤送字 |
| `MaximumRadicalLength` | `maximum_radical_length`；省略使用 5／2 |
| `UseDynamicFrequency` | `learning.table_learning` 及 `learn_selection`；明確選字才記錄 |
| `UseSpaceAsFirstCandidateSelectionKey` | `space_as_first_selection_key`；候選鍵及頁大小一併傳入 FE |
| `SendFirstCandidateWithSpaceWithOnePageList` | `space_commits_first_on_single_page` |
| `MatchOneChar`／`MatchZeroOrMoreChar` | `wildcards.one/many`；停用與自訂字元均按行為設定 |
| `UseOverrideTable` | 原字表、既有倉頡半形／混合標點；不以任意 SQL 字表名稱擴張核心介面 |
| `UseCharactersSupportedByEncoding` | 與注音共用 FE 字型／編碼接受回呼 |

字型過濾在完整碼、wildcard、前綴上限、排序及分頁之前進行。實際 macOS 字型下「竹大」保留「夭」並以前綴補上第二候選「喬」；完整順序依同一台機器的原生字型服務核對，不將罕字字型範圍寫死於 Rust。

## 輸入、學習與生命週期

| 範圍 | 檢查內容 |
|---|---|
| 注音解析 | 五配置、舊別名、聲調、刪除、完整候選、讀音及文字座標 |
| 好打組句 | Bigram/backoff、候選方向、Ctrl 標點目標、選詞、句中編輯、10／11／19 及 20 音節邊界 |
| 圈選加詞 | Shift 選取六個讀音、取消、確認、scalar 反白、重複詞、混合 query 及原子保存 |
| 字表輸入 | 即時／確認、前綴、wildcard、翻頁、單頁 Space、錯碼與碼長、自訂選字規則 |
| 選字學習 | 明確候選記錄、前綴不記、繼續字根的隱式送字不記、跨 session 同步與 stale view 拒絕 |
| 修飾鍵 | macOS 真實 Shift／Caps Lock 文字、已由 FE 放行的 Ctrl 標點、候選 non-panel 拒絕、直接文字 |
| 數字鍵盤 | 使用者指定的 `literal_keypad` 行為；主鍵盤不因全域 NumLock 被誤判 |
| 宿主與設定 | 保留交易、重入／失敗、未完成讀音、候選擁有權、安全邊界更新設定、焦點返回、重複生命週期回呼 |
| 使用者資料 | 自訂詞 CRUD、Guanyinma DB、reset 保留詞、明確 MJSR／JSON 匯入匯出，固定 Rust backend token 並拒絕舊核心 token |
| 共同 FE | 一般設定三語完整視窗、候選窗樣式／比例／配色、原生 output／around filters、符號與中英模式 |

macOS Shift 字母事件由 `NSEvent.characters` 提供實際大寫字元；原核心到語意文字的反轉規則留在 macOS FE。人造的「小寫 keyCode 搭 Shift」不是這條實體事件路徑，不據此改變共用核心的明確文字契約。

## 普通驗證入口

```sh
# Rust unit／整合與真正 C consumer；不讀遷移基準
(cd Source/Guanyinma && cargo test --locked)
(cd Source/Guanyinma && python3 tests/run_c_abi_test.py --release)

# FE 單核心 package／設定／使用者資料接合；依改動選擇 suite
python3 Source/Loaders/OSX-IMK/Tests/run-guanyinma-tests.py \
  --suite integration --library /absolute/path/to/libguanyinma.a
python3 Source/Loaders/OSX-IMK/Tests/run-guanyinma-tests.py \
  --suite archive --library /absolute/path/to/libguanyinma.a
python3 Source/Loaders/OSX-IMK/Tests/run-input-mode-tests.py
python3 Source/Loaders/OSX-IMK/Tests/run-general-preferences-window-tests.py
```

平台 workflow 只跑少量 `integration` FE 接合；完整 Rust／C ABI 核心矩陣仍由 `guanyinma-core.yml` 負責。上面的 archive 測試使用固定格式資料，不建置舊核心。

需要遷移分析時，手動加上 `--migration-reference` 才編譯歷史來源 oracle：

```sh
python3 Source/Loaders/OSX-IMK/Tests/run-guanyinma-native-behavior-tests.py \
  --migration-reference --library /absolute/path/to/libguanyinma.a
python3 Source/Loaders/OSX-IMK/Tests/run-guanyinma-tests.py \
  --suite archive --migration-reference --library /absolute/path/to/libguanyinma.a
```

來源 oracle 不讀取或更新 functional baseline，也不加入日常、CI 或發布驗收。unit、原生隔離管線、實際 IMK 文字宿主、建置產物、安裝包及正式簽章是不同證據層級；未完成的層級不能由另一層替代。正式建置及封裝入口見 [macOS 接合文件](GUANYINMA_MACOS_ADAPTER.md)。
