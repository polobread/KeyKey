# Windows 共用建置、CI unsigned artifact 與本機簽包

Windows 採用一份 `Build-WindowsRelease.ps1`，在 GitHub Actions 與 Windows 本機執行相同的建置、測試及未簽署封裝命令。正式待簽來源取自官方 Actions 成功 run 的 artifact；本機 `Release-Windows.ps1` 只下載驗證、Certum 簽章與重新封裝，不重新編譯或重跑完整矩陣。Ed25519 使用既有 `Prepare-WindowsUpdate.ps1`。

建置與待簽 artifact 不依賴 GitHub Release。Release 建立、正式上傳及 CDN 鏡像都在本機簽包與人工驗收完成後，另由維護者核准。沒有 unsigned 正式發布分支，也不使用 `WINDOWS_RELEASE_MODE`。

## 與 1.3.2 workflow 的對表

基準為 [v1.3.2 的 package-windows.yml](https://github.com/polobread/KeyKey/blob/v1.3.2/.github/workflows/package-windows.yml)。沿用目前原始碼、版號來源與封裝器，不倒回舊產品程式。

| 1.3.2 步驟 | 共用 PowerShell 與目前分工 |
|---|---|
| Ruby、.NET、NSIS 準備 | Actions 安裝 Ruby 3.4、.NET 10、NSIS 3.12；本機建置入口先檢查工具 |
| WinSparkle SDK、更新設定 | 驗證固定 SDK，依 CMake 版號及 stable／beta 標籤產生暫存設定 |
| x64／x86 configure、build、CTest | 保留相同 presets 與排除重複 managed 測試的規則 |
| 設定、部署、跨程序／跨架構資料保護 | 保留各項命令，各執行一次 |
| 更新 metadata、原生 updater | 保留共用 Windows 測試；macOS 專屬簽章／公證測試留在 macOS 流程 |
| 兩種 unsigned ZIP、NSIS unsigned EXE | 仍使用 Package-Windows／Package-Store-Windows，並驗證實際 ZIP 內容 |
| artifact 與校驗檔 | 改存精確白名單的待簽 payload、unsigned 測試包、設定與測試／雜湊紀錄 |
| Release 上傳與鏡像 | 移至本機簽包、VM 驗收及人工核准之後；CI 不發布正式檔案 |

## 1. 共用建置與 CI artifact

完整建置環境需要 Windows、Visual Studio 2026 C++／Windows SDK、CMake、Ruby 3.4、Python 3.11+、.NET SDK 10、OpenSSL 3、NSIS 3.12、Git。開發者也可直接從儲存庫根目錄執行相同入口：

~~~powershell
& .\Source\Loaders\Windows-TSF\Build-WindowsRelease.ps1 -OutputDirectory "$PWD\update\out\windows-checks"
~~~

必要時使用 `-Python`、`-OpenSslPath`、`-MakensisPath` 指定工具。輸出須為新目錄且路徑不可過長；腳本在開始建置前檢查，保留既有失敗輸出。這個入口不簽章、不安裝、不建立 tag／Release，也不發布檔案。

`Windows Build and Unsigned Inputs` 在 PR、master push 或手動執行時呼叫此腳本。手動 stable 可留空 `release_tag`，由 CMake 版號決定；beta 填 `vX.Y.Z-betaN` 並選正確來源 ref。這只是建置標籤，不建立或移動 tag。

只有官方儲存庫的非 PR run 才上傳 `keykey-windows-unsigned-RUN_ID-RUN_ATTEMPT`，保留 30 天。PR 仍執行共用建置、測試與 unsigned 封裝驗證，但不提供正式待簽 artifact。本機自行產生的同格式目錄標示為 `local`，不能冒充 Actions 待簽來源。

artifact 僅包含：

- `inputs/x64/`、`inputs/x86/`：TSF、設定、部署、x86 bridge、WinSparkle、詞庫與必要授權檔。
- `unsigned/`：用於封裝驗證的 x64 unsigned setup、x64／x86 ZIP 及三份 checksum。
- `build-checks.json`、`update-config.json`、`signing-inputs.json`：來源、頻道、步驟、逐項 CTest 狀態及每檔 SHA-256。

不是把整個工作區或 build 目錄上傳；私鑰、憑證識別、OTP／PIN、使用者資料、診斷紀錄與未列入白名單的檔案均不進 artifact。測試報告分別記錄 `passed`／`skipped`，不把跳過寫成通過；CI 成功不能取代缺少的 GUI／實機與 VM 驗收。

## 2. 固定來源後在本機簽包

先由維護者 review／merge 原始碼、腳本與 CI 變更。取得該來源的成功 run，維護者核對正式 tag 指向同一 commit。若現有 tag 指向不同來源，停止簽包，不移動 tag、改寫測試紀錄或以同版覆蓋產物。

本機簽包只需 Git、已登入的 GitHub CLI、Python、Windows SDK SignTool、NSIS 3.12 與 SimplySign Desktop；不需要重新準備完整 C++、Ruby 或 .NET SDK 建置環境。Ed25519 另需 OpenSSL 3 與既有私鑰。

從乾淨、已更新來源的 tag checkout 執行：

~~~powershell
& .\Source\Loaders\Windows-TSF\Release-Windows.ps1 -RunId 123456789 -ReleaseTag vX.Y.Z
~~~

`RunId` 換成成功 run ID。beta 用對應 `vX.Y.Z-betaN`；產品檔名與 PE 版號仍由 CMake 的 `X.Y.Z` 取得。腳本要求：

1. 官方 workflow、官方 head repository；成功的 master push，或 master／指定 tag 的手動 run。PR、fork、其他工作分支不接受。
2. `CI head_sha == tag commit == local HEAD`，且來源已進入 `origin/master`；本機來源乾淨、origin 正確，沒有已追蹤／暫存的指定私鑰。
3. artifact ID、run attempt、未過期狀態與 GitHub 提供的 SHA-256 相符；解壓只接受明確白名單，拒絕多餘、重複或不安全路徑。
4. 每個檔案、測試來源、更新頻道與 manifest 相符。下載快取再次使用時重新核對，不重新建置。

維護者在 SimplySign 介面輸入手機 token／PIN。指定存放區只有一張有效且具私鑰存取權的 Certum code signing 憑證時，腳本直接在記憶體選取；沒有候選或候選不唯一時才以遮罩提示讀取憑證識別。簽章診斷不回顯，也不記錄簽署憑證識別。

腳本簽署 x64／x86 全部 payload EXE／DLL 副本，逐檔核對 SHA-256 Authenticode 與 RFC 3161 時間戳。接著從同一份已簽 payload 重包 x64／x86 ZIP 與 x64 NSIS EXE，再簽外層 EXE，最後核對版本、架構、詞庫、實際內容及簽章。CI 的 unsigned setup 是封裝測試產物，不作正式更新安裝器。

預設輸出為 `update/out/local-release/RUN_ID-TAG/signed/`，共七份正式候選檔案：

- `chichi77-KeyKey-VERSION-windows-x64-setup.exe` 與 `.sha256`
- `chichi77-KeyKey-VERSION-windows-x64.zip` 與 `.sha256`
- `chichi77-KeyKey-VERSION-windows-x86.zip` 與 `.sha256`
- `chichi77-KeyKey-VERSION-windows-build-info.json`

build-info 保存 CI 來源與 artifact 證據、完整步驟／逐項測試狀態、輸入及六份產物的雜湊，不記錄主機個人資訊或簽章私密資料。可用 `-OutputDirectory` 指定其他 Git 忽略目錄。簽包後不修改、重壓縮、重簽或覆蓋完成產物。

ZIP 驗證保留全部檔案的同發行者簽章、時間戳、雜湊、架構及固定清單檢查。`KeyKeySettingsBackend.dll` 與 `KeyKeyRegistration_x86.exe` 依目前 CMake 未嵌入版本資源，缺少 ProductVersion 時以封裝版號與來源核對；若日後嵌入版號仍須相符。其他產品程式必須具備正確版號。Python 啟動 Windows PowerShell 驗證時只使用其原生系統模組，避免繼承 PowerShell 7 模組路徑。

## 3. 本機 Ed25519 與人工驗收

Authenticode 完成後，依 [更新資料說明](../update/README.md#產生與驗證更新資料) 準備 Windows 單平台 manifest：指定最終已簽 x64 EXE、實際版本／tag、相同的 source／tag commit、`windows_signing: authenticode`、最低 Windows 版本與發布說明。

~~~powershell
& .\Source\Loaders\Windows-TSF\Prepare-WindowsUpdate.ps1 -Manifest C:/release/windows-manifest.json -PrivateKeyPath C:/protected/keykey-update-private.pem -BaseUrl https://download.aws.polobread.com/keykey/releases/download -OutputDirectory update/out/signed-release
~~~

私鑰只交給本機密碼工具讀取，不 commit／stage、複製、列印、上傳或放進 artifact。包裝器核對正式公鑰並抑制工具診斷。輸出是安裝包 Ed25519 簽章、metadata／簽章、SHA-256 內容位址副本及 appcast；這一步不上傳或提升 feed。

在乾淨 Windows VM 驗收 EXE 與兩種 ZIP 的發行者／時間戳、安裝／升級／同版重裝／降版拒絕、x64／32 位元文字宿主輸入、設定及使用者詞庫保留與移除。補上 CI 跳過的必要 GUI 驗收。來源、隔離測試、CI 綠勾與簽章各自是不同層級的證據。

## 4. 人工核准後才發布

維護者驗收並明確核准後，才建立對應正式 Release／Pre-release。從同一來源、run／tag 與輸出目錄執行：

~~~powershell
& .\Source\Loaders\Windows-TSF\Release-Windows.ps1 -Action Publish -RunId 123456789 -ReleaseTag vX.Y.Z
~~~

腳本列出六份產物的 SHA-256，要求完整輸入 `PUBLISH TAG BUILD_INFO_SHA256`，核准範圍涵蓋 EXE、兩個 ZIP 與 checksum。發布前再次核對 CI／artifact、來源、全部雜湊及實際簽章。七份檔案上傳既有 Release 後逐份回讀，再請求受保護的 CDN 鏡像。不同 bytes 的同名資產拒絕覆寫；不建立／刪除 Release、不移動 tag、不使用 clobber，也不自動修改 feed。

Release 若已有 Ed25519 內容位址 EXE，既有 CDN 鏡像流程會先下載並核對其大小與 SHA-256，確認和已驗證的 setup 完全相同，再條件新增該副本、回讀並驗證 CDN。原 tag 的 Windows 工作仍負責驗證產品；鏡像工作使用發送當次已審查的 master 工具，無須移動產品 tag、重建或重簽。副本不存在時仍只鏡像原七份檔案，內容不同則在任何 AWS 寫入前停止。

Ed25519 不可變副本須先經核准上線與驗證，feed 再以獨立 PR 由維護者 review／merge。沿用既有 metadata、signature 與 appcast 原始 bytes；metadata 或 URL 有變動就不能沿用原簽章。平台其他發布流程維持各自規則。

feed PR 合併後，由 `master` 上的 `Sync Update Feeds to CDN` 同步；若自動執行
被 `[skip ci]` 略過，才手動執行 `sync-feeds`，不重複發送已在執行的同步。
beta 原生驗證依實際 beta 檔案或其驗證工具變更決定；單純 workflow 或 stable feed
修改，不因舊 beta 設定仍存在而重驗舊安裝器。`stage-beta-assets` 每次都要求原生
驗證，缺少 beta 設定時仍須失敗，不可略過。同步沿用現有簽包及簽章，不重新建置或簽署。

## 必要工具驗證與失敗處理

~~~powershell
python -m unittest discover -s .github/scripts -p test_windows_signing.py -v
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Source/Loaders/Windows-TSF/Packaging/Test-Signing.ps1
~~~

隔離案例涵蓋共用 PowerShell 的編排、unsigned staging、跳過狀態、來源／run／雜湊與白名單，以及既有簽包／Ed25519 私密診斷保護，不讀使用者私鑰、不連 Certum、不上傳。完整原生矩陣由同一份 PowerShell 在 CI 執行一次；本機簽包不重跑。

下載或簽包中斷時保留原始 artifact、快取與失敗輸出，先確認失敗階段；完成的簽包輸出不可覆寫。來源或 run attempt 不同時不沿用，不能以改寫紀錄迴避檢查。重試本機簽包不需要再執行 Windows 建置 workflow。
