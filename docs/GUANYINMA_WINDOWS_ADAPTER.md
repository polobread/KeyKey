# Guanyinma Windows TSF 接合

Windows 同一個 TSF frontend 可選 Manjusri 原核心或 Guanyinma Rust 核心，預設為 Manjusri。一般設定的「輸入核心」保存 `InputCore=Manjusri/Guanyinma`；缺少或未知值沿用原核心。這是開發接合，正式發布狀態仍以 README 與安裝文件為準。

## 輸入與宿主權責

`KeyKeyEngineSession` 保留既有 PV sandwich，Rust context 只透過正式 C ABI 處理四種輸入法；候選窗、關聯詞互動、繁簡輸出、Shift 單按、中英文及全半形切換仍由 Windows FE 處理。Rust context 的關聯詞查詢、分類順序與去重經獨立唯讀 C ABI 執行；原核心的查詢仍保留。按鍵沿用固定美式虛擬鍵轉換，不在 adapter 重寫注音解析或排序。好打注音沿用 10～20 音節設定與十／十一音節桌面邊界。

核心偏好與輸入法選擇分開。舊 context 有未完成讀音、組句或候選時繼續使用原核心；完成後，由下一個新輸入事件採用偏好，不重播事件。候選分頁／游標先由既有 PV panel 處理，回呼以文字、索引及跨度核對後轉成 Rust page-local 操作。選字與取消仍交給產生該候選的核心。

TSF 的有序 edit-session 佇列與 retained result 保留原有權責：先重試前次宿主效果，成功後才進入下一個引擎事件。因此 Rust 已產生 commit，但宿主尚未接受選取／寫入時，不會先換核或重複學習。沒有宿主／失焦／取消仍走既有 TSF 邊界，不把引擎快照當成宿主送字成功。

Windows 預設忽略中文 Caps Lock。數字鍵盤先保留目前顯示文字再直接輸入；主鍵盤不因全域 Num Lock 被視為 keypad。Rust session 建立失敗或原生設定不受支援時，建立前可回退原核心；已接受的事件失敗不轉交另一核心重播。同一偏好不逐鍵重試初次換核失敗，重新選擇核心或重建 context 可再嘗試。

## 字型與座標

每個 Rust context 固定持有 Windows DirectWrite 系統字型集合及 fallback 判斷，搭配既有 Big-5／UTF-8 字集設定，經 `guanyinma_session_open_with_candidate_filter` 在排序、分頁與 Smart graph 之前過濾。callback 同步、不可拋出例外，生命週期涵蓋 Rust session。FE 不在顯示階段另刪候選。

Rust 游標使用 Unicode scalar；adapter 轉成 PV 組字／未完成讀音，最後由既有 `PVCombinedUTF16TextBuffer` 產生 TSF 的 UTF-16 游標。Windows JSON 服務僅用於 ABI transport；每次操作平衡 WinRT 初始化，釋放本次 apartment 前清除 factory cache，避免獨立無 UI consumer 在下一次操作使用已卸載的 factory。

## 使用者資料

| 資料 | 擁有者 |
|---|---|
| 共用 `Databases/KeyKey.db` | 唯讀正式模型，建置不 cooker |
| `SmartMandarinUserData.db` 與既有表格排序檔 | Manjusri／Generic 原核心 |
| `GuanyinmaUserData.db` | Rust 自訂詞、好打與表格學習，全部透過 C ABI |

使用者資料沿用 `SettingsDirectory()`。桌面通常在 Roaming AppData；受限宿主沿用其可寫的私有位置。`InputCore` 納入 v3 runtime preferences 允許清單；v1／v2 快照回到 Manjusri。這個設定通道不傳送自訂詞或學習，不放寬 profile ACL。

每個設定視窗以 SafeHandle 固定開啟時的資料核心。套用另一核心後，原視窗的詞庫 CRUD、匯入／匯出及重設仍使用原資料；重新開啟設定才管理另一核心。Rust 列 token 只對應該 handle 的詞語／讀音快照，重載後拒絕舊 token，不拿它當另一個 DB 的 rowid。

Rust 的「重設好打注音學習紀錄」只清 Smart 學習，保留自訂詞及表格學習。匯出為完整版本化 JSON，包含自訂詞及各種學習，不含 generation／revision；匯入先驗證再原子套用。既有 Windows SQLite 詞庫只在明確匯入時唯讀開啟，不自動遷移。匯出透過同目錄暫存檔原子替換，拒絕模型、現用／舊詞庫、sidecar 及其檔案身分別名，失敗保留原備份。

Guanyinma 詞庫的讀音編解碼經無資料庫／session 的 `guanyinma_reading_codec` C ABI，Windows 不再複製 Formosa 的 codec。編碼使用逗號分隔、同類後項覆蓋前項、拒絕空項，並保留既有非注音成分忽略規則；解碼保留 printable modulo 與忽略奇數尾 byte 的相容行為。格式錯誤回傳失敗，不套用詞庫修改。

## 建置

CMake 預設 `KEYKEY_ENABLE_GUANYINMA=ON`，需要 Python 3.11 以上與 `Source/Guanyinma/rust-toolchain.toml` 鎖定的 Rustup 工具鏈。x64 使用 `x86_64-pc-windows-msvc`，x86 使用 `i686-pc-windows-msvc`；建置兩者前需安裝相應 Rust target。原有 CMake presets 與產品版號來源維持不變。

`tools/build-windows-core.py` 只執行鎖定依賴的 Release build，使用 `+crt-static` 與 bundled SQLite。雙核心建置的 C++ 原核心和 Rust 共用這份 SQLite，C++ header 直接取自 Cargo.lock 解析到的 `libsqlite3-sys`，不使用舊版 bundled header，也不混用 WinSQLite 的 x86 stdcall ABI。原生 Debug 設定也使用 `/MT`，保持與 Rust／SQLite 的 CRT 一致；仍可產生原生偵錯資訊。Rust 分配的物件仍只經 C ABI 對應 close 釋放。靜態連結不另部署 Rust DLL。

`-DKEYKEY_ENABLE_GUANYINMA=OFF` 可建置原核心及 WinSQLite，設定頁的核心選擇停用。雙核心 build 另外產生 `guanyinma/Guanyinma-NOTICES.txt`，含完整 Rust、crate、來源／資料與 SQLite notices，兩個封裝入口會放入既有 Licenses 目錄。

## 局部驗證

以下於已載入 MSVC 的 Developer PowerShell，從 `Source/Loaders/Windows-TSF` 執行；建置目錄依實際 preset 調整：

```powershell
cmake --preset windows-x64
cmake --build out/build/x64-ninja --target KeyKeyGuanyinmaIntegrationTest KeyKeySettingsBackend KeyKeyTsfOutputBehaviorTest
ctest --test-dir out/build/x64-ninja -C Release --output-on-failure --no-tests=error `
  -R '^KeyKeyGuanyinma(Adapter|UserData|TsfHostEffects|SettingsControls)$'
```

這些是少量 FE 冒煙：四法建立／基本候選與送字、安全換核、UTF-16、獨立資料／封存、TSF 宿主拒絕後重試，以及真正 WPF 控制項／PInvoke 套用重開。使用隔離 profile，不註冊 TIP、不切換使用者系統輸入法，也不讀遷移 functional baseline。

讀音 codec 的行為與 C ABI 由核心無 UI 測試驗證；Windows 接線目前完成原始碼檢查，尚未執行 Windows 原生建置或 consumer 測試，不能由 macOS host 的其他 adapter 測試推定通過。

完整 Rust／C consumer／跨平台核心矩陣仍只由 `guanyinma-core.yml` 負責。Windows workflow 直接建置並連結核心，保留既有平台建置與發布結構。x64／x86 原生可執行檔通過不代表 Windows Search AppContainer、真實文字宿主、安裝升級或簽章／發布完成；這些層級仍須分別驗收。
