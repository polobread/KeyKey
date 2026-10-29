# 建置、安裝與打包 / Building, installation, and packaging

本文件集中說明琦琦輸入法各平台的建置流程。

Guanyinma 共用 Rust 核心位於 `Source/Guanyinma`，目前提供唯讀 DB、C ABI 與四種輸入法的共用 session，包括好打注音組句與 FE 可設定的 10～20 音節邊界。
其獨立建置／單元及 C consumer 驗證見 [Guanyinma README](Source/Guanyinma/README.md)，
移植範圍見 [實作計畫](docs/GUANYINMA_IMPLEMENTATION_PLAN.md)。完整 Guanyinma 核心 CI 統一由 `guanyinma-core.yml` 負責；平台 workflow 編譯／連結核心後只跑少量 FE 串接冒煙，沿用該平台原有建置與發布流程。iOS 預設建置同時包含 Swift 與 Guanyinma，使用者預設選 Swift；macOS 可用 `Takao-Guanyinma.xcconfig` 建置同一 FE 的雙核心 App，並在一般設定切換，見 [Guanyinma 開發接合](docs/GUANYINMA_MACOS_ADAPTER.md)。

Linux 1.3.7 的 Ubuntu Desktop 24.04 LTS、GNOME Shell 46、Fcitx 5、amd64 安裝流程見
[Ubuntu 安裝與使用指南](LINUX_INSTALL.md)。macOS 正式版為
[1.3.8](https://github.com/polobread/KeyKey/releases/tag/v1.3.8)；Windows、Linux／FreeBSD、iOS 與 Android 正式版維持 1.3.7。
Windows 與 Ubuntu 安裝包由 [1.3.7 Release](https://github.com/polobread/KeyKey/releases/tag/v1.3.7)
提供，iOS 與 Android 1.3.7 已分別在 App Store、Google Play 上架，不需加入測試。
FreeBSD 已完成桌面驗證，透過 ports／pkg 安裝，詳見 [FreeBSD 安裝指南](FREEBSD_INSTALL.md)。
Guanyinma 工作分支的六平台原始碼開發版號統一為 `1.5.0`，正式發布狀態依上列平台資訊；共用好打注音模型維持 `1.3.1`。
Linux／FreeBSD 開發來源只使用 Guanyinma Rust 核心；接合、設定與聚焦驗證見
[Linux Guanyinma 說明](docs/GUANYINMA_LINUX_ADAPTER.md)。X11、GNOME Wayland／XWayland、
FreeBSD 原生與套件安裝各自驗證，不以舊版本的桌面結果代替新核心驗收。

[English](#english)

## Linux 原始碼建置

Ubuntu 24.04 使用者若要從下載、編譯一路完成 Fcitx 啟用與試打，請先看
[Linux `./configure` 編譯安裝與使用指南](LINUX_CONFIGURE_INSTALL.md)。

傳統原始碼建置需要 CMake 3.22、GNU Make、C++17 compiler、`pkg-config`、
Fcitx 5 Core、libcanberra、SQLite 3、json-c、PangoFT2 開發檔、Python 3，
以及 `Source/Guanyinma/rust-toolchain.toml` 鎖定的 Rustup 工具鏈；
不需要 Ninja、Docker、Autoconf 或 Automake。Ubuntu 可先安裝：

```sh
sudo apt-get install build-essential cmake curl libcanberra-dev libfcitx5core-dev libsqlite3-dev libjson-c-dev libpango1.0-dev pkg-config python3 python3-gi gir1.2-gtk-3.0
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

Linux／FreeBSD frontend 現在只使用 Guanyinma；Rust 不是可選後端。可先在 Bash
中 `source ci/prepare-guanyinma.sh` 準備鎖定工具鏈，或自行配置 `CARGO`、`CARGO_HOME`
與 `RUSTUP_HOME`。建置入口不提供核心選擇參數。接合、設定與 Guanyinma 詞庫管理見
[Linux Guanyinma 說明](docs/GUANYINMA_LINUX_ADAPTER.md)。

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
Ubuntu 24.04 amd64 的安裝套件與支援範圍見 [Linux 1.3.7 安裝與使用指南](LINUX_INSTALL.md)；
本節指令產生的本機套件仍需通過發布流程的驗證，才可作為 GitHub Release 安裝檔。

Ubuntu 24.04 的套件建置另產生獨立 GPL-2.0
`gnome-shell-extension-keykey-kimpanel` `.deb`，只支援 GNOME Shell 46，供
GNOME Wayland 候選面板使用。安裝、啟用、停用和同 UUID 的 user-local
extension 處理方式見 [面板說明](Source/Loaders/Linux-IME/gnome-panel/README.md)。
`fcitx5-chichi77-keykey` 另安裝「文字編輯器（琦琦注音）」啟動器與
`keykey-fcitx-app`；這兩者只為個別啟動的 GTK App 選用直接 Fcitx 輸入路徑。

## macOS

建置前先在 repository root 執行 `python3 update/prepare.py fetch macos`，準備
校驗固定版本的 Sparkle SDK。桌面更新未設定正式 key／feed 時維持離線，見
[更新建置與發布說明](update/README.md)。Windows 本機建置同樣需先執行
`python update/prepare.py fetch windows`。
Windows 日常開發依 [開發型態與測試範圍](Source/Loaders/Windows-TSF/README.md#windows-日常開發型態與測試)
只建置及驗證受影響項目；以下完整平台建置流程用於初次準備或發布。

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

此處 `make` 只驗證儲存庫已提供的正式共用
`Source/Distributions/Takao/CookedDatabase/KeyKey.db`；Xcode 驗證後複製同一份
DB 到 `chichi77 KeyKey.app`。平台建置不得自行 cooker、重新建模或累加補償。
模型來源、正式資料更新及固定驗證流程見
[共用詞庫維護流程](docs/KEYKEY_DATABASE_WORKFLOW.md)。

目前 macOS build 僅支援 arm64。若要製作 universal binary，需要另行準備
x86_64 OpenSSL 並調整 `Source/Takao-macOS.xcconfig`。

### 分類關聯詞詞庫

分類來源放在 `DataSource/chichi77Collection`，由共用詞庫維護流程統一建置及
驗證後納入正式 DB；macOS 建置直接使用該成品，不在平台封裝時重新匯入來源。
這些資料包含自動化生成、推論與整理內容，沒有逐筆人工校正，也不保證正確性或完整性。

### 安裝包

安裝包使用 `Installer/build.sh APP_PATH`，由 `pkgbuild`／`productbuild` 產生
`chichi77KeyKey.pkg` 及其 `.pkg.zip`，不是單純壓縮 App。雙核心版本將上面
建置命令的 xcconfig 換成 `Takao-Guanyinma.xcconfig`，再把該 App 明確傳給同一
封裝入口；兩個核心維持在同一個 FE／App 中。

本機建置會對 staged App／helper 做 ad hoc 簽章；Developer ID 簽章與
notarization 屬正式發布步驟。完整建置、本機安裝及簽署流程見
[Installer/README.md](Installer/README.md)。

## Windows 10 與 11

### 需求

- Windows 10 或更新版本（目前開發機在 Windows 11 驗證；Windows 10 待實機驗證）
- Visual Studio 2026，安裝「使用 C++ 的桌面開發」workload；也提供 Visual
  Studio 2022 相容 preset
- CMake 3.25 以上；Visual Studio 內附版本即可
- .NET 10 SDK（設定頁與部署工具皆 self-contained；使用者不需另裝 runtime）
- Python 3（驗證預先產生的共用資料庫）
- Windows 固定使用 Guanyinma，建置需要 Python 3.11 以上及 `Source/Guanyinma/rust-toolchain.toml` 指定的 Rustup 工具鏈；安裝 x64／x86 相應的 `x86_64-pc-windows-msvc`／`i686-pc-windows-msvc` target
- NSIS 3.12（只有建立 Store EXE 時需要）

Windows 建置只驗證並複製正式共用 `Source/Distributions/Takao/CookedDatabase/KeyKey.db`，
不得自行 cooker；Rust 與原生 FE 共用 Cargo.lock 鎖定的 bundled SQLite 與靜態 CRT，避免 x86 WinSQLite 呼叫慣例不同。Windows 不提供原核心建置或選擇參數。接合與局部驗證見 [Windows Guanyinma](docs/GUANYINMA_WINDOWS_ADAPTER.md)。不需要 GNU Make、
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

- 將整套檔案複製到 `C:\Program Files\chichi77 KeyKey\X.Y.Z-內容指紋`
- 驗證後才切換 TSF 註冊，保留仍供舊行程使用的 payload
- 在 Windows「已安裝的應用程式」加入解除安裝項目

請勿直接從網路磁碟、NAS 或 UNC 路徑安裝；UAC 後可能無法存取原路徑，且安裝
視窗可能立即關閉。所有建置（含 GitHub Actions）診斷預設關閉；需至設定的一般頁
勾選「啟用診斷記錄」並套用，固定 3 天後自動停止，沒有天數選項。有效期限內才寫
`%TEMP%\KeyKeyTsf.log` 與 `%ProgramFiles%\chichi77 KeyKey\Deployment.log`。
輸入記錄含備份最多 20 MiB，部署記錄最多 1 MiB；安裝錯誤仍需記錄錯誤碼。

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

產物是 `out\store-package\chichi77-KeyKey-X.Y.Z-windows-x64-setup.unsigned.exe`。
Windows 產品版號 `X.Y.Z` 讀取自 TSF `CMakeLists.txt`；ZIP、未簽 EXE 與正式簽章包一律使用 `X.Y.Z-<內容指紋>`。
修復使用 `X.Y.Z-<新實例 ID>`，新目錄不含 `test`；舊 `test` 目錄仍可辨識供遷移。

Windows frontend 的部署及驗證細節見
[Source/Loaders/Windows-TSF/README.md](Source/Loaders/Windows-TSF/README.md)。

### Certum 本機簽章與發布

Actions 與本機共用 Build-WindowsRelease.ps1 的建置、測試及 unsigned 封裝命令；
正式待簽來源取自成功的官方 CI run。建置不需要先建立 GitHub Release。
本機簽包只需 Python、Windows SDK SignTool、NSIS 3.12、GitHub CLI 與 SimplySign，
Ed25519 另需 OpenSSL 3。從已合併、乾淨且與 CI 相同的 tag checkout 執行：

~~~powershell
& .\Source\Loaders\Windows-TSF\Release-Windows.ps1 -RunId 123456789 -ReleaseTag vX.Y.Z
# EXE 與兩個 ZIP 通過乾淨 VM 驗收後，另行核准全部產物的 build-info SHA-256：
& .\Source\Loaders\Windows-TSF\Release-Windows.ps1 -Action Publish -RunId 123456789 -ReleaseTag vX.Y.Z
~~~

本機產生已簽 x64 EXE、內含已簽 EXE/DLL 的 x64／x86 ZIP、三份校驗檔與 build-info。
輸出在 Git 忽略的 update/out/local-release/RUN_ID-TAG；本機不重新建置，不覆蓋已發布資產，也不自動改 feed。
Windows Ed25519 也在本機使用 keykey-update-private.pem；禁止提交、上傳或顯示內容。
完整步驟、工具選項、金鑰保護與 feed PR 見 [Windows 本機發布指南](docs/WINDOWS_CERTUM_RELEASE.md)。

## Android

Android 同一 FE 內建 Java 與 Guanyinma 雙核心，預設使用 Java。建置需要固定 Rust 工具鏈、完整 JDK（含 JNI headers）、NDK 及 CMake；版本與四個 ABI 對照見 [Android 接合文件](docs/GUANYINMA_ANDROID_ADAPTER.md)。Gradle 只編譯 Rust，平台 workflow 只執行少量 JNI／FE 串接；完整核心測試留在 `guanyinma-core.yml`。

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
- iOS SDK；執行選用宿主／UI 測試時另備 Simulator runtime
- 固定 Rust 工具鏈與 iOS targets，見 [iOS 雙核心接合](docs/GUANYINMA_IOS_ADAPTER.md)
- GNU Make、Ruby 與 `sqlite3`，用於既有共用資料庫驗證入口

從 repository 根目錄執行：

```sh
make -C Source/Distributions/Takao/DatabaseCooker
xcodebuild -project Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj \
  -scheme "chichi77 KeyKey" -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

bash Source/Guanyinma/tools/test-ios-swift-package.sh
```

`KeyKey.db` 是版控內共用建置輸入；Xcode Cloud 的
`Source/Loaders/iOS-Keyboard/ci_scripts/ci_post_clone.sh` 驗證及複製前置條件，不 cooker。
Cloud 主機需預裝 `rustup`；hook 準備固定工具鏈及 iOS targets，不執行核心全套測試。
下列宿主自動化及 [iOS Simulator 測試計畫](docs/IOS_SIMULATOR_TEST_PLAN.md) 屬 FE 的選用驗證，
按接合修改挑選，與核心 CI 分開：

```sh
Source/Loaders/iOS-Keyboard/run-simulator-tests.sh --host-only
```

實機 Debug build 請在 Xcode 選擇 Apple Developer Team 並使用 Automatic Signing；
TestFlight 與 App Store archive 由 Xcode Cloud／App Store Connect 管理。iOS 的 keyboard
extension 無法接收 USB／藍牙鍵盤事件；容器 App 的「實體鍵盤編輯器」只能在 App 前景
接管按鍵，完成後以複製或系統分享面板把文字送往其他 App。詳細架構、限制與簽章需求見
[iOS Keyboard README](Source/Loaders/iOS-Keyboard/README.md)。

## GitHub Actions 封裝

PR／push 的平台建置排除純文件、README、授權說明與更新公告；程式、設定及詞庫沿用
各平台與共用模組目錄，最多三層目錄分組，不逐檔列清單。`update/stable/` 與 `update/beta/` 公告保留 feed 驗證與同步，
不觸發原生建置。手動及正式 Release 的入口維持原有流程。

Android 的 debug 封裝、iOS Simulator 與 `Android Play Release` workflow 都從
GitHub Actions 頁面按 **Run workflow** 手動執行。Android Play workflow 使用所選分支
或 tag 的 commit 建置、簽署並上傳 AAB 到 Google Play 內部測試；PR 合併與直接 push
都不觸發，也不設定 `changesNotSentForReview`。正式版推廣由 Play Console 操作。
Android 1.3.7 已在 Google Play 正式上架；後續正式發布不需再以封閉測試作為前置步驟。
CI 上傳至內部測試與一般使用者從 Google Play 安裝正式版是不同流程。

所有修改先在工作分支提交，再由維護者親自 review 和 merge PR 回 `master`；agent 不自行合併。
原始碼、建置腳本與 CI 都依 [Code signing policy](CODE_SIGNING_POLICY.md) 納入審查。
macOS 與 Linux 在 GitHub **Publish release** 後自動建置並驗證上傳；
Windows 由 CI 呼叫共用 PowerShell 建置、測試及產生 unsigned artifact，本機只簽章、重包及人工核准上傳。Release 的 tag
必須符合該 tag 的平台原始碼版號，可在發布頁面同時建立；同一 Release 的三平台產物只在各平台同版時成立。
測試頻道使用通用 `vX.Y.Z-betaN` 格式，X.Y.Z 對應平台產品版號，N 為不含前導零的正整數；
必須標記 Pre-release 且只從原 tag commit 建置，不改 Latest。產品來源修正後應建立新的測試 tag，不移動既有 tag。
Linux 手動 beta 重跑可選 `master` 上的 workflow 並填 `release_tag`；兩個 Ubuntu job
都固定 checkout 該 beta tag，發布仍核對原 tag commit、產品版號及套件校驗，避免混入後續來源修改。
macOS 從四份產品 plist 讀取並核對版號，不從 README 讀取版號。只推 tag 或儲存草稿
不會觸發桌面封裝；一般 commit 與尚未合併的 pull request 不會發布桌面資產。`Linux CI` 另保留 PR smoke，
發布前須通過 Ubuntu 24.04 完整測試與 Ubuntu 22.04 相容性驗證。

正式版單一平台失敗時，把修正合併到 `master`，到 Actions 選該平台的 workflow，按
**Run workflow**，macOS／Linux 將 **Use workflow from** 選為 `master`，
並依平台填入已發布的 tag，例如 macOS 的 `release_tag=v1.3.8`、Linux 的 `release_tag=v1.3.7`。Windows 依本機發布指南從原 tag
重試；來源修改需新版本／tag，不接受不同來源的同版本補發。macOS／Linux 建置使用所選分支，
平台版號仍須與 Release 相同；成功後自動補上或
覆寫該平台的資產，其他平台不變。macOS／Linux workflow 接受此欄位，留空則只保留 artifact。
同平台、同 Release 的發布會依序執行。這些 workflow 修改須先合併到預設分支才可使用。

也可以個別使用 CLI（只執行需要補發的平台）：

```sh
gh workflow run package-macos.yml --ref master -f release_tag=v1.3.8
gh workflow run package-windows.yml --ref master # Build/test unsigned inputs; sign locally
gh workflow run linux-ci.yml --ref master -f release_tag=v1.3.7
```

**Re-run jobs** 使用原本的 commit，適合暫時性失敗；有程式修正時應使用上述
**Run workflow**，才會建置新的 commit。
其他平台建置完成後，以下檔案以 Actions artifact 保留 7 天；Windows 待簽 artifact 保留 30 天，不直接發布：

| Workflow | 產物 | 限制 |
|---|---|---|
| Package macOS | `chichi77-KeyKey-版本-macos-arm64.pkg.zip` | 發布到 Release 前以 Developer ID 簽章並 notarize；僅 artifact 的 run 未簽章 |
| Windows Build and Unsigned Inputs | 待簽 EXE／DLL、unsigned 測試包及來源／測試／雜湊紀錄 | 共用 PowerShell 建置測試；本機驗證 artifact 後簽章與重包，見 [發布指南](docs/WINDOWS_CERTUM_RELEASE.md) |
| Package Android | `chichi77-KeyKey-版本-android-debug.apk` | debug key 簽署；不同次建置間可能無法直接升級 |
| Android Play Release | 無公開 artifact；直接上傳簽署 AAB | 只在手動 Run workflow 時建置、簽署並上傳到 Google Play internal testing；PR 合併與直接 push 都不觸發，由 Play Console 推廣至正式版；一般使用者不需加入封閉測試 |
| Package iOS Simulator | `chichi77-KeyKey-版本-ios-simulator.zip` | 僅 Apple Silicon iOS Simulator，不能安裝到實機 |
| Linux CI | Ubuntu 22.04／24.04 `.deb`；Ubuntu 24.04 另有面板原始碼與 `SHA256SUMS` | 完整測試通過後，發布 run 只上傳 Ubuntu 24.04 的五個檔案；Ubuntu 22.04 套件僅保留 artifact |

Windows 保存 CI／artifact 來源、逐項測試狀態、輸入及已簽產物雜湊，EXE 與兩個 ZIP 各有 `.sha256`。
其他桌面版 artifact 另附同名 `.sha256`；Linux 使用涵蓋四個檔案的 `SHA256SUMS`。
Windows 發布不覆寫資產；以下同版補發／覆寫說明只適用其他平台。
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
repository 內的公開詞庫。Windows 正式發布沿用 Certum 本機簽章流程。這是公開 repository，因此
artifact 在 7 天保留期間仍可能被 repository 讀者下載。

<a id="english"></a>

## English

Linux and FreeBSD development sources use Guanyinma as the only input core.
See the [Linux adapter guide](docs/GUANYINMA_LINUX_ADAPTER.md) for settings,
user data, and focused integration checks. Source, staged addon, installed
packages, X11, GNOME Wayland/XWayland, and native FreeBSD acceptance are separate
layers; results from an earlier core do not establish current acceptance.

### Linux source build

A traditional source build requires CMake 3.22, GNU Make, a C++17 compiler,
`pkg-config`, Python 3, the pinned Rustup toolchain, and Fcitx 5 Core, libcanberra,
SQLite 3, json-c and PangoFT2 development files. It does not require Ninja, Docker,
Autoconf, or Automake. On Ubuntu, install the dependencies and build with the
default `/usr/local` prefix as follows:

```sh
sudo apt-get install build-essential cmake curl libcanberra-dev libfcitx5core-dev libsqlite3-dev libjson-c-dev libpango1.0-dev pkg-config python3 python3-gi gir1.2-gtk-3.0
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

Linux/FreeBSD now uses Guanyinma as its only input core. Every build requires
the pinned Rustup toolchain, `libjson-c-dev`, and `libpango1.0-dev`. In Bash,
`source ci/prepare-guanyinma.sh` prepares the pinned toolchain; prepared builds may
set `CARGO`, `CARGO_HOME`, and `RUSTUP_HOME` explicitly. Build entry points do not
provide core-selection options. See the [Linux adapter guide](docs/GUANYINMA_LINUX_ADAPTER.md).

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

Prepare the checksum-pinned Sparkle SDK from the repository root with
`python3 update/prepare.py fetch macos` before invoking Xcode. Windows builds
similarly require `python update/prepare.py fetch windows`. See
[desktop update setup](update/README.md); SDK preparation does not enable
network update checks in an unconfigured application.

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
`%ProgramFiles%\chichi77 KeyKey\Deployment.log` only during an active diagnostic
session. Diagnostics default to off, including GitHub Actions builds. Enable the
single checkbox in Settings to record for three days; it then stops automatically.
TSF logs retain at most 20 MiB including the backup; deployment logs at most 1 MiB.
It stages the runtime in
`C:\Program Files\chichi77 KeyKey\X.Y.Z-<fingerprint>`, then registers
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

The output is `out\store-package\chichi77-KeyKey-X.Y.Z-windows-x64-setup.unsigned.exe`.
Its Windows product version `X.Y.Z` comes from the TSF `CMakeLists.txt`; ZIP and EXE, signed and unsigned, use
`X.Y.Z-<content fingerprint>`. Repair uses a fresh `X.Y.Z-<instance-id>` path.
New names do not contain `test`; old labelled directories remain recognizable.

See the [Windows TSF README](Source/Loaders/Windows-TSF/README.md) for detailed
deployment and verification information.

#### Manually sign a Microsoft Store NSIS EXE

The shared Build-WindowsRelease.ps1 builds/tests and validates unsigned packages
in Actions or locally. Official CI runs retain allowlisted signing inputs.
Release-Windows.ps1 verifies a successful run and matching reviewed tag, then
signs and repackages locally without compiling or rerunning tests.
Both x64/x86 ZIPs contain signed executables. After clean-VM acceptance,
the separate Publish action requires approval of the build-info SHA-256 covering
the EXE, both ZIPs and their checksums. Windows Ed25519 preparation is local,
using keykey-update-private.pem; never commit, upload or display that key.
Publication uploads immutable GitHub assets and dispatches the protected OIDC
mirror workflow. See the [complete release guide](docs/WINDOWS_CERTUM_RELEASE.md).

## Android

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

Requirements are macOS, Xcode with the iOS SDK, the pinned Rust toolchain and
iOS targets described in the [iOS adapter guide](docs/GUANYINMA_IOS_ADAPTER.md),
and the existing shared-database verification tools. A simulator runtime is
needed only for optional host/UI execution. From the repository root, run:

```sh
make -C Source/Distributions/Takao/DatabaseCooker
xcodebuild -project Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj \
  -scheme "chichi77 KeyKey" -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

bash Source/Guanyinma/tools/test-ios-swift-package.sh
```

`KeyKey.db` is the committed shared build input. Xcode Cloud verifies it through
`Source/Loaders/iOS-Keyboard/ci_scripts/ci_post_clone.sh` without cooking it.
Cloud hosts must already provide `rustup`; the hook prepares the pinned toolchain
and targets. Optional frontend host automation remains separate from core CI:

```sh
Source/Loaders/iOS-Keyboard/run-simulator-tests.sh --host-only
```

See the [iOS Simulator test plan](docs/IOS_SIMULATOR_TEST_PLAN.md)
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
Android 1.3.7 is available on Google Play. Closed testing is no longer a prerequisite for subsequent production
releases or public installation. CI uploads to internal testing; users install
the production release from Google Play. iOS 1.3.7 is available on the App Store.

Commit all changes on a working branch; the maintainer reviews and merges the PR.
Agents must not merge PRs. Source, build scripts, and CI are covered by the
[Code signing policy](CODE_SIGNING_POLICY.md). The macOS and Linux workflows
start when a GitHub Release is published and upload verified packages independently.
Windows runs its full release build, signing, EXE/ZIP packaging and approved publication
locally; its CI workflow only checks. The tag must match the
platform's source version at that tag and can be created on the Release page.
The official macOS release is `1.3.8`; Windows, Linux/FreeBSD, iOS, and Android
remain at `1.3.7`. Current development sources on the Guanyinma branch use `1.5.0` across all six platforms.
The test channel uses the generic `vX.Y.Z-betaN` format: X.Y.Z matches the product
version and N is a positive integer without leading zeros.
Betas require Pre-release and the exact tag commit; Latest is unchanged. Fixes
require a new beta tag, not recovery builds or moving an existing tag.
Uploading all three platforms to one Release applies when their versions match.
macOS packaging reads and checks the four
product plists independently of the Linux version at the end of the README title.
Pushing a tag or saving a draft alone does not trigger desktop packaging.
Ordinary commits and unmerged pull requests do not publish desktop assets. Linux keeps PR smoke checks; publishing
requires both the full Ubuntu 24.04 gate and Ubuntu 22.04 compatibility checks.

To recover one failed stable platform, merge the fix into `master`, select its workflow
in Actions, choose **Run workflow**, set **Use workflow from** to `master`, and
enter the published platform tag in `release_tag`, such as `v1.3.8` for macOS
or `v1.3.7` for Linux; the corresponding Release must already be published.
Windows retries use the local release guide and the exact reviewed tag; source
fixes require a new version/tag. Only the macOS/Linux workflows accept this input. They build
the selected revision and replace only that platform's assets; its source
version must still match the Release. Leaving the input blank keeps artifacts
only. Publishing runs for the same platform and Release are serialized.
Merge these workflow changes into the default branch before using them.

For example, run just the command for the platform needing recovery:

```sh
gh workflow run package-macos.yml --ref master -f release_tag=v1.3.8
gh workflow run package-windows.yml --ref master # Build/test unsigned inputs; sign locally
gh workflow run linux-ci.yml --ref master -f release_tag=v1.3.7
```

**Re-run jobs** uses the original commit and suits transient failures; use
**Run workflow** to include a new fix. Successful runs retain these Actions
artifacts for seven days; Windows unsigned inputs are retained for 30 days and signed locally:

| Workflow | Output | Limitation |
|---|---|---|
| Package macOS | `chichi77-KeyKey-VERSION-macos-arm64.pkg.zip` | Signed with a Developer ID and notarized before Release upload; artifact-only runs remain unsigned |
| Windows Build and Unsigned Inputs | Unsigned payload, test packages, source/test/hash records | Shared PowerShell builds/tests; local Windows verifies CI inputs, signs and repackages; see [release guide](docs/WINDOWS_CERTUM_RELEASE.md). |
| Package Android | `chichi77-KeyKey-VERSION-android-debug.apk` | Debug signed; a build from another run may require uninstalling the old APK |
| Android Play Release | No public artifact; uploads the signed AAB directly | Builds, signs, and uploads only after a manual Run workflow; PR merges and direct pushes do not trigger it. Promote the build to production in Play Console; public installation does not require closed testing |
| Package iOS Simulator | `chichi77-KeyKey-VERSION-ios-simulator.zip` | Apple Silicon iOS Simulator only; not installable on a device |
| Linux CI | Ubuntu 22.04 and 24.04 `.deb` packages; Ubuntu 24.04 panel source and `SHA256SUMS` | Publishing runs upload five verified Ubuntu 24.04 assets after both gates pass; Ubuntu 22.04 packages remain Actions artifacts |

Windows build-info retains CI/artifact provenance, test/skip results and file hashes. Signed EXE and both ZIPs
have checksums and are never overwritten on publication.
The recovery/overwrite notes below apply only to other platforms. Other desktop outputs have `.sha256` files; Linux uses `SHA256SUMS` for its
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
