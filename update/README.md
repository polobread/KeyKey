# 桌面更新（開發中）

此目錄開發 macOS／Windows 更新通知與手動確認後的更新流程，以及發布工具；**端到端驗收尚未完成**。
`config.json` 已設定維護者提供的正式公開金鑰與 stable／beta CDN feed。自動檢查預設開啟，保留使用者既有關閉設定；所有桌面版採下述啟動延後／每週排程；beta 選項預設關閉；舊版第一次導入仍須手動安裝含新設定的版本。未使用 Yahoo 舊服務、
RSA/SHA-1 metadata 或 deprecated DownloadUpdate helper。

## 目錄與維護入口

更新設定、建置／發布工具與 feed 統一放在小寫單數 `update/`。
GitHub Raw 與 CDN 的固定 feed 檔名為 `macos-arm64.xml`、`windows-x64.xml`、`windows-x86.xml` 和 `unix-fcitx5.xml`，stable 與 beta 分別放在 `update/stable/`、`update/beta/` prefix。

| 檔案／目錄 | 何時維護 |
|---|---|
| `config.json` | 設定正式公開金鑰與各平台 feed URL；私鑰放在 repository 外 |
| `dependencies.json` | 升級 Sparkle／WinSparkle SDK 時更新版本與 SHA-256 |
| `prepare.py` | 建置前準備 SDK；由各平台建置流程呼叫 |
| `metadata.py` | 發布時驗證 manifest 與安裝包，產生簽章、metadata 及 feed |
| `macos_release.py` | 核對 macOS 四份版號及正式設定，再產生經驗證的單平台更新候選，不發布 |
| `verify-windows.ps1`、`sign-macos.py` | 平台驗證／簽章實作，由發布或建置工具呼叫 |
| `notarize-macos.py` | 保存 Apple 公證報告，僅 `Accepted` 且成功退出後 staple／validate |
| `test_*` | 測試，由 CI 執行 |
| `stable/` | 固定網址的 feed；發布時提交已驗證的輸出，經 PR review／merge |
| `beta/` | 獨立測試版 feed，絕不提升至 stable；初始 XML 無更新項目 |
| `channels.py` | 正式／`-betaN` tag、顯示版號與原生比較版號的共用規則 |
| `.cache/`、`out/` | SDK 快取與產物，不提交 |

日常建置只需要 `prepare.py`；發布依下方 manifest 流程操作，不必逐一編輯這些工具。

## 共用與平台邊界

三個桌面平台統一採「檢查並通知新版，使用者按下更新後才下載與安裝」：
排程檢查只代表新版通知，不授權自動安裝或預先下載安裝包。Windows／macOS 由更新視窗
接受使用者確認後下載、驗證及安裝；Linux／FreeBSD 的按鈕開啟官方發行頁，
由使用者下載並透過套件管理器安裝。關閉或略過通知不會開始下載。

macOS、Windows、Linux／FreeBSD 的更新查詢都在背景執行，整輪查詢時限為 **10 秒**。
失敗或逾時後顯示結果，由使用者按「立即檢查」／「檢查新版」重試，不做自動重試或來源切換。
自動檢查可隨時關閉，成功、失敗與手動檢查都記錄嘗試時間。
macOS、Windows、Linux／FreeBSD 均採相同規則：距上次嘗試已滿 7 天，才在更新程式
啟動 10 分鐘後首次自動檢查；若未滿 7 天，直接排至到期時間，且不得早於啟動後 10 分鐘。
持續執行時以一次性計時器每 7 天檢查，不逐分鐘輪詢，不補跑睡眠期間漏掉的次數。
忙碌時亦延至下週；手動檢查可立即執行，並將下次自動期限延至 7 天後。
macOS 自身 App 偏好值使用 `standardUserDefaults`；三個入口均保留記憶體期限，避免保存失敗重送。
排程沿用既有入口：macOS IMK 主程式、Windows 設定程式、Linux／FreeBSD XDG 通知工具；
關閉電腦或退出該程式時不執行檢查，重啟後仍保留上次嘗試紀錄。
macOS／Windows 由客戶端以同一條可取消的查詢路徑排程，停用 SDK 自己的背景排程；
SDK 繼續負責版本選擇、套件簽章與安裝確認。macOS 查無更新直接顯示於設定頁，
設定頁與一般頁的更新狀態／同意設定透過有時限的背景本機呼叫讀取；Windows 原生取消與
清理不在 WPF 執行緒等待。晚到的查詢結果與關閉視窗後的回覆不再修改介面。

- 共用的是 manifest 格式、Ed25519 金鑰／簽章規格與發布工具，不是同一個安裝包。
- `metadata.json` 的 detached signature 用於發布驗證與後續消費者；Sparkle／WinSparkle
  **不直接解析或驗證這份 JSON**。工具從同一份資料產生個別 appcast；目前原生客戶端
  驗證的是 appcast enclosure 指定的**安裝包 Ed25519 簽章**，不是 JSON signature。
  feed 本身仍依賴 HTTPS 與託管端控制，尚未實作 signed-feed 驗證／metadata 到期與防重播。
- macOS：Sparkle 2.10.0，由 IMK 主程式持有 updater，Preferences 透過既有本機服務
  檢查與切換自動檢查。更新 `.pkg.zip`，保留 `/Library/Input Methods` 的安裝方式。
  套件仍需管理員同意；完成後從輸入法選單選取琦琦，並在「文字編輯」試打、核對版本。
  能正常輸入即可繼續使用；來源缺少時從鍵盤設定加入。不啟用靜默安裝或背景自動下載。
  原生回呼同步檢查／下載／錯誤／取消狀態；組字未完成時延後更新重啟，真正結束前
  由 Sparkle 重啟回呼再檢查新組字，不自行送字或清除。一般結束、登出與關機不經過
  更新器的拒絕結束判斷。這是客戶端保護，不是所有 App 實機驗收的替代品。
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
- Linux／FreeBSD：Fcitx 設定中的「更新通知與下載…」提供手動新版檢查、預設開啟且可關閉的每週
  通知及官方發行頁入口。兩者共用 CDN `unix-fcitx5.xml`，客戶端不查 GitHub API／tag 原始碼。Linux 依公告的已驗證架構篩選；FreeBSD 同步顯示上游原始碼新版，
  明示由 ports/pkg 更新及套件庫可能較晚上架。詳細設定與既有 port 的封裝修改見
  [更新通知](../Source/Loaders/Linux-IME/docs/update-notifications.md)。安裝仍交給套件
  管理器；沒有建立 APT/pkg 更新庫，也不在輸入法內下載或執行安裝包。

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

### macOS 正式更新與啟用

macOS **1.3.8** 已正式發布，stable appcast 與 signed metadata 已合併並同步 CDN，提供 Apple Silicon 的 1.3.8 簽章更新項目，最低系統為 macOS 15。Windows x64／x86 與 Linux／FreeBSD 公告維持 **1.3.7**；iOS、Android 正式版也維持 1.3.7。已包含相同正式 feed 與公鑰的舊版可找到這次 macOS 更新；每週檢查保留使用者既有開關，也可按「立即檢查」。尚未包含更新設定的舊版仍需先手動安裝。

正式安裝包、SHA-256 校驗檔與建置資訊見 [1.3.8 Release 的台灣 AWS 下載點](https://github.com/polobread/KeyKey/releases/tag/v1.3.8#台灣-aws-下載點)。該頁僅提供 macOS；Windows 與 Ubuntu 下載維持 [1.3.7](https://github.com/polobread/KeyKey/releases/tag/v1.3.7#台灣-aws-下載點)。

正式 feed 為 `https://download.aws.polobread.com/keykey/update/stable/macos-arm64.xml`，GitHub 原始檔為 `https://raw.githubusercontent.com/polobread/KeyKey/master/update/stable/macos-arm64.xml`。客戶端目前不會在兩個來源間自動切換。

**後續版本自動準備公告：** `Package macOS` 成功發布穩定版後，`Prepare macOS Stable Update` 會在受保護的 `release` environment 執行。它只使用已 review 的 `master` 工具，重新下載原 Release 安裝包，核對成功的官方建置、tag commit、Release digest、checksum 與 build-info，再驗證 Apple 簽章、公證、四份產品版號及更新公鑰。全部通過後，用 `UPDATE_ED25519_PRIVATE_KEY_PEM` 產生 Ed25519 更新簽章，新增逐 byte 相同的 SHA-256 內容位址副本，回讀驗證後自動開 feed PR。既有 Windows 公告與 metadata 項目會保留；不重新建置、移動 tag、覆蓋已發布檔案或自動合併 PR。

必須在 `release` environment 設定 `UPDATE_ED25519_PRIVATE_KEY_PEM`，並在 repository 的 Actions 權限允許 workflow 建立 PR。穩定版不再需要 `MACOS_UPDATE_METADATA_ENABLED`；既有 beta 候選流程仍使用該開關。私鑰只寫入 runner 的暫存檔供 OpenSSL 使用，步驟結束即刪除，不輸出、不放入 artifact。workflow 另保存公開簽章候選 artifact，供檢視或開 PR 失敗時手動取回。

**已發布版本的手動補救：** 在 Actions 選 `Prepare macOS Stable Update`，使用 `master`，填入 `release_tag=v1.3.8`。此入口沿用已發布原包及來源驗證；同版已在正式 feed 且雜湊相同時不重複建立更新，不允許降版或替換同版內容。若該版已有 PR 分支，會停止並要求先檢查既有 PR，不覆寫他人修改。

feed PR 仍須由維護者 review／merge；合併後才由 `Sync Update Feeds to CDN` 部署公告。workflow 只準備穩定 macOS 更新，不發布 beta feed、不直接部署 CDN。若準備期間 `master` 已更新，會停止並要求重跑，以免覆蓋其他平台剛更新的 metadata。

本機補簽可使用 `.github/scripts/prepare-macos-update.py` 的 `prepare`、`sign`、`stage-asset` 指令，再將 `proposal/` 的 `macos-arm64.xml`、`metadata.json`、`metadata.json.sig` 逐檔放入工作分支。`sign --key` 只接受未被 Git 追蹤的本機私鑰，且必須對應 `config.json` 的正式公鑰。候選、下載檔及執行記錄保存在忽略的 `update/out/`。

本機 `bash update/test-macos.sh` 使用 fake engine 與離屏設定頁，無網路、安裝或已安裝 loader 變動。
`KEYKEY_TEST_OPENSSL=/opt/homebrew/bin/openssl python3 -m unittest discover -s update -p test_macos_release.py -v`
使用臨時測試金鑰驗證候選簽章，正向 OS 驗證為 mock；不能宣稱已完成 notarized 升級。
正式啟用前須完成本文最後列出的已安裝版本驗收，包含組字中／新組字及個人詞庫保留。

macOS 發行建置禁止注入 `get-task-allow` 除錯權限；重新簽章只移除此權限，
保留 Sparkle 的 sandbox／XPC 必要權限，並逐一驗證所有架構。公證結果不是 `Accepted`
或命令失敗時停止封裝；Apple submission JSON、錯誤輸出及拒絕報告會保存為 CI artifact，
不再把缺少票證的 stapler Error 65 當成第一個錯誤。隔離回歸及報告路徑見
[`Installer/README.md`](../Installer/README.md#signing-and-notarising)。測試不送件或發布 Release。

## Feed／signed metadata 自動同步到 CDN

[`Sync Update Feeds to CDN`](../.github/workflows/sync-update-feeds.yml) 在 `master` 的
`update/stable/*.xml`、`update/beta/*.xml` 或對應 `metadata.json`／`.sig` 變更後觸發；工作分支／PR 只做驗證，不部署。Windows beta 原生驗證已整合在同一 workflow，不另設發布 workflow。
發布沿用受保護的 `release` environment 與 AWS OIDC role；若 environment 設定人工
核准，仍需維護者核准該 job，不繞過現有發布規則。

每次同步已驗證 master snapshot 的 stable／beta 全部頂層 XML 與 signed metadata，對應位置為
`update/CHANNEL/FILE.xml` → `s3://AWS_RELEASE_MIRROR_BUCKET/keykey/update/CHANNEL/FILE.xml`，
公開網址為 `AWS_RELEASE_MIRROR_BASE_URL/keykey/update/CHANNEL/FILE.xml`。
`CHANNEL` 僅接受 `stable`／`beta`；兩者先完整驗證，再開始任何上傳。
stable XML 拒絕 beta 比較版號、顯示版號或 beta tag 安裝包網址，避免誤投放。
發布使用原生驗證所對應的同一 commit，並在發布前確認仍為目前 master；舊的等待核准／重跑執行若已過時就失敗，請執行最新 master，不讓舊驗證套用到新 snapshot 或將 CDN 回滾。發布串行化，Actions summary 記錄實際 commit 與 CDN 連結。

工具先驗證所有 XML／RSS、安全檔名與 metadata 的正式公鑰簽章，自動安裝 XML 必須完全對應 signed metadata。再下載 SHA-256 副本驗證大小、雜湊及安裝包 Ed25519 簽章；副本尚未上線或被竄改時，禁止任何 CDN 寫入。通過後上傳相同 bytes，以 SHA-256 與 S3 回讀比對，
設定 `application/rss+xml; charset=utf-8` 和
`public,max-age=0,s-maxage=60,must-revalidate`（JSON／signature 使用各自 content type）。最後只 invalidate 精確 feed／metadata 路徑，等待完成，
再比對 CDN 回傳內容；上傳、驗證或 cache invalidation 失敗會讓 job 失敗。
多份 feed 不是原子交易，部分上傳後失敗可重新執行同步；S3 versioning 保留舊版本供維護者恢復。

預設同步入口只鏡像已 review 的 XML 與 `metadata.json`／`.sig`，不產生新版本、簽章或 installer，不修改 Git、不刪除 CDN 檔案。移除 repository 檔案不會刪除遠端 feed；停用更新可
改為無 item 的 RSS 再提交。增加手動下載連結不代表已啟用客戶端自動更新。

首次使用需先 review／merge 並依 [Terraform 流程](../terraform/infra/README.md) plan／apply
新增的 XML／精確 metadata 路徑寫入權限、CloudFront `GetInvalidation` 權限與獨立短快取 behavior。
原 Release 安裝包的長快取與權限保持不變；本次程式開發不執行 Terraform apply 或線上上傳。
沿用 `release` environment 的現有 `AWS_ACCOUNT_ID` 與 `AWS_RELEASE_MIRROR_*` variables，
不新增 AWS 長期金鑰。完成基礎設施部署後，可在 Actions 選擇此 workflow、`master`、
**Run workflow** 補同步兩個 channel 的八份初始 feed；後續 XML 變更會觸發同步。

本機唯讀／隔離驗證：

```sh
python3 .github/scripts/sync-update-feeds.py --check-only
python3 -m unittest discover -s .github/scripts -p test_sync_update_feeds.py -v
# 僅驗證 beta 目錄，不發出 AWS 請求
python3 .github/scripts/sync-update-feeds.py --channel beta --directory update/beta --check-only
# 另下載安裝包副本並驗證 Ed25519；仍不寫 GitHub／AWS
python3 .github/scripts/sync-update-feeds.py --check-only --verify-assets
```

### 已發布 beta 的 SHA-256 副本（兩階段審查）

保留 `metadata.py` 的內容位址方案，新增 `KeyKey-VERSION-TARGET-SHA256.pkg.zip`／`.exe`；內容與既有 beta 安裝包逐 byte 相同，不重新打包或重簽平台憑證。原檔、tag、Pre-release 與 Latest 不變。

1. 先 review／merge 副本工具與頻道選項 PR。不要將尚不存在的副本網址當成可部署 feed。
2. 在同一 `Sync Update Feeds to CDN` 的 **Run workflow** 選擇 `master`、`operation=stage-beta-assets`，按既有 `release` environment 規則核准。這個入口只接受 master 手動執行；工作分支／PR 不取得寫入權限。
3. Windows job 先對既有 EXE 原生驗證。macOS job 驗證同一次 run／revision 的公開報告，實際檢查 pkg 的 Gatekeeper、公證票證與 beta 版號，再下載並新增副本。GitHub 不使用 `--clobber`；S3 使用 `If-None-Match: *`，已存在物件只回讀確認，差異或權限錯誤一律停止。
4. GitHub／S3／CDN 副本雜湊與大小全部確認後，請 AI 使用受保護的既有更新私鑰準備 signed metadata／appcasts、建立第二份 feed PR。私鑰不在 Git 或 artifact。你 review／merge master 後，才由預設同步入口部署 feed／metadata。

Windows x86 ZIP 只公告手動下載；Linux 仍透過套件管理器安裝。Linux／FreeBSD 共用 Unix feed 並同步公告，不延後 FreeBSD 通知；不檢查 ports/pkg 是否已上架，並揭露可能尚不可用，不新增自動排程。

## 發布版本與隔離的更新來源

正式版 tag 使用 `vX.Y.Z`，測試頻道使用 `vX.Y.Z-betaN`；
X.Y.Z 為對應平台的產品版號，N 是不含前導零的正整數。
產品原始碼保持 X.Y.Z，不連帶修改其他平台版號。
測試頻道的 GitHub Release 必須標記 **Pre-release**，不改 Latest；
正式 `vX.Y.Z` 不接受 Pre-release 標記。工具只上傳已存在 Release 的資產，
不建立／編輯 Release。
beta 的手動重跑也必須選該 tag 的 commit，不提供同版 recovery 替換。

| 用途 | 正式版 | 測試頻道 |
|---|---|---|
| GitHub tag／顯示更新版號 | `vX.Y.Z`／`X.Y.Z` | `vX.Y.Z-betaN`／`X.Y.Z-betaN` |
| 原生比較版號 | `X.Y.Z` | `X.Y.ZbN` |
| metadata channel／XML 目錄 | `stable`／`update/stable/` | `beta`／`update/beta/` |

原生排序須通過 SDK 測試：同產品版號的測試頻道按 N 的數值遞增，正式版高於所有測試版本。
macOS 在簽章前將建置後 IMK App 的 `CFBundleVersion` 設為比較版號，
`KeyKeyReleaseVersion` 設為顯示版號；`CFBundleShortVersionString` 及四份原始碼 plist
仍保持產品 X.Y.Z。pkg 的 PackageInfo 版號跟隨比較版號，notarization 驗證不放寬。
Windows PE／Deployment 產品版號保持 X.Y.Z；Settings 內嵌 beta 更新設定並把比較
版號交給 WinSparkle。使用者選擇 beta 時使用獨立 registry 更新偏好，不改 stable 的連網同意／跳過版本；不由已安裝版本的 beta 後綴代替使用者選擇。
既有 GitHub 下載檔名仍含產品 X.Y.Z，各次測試建置放在各自不同的 tag 下載目錄；
簽章更新候選檔名則含完整 beta 版號及 SHA-256。

建置 workflow 用 `prepare.py select-release` 產生暫存設定（不改 tracked config）：
設定保留 stable／beta 兩組已審查網址，另記錄 tag 來源及 `channel_selection=user-opt-in`。
macOS／Windows 的「接收 beta 測試版更新」預設關閉，beta 建置也不自動開啟；使用者選擇會保存。只允許這兩個建置時固定的來源，不能任填網址。缺少所選 beta URL 時保持離線，不回退 stable。公開金鑰共用，對應的 XML 網址為：

```text
https://download.aws.polobread.com/keykey/update/beta/macos-arm64.xml
https://download.aws.polobread.com/keykey/update/beta/windows-x64.xml
https://download.aws.polobread.com/keykey/update/beta/windows-x86.xml
```

若選 GitHub Raw，路徑為 `https://raw.githubusercontent.com/polobread/KeyKey/master/update/beta/FILE.xml`。
首次使用測試頻道需手動安裝含新設定的版本，不能只改遠端 XML 就把 stable 客戶端切成 beta。
beta feed 只接受 beta manifest。取消 beta 只更換檢查來源，不會自動降版；需等 stable 發布更高版號，或自行手動安裝。
Windows 目前仍使用既有 unsigned EXE；真實 beta 升級須在 Windows 驗收。
日後 signed beta 還須調整 Deployment 的「同產品版號不同 official build」保護，
不能從 WinSparkle 版號比較通過推定同產品版號的 signed 測試版本互相升級已支援。

測試頻道的發布 manifest 將 `channel` 設為 `beta`，entry 的 `version` 為 `X.Y.Z-betaN`、
`release_tag` 為 `vX.Y.Z-betaN`；同樣要求 source/tag commit 相等、平台簽章與
不可變資產。`metadata.py build` 回傳 beta metadata，appcast 的比較版號為 `X.Y.ZbN`。
輸出平台 XML 經 review 後只放 `update/beta/`，包先上傳並驗證，才提升 feed。
macOS stable 在原包發布成功後自動準備公告 PR；beta 候選仍須另外驗證及審查，不會由穩定版流程發布。

本機選擇發布設定與版本標記（以下以正式產品版號為例，只供建置，不安裝；測試頻道套用上表的 tag 規則）：

```sh
python3 update/prepare.py select-release --tag v1.3.2 --version 1.3.2 \
  --out update/out/release-build-config.json
export KEYKEY_UPDATE_CONFIG="$PWD/update/out/release-build-config.json"
# 接既有 macOS／Windows 建置；macOS 在 build 後、簽章前另執行：
python3 update/prepare.py stamp-macos "Source/build/Release/chichi77 KeyKey.app"
```

`Desktop Release Tools` PR workflow 只跑共用工具、隔離 macOS 測試及 Windows x64
updater 測試，不建置 TSF、不安裝、不發布、不取得 release secret。

## 正式金鑰與網址設定（需維護者審查）

`config.json` 使用維護者提供的 32-byte base64 Ed25519 公鑰。
公鑰原始 bytes 的 SHA-256 為
`abbbf302de90de80897a16e275dcf8db199509bc908bfe432d917f1222d9f273`。
私鑰配對與受保護的 CI secret 須由維護者另行確認。
兩個頻道的各平台 CDN feed 網址設定於 `config.json`；發布時須確認可下載性。
每週檢查預設開啟，beta 頻道仍需明確選擇；未設定或無效的公鑰／所選 feed 仍保持離線。

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
   增加平台子目錄，也不將不同平台合併成同一份 XML。Windows x64 feed 與 signed metadata
   一起經 PR 審查，合併後再同步至 CDN：

   ```text
   https://download.aws.polobread.com/keykey/update/stable/
     macos-arm64.xml
     windows-x64.xml
     windows-x86.xml
     metadata.json
     metadata.json.sig
   ```

   `windows-x86.xml` 目前提供無自動更新項目的 RSS；建立並驗證正式 x86 installer 後，
   才加入自動安裝項目；目前已設定 x86 feed URL，仍只提供手動 ZIP 下載資訊。
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

`update/stable/windows-x64.xml` 提供 Windows 1.3.7 的自動更新項目，指向已通過
Certum Authenticode 與 Ed25519 驗證的內容位址 EXE。`metadata.json` 與
`metadata.json.sig` 保留本機簽包時的原始 bytes；版本、tag 與建置來源一致。
`windows-x86.xml` 提供 1.3.7 已簽署 ZIP 的 CDN／GitHub 手動下載連結，
仍無 `item`／`enclosure`，不會自動下載或安裝 x86 ZIP。
客戶端目前使用單一 feed URL，尚未實作來源自動切換。
使用者 review 並將 feed PR 合併至 `master` 後，Raw 網址才會更新；CDN 由
`Sync Update Feeds to CDN` 驗證遠端安裝包後同步。若以 `[skip ci]` 避免重跑
建置，合併後須在 `master` 手動執行該 workflow 的 `sync-feeds` 操作。
正式公鑰與兩個 channel 的 CDN feed 設定已加入原始碼；既有安裝版本須另行核對是否包含這些設定。

v1.3.1 的 GitHub Release 尚無 x86 EXE 或安裝包 Ed25519 更新簽章；其 Windows
build-info 的 `source_sha` 與 `tag_sha` 不同，屬既有同版 recovery 下載資產。
這批檔案可供手動下載，但不直接通過現有 stable 自動更新的來源驗證。
後續自動更新需另有符合 review／tag／版本規則、已完成 Ed25519 簽章的安裝器。

Windows 1.3.7 的 GitHub Raw 與 CDN 提供同一份 feed，安裝包網址固定指向 CDN。
現有 metadata 簽章包含下載網址，沿用簽包時須保留原始 bytes；Raw 目前只提供 feed
備份，安裝包下載仍依賴 CDN。日後若提供獨立的 GitHub 安裝包來源 feed，須為該網址
另行產生並簽署 metadata，先驗證遠端安裝包，再發布該來源的 feed。
各來源必須使用同一組 Ed25519 金鑰與已通過所宣告簽章模式驗證的安裝包，
版本、檔案內容／SHA-256 及安裝包簽章均須一致。

GitHub feed 變更在工作分支提交，再由使用者 review／merge 至 `master`，不得由
workflow 直接回存 `master`。CDN feed 使用短快取及精確 invalidation。現有 metadata
工具可針對不同 `--base-url` 產生兩份輸出；XML CDN 鏡像已接入獨立 workflow，
但兩套安裝包／feed 的發布協調尚未自動化；
Windows 客戶端也仍只接受單一 feed URL，來源設定與失敗切換功能尚待實作。

## 產生與驗證更新資料

Windows 的共用 PowerShell 在 Actions 建置、測試並產生待簽 artifact；Authenticode、重新封裝與 Ed25519 在本機完成，其他平台流程不變。
先依 [Windows 本機發布指南](../docs/WINDOWS_CERTUM_RELEASE.md) 完成 EXE 與已簽 x64／x86 ZIP，
再使用 `Source/Loaders/Windows-TSF/Prepare-WindowsUpdate.ps1` 準備 Windows 單平台更新資料。
指定私鑰為 `keykey-update-private.pem`，僅交給本機密碼工具使用；禁止 commit／stage、上傳、顯示內容或放進 artifact。
Windows 包裝器拒絕已追蹤私鑰並抑制簽章工具診斷；正式公鑰比對仍由 `metadata.py` 執行。
feed 維持獨立 PR，由維護者 review／merge 後才同步 CDN。

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

多平台彙整時，macOS 使用受保護的更新公告 workflow；Windows 在本機執行 `metadata.py attest --manifest ... --key ... --out ...`。
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

### 既有 Windows unsigned 過渡版本的相容驗證

新的 Windows 本機正式發布只產生已簽版本。以下規格保留給既有 unsigned 過渡資產的驗證，
不再提供新的 unsigned 發布流程；歷史 stable 過渡版本使用 unsigned EXE。
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

## Linux／FreeBSD 共用 CDN feed

固定網址：

- `https://download.aws.polobread.com/keykey/update/stable/unix-fcitx5.xml`
- 勾選 beta 後，另外讀取 `https://download.aws.polobread.com/keykey/update/beta/unix-fcitx5.xml`

每週檢查、失敗節流與使用者既有關閉設定保持一致；手動檢查可提前執行。
Linux／FreeBSD 共用同一公告，同步通知，不延後 FreeBSD。FreeBSD 始終提示透過
ports／pkg 更新、套件可能較晚上架，不查套件庫，也不增加排程。
新版客戶端只讀這些固定 CDN URL；開啟下載頁仍使用該版本的官方 GitHub Release。
發行頁及 RSS description 可以同時列出 CDN／GitHub 下載連結。
舊版客戶端仍查 GitHub API，必須安裝含新 reader 的版本才會切換。

stable feed 已加入 1.3.7 公告，對應已驗證的 Ubuntu 24.04 amd64 套件與共用詞庫；
GitHub／CDN 副本的大小、SHA-256、套件版本及架構均已核對。尚未驗證 arm64 套件，
因此 Linux 只向 amd64 使用者公告；FreeBSD 使用相同 item，同步通知並提示 ports／pkg
套件可能較晚上架。beta feed 目前沒有 item。
公告須經 PR 合併並完成 CDN 同步後才生效。此 feed 只通知並開啟下載頁，
不提供 installer `enclosure` 或自動安裝。
同步工具使用與客戶端相同的 XML 驗證，不改變既有 macOS／Windows signed metadata 規則。
既有 Terraform 的 `keykey/update/CHANNEL/*.xml` 權限與短快取已涵蓋新路徑。

發布流程：

1. Linux Release 的建置、套件生命週期及發布 jobs 完成後，取得正式套件、`SHA256SUMS`
   與 build-info，校驗套件大小／SHA-256、版本、架構與 CDN／GitHub 副本。
   同時核對該 tag 的 Unix CMake 產品版號，排除只更新行動平台的 tag。
2. 正式 Release 驗證成功後自動準備 stable feed PR；beta 與特殊補救請 AI 手動準備。
   只宣告已驗證的 Linux 架構，同一 item 也公告 FreeBSD。
   每個版本只能有一個 item，stable 不接受 beta；beta 顯示 `X.Y.Z-betaN`，比較版號為 `X.Y.ZbN`。
3. PR 需附套件驗證證據並由維護者 review／merge；準備流程只寫工作分支，不直接回存 master。
4. 合併 master 後沿用 `Sync Update Feeds to CDN`，上傳、回讀比對、精確 invalidation 及 CDN bytes
   驗證。客戶端下次每週／手動檢查便讀取公告。Linux 下載後透過套件管理器安裝；FreeBSD 走 ports/pkg。

**Linux stable 自動準備：** `Prepare Linux Stable Update` 在正式 Release 的 `Linux CI`
全部成功後執行。只使用已 review 的 `master` 工具，核對官方工作與 run attempt、
成功的 Ubuntu 24.04 套件生命週期／X11、Ubuntu 22.04 最低 API 與發布 jobs；
再驗證 tag/source、tag 內的 Linux CMake 版號、Release digest、`SHA256SUMS`、
build-info、DEB control 版本／架構，以及 GitHub／CDN 的相同 bytes。目前只宣告
Ubuntu 24.04 amd64；FreeBSD 同一公告始終提示 ports／pkg 更新與套件可能較晚上架。
這是通知與下載頁入口，不產生安裝包簽章，也不需要更新私鑰。

驗證通過後保存公開候選檔與驗證清單 artifact（7 天），建立
`codex/linux-update-vX.Y.Z` 分支，只提交 `update/stable/unix-fcitx5.xml` 並開 PR。
不修改 macOS／Windows metadata、不合併 PR 或直接部署 CDN。已公告同版則不重複建立，
不允許降版；既有同版分支不覆寫。若準備期間 master 前進，會停止並要求重跑。
Actions 的建立 PR 權限需開啟；review／merge 仍由維護者完成。

手動重跑時，在 Actions 選 `Prepare Linux Stable Update`、使用 `master`，填入已發布的
`release_tag=vX.Y.Z`。此入口仍要求原官方發布工作與必要 gates 全部成功，且 source 等於 tag；
不接受 beta、artifact-only、失敗／取消的發布工作或 tag 後的同版重建。這類特殊補救需另附
驗收證據，請 AI 手動準備 PR，不由此自動流程放行。新 workflow 合併後的下一次正式發布
才會自動觸發，不會因合併本工具而重新發布現有安裝包或公告。

以下僅為格式範例，不表示該版本已驗證或可發布：

```xml
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:keykey="urn:chichi77:keykey:update:1">
  <channel>
    <title>琦琦輸入法 Linux／FreeBSD 更新通知</title>
    <link>https://github.com/polobread/KeyKey/releases</link>
    <keykey:schemaVersion>1</keykey:schemaVersion>
    <item>
      <title>琦琦輸入法 1.3.2</title>
      <sparkle:version>1.3.2</sparkle:version>
      <sparkle:shortVersionString>1.3.2</sparkle:shortVersionString>
      <link>https://github.com/polobread/KeyKey/releases/tag/v1.3.2</link>
      <keykey:linuxArchitecture>amd64</keykey:linuxArchitecture>
      <description>Linux 請透過套件管理器安裝；FreeBSD 請透過 ports/pkg 更新，套件可能較晚上架。</description>
    </item>
  </channel>
</rss>
```

同時驗證 arm64 套件後才可另加 `<keykey:linuxArchitecture>arm64</keykey:linuxArchitecture>`。
`link` 必須是該版本的官方 Release，版本、頻道或架構不一致及 DTD／entities 一律拒絕。
`--check-only` 檢查格式與同步範圍；Unix 的套件完成與校驗證據仍需在 feed PR 審查，不能用 XML 通過代替套件驗證。

## GitHub Release／CDN 發布順序（安裝包先發布，再同步 feed）

1. 通過原始碼 review。Windows 的共用 PowerShell 由 Actions 測試並產生 unsigned
   artifact，再依 [Certum 本機簽包流程](../docs/WINDOWS_CERTUM_RELEASE.md)完成
   Authenticode、時間戳記、重新封裝與 Ed25519。核對 CI、release tag 與簽包來源，
   完成安裝驗收並取得人工發布核准後，沿用這批產物發布。
2. 上傳 `packages/` 的内容位址檔案到指定 Release；不使用 `--clobber`。
   base URL 使用 GitHub 時填 `https://github.com/OWNER/REPO/releases/download`。
3. CDN 模式先將相同 bytes 鏡像到 `keykey/releases/download/TAG/FILE`；校驗遠端可取得、
   size 與 SHA-256 正確後，最後才更新固定 feed。GitHub Releases 可放不可變資產，
   固定 feed 另外放在 CDN／靜態網站，不能把 GitHub Release API 當 appcast。
4. packages 使用長快取；feeds／metadata 使用短 TTL 與精確 invalidation。
   feed、metadata 與其簽章經 PR 合併至 `master` 後，由既有同步 workflow 上傳。
   `[skip ci]` 的 PR 合併後須手動執行 `sync-feeds`，不重新建置或簽署安裝包。
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
隔離個人資料；這組 WPF 回歸不執行 WinSparkle 下載或安裝。另行完成的本機真實升級範圍見下節。

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

### Windows 本機真實安裝與升級驗證

已在 Windows x64 完成同包重新安裝，以及已安裝 1.3.2 升至本機測試版 1.3.3。
升級案例重新編譯 x64／x86 TSF、設定與部署所需元件，確認安裝器及產品版號一致；
隔離入口使用實際已安裝版號、正式 `WinSparkleBackend` 與固定版本 WinSparkle DLL，
由 loopback feed 提供臨時 Ed25519 金鑰簽署的真實 unsigned NSIS 安裝包。
下載及簽章驗證後沿用原生安裝器啟動流程，由使用者核准 UAC 並完成安裝精靈。

安裝後核對 17 個 payload 檔案雜湊、x64／x86 COM 註冊、移除入口及設定頁版號；
12 個個人設定／詞庫檔案在升級前後完全相同，舊版目錄保留，沒有未完成部署交易。
升級後重新查詢相同 feed 回報無更新，沒有重複下載。測試入口、金鑰、feed 及執行資料
屬本機產物，不納入 Git；正式 `config.json`、stable／beta feed 與來源產品版號未變更。

此結果證明隔離原生更新入口至真實安裝器的本機升級路徑；尚未涵蓋已安裝設定程式
透過正式 HTTPS feed 的完整流程、正式金鑰／Authenticode、取消 UAC、安裝失敗、
多帳號及登出後文字宿主載入新版 DLL 的驗收，不能代替正式發布矩陣。
