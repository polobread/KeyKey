# 琦琦輸入法 / chichi77 KeyKey 1.2.2

琦琦輸入法是 Yahoo! KeyKey 開放原始碼的現代化分支，支援 macOS 15 以上的
Apple Silicon、Windows 11 x64，以及 Android 8 以上；Windows 套件同時支援
32-bit Office。

本專案以 Yahoo! Inc. 於 2012 年以 BSD 3-Clause License 釋出的原始碼為基礎，
保留 OpenVanilla／PlainVanilla 核心，移除失效的網路服務與 Yahoo 品牌，並加入
現代 Windows TSF frontend。

**本軟體不是 Yahoo 官方產品，與 Yahoo 無隸屬關係，也未獲 Yahoo 背書或贊助。**

[English](#english) · [建置、安裝與打包](BUILDING.md)

## 目前功能

### macOS

- InputMethodKit frontend，目前支援 arm64、macOS 15 以上
- 預設使用傳統注音，並保留倉頡、簡易等既有模組
- 支援候選字、關聯詞、自訂詞與偏好設定

> **安裝注意：** 首次安裝後請登出再重新登入，Text Input Services 只在登入時
> 掃描 `/Library/Input Methods`；重新登入後於「系統設定 → 鍵盤 → 輸入來源」
> 加入琦琦輸入法。覆蓋既有版本不需要登出，安裝程式會結束執行中的輸入法，並由
> 系統接上新版。

### Windows 11

- 原生 TSF frontend，支援 x86 與 x64 host process
- 支援注音組字、候選字、關聯詞、送字與游標定位
- 預設為中文注音、半形模式
- `Shift` 或 `Ctrl+Space` 切換中文／英文，`Shift+Space` 切換半形／全形
- 語言列顯示「琦」、「ㄅ／英」與「半／全」，並提供一般、注音與關聯詞設定入口

> **安裝注意：** 請先完整解壓縮 ZIP，再把整個解壓縮資料夾複製到本機
> `C:\`（例如 `C:\KeyKeyInstaller`），最後才執行 `Install.cmd`。請勿直接從
> 網路磁碟、NAS 或 UNC 路徑安裝；UAC 提升權限後可能無法存取原路徑，且安裝
> 視窗可能立即關閉。

### Android

- 原生 Android IME，支援 Android 8 以上
- 直式六排鍵盤：候選列加上與電腦相同的五排標準注音鍵位
- 橫式五排鍵盤：中央為兩欄候選字（左 1–5、右 6–0）
- USB／藍牙鍵盤模式只顯示單行候選字，可用數字鍵選字
- 使用 repository 內相同的 `bpmf-ext.cin` 傳統注音字表，不需要網路權限

## 文件

- [BUILDING.md](BUILDING.md)：macOS／Windows 中英文建置、測試、安裝與打包
- [Windows TSF README](Source/Loaders/Windows-TSF/README.md)：Windows frontend
  的實作、部署及驗證細節
- [Android IME README](Source/Loaders/Android-IME/README.md)：Android 鍵盤配置、
  建置與啟用方式
- [Installer README](Installer/README.md)：macOS 安裝包、簽署及 notarization
- [LICENSING.md](LICENSING.md)：Yahoo BSD、原創 frontend MIT 與第三方授權範圍
- [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)：第三方素材與授權

## 詞庫與限制

公開 repository 內含 McBopomofo 以 MIT License 釋出的字音對照及詞頻資料，供
注音候選與關聯詞使用。私人 `chichi77Collection` 在獨立 repository 維護，不屬於
本 repository，也不包含在本專案的開源授權內。

智慧注音（Smart Mandarin）需要的中研院 unigram／bigram 語料未包含在 Yahoo
的開源釋出中，因此目前不啟用。Yahoo 1.1 的 CEROD 字典、SEE 加密使用者資料，
以及已停止的 Yahoo／MobileMe 網路服務也不包含在目前版本中。

## 參考資料

- [McBopomofo](https://github.com/openvanilla/McBopomofo)
- [win-mcbopomofo](https://github.com/openvanilla/win-mcbopomofo)
- [McBopomofo Text Pool](https://mcbopomofo.openvanilla.org/textpool.html)
- [詞庫開發說明](https://github.com/openvanilla/McBopomofo/wiki/%E8%A9%9E%E5%BA%AB%E9%96%8B%E7%99%BC%E8%AA%AA%E6%98%8E)

<a id="english"></a>

## English

chichi77 KeyKey is a modernized fork of the open-source Yahoo! KeyKey input
method. It supports macOS 15 or later on Apple Silicon, Windows 11 on x64,
and Android 8 or later. The Windows package also supports 32-bit Office processes.

The project retains the OpenVanilla/PlainVanilla core, removes obsolete online
services and Yahoo branding, and adds a modern Windows TSF frontend.

**This is not an official Yahoo product. It is not affiliated with, endorsed
by, or sponsored by Yahoo.**

### Current features

- macOS uses InputMethodKit. Traditional Phonetic is the default, with
  candidates, associated phrases, user phrases, and preferences.
- Windows uses a native TSF frontend with Bopomofo composition and candidates,
  associated phrases, caret-aware commit, mode indicators, and dictionary
  settings.
- Windows starts in Chinese Bopomofo and half-width mode. Press `Shift` or
  `Ctrl+Space` to switch Chinese/English, and `Shift+Space` to switch width.
- Android uses a native IME with a six-row portrait layout, a five-row
  landscape layout with two center candidate columns, and a candidate-only
  layout for USB or Bluetooth keyboards. It uses the shared `bpmf-ext.cin`
  dictionary and requests no network permission.

> **macOS installation:** After a first install, log out and back in. Text
> Input Services only scans `/Library/Input Methods` at login. Then add the
> input source under System Settings, Keyboard, Input Sources. Upgrading over
> an already installed version needs neither step; the installer ends the
> running input method and the system starts the new one in its place.

> **Windows installation:** Extract the complete ZIP, copy the entire extracted
> folder to a local `C:\` path such as `C:\KeyKeyInstaller`, and only then run
> `Install.cmd`. Do not install directly from a mapped network drive, NAS, or
> UNC path; the source can become inaccessible after UAC elevation.

### Documentation

- [BUILDING.md](BUILDING.md): bilingual macOS/Windows build, test,
  installation, and packaging instructions
- [Windows TSF README](Source/Loaders/Windows-TSF/README.md): frontend
  implementation, deployment, and verification details
- [Android IME README](Source/Loaders/Android-IME/README.md): layouts, build,
  and setup instructions
- [Installer README](Installer/README.md): macOS packaging, signing, and
  notarization
- [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md): third-party material and
  licenses

### Data and limitations

The public repository vendors McBopomofo mappings and frequency data under the
MIT License. The private `chichi77Collection` is maintained separately and is
not covered by this repository's open-source license.

Smart Mandarin remains disabled because the required Sinica unigram/bigram
corpus was not included in Yahoo's source release. Yahoo's CEROD dictionary,
SEE-encrypted user data, and obsolete Yahoo/MobileMe services are also absent.

### Reference

- [McBopomofo](https://github.com/openvanilla/McBopomofo)
- [win-mcbopomofo](https://github.com/openvanilla/win-mcbopomofo)
- [McBopomofo Text Pool](https://mcbopomofo.openvanilla.org/textpool.html)
- [Dictionary development guide](https://github.com/openvanilla/McBopomofo/wiki/%E8%A9%9E%E5%BA%AB%E9%96%8B%E7%99%BC%E8%AA%AA%E6%98%8E)

## License

This is a mixed-license repository. Original Android, iOS, and Windows TSF
frontend material is Copyright (c) 2026 Chui-Ping Cheng and distributed under
the [MIT License](LICENSES/MIT.txt). The original Yahoo! KeyKey source and
modifications derived from it remain under the BSD 3-Clause License below.
See [LICENSING.md](LICENSING.md) for the scope map and
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for third-party material.

### BSD 3-Clause License — Yahoo! KeyKey source

Copyright (c) 2012, Yahoo! Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of Yahoo! Inc. nor the names of its contributors may be
   used to endorse or promote products derived from this software without
   specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
