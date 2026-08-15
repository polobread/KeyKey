# 建置、安裝與打包 / Building, installation, and packaging

本文件集中說明琦琦輸入法的 macOS 與 Windows 建置流程。

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

### 私人詞庫

經授權的 build 可將獨立的 `chichi77Collection` repository 放在 KeyKey 同層，
並從 KeyKey 根目錄建立本機 symlink：

```sh
ln -s ../../chichi77Collection DataSource/chichi77Collection
```

此 symlink 已被 Git 忽略。私人詞庫不屬於 KeyKey repository，也不包含在本專案
的開源授權內。

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
```

輸出檔案為：

```text
out\build\x64-ninja\KeyKeyTsf.dll
out\build\x64-ninja\KeyKeySettings.exe
out\build\x64-ninja\Databases\KeyKey.db
```

若 KeyKey 同層存在 `chichi77Collection`，建置時會自動納入其中的詞庫。若詞庫在
其他位置，可在 CMake configure 時加入：

```powershell
-DKEYKEY_CHICHI77_COLLECTION_DIR=C:\path\to\chichi77Collection
```

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
.\Package-Windows.ps1 -BuildDirectory .\out\build\x64-ninja
```

會產生 `out\package\chichi77-KeyKey-1.2-windows-x64.zip`。把 ZIP 複製到另一台
x64 Windows 11 電腦，完整解壓縮後執行 `Install.cmd` 並允許 UAC。安裝程式會：

- 將檔案複製到 `C:\Program Files\chichi77 KeyKey`
- 從固定路徑註冊 TSF
- 在 Windows「已安裝的應用程式」加入解除安裝項目

安裝腳本會自動加入目前使用者的 `Win+Space` 輸入法清單；若沒有立即出現，請登出
再登入。這是未簽署的家用測試套件，因此從網路下載時 Windows 可能顯示安全警告。

ARM64 請改用 `windows-arm64` 與 `windows-arm64-release` preset，並在打包時加入
`-Architecture arm64`。DLL 架構必須和載入它的應用程式架構相同。若資料庫含有
私人 `chichi77Collection`，只應交給有權使用該資料的人。

Windows frontend 的部署及驗證細節見
[Source/Loaders/Windows-TSF/README.md](Source/Loaders/Windows-TSF/README.md)。

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

An authorized build can expose the separately maintained private collection to
the legacy cooker by placing `chichi77Collection` beside KeyKey and running
this from the KeyKey repository root:

```sh
ln -s ../../chichi77Collection DataSource/chichi77Collection
```

The symlink is ignored by Git. The private collection is not part of KeyKey or
its open-source license. See [Installer/README.md](Installer/README.md) for
macOS packaging, local installation, signing, and notarization.

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
```

The outputs are:

```text
out\build\x64-ninja\KeyKeyTsf.dll
out\build\x64-ninja\KeyKeySettings.exe
out\build\x64-ninja\Databases\KeyKey.db
```

A sibling `chichi77Collection` is detected automatically. Override its location
during CMake configuration with:

```powershell
-DKEYKEY_CHICHI77_COLLECTION_DIR=C:\path\to\chichi77Collection
```

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
.\Package-Windows.ps1 -BuildDirectory .\out\build\x64-ninja
```

This creates `out\package\chichi77-KeyKey-1.2-windows-x64.zip`. Copy it to the
other x64 Windows 11 PC, extract the entire ZIP, and run `Install.cmd`. The
installer copies the runtime to `C:\Program Files\chichi77 KeyKey`, registers
the TSF, adds it to the current user's `Win+Space` list, and creates an entry in
Windows Installed apps. Sign out and back in if it does not appear immediately.

The home-testing package is unsigned, so Windows may warn about a downloaded
copy. For ARM64, use the `windows-arm64` build presets and pass
`-Architecture arm64` when packaging. Distribute a database containing the
private `chichi77Collection` only to authorized users.

See the [Windows TSF README](Source/Loaders/Windows-TSF/README.md) for detailed
deployment and verification information.
