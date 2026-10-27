# Guanyinma Linux／FreeBSD Fcitx 5 接合

Linux／FreeBSD 共用的 Fcitx 5 frontend 現在只使用 **Guanyinma（Rust）**。原 Legacy C++ 組句、排序、可寫學習實作及核心切換已移除；原有輸入法識別字、產品版號與正式共用模型維持不變。C++ 僅保留 Fcitx、原生字型、關聯詞、繁簡輸出及必要資料轉換接合。

## 建置

```sh
cd Source/Loaders/Linux-IME
# Bash：準備 rust-toolchain.toml 鎖定的工具鏈與 Cargo.lock 來源
source ci/prepare-guanyinma.sh
cmake --preset linux-release
cmake --build --preset linux-release
ctest --preset linux-release
```

必要依賴為 C++17、CMake、Python 3、鎖定 Rustup 工具鏈、系統 SQLite、json-c、PangoFT2／Fontconfig；Fcitx addon 另需 Fcitx 5 Core 與 libcanberra。圖形工具使用 Python GI／GTK 3。`engine-only` 是無 Fcitx／無視窗的同一 Rust adapter 測試，仍需要 Rust、JSON 和字型依賴。

`CARGO` 可指定已準備工具鏈的 Cargo；`-DKEYKEY_GUANYINMA_OFFLINE=ON` 使用已快取或 vendored 的鎖定來源。建置入口不提供核心選擇參數。來源包預設帶 checksummed Cargo vendor，工具鏈本身須另行準備。建置只驗證、複製正式模型，不自行 cooker，也不重跑完整核心矩陣。

FreeBSD 沿用 `/usr/local` prefix 與系統 SQLite、pkg-config、PangoFT2；ports 配方需同步 Rust／Cargo 來源、相依、notices 與 plist。本次沒有 FreeBSD 原生 runner，不能把 Ubuntu 的編譯或 X11 結果當作 FreeBSD 驗收。

## 偏好設定

設定參考 macOS／Windows 的共通輸入行為。Fcitx 原生設定頁最上方保留關於與檢查更新，其後依「一般、注音、倉頡、簡易、自訂詞、詞庫」分組；組內對應選項也參照 Windows 順序。顯示分組與排序不改變既有 INI 儲存路徑或偏好值；候選字窗的字型、縮放與色彩仍由 Fcitx UI／GNOME panel 管理。

輸入設定維持 Fcitx 原本的捲動長頁。「關於」與「檢查更新」另共用一個 GTK 視窗，各自使用一個頁籤；從任一入口開啟會選取同一視窗的對應頁。此資訊視窗不需讀取 Fcitx 設定結構。更新通知選項立即儲存，單純開啟頁籤不會檢查網路。

| 類別 | 可設定項目 |
|---|---|
| 一般 | 啟動中／英文、中文忽略 Caps Lock、數字鍵盤直接送字、候選字窗方向、中英切換快捷鍵、單按 Shift 開關、錯誤音效、繁簡輸出 |
| 注音 | 布局／好打或傳統模式、Big5-HKSCS 字集、傳統選字鍵；好打的空白開候選、游標前／後選字、選字鍵、10～20 音節組字長度、Esc 清句、選字後回句尾、Shift 字母強制大寫、Bigram 與學習選項 |
| 倉頡 | 滿碼處理、動態詞頻、即時候選、前綴候選、錯碼清除、標點樣式，以及選字鍵、最大字碼長度、空白首選／單頁送出、通配符等進階選項 |
| 簡易 | 即時候選、錯碼清除，以及滿碼處理、動態詞頻、標點樣式、選字鍵、最大字碼長度、空白首選／單頁送出、通配符等進階選項 |
| 自訂詞 | 使用自訂詞庫開關；圖形新增／修改／刪除、模型讀音建議、學習重設、完整 Guanyinma JSON 匯入／備份 |
| 詞庫 | `[AssociatedPhrases]` 分組中，小麥與 29 組分類詞庫的個別 Boolean 開關 |

好打保留 Linux 既有九個數字選字鍵為初始值，也可選桌面八鍵組合；設定、核心分頁、Fcitx 鍵標使用同一組鍵。組字長度預設十個完成音節，第十一個擠出完整詞；長度可改為 10～20。中文忽略 Caps Lock 預設關閉，英文模式保留大小寫功能。中英、全半形與快捷鍵的物理事件辨識仍由 frontend 處理。

`InputCore` 不再是可選設定；舊設定檔保存的 `Legacy`／`Guanyinma` 不會選回已移除的引擎。關聯詞設定只使用現行分組，不讀取或同步舊逗號格式。設定變更在組字、候選及當次宿主效果完成後才建立新 session，不為了套用偏好而丟棄或重播組字。

## 狀態、送字與字型

每個 Fcitx context 保存自己的 Rust session、模式與候選世代。舊候選回呼帶 context 生命週期與世代檢查，不會選到新頁面的同一 index。Unicode scalar 游標轉成 Fcitx UTF-8 byte cursor；組字點字依快照的文字／讀音跨度定位。

一次 operation 的 commit／delete／return／discard 效果只交給原 Fcitx context 一次，重畫 snapshot 不重送。Fcitx API 沒有應用接受回傳；宿主已自行提交 preedit 時只清理 session，失敗時不讓舊文字在下一宿主重現。Rust 初始化失敗明確顯示原因，不回退另一套演算法。

候選可顯示性由原生 PangoFT2／Fontconfig callback 在核心排序、分頁、前綴與 Smart graph 前過濾，注音可再限制 Big5-HKSCS；不在畫面顯示後刪候選。字型政策固定於 session，改設定時在安全邊界重建。Rust 產生的 commit 已完成全半形；FE 原生關聯詞／符號及最終繁簡輸出各轉一次。Password／Sensitive 欄位不提供關聯詞。

## 使用者資料與工具

Rust 私有資料庫固定為 `$XDG_DATA_HOME/chichi77-keykey/guanyinma-user.db`；未設定 XDG 時位於 `~/.local/share`。可用 `CHICHI77_KEYKEY_GUANYINMA_USER_DB` 覆寫。正式模型 `smart-mandarin.db` 維持唯讀。不再讀寫或匯入舊 Linux C++ 的 `smart-mandarin-user.db`；既有舊檔不自動刪除。

```sh
keykey-user-phrases
keykey-smart-phrases list
keykey-smart-phrases list --json
keykey-smart-phrases readings 琦琦
keykey-smart-phrases add 琦琦星 'ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ'
keykey-smart-phrases reset-learning
keykey-smart-phrases export backup.json
keykey-smart-phrases import backup.json
```

CLI 直接操作 Guanyinma，不提供核心選擇參數或舊 Linux C++ 資料相容命令。完整 JSON 備份保留自訂詞、Smart 與字表學習，排除 generation／revision；匯入先驗證整份再原子套用。匯出以私有暫存檔原子替換，不允許覆蓋模型、使用者 DB／sidecar 或別名。舊 Linux C++ 資料格式不在此工具的支援範圍；其他平台的匯入契約不受此 Linux 前端決定影響。

## 聚焦驗證

```sh
ctest --test-dir out/build/release -R 'guanyinma|fcitx5|user_phrases' --output-on-failure
# 隔離 D-Bus／Xvfb、GTK3／GTK4／Qt6；不修改個人設定或 /usr
bash ci/run-guanyinma-smoke.sh BUILD_DIR STAGE_DIR
```

Linux 測試聚焦正式 C ABI、設定映射、動態選字鍵與分頁、字型、生命週期／效果、CLI 與圖形詞庫工具。完整 Rust／C consumer／跨平台核心矩陣由 `guanyinma-core.yml` 負責；不把遷移 functional baseline 加入日常 CTest 或 CI gate。

原始碼、無視窗測試、staged addon、套件安裝、X11、GNOME Wayland／XWayland 與 FreeBSD 原生驗證各自記錄。任一層通過不能取代其餘層的宿主證據；正式發布與支援狀態仍以安裝指南與 Release 為準。
