# Windows 本機建置、Certum 簽章與發布

Windows 正式發布完全由本機產生安裝包、兩個架構的 ZIP、校驗檔及 build-info。
Windows Checks 只在 PR、master push 或手動執行時建置與測試，不產生發布 artifact、不簽章、不上傳 Release。
發布 GitHub Release 不會啟動 Windows 建置；不再使用待簽 artifact、RunId 或 WINDOWS_RELEASE_MODE。
所有新版發布都要求 Authenticode，沒有 unsigned 發布分支。低階封裝的 UnsignedTest 僅供隔離測試。

## 前置準備與來源

- 維護者先 review／merge 工作分支，再為該 commit 建立 vX.Y.Z 或 vX.Y.Z-betaN tag。beta 使用 Pre-release。
- 發布 checkout 必須乾淨，HEAD 等於本機 tag，且該 commit 已在 origin/master 中。不要在其他 chat 正在修改的 checkout 發布。
- 本機安裝 Visual Studio 2026 C++／Windows SDK、CMake 3.25+、Ruby 3.4、Python 3.11+、.NET SDK 10、OpenSSL 3、NSIS 3.12、Git、GitHub CLI 與 SimplySign Desktop。
- 先更新來源及 tags，確認 origin 是官方 polobread/KeyKey。Publish 時會再次核對 GitHub 上的 tag，拒絕來源不同的同版補發。
- GitHub CLI 使用自己的登入儲存區；不將 token、thumbprint、OTP、PIN、TOTP seed 或私鑰寫入 Git、日誌或命令範例。
- SimplySign 手機 token／PIN 由維護者在供應商介面輸入；thumbprint 由腳本的遮罩提示讀取。
- 建置輸出只放 Git 忽略的 out/local-release。可用額外的乾淨 checkout 發布，保留開發工作區與本機產物。

## 1. 本機完整建置、測試、簽章及封裝

從乾淨的 tag checkout，在儲存庫根目錄執行：

~~~powershell
& .\Source\Loaders\Windows-TSF\Release-Windows.ps1 -ReleaseTag vX.Y.Z
~~~

X.Y.Z 是產品版號占位；beta 使用 vX.Y.Z-betaN，必須與 CMake 產品版號及原 tag commit 對應。
檔名及 PE 產品版號使用 X.Y.Z；頻道／beta 輪次由 release_tag、release_version 與獨立 CDN／feed 路徑識別。
腳本不建立 Release、不建立或移動 tag。建置簽包時不下載 GitHub artifact。

預設 Build 動作會：

1. 核對乾淨來源、官方 origin、本機 tag 與已合併來源；建立來源 context。
2. 選擇 stable／beta 更新設定，下載／核對固定的 WinSparkle SDK。
3. 在獨立輸出目錄建置 x64 與 x86，執行完整發布矩陣。CI 的 Windows Checks 使用同一份 Build-WindowsRelease.ps1。
4. 執行各架構 CTest、設定／部署、跨架構及原生／managed 資料保護、更新器／簽章回歸，記錄全部通過的 build-checks。
5. 保存兩個架構的原始建置檔案與逐檔 SHA-256；副本中的全部 EXE／DLL 以 SHA-256 與 RFC 3161 時間戳簽章並逐檔驗證。
6. 用同一份已簽 payload 產生 x64 NSIS 安裝檔、x64 ZIP 與 x86 ZIP。ZIP 內的設定、部署、TSF、bridge、WinSparkle 均為已簽檔案；簽章後才建立 manifest 與壓縮。
7. 簽署外層 EXE，再檢查 EXE、ZIP 真正內容、PE 架構、產品版號、詞庫雜湊、簽章及可信任時間戳，產生三份校驗檔與涵蓋全部產物的 build-info。

Windows 完整建置矩陣的 `update-metadata` 檢查會從 `update/` 執行共用的
`test_channels` 與 `test_metadata` 測試，涵蓋更新頻道、metadata、Ed25519 與 Windows
簽章驗證案例。macOS 專屬的簽章與公證測試由 macOS 流程執行；它們不屬於 Windows
發布矩陣。Build-WindowsRelease 仍須完成所有 Windows 架構、部署、更新器、傳輸與簽章政策檢查。

x64 安裝檔與 x64 ZIP 同時包含 x86 TSF／bridge，以支援 32 位元文字宿主；x86 ZIP 供 32 位元 Windows。
解除安裝沿用已簽的部署程式。原始碼、隔離測試與本機簽章成功不能代替實際安裝驗收。

預設輸出在 Source/Loaders/Windows-TSF/out/local-release/TAG/signed/，正好七份發布資產：

- chichi77-KeyKey-VERSION-windows-build-info.json
- chichi77-KeyKey-VERSION-windows-x64-setup.exe
- chichi77-KeyKey-VERSION-windows-x64-setup.exe.sha256
- chichi77-KeyKey-VERSION-windows-x64.zip
- chichi77-KeyKey-VERSION-windows-x64.zip.sha256
- chichi77-KeyKey-VERSION-windows-x86.zip
- chichi77-KeyKey-VERSION-windows-x86.zip.sha256

build-info 記錄本機建置來源、tag、完整測試紀錄、建置輸入雜湊，以及六份檔案的大小與 SHA-256。
不記錄憑證識別或主機個人資訊。簽章後不修改、重壓縮或覆蓋產物。

可用 -Python、-OpenSslPath、-MakensisPath、-SignToolPath 指定工具；
必要時使用 -CertificateStoreLocation LocalMachine，預設為 CurrentUser。
時間戳預設 http://time.certum.pl。輸出可用 -OutputDirectory 改至另一個 Git 忽略目錄。

## 2. 人工驗收

在乾淨 Windows VM 驗證 EXE 與兩個 ZIP 的有效發行者／時間戳、UAC、一般／靜默安裝、舊版升級、
同版重裝、降版拒絕、x64／32 位元文字宿主輸入、設定與使用者詞庫保留，以及移除。
簽包後保留原始產物，驗收不重新修改或簽署它們。

## 3. 核准 GitHub 上傳與 CDN 鏡像

建立對應的正式 Release 或 Pre-release 後，從相同來源 checkout 與輸出目錄執行：

~~~powershell
& .\Source\Loaders\Windows-TSF\Release-Windows.ps1 -Action Publish -ReleaseTag vX.Y.Z
~~~

腳本列出六份檔案的 SHA-256，並要求完整輸入 PUBLISH TAG BUILD_INFO_SHA256。
核准的是 build-info 雜湊，連同其內記錄的三個包及三份校驗檔一起固定，避免只核准 EXE 而漏掉 ZIP。
發布前重新核對 GitHub tag、乾淨本機來源、原始建置輸入、測試紀錄、所有雜湊與實際 Authenticode。
任何 ZIP 的簽章、內容或來源不符，皆在上傳前停止。

七份檔案上傳至既有 Release，逐份下載回讀比對，然後觸發 Mirror Signed Windows Release。
不編輯 Release／Latest、不移動 tag、不使用 clobber。同名相同 bytes 可重試，同名不同 bytes 拒絕覆寫。
鏡像 workflow 從 master 啟動，在 Windows checkout tag 並重新下載／驗證七份產物，包含 ZIP 中的簽章。
受保護的 release environment 以 OIDC 寫入既有 S3／CloudFront，條件式新增後回讀 S3／CDN。
若 environment 設有 reviewer，需完成該核准。已請求鏡像不代表鏡像成功，應查看最終結果。

## 4. 本機 Ed25519 與更新 feed PR

Authenticode／時間戳完成後，Windows 的 Ed25519 也在本機使用 keykey-update-private.pem 處理。
此檔名已加入 Git 忽略規則；禁止 commit／stage、上傳、顯示內容或放進產物，建議存放在儲存庫外。
Windows 發布前會拒絕已追蹤／暫存的同名私鑰；本機包裝器抑制簽章工具診斷，不回顯私鑰。
依 [更新發布說明](../update/README.md#產生與驗證更新資料) 準備 Windows manifest，宣告 authenticode、
實際 tag／source commit、最終已簽 x64 EXE、最低 Windows 版本及發布說明，再執行：

~~~powershell
& .\Source\Loaders\Windows-TSF\Prepare-WindowsUpdate.ps1 -Manifest /path/windows-manifest.json -PrivateKeyPath /protected/keykey-update-private.pem -BaseUrl https://YOUR-CDN/keykey/releases/download -OutputDirectory update/out/signed-release
~~~

此 Windows 專用入口只接受已簽 x64 EXE 的單平台 manifest，其他平台維持各自既有流程。
它使用本機 metadata.py／OpenSSL，核對私鑰與既有正式公鑰一致，驗證安裝檔簽章與產品版號，產生安裝包 Ed25519 簽章、metadata.json／.sig、
SHA-256 內容位址副本及 appcast。私鑰不進 Git、Actions 或 artifact。
x86 ZIP 是手動安裝入口，不把 ZIP 當自動更新 EXE，也不另產生 x86 NSIS 安裝器。
先上線並驗證不可變副本，才準備相應 stable／beta 的 feed PR；由維護者 review、merge master 後同步 CDN。
Release-Windows 不自動修改、提升或上傳 feed。

## 重試與驗證

建置測試完成但尚未開始簽章時，可用相同 tag／輸出目錄執行 -Action Sign，會重新核對保存的建置輸入。
若有不完整的簽包輸出，先保留診斷，人工移走失敗輸出或改用全新的 Git 忽略輸出目錄重新 Build。
工具不自動刪除失敗產物。完整 signed 輸出存在後不重新簽包，直接在驗收後 Publish。
GitHub／CDN 中斷可重新 Publish，但每次都需核准完整 build-info 雜湊。

~~~powershell
python -m unittest discover -s .github/scripts -p test_windows_signing.py -v
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Source/Loaders/Windows-TSF/Packaging/Test-Signing.ps1
~~~

以上隔離驗證使用合成資料與工具替身，不連 Certum／GitHub／AWS，不讀本機憑證、不執行安裝器。
正式發布矩陣由 Build-WindowsRelease.ps1 執行；不把日常工具修改的局部測試當成發布驗收。
