# Guanyinma Linux Fcitx 5 接合

Linux 的同一套 Fcitx 5 frontend 可選 C++ 原核心或 Guanyinma Rust 核心。執行時預設固定為 **C++ 原核心**；原有輸入法識別字、產品名稱、平台版號與共用模型維持既有來源。Guanyinma 的候選與組句行為使用共用核心，平台事件、視窗、宿主效果、關聯詞及繁簡輸出由 Fcitx frontend 處理。

## 建置與選擇

建置開關 `KEYKEY_ENABLE_GUANYINMA` 預設 OFF，`engine-only` 仍可在沒有 Rust、JSON、字型開發套件時建置。雙核心可使用：

```sh
cd Source/Loaders/Linux-IME
cmake --preset linux-guanyinma
cmake --build --preset linux-guanyinma
```

除原有 Fcitx／SQLite／canberra 依賴外，雙核心需要 `Source/Guanyinma/rust-toolchain.toml` 鎖定的 Rustup 工具鏈、`Cargo.lock` 依賴、json-c 與 PangoFT2 開發套件。Linux／FreeBSD 使用 CMake 選定的系統 SQLite；不啟用 bundled SQLite。Rust staticlib 使用 PIC，連入既有 addon，完整 notices 安裝於 `share/doc/chichi77-keykey/Guanyinma-NOTICES.txt`。

`CARGO` 可指定 Cargo 路徑；已預備依賴時使用 `-DKEYKEY_GUANYINMA_OFFLINE=ON`。一般 CMake、`configure --enable-guanyinma` 與 Debian 的 `KEYKEY_ENABLE_GUANYINMA=ON` 可啟用雙核心建置。來源封裝的 vendor 選項與離線來源準備見 `ci/create-source-archive.sh`、`Source/Guanyinma/tools/prepare-unix-vendor.py`；鎖定工具鏈本身仍須事先安裝。建置腳本不重建模型、不執行完整 Rust 測試。

在 Fcitx 的琦琦輸入法設定中選「輸入核心」。設定檔 `conf/chichi77-keykey.conf` 的 `InputCore=Legacy/Guanyinma` 保存偏好；缺值、未知值皆使用 Legacy。不含 Rust 的建置無法啟用 Guanyinma，會顯示原因，不假裝切換成功。

## 狀態與生命週期

`FcitxState` 是穩定的每 context 代理，持有原 `Engine`／`InputContextState` 或 `GuanyinmaSession`。設定保存只改 requested core；組字、未完成讀音、核心候選、FE 關聯詞或待處理宿主效果尚未完成時，沿用原 backend，下一個安全的新事件才切換。候選回呼帶視圖 generation 與 context 生命週期檢查，舊頁或舊核心的 index 不會誤選新候選。

模式狀態仍由 FE 管理，切核心保留中英與全半形；英文半形維持原生按鍵 pass-through。Shift tap 仍沿用 300ms 的原生辨識；Shift release filter 不等於 accept，避免宿主卡住 Shift。Shift+Space 轉成語意寬度操作；Rust 路徑保留 raw Shift、CapsLock、NumLock 與真正 keypad 來源。

`GuanyinmaSession` 只透過正式 C ABI 操作 Rust，不實作替代 walker／排序。四法設定明確映射為 desktop profile；好打保留十／十一音節、九個數字候選鍵、Linux 原有進階設定及學習選擇。字表持久學習維持關閉。

新增的通用 `finish_composition` 語意操作可完成 Smart 未完成讀音、保留傳統注音反白候選，或清除未確認表格字碼；這些選擇由 FE 明確傳入，核心沒有 Linux 名稱分支。原 `finish` 契約維持不變。

一次 operation 的 commit／delete／return／discard 效果只交給原 Fcitx context 一次；重畫 snapshot 不會重送。Fcitx API 無應用接受結果，呼叫返回不代表應用已接受文字。focus-out 的 `ClientUnfocusCommit` 由客戶端提交過 preedit 時，只清理舊 session；reset 失敗則退役 session，不能讓舊文字在下一宿主重現。首次建立 Rust 失敗可在接受事件前保留原核心並顯示原因；已運作 session 的錯誤保留最後視圖、消耗事件及回報，不將該事件重播給另一核心。

## 候選、輸出及字型

快照的 Unicode scalar 游標轉成 Fcitx UTF-8 byte cursor；Smart preedit 點字再依 Rust segment 的文字／讀音跨度映射。核心完整候選與當頁候選分開，Fcitx 只呈現當頁九個，點擊使用 page-local index。

原生 PangoFT2／Fontconfig provider 不依賴視窗，於 session 建立時固定字型能力與快取；注音另合併既有 Big5-HKSCS 設定。透過 `guanyinma_session_open_with_candidate_filter`，在排序、分頁、前綴上限及 Smart graph 前過濾，不在 UI 再刪核心候選。FE 自有關聯詞沿用同一能力政策。系統字型判斷不能代替所有應用／panel 的實際顯示驗收。

Rust commit 已轉全半形，FE 不重做；FE raw 關聯詞／符號按同步寬度轉換一次。最終繁簡輸出各做一次，關聯詞查詢／學習仍用原始繁體文字。Password／Sensitive 欄位不提供關聯詞。

## 資料與命令

| 核心 | 私有資料庫 | override |
|---|---|---|
| C++ | `$XDG_DATA_HOME/chichi77-keykey/smart-mandarin-user.db` | `CHICHI77_KEYKEY_USER_DB` |
| Guanyinma | `$XDG_DATA_HOME/chichi77-keykey/guanyinma-user.db` | `CHICHI77_KEYKEY_GUANYINMA_USER_DB` |

XDG 未設定時使用 `~/.local/share`。共用安裝模型仍為唯讀 `smart-mandarin.db`，兩核心不混寫使用者資料，也不自動匯入舊檔。Rust 的詞庫命令使用相同 C ABI admin session，不直接改 Rust schema。

```sh
# 原命令固定操作 C++ 詞庫，不跟隨 GUI 偏好
keykey-smart-phrases list
keykey-smart-phrases --core guanyinma list
keykey-smart-phrases --core guanyinma add 琦琦星 'ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ'
keykey-smart-phrases --core guanyinma update 琦琦星 'ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ' 琦琦光 'ㄑㄧˊ ㄑㄧˊ ㄍㄨㄤ'
keykey-smart-phrases --core guanyinma reset-learning
keykey-smart-phrases --core guanyinma export backup.json
keykey-smart-phrases --core guanyinma import backup.json
keykey-smart-phrases --core guanyinma import-legacy /path/to/smart-mandarin-user.db
```

Smart reset 保留自訂詞與其他方法學習。完整 JSON 備份保留自訂詞、Smart 與字表學習，排除 generation／revision；驗證整份內容後原子匯入。匯出使用私有暫存檔及原子替換，不允許覆蓋模型、兩核心 DB／sidecar 或別名。顯式舊 DB 匯入唯讀來源，合併詞條、替換來源提供的 Smart 學習、保留其他方法；只保留最新 200 筆 override／Bigram query，不是全部舊學習的無損搬運。

## 聚焦驗證

```sh
ctest --test-dir out/build/guanyinma -R 'guanyinma|fcitx5_mode_keys' --output-on-failure
# 以下以實際 build／stage 目錄代入；只使用隔離 D-Bus／Xvfb，不安裝至 /usr
bash ci/run-dual-core-smoke.sh BUILD_DIR STAGE_DIR
```

新測試涵蓋真正 C ABI 的 adapter、FcitxState 的核心切換／效果／焦點，以及 CLI 的兩資料庫隔離、CRUD、JSON 與舊資料匯入、備份路徑保護。完整核心矩陣由 `guanyinma-core.yml` 負責；Linux workflow 只增加編譯連結與少量 FE smoke。遷移 functional baseline 不在日常 CTest／CI gate 內。

staged install、來源離線重建、Debian 生命週期、X11、GNOME Wayland／XWayland 及 FreeBSD 原生接合各自記錄；任何一項未執行都不能以另一項通過替代。正式平台支援與發布狀態仍以 README／安裝文件為準。
