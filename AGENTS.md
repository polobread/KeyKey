# AGENTS.md — 開發交接

macOS、Windows、Android 與 iOS 由不同環境輪流開發，這份檔案是各平台的交接點。

**接手時：** 先讀完本檔，再讀 [BUILDING.md](BUILDING.md)。動任何 `Source/Frameworks`
或 `Source/ModulePackages` 底下的檔案前，先看「跨平台影響」。

**交接前：** 更新本檔的 TODO 與「已知陷阱」。調查出來的結論寫進來，下一個代理才
不會重跑一遍。

**Linux 原生版（開發中）：** 先讀 [LINUX_DEVELOPMENT_PLAN.md](LINUX_DEVELOPMENT_PLAN.md)
與 [LINUX_TEST_PLAN.md](LINUX_TEST_PLAN.md)。首版目標為 1.2.8，第一階段以 Windows TSF
目前實際提供的全部功能為對標，包含 Standard、ETen、ETen26、Hsu、Hanyu Pinyin
五種傳統注音布局、關聯詞、候選操作與其設定。已完成但不在 Windows 基線內的 Linux
切片不需移除，保留日後擴充可能；候選學習／動態頻率、注音自動修正與 F12–F15
目前不加入。新建 Linux-only 引擎與 IBus／Fcitx 5 整合，不修改或連結既有
KeyKeyEngine／OpenVanilla 核心。2026-09-12 已完成規劃、四平台版號 1.2.8 同步及
第一段 Linux-only engine／Fcitx 5 垂直切片；local Ubuntu 24.04 Xvfb 已以 GTK 3、
GTK 4 與 Qt 6 跑過各自適用的完整第一階段真實輸入矩陣，
並含五種注音布局、
候選鍵盤／滑鼠操作、
標點／符號候選、30 套內建關聯詞、
直／橫候選設定、中英文模式與全半形、XDG 錯誤提示聲、Fcitx 原生設定 schema 與
Ubuntu 22.04／24.04
Debian 開發套件生命週期驗證；Ubuntu 22.04／24.04 hosted Linux CI 基線已通過，
隔離 GNOME X11 的 76 案 desktop-safe gate 亦已通過；完整 GNOME 登入、XWayland 與
native Wayland 仍未跑。版號更新與這些 local
測試都不代表 Linux 已可發布。
**主要支援／最完整測試環境是 Ubuntu Desktop 24.04 LTS + Fcitx 5（GNOME）**；
先完成 X11、native Wayland、XWayland 的完整打字／視窗／App／套件驗收，再完成
近四年的 Ubuntu 版本。Debian／Fedora 已移到 future TODO，不得在 Ubuntu 完成前
新增 required job 或把它們列為 Ubuntu 1.2.8 的發布 blocker。完整版本清單見計畫。

### 2026-09-13 Windows 11 主機接手 Linux 原生版

- PR #2 已合併到 `origin/master` 的 `d7a00a8`，遠端 `v1.2.8` 隨後刪除；本機
  `v1.2.8` 已 rebase 到同一提交，後續也已重新建立 `origin/v1.2.8` 並設為 upstream。
  不可把曾存在的舊七筆歷史 merge 回來。正式詞庫保留原始內容；Linux 測試與文件
  不使用「中國／中国／中!」案例。
- 在 Windows 上接續的是 **Linux Fcitx 5 frontend**，不是 Windows TSF。建議從
  WSL2 Ubuntu 的 shell 執行，repository 放在 WSL 的 Linux filesystem（例如
  `/home/.../KeyKey`），並以 WSL 內的 Git 保留 LF 與 executable bit；不要從會自動
  轉 CRLF 的 Windows checkout 執行這批 Bash script。
- Docker Desktop、Rancher Desktop 或其他相容引擎皆可，但必須使用 Linux containers，
  且 WSL 內的 `docker info` 能直接連到 engine。一般 x64 Windows 主機的 `uname -m`
  是 `x86_64`，`ci/dev.sh` 因此直接使用 `linux/amd64`，可避免 Apple Silicon 執行
  amd64 package gate 時的模擬成本。2026-09-13 已在 Windows 11 + WSL2 Ubuntu
  24.04.4、WSL ext4 checkout、rootless Docker 29.8.0 實跑 warm `ci/dev.sh verify`：
  2 個 CTest 與 17 個 X11 案例全數通過，總耗時 18.22 秒。當時 dependency image 與
  container 已存在，不能把這筆時間當成全新主機的 cold build；後續擴充
  T02 聲調後的 2 個 CTest 與 18 個 X11 案例亦在同一 WSL 環境通過。
  下次乾淨環境仍須記錄 cold build。
- 受限制的自動化行程可能無法開啟 rootless Docker 的
  `/run/user/UID/docker.sock`，即使 socket owner、mode 與一般 WSL shell 都正常；
  這時 `docker info` 會顯示 `permission denied`。先在一般 WSL shell 重跑
  `docker info`；若正常，應允許該 sandbox 存取本機 socket，不要改用 `sudo docker`、
  `chmod 666` 或隨意改群組。這是呼叫行程隔離，不是 Docker daemon 未啟動。
- Rootless Docker 的 bind mount 會把 WSL checkout owner 顯示成 container root；
  one-shot package／X11 scripts 因此會從 `docker info` 偵測 rootless，改以 container
  UID/GID 0 寫 `out/`。Rootful engine 才沿用 host UID/GID。不可一律傳
  `--user "$(id -u)"`，否則 rootless engine 會在 CMake 建立 build directory 時得到
  `Permission denied`；artifact cleanup 的 chown 也必須使用同一組 container-side
  UID/GID。
- 2026-09-13 同一台 WSL2／rootless Docker 主機已實跑兩個 one-shot gate：Ubuntu 22.04
  的 Fcitx 5.0.14 build、2/2 CTest、lintian、安裝／移除／重裝全數通過；Ubuntu 24.04
  的 preview 安裝、release 升級、移除／重裝全數通過；加入注音 Big-5 過濾後再實跑
  初裝與升級各 21 個純鍵盤案例，重裝後完整 22 案例也全數通過。
  另直接執行 `run-ubuntu-24.04-x11-e2e.sh` 的原 17/17 基線亦通過，證明 rootless UID
  選擇同時適用 package 與獨立 X11 路徑；這些仍不是 GNOME／native Wayland 驗收。
- 長駐 container 把 named volume 掛在 `out/stage`，但 verify 會刪除再建立其下的
  `dev-container-ARCH`。`initialize_writable_paths` 必須 `chown` stage 的掛載父目錄
  `${stage_dir%/*}`，不能只改 child；否則 root 建立的新 volume 會讓非 root 開發使用者
  在 staging 時遇到 `Permission denied`。修改 volume layout 時要保留此不變條件。
- 從 repository 根目錄開始；第一次 `up` 會建立 dependency image，後續命令會重用
  同一 container 與 named-volume 編譯快取：

  ```sh
  git fetch origin --prune
  git switch v1.2.8
  Source/Loaders/Linux-IME/ci/dev.sh up
  Source/Loaders/Linux-IME/ci/dev.sh status
  Source/Loaders/Linux-IME/ci/dev.sh test
  Source/Loaders/Linux-IME/ci/dev.sh verify
  ```

  日常迭代先用 `test` 或 `e2e CASE-ID`；`verify` 才跑完整 staged 檢查與 83 個
  Xvfb/GTK3/GTK4/Qt6/Fcitx 案例。`run-debian-package.sh ubuntu-24.04` 是乾淨安裝、升級、移除、
  重裝的 amd64 套件 gate，只在里程碑跑，不要每次修改都跑。Windows 桌面本身不能
  取代 GNOME／native Wayland 驗收；Xvfb 通過後仍須另找真 Linux desktop／VM。
- 目前 WSL 移交狀態：warm container 的 CTest 2/2 與完整 X11 suite 83/83
  通過；案例涵蓋注音候選直接接下一音節、五布局 reading 中無效裸 `\` 與 Ctrl 快捷鍵，以及
  空狀態／reading／候選的 Backspace 與 Escape 邊界；也涵蓋每個 input context 的
  中英文模式、`Ctrl+\`、單按 Shift、Caps Lock、英文全半形，以及 reading／候選期間
  Ctrl／Alt 快捷鍵與 press／release 邊界；長按 `Ctrl+\` 只會切換一次。
  T10 另以 GTK3／GTK4／Qt6 驗證同一 App 兩欄 context 隔離、候選中關閉 client、重啟 Fcitx 與新 client
  恢復輸入，以及兩個同時存活的獨立 App 各自保留中英文與全半形狀態；桌面登出登入、
  active preedit 跨 App 切換及瀏覽器矩陣仍待 GNOME 驗收；GTK4 `GtkText`
  已有 Standard 注音 `中` 的真實逐鍵 T01，以及五布局四聲／輕聲、無效鍵與快捷鍵的
  T02，空狀態／reading／候選中 Backspace 與 Escape 邊界的 T03，以及直式
  鍵盤／滑鼠候選、橫式 Windows 對標鍵盤導覽的 T06，以及預設／分類／停用／舊設定
  遷移／D-Bus 保存重啟的關聯詞 T07，以及中英文切換、停用 `Ctrl+\`、全形與繁轉簡的
  T08，以及長按 `Ctrl+\` 與 reading／候選中 Ctrl／Alt pass-through 的 T09，以及
  同 App 兩欄、client/Fcitx 復原與兩個同時存活 App 狀態隔離的 T10，以及 T11
  內容指標選取／替換／密碼／唯讀欄與 T12 符號候選；
  每案都有 `keyboard-us` 負控制。
  T11 另以三套 toolkit 真實欄位驗證 active reading 中的方向、Home／End、Delete／Tab 與 Shift
  變體不會移動 App caret／selection 或換欄，並以 XTest 指標拖曳選取既有「乙」後由
  候選精確替換為「中」、
  密碼／Sensitive 路徑只產生 literal，以及唯讀欄位在完整鍵序後不變；一般注音候選
  另以 GTK3／GTK4／Qt6 真實滑鼠點擊第二列選出「鐘」，
  符號表則點擊
  第一列提交「，」。瀏覽器與 Wayland 的 App 內容滑鼠 selection 仍待驗收。
  候選方向已能在原生設定由 Vertical 切成 Horizontal，保存／重啟後套用到真實候選；
  錯誤訊號已接到可關閉的 XDG 提示聲，設定視窗的關閉、保存與重啟讀回已納入同一
  suite；`configure`／GNU Make source-directory 與 out-of-source gate 亦在重建後的
  24.04 container 通過。單次 24.04 `.deb` 已重建並確認自動產生的 runtime dependency
  包含 `libcanberra0t64`。
  Ubuntu 24.04 package lifecycle 已重跑：preview 初裝與 release 升級各通過 82 個
  非設定視窗案例，移除／重裝後通過包含設定視窗的完整 83 案；dependency、資料 hash、
  移除與設定 sentinel 也全數通過。
  2026-09-14 另把同一組 release-candidate `.deb` 實裝到 WSL2 Ubuntu 24.04.4，
  由使用者在 WSLg XWayland 的 GTK3 gedit 以 Fcitx 5.1.7 實際確認可輸入中文；這只算
  package／GTK3／XWayland 手動 smoke，不是 GNOME desktop、native Wayland 或候選視覺
  驗收。WSLg 對已 unmap 的 Fcitx X11 候選窗會留下約一秒殘影，另見下方已知陷阱。
  同日另啟動獨立的 GNOME Shell 46／TigerVNC X11 `:21` 診斷桌面，由本機 noVNC
  顯示，沿用相同已安裝 addon。三次「快→Shift+1→樂」與十次「ㄎ、Space」連打的
  GTK commit 為 0.72–1.88 ms，X11 隱藏觀測為 4.27–6.30 ms；兩個抽樣候選區域在
  約 59 ms 已清除，半秒後像素一致，英文負控制也通過。這是隔離 X11 診斷證據；
  同日使用者已在瀏覽器端確認延遲與多重殘影解決、試打成功。完整 GNOME 登入與
  native Wayland 仍待完成。2026-09-16 同類隔離 GNOME X11 session 再以系統安裝的
  1.2.8 addon 跑過 GTK3／GTK4／Qt6 共 76/76 desktop-safe 案例，包含五布局、候選
  鍵盤／滑鼠、關聯詞、模式、兩 App、編輯欄位與符號表；七個會重啟承載 Fcitx 的
  persistence／recovery 案仍只在 managed Xvfb／package gate。後續在此主機提供人工
  試打時優先沿用
  [Ubuntu 手動試打交接](Source/Loaders/Linux-IME/docs/manual-desktop.md)，先啟動桌面、
  切好琦琦注音並開啟本機連結，再請使用者測試。
  Windows 主機不會取得原 Mac 的 container／named volumes，
  首次執行較慢屬正常，之後應以同一 `ci/dev.sh` session 迭代。

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
7. 調查或實作 Linux 行為對標時，固定先查 macOS 的 OSX-IMK、PlainVanilla 與實際
   模組事件流，再查 Windows TSF；兩者不同時明列平台差異，不得先以 Windows 推定
   macOS 行為。第一階段功能範圍仍以 Windows TSF 已提供的功能為界。

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
  `generateIndexedDictionaryAssets` 再把 CIN 與關聯詞編成 `.kki`。執行時直接讀索引，
  關聯詞索引由單一背景執行緒載入；原始文字檔才是資料來源，不要手改 generated 索引。

### iOS

```sh
cd Source/Loaders/iOS-Keyboard
xcodebuild -project KeyKeyiOS.xcodeproj -scheme "chichi77 KeyKey" \
  -configuration Debug -destination 'platform=iOS Simulator,name=KeyKey iOS 26 iPhone 17 Pro' \
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
- 兩個 target 各有 `PrivacyInfo.xcprivacy`，也都宣告 `UserDefaults`（required reason
  `CA92.1`）：extension 自己保存按鍵音、候選底色與關聯詞庫，容器 App 自己保存實體
  鍵盤編輯器的關聯詞庫；只有首次使用與支持 entitlement cache 透過 App Group 在兩個
  target 間共用。兩份都宣告不追蹤、不收集。

---

## 已知陷阱（不要重複調查）

- **Ubuntu 24.04 的主框架是 Fcitx 5**：這是使用者指定的主要支援環境，需最完整
  測試；不能只保留 Ubuntu + IBus 或以 KDE + Fcitx 的結果替代。GNOME 可能使用
  IBus protocol bridge，但實測必須確認載入本專案 Fcitx addon。主環境每次相關
  PR 只跑 Ubuntu 24.04 build、unit、staged install 與 GTK3/Fcitx T01 真打字 smoke；
  合併進 `master` 後才跑完整 hosted typing、UI、source 與套件生命週期。手動完整
  測試／發布跑全部 App、sandbox、UI 組合與穩定性；Linux desktop workflow 不設定
  每日或每週排程。
- **Linux 第一階段以 Windows TSF 現有功能為基準**：2026-09-13 最新決定是把 Windows
  已有的五種傳統注音布局、逐音節輸入、候選、關聯詞、Big-5 過濾、全半形、中英文
  切換、標點／符號列表、直橫候選、比例／配色、錯誤提示與三頁設定全部列入。先前
  「只做 Standard」的決定已被此基準取代，既有多布局設定不移除。Linux 已完成而
  Windows 沒有的倉頡／簡易與繁轉簡切片也不特別拆除，保留架構與日後擴充可能，但
  不因此成為第一階段 blocker。候選學習／動態頻率與注音自動修正仍不加入；F12
  計算機、F13 自訂詞／詞庫管理、F14 通用表格／外掛設定、F15 一點通／提示通知視窗
  也不屬於 Windows 對標範圍。其他平台既有功能維持原狀。
  SmartMandarin 仍因語料缺失而不啟用；不可憑舊模組存在就重新擴張 Linux 範圍。
- **Fcitx 沒有單一輸入法的候選縮放屬性**：macOS 與 Windows 都提供 system、75、
  90、100、125、150、175、200、225、250、300、350%，前者直接乘上直／橫候選窗
  幾何，後者把比例與 monitor/host DPI 合成後縮放字型、padding 與視窗。Fcitx
  5.0.14 只有一個全域 active UI，沒有 per-context panel callback；5.1.7 雖有
  5.0.24 起新增的 custom callback，仍要求輸入法自行畫完整 panel，且不能當作
  Ubuntu 22.04 最低 API。改 Classic UI 的 `Font`／DPI 會影響所有 Fcitx 輸入法並
  寫入全域設定，不可偽裝成琦琦注音專屬比例。精確 parity 要做同時支援 X11 與
  native Wayland 的自有 renderer；未完成前不加無作用的比例選項。
- **TraditionalMandarin 的 Backspace／Escape 邊界以 Windows event flow 為準**：
  reading 中 Backspace 只刪最後一個注音成分，Escape 清掉整段；一般候選中 Backspace
  先關候選再刪最後一音，Escape 則經 candidate cancel 清掉整段。composition 與候選都
  空時，兩鍵都必須交回 App，不能無條件吃掉，否則 Backspace 不會刪除 App 既有文字。
  關聯詞候選另依 F05 規則處理，不可拿它的 Backspace pass-through 套到一般注音候選。
- **Linux 的 CI 綠燈要分層**：unit、adapter 或 Xvfb 通過都不等於原生 Wayland
  可用；E2E 必須從鍵盤事件經過 IME，核對實際 App 文字與 preedit／候選流程，
  並有停用 engine 的負控制。GNOME／KWin 的 hosted VM、popup 樣式與焦點能力
  先做 P0；未驗證前不可承諾全部桌面測試皆可在 hosted runner 完成。
- **WSLg 的 Fcitx X11 候選殘影不是 engine 延遲**：2026-09-14 手動流程中，「快」
  選字後由注音候選重畫成關聯詞候選很快，但再以 `Shift+1` 選「樂」後，已關閉的視窗
  仍在 Windows 桌面殘留約 1–1.5 秒。先依 macOS／Windows 確認兩者都在同一按鍵處理
  內 commit 並隱藏，再嘗試讓 Linux adapter 在 commit 前清空 panel；使用者確認完全
  無改善，因此該嘗試已撤回。這與 [microsoft/wslg#1495](https://github.com/microsoft/wslg/issues/1495)
  的 Fcitx 5.1.19 A/B 結果完全相同：`xcb_unmap_window()` 後只留下視覺殘影，維持 mapped
  並縮成 1×1 才消失。Ubuntu 24.04 的 Fcitx 5.1.7 使用
  `_NET_WM_WINDOW_TYPE_POPUP_MENU`；臨時改成新版的 `COMBO` 也不能視為產品修正，因為
  上述 5.1.19 重現環境早已使用 `COMBO`。不可在 KeyKey engine 加 sleep、重複 commit
  或篡改候選狀態規避；WSLg 只能驗證輸入功能，候選顯示／隱藏速度必須在真正 GNOME
  X11／XWayland／native Wayland session 各自驗收。
- **本機 GNOME／VNC 診斷桌面與原 WSLg 視窗並存**：2026-09-14 的
  `keykey-manual-desktop.service` 使用獨立 X display `:21`、D-Bus、XDG 設定與 runtime，
  從 `http://localhost:6080/vnc.html?autoconnect=true&resize=scale` 操作；已預選琦琦注音。
  版控啟動入口為 `Source/Loaders/Linux-IME/tools/manual-desktop/start-desktop.sh`，
  同目錄 `session-command.sh` 可在正確 session 執行 `fcitx5-remote`；詳細步驟與
  排查順序見 `docs/manual-desktop.md`。不可沿用原 WSLg 的使用者 bus，否則會切錯
  輸入法。VNC 僅開 0600 Unix socket，網頁／WebSocket 只綁 `127.0.0.1:6080` 並檢查
  localhost Origin，不向區網開放。停止時只停止此 service，保留原 gedit 的未存文字。
  Mutter 外框與 GTK client 有相同視窗標題，定位須核對 client 屬性；X11 map 早於
  compositor 重畫，像素比較須先確認關窗前確實有候選畫面。診斷結果在
  `out/manual-vnc/popup-timing-20260914-011529.json`，不是正式 CI 新增案例，也不是完整
  desktop gate。使用者已確認此桌面試打成功；不要再次要求用同一個有殘影的 WSLg
  單窗重試，也不要把環境修正寫成 KeyKey／Fcitx 產品修正。日後若同一獨立桌面也
  重現，必須重新量測，不可直接套用 WSLg 結論。
- **GNOME X11 runner 不可用 Xvfb 的 focus 假設**：2026-09-16 新增
  `tools/manual-desktop/run-gnome-x11-e2e.sh`，會在上述隔離桌面跑 76 個
  desktop-safe 案例。Mutter 外框與 client 同名，`xdotool search` 的多條件預設為 OR；
  必須加 `--all` 並核對 host PID，existing GNOME 只用 `windowactivate` 並確認
  `_NET_ACTIVE_WINDOW`，不可再以 `windowfocus` 強設焦點；新 client 可能在搜尋前就已
  active，不能直接呼叫 `windowactivate --sync`，否則會等不到下一次焦點變更而逾時。
  多欄 host 啟用後不要額外
  點擊，否則兩次近距離點擊會被視為雙擊、破壞 T11 selection；單欄與 multi-App
  才點內容區。承載桌面的 Fcitx PID 不可由案例重啟，runner 因此拒絕三個 persistence、
  設定視窗 persistence 與三個 input-context recovery 案；它們仍由 managed Xvfb／
  package gate 執行。GNOME runner 會備份／還原 KeyKey 設定與 active engine，並記錄
  addon、panel、package 及 SHA-256；76/76 不等於完整 83 案、登入生命週期或 Wayland。
- **Linux 不沿用舊 cooker 建置依賴**：macOS cooker 使用 Formosa Ruby extension；
  Linux 應唯讀共用字表／詞庫，以獨立原生資料工具生成自身索引，不修改四平台
  cooker 或資料內容。CIN 可能有 CRLF 與合法 `%` 字元列，解析不能一律略過。
- **Fcitx 5 最低 API 必須以 Ubuntu 22.04 實編譯**：22.04 的 Fcitx 5.0.14 與 24.04
  的 5.1.7 都使用 `FCITX_ADDON_FACTORY`；不可只看新版文件改用舊套件沒有的 V2
  factory macro。獨立的 Rancher Desktop one-shot scripts 預設強制 `linux/amd64`；
  `ci/dev.sh` 長駐開發 session 則預設跟隨 host architecture，Apple Silicon 使用
  `linux/arm64` preview。兩者都只是 container userspace，不能當成桌面 E2E。
- **Linux 錯誤提示聲不要改成 X11 bell**：Fcitx 5 Core 沒有提供 input-method addon
  可直接呼叫的提示聲 API；目前用 libcanberra 播放 XDG 標準
  `bell-window-system` 事件，才能共用 X11、XWayland 與 native Wayland 路徑。選項
  `PlaySoundOnTypingError` 預設開啟，只有 engine 回報 `beep` 才播放；一般快捷鍵仍
  pass through。建置要明列 `libcanberra-dev` 與 `pkg-config`，尤其 Ubuntu 22.04
  前者不會自動帶入後者。Debian 成品由 shlibdeps 依 Ubuntu 版本產生 libcanberra
  runtime dependency，另 `Recommends: libcanberra-pulse` 供 Ubuntu GNOME 的
  PulseAudio／PipeWire 相容音訊路徑；不能把開發套件寫進 runtime Depends。Xvfb 沒有
  音訊 session，只能驗證呼叫不使 Fcitx 失效以及原生設定關閉／保存／重啟讀回；真正
  可聽結果必須在 Ubuntu GNOME 驗收。Container Dockerfile 與 Debian `Build-Depends`
  加入相依套件時，也要同步 `.github/workflows/linux-ci.yml` 的兩份 native apt 清單；
  hosted build 不會沿用 container 定義。run `34762595629` 曾因 24.04 缺
  `libcanberra-dev`、22.04 同時缺 `libcanberra-dev` 與 `pkg-config` 而在 CMake configure
  階段失敗。
- **Linux 本機快速迭代使用長駐 dev container**：`ci/dev.sh up` 只在 24.04 Dockerfile
  改變時重建 dependency image，後續 build／CTest／stage／X11 E2E／單次 package build
  都以 `docker exec` 留在同一個 container。build 與 stage 使用具 checkout／架構隔離的
  named volumes；`down` 保留快取。`e2e` 可用完整 case ID 或逗號清單縮小範圍，結果
  JSON 只能列實際執行案例。這條路徑不乾淨，不能取代 `run-debian-package.sh` 的
  runtime dependency、升級、移除及重裝 gate。
- **Linux configure／make 是包住獨立 CMake build 的薄層**：入口位於
  `Source/Loaders/Linux-IME/configure`，source-directory 使用
  `out/build/configure-make`，out-of-source 使用 `.keykey-configure-build`，兩者只在
  呼叫目錄生成一份有 marker 的 wrapper `Makefile`。不可改成直接在 source root 跑
  CMake，也不可讓 `distclean` 刪到其他 Ninja build。Fcitx addon／metadata 改用
  `CMAKE_INSTALL_LIBDIR`／`CMAKE_INSTALL_DATADIR`，才能共同遵守
  prefix／libdir／datadir；runtime data path 使用 full datadir，絕不可加入 `DESTDIR`。
  CMake 3.28 的 GNUInstallDirs 可能把預設 `CMAKE_INSTALL_DATADIR` cache 欄位留空，實際
  作用域仍是 `share`；摘要與測試必須讀 configure 時生成的
  `keykey-install-layout.txt`，不能直接把空 cache 當成安裝根目錄。
- **長駐 dev container 的 source gate 和一般 incremental build 權限不同**：rootless
  container 的 user namespace 可能讓數字相同的 host UID 無法寫 bind-mounted checkout，
  因此 `ci/dev.sh source` 在隔離 container 內以 root 跑測試，再由 distclean／精確的
  `out/` 路徑清理；不可改用 host 的 sudo 或放寬 Docker socket。24.04 system E2E 會先
  拒絕覆寫既有 `/usr/local` 目標，再暫裝、跑 T01 真打字，最後依 install manifest
  卸載。`/usr/local` 在不同 Fcitx build 不保證同時位於 addon 與 XDG data 的內建搜尋
  路徑，system E2E 必須依 configure layout 明示 `FCITX_ADDON_DIRS` 與 `XDG_DATA_DIRS`；
  前者是取代而非只附加內建 addon 目錄，必須一併加入 Fcitx5Core pkg-config 回報的
  system libdir 下 `fcitx5`，否則連 D-Bus／XCB addon 都找不到，Fcitx 不會就緒。
  `/usr` 安裝則使用發行版原生位置。2026-09-13 local amd64 已通過，含同一 commit 的 2.0 MB source tarball 在無
  `.git`／無 cache 解壓目錄重建；Ubuntu 22.04／24.04 兩個 hosted job 亦已在
  run `34742072894` 通過。
- **Rootless Docker 的 one-shot build 也要使用 container-side root**：
  `run-container-build.sh`、獨立 X11 與 package scripts 的 bind mount 規則一致。
  Rootless engine 會把 WSL checkout owner 映射為 container UID/GID 0；若仍傳 host
  UID/GID，清掉舊 build directory 後 CMake 會因無法建立 `CMakeFiles` 報一串
  誤導性 compiler 偵測錯誤。先從 `docker info` 判斷 rootless；rootful 才傳 host UID/GID。
- **混用 one-shot 與長駐 container 時，套件生成目錄可能有不同的 container owner**：
  rootless engine 下，one-shot package 由 container root 產生的 bind-mounted 檔案在 WSL
  看起來仍屬於目前使用者，但長駐 container 的 host UID 無法刪除其內層目錄。
  `ci/dev.sh package` 因此先由 container root 精確清掉目前架構的
  `out/package-build/ubuntu-24.04-ARCH-release-candidate` 與
  `out/packages/ubuntu-24.04-ARCH/release-candidate`，再切回 host UID 建置。不要要求使用者
  `sudo rm`、放寬整個 checkout 權限或把清理範圍擴到整個 `out/`。
- **探測 Fcitx D-Bus 就緒不能先呼叫 `fcitx5-remote`**：它會透過 D-Bus activation
  啟動第二個 Fcitx 並搶走名稱，使測試中的明確 PID 退出。先對 bus daemon 呼叫
  `NameHasOwner(org.fcitx.Fcitx5)`，確認原行程取得名稱後才能使用 remote 指令。
- **Fcitx 取得 D-Bus 名稱不代表自訂 addon 已載入**：乾淨 session 中 D-Bus controller
  可能先可用，`chichi77-keykey.so` 約一至兩秒後才載入；此時只呼叫一次
  `fcitx5-remote -s` 會靜默失敗且後續輪詢永遠留在 keyboard。X11 E2E 先以受控 PID
  的 `/proc/PID/maps` 有界等待 addon，再於 engine 輪詢內重送切換要求。
- **X11 E2E 的 private runtime 要等 D-Bus session 結束後再刪**：AT-SPI registry 是由
  private bus 啟動的額外 process，內層測試 cleanup 即使 kill／wait 自己追蹤的 Fcitx、
  GTK host 與 Xvfb，AT-SPI 仍可能短暫寫入 `/tmp/chichi77-keykey-e2e.*`。若在
  `dbus-run-session` 返回前執行 `cmake -E remove_directory`，會偶發因目錄內容競態失敗，
  把其實已通過的完整 suite 改判紅燈。runtime root 由外層建立，待 bus 完全退出後有界
  重試清理，並保留原測試 exit code；不可把清理搬回 session 內。
- **`fcitx5-remote -r` 不會重載 input-method addon 自己的設定**：五布局 E2E 寫入
  `conf/chichi77-keykey.conf` 後，須同步呼叫 Controller1 的 `ReloadAddonConfig`
  並傳 addon ID。查設定 schema 時 `GetConfig` 需要完整 URI
  `fcitx://config/inputmethod/chichi77-keykey-bopomofo`，不能只傳 addon ID；後者會回
  `Configuration does not exist`。輸入法切換本身是非同步的，送鍵前要有界輪詢
  `fcitx5-remote -n`，不能切換後立刻比較一次。
- **Fcitx 原生設定視窗用 AT-SPI 名稱定位，不寫死螢幕座標**：Ubuntu 24.04 測試需安裝
  `fcitx5-config-qt`、`at-spi2-core`、`python3-pyatspi`、`fonts-wqy-zenhei`、`x11-apps`
  與 `netpbm`，並設 `QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1`。Qt 的 input-method list
  沒有可用的 Selection interface，先從 AT-SPI 取得 row extents，再用 XTest 點擊；
  `Configure` 會開 modal dialog，不能同步呼叫其 `Press` action，否則 AT-SPI D-Bus
  會等到逾時。對該按鈕同樣用語意定位後點擊，核取方塊與 OK 才用 action。Apple
  Silicon 模擬 amd64 的 Qt 冷啟動可能超過 10 秒，UI 等待上限須保留 30 秒；找到元件後
  會立即繼續，不會固定增加 native runner 時間。hosted runner 透過 `sudo` 執行套件
  生命週期時，可能把一般使用者的 `XDG_RUNTIME_DIR` 留給 root；進入私有
  `dbus-run-session` 前須清掉外部的 D-Bus／AT-SPI／runtime 位址，再用
  `dbus-update-activation-environment` 把測試建立且擁有者正確的 XDG 目錄同步給 D-Bus
  啟動的無障礙服務，否則設定工具即使已被 Fcitx 啟動也可能不會出現在 AT-SPI tree。
  `safeSaveAsIni` 寫出的實際設定是 0600；複製到 E2E artifact 後要只把證據副本改成
  0644，否則 rootless container 的 UID mapping 會讓 WSL host 無法直接閱讀。不要放寬
  使用者真正的 Fcitx 設定檔權限。
- **Xvfb 找到 window ID 不代表 GTK 視窗已可聚焦**：X11 可能在視窗 map 成可見狀態前
  就讓 `xdotool search` 找到 ID，立刻 `windowfocus` 會以 `X_SetInputFocus BadMatch`
  結束；同名 host 快速重開時，舊 ID 也可能短暫留在搜尋結果。真實打字 E2E 必須用
  `search --onlyvisible`，從最新 ID 起逐一嘗試，並在 host 尚存活時有界重試 focus；
  不能只取第一個 ID 或延長固定 sleep，否則 hosted runner 仍會偶發失敗。
- **Fcitx 候選窗的第一個可見 geometry 不是完整候選**：classic-ui 的
  `Fcitx5 Input Window` 會先以 1×1 map，再變成只容納 preedit 的小窗，最後才展開
  九列直式候選。T06 滑鼠測試必須先明確設為 Vertical，再以有界輪詢等待 width > 10
  且 height > 100，才可按九等分列中心點擊第二列；只等 window ID 或固定 sleep 會點到
  暫態空窗。2026-09-15 的 Xvfb/Fcitx 5.1.7 實測完整窗為 44×247，第二列中心為
  (22, 41)，但這些絕對像素只寫入 artifact，不得硬編碼成點擊座標。macOS 候選控制器
  只在 panel 取得 control 時把滑鼠列／索引換成選字鍵送入 PlainVanilla；AssociatedPhrase
  只 show 而不 yield control，所以橫式禁點、直式拒絕 selection change。目前 Windows TSF 自繪
  `CandidateWindow` 沒有 mouse-button 選字訊息，屬平台差異，不可誤寫成 Windows parity。
- **Fcitx input context 的 active engine 與 KeyKey 組字狀態是兩回事**：停用 Fcitx
  share-input-state 時，新取得焦點的 GTK entry 可能先使用 `keyboard-us`，即使前一欄是
  琦琦注音；T10 跨欄測試要在切入新 context 後明確選擇注音並輪詢
  `fcitx5-remote -n`，不能把框架的 per-context 選擇策略誤判成 addon 串字。KeyKey 狀態
  仍必須由 `InputContextProperty` 隔離；失焦後應看到舊 preedit 清空，切回後按 `1` 只會
  開始新的 `ㄅ` reading，不可選到舊候選。GTK `changed` 在 focus-out 附近可能暫時回報
  preedit 文字；GTK4 `GtkText` 在失焦時也會短暫以 `changed` 回報 `ㄓㄨㄥ`，切回後由
  Fcitx 清除，再從新的 reading 提交正確結果。應以有序 preedit 與最終 buffer 判定
  是否誤提交。Xvfb 沒有 window
  manager，`xdotool windowclose` 可能直接摧毀 X window 並使 GTK 報 `BadWindow`；client
  lifecycle 測試改由 host 收到控制檔後自行 `gtk_widget_destroy()`。
- **跨 App 的 active preedit 失焦行為不是四平台共同基線**：先查 macOS，
  `deactivateServer:` 會先 commit composing buffer 再清理；Windows TSF 在 document
  manager 失焦時則 `abandonComposition()` 並非同步終止。local Xvfb/Fcitx 5/GTK3 的
  診斷中，App A 的 `ㄓㄨㄥ` client preedit 在切到 App B 時被 GTK 提交進 App A 的文字欄，
  切回後再選字會得到 `ㄓㄨㄥ中`。這不能當成 KeyKey context 串字，也不能在 addon 內硬改成 Windows
  語意。正式 T10 multi-App isolation 只在 composition 為空時切焦點，以兩個同時存活
  的 GTK process 驗證每個 context 的中英文與全半形狀態；active preedit 仍須在 GNOME
  與 GTK4／Qt／瀏覽器逐一確認並明列平台差異。
- **候選開啟時不能用 Tab 製造 T10 focus-out**：macOS 的 PlainVanilla candidate flow
  會吃掉 Tab 並提示錯誤，Windows TSF 的相同共用 candidate flow 亦然；Linux 對標後
  也必須保留候選，不能為了測跨欄而讓 Tab 漏到 App。T10 改由 GTK host 輸出實際
  widget 中心座標，再以 XTest 真實滑鼠點擊第二欄；不可寫死 Xvfb 螢幕座標，也不可
  改回會掩蓋產品行為的 Tab。
- **T10 的 GTK4 第二欄不可放在候選窗正下方**：GTK4 `GtkText` 的第一欄候選有時會
  覆蓋垂直排列的第二欄，XTest 點擊就變成選出「衷」而不是切換 input context。
  GTK4 focus host 因此以 960 px 寬的左右欄位保留真實滑鼠失焦路徑；座標仍由
  `gtk_widget_compute_bounds()` 動態取得。不可改回上下排列或用固定螢幕座標。
- **GTK3 指標選字不能把初始 focus selection 當成測試結果**：T11 的 `GtkEntry` 設定
  「甲乙丙」後，初次取得焦點會先全選 `0:3`；若直接在第二字左緣 click 後立刻從同點
  drag，GTK 可能把它判成 double click 而再次全選。測試先點 entry 文字右側空白區並
  等 caret 到索引 3，再以 Pango layout 算出的第二字左右 hit point 做 XTest drag，最後
  從 `GtkEditable` 有界輪詢精確確認 `1:2`。不可硬編碼 Xvfb 像素，也不能只接 entry 的
  button signal，因為它的內部 event window 可能先吃掉指標事件。
- **GTK3 密碼欄會由 Fcitx capability 停用自訂輸入法**：設為
  `GTK_INPUT_PURPOSE_PASSWORD` 後，該 context 會切回 `keyboard-us`，而且不能用
  `fcitx5-remote -s chichi77-keykey-bopomofo` 強制選回；T11 應把這個安全邊界當成
  預期結果，不能為了跑注音而移除 password purpose。Fcitx adapter 仍在收到
  `Password`／`Sensitive` capability 時防禦性清除關聯詞候選，供其他 frontend 行為。
- **GTK4／Qt6 真實輸入要由各自的 host 驗證，不能拿 GTK3 binary 代稱**：Ubuntu 24.04
  的 GTK4 案例使用 `GtkText` 與 `preedit-changed`，Qt6 案例使用
  `QLineEdit`／`QPlainTextEdit` 與 `QInputMethodEvent`；runtime 同時安裝
  `fcitx5-frontend-gtk4` 與 `fcitx5-frontend-qt6`。CMake 的
  `--enable-x11-e2e-host` 因此需要 GTK3、GTK4、Qt6 Widgets 三套開發檔。E2E runner
  保留 `KEYKEY_E2E_HOST` 給既有 GTK3 suite，另以 `KEYKEY_E2E_GTK4_HOST`、
  `KEYKEY_E2E_QT6_HOST` 指定其餘 host，並依 case 選對視窗標題；不可只因都經 Fcitx
  就改用別的 toolkit client。
- **Qt6 唯讀欄位必須透過 input-method query 發布停用狀態**：`QLineEdit` 與
  `QPlainTextEdit` 單獨呼叫 `setReadOnly(true)`，focus-in 後仍可能向 Fcitx 宣告 IME
  可用，結果連標準 Fcitx engine 都會送入 preedit／commit。T11 的唯讀多行 host 因此
  依 Qt 平台介面讓 `Qt::ImEnabled` 回傳 false，Fcitx 核心才會把完整按鍵交回 widget；
  此路徑不需要在 KeyKey addon 猜測 widget 狀態或新增 Fcitx 5.0.14 沒有的 capability
  enum。密碼欄在 Qt6 會保留目前 engine 名稱但將字元直接送 App，與 GTK3 自動顯示
  `keyboard-us` 不同；驗收應核對無 preedit、只有 literal 和無關聯詞，不可硬套 GTK 的
  `fcitx5-remote -n` golden。
- **停用 `Ctrl+\` 後，active preedit 的處置屬於 client，不可在 addon 裡統一**：先查
  macOS，其內部切換並不使用 Windows 式的 `Ctrl+\` 開關；再查 Windows TSF，停用
  選項後 shortcut 會交回 App。Linux 也只 pass through。local Xvfb 中，GTK3 收到
  `Ctrl+\` 時會先把 `ㄓ` client preedit 提交，再於其後插入下一個 commit，得到
  `ㄓ翁`；GTK4 `GtkText` 同樣先提交 preedit，但 insertion point 留在其前，下一個
  commit 因此得到 `翁ㄓ`。兩者都證明 KeyKey 狀態仍是中文且 shortcut 未被 addon
  吃掉；不可為了讓文字順序一致而重送按鍵、提交或篡改 composition。
- **橫式候選外觀不代表 macOS 與 Windows 有相同方向鍵語意**：macOS PlainVanilla
  會隨候選方向交換按鍵角色，橫式以 Left／Right 移動反白、Up／Down 翻頁；Windows
  TSF 目前只改 `CandidateWindow` 的繪製排列，底層 candidate service 維持直式，因此
  仍由 Up／Down 移動反白、Left／Right 翻頁。Linux 1.2.8 第一階段依 Windows 行為，
  Horizontal `CandidateLayoutHint` 不得自行交換按鍵角色；比較時仍必須先記錄 macOS
  差異，再以 Windows runtime 界定範圍。
- **APT 安裝本機 `.deb` 時路徑必須是絕對路徑或以 `./` 開頭**：傳入
  `out/packages/.../*.deb` 會被當成 package expression。package lifecycle script
  先限制輸出必須位於 `out/packages/`，再轉成絕對路徑；不要放寬成任意目錄。
- **Debian source staging 必須保留 monorepo 的相對資料結構**：Linux CMake 以
  `Source/Loaders/Linux-IME/../../..` 找唯讀字表與根授權，因此 package script 只複製
  所需 Linux 原始碼（包含 CMake `cmake/*.in` configure template）、四份舊資料 CIN、
  Linux 產生的 `tc2sc.cin`、McBopomofo
  `phrase.occ`、29 個分類 TSV、顯示名稱表與各自授權複製到暫存 source tree，
  不依賴 repo 外檔案。
  `1.2.8~preview1` 僅為首版 package upgrade 流程 fixture，不可宣稱是真實已發布舊版。
- **Linux 標點表是第四份必要套件資料**：`bpmf-punctuations.cin` 必須和注音、倉頡、
  簡易三份字表一起 staged、封裝並做 installed-file hash 比對。只有表內存在的
  `Ctrl+0`／`Ctrl+1`、Ctrl 標點與 Ctrl+Alt 組合才由輸入法處理；未定義的 Ctrl
  shortcut 要交回 App。reading 尚未清空時，已識別 shortcut 依 macOS 行為由輸入法
  吃掉但保留 reading，不能清掉組字或誤送標點。
- **倉頡／簡易的直接標點就在各自 CIN，不是第四份標點表**：`cj-ext.cin` 與
  `simplex-ext.cin` 的 `%keyname`、`%endkey`、`%chardef` 已包含逗號等鍵；Linux parser
  必須保存 end-key metadata，不能把 table 輸入硬限為英文字母。end key 立即查詢，
  單一候選直接提交；簡易一般字根到兩碼也立即查詢，候選開啟後繼續打下一字根時，
  先提交目前反白候選再開始新組字。倉頡預設查無結果會清空 reading；簡易目前依
  Preferences 預設保留，待完整設定入口提供切換。帶 Shift 的標點 keysym 需允許，
  Ctrl／Alt 組合仍交回 App，不能為了標點把所有 modifier 吃掉。
- **倉頡的 `?`／`*` 同時是直接標點與萬用字元**：單獨作為第一個 component 時依
  `cj-ext.cin` 的 end-key／chardef 立即處理為「？」／「＊」候選；前面已有字根時，
  舊 `OVIMGeneric` 會排除 end-key 語意，分別作為「恰一碼」與「零碼以上」的 wildcard，
  等 Space／Enter 才查詢。Linux 必須依 code 排序再保留同碼候選的 CIN 順序，不能
  直接走 `unordered_map` iteration，也不能看到 `%endkey` 就把 `a?` 提前提交。
- **Linux 繁轉簡映射是第五份必要套件資料**：`data/tc2sc.cin` 由
  `tools/generate-tc2sc-cin.rb` 從唯讀 `VXHCTC2SCTable.c` 的 3,058 筆明示配對產生；
  不編譯或連結舊模組。舊 C array 雖宣告 3,059 組，實際只列 3,058 組，
  最後多出的零值初始化不是轉換資料，產生器必須固定驗證此數量。
- **Linux Big-5 候選限制只套用注音**：F03 倉頡與 F04 簡易不在 Windows 第一階段基線，
  目前不為它們擴張新設定，但保留已有實作與擴充結構。Linux 以 `iconv` 的
  `BIG5-HKSCS` 做無損可表示性檢查，每個候選都要
  重設 converter，並在分頁前過濾且保留來源順序；`UseAllUnicodeCharacters` 預設為
  `True`。正式注音表的 Standard `,4` 是固定錨點：未過濾時第二候選為 `𠔅`，過濾後
  必須精確為「誒、𤦩、𨗴」，按 `2` 提交「𤦩」。Ubuntu 22.04／24.04 的 glibc 都由
  CMake `FindIconv` 判定為內建實作；更廣的 macOS 對照與多 filter 組合順序仍待驗證。
- **Windows TraditionalMandarin 已有逐音節連續輸入與錯誤鍵處理**：候選窗開啟時若
  直接按下一個合法注音鍵，`candidateNonPanelKeyReceived` 會先提交目前反白候選，再以
  該鍵開始下一個 reading；這不是 SmartMandarin 的整句組字。reading 中的無效一般鍵
  會提示錯誤並保留 reading，Ctrl／Alt 等應用程式快捷鍵則放行。Windows 有五布局
  設定，Linux 第一階段須維持相同選項。Windows module package
  只註冊 TraditionalMandarin 與 AssociatedPhrase，雖 cooker 含 correction table，
  實際未載入 BopomofoCorrection，所以 Linux 也不需實作注音自動修正。
- **五布局錯誤鍵使用裸 `\` 作共同 E2E 錨點**：macOS TraditionalMandarin 在 reading
  非空時會吃掉無法組入的普通鍵、保留 reading 並 beep；Ctrl／Alt 組合則放行且不改
  reading。Windows 沿用同一 module 行為，TSF 另在送入引擎前排除 Ctrl／Alt 應用程式
  快捷鍵。裸 `\` 不在 Standard、ETen、ETen26、Hsu 或 Hanyu Pinyin 的 reading key
  集合內，且不會觸發只接受 `Ctrl+\` 的中英切換，因此可跨五布局固定這條契約；英文
  負控制必須保留 literal `\`，才能證明事件確實走過真 App。
- **Windows TraditionalMandarin 輸入明示聲調後立即查詢**：二、三、四、輕聲鍵由
  `hasToneMarker()` 觸發 `queryAndCompose()`，不需再按 Space。Linux 五布局亦須如此；
  無聲調的一聲仍以 Space／Enter 查詢。真實按鍵負控制要同步移除聲調後多餘空白，
  否則會把候選翻到下一頁，掩蓋實際差異。
- **Fcitx／GTK 可能將 `Shift+字母` 正規化成大寫 keysym**：X11 真實逐鍵測試中，
  `Shift+A` 到 addon 時可能已是 `A` 且 Shift state 被拿掉；全形路徑必須同時識別
  帶 Shift 的 ASCII 與正規化大寫，不能只看 modifier。`Shift+Space` 切換要保留
  reading／候選，repeat 事件不可二次切換；context reset 清組字但保留該 context
  的全／半形狀態。
- **Fcitx 的單按 Shift 必須在 input-method handler 前監看**：modifier-only Shift
  不會進入 `InputMethodEngine::keyEvent()`，中英文切換要監看 `InputContextKeyEvent`
  的 `PreInputMethod` phase；300 ms 內按下再放開才切換，期間任何其他鍵都取消。
  已追蹤的 Shift release 即使超時也要吃掉，否則 Fcitx core 可能把輸入法切到
  `keyboard-us`。停用 `Ctrl+\` 時要用 `filter()` 略過 KeyKey／Fcitx handler 並交給
  client，不能 `filterAndAccept()` 吃鍵；GTK3 收到這個快捷鍵時可能自行提交 active
  preedit，所以負控制只應驗證 KeyKey 留在中文模式，不能要求 reading 一定保留。
- **X11 的長按鍵不一定帶 Fcitx `Repeat` state**：`xdotool` 與部分實體鍵盤長按
  `Ctrl+\` 時，重送的 key-down 可能看起來像新的普通 press；只檢查 `KeyState::Repeat`
  會在一次長按內反覆切換中英文。Fcitx state 必須在首次 chord press 後鎖住反斜線，
  到該實體 keysym 的 release 才解除；使用者先放開 Ctrl 時，X11 還可能在真正 key-up
  前重送一個沒有 Ctrl 的 backslash press，所以 latch 期間要吃掉該鍵的全部事件，不能
  只處理 repeat 或 release。Xvfb 沒有 GNOME window manager，`Super+L` 會落到 GTK，
  所以 Super 保留在 L1，真正桌面快捷鍵仍須在 GNOME T09 驗收。
- **T09 英文負控制不能依賴長按 chord 的 key-up 排程**：上述案例刻意先放 Ctrl、再放
  反斜線來驗證 KeyKey latch，但 `keyboard-us` 是否在兩次 key-up 間收到一次裸 `\`
  取決於 X11 autorepeat 時序；warm staged test 曾收到，乾淨 package container 則沒有。
  長按後必須在正負控制都送相同的 `Ctrl+A`／Backspace 清除可能殘值，再開始精確文字
  比較；不可把不穩定的裸 `\` 寫進 expected literal，也不能改掉原本的 release 順序。
- **Fcitx 候選方向與候選外觀不是同一層 API**：Ubuntu 22.04 的 Fcitx 5.0.14 與
  24.04 的 5.1.7 都能在每份 `CommonCandidateList` 呼叫 `setLayoutHint()` 指定
  Vertical／Horizontal，Linux 設定應保存這個 hint。比例與反白顏色則由 active Fcitx
  UI/theme 控制，input-method addon 沒有 per-IME scale/color API；要完全複製 Windows
  選項須另作 custom UI addon，不能先放不會生效的設定。`fcitx5-config-qt` 的 enum
  combo box 在 AT-SPI 上以目前值命名（`Vertical`／`Horizontal`），不是以欄位標籤
  `Candidate window style` 命名。Xvfb classic-ui 頂層 `Fcitx5 Input Window` 的 geometry
  也不可靠地代表候選內容，不可只比較該 window 寬高就宣稱方向畫面通過。
- **Fcitx 也可能把 `Shift+1–9` 正規化成符號並移除 Shift state**：Linux 關聯詞
  選取必須同時接受帶 Shift 的數字／符號與無 Shift state 的 `!@#$%^&*(` keysym；
  候選角標仍顯示 `1–9`，上方提示 `Shift + 1-9`。未按 Shift 的數字須關閉關聯詞，
  再依當前輸入法正常處理；例如 Standard 注音的 `1` 要開始新的 `ㄅ` reading。
  Enter／Escape 只關閉關聯詞而不選入詞尾，選取時只 commit 詞尾且不接續第二輪。
- **lintian override 的 path context 語法跨 Ubuntu 版本不同**：22.04 的 lintian
  2.114 使用裸路徑，24.04 的 2.117 使用方括號；package script 必須從 `.in` 模板按
  target 產生最終檔案。不要把其中一種格式直接固定，否則另一端會出現
  `mismatched-override` 與 unused override。
- **目前先完成 Ubuntu，Debian／Fedora 是 future TODO**：matrix 保留 20 個盤點列，
  但 active release gate 是 2022–2026 的 9 個 Ubuntu 版本；另 11 個 Debian／Fedora
  target 為 `future-todo`、`required=false`。Ubuntu 歷史 EOL 列仍需套件安裝與真打字。
  使用現行 runner 搭配舊 userspace／guest，最低 Qt／框架 API 由 Ubuntu 22.04 決定；
  不能依賴 GitHub 保留舊 runner label，或為方便提高最低 OS 要求。
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
- **macOS 標準 UI 要使用系統動態色**：Preferences、PhraseEditor、About、搜尋輸入框、
  符號表及候選提示的 window/table/text/header 不可寫死 calibrated white、black 或 gray；
  分別使用 `windowBackgroundColor`、`controlBackgroundColor`、`textBackgroundColor`、
  `controlTextColor`、`secondaryLabelColor` 與 `headerColor`。三份語系 XIB 必須一起改。
  黑底白字候選窗、通知窗等自訂浮動 UI 是刻意的固定主題，前景與背景必須成對設定，
  不要只把其中一色改成動態色。
- **macOS 直式候選每次更新都要重設 scroll origin**：自訂比例調整 window/content bounds
  後，AppKit 可能保留 `NSClipView` offset，所以更新候選頁與 selection 後要將 clip view
  回到 `NSZeroPoint`，否則前幾列會跑到上緣之外、底部留下空白。候選窗沒有語系相關
  布局，英文版不會造成這個問題。
- **macOS 直式候選的提示列與候選內容要分開計算寬度**：候選欄只需按鍵欄、最長候選、
  cell padding 與外框；`SHIFT + 數字鍵` 等 prompt 另以其文字寬度和翻頁按鈕空間決定
  minimum window width。不可先把 prompt 寫進候選 `_width` 再固定加 50 點，也不可交給
  `NSTableView sizeToFit` 重新分配欄寬，否則外框留下大塊空白但提示仍可能被截斷。
  自訂比例改變 window frame 時要暫停 content view 的 subview autoresizing，並先以未縮放
  bounds 明確排好 scroll view、table、prompt 與翻頁控制，避免 AppKit 依前一次實體 frame
  累積縮窄子視圖。
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
  的唯一寬鍵。注音鍵必須同時顯示注音與實體鍵位（如 `ㄅ／1`、`ㄉ／2`）。100% 時
  橫式內容為一般比例的 230dp；直式與橫式可各自調為 50%–200%，但 40dp／35dp
  系統區固定不縮放，
  實體鍵盤候選列與浮窗也不套用此比例。六排使用橫式小字級，不要恢復舊的左右分割候選。
  左下模式鍵隨目前模式分別顯示「英/數」、「數/ㄅ」、「ㄅ/英」，不要改回「中」或固定
  「中/英/數」。
- **Android 字典索引由文字來源產生**：`app/tools/DictionaryCompiler.java` 會產生 `KKI1`
  格式；core 在 IME 建立時讀索引，關聯詞索引在背景載入並於查詢時才解碼候選。
  修改解析、過濾、排序或人名 exclusion 時，必須同步更新 compiler 及逐項一致性測試；
  不可提交 `app/build/generated` 內容或把 `.kki` 當成手工資料來源。
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
  繪製。Android 的系統級實體鍵盤支援與浮動候選窗在 iOS **做不到**，不要再嘗試。
  iOS 容器 App 另有「實體鍵盤編輯器」：前景 App 的非文字 responder 以
  `pressesBegan` 攔截按鍵，直接唯讀內嵌 `Keyboard.appex` 的同一份 `KeyKey.db`，完成後
  直式可用固定底部按鈕或 `Ctrl+C`／`⌘C` 複製全文，並可用分享按鈕或
  `Ctrl+S`／`⌘S` 開啟系統分享面板；`Ctrl+K`／`⌘K` 開啟清除全文確認窗，
  並以 Enter 確認、Esc 取消。候選窗固定直排
  1–9，不放觸控上一／下一頁按鈕；一般候選
  以 `1–9` 選取、關聯詞以 `Shift+1–9`
  （`!@#$%^&*(`）選取；沒有候選與組字時，方向鍵移動容器編輯器自己的可見插入游標。
  控制列不重複顯示「準備輸入／組字」，有候選時把 `1/n` 頁碼放在第 9 個候選字下方；右側固定提供
  ㄅ／英、半／全、符號與 `🙂` 按鈕；詞庫與
  Esc、Backspace、Enter、四方向、空白等觸控備援鍵置於候選窗右側。
  橫式固定由左到右使用輸入區、1–9 候選區、操作按鍵區、清除／複製／分享文字四欄，
  最右欄三個動作按鈕由上到下排列；iPad 保留方向鍵與空白鍵，iPhone 橫式高度不足時可收起
  方向鍵與空白鍵。4.7 吋 iPhone SE 的直式輸入區使用緊湊高度，仍須讓 1–9 候選、頁碼與
  全部操作鍵留在固定底部動作列上方。候選內容只能改文字與反白，不得改欄寬或高度，直式
  轉橫式再轉回直式時各區塊也必須精確恢復原尺寸。
  一般候選狀態下
  ↑／↓逐列移動、←／→換頁；快捷鍵說明只在點擊右上角資訊按鈕時顯示。容器編輯器能獨立選擇並保存
  關聯詞庫，但 extension 不開完整取用，因此兩邊設定不可宣稱同步。這只能在琦琦 App
  內工作，不可宣稱能在其他 App 直接輸入。
- **iOS 關聯候選按 Enter 不可選入反白詞尾**：關聯詞已是確定單字後的額外推薦，觸控
  keyboard extension 與容器實體鍵盤編輯器都必須先關閉關聯候選，再把 Enter 當作換行；
  只有一般候選狀態下 Enter 才選取目前反白候選。這條與 Android 的軟 Enter 原則一致。
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
- **iOS Supporter entitlement 與 keyboard extension 必須保持分離**：StoreKit 2 只由
  容器 App 的 `SupporterStore` 查詢商品、監聽／驗證交易與執行恢復購買；extension 只能
  讀 App Group `group.io.github.polobread.inputmethod.chichi77.ios` 的 `SupporterState`
  cache，不可在輸入路徑建立 StoreKit 或網路工作。產品 ID 同樣是非消耗型
  `chichi_supporter`，未購買也不能限制任何輸入功能；首次使用滿 30 天後只在空白注音狀態
  顯示支持提示。Apple Developer 的 App Group 必須同時指派給容器與 extension bundle ID。
- **iOS 商品未載入時不能顯示可購買狀態**：`Product.products(for:)` 可能拋錯，也可能成功
  回傳空陣列。這兩種情況都要保留恢復購買，但主按鈕只能顯示「重新載入價格」，不可顯示
  「付費支持」後再必然跳錯誤。App Store Connect 的「付費 App 協議」也必須先顯示「有效」；
  2026-09-09 送審被 Guideline 2.1(b) 拒絕時，該協議仍顯示「新」。
- **App Store 描述欄不接受注音符號「ㄅ」**：App Store Connect 會以「此欄位包含一個或多個
  無效的字元」拒絕儲存含「ㄅ半注音」的描述。商店描述固定寫「傳統注音」，不要把
  `StoreAssets/README.md` 的這個用語改回「ㄅ半注音」。副標題目前可使用「ㄅ半注音的第一選擇」，
  這項限制不要擴大套用到未出錯的欄位。
- **iOS 購買／恢復／商品重載必須共用互斥狀態**：`SupporterStore` 在第一個 await 前
  設定 `operation`，以 `defer` 回到 idle；不能只停用 UI，因為連點可能已排入多個 Task。
  `iOS-Keyboard/Package.swift` 直接編譯容器的 `SupporterStore.swift` 並注入商店介面，
  用 `swift test --scratch-path /tmp/keykey-supporter-flow-tests` 驗證，不把 StoreKit
  放進共用引擎。這些流程測試不會連到 App Store，不能取代 Sandbox 真實交易。
- **iOS 新版以 commit／push 觸發 Xcode Cloud**：2026-09-09 確認 App Store Connect 的
  `Default` workflow 監看 `master` 任意檔案變更，執行 iOS Archive 並準備分發至
  App Store Connect；目前沒有 Test action 或後續動作。依使用者要求，正式新版走這條
  流程，不另從本機上傳。`testFlight` 只是本機工作分支；推送前核對 `origin/master`
  並使用正常快轉，不要 force push。Cloud 由 `CI_BUILD_NUMBER` 設定兩個 target 版號。
- **macOS／iOS cooker 的 people exclusion 來自公開分類詞庫**：
  `DatabaseCooker/Makefile` 會從 `DataSource/chichi77Collection/phrase.people-*.tsv`
  產生人名 exclusion，再匯入 McBopomofo 與 29 個分類詞庫。不要移除檔案存在時才執行
  `awk` 的保護；資料目錄暫時不完整時仍應能產生空 exclusion，避免錯誤訊息誤導。

---

## TODO

### Linux 原生版

- [x] 2026-09-14 為使用者的 WSLg 候選窗一秒殘影與連打多重殘影，建立獨立
      GNOME Shell／TigerVNC／noVNC X11 診斷桌面；相同 addon 通過三次關聯選字、
      十次「ㄎ」連打、英文負控制，以及關窗後約 59 ms 的候選區域像素清除檢查。
- [x] 2026-09-14 使用者在上述本機瀏覽器桌面確認延遲、多重殘窗解決，人工試打成功；
      將成功環境、輸入法預選、按鍵衝突處理與分層排查流程寫進
      `docs/manual-desktop.md`，並把可重建的啟動入口放在 `tools/manual-desktop/`。
- [x] 2026-09-16 建立 installed-addon GNOME X11 desktop-safe gate：沿用獨立
      GNOME Shell 46／Mutter／TigerVNC session，明確驗證 Fcitx 5.1.7 載入系統套件的
      KeyKey addon 與 Classic UI panel，以 GTK3／GTK4／Qt6 重跑不會重啟承載 Fcitx 的
      76 案並全部通過；五布局、候選鍵盤／真實滑鼠、關聯詞、模式、兩 App、selection、
      密碼／唯讀與符號列表都有 exact text 與 `keyboard-us` 負控制。runner 依 PID 排除
      同名 Mutter 外框，保留 Fcitx PID，失敗也會還原設定與 active engine，並輸出
      addon／host SHA-256。七個 restart／persistence 案仍在 managed gate，完整登入、
      視覺 sweep、音訊、真實 App、XWayland 與 native Wayland 未完成。
- [ ] 以完整 Ubuntu Desktop 登入 session 完成 GNOME X11／XWayland／native Wayland
      驗收；本機 GNOME X11 人工通過不代替其他 session／App／發布 gate。
- [ ] 決定並實作 F07 琦琦注音專屬候選 renderer；完整分解見
      `LINUX_DEVELOPMENT_PLAN.md` 的「F07 專屬 renderer」TODO。決策前須先比較
      Fcitx 5.0.14 相容 UI addon 與 5.0.24+ callback／22.04 相容層，涵蓋 system 與
      75–350% 的完整 geometry／hit area、直橫候選、X11／XWayland／native Wayland、
      mixed DPI、設定遷移、套件 dependency／授權及 GTK3／GTK4／Qt6 證據；不可用
      會影響其他輸入法的 Classic UI 全域字型縮放代替，也不可先露出無作用選項。

- [x] 2026-09-13 完成 `LINUX_DEVELOPMENT_PLAN.md` 第 5.1 節的基本 configure／GNU Make
      入口：平行建置、check、source-directory／out-of-source、prefix／libdir／datadir、
      編譯環境旗標、DESTDIR、manifest install／uninstall、clean／distclean 與 source
      tarball 腳本；納入 Ubuntu 22.04／24.04 workflow。24.04 local amd64 已通過兩種
      build、2/2 CTest、staging／卸載／清理，及預設 `/usr/local` 暫時真安裝後的 Fcitx
      5 → GTK 3 X11 T01 打字與卸載。
- [ ] 完成 T14-SOURCE 其餘發布 gate：Ubuntu 22.04／24.04 hosted 已在
      run `34742072894` 通過；再補 `/usr`／任意 prefix 的注音完整真打字、原始碼
      升級／重裝、9 個 active Ubuntu 與 P4／P5 release evidence；目前局部結果不得當成
      整組 T14 或 Linux 1.2.8 已可發布。
- [x] 已將 Ubuntu Desktop 24.04 LTS + Fcitx 5（GNOME）設為首要支援與最完整
      測試目標；開發／測試計畫同步新增主環境完整驗收與 required CI 規格。
- [x] 2026-09-12 完成開發／測試 plan 與原始碼功能盤點；沒有 Linux build、
      workflow 或執行結果。依近四年要求改為 Ubuntu 22.04–26.04 各 LTS／中間版、
      Debian 12／13、Fedora 36–44，共 20 個版本目標；x86_64 正式目標，ARM64
      先 preview，套件採獨立 DEB／RPM。2026-09-12 依後續決定改為 9 個 Ubuntu
      active targets，Debian／Fedora 11 列保留為 future TODO、`required=false`。
- [x] 依使用者要求將四平台版號同步至 1.2.8（Android versionCode 1002008），
      設為 Linux 首版目標；從 Linux 計畫／測試移除 F12–F15 的開發要求，保留
      F05 內建關聯詞分類；該版號提交當時 Linux 實作與 CI 尚未開始，不可因版號
      更新本身當成已發布或已支援。
      已檢查 14 個產品版號欄位、Android versionCode、四個 macOS plist 與 iOS
      project 格式，均通過；本次未重新建置四平台。1.2.7 的已送審紀錄與錄影保留原版號。
- [x] 2026-09-12 建立 Linux-only C++17 engine、嚴格 CIN reader、每 context 狀態與
      第一個 Fcitx 5 注音 addon；加入 Ubuntu 24.04／22.04 Rancher Desktop scripts、
      real-data CTest、staged install／dependency／factory export 驗證及單一
      `linux-ci.yml`，並建立 parity ledger 與 20 版本 machine-readable matrix。
      Ubuntu 24.04 x86_64／ARM64 preview 與 22.04 x86_64 local container build/test
      已通過；24.04 ASan/UBSan 通過。後續 hosted workflow run `34742072894`
      兩個 job 全綠；GNOME 真打字尚未執行。
- [x] 2026-09-12 加入 Ubuntu 24.04 Fcitx 5 installed-addon X11 E2E：獨立 D-Bus、
      Xvfb、GTK 3 Entry 與 XTest/xdotool；逐鍵驗證注音 `ㄓ` → `ㄓㄨ` → `ㄓㄨㄥ`
      →「中」、倉頡 `a` →「日」、簡易 `a` →第二候選「曰」，`/proc` maps 核對
      staged addon，三者切到 `keyboard-us` 後同鍵序負控制分別為 `5j/ 1`、`a 1`、`a 2`。
      已在 Rancher Desktop x86_64 通過；併入既有 24.04 job，不新增 workflow/job。
      後續 hosted runner 已通過；GNOME／Wayland／popup 不得視為已驗收。
- [x] 2026-09-12 完成 Linux 注音 Standard、ETen、ETen26、Hsu、HanyuPinyin 五種
      鍵盤配置與 Fcitx 原生持久化下拉設定。L1 對固定 `bpmf-ext.cin` 的 1,541 筆
      unique keys 驗證可正規化鍵序，round-trip 覆蓋為 Standard／ETen 各 1,521、
      ETen26 1,495、Hsu 1,494；複用鍵無法區分的碰撞保留明確 exclusion。Ubuntu 24.04
      installed-addon X11/GTK3 後續擴充為五配置的二、三、四、輕聲逐鍵流程，
      均 commit「麻馬罵嘛」；ETen26／Hsu 核對複用鍵消歧中間態，漢語拼音另核對
      不完整 `zh` 退格到空，GTK host 並改為依序核對 preedit。五值設定 schema
      與每案 `keyboard-us` 負控制皆通過。這不等於更廣的錯誤輸入、GNOME／Wayland、
      候選窗畫面或完整 T02 已驗收。2026-09-13 最新決定改以 Windows 全功能為第一階段
      基準，因此五種布局與這個下拉設定維持支援，不拆除既有實作。
- [x] 2026-09-13 擴充 F03／F04 table 行為：嚴格 CIN reader 保存 `%endkey`，倉頡與
      簡易接受字表宣告的直接標點、單一候選直接提交；倉頡查無碼依預設清空，簡易
      到兩碼自動開候選，候選中繼續輸入會先提交反白項再開始下一組，單一候選則自動
      提交。L1 使用正式 `cj-ext.cin`／`simplex-ext.cin`；Ubuntu 24.04 Xvfb/GTK3
      新增兩案，精確提交「，用」與「明銖䍤、」，完整 staged suite 20/20 通過且每案
      都有 `keyboard-us` 負控制。F03／F04 不屬 Windows 第一階段基線，但最新決定是
      保留既有切片、註冊、測試與可擴充架構，不需拆除。
- [x] 2026-09-13 完成第一段 F03 倉頡萬用字元：Linux-only CIN dictionary 以穩定
      code／同碼來源順序支援 `?` 恰一碼、`*` 零碼以上；保留單獨首鍵的直接標點語意，
      接在字根後則等 Space／Enter 查詢。L1 合成表及正式 `cj-ext.cin` 均驗證順序，
      Ubuntu 24.04 Xvfb/GTK3 逐鍵以 `a?`、`a*` 精確提交「昌日」，英文負控制為
      `a? 1a* 1`；完整 staged suite 21/21 通過。這項既有切片保留為額外功能與未來
      擴充點，不阻擋 Windows parity。
- [x] 2026-09-13 當時先將 Linux 支援條件收斂至注音，倉頡／簡易未新增持久化或
      設定，候選學習／動態頻率也未加入。後續決定已改為 Windows 全功能對標；既有
      倉頡／簡易切片保留回歸與擴充結構。同批另完成 F01 注音 Big5-HKSCS 候選限制：
      L1 驗證可表示性、正式
      `bpmf-ext.cin` 順序及選取；Fcitx 原生設定預設保留所有 Unicode，Xvfb/GTK3
      逐鍵以 `,4` 從過濾後候選提交「𤦩」。Ubuntu 22.04 build/CTest/staging、24.04
      ASan/UBSan、configure／GNU Make source gate、完整 staged suite 22/22，以及
      24.04 套件初裝／升級各 21 個鍵盤案例、重裝後 22 案全數通過；GNOME／Wayland
      與 hosted workflow 仍待驗證。
- [x] 2026-09-13 先依 macOS TraditionalMandarin、再以 Windows TSF 交叉檢查，補齊
      Linux engine 的逐音節連續輸入與
      錯誤狀態保護：五布局候選開啟時，下一個合法 reading key 先提交目前反白字再開始
      新 reading；無效一般鍵與查無候選會保留 reading 並回報錯誤提示訊號，Ctrl／Alt
      應用程式快捷鍵維持放行。L1 合成資料覆蓋五布局、無效鍵、查無候選及快捷鍵；新增
      Fcitx→GTK3 X11 實體按鍵案例精確提交「中文」與在 `=`／`Ctrl+C` 後提交「中」，
      同時讓五布局的明示聲調鍵立即開候選，不再多按 Space。完整 warm
      `ci/dev.sh verify` 為 CTest 2/2、X11 24/24，更新後的 configure／GNU Make
      source-directory 與 out-of-source gate，以及 ASan／UBSan／LSan CTest 2/2
      亦通過。錯誤訊號已由 Fcitx adapter 透過 libcanberra 播放 XDG
      `bell-window-system`，`PlaySoundOnTypingError` 預設開啟；原生設定 UI 的關閉、保存、
      重啟讀回與錯誤路徑無崩潰已納入 24 案。Ubuntu 22.04／24.04 最低建置均通過，
      24.04 單次 `.deb` 亦確認 runtime dependency 為 `libcanberra0t64` 並建議安裝
      `libcanberra-pulse`；真正可聽效果仍待 GNOME 音訊 session 驗收。
- [x] 2026-09-13 依 macOS TraditionalMandarin 行為、再用 Windows TSF 交叉檢查，將
      五布局 reading 中的無效裸 `\` 與 `Ctrl+C` 加入同一批 L1 與 installed
      Fcitx→GTK3 X11 T02：普通無效鍵被吃掉並提示錯誤、快捷鍵放行，兩者都保留
      reading，隨後各布局仍精確提交「麻馬罵嘛」。五個 targeted X11 案例及完整 warm
      `ci/dev.sh verify` 的 CTest 2/2、X11 30/30 均在 WSL2 rootless container 通過；
      Ubuntu 24.04 package lifecycle 的 preview 初裝、release 升級各為 29/29，移除／
      重裝後含設定視窗為 30/30。package gate 同時發現 T09 英文負控制依賴 X11 key-up
      時序的偶發差異，改為正負控制都先清除可能殘值後，第二次完整 lifecycle 已通過。
- [x] 2026-09-13 補齊 T03 注音編輯／取消邊界：先由 macOS `OpenVanillaController`、
      `OVIMTraditionalMandarin` 與 PlainVanilla candidate event flow 固定 golden，再以
      Windows TSF 交叉檢查，
      L1 覆蓋空狀態 pass-through、reading 逐音 Backspace／整段 Escape、一般候選
      Backspace 關窗後只退最後一音，以及候選 Escape 清空。新增 installed-addon
      X11/GTK3 案例先讓空狀態 Backspace 刪除 App 的 `=`，再交錯兩種 Backspace 與兩種
      Escape，最終只提交「中文麻」；`keyboard-us` 負控制也通過。完整
      `ci/dev.sh verify` 為 CTest 2/2、X11 27/27；Ubuntu 24.04 package lifecycle 的
      preview 初裝、release 升級各為 26/26，移除／重裝後含設定視窗為 27/27。
      Ubuntu 22.04／Fcitx 5.0.14 的 build、CTest 2/2 與 staged install 亦通過；GNOME、
      native Wayland／XWayland 與多 App T03 仍待驗收。
- [x] 2026-09-13 補齊 T09 修飾鍵、repeat 與 key-up 邊界：先依 macOS
      TraditionalMandarin／PlainVanilla event flow，再以 Windows
      `KeyKeyEngineSession::wantsKey` 與 TSF control-key 白名單交叉檢查；L1 驗證 reading／一般
      候選中的 Ctrl+C、Alt+F、Super+L、Ctrl+Left、repeat，以及關聯詞與候選選字鍵的
      release 不會誤提交或破壞狀態。installed-addon X11/GTK3 案例長按 `Ctrl+\` 一秒後
      只切換一次，再於 reading／候選中送 Ctrl+C、Alt+F，精確提交 `x中文`；
      正負控制先以同一組 `Ctrl+A`／Backspace 清除長按時序可能留下的裸反斜線，
      `keyboard-us` 負控制固定為 `x5j/ 1jp61`。測試先重現
      X11 repeat 未標記導致反覆切換，
      Fcitx state 改以實體 backslash press/release latch 修正。完整 `ci/dev.sh verify`
      為 CTest 2/2、X11 28/28；Ubuntu 24.04 package lifecycle 的 preview 初裝、release
      升級各為 27/27，移除／重裝後含設定視窗為 28/28。Super、GNOME、native
      Wayland／XWayland 與多 App 快捷鍵仍待桌面驗收。
- [x] 2026-09-13 建立 T10 input-context／client lifecycle：L1 擴充為兩個 context 的
      reading、候選、reset、全半形與繁簡 filter state 隔離；installed-addon X11/GTK3
      以同一視窗兩個 `GtkEntry` 真實切焦點，第一欄候選失焦後清空 preedit，第二欄
      獨立提交「文」，切回第一欄先以 `1` 證明沒有沿用舊候選，再提交「中」。另一段
      在候選開啟時讓 client 正常關閉，確認 Fcitx 與 staged addon 仍存活，重啟 Fcitx
      後由新 client 再提交「中」；正向流程及 recovery 都有 `keyboard-us` 負控制。
      單獨 T10、完整 warm gate（CTest 2/2、X11 29/29）及 Ubuntu 24.04 package
      lifecycle（初裝 28/28、升級 28/28、重裝 29/29）均已通過；兩個同時存活的
      獨立 App 已由下列 2026-09-15 切片補上，GNOME 登出登入、native
      Wayland／XWayland 仍待桌面驗收。
- [x] 2026-09-15 擴充 T10 為兩個同時存活的獨立 GTK3 App：仍先查 macOS
      `deactivateServer:`，確認失焦時會 commit composing buffer 後清理，再查 Windows
      TSF，確認 document manager 失焦會 abandon 並非同步終止 composition。因 active
      preedit 語意不同，正式 isolation 案例只在空 composition 切焦點：App A 切為英文
      全形並輸出 `ａ`，App B 保持預設中文半形輸出「文」，切回 App A 後確認保留原狀態
      並完成 `ａｂ中`；兩個 process 在受控關閉前都仍存活。`keyboard-us` 負控制精確為
      `ab5j/ 1|jp61`。targeted T10、完整 warm gate（CTest 2/2、X11 33/33）及 Ubuntu
      24.04 package lifecycle（preview 初裝 32/32、release 升級 32/32、移除／重裝後
      33/33）均通過。local GTK3 active-preedit 診斷會在 App A 留下 `ㄓㄨㄥ中`，不能拿
      Windows abandon 語意改寫 addon；GNOME、其他 toolkit 與登出登入仍待驗收。
- [x] 2026-09-13 建立第一段 T11 編輯／敏感欄位邊界：installed-addon X11/GTK3
      先依 macOS OSX-IMK／TraditionalMandarin／PlainVanilla 事件流，再用 Windows TSF
      交叉確認：reading 中未帶 Ctrl／Alt／Super 的 Left／Right／Up／Down／Home／End／
      PageUp／PageDown／Delete／Tab（含 Shift 變體）由輸入法吃掉、保留 reading 並回報
      錯誤，組合快捷鍵仍交回 App；一般候選的 Home／End 精確跳到首／尾候選，不適用的
      Delete／Tab 與 Shift 編輯鍵也不漏入 App。installed-addon X11/GTK3 先在「甲乙丙」
      中間組字，送上述 caret／欄位鍵仍在原位置提交「中」，再以 Shift+Right 選取「乙」
      並由候選替換，精確得到「甲中中丙」；切到 `GTK_INPUT_PURPOSE_PASSWORD` 後確認 Fcitx 自動回到
      `keyboard-us`、輸出 literal `rup 1!` 而不產生關聯詞，再於不可編輯欄送完整注音
      鍵序後保持「唯讀」。正向與 `keyboard-us` 負控制均通過，完整 warm gate 為
      CTest 2/2、X11 30/30；Ubuntu 22.04 Fcitx 5.0.14 build／CTest／staging 亦通過。
      Ubuntu 24.04 `.deb` lifecycle 亦於 preview 初裝與 release 升級各通過 29/29，
      移除／重裝後含設定視窗通過 30/30，dependency、資料 hash、移除與設定 sentinel
      均通過。
      Adapter 對 `Password`／`Sensitive` capability 另有防禦性關聯詞清除。GTK3 App
      內容的滑鼠 selection 已於下列 2026-09-15 切片補上；GTK4／Qt／瀏覽器、GNOME 與
      Wayland 仍待驗收。
- [x] 2026-09-15 擴充同一 T11 installed-addon 案例的 App 內容指標選取：先查 macOS
      `OpenVanillaController`／PlainVanilla，再比對 Windows TSF。macOS 在外部強制結束
      composition 時可提交 residue 後清理；Windows 若 selection 離開追蹤範圍則放棄並
      非同步終止 TSF composition，兩邊不能假設完全相同。本切片只固定共同且無歧義的
      committed-text 路徑：GTK host 以 Pango layout 回報第二字 hit point，XTest 真實
      拖曳選取「乙」並精確觀測 selection `1:2`，再由注音候選替換為「中」得到
      「甲中丙」；後續 active-reading 編輯鍵回歸仍得到「甲中中丙」，`keyboard-us`
      負控制則精確得到「甲5j/ 1丙」。targeted T11 與完整 warm gate 均通過，後者為
      CTest 2/2、X11 32/32；active composition 期間以指標改 selection、GTK4／Qt／
      瀏覽器、GNOME 與 Wayland 仍待驗收。本次只改測試覆蓋，未重跑套件 lifecycle。
- [x] 2026-09-15 建立 GTK4 Standard 注音 T01 真實 client slice：先查 macOS
      `OVIMTraditionalMandarin` 選字後的 committed text 與 OSX-IMK
      `commitComposition`／`insertText`，再查 Windows TSF snapshot → `commitText` →
      候選更新／隱藏，確認兩邊在這條逐音、選字、清空流程一致。新增獨立 GTK4
      `GtkText` host，透過 installed addon 與實體 XTest 鍵序精確觀測 `ㄓ` → `ㄓㄨ` →
      `ㄓㄨㄥ` →「中」，`keyboard-us` 負控制為 `5j/ 1`。targeted 案例、完整 warm gate
      （CTest 2/2、X11 34/34）與 Ubuntu 24.04 package lifecycle（preview 初裝 33/33、
      release 升級 33/33、移除／重裝後含設定視窗 34/34）均通過。這一個 T01 切片
      完成當時，GTK4 T02–T12、GNOME、native Wayland／XWayland 仍待驗收。
- [x] 2026-09-15 將 GTK4 擴充至五布局 T02：先查 macOS
      `OVIMTraditionalMandarin` 的 `combineKey`、tone marker 立即查詢與候選事件流，再查
      Windows TSF 對同一共用 module 的 dispatch 及 Standard、ETen、ETen26、Hsu、
      Hanyu Pinyin 五項設定。兩邊都在 reading 中吃掉無效一般鍵並提示錯誤，Ctrl／Alt
      App shortcut 則 pass through。GTK4 `GtkText` 以真實鍵序逐布局輸入四聲／輕聲
      「麻馬罵嘛」，並核對 ETen26／Hsu 複用鍵中間態、Hanyu Pinyin 不完整 `zh` 退格、
      裸 `\` 與 `Ctrl+C` 後 reading 保留；每案都有 `keyboard-us` literal control。
      五個 targeted 案例、完整 warm gate（CTest 2/2、X11 39/39）及 Ubuntu 24.04
      package lifecycle（preview 初裝 38/38、release 升級 38/38、移除／重裝後含設定
      視窗 39/39）均通過。GTK4 T03–T12、GNOME、native Wayland／XWayland 仍待驗收。
- [x] 2026-09-15 將 GTK4 擴充至 T03 編輯／取消邊界：先查 macOS
      `OVIMTraditionalMandarinContext::handleBackspace`、`handleKey` 與 PlainVanilla
      candidate cancel flow，再查 Windows TSF `wantsKey`、`isPotentialKey` 與
      snapshot/updateComposition。兩邊的共同語意為空狀態將 Backspace／Escape
      交回 App，reading Backspace 只刪一個注音成分、Escape 清空；一般候選中
      Backspace 先關候選再刪最後一音，Escape 則取消整段 reading。GTK4
      `GtkText` 以真實鍵序重跑與 GTK3 相同的狀態轉移，只提交「中文麻」；
      `keyboard-us` 負控制亦通過。targeted T03、完整 warm gate（CTest 2/2、
      X11 40/40）及 Ubuntu 24.04 package lifecycle（preview 初裝 39/39、release
      升級 39/39、移除／重裝後含設定視窗 40/40）均通過。Windows 對標的
      GTK4 T06–T12、GNOME、native Wayland／XWayland 仍待驗收；T04／T05 為保留的
      Linux 擴充，不是 1.2.8 第一階段 blocker。
- [x] 2026-09-15 將 GTK4 擴充至 T06 候選導覽：先查 macOS `PVCandidate.h` 與
      直／橫 candidate controller，確認橫式會交換方向鍵的反白／翻頁角色且一般候選
      可由滑鼠索引轉選字鍵；再查 Windows TSF `CandidateWindow.cpp` 與
      `CandidateStateTest.cpp`，確認橫式只改繪製，核心仍用直式鍵盤語意，且自繪窗
      沒有 mouse-button 選字訊息。Linux 依第一階段 Windows 基線，兩種樣式都維持
      Up／Down 反白、Left／Right／PageUp／PageDown／Space 翻頁，同時保留 Fcitx
      原生滑鼠 callback。GTK4 直式鍵盤案選出「妐」、直式真實滑鼠第二列選出「鐘」，
      橫式案送 End、Home、PageDown、PageUp、Right、Left、Space、Down、Enter 後選出
      「妐」，三案都有 `keyboard-us` 負控制。targeted 三案、完整 warm gate
      （CTest 2/2、X11 43/43）與 Ubuntu 24.04 package lifecycle（preview 初裝 42/42、
      release 升級 42/42、移除／重裝後含設定視窗 43/43）均通過。GTK4 T07–T12 與
      GNOME X11／XWayland／native Wayland 的候選畫面、位置、點擊仍待驗收。
- [x] 2026-09-15 將 GTK4 擴充至 T07 關聯詞鍵盤與設定流程：先查 macOS
      `OVAFAssociatedPhraseContext` 與 PlainVanilla around-filter event flow，確認單字
      先提交、候選內容是不重複首字的後綴，並由 `Shift+1–9` 選取；再查 Windows TSF
      `KeyKeyEngine` 的同一模組載入與設定同步，兩邊在本段鍵盤語意一致，且關聯詞窗
      都不是一般候選的滑鼠控制流程。GTK4 `GtkText` 新增五案，分別驗證 McBopomofo
      預設「今→今天」、history-only「臺→臺灣史」、全部停用後 `Shift+1` 交回 App、
      舊逗號設定遷移，以及 D-Bus 寫入 government、重啟 Fcitx、讀回後輸入
      「中程計畫」；每案都有 `keyboard-us` 負控制。targeted 五案、完整 warm gate
      （CTest 2/2、X11 48/48）與 Ubuntu 24.04 package lifecycle（preview 初裝 47/47、
      release 升級 47/47、移除／重裝後含設定視窗 48/48）均通過。關聯詞滑鼠仍不是
      macOS／Windows 對標要求；GTK4 T08–T12 與 GNOME／Wayland 尚待驗收。
- [x] 2026-09-15 將 GTK4 擴充至 T08 中英文、全半形與繁轉簡：先查 macOS
      `OpenVanillaController.mm` 與 TraditionalMandarin／output-filter 事件流；macOS
      的 `Ctrl+\` 是輪替內建輸入法、單按 Shift 不切內部中英文、全形選單快捷鍵為
      Command+Shift+Space。再查 Windows TSF `TextService.cpp`／`SettingsApp.cpp`，其
      內部中文／英文模式、可停用 `Ctrl+\`、固定 Ctrl+Space、短按 Shift、Shift+Space
      全半形與 Caps Lock 才是 1.2.8 第一階段基線；兩平台的繁轉簡則都在輸出階段套用。
      GTK4 `GtkText` 新增四案，精確得到中英模式
      `5j/aBａ！　文abcde麻`、停用快捷鍵 `翁ㄓ`、全形 `Ａ！～　` 與繁轉簡 `台湾`，
      並各有 `keyboard-us` 負控制。停用 shortcut 時 GTK3 為 `ㄓ翁`、GTK4 為 `翁ㄓ`，
      這是 client 接收 active preedit 後的插入順序差異，不改 engine。targeted 四案、
      完整 warm gate（CTest 2/2、X11 52/52）與 Ubuntu 24.04 package lifecycle
      （preview 初裝 51/51、release 升級 51/51、移除／重裝後含設定視窗 52/52）均通過。
      GTK4 T09–T12 與 GNOME X11／XWayland／native Wayland 尚待驗收。
- [x] 2026-09-15 將 GTK4 擴充至 T09 修飾鍵、repeat 與 key-up 邊界：先查 macOS
      `OpenVanillaController.mm` 與 TraditionalMandarin candidate flow，確認 Command、
      一般 Ctrl／Option shortcut 在 loader 層交回 App，只有已處理的 key-down 才配對
      吃掉 key-up；再查 Windows TSF `TextService.cpp`／`KeyKeyEngine.cpp`，確認一般
      Ctrl／Alt 也在進 engine 前放行，普通 key-up 不吃，僅短按 Shift 另有切換語意。
      Linux 保留既有 X11 平台差異：長按 `Ctrl+\` 的 repeat 可能未帶 Repeat state，
      因此以實體 backslash press/release latch 保證只切一次。GTK4 `GtkText` 使用和 GTK3
      完全相同的長按、清除殘值、切回中文及 reading／候選中 Ctrl+C／Alt+F 鍵序，精確
      提交 `x中文`，`keyboard-us` 負控制為 `x5j/ 1jp61`。targeted 案、完整 warm gate
      （CTest 2/2、X11 53/53）與 Ubuntu 24.04 package lifecycle（preview 初裝 52/52、
      release 升級 52/52、移除／重裝後含設定視窗 53/53）均通過。Super 仍只在 L1，
      GTK4 T10–T12 與 GNOME X11／XWayland／native Wayland 尚待驗收。
- [x] 2026-09-15 將 GTK4 擴充至 T10 input-context／client lifecycle：先查 macOS
      `OpenVanillaController`，確認每個 controller 有獨立 loader context，失焦時會
      commit composing buffer 後清理；再查 Windows TSF `TextService.cpp`，其 document
      manager／context 失焦會 `abandonComposition()` 並非同步終止。兩邊 active
      composition 語意不同，因此沿用既有 T10 的共同可驗證邊界，不在 addon 強制統一。
      GTK4 `GtkText` 以和 GTK3 相同的實體鍵序驗證同 App 兩欄各自提交 `中|文`、候選中
      關閉 client 後 Fcitx/addon 存活、重啟 Fcitx 後新 client 再提交「中」，以及兩個
      同時存活 App 各自保留英文全形與中文半形狀態並得到 `ａｂ中|文`；兩案都有
      `keyboard-us` 負控制。GTK4 失焦時會短暫回報 client preedit 文字，切回後清除，
      最終 buffer 與狀態隔離正確。focus host 改成左右欄避免候選 popup 蓋住第二欄，
      runner 也會逐一嘗試同名可見 X11 window ID，排除快速重開的舊 ID。targeted 兩案、
      完整 warm gate（CTest 2/2、X11 55/55）與 Ubuntu 24.04 package lifecycle（preview
      初裝 54/54、release 升級 54/54、移除／重裝後含設定視窗 55/55）均通過。
      GTK4 T11–T12、GNOME X11／XWayland／native Wayland、Qt／瀏覽器及桌面登出登入仍待驗收。
- [x] 2026-09-16 一次完成 GTK4 T11–T12 與 Qt6 第一階段 X11 矩陣：比對仍先查
      macOS OSX-IMK／PlainVanilla／TraditionalMandarin，再查 Windows TSF，固定共同的
      組字、候選、關聯詞、符號與 App 編輯邊界，並保留 client 插入與 focus 行為差異。
      GTK4 補上 T11 指標選取 `1:2`、候選替換、active-reading 編輯鍵、密碼／唯讀欄，
      以及 T12 符號候選的鍵盤與滑鼠選取。新增獨立 Qt6 Widgets host，以
      `QLineEdit`／`QPlainTextEdit`、`QInputMethodEvent` 和真實 XTest 重跑 T01–T03、
      T06–T12 共 25 案，涵蓋五布局、直／橫候選、關聯詞設定保存、模式、兩 context、
      兩 App、client/Fcitx 復原、指標 selection、多行唯讀與符號列表。Qt6 的 password
      frontend 保留 engine 名稱但只送 literal；標準 read-only widget focus 後不穩定發布
      IME disable，host 以 Qt 的 `ImEnabled=false` query 明確宣告，Fcitx 核心即可放行，
      未加入 addon 特例。Qt6 的 `Alt+F` 會由 App 插入 `f`，且停用 `Ctrl+\` 後保留的
      preedit 插入順序亦與 GTK4 不同，均以 toolkit golden 固定。25/25 targeted batch
      與完整 warm gate（CTest 2/2、X11 83/83）通過；Ubuntu 24.04 package lifecycle
      亦在 preview 初裝與 release 升級各通過 82/82，移除／重裝後含設定視窗通過
      83/83，dependency、資料 hash、移除與設定 sentinel 全數通過。GNOME X11／XWayland／native Wayland、瀏覽器、
      Qt5、active-preedit 跨 App 與桌面登出登入仍待驗收。
- [x] 2026-09-13 完成 Windows 對標的 Linux F08 中英文模式：每個 Fcitx input context
      保存中文／英文狀態，狀態標籤顯示「中／英」，預設以 `Ctrl+\` 或 300 ms 內的
      單按 Shift 切換；進入任一模式都清除 active composition，英文半形將可列印鍵交回
      App，英文全形仍由 KeyKey 對映，Caps Lock 與長按 Shift 亦有負控制。原生設定
      schema／UI 可停用 `Ctrl+\` 並保存、重啟讀回。完整 warm `ci/dev.sh verify` 為
      CTest 2/2、X11 26/26；Ubuntu 22.04 的 Fcitx 5.0.14 build／CTest／staging 與
      configure／GNU Make source gate 通過。Ubuntu 24.04 package lifecycle 的 preview
      初裝、release 升級各通過 25 個純鍵盤案例，移除／重裝後完整 26 案通過；GNOME、
      native Wayland／XWayland 與實際桌面狀態選單仍待驗收。
- [x] 2026-09-12 建立 debhelper Debian packaging，產出
      `chichi77-keykey-data`（all）與 `fcitx5-chichi77-keykey`（每架構）兩包；Ubuntu
      24.04 amd64 local 已通過 lintian error gate、乾淨 runtime 安裝、受控 preview
      fixture 升級、移除、重裝；擴充 F03／F04 當時的 local gate 在初裝與升級
      各跑二十個純鍵盤 X11/GTK3 真實打字案例，重裝後跑完整二十一案，
      UI 較重的設定案例只在重裝後執行一次。
      Ubuntu 22.04 amd64 local 亦已在 Fcitx 5.0.14 通過建置、lintian error gate、
      乾淨 runtime 安裝、移除、重裝、dependency／資料 hash／授權檢查；該 smoke
      已接入既有第二個 CI job，並在 run `34742072894` 通過。workflow 總數維持 1、
      job 數維持 2，
      尚非正式發布套件。
- [x] 2026-09-12 完成第一段 F06 候選鍵盤導覽：Linux engine 與 Fcitx 5 支援
      Up／Down 跨頁循環反白、Left／Right／PageUp／PageDown 循環翻頁、Home／End
      跳整份候選首尾及 Enter 確定；L1 固定 12 候選驗證首尾與頁界，Ubuntu 24.04
      Xvfb/GTK3 以真實 `5j/` 候選送 End、Home、PageDown、Down、Enter 提交「妐」，
      `keyboard-us` 負控制為 `5j/ `。仍未包含
      滑鼠選字、直橫樣式、popup 畫面、GNOME 或 Wayland，不能將 F06 標為完成。
- [x] 2026-09-13 補上 F06 直／橫候選設定：預設 Vertical，可由 Fcitx 原生 enum
      改為 Horizontal，兩值皆轉為每份 candidate list 的 `CandidateLayoutHint`。
      AT-SPI 設定案例已實際切換、保存、重啟讀回，並在 Horizontal hint 下完成
      「作物育種」候選流程；完整 `ci/dev.sh verify` 為 CTest 2/2、X11 26/26，Ubuntu
      22.04 Fcitx 5.0.14 build／CTest／staging 與 configure／GNU Make source gate 亦通過。
      更新後的 Ubuntu 24.04 `.deb` lifecycle 亦為初裝 25/25、升級 25/25、重裝
      26/26。F07 比例／配色因屬 Fcitx UI/theme 尚未實作，F06 也仍缺
      GNOME／Wayland popup 畫面與滑鼠選字，不能標成完整 parity。
- [x] 2026-09-15 補上 F06 一般注音候選的 X11 真實滑鼠選字：先查 macOS
      `CVHorizontalCandidateControl`／兩種 candidate controller，確認點擊索引會換算為
      選字鍵並送入 PlainVanilla `CandidateChosen`／TraditionalMandarin commit；再查
      Windows TSF `CandidateWindow`，確認現行自繪窗只有鍵盤、繪製、DPI 與
      `WM_MOUSEACTIVATE`，沒有 `WM_LBUTTONDOWN`／`WM_LBUTTONUP` 選字訊息。Linux 保留
      Fcitx 原生 `CandidateWord::select` callback，新增 T06 installed-addon 案例：鎖定
      Vertical，等候候選窗越過 1×1／preedit-only 暫態後，以 XTest 點第二列並精確提交
      「鐘」，`keyboard-us` 負控制為 `5j/ `。targeted 鍵盤／滑鼠兩案、完整 warm gate
      CTest 2/2、X11 31/31 均通過；Ubuntu 24.04 package lifecycle 的 preview 初裝與
      release 升級各通過 30/30，移除／重裝後含設定視窗通過 31/31。GNOME X11、
      XWayland、native Wayland 的 popup 畫面／位置／點擊仍待驗收；符號候選滑鼠由下列
      T12 案例接續。不能將 F06 標成完整 parity。
- [x] 2026-09-12 完成第一段 F10／F11 標點與符號候選：Linux engine 與 Fcitx 5
      唯讀載入 `bpmf-punctuations.cin`；`Ctrl+,`／`Ctrl+.` 可提交「，」／「。」，
      `Ctrl+0`／`Ctrl+1` 可開啟真實候選表並以數字、翻頁與 Enter 選取。L1 驗證
      reading 保留及未定義 Ctrl shortcut pass-through；Ubuntu 24.04 Xvfb/GTK3 以
      真實 `Ctrl+0`、`1` 提交「，」，英文負控制只得到 `1`，套件三種狀態皆通過。
      仍未包含直接鍵盤標點、自訂符號／顏文字／常用文字視窗、視覺／滑鼠、
      GNOME 或 Wayland，不能將 F10／F11 標為完成。
- [x] 2026-09-15 補上 F11 符號候選的 X11 真實滑鼠選字：先確認 macOS
      TraditionalMandarin 的一般／標點候選會 yield 給 candidate handler，故 panel 可點；
      AssociatedPhrase 不 yield，並非關聯詞滑鼠的對標依據。再確認 Windows TSF 的
      `Ctrl+0`／`Ctrl+1` 會開同一標點資料，但自繪 `CandidateWindow` 沒有 mouse-button
      訊息。Linux 將 Fcitx 原生 pointer callback 保留為額外能力，新增 installed-addon
      案例以 `Ctrl+0` 開表、XTest 點第一列、接著輸入 `!`，精確得到「，!」，
      `keyboard-us` 負控制只得到 `!`。targeted 三案、完整 warm gate CTest 2/2、
      X11 32/32 均通過；Ubuntu 24.04 package lifecycle 的 preview 初裝與 release 升級
      各通過 31/31，移除／重裝後含設定視窗通過 32/32。GNOME X11、XWayland、native
      Wayland 的符號窗畫面／位置／點擊仍待驗收，不能將 F11 標成完整 parity。
- [x] 2026-09-12 完成第一段 F09 全／半形與繁轉簡：Linux engine 與 Fcitx 5 以
      `Shift+Space` 切換每個 input context 的狀態，全形模式將 ASCII space 及
      `!`–`~` 對映到 U+3000／U+FF01–U+FF5E，並在切換時保留 reading／候選。
      L1 覆蓋映射、repeat、reset、組字／候選保留與切回半形；Ubuntu 24.04
      Xvfb/GTK3 真實逐鍵提交 `Ａ！～　`，`keyboard-us` 負控制為 ` A!~ `，
      同源 3,058 筆舊轉換配對另透過 Fcitx 原生 Boolean 設定開啟；Xvfb/GTK3
      實際組成並選出「臺灣」、提交「台湾」；聲調即時查詢修正後的英文負控制為
      `w962j0 1`。
      Ubuntu 22.04 最低 API 與 ASan/UBSan 亦通過。尚未完成未啟用輸入法時的英文
      全形／全域狀態、macOS 繁轉簡快捷鍵對等、專用設定 UI、組合 filter 順序 baseline、
      GNOME 與 Wayland，
      不能將 F09 標為完成。
- [x] 2026-09-13 完成第一段 F05 內建關聯詞：Linux-only C++17 parser 唯讀解析
      McBopomofo 基本詞庫與 29 個分類 TSV，套用人名 exclusion、頻率門檻、排序、
      過濾、來源順序合併與跨來源去重；預設只開基本詞庫，Fcitx 原生巢狀設定提供
      基本詞庫與 29 分類的獨立 Boolean 選項，全部取消即停用，舊逗號格式以隱藏欄位
      migration。確定單字後顯示不含首字的詞尾，`Shift+1–9` 只提交
      詞尾，未按 Shift 的數字回到正常輸入。L1 使用完整真實資料與 parser 邊界；
      Ubuntu 24.04 Xvfb/GTK3 六個 T07 案例先得到「今天」、history-only
      「臺灣史」、停用後的「臺!」、舊設定 migration 後的「中程計畫」，以及以
      Fcitx `SetConfig` 寫入、
      落盤、重啟 Fcitx、讀回後仍得到「中程計畫」；每案均有 `keyboard-us` 負控制，
      running D-Bus schema 確認 30 個 Boolean 選項。第六案從 AT-SPI 找出
      `fcitx5-config-qt` 的 Bopomofo 列、Configure、兩個分類核取方塊及 OK，透過真實
      X11 點擊只開 agriculture-food，保存切換前後 PNG，核對 INI，重啟並讀回後逐鍵
      得到「作物育種」；package lifecycle 為節省 runner 時間只在 reinstalled 狀態跑此案。
      資料、顯示名稱與兩份來源授權均納入 staged install、DEB hash／移除檢查。Linux
      額外的關聯詞候選滑鼠操作尚未驗收，但 macOS source 已確認該 panel 不接受點選，
      Windows 自繪窗也沒有滑鼠選字，因此不列為 parity blocker。桌面登出登入、平台
      實際操作錄製、GNOME 與 Wayland 仍缺，不能將 F05 標為完成。
- [x] 2026-09-12 建立 Ubuntu 24.04 長駐本機開發 session：Apple Silicon 預設原生
      ARM64，dependency image 依 Dockerfile hash 重建，CMake build／stage 置於 named
      volumes，並可在同一 container 反覆執行 build、CTest、指定或完整 X11 E2E 及單次
      `.deb` build。local 實跑首次 build + CTest 17.4 秒、warm CTest 約 4.6–6.4 秒、單一 T01
      X11 案例 10.4 秒、80ms 間隔的 warm 完整 verify 25.3 秒、25ms 間隔的完整 X11
      E2E 15.0 秒，ARM64 package build 27.1 秒；
      另將 one-shot Docker build context 從整個 repository 縮到不含 source 的 container
      定義目錄。這些時間只代表目前 Rancher Desktop 主機，不是 CI SLA；乾淨 package
      lifecycle 與 amd64 release gate 仍使用既有獨立路徑。
- [ ] 依 `LINUX_DEVELOPMENT_PLAN.md` P0 先凍結 macOS 行為 baseline，再以
      Windows TSF 交叉檢查並凍結第一階段功能範圍，確認五布局、連續輸入、
      錯誤鍵、候選與設定行為；優先實證 Ubuntu 24.04 + Fcitx 5 三條 session
      路徑的真打字、addon 身分與負控制，再擴充其他 GNOME／KWin 組合。
- [ ] 完成 Linux-only 注音引擎、兩 adapter 與完整原生視窗／設定；禁止為此
      修改、搬動或連結四平台既有核心；資料唯讀共用。保留既有五布局、倉頡／簡易與
      繁轉簡切片的可擴充架構；候選學習／動態頻率、注音自動修正與 F12–F15 不加入。
- [ ] 依 `LINUX_TEST_PLAN.md` 建立逐鍵 golden、App 最終文字 assertion、Ubuntu 四年矩陣
      packages／安裝升級驗證，以及 PR／手動完整測試／release workflows；Linux desktop
      workflow 不設排程，未實跑不勾選。
- [x] 2026-09-13 在 Windows 11 x64 + WSL2 Ubuntu 24.04.4 + rootless Linux container
      engine 實跑 warm `ci/dev.sh verify`；初始 17 案耗時 18.22 秒，擴充 T02 後
      `linux/amd64`、2 個 CTest、18 個 X11 案例亦全數通過。這只補 Windows-hosted
      container 證據，不得取代
      GNOME／native Wayland 驗收。
- [ ] 下次全新 WSL 主機記錄 dependency image cold build 時間；目前 warm verify
      與已完成的 24.04 package lifecycle 都不能代表 cold build 時間。
- [ ] Ubuntu 完整發布 gate 達成後，才開始 P6 Debian 12／13 與 Fedora 36–44；
      重新計算四年範圍並逐列建立原生套件、桌面 E2E 與必要 CI。

### GitHub Actions

- [x] 2026-08-27 的 `v1.2.4` tag 已實跑 macOS 與 Windows workflow：兩者都成功，
      Windows 公開 Release 含 ZIP、unsigned EXE 與各自 SHA-256；macOS build artifact
      也包含公開詞庫，Windows 的 VS2026 修正已由該次 run 驗證。
- [ ] 從 GitHub Actions 頁面手動重跑 Android 與 iOS Simulator workflow，確認 hosted
      runner 的工具版本、7 天 artifact 與公開 `chichi77Collection` 都被封裝；Android
      的循環 symlink 修正仍待 hosted runner 驗證。

### iOS 發布

- [x] 2026-09-09 補上購買／恢復／重載共用忙碌狀態、連點防護與取消／錯誤復原；
      容器購買流程 7 組測試（15 個情境）通過，iOS Simulator Debug App 建置通過。
      同日 iPhone 17 Pro Simulator Release smoke 5／5 通過、零 skip；本機 Release
      archive 與匯出 IPA 的發佈簽章、App Group、資料庫與無 Debug 入口檢查均通過。
- [ ] App Store Connect 付費 App 協議確認為「有效」，完成必要稅務／銀行資料，再驗證
      Sandbox 購買並上傳含修正的新 build；更新審查備註中的錄影附件說明後重新送審。
- [ ] 用 Sandbox Apple ID 實測 `chichi_supporter` 的購買、待處理、取消、恢復與退款／撤銷，
      並確認容器 App 與 keyboard extension 透過 App Group 同步 entitlement；Simulator 的
      狀態與 UI 測試不能取代 App Store 伺服器交易驗證。

### macOS 發布

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

- [x] 2026-09-17 修正 Preferences 深色模式的白底白字，三種語系的表格改用系統動態底色；
      同時在直式候選每次更新後重設 scroll origin，避免放大候選窗時第 1、2 列移出可視範圍。
      三份 XIB 已通過 `ibtool --compile`，並以 Xcode 27／macOS 27 SDK 完成 arm64 Release
      target 建置。
- [x] 2026-09-17 重作 macOS 直式候選的寬度與子視圖布局：候選內容和 prompt 分別量測，
      明確配置兩欄、scroll view、提示列及翻頁控制，避免短候選仍保留多餘寬度以及
      `SHIFT + 數字鍵` 被截斷；已完成 arm64 Release target 建置。
- [x] 2026-09-17 完成 macOS UI 深色模式稽核：Preferences 與 PhraseEditor 三種語系的
      table/header、About 視窗、搜尋輸入框、符號表及橫／直式候選 XIB 均改用系統動態色；
      所有受影響 XIB 已通過 `ibtool --compile`，並完成 arm64 Release target 建置。
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
- [x] 2026-08-24 的語言列生命週期修正版已完成 x64／x86 Release 建置，x64 的 3 個
      CTest 也已通過。
- [ ] 安裝該修正版後，在 Android Studio 反覆以 `Ctrl+Space` 切換中英文，確認不再產生
      `studio64.exe`／`KeyKeyTsf_x64.dll` Application Error。
- [ ] 為 `KeyKeySettings.exe` 增加 UI automation：目前只有啟動 smoke test，仍需人工
      驗證一般／注音／關聯詞三頁、五種注音鍵盤、直橫選字窗、十種比例、四種配色、Ctrl+\\、
      提示聲與 CNS11643 開關在實際 TSF host 中會即時套用；候選窗另需在 100%／225%
      與兩台不同縮放比例的螢幕間移動驗證字型、間距及游標定位。
- [x] 已確認 Ctrl／Alt 快捷鍵放行時保留候選或聯想詞面板是設計決定：引擎收不到該鍵，
      `updateCandidateWindow` 不會被呼叫，且行為與 macOS 對稱。未來若改須兩平台一起改，
      不可單邊處理。

### iOS

- [ ] 完成 App Store Connect 的付費 App 協議、銀行與稅務資料，等狀態變成「有效」後，
      用 Sandbox 實測 `chichi_supporter` 的商品載入、購買與恢復，再上傳包含商品重試流程的
      新 build。2026-09-09 已修正商品查詢失敗仍顯示「付費支持」的流程，並清除 App Store
      文案與截圖中的 Android／Windows 資訊。
- [x] 五台 Simulator 已加入共用 XCUITest target 與 `run-simulator-tests.sh`；
      2026-09-02 的 `--host-only` 基線為 79 個 Swift tests 與五台各 3 個 UI tests 全部
      通過（含 App 內授權告知）。
- [ ] 逐台切到琦琦注音跑 extension-required 模式，完成 A–K 並把結果記進
      `IOS_SIMULATOR_TEST_PLAN.md`。系統輸入切換器不能由 XCUITest 穩定選定，不得把
      opt-in 成功當成 extension 功能通過。
- [x] 2026-09-06 的實體鍵盤編輯器針對性回歸已通過 93 個 Swift tests；iOS 26.5
      iPhone 17 Pro 與 4.7 吋 iPhone SE 通過入口、控制項與直橫旋轉復原測試，iOS 26.5
      iPad 通過橫式四欄測試。這只涵蓋編輯器本次改版，不可取代五台 A–K。
- [ ] 用實體 USB／藍牙鍵盤驗證容器編輯器的注音、一般候選 `1–9`、關聯詞
      `Shift+1–9`、Space／Page Up／Page Down 翻頁、方向鍵、全半形、Ctrl／Command
      複製／分享／清除與清除確認；後續版面改動至少重跑兩台 iPhone 的
      `testHardwareKeyboardEditorHasCopyAndShareActions` 與 iPad 的
      `testHardwareKeyboardEditorLandscapeColumns`，並把結果同步到 iOS test plan。
- [x] 11 種 `UIKeyboardType` 的純邏輯測試與 iOS 26.5 iPhone 17 Pro Simulator
      App／extension build 已於 2026-09-02 通過；當時整套為 79 個 Swift tests。
- [ ] 在實機或 Simulator 測試 `default`、`asciiCapable`、`numbersAndPunctuation`、URL、
      numberPad、phonePad、namePhonePad、emailAddress、decimalPad、webSearch、
      asciiCapableNumberPad；確認直橫式 disabled key 無法點擊、VoiceOver 朗讀為 disabled，
      並確認 secure、phonePad、namePhonePad 由 iOS 換回系統鍵盤。`selectionDidChange`
      的游標移動清理、inline marked text 與 MODE／SHIFT 預覽仍須依
      `IOS_SIMULATOR_TEST_PLAN.md` 在五台受控 Simulator 跑完 A–K 才算完整驗證。

- [ ] 版號集中：`MARKETING_VERSION` 目前寫在 pbxproj 的 Debug／Release 兩個 project
      configuration 裡，可抽成 xcconfig（2 處 → 1 處）。
- [x] 2026-08-23 已用 hierarchy dump 驗證 VoiceOver 元素樹：直式共 57 個元素，順序為
      狀態列 → 候選列（上一頁／「第 n 個候選，字」／下一頁）→ 四排注音鍵 → 功能列；
      每個都有中文標籤，聲調鍵唸注音符號而不是鍵位數字，空候選格已排除。
- [ ] 實際開 VoiceOver 聽朗讀與 rotor 行為，並執行 accessibility audit；元素樹檢查
      不能取代真人聽測。
- [ ] 設定面板每列的文字與開關是兩個獨立元素，VoiceOver 會把詞庫名稱唸兩次
      （系統「設定」App 是合併成一個元素）。要修就把整列包成一個
      `UIAccessibilityElement`，或改用 `UITableViewCell`。
- [x] iPad keyboard extension 已使用專用 `.pad` metrics（330pt 高、最大 820pt 置中），
      實體鍵盤編輯器的橫式四欄也已通過 iPad UI 測試。
- [ ] 依 A–K 在 iPad 人工檢查直橫式實際字級、Dynamic Type、VoiceOver 與長時間輸入；
      frame assertion 不能取代視覺驗證。
- [x] 直式聲調符號已放大 1.8 倍；橫式刻意維持正常字級，因為橫式把注音與鍵位併成
      一行（`ㄅ 1`），只放大其中一個字會高低不齊，且橫式該排只有 26pt。未來若要放大，
      必須先拆成兩個 label。

### Android

- [x] 2026-09-17 已將注音字表與 30 個關聯詞庫改為建置時產生 `.kki` 索引；core 不再於
      IME 啟動時解析 CIN，關聯詞改用低優先序背景載入及按鍵延遲解碼。另加入直式／橫式
      各自 50%–200% 的虛擬鍵盤高度、0–100ms 每 1ms 的震動設定與舊震動設定遷移；
      JVM 測試會逐項比對原始字典與產生索引。`lintDebug testDebugUnitTest assembleDebug`
      已通過。API 26 `Medium_Phone` 的單次 cold-process smoke 中，`ime set` 在詞庫全關為
      0.11 秒、30 庫全開為 0.09 秒，全開後可輸入「今」並顯示關聯候選，crash buffer 為空；
      API 35 `Medium_Tablet` 已目視橫式 75%／150%、直式 150%，API 26 實體候選列也未被
      虛擬鍵盤比例改變。這些是抽樣 smoke，不是 Pixel C 實機或下列六台 AVD 完整矩陣。
- [x] 2026-09-17 已把手機與平板共用的橫式 100% 內容高度由特別縮小的 155dp 改為一般
      比例 230dp；API 35 `Medium_Tablet`（2560×1600）與 API 30 `Pixel_4a`
      （2340×1080）皆已在橫式 100% 目視確認候選列、四排注音鍵、功能列與系統區完整，
      沒有裁切或重疊。
- [ ] 在 Pixel C／Android 8 分別以詞庫全部啟用與全部關閉量測冷啟動及再次叫出鍵盤時間，
      確認沒有原本約 10 秒與 1–3 秒的等待；再以 1、5、10ms 比對 Gboard 短震動手感，並
      目視確認直式／橫式 50%、100%、200% 與實體候選窗不受比例影響。
- [x] Android 欄位與 Enter action 的 JVM 策略測試已加入，並於 2026-08-30 通過
      `lintDebug testDebugUnitTest assembleDebug`。
- [ ] 在 Android 實機依序測一般、Email、URL、電話、整數、小數、日期時間、密碼、姓名、
      地址、搜尋、簡訊／長文字與 ASCII 欄位；直橫式各確認 disabled key 無 hit／無震動，
      軟 Enter 的完成、下一個、搜尋、傳送、前往、上一個及 App 自訂 `actionLabel`／
      `actionId` 會觸發正確 action，而 USB／藍牙 Enter 仍送 plain Enter，且實體字元不受
      觸控欄位限制。

- [x] 2026-08-30 已在 Pixel 9a 驗證設定列正常顯示、觸控按住預覽鍵無執行期錯誤；
      composing `ㄅ` 移到字首後輸入 `ㄚ` 得到 `ㄚㄅ`，`ㄅㄚ` 選取尾字後輸入 `ㄉ`
      得到 `ㄅㄉ`，確認游標與 selection range 都沒有沿用舊 reading。
- [ ] 在 Android 實機補測組字／候選開啟時由滑鼠及 App 程式改變游標或選取範圍，確認會
      清除舊引擎狀態，而 IME 自己逐鍵更新 composing、確定候選與建立關聯詞不會被誤清；
      人工畫面確認直橫式文字／注音／符號鍵預覽約放大 1.4 倍、邊緣鍵不超出畫面、滑出與
      放開會消失，設定關閉後不再顯示。該裝置的 ADB 截圖輸出全黑，不能取代目視檢查。

- [x] 2026-08-30 已加入 Android modifier bit、全形映射與引擎單元測試，並通過
      `lintDebug testDebugUnitTest assembleDebug`。
- [ ] 接上真正的 USB／藍牙鍵盤，確認底部候選列為 12 個等寬按鍵（9 候選、Emoji、
      `ㄅ／英`、`半／全`），沒有 ▲／▼；驗證點擊後兩鍵可切換，並再驗證 `Ctrl+Space`、
      `Shift+Space` 的 keydown／keyup／長按，以及全形 `Ａｚ０９！～　`、切回半形和
      reading／候選保留。ADB `input keycombination` 直接送到 editor，不會經過
      `InputMethodService.onKeyDown`，不能代替實體鍵盤驗證。

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
- [x] Android Enter 鍵描邊繪製（`drawEnterKey`）已於 2026-08-24 通過
      `lintDebug testDebugUnitTest assembleDebug` 編譯驗證。
- [ ] 在 Android 模擬器或實機截圖，比對 Enter 鍵外觀與 iOS 一致。
- [x] 2026-08-24 已在 Pixel 9a 的 Google 搜尋欄實測單一 composing `ㄅ` 按 Backspace
      會完整移除，不會留下失去底線的 `ㄅ`。
- [ ] 增加會在模擬器或實機啟動 `BopomofoImeService`，並驗證組字、觸控候選列、
      外接鍵盤一般候選 `1–9`／關聯詞 `Shift+1–9`、一次性注音 Shift、英文大小寫與
      兩套數字符號版面、`ㄋㄧˇ` Backspace 退音及複合 Emoji 一次刪除、
      關聯詞接續與全部關閉、符號／Emoji 各 10 頁及循環翻頁、外接鍵盤
      `Ctrl+Space`／`Shift+Space`／`Ctrl+,`／`Ctrl+.`／`Ctrl+0`／`Ctrl+1` 與全半形的
      smoke test；另需驗證實體鍵盤浮動候選預設關閉、直橫排列、游標四邊翻轉、
      不支援 `CursorAnchorInfo` 時的底部中央備援、觸控選字、方向鍵反白、Enter 與 ESC；
      目前 JVM 單元測試與 APK 建置無法攔截 D8／R8 合成類別漏包及
      `InputConnection` 互動之類的執行期問題；也應截圖檢查底列沒有與系統導覽區重疊，
      並確認直橫式 11 欄按鍵等寬、橫式文字沒有裁切。
