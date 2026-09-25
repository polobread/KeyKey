# 琦琦輸入法 / chichi77 KeyKey 1.3.0

1.3.0 原始碼仍在開發中。目前公開的安裝包為 `v1.2.9`。
`v1.2.9` 的 macOS、Windows 與 Ubuntu 24.04 安裝包集中在同一個
[GitHub Release](https://github.com/polobread/KeyKey/releases/tag/v1.2.9)；
Android 與 iOS 依各自的商店管道安裝。

[下載目前最新的 GitHub Release](https://github.com/polobread/KeyKey/releases/latest)

## 開發初衷

開發琦琦輸入法，是因為我很懷念 Windows 上的微軟「ㄅ半」，以及 macOS 上的
Yahoo! KeyKey。這兩套輸入法後來都沒有持續維護；Android 與 iOS 即使接上實體鍵盤，
也很難沿用「ㄅ半」養成的注音輸入肌肉記憶。因此，我利用自己閒置的生成式 AI 額度，
著手把琦琦輸入法做成跨平台輸入法，希望大家換到不同裝置時，仍能盡量維持熟悉的
按鍵配置與操作習慣，在 macOS、Windows、Android 與 iOS 上快樂地輸入注音。這就是
這個專案的初衷。

也謝謝小麥注音以 MIT License 提供詞庫資料，讓本專案能在它的基礎上繼續擴充。我另外
利用生成式 AI 產生、推論並整理各類分類詞庫；這些資料沒有全面逐筆人工校正，不保證
正確性或完整性，重要用途請自行查證。

Android 與 iOS 版透過 Google Play 與 App Store 的官方流程發行，並提供不影響任何輸入
功能的一次性支持方案；希望免費使用的朋友，仍可 fork 本專案，拉回自己的電腦自行編譯
安裝。macOS、Windows 與 Ubuntu 24.04 安裝包則由 GitHub Release 提供。

琦琦輸入法是 Yahoo! KeyKey 開放原始碼的現代化分支，支援 macOS、Windows、
Android、iOS，以及 Ubuntu Desktop 24.04 LTS 的 Linux 原生版。

Linux 原生版針對 Ubuntu Desktop 24.04、GNOME Shell 46、Fcitx 5、amd64，包含五種傳統注音
布局、候選與符號、30 套關聯詞、中英文與全半形切換，以及額外的倉頡和簡易。
先前版本已驗證 GNOME X11、Wayland、XWayland 的 GTK 3／GTK 4／Qt 6 輸入與候選操作，
另有獨立的 GNOME 候選面板套件。安裝步驟見
[Ubuntu 安裝與使用指南](LINUX_INSTALL.md)。
其他 Ubuntu 版本、IBus、ARM64 與其他發行版留待後續相容性驗收。

本專案以 Yahoo! Inc. 於 2012 年以 BSD 3-Clause License 釋出的原始碼為基礎，
保留 OpenVanilla／PlainVanilla 核心與傳統注音資料，移除失效的網路服務，並為
Windows、Android 與 iOS 建立現代化 frontend。

**本軟體不是 Yahoo 官方產品，與 Yahoo 無隸屬關係，也未獲 Yahoo 背書或贊助。**

[English](#english) · [建置、安裝與打包](BUILDING.md)

## 平台

| 平台 | 實作與支援範圍 |
|---|---|
| macOS | InputMethodKit；macOS 15 以上、Apple Silicon |
| Windows | 原生 TSF；已發布 v1.2.9 適用 Windows 11 x64。1.3.0 開發版以 Windows 10 起為目標，提供 x64／x86 套件；Windows 10 尚待實機驗證 |
| Android | 原生 IME；Android 8 以上，支援觸控與外接鍵盤，不需網路權限 |
| iOS | Swift custom keyboard extension、安裝引導 App 與 App 內實體鍵盤編輯器；不要求完整取用權限、不連網 |
| Linux | Ubuntu Desktop 24.04 LTS、GNOME Shell 46、Fcitx 5、amd64；注音、倉頡、簡易 |

五個平台都提供傳統注音組字、候選字與關聯詞；各平台受作業系統 API 限制，介面與
部分功能會有差異。

1.3.0 的 Windows 原始碼加入好打注音與傳統注音的工作列快速切換、跟隨系統明暗模式的
四頁設定介面，以及 x64／x86 TSF。x64 套件同時包含 x64 與 x86 DLL，供兩種位元數的
應用程式使用；x86 套件供 32 位元 Windows 使用。這些是開發版功能，尚未以 1.3.0
正式發布；升級後須登出再登入，讓工作列載入新版輸入法。

iOS 不允許第三方 keyboard extension 接管 USB／藍牙鍵盤，因此無法在備忘錄、LINE 或
Safari 中提供系統級實體鍵盤注音。琦琦容器 App 另附「實體鍵盤編輯器」：在 App 前景
使用同一套注音引擎與固定直排 `1–9` 候選完成文字，再以複製或 iOS 分享面板送到其他 App。

## 下載與發行

- [下載最新版本](https://github.com/polobread/KeyKey/releases/latest)：此連結會自動前往目前標為 Latest 的 GitHub Release。
- macOS 一般使用者請從[圖文安裝與使用指南](MACOS_INSTALL.md)開始：含下載、啟用、注音選字、詞庫設定及常見問題。
- [Windows 1.3.0 安裝與使用指南](WINDOWS_INSTALL.md)說明新版安裝精靈、好打／傳統注音切換與設定畫面；1.3.0 尚未正式發布。自行建置與測試見 [Windows TSF README](Source/Loaders/Windows-TSF/README.md)。
- Ubuntu 24.04 使用者請看[Linux 安裝與使用指南](LINUX_INSTALL.md)：`v1.2.9` 套件安裝、Fcitx 5 設定與實際桌面截圖。
- 想自行編譯 Linux 版，請看[`./configure` 編譯安裝與使用指南](LINUX_CONFIGURE_INSTALL.md)：下載完整原始碼、編譯測試、啟用輸入法與移除。
- iPhone／iPad 使用者請看[iOS 安裝與使用指南](IOS_INSTALL.md)；可從[《琦琦注音》App Store 頁面](https://apps.apple.com/tw/app/%E7%90%A6%E7%90%A6%E6%B3%A8%E9%9F%B3/id6807832939)安裝。
- Android 手機／平板使用者請看[Android 安裝與使用指南](ANDROID_INSTALL.md)；目前透過 Google 群組及 Google Play 封閉測試加入後安裝。
- [GitHub Releases](https://github.com/polobread/KeyKey/releases) 提供 macOS、Windows 與
  Ubuntu 24.04 版本。macOS 套件以 Developer ID 簽章、經 Apple notarization 並附 SHA-256；Windows
  ZIP 與安裝程式目前未簽章，下載或執行時可能出現安全警告。
- Linux 的三個 `.deb`、面板原始碼及 `SHA256SUMS` 與桌面版同放在 `v1.2.9` Release。
- Android 正式 AAB 由 `Android Play Release` workflow 簽署並手動送到 Google Play；
  1.2.7 已送交封閉測試。`Package Android` 只產生供開發測試的 debug APK。
- iOS 實機版由 App Store 發行；`Package iOS Simulator` 只產生 Apple Silicon
  Simulator 測試包，不能安裝到 iPhone 或 iPad。

### Code signing policy

Free code signing provided by [SignPath.io](https://signpath.io/), certificate
by [SignPath Foundation](https://signpath.org/)。詳見
[Code signing policy](CODE_SIGNING_POLICY.md)。`v1.2.9` Windows 發行檔早於此整合，
目前仍未簽章；SignPath Foundation 核准申請並完成驗證流程後，政策才適用於後續正式版。

推送符合專案版號的 tag（例如 `v1.3.0`）會啟動 `Package macOS`、
`Package Windows` 與完整 `Linux CI`。macOS 和 Windows 的產物，以及通過 Ubuntu 24.04
套件安裝與輸入測試的 Linux 套件，會加入同一個 GitHub Release。手動執行 Linux CI
只保留 Actions artifact，不發布 Release。Linux 的 1.2.9 GNOME 實機相容性仍須持續驗收。
完整產物、簽章與限制見 [BUILDING.md](BUILDING.md#github-actions-封裝)。

## 文件

- [macOS 圖文安裝與使用指南](MACOS_INSTALL.md)：首次安裝、日常選字、符號與偏好設定
- [macOS App Store Connect 上架可行性與發行計畫](MACOS_APP_STORE_PLAN.md)：Apple
  現行政策阻礙、第三方輸入法經驗、商店外發行改善與未來上架 gate
- [Windows 1.3.0 安裝與使用指南](WINDOWS_INSTALL.md)：新版安裝精靈、啟用、選字、設定與解除安裝
- [Linux 安裝與使用指南](LINUX_INSTALL.md)：Ubuntu 24.04 的套件安裝、Fcitx 5 設定、注音選字與實拍圖
- [Linux `./configure` 編譯安裝與使用指南](LINUX_CONFIGURE_INSTALL.md)：Ubuntu 24.04 的原始碼安裝、啟用、試打與移除
- [iOS 安裝與使用指南](IOS_INSTALL.md)：App Store 安裝、加入鍵盤、日常操作與實體鍵盤編輯器
- [Android 安裝與使用指南](ANDROID_INSTALL.md)：Google Play 測試安裝、啟用鍵盤、觸控與實體鍵盤操作
- [BUILDING.md](BUILDING.md)：各平台建置、測試、安裝與打包
- [五平台心經長文 functional test](tests/HEART_SUTRA_FUNCTIONAL.md)：關閉關聯詞庫後逐字輸入，核對全文及每字候選順位
- [Linux 開發計畫](LINUX_DEVELOPMENT_PLAN.md)與[自動化測試計畫](LINUX_TEST_PLAN.md)：
  1.2.8 起的原生 Linux 支援目標、目前進度、功能範圍與驗收門檻
- [Windows TSF README](Source/Loaders/Windows-TSF/README.md)：Windows frontend
  的實作、部署及驗證細節
- [Android IME README](Source/Loaders/Android-IME/README.md)：Android 鍵盤配置、
  建置與啟用方式
- [iOS Keyboard README](Source/Loaders/iOS-Keyboard/README.md)：iOS extension 架構、
  建置方式與平台限制
- [CHANGELOG.md](CHANGELOG.md)：版本更新內容
- [App Store / Google Play 素材](StoreAssets/README.md)：商店圖片、來源截圖、內文與發布管道
- [Installer README](Installer/README.md)：macOS 安裝包、簽署及 notarization
- [LICENSING.md](LICENSING.md)：Yahoo BSD、原創 frontend MIT 與第三方授權範圍
- [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)：第三方素材與授權

## 詞庫與限制

公開 repository 內含 McBopomofo 的字音與詞頻資料，以及 29 份以 MIT License
釋出的分類關聯詞詞庫。分類詞庫由自動化方式生成、推論與整理，沒有逐筆人工校正，
可能含有錯誤；不保證正確性或完整性，詳見
[`DataSource/chichi77Collection`](DataSource/chichi77Collection/README.md)。

1.3.0 的 macOS、Windows、iOS、Android 與 Linux 原始碼均提供「好打注音」整句組字模式，
並可切回傳統逐字注音；已發布套件的功能仍以各版本安裝指南為準。語言模型由
McBopomofo 的 MIT 授權字音與詞頻資料在建置時產生，不使用 Yahoo 未釋出的中研院語料；
另加入可替換的 11,180 句 AI 合成 bootstrap corpora 產生初版 bigram 上下文資料。這份
小型合成語料用於工程與 A/B 測試，不代表完整的台灣繁中語料分布。

<a id="english"></a>

## English

The 1.3.0 source version is still in development. The currently published
macOS, Windows, and Ubuntu 24.04 installers for `v1.2.9` share one
[GitHub Release](https://github.com/polobread/KeyKey/releases/tag/v1.2.9).
Android and iOS use their respective store distribution channels.

The 1.3.0 source implements Smart Phonetic sentence composition on macOS,
Windows, iOS, Android, and Linux, with Traditional Phonetic available as an
option. For published builds, consult the installation guide for that version.
Its redistributable unigram model is generated from the MIT-licensed
McBopomofo readings and occurrence counts. Replaceable AI-generated bootstrap
corpora with 11,180 sentences supply an initial bigram layer for engineering and A/B testing; the
proprietary corpus from the historical Yahoo build is not included.

[Download the latest GitHub Release](https://github.com/polobread/KeyKey/releases/latest).

chichi77 KeyKey is a modernized fork of the open-source Yahoo! KeyKey input
method. It supports macOS, Windows, Android, iOS, and Ubuntu Desktop 24.04 LTS.

The native Linux build targets Ubuntu Desktop 24.04, GNOME Shell 46, Fcitx 5,
and amd64. It includes five Traditional Bopomofo layouts, candidates, symbols,
30 associated-phrase collections, Chinese/English and full-width modes, plus
Cangjie and Simplex. Earlier builds were checked with GTK 3, GTK 4, and Qt 6
on GNOME X11, Wayland, and XWayland. The separate GNOME candidate panel package
handles popup placement. See the [Ubuntu installation guide](LINUX_INSTALL.md).
Other Ubuntu versions,
IBus, ARM64, and other distributions await compatibility testing.

The project retains the OpenVanilla/PlainVanilla core and Traditional Bopomofo
data, removes obsolete online services, and adds modern Windows, Android, and
iOS frontends.

**This is not an official Yahoo product. It is not affiliated with, endorsed
by, or sponsored by Yahoo.**

### Platforms

| Platform | Implementation and support |
|---|---|
| macOS | InputMethodKit; macOS 15 or later on Apple Silicon |
| Windows | Native TSF; published v1.2.9 targets Windows 11 x64. The 1.3.0 development build targets Windows 10 or later with x64/x86 packages; Windows 10 device verification is pending |
| Android | Native IME; Android 8 or later, touch and hardware keyboards, no network permission |
| iOS | Swift custom keyboard extension and in-app hardware keyboard editor; no Full Access or network access |
| Linux | Ubuntu Desktop 24.04 LTS, GNOME Shell 46, Fcitx 5, amd64; Bopomofo, Cangjie, Simplex |

All five platforms provide Traditional Bopomofo composition, candidates, and
associated phrases. UI and some features differ with each platform's APIs.

The 1.3.0 Windows source adds direct Smart/Traditional Phonetic selection from
the taskbar, a four-page settings app that follows the system light/dark mode,
and x64/x86 TSF builds. The x64 package includes both DLL architectures for
64-bit and 32-bit applications; the x86 package is for 32-bit Windows. Version
1.3.0 has not been published. After upgrading a development installation, sign
out and back in so the taskbar loads the new input method.

iOS does not let a third-party keyboard extension take over USB or Bluetooth
keyboard events, so system-wide hardware-keyboard input in Notes, LINE, or
Safari is not available. The container app instead includes a hardware-keyboard
editor that uses the same engine and a fixed vertical `1–9` candidate list while
the app is in the foreground, then copies or shares the completed text through
iOS.

### Downloads and releases

- [Latest release](https://github.com/polobread/KeyKey/releases/latest) always opens the release currently marked Latest on GitHub.
- First-time macOS setup, illustrated steps, and troubleshooting: [macOS installation guide (Traditional Chinese)](MACOS_INSTALL.md).
- The [Windows 1.3.0 installation guide (Traditional Chinese)](WINDOWS_INSTALL.md) covers the new installer, typing modes, and settings. Version 1.3.0 has not been published; see the [Windows TSF README](Source/Loaders/Windows-TSF/README.md) for building and testing.
- Ubuntu 24.04 installation, Fcitx 5 setup, and typing with desktop screenshots: [Linux installation guide (Traditional Chinese)](LINUX_INSTALL.md).
- Build and install the Ubuntu 24.04 version from source with `./configure`: [Linux source installation and usage guide (Traditional Chinese)](LINUX_CONFIGURE_INSTALL.md).
- iPhone and iPad setup and use: [iOS installation guide (Traditional Chinese)](IOS_INSTALL.md), with the [App Store listing](https://apps.apple.com/tw/app/%E7%90%A6%E7%90%A6%E6%B3%A8%E9%9F%B3/id6807832939).
- Android setup and daily use: [Android installation guide (Traditional Chinese)](ANDROID_INSTALL.md). Installation currently uses a Google Group and Google Play closed testing.
- [GitHub Releases](https://github.com/polobread/KeyKey/releases) provides the
  macOS, Windows, and Ubuntu 24.04 builds. The macOS package is Developer ID signed,
  notarized by Apple, and accompanied by a SHA-256 checksum. The Windows ZIP
  and installer are currently unsigned and may trigger a security warning.
- The three Linux `.deb` files, panel source archive, and `SHA256SUMS` share the
  `v1.2.9` Release with the desktop builds.
- The signed Android AAB is uploaded manually to Google Play by the
  `Android Play Release` workflow. Version 1.2.7 has been submitted to closed
  testing. `Package Android` produces a debug APK for development only.
- Device builds for iOS are distributed through the App Store.
  `Package iOS Simulator` produces an Apple Silicon Simulator build that cannot
  be installed on an iPhone or iPad.

#### Code signing policy

Free code signing provided by [SignPath.io](https://signpath.io/), certificate
by [SignPath Foundation](https://signpath.org/). See the
[Code signing policy](CODE_SIGNING_POLICY.md). The Windows assets in `v1.2.9`
predate this integration and remain unsigned; the policy applies to later
official releases after the application is accepted and the verified workflow
is enabled.

Pushing a tag that exactly matches the project version, such as `v1.3.0`,
starts `Package macOS`, `Package Windows`, and the full `Linux CI`. The desktop
outputs and the Linux packages that pass the Ubuntu 24.04 package checks are
added to the same GitHub Release. Manual Linux CI runs retain Actions artifacts
without publishing a Release. Linux 1.2.9 GNOME hardware compatibility still
needs broader validation.
See [BUILDING.md](BUILDING.md#github-actions-packaging) for the
complete output and signing details.

### Documentation

- [macOS App Store Connect feasibility and distribution plan (Traditional Chinese)](MACOS_APP_STORE_PLAN.md): current Apple policy blocker, external distribution improvements, and future go/no-go gates
- [Windows 1.3.0 installation and use guide (Traditional Chinese)](WINDOWS_INSTALL.md): new installer, setup, typing, preferences, and removal
- [Linux installation and use guide (Traditional Chinese)](LINUX_INSTALL.md): Ubuntu 24.04 packages, Fcitx 5 setup, typing, and desktop screenshots
- [Linux `./configure` installation and use guide (Traditional Chinese)](LINUX_CONFIGURE_INSTALL.md): source build, Fcitx 5 setup, typing, and removal on Ubuntu 24.04
- [Android installation and use guide (Traditional Chinese)](ANDROID_INSTALL.md): Google Play testing, keyboard setup, touch and hardware keyboard use
- [BUILDING.md](BUILDING.md): build, test, installation, and packaging instructions
- [Linux development plan](LINUX_DEVELOPMENT_PLAN.md) and
  [automated test plan](LINUX_TEST_PLAN.md): scope and acceptance criteria for
  native Linux support targeted for 1.2.8 onward, including current progress
- [Windows TSF README](Source/Loaders/Windows-TSF/README.md): frontend
  implementation, deployment, and verification details
- [Android IME README](Source/Loaders/Android-IME/README.md): layouts, build,
  and setup instructions
- [iOS Keyboard README](Source/Loaders/iOS-Keyboard/README.md): extension
  architecture, build instructions, and platform limitations
- [CHANGELOG.md](CHANGELOG.md): release changes
- [App Store / Google Play assets](StoreAssets/README.md): store images, source
  captures, copy, and distribution channels
- [Installer README](Installer/README.md): macOS packaging, signing, and
  notarization
- [LICENSING.md](LICENSING.md): Yahoo BSD, original frontend MIT, and
  third-party license scope
- [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md): third-party material and
  licenses

### Data and limitations

The public repository includes McBopomofo mappings and frequency data and 29
categorized associated-phrase collections under the MIT License. The categorized
data was generated, inferred, and normalized automatically, has not been reviewed
item by item, and may contain errors. Accuracy and completeness are not
guaranteed; see
[`DataSource/chichi77Collection`](DataSource/chichi77Collection/README.md).
Smart Mandarin uses a redistributable model generated from McBopomofo data and the
replaceable synthetic bootstrap corpora described above. Yahoo's proprietary Sinica corpus
is not included.

## License

This is a mixed-license repository. Original Android, iOS, and Windows TSF
frontend material is Copyright (c) 2026 Chui-Ping Cheng and distributed under
the [MIT License](LICENSES/MIT.txt). The original Yahoo! KeyKey source and
modifications derived from it remain under the BSD 3-Clause License in
[LICENSE.txt](LICENSE.txt).
See [LICENSING.md](LICENSING.md) for the scope map and
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for third-party material.
