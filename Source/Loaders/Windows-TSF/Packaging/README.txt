琦琦輸入法 Windows 1.3.2 安裝與設定
================================

首次安裝：
1. 使用符合 Windows 系統類型的 ZIP（x64 或 x86），完整解壓縮到本機資料夾，
   例如 C:\KeyKeyInstaller。不要在 ZIP 預覽、網路磁碟或 NAS 內執行。
2. 連按兩下 Install.cmd，核對來源並允許 Windows 的系統管理員權限提示。
   安裝在 Program Files\chichi77 KeyKey\1.3.2-內容指紋，位置由程式管理。
3. 自行新增鍵盤：
   Windows 11：設定 > 時間與語言 > 語言與地區 > 繁體中文右側 … > 語言選項
               > 鍵盤 > 新增鍵盤 > 琦琦輸入法。
   Windows 10：設定 > 時間與語言 > 語言 > 繁體中文 > 選項
               > 鍵盤 > 新增鍵盤 > 琦琦輸入法。
   台灣、香港或澳門的繁體中文均可；沒有該語言時，由你自行新增所需語言。
   台港澳共用一個琦琦入口（登記於台灣）；其他語言可在清單其他語言區域尋找。
   找不到時，可自行新增繁體中文（台灣）再加入琦琦，不需改顯示語言。
   安裝程式不變更語言清單、顯示語言、預設輸入法，也不替你加入鍵盤。
4. 開啟記事本，按 Win + Space 選擇琦琦輸入法。顯示「英」時，按
   Ctrl + Space 切回中文「ㄅ」。找不到時先確認已手動加入，再登出、登入。

調整輸入設定：
從工作列琦琦選單開啟「輸入法設定…」。「注音」選熟悉的鍵盤配置；「一般」
調整候選窗方向、大小；「關聯詞庫」選詞庫；「自訂詞」新增詞、匯入或匯出資料。
按「套用」後回記事本試打。要改預設輸入法，可自行在 Windows 搜尋「進階鍵盤設定」。

升級與移除：
- 舊版三個同名項目是台灣、香港、澳門 profile，並非三份版本。新版只保留共用入口，
  移除舊香港／澳門入口。原先選用舊區域入口者，需自行在 Windows 設定新增及選用
  共用的「琦琦輸入法」；原先設為預設者也請重新選擇。個人資料保留。
  更新後請關閉 Windows 設定再重開；仍未刷新時，儲存工作後登出再登入。
- 使用新版 Install.cmd 直接升級，不必先執行舊解除安裝器。共用入口的既有選擇、個人資料
  保留；舊區域入口需改選共用入口。儲存工作後登出再登入。舊檔暫供既有程式使用，請勿自行移動或刪除。
- Windows 11：設定 > 應用程式 > 已安裝的應用程式 > chichi77 KeyKey > 解除安裝。
  Windows 10：設定 > 應用程式 > 應用程式與功能 > chichi77 KeyKey > 解除安裝。
  也可執行這份新版 ZIP 的 Uninstall.cmd。保留個人設定、自訂詞及學習資料。
- 若提示 3010，解除安裝已完成，使用中的產品檔案已排定重開機時刪除。
  儲存工作後重新開機即可，不需要再次解除安裝。正常移除會移除應用程式清單項目，
  只有失敗才保留重試入口。額外／修改過的檔案、根目錄的診斷與狀態記錄會保留。
  升級後請勿使用另存的舊 ZIP 或舊解除安裝 EXE。
- 安裝／移除失敗請記下錯誤碼並保留安裝包。一般建置與 GitHub Actions 預設關閉診斷；
  設定內開啟診斷後固定記錄 3 天，到期自動停止，有效期限內才寫
  Program Files\chichi77 KeyKey\Deployment.log。

未簽署 ZIP 僅供可信來源的測試，不要關閉安全防護。x64 包支援 x64／x86 程式，
x86 包供 32 位元 Windows。目前不支援 ARM64。歷代發布包的實際升級、移除與重裝
仍須逐一驗收，自訂或損壞的舊安裝可能需個別處理。
完整指南：https://github.com/polobread/KeyKey/blob/v1.3.2/WINDOWS_INSTALL.md

-------------------------------------------------------------------------------
chichi77 KeyKey 1.3.2 for Windows 10/11
=====================================

1. Extract the entire ZIP matching your Windows architecture to a local folder,
   for example C:\KeyKeyInstaller. Run Install.cmd and approve the administrator
   prompt after checking its source. Installation uses Program Files\chichi77
   KeyKey\1.3.2-<fingerprint>; do not move or delete managed folders.
2. Add the keyboard yourself:
   Windows 11: Settings > Time & language > Language & region > Traditional
               Chinese (...) > Language options > Keyboards > Add a keyboard.
   Windows 10: Settings > Time & language > Language > Traditional Chinese
               > Options > Keyboards > Add a keyboard.
   Choose KeyKey (琦琦輸入法) under Taiwan, Hong Kong or Macao Traditional Chinese.
   There is one selectable entry, using the Taiwan profile. For other languages,
   look in the other-language section of the keyboard picker. If unavailable,
   add Traditional Chinese (Taiwan), then KeyKey; no display-language change is needed.
   If needed, add your chosen language first. The installer does not change your
   languages or display language, and does not choose a keyboard or default for you.
   Upgrades retire the old regional entries as described below.
3. Open Notepad and select KeyKey with Win + Space. Ctrl + Space toggles Chinese
   and English. If missing, check that you added it, then sign out and back in.
4. Open Input Method Settings from KeyKey's taskbar menu. Choose your layout on
   Bopomofo, candidate direction/size on General, dictionaries on Associated
   Phrases, and personal words on User Phrases. Click Apply and test. To choose
   a default input method, use Windows Advanced keyboard settings.

Upgrade directly with the new Install.cmd. The shared entry selection and personal
data are preserved. Both old Hong Kong/Macao entries are removed after installation.
If you used either old entry, add and select the shared KeyKey entry in Settings;
choose it again as your default if desired. All regions now use one entry.
Reopen Settings to refresh. Rerun the package if the log reports cleanup failure.
Save your work, then sign out and back in. Old folders are kept
for running applications; do not delete them manually.

Uninstall using the CURRENT chichi77 KeyKey entry in Windows Installed apps
(Windows 10: Apps & features), or this new package's Uninstall.cmd. Do not run
saved old uninstallers after upgrading. Preferences, personal words and learning
are kept. Exit code 3010 means removal is complete and in-use product files are
queued for deletion at restart. Save your work and restart; no second uninstall
is needed. The app list entry is removed after all deletions are completed or
queued. Only failures keep a retry entry. Modified/extra files and root diagnostic
logs/state records are retained.

On errors, record the exit code and retain the package. Diagnostics default to off,
including GitHub Actions builds. Only an active three-day diagnostic session enabled in Settings
write Program Files\chichi77 KeyKey\Deployment.log. Do not disable security protection.
This unsigned ZIP is for trusted-source testing. The x64 package supports x64
and x86 applications; x86 is for 32-bit Windows. ARM64 is not supported. Each
historical release still needs device migration verification; damaged or custom
legacy installations may require assistance.
Full guide: https://github.com/polobread/KeyKey/blob/v1.3.2/WINDOWS_INSTALL.md
