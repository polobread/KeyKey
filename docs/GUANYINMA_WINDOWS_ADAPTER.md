# Guanyinma Windows TSF 接合

Windows 1.5.0 同一個 TSF frontend 的四種輸入法固定使用 Guanyinma Rust 核心。一般設定沒有核心選項，舊 `InputCore` 偏好不影響輸入；產品不建置或回退到 Manjusri／Generic 原核心。正式發布狀態仍以 README 與安裝文件為準。

## 輸入與宿主權責

`KeyKeyEngineSession` 保留既有 PV sandwich，Rust context 只透過正式 C ABI 處理四種輸入法；候選窗、關聯詞互動、繁簡輸出、Shift 單按、中英文及全半形切換仍由 Windows FE 處理。關聯詞查詢、分類順序與去重經獨立唯讀 C ABI 執行。原生 module 只提供識別與設定接合，不建立 C++ 輸入核心或舊可寫學習庫。按鍵沿用固定美式虛擬鍵轉換，好打注音沿用 10～20 音節設定與十／十一音節桌面邊界。

輸入法及設定變更仍由 TSF 在既有有序交易邊界處理，保留組字、候選與待送效果，不重播事件。獨立非 controlled session 依目前輸入法的設定內容重新建立 Rust context。候選分頁／游標先由既有 PV panel 處理，回呼以文字、索引及跨度核對後轉成 Rust page-local 操作。

TSF 的有序 edit-session 佇列與 retained result 保留原有權責：先重試前次宿主效果，成功後才進入下一個引擎事件。因此 Rust 已產生 commit，但宿主尚未接受選取／寫入時，不會重複送字或學習。沒有宿主／失焦／取消仍走既有 TSF 邊界，不把引擎快照當成宿主送字成功。

Windows 預設忽略中文 Caps Lock。數字鍵盤先保留目前顯示文字再直接輸入；主鍵盤不因全域 Num Lock 被視為 keypad。Rust session 建立失敗或設定不受支援時回報失敗，不建立另一核心、不轉交已接受事件重播。

## 字型與座標

每個 Rust context 固定持有 Windows DirectWrite 系統字型集合及 fallback 判斷，搭配既有 Big-5／UTF-8 字集設定，經 `guanyinma_session_open_with_candidate_filter` 在排序、分頁與 Smart graph 之前過濾。callback 同步、不可拋出例外，生命週期涵蓋 Rust session。FE 不在顯示階段另刪候選。

Rust 游標使用 Unicode scalar；adapter 轉成 PV 組字／未完成讀音，最後由既有 `PVCombinedUTF16TextBuffer` 產生 TSF 的 UTF-16 游標。Windows JSON 服務僅用於 ABI transport；每次操作平衡 WinRT 初始化，釋放本次 apartment 前清除 factory cache，避免獨立無 UI consumer 在下一次操作使用已卸載的 factory。

## 使用者資料

| 資料 | 擁有者 |
|---|---|
| 共用 `Databases/KeyKey.db` | 唯讀正式模型，建置不 cooker |
| `SmartMandarinUserData.db` 與既有表格排序檔 | 保留舊檔；只供明確唯讀匯入 |
| `GuanyinmaUserData.db` | Rust 自訂詞、好打與表格學習，全部透過 C ABI |

使用者資料沿用 `SettingsDirectory()`。桌面通常在 Roaming AppData；受限宿主沿用其可寫的私有位置。runtime preferences 發布 v2 格式，接受 v1／v2 及舊 v3；v3 的核心欄位只消耗、不套用或回存。這個通道不傳送自訂詞或學習，不放寬 profile ACL。

每個設定視窗以 SafeHandle 開啟 Guanyinma 詞庫。Rust 列 token 只對應該 handle 的詞語／讀音快照，重載後拒絕舊 token，不拿它當 SQLite rowid；舊詞庫只在明確匯入時唯讀開啟。產品沒有原核心詞庫的 CRUD 或備份輸出入口。

Rust 的「重設好打注音學習紀錄」只清 Smart 學習，保留自訂詞及表格學習。匯出為完整版本化 JSON，包含自訂詞及各種學習，不含 generation／revision；匯入先驗證再原子套用。既有 Windows SQLite 詞庫只在明確匯入時唯讀開啟，不自動遷移。匯出透過同目錄暫存檔原子替換，拒絕模型、現用／舊詞庫、sidecar 及其檔案身分別名，失敗保留原備份。

Guanyinma 詞庫的讀音編解碼經無資料庫／session 的 `guanyinma_reading_codec` C ABI，Windows 不再複製 Formosa 的 codec。編碼使用逗號分隔、同類後項覆蓋前項、拒絕空項，並保留既有非注音成分忽略規則；解碼保留 printable modulo 與忽略奇數尾 byte 的相容行為。格式錯誤回傳失敗，不套用詞庫修改。

## 建置

Guanyinma 為必要建置依賴，需要 Python 3.11 以上與 `Source/Guanyinma/rust-toolchain.toml` 鎖定的 Rustup 工具鏈。x64 使用 `x86_64-pc-windows-msvc`，x86 使用 `i686-pc-windows-msvc`；建置兩者前需安裝相應 Rust target。原有 CMake presets 與產品版號來源維持不變。

`tools/build-windows-core.py` 只執行鎖定依賴的 Release build，Rust 與原生 FE 共用 `+crt-static`／`/MT` 及 bundled SQLite。C++ header 直接取自 Cargo.lock 解析到的 `libsqlite3-sys`，不使用舊版 bundled header，也不混用 WinSQLite 的 x86 stdcall ABI。原生 Debug 仍使用 `/MT`，保持 CRT 一致，並可產生原生偵錯資訊。Rust 分配的物件只經 C ABI 對應 close 釋放；靜態連結不另部署 Rust DLL。

建置固定產生 `guanyinma/Guanyinma-NOTICES.txt`，含完整 Rust、crate、來源／資料與 SQLite notices。兩個封裝入口及待簽 artifact 必須包含此檔，缺少時中止封裝。舊 store 寫入工具只留在測試 fixture，歷史 migration recorder 只可明確手動建置，不連入產品、不加入一般 CTest 或 CI gate。

## 局部驗證

以下於已載入 MSVC 的 Developer PowerShell，從 `Source/Loaders/Windows-TSF` 執行；建置目錄依實際 preset 調整：

```powershell
cmake --preset windows-x64
cmake --build out/build/x64-ninja --target KeyKeyGuanyinmaIntegrationTest KeyKeySettingsBackend KeyKeyTsfOutputBehaviorTest
ctest --test-dir out/build/x64-ninja -C Release --output-on-failure --no-tests=error `
  -R '^KeyKeyGuanyinma(Adapter|UserData|TsfHostEffects|SettingsControls)$'
```

這些是少量 FE 冒煙：無偏好時四法直接建立 Rust session、忽略舊核心偏好與快照、無失敗回退、基本候選與送字、UTF-16、獨立資料／封存、TSF 宿主拒絕後重試，以及真正 WPF 控制項／PInvoke CRUD。使用隔離 profile，不註冊 TIP、不切換使用者系統輸入法，也不讀遷移 functional baseline。

讀音 codec 的行為與 C ABI 由核心無 UI 測試驗證；Windows x64／x86 已執行原生 Rust 測試與真實 C consumer，使用 bundled SQLite 並核對正式模型前後雜湊。MSVC consumer 的匯入程式庫須放在 `/link` 之後，避免被 `/TC` 當成 C 原始碼編譯。這些結果不代替實際文字宿主或安裝驗收。

完整 Rust／C consumer／跨平台核心矩陣仍只由 `guanyinma-core.yml` 負責。Windows workflow 直接建置並連結核心，保留既有平台建置與發布結構。x64／x86 原生可執行檔通過不代表 Windows Search AppContainer、真實文字宿主、安裝升級或簽章／發布完成；這些層級仍須分別驗收。
