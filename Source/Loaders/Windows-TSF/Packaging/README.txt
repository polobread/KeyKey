琦琦輸入法 Windows 11 安裝說明
================================

1. 先把整個 ZIP 解壓縮，不要直接在 ZIP 裡執行檔案。
2. 把整個解壓縮資料夾複製到本機 C:\，例如 C:\KeyKeyInstaller。
3. 從本機資料夾雙擊 Install.cmd，並允許 Windows 的系統管理員權限提示。
4. 安裝程式會自動將「琦琦輸入法」加入 Win+Space 清單。
5. 若沒有立即出現，請登出再登入。

請勿直接從網路磁碟、NAS 或 UNC 路徑執行安裝。UAC 提升權限後可能無法存取
原路徑，且安裝視窗可能立即關閉。若安裝失敗，請查看
%TEMP%\chichi77-keykey-install.log。

解除安裝：

- 到「設定 > 應用程式 > 已安裝的應用程式」移除「琦琦輸入法」；或
- 執行解壓縮資料夾裡的 Uninstall.cmd。

這是未簽署的家用測試版本。若檔案是從網路下載，Windows 可能顯示安全警告；
請只安裝由你信任的人提供的檔案。x64 套件同時包含 x64 與 x86 TSF DLL，支援
32-bit Office；目前套件只適用於 x64 Windows 11，不含 ARM64。

-------------------------------------------------------------------------------

chichi77 KeyKey for Windows 11
==============================

1. Extract the entire ZIP. Do not run the installer from inside the ZIP.
2. Copy the entire extracted folder to a local C:\ path, for example
   C:\KeyKeyInstaller.
3. Run Install.cmd from that local folder and approve the administrator prompt.
4. The installer automatically adds chichi77 KeyKey to the Win+Space list.
5. Sign out and back in if it does not appear immediately.

Do not install directly from a mapped network drive, NAS, or UNC path. The
source can become inaccessible after UAC elevation and the installer window
can close immediately. Failures are logged to
%TEMP%\chichi77-keykey-install.log.

Uninstall it from Settings > Apps > Installed apps, or run Uninstall.cmd from
the extracted package. This is an unsigned home-testing build. Install it only
when it came from someone you trust. The x64 package includes both x64 and x86
TSF DLLs so it also works in 32-bit Office. It requires x64 Windows 11 and does
not include ARM64.
