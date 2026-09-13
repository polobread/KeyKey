# 建置、安裝與打包 / Building, installation, and packaging

本文件集中說明琦琦輸入法各平台的建置流程。

Linux 是 1.2.8 起的原生支援目標，目前已有可建置的 Linux-only 引擎與 Fcitx 5
外掛與 local X11/GTK 3 真實逐鍵測試，但尚未完成全部功能、GNOME／Wayland 桌面
驗收或正式套件。開發／套件規格見
[LINUX_DEVELOPMENT_PLAN.md](LINUX_DEVELOPMENT_PLAN.md)，實際打字與 GitHub Actions
驗收見 [LINUX_TEST_PLAN.md](LINUX_TEST_PLAN.md)。

[English](#english)

## Linux（開發中）

傳統原始碼建置需要 CMake 3.22、GNU Make、C++17 compiler 與 Fcitx 5 Core 開發檔；
不需要 Ninja、Docker、Autoconf 或 Automake。Ubuntu 可先安裝：

```sh
sudo apt-get install build-essential cmake libfcitx5core-dev
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
Source/Loaders/Linux-IME/ci/dev.sh e2e T01-X11-GTK3-BOPOMOFO-STANDARD
Source/Loaders/Linux-IME/ci/dev.sh verify
Source/Loaders/Linux-IME/ci/dev.sh package
```

`dev.sh` 在 Apple Silicon 自動使用 `linux/arm64`，保留同一個 container，並把
incremental build／stage 放在 Docker named volumes；`down` 只移除 container，保留
編譯快取。`e2e` 可指定一個 case、逗號分隔的 cases 或 `all`。這條快速路徑產生的
ARM64 package 是開發 preview，不能取代 x86_64 release gate；`package` 也不取代乾淨
runtime container 的安裝／升級／移除驗證。

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
API 邊界，第三個另跑已安裝 addon → Fcitx 5 → GTK 3 的 X11 真實逐鍵輸入：五種
注音配置及各自的英文負控制，並驗證注音設定 schema；目前也保留已排除的倉頡／簡易
垂直切片回歸，但不代表 Linux 1.2.8 支援。這些 one-shot 指令預設建立
`linux/amd64` 產物；ARM64 preview 可在指令前設定
`KEYKEY_DOCKER_PLATFORM=linux/arm64`。Xvfb E2E 是 L3 X11 證據，不等於 GNOME／
native Wayland 的實際桌面打字測試。詳細狀態與輸出路徑見
[Linux frontend README](Source/Loaders/Linux-IME/README.md)。

後兩個指令用 debhelper 產生依發行版命名的 `chichi77-keykey-data` 與
`fcitx5-chichi77-keykey` 套件。24.04 會在安裝、受控升級及移除後重裝三個狀態，
各跑一次二十一個純鍵盤 X11 真實打字案例，並只在重裝後多跑一次 Fcitx 原生設定視窗
點選、保存、重啟及真實打字案例；22.04 則跑較省時的套件安裝／移除 smoke。
這些仍是開發產物，不能在完整 release gates 完成前當成正式 Linux 版發布。

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
`chichi77 KeyKey.app`。

目前 macOS build 僅支援 arm64。若要製作 universal binary，需要另行準備
x86_64 OpenSSL 並調整 `Source/Takao-macOS.xcconfig`。

### 分類關聯詞詞庫

`DataSource/chichi77Collection` 已納入公開 repository，macOS DatabaseCooker 會固定
把其中 29 份 TSV 寫入 `KeyKey.db`，不需私人 checkout、symlink 或 secret。這些資料
由自動化方式生成、推論與整理，沒有逐筆人工校正，也不保證正確性或完整性。

### 安裝包

安裝包的建置、本機安裝、簽署及 notarization 說明見
[Installer/README.md](Installer/README.md)。

## Windows 11

### 需求

- Windows 11
- Visual Studio 2026，安裝「使用 C++ 的桌面開發」workload；也提供 Visual
  Studio 2022 相容 preset
- CMake 3.25 以上；Visual Studio 內附版本即可
- NSIS 3.12（只有建立 Store EXE 時需要）

Windows 使用獨立的原生 C++ DatabaseCooker，不需要 Ruby、GNU Make、`awk`、
`sed` 或外部 `sqlite3` 程式，也不會修改 macOS 的既有 cooker。

### 建置及測試 x64

開啟 Visual Studio 的 **x64 Native Tools Command Prompt 或 PowerShell**，從
repository 根目錄執行：

```powershell
cd Source\Loaders\Windows-TSF
cmake --preset windows-x64
cmake --build --preset windows-x64-release
ctest --test-dir .\out\build\x64-ninja --output-on-failure
cmake --preset windows-x86
cmake --build --preset windows-x86-release --target KeyKeyTsf
```

輸出檔案為：

```text
out\build\x64-ninja\KeyKeyTsf.dll
out\build\x64-ninja\KeyKeySettings.exe
out\build\x64-ninja\Databases\KeyKey.db
```

Windows DatabaseCooker 會固定納入公開 repository 內
`DataSource/chichi77Collection` 的 29 份分類詞庫，不需另設 CMake 路徑。

### 本機註冊

開發階段可直接註冊 build 目錄中的 DLL。註冊範圍是整台電腦，會顯示 UAC：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-Tip.ps1 `
  -DllPath .\out\build\x64-ninja\KeyKeyTsf.dll
```

註冊腳本也會將「琦琦輸入法」加入目前使用者的繁體中文輸入法清單。若沒有立即
出現在 `Win+Space`，請登出再登入。解除註冊：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-Tip.ps1 `
  -DllPath .\out\build\x64-ninja\KeyKeyTsf.dll -Unregister
```

### 打包給另一台 Windows 電腦

完成建置及測試後，在 `Source\Loaders\Windows-TSF` 執行：

```powershell
.\Package-Windows.ps1 -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86
```

會產生 `out\package\chichi77-KeyKey-1.2.8-windows-x64.zip`。在另一台 x64 Windows
11 電腦完整解壓縮後，請把整個資料夾複製到本機 `C:\`（例如
`C:\KeyKeyInstaller`），再執行 `Install.cmd` 並允許 UAC。安裝程式會：

- 將檔案複製到 `C:\Program Files\chichi77 KeyKey`
- 從固定路徑註冊 TSF
- 在 Windows「已安裝的應用程式」加入解除安裝項目

請勿直接從網路磁碟、NAS 或 UNC 路徑安裝；UAC 後可能無法存取原路徑，且安裝
視窗可能立即關閉。失敗記錄位於 `%TEMP%\chichi77-keykey-install.log`。

安裝腳本會自動加入目前使用者的 `Win+Space` 輸入法清單；若沒有立即出現，請登出
再登入。這是未簽署的家用測試套件，因此從網路下載時 Windows 可能顯示安全警告。

Windows x64 套件會同時安裝 x64 與 x86 TSF DLL，因此也可在 32-bit Office 中輸入。
ARM64 preset 與打包選項目前僅保留供未來移植，尚未驗證，也不在目前發佈套件內。
DLL 架構必須和載入它的應用程式架構相同。

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

腳本會在暫存副本依序簽署並驗證 x64 DLL、x86 DLL、設定 EXE，以 NSIS 建立離線安裝
程式後再簽署並驗證外層 EXE；不會修改原建置輸出，也不會儲存 PFX 密碼。結果位於
`out\store-package\chichi77-KeyKey-1.2.8-windows-x64-setup.exe`。完整參數、`/S`
靜默安裝測試及 Partner Center 的版本化 HTTPS URL 說明見 Windows TSF README。
互動式完成頁可選擇開啟琦琦設定或 Windows 語言設定；只有舊檔被占用而必須延後清除
時才會顯示重新啟動選項，且預設為稍後重新啟動。

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
加入 `DataSource/chichi77Collection` 的 29 個公開分類詞庫。Android 仍直接把這些
TSV 複製為 generated assets，不另轉為專用二進位格式。
Debug APK 位於
`app/build/outputs/apk/debug/app-debug.apk`。安裝後開啟「琦琦注音」，依畫面按鈕
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

Android 的 debug 封裝、Google Play 正式上傳與 iOS Simulator workflow 都從 GitHub
Actions 頁面按 **Run workflow** 手動執行。macOS 與 Windows 在推送完全符合專案版號的 tag
（例如 `v1.2.8`）時會自動發布到該 Release；兩者也都可以手動執行，Windows 額外接受
`release_tag` 輸入，留空時只保留測試 artifact。一般 commit、pull request 與不符合版號的
tag 不會發布 Release。建置完成後，以下檔案會以 Actions artifact 保留 7 天：

| Workflow | 產物 | 限制 |
|---|---|---|
| Package macOS | `chichi77-KeyKey-版本-macos-arm64.pkg.zip` | 手動 run 未簽章；tag run 以 Developer ID 簽章並 notarize |
| Package Windows | `chichi77-KeyKey-版本-windows-x64.zip`、`chichi77-KeyKey-版本-windows-x64-setup.unsigned.exe` | 兩者皆未簽章；EXE 只供測試，不能送 Store |
| Package Android | `chichi77-KeyKey-版本-android-debug.apk` | debug key 簽署；不同次建置間可能無法直接升級 |
| Android Play Release | 無公開 artifact；直接上傳簽署 AAB | 手動執行並上傳到 Google Play internal testing，後續在 Play Console 推廣到封閉測試 |
| Package iOS Simulator | `chichi77-KeyKey-版本-ios-simulator.zip` | 僅 Apple Silicon iOS Simulator，不能安裝到實機 |

artifact 另附同名 `.sha256`。發布 run 會把產物與 checksum 上傳到既有 Release；若 Release
尚不存在才建立。workflow 不會建立 tag，也不會覆寫同名資產。

macOS workflow 拆成兩個 job。`build` 永遠會跑、拿不到任何 secret，產出未簽章 pkg；
`publish` 只在 tag 觸發時跑，掛 `release` environment，取得 Developer ID 憑證後簽章、
notarize、staple，再發布到 Release。因此**從 Release 下載的 macOS pkg 不需要
`xattr -d com.apple.quarantine`**，Gatekeeper 直接放行；手動 run 留下的 artifact 仍是
未簽章的測試包。

tag run 會留下兩個 macOS artifact，裡面的檔名相同但內容不同：`build` 的
`keykey-macos-版本-commit` 是未簽章的，`publish` 的 `keykey-macos-signed-版本` 才是已簽章
並 notarize 的，也就是發布到 Release 的那一份。要給別人裝就取 Release 上的資產，不要從
artifact 抓。

`publish` 需要在 repository 的 `release` environment 底下設定 5 個 secret：
`APPLE_DEVELOPER_ID_P12`（含 `Developer ID Application` 與 `Developer ID Installer`
的 `.p12`，base64）、`APPLE_DEVELOPER_ID_P12_PASSWORD`、`APPLE_ID`、
`APPLE_APP_SPECIFIC_PASSWORD`、`APPLE_TEAM_ID`。該 environment 的 deployment rule 必須
限定 ref type 為 **tag** 的 `v*`，其他 workflow 與手動 branch run 才拿不到私鑰。

Android Play workflow 需要 `google-play-release` environment 的上傳金鑰與 Play service
account secret；正式 AAB 由 Google Play 管理及簽署。iOS 實機、TestFlight 與 App Store
上傳由 Xcode Cloud／App Store Connect 處理，不使用 Simulator workflow。其餘測試封裝只用
repository 內的公開詞庫。Windows 正式簽章仍留待後續處理。這是公開 repository，因此
artifact 在 7 天保留期間仍可能被 repository 讀者下載。

<a id="english"></a>

## English

Native Linux development starts with version 1.2.8. A buildable Linux-only
engine and Fcitx 5 addon skeleton exist, but full features, real desktop typing
acceptance, and release packages are not complete. See the
[development plan](LINUX_DEVELOPMENT_PLAN.md) and [test plan](LINUX_TEST_PLAN.md).

### Linux (in development)

A traditional source build requires CMake 3.22, GNU Make, a C++17 compiler,
and the Fcitx 5 Core development files. It does not require Ninja, Docker,
Autoconf, or Automake. On Ubuntu, install the dependencies and build with the
default `/usr/local` prefix as follows:

```sh
sudo apt-get install build-essential cmake libfcitx5core-dev
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
this path are development previews, and `package` does not replace clean
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
into a GTK 3 entry on Xvfb and runs an English-keyboard negative control. They
default to `linux/amd64`; set `KEYKEY_DOCKER_PLATFORM=linux/arm64` for the ARM64
preview build. The Xvfb result is L3 X11 evidence and does not count as GNOME or
native Wayland desktop typing acceptance. See the
[Linux frontend README](Source/Loaders/Linux-IME/README.md) for current scope.

The final two commands create distro-labelled `chichi77-keykey-data` and
`fcitx5-chichi77-keykey` Debian packages with debhelper. Ubuntu 24.04 also runs
the twenty-one keyboard-only X11 cases after install, controlled upgrade, and
reinstall. The native Fcitx settings-window click, persistence, restart, and
typing case runs once after reinstall. These are development artifacts until
the remaining release gates are complete.

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
change.

The public `DataSource/chichi77Collection` directory is included in the
repository. The macOS DatabaseCooker always writes its 29 TSV collections into
`KeyKey.db`; no private checkout, symlink, or secret is required. This data was
generated, inferred, and normalized automatically, has not been reviewed item by
item, and is not guaranteed to be accurate or complete. See
[Installer/README.md](Installer/README.md) for macOS packaging, local
installation, signing, and notarization.

### Windows 11

#### Requirements

- Windows 11
- Visual Studio 2026 with the **Desktop development with C++** workload;
  Visual Studio 2022-compatible presets are also included
- CMake 3.25 or newer; the Visual Studio copy is sufficient
- NSIS 3.12, only when building the Store EXE

Windows uses its own native C++ database cooker. Ruby, GNU Make, `awk`, `sed`,
and a separate `sqlite3` program are not required.

#### Build and test x64

Open an **x64 Native Tools Command Prompt or PowerShell** and run from the
repository root:

```powershell
cd Source\Loaders\Windows-TSF
cmake --preset windows-x64
cmake --build --preset windows-x64-release
ctest --test-dir .\out\build\x64-ninja --output-on-failure
cmake --preset windows-x86
cmake --build --preset windows-x86-release --target KeyKeyTsf
```

The outputs are:

```text
out\build\x64-ninja\KeyKeyTsf.dll
out\build\x64-ninja\KeyKeySettings.exe
out\build\x64-ninja\Databases\KeyKey.db
```

The Windows DatabaseCooker always includes the 29 public categorized collections
from `DataSource/chichi77Collection`; no separate CMake path is required.

#### Register a development build

Registration is machine-wide and prompts for elevation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-Tip.ps1 `
  -DllPath .\out\build\x64-ninja\KeyKeyTsf.dll
```

The script also adds **琦琦輸入法** to the current user's Traditional Chinese
input methods. Sign out and back in if it does not immediately appear in
`Win+Space`. To unregister:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-Tip.ps1 `
  -DllPath .\out\build\x64-ninja\KeyKeyTsf.dll -Unregister
```

#### Package for another Windows PC

After building and testing, run from `Source\Loaders\Windows-TSF`:

```powershell
.\Package-Windows.ps1 -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86
```

This creates `out\package\chichi77-KeyKey-1.2.8-windows-x64.zip`. On the other
x64 Windows 11 PC, extract the complete ZIP, copy the entire extracted folder
to a local `C:\` path such as `C:\KeyKeyInstaller`, and run `Install.cmd`
there. Do not install directly from a mapped drive, NAS, or UNC path; it may
become inaccessible after UAC elevation and the installer window can close
immediately. Failures are logged to `%TEMP%\chichi77-keykey-install.log`. It copies the runtime to
`C:\Program Files\chichi77 KeyKey`, registers
both x64 and x86 TSF DLLs (including support for 32-bit Office), adds it to the
current user's `Win+Space` list, and creates an entry in Windows Installed apps.
Sign out and back in if it does not appear immediately.

The home-testing package is unsigned, so Windows may warn about a downloaded
copy. The ARM64 preset and packaging option are retained for future bring-up,
but ARM64 is not currently verified or published.

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

The script signs and verifies the three PE payloads, builds an offline NSIS
installer, then signs and verifies the outer EXE. It writes
`out\store-package\chichi77-KeyKey-1.2.8-windows-x64-setup.exe`. See the Windows
TSF README for all parameters, `/S` silent-install testing, and the versioned
HTTPS URL used by Partner Center.
The interactive finish page can open KeyKey settings or Windows Language &
region settings. It offers a restart only when a locked old file must be removed
later, and defaults to restarting later.

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
`DataSource/chichi77Collection`. Android copies the TSV files as generated assets
and does not convert them to a custom binary format. The debug APK is written to
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

The Android debug packaging, Google Play release, and iOS Simulator workflows
run only after **Run workflow** is selected on the GitHub Actions page. The
macOS and Windows workflows publish to a Release when a tag that exactly
matches the repository version, such as `v1.2.8`, is pushed. Both can also be
run manually; the Windows workflow additionally takes a `release_tag` input,
and leaving it blank produces a test artifact only. Commits, pull requests, and
mismatched tags do not publish a Release. Successful runs retain these Actions
artifacts for seven days:

| Workflow | Output | Limitation |
|---|---|---|
| Package macOS | `chichi77-KeyKey-VERSION-macos-arm64.pkg.zip` | Unsigned on a manual run; signed with a Developer ID and notarized on a tag run |
| Package Windows | `chichi77-KeyKey-VERSION-windows-x64.zip`, `chichi77-KeyKey-VERSION-windows-x64-setup.unsigned.exe` | Both are unsigned; the EXE is test-only and cannot be submitted to the Store |
| Package Android | `chichi77-KeyKey-VERSION-android-debug.apk` | Debug signed; a build from another run may require uninstalling the old APK |
| Android Play Release | No public artifact; uploads the signed AAB directly | Manually uploads to Google Play internal testing; promotion to closed testing is managed in Play Console |
| Package iOS Simulator | `chichi77-KeyKey-VERSION-ios-simulator.zip` | Apple Silicon iOS Simulator only; not installable on a device |

Each output has a matching `.sha256` file. A publishing run uploads its output
and checksum to an existing Release, or creates the Release if it does not
exist. It never creates a tag or overwrites an existing asset.

The macOS workflow is split in two jobs. `build` always runs and is given no
secrets at all, producing the unsigned package; `publish` runs only for a tag,
uses the `release` environment, and signs, notarizes, and staples before
publishing to the Release. A macOS package downloaded from a Release therefore
needs no `xattr -d com.apple.quarantine`: Gatekeeper accepts it as it is. The
artifact left behind by a manual run is still an unsigned test build.

A tag run leaves two macOS artifacts whose contents differ under the same file
name: `keykey-macos-VERSION-COMMIT` from `build` is unsigned, and
`keykey-macos-signed-VERSION` from `publish` is the signed and notarized one
that also goes to the Release. Take the Release asset when handing the package
to someone else, not an artifact.

`publish` needs five secrets under the repository's `release` environment:
`APPLE_DEVELOPER_ID_P12` (base64 of a `.p12` holding both the Developer ID
Application and Developer ID Installer identities),
`APPLE_DEVELOPER_ID_P12_PASSWORD`, `APPLE_ID`,
`APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`. That environment's
deployment rule must be restricted to `v*` with a ref type of **tag**, so that
no other workflow and no manual branch run can reach the private key.

The Android Play workflow uses upload-key and Play service-account secrets in
the `google-play-release` environment; Google Play manages the final app
signing. iOS device, TestFlight, and App Store builds are handled by Xcode Cloud
and App Store Connect, not by the Simulator workflow. The other test packages
use only the public dictionaries in this repository. Windows production signing
is still deferred. Because the repository is public, readers may still download
an artifact during its seven-day retention period.
