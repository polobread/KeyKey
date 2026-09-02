# AGENTS.md — 開發交接

macOS、Windows、Android 與 iOS 由不同環境輪流開發，這份檔案是各平台的交接點。

**接手時：** 先讀完本檔，再讀 [BUILDING.md](BUILDING.md)。動任何 `Source/Frameworks`
或 `Source/ModulePackages` 底下的檔案前，先看「跨平台影響」。

**交接前：** 更新本檔的 TODO 與「已知陷阱」。調查出來的結論寫進來，下一個代理才
不會重跑一遍。

---

## 硬規則

1. commit 訊息與任何檔案內容都**不得出現 AI 工具或模型名稱**，也不要加
   `Co-Authored-By` trailer。
2. 產品內（UI、About 視窗、字串資源）**不得出現開發者或工具署名**。
3. commit author／committer 沿用 repo 既有 commit 的身分
   （`git log -1 --format='%an <%ae>'`），**不可用公司信箱**。
4. `git add` **逐檔指定**，不要用 `git add -A` 或 `git add .`。工作區常有未追蹤的
   編輯器暫存檔。
5. 以下是 BSD 條款要求，**移除會違反授權**：各原始檔的
   `Copyright (c) 2012, Yahoo! Inc.` 標頭、`LICENSE.txt`、About 視窗的出處標示、
   Info.plist 的「非 Yahoo 官方產品」聲明。README 只需連到 `LICENSE.txt`，不重複
   收錄 BSD 全文。
6. 本專案是混合授權：Android、iOS 與 Windows TSF 目錄內的原創 frontend 以目錄級
   MIT License 授權；Yahoo 舊碼與其衍生修改仍是 BSD 3-Clause，第三方素材維持各自
   授權。範圍以 `LICENSING.md` 為準，不要逐檔補 MIT 標頭，也不要把整個
   `Source/Loaders/OSX-IMK` 改標成 MIT。

---

## 改版號要動的地方

宣告版號的位置是 `README.md` 標題。改版時**以下全部要一起改**，否則 macOS
「關於」視窗會與 Windows 套件不一致。

### macOS — 4 個 plist，每檔 `CFBundleVersion` + `CFBundleShortVersionString`（共 8 處）

| 檔案 | 產出 |
|---|---|
| `Source/Loaders/OSX-IMK/Takao-Info.plist` | 主程式 |
| `Source/PreferenceApplications/OSX/Info.plist` | Preferences.app |
| `Source/Utilities/PhraseEditor/OSX/Info.plist` | PhraseEditor.app |
| `Source/Distributions/Takao/Installer-OSX-Help/Info.plist` | InstallerHelp.app |

`Installer/build.sh` 從主程式的 `CFBundleVersion` 取值，不需另外改。

### Windows — 2 處

| 檔案 | 位置 |
|---|---|
| `Source/Loaders/Windows-TSF/CMakeLists.txt` | `project(... VERSION x.y.z)`；同時產生 DLL／EXE 的 `VERSIONINFO` |
| `Source/Loaders/Windows-TSF/Package-Windows.ps1` | `$Version` 參數預設值 |

### Android — 2 個本機預設值

`Source/Loaders/Android-IME/app/build.gradle.kts` 的 `keyKeyVersionName` 預設值與
由 `major * 1,000,000 + minor * 1,000 + patch` 算出的 `keyKeyVersionCode` 預設值。
GitHub Actions 仍會從 `README.md` 解析並以 Gradle properties 覆寫這兩個值。

### iOS — 1 處

| 檔案 | 位置 |
|---|---|
| `Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj/project.pbxproj` | 兩個 target 共用的 `MARKETING_VERSION` |

### 文件 — 非建置輸入，但會過期

`README.md` 標題、`BUILDING.md` 與 `Source/Loaders/Windows-TSF/README.md` 裡的範例
zip 檔名。

### 改完自我檢查

```sh
# 應該只看到同一個版號
grep -rn "CFBundleShortVersionString" -A 1 --include='*.plist' Source/ \
  | grep -v Source/build | grep string
grep -n "VERSION" Source/Loaders/Windows-TSF/CMakeLists.txt
grep -n 'Version = ' Source/Loaders/Windows-TSF/Package-Windows.ps1
```

---

## 跨平台影響

改到共用區就等於同時改另一邊。**單邊測過不代表沒事。**

| 路徑 | 影響範圍 |
|---|---|
| `Source/Frameworks/` （OpenVanilla、PlainVanilla、Formosa、Manjusri） | 兩平台 |
| `Source/ModulePackages/OVIMMandarin/` | 兩平台 |
| `Source/DataTables/*.cin` | 兩平台（各自的 DatabaseCooker） |
| `Source/Loaders/OSX-IMK/` | 僅 macOS |
| `Source/Loaders/Windows-TSF/` | 僅 Windows |
| `Source/Loaders/Android-IME/` | 僅 Android；建置時唯讀 `Source/DataTables`、`DataSource/McBopomofo` 與公開的 `DataSource/chichi77Collection` |
| `Source/Loaders/iOS-Keyboard/` | 僅 iOS；建置時把已 cook 好的 `KeyKey.db` 打包進 extension |
| `Source/Branding/enter.svg` | Android 與 iOS 兩個觸控鍵盤（各自照座標描邊，不直接讀檔） |

模組註冊不對稱，看共用模組時要記得：

- **macOS** 載入 TraditionalMandarin、SmartMandarin、AssociatedPhrase、Generic、
  FullWidthCharacter、HanConvert、BopomofoCorrection、YKAFOneKey、OVAFEval
- **Windows** 只載入 TraditionalMandarin 與 AssociatedPhrase（SmartMandarin 需要
  的中研院語料不在開源釋出內）
- **Android** 以 Java 重作 TraditionalMandarin 的單音節組字、選字與 AssociatedPhrase
  關聯詞，直接解析 `bpmf-ext.cin` 與詞庫文字資產；目前不載入 C++ framework 或
  SmartMandarin
- **iOS** 以 Swift 重作同一組行為，但**資料層走已 cook 好的 `KeyKey.db`**（系統
  `libsqlite3`），不在執行時解析 `.cin`；同樣不載入 C++ framework

所以「SmartMandarin 裡的某段邏輯」在 Windows 上是死碼，反之 TraditionalMandarin
沒實作的功能在 Windows 就不存在。

---

## 建置前置條件

完整說明在 BUILDING.md，這裡只列最容易踩的。

### macOS

```sh
cd Source
(cd Distributions/Takao/DatabaseCooker && make)
xcodebuild -project Takao.xcodeproj -target "Takao (Loader OSX-IMK)" \
  -configuration Release -xcconfig Takao-macOS.xcconfig build
```

- **DatabaseCooker 一定要先跑。** 產出的 `CookedDatabase/KeyKey.db` 不在版控內，
  缺了 xcodebuild 會在最後 copy 步驟失敗，錯誤訊息誤導成建置環境壞掉。
- `-xcconfig Takao-macOS.xcconfig` 不可省略。該檔沒有被 pbxproj 引用，用 Xcode.app
  直接建置拿不到 SDK／arch／OpenSSL 設定。
- 目前僅支援 arm64。

### Windows

```powershell
cd Source\Loaders\Windows-TSF
cmake --preset windows-x64
cmake --build --preset windows-x64-release
ctest --test-dir .\out\build\x64-ninja --output-on-failure
cmake --preset windows-x86
cmake --build --preset windows-x86-release --target KeyKeyTsf
```

x86 也必須建，32-bit Office 需要。

### Android

```powershell
cd Source\Loaders\Android-IME
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug
```

- 使用 Android SDK 36.1 時，`compileSdk` 必須用 `release(36)` 加
  `minorApiLevel = 1` 的區塊寫法；寫成 `compileSdk = 36` 會另找未安裝的
  `platforms;android-36`。
- `bpmf-ext.cin` 與 `bpmf-punctuations.cin` 由 `generateBopomofoAssets` 在建置時
  從共用 `Source/DataTables` 複製，不要在 app 內另存一份。
- 關聯詞由 `generateAssociatedPhraseAssets` 從 `DataSource/McBopomofo/phrase.occ`
  與公開的 `DataSource/chichi77Collection/phrase.*.tsv` 複製到 generated assets；
  Android 仍在執行時解析文字資產，不另轉為專用二進位格式。

### iOS

```sh
cd Source/Loaders/iOS-Keyboard
xcodebuild -project KeyKeyiOS.xcodeproj -scheme "chichi77 KeyKey" \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

- 引擎測試不需要模擬器：`cd KeyKeyEngine && swift test`。
- **必須用 `-scheme`，不能用 `-target`** —— Swift Package 依賴只有透過 scheme 才會
  被建置。`xcshareddata/xcschemes` 內的 shared scheme 因此必須留在版控中；缺了它，
  新 clone 會由 xcodebuild 自動產生到 gitignore 的 `xcuserdata`，換機就壞。
- 新機器要先取得模擬器 runtime：`xcodebuild -downloadPlatform iOS`（約 8.5 GB）。
- 需要先有 cook 好的 `KeyKey.db`；它會被複製進 **extension** bundle，不要放進容器
  App，否則 10 MB 會打包兩次。
- Xcode Cloud 的 `ci_scripts` 必須位於 `Source/Loaders/iOS-Keyboard/`（與 xcodeproj
  同層），`ci_post_clone.sh` 也必須保留 executable bit。腳本會在乾淨 checkout cook
  `KeyKey.db`，再以 `CI_BUILD_NUMBER` 搭配 Apple Generic Versioning 同步 App 與
  extension 的 build number；不要把 cook 後的資料庫提交進版控。
- 容器 App target 的 `COPY_PHASE_STRIP` 必須保持 `NO`。Keyboard extension 在自己的
  target 已完成 Release strip 與簽章，Embed Foundation Extensions 階段若再次 strip，
  Xcode 只會跳過並警告 `not stripping binary because it is signed`；這個設定不會關閉
  extension 自己的 `STRIP_INSTALLED_PRODUCT`。
- 配色只在 `Keyboard/Palette.swift`，全部是 `UIColor(dynamicProvider:)`，深色模式
  跟著系統走。淺色值與 Android 相同，深色值只有 iOS 有。
- App 圖示來自 `Source/Branding/chichi77.png`，縮成 1024×1024 放在
  `ContainerApp/Assets.xcassets/AppIcon.appiconset`（單一尺寸，Xcode 自行衍生）。
- 兩個 target 各有 `PrivacyInfo.xcprivacy`。extension 宣告 `UserDefaults`
  （required reason `CA92.1`，關聯詞詞庫開關）；容器 App 沒有 required-reason API。
  兩份都宣告不追蹤、不收集。

---

## 已知陷阱（不要重複調查）

- **授權按來源而不是路徑歷史判斷**：`Source/Loaders/Android-IME`、
  `Source/Loaders/iOS-Keyboard` 與 `Source/Loaders/Windows-TSF` 的原創 frontend
  由各目錄 `LICENSE.txt` 套用 MIT，不需逐檔標頭；其中引用、複製或打包的 Yahoo、
  OpenVanilla、McBopomofo、Gradle wrapper 與資料庫不會因此變成 MIT。
  `Source/Loaders/OSX-IMK` 雖在 2026 重整路徑，但大量檔案與 Yahoo 原碼相同或由其
  修改，整體仍維持 BSD。全新且未含舊碼的 macOS 檔案若要用 MIT，必須逐項加入
  `LICENSING.md`，不能用整個目錄覆蓋。
- **macOS framework 的 Headers 封印**：framework target 在 `Headers` 還在的狀態下簽好
  自己的產物，app 的 Copy Files phase 再把 header 砍掉，封印就留著已經不存在的檔案，
  `codesign --verify --deep --strict` 必定回報 `a sealed resource is missing or invalid`，
  notarize 也會被退。**不影響本機安裝與使用**，裝不起來時不要往這裡查。已由
  `Installer/build.sh` 在 stage 之後、簽章之前刪掉 `Versions/A/Headers` 與最上層的
  `Headers` symlink 處理掉（header 對執行期沒有用途）。修掉之前 `build.sh` 的
  `DEVELOPER_ID_APPLICATION` 分支其實跑不完：`set -euo pipefail` 加上必定失敗的
  `--verify --deep --strict` 會直接中斷整個腳本。
- **舊 macOS TSM component ID 有三份同步點**：雖然 `Source/Loaders/OSX-TSM` 已不在
  目前支援的建置路徑，`io.github.polobread.inputmethod.chichi77.tsm` 仍同時出現在
  component plist、`Component.m` 與 `Source/Takao.xcodeproj/project.pbxproj`。pbxproj
  的 `TSMC_BUNDLE_ID_LENGTH` 是字串長度的十六進位 byte，目前 44 bytes 必須寫成
  `$"2c"`；只換 ID 不改長度會產生損壞的舊式 TSM 資源。
- **macOS 首次安裝看不到輸入法**：Text Input Services 只在登入時掃
  `/Library/Input Methods`，換過 bundle id 就等於首次安裝，必須登出再登入，
  `lsregister` 手動註冊無效。確認是否註冊：
  `defaults read com.apple.HIToolbox | grep -c chichi77`。`distribution.plist` 刻意不設
  `RequireLogout`：完成頁要求首次安裝者方便時自行登出，但升級由 postinstall 結束舊
  process 後立即生效，不應每次安裝都中斷工作階段。
- **macOS pkg 安裝**：`pkgbuild` 預設把 app bundle 標成 relocatable，`installer`
  會把 payload 寫到別處卻回報成功。已用 `Installer/build.sh` 的
  `BundleIsRelocatable false` 處理；安裝後仍務必
  `ls -ld "/Library/Input Methods/chichi77 KeyKey.app"` 確認。
- **Windows ZIP 安裝**：ZIP 版必須先完整解壓縮、複製到本機 `C:\` 路徑，才執行
  `Install.cmd`；UAC 提升權限後可能存取不到網路磁碟／NAS／UNC 來源。NSIS EXE 是
  獨立離線安裝器，不受這個解壓縮限制，也不要再包進另一層 ZIP 才交給 Partner Center。
- **Windows NSIS 完成頁只在必要時要求重啟**：`Delete /REBOOTOK`／`RMDir /REBOOTOK`
  遇到被鎖定的舊檔才設 reboot flag，完成頁此時預設「稍後重新啟動」；一般安裝不應
  主動要求重啟。互動模式預設開啟琦琦設定，另可選開啟 `ms-settings:regionlanguage`；
  `/S` 靜默安裝不可啟動兩者。
- **Android Studio agent shell 的 x86 preset 可能撞到重複環境變數**：這個環境同時
  傳入 `Path` 與 `PATH` 時，Visual Studio generator 的 MSBuild 會以 MSB6001／
  `ArgumentException` 停在編譯器偵測。不是 x86 原始碼錯誤；用
  `VsDevCmd.bat -arch=x86 -host_arch=x64` 後以 Ninja 設定 `out/build/x86-ninja`
  可正常完成 DLL、測試與連結。
- **Windows TSF 的 Ctrl 白名單必須精確**：`IsInputMethodControlKey` 只放行
  `bpmf-punctuations.cin` 保證存在的 Ctrl+0／Ctrl+1、Ctrl+標點，以及
  Ctrl+Alt+字母／五個標點；一般 Ctrl+C、Ctrl+方向鍵、Alt 快捷鍵仍交給應用程式。
  Ctrl+0／Ctrl+1 會與瀏覽器縮放／分頁及 Excel 快捷鍵衝突，這是目前依產品需求
  選擇由輸入法優先處理的行為。不要把白名單擴成所有 Ctrl／Alt 鍵，否則
  `OnTestKeyDown` 與實際引擎處理結果不一致時，某些 host 會把按鍵吃掉。
- **Windows TSF 必須監看外部游標移動**：`ITfTextEditSink::OnEndEdit` 在 selection
  離開 composition range 或無組字候選的 anchor 時清掉引擎狀態。移除這個 sink
  會讓滑鼠／應用程式移動游標後仍沿用舊 range，Enter 可能只移動游標而文字留在
  原行。切換 document context 時也必須同步重掛 sink。
- **Windows TSF 單按 Shift 依賴 key-up opt-in**：`OnTestKeyUp` 必須先回 TRUE，TSF
  才會呼叫 `OnKeyUp`；目前採 Windows-IMM 相同的 300ms 單按判定。Shift 與其他鍵
  組合時要取消 pending，不能誤切中英文模式。
- **Windows 設定共用 PlainVanilla plist**：一般設定寫在
  `%APPDATA%\chichi77 KeyKey\org.openvanilla.chichi77-keykey.windows.plist`，必須保留
  loader 已有的 `PrimaryInputMethod`、`ActivatedAroundFilters` 等陣列，不能整檔覆寫。
  注音與關聯詞則各自使用 `TraditionalMandarin.plist`、`AssociatedPhrase.plist`。
- **Windows 的 Big-5 候選限制需要自訂 encoding service**：舊的
  `PVDefaultEncodingService` 只宣告 UTF-8，會把 TraditionalMandarin 設定的 `BIG-5`
  清空，讓「使用全字庫罕用字」永遠無法關閉。Windows TSF 現在用 CP950 搭配
  `WC_NO_BEST_FIT_CHARS` 判斷候選是否真能以 Big-5 表示，不要改回預設 service。
- **Windows 候選窗的 DPI 由 host 決定**：TSF DLL 載入應用程式行程，不能呼叫
  `SetProcessDpiAwareness*` 改掉 host 的 DPI 模式。候選窗以 owner 的
  `GetDpiForWindow()` 建立對應字型並縮放 padding／間距／邊框，另以
  `WM_DPICHANGED` 處理跨螢幕移動。DPI-unaware host 會回報 96 DPI 並由系統整體
  virtualization；不要再乘一次實體螢幕比例，否則會雙重放大。
- **Windows 候選窗比例可覆寫 host DPI**：一般設定的「比例」預設跟隨 Windows；
  選擇 `75%` 到 `350%` 時是候選窗自己的絕對縮放比例，讓高 DPI 螢幕可以把候選窗
  調得比系統比例小。設定值存為 `CandidateWindowScalePercent`；只有清單內的值有效，
  缺少或無效時回到跟隨 Windows。自訂值會用 `GetScaleFactorForMonitor` 對 host 回報
  DPI 做反向正規化，抵消 DPI-unaware／system-aware host 的 bitmap virtualization；
  不可直接把自訂百分比當 DPI，也不可再和 host DPI 相乘。
- **macOS 候選窗比例沿用同一個設定鍵與選項**：Preferences 的一般設定以程式建立
  「跟隨顯示器、75%–350%」選單，值同樣存為 `CandidateWindowScalePercent`。AppKit
  已負責 point 到 Retina pixel 的映射，所以「跟隨顯示器」維持原本 1 倍 point 尺寸；
  指定百分比則以 content view 的 bounds 等比例放大直式與橫式候選窗，不能再乘
  `backingScaleFactor`，否則 Retina 螢幕會雙重放大。設定在下次輸入法 activate 時套用。
  比例列與 XIB 原有的「可隱藏部分輸入法模組」說明佔用同一列；建立控制項時必須先把
  說明移到比例列上方並縮短模組清單，否則比例 popup 會直接蓋住說明文字。
  三份 `MainMenu.xib` 都必須把 `_candidateWindowStyleMatrix` 接到 `TakaoGlobal`；簡中曾
  漏接，會讓程式建立的比例列使用零座標並且無法保存直／橫式選擇。
- **macOS 輸入法浮動視窗不可蓋過系統安全 UI 或搶焦點**：候選窗、提示泡泡與一般
  浮動窗使用 `NSStatusWindowLevel`，並加入所有 Space／全螢幕輔助行為；只有需要互動的
  字典視窗可成為 key window。候選窗顯示用 `orderFront:`，不要改回
  `makeKeyAndOrderFront:`。多螢幕定位必須用完整的 `NSPointInRect` 同時判斷 x、y，否則
  上下排列的螢幕會選錯 visible frame。
- **macOS OneKey 啟動程式不可經過 shell**：`LaunchApp` 的值以 tab 分隔程式名稱／路徑
  和參數，必須交給 `NSWorkspaceOpenConfiguration.arguments`；不要拼成 `open ...` 再呼叫
  `system()`，否則設定值中的 shell metacharacter 會被執行。
- **Windows 語言列通知可能重入或跨執行緒**：2026-08-24 的 Android Studio
  `studio64.exe` 在 `Ctrl+Space` 切換模式時連續三次以 `0xc0000005` 崩潰；WER 的
  faulting module 是 `KeyKeyTsf_x64.dll`，固定 offset `0xA087` 經同版 map 確認為
  `LangBarButton::update()` 讀取已失效物件。`refreshLangBar()` 必須在鎖內取得每個
  button 的暫時 COM reference，再於鎖外通知；button 的 sink vector 也必須同步，
  且 `OnUpdate` 不可在持鎖時呼叫（會重入 `UnadviseSink`／`Deactivate`）。不要改回
  未同步的 raw pointer 逐一呼叫。
- **三平台詞庫顯示名稱以共用 mapping 為準**：唯一來源是
  `DataSource/AssociatedPhraseCollectionNames.tsv`，目前把 `McBopomofo`、`chinese`、
  `general` 顯示為「小麥注音」、「中文文學」、「一般生活」。macOS 的
  `collection-name.rb`、Windows 的 `DatabaseCooker.cpp` 與 Android generated assets
  都必須讀同一檔；不要修改分類 TSV 的分類欄位，也不要在 frontend 另寫名稱常數。
- **Android 主程式不要用 Java `record`**：AGP 9.2.0 曾把 record 轉譯成
  `com.android.tools.r8.RecordTag`，卻未把該合成類別包進 debug APK；Android 17
  會在建立 `BopomofoImeService` 時以 `NoClassDefFoundError` 崩潰。`assembleDebug`
  與 JVM 單元測試都不會發現。現行程式改用一般 immutable class；工具鏈修正並經
  實機驗證前不要改回 record。
- **Android 選字不可先結束 composing**：`InputConnection.finishComposingText()` 會把
  當前注音讀音直接確定送出；若再 `commitText()` 候選字，輸入區會變成
  `ㄋㄧˇ你`。選字時應直接以 `commitText()` 取代 composing region，之後再依引擎
  狀態更新或結束組字。
- **Android 候選翻頁是循環式**：觸控鍵盤的 ▲、▼、左右滑動，以及外接鍵盤的
  `Page Up`、`Page Down` 與空白鍵都共用 `changePage()`；第一頁的上一頁是最後一頁，最後一頁
  的下一頁是第一頁。空白只有在尚未開啟候選時才用來查詢讀音或輸入空格。
- **Android TraditionalMandarin 選字鍵是 `1–9`**：與共用模組
  `OVIMTraditionalMandarin.cpp` 的 `setCandidateKeys("123456789")` 一致，每頁 9 個。
  觸控版有獨立候選列，必須直接點候選，四排注音鍵即使候選開啟也仍是注音輸入；
  外接鍵盤的一般候選才用 `1–9`。關聯詞依 Windows 行為用外接鍵盤 `Shift+1–9`
  選取，未按 Shift 的數字須關閉關聯詞並交給標準注音鍵位；`0` 不是選字鍵。
- **Android 軟體鍵盤要保留底部系統區**：targetSdk 36 的 IME 視窗會延伸到導覽區，
  系統的多國語系地球鍵與手勢橫條可能蓋住最底列。繪製內容須靠上，底部空白留給
  系統控制項；直式固定保留 40dp、橫式固定保留 35dp，不要把按鍵重新畫滿整個
  view 高度。
- **Android 觸控鍵盤是 11 欄注音版面**：直橫式都由候選列、四排 11 個等寬輸入鍵與
  一排功能鍵組成；四排依序結束於 `ㄦ`、`@`、Emoji、Shift。功能列的長空白是刻意
  的唯一寬鍵。注音鍵必須同時顯示注音與實體鍵位（如 `ㄅ／1`、`ㄉ／2`）。橫式內容
  仍固定 155dp，六排使用橫式小字級，不要恢復舊的左右分割候選。左下模式鍵隨目前
  模式分別顯示「英/數」、「數/ㄅ」、「ㄅ/英」，不要改回「中」或固定「中/英/數」。
- **Android 欄位模式由 App 的 `EditorInfo` 決定**：`inputType` 的文字／Email／URI／
  password／phone／number（含 decimal、signed）／datetime 會轉成 `InputFieldPolicy`。
  一般、姓名、地址、搜尋與長文字保留注音；Email、URL、ASCII／password 只留英文與
  數字符號；電話、整數、小數、日期時間只留數字。限制型欄位不可移除按鍵造成版面跳動，
  要淡化並移除 hit target；觸控 callback 也要再次拒絕 disabled key，不能只靠畫面擋。
  此限制刻意不套到 USB／藍牙實體鍵盤：為與 Windows／macOS 一致，硬體字元與快捷鍵
  維持完整輸入，欄位內容仍由 App 驗證；不要在 `onKeyDown` 用 `inputType` 擋實體鍵。
- **Android 測試完成以完整 AVD 計畫為準**：Android IME 行為、版面、設定、字典或建置有變更時，
  必須依 `Source/Loaders/Android-IME/VIRTUAL_DEVICE_TEST_PLAN.md` 在 API 26、28、30、33、35、37
  六台 AVD 跑完 A–L 矩陣；只跑 JVM test、安裝 APK、打出一個字或只測實體鍵盤都不算完成。
  debug-only `ImeTestActivity` 是欄位型態與 Enter action 的 host，不能加入 release source set。
- **Android 軟 Enter action 與實體 Enter 必須分流**：直橫式觸控 Enter 在沒有 reading／
  一般候選時，依 `imeOptions & IME_MASK_ACTION` 呼叫 `performEditorAction(DONE/NEXT/SEARCH/
  SEND/GO/PREVIOUS)`，並顯示中文 action 名；若 App 提供 `actionLabel`／`actionId`，要顯示
  自訂標籤並以該 ID 呼叫 action。`IME_FLAG_NO_ENTER_ACTION`、無 action 或 App 拒絕時才
  送 Enter key event。關聯候選已是額外推薦，不是待確定的組字；Enter 必須關閉關聯候選後
  直接執行 action，不可插入反白關聯詞。外接鍵盤 Enter 永遠走 key event，不可套 editor action，
  也不可選入關聯詞。
- **Android 外部 selection 變動必須清掉組字狀態**：`onUpdateSelection` 在 reading 或
  候選存在時偵測游標／選取變更，重設引擎並結束 composing，否則下一鍵會在新游標沿用
  舊讀音。為避免把游標拉回去或刪錯 App 文字，已顯示的 raw 注音會由
  `finishComposingText()` 留在原處；只清引擎狀態。IME 自己的 `commitText`／
  `setComposingText` 也會觸發 callback；必須以短期
  mutation guard 略過自己的更新，而且只在真的修改 InputConnection 時啟用，否則按空白
  開候選後立刻移動游標可能被誤判為自己的 callback。
- **Android 觸控按鍵預覽不新增 hit target**：`BopomofoKeyboardView` 只為單一文字、注音
  與符號鍵畫 1.4 倍 Canvas overlay，滑出原鍵、放開或取消即隱藏；功能鍵、候選列與實體
  鍵盤模式不顯示。設定鍵 `key_preview_enabled` 預設 true，變更後由既有
  `ime_settings` listener 立即刷新；不要讓預覽框本身可點擊或改變原按鍵範圍。
- **Android 觸控 Shift 不等於實體 Shift**：注音版按 Shift 只暫時顯示英文小寫，
  並把雙標籤從「注音在上、鍵位在下」交換成「鍵位在上、注音在下」，輸入下一個
  觸控字元後立即回注音；由功能列切入的英文版按 Shift 才會持續切換大小寫，且大寫時
  數字排換成 `!@#…`。數字符號模式的 Shift 不離開該模式，只切換兩套各 44 鍵的
  符號頁。實體 Shift 只當該次硬體按鍵的修飾鍵，不能改變觸控版面。
- **Android 聲調符號要單獨放大並校正位置**：`ˊˇˋ˙` 是 spacing modifier letter，
  在系統字型中以一般注音字級繪製會顯得過小，直接放大又會因字型 baseline 偏高而超出
  按鍵。`drawBopomofoKey` 固定將四個聲調放大 1.8 倍，再依實際 glyph bounds 下移，
  讓上緣與一般注音符號對齊。直式鍵位提示使用共同的固定 baseline，讓聲調鍵下方的
  `3467` 與其他鍵的 `125890` 對齊；不要把兩個標籤重新合成單一字串繪製。
- **Android 符號與 Emoji 候選各固定 10 頁**：「符」開啟 90 個標點、括號、數學、
  單位、貨幣、箭頭及圖形符號；第三排 Emoji 開啟 90 個常用表情，兩者每頁 9 個。
  與文字候選共用翻頁與空白循環；觸控直接點候選，外接鍵盤一般候選仍可用 `1–9`
  選取，不是 AssociatedPhrase 關聯詞。
- **Android 首頁與設定頁要避開前相機挖孔**：targetSdk 36 的 Activity 會 edge-to-edge，
  兩頁由 `UiInsets` 把 system bars 與 display cutout 加到既有 padding；不要改回固定
  上邊距。首頁第三個按鈕開啟震動設定，`HapticSettings` 固定使用
  `0/10/20/30/50/80/100/150/200ms` 九段並以 SharedPreferences 共用給 IME；`0`
  表示關閉，震動需要 manifest 的 `VIBRATE` 權限。
- **Android Backspace 要以完整文字圖形為單位**：有注音 reading 時由引擎逐步刪除
  聲調、韻母、介音、聲母，候選開啟也不可只關候選而不退音；reading 為空時才由
  `TextDeletion` 計算游標前完整 grapheme 的 UTF-16 長度，讓代理字元、變體選擇符、
  膚色與 ZWJ Emoji 一次刪乾淨，不要改回固定 `deleteSurroundingText(1, 0)`。刪掉最後
  一個注音 component 時也不可呼叫 `finishComposingText()`，因為它只移除 composing
  樣式並原樣保留 `ㄅ`；引擎必須回報丟棄 composing text，讓 loader 以
  `commitText("", 1)` 取代並結束 composing region。
- **Android 外接鍵盤候選列也要保留底部系統區**：候選列有 12 個等寬按鍵：9 個候選、
  Emoji、`ㄅ／英` 與 `半／全`；後兩鍵不可再塞進同一欄縮成半寬。語言鍵點擊等同
  `Ctrl+Space`，右格點擊等同 `Shift+Space`。輸入模式格只有兩種，NUMBER 也顯示為
  `英`，點擊後切到 `ㄅ`；不可加回第三種「數」。候選列不顯示 ▲／▼，
  翻頁使用 `Page Up`／`Page Down` 或空白。直式／橫式分別在下方保留 40dp／35dp，
  避免 Android 的多國語系地球鍵遮住控制項。Emoji 必須在沒有中文字候選時仍可按。
  所有候選角標都固定顯示 `1–9`；
  關聯詞雖以 Windows 式 `Shift+1–9` 選取，也不可把角標改成 `!@#$%^&*(`。
- **Android 浮動候選依賴 App 回報游標座標**：設定啟用後以
  `requestCursorUpdates()`／`onUpdateCursorAnchorInfo()` 跟隨插入點，候選 Window
  必須附掛 IME token、不可取得焦點，否則觸控選字會讓原文字欄位失焦。部分自訂 editor
  不回報 `CursorAnchorInfo`，此時固定退回可用畫面底部中央，不要因此恢復底部候選列。
  浮動模式只把 IME input view 留成 1dp 以維持 window token；這不是待清理的空白。
  垂直窗用上下移動反白／左右換頁，水平窗相反，Enter 選反白，ESC 取消整個讀音。
  若系統拒絕附掛浮窗，或 IME token 經約 1.5 秒重試仍拿不到，必須自動關閉浮窗設定、
  記錄並在設定頁顯示原因，直接改用一般實體鍵盤候選列；原因持續保留至使用者重新勾選，
  重新勾選才清除並允許再試一次，不能靜默吃掉候選。
- **Android 外接鍵盤的 Ctrl 快捷鍵要先於修飾鍵攔截判斷**：`Ctrl+Space` 只在注音與
  英文間切換，`Ctrl+,`／`Ctrl+.` 輸入全型 `，`／`。`；`Ctrl+0` 與 `Ctrl+1` 則比照
  macOS `OVIMTraditionalMandarin.cpp` 的 `_punctuation_list`，開啟與觸控「符」相同的
  90 個符號候選。組字 reading 尚未清空時，標點與符號快捷鍵須保留 reading，不可
  丟掉使用者正在組的注音。快捷鍵的 keydown 與 keyup 都要吃掉，長按不可重複觸發。
- **Android 實體鍵盤全半形比照 Windows**：`Shift+Space` 切換 `半／全`，切換時保留
  目前 reading／候選；全形模式將實體鍵盤提交的 ASCII 空白映成 U+3000，`!`–`~`
  依序映成 U+FF01–U+FF5E，非 ASCII 與中文字不變。這個狀態不影響觸控鍵盤。
  `Shift+Space` 必須先於一般 Space 處理，keydown／keyup 與 repeat 都要吃掉；即使使用者
  先放開 Shift，按住 Space 產生的 repeat 也不可漏成空白。
- **Android 關聯詞庫是固定 30 個文字資產**：`generateAssociatedPhraseAssets` 從
  `DataSource/McBopomofo/phrase.occ` 加入顯示為「小麥注音」的基本詞庫，再從公開的
  `DataSource/chichi77Collection` 加入 29 個 `phrase.*.tsv`。設定首次預設
  `McBopomofo`，但 SharedPreferences 已存在空集合時代表使用者
  刻意全部關閉，不能偷偷恢復預設。基本詞庫中與三個 `people-*` 詞庫重疊的人名必須先排除，
  否則關閉人名詞庫仍會漏出候選。
- **Android 關聯詞只在確定單一中文字後開啟**：候選內容是已輸入首字後的詞尾，
  選取時只 commit 詞尾；輸入下一個注音鍵會關閉關聯詞但不可自動送出第一個詞尾。
  30 個全不選時 `AssociatedPhraseDictionary.load` 必須直接回空詞庫，不解析資產。
- **macOS 拿不到 Ctrl+Shift+標點**：macOS 不會把 Ctrl 組合的 shift 變體交給輸入法，
  `Ctrl+,` 與 `Ctrl+Shift+,` 都以 `,` 送達，`charactersIgnoringModifiers` 也一樣。
  所以 `bpmf-punctuations.cin` 的 `_ctrl_:`、`_ctrl_"`、`_ctrl_<`、`_ctrl_>`、
  `_ctrl_?` 在 macOS **無法觸發**，`Ctrl+[`、`Ctrl+]` 也根本收不到。已實測確認，
  不要再嘗試用 `charactersIgnoringModifiers` 或改寫 `unicharCode` remap 表去救。
  這幾條在 **Windows 仍可用** —— TSF loader 的 `PrintableAsciiFromVirtualKey`
  是從 virtual key 推導字元（`VK_OEM_1` + shift → `:`），不受此限。macOS 端的
  白名單只列真的收得到的組合，`OVCIsInputMethodCtrlKey` 的註解有完整說明。
- **選字鍵的 US 佈局隱性契約**：`OVAFAssociatedPhrase` 的聯想詞選字鍵表
  `"!@#$%^&*("` 依賴上游把鍵盤正規化成 US——macOS 靠 `activateServer:` 的
  `overrideKeyboardWithKeyboardNamed:`（預設 `com.apple.keylayout.US`），Windows 靠
  `PrintableAsciiFromVirtualKey` 的 `")!@#$%^&*("` VK 對照。三處必須一致但彼此看
  不到對方，改任一處要一併檢查。目前是正確的，不要當成 bug 去「修」。
- **iOS extension 收不到實體鍵盤按鍵**：`UIInputViewController` 的
  `pressesBegan`／`pressesEnded` 不會被呼叫，第三方鍵盤也只能在自己的 input view 內
  繪製。Android 的實體鍵盤支援與浮動候選窗在 iOS **做不到**，不要再嘗試。
- **iOS 欄位模式由 `textDocumentProxy.keyboardType` 決定**：11 種 `UIKeyboardType`
  先映成 UIKit-free 的 `KeyboardTypeHint`／`InputFieldPolicy`，才能用 macOS SwiftPM
  測試。限制型欄位保留固定 11 欄位置，將無效按鍵設為 `isEnabled = false` 並淡化；
  controller 也要再次拒絕 disabled key。欄位類型改變時選 preferred mode，同類欄位間
  則保留使用者手動選的 mode。
- **iOS secure／phone pad 欄位禁止第三方鍵盤**：Apple 明定 secure text field、
  `UIKeyboardType.phonePad` 與 `namePhonePad` 都會切回內建鍵盤，App 也能透過 extension
  policy 全面禁用第三方鍵盤。對應 `InputFieldPolicy` 仍需保留作純邏輯測試與防禦性處理，
  但不可宣稱 extension 能在這些欄位實際出現。
- **iOS 13 起可使用 inline 組字**：`UITextDocumentProxy.setMarkedText`／`unmarkText`
  自 iOS 13 可用，本專案最低 iOS 17。loader 把 reading 寫成 marked text；確定候選時
  必須先以候選取代同一 marked range 再 `unmarkText`，不可先 unmark 原始注音，否則會
  產生 `ㄋㄧˇ你`。取消組字則以空字串取代 marked range，不能用 `unmarkText` 接受讀音。
- **iOS 外部文字／選取變動要清掉組字狀態**：`textDidChange`、`selectionDidChange` 與
  鍵盤離開畫面時清除 reading、候選、關聯詞和暫時狀態；外部游標移動後不能沿用舊的
  marked range。loader 自己呼叫 `insertText`／`deleteBackward`／`setMarkedText` 造成的
  callback 必須以短期 mutation generation 略過；同一按鍵可能連續替換舊 marked text
  與建立新 reading，較早的非同步清除不可解除較新 mutation 的 guard。切換欄位時用
  `documentIdentifier` 強制失效舊 guard，但不要在新游標位置刪除舊 marked range。
- **實機可能讓 `documentIdentifier` 違反 nonnull 宣告**：iPhone 16 Plus／iOS 26.6.1
  在 keyboard proxy 剛啟動時實際回傳 Objective-C nil，直接讀 Swift 的非 optional
  `UUID` 會在 `_unconditionallyBridgeFromObjectiveC` trap，造成輸入法立即跳回上一個。
  必須經 `currentDocumentIdentifier()` 的 KVC optional bridge 讀取；不要改回直接存取。
  proxy 後續第一次從 nil 取得 UUID 只是在完成初始化，不是切換輸入欄位，必須先建立
  identifier 基準而不能 reset engine，否則選字後的關聯候選會閃現後立刻消失。
- **實機 document callback 可能晚於下一個 main-loop**：選字時的
  `setMarkedText + unmarkText` 在 iPhone 上可能延遲回報 `textDidChange`／
  `selectionDidChange`。`mutateDocument` 的 guard 必須涵蓋這段短暫 grace period；這只用來
  分類 callback，不可把文件 mutation 或候選顯示本身延遲。
- **候選文字不可決定鍵盤內層寬度**：`KeyboardView` 的 root stack 必須以 999 priority
  填滿手機可用寬度，再由 required maximum 把 iPad 限在 820pt。只放 leading/trailing
  inequality 會讓 Auto Layout 依候選 intrinsic width 排版；動漫的「的名字」會把 11 欄
  鍵盤撐寬，選完關聯詞後又縮回。UI test 必須用僅啟用 `anime` 的多字候選覆蓋這條路徑。
- **iOS SQLite 順序不可依賴未指定的 row order**：單字候選查詢明確以 `rowid` 排序；
  多個關聯詞庫一次查詢後，還要依使用者啟用的 source 順序重組並去重，不能把 SQL
  `IN (...)` 的回傳順序當成詞庫優先權。變更 source 清單時需同步清掉 statement cache。
- **iOS `deleteBackward()` 已經是 grapheme 感知，不要移植 `TextDeletion`**：
  2026-08-23 在模擬器實測，一次 `deleteBackward()` 可完整刪除 👍🏻（膚色修飾符，
  4 個 UTF-16 unit）與 👨‍👩‍👧（ZWJ 家庭序列，8 個 unit／5 個 scalar），沒有殘骸。
  Android 需要 `TextDeletion` 是因為 `deleteSurroundingText(1, 0)` 刪的是**一個
  UTF-16 碼元**；`deleteBackward()` 是「刪除鍵」動作，層級不同。自己再算長度補刪會
  **刪過頭**。
- **iOS 按鍵震動需要 Full Access**：`UIFeedbackGenerator` 在 extension 內被
  `RequestsOpenAccess` 把關，沒開就靜靜失效。本專案選擇不開，改用
  `UIDevice.playInputClick()`（聲音，不需權限）。設定值本身存在 extension 自己的
  `UserDefaults`，那不需要任何權限 —— 別把「存設定」和「產生震動」混為一談。
- **iOS 鍵盤約 60 MB 就會被 jetsam 終止，且沒有 crash log**：不要學 Android 把
  1.2 MB／98k 行的 `.cin` 解析進記憶體。實測 SQLite 只映射查詢用到的頁，資料層常駐
  足跡不到 1 MB。
- **`Mandarin-bpmf-cin` 的 key 是 absolute-order 編碼，不是鍵盤按鍵**：兩個桌面
  cooker 都透過 Formosa 把 `1ji6` 這種按鍵序列轉成 2 字元 base-79 碼，所以 iOS 的
  `BopomofoSyllable` 必須實作同一套編碼（`Mandarin.h:190-227`）才查得到東西。附帶
  好處是與鍵盤佈局無關。
- **Simulator 的 Connect Hardware Keyboard 會讓軟體鍵盤整個消失**：連地球鍵一起，
  看起來像鍵盤掛掉。關法是 Simulator 的 Cmd+Shift+K，或寫
  `defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false`
  再重開 Simulator 視窗。注意 `killall Simulator` 會把 booted 的裝置一起關掉。
- **iOS XCUITest 能加入第三方鍵盤，但不保證能把它設為目前鍵盤**：五機入口是
  `Source/Loaders/iOS-Keyboard/run-simulator-tests.sh`。`--host-only` 會自動跑引擎、
  設定 opt-in 與 14 種宿主欄位；不加參數會要求 extension 的模式／組字／直橫測試。
  iOS 26 的 `InputSwitcherView` 對合成 tap／drag 可能只反白不切換，不能把兩個
  extension test 靜默 skip 後宣稱完整通過。iOS 26 設定頁文字是「新增鍵盤」，舊系統
  可能是「加入新的鍵盤」；UI test 同時接受中英文與兩種標籤。
- **iOS 按鍵標籤是兩個 UILabel，不是一個兩行的 attributed title**：注音鍵要同時顯示
  注音與鍵位，而聲調符號（ˊ ˇ ˋ ˙）是 spacing modifier letter，字級要放大約 1.8 倍
  才看得清。放大後若用兩行 label，第二行的鍵位數字會被推出按鍵外；改用
  `.baselineOffset` 想把符號往下拉也一樣 —— TextKit 會連帶把行框加高，結果照樣裁掉。
  所以兩個 label 各自用固定高度定位（`KeyboardView.configure`），鍵位數字才會與同排
  其他鍵齊高。改這段一定要截圖檢查整排數字是否對齊。
- **Enter 鍵是描邊畫出來的，不是字元**：`↵` 在 Android 與 iOS 系統字體下都偏細且不
  一致。座標在 `Source/Branding/enter.svg`，兩個平台各自照抄同一組數字描邊
  （`EnterGlyph.swift`／`BopomofoKeyboardView.drawEnterKey`）。**三個檔要一起改。**
  Android 端不從 SVG 讀檔 —— 該 View 全部是 Canvas 手繪，多帶一個 drawable 反而不一致。
- **iPad 不會替鍵盤畫地球鍵，iPhone 會**：iPhone 由系統在 input view 下方另外畫一排
  地球＋聽寫，iPad 沒有那一排。`TARGETED_DEVICE_FAMILY = "1,2"`，所以這支在 iPad 上
  是原生安裝、跑得起來 —— 但少了地球鍵就**出不去鍵盤**（只能去「設定」關掉它）。
  判斷依據是 `UIInputViewController.needsInputModeSwitchKey`，iPhone false／iPad true，
  照它決定功能列要不要多一顆。按鍵要用
  `addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)`
  接到 controller，才會有系統行為（點一下換下一個、長按出鍵盤清單）；自己呼叫
  `advanceToNextInputMode()` 只有點一下。接對了的話系統第一次會自己跳出
  「快速更改鍵盤」說明卡。
- **iPad 橫式不會進 compact 版面**：iPad 全螢幕時 `verticalSizeClass` 兩個方向都是
  `.regular`，所以 metrics 必須另外判斷 `userInterfaceIdiom == .pad`。iPad 使用 330pt
  高度、最大 820pt 的置中鍵盤內容；iPhone 仍依 compact height 切換 330／155pt，
  不要只靠 size class 判斷 iPad 版面。
- **在乾淨的模擬器上啟用第三方鍵盤不必手動點設定**：啟用清單是
  `.GlobalPreferences.plist` 的 `AppleKeyboards`，第三方項目就是 extension 的
  bundle ID。
  `xcrun simctl spawn <udid> defaults write -g AppleKeyboards -array "zh_Hant-Zhuyin@sw=Zhuyin;hw=Automatic" "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji" "io.github.polobread.inputmethod.chichi77.ios.keyboard"`
  重裝 App 會把選中的鍵盤重設回系統的，每次重裝都要重選一次。
- **Slack／Electron 按 ESC 會多送一個 Escape**：組字中按 ESC，Slack 取消組字後
  editor 又收到 Escape。**macOS 內建注音行為完全相同**，而原生 app（Line、
  TextEdit）正常，所以這是 Chromium 端行為：keydown 會被 mask 成 `keyCode 229` +
  `isComposing=true`，但 keyup 不經輸入法、原樣送到 DOM，輸入法端攔不到。
  **不要再往本專案查這題。**
- **公開分類詞庫必須維持匯入界線**：`DataSource/chichi77Collection` 是自動化生成、
  推論與整理的資料；長詞拆分於 2026-08-24 做過專項 review，但整體沒有全面逐筆人工
  校正，不可宣稱正確或完整。公開資料只保留中文字首、2–5 個 Unicode code point 的
  詞條；較長原詞必須依明確 review 結果選取有意義的連續片段，不可再用統計斷詞器直接
  拆分。中文字首後混有拉丁字母的詞可保留。授權與免責說明在該目錄的 `README.md` 與
  `LICENSE.txt`，更新資料時不可覆蓋。
- **GitHub Actions 封裝與 Release**：Android 與 iOS workflow 只有 `workflow_dispatch`；
  macOS 與 Windows 在推送 `v*` tag 時會先驗證 tag 必須精確等於 repository 版號
  （例如 `v1.2.4`），再發布到公開 GitHub Release。publishing run 需要 `contents: write`；
  Release 已存在就沿用，不存在才建立，workflow 絕不建立 tag 或覆寫同名資產。
  repository 是公開的，所以 artifact 在保留期間仍可能被讀者下載。workflow 會封裝包含
  `chichi77Collection` 在內的全部公開詞庫。
  - macOS 拆成兩個 job。`build` 沒有 environment 也拿不到 secret，永遠會跑，產出未簽章
    pkg 的 7 天 artifact，另外用 `ditto` 把建好的 app 打包成保留 1 天的交棒 artifact
    （`upload-artifact` 不保留 symlink 與執行權限，framework 會壞，一定要先 `ditto`）。
    `publish` 只在 `github.ref_type == 'tag'` 時跑，掛 `release` environment，簽章、
    notarize、staple 之後把 pkg zip 與 SHA-256 發布到 Release。
  - macOS 與 iOS 沒有 Windows 那個 `release_tag` 手動輸入。`release` environment 的
    tag rule 會擋掉在 branch 上跑的 `workflow_dispatch`；補救失敗的 tag run 要從 Actions
    頁面 re-run（ref 仍是 tag），或用 Run workflow 直接選那個 tag。
  - Windows 兩種產物都未簽章，`.unsigned.exe` 只供測試；Android 是 debug APK；iOS 只產
    Apple Silicon Simulator app。GitHub Actions 的 iOS TestFlight／商店上傳尚未處理，
    那需要 App Store Connect API key（`xcodebuild -allowProvisioningUpdates` 只吃 API
    key，app-specific password 餵不了）。Xcode Cloud 則由 `ci_post_clone.sh` cook 資料庫
    並以 Cloud build number 覆寫 `CURRENT_PROJECT_VERSION`；出口合規宣告已固定為不使用
    non-exempt encryption。
- **Apple 簽章刻意把私鑰放進 GitHub Actions，Windows 不放**：這是明知的破例。hosted
  runner 沒有 Windows 憑證存放區的對等機制，notarization 也只能在 macOS 上跑，所以
  `Developer ID` 的 `.p12` 以 base64 存成 secret。收斂方式：secret 一律掛在 `release`
  environment 而不是 repository secrets，該 environment 的 deployment rule 只允許
  **ref type 為 tag** 的 `v*`（設成 branch 會讓 tag 觸發的 job 全部被擋）；所有
  `actions/*` pin 到 commit SHA，避免上游搬動 tag 就等於私鑰外洩；`if: always()` 收尾
  刪掉臨時 keychain。5 個 secret：`APPLE_DEVELOPER_ID_P12`、
  `APPLE_DEVELOPER_ID_P12_PASSWORD`、`APPLE_ID`、`APPLE_APP_SPECIFIC_PASSWORD`、
  `APPLE_TEAM_ID`。簽章身分字串含法定姓名，不進 secret，在 runner 上用
  `security find-identity` 查——注意 `Developer ID Installer` 不是 codesigning 用途，
  `-p codesigning` 撈不到它。
- **臨時 keychain 有兩個一定要做的動作**：`set-key-partition-list`（不做的話 codesign
  與 productbuild 會等 GUI 授權，job 掛到 timeout），以及匯入 Apple 的中介憑證。
  Keychain Access 匯出的 `.p12` 只帶 leaf identity，不含簽發者，臨時 keychain 裡沒有
  中介 codesign 就建不出憑證鏈；workflow 直接抓
  `https://www.apple.com/certificateauthority/DeveloperIDCA.cer`，不依賴 runner image
  剛好裝了什麼。另外，本機要驗 `.p12` 時測試用的 keychain **不要放在 `mktemp -d` 底下**：
  `/var` 是 `private/var` 的 symlink，`securityd` 存正規化後的路徑，再用 `/var/...`
  去找會回報 `The specified keychain could not be found`。CI 不受影響，`$RUNNER_TEMP`
  在 `/Users/runner/work/_temp`。
- **Windows Store EXE 採 NSIS 3.12＋本機手動簽章**：`windows-2025` image 不內建
  NSIS，workflow 會透過 Chocolatey 固定安裝 3.12；不要降回 3.11，3.12 修正 elevated
  installer 使用低 integrity 暫存目錄的安全問題。`Package-Store-Windows.ps1` 正式模式
  只從 Windows 憑證存放區依 thumbprint 使用憑證，不把私鑰或密碼放進 GitHub Actions；
  會先簽 x64 DLL、x86 DLL、設定 EXE，再建立並簽署 NSIS EXE。`-UnsignedTest` 只供
  Actions／本機檢查，絕對不可上架。NSIS 使用 `/S`（大小寫有別）靜默安裝，payload
  放在版本子目錄，避免升級時已載入的舊 TSF DLL 阻擋覆寫。Partner Center 使用不可
  覆寫的版本化 HTTPS URL；自動 Release 只含 unsigned 測試資產，已簽 EXE 必須以不同
  檔名手動上傳到對應版本的既有 Release；
  ZIP 與 EXE 都必須保留 `Windows-TSF/LICENSE.txt`、
  `chichi77Collection/LICENSE.txt` 與其餘授權告知。NSIS 的同意頁順序固定為
  `LICENSING.md`（混合授權範圍）→ Windows frontend MIT → Yahoo BSD；不可把 MIT
  放在範圍說明之前而誤導成整個產品只有 MIT。
- **GitHub 的 `windows-2025` 目前是 VS2026 image**：2026-08-24 實跑得到
  `windows-2025-vs2026`，只有 Visual Studio 18 2026；用 `Visual Studio 17 2022`
  generator 會立即回報找不到 Visual Studio。hosted workflow 必須使用
  `windows-x64-vs2026` 與 `windows-x86` preset；VS2022 presets 只留給仍安裝
  Visual Studio 2022 的本機環境。
- **Android workflow 不可啟用 `setup-java` 的 Gradle cache**：repo 內歷史檔案
  `Source/ExternalLibraries/UnitTest++/UnitTest++` 在 Unix checkout 是指向自己的 symlink；
  `setup-java@v5` 的 cache dependency 掃描會跟隨它並以 `ELOOP` 失敗，早於 Gradle
  建置。Android 不讀該目錄，目前刻意不啟用這層 cache；不要在未排除循環 symlink
  前加回 `cache: gradle`。
- **Android 的 `gradlew` 必須保留 Git executable bit**：Windows 工作目錄不會直接
  顯示 Unix 執行權限，提交前以
  `git ls-files -s Source/Loaders/Android-IME/gradlew` 確認模式是 `100755`。若變成
  `100644`，Ubuntu runner 執行 `./gradlew` 會立刻以 exit 126／Permission denied
  失敗；用 `git add --chmod=+x Source/Loaders/Android-IME/gradlew` 修復。
- **Android Google Play 發布只走獨立 environment**：
  `.github/workflows/android-play-release.yml` 使用 `google-play-release` environment 的
  5 個 upload key／service account secrets，建 signed AAB 後只推 internal track；
  package name 必須是 `tw.chichi77.keykey.android`，不是舊範例的
  `com.polosoft.chichi`。tag 觸發時必須精確等於 repository 版號，manual run 則使用所選
  ref 的版號；重跑相同 versionCode 會被 Play 拒絕。upload certificate 本來就是
  self-signed，`jarsigner -verify -strict` 會因沒有公有 CA chain 誤判失敗，workflow
  只能用 `jarsigner -verify` 確認 AAB 有簽章。正式 keystore 只還原到 runner temp，
  Gradle 關閉 configuration cache，job 收尾刪除該檔。
- **Android Supporter entitlement 與 IME 必須保持分離**：Google Play Billing 9.1.0
  只由 `SupporterBillingManager` 在設定頁建立；`BopomofoImeService` 只能讀
  `SupporterState` 的 SharedPreferences cache，Billing／網路失敗不得進入輸入路徑。
  `chichi_supporter` 是非消耗性 one-time product，不可 consume；只有 `PURCHASED` 才
  授權並補 acknowledge，`PENDING` 不授權。PBL 9 的一次性商品要從
  `OneTimePurchaseOfferDetails` 選 `purchaseOptionId == "buy"`，並把該項的 offer token
  傳入 `BillingFlowParams`；不要退回舊式只傳 ProductDetails 的做法。試用期固定以
  `PackageInfo.firstInstallTime` 算 30 天，滿 30 天的邊界即 expired，解除安裝重裝重算。
- **macOS／iOS cooker 的 people exclusion 來自公開分類詞庫**：
  `DatabaseCooker/Makefile` 會從 `DataSource/chichi77Collection/phrase.people-*.tsv`
  產生人名 exclusion，再匯入 McBopomofo 與 29 個分類詞庫。不要移除檔案存在時才執行
  `awk` 的保護；資料目錄暫時不完整時仍應能產生空 exclusion，避免錯誤訊息誤導。

---

## TODO

### GitHub Actions

- [ ] Android 與 iOS Simulator workflow 仍需從 GitHub Actions 頁面手動重跑，確認
      hosted runner 的工具版本、7 天 artifact 與公開 `chichi77Collection` 都被封裝。
      2026-08-27 的 `v1.2.4` tag 已實跑 macOS 與 Windows：兩個 workflow 都成功，
      Windows 公開 Release 含 ZIP、unsigned EXE 與各自 SHA-256；macOS 的 build
      artifact 也包含公開詞庫。先前 Windows 的 VS2026 與 Android 循環 symlink 修正中，
      Windows 已由本次 tag run 驗證，Android 仍待重跑。
- [x] macOS `publish` job 已於 2026-08-27 的 `v1.2.4` 首次實跑成功（run
      `33031272995`，build 18m25s、publish 31m20s）：臨時 keychain、
      `set-key-partition-list`、Apple 中介憑證鏈、簽章、notarytool、staple、
      `stapler validate`、`spctl --assess --type install -vv` 與 Release 上傳全部通過；
      Release 含 signed pkg zip 與 SHA-256。
- [ ] 從 `v1.2.4` Release 下載 signed pkg zip，在另一台 Mac 實際安裝並確認不再觸發
      Gatekeeper 警告。
- [ ] 兩張 Developer ID 憑證掛在 G1 中介之下，`notAfter` 被 CA 自己的到期日砍到
      **2027-02-01**（不是常見的 5 年；G2 中介到 2031）。到期後簽不出新版本，已 staple
      的舊產物仍有效。值得從 developer.apple.com 網頁重新申請，看 Apple 是否改簽在 G2。

### 舊碼清理

- [ ] **已確認可在未來刪除的舊碼**：下列目錄不在目前支援的 macOS IMK、Windows
      TSF、Android、iOS 建置或封裝路徑內，只屬於已淘汰的 Windows IMM／macOS TSM
      frontend、其附屬工具或獨立實驗。刪除時必須在同一個 commit 清掉
      `Source/Takao.sln`、`Source/Takao.xcodeproj` 的 legacy target、
      `Source/Distributions/Takao/makeall-osx.sh` 與 `Source/Utilities/version-upper.rb`
      等留下的失效引用，再完整驗證四平台目前的建置入口：
      - `Source/Loaders/Windows-IMM`
      - `Source/PreferenceApplications/Windows`
      - `Source/Loaders/OSX-TSM`
      - `Source/Studies`
      - `Source/Utilities/CinInstaller`
      - `Source/Utilities/HomophoneFilter`
      - `Source/Utilities/PhraseEditor/Windows`（只刪 Windows 子目錄；OSX 仍在打包）
      - `Source/Distributions/Takao/Installer-OSX-TSM`
      - `Source/Distributions/Takao/Installer-Windows`
- [ ] **需要再確認才能刪除**：下列目錄沒有出現在目前四平台的自動建置／封裝入口，
      但可能仍供人工簽章、更新資料、舊式 DMG 製作或一次性維護使用。刪除前先確認
      本機／外部發布流程沒有依賴，並追查動態路徑與預編譯工具的來源：
      - `Source/Utilities/SignatureMaker`
      - `Source/Utilities/TextOverlay`
      - `Source/Utilities/VersionInfoMaker`
      - `Source/Distributions/Takao/Installer-OSX-DB`
      - `Source/Distributions/Takao/Installer-OSX-ExtraModules`
      - `Source/Distributions/Takao/Installer-OSX-IMK`
      - `Source/Distributions/Takao/OnlineDataTemplates`
      - `Source/Distributions/Takao/PrecompiledTools`
      - `Source/Distributions/Takao/VersionInfo`
- `DataSource/chichi77Collection` 仍供四平台資料生成與封裝使用；
  `Source/Loaders/CrossPlatform`、`Source/WebResources`、
  `Source/Distributions/Takao/Installer-OSX-UI`、
  `Source/Distributions/Takao/Installer-OSX-Help` 與 `Source/Utilities/PhraseEditor/OSX`
  仍由目前 macOS IMK target 編譯、複製或打包。以上均**不在刪除範圍內**。

### macOS

- [ ] 在實體 Mac 截圖確認 Preferences 三種語系新增的候選窗比例列不再覆蓋模組說明，
      以及直式／橫式候選窗在「跟隨顯示器、75%、90%、100%、200%、350%」下的字體、
      按鍵角標、翻頁控制與點選
      hit testing 都一起縮放；Windows 環境只能做原始碼與 plist 靜態檢查。
- [ ] 版號集中：`Takao-macOS.xcconfig` 設 `MARKETING_VERSION` 與
      `CURRENT_PROJECT_VERSION`，4 個 plist 改用 `$(MARKETING_VERSION)`（8 處 → 1 處）。
      注意 Xcode.app 建置路徑吃不到該 xcconfig，改完會拿到空版號。
- [ ] `Takao-macOS.xcconfig` 未接進 pbxproj 當 project 層級的
      `baseConfigurationReference`（專案有 5 個 configuration：Debug／Debug64／
      DebugPPC／Release／Release64）。接進去可讓兩種建置路徑一致，代價是手改 pbxproj。
- [ ] 去 Yahoo 化未完成：隨主程式打包的 Preferences、PhraseEditor、DownloadUpdate、
      InstallerHelp 仍有使用者可見的 Yahoo 字串（如「Yahoo! KeyKey is not running」、
      `NSHumanReadableCopyright`）。注意硬規則第 5 條，BSD 要求保留的部分不能動。

### Windows

- [ ] 取得受信任的正式程式碼簽章憑證後，實跑 `Package-Store-Windows.ps1`，確認三個
      PE 與 NSIS EXE 的 RFC 3161 時間戳記；目前只驗證 `-UnsignedTest` 能編譯並含完整
      payload。還要在乾淨 Windows 11 VM 測 `/S` 安裝、靜默解除安裝、升級、x64
      應用程式及 32-bit Office 載入，再把已簽 EXE 手動放到不可覆寫的版本化
      GitHub Release URL 供 Partner Center 抓取。
- [ ] `Package-Windows.ps1` 的 `$Version` 與 `CMakeLists.txt` 重複，可改成從
      `CMakeLists.txt` regex 讀取。
- [ ] 安裝 2026-08-24 的語言列生命週期修正版後，在 Android Studio 反覆以
      `Ctrl+Space` 切換中英文並確認不再產生 `studio64.exe`／`KeyKeyTsf_x64.dll`
      Application Error；x64／x86 Release 已建置，x64 的 3 個 CTest 已通過。
- [ ] 為 `KeyKeySettings.exe` 增加 UI automation：目前只有啟動 smoke test，仍需人工
      驗證一般／注音／關聯詞三頁、五種注音鍵盤、直橫選字窗、十種比例、四種配色、Ctrl+\\、
      提示聲與 CNS11643 開關在實際 TSF host 中會即時套用；候選窗另需在 100%／225%
      與兩台不同縮放比例的螢幕間移動驗證字型、間距及游標定位。
- [ ] Ctrl／Alt 快捷鍵放行時，候選或聯想詞面板會留在畫面上（引擎收不到該鍵，
      `updateCandidateWindow` 不會被呼叫）。**與 macOS 現行行為對稱**，屬「快捷鍵
      不改動組字狀態」的設計決定。要改請兩個平台一起改，不要單邊處理。

### iOS

- [ ] 五台 Simulator 已加入共用 XCUITest target 與
      `run-simulator-tests.sh`；2026-09-02 的 `--host-only` 基線為 79 個 Swift tests 與
      五台各 3 個 UI tests 全部通過（含 App 內授權告知）。仍須逐台切到琦琦注音跑
      extension-required 模式並把結果記進 `IOS_SIMULATOR_TEST_PLAN.md`。系統輸入切換器
      不能由 XCUITest 穩定選定，不得把 opt-in 成功當成 extension 功能通過。
- [ ] 在實機或 Simulator 測試 `default`、`asciiCapable`、`numbersAndPunctuation`、URL、
      numberPad、phonePad、namePhonePad、emailAddress、decimalPad、webSearch、
      asciiCapableNumberPad；確認直橫式 disabled key 無法點擊、VoiceOver 朗讀為 disabled，
      並確認 secure、phonePad、namePhonePad 由 iOS 換回系統鍵盤。79 個 Swift 測試與
      iOS 26.5 iPhone 17 Pro Simulator App／extension build 已於 2026-09-02 通過；
      `selectionDidChange` 的游標移動清理、inline marked text 與 MODE／SHIFT 預覽仍須依
      `IOS_SIMULATOR_TEST_PLAN.md` 在五台受控 Simulator 跑完 A–K 才算完整驗證。

- [ ] 版號集中：`MARKETING_VERSION` 目前寫在 pbxproj 的四個 configuration 裡，
      可抽成 xcconfig（4 處 → 1 處）。
- [ ] VoiceOver：**元素樹已驗證，朗讀本身還沒聽過。** 2026-08-23 用臨時的
      hierarchy dump（模擬 VoiceOver 遇到 accessibility element 就停止下探的走法）
      確認直式共 57 個元素，順序為狀態列 →候選列（上一頁／「第 n 個候選，字」／下一頁）
      →四排注音鍵→功能列，每個都有中文標籤，聲調鍵唸注音符號而不是鍵位數字，
      空候選格已排除。**尚未做的**：實際開 VoiceOver 聽朗讀與 rotor 行為、
      accessibility audit。
- [ ] 設定面板每列的文字與開關是兩個獨立元素，VoiceOver 會把詞庫名稱唸兩次
      （系統「設定」App 是合併成一個元素）。要修就把整列包成一個
      `UIAccessibilityElement`，或改用 `UITableViewCell`。
- [ ] iPad 版面沒有調過：目前兩個方向都吃直式的 330pt 與 iPhone 字級，按鍵被拉成
      寬扁形。要做就得加一組 iPad metrics（judgement：高度拉到約 380–420pt、字級放大、
      或改成不佔滿寬度的分段版面）。功能面已可用，地球鍵也有了。
- [ ] 直式聲調符號放大 1.8 倍，**橫式刻意沒放大** —— 橫式把注音與鍵位併成一行
      （`ㄅ 1`），只放大其中一個字會高低不齊，且橫式那排只有 26pt。要改的話得先
      拆成兩個 label。

### Android

- [ ] 在 Android 實機依序測一般、Email、URL、電話、整數、小數、日期時間、密碼、姓名、
      地址、搜尋、簡訊／長文字與 ASCII 欄位；直橫式各確認 disabled key 無 hit／無震動，
      軟 Enter 的完成、下一個、搜尋、傳送、前往、上一個及 App 自訂 `actionLabel`／
      `actionId` 會觸發正確 action，而 USB／藍牙 Enter 仍送 plain Enter，且實體字元不受
      觸控欄位限制。JVM 策略測試已加入；2026-08-30 已通過
      `lintDebug testDebugUnitTest assembleDebug`，仍需在實機用自訂 editor 驗證 action callback。

- [ ] 在 Android 實機驗證組字／候選開啟時，以觸控、滑鼠及 App 程式改變游標或選取範圍
      會清除舊引擎狀態，IME 自己逐鍵更新 composing、確定候選與建立關聯詞則不會被誤清；
      同時截圖確認直橫式文字／注音／符號鍵預覽約放大 1.4 倍、邊緣鍵不超出畫面、滑出與
      放開會消失，設定關閉後不再顯示。2026-08-30 已在 Pixel 9a 驗證設定列正常顯示，
      觸控按住預覽鍵無執行期錯誤，並以 composing `ㄅ` 移到字首後再輸入 `ㄚ` 得到
      `ㄚㄅ`，另以 `ㄅㄚ` 選取尾字後輸入 `ㄉ` 得到 `ㄅㄉ`，確認游標與 selection range
      都沒有沿用舊 reading；裝置的 ADB 截圖輸出全黑，預覽外觀與 App 程式改動仍待
      人工畫面驗證。

- [ ] 接上真正的 USB／藍牙鍵盤，確認底部候選列為 12 個等寬按鍵（9 候選、Emoji、
      `ㄅ／英`、`半／全`），沒有 ▲／▼；驗證點擊後兩鍵可切換，並再驗證 `Ctrl+Space`、
      `Shift+Space` 的 keydown／keyup／長按，以及全形 `Ａｚ０９！～　`、切回半形和
      reading／候選保留。2026-08-30 已加入 modifier bit、全形映射與引擎單元測試並通過
      `lintDebug testDebugUnitTest assembleDebug`；ADB `input keycombination` 直接送到 editor，
      不會經過 `InputMethodService.onKeyDown`，不能代替實體鍵盤驗證。

- [ ] 先在 Play Console 手動完成首次 app／AAB、Play App Signing 與 upload certificate
      登記（Publishing API 不能代替首次建立 app），再把 5 個 secrets 放進
      `google-play-release` environment 並實跑 `Android Play Release`。首次手動上傳若已
      使用目前 versionCode，workflow 必須等下一版，不能重送相同 code。成功進 internal
      testing 後，用 license tester 實測 purchase option `buy` 的 localized formatted
      price、新購、取消、PENDING 轉 PURCHASED、acknowledge、清除 app data／換機後恢復
      購買，以及離線或沒有 Play Store 時仍可完整輸入。直接 sideload 的 debug APK 無法
      完整驗證 Play 商品設定。

- [x] Android 直式聲調符號已比照 iOS 放大 1.8 倍並以 glyph bounds 校正上緣；橫式兩端
      都維持同列正常字級，於 2026-08-30 完成。
- [ ] Enter 鍵描邊繪製（`drawEnterKey`）已於 2026-08-24 通過
      `lintDebug testDebugUnitTest assembleDebug` 編譯驗證；仍需在模擬器或實機截圖，
      比對 Enter 鍵外觀與 iOS 一致。
- [ ] 增加會在模擬器或實機啟動 `BopomofoImeService`，並驗證組字、觸控候選列、
      外接鍵盤一般候選 `1–9`／關聯詞 `Shift+1–9`、一次性注音 Shift、英文大小寫與
      兩套數字符號版面、`ㄋㄧˇ` Backspace 退音及複合 Emoji 一次刪除、
      關聯詞接續與全部關閉、符號／Emoji 各 10 頁及循環翻頁、外接鍵盤
      `Ctrl+Space`／`Shift+Space`／`Ctrl+,`／`Ctrl+.`／`Ctrl+0`／`Ctrl+1` 與全半形的
      smoke test；另需驗證實體鍵盤浮動候選預設關閉、直橫排列、游標四邊翻轉、
      不支援 `CursorAnchorInfo` 時的底部中央備援、觸控選字、方向鍵反白、Enter 與 ESC；
      2026-08-24 已在 Pixel 9a 的 Google 搜尋欄實測單一 composing `ㄅ` 按 Backspace
      會完整移除、不會留下失去底線的 `ㄅ`；
      目前 JVM 單元測試與 APK 建置無法攔截 D8／R8 合成類別漏包及
      `InputConnection` 互動之類的執行期問題；也應截圖檢查底列沒有與系統導覽區重疊，
      並確認直橫式 11 欄按鍵等寬、橫式文字沒有裁切。
