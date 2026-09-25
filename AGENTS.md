# AGENTS.md — 開發指引

此檔只記錄目前開發需要遵守的規則與入口。舊版逐日進度、測試數字和待辦已完整移到 [歷史交接紀錄](docs/AGENTS_HISTORY.md)；該紀錄僅供查證當時情況，不能當成現況或發布驗收。開始工作時先看目前分支、程式碼、`CHANGELOG.md` 和相關平台文件。

目前本機開發分支為 `v1.3.0`，五平台原始碼版號已升至 1.3.0；尚未建立對應 tag 或發布套件。README 說明目前公開下載仍為 `v1.2.9`；Windows 安裝指南以 1.3.0 的安裝與操作畫面為準，並標明尚未發布。舊版測試紀錄和 Android 私有資料庫清理清單中的 `1.2.10` 也須保留原意。發布前仍需依各平台建置與驗證流程確認實際產物。

## 工作區與提交

- 先執行 `git status --short --branch`；保留使用者既有的未提交修改。只逐檔 `git add` 本次工作，不用 `git add .` 或 `git add -A`。
- 提交前檢查 diff、`git diff --check` 和測試結果。提交作者與提交者沿用儲存庫既有身分；不要改用公司信箱，也不要加入工具署名或 `Co-Authored-By`。
- 產品 UI、About 和字串資源不加入開發者或工具署名。語料、測試與建置設定中必要的模型名稱屬資料內容，不能因署名規則刪除。
- `Source/Distributions/Takao/CookedDatabase/KeyKey.db`、各平台建置目錄、`Installer/local-builds/`、影片、API 請求和執行紀錄都是產物，不要因它們出現在工作區就一併提交。不要提交 API 金鑰。
- 對外宣稱「已修正」時，區分原始碼、建置產物、已安裝版本和實機行為；一層通過不代表其他層也通過。

## 授權與資料來源

- 授權範圍以 [LICENSING.md](LICENSING.md) 為準。Yahoo 舊碼與衍生修改保留 BSD 3-Clause 標頭、`LICENSE.txt`、About 出處及必要聲明；Android、iOS、Linux、Windows TSF 的原創 frontend 有各自的 MIT 範圍，第三方素材維持原授權。
- 不直接改 `DataSource/McBopomofo/phrase.occ` 或 `BPMFMappings.txt` 這類上游副本；本專案補充詞放在 `DataSource/AISyntheticBigram/` 的詞庫與語料中。
- `Source/DataTables/*.cin`、`DataSource/McBopomofo/` 和 `DataSource/chichi77Collection/` 會影響多個平台。修改共用資料後，逐平台核對產生的資料庫、資產與候選行為。

## 五平台架構

| 平台 | 好打注音執行路徑 | 語言模型來源 |
|---|---|---|
| macOS | `OSX-IMK`、`OVIMSmartMandarin`、Manjusri C++ | 共用 Ruby cooker 產生並打包 `KeyKey.db` |
| Windows | `Windows-TSF`、`OVIMSmartMandarin`、Manjusri C++ | 原始資料 cook 或指定外部 `KeyKey.db`，建置時驗證後打包 |
| iOS | `iOS-Keyboard/KeyKeyEngine` 的 Swift walker | 鍵盤 extension 內的共用 `KeyKey.db` |
| Android | `Android-IME` 的 Java walker | APK asset 內的共用 `KeyKey.db`，安裝時複製到私有目錄 |
| Linux | `Linux-IME` 的 C++ walker、Fcitx 5 adapter | Python cooker 產生 `smart-mandarin.db` |

- macOS 與 Windows 共用框架和注音模組；iOS、Android、Linux 另有組句實作。改動 SmartMandarin 的詞頻、Bigram、backoff 或候選排序時，必須檢查五平台，不能只看同一份資料庫。
- 目前 `v1.3.0` 模型有 **885,614 筆 Bigram**。第一音節應以該讀音的常用字為首選，例如「ㄅㄨˋ→不」、「ㄌㄧㄝˋ→列」；「列上去」要檢查整句組字。變動語料或 cooker 後，更新驗證預期值與測試，避免只用 Bigram 筆數判斷新舊。
- `Source/Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py` 檢查共用 DB 完整性、筆數與首音節。iOS archive、Android asset、macOS App 和 Windows 打包目錄仍要各自確認；Linux 使用自己的資料庫與核心測試。
- Android 的私有 DB 檔名是更新快取的版本邊界。換模型後若不變更檔名或加入內容校驗，已安裝使用者可能繼續讀舊庫。Windows 的 `keykey_database_deploy` 須在 DB 更新而 DLL 未重新連結時同步打包目錄。

## iOS／Android 好打注音螢幕鍵盤

- 觸控版與實體鍵盤共用組字引擎，但操作契約不同。只調整螢幕鍵盤時，檢查 iOS 的 `KeyboardView.swift`、`KeyboardViewController.swift`、`BopomofoEngine.swift`，以及 Android 的 `BopomofoKeyboardView.java`、`BopomofoImeService.java`、`BopomofoEngine.java`；不要把觸控選字方式套到實體鍵盤游標。
- 好打注音上方固定 11 個組字格，最多保留 9 個已完成、可點選修正的音節，餘格顯示尚未完成的注音；第 10 個音節完成時才送出最前一字。選字格只指定候選目標，不能改變後續輸入的插入游標；修正句中第三字後再打字，應接在句尾。
- 觸控候選窗開啟時覆蓋第一排注音按鍵並攔截該排觸控，收起後恢復按鍵。開關候選窗不得調整鍵盤列的大小或位置。傳統注音仍使用原有候選列與輸入行為。
- 修改上述行為時，至少驗證 9／10 音節邊界、句中改字後繼續輸入、未完成注音時回頭選字、跨越邊界的多字詞、候選窗開關，以及傳統注音與實體鍵盤回歸。引擎測試不能代替 App／鍵盤 extension 建置或實機版面檢查。

## 建置與驗證入口

完整依賴與發布流程見 [BUILDING.md](BUILDING.md) 及各平台 README。下列命令從儲存庫根目錄執行；需要相應平台的 SDK 和工具鏈。

```sh
# macOS、iOS、Android 共用的 cooked DB；改資料或 cooker 後先重建
make -C Source/Distributions/Takao/DatabaseCooker
python3 Source/Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py \
  Source/Distributions/Takao/CookedDatabase/KeyKey.db

# macOS；xcconfig 不可省略
(cd Source && xcodebuild -project Takao.xcodeproj \
  -target 'Takao (Loader OSX-IMK)' -configuration Release \
  -xcconfig Takao-macOS.xcconfig build)

# iOS 引擎；App／extension 使用 shared scheme 建置
(cd Source/Loaders/iOS-Keyboard/KeyKeyEngine && swift test)

# Android
(cd Source/Loaders/Android-IME && ./gradlew lintDebug testDebugUnitTest assembleDebug)

# Linux：於有 Fcitx 5 開發依賴的 Ubuntu 環境
(cd Source/Loaders/Linux-IME && ci/build-and-test.sh)
```

- iOS 專案用 `-scheme 'chichi77 KeyKey'` 建置；`-target` 不能取代 Swift Package 依賴。DB 應只打包進 `Keyboard.appex`。Xcode Cloud 的 `ci_scripts/ci_post_clone.sh` 會於乾淨 checkout 重煮並驗證 DB。
- `KeyKeyiOS.xcodeproj/xcshareddata/xcodecloud/manifest.json` 是 Xcode Cloud 的產品對應資料，須隨專案提交；不要將它當成 `xcuserdata` 暫存檔。工作流程本身仍在 Xcode Cloud 管理。
- Windows 1.3.0 開發套件以 Windows 10 起為目標。x64 ZIP 內含 x64／x86 TSF DLL，供兩種位元數的所有應用程式使用；x86 ZIP 供 32 位元 Windows 使用，只含 x86 TSF DLL。NSIS 測試安裝器目前仍為 x64。設定程式改用 .NET 10 WPF Fluent 介面，跟隨系統明暗模式；x64／x86 各自編出設定 EXE 與同位元數的 `KeyKeySettingsBackend.dll`，設定 DLL 不會載入應用程式的 TSF 行程。兩種設定程式皆為獨立離線 EXE，不要求使用者另裝 .NET。已在 Windows 11 x64 建置並啟動兩種設定程式，Windows 10 x86／x64 尚待實機驗證。
- Windows 使用 `Source/Loaders/Windows-TSF` 的 CMake presets 建置。正常 cook 與 `KEYKEY_DATABASE_PATH` 覆寫都要通過 DB verifier。驗證 Windows TSF 行為須在 Windows 執行，macOS 靜態檢查不能算實測。
- Windows 好打注音設定的 `UseCharactersSupportedByEncoding` 空值或 `UTF-8` 代表不限制字集；`WindowsEncodingService` 必須接受空值，否則詞庫查到的中文字候選會全部被濾掉，只留下底線注音。WPF 設定頁讀取兩者，但儲存時使用 `UTF-8`，讓尚未換掉舊 DLL 的行程也能輸入。引擎測試需實際驗證完整音節能組成中文字，不能只檢查注音鍵有被攔截。
- Windows TSF 的組字底線由 `ITfDisplayAttributeProvider` 與 `GUID_PROP_ATTRIBUTE` 宣告，實際呈現仍由文字宿主決定；驗證需分別看記事本與其他 App。中英模式切換及 TIP 失焦時，應在可寫入的 edit session 以 `EndComposition` 保留組字文字，不可呼叫會清空 range 的 `abandonComposition()`。好打注音可能先把符號留在組字內，傳統注音可能直接送出，候選鍵測試需接受兩種有效狀態。
- Windows TSF 以繁體中文（台灣）`0x0404` 為預設啟用的 profile，同時註冊繁體中文（香港）`0x0c04` 與繁體中文（澳門）`0x1404` 供使用者手動加入；不得註冊或安裝簡體中文。台灣原 GUID 必須保留，香港、澳門各有獨立 GUID。ZIP 安裝、解除安裝與 `Register-Tip.ps1` 不以 `Set-WinUserLanguageList` 改動 Windows 語言清單，也不要求使用者先安裝語言套件；NSIS 不開啟 Windows 語言設定頁。香港、澳門 profile 尚未在對應語言環境實測。
- Windows NSIS 升級不可先以舊 DLL 執行 `regsvr32 /u`：2026-09-25 本機 A/B 驗證中，即使只註冊台灣 profile，先解除舊版再註冊新版仍會讓 Windows 的 `Microsoft.Windows.LanguageComponentsInstaller` 發出「簡體中文輸入法字典尚未就緒」通知；只重複註冊 DLL 不會。改成先將新版完整寫入獨立目錄、重新註冊相同 CLSID/profile；完整三 profile 套件安裝後，事件紀錄沒有新增通知，使用者也確認畫面未再出現。`Get-WinUserLanguageList` 仍只有 `zh-Hant-TW`，`Get-InstalledLanguage` 只有 `en-US`、`und-Hant` 字型與 `zh-TW`，沒有 `zh-CN`。ZIP 安裝仍使用舊的先解除註冊流程，後續要另行改成不中斷 profile 的升級。
- Windows 文字宿主會長時間載入舊版 TSF DLL：2026-09-25 的 `explorer.exe` 與桌面程式仍載入 `1.2.9` DLL，舊版 `openSettings()` 從 DLL 旁尋找 `KeyKeySettings.exe`。NSIS 若在升級後立即刪除舊 payload，工作列「輸入法設定…」就沒有反應，舊 DLL 也可能失去旁邊的 DB。新版 DLL 改優先讀 HKLM 解除安裝項目的 `VersionLocation`；NSIS 升級保留舊 payload 供既有行程使用，舊目錄需待行程結束後另外清理。升級後仍載入舊 DLL 的工作列會暫時開啟舊版設定頁；登出再登入即可讓 Explorer 載入新版 DLL 與新設定頁。不要為此複製整份設定程式到每個舊版目錄。
- Windows NSIS 同一份安裝檔重跑時不得覆寫已載入的 `KeyKeyTsf_x64.dll`：正式簽章套件的安裝目錄是清楚的版號（如 `1.3.0`），本機未簽署測試套件則以相同產品版號加內容指紋作獨立目錄（如 `1.3.0-test-xxxxxxxxxxxx`）。比較 HKLM `VersionLocation` 與 `PayloadFingerprint`，並確認所需檔案存在；完全相同就跳過檔案寫入及註冊，在完成頁顯示「已安裝」。不同內容不得覆寫相同目錄；正式升版仍使用 `1.3.1` 這類正常版號。
- Windows 工作列選單的「輸入法」區直接選好打注音或傳統注音，選取時透過共用 loader 的 `setPrimaryInputMethod` 保存到 plist；其他 TSF 行程在下次按鍵同步。設定「一般」頁用 `ModulesSuppressedFromUI` plist 陣列控制可見項目，至少保留一種，隱藏目前模式時改選另一種；未加入 Windows 的倉頡與簡易不顯示。NSIS 升級完成頁與 ZIP 安裝腳本會提示登出再登入，首次安裝不顯示升級專用提示。
- Windows 設定仍使用 OpenVanilla 的 plist XML 格式，但 Windows 共用寫入器原本就省略 `DOCTYPE`；WPF 設定頁也不產生它。讀取舊檔時 `XmlResolver = null` 且忽略 DTD，不連到 XML 裡的外部網址。
- Windows loader 與三份模組 plist 改以 `com.polobread.chichi77-keykey.windows` 為識別前綴。TSF 啟動與 WPF 設定啟動時都會在新檔不存在的情況下從已使用的 `org.openvanilla...` 前綴複製設定；不覆寫新檔，也不刪舊檔，因為登出前舊版 TSF 行程可能仍在讀寫舊檔。`SmartMandarinUserData.db` 名稱不變。
- Windows 1.3.0 在 Visual Studio 2026／CMake 4.3 建置時，Ruby 只需 Interpreter 元件；Windows SDK 的 WinSQLite 標頭可能在 `um/winsqlite/winsqlite3.h`；NSIS 3.12 編譯含繁中文字串的安裝腳本須指定 UTF-8 輸入字元集。現代設定頁另需 .NET 10 SDK，CMake 以 `dotnet publish` 為 x64／x86 各產生自包含 EXE；CI 必須安裝 .NET 10。若 x86 VS generator 的 MSBuild FileTracker 在代理環境回報存取被拒，可用 x86 VsDevCmd 與 Ninja 在獨立 `out/build/x86-ninja` 建置。x64／x86 DLL、885,614 筆 Bigram 的 DB 與 3 個 CTest 先前已建置驗證；較廣的 App 相容性尚待使用者測試。
- Linux 的 unit、staged install、X11 與 GNOME Wayland 測試是不同層級。測試結果要寫明實際環境與輸入路徑；詳細 VM 診斷見 `Source/Loaders/Linux-IME/docs/`，不要把舊測試數字當成目前版本結果。
- iOS 鍵盤 extension 接收不到一般實體鍵盤事件；實體鍵盤編輯器在容器 App，這兩條路徑需分別驗證。
- 修改 Linux 與 Windows 的跨平台鍵盤語意時，先讀 macOS `OSX-IMK`、PlainVanilla 和模組事件流，再讀 Windows TSF；兩者不同時明列差異，不從單一平台推定另一平台。

## 改版號清單

`README.md` 標題是對外版本入口。升版時同步檢查：

| 平台 | 版號來源 |
|---|---|
| macOS | `Source/Loaders/OSX-IMK/Takao-Info.plist`、`Source/PreferenceApplications/OSX/Info.plist`、`Source/Utilities/PhraseEditor/OSX/Info.plist`、`Source/Distributions/Takao/Installer-OSX-Help/Info.plist` 的 `CFBundleVersion` 與 `CFBundleShortVersionString` |
| Windows | `Source/Loaders/Windows-TSF/CMakeLists.txt` 的 `project(... VERSION ...)`、`Package-Windows.ps1` 的 `$Version` |
| iOS | `Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION`；App 與 extension 都要一致 |
| Android | `Source/Loaders/Android-IME/app/build.gradle.kts` 的預設 `keyKeyVersionName` 與 `keyKeyVersionCode` |
| Linux | `Source/Loaders/Linux-IME/CMakeLists.txt` 的 `project(... VERSION ...)` |

再核對文件範例、各平台打包後的實際版本與發行流程；GitHub Release、App Store、Google Play 的版本不能由原始碼版號推定。

目前待辦：在各平台完成 1.3.0 建置與套件版號驗證；發布後再把安裝指南、下載連結及支援矩陣的發布狀態更新到實際可取得的套件。

## 專題文件

- [CHANGELOG.md](CHANGELOG.md)：各平台版本變更。
- [CANDIDATE_ORDER_1_3_PLAN.md](CANDIDATE_ORDER_1_3_PLAN.md)：候選順位與罕字顯示的未來規劃；尚未等同實作或驗收。
- [歷史交接紀錄](docs/AGENTS_HISTORY.md)：整理前的逐日紀錄、測試細節與舊待辦；先核對當前程式與文件再使用。
