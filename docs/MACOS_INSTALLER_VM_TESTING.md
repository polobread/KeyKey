# macOS 安裝程式的 VM 建置與驗收

修改安裝 helper、安裝腳本、Distribution 或封裝腳本後，依 [AGENTS.md](../AGENTS.md#macos-安裝程式的-vm-實測) 實測三條安裝路徑。僅修改 GitHub Actions workflow 時，不額外要求 VM；按 workflow 的實際變更做相應檢查。純文件更新不重跑安裝。

## 快照 a／b 代表什麼

| 基準 | 內容 | 用途 |
| --- | --- | --- |
| 快照 a：乾淨系統 | macOS 首次設定完成，已補正確中文字型；未安裝 KeyKey，沒有其 receipt、偏好與使用者資料；沒有 Rosetta。 | 全新安裝最新版。 |
| 快照 b：舊版可用系統 | 從 a 建立工作 VM，先裝正式 1.3.1，再升到正式 1.3.7；保留正式 feed／公鑰，琦琦已啟用且中文可用。 | 分別測手動 PKG 升級，以及從舊版程式內自動更新。 |

這裡的「快照」是 **正常關機後，以 Tart clone 保存的磁碟與組態基準**，不是執行中的記憶體快照。兩份基準保持關機，每次測試另建工作副本；不直接在基準安裝新包，也不用解除安裝來假裝回到乾淨狀態。

目前本機可重用的基準名稱是：

- a：`keykey-snapshot-clean-fonts-15-6-1-20261028`
- b：`keykey-snapshot-137-ready-15-6-1-20261028`

另保留未補字型的 `keykey-snapshot-clean-15-6-1-20261027`，只供缺字型問題重現；它不是正常安裝驗收所用的 a。名稱只是本機標籤，以環境檢查與保存的來源紀錄確認內容。重用既有基準時，`TART_HOME` 必須指向該輪紀錄的原儲存目錄；下方新建範例使用另一個 lab，不能只複製 VM 名稱就找到既有磁碟。

## 1. 準備 Tart 與固定的 macOS 映像

主機使用 Apple Silicon，VM 檔案放在有足夠空間的 APFS 磁碟。Tart 使用 Apple Virtualization.framework；本流程以本機已驗證的 Tart **2.41.1** 為例，命令可與 `tart --help` 核對。安裝方式與 IPSW 建立 VM 的介面見 [Tart 官方說明](https://tart.run/quick-start/)，固定版本下載見 [2.41.1 Release](https://github.com/openai/tart/releases/tag/2.41.1)。

以下指令在 **主機、儲存庫根目錄** 執行。使用獨立的 `TART_HOME`，避免混用其他 VM；關閉自動清理，保留基準：

```sh
vm_lab="$PWD/Installer/local-builds/macos-vm-lab"
mkdir -p "$vm_lab/tools" "$vm_lab/share" "$vm_lab/evidence"
export TART_HOME="$vm_lab/tart-home"
export TART_NO_AUTO_PRUNE=1
vm_tart="$vm_lab/tools/tart.app/Contents/MacOS/tart"
```

從固定 Release 取得 `tart.tar.gz`，核對該 Release 公布的 SHA-256，解壓縮至 `tools/`。保留整個 `tart.app`，透過上述 bundle 內的執行檔執行；不要只搬出單一 binary。記錄實際版本：

```sh
"$vm_tart" --version
```

目前 a／b 使用的是 Apple 官方 **macOS 15.6.1（24G90）UniversalMac restore IPSW**，不是先前嘗試下載的約 25 GB OCI 預製 VM。固定來源為：

[UniversalMac_15.6.1_24G90_Restore.ipsw（Apple CDN）](https://updates.cdn-apple.com/2025SummerFCS/fullrestores/093-10809/CFD6DD38-DAF0-40DA-854F-31AAD1294C6F/UniversalMac_15.6.1_24G90_Restore.ipsw)

該檔為 16,814,137,790 bytes。下載後保存檔案 SHA-256、URL、檔案大小及還原後的 `sw_vers`；不以會變動的 `latest` 宣稱重現同一環境。IPSW、Tart、VM 磁碟和測試包都留在忽略的本地產物目錄，不提交到 Git。

```sh
shasum -a 256 "$vm_lab/UniversalMac_15.6.1_24G90_Restore.ipsw"
"$vm_tart" create keykey-clean-setup \
  --from-ipsw "$vm_lab/UniversalMac_15.6.1_24G90_Restore.ipsw" \
  --disk-size 64
"$vm_tart" set keykey-clean-setup --cpu 4 --memory 8192 \
  --display 1280x900 --no-display-refit
"$vm_tart" run --no-audio --no-clipboard --no-usb-accessories \
  --dir="fixtures:$vm_lab/share:ro" keykey-clean-setup
```

本機參考配置為 4 CPU、8 GiB RAM、64 GB 虛擬磁碟。APFS clone 共用未變動區塊，後續 VM 寫入仍會增加實際占用；保留足夠磁碟空間。

在 **VM** 完成首次設定，選定測試語言與鍵盤，建立專用管理員帳號（例如 `keykeytest`）。授權條款與新帳號密碼由使用者本人確認與輸入。保留正常登入與密碼要求，不為了自動化啟用自動登入、免密碼 sudo 或移除鎖定。

## 2. 先補字型，再保存快照 a

乾淨 VM 能顯示中文，不代表 KeyKey 需要的字型存在。目前 [CVEncodingService](../Source/Loaders/OSX-IMK/CVEncodingService.mm) 先要求 `STHeiti`，找不到時改用其他字型做字元支援判斷，可能排除詞庫本來有的常用字。因此「台北」能打出來還不足以排除缺字型問題。

在 **VM 內** 操作：

1. 開啟「字體簿」，下載 Apple 提供的相應字型；若已有 Apple 提供且可使用的 `STHEITI.ttf`，可經唯讀共享資料夾帶入，在 VM 內連按兩下安裝到測試帳號。
2. 在字型資訊核對 **PostScript 名稱必須是 `STHeiti`**。`STHeitiTC-Light`、`STHeitiSC-Light` 與 Medium 等相近名稱不能代替。不要只改檔名或複製 Light／Medium `.ttc` 就判定補齊。
3. 使用「字體簿」驗證並啟用字型，記錄來源、PostScript 名稱與實際字型檔 SHA-256。主機裝好字型不會自動補到 guest。
4. 在尚未安裝 KeyKey 的情況下，正常登出再登入，確認字型仍啟用。缺少檔案時，單純登出或重開機不會補上字型。

字型的下載、安裝與驗證介面見 [Apple 字體簿手冊](https://support.apple.com/zh-tw/guide/font-book/fntbk1000/mac)。現有基準 a 的字型位於測試使用者 `~/Library/Fonts/STHEITI.ttf`，PostScript 名稱為 `STHeiti`，SHA-256 為 `86778e228eb5412b033156c78787c46be51f7f9d8dc72173233516de3c9e3400`。這個 hash 只識別現有基準的檔案，不要求其他 Apple 字型版本具有相同 hash。字型不隨專案或測試包再散布。

在 **VM 終端機** 核對乾淨狀態並保存結果：

```sh
sw_vers
uname -m
test ! -e "/Library/Input Methods/chichi77 KeyKey.app"
pkgutil --pkgs | /usr/bin/grep -Ei 'keykey|chichi'
test ! -e /Library/Apple/usr/libexec/oah/libRosettaRuntime
```

receipt 查詢應沒有匹配（grep 在沒有匹配時回傳 1）；另確認沒有先前 KeyKey 偏好或使用者資料。字型補齊後也不要先安裝 KeyKey 來「測乾淨系統」。

從 VM 的 Apple 選單正常關機，等待主機 `tart list` 顯示 `stopped`，再在 **主機** 保存 a：

```sh
"$vm_tart" list
"$vm_tart" clone keykey-clean-setup keykey-snapshot-a-clean-fonts
```

若已存在較早、未補字型的 a，先從它建立工作副本，只補字型並關機，再以新名稱保存；保留原始無字型基準，不直接覆寫。

## 3. 建立快照 b：正式 1.3.1 → 1.3.7

在 **主機** 從 a 建立舊版安裝用的工作 VM：

```sh
"$vm_tart" clone keykey-snapshot-a-clean-fonts keykey-baseline-setup
"$vm_tart" run --no-audio --no-clipboard --no-usb-accessories \
  --dir="fixtures:$vm_lab/share:ro" keykey-baseline-setup
```

從官方 [1.3.1 Release](https://github.com/polobread/KeyKey/releases/tag/v1.3.1) 與 [1.3.7 Release](https://github.com/polobread/KeyKey/releases/tag/v1.3.7) 下載原始 Apple Silicon 安裝包，保存來源、SHA-256 與簽章檢查。順序固定為：

1. 在 VM 全新安裝正式 1.3.1，依需要正常重新登入、從鍵盤設定加入琦琦，實際試打。
2. 升級安裝正式 1.3.7，核對 App 與 receipt 皆為 1.3.7。
3. 保留原琦琦項目，選回並以實體按鍵測「你好」、「哈囉」、「台北」及一句較長的中文；確認組字、候選、數字選字與 Return 提交。不要用貼上中文代替輸入。
4. 確認正式更新 feed／公鑰沒有改成 localhost，沒有測試憑證信任或正在跑的更新 server。
5. 正常關機，在主機確認 `stopped`，保存 b。

```sh
"$vm_tart" clone keykey-baseline-setup keykey-snapshot-b-137-ready
```

**舊安裝包的已知限制：** 正式 1.3.1／1.3.7 的 full Distribution 在沒有 Rosetta 的 VM 仍可能要求 Rosetta，雖然產品 payload 為 arm64。現有 b 使用原始官方 component payload／scripts 依序建立，沒有安裝 Rosetta；這是準備舊版 runtime 的 fixture，不代表舊 GUI wrapper 已通過驗收。

需重做這個 fixture 時，在 **主機的本地產物目錄** 用 `pkgutil --expand` 展開官方 product PKG，再用 `pkgutil --flatten` 將其中 `chichi77KeyKeyApp.pkg` 目錄另存為 component PKG。核對重新展開後的 `Payload`、`Bom`、`PackageInfo` 及存在的 `Scripts` 與原始內容一致，記錄原 product／新 component 的 hash，再只在工作 VM 內依序安裝。此處不修改 app、安裝腳本或版號，不把重封裝的 fixture 當成官方原包或對外發布。

如果新版候選包仍要求 Rosetta，記錄並停止該次驗收，不用先安裝 Rosetta 掩蓋問題。

## 4. 從 a／b 建立三台工作 VM

確認基準為 `stopped`，在 **主機** 執行：

```sh
"$vm_tart" clone keykey-snapshot-a-clean-fonts keykey-case-fresh
"$vm_tart" clone keykey-snapshot-b-137-ready keykey-case-manual
"$vm_tart" clone keykey-snapshot-b-137-ready keykey-case-auto
```

已有同名工作 VM 時，保留證據並另取新名稱；不要用 `--overwrite` 蓋掉基準或前一次失敗環境。依序啟動，避免同時占用太多記憶體：

```sh
"$vm_tart" run --no-audio --no-clipboard --no-usb-accessories \
  --dir="package:$vm_lab/share:ro" keykey-case-fresh
```

官方共享介面會將此目錄掛在 guest 的 `/Volumes/My Shared Files/package`。將要測的 PKG／ZIP 與校驗檔放在主機 `share/`，guest 核對檔案 hash；這裡的共享方式見 [Tart 官方文件](https://tart.run/quick-start/#mounting-directories)。不要把整個主機家目錄或憑證目錄掛進 guest。

「還原 a／b」就是結束該工作 VM、保留測試紀錄，再從相應基準 clone 新工作 VM。基準本身不啟動、不做自動更新、不移除軟體。Tart clone 在 APFS 上使用 copy-on-write；本流程仍要求先正常關機，不以暫停中的記憶體狀態作安裝基準。

## 5. 三條驗收路徑

| 情境 | 操作 | 必須核對 |
| --- | --- | --- |
| 全新安裝 | 從 a 啟動，安裝最新版完整 PKG；正常登出再登入、首次加入琦琦。 | 沒有不必要的升級前檢查與 Rosetta 提示；固定路徑落地；版本正確；可實際輸入。 |
| 手動升級 | 從 b 啟動，先確認 1.3.7 可輸入，從 GitHub 取得最新版或明確標示本地候選包，開啟完整 PKG 安裝。 | 舊作用中行程正常退出；保留原輸入法項目；新版實際啟動且可輸入。 |
| 程式內更新 | 從另一份 b 啟動，在 1.3.7 偏好設定檢查更新，依序下載、驗章、管理員授權、安裝並重新啟動。 | 記錄 Sparkle 與真正 installer 日誌、已安裝 App／receipt 版本；選回後可輸入；不能用 CLI 安裝代替。 |

兩個升級情境保留舊來源，不以先移除再重加來讓測試通過。安裝後先選 ABC，再選琦琦試打；安裝完成後統一正常登出再登入，記錄登入畫面是否完整顯示與實際結果。記錄 `sysctl kern.boottime`，區分「只有登出登入」與「重新開機」；不要直接重開機而漏掉原本的失敗情境。

實際輸入驗收涵蓋組字底線、開候選、數字選字、Return 提交及下一段輸入。至少測「你好」、「哈囉」、「台北」、「請假要去哪裡玩呢去海邊」。截圖保留按鍵與候選狀態；首次立即輸入與穩定後重測分開記錄，異常不得因後續重測通過而刪除。

CLI `installer -pkg ... -target /` 可作直接安裝與診斷證據，但須標示是 CLI；不能聲稱 GUI 授權頁或程式內更新因此也已通過。原包、component bootstrap、未公證本地候選與正式發布包分別記錄。

## 6. 未發布版本的程式內更新 fixture

正式 feed 還沒有候選版時，只在 **case-auto 工作 VM** 建立本地測試來源：

1. 使用實際舊版 runtime，只修改測試副本的 feed／公鑰並依原簽章流程重簽。保持與原產品相同的 Developer ID／designated requirement，不修改舊版更新邏輯。套件／App 的深層簽章與 framework symlink 也要核對。
2. 使用專用測試 Ed25519 金鑰簽署候選 ZIP，feed 的版號、URL、長度、簽章與檔案 hash 相符。正常情況直接用比 1.3.7 新的候選版；需測「同一版本互升」時，才另外建更高的本地假版號，不能發布至正式 feed。
3. HTTPS server 放在 guest 本地磁碟，僅監聽 `127.0.0.1`。共享資料夾只用於搬入 fixture；不要一邊從主機覆寫 feed，一邊讓 guest server 從 virtiofs 讀，避免讀到舊資料或不完整內容。
4. 如需 localhost 短期憑證，先確認用途、到期日及只在該工作 VM 使用，取得信任授權；只允許 SSL／localhost。不信任到主機，不把測試根憑證放進 a／b，不關閉 TLS 或簽章驗證。
5. 用 guest 原生 `/usr/bin/nscurl` 確認取得正確 XML，且沒有 TLS 錯誤；不能只看 exit code。再從 1.3.7 的真實 UI 下載與安裝，保存 EdDSA 成功、installer 結果、版本及實際輸入證據。
6. 停止測試 server，正常關機保存結果。官方 feed／CDN、正式資產與 a／b 不變；本地 fixture 結果不能直接當作正式網路來源的驗收。

部分舊版更新視窗會被浮動偏好設定或其他 App 遮住。記錄後關閉／縮小遮擋視窗再操作；不能因看不到視窗就認定 installer 沒有執行，也不能宣稱新包已追溯修正舊 runtime 的 UI。

## 7. 證據、故障保存與測試邊界

每輪記錄來源 commit、是否含未提交差異、封裝工具與命令、PKG／ZIP SHA-256、四份產品 plist 版本、架構與簽章模式。三條路徑用與最終提交來源相同的同一份目標安裝包；不能把「含額外本地修正」的成功直接填成 PR 相同來源已通過。

下列唯讀命令只在 **VM 終端機** 執行；將輸出保存到該輪證據目錄：

```sh
sw_vers
sysctl kern.boottime
pkgutil --pkg-info io.github.polobread.chichi77.installerpackage
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "/Library/Input Methods/chichi77 KeyKey.app/Contents/Info.plist"
codesign --verify --deep --strict "/Library/Input Methods/chichi77 KeyKey.app"
```

目前 helper 僅提供升級安全準備／收尾，不提供啟用狀態 snapshot；啟用狀態以重新登入後的輸入法選單／設定畫面記錄。保留 `/var/log/install.log`、Sparkle 相關 unified log、出錯時間、畫面與是否需重新登入；receipt 與 TIS 註冊成功均不能代替中文實打。

失敗時先保留工作 VM 與證據，再從 a／b 開新副本比較。不強制結束整批 IMK、不刪 HIToolbox 偏好、不改主機輸入法、DNS、鎖定或信任設定來讓測試通過。若診斷 guest-agent 還在終端機執行，正常登出前先結束該診斷程序，避免終端機自己的執行中工作阻擋登出，誤判成輸入法造成的登入畫面故障。

guest-agent 只在需要執行 VM 診斷時使用官方來源，或直接在 VM 終端機操作；不需要為此開 SSH、免密碼 sudo 或常駐登入服務。帳號密碼、測試私鑰、憑證私鑰與登入 token 不進 Git、PR 描述或 log。

完成後正常關閉工作 VM、結束暫時防休眠與測試 server。主機短期防閒置可用有時限的 `caffeinate`，不改鎖定或密碼設定；主機已鎖定時由使用者解鎖。VM 測過的 macOS／架構與主機是不同證據；最低支援版本的 VM 通過，不能代替其他 macOS 或 Intel 實機驗收。
