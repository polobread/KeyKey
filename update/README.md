# 桌面更新（開發中）

此目錄在 local `v1.3.2` 開發 macOS／Windows 更新客戶端與發布工具，**不是已上線的自動更新服務**。
`config.json` 的公開金鑰與 feed 目前留空，因此建置不連線。未使用 Yahoo 舊服務、
RSA/SHA-1 metadata 或 deprecated DownloadUpdate helper。

## 目錄與維護入口

更新設定、建置／發布工具與 feed 統一放在小寫單數 `update/`。
GitHub Raw 與 CDN 的固定 feed 檔名為 `macos-arm64.xml`、`windows-x64.xml` 和
`windows-x86.xml`，放在各自的 `update/stable/` prefix。

| 檔案／目錄 | 何時維護 |
|---|---|
| `config.json` | 設定正式公開金鑰與各平台 feed URL；私鑰放在 repository 外 |
| `dependencies.json` | 升級 Sparkle／WinSparkle SDK 時更新版本與 SHA-256 |
| `prepare.py` | 建置前準備 SDK；由各平台建置流程呼叫 |
| `metadata.py` | 發布時驗證 manifest 與安裝包，產生簽章、metadata 及 feed |
| `macos_release.py` | 核對 macOS 四份版號及正式設定，再產生經驗證的單平台更新候選，不發布 |
| `verify-windows.ps1`、`sign-macos.py` | 平台驗證／簽章實作，由發布或建置工具呼叫 |
| `test_*` | 測試，由 CI 執行 |
| `stable/` | 固定網址的 feed；發布時提交已驗證的輸出，經 PR review／merge |
| `.cache/`、`out/` | SDK 快取與產物，不提交 |

日常建置只需要 `prepare.py`；發布依下方 manifest 流程操作，不必逐一編輯這些工具。

## 共用與平台邊界

- 共用的是 manifest 格式、Ed25519 金鑰／簽章規格與發布工具，不是同一個安裝包。
- `metadata.json` 的 detached signature 用於發布驗證與後續消費者；Sparkle／WinSparkle
  **不直接解析或驗證這份 JSON**。工具從同一份資料產生個別 appcast；目前原生客戶端
  驗證的是 appcast enclosure 指定的**安裝包 Ed25519 簽章**，不是 JSON signature。
  feed 本身仍依賴 HTTPS 與託管端控制，尚未實作 signed-feed 驗證／metadata 到期與防重播。
- macOS：Sparkle 2.10.0，由 IMK 主程式持有 updater，Preferences 透過既有本機服務
  檢查與切換自動檢查。更新 `.pkg.zip`，保留 `/Library/Input Methods` 的安裝方式。
  套件仍需管理員同意，安裝後登出／登入；不啟用靜默安裝或背景自動下載。
  原生回呼同步檢查／下載／錯誤／取消狀態；組字未完成時延後更新重啟，真正結束前
  再檢查新組字，不自行送字或清除。這是客戶端保護，不是所有 App 實機驗收的替代品。
  保護範圍是此 IMK 行程的活動組字；手動安裝與其他登入工作階段不經過此回呼。
- Windows：WinSparkle 0.9.4，只在現代 Settings 執行檢查；**沒有登入排程／背景服務**。
  native DLL 與 feed 依 Settings 的 bitness 選擇。安裝沿用現有 NSIS＋版本化 Deployment。
  目前 NSIS 只有 x64 installer，故 x86 feed 只提供手動下載資訊，不把 ZIP 當自動安裝器。
  更新分頁會顯示檢查結果、錯誤及取消狀態。安裝入口重查未儲存內容；如果安裝器
  已啟動後才有新的編輯，設定視窗會保持開啟以保留草稿。這項保護不會取消已啟動的
  安裝器，也不能從啟動成功推定安裝成功。WinSparkle 管理下載進度、簽章及 UAC；
  設定視窗的回呼只非同步送往 WPF，避免清理時互相等待。
  「重新安裝目前版本…」另提供手動下載入口：只有使用者按下時才查詢 GitHub Release，
  確認與目前 Settings 版號／架構相同且非 draft 的 EXE 或 ZIP 存在後，開啟該版官方
  Release 頁，由使用者下載並執行安裝。這個入口不依賴更新 key／feed，不下載、驗證或
  啟動安裝器，也不關閉設定視窗；仍要求先儲存設定／自訂詞，查詢期間新增草稿會阻止
  開頁。沒有發布下載檔、離線或查詢失敗時顯示原因，不改用其他版本或架構。
- Linux：交給發行版套件庫；現有 `.deb` 下載不等於已架設 APT 更新庫。
- FreeBSD：交給 ports/pkg；此變更沒有新增 port，也不讓輸入法繞過套件管理器覆寫檔案。

## 本機建置

在 repository root 執行：

```sh
python3 update/prepare.py fetch macos
bash update/test-macos.sh
(cd Source && xcodebuild -project Takao.xcodeproj \
  -target 'Takao (Loader OSX-IMK)' -configuration Release \
  -xcconfig Takao-macOS.xcconfig build)
(cd Installer && ./build.sh)
```

在 Windows 建置前執行 `python update/prepare.py fetch windows`，再使用既有
Windows TSF CMake presets。Package macOS／Windows workflows 已加入準備步驟。
下載會校驗官方 SDK 的固定 SHA-256；cache 與產物不提交。macOS SDK 內全部授權通知及
Windows WinSparkle 的 COPYING 都會隨安裝包保留。

### macOS 1.3.2 開發與啟用

macOS 原始碼版號為 1.3.2（未發布）；四份產品 plist 必須一致，封裝不再讀取
README 的 Linux 版號。更新設定頁每秒讀取 IMK 的本機狀態；Sparkle 自己呈現下載
進度與簽章／安裝錯誤。自動檢查預設關閉，舊 Yahoo 旗標不算同意；開啟後只在 IMK
主程式執行時每日檢查，不新增 launch agent。系統 profile 與背景下載均強制關閉。

固定來源可選擇以下之一，macOS 尚未實作來源失敗自動切換：

- CDN：`https://download.aws.polobread.com/keykey/update/stable/macos-arm64.xml`
- GitHub Raw：`https://raw.githubusercontent.com/polobread/KeyKey/master/update/stable/macos-arm64.xml`

初始 `stable/macos-arm64.xml` 只有已發布 1.3.1 的手動下載連結，沒有更新 item。
分支內檔案不表示 Raw master 或 CDN 已部署。舊版沒有正式更新設定，因此第一次
導入必須手動下載並安裝含公開金鑰與 feed 的 notarized 版本，再登出／登入。
後續更新必須使用更高版號；同版本重新打包不是自動升級。

`package-macos.yml` 的受保護 `release` environment 簽章 job 支援選擇性候選產生：

1. 先審查並設定 `config.json` 的正式公開金鑰及已可存取的 macOS feed。
2. 在有人工核准的 environment 設定 secret `UPDATE_ED25519_PRIVATE_KEY_PEM`，內容為
   對應公開金鑰的 PEM 私鑰；不要貼在聊天、提交 Git 或放進 artifact。
3. 設定 variable `MACOS_UPDATE_METADATA_ENABLED=true`。可選的
   `AWS_RELEASE_MIRROR_BASE_URL` 決定 enclosure 指向 CDN，未設定則指向 GitHub Release。
4. 使用已審查的正式 tag 建置，且 `source_sha == tag_sha`；同版 recovery 不產生更新候選。
   job 先驗證 Developer ID／notarization，再產生 `keykey-macos-updater-VERSION` artifact，
   包含內容位址安裝包、`macos-arm64.xml` 與單平台 signed metadata。私鑰暫存檔離開步驟即移除。
5. 維護者 review 候選，按下方發布順序上傳不可變 `packages/`，確認可下載且 SHA-256 相同，
   才以 PR 提升 GitHub feed／部署 CDN feed。此 workflow 不自動上傳更新候選或改寫 feed，
   原有 Release 下載資產發布仍照既有流程執行。

本機 `bash update/test-macos.sh` 使用 fake engine 與離屏設定頁，無網路、安裝或已安裝 loader 變動。
`KEYKEY_TEST_OPENSSL=/opt/homebrew/bin/openssl python3 -m unittest discover -s update -p test_macos_release.py -v`
使用臨時測試金鑰驗證候選簽章，正向 OS 驗證為 mock；不能宣稱已完成 notarized 升級。
正式啟用前須完成本文最後列出的已安裝版本驗收，包含組字中／新組字及個人詞庫保留。

## 正式金鑰與網址設定（需維護者審查）

1. 在 repository **外部**產生並備份 PEM Ed25519 私鑰，例如在受保護的金鑰目錄執行：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out keykey-update-private.pem
   ```

   使用 OpenSSL 3，不用 macOS 內建 LibreSSL。私鑰不加入 Git、不在命令參數中傳私鑰內容；
   正式 CI 透過受保護且需人工核准的 environment secret 暫存為檔案。

2. 取得公開金鑰：

   ```sh
   python3 update/metadata.py --openssl /opt/homebrew/bin/openssl public-key \
     --key /absolute/protected/path/keykey-update-private.pem
   ```

   把輸出的 32-byte base64 公開金鑰放入 `config.json`。這是公開資料，可審查／提交。
   不在客戶端接受 feed 提供的新公開金鑰。Package updater 的金鑰輪替需另行設計，
   不應在沒有過渡方案時直接換 key。

3. 設定 `macos_feed_url`、`windows_x64_feed_url` 為 HTTPS 的固定平台 feed。
   各平台共用 CDN 的 `keykey/update/stable/` 目錄，以獨立檔案提供 feed，不另外
   增加平台子目錄，也不將不同平台合併成同一份 XML。預定配置如下，尚未上傳或啟用：

   ```text
   https://download.aws.polobread.com/keykey/update/stable/
     macos-arm64.xml
     windows-x64.xml
     windows-x86.xml
     metadata.json
     metadata.json.sig
   ```

   `windows-x86.xml` 目前提供無更新項目的初始 RSS；建立並驗證正式 x86 installer 後，
   才加入版本與下載項目。在此之前保持 `windows_x86_feed_url` 空白。
   各 feed URL 必須先實際建立、驗證，再寫入 `config.json`。
   安裝包仍放在 `keykey/releases/download/TAG/FILE`，不放進 feed 目錄。

### Windows 的 CDN 與 GitHub Raw 來源

正式來源規劃如下；CDN 為主要來源，GitHub Raw 為備援，不使用 GitHub Pages：

| 來源 | 固定 feed URL |
|---|---|
| CDN x64 | `https://download.aws.polobread.com/keykey/update/stable/windows-x64.xml` |
| GitHub Raw x64 | `https://raw.githubusercontent.com/polobread/KeyKey/master/update/stable/windows-x64.xml` |
| CDN x86 | `https://download.aws.polobread.com/keykey/update/stable/windows-x86.xml` |
| GitHub Raw x86 | `https://raw.githubusercontent.com/polobread/KeyKey/master/update/stable/windows-x86.xml` |

`update/stable/windows-x64.xml` 與 `windows-x86.xml` 是 GitHub 來源的初始 RSS，
目前記錄已發布的 Windows 1.3.1 手動下載資訊：x64 指向 unsigned EXE，x86 指向 ZIP。
每份 feed 的 channel `link` 使用 CDN 主來源，`description` 以 HTML 列出 CDN 與
GitHub 兩個手動下載連結。維持一個標準 RSS `link`，不放重複的 channel `link`。
兩個來源的連結都由使用者自行選用，客戶端尚未實作自動切換。
資訊放在 RSS channel 的 `link` 與 `description`，沒有自動更新 `item`／`enclosure`，
WinSparkle 讀取後仍回報無可用更新，不會自動下載或執行這些檔案。
待使用者 review 並將 PR 合併至 `master` 後，才會出現在上述 Raw 網址；CDN 副本仍需
完成 IAM／cache 設定並實際上傳。手動下載資訊不表示已完成自動更新發布。
正式公鑰與客戶端 feed 設定目前仍留空。

v1.3.1 的 GitHub Release 尚無 x86 EXE 或安裝包 Ed25519 更新簽章；其 Windows
build-info 的 `source_sha` 與 `tag_sha` 不同，屬既有同版 recovery 下載資產。
這批檔案可供手動下載，但不直接通過現有 stable 自動更新的來源驗證。
後續自動更新需另有符合 review／tag／版本規則、已完成 Ed25519 簽章的安裝器。

每次正式發布使用同一組 Ed25519 金鑰與同一個已通過所宣告簽章模式驗證的安裝包，
兩個來源的版本、檔案內容／SHA-256 及安裝包簽章必須一致。各來源的 feed 使用自己的
安裝包下載網址：GitHub 指向 `https://github.com/polobread/KeyKey/releases/download/TAG/FILE`，
CDN 指向 `https://download.aws.polobread.com/keykey/releases/download/TAG/FILE`。
必須先分別上傳並驗證安裝包，再發布該來源的 feed；只備份 XML、卻共用唯一下載來源，
不能提供完整的下載備援。

GitHub feed 變更在工作分支提交，再由使用者 review／merge 至 `master`，不得由
workflow 直接回存 `master`。CDN feed 使用短快取及精確 invalidation。現有 metadata
工具可針對不同 `--base-url` 產生兩份輸出，但雙來源發布協調尚未接入 workflow；
Windows 客戶端也仍只接受單一 feed URL，來源設定與失敗切換功能尚待實作。

## 產生與驗證更新資料

Manifest 是 JSON，`schema_version: 1`、`channel: "stable"`、`releases` 陣列。
每個 release 必須提供：

```json
{
  "target": "macos-arm64",
  "version": "1.3.2",
  "release_tag": "v1.3.2",
  "source_sha": "0000000000000000000000000000000000000000",
  "tag_sha": "0000000000000000000000000000000000000000",
  "file": "/absolute/path/signed-and-notarized.pkg.zip",
  "minimum_system_version": "15.0.0",
  "notes": "修正說明"
}
```

上例的 SHA 是占位文字，必須由實際 tag checkout／建置來源取得；不能當正式來源證明。
Windows target 為 `windows-x64` 或 `windows-x86`，檔案需是安裝器 `.exe`，不能用 ZIP；
最低 OS 依產品需求填寫。`windows_signing` 未設定時預設為 `authenticode`，要求有效且
帶 timestamp 的 Windows 發行者簽章。過渡發布方式見下節。
各平台可以有不同版本。穩定自動更新必須 `source_sha == tag_sha`，不可用同版 recovery
覆蓋已公布的更新；既有 `release-assets.py --clobber` 流程僅供原下載資產，不用於 updater。

在各平台的受保護簽章 job 上，先執行 `metadata.py attest --manifest ... --key ... --out ...`。
macOS 會實際檢查 Gatekeeper installer assessment 與 stapled notarization；Windows
會實際檢查所宣告的 Windows 簽章狀態與 installer product version。各平台產生
`TARGET.attestation.json` 與 `.sig`，用來將 OS 驗證結果綁定到檔案 SHA-256／版本／commit。
這是受信任簽章 job 的證明，工具本身不能從 binary 推導或證明 source commit。

把驗證證明及安裝包集中後，可在單一 runner 產生共用 metadata 與所有平台 feed：

```sh
python3 update/metadata.py build --manifest /path/all-platforms.json \
  --attestations /path/attestations --key /protected/key.pem \
  --base-url https://YOUR-CDN/keykey/releases/download --out update/out/signed-release
```

不提供 `--attestations` 時，工具在當前 OS 直接驗證每個包，適合單平台發布。
輸出包括 `packages/` 內帶完整 SHA-256 的不可變檔名、平台 `.xml`、共用 `metadata.json`
與 base64 detached signature `metadata.json.sig`。已有 output directory 一律拒絕覆寫。

```sh
python3 update/metadata.py verify --file /path/metadata.json \
  --signature /path/metadata.json.sig
```

### Windows stable 的 unsigned 過渡模式

維護者決定在 Windows 正式發行者簽章尚未就緒時，stable 可以使用 unsigned EXE。
這只免除 Authenticode，不免除安裝包的 Ed25519 更新簽章、正式公鑰、HTTPS、來源 review、
tag／版本一致性及不可變資產要求。每一版的 manifest 必須明確宣告：

```json
{
  "target": "windows-x64",
  "version": "1.3.2",
  "release_tag": "v1.3.2",
  "source_sha": "0000000000000000000000000000000000000000",
  "tag_sha": "0000000000000000000000000000000000000000",
  "file": "C:/release/chichi77-KeyKey-1.3.2-windows-x64-setup.unsigned.exe",
  "windows_signing": "unsigned-transition",
  "minimum_system_version": "10.0.0",
  "notes": "Windows 1.3.2 正式版；發行者簽章仍在準備中。"
}
```

此物件放在前述 `releases` 陣列中；SHA 仍是占位文字，必須換成實際建置 tag commit。
Windows 驗證器只接受 `NotSigned` 且無簽章憑證的 EXE，不把無效、遭竄改或不受信任的
簽章降級成 unsigned。簽章模式一起綁入 Ed25519 attestation 與 metadata；unsigned
驗證證明不能改標為 Authenticode。工具自動在 appcast 加入未知發行者／SmartScreen
提示；Ed25519 驗證不會讓 Windows 認定已驗證發行者，也不會略過 UAC 或系統封鎖。

之後取得 Authenticode 簽章時，使用**更高的產品版號**、相應 tag 與新安裝包，將
`windows_signing` 改為 `authenticode`（或移除，採用預設）。先完成 Authenticode 與
timestamp，再以原本的 Ed25519 私鑰簽署最終 bytes，重新產生 metadata／appcast。
沿用同一個 stable URL 與 Ed25519 公鑰即可升級，不需要另外開 channel 或換金鑰。
不能覆蓋已發布的同版 unsigned EXE，也不能直接把簽章加到既有不可變下載檔；
同版重新簽章不會讓已安裝相同版本的客戶端偵測到新版本。

## GitHub Release／CDN 發布順序（尚未自動化）

1. 通過原始碼 review 與發布核准。Windows workflow 目前仍產生 unsigned installer；
   只有從相應 release tag 建置、驗證版本並明確宣告 `unsigned-transition` 的 EXE，
   才能以正式 Ed25519 私鑰建立過渡 stable feed。無 tag 的手動 artifact 仍是測試包。
   Authenticode 發布則需先完成 SignPath 或等效的簽章與人工核准流程。
2. 上傳 `packages/` 的内容位址檔案到指定 Release；不使用 `--clobber`。
   base URL 使用 GitHub 時填 `https://github.com/OWNER/REPO/releases/download`。
3. CDN 模式先將相同 bytes 鏡像到 `keykey/releases/download/TAG/FILE`；校驗遠端可取得、
   size 與 SHA-256 正確後，最後才更新固定 feed。GitHub Releases 可放不可變資產，
   固定 feed 另外放在 CDN／靜態網站，不能把 GitHub Release API 當 appcast。
4. packages 使用長快取；feeds／metadata 使用短 TTL 與精確 invalidation。
   現有 Terraform mirror role 僅允許 release download prefix；使用新的
   `keykey/update/stable/` 前需 review IAM／cache 設定，這次沒有 apply 或修改線上資源。
5. 分平台 promotion，避免尚未完成的 Windows 發布拖累 macOS。最終的共用 metadata
   可以集合獨立版本，但 feed、簽章與安裝程序仍是平台各自的。

正式啟用前還需在實際 Windows 與已安裝的 notarized macOS 版本上驗收：合法升級、
修改安裝包、錯誤 key、離線、取消下載／UAC、安裝失敗、已使用中的 DLL，以及升級後
個人資料保留。本機編譯與單元測試不等於這些端到端驗收。

## 測試

```sh
KEYKEY_TEST_OPENSSL=/opt/homebrew/bin/openssl python3 -m unittest discover -s update -v
python3 -m unittest discover -s .github/scripts -v
```

測試金鑰只存在 TemporaryDirectory，OS 簽章正例由 mock 隔離；真實 Ed25519 簽章、
防竄改與錯 key 驗證使用 OpenSSL。mock 正例不能當 notarization／Authenticode 驗收。

Windows unsigned 過渡模式的 metadata 12 項回歸已通過，其中 Windows runner 包含
16 個隔離簽章／版號案例；驗證明確 opt-in、unsigned bytes 的 Ed25519 防竄改，以及
unsigned attestation 不能改標為 signed。已唯讀確認既有本機 unsigned 1.3.2 測試 EXE
通過過渡簽章狀態與版號檢查；沒有替它產生正式更新簽章或發布 feed。Windows CI
已加入這組回歸，尚待 Actions 執行。signed EXE 的真實憑證驗收仍待正式簽章流程。

目前本機已驗證 macOS Release 編譯、含 Sparkle helper 的 ad-hoc 深層簽章與未簽章
pkg 打包，及 Windows Settings 的 win-x64／win-x86 self-contained 交叉編譯。
既有 metadata、release-assets 測試與共用模型檢查通過。
Windows 已通過 30 項隔離 Deployment.Tests，及 x64／x86 WPF 設定回歸；新增回歸涵蓋
Windows 10／11 manifest 的最低系統版本檢查，以及套用設定、成功／失敗儲存自訂詞、
選取已儲存詞與關聯詞庫變更時的更新關閉保護。WPF 測試使用既有已編譯原生後端與
隔離個人資料；不執行 WinSparkle 下載或安裝。完整 TSF／NSIS 建置與 GUI 升級驗收尚未完成。

2026-10-11 Windows 客戶端補充驗證：x64／x86 Settings 建置、WPF 設定／自訂詞回歸
及固定 WinSparkle 0.9.4 DLL 的 8 個原生案例各通過。原生案例以 loopback HTTP 提供
測試 appcast／無法執行的測試 bytes，暫存 Ed25519 金鑰及隨機 HKCU 測試區在結束後
移除；不修改正式 config，也不執行安裝器。涵蓋同版無更新、x64／x86 初始空 feed、
合法簽章下載、檔案竄改、
錯 key、缺少簽章與損壞 feed。只有測試直接呼叫原生 backend 使用 HTTP；正式客戶端
仍只接受設定內的 HTTPS URL。合法簽章正例只是下載與驗證證據，不是 Authenticode、
UAC、NSIS 升級或安裝成功證據；取消與關閉競態由隔離 managed backend 測試驗證。

```powershell
# 一般使用者環境；需 OpenSSL 3（例如 Git for Windows 內附版本）
python update/prepare.py fetch windows
$openssl = Join-Path $env:ProgramFiles 'Git/usr/bin/openssl.exe'
foreach ($architecture in @('x64', 'x86')) {
    dotnet run --project Source/Loaders/Windows-TSF/DesktopUpdater.Tests/DesktopUpdater.Tests.csproj `
      --configuration Release -r "win-$architecture" --self-contained -- --native --openssl $openssl
    if ($LASTEXITCODE -ne 0) { throw "Updater tests failed: $architecture" }
}
```

不加 `--native` 可只跑無登錄／連線的 managed 生命週期回歸，包含離線預設、無效設定、
架構 feed 選擇、重複檢查、重試、取消、背景回呼、初始化失敗重試、釋放及草稿保護。
Windows package workflow 會跑兩種架構的 managed＋原生案例，並要求 ZIP 含相同架構
的 WinSparkle DLL 與授權通知。本機兩份 1.3.2 測試 ZIP 已通過內容雜湊、PE 架構、
共用 DB 及授權通知檢查；使用此次 Settings publish 產物與既有已編譯 native／Deployment
產物，沒有重跑完整 TSF／NSIS 建置或實際安裝。workflow 尚待 GitHub Actions 執行驗證。
