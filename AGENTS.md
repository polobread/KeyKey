# AGENTS.md — 開發指引

此檔只記錄目前開發需要遵守的規則與入口。舊版逐日進度、測試數字和待辦已完整移到 [歷史交接紀錄](docs/AGENTS_HISTORY.md)；該紀錄僅供查證當時情況，不能當成現況或發布驗收。開始工作時先看目前分支、程式碼、`CHANGELOG.md` 和相關平台文件。

目前本機開發分支為 `v1.3.0`，五平台原始碼版號已升至 1.3.0；尚未建立對應 tag 或發布套件。README 與安裝指南指向已發布的 `v1.2.9`，舊版測試紀錄和 Android 私有資料庫清理清單中的 `1.2.10` 也須保留原意。發布前仍需依各平台建置與驗證流程確認實際產物。

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
- Windows 用 `Source/Loaders/Windows-TSF` 的 CMake presets 建置 x64 和 x86；正常 cook 與 `KEYKEY_DATABASE_PATH` 覆寫都要通過 DB verifier。驗證 Windows TSF 行為須在 Windows 執行，macOS 靜態檢查不能算實測。
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
