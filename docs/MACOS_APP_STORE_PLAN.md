# macOS App Store Connect 上架可行性與發行計畫

調查日期：2026-09-21
適用基線：`v1.2.9` branch、macOS 15 以上、Apple Silicon 版 InputMethodKit 輸入法

## 結論

**目前不能把琦琦注音的 macOS 輸入法本體當成一般 Mac App，透過 Mac App Store
發行。** 這不是單純缺少 App Store Connect metadata、簽章或 sandbox entitlement，
而是 Apple 尚未提供可由 Mac App Store 安裝的 macOS 輸入法 extension point。

Apple Developer Technical Support 對「macOS IME 是否有官方 Mac App Store 發行方式」
的 accepted answer 是「沒有，只能在 Mac App Store 外發行」；Apple DTS 在 2026 年
4 月再次回覆時，仍建議提出 enhancement request，讓 macOS 未來支援類似 iOS keyboard
extension 的機制。見 [Apple Developer Forums：How to distribute an Input Method
Engine](https://developer.apple.com/forums/thread/134115)。

因此本計畫的決策是：

1. **不建立會複製、下載或啟動外部 `.pkg` 的 Mac App Store 殼 App。**
2. **macOS 輸入法正式版繼續走 Developer ID 簽章、notarization、stapling 與 GitHub
   Release。** 這是目前受 Apple 支援的商店外發行方式。
3. 先向 Apple 提交 Feedback Assistant／Developer Technical Support 問題，取得本產品的
   書面答案；只有 Apple 提供新的 sanctioned extension／installation path，才啟動
   App Store Connect 實作階段。

App Store Connect 仍可用於既有 iOS／iPadOS app；本文件只否定「現有 macOS IMK
輸入法本體直接上 Mac App Store」這一條路，不影響 iOS keyboard extension。

## 為什麼現行架構無法直接送審

### Apple 的規則與平台缺口

- [App Review Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/)
  要求 Mac App Store app 使用 App Sandbox、為單一自足 app bundle、不可把 code 或
  resource 安裝到 shared location、不可下載／安裝 standalone app，也不可要求 root
  權限。更新也必須由 Mac App Store 提供。
- [Apple 的 App Sandbox 文件](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
  明列 App Sandbox 是 Mac App Store 發行必要條件，並限制 app container 外的檔案存取、
  跨 process 通訊及修改其他 app preference。
- macOS InputMethodKit 輸入法必須位於 Text Input Services 會掃描的位置，例如
  `/Library/Input Methods` 或 `~/Library/Input Methods`。Mac App Store 會把 app 安裝在
  `/Applications`，現行 macOS 又沒有 iOS keyboard extension 的對等機制。Apple DTS
  因此明確回答目前只能在商店外發行。

所以即使讓現有 binary 通過 sandbox，也不能解決「App Store 如何把它註冊成系統輸入法」
這個首要問題。反過來，在 App Store app 第一次啟動時複製 bundled IME、下載 `.pkg`、
呼叫 Installer 或要求管理員權限，會直接碰到 2.4.5(ii)、(iv)、(v) 的限制。

### 琦琦注音目前的實際架構

| 項目 | `v1.2.9` 現況 | 對 Mac App Store 的影響 |
| --- | --- | --- |
| 輸入法型態 | InputMethodKit background app；`LSBackgroundOnly=1`、`InputMethodConnectionName=chichi77_1_Connection` | 沒有可提交的 macOS keyboard extension target |
| 安裝位置 | `.pkg` 固定寫入 `/Library/Input Methods/chichi77 KeyKey.app` | shared location，且安裝時需要管理員授權 |
| 安裝腳本 | `postinstall` 結束既有輸入法 process；首次安裝要求登出／登入 | Mac App Store 不接受這種 package lifecycle |
| 簽章 | Developer ID Application／Installer、Hardened Runtime、notarization | 是商店外憑證；不是 Mac App Distribution／App Store provisioning |
| Sandbox | macOS app 與三個 nested helper app 沒有 entitlement；目前 build 的 entitlement dict 為空 | 不能直接上傳 Mac App Store |
| 資料位置 | 直接使用 `~/Library/Preferences`、`~/Library/Application Support` 等 legacy path | sandbox 後須遷移至 container／App Group，並處理舊資料 |
| Process 通訊 | IMK server 之外，Preferences／PhraseEditor 以 registered `NSConnection` 連到輸入法 | sandbox 下需要 entitlement 與完整跨 process 回歸驗證 |
| Bundle 內容 | `Preferences.app`、`PhraseEditor.app`、`InstallerHelp.app`、兩個 frameworks | 每個 nested code 都要正確簽章／sandbox；InstallerHelp 對 store build 沒有合理角色 |
| 架構 | 目前只建置 `arm64`，最低 macOS 15；約 17 MB | 只能服務 Apple Silicon；Intel 版仍受 x86_64 OpenSSL 靜態庫阻擋 |
| 加密 | 靜態連結 OpenSSL 3 `libcrypto.a`，仍有 SHA-1／RSA verification code | 上傳時須如實回答 export compliance，不能假設「無網路」就免填 |
| Metadata | macOS 使用舊 `.icns`，未建立 Mac App Store screenshot／listing 集合 | 只有 Gate 0 通過後才值得製作 |

## 網路上的實務經驗

以下案例不是 Apple 政策的替代品，但與官方結論一致：主流第三方 macOS 輸入法皆採
installer／package 與商店外簽章，而不是由 Mac App Store 安裝輸入法本體。

- [小麥注音 McBopomofo](https://github.com/openvanilla/McBopomofo) 使用獨立 installer。
  維護者記錄 macOS 會限制同一 login session 反覆終止輸入法 process 的次數；多次安裝
  後若新版未載入或輸入法失效，需登出再登入。這與琦琦注音目前的安裝／升級風險相同。
- [鼠鬚管 Squirrel 的安裝文件](https://github.com/rime/squirrel/blob/master/INSTALL.md)
  使用 Developer ID Installer、notarytool 與 `.pkg`，也提醒直接安裝後可能仍需 logout。
- [唯音 vChewing 的 package script](https://github.com/vChewing/vChewing-macOS/blob/main/BuildPKG.sh)
  將輸入法放入 `~/Library/Input Methods`，並替輸入法本身加入 sandbox entitlements；但發行
  仍是 signed package，而不是 Mac App Store。這表示「讓 IME sandboxed」是可考慮的安全
  強化，卻不會自動取得 Mac App Store 的安裝能力。

## Gate 0：先取得 Apple 的可行性答案

這一階段不改 production code，也不建立 App Store app record。

- [ ] 用 Feedback Assistant 提交 enhancement request，引用 Apple DTS thread，說明琦琦
      注音是 InputMethodKit app、目前安裝路徑，以及希望使用官方 macOS keyboard extension
      或其他受支援的 App Store distribution mechanism；保存 `FB...` 編號。
- [ ] 向 Developer Technical Support 提出具體問題，要求回答：
  1. 2026 年是否已有 Mac App Store 可用的第三方 IME extension point？
  2. 是否允許 self-contained host app 內含 IME，而且不複製到 app bundle 外？若允許，
     Text Input Services 用哪一個公開 API 註冊？
  3. 需要哪些 documented entitlement、provisioning profile 與安裝位置？
  4. Preferences 與 phrase editor 應以何種官方 App Group／XPC 方式和 IME 共用資料？
- [ ] 將 Apple 回覆、文件 URL、OS／Xcode version 與日期存回本文件。

**Gate 0 通過條件：** Apple 提供 documented、可由 Mac App Store 安裝並被 Text Input
Services 發現的機制，而且明確允許本產品使用。只有一般 sandbox 建議、temporary
exception 或人工 review 意見，若沒有安裝／註冊 API，均不算通過。

**若 Apple 仍回答不支援：** 結案為 `NO-GO`，不建立 Mac App Store listing，繼續下方的
商店外發行計畫。

## 推薦執行路線：改善現有商店外發行

這條路不需等待 Apple 新功能，可獨立排程；每一項都應在新版本做，不回寫已發布的
`v1.2.9` tag。

### P0：發行可靠性

- [ ] 在乾淨 Apple Silicon 測試帳號驗證首次安裝、登出／登入、加入輸入來源、TextEdit
      試打、覆蓋升級、移除與重裝；保存畫面、Console 摘要與實際 bundle version。
- [ ] 重跑 `codesign --verify --deep --strict`、`spctl --assess --type install`、
      `stapler validate`、package install path、SQLite integrity 與 SHA-256 gate。
- [ ] 驗證升級時 `postinstall` 結束舊 process 後能自動重啟；反覆安裝達系統限制時，錯誤
      文件必須明確要求 logout，而不是讓使用者重複安裝。
- [ ] 在 macOS 15、26、27 的乾淨帳號至少各跑一次；beta OS 結果不可取代已發布 OS。

### P1：降低安裝與相容性問題

- [ ] 做「系統層 `/Library/Input Methods`」與「單一使用者 `~/Library/Input Methods`」
      的 migration spike。後者可避免 root，但須驗證 package 簽章、更新、移除、既有安裝
      衝突與多使用者行為後才能採用。
- [ ] 另立 sandbox spike：只測 IME 本體、Preferences、PhraseEditor、設定與使用者詞庫；
      列出所需 temporary exception。不要把 spike 成功誤記為 Mac App Store 可上架。
- [ ] 解決 x86_64 OpenSSL 後產生 universal build，或在下載頁、installer distribution
      與網站一致地維持「Apple Silicon only」。目前只有文件提示，package 本身仍缺明確
      CPU 安裝 gate。
- [ ] 將三個 nested helper 的舊 Yahoo 使用者可見字串、copyright、無用 InstallerHelp
      及 deprecated API 分開盤點；BSD／第三方 attribution 不可誤刪。

### P2：發現與信任

- [ ] 保持下載頁只提供 notarized、stapled package 與 checksum，不提供需要手動移除
      quarantine 的正式產物。
- [ ] 評估官方網站與 Homebrew Cask 作為發現管道；所有管道都固定指向不可覆寫的版本化
      release asset，且核對 Team ID 與 checksum。
- [ ] 在隱私權政策補 macOS：本機詞庫、使用者詞彙、設定儲存位置、無輸入內容上傳、
      無 analytics／tracking；不可只沿用目前偏重 iOS keyboard extension 的文字。

## 只有 Gate 0 通過後才啟動的 Mac App Store 路線

### Phase 1：最小技術原型

- [ ] 依 Apple 指定的新 extension point 建立全新的 macOS host app／extension target；
      不以 copy 到 `Library/Input Methods`、shell script、helper installer 或 private API
      模擬安裝。
- [ ] 為 host、extension 與每個 nested executable 使用 Mac App Distribution signing、
      App Store provisioning 與 App Sandbox；由 Xcode Archive 產生可驗證的 distribution
      artifact。
- [ ] 將設定與使用者詞庫移入 container／App Group，設計一次性 migration；測 direct
      build 與 store build 同時存在、升級、降級和移除時不毀損資料。
- [ ] 以 Apple 指定的 documented IPC 取代或限制 global registered `NSConnection`；避免
      依賴未核准的 temporary exception。
- [ ] 在 TextEdit、Safari、Mail、Notes、Office、Electron app、secure text field、
      多螢幕與快速切換輸入來源上完成端到端試打。

**Phase 1 exit gate：** 從 TestFlight／App Store 測試安裝取得的 app 能在全新使用者帳號
被系統列為輸入來源，且沒有手動複製、`.pkg`、Terminal、root 或關閉安全機制。

### Phase 2：App Store Connect 與 review

- [ ] 決定是替既有 App Store Connect app 加 macOS platform，或建立獨立 Mac app。
      先核對 iOS bundle ID `io.github.polobread.inputmethod.chichi77.ios`、macOS 現有 bundle
      ID `io.github.polobread.inputmethod.chichi77`、SKU、產品名稱與 universal purchase
      需求；建立 build 後 bundle ID 不能再任意更換。
- [ ] 建立獨立且單調遞增的 macOS build number；目前 macOS `CFBundleVersion=1.2.9`
      不適合作為長期 App Store build counter。
- [ ] 建立 Mac App Store icon、繁中與英文名稱／副標題／說明／關鍵字、support URL、
      marketing URL、copyright、category、age rating 與 review contact。
- [ ] 準備 1–10 張同尺寸 16:10 Mac screenshots；Apple 目前接受
      `1280x800`、`1440x900`、`2560x1600`、`2880x1800`。截圖必須呈現真實 IME 使用情境，
      不能只有安裝說明。
- [ ] 更新 privacy policy URL 與 App Privacy 回答；若完全不收集資料則明確選擇
      `Data Not Collected`，同時核對所有 bundled third-party code。
- [ ] 盤點 privacy manifest／required-reason API、第三方 SDK signature、export compliance
      與 OpenSSL 用途；在 `Info.plist` 以真實情況設定 encryption declaration。
- [ ] Review Notes 提供逐步啟用與測試方法、測試字串、設定入口、無帳號／無網路說明，
      並引用 Apple 核准此 extension path 的文件或 DTS case。
- [ ] 先走 TestFlight internal／external 測試，再送審；預留一次以上 metadata 或 binary
      rejection 修正，不把 review 通過日期綁成不可變的發布日。

Apple 目前要求 Mac app 至少一張、最多十張 screenshot；Mac screenshot 尺寸與上傳規格見
[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)。
App 名稱上限 30 字元、macOS privacy policy URL、bundle ID 與 age rating 等欄位見
[App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)。
Build upload、bundle ID／version／build string 對應方式見
[Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)。

## 主要風險清單

| 等級 | 風險 | 提早處理方式 |
| --- | --- | --- |
| P0 | macOS 沒有 Mac App Store IME extension point | Gate 0；未取得 Apple 書面路徑前不開發 store build |
| P0 | 殼 App 安裝／下載 `.pkg` 違反 2.4.5 | 不做 workaround；維持 Developer ID 外部發行 |
| P0 | Sandbox 後 IMK IPC、preferences、phrase DB 失效 | 分離 sandbox spike；container／App Group migration 與 E2E |
| P0 | Store 與 direct build 互相覆蓋或同時註冊 | 分離 bundle ID／資料 migration／coexistence 測試，依 Apple 核准架構決定 |
| P1 | 只有 arm64，Intel 使用者無法安裝 | universal build 或 package CPU gate 與清楚 metadata |
| P1 | 首次安裝後找不到輸入法、必須 logout | 乾淨帳號驗收；安裝完成頁與排錯文件一致 |
| P1 | 多次 kill IME 後系統不再重載 | 限制 installer 行為；偵測後提示 logout；保存實測紀錄 |
| P1 | Nested helper 未 sandbox／簽章不一致 | 每個 executable 個別簽章、entitlement 與 store validation |
| P1 | `~/Library` legacy 資料在 sandbox 下不可用 | App Group 與一次性 migration；升降版／移除測試 |
| P1 | OpenSSL 觸發 export compliance 問題 | 盤點實際 RSA／SHA-1 用途並如實申報，不猜 exemption |
| P1 | 舊 API、舊 NIB、AddressBook 或 private/deprecated API validation | archive 前跑 analyzer、store validation 與 API audit |
| P2 | 商店畫面無法清楚展示 background-only IME | 真實跨 App 輸入截圖與 reviewer walk-through；不得誇大功能 |
| P2 | Yahoo 字串與授權 attribution 不一致 | 分開處理品牌清理與法定 notice，逐一核對 `LICENSING.md` |

## 完成定義

在 Apple 尚未提供 macOS IME App Store 機制時，本計畫的完成定義不是「成功上架一個不能
安裝輸入法的殼 App」，而是：

- Apple case／Feedback 編號與書面結論已保存；
- 產品頁與文件沒有暗示 macOS 版可從 App Store 安裝；
- Developer ID package 可在支援的乾淨 macOS／CPU 組合完成簽章、notarization、安裝、
  啟用、試打、升級與移除；
- 使用者能從可信任的固定 URL 找到 package、checksum、隱私政策與排錯步驟；
- Apple 日後若提供 extension point，才依 Phase 1／2 的 gate 重新開案。
