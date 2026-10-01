# Windows 1.3.1 安裝與舊版遷移規劃

本文件供 Windows 安裝流程開發與驗收使用。2026-10-01 已更新 `origin/master` 與 `origin/v1.3.1`，以 `v1.3.1` 的 `5a2bb9c` 為修正前稽核基準，檢查 NSIS EXE、ZIP PowerShell 腳本、TSF 註冊實作及歷史 tag。共用維護核心與兩種入口已依下述設計修改；驗證記錄在文末。**原始碼修正與建置測試不能代替歷代實際安裝包的 VM／宿主驗收。**

結論：保留 EXE 與 ZIP 兩種入口，但共用一套安裝、遷移與解除安裝核心。升級採完整版本目錄並存，再切換註冊；不要先解除舊版註冊。由新版接管已辨識的舊安裝與清理責任，解除安裝只移除屬於本產品的檔案與註冊，保留使用者資料。

使用者指定的安裝契約：安裝只把琦琦輸入法登記為 Windows 可供選擇的輸入法，是否加入個人鍵盤清單及選用，由使用者在 Windows 設定中決定。新安裝只提供一個共用入口且不預設啟用。依使用者後續確認，台港澳共用此入口；升級保留其加入／停用狀態，成功後移除兩個舊區域入口。原先選用舊香港／澳門者需手動改選共用入口，包括原先的預設選擇。個人資料保留。

## 修正前稽核與風險

以下表格記錄 `5a2bb9c` 的修正前行為，不是修改後現況。範圍為 `Source/Loaders/Windows-TSF`，表內路徑以該目錄為基準。P1 為應阻擋發布的資料刪除或安裝失效風險；P2 為需補齊的可靠性與部署行為。

| 優先度 | 位置 | 已確認的行為與影響 |
| --- | --- | --- |
| P1 | `ComServer.cpp::RegisterProfile` 的 `bEnabledByDefault` | 目前台灣 profile 傳入 TRUE，香港／澳門傳入 FALSE。雖然不等同強設預設輸入法，但不符合本次「由使用者在 Windows 設定自行加入」的契約，須改為新安裝全部不預設啟用；升級不可順帶停用使用者已加入的項目。 |
| P1 | `Packaging/Uninstall.ps1` 的安裝路徑讀取及尾段 | 信任登錄的 `InstallLocation`，先刪解除安裝項目，再 `Remove-Item -Recurse -Force` 刪整個目錄。沒有產品所有權、路徑邊界與 junction 檢查。可能刪掉放入該目錄的其他檔案；遇到使用中的 DLL 又可能留下半移除狀態與消失的移除入口。 |
| P1 | `Packaging/Install.ps1` 的 `$oldRegistration` 迴圈及複製段 | ZIP 先 `/u`，再覆寫固定根目錄。正在使用的 DLL 會擋住更新，失敗時沒有回復；暫時移除 profile 也會打斷 Windows 的輸入法狀態。過去的系統通知紀錄是歷史證據，本輪未重現。 |
| P1 | ZIP 與 NSIS 共用 `chichi77KeyKey` 解除安裝項目 | ZIP 不依 `VersionLocation` 遷移，也不清理或接管 NSIS 的相關欄位；NSIS 又保留舊根目錄腳本。EXE → ZIP 後可能留下舊 `VersionLocation`、`QuietUninstallString` 及捷徑；`TextService.cpp` 仍優先用該位置開設定，造成新舊版本混用。 |
| P1 | `Packaging/Store-Installer.nsi` 的 x86 註冊失敗分支；`ComServer.cpp` | x86 註冊失敗會 `/u` 新 x64 DLL，卻不恢復舊 x64 路徑。DLL 自身註冊 profile 失敗也會移除先前成功的共用 profile／COM 註冊。相同 CLSID 與 GUID 下，這不是完整回復，可能破壞原本可用的安裝。 |
| P1 | NSIS `Uninstall`；`ComServer.cpp::DllUnregisterServer` | NSIS 不驗證自己是否仍是目前安裝，就刪共用解除安裝鍵並以自身版本 DLL 解除註冊。DLL 也不檢查 COM 目前是否已指向新版。保留或複製出的舊解除安裝器可能移除新版註冊。 |
| P2 | NSIS `.onInit` 與目錄頁 | 相同安裝的判定在目錄頁前完成，使用者之後仍能改目錄。只比登錄指紋與檔案存在，沒有重驗內容；已有同版不同內容的非目前目錄也可能進入覆寫流程。部分檔案缺失時會嘗試覆寫其餘已載入檔案。 |
| P2 | NSIS `RemoveKnownPayload` 與 `Uninstall` | 升級保留舊 payload 是必要措施，但最後移除只處理此次版本。歷代目錄及根目錄 ZIP 檔案沒有完整清理清單；`Databases`、`LICENSES` 仍整目錄遞迴刪除，且版本中的 `README.md` 不在刪除清單。 |
| P2 | ZIP 的 PowerShell／regsvr32 選擇 | 依執行程序取得 Program Files 與登錄 view，沒有在 x64 Windows 明確固定原生 view。從 32 位元父程序啟動時可能寫到另一位置或以錯誤架構註冊。`Register-Tip.ps1` 對 x86 PE 一律選 SysWOW64，也需補上 32 位元 Windows 路徑。 |
| P2 | NSIS 完成頁 `LaunchKeyKeySettings` | 從已提升權限的安裝器直接啟動設定。使用另一個管理員帳號通過 UAC 時，可能編輯管理員的偏好而非原使用者的偏好。 |
| P2 | 兩種安裝流程 | 缺少共同互斥鎖、持久化進度與中斷恢復。登錄／捷徑／解除安裝器寫入失敗沒有一致處理；ZIP 也沒有降版拒絕規則。 |
| Store 發布缺口 | `Package-Store-Windows.ps1` 與 `WriteUninstaller` | 打包流程簽四個 payload PE 與外層安裝 EXE，但未見生成的 `Uninstall.exe` 簽章步驟。必須檢查實際產物並補簽，不能由外層簽章推定內層也有簽章。 |

目前兩種 TSF 安裝器未見強制終止 Explorer／ctfmon／使用者 App、停用 Defender、取得整個 Program Files 所有權或強制重新開機。UAC 提升、註冊自己的 COM、對產品檔案授予 ALL APPLICATION PACKAGES 唯讀／執行權，本身並非不當行為。現況問題主要是變更邊界與失敗處理，不應籠統稱作 Windows 禁止使用 NSIS 或 PowerShell。

## 平台規範依據

Microsoft 要求自製 IME 透過 TSF `RegisterProfile` 註冊，不直接拼寫 profile 登錄；不建議直接改登錄強設預設鍵盤。詞庫應可被 AppContainer 讀取，Program Files 是文件列出的適當位置。現行 `ComServer.cpp` 使用 TSF API 的方向正確，直接寫自身 COM 類別與應用程式解除安裝資訊，不等同直接竄改輸入法 profile。[Microsoft IME requirements](https://learn.microsoft.com/en-us/windows/apps/develop/input/input-method-editor-requirements)

`bEnabledByDefault` 是 profile 的預設啟用值，不等同指定使用者預設輸入法。升級時仍須實測共用入口的加入／停用狀態，以及舊香港／澳門使用者手動改選共用入口的流程。[RegisterProfile](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfinputprocessorprofilemgr-registerprofile)

Store 的 EXE／MSI 路徑要求離線安裝、靜默安裝及所有 PE 簽章，且已提交的版本下載 URL 對應內容不可變更。這些是 Store 發布條件；ZIP 發布不因此自動違規，也不能宣稱 ZIP 可作為該 Store 安裝入口。[Store package requirements](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/app-package-requirements)

NSIS 提供 `!uninstfinalize` 或先產生、簽署解除安裝器再封裝的方式。[NSIS uninstaller signing](https://nsis.sourceforge.io/Signing_an_Uninstaller_externally)

使用中檔案可透過 `MoveFileExW(..., NULL, MOVEFILE_DELAY_UNTIL_REBOOT)` 排定刪除；API 成功只代表排程成功，不代表重開機後一定刪除。排程以路徑為單位，因此後續安裝不能重用仍待刪除的路徑。[MoveFileExW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw)

以上是安裝範圍的 API 與發布要求檢查，不是完整 Store 認證、授權審查或所有 IME 功能認證。

## 舊版涵蓋範圍

已以明確的 `refs/tags/...` 核對腳本，避免 `v1.3.0` 分支與 tag 同名造成誤判。tag 有原始碼不代表已取得當時發布的安裝檔，尚須建立實際 EXE／ZIP 的 SHA-256 清冊。

| 舊版來源 | 原始碼特徵 | 新版遷移策略 |
| --- | --- | --- |
| v1.2 ZIP | 固定根目錄、單一 `KeyKeyTsf.dll`，安裝與移除會呼叫 `Set-WinUserLanguageList` | 辨識 PE 架構、舊 GUID 與安裝路徑；以新版接管，不執行舊腳本。 |
| v1.2.1、v1.2.3～v1.2.9 ZIP | 所列 tag 的 Install／Uninstall 腳本各自相同；改為架構命名 DLL，仍會重寫語言清單 | 同上；不要為回復舊版曾做的動作而刪除語言，現有語言可能已是使用者主動保留。 |
| v1.2.3～v1.2.6 NSIS | 相同 NSIS blob；版本目錄，升級先解除舊註冊並清除舊 payload | 接管其登錄與目錄，不呼叫原解除安裝 EXE。 |
| v1.2.7～v1.2.9 NSIS | 另一組相同 NSIS blob；仍有先解除註冊及舊 payload 清除 | 同上；另辨識可能尚未執行的延後刪除。 |
| v1.3.0 ZIP | 不再重寫語言清單，但仍先 `/u`、覆寫根目錄及遞迴移除 | 轉為版本目錄與共同解除安裝核心。 |
| v1.3.0 NSIS 與本機 test 包 | 升級直接重新註冊、保留舊 payload；正式版號目錄或 `1.3.0-test-指紋` | 匯入目前版本及可信的歷代 payload 清單；保留舊行程所需整套檔案。 |
| v1.2.2、v1.2.10 或其他未見 tag 的包 | 本次本地 tag 清單無對應項目；不能僅依文件版號推定 Windows 發布 | 發布前查 Release／封存產物；缺少產物的版本標示未驗收。未知內容提供診斷，不猜測刪除。 |
| Yahoo 舊 IMM／MSI | `Source/Distributions/Takao/Installer-Windows` 的 WiX 是另一產品與安裝技術 | 以實際 MSI ProductCode／UpgradeCode 識別，保留原 Windows Installer 維護途徑；不得拿 TSF GUID 或目錄名稱當作可刪除的證據。 |

修正前的本機唯讀查詢顯示：HKLM 64 位元解除安裝項目為 `1.3.0`，`VersionLocation` 是 `C:\Program Files\chichi77 KeyKey\1.3.0-test-49cb75705c0e`，32／64 位元 COM view 分別指向其 x86／x64 DLL。這只證明登錄指向，不證明所有既有程序已載入該 DLL。此為修正前盤點；使用者後續自行安裝及移除測試包的現況另記於文末。

## 共用安裝設計

已新增 self-contained .NET 10 `KeyKeyDeployment` 安裝維護工具與可測試共用核心，沿用既有設定程式的 .NET 建置工具鏈；使用者不需另裝 runtime。TSF 狀態由新版 native DLL 的受限 API 查詢／回復，x64 包另附 x86 bridge 處理 32 位元 view。NSIS 負責 UI／封裝，ZIP 的 CMD／PowerShell 只啟動同一核心與呈現結果。這是本專案設計選擇，不是 Microsoft 強制要求使用特定 installer framework。

保留同一產品 CLSID 與原台灣 profile GUID，作為台港澳唯一共用入口。香港與澳門的兩個舊獨立 GUID 在主安裝成功後透過 TSF API 移除，不保留另兩個舊地區選項。原先選用舊區域入口者依文件手動加入及選用共用入口。不加入簡體中文、不改系統語言順序、不強設預設輸入法。保留 x64 包的 x64／x86 TSF 支援，x86 包只用於 32 位元 Windows；ARM64 在有正式產物與驗收前明確拒絕，不靠 DLL 檔名猜測支援。

### 由使用者在 Windows 設定加入

必要的 COM／TSF 註冊仍要保留，否則 Windows 設定無法列出此輸入法。註冊與替使用者加入鍵盤清單是不同動作，兩種安裝入口都須遵守以下規則：

- 全新台灣 profile 使用 `RegisterProfile(bEnabledByDefault=FALSE, flags=0)`。此 Windows 實測接受 `TF_RP_HIDDENINSETTINGUI` 卻未持久化隱藏狀態，所以不依賴該旗標，也不直接改寫輸入法登錄。主安裝 commit 後才透過 TSF API 移除兩個舊港澳 profile，逐 view 驗證只剩共用入口與所需 categories。共用入口的 GUID、圖示、machine default-enable 與使用者啟用值保留，不再掃描其他帳號 hive。清理失敗留記錄供重跑，不撤銷已完成的新安裝。
- 不呼叫 `InstallLayoutOrTip` 自動加入，不呼叫啟用／切換／設預設的 API 替使用者作選擇，也不呼叫 `Set-WinUserLanguageList` 或直接改使用者鍵盤清單登錄。
- 升級先辨識既有 profile，再更新其註冊位置與必要中繼資料；保留共用入口原有的啟用狀態，不重新加入使用者曾移除的琦琦鍵盤。兩個舊區域入口於 commit 後退休；文件明示原先使用它們的帳號須手動改選共用入口，不偷偷重寫其鍵盤清單或預設。此行為需跨帳號實測，不從 `FALSE` 參數推定已達成。
- 新安裝完成頁提供文字步驟：「Windows 設定 → 時間與語言 → 語言與地區 → 繁體中文的語言選項 → 新增鍵盤 → 琦琦輸入法」。Windows 10 的頁面名稱另行核對。若提供開啟設定按鈕，必須由使用者點選，且開啟原使用者的設定；不自動彈出或替其操作。沒有相應語言時由使用者自行決定是否新增。
- 靜默安裝只完成系統層登記，不開設定、不替執行安裝的管理員或其他使用者加入鍵盤。升級提示登出後載入新版；已加入共用入口者不必重加，舊區域入口使用者則須手動改選。

這是本產品採用的較保守使用者選擇契約；不能將「不預設啟用」描述成 Microsoft 對所有 IME 的強制規定。

共用核心的最低契約：

| 操作 | 行為 |
| --- | --- |
| `inspect` | 唯讀列出兩個 COM view、解除安裝項目、版本／來源、檔案清單、待刪除與異常；不自動修復。 |
| `install` | 執行前置檢查、獨立 staging、驗證、註冊切換、提交紀錄與錯誤回復。可接管已知舊安裝。 |
| `repair` | 同版內容損坏時以新實體目錄修復及重新註冊，不覆寫已載入 DLL。 |
| `uninstall` | 從目前安裝紀錄驗證所有權，再解除本產品註冊、按清單移除；舊安裝器不得解除新版。 |
| `cleanup` | 清除已退休且確定可清理的產品 payload；不再對歷代 DLL 逐一 `/u`。 |

HKLM 解除安裝項維持單一 `chichi77KeyKey`，x64 Windows 明確使用 64 位元 view；兩種入口都寫完整且一致的 DisplayVersion、InstallLocation、VersionLocation、DisplayIcon、UninstallString、QuietUninstallString、NoModify／NoRepair。核心的安裝紀錄另存 `SchemaVersion`、`InstallationId`、架構、目前／退休 payload、逐檔雜湊、來源、待清理狀態與交易進度。紀錄放在管理員可寫的產品專用位置，不信任使用者可改寫的 JSON。

依使用者後續要求，所有新目錄統一用 `1.3.1-內容指紋`，不含 `test`。同版路徑已存在、損壞或排定重開機刪除時，採 `1.3.1-新實例 ID`，不含 `repair`，不重用危險路徑。仍辨識舊 `1.3.x-test-指紋` 和單純版號目錄供遷移；版本排序只用產品版號。

## 安裝與升級順序

1. 取得全機共同互斥鎖；檢查 Windows／原生架構、權限、磁碟空間、包清單與來源。以明確登錄 view 和原生系統工具路徑運作，不依父程序位元數決定。
2. 讀取目前 ARP（已安裝應用程式）資訊、32／64 位元 COM 路徑、既有 profiles 與產品紀錄。路徑或版本矛盾時留下診斷並停止切換；不得執行任意登錄字串裡的舊 EXE／DLL。
3. 驗證安裝目錄為受保護的本機產品專用位置。拒絕磁碟根、Windows／Program Files 本身、使用者資料目錄、UNC、junction／symlink 跳出與不安全 ACL。沿路逐段檢查，不能只做字串前綴比較；舊自訂目錄若無法證明安全，保留舊檔並遷到受保護的新根目錄。
4. 複製整套 payload 到同磁碟的新目錄，驗證 PE 架構、逐檔 SHA-256、正式簽章及共用 DB manifest；授予必要唯讀權，拒絕 Users／Everyone 寫入可被提升程序載入的檔案。先準備好可用的維護工具，再開始改註冊。
5. 建立持久化交易紀錄，保存兩個 COM view 與產品欄位的原值、可用舊 payload 及 profile 狀態。記錄每個步驟，以便斷電後重跑可恢復。
6. 安裝完整新版後才重新註冊 x64／x86 COM 與 TSF。升級不先 `/u`。將 `ComServer.cpp` 的破壞式失敗清理改成可辨識既有狀態的回復；註冊結果與查詢後置條件都通過，才更新目前安裝紀錄、解除安裝入口及捷徑。
7. 任一步失敗，恢復已變更的產品欄位與兩個 COM view；透過 TSF API 恢復已存在的 profiles，不直接重寫整份使用者語言登錄。新裝只撤銷本交易新增內容；升級不能把原本存在的 GUID 當作新增項移除。舊 payload 缺失時在切換前中止，進入明確修復途徑。回復也失敗時保留維護入口、紀錄及非零狀態，不顯示成功。
8. 提交後清理兩個舊區域入口，再保留舊 payload 的 DLL、設定程式及 DB 整套檔案，讓既有程序繼續使用。提示使用者自行登出再登入；不強殺程序，不自動登出或重開機。完成頁預設不從提升程序啟動設定；需啟動時由原使用者、未提升的程序完成，無法取得原 token 時提供捷徑。

同版同內容重跑須檢查 payload 雜湊、兩個 COM view 及維護入口；全數一致才回報已安裝。較舊版預設拒絕。完整內容不同的正式包不悄悄覆寫相同版號；未簽署測試包按不同指紋隔離。新版 NSIS 不提供目錄頁，固定受保護 Program Files 專用根目錄。舊自訂安裝不符合安全邊界時停止自動遷移，須個別診斷，不能宣稱已完成搬移。

## 解除安裝與舊版接管

目前版本的解除安裝核心先確認 `InstallationId`、目前 COM 路徑和已知產品身分。不是目前版本的入口只可提示新版維護入口，或清除自己已退休且可驗證的檔案；不得刪新版共用註冊、ARP 或捷徑。新版 DLL 的 `DllUnregisterServer` 也要檢查其所屬 COM view 的路徑；同時回傳 TSF／登錄失敗，不能忽略失敗後固定回報 S_OK。

對已發布的舊二進位檔，無法靠新版加入檢查就保證其安全。遷移時要接管受管理目錄內可辨識的舊 `Uninstall.ps1`／`Uninstall.exe`，以安全相容入口取代或停用；不要修改仍提供輸入功能的舊 DLL／DB。新維護工具應有獨立穩定位置，取代入口失敗時要保留明確未完成狀態。使用者保存在別處的舊 ZIP 或解除安裝 EXE 不受控，文件須說明改用目前「已安裝的應用程式」入口；不能承諾任意舊執行檔在新版安裝後都可放心執行。

### 一次解除安裝的完成契約

- 區分目前安裝（`Current`）、註冊移除中（`Removing`）、已解除註冊但清理尚未完成，以及所有產品檔案已刪除或排程完成（`RemovalQueued`）。新欄位預設 false，能讀取前次測試包留下的狀態。
- 不先刪除 ARP。所有清冊內、雜湊相符的 payload 與 maintenance 檔案都完成刪除或 Windows 重開機刪除排程後，寫入完成狀態，才移除 ARP。正常 3010 不留下需要再按一次解除安裝的項目。
- 執行中的 EXE 與 DLL 可能回傳 access denied。只對已驗證的產品檔案安排延後刪除；排程失敗保持非零與可重試狀態，不修改 ACL 或強制終止程序。維護程式正常退出，Windows 於同一次重開機刪除它，不另設常駐服務或啟動工作。
- 版本子目錄只在空白時立即刪除，或所有剩餘子項均已排程後，依子目錄到父目錄順序排程。產品根目錄、狀態與診斷記錄不加入重開機刪除，避免新安裝重用根目錄時遭到舊排程影響。未知／變更檔案保留。
- 清理失敗時將 ARP 指向仍可驗證的維護工具並標示「解除安裝未完成，請重試」。已排程但未重開機仍可重裝；新版 payload 與維護 EXE 都使用未排程的新路徑。
- 以失敗注入、真正 Windows image section 占用、跨程序 STA + DLL 卸載／重載測試驗證；fake backend 的重開機模擬與真正 VM 重開機分開記錄。

解除安裝順序：

1. 取得同一互斥鎖，驗證身分、路徑及檔案清單；保留所有使用者的 plist、自訂詞及學習 DB。不要枚舉其他帳號並刪資料。
2. 只解除目前產品所擁有的 TSF profiles、categories 與兩個 COM view，驗證結果；不以歷代 DLL 反覆 `/u`。部分失敗保留可重試入口，不能先刪 ARP。
3. 每個 payload 依已驗證的 manifest 逐檔刪除，只移除空目錄。舊版沒有 manifest 時，以受審查的舊包清單及產品身分建立遷移清冊；不以「位於 KeyKey 資料夾」推定整棵樹可刪。未知、已變更或額外放入的檔案保留並列報。
4. 若仍有程序使用某 payload，保留它的伴隨 DB／設定直到該實例可整套退休。可利用 Restart Manager 查詢占用，但不自動關閉程序。無法完整確認其他登入 session 的占用時，保守留待重開機清理。
5. 需要延後移除時只為已驗證的產品檔案使用 Windows 延後刪除 API，保留清理清冊與重試能力；不改寫或清空整份系統 PendingFileRenameOperations。回報「已解除註冊，重新開機後完成檔案移除」，不要稱作已全數移除。
6. 解除註冊、payload 與 maintenance 刪除／排程全部成功後，寫入 `RemovalQueued=true` 並移除 ARP，回報 0 或 3010。正常重開機後不要求再次解除安裝；只有操作失敗才保留可驗證的重試入口。根目錄狀態與日誌保留，供後續安裝判定；不把排程成功當作已經重開機或檔案已不存在。未重開機即重裝必須避開所有待刪路徑。

既有 Yahoo MSI 僅提供已確認身分的原生維護入口，不掃描刪除 System32、IME 機碼或 Yahoo 目錄。若要支援其自動移除，需另建實際 MSI 產物與 VM 測試；這與 TSF 1.2 系列的遷移不可混為一談。

## 實作拆分與發布門檻

| 階段 | 修改範圍 | 完成條件 |
| --- | --- | --- |
| 1 | 新共用 deployment 核心、狀態紀錄及測試 | 支援唯讀盤點、嚴格路徑驗證、所有權、互斥、檔案清單及可注入失敗的回復；先用暫存目錄與假的系統介面測試。 |
| 2 | `ComServer.cpp`、`Register-Tip.ps1` | 既有註冊失敗不被破壞，解除註冊有所有權與 HRESULT 檢查；Win10 x86、Win10／11 x64 的 view／工具選擇正確。 |
| 3 | `Packaging/Install.ps1`、`Uninstall.ps1`、CMD、NSIS | 兩入口都改用共同核心；舊格式接管、版本並存、修復、降版阻擋、權限及結果語意一致。 |
| 4 | 兩份 Package 腳本、CMake／CI | 包含清單與維護工具，簽署並驗證所有實際 PE（含解除安裝器），驗證最終簽章後 payload 雜湊；加入安裝整合測試。 |
| 5 | `WINDOWS_INSTALL.md`、frontend README、CHANGELOG | 只在相應測試通過後寫「已修正」；公布實測舊版、架構、重開機條件與仍未涵蓋的情況。 |

共同結果至少區分成功、需要重新開機、使用者取消、另一安裝進行中、不支援架構、降版拒絕、失敗且已回復、失敗且需修復。可採 0／3010／1602／1618／1633／1638 等部署慣例並文件化，其餘失敗碼保持非零；兩種入口必須傳遞相同結果。這是產品契約，不能把 NSIS 預設輸出當作已實作此契約。

## 驗收矩陣

以下是發布前的實機／VM 矩陣，仍待執行；文末另外記錄本輪程式碼、建置與隔離測試證據。不得將單元測試通過填成實機案例通過。

| 類型 | 必跑情境 | 檢查結果 |
| --- | --- | --- |
| 平台與權限 | Win10 x86、Win10 x64、Win11 x64；管理員與標準帳號輸入另一管理員認證；32 位元父程序啟動 | 正確系統 view、DLL 架構與產品目錄；不寫錯帳號的偏好；取消 UAC 無部分安裝。 |
| 每個實際舊包 | 所有取得的 1.2 系列與 1.3.0 正式／test 包 | 各跑直接升級，以及由新版安全維護核心移除舊版後再新裝；記錄產物 SHA-256。不能只按腳本分組就宣稱所有發布包均通過。 |
| 入口互換 | ZIP → ZIP、ZIP → EXE、EXE → ZIP、EXE → EXE | 一個正確 ARP、兩個 COM view 指向同一新 payload、設定入口一致；移除後不留有效產品註冊。 |
| 檔案占用 | Explorer、x64 宿主、x86 宿主、設定頁、另一登入 session 保持開啟 | 不強殺、不丟未存文字，舊 DB／設定可用；登出後新程序載入新 DLL。 |
| 重跑與修復 | 同包重跑、同版異內容、DLL／DB／uninstaller 缺失、COM 路徑被改、降版 | 不覆寫占用檔案；僅完整一致才報已安裝，故障可修復、降版被阻擋。 |
| 失敗注入 | 複製途中、磁碟滿、x64 成功後 x86 失敗、profile／category 失敗、ARP／捷徑寫入失敗、回復失敗、程序被中止 | 舊版仍可用或有明確可恢復狀態；不假成功、不丟維護入口。 |
| 路徑防護 | 自訂根目錄、空字串、`..`、同名前綴兄弟目錄、UNC、junction、改寫過的 manifest、未知額外檔案 | 拒絕越界操作；其他檔案不變；不載入未驗證的提升權限 DLL。 |
| 舊移除入口 | 升級後執行受管理的舊入口；保留在外部的舊 ZIP／EXE 作負面案例 | 接管的入口不破壞新版；外部舊二進位風險明列，修復途徑可用，不宣稱無法達成的保證。 |
| 移除後重裝 | 占用時移除，未重開機立即重裝，再重開機 | 新 payload／維護工具不被舊延後刪除移除；舊檔可清理，使用者 DB／plist 保留。 |
| 語言與資料 | 安裝前後語言清單、預設輸入法、台港澳啟用狀態；舊 plist 與自訂詞 | 不增加或刪除語言、不強改預設、不清除設定或學習；升級後設定與資料可用。 |
| 使用者自行加入 | 全新帳號、已有繁中帳號、沒有繁中帳號；GUI 與靜默安裝；安裝後新建帳號 | 安裝後琦琦可在適用語言的新增鍵盤清單找到，但未自動成為已加入或目前使用的鍵盤；使用者手動加入後可正常輸入及移除。 |
| 升級入口遷移 | 已加入台灣／香港／澳門、已移除琦琦、其他輸入法為預設；多帳號 | 共用入口既有選擇保留、不重加已移除項目；舊港澳定義移除，原使用者可依文件手動加入及選用共用入口。安裝器不自行重寫語言清單或設預設，資料保留；不能只驗證執行 UAC 的帳號。 |
| 正式產物 | EXE／ZIP 實際解包清單、全部 PE 簽章、離線、NSIS `/S` 及靜默移除、回傳碼 | Store 候選包滿足簽章／靜默門檻；測試未簽包清楚標示，不當正式驗收。 |

VM 測試保留安裝前後 registry／檔案差異、實際載入模組路徑及 LanguageComponentsInstaller 相關事件。每次失敗測試由乾淨快照開始。引擎 CTest、安裝核心單元測試、安裝包編譯與宿主實測分開記錄；不能互相代替。

## 2026-10-01 實作與驗證記錄

已修改共用維護核心、CMake／CI、兩種包裝入口、native 註冊與查詢、簽署清單，並同步更新 `WINDOWS_INSTALL.md`、`BUILDING.md`、frontend README、ZIP 內中英說明及 CHANGELOG。

核心使用受保護的 JSON 狀態與交易紀錄。相容移除入口在搬移／寫入前先記錄所有權，避免中斷後遺失清理清冊；同包重跑不重複製造備份。若根目錄維護工具已排定延後刪除，改用新的實體檔名，避免重新安裝後被舊排程刪掉。已知舊 TSF 安裝可先用新版 ZIP 準備維護工具再移除，過程不註冊新版輸入法；接管中斷後可重試。

唯讀實測發現，沒有安裝繁體中文語言的沙箱帳號，`GetProfile` 回報不到本機既有的三個 profile，而真正使用者帳號可查到。因此先唯讀核對本產品的 machine 定義是否存在，再用 `GetLanguageProfileDescription` 驗證 TSF 可讀；API 快取不得把已移除的定義算為仍存在。曾使用 category 列舉結果配合本機定義核對，仍漏測安裝器的 STA 快取。後續已重現：相同 STA apartment 中依序查詢、卸載 DLL、註冊、再卸載與查詢，回傳 0x1 而非 0x1f01。現在 category 快照直接唯讀核對五個產品 machine 定義，不依賴該列舉快取；註冊與移除仍透過 TSF API，不直接改寫 TSF 或使用者鍵盤登錄。native smoke test 檢查既有 machine profile 的存在，不依測試帳號是否已安裝語言判斷。

使用者在安裝前次 1.3.1 測試包後回報「新增鍵盤」顯示三個同名琦琦項目。唯讀核對只有同一 CLSID 下的台灣、香港、澳門三個定義，香港／澳門 machine Enable=0，但定義仍在設定 UI 可見。其後測試包安裝失敗；Deployment.log 確認恢復原 COM 註冊。隔離原生 API 測試證明隱藏旗標回傳成功但未持久化，因此改為只新增台灣入口，依使用者確認於 commit 後移除兩個舊區域定義，統一為一個共用入口；未以刪除三份安裝目錄或使用者鍵盤登錄處理。

| 證據層級 | 本輪結果 |
| --- | --- |
| 原始碼／暫存測試 | 29 個部署案例通過，涵蓋升級、部分註冊與 ARP 失敗回復、中斷重試、回復失敗保留日誌、修復、降版、舊 owner／cleanup 入口阻擋、額外／變更檔案、占用與未重開機重裝、校驗及路徑邊界、舊移除入口接管重試，以及主入口驗證、共用入口與舊入口清理後置條件，以及不阻擋主安裝的清理失敗及同包重試。部署系統操作使用 fake backend；相容入口檔案測試只使用暫存目錄。新增真正 Windows image section 鎖定、一次移除排程 payload 與 maintenance、排程失敗保留重試、未知檔案保留，以及模擬重開機後直接重裝／重開機前先裝新版的案例；模擬重開機不是 VM 重開機。另有原生 TSF 整合測試，程序內將 HKLM／HKCU 分別導向獨立隨機暫存登錄區，測真正 API 的首次安裝、升級移除閒置入口、移除已選用的兩個舊入口但保留共用入口啟用值、重跑與移除後重裝，並涵蓋獨立程序、STA apartment 與 DLL 卸載／重新載入邊界，結束清理測試區。 |
| Windows 11 建置 | VS 2026 x64 Ninja 與 x86 Ninja 建置成功；各自 CTest 7／7 通過。x86 包與 native 測試是在 x64 Windows 上執行，不能當成 32 位元 Windows 驗收。 |
| ZIP 產物 | x64、x86 ZIP 已打包；`Packaging/verify-package.py` 直接讀取 ZIP，核對 14／13 個 payload 檔案的清單、雜湊、PE 架構、正式 DB 雜湊及 Win10／Win11 設定說明。CI 增加相同檢查。 |
| NSIS 產物 | NSIS 3.12 未簽署 EXE 編譯成功；只驗證包裝編譯，未在本機執行安裝、靜默安裝或移除，也未完成 EXE 解包驗證。 |
| 本機既有安裝 | 使用者 14:08 自行成功安裝前次測試包，畫面顯示共用入口及兩個保留的舊區域名稱，因此進一步確認只需要一個入口。14:15 解除安裝後有占用檔案待重開機，14:16 再按清理仍待重開機。14:37 重開機後清理因執行中的 Uninstall.exe 拒絕存取而失敗；14:40 重裝因 category 快取驗證失敗後回復。兩個原因已分別以 image section 與 STA/DLL 重載回歸重現。本輪改為一次移除完成排程並移除 ARP，及修正 category 快照；本輪包尚未在實際系統安裝，不能以隔離／模擬測試代替 VM 重開機與使用者畫面驗收。 |
| 共用資料庫 | 建置驗證正式 DB 與來源雜湊；新增 `.gitattributes` 固定 9 個雜湊來源檔的 LF，避免 Windows autocrlf 改變原始位元組。沒有 cooker 或改變 DB／語料內容。 |

測試產物位於忽略的 `Source/Loaders/Windows-TSF/out/package/` 與 `out/store-package/`，不提交。尚未使用正式憑證驗證簽署路徑；沒有宣稱 Store 認證完成。上述 VM 矩陣、多帳號／UAC、真正宿主載入、各個歷代發布產物的移除後重裝仍是發布門檻。
