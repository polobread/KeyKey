# AGENTS.md — 開發交接

macOS、Windows 與 Android 由不同環境輪流開發，這份檔案是各平台的交接點。

**接手時：** 先讀完本檔，再讀 [BUILDING.md](BUILDING.md)。動任何 `Source/Frameworks`
或 `Source/ModulePackages` 底下的檔案前，先看「跨平台影響」。

**交接前：** 更新本檔的 TODO 與「已知陷阱」。調查出來的結論寫進來，下一個代理才
不會重跑一遍。

---

## 硬規則

1. commit 訊息與任何檔案內容都**不得出現 AI 工具或模型名稱**，也不要加
   `Co-Authored-By` trailer。
2. 產品內（UI、About 視窗、字串資源）**不得出現開發者或工具署名**。
3. commit author／committer 必須是 `Polo <polobread@yahoo.com.tw>`。
4. `git add` **逐檔指定**，不要用 `git add -A` 或 `git add .`。工作區常有未追蹤的
   編輯器暫存檔。
5. 以下是 BSD 條款要求，**移除會違反授權**：各原始檔的
   `Copyright (c) 2012, Yahoo! Inc.` 標頭、`LICENSE.txt`、README 的 BSD 全文、
   About 視窗的出處標示、Info.plist 的「非 Yahoo 官方產品」聲明。

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
| `Source/Loaders/Windows-TSF/CMakeLists.txt` | `project(... VERSION x.y.z)` |
| `Source/Loaders/Windows-TSF/Package-Windows.ps1` | `$Version` 參數預設值 |

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
| `Source/Loaders/Android-IME/` | 僅 Android；建置時唯讀 `Source/DataTables`、`DataSource/McBopomofo` 與可選的相鄰私人詞庫 |

模組註冊不對稱，看共用模組時要記得：

- **macOS** 載入 TraditionalMandarin、SmartMandarin、AssociatedPhrase、Generic、
  FullWidthCharacter、HanConvert、BopomofoCorrection、YKAFOneKey、OVAFEval
- **Windows** 只載入 TraditionalMandarin 與 AssociatedPhrase（SmartMandarin 需要
  的中研院語料不在開源釋出內）
- **Android** 以 Java 重作 TraditionalMandarin 的單音節組字、選字與 AssociatedPhrase
  關聯詞，直接解析 `bpmf-ext.cin` 與詞庫文字資產；目前不載入 C++ framework 或
  SmartMandarin

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
  與可選的相鄰 `chichi77Collection/phrase.*.tsv` 複製到 generated assets；私人詞庫
  不在 KeyKey 版控內，含私人資料的 APK 只能交給有權使用的人。

---

## 已知陷阱（不要重複調查）

- **macOS codesign**：`codesign --verify --deep --strict` 會失敗（framework 的
  `Headers` 目錄是空的、封印卻記錄了那些檔案）。**不影響本機安裝與使用**，裝不
  起來時不要往這裡查；但對外 notarize 會被卡。
- **macOS 首次安裝看不到輸入法**：Text Input Services 只在登入時掃
  `/Library/Input Methods`，換過 bundle id 就等於首次安裝，必須登出再登入，
  `lsregister` 手動註冊無效。確認是否註冊：
  `defaults read com.apple.HIToolbox | grep -c chichi77`
- **macOS pkg 安裝**：`pkgbuild` 預設把 app bundle 標成 relocatable，`installer`
  會把 payload 寫到別處卻回報成功。已用 `Installer/build.sh` 的
  `BundleIsRelocatable false` 處理；安裝後仍務必
  `ls -ld "/Library/Input Methods/chichi77 KeyKey.app"` 確認。
- **Windows 安裝**：必須先完整解壓縮、複製到本機 `C:\` 路徑，才執行 `Install.cmd`。
  UAC 提升權限後可能存取不到網路磁碟／NAS／UNC 來源。
- **Android 主程式不要用 Java `record`**：AGP 9.2.0 曾把 record 轉譯成
  `com.android.tools.r8.RecordTag`，卻未把該合成類別包進 debug APK；Android 17
  會在建立 `BopomofoImeService` 時以 `NoClassDefFoundError` 崩潰。`assembleDebug`
  與 JVM 單元測試都不會發現。現行程式改用一般 immutable class；工具鏈修正並經
  實機驗證前不要改回 record。
- **Android 選字不可先結束 composing**：`InputConnection.finishComposingText()` 會把
  當前注音讀音直接確定送出；若再 `commitText()` 候選字，輸入區會變成
  `ㄋㄧˇ你`。選字時應直接以 `commitText()` 取代 composing region，之後再依引擎
  狀態更新或結束組字。
- **Android 候選翻頁是循環式**：候選開啟時，▲、▼、左右滑動、`Page Up`、
  `Page Down` 與空白鍵都共用 `changePage()`；第一頁的上一頁是最後一頁，最後一頁
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
  仍固定 155dp，六排使用橫式小字級，不要恢復舊的左右分割候選。
- **Android 觸控 Shift 不等於實體 Shift**：注音版按 Shift 只暫時顯示英文小寫，
  並把雙標籤從「注音在上、鍵位在下」交換成「鍵位在上、注音在下」，輸入下一個
  觸控字元後立即回注音；由功能列切入的英文版按 Shift 才會持續切換大小寫，且大寫時
  數字排換成 `!@#…`。數字符號模式的 Shift 不離開該模式，只切換兩套各 44 鍵的
  符號頁。實體 Shift 只當該次硬體按鍵的修飾鍵，不能改變觸控版面。
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
  膚色與 ZWJ Emoji 一次刪乾淨，不要改回固定 `deleteSurroundingText(1, 0)`。
- **Android 外接鍵盤候選列也要保留底部系統區**：候選列依序為 ▲、9 個候選、▼、
  Emoji，直式／橫式分別在下方保留 40dp／35dp，避免 Android 的多國語系地球鍵
  遮住控制項。Emoji 必須在沒有中文字候選時仍可按。所有候選角標都固定顯示 `1–9`；
  關聯詞雖以 Windows 式 `Shift+1–9` 選取，也不可把角標改成 `!@#$%^&*(`。
- **Android 外接鍵盤的 Ctrl 快捷鍵要先於修飾鍵攔截判斷**：`Ctrl+Space` 只在注音與
  英文間切換，`Ctrl+,`／`Ctrl+.` 輸入全型 `，`／`。`；`Ctrl+0` 與 `Ctrl+1` 則比照
  macOS `OVIMTraditionalMandarin.cpp` 的 `_punctuation_list`，開啟與觸控「符」相同的
  90 個符號候選。組字 reading 尚未清空時，標點與符號快捷鍵須保留 reading，不可
  丟掉使用者正在組的注音。快捷鍵的 keydown 與 keyup 都要吃掉，長按不可重複觸發。
- **Android 關聯詞庫是可選的 30 個文字資產**：`generateAssociatedPhraseAssets` 固定
  從 `DataSource/McBopomofo/phrase.occ` 加入小麥；若 KeyKey 同層存在經授權的
  `chichi77Collection`，再加入 29 個 `phrase.*.tsv`。不要把私人資料複製進 KeyKey
  原始碼。設定首次預設小麥，但 SharedPreferences 已存在空集合時代表使用者刻意
  全部關閉，不能偷偷恢復預設。小麥中與三個 `people-*` 詞庫重疊的人名必須先排除，
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
- **Slack／Electron 按 ESC 會多送一個 Escape**：組字中按 ESC，Slack 取消組字後
  editor 又收到 Escape。**macOS 內建注音行為完全相同**，而原生 app（Line、
  TextEdit）正常，所以這是 Chromium 端行為：keydown 會被 mask 成 `keyCode 229` +
  `isComposing=true`，但 keyup 不經輸入法、原樣送到 DOM，輸入法端攔不到。
  **不要再往本專案查這題。**

---

## TODO

### macOS

- [ ] 版號集中：`Takao-macOS.xcconfig` 設 `MARKETING_VERSION` 與
      `CURRENT_PROJECT_VERSION`，4 個 plist 改用 `$(MARKETING_VERSION)`（8 處 → 1 處）。
      注意 Xcode.app 建置路徑吃不到該 xcconfig，改完會拿到空版號。
- [ ] `Takao-macOS.xcconfig` 未接進 pbxproj 當 project 層級的
      `baseConfigurationReference`（專案有 5 個 configuration：Debug／Debug64／
      DebugPPC／Release／Release64）。接進去可讓兩種建置路徑一致，代價是手改 pbxproj。
- [ ] 去 Yahoo 化未完成：隨主程式打包的 Preferences、PhraseEditor、DownloadUpdate、
      InstallerHelp 仍有使用者可見的 Yahoo 字串（如「Yahoo! KeyKey is not running」、
      `NSHumanReadableCopyright`）。注意硬規則第 5 條，BSD 要求保留的部分不能動。
- [ ] 未被任何建置引用的舊目錄仍保留（`Source/Loaders/Windows-IMM`、
      `Source/PreferenceApplications/Windows`、`Source/Loaders/OSX-TSM`、
      `Source/Studies`，約 700 檔）。**刻意不刪**，不要自行清理。

### Windows

- [ ] `KeyKeyEngine.cpp` 的 `wantsKey()` 對 `event.control || event.alt` 一刀回
      false，導致 TraditionalMandarin 自己的 `_ctrl_opt_*`（Ctrl+Alt+字母／標點）
      與 Ctrl+0／Ctrl+1 標點列表從 port 第一版起就沒生效。修法是在
      `TextService::isPotentialKey` 呼叫 `wantsKey` 之前加白名單，但有三個前提：
    - **白名單只能放資料庫保證命中的組合。** `queryAndCompose` 在查不到且 reading
      為空時回 `false`，會造成 `OnTestKeyDown` 回 TRUE 但 `OnKeyDown` 回 FALSE，
      某些 host 會直接吃掉該鍵。
    - 白名單的真實來源是 `Source/DataTables/bpmf-punctuations.cin`（不是 KeyKey.db），
      灌進 `Mandarin-bpmf-cin` 這張表。`_ctrl_opt_*`、`_ctrl_<標點>` 與
      `_punctuation_list` 都由 TraditionalMandarin 實作，Windows 可以全數放行
      （含 macOS 收不到的 `:` `"` `<` `>` `?` `[` `]`，見「已知陷阱」）。
    - Ctrl+0／Ctrl+1 在 Windows 與瀏覽器縮放／切分頁、Excel 儲存格格式衝突，建議
      不放行，標點列表另尋入口。
- [ ] `Package-Windows.ps1` 的 `$Version` 與 `CMakeLists.txt` 重複，可改成從
      `CMakeLists.txt` regex 讀取。
- [ ] Ctrl／Alt 快捷鍵放行時，候選或聯想詞面板會留在畫面上（引擎收不到該鍵，
      `updateCandidateWindow` 不會被呼叫）。**與 macOS 現行行為對稱**，屬「快捷鍵
      不改動組字狀態」的設計決定。要改請兩個平台一起改，不要單邊處理。

### Android

- [ ] 增加會在模擬器或實機啟動 `BopomofoImeService`，並驗證組字、觸控候選列、
      外接鍵盤一般候選 `1–9`／關聯詞 `Shift+1–9`、一次性注音 Shift、英文大小寫與
      兩套數字符號版面、`ㄋㄧˇ` Backspace 退音及複合 Emoji 一次刪除、
      關聯詞接續與全部關閉、符號／Emoji 各 10 頁及循環翻頁、外接鍵盤
      `Ctrl+Space`／`Ctrl+,`／`Ctrl+.`／`Ctrl+0`／`Ctrl+1` 的
      smoke test；目前 JVM 單元測試與 APK 建置無法攔截 D8／R8 合成類別漏包及
      `InputConnection` 互動之類的執行期問題；也應截圖檢查底列沒有與系統導覽區重疊，
      並確認直橫式 11 欄按鍵等寬、橫式文字沒有裁切。
