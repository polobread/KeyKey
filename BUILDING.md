# 建置、安裝與打包 / Building, installation, and packaging

本文件集中說明琦琦輸入法的 macOS、Windows 與 Android 建置流程。

[English](#english)

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

會產生 `out\package\chichi77-KeyKey-1.2.2-windows-x64.zip`。在另一台 x64 Windows
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

## 手動 GitHub Actions 封裝

四個 workflow 都只支援從 GitHub Actions 頁面按 **Run workflow** 手動執行；選擇
要建置的 branch 即可，不需要先建立 tag。一般 commit、pull request 與 tag 不會
觸發。建置完成後，以下未簽章檔案會以 Actions artifact 保留 7 天：

| Workflow | 產物 | 限制 |
|---|---|---|
| Package macOS | `chichi77-KeyKey-版本-macos-arm64.pkg.zip` | 未簽章、未 notarize |
| Package Windows | `chichi77-KeyKey-版本-windows-x64.zip` | 未簽章；內含 x64 與 x86 TSF DLL |
| Package Android | `chichi77-KeyKey-版本-android-debug.apk` | debug key 簽署；不同次建置間可能無法直接升級 |
| Package iOS Simulator | `chichi77-KeyKey-版本-ios-simulator.zip` | 僅 Apple Silicon iOS Simulator，不能安裝到實機 |

artifact 另附同名 `.sha256`。workflow 會封裝 repository 內全部公開詞庫，不需要
私人 repository 或 secret，也不會建立或更新 GitHub Release。正式簽章、公證、
TestFlight 與商店上傳留待後續處理。這是公開 repository，因此 artifact 在 7 天保留
期間仍可能被 repository 讀者下載。

<a id="english"></a>

## English

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

This creates `out\package\chichi77-KeyKey-1.2.2-windows-x64.zip`. On the other
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

### Manual GitHub Actions packaging

The four packaging workflows run only after **Run workflow** is selected on
the GitHub Actions page. Choose the branch to build; commits, pull requests,
and tags do not trigger a run. Successful runs retain these unsigned Actions
artifacts for seven days:

| Workflow | Output | Limitation |
|---|---|---|
| Package macOS | `chichi77-KeyKey-VERSION-macos-arm64.pkg.zip` | Unsigned and not notarized |
| Package Windows | `chichi77-KeyKey-VERSION-windows-x64.zip` | Unsigned; includes x64 and x86 TSF DLLs |
| Package Android | `chichi77-KeyKey-VERSION-android-debug.apk` | Debug signed; a build from another run may require uninstalling the old APK |
| Package iOS Simulator | `chichi77-KeyKey-VERSION-ios-simulator.zip` | Apple Silicon iOS Simulator only; not installable on a device |

Each output has a matching `.sha256` file. The workflows package all public
dictionaries in this repository and require no private repository or secret.
They do not create or modify GitHub Releases. Production
signing, notarization, TestFlight, and store upload are intentionally deferred.
Because the repository is public, readers may still download an artifact
during its seven-day retention period.
