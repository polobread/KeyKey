# 桌面更新（開發中）

此目錄是在 local `v1.3.2` 接上的第一階段實作，**不是已上線的自動更新服務**。
`config.json` 的公開金鑰與 feed 目前留空，因此建置不連線。未使用 Yahoo 舊服務、
RSA/SHA-1 metadata 或 deprecated DownloadUpdate helper。

## 共用與平台邊界

- 共用的是 manifest 格式、Ed25519 金鑰／簽章規格與發布工具，不是同一個安裝包。
- `metadata.json` 的 detached signature 用於發布驗證與後續消費者；Sparkle／WinSparkle
  **不直接解析或驗證這份 JSON**。工具從同一份資料產生個別 appcast；目前原生客戶端
  驗證的是 appcast enclosure 指定的**安裝包 Ed25519 簽章**，不是 JSON signature。
  feed 本身仍依賴 HTTPS 與託管端控制，尚未實作 signed-feed 驗證／metadata 到期與防重播。
- macOS：Sparkle 2.10.0，由 IMK 主程式持有 updater，Preferences 透過既有本機服務
  檢查與切換自動檢查。更新 `.pkg.zip`，保留 `/Library/Input Methods` 的安裝方式。
  套件仍需管理員同意，安裝後登出／登入；不啟用靜默安裝或背景自動下載。
- Windows：WinSparkle 0.9.4，只在現代 Settings 執行檢查；**沒有登入排程／背景服務**。
  native DLL 與 feed 依 Settings 的 bitness 選擇。安裝沿用現有 NSIS＋版本化 Deployment。
  目前 NSIS 只有 x64 installer，故 x86 feed 維持空白，不把 ZIP 當自動安裝器。
  更新分頁會顯示檢查結果、錯誤及取消狀態。安裝入口重查未儲存內容；如果安裝器
  已啟動後才有新的編輯，設定視窗會保持開啟以保留草稿。這項保護不會取消已啟動的
  安裝器，也不能從啟動成功推定安裝成功。WinSparkle 管理下載進度、簽章及 UAC；
  設定視窗的回呼只非同步送往 WPF，避免清理時互相等待。
- Linux：交給發行版套件庫；現有 `.deb` 下載不等於已架設 APT 更新庫。
- FreeBSD：交給 ports/pkg；此變更沒有新增 port，也不讓輸入法繞過套件管理器覆寫檔案。

## 本機建置

在 repository root 執行：

```sh
python3 Updates/prepare.py fetch macos
(cd Source && xcodebuild -project Takao.xcodeproj \
  -target 'Takao (Loader OSX-IMK)' -configuration Release \
  -xcconfig Takao-macOS.xcconfig build)
(cd Installer && ./build.sh)
```

在 Windows 建置前執行 `python Updates/prepare.py fetch windows`，再使用既有
Windows TSF CMake presets。Package macOS／Windows workflows 已加入準備步驟。
下載會校驗官方 SDK 的固定 SHA-256；cache 與產物不提交。macOS SDK 內全部授權通知及
Windows WinSparkle 的 COPYING 都會隨安裝包保留。

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
   python3 Updates/metadata.py --openssl /opt/homebrew/bin/openssl public-key \
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
沒有任何版本或下載項目。
待使用者 review 並將 PR 合併至 `master` 後，才會出現在上述 Raw 網址；CDN 副本仍需
完成 IAM／cache 設定並實際上傳。空 feed 只表示目前沒有可用更新，不是已完成正式發布。
正式公鑰與客戶端 feed 設定目前仍留空。

每次正式發布使用同一組 Ed25519 金鑰與同一個已完成 Authenticode 簽章的安裝包，
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
Windows target 為 `windows-x64`，檔案需是已簽章的 `.exe`；最低 OS 依產品需求填寫。
各平台可以有不同版本。穩定自動更新必須 `source_sha == tag_sha`，不可用同版 recovery
覆蓋已公布的更新；既有 `release-assets.py --clobber` 流程僅供原下載資產，不用於 updater。

在各平台的受保護簽章 job 上，先執行 `metadata.py attest --manifest ... --key ... --out ...`。
macOS 會實際檢查 Gatekeeper installer assessment 與 stapled notarization；Windows
會實際檢查有效且帶 timestamp 的 Authenticode。各平台產生
`TARGET.attestation.json` 與 `.sig`，用來將 OS 驗證結果綁定到檔案 SHA-256／版本／commit。
這是受信任簽章 job 的證明，工具本身不能從 binary 推導或證明 source commit。

把驗證證明及安裝包集中後，可在單一 runner 產生共用 metadata 與所有平台 feed：

```sh
python3 Updates/metadata.py build --manifest /path/all-platforms.json \
  --attestations /path/attestations --key /protected/key.pem \
  --base-url https://YOUR-CDN/keykey/releases/download --out Updates/out/signed-release
```

不提供 `--attestations` 時，工具在當前 OS 直接驗證每個包，適合單平台發布。
輸出包括 `packages/` 內帶完整 SHA-256 的不可變檔名、平台 `.xml`、共用 `metadata.json`
與 base64 detached signature `metadata.json.sig`。已有 output directory 一律拒絕覆寫。

```sh
python3 Updates/metadata.py verify --file /path/metadata.json \
  --signature /path/metadata.json.sig
```

## GitHub Release／CDN 發布順序（尚未自動化）

1. 通過原始碼 review 與各平台簽章核准；目前 Windows workflow 仍只產生 unsigned test
   installer，**不得**用它建立正式更新 feed。需先完成 SignPath 或等效的簽章流程。
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
KEYKEY_TEST_OPENSSL=/opt/homebrew/bin/openssl python3 -m unittest discover -s Updates -v
python3 -m unittest discover -s .github/scripts -v
```

測試金鑰只存在 TemporaryDirectory，OS 簽章正例由 mock 隔離；真實 Ed25519 簽章、
防竄改與錯 key 驗證使用 OpenSSL。mock 正例不能當 notarization／Authenticode 驗收。

目前本機已驗證 macOS Release 編譯、含 Sparkle helper 的 ad-hoc 深層簽章與未簽章
pkg 打包，及 Windows Settings 的 win-x64／win-x86 self-contained 交叉編譯。
metadata 9 項與既有 release-assets 8 項測試通過，共用模型檢查通過。
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
python Updates/prepare.py fetch windows
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
