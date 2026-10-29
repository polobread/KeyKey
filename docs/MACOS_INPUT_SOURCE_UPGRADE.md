# macOS 安裝與升級流程

安裝流程統一為：**硬體檢查 → 升級安全準備 → 寫入新版 → 檢查舊詞庫行程 → 登出再登入**。
全新安裝、手動 PKG 升級與程式內更新皆要求重新登入，不要求重新開機。
首次安裝於重新登入後加入琦琦；升級保留原有項目，重新登入後選回，不移除重加。

## 安裝器與封裝

- Distribution 宣告 `hostArchitectures="arm64,x86_64"`，Apple Silicon 不需 Rosetta；Intel 能看到明確阻擋提示。payload／helper 仍只有 arm64。
- `preinstall` 在執行 helper 前重複硬體檢查，涵蓋 component package 直接安裝。
- 保留固定安裝位置 `/Library/Input Methods/chichi77 KeyKey.app`、簽章與公證流程。
- Distribution 的 `onConclusion="RequireLogout"` 明確要求重新登入；完成頁及更新器訊息採相同指引。

## 覆蓋前：只保留安全準備

固定安裝位置不存在時，直接略過舊版準備；不完整 bundle、普通檔案或失效符號連結仍走升級保護。
有 console 帳號且目標是開機磁碟時，用套件附帶的已簽章 helper 執行 `--prepare-upgrade`：

1. 查目前選取的來源；若是琦琦，切至現有已啟用的 ASCII 鍵盤並核對選取成功。
2. 對捕捉到且 executable path 符合固定安裝位置的琦琦行程，要求正常退出。
3. 以核心 PID、UID、啟動時間確認同一個行程已退出；每個行程最多 3 秒。不使用全域 kill 或強制退出。

無法讀取目前選取、切換失敗、不能確認舊行程退出時，在覆蓋前中止並保留舊 App。
不再讀取 enabled 狀態、不寫入跨階段狀態檔。原本的啟用設定由系統保留。
helper 複製到唯一的 root 擁有暫存目錄供 GUI 帳號執行，結束即清除。

## 覆蓋後：只處理仍持舊詞庫的行程

`postinstall` 以 `--finish-upgrade` 比較固定位置行程開啟詞庫的 device／inode 與安裝位置。
只有仍持有已替換詞庫的行程才正常退出；使用目前詞庫的行程保留。
這保留 macOS 在 preinstall 與覆蓋完成間重啟 IMK 時的保護。
無法判定或退出失敗只記錄日誌；檔案已完成安裝，使用者仍依統一流程重新登入。

不再執行 TIS 註冊、啟用恢復、獨立 snapshot 驗證或額外 GUI 修復提示。
不呼叫 disable、不改私有 HIToolbox 偏好，不自行選回琦琦。
兩個階段的 helper 都以 `launchctl asuser`、`sudo -H -u` 取得 console 帳號的 GUI session 與憑證，
再以 `env -u __CF_USER_TEXT_ENCODING` 清除繼承的管理員標記。helper 核對帳號未切換，整次限時 20 秒。
無 console 帳號或非開機磁碟時不操作目前登入者的輸入法，於登入目標系統後完成使用。

## 更新器

Sparkle 保留下載、驗章、管理員授權及安裝流程，安裝完成後也要求儲存工作、登出再登入。
原有組字延後更新、背景檢查排程與更新視窗置前行為不變。
一般 App 結束、登出與關機不交給更新器否決。

## 驗證

`bash Installer/test-input-sources.sh` 以假 TIS、測試自己的子行程及暫存詞庫檔，驗證硬體阻擋、
全新安裝略過準備、ASCII 切換、正常退出與 PID 身分、舊詞庫 descriptor，以及腳本失敗邊界。
不操作已安裝的 IMK 或使用者輸入法設定。

按 [VM 操作指南](MACOS_INSTALLER_VM_TESTING.md) 從快照 a／b 建立三個獨立工作副本，
以相同提交來源的同一份安裝包完成全新、手動升級、舊版程式內更新。
三條路徑皆正常登出再登入，記錄登入畫面、既有來源保留與實際中文組字／候選／選字／提交；
已安裝版本或 receipt 不能代替實打。升級不得藉移除重加通過驗收。
