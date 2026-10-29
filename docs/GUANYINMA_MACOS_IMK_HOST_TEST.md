# Guanyinma macOS 真 IMK 宿主測試

本流程讓固定使用 Guanyinma Rust 核心的 macOS frontend 經過系統 TIS、IMKServer、OpenVanillaController，實際送入 Cocoa `NSTextView`。它補足 core unit、C ABI、adapter 與 mock client 無法證明的宿主路徑。`tests/run_core_functional.py` 與遷移 fixture 不參與本流程。

## 使用範圍

這是 macOS FE 接合、宿主生命週期或安裝異常的**選用診斷工具**，不是 Rust 核心的日常測試或完成門檻。核心以無 UI 的公開介面／行為契約驗證為主；各平台 FE 接合另行處理，UI 只保留少量自動化冒煙。後面的診斷項目按實際修改挑選，不在每次核心開發全部執行，也不要求使用者逐項代打或反覆搶用其桌面輸入法。

## 隔離範圍

`Source/Loaders/OSX-IMK/Tests/prepare-guanyinma-host-test.py` 先在 `Installer/local-builds/` 建立原始碼私有副本，再依現有 `Takao (Loader OSX-IMK)` Release target 與 `Takao-macOS.xcconfig` 建置 Rust 單核心。正式原始碼及 `KeyKey.db` 不修改；模型以複製檔納入 App，建置前後比對 SHA-256。版號沿用來源 plist，不另寫產品版號。

每次使用新的 tag，建立獨立的命名。主 App／source ID 採含 `.inputmethod.` 的完整片段，並在末端保留 `KeyKey`；不使用只以 `.inputmethod` 結尾的測試 ID：

| 用途 | 命名 |
| --- | --- |
| 主 App／TIS source ID | `io.github.polobread.guanyinma.imktest.TAG.inputmethod.KeyKey` |
| IMK connection | `io.github.polobread.guanyinma.imktest.TAG.inputmethod.KeyKey_Connection` |
| DO connection | `GuanyinmaIMKTestService_TAG` |
| loader identifier／plist 前綴 | `io.github.polobread.guanyinma.imktest.TAG.loader` |
| loader name／Application Support | `KeyKey-Guanyinma-IMK-Test-TAG` |
| 測試宿主 App | `io.github.polobread.guanyinma.imktest.TAG.host` |

IMK connection 採完整 bundle ID 加 `_Connection`，編入的宏、`InputMethodConnectionName`、manifest 及 Host 驗證必須完全相同。系統 launch agent 可能拒絕任意格式的連線名稱，即使來源可註冊／選取、IME 行程已啟動，仍不能據此認定 IMK client 已連上。

macOS 的 `UserPreferencesDirectory(applicationName)` 忽略 applicationName，直接使用 `~/Library/Preferences`，因此只換 loader name 並不足夠。工具同時更換 loader identifier；Guanyinma 使用者 DB 落在上述新 Application Support 目錄，既有 Manjusri profile 不自動讀寫或改刪。

四個命名宏透過 `OTHER_CFLAGS`／`OTHER_CPLUSPLUSFLAGS` 尾端的 `-U`／`-D` 覆寫，保留 target 的 `GCC_PREPROCESSOR_DEFINITIONS` 與四法 module IDs。私有副本只允許改指定的 identity／metadata 檔案，包括子 Preferences／PhraseEditor 的 bundle ID、硬編 plist／cache 名稱及 fallback launch ID。演算法及 Rust source 保持原始位元組，manifest 記錄雜湊及 allowlist。測試不要開正式偏好設定、詞庫編輯器或讀取／匯入正式 profile。

測試 App 不註冊正式 URL scheme，更新 feed／key 留空並從產物移除。未設定 feed／key 時 updater 不連線。正式 installer 的 `InputSourceTool`、preinstall／postinstall 會處理正式安裝位置及行程，**本隔離流程不執行它們**。

## 準備與編譯

先完成要測的 core／FE 修改，再 snapshot，避免測到舊版。依 [BUILDING.md](../BUILDING.md) 準備 Xcode、OpenSSL、已快取的 pinned Rust toolchain／依賴與 Sparkle SDK。下列命令不安裝、啟動 App，也不呼叫 TIS：

```sh
python3 Source/Loaders/OSX-IMK/Tests/prepare-guanyinma-host-test.py prepare \
  --tag YOUR-UNIQUE-LOWERCASE-TAG \
  --output "$PWD/Installer/local-builds/guanyinma-imk-host-YOUR-TAG"

# 保留呼叫端既有 CARGO_HOME／RUSTUP_HOME；build 使用離線 Cargo。
python3 Source/Loaders/OSX-IMK/Tests/prepare-guanyinma-host-test.py build \
  --output "$PWD/Installer/local-builds/guanyinma-imk-host-YOUR-TAG" \
  --cargo /absolute/path/to/pinned/cargo

python3 Source/Loaders/OSX-IMK/Tests/prepare-guanyinma-host-test.py verify \
  --output "$PWD/Installer/local-builds/guanyinma-imk-host-YOUR-TAG"
```

tag 僅接受小寫英數與 `-`，`prepare` 不覆寫已有目錄。不指定 tag／output 時會產生新的日期／隨機 tag 與 local-builds 目錄。編譯、簽章、host 編譯記錄保存在該輸出目錄；`manifest.json` 記錄命名、原始碼、模型及產物雜湊。這些是本機產物，不提交。

Xcode 的 macOS App build 可能自動執行 `RegisterWithLaunchServices`，讓 raw build 產物也進入 App 解析清單；這與 TIS 輸入來源註冊是不同動作。本機目前未找到可驗證的布林 build setting 來關閉此階段，不使用猜測的設定名稱。Host 啟用前會正常註冊精確的已安裝 App，並拒絕 preferred URL 仍指向其他副本的情況。

`verify` 檢查私有原始碼、四個編入的 connection／profile 字串、主／子 App identity、模型複製、網路設定與 `codesign --verify --deep --strict`。通過只證明產物可審查，尚未證明 TIS 或 IMK 中文輸入。

## Stage、啟用及還原

先 review manifest、隔離路徑與已簽章 App，再明確執行 stage：

```sh
python3 Source/Loaders/OSX-IMK/Tests/prepare-guanyinma-host-test.py stage \
  --output "$PWD/Installer/local-builds/guanyinma-imk-host-YOUR-TAG"
```

此步只複製到 `~/Library/Input Methods/KeyKey Guanyinma IMK Test TAG.app`，拒絕已有目的地；不要求 admin，不啟動、不註冊、不啟用、不選取。它不覆蓋 `/Library/Input Methods/chichi77 KeyKey.app`，也不終止正式 KeyKey 行程。

以一般 UI 開啟輸出內的 `Manual Guanyinma IMK Host.app`。啟動時僅建立視窗及記錄，文字欄尚不可編輯，未呼叫 TIS。由操作者按 **「啟用隔離測試輸入法」**，才會：

1. 驗證精確的 per-user App 路徑、獨立 identity／marker、模型及執行檔 SHA-256。對該已驗證 URL 執行正常的 `LSRegisterURL(url, true)`，再確認 LaunchServices 對此 bundle ID 的 preferred URL（解析 symlink 後）就是該安裝路徑；不一致便停止，不呼叫 TIS。此步只更新這個 App 的正常註冊，不清除或重建全域資料。`launchServicesRegistration` 記錄 status 及兩邊路徑。
2. 保存目前 TIS source；若無法讀取，或已選此測試來源卻沒有先前來源，立即拒絕。
3. `TISRegisterInputSource`，依完整 source ID 查唯一來源，另以 bundle ID 作診斷查詢；記下測試來源原啟用狀態。註冊結果及兩種查詢筆數寫入 `registrationResult`；`-1` 表示 NULL、`-2` 表示未查詢，UI 亦明列這些狀態。
4. 保存 `restore-state.plist`，僅在需要時 enable；呼叫一次後回到主事件迴圈，每 250 ms 以完整 source ID 重新查詢，最多等待 5 秒；確認 enabled 才以新參照 select，不重複 enable。每次記錄 generation／attempt／elapsed 及來源屬性，逾時記錄 rollback。還原及關閉會使 generation 失效，過期回呼不能選取來源。`enableResult`、`enableVerification`、`selectionResult` 分別記錄 OSStatus、來源屬性及確認結果。啟用、選取或確認失敗即進入還原，UI 明列失敗階段。
5. 開放下方 `NSTextView`，由實體鍵盤或 Cua 的正常鍵盤操作輸入。

macOS SDK 明定註冊的 IMK App 必須在 `/Library/Input Methods/` 或 `~/Library/Input Methods/`。單獨建立新的 `NSTextInputContext`、直接呼叫 core，或從任意 build 目錄啟動 IMK 都不能取代這個系統路徑。首次來源註冊若未能由系統使用，記錄 OSStatus 及實際現象，可能須新登入／獨立測試帳號；不要改 HIToolbox plist、重啟系統 agent、登出使用者或繞過系統限制。

測試切換會暫時改變目前輸入來源。測完按 **「還原來源」**，正常關閉視窗／退出亦先還原。若目前仍選測試來源，工具選回保存的來源；若使用者已自行改選其他來源，工具不覆蓋後來的選擇。只停用由工具啟用的測試來源，不停用正式來源。還原每一步記錄 fresh source 查詢、選回結果、disable 結果及再次查詢確認。還原失敗時保留視窗及 recovery 檔，要求操作者在系統選單還原後重試。異常崩潰／強制結束無法保證自動還原，依 recovery 檔中的 source ID 手動處理。

宿主固定使用 Rust，不提供核心切換。「套用輸入法」只寫獨立 loader plist 的 `PrimaryInputMethod` 並透過獨立 DO reload；有 marked text 時拒絕，須先完成或取消組字。這個控制項用來選擇同一 FE 的四種輸入法，也可使用隔離來源自己的輸入選單。不要開正式來源的 Preferences。

若來源已選取但實際文字宿主仍只有 raw 字母、且查不到該測試 IME 行程，可由操作者明確按 **「啟動隔離服務」** 分開驗證背景 App 啟動。按鈕先核對已安裝 App 的 namespace／雜湊及 exact LaunchServices preferred URL，再用 `NSWorkspace.openApplicationAtURL` 開啟該精確 URL；不啟用 App 前景、不強制新 instance、不替換成其他 URL 的執行中副本，也不操作 TIS／中英模式／按鍵。`serviceLaunchResult` 記錄錯誤、PID、Bundle ID、執行檔 URL 與核對結果。這只能證明操作者明確啟動的服務，**不能宣稱正常選取後的自動啟動已通過**。

## 同 Bundle ID 的測試副本干擾解析時

若 `launchServicesRegistration` 顯示 preferred URL 仍指向 build 目錄，先只讀查詢該精確 Bundle ID 的所有 App URL，確認實際安裝位置的簽章、執行檔雜湊與 plist 都正確。不可從 raw 字母輸入直接判定核心有錯，也不建立新的核心特例。

可回復的處理僅限該次隔離測試的未安裝 App 副本：先關閉測試 Host、確認來源已還原，並在必要時核對精確路徑及執行檔身分後正常退出該測試 IME。對每份待退休 App 核對實際路徑、隔離 tag 及完整 Bundle ID，排除 `/Library/Input Methods`、已安裝的 per-user App、Host.app、私有 Source、安裝包及所有使用者 profile。

每份 App 先用 `ditto -c -k --sequesterRsrc --keepParent` 建立獨立 ZIP，記錄原路徑、ZIP／Trash 路徑、ZIP SHA-256，以及每個一般檔案的 SHA-256／大小／模式與 symlink 目標。檢查 ZIP CRC，逐檔核對封存的內容及 symlink，所有副本驗證完成後才移到專屬的 `~/.Trash/` 測試子目錄；移動後再核對完整檔案樹。ZIP、metadata 與 Trash 原件都保留，不永久刪除。不必為驗證另外解壓出同 ID 的 live App，避免新副本再次參與解析；需要還原時可依 metadata 從 Trash 原件移回，或從已驗證 ZIP 還原。

移入 Trash 後，LaunchServices 可能仍依原 App 身分追蹤到 Trash 路徑。若只讀查詢證實仍是這些已退休副本，先 review 原路徑／Trash 路徑／Bundle ID manifest，再檢查系統 `lsregister -h` 確認 `-u` 是逐指定路徑解除註冊；僅對該 manifest 列出的退休 App URL 執行正常的 `lsregister -u PATH` 卸載註冊生命週期。記錄每個命令、status、stdout／stderr與 fresh probe，排除已安裝 App 及其他 ID，不使用全域重建／清除／掃描參數。解除後仍保留 ZIP 與 Trash 原件，必要時可還原檔案並透過正常 per-App 註冊回復。

只讀重新查詢 preferred URL，然後重新開啟 Host，讓正常的精確 per-App 註冊及路徑 gate 再驗一次。若 Trash 權限受阻、出現未知路徑／ID、測試 IME 仍執行，或 preferred URL 仍錯誤，就停止並回報；不永久刪除，不改 HIToolbox、不重建全域 LaunchServices 快取、不重啟系統 agent。

## 實際宿主驗收

依受影響的 FE 接合挑選少量案例，記錄 Rust 核心、輸入法、隔離 FE 設定、鍵盤操作、marked text、候選畫面及最終宿主字串。候選排序、學習與組句矩陣以無 UI 測試驗證，不逐項在桌面重跑；不以註冊成功、mock client 或 unit 通過代替已選宿主案例的實際輸入。舊核心的來源對照另由明確的 `--migration-reference` 手動入口處理，不要求在此工具切換核心。

- 四法：好打注音、傳統注音、倉頡、簡易；測讀音／字根、完成、候選翻頁、Esc／Backspace、Return、方向鍵、錯碼及全半形。
- 倉頡「竹大」：分別測即時候選／未打完也能選字組合；檢查系統字型過濾後的候選順序，實際選「喬」。
- 好打注音：句中選詞、前後選字目標、空白開候選、三組選字鍵、10／20 音節及 10／11／19 邊界；實際確認無重複／漏字。
- 設定與 FE：五種注音鍵盤配置、標點、Esc 清組字、Shift 字母大小寫、Caps Lock、數字鍵盤、單按 Shift 切中英、Shift+Space 依普通 Space 處理及原生全半形選單；共用語意 set／toggle 介面另由 unit test 驗證。對無法由 Cua 可靠發出的實體事件，須明列尚未驗證，不偽稱通過。
- 使用者資料：只在隔離 profile 做少量新增詞、詞庫管理與 JSON 備份接合；學習演算法另由無 UI 測試驗證。需要 MJSR 交換時使用明確指定的副本，不讀寫正式唯一副本，也不自動改刪舊 Manjusri 檔。
- 生命週期：組字中切焦點、切 App／輸入來源、候選顯示中失焦與返回、完成組字後切換輸入法、重複回呼；逐次檢查宿主送字次數。宿主工具只有單一文字欄，跨 App 行為須另以實際文字宿主測試。

`host-events.jsonl` 只記錄此工具自身 NSTextView 收到的 `keyDown`、`setMarkedText`、`insertText`、`unmarkText`、來源及 UI 控制結果；包括實際 characters／keyCode／modifiers／repeat，以及該文字欄的輸入情境來源、current context、焦點與視窗狀態，沒有全域鍵盤攔截或合成事件。範圍使用 AppKit 的 UTF-16 NSRange；不能直接當作 Rust scalar offset。候選視窗／設定版面需由實際 UI 截圖補證。

完成後先還原來源、關閉隔離宿主與隔離 IMK，確認未再選取該來源，再移除精確的 test App 及其 tag 對應 profile。TIS 沒有一般的 unregister API，停用及移除後的來源清單更新由 macOS 管理；不要直接修改系統偏好資料。保留測試紀錄時只保留 local-builds 產物，不提交詞庫、畫面或事件記錄。
