# 琦琦輸入法 / chichi77 KeyKey 1.2.7

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
安裝。macOS 與 Windows 安裝包則由 GitHub Release 提供。

琦琦輸入法是 Yahoo! KeyKey 開放原始碼的現代化分支，目前支援 macOS、Windows、
Android 與 iOS 四個平台。

本專案以 Yahoo! Inc. 於 2012 年以 BSD 3-Clause License 釋出的原始碼為基礎，
保留 OpenVanilla／PlainVanilla 核心與傳統注音資料，移除失效的網路服務，並為
Windows、Android 與 iOS 建立現代化 frontend。

**本軟體不是 Yahoo 官方產品，與 Yahoo 無隸屬關係，也未獲 Yahoo 背書或贊助。**

[English](#english) · [建置、安裝與打包](BUILDING.md)

## 平台

| 平台 | 實作與支援範圍 |
|---|---|
| macOS | InputMethodKit；macOS 15 以上、Apple Silicon |
| Windows | 原生 TSF；Windows 11 x64，並支援 32-bit Office process |
| Android | 原生 IME；Android 8 以上，支援觸控與外接鍵盤，不需網路權限 |
| iOS | Swift custom keyboard extension 與安裝引導 App；不要求完整取用權限、不連網 |

四個平台都提供傳統注音組字、候選字與關聯詞；各平台受作業系統 API 限制，介面與
部分功能會有差異。

## 下載與發行

- [GitHub Releases](https://github.com/polobread/KeyKey/releases) 提供 macOS 與 Windows
  桌面版。macOS 套件以 Developer ID 簽章、經 Apple notarization 並附 SHA-256；Windows
  ZIP 與安裝程式目前未簽章，下載或執行時可能出現安全警告。
- Android 正式 AAB 由 `Android Play Release` workflow 簽署並手動送到 Google Play；
  1.2.7 已送交封閉測試。`Package Android` 只產生供開發測試的 debug APK。
- iOS 實機版由 Xcode Cloud／App Store Connect 建置及發行；`Package iOS Simulator`
  只產生 Apple Silicon Simulator 測試包，不能安裝到 iPhone 或 iPad。

推送符合專案版號的 tag（例如 `v1.2.7`）會同時啟動 `Package macOS` 與
`Package Windows`，並把桌面版產物加入同一個 GitHub Release。兩個 workflow 也能手動
執行；手動執行只保留 Actions artifact，不代表正式發行。完整產物、簽章與限制見
[BUILDING.md](BUILDING.md#github-actions-封裝)。

## 文件

- [BUILDING.md](BUILDING.md)：四平台建置、測試、安裝與打包
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

智慧注音所需的中研院語料未包含在 Yahoo 的開源釋出中，因此目前不啟用。

<a id="english"></a>

## English

chichi77 KeyKey is a modernized fork of the open-source Yahoo! KeyKey input
method. It supports macOS, Windows, Android, and iOS.

The project retains the OpenVanilla/PlainVanilla core and Traditional Bopomofo
data, removes obsolete online services, and adds modern Windows, Android, and
iOS frontends.

**This is not an official Yahoo product. It is not affiliated with, endorsed
by, or sponsored by Yahoo.**

### Platforms

| Platform | Implementation and support |
|---|---|
| macOS | InputMethodKit; macOS 15 or later on Apple Silicon |
| Windows | Native TSF; Windows 11 x64, including 32-bit Office processes |
| Android | Native IME; Android 8 or later, touch and hardware keyboards, no network permission |
| iOS | Swift custom keyboard extension and setup app; no Full Access or network access |

All four platforms provide Traditional Bopomofo composition, candidates, and
associated phrases. UI and some features differ with each platform's APIs.

### Downloads and releases

- [GitHub Releases](https://github.com/polobread/KeyKey/releases) provides the
  macOS and Windows desktop builds. The macOS package is Developer ID signed,
  notarized by Apple, and accompanied by a SHA-256 checksum. The Windows ZIP
  and installer are currently unsigned and may trigger a security warning.
- The signed Android AAB is uploaded manually to Google Play by the
  `Android Play Release` workflow. Version 1.2.7 has been submitted to closed
  testing. `Package Android` produces a debug APK for development only.
- Device builds for iOS are handled by Xcode Cloud and App Store Connect.
  `Package iOS Simulator` produces an Apple Silicon Simulator build that cannot
  be installed on an iPhone or iPad.

Pushing a tag that exactly matches the project version, such as `v1.2.7`,
starts `Package macOS` and `Package Windows` and adds both desktop outputs to
the same GitHub Release. Manual runs retain Actions artifacts for testing but
are not a formal release. See [BUILDING.md](BUILDING.md#github-actions-packaging)
for the complete output and signing details.

### Documentation

- [BUILDING.md](BUILDING.md): build, test, installation, and packaging instructions
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
Smart Mandarin remains disabled because the required Sinica corpus was not
included in Yahoo's source release.

## License

This is a mixed-license repository. Original Android, iOS, and Windows TSF
frontend material is Copyright (c) 2026 Chui-Ping Cheng and distributed under
the [MIT License](LICENSES/MIT.txt). The original Yahoo! KeyKey source and
modifications derived from it remain under the BSD 3-Clause License in
[LICENSE.txt](LICENSE.txt).
See [LICENSING.md](LICENSING.md) for the scope map and
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for third-party material.
