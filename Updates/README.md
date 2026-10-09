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
   可用 CDN 的 `keykey/updates/stable/macos-arm64.xml`、`windows-x64.xml`；未建立 x86
   installer 前保持 `windows_x86_feed_url` 空白。這些網址必須先實際建立、驗證，不填猜測網址。

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
   `keykey/updates/stable/` 前需 review IAM／cache 設定，這次沒有 apply 或修改線上資源。
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
Windows Deployment.Tests 已能編譯，但執行依賴 Windows 路徑／維護工具語意，在 macOS
未通過；需 Windows runner 執行。完整 TSF／NSIS 建置與 GUI 升級驗收尚未完成。
