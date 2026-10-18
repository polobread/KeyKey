# Windows Certum 本機簽章與發布

本流程是半自動流程：新的 `Prepare Windows Signing Inputs` workflow 負責編譯、測試與整理待簽產物，
本機腳本負責下載驗證、簽章與 NSIS 封裝。SimplySign 登入／PIN、VM 驗收與發布核准保留人工操作。
簽包與發布是兩次命令。原本 unsigned workflow 完整保留、預設停用，切換方式見下節。
憑證已由維護者取得；真實 Certum 簽章、乾淨 VM 與雲端發布仍須首次驗收，
隔離測試不代表這些項目已完成。Windows 產品版本從 CMake 讀取，不連動其他平台與模型。

## 一次性準備

- 先由維護者 review／merge 導入 PR；release tag 必須包含新版 workflow 與腳本。
- Windows 安裝 Python **3.11 以上**、Git、GitHub CLI、Windows SDK SignTool、NSIS **3.12**、SimplySign Desktop。
- 執行 `gh auth login`，登入有本儲存庫 Actions 讀取、Release 上傳及 workflow dispatch 權限的維護者帳號。
  不將 GitHub token 寫入腳本；CLI 使用自己的登入儲存區。
- 手機 SimplySign 已啟用。本機不保存 OTP、PIN、QR code 或 TOTP seed。
- GitHub `release` environment 沿用既有 AWS OIDC 角色及變數：
  `AWS_RELEASE_MIRROR_ROLE_ARN`、`AWS_RELEASE_MIRROR_REGION`、`AWS_ACCOUNT_ID`、
  `AWS_RELEASE_MIRROR_BUCKET`、`AWS_RELEASE_MIRROR_DISTRIBUTION_ID`、`AWS_RELEASE_MIRROR_BASE_URL`。
  IAM 須允許既有 release 目錄的條件式 PutObject／GetObject 與 CloudFront invalidation。
  若環境限制只允許 master，須由維護者明確允許本流程使用的 release tag；
  workflow dispatch 本身限定從 master 啟動，mirror job checkout 已核對的 tag。
  本流程不修改 IAM、environment 核准規則或存放任何 AWS 長期金鑰。

不需要在本機安裝 Visual Studio、.NET SDK、Ruby 或 AWS CLI；本機不重新編譯，也不登入 AWS。
若 `python` 不在 PATH，兩次命令均可加 `-Python '實際 python.exe 路徑'`。

## unsigned 備援與模式切換

原本的 `.github/workflows/package-windows.yml`（`Package Windows`）保留完整編譯、測試、
unsigned ZIP／NSIS 封裝、Release 發布與鏡像工作，沒有改成待簽流程。
其 package／publish jobs 只有 repository Actions variable `WINDOWS_RELEASE_MODE=unsigned` 才執行；
未設定此變數時全部跳過，因此合併後預設停用。這是受版本控制的 job gate，與 GitHub UI 的
`Disable workflow` 狀態不同；不會由本機腳本改寫任何 repository variable。

| `WINDOWS_RELEASE_MODE` | 原 unsigned workflow | 新待簽 workflow |
| --- | --- | --- |
| 未設定或 `certum` | 停用 | 啟用 |
| `unsigned` | 啟用 | 停用 |
| 其他值 | 停用 | 停用 |

未來若不續購 Certum，由維護者手動切回 unsigned，無須還原程式碼：

```powershell
gh variable set WINDOWS_RELEASE_MODE --repo polobread/KeyKey --body unsigned
# 切回 Certum：
gh variable set WINDOWS_RELEASE_MODE --repo polobread/KeyKey --body certum
```

切換前先等待該平台已在執行的發布結束；模式變數不會取消已開始的工作。
不要以切換模式取代版本／來源 review。憑證到期或登入失敗不會自動降級為 unsigned。
unsigned 模式仍須逐版明確使用 `windows_signing: "unsigned-transition"`、Ed25519 與人工 feed PR；
無效簽章不能當 unsigned，已發布資產不能用此模式原地替換。

## 1. 產生待簽包

完成原始碼 review 後，以產品版本建立 tag 並發布對應的 GitHub Release；beta 使用
`vX.Y.Z-betaN` 與 Pre-release。Certum 模式會啟動新的 `Prepare Windows Signing Inputs`，
執行既有 x64／x86 發布測試並整理待簽產物。此 workflow 不上傳 unsigned EXE／ZIP 至 Release，
也不進行鏡像同步。

若需手動啟動，以相同 tag 作為 workflow ref，並填入 `release_tag`：

```powershell
gh workflow run prepare-windows-signing.yml --repo polobread/KeyKey --ref vX.Y.Z -f release_tag=vX.Y.Z
```

`X.Y.Z` 是格式占位，請換成實際 Windows 版本；beta 的兩個 tag 參數也要相同。
CI source 必須等於 tag commit；不接受同版本但 source 不同的 recovery build。
修正原始碼後要走新版本／新 tag，不能移動已發布 tag。

CI 產生 `keykey-windows-signing-VERSION-RUN_ID-ATTEMPT` artifact，保存 30 天，包含固定的
9 個建置輸入及 `signing-inputs.json`。內容為兩個架構的 TSF、x86 registration bridge、
x64 設定／部署／更新元件、DB 與 WinSparkle 授權。manifest 記錄來源、run、attempt 與逐檔 SHA-256。
未填 `release_tag` 的手動 run 僅供測試，不可事後宣告為正式待簽包。

## 2. 本機下載、驗證、簽包

在本機使用官方 repository 的**乾淨 checkout**，checkout 到該 CI 的確切 commit。
不要在有個人未提交修改的工作目錄直接切換；可另備一份發布 checkout。
以下命令從儲存庫根目錄執行，`123456789` 改成成功的 Prepare Windows Signing Inputs run ID：

```powershell
& .\Source\Loaders\Windows-TSF\Release-Windows.ps1 `
  -RunId 123456789 -ReleaseTag vX.Y.Z
```

腳本先驗證官方 repository、workflow、成功狀態、事件、run attempt、tag／source commit，
下載 artifact archive，核對 GitHub API 的 SHA-256 digest，再嚴格檢查固定檔名與逐檔雜湊。
不執行 artifact 內任何腳本，封裝程式與授權檔取自同一個已核對的 source checkout。

看到登入提示後，在 SimplySign Desktop 連線，輸入手機 token；thumbprint 在 PowerShell
遮罩提示內輸入。若需要 PIN，只在 SimplySign 的對話框輸入。
預設憑證位於 `CurrentUser\My`；必要時加 `-CertificateStoreLocation LocalMachine`。
工具不在預設位置時加 `-MakensisPath` 或 `-SignToolPath`。
預設 Certum RFC 3161 URL 為 `http://time.certum.pl`，可用 `-TimestampUrl` 明確更換。

腳本在暫存副本以 SHA-256 簽內部 7 個 PE，逐檔驗證完整簽章、指定憑證與可信任時間戳記，
再產生 signed payload manifest、建立 NSIS x64 安裝包、簽外層並驗證，最後計算 SHA-256。
x64 安裝包包含 x86 TSF／bridge，供 32 位元文字宿主使用；本流程不新增 32 位元 Windows 安裝器。
解除安裝器沿用已簽的部署 EXE，不產生未簽的 NSIS uninstaller。

輸出在忽略提交的 `Source/Loaders/Windows-TSF/out/local-release/RUN_ID-TAG/signed/`：

- `chichi77-KeyKey-VERSION-windows-x64-setup.exe`
- 相同檔名加 `.sha256`
- `chichi77-KeyKey-VERSION-windows-signed-build-info.json`：來源／CI artifact 身分與最終安裝包雜湊。

不將 thumbprint、token、PIN、seed 寫入設定、JSON、命令範例或日誌。SignTool/provider 的原始
stdout／stderr 丟棄，只回報成功或通用錯誤。正式 Authenticode 檔案仍會內含公開憑證。
不要對此互動流程啟用 PowerShell tracing、transcription 或外部命令列錄製。

## 3. 人工驗收

在乾淨 Windows VM 驗證有效發行者／時間戳記、UAC、一般與 `/S` 安裝、既有版升級、
x64／32 位元文字宿主中文輸入、設定與使用者詞庫保留，以及移除。
原始碼、mock、CI 成功不能取代已簽安裝包的實機行為。簽完不再修改安裝包。

## 4. 核准上傳與鏡像

使用相同 checkout、run 與 tag：

```powershell
& .\Source\Loaders\Windows-TSF\Release-Windows.ps1 `
  -Action Publish -RunId 123456789 -ReleaseTag vX.Y.Z
```

腳本顯示版本、檔名與最終 SHA-256，要求完整輸入 `PUBLISH TAG SHA256`。
確認後會重新驗證 CI／tag、原 archive、最終雜湊、Windows Authenticode、時間戳記與版本，
上傳這 3 份檔案至既有 Release，逐份下載回讀比對，再觸發 `Mirror Signed Windows Release`。
不建立／編輯 Release、不移動 tag、不變更 Latest，不使用 `--clobber`。

鏡像 workflow 從 master 啟動，在 Windows checkout tag、重新下載 Release 產物及驗簽，
再由受保護的 `release` environment 以 OIDC 寫入原有 S3／CloudFront 路徑。
若 environment 設有 reviewer，需完成該核准。
S3 使用 `If-None-Match: *`，已存在時只接受完全相同 bytes；同步後回讀 S3、等待指定路徑
invalidation 完成並核對 CDN bytes。Actions 摘要提供下載連結。
本機顯示「已請求鏡像」不等於鏡像成功，須確認該 workflow 最終結果。

## 重試與界線

- 簽章中斷且尚未產生最終 EXE：可用同一個 Sign 命令，重新驗證快取後重試。
- 下載未完成：保留錯誤供診斷，人工移走該 run 的失敗輸出目錄後重試；不自動刪除使用者檔案。
- 最終 signed EXE 已存在時不重簽覆蓋；首次執行產生 receipt 後，直接 Publish。
- GitHub 上傳或鏡像中斷：重新 Publish，必須再次核准。相同 bytes 可重試；任何同名不同內容
  都中止，不能改 receipt 掩蓋不同的簽包。
- 不要重跑已簽 run 的 CI attempt 或刪除 artifact；來源證明核對仍需 GitHub 上的 artifact metadata。
  artifact 過期後無法重新下載，已有本機 archive 仍可依保留的 API metadata 核對；metadata 被刪除則停止。
- feed、Ed25519、商店提交仍遵循各自流程；本命令不改 feed 或提交 Partner Center。
  自動更新採 `windows_signing: "authenticode"`，先完成 Authenticode 才建立 Ed25519 更新簽章。
  已公布 unsigned 版本不原地替換，使用更高產品版本。

## 隔離驗證

```powershell
python -m unittest discover -s .github/scripts -p test_windows_signing.py -v
powershell.exe -NoProfile -File Source/Loaders/Windows-TSF/Packaging/Test-Signing.ps1
```

這些測試使用合成資料與工具替身，不連 Certum／GitHub／AWS、不執行安裝器，也不讀本機憑證。
服務操作依據：[GitHub artifact REST API](https://docs.github.com/en/rest/actions/artifacts)、
[Certum 官方手冊](https://files.certum.eu/documents/manual_en/CS-Code_Signing_in_the_Cloud_Signtool_jarsigner_signing.pdf)、
[Microsoft SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool)。
