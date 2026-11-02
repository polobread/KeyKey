# 琦琦輸入法 1.2.9～1.3.7 六平台改版宣傳素材

本份將 1.2.9～1.3.7 的變化按平台一次彙整，供社群貼文、媒體介紹與圖片文案使用，不逐版發文。下方「總宣傳文案」「六平台文案」「短文與圖片文字」可依使用場景直接取用；末尾保留編輯核對依據。

整理日期：2026-10-25。依據 `master` 修訂 `892c47468328d83986c0bae8538975ab04209eaa`、正式 Release、六平台安裝指南、設定支援表與相關程式碼。文案功能以當時正式版 **1.3.7** 為基準。

目前 macOS 正式版為 **1.3.8**，其他平台維持 **1.3.7**；本文下載入口已依平台分開，功能與圖片仍保留原本的 1.3.7 基準。

## 總宣傳文案

### 主標題

琦琦輸入法 1.3.7：整句順著打，倉頡打到一半也能選

### 副標題

從電腦到手機，讓熟悉的中文輸入習慣，陪你走到六大平台。

### 貼文內文

還記得 Windows「ㄅ半」與 Yahoo! KeyKey 的打字手感嗎？琦琦輸入法持續把熟悉的操作帶到現在的裝置。從 1.2.9 到 1.3.7，這一波改版把重點放在每天都會用到的事：整句輸入、句中改字、記住常用詞，以及切換中英文。

**好打注音，先順著句子打。** 連續輸入注音，由上下文協助組句；要修改同音字，再回到仍在組字範圍內的位置選字。習慣逐字選字，也能切回傳統注音。

**倉頡，不必每次打完完整字碼。** 開啟「即時候選」與「未打完也能選字」，輸入「竹大」就能從候選找「喬」。完整字碼仍可照常輸入，熟悉的選字與翻頁方式也保留下來。

**六大平台，各有適合的操作方式。** Windows 與 Mac 強化設定、自訂詞及 Emoji；iPhone、iPad 和 Android 改善觸控組句與選字；Ubuntu 持續完善 Fcitx 5 整合，FreeBSD 也正式納入支援。

目前正式支援 **Windows／macOS／iOS／Android／Linux／FreeBSD**。iOS、Android 可直接從 App Store、Google Play 安裝，未付費也能完整使用輸入功能；Mac、Windows、Ubuntu 可從 GitHub Release 或台灣 AWS CDN 下載，FreeBSD 透過 ports／pkg 安裝。

[依平台下載正式版](../README.md#下載與發行) · [App Store](https://apps.apple.com/tw/app/id6807832939) · [Google Play](https://play.google.com/store/apps/details?id=tw.chichi77.keykey.android)

## 六平台文案

### Windows：熟悉的注音習慣，搭配更完整的設定

從整句組字到逐字選字，琦琦 Windows 版把好打注音、傳統注音、倉頡與簡易放進同一個工作列選單。這一波改版加入自訂詞與選字學習，改善搜尋列、切換輸入法與長句輸入的操作，也讓設定更貼近個人習慣。

習慣微軟新舊注音的 Caps Lock 行為，可以使用預設開啟的「中文模式忽略 Caps Lock」；空白鍵開候選、三組選字鍵與 10～20 音節組字長度，也能依需求調整。自訂詞可查本地讀音、選擇破音字讀音，常用名稱不用每次重新選字。

想加個表情，符號表已有 **200 個 Emoji**，還能連續點選插入。倉頡開啟「未打完也能選字」後，打到「竹大」即可找「喬」。正式 1.3.7 提供已簽章的 x64 安裝程式與 ZIP 套件，安裝、升級更方便辨認來源。

- 圖片主標：**熟悉的注音習慣，更完整的選字設定**
- 圖片短句：**整句組字／自訂詞讀音輔助／200 個 Emoji**
- 操作重點：中文模式忽略 Caps Lock 預設開啟；倉頡的即時候選與未打完選字須自行開啟。
- 下載：[1.3.7 正式版與台灣 AWS 下載點](https://github.com/polobread/KeyKey/releases/tag/v1.3.7)
- 教學：[Windows 安裝與使用指南](../WINDOWS_INSTALL.md)
- 配圖：[句中「玩」候選](images/keykey-windows-v137-win07a-middle-candidate-win11.png)、[一般設定](images/keykey-windows-v137-win12a-general-win11.png)、[Emoji 插入結果](images/keykey-windows-v137-win11b-emoji-inserted-win11.png)。圖片環境為 Windows 11。

### macOS：好打注音回來了，輕按 Shift 就能切換中英文

琦琦 Mac 版恢復好打注音的整句輸入，搭配更新的常用詞、上下文排序與選字學習。想順著句子打，使用好打注音；習慣傳統注音、倉頡或簡易，也能從輸入法選單切換。

這次新增獨立英文模式，**輕按 Shift 就能切換中英文**；不想使用這個快捷鍵，也可以在一般設定關閉。倉頡加入未打完選字，輸入「竹大」就能提前找「喬」。符號表新增 **200 個 Emoji**，點選後可繼續挑選，聊天與筆記都更方便。

自訂詞可編輯，學習紀錄也能單獨重設，保留自己新增的詞。安裝與升級流程同步改善，減少更新後仍沿用舊詞庫的問題。適用於 **macOS 15 以上的 Apple Silicon Mac**。

- 圖片主標：**整句順著打，中英輕鬆切換**
- 圖片短句：**好打注音／Shift 切換／倉頡提前選字／200 個 Emoji**
- 操作重點：Shift 快捷鍵可關閉；桌面倉頡的兩個候選選項須自行開啟。
- 下載：[1.3.8 正式版與台灣 AWS 下載點](https://github.com/polobread/KeyKey/releases/tag/v1.3.8)
- 教學：[macOS 安裝與使用指南](../MACOS_INSTALL.md)
- 配圖：[好打注音「玩」候選](images/keykey-macos-v137-mac07-middle-candidate-apple-silicon.png)、[英文模式提示](images/keykey-macos-v137-mac10b-english-mode.png)、[Emoji 插入結果](images/keykey-macos-v137-mac11b-emoji-inserted.png)。均為 Mac 實機素材。

### iPhone／iPad：整句先打，需要改字再點選

在 iPhone、iPad 上，琦琦好打注音讓你連續輸入，不必每個字都停下來選。組好的中文字會出現在 App 欄位，最近仍可修改的部分保留在鍵盤上方；想改同音字，點組字格就能開候選。長句、句中改字與切換 App 時的文字保留，也持續改善。

這一波新增倉頡、簡易與許氏注音配置；到了 1.3.7，倉頡更能在字根尚未打完時選字，打到「竹大」就能找「喬」。偏好空白鍵選字的人，可以開啟「使用空白鍵選字」，用空白開候選與翻頁。

**鍵盤不要求「完整取用」權限**，未付費也能完整使用輸入功能。接上 USB／藍牙鍵盤時，可在琦琦 App 內的實體鍵盤編輯器完成文字，再複製或分享。正式版可直接從台灣 App Store 安裝，適用於 **iOS 17／iPadOS 17 以上**。

- 圖片主標：**整句先打，點字就能改**
- 圖片短句：**好打注音／倉頡與簡易／標準與許氏／不要求完整取用**
- 操作重點：可修改範圍為最近九個音節；外接鍵盤輸入只在琦琦 App 前景編輯器中提供。
- 安裝：[台灣 App Store](https://apps.apple.com/tw/app/id6807832939)
- 教學：[iPhone、iPad 安裝與使用指南](../IOS_INSTALL.md)
- 配圖：[App Store 實機商品頁](images/keykey-ios-v137-ios01-app-store-user-iphone.png)、[台灣價格實機首頁](images/keykey-ios-v137-ios02-home-user-iphone.png)、[「玩」候選示範](images/keykey-ios-v137-ios07a-middle-candidate-iphone17pro-simulator.png)。第三張為正式 1.3.7 來源的 iPhone 模擬器畫面，引用時保留此標示。

### Android：觸控整句輸入，接上鍵盤也有自己的選字方式

琦琦 Android 版加入好打注音整句輸入，也可切換傳統注音、倉頡與簡易。觸控時能點組字格修改句中的字；選字後繼續打，文字接在句尾。自訂詞與選字學習保存在裝置上，觸控與實體鍵盤共用，長句與切換 App 時的文字保留也持續改善。

接上 USB／藍牙鍵盤後，這一波新增 **好打注音雙排選字**：上排保留組字，下排在數字鍵與候選之間切換，面板高度固定；也可依需求選用原有的浮動候選窗。不需要面板時，按「▼」收起，把空間還給 App。

1.3.7 的倉頡支援未打完選字；觸控與實體鍵盤的倉頡候選設定可分開保存。正式版可直接從 Google Play 安裝，適用於 **Android 8 以上**，App 不要求網路權限，未付費也能完整使用輸入功能。

- 圖片主標：**手機順手打，接上鍵盤也好選**
- 圖片短句：**整句輸入／句中改字／實體鍵盤雙排選字／倉頡提前選字**
- 操作重點：雙排選字預設關閉，與浮動候選窗分開使用；浮動窗呈現受系統與目標 App 支援影響。
- 安裝：[Google Play](https://play.google.com/store/apps/details?id=tw.chichi77.keykey.android)
- 教學：[Android 安裝與使用指南](../ANDROID_INSTALL.md)
- 配圖：[「玩」候選](images/keykey-android-v137-and06a-middle-candidate-pixel8pro-simulator-detail.png)、[倉頡「竹大」候選](images/keykey-android-v137-and08b-cangjie-candidates-pixel8pro-simulator-detail.png)。均為正式 1.3.7 來源的 Pixel 8 Pro 模擬器素材；目前不以這兩張圖示範實體雙排或浮動候選窗。

### Linux／Ubuntu：熟悉的整句組字，融入 Fcitx 5 桌面

在 Ubuntu，也能延續熟悉的中文輸入習慣。琦琦 Linux 版這一波加入好打注音整句組字、自訂詞與選字學習，並持續改善長句、中文標點及切換輸入法時的文字保留；需要逐字選字，也可切回傳統注音。

到了 1.3.7，設定介面使用台灣繁體中文，空白鍵開候選、選字目標與 Esc 清除整句可依習慣調整。倉頡開啟「即時候選」與「未打完也能選字」，輸入「竹大」即可從候選找「喬」，另可選用簡易輸入。

正式套件以 **Ubuntu Desktop 24.04 LTS、GNOME Shell 46、Fcitx 5、amd64** 為支援主線，提供詞庫、輸入法與 GNOME 候選面板套件。GitHub Release 與台灣 AWS CDN 都能下載，圖文指南帶你完成安裝、啟用與第一次試打。

- 圖片主標：**在 Ubuntu，也能整句順著打**
- 圖片短句：**Fcitx 5 整合／繁體中文設定／自訂詞學習／倉頡提前選字**
- 操作重點：自訂詞管理目前透過命令列；其他發行版、ARM64、IBus 與桌面環境不由本份宣傳擴大支援。
- 下載：[1.3.7 正式版與台灣 AWS 下載點](https://github.com/polobread/KeyKey/releases/tag/v1.3.7)
- 教學：[Linux／Ubuntu 安裝與使用指南](../LINUX_INSTALL.md)
- 配圖：[「玩」候選](images/keykey-linux-v137-lnx07a-middle-candidate-ubuntu2404-wayland.png)、[好打注音進階設定](images/keykey-linux-v137-lnx10-smart-options-ubuntu2404-wayland.png)。環境為 Ubuntu 24.04.5／GNOME 46／Wayland VM，文字編輯器採指南記錄的直接 Fcitx 路徑。

### FreeBSD：六平台正式支援，熟悉的注音來到 BSD 桌面

琦琦輸入法的六平台版圖，正式加入 FreeBSD。1.3.7 透過 Fcitx 5 提供好打注音、傳統注音、倉頡與簡易：可以連續組句，也能在仍可編輯的範圍內回頭選字。倉頡開啟兩個候選選項後，打到「竹大」就能從候選找「喬」。

設定介面採台灣繁體中文，提供空白鍵開候選、選字目標與 Esc 行為調整。安裝可依套件庫供應情況使用 pkg，或透過官方 **chinese/fcitx5-keykey** port 建置，再由 pkg 管理。

1.3.7 已在 **FreeBSD 15.1-RELEASE-p3、amd64、Xfce／X11、LightDM、Fcitx 5 與 Mousepad／GTK 3** 驗證。圖文指南也整理了字型、GTK 橋接、登入環境與試打步驟，讓 BSD 使用者有可跟著操作的安裝路線。套件庫可能較晚上架，請確認實際安裝版本。

- 圖片主標：**熟悉的中文輸入，也來到 FreeBSD**
- 圖片短句：**Fcitx 5／好打注音／倉頡提前選字／ports 與 pkg**
- 操作重點：FreeBSD 是本次彙整中的正式支援擴展，不宣稱六平台從 1.2.9 起就全部提供；不提供 AWS CDN 安裝包。
- 套件：[FreshPorts：chinese/fcitx5-keykey](https://www.freshports.org/chinese/fcitx5-keykey/)
- 教學：[FreeBSD 安裝與使用指南](../FREEBSD_INSTALL.md)
- 配圖：[「玩」候選](images/keykey-freebsd-v137-bsd07a-middle-candidate.png)、[倉頡「竹大」候選](images/keykey-freebsd-v137-bsd09b-cangjie-candidates.png)。均為 FreeBSD 自己的桌面實拍；保留原始字型顯示狀態。

## 短文與圖片文字

### 社群短版

琦琦輸入法 1.3.7，讓熟悉的中文輸入陪你走到六大平台。好打注音整句順著打，倉頡輸入「竹大」就能找「喬」；Mac 輕按 Shift 切換中英文，Android 新增實體鍵盤雙排選字，Windows 與 Mac 提供 200 個 Emoji。iOS、Android 正式商店可直接安裝，FreeBSD 也正式支援！

### 圖片文字組

| 圖片 | 主標 | 副標 |
|---|---|---|
| 總覽 | 熟悉的中文輸入，走到六大平台 | Windows／macOS／iOS／Android／Linux／FreeBSD |
| 好打注音 | 先順著句子打，需要時再改字 | 連續組句，在仍可編輯的位置選字 |
| 倉頡 | 打到「竹大」，就能找「喬」 | 開啟即時候選與未打完選字 |
| Mac／Windows Emoji | 用表情，接住想說的話 | 符號表加入 200 個 Emoji |
| 手機正式版 | 打開商店，就能安裝琦琦 | App Store／Google Play 正式版 1.3.7 |
| 桌面下載 | 選你方便的下載方式 | Mac／Windows／Ubuntu：GitHub Release 或台灣 AWS CDN |

### 通用下載尾段

- **Windows／macOS／Ubuntu：**依 [README 的平台下載表](../README.md#下載與發行)選擇 macOS 1.3.8 或 Windows／Ubuntu 1.3.7，各版本發布頁均提供台灣 AWS CDN 下載點。
- **iPhone／iPad：**[台灣 App Store](https://apps.apple.com/tw/app/id6807832939)。
- **Android：**[Google Play](https://play.google.com/store/apps/details?id=tw.chichi77.keykey.android)。
- **FreeBSD：**[官方 port 套件資訊](https://www.freshports.org/chinese/fcitx5-keykey/)，依指南使用 ports／pkg；套件庫版本可能較晚上架。

## 編輯核對依據

本節供改稿與查證使用，不必連同社群文案刊出。

### 版本與發布範圍

| 範圍 | 本份採用方式 |
|---|---|
| 1.2.9 | 起點包含五平台版號與桌面下載、Linux 套件發布及安裝指南整理；不把既有五排鍵盤、Linux 原生版或 iOS App 實體編輯器誤寫成這一波首創。 |
| 1.3.0～1.3.1 | 彙整整句組字、詞庫與學習、自訂詞、長句與切換改善，以及 Windows／手機倉頡與簡易。 |
| 手機中間版本～1.3.7 | 彙整正式商店發行、空白鍵選字、候選缺字過濾、Android 雙排與面板收合、倉頡未打完選字；不替沒有獨立變更紀錄的版號補造功能。 |
| FreeBSD 1.3.7 | 以正式支援及該平台驗證範圍介紹；不套用 Linux 的測試結果，也不承諾所有 pkg 分支均已有 1.3.7。 |
| 發布狀態 | 採最新 README、安裝指南、維護者已確認的商店狀態與 1.3.7 Release 的補充資訊。設定 Roadmap 的 2026-10-20 發布表已落後，不以其中的舊商店版號或「待發布」狀態覆蓋新紀錄。 |

本份只整理正式 1.3.7 以前的產品變化；macOS 1.3.8 的安裝修正另見 [CHANGELOG](../CHANGELOG.md)。開發中的 **Guanyinma** 核心、其他尚未發布工作與 Roadmap 待規劃項目均不列為已發布賣點。

### 原始碼與文件對照

| 宣傳主張 | 文件／發布依據 | 程式碼核對入口 |
|---|---|---|
| 整句組字、詞庫與學習改善 | [CHANGELOG 1.3.0／1.3.1](../CHANGELOG.md)、[1.3.0 Release](https://github.com/polobread/KeyKey/releases/tag/v1.3.0)、[1.3.1 Release](https://github.com/polobread/KeyKey/releases/tag/v1.3.1) | [共用好打注音模型說明](../DataSource/AISyntheticBigram/SMART_MANDARIN_MODEL_V1_3_1.md)、[iOS 核心](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine)、[Android 核心](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android) |
| 六平台倉頡未打完選字 | [1.3.7 Release](https://github.com/polobread/KeyKey/releases/tag/v1.3.7)、[六平台指南及截圖登記](CROSS_PLATFORM_SCREENSHOT_PLAN.md) | [桌面共用前綴候選](../Source/Shared/CangjiePrefix.h)、[iOS](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/CangjiePrefixSelection.swift)、[Android](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/CangjiePrefixSelection.java)、[Linux／FreeBSD](../Source/Loaders/Linux-IME/adapters/fcitx5/fcitx5_engine.cpp) |
| Mac Shift、英文模式與 Emoji | [macOS 指南](../MACOS_INSTALL.md)、[CHANGELOG 1.3.7](../CHANGELOG.md) | [一般設定](../Source/PreferenceApplications/OSX/TakaoGlobal.m)、[符號表](../Source/Loaders/OSX-IMK) |
| Windows Caps Lock、選字鍵、組字長度及自訂詞 | [Windows 指南](../WINDOWS_INSTALL.md)、[CHANGELOG 1.3.0／1.3.1／1.3.7](../CHANGELOG.md) | [設定介面](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml)、[設定邏輯](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml.cs) |
| iOS 權限、候選及 App 實體編輯器 | [iOS 指南](../IOS_INSTALL.md)、[iOS 技術文件](../Source/Loaders/iOS-Keyboard/README.md) | [extension 權限](../Source/Loaders/iOS-Keyboard/Keyboard/Info.plist)、[App 實體編輯器](../Source/Loaders/iOS-Keyboard/ContainerApp/HardwareKeyboardEditorViewController.swift) |
| Android 雙排、浮動窗與面板收合 | [Android 指南](../ANDROID_INSTALL.md)、[CHANGELOG Android 1.3.5／1.3.6](../CHANGELOG.md) | [設定文字與使用條件](../Source/Loaders/Android-IME/app/src/main/res/values/strings.xml)、[設定入口](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/SettingsActivity.java) |
| Linux 設定、整合與支援範圍 | [Linux 指南](../LINUX_INSTALL.md)、[CHANGELOG](../CHANGELOG.md) | [Fcitx 5 frontend](../Source/Loaders/Linux-IME/adapters/fcitx5/fcitx5_engine.cpp) |
| FreeBSD 支援、安裝與實拍 | [FreeBSD 指南](../FREEBSD_INSTALL.md)、[1.3.7 Release 的 FreeBSD 建置與安裝補充](https://github.com/polobread/KeyKey/releases/tag/v1.3.7) | [Linux／FreeBSD 共用 frontend](../Source/Loaders/Linux-IME)、[設定支援表](CROSS_PLATFORM_SETTINGS_ROADMAP.md) |

歷史基準另見 [1.2.9 Release](https://github.com/polobread/KeyKey/releases/tag/v1.2.9)。正式版下載入口依 [README 的平台下載表](../README.md#下載與發行)維護；每個平台連到提供對應安裝包的 Release。

### 使用文案與圖片時保留的差異

- 倉頡候選順位依平台、字表與學習結果而異，文案使用「找到喬」，不寫成固定第幾項；手機觸控的新設定預設開啟，桌面與手機實體鍵盤須自行開啟，既有設定保留。
- 好打注音使用共用詞庫，不代表六平台介面、所有設定與每個候選順序完全相同。使用者自訂詞與學習資料也不會跨裝置自動同步。
- 手機觸控保留最近九個音節供修改；Mac／Windows 可調整組字長度，Linux 與手機實體的行為另依指南。不要宣稱整篇文章都能一直回頭選字。
- iOS 外接鍵盤只在琦琦 App 前景編輯器使用，不宣傳成能在所有 App 接管 USB／藍牙鍵盤。Android 雙排與浮動窗為不同模式，不同時開啟。
- 200 個 Emoji 是本波 Mac／Windows 符號表的重點，不泛稱六平台都新增相同符號面板。
- 桌面每週更新檢查只通知；Mac／Windows 要在使用者選擇更新後才下載及安裝，Linux／FreeBSD 走下載頁及套件管理器。不寫「背景自動安裝」或「已驗證所有更新流程」。
- Windows 10 有建置來源但實機仍待驗證；Linux 以 Ubuntu 24.04／GNOME 46／Fcitx 5／amd64 為支援主線；FreeBSD 保留已驗證桌面範圍。避免「所有 Windows／Linux／BSD 都通用」的說法。
- 模擬器畫面保留來源標示；FreeBSD 不放 AWS CDN 下載按鈕。配圖與來源詳見[跨平台截圖清單](CROSS_PLATFORM_SCREENSHOT_PLAN.md)。
