琦琦輸入法 Windows 10／11 安裝說明
================================

1. 先把整個 ZIP 解壓縮，不要直接在 ZIP 裡執行檔案。
2. 把整個解壓縮資料夾複製到本機 C:\，例如 C:\KeyKeyInstaller。
3. 從本機資料夾雙擊 Install.cmd，並允許 Windows 的系統管理員權限提示。
4. 安裝程式以「繁體中文（台灣）」為主要語言，並支援「繁體中文（香港）」與「繁體中文（澳門）」；不會新增或變更 Windows 語言清單，也不會安裝語言套件。
5. 版本升級完成後，請依安裝提示登出 Windows 再登入，讓工作列載入新版設定頁；首次安裝若沒有立即出現，也請登出再登入。

請勿直接從網路磁碟、NAS 或 UNC 路徑執行安裝。UAC 提升權限後可能無法存取
原路徑，且安裝視窗可能立即關閉。若安裝失敗，請查看
%TEMP%\chichi77-keykey-install.log。

解除安裝：

- 到「設定 > 應用程式 > 已安裝的應用程式」移除「琦琦輸入法」；或
- 執行解壓縮資料夾裡的 Uninstall.cmd。

這是未簽署的家用測試版本。若檔案是從網路下載，Windows 可能顯示安全警告；
請只安裝由你信任的人提供的檔案。x64 套件同時包含 x64 與 x86 TSF DLL，支援
所有 32 位元應用程式；x86 ZIP 套件供 32 位元 Windows 使用。

-------------------------------------------------------------------------------

chichi77 KeyKey for Windows 10/11
==============================

1. Extract the entire ZIP. Do not run the installer from inside the ZIP.
2. Copy the entire extracted folder to a local C:\ path, for example
   C:\KeyKeyInstaller.
3. Run Install.cmd from that local folder and approve the administrator prompt.
4. The installer registers KeyKey primarily for Traditional Chinese (Taiwan), with Hong Kong and Macao support. It does not add or change Windows languages or install language packs.
5. After a version upgrade, follow the installer prompt to sign out and back in so the taskbar loads the new settings page. On a first install, sign out and back in if the input method does not appear immediately.

Do not install directly from a mapped network drive, NAS, or UNC path. The
source can become inaccessible after UAC elevation and the installer window
can close immediately. Failures are logged to
%TEMP%\chichi77-keykey-install.log.

Uninstall it from Settings > Apps > Installed apps, or run Uninstall.cmd from
the extracted package. This is an unsigned home-testing build. Install it only
when it came from someone you trust. The x64 package includes both x64 and x86
TSF DLLs for all 32-bit applications. The x86 ZIP is for 32-bit Windows.
