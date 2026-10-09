# 建置、安裝與打包 / Building, installation, and packaging

本文件集中說明琦琦輸入法各平台的建置流程。

Linux 1.3.1 的 Ubuntu Desktop 24.04 LTS、GNOME Shell 46、Fcitx 5、amd64 安裝流程見
[Ubuntu 安裝與使用指南](LINUX_INSTALL.md)。Ubuntu 24.04 套件與 macOS、Windows
依各自版本提供於 [GitHub Release](https://github.com/polobread/KeyKey/releases)；Android 與 iOS 原始碼開發版號為 `1.3.3`，商店正式版 `1.3.2` 已分別在 Google Play 與 App Store 上線（iOS build 41）；Android 於 2026-10-08 正式發布，不再要求一般使用者加入封閉測試。Windows `1.3.2` 尚未發布，macOS、Linux 與共用模型仍為 `1.3.1`。先前 Linux 版本的發布紀錄保留在
[1.2.8 發布說明](Source/Loaders/Linux-IME/docs/linux-1.2.8-release.md)。
其他 Ubuntu 版本、IBus、ARM64 與其他發行版另行驗收。以下保留開發與建置紀錄。
目前已有可建置的 Linux-only 引擎與 Fcitx 5
外掛，以及 local X11/GTK 3、GTK 4、Qt 6 各自適用的完整第一階段真實逐鍵矩陣，
並已在隔離 Ubuntu 24.04 GNOME X11 session 通過 76 個不重啟桌面 Fcitx 的案例；
另在完整 Ubuntu 24.04 GNOME Wayland KVM guest 通過涵蓋 native Wayland／XWayland
的舊版 160/160 組逐鍵／滑鼠矩陣；加入符號表真滑鼠後，系統安裝的候選
面板下完整 168/168 組通過。真實 gedit 四條輸入路徑與 GNOME Text Editor 的直接 Fcitx
Wayland／XWayland 路徑已通過，後者的兩條 GTK Wayland IM 路徑仍有缺口。
雙欄焦點正負控制 16/16 通過並量到失焦語意依輸入路徑而異。
更廣的視窗／App 相容性與實體雙螢幕仍待驗收。GNOME Shell 46 的獨立候選
面板套件已在 Ubuntu 24.04 VM 測過安裝、升級、停用與再啟用。開發／套件規格見
[LINUX_DEVELOPMENT_PLAN.md](LINUX_DEVELOPMENT_PLAN.md)，實際打字與 GitHub Actions
驗收見 [LINUX_TEST_PLAN.md](LINUX_TEST_PLAN.md)。

[English](#english)

## Linux 原始碼建置

Ubuntu 24.04 使用者若要從下載、編譯一路完成 Fcitx 啟用與試打，請先看
[Linux `./configure` 編譯安裝與使用指南](LINUX_CONFIGURE_INSTALL.md)。

傳統原始碼建置需要 CMake 3.22、GNU Make、C++17 compiler、`pkg-config`、
Fcitx 5 Core、libcanberra 與 SQLite 3 開發檔，以及 Python 3；
不需要 Ninja、Docker、Autoconf 或 Automake。Ubuntu 可先安裝：

```sh
sudo apt-get install build-essential cmake libcanberra-dev libfcitx5core-dev libsqlite3-dev pkg-config python3
```

接著使用預設 `/usr/local` prefix：

```sh
cd Source/Loaders/Linux-IME
./configure
make -j2
make check
make DESTDIR="$PWD/out/source-stage" install
```

最後一行只做無權限的暫存安裝。要實際安裝改用 `sudo make install`，移除則用
`sudo make uninstall`；uninstall 只依這次建置的 install manifest 刪除專案檔案，
不刪除使用者設定、其他使用者資料或其他檔案，也不會自動切換預設輸入法。發行版形式可改用
`./configure --prefix=/usr`。若系統已安裝 `fcitx5-chichi77-keykey` 或
`chichi77-keykey-data` 套件，不要直接覆寫套件管理器的檔案；先移除套件，或在回到套件版
以前先執行 source build 的 `make uninstall`。

`./configure --help` 另列出 `--libdir`、`--datadir` 與 adapter／測試選項，並支援
`CXX`、`CPPFLAGS`、`CXXFLAGS`、`LDFLAGS`。`make clean` 保留配置，
`make distclean` 只移除此 configure 產生的 wrapper Makefile 與隔離 build directory。
也可另建空目錄，再從該目錄執行完整路徑的 `configure`。非標準 prefix 的 Fcitx session
搜尋路徑與完整注意事項見
[Linux frontend README](Source/Loaders/Linux-IME/README.md#configure-and-gnu-make-source-build)。

開發者若已安裝 Ninja，也可繼續使用既有 CMake preset：

```sh
cd Source/Loaders/Linux-IME
cmake --preset linux-release
cmake --build --preset linux-release
ctest --preset linux-release
```

macOS 開發機可用 Rancher Desktop 或其他 Docker-compatible engine 重現 Ubuntu
userspace。日常修改優先使用一個長駐的 native-architecture 開發 container：

```sh
Source/Loaders/Linux-IME/ci/dev.sh up
Source/Loaders/Linux-IME/ci/dev.sh test
Source/Loaders/Linux-IME/ci/dev.sh source
Source/Loaders/Linux-IME/ci/dev.sh source-e2e
Source/Loaders/Linux-IME/ci/dev.sh e2e T01-X11-GTK3-BOPOMOFO-STANDARD
Source/Loaders/Linux-IME/ci/dev.sh verify
Source/Loaders/Linux-IME/ci/dev.sh package
```

`dev.sh` 在 Apple Silicon 自動使用 `linux/arm64`，保留同一個 container，並把
incremental build／stage 放在 Docker named volumes；`down` 只移除 container，保留
編譯快取。`e2e` 可指定一個 case、逗號分隔的 cases 或 `all`。這條快速路徑產生的
ARM64 package 是未列入支援範圍的測試產物，不能取代 x86_64 release gate；`package` 也不取代乾淨
runtime container 的安裝／升級／移除驗證。
`source-e2e` 使用乾淨的一次性 container，分別驗證 `/usr/local`、`/usr` 與自訂
prefix 的原始碼安裝、GTK3／GTK4／Qt6 X11 真實打字及解除安裝；自訂 prefix 另驗證
無關檔案保留與重裝。
Ubuntu 24.04 GNOME Wayland 的本機 KVM guest 建立、`.deb` 安裝、逐鍵／滑鼠矩陣與
真實 App 驗證見 [VM 手冊](Source/Loaders/Linux-IME/docs/gnome-wayland-vm.md)。

Windows 11 可從 WSL2 Ubuntu 使用同一組指令。Repository 必須放在 WSL 的 Linux
filesystem（例如 `/home/.../KeyKey`），不要放在 `/mnt/c` 或會自動轉 CRLF 的 Windows
checkout；先確認 `docker info` 能從一般 WSL shell 連到 Linux container engine。
若受限制的自動化行程回報 Docker socket `permission denied`，但一般 WSL shell 的
`docker info` 正常，這是呼叫行程的 sandbox 權限，不是 daemon 或 socket mode 壞掉；
應允許該行程存取本機 Docker socket，不要改用 `sudo docker` 或把 socket 改成
world-writable。完整診斷與 named-volume 注意事項見
[Linux frontend README](Source/Loaders/Linux-IME/README.md)。

以下 one-shot 指令仍用於獨立、可重建的 Ubuntu userspace 檢查：

```sh
Source/Loaders/Linux-IME/ci/run-ubuntu-24.04.sh
Source/Loaders/Linux-IME/ci/run-ubuntu-22.04.sh
Source/Loaders/Linux-IME/ci/run-ubuntu-24.04-x11-e2e.sh
Source/Loaders/Linux-IME/ci/run-debian-package.sh ubuntu-24.04
Source/Loaders/Linux-IME/ci/run-debian-package.sh ubuntu-22.04
```

第一個指令是主要 Ubuntu 24.04 / Fcitx 5 build，第二個守住 Ubuntu 22.04 的最低
API 邊界，第三個另跑已安裝 addon → Fcitx 5 → GTK 3／GTK 4／Qt 6 的 X11 真實逐鍵輸入：
三套 toolkit 覆蓋各自適用的 T01–T03、T06–T12，且都有英文負控制；並驗證
注音設定 schema。五種布局都是 Windows 對標的
Linux 1.2.8 第一階段範圍。已完成的倉頡／簡易切片保留作回歸與未來擴充，不需從程式或
測試中拆除。這些 one-shot 指令預設建立
`linux/amd64` 產物；ARM64 測試產物可在指令前設定
`KEYKEY_DOCKER_PLATFORM=linux/arm64`。Xvfb E2E 是 L3 X11 證據，不等於 GNOME／
native Wayland 的實際桌面打字測試。詳細狀態與輸出路徑見
[Linux frontend README](Source/Loaders/Linux-IME/README.md)。

後兩個指令用 debhelper 產生依發行版命名的 `chichi77-keykey-data` 與
`fcitx5-chichi77-keykey` 套件。24.04 會在安裝、受控升級及移除後重裝三個狀態，
各跑一次八十二個不開設定視窗的 X11 真實輸入案例，並只在重裝後多跑一次 Fcitx 原生設定視窗
點選、保存、重啟及真實打字案例（合計八十三案）；22.04 則跑較省時的套件安裝／移除 smoke。
Ubuntu 24.04 amd64 的安裝套件與支援範圍見 [Linux 1.3.1 安裝與使用指南](LINUX_INSTALL.md)；
本節指令產生的本機套件仍需通過發布流程的驗證，才可作為 GitHub Release 安裝檔。

Ubuntu 24.04 的套件建置另產生獨立 GPL-2.0
`gnome-shell-extension-keykey-kimpanel` `.deb`，只支援 GNOME Shell 46，供
GNOME Wayland 候選面板使用。安裝、啟用、停用和同 UUID 的 user-local
extension 處理方式見 [面板說明](Source/Loaders/Linux-IME/gnome-panel/README.md)。
`fcitx5-chichi77-keykey` 另安裝「文字編輯器（琦琦注音）」啟動器與
`keykey-fcitx-app`；這兩者只為個別啟動的 GTK App 選用直接 Fcitx 輸入路徑。

## macOS

### 需求

- macOS 15 以上
- Xcode
- Homebrew 的 `openssl@3`
- Ruby、GNU Make 與 `sqlite3` 命令列工具，用於既有 DatabaseCooker

### 建置

```sh
brew install openssl@3
cd Source
(cd Distributions/Takao/DatabaseCooker && make)
xcodebuild -project Takao.xcodeproj -target "Takao (Loader OSX-IMK)" \
  -configuration Release -xcconfig Takao-macOS.xcconfig build
```

DatabaseCooker 會產生
`Source/Distributions/Takao/CookedDatabase/KeyKey.db`，Xcode 再將它包進
`chichi77 KeyKey.app`。建置時也會以 `DataSource/McBopomofo/phrase.occ`、
`BPMFMappings.txt` 及注音字表產生好打注音的 unigram 語言模型；不需要 Yahoo 未釋出的
中研院語料或舊的 `PhraseTool`／CEROD 工具。另以
`DataSource/AISyntheticBigram/corpus-v1.txt`、`corpus-v2.txt`、`corpus-v3.txt`、
試打回饋與去重後的 2,300 篇文章建立合成 bigram 與 backoff；語料每行
一句，可使用空白標示詞界，也可交由 cooker 依現有 unigram 詞頻切詞。
`DataSource/AISyntheticBigram/numeric-unit-lexicon.tsv` 另以資料列補入中文數字與
常用單位組合；阿拉伯數字開頭的詞組目前不走這條詞庫路徑。

目前 macOS build 僅支援 arm64。若要製作 universal binary，需要另行準備
x86_64 OpenSSL 並調整 `Source/Takao-macOS.xcconfig`。

### 分類關聯詞詞庫

`DataSource/chichi77Collection` 已納入公開 repository，macOS DatabaseCooker 會固定
把其中 29 份 TSV 寫入 `KeyKey.db`，不需私人 checkout、symlink 或 secret。這些資料
由自動化方式生成、推論與整理，沒有逐筆人工校正，也不保證正確性或完整性。

### 安裝包

安裝包的建置、本機安裝、簽署及 notarization 說明見
[Installer/README.md](Installer/README.md)。

## Windows 10 與 11

### 需求

- Windows 10 或更新版本（目前開發機在 Windows 11 驗證；Windows 10 待實機驗證）
- Visual Studio 2026，安裝「使用 C++ 的桌面開發」workload；也提供 Visual
  Studio 2022 相容 preset
- CMake 3.25 以上；Visual Studio 內附版本即可
- .NET 10 SDK（設定頁與部署工具皆 self-contained；使用者不需另裝 runtime）
- Python 3（驗證預先產生的共用資料庫）
- NSIS 3.12（只有建立 Store EXE 時需要）

Windows 建置只驗證並複製正式共用 `Source/Distributions/Takao/CookedDatabase/KeyKey.db`，
不得自行 cooker；SQLite 連結 Windows 內建的 WinSQLite3。不需要 GNU Make、
`awk`、`sed` 或外部 `sqlite3` 程式。

### 建置及測試 x64

開啟 Visual Studio 的 **x64 Native Tools Command Prompt 或 PowerShell**，從
repository 根目錄執行：

```powershell
cd Source\Loaders\Windows-TSF
cmake --preset windows-x64
cmake --build --preset windows-x64-release
ctest --test-dir .\out\build\x64-ninja --output-on-failure
cmake --preset windows-x86
cmake --build --preset windows-x86-release
ctest --test-dir .\out\build\x86 -C Release --output-on-failure
```

輸出檔案為：

```text
out\build\x64-ninja\KeyKeyTsf.dll
out\build\x64-ninja\KeyKeySettings.exe
out\build\x64-ninja\KeyKeySettingsBackend.dll
out\build\x64-ninja\KeyKeyDeployment.exe
out\build\x64-ninja\KeyKeyRegistration.exe
out\build\x64-ninja\Databases\KeyKey.db
```

共用資料庫含 `DataSource/chichi77Collection` 的公開分類詞庫，平台建置不另煮資料。

### 本機註冊

開發階段可直接註冊 build 目錄中的 DLL。註冊範圍是整台電腦，會顯示 UAC：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-Tip.ps1 `
  -DllPath .\out\build\x64-ninja\KeyKeyTsf.dll
```

註冊後，使用者自行到繁體中文（台灣、香港或澳門）的「語言選項 → 新增鍵盤」
加入琦琦，再用 `Win+Space` 選用；註冊腳本不變更語言清單或預設輸入法。
詳細 Win10／Win11 步驟見 [Windows 安裝指南](WINDOWS_INSTALL.md)。解除註冊：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-Tip.ps1 `
  -DllPath .\out\build\x64-ninja\KeyKeyTsf.dll -Unregister
```

### 打包給另一台 Windows 電腦

完成建置及測試後，在 `Source\Loaders\Windows-TSF` 執行：

```powershell
.\Package-Windows.ps1 -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86
.\Package-Windows.ps1 -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86 -Architecture x86
```

會產生 x64 與 x86 兩種 ZIP。選擇與 Windows 系統架構相同的套件；在另一台 Windows 10
或 11 電腦完整解壓縮後，請把整個資料夾複製到本機 `C:\`（例如
`C:\KeyKeyInstaller`），再執行 `Install.cmd` 並允許 UAC。安裝程式會：

- 將整套檔案複製到 `C:\Program Files\chichi77 KeyKey\1.3.2-內容指紋`
- 驗證後才切換 TSF 註冊，保留仍供舊行程使用的 payload
- 在 Windows「已安裝的應用程式」加入解除安裝項目

請勿直接從網路磁碟、NAS 或 UNC 路徑安裝；UAC 後可能無法存取原路徑，且安裝
視窗可能立即關閉。開始部署後的記錄位於 `%ProgramFiles%\chichi77 KeyKey\Deployment.log`。

首次安裝須自行在 Windows 設定新增鍵盤；升級保留共用入口的選擇，舊香港／澳門入口使用者需改選共用入口。請登出再登入載入新版。
這是未簽署的家用測試套件，因此從網路下載時 Windows 可能顯示安全警告。

Windows x64 套件會同時安裝 x64 與 x86 TSF DLL，可供所有 32 位元應用程式使用；
x86 套件供 32 位元 Windows 使用。
DLL 架構必須和載入它的應用程式架構相同。

本機要產生未簽署的 NSIS 測試安裝檔，可執行：

```powershell
.\Package-Store-Windows.ps1 -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86 -UnsignedTest
```

產物是 `out\store-package\chichi77-KeyKey-1.3.2-windows-x64-setup.unsigned.exe`。
Windows 產品版號為 `1.3.2`；ZIP、未簽 EXE 與正式簽章包一律使用 `1.3.2-<內容指紋>`。
修復使用 `1.3.2-<新實例 ID>`，新目錄不含 `test`；舊 `test` 目錄仍可辨識供遷移。

Windows frontend 的部署及驗證細節見
[Source/Loaders/Windows-TSF/README.md](Source/Loaders/Windows-TSF/README.md)。

### 手動簽署 Microsoft Store NSIS EXE

正式商店套件不把憑證私鑰放進 GitHub Actions。先把受信任 CA 核發的程式碼簽章憑證
安裝至 Windows 憑證存放區，安裝 NSIS 3.12，再執行：

```powershell
$thumbprint = '你的 40 字元憑證指紋'
$timestampUrl = '憑證機構提供的 RFC 3161 時間戳記 URL'

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Package-Store-Windows.ps1 `
  -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86 `
  -CertificateThumbprint $thumbprint `
  -TimestampUrl $timestampUrl
```

腳本會在暫存副本簽署並驗證 x64／x86 DLL、設定 EXE、設定後端 DLL、部署 EXE 及 x86 bridge，以 NSIS 建立離線安裝
程式後再簽署並驗證外層 EXE；不會修改原建置輸出，也不會儲存 PFX 密碼。結果位於
`out\store-package\chichi77-KeyKey-1.3.2-windows-x64-setup.exe`。完整參數、`/S`
靜默安裝測試及 Partner Center 的版本化 HTTPS URL 說明見 Windows TSF README。
解除安裝器沿用已簽署的部署 EXE。完成頁提供自行新增鍵盤的步驟；升級提示登出再登入，
不自動開設定。版本目錄保留至移除時按清冊清理；個人設定、自訂詞與學習資料保留。

## Android

### 需求與建置

- Android Studio
- JDK 17 以上
- Android SDK 36.1 與 Build Tools 36.0.0

```powershell
cd Source\Loaders\Android-IME
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug
```

建置時會自動從 `Source/DataTables` 複製 `bpmf-ext.cin` 與
`bpmf-punctuations.cin`，並從 `DataSource/McBopomofo` 加入基本關聯詞詞庫，另固定
加入 `DataSource/chichi77Collection` 的 29 個公開分類詞庫。建置會從 CIN、基本詞庫與
29 個 TSV 產生 `.kki` 索引，並把 cook 好的 `KeyKey.db` 加入 APK，供預設的好打注音
整句組字使用；Android 執行時讀取索引，關聯詞索引在背景載入。
Debug APK 位於
`app/build/outputs/apk/debug/app-debug.apk`。安裝後開啟「琦琦輸入法」，依畫面按鈕
啟用並選擇輸入法。Android frontend 的配置與操作方式見
[Source/Loaders/Android-IME/README.md](Source/Loaders/Android-IME/README.md)。

## iOS

### 需求、建置與測試

- macOS 與 Xcode
- 可用的 iOS Simulator runtime
- GNU Make、Ruby 與 `sqlite3`，用於既有 DatabaseCooker

從 repository 根目錄執行：

```sh
make -C Source/Distributions/Takao/DatabaseCooker
xcodebuild -project Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj \
  -scheme "chichi77 KeyKey" -configuration Debug \
  -destination 'platform=iOS Simulator,name=KeyKey iOS 26 iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build

cd Source/Loaders/iOS-Keyboard/KeyKeyEngine
swift test
```

`KeyKey.db` 是建置輸入但不進版控；Xcode Cloud 會由
`Source/Loaders/iOS-Keyboard/ci_scripts/ci_post_clone.sh` 自動 cook。五台受控 Simulator
與完整 A–K 驗證方式見
[iOS Simulator 測試計畫](Source/Loaders/iOS-Keyboard/IOS_SIMULATOR_TEST_PLAN.md)；可先從
repository 根目錄執行可無人值守的宿主基線：

```sh
Source/Loaders/iOS-Keyboard/run-simulator-tests.sh --host-only
```

實機 Debug build 請在 Xcode 選擇 Apple Developer Team 並使用 Automatic Signing；
TestFlight 與 App Store archive 由 Xcode Cloud／App Store Connect 管理。iOS 的 keyboard
extension 無法接收 USB／藍牙鍵盤事件；容器 App 的「實體鍵盤編輯器」只能在 App 前景
接管按鍵，完成後以複製或系統分享面板把文字送往其他 App。詳細架構、限制與簽章需求見
[iOS Keyboard README](Source/Loaders/iOS-Keyboard/README.md)。

## GitHub Actions 封裝

Android 的 debug 封裝、iOS Simulator 與 `Android Play Release` workflow 都從
GitHub Actions 頁面按 **Run workflow** 手動執行。Android Play workflow 使用所選分支
或 tag 的 commit 建置、簽署並上傳 AAB 到 Google Play 內部測試；PR 合併與直接 push
都不觸發，也不設定 `changesNotSentForReview`。正式版推廣由 Play Console 操作。
Android 1.3.2 已於 2026-10-08 正式上線；後續正式發布不需再以封閉測試作為前置步驟。
CI 上傳至內部測試與一般使用者從 Google Play 安裝正式版是不同流程。

所有修改先在工作分支提交，再由維護者親自 review 和 merge PR 回 `master`；agent 不自行合併。
原始碼、建置腳本與 CI 都依 [Code signing policy](CODE_SIGNING_POLICY.md) 納入審查。
macOS、Windows 與 Linux 則在 GitHub
**Publish release** 後自動建置，各自驗證成功後上傳到同一個 Release。Release 的 tag
必須完全符合該平台原始碼版號，可在發布頁面同時建立。目前 Windows 為 `v1.3.2`，
macOS、Linux 仍為 `v1.3.1`；同一 Release 的三平台產物只在各平台同版時成立，不能期待
發布 `v1.3.2` 讓其餘兩平台也成功封裝。只推 tag 或儲存草稿
不會觸發桌面封裝；一般 commit 與尚未合併的 pull request 不會發布桌面資產。`Linux CI` 另保留 PR smoke，
發布前須通過 Ubuntu 24.04 完整測試與 Ubuntu 22.04 相容性驗證。

單一平台失敗時，把修正合併到 `master`，到 Actions 選該平台的 workflow，按
**Run workflow**，將 **Use workflow from** 選為 `master`，並填入
Windows 填 `release_tag=v1.3.2`，macOS／Linux 填 `release_tag=v1.3.1`。建置使用所選分支，
平台版號仍須與 Release 相同；成功後自動補上或
覆寫該平台的資產，其他平台不變。三個 workflow 都接受此欄位，留空則只保留 artifact。
同平台、同 Release 的發布會依序執行。這些 workflow 修改須先合併到預設分支才可使用。

也可以個別使用 CLI（只執行需要補發的平台）：

```sh
gh workflow run package-macos.yml --ref master -f release_tag=v1.3.1
gh workflow run package-windows.yml --ref master -f release_tag=v1.3.2
gh workflow run linux-ci.yml --ref master -f release_tag=v1.3.1
```

**Re-run jobs** 使用原本的 commit，適合暫時性失敗；有程式修正時應使用上述
**Run workflow**，才會建置新的 commit。
建置完成後，以下檔案會以 Actions artifact 保留 7 天：

| Workflow | 產物 | 限制 |
|---|---|---|
| Package macOS | `chichi77-KeyKey-版本-macos-arm64.pkg.zip` | 發布到 Release 前以 Developer ID 簽章並 notarize；僅 artifact 的 run 未簽章 |
| Package Windows | `chichi77-KeyKey-版本-windows-x64.zip`、`windows-x86.zip`、`windows-x64-setup.unsigned.exe`（同前綴） | 全部未簽章；EXE 只供測試，不能送 Store |
| Package Android | `chichi77-KeyKey-版本-android-debug.apk` | debug key 簽署；不同次建置間可能無法直接升級 |
| Android Play Release | 無公開 artifact；直接上傳簽署 AAB | 只在手動 Run workflow 時建置、簽署並上傳到 Google Play internal testing；PR 合併與直接 push 都不觸發，由 Play Console 推廣至正式版；一般使用者不需加入封閉測試 |
| Package iOS Simulator | `chichi77-KeyKey-版本-ios-simulator.zip` | 僅 Apple Silicon iOS Simulator，不能安裝到實機 |
| Linux CI | Ubuntu 22.04／24.04 `.deb`；Ubuntu 24.04 另有面板原始碼與 `SHA256SUMS` | 完整測試通過後，發布 run 只上傳 Ubuntu 24.04 的五個檔案；Ubuntu 22.04 套件僅保留 artifact |

桌面版 artifact 另附同名 `.sha256`；Linux 使用涵蓋四個檔案的 `SHA256SUMS`。
發布前會驗證全部 checksum，再上傳到既有、已發布的 Release，覆寫該平台的同名資產。
每平台另上傳 `chichi77-KeyKey-版本-平台-build-info.json`，記錄實際建置 commit、
tag commit、workflow 連結與檔案雜湊；修正後的補發可能與原 tag commit 不同。
workflow 不建立 Release，也不建立或移動 tag。若上傳中斷，可重新執行補發。

macOS workflow 拆成兩個 job。`build` 永遠會跑、拿不到任何 secret，產出未簽章 pkg；
`publish` 在 Release 發布或手動填入 `release_tag` 時跑，掛 `release` environment，取得 Developer ID 憑證後簽章、
notarize、staple，再發布到 Release。因此**從 Release 下載的 macOS pkg 不需要
`xattr -d com.apple.quarantine`**，Gatekeeper 直接放行；未填 `release_tag` 的手動 run 仍是
未簽章的測試包。

發布 run 會留下兩個 macOS artifact，裡面的檔名相同但內容不同：`build` 的
`keykey-macos-版本-commit` 是未簽章的，`publish` 的 `keykey-macos-signed-版本` 才是已簽章
並 notarize 的，也就是發布到 Release 的那一份。要給別人裝就取 Release 上的資產，不要從
artifact 抓。

`publish` 需要在 repository 的 `release` environment 底下設定 5 個 secret：
`APPLE_DEVELOPER_ID_P12`（含 `Developer ID Application` 與 `Developer ID Installer`
的 `.p12`，base64）、`APPLE_DEVELOPER_ID_P12_PASSWORD`、`APPLE_ID`、
`APPLE_APP_SPECIFIC_PASSWORD`、`APPLE_TEAM_ID`。該 environment 的 deployment rule 必須
只允許 ref type 為 **tag** 的 `v*` 與 ref type 為 **branch** 的 `master`，
讓正式發布與修正後的手動補發都能執行；其他分支不開放。三個平台的發布 job 都使用此 environment。
此規則需 repository 管理員在 **Settings → Environments → release → Deployment
branches and tags** 設定：保留 `v*` tag，新增 `master` branch；只修改 workflow 不會更新此設定。

Android Play workflow 需要 `google-play-release` environment 的上傳金鑰與 Play service
account secret；正式 AAB 由 Google Play 管理及簽署。iOS 實機、TestFlight 與 App Store
上傳由 Xcode Cloud／App Store Connect 處理，不使用 Simulator workflow。其餘測試封裝只用
repository 內的公開詞庫。Windows 正式簽章仍留待後續處理。這是公開 repository，因此
artifact 在 7 天保留期間仍可能被 repository 讀者下載。

<a id="english"></a>

## English

Native Linux support began with version 1.2.8. Version 1.3.1 includes a
Linux-only engine and Fcitx 5 addon. The GTK 3, GTK 4, and Qt 6 X11 matrix is
implemented, and 76 cases that do not restart the desktop Fcitx process pass
in an isolated Ubuntu 24.04 GNOME X11 session. A GNOME Wayland KVM guest also
passes 160/160 native Wayland/XWayland key and pointer combinations. Real gedit
passes four input paths; GNOME Text Editor passes the direct Fcitx Wayland and
XWayland paths, with two GTK Wayland IM paths still failing. These earlier
checks do not replace the versioned release workflow. The guest also passes 16/16
two-field focus phases, with a recorded raw-preedit blur difference between
direct Fcitx and default GTK Wayland paths. Separate editing-field evidence
passed 21 cases before a GNOME Shell crash and the remaining three after
session recovery; symbol-list pointer selection passed all eight modes.
Two live applications preserve independent modes in six direct Fcitx paths
(12/12), while the two default GTK Wayland bridge paths share one IBus input
context and fail mode isolation. All eight modes passed candidate-client
closure and immediate new-client recovery; all eight also passed after a
fresh Fcitx process was started. An explicit GDM logout/login followed by
T01 and pointer T06 also passed 16/16. Firefox Snap and Epiphany passed 15
real browser field/mode cases across native Wayland and XWayland, covering
`<textarea>`, `<input>` and `contenteditable` with DOM input checks and
literal controls. See the
[development plan](LINUX_DEVELOPMENT_PLAN.md) and [test plan](LINUX_TEST_PLAN.md).

### Linux source build

A traditional source build requires CMake 3.22, GNU Make, a C++17 compiler,
`pkg-config`, Python 3, and the Fcitx 5 Core, libcanberra, and SQLite 3 development files. It does not require Ninja, Docker,
Autoconf, or Automake. On Ubuntu, install the dependencies and build with the
default `/usr/local` prefix as follows:

```sh
sudo apt-get install build-essential cmake libcanberra-dev libfcitx5core-dev libsqlite3-dev pkg-config python3
cd Source/Loaders/Linux-IME
./configure
make -j2
make check
make DESTDIR="$PWD/out/source-stage" install
```

The final command is an unprivileged staging install. Use `sudo make install`
for the real system install and `sudo make uninstall` to remove only the files
recorded in that build's install manifest. User settings, other user data, and
unrelated files remain untouched, and installation does not select a default
input method. Use `./configure --prefix=/usr` for a distribution-style layout.
Do not overwrite files owned by the `fcitx5-chichi77-keykey` or
`chichi77-keykey-data` Debian packages; remove those packages first, or
uninstall the source build before returning to package-managed files.

Run `./configure --help` for `--libdir`, `--datadir`, adapter, and test options.
The wrapper also honors `CXX`, `CPPFLAGS`, `CXXFLAGS`, and `LDFLAGS` and
supports an out-of-source invocation. `make clean` preserves the configuration;
`make distclean` removes only the generated wrapper Makefile and its private
build directory. See the
[Linux frontend README](Source/Loaders/Linux-IME/README.md#configure-and-gnu-make-source-build)
for nonstandard Fcitx prefix activation.

Developers with Ninja installed may continue to use the existing CMake preset:

```sh
cd Source/Loaders/Linux-IME
cmake --preset linux-release
cmake --build --preset linux-release
ctest --preset linux-release
```

Rancher Desktop or another Docker-compatible engine can reproduce the Ubuntu
userspace from macOS. Use the persistent native-architecture container for the
normal edit/build/test loop:

```sh
Source/Loaders/Linux-IME/ci/dev.sh up
Source/Loaders/Linux-IME/ci/dev.sh test
Source/Loaders/Linux-IME/ci/dev.sh source
Source/Loaders/Linux-IME/ci/dev.sh e2e T01-X11-GTK3-BOPOMOFO-STANDARD
Source/Loaders/Linux-IME/ci/dev.sh verify
Source/Loaders/Linux-IME/ci/dev.sh package
```

On Apple Silicon, `dev.sh` automatically uses `linux/arm64`. It reuses one
container and keeps incremental build and staging files in Docker named
volumes. `e2e` accepts one case, a comma-separated case list, or `all`; `down`
removes the container but retains the compilation cache. ARM64 packages from
this path are test outputs outside the supported release scope, and `package` does not replace clean
install/upgrade/removal acceptance.

Windows 11 can use the same commands from WSL2 Ubuntu. Keep the repository on
the WSL Linux filesystem, such as `/home/.../KeyKey`, rather than `/mnt/c` or a
Windows checkout that converts files to CRLF. First verify that `docker info`
can reach a Linux container engine from a normal WSL shell. If only a
restricted automation process reports Docker socket `permission denied`, grant
that process access to the local socket; do not use `sudo docker` or make the
socket world-writable. See the Linux frontend README for the full diagnostics
and named-volume ownership note.

The following one-shot commands remain the independent, reproducible checks:

```sh
Source/Loaders/Linux-IME/ci/run-ubuntu-24.04.sh
Source/Loaders/Linux-IME/ci/run-ubuntu-22.04.sh
Source/Loaders/Linux-IME/ci/run-ubuntu-24.04-x11-e2e.sh
Source/Loaders/Linux-IME/ci/run-debian-package.sh ubuntu-24.04
Source/Loaders/Linux-IME/ci/run-debian-package.sh ubuntu-22.04
```

The third one-shot command types physical key events through the staged Fcitx 5 addon
into GTK 3, GTK 4, and Qt 6 editors on Xvfb and runs English-keyboard negative controls. They
default to `linux/amd64`; set `KEYKEY_DOCKER_PLATFORM=linux/arm64` for the ARM64
test build. The Xvfb result is L3 X11 evidence and does not count as GNOME or
native Wayland desktop typing acceptance. See the
[Linux frontend README](Source/Loaders/Linux-IME/README.md) for current scope.

The final two commands create distro-labelled `chichi77-keykey-data` and
`fcitx5-chichi77-keykey` Debian packages with debhelper. Ubuntu 24.04 also runs
the eighty-two non-settings-window X11 cases after install, controlled upgrade, and
reinstall. The native Fcitx settings-window click, persistence, restart, and
typing case—including changing the candidate style from vertical to
horizontal—runs once after reinstall, for eighty-three cases in that final state.
Local outputs from these commands require the release workflow's checks before distribution.

### macOS

#### Requirements and build

Requirements:

- macOS 15 or later
- Xcode
- Homebrew's `openssl@3`
- Ruby, GNU Make, and the `sqlite3` command-line tool for the legacy cooker

```sh
brew install openssl@3
cd Source
(cd Distributions/Takao/DatabaseCooker && make)
xcodebuild -project Takao.xcodeproj -target "Takao (Loader OSX-IMK)" \
  -configuration Release -xcconfig Takao-macOS.xcconfig build
```

The cooker creates `Source/Distributions/Takao/CookedDatabase/KeyKey.db`, which
is bundled into `chichi77 KeyKey.app`. The current configuration is arm64-only;
a universal build requires a separate x86_64 OpenSSL build and an xcconfig
change. The cooker also generates the Smart Phonetic unigram model from
`DataSource/McBopomofo/phrase.occ`, `BPMFMappings.txt`, and the Bopomofo CIN;
the unpublished Yahoo corpus and the historical PhraseTool/CEROD tools are not
required. `DataSource/AISyntheticBigram/corpus-v1.txt`, `corpus-v2.txt`,
`corpus-v3.txt`, typing feedback, and the deduplicated 2,300-article corpus
add a synthetic bigram and backoff layer. Each line is one sentence; whitespace may
mark word boundaries, or the cooker can segment unspaced Chinese text with the
existing unigram scores.

The public `DataSource/chichi77Collection` directory is included in the
repository. The macOS DatabaseCooker always writes its 29 TSV collections into
`KeyKey.db`; no private checkout, symlink, or secret is required. This data was
generated, inferred, and normalized automatically, has not been reviewed item by
item, and is not guaranteed to be accurate or complete. See
[Installer/README.md](Installer/README.md) for macOS packaging, local
installation, signing, and notarization.

### Windows 10 and 11

#### Requirements

- Windows 10 or later (built and launched on Windows 11; Windows 10 needs device testing)
- .NET 10 SDK to build self-contained settings and deployment apps
- Visual Studio 2026 with the **Desktop development with C++** workload;
  Visual Studio 2022-compatible presets are also included
- CMake 3.25 or newer; the Visual Studio copy is sufficient
- Python 3 to verify the pre-generated shared database
- NSIS 3.12, only when building the Store EXE

Windows verifies and copies the canonical shared
`Source/Distributions/Takao/CookedDatabase/KeyKey.db`; it does not cook the model.
It links the system WinSQLite3 library. GNU Make, `awk`,
`sed`, and a separate `sqlite3` program are not required.

#### Build and test x64

Open an **x64 Native Tools Command Prompt or PowerShell** and run from the
repository root:

```powershell
cd Source\Loaders\Windows-TSF
cmake --preset windows-x64
cmake --build --preset windows-x64-release
ctest --test-dir .\out\build\x64-ninja --output-on-failure
cmake --preset windows-x86
cmake --build --preset windows-x86-release
ctest --test-dir .\out\build\x86 -C Release --output-on-failure
```

The outputs are:

```text
out\build\x64-ninja\KeyKeyTsf.dll
out\build\x64-ninja\KeyKeySettings.exe
out\build\x64-ninja\KeyKeySettingsBackend.dll
out\build\x64-ninja\KeyKeyDeployment.exe
out\build\x64-ninja\KeyKeyRegistration.exe
out\build\x64-ninja\Databases\KeyKey.db
```

The shared database includes the public categorized collections from
`DataSource/chichi77Collection`; platform builds do not recook them.

#### Register a development build

Registration is machine-wide and prompts for elevation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-Tip.ps1 `
  -DllPath .\out\build\x64-ninja\KeyKeyTsf.dll
```

Users add the registered TSF in a Traditional Chinese (Taiwan, Hong Kong or
Macao) language's options using Add a keyboard, then select it with `Win+Space`.
The script does not change the language list or default input method.
See the [Windows installation guide](WINDOWS_INSTALL.md). To unregister:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-Tip.ps1 `
  -DllPath .\out\build\x64-ninja\KeyKeyTsf.dll -Unregister
```

#### Package for another Windows PC

After building and testing, run from `Source\Loaders\Windows-TSF`:

```powershell
.\Package-Windows.ps1 -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86
.\Package-Windows.ps1 -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86 -Architecture x86
```

This creates x64 and x86 ZIPs. Use the ZIP matching the Windows 10/11 OS
architecture. On the other PC, extract the complete ZIP and copy the folder
to a local `C:\` path such as `C:\KeyKeyInstaller`, and run `Install.cmd`
there. Do not install directly from a mapped drive, NAS, or UNC path; it may
become inaccessible after UAC elevation and the installer window can close
immediately. Once deployment starts, records are in
`%ProgramFiles%\chichi77 KeyKey\Deployment.log`. It stages the runtime in
`C:\Program Files\chichi77 KeyKey\1.3.2-<fingerprint>`, then registers
both x64 and x86 TSF DLLs on x64 Windows (for all 32-bit applications), or the
x86 DLL on 32-bit Windows, and creates an
entry in Windows Installed apps. First-time users add KeyKey in Windows
Settings before selecting it with `Win+Space`. Upgrades preserve the shared
entry selection and retire the two old Hong Kong/Macao entries. Users of those
entries must add/select the shared entry. Sign out and back in to load the new DLLs.

The home-testing package is unsigned, so Windows may warn about a downloaded
copy.

To build an unsigned local NSIS test installer, run:

```powershell
.\Package-Store-Windows.ps1 -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86 -UnsignedTest
```

The output is `out\store-package\chichi77-KeyKey-1.3.2-windows-x64-setup.unsigned.exe`.
Its Windows product version is `1.3.2`; ZIP and EXE, signed and unsigned, use
`1.3.2-<content fingerprint>`. Repair uses a fresh `1.3.2-<instance-id>` path.
New names do not contain `test`; old labelled directories remain recognizable.

See the [Windows TSF README](Source/Loaders/Windows-TSF/README.md) for detailed
deployment and verification information.

#### Manually sign a Microsoft Store NSIS EXE

Production Store packaging is local and interactive, so the private key is not
stored in GitHub Actions. After installing a CA-issued code-signing certificate
in the Windows certificate store and installing NSIS 3.12, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Package-Store-Windows.ps1 `
  -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86 `
  -CertificateThumbprint 'YOUR_40_CHARACTER_CERTIFICATE_THUMBPRINT' `
  -TimestampUrl 'YOUR_CA_RFC3161_TIMESTAMP_URL'
```

The script signs and verifies all six PE payloads, builds an offline NSIS
installer, then signs and verifies the outer EXE. It writes
`out\store-package\chichi77-KeyKey-1.3.2-windows-x64-setup.exe`. See the Windows
TSF README for all parameters, `/S` silent-install testing, and the versioned
HTTPS URL used by Partner Center.
The signed deployment executable also serves as the uninstaller. The finish
page explains manual keyboard setup and does not launch settings. Upgrades keep
older payloads for running hosts and existing profile icon paths; removal uses
an ownership-checked inventory, retaining personal preferences and learning.

### Android

Requirements: Android Studio, JDK 17 or later, Android SDK 36.1, and Build
Tools 36.0.0.

```powershell
cd Source\Loaders\Android-IME
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug
```

The build copies `bpmf-ext.cin` and `bpmf-punctuations.cin` from the shared
`Source/DataTables` directory and adds the base associated-phrase collection
from `DataSource/McBopomofo` plus all 29 public categorized collections from
`DataSource/chichi77Collection`. The build compiles the CIN and phrase sources into
`.kki` indexes and packages the cooked `KeyKey.db` for the default Smart Phonetic
composition mode. Android reads the indexes at runtime and loads associated-phrase indexes
in the background. The debug APK is written to
`app/build/outputs/apk/debug/app-debug.apk`. See the
[Android IME README](Source/Loaders/Android-IME/README.md) for layout and setup
details.

### iOS

Requirements are macOS, Xcode, an installed iOS Simulator runtime, and the
existing DatabaseCooker dependencies (GNU Make, Ruby, and `sqlite3`). From the
repository root, run:

```sh
make -C Source/Distributions/Takao/DatabaseCooker
xcodebuild -project Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj \
  -scheme "chichi77 KeyKey" -configuration Debug \
  -destination 'platform=iOS Simulator,name=KeyKey iOS 26 iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build

cd Source/Loaders/iOS-Keyboard/KeyKeyEngine
swift test
```

`KeyKey.db` is a generated build input and is not committed. Xcode Cloud cooks
it through `Source/Loaders/iOS-Keyboard/ci_scripts/ci_post_clone.sh`. Run the
unattended host baseline from the repository root with:

```sh
Source/Loaders/iOS-Keyboard/run-simulator-tests.sh --host-only
```

See the [iOS Simulator test plan](Source/Loaders/iOS-Keyboard/IOS_SIMULATOR_TEST_PLAN.md)
for the five-device A–K matrix. Device Debug builds use an Apple Developer Team
and Automatic Signing in Xcode; Xcode Cloud and App Store Connect handle
TestFlight and App Store archives. A third-party keyboard extension cannot
receive USB or Bluetooth keyboard events. The container app's hardware-keyboard
editor handles them only while that app is in the foreground, then copies or
shares the completed text. See the
[iOS Keyboard README](Source/Loaders/iOS-Keyboard/README.md) for details.

### GitHub Actions packaging

Android debug packaging, iOS Simulator packaging, and `Android Play Release` run only
after **Run workflow** is selected in GitHub Actions. The Android Play workflow builds
the selected branch or tag and uploads it to Google Play internal testing. PR merges
and direct pushes do not trigger it, and the workflow does not set
`changesNotSentForReview`. Production promotion is performed in Play Console.
Android 1.3.2 entered production on
2026-10-08; closed testing is no longer a prerequisite for subsequent production
releases or public installation. CI uploads to internal testing; users install
the production release from Google Play. iOS 1.3.2 (build 41) is available on the App Store.

Commit all changes on a working branch; the maintainer reviews and merges the PR.
Agents must not merge PRs. Source, build scripts, and CI are covered by the
[Code signing policy](CODE_SIGNING_POLICY.md). The macOS, Windows, and Linux
workflows start when a GitHub Release is published,
and each independently uploads its verified packages. The tag must match the
platform's source version and can be created on the Release page. Windows is now
`v1.3.2`; macOS and Linux remain at `v1.3.1`. Uploading all three platforms to one
Release applies when their versions match; publishing `v1.3.2` cannot produce
matching macOS/Linux packages from this branch.
Pushing a tag or saving a draft alone does not trigger desktop packaging.
Ordinary commits and unmerged pull requests do not publish desktop assets. Linux keeps PR smoke checks; publishing
requires both the full Ubuntu 24.04 gate and Ubuntu 22.04 compatibility checks.

To recover one failed platform, merge the fix into `master`, select its workflow
in Actions, choose **Run workflow**, set **Use workflow from** to `master`, and
enter `v1.3.2` for Windows or `v1.3.1` for macOS/Linux in `release_tag`.
All three workflows accept this input. They build
the selected revision and replace only that platform's assets; its source
version must still match the Release. Leaving the input blank keeps artifacts
only. Publishing runs for the same platform and Release are serialized.
Merge these workflow changes into the default branch before using them.

For example, run just the command for the platform needing recovery:

```sh
gh workflow run package-macos.yml --ref master -f release_tag=v1.3.1
gh workflow run package-windows.yml --ref master -f release_tag=v1.3.2
gh workflow run linux-ci.yml --ref master -f release_tag=v1.3.1
```

**Re-run jobs** uses the original commit and suits transient failures; use
**Run workflow** to include a new fix. Successful runs retain these Actions
artifacts for seven days:

| Workflow | Output | Limitation |
|---|---|---|
| Package macOS | `chichi77-KeyKey-VERSION-macos-arm64.pkg.zip` | Signed with a Developer ID and notarized before Release upload; artifact-only runs remain unsigned |
| Package Windows | `chichi77-KeyKey-VERSION-windows-x64.zip`, `windows-x86.zip`, `windows-x64-setup.unsigned.exe` (same prefix) | All unsigned; the EXE is test-only and cannot be submitted to the Store |
| Package Android | `chichi77-KeyKey-VERSION-android-debug.apk` | Debug signed; a build from another run may require uninstalling the old APK |
| Android Play Release | No public artifact; uploads the signed AAB directly | Builds, signs, and uploads only after a manual Run workflow; PR merges and direct pushes do not trigger it. Promote the build to production in Play Console; public installation does not require closed testing |
| Package iOS Simulator | `chichi77-KeyKey-VERSION-ios-simulator.zip` | Apple Silicon iOS Simulator only; not installable on a device |
| Linux CI | Ubuntu 22.04 and 24.04 `.deb` packages; Ubuntu 24.04 panel source and `SHA256SUMS` | Publishing runs upload five verified Ubuntu 24.04 assets after both gates pass; Ubuntu 22.04 packages remain Actions artifacts |

Desktop outputs have matching `.sha256` files; Linux uses `SHA256SUMS` for its
four downloadable files. A publishing run verifies all checksums before
replacing that platform's assets in an existing, published Release. Each
platform also uploads `chichi77-KeyKey-VERSION-PLATFORM-build-info.json` with the
actual source commit, tag commit, run URL, and asset hashes. A recovery build
can therefore differ from the original tag. The workflow does not create a
Release or create/move a tag. Retry publishing if an upload is interrupted.

After the AWS variables are configured on the `release` environment, the same
validated files are uploaded to the private S3 origin and served through
CloudFront at `keykey/releases/download/TAG/FILE`. The workflow uses GitHub OIDC rather
than stored AWS access keys. Browsers revalidate downloads, CloudFront caches
them for up to one year, and each upload invalidates only the exact paths that
changed so same-tag recovery builds take effect. Provisioning, least-privilege
IAM, and environment-variable setup are documented in
[`terraform/infra`](terraform/infra/README.md).

The macOS workflow is split in two jobs. `build` always runs and is given no
signing secrets, producing the unsigned package; `publish` runs for a published
Release or a manual run with `release_tag`,
uses the `release` environment, and signs, notarizes, and staples before
publishing to the Release. A macOS package downloaded from a Release therefore
needs no `xattr -d com.apple.quarantine`: Gatekeeper accepts it as it is. The
artifact from a manual run without `release_tag` is still an unsigned test build.

A publishing run leaves two macOS artifacts whose contents differ under the same file
name: `keykey-macos-VERSION-COMMIT` from `build` is unsigned, and
`keykey-macos-signed-VERSION` from `publish` is the signed and notarized one
that also goes to the Release. Take the Release asset when handing the package
to someone else, not an artifact.

`publish` needs five secrets under the repository's `release` environment:
`APPLE_DEVELOPER_ID_P12` (base64 of a `.p12` holding both the Developer ID
Application and Developer ID Installer identities),
`APPLE_DEVELOPER_ID_P12_PASSWORD`, `APPLE_ID`,
`APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`. That environment's
deployment rules must allow only `v*` with ref type **tag** and `master` with
ref type **branch**, enabling both official releases and manual recovery from
the fixed branch. All three platform publishing jobs use this environment.
A repository administrator must configure this under **Settings → Environments
→ release → Deployment branches and tags**: keep the `v*` tag rule and add the
`master` branch rule. Editing the workflow does not update this setting.

The Android Play workflow uses upload-key and Play service-account secrets in
the `google-play-release` environment; Google Play manages the final app
signing. iOS device, TestFlight, and App Store builds are handled by Xcode Cloud
and App Store Connect, not by the Simulator workflow. The other test packages
use only the public dictionaries in this repository. Windows production signing
is still deferred. Because the repository is public, readers may still download
an artifact during its seven-day retention period.

Windows 安裝包反覆測試時，若前一次 EXE 仍開啟，可在 `Package-Store-Windows.ps1`
加上 `-BuildLabel fix-20261001-143000` 產生不同檔名，避免覆寫執行中的檔案。
此參數只改安裝檔名，不改產品版號或 Program Files 下的版本目錄。
