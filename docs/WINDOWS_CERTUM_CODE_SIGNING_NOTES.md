# Windows Certum 簽章研究與案例筆記

查詢日期：2026-10-13。本文整理維護者評估 Certum 的網路查證、商品頁觀察及公開專案經驗。
KeyKey 尚未以實際 Certum 帳號完成購買、身分驗證、簽章或 CI 驗收；本文不是成功操作紀錄，
也不代表已採用 Certum。正式發布政策仍見 [CODE_SIGNING_POLICY.md](../CODE_SIGNING_POLICY.md)。

## 方案選擇

| 方案 | 查詢時官網價格 | 金鑰位置與必要條件 |
| --- | --- | --- |
| [Open Source Code Signing in the Cloud](https://shop.certum.eu/open-source-code-signing-on-simplysign.html) | €49 | SimplySign 雲端；手機 App、Desktop 與網路，不需購買加密卡 |
| [Open Source Code Signing – code](https://shop.certum.eu/open-source-code-signing-code.html) | €25 起 | 僅憑證啟用碼；已有 cryptoCertum 3.6／3.7 加密卡、讀卡機與驅動者適用 |
| [Open Source Code Signing – set](https://shop.certum.eu/open-source-code-signing.html) | €69 起 | 包含加密卡；只有特定套裝包含讀卡機，另確認硬體寄送成本 |

[官方產品比較](https://www.certum.eu/en/code-signing-certificates/)列開源方案有效期為一年。
價格、稅額、套裝選項及供應情形以實際結帳為準，不把起價當完整報價。

本次文字擷取曾同時出現「out of stock」與「Add to Cart」；維護者截圖與實際瀏覽器頁面則
顯示 €49、可用的加入購物車按鈕，既有購物車也列有一份該商品。因此不能只依文字擷取判定缺貨；
這也不等於已完成付款或確定可核發。

雲端商品說明列出 EXE、MSI、DLL、JAR、WAR 等格式、每月最多 5,000 次簽章，以及至少
RSA 3072-bit、FIPS 140-2 Level 3 或 CC EAL 4+ 金鑰保存環境。證書身分是自然人，姓名前加上
「Open Source Developer」。Linux／macOS 上可使用相容工具簽 Windows 檔案，不能取代 Apple Developer ID。

## 購買、驗證與啟用

1. 在雲端商品頁加入數量 1，進入購物車並核對商品名稱、金額及結帳選項。
2. 註冊或登入 Certum Shop，填寫本人及帳單地址；憑證欄位另在啟用階段提供。
3. 選擇結帳頁提供的付款方式。[付款說明](https://shop.certum.eu/payment-shipping)列有信用卡、
   PayPal 與銀行轉帳；電子產品交付沒有實體運費。
4. 入帳後進入 `My account → Data security products`，選購入憑證並開始 `Data verification`。
5. 提供與證件一致的姓名、本人地址、身分驗證資料與公開開源專案網址，等待審查或補件。
6. 驗證成功後執行 `Activate certificate`，確認證書欄位、雲端金鑰演算法與長度，指定現有或新建
   SimplySign 帳號的 Email，送出核發申請。
7. 核發後依收到的啟用連結與啟用碼，在手機 SimplySign 掃描 QR code；Windows 安裝
   SimplySign Desktop，登入後才可使用雲端憑證簽章。

依據：[官方購買指南](https://support.certum.eu/en/how-to-buy-code-signing/)、
[開源雲端啟用手冊](https://www.files.certum.eu/documents/manual_en/CS-Open_Source_Code_Signing_in_the_cloud_Certificate_activation.pdf)、
[SimplySign App 啟用](https://support.certum.eu/en/how-to-activate-simplysign-app/)。
購買指南列驗證完成後開源憑證約 1–3 天核發；其他產品頁列 1–5 天，不能當保證期限，補件時間另計。

### 台灣個人與開源專案資格

[官方文件要求](https://support.certum.eu/en/code-signing-required-documents/)說明：

- 開源憑證只發給個人；身分驗證提供自動驗證、登記點、公證及持證件照片等方式。
- 另需本人名下的水電、瓦斯或電話帳單，以及公開專案網址；公開資訊須能證明申請人與專案的關係。
- 若 Certum 無法確認專案，可能不核發；使用開源憑證簽署商業販售軟體，可能被撤銷憑證。

[證件支援入口](https://support.certum.eu/en/what-documents-are-supported/)目前連結的
[2023 年文件清單](https://files.certum.eu/documents/manual_en/ARIADNEXT_IDnow_Document_Coverage_Release_23.04_PUBLIC.pdf#page=20)
列有台灣 2008、2018、2021 版電子護照。這是可用台灣護照驗證的依據，但不是所有台灣申請
必定成功的保證；實際支援、中文帳單是否需翻譯及驗證失敗的退款處理仍待 Certum 確認。

Inkdrop 作者的[親身申請經驗](https://www.devas.life/code-signing-certificate-for-indie-developers/)
記錄日本個人使用護照與英文銀行帳單完成驗證，在 Parallels 上簽 Windows Electron 安裝器。
他購買的是 Standard 雲端方案，不能據此認定開源方案接受相同替代文件；文內舊價格與
EV／SmartScreen 敘述也不能當目前規則。

## 一年到期、時間戳記與 SmartScreen

關鍵是簽章時憑證是否有效，以及有無可信任時間戳記，不是 build 日期。

| 情況 | 憑證到期後 |
| --- | --- |
| 有效期間內簽章並加入有效時間戳記 | 舊版可繼續驗簽，不會單純因簽章憑證到期失效 |
| 簽章沒有時間戳記 | 簽章憑證到期會影響驗證 |
| 到期後要簽新版本 | 需續發／取得新憑證 |

依據：[Certum 商品說明](https://shop.certum.eu/open-source-code-signing-on-simplysign.html)、
[Microsoft Authenticode 時間戳記](https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures)。
撤銷、檔案被修改、時間戳記或憑證鏈失去信任等仍可能使驗證失敗，不承諾永久有效。

Authenticode 可證明發行者及檔案完整性；有效簽章與「SmartScreen 不顯示警告」是不同結果。
[Microsoft 現況說明](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/distribution-feature-status#smartscreen-reputation-ev-certificates-no-longer-grant-instant-bypass)
指出 OV／EV 均不再保證立即通過 SmartScreen，仍須累積信譽。Certum 商品也只承諾協助建立信譽與降低警告機率。

## 開源專案的採用證據

以下依據是官方專案文件或維護者紀錄，未下載每份 release 逐一驗簽；文件、workflow 程式碼、
成功執行紀錄及實際產物是不同證據層級。

| 專案 | 可確認的採用方式 | 來源 |
| --- | --- | --- |
| HTTrack／WinHTTrack | Certum Open Source＋雲端 HSM；文件說明 GitHub-hosted runner 經人工核准，簽 EXE、DLL、安裝器與解除安裝器，使用 SHA-256／RFC 3161 | [SIGNING.md](https://github.com/xroche/httrack-windows/blob/master/SIGNING.md) |
| GAM | 官方 Windows EXE／安裝包使用 Certum Open Source；文件附 James Lee 的憑證及驗簽輸出，另有年度續發與重新驗證經驗 | [驗證指南](https://github.com/GAM-team/GAM/wiki/Verifying-a-GAM7-Build-is-Legitimate-and-Official)、[續發紀錄](https://github.com/GAM-team/GAM/issues/1825) |
| 2FAGuard | 安全文件列 Timo Kössler 的 2024、2025、2026 年 Certum 開源憑證；商店版以外的 release 簽章，未明列雲端或硬體 | [SECURITY.md](https://github.com/timokoessler/2FAGuard/blob/main/SECURITY.md) |
| openstan | Certum Open Source＋SimplySign；CI 建置 MSI，維護者手動登入、使用 jsign 簽章與驗證後發布 | [Code Signing Policy](https://openstan.org/codesigning/) |
| CrystalDiskInfo／CrystalDiskMark | 作者列 2020–2026 年間多份 Certum Open Source 憑證歷史，也列有後來的 GlobalSign 公司憑證；不能說目前只用 Certum | [數位簽章歷史](https://crystalmark.info/ja/information/digital-signature/) |

HTTrack 的內部檔案、安裝器與人工核准流程最接近 KeyKey；openstan 則提供先用 CI 建置、
再由本人簽章的較簡單路徑。GAM 維護者在 2025 年續發紀錄表示需每年重新驗證專案，續發應提早準備。

## CI 自動化的可行路徑與限制

[Certum 官方 SignTool／Jarsigner 手冊](https://files.certum.eu/documents/manual_en/CS-Code_Signing_in_the_Cloud_Signtool_jarsigner_signing.pdf)
描述手機產生 OTP、登入 SimplySign Desktop，再以命令列或批次簽章。查詢時未找到官方保證
€49 開源方案可用的 headless signing API 或官方 GitHub Action；這不代表社群無法自動化。

| 路徑／案例 | 做法 | 查證界線 |
| --- | --- | --- |
| [Inkdrop 自動化分享](https://www.devas.life/how-to-automate-signing-your-windows-app-with-certum/) | 從啟用 QR code 的 otpauth URI 產生 TOTP，以 PowerShell 操作 Desktop 登入 | 作者親身成功分享，屬桌面自動化，非官方 CI 保證 |
| [dismine Windows Action](https://github.com/dismine/windows-app-signing-setup-action) | Windows runner 安裝 Desktop、設定登錄資料、以 TOTP 自動登入，後續使用 SignTool | 非官方 Action；只查閱公開程式碼，KeyKey 尚未實測 |
| [ExHyperV workflow](https://github.com/Justsenger/ExHyperV/blob/main/.github/workflows/publish.yml) | 發布流程已有安裝、登入及 EXE 簽章步驟 | 可確認主分支整合程式碼，未逐一核對成功 run／產物 |
| [ReactiveUI 簽章 Action](https://github.com/reactiveui/actions-common/blob/main/.github/actions/certum-sign/action.yml) | Linux 顯示環境內自動操作 Desktop，以 jsign／PKCS#11 簽 NuGet | 格式是 NuGet；不能直接當 KeyKey EXE 驗收 |
| [hpvb/certum-container](https://github.com/hpvb/certum-container) | 容器內 Desktop＋VNC 人工登入，對外提供 PKCS#11；之後自動簽章 | 每次重啟需登入；作者記錄登入視窗未關閉會使 token 不可用 |
| [ssign](https://github.com/Le-Syl21/ssign) | 非官方、以研究 SimplySign 協定的 HTTPS 客戶端簽 EXE／DLL，免 Desktop，支援 RFC 3161 | [0.1.x 文件](https://docs.rs/crate/ssign/latest)列作者已在 CI 完成 PE 簽章；2026 年新工具，KeyKey 未驗證 |
| [EasyTier PR #2292](https://github.com/EasyTier/EasyTier/pull/2292) | EV 雲端方案的 Windows 自動簽章整合提案 | 查詢時尚未合併，不能當正式採用開源方案或成功發布的證據 |

Desktop GUI 方案需維護登入視窗、等待／重試及安裝版本；ssign 免 GUI，但增加對非官方
協定實作的依賴。不能把社群自動化可行誤寫成「Certum 官方開箱即用 CI 支援」。

自動化常需 TOTP 長期祕密（otpauth URI／seed），不是一次性的六位數 OTP。該祕密可授權
簽章，必須當簽章憑據保管，不進入 Git、聊天、日誌、截圖或 artifact。若採用 CI，先審查
工具與憑據處理，固定經審查版本／commit，以受保護的 signing environment 限制存取，
保留人工核准；fork PR 不可取得簽章憑據。範例文中的輸出 OTP 等做法不直接照抄。

## Certum 的可信度與服務經驗

Certum 自 1998 年營運，屬 Asseco 集團；可查
[公司背景](https://www.certum.eu/en/certum-by-asseco/)、
[Microsoft／CCADB 包含的根憑證及用途](https://ccadb.my.salesforce-sites.com/microsoft/includedcacertificatereportformsft)，
及涵蓋 2025–2026 年的 [EY WebTrust CA 稽核報告](https://www.cpacanada.ca/api/getPDFWebTrust?attachmentId=84a61b66-db2a-4a62-a227-ea3624e52f3e)。
正式信任與稽核不等於客服品質或 CI 易用性保證。

[Mysterium VPN 2024 年維護者回報](https://github.com/mysteriumnetwork/mysterium-vpn/issues/613)
抱怨人工登入、文件與自助介面妨礙自動化。這是特定時期的使用經驗，不足以否定後來的
自動化方案，也不能代表全部客戶。採用案例證明有人實際使用，不保證 KeyKey 的驗證結果。

## KeyKey 的後續驗收

現有 [Package-Store-Windows.ps1](../Source/Loaders/Windows-TSF/Package-Store-Windows.ps1)
使用 Windows 憑證存放區 thumbprint，先簽內部 PE、再建安裝器、最後簽外層 EXE；
簽章參數已有 `/fd SHA256 /tr <TimestampUrl> /td SHA256`，並以 `signtool verify /pa /all /v` 驗證。
它與 SimplySign 提供 Windows 憑證的方式有整合基礎，但腳本存在不代表 Certum 實測通過。

真正導入時仍需：

- 確認台灣文件、非商業開源資格、費用與核發結果，保存適當的憑證／信任鏈資訊。
- 先在 Windows 用實際憑證簽測試 EXE／DLL，確認 Authenticode 及時間戳記，再驗完整安裝包。
- 若採 CI，另驗登入、內部檔案與外層簽章、憑據不外洩、驗簽失敗即停止發布及人工核准流程。
- 正式變更簽章供應商時同步審查發布政策／workflow，不能因新增研究筆記就宣告已完成整合。
- Authenticode 完成後才產生更新 Ed25519 簽章與雜湊；已發布資產不原地替換。
  unsigned 過渡到 signed 發布時使用更高產品版號，依 [更新發布規則](../update/README.md)驗收。
