# 跨平台輸入法設定支援表與 Roadmap

下表的商店、安裝包及公告狀態為 2026-11-09 核對的 1.5.0 紀錄。現行六平台原始碼版號為 1.5.2。六平台使用 Guanyinma（觀音嬤）Rust 共用核心，五個 frontend 共用 **1.5.0 好打注音模型**的 `KeyKey.db`。資料來源與雜湊見[模型 manifest](../DataSource/AISyntheticBigram/smart-mandarin-model-manifest.json)。新版各平台驗收條件見 [1.5.1 發布準備](CROSS_PLATFORM_V1_5_1_RELEASE.md)。

本表以目前可進入的輸入法設定、設定讀寫與 frontend 實作為依據，供後續功能規劃使用。功能已存在於原始碼，不等於已建置、已安裝、通過實機驗收或正式推出。本文後段依功能引入或關鍵調整的提交日期整理開發時間表。

## 閱讀方式與平台範圍

| 標記 | 意義 |
|---|---|
| ✓ | 提供可操作的設定或管理入口 |
| 固定 | 已有相關行為，但不能用對應設定調整 |
| 外部 | 由系統、Fcitx 或命令列管理，沒有相同的琦琦設定介面 |
| — | 沒有提供此項設定；備註另說明相關功能是否存在 |
| 不適用 | 該輸入方式不適用，不當作待補功能 |
| 待驗收 | 原始碼已有實作，仍須補該平台的實際環境驗證 |

「Android 實體」包含 USB／藍牙鍵盤搭配原生 IME；「iOS 實體」**只限琦琦容器 App 前景的實體鍵盤編輯器**，不能在其他 App 接管外接鍵盤。下表的 iOS 實體欄全部受此限制。

Linux 與 FreeBSD 共用 Fcitx 5 frontend，依使用者要求合併一欄；相同原始碼不代表相同驗收程度。Linux 的 X11、GNOME Wayland 與 FreeBSD 原生桌面須分別驗證；FreeBSD 共用 Linux 產品版號，實際套件上架與原生測試結果仍須分別確認。

下表記錄 2026-11-09 核對的交付狀態。實際可取得的手機與 FreeBSD 版本以各發行入口為準。

| 平台 | 來源版號 | 交付狀態與入口 |
|---|---|---|
| macOS | 1.5.0 | Apple Silicon 安裝包已發布至 [GitHub Release／AWS CDN](https://github.com/polobread/KeyKey/releases/tag/v1.5.0#台灣-aws-下載點) |
| Windows TSF | 1.5.0 | x64 安裝程式及 x64／x86 ZIP 已發布至 [GitHub Release／AWS CDN](https://github.com/polobread/KeyKey/releases/tag/v1.5.0#台灣-aws-下載點) |
| Linux | 1.5.0 | Ubuntu 24.04 amd64 的 Fcitx 5 套件與 GNOME 面板擴充已發布至 [GitHub Release／AWS CDN](https://github.com/polobread/KeyKey/releases/tag/v1.5.0#台灣-aws-下載點) |
| FreeBSD | 1.5.0 | 共用 Linux frontend 與正式更新公告。透過 [ports／pkg](../FREEBSD_INSTALL.md) 安裝，套件可能較晚上架，1.5.0 原生驗收待確認 |
| Android（虛擬／實體） | 1.5.0 | [Google Play](https://play.google.com/store/apps/details?id=tw.chichi77.keykey.android) 正式管道 100% 推出，versionCode `1005000` |
| iOS（虛擬／App 內實體） | 1.5.0 | build 118 已送審，核對時等待審查。公開版本見 [App Store](https://apps.apple.com/tw/app/id6807832939) |

## 一般、輸入法與鍵盤配置

來源：[macOS 一般設定](../Source/PreferenceApplications/OSX/TakaoGlobal.m)、[Windows 設定](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml)、[Linux／FreeBSD 設定](../Source/Loaders/Linux-IME/adapters/fcitx5/fcitx5_engine.cpp)、[Android 設定](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/SettingsActivity.java)、[iOS App 設定](../Source/Loaders/iOS-Keyboard/ContainerApp/SetupViewController.swift)。

| 設定項目 | macOS | Windows | Linux／FreeBSD | Android 虛擬 | iOS 虛擬 | Android 實體 | iOS 實體 |
|---|---|---|---|---|---|---|---|
| 選用好打注音 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 選用傳統注音 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 選用倉頡 | ✓ | ✓ | ✓ Fcitx 輸入法 | ✓ | ✓ | ✓ | ✓ |
| 選用簡易 | ✓ | ✓ | ✓ Fcitx 輸入法 | ✓ | ✓ | ✓ | ✓ |
| 在輸入法選單顯示／隱藏個別中文輸入法 | ✓ | ✓ | 外部 Fcitx 輸入法清單 | — | — | — | — |
| 啟動時預設中文／英文 | ✓ | ✓ | ✓ | — | — | — | — |
| 單按 Shift 切換中英文的開關 | ✓ | 固定可切換 | ✓ | 不適用 | 不適用 | — | — |
| Ctrl+反斜線切換中英文的開關 | ✓ | ✓ | ✓ | 不適用 | 不適用 | — | — |
| Ctrl+Alt+逗號開啟符號表的開關 | — | ✓ 中文模式限定 | — | 不適用 | 不適用 | — | — |
| 中文模式忽略 Caps Lock 的開關 | — | ✓ 預設開啟 | ✓ 預設關閉 | 不適用 | 不適用 | ✓ 一般／浮動，預設關閉 | ✓ App 編輯器，預設關閉 |
| 實體鍵盤類型對應（非注音排列） | ✓ 系統鍵盤配置 | 固定美式 | 外部系統／Fcitx | 不適用 | 不適用 | 外部 Android | 外部 iOS |
| 注音配置：標準 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 注音配置：許氏 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 注音配置：倚天 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 注音配置：倚天 26 鍵 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 注音配置：漢語拼音 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ App 實體編輯器 |
| 簡體中文輸出 | — | ✓ 四種輸入法 | ✓ 繁轉簡 | ✓ | ✓ | ✓ 獨立保存 | ✓ App 編輯器獨立保存 |

手機的好打注音與傳統注音可在設定選擇五種鍵位。除標準與許氏，1.5.1 加入漢語拼音，1.5.2 加入倚天與倚天 26 鍵。Android 的觸控與實體鍵盤都可用，iOS 也可在 App 的實體鍵盤編輯器選用。「啟動時預設中文／英文」是另一項偏好，不能把切換輸入法或依欄位類型自動選擇英文／數字視為支援該設定。Windows 固定保留 Shift 切換；Linux／FreeBSD 來源已提供獨立啟用開關。

## 注音與好打注音進階設定

來源：[macOS 好打注音](../Source/PreferenceApplications/OSX/TakaoSmartPhonetic.m)、[Windows 設定與選項](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml.cs)、[Linux／FreeBSD frontend](../Source/Loaders/Linux-IME/adapters/fcitx5/fcitx5_engine.cpp)、[Android README](../Source/Loaders/Android-IME/README.md)、[iOS README](../Source/Loaders/iOS-Keyboard/README.md)。

| 設定項目 | macOS | Windows | Linux／FreeBSD | Android 虛擬 | iOS 虛擬 | Android 實體 | iOS 實體 |
|---|---|---|---|---|---|---|---|
| 好打注音：空白鍵開候選／使用空白鍵選字 | ✓ | ✓ | ✓ | ✓ | ✓ App／鍵盤可調 | ✓ 獨立保存 | ✓ 獨立保存 |
| 好打注音：選字目標在游標前方／後方 | ✓ | ✓ | ✓ | — 點字指定 | — 點字指定 | ✓ 一般／浮動 | ✓ App 編輯器 |
| 好打注音：選字按鍵配置 | ✓ | ✓ 三組 | ✓ | 不適用 觸控點選 | 不適用 觸控點選 | 固定 1–9 | 固定 1–9 |
| 好打注音：組字區長度 | ✓ 10–20 | ✓ 10–20 | ✓ 10–20 | 固定九／十音節，省略聲調時十一／十二音節 | 固定九／十音節，省略聲調時十一／十二音節 | ✓ 一般／浮動 10–20；雙排維持九／十 | ✓ App 編輯器 10–20 |
| 好打注音：省略聲調 | ✓ 五種鍵位，預設關閉 | ✓ 五種鍵位，預設關閉 | ✓ 五種鍵位，預設關閉 | ✓ 五種鍵位，預設關閉 | ✓ 五種鍵位，預設關閉 | ✓ 一般／浮動，預設關閉 | ✓ App 編輯器，預設關閉 |
| 好打注音：Esc 清除整句的開關 | ✓ | ✓ | ✓ | 不適用 | 不適用 | ✓ 一般／浮動 | ✓ App 編輯器 |
| 好打注音：使用上下文選字（Bigram）開關 | 固定開啟 | 固定開啟 | ✓ | ✓ | ✓ | ✓ 獨立保存 | ✓ 獨立保存 |
| 注音：全字庫／Big5 字集限制 | ✓ | ✓ | ✓ 注音與符號過濾 | — | — | — | — |
| 重設好打注音學習紀錄，保留自訂詞 | ✓ 輸入法選單 | ✓ | ✓ 圖形／CLI | ✓ | ✓ | ✓ 共用學習資料 | ✓ 獨立學習資料 |

Windows 的三組選字鍵為 `12345678`、`asdfghjk`、`asdfzxcv`。Linux／FreeBSD 的字集設定是 Big5-HKSCS 過濾，不能視為與其他桌面平台完全相同的編碼範圍。

Android 實體一般模式及 iOS App 實體編輯器預設選游標右側的字，游標在句尾時選最後一字，可在實體頁改選游標前方。一般實體預設保留十個完成音節，第十一個完成時擠出前段完整詞，可調為 10～20 音節。啟用 Android 好打注音雙排選字後，選字與九／十音節組字仍沿用觸控流程。

手機未提供桌面的字集限制開關；iOS／Android 已自動隱藏系統字型不能顯示的候選，此為固定行為，與使用者選擇 Big5 字集不同。

## 手機虛擬與實體設定分頁

App 提供獨立的虛擬與實體設定頁。Android 首頁在啟用與選用輸入法後直接顯示「琦琦輸入法設定」區塊，提供「虛擬鍵盤設定」、「實體鍵盤設定」、自訂詞、關聯詞詞庫與重設學習入口，不再先開一頁總覽。iOS 首頁同樣直接提供「虛擬鍵盤調整設定」與「實體鍵盤調整設定（App 編輯器）」入口，以及共用的自訂詞、關聯詞詞庫與重設學習入口，不再經過「輸入法設定」總覽頁。觸控「設」進入虛擬頁，Android 實體四鍵面板的「設定」進入實體頁。iOS 實體設定只適用琦琦 App 內的編輯器，不能在 Safari、LINE 等其他 App 接管實體鍵盤。

iOS 設定以可收合群組整理，同一頁展開選項。App 虛擬頁與鍵盤「設」提供「注音與選字」、「倉頡與簡易」、「外觀與操作」；App 實體頁只顯示已有選項的前兩組。倉頡／簡易的開關直接列在群組內，倉頡標點以分段選項切換，沒有第二層選單。

輸入法、注音配置、繁簡輸出、空白選字，以及倉頡／簡易操作選項各自保存。升級沿用舊值，之後兩組不互相改寫。實體省略聲調是新接上的選項，預設關閉，不繼承舊觸控省略聲調的開啟狀態。關聯詞、自訂詞與學習資料維持原有範圍；Android 共用本機資料，iOS App 與 extension 的學習仍各自私有。

Android 一般底部候選列／浮動窗與 iOS App 編輯器接入既有 Guanyinma 選項：游標前／後選字、選字後回句尾、Esc 清除整句、10～20 音節組字長度、上下文選字、中文忽略 Caps Lock 及 Shift 字母大寫。選字鍵維持現有 1–9，不新增候選數、快捷鍵系統或候選窗外觀。回句尾選項也代表後續新音節接在句尾；不勾選時保留核心的游標編輯行為。

Android 雙排保留九格與九／十音節邊界，不套用上述桌面進階行為；不相容設定在雙排時停用並保留原值。停用控制旁的 ⓘ 仍可閱讀，各進階選項分別交代作用與適用範圍。浮動窗與雙排、數字符號列及底部空間仍沿用原有互斥規則，宿主無法提供有效游標位置時仍回到一般候選列。

iOS 維持 App 預設與修訂套用機制，不新增雙向同步或完整取用需求。鍵盤「設」可調整當下虛擬設定；「套用到鍵盤」只放在虛擬設定頁頂端，重新發布虛擬鍵盤預設及關聯詞詞庫，於鍵盤下次顯示時套用；不重套實體編輯器的輸入設定，兩組套用修訂獨立保存。首頁與實體子頁不提供這個按鈕，返回或重新開啟 App 編輯器就會讀取設定，不必切回虛擬鍵盤；輸入規則仍等原組字完成後套用。高度仍由鍵盤內拖曳調整、直橫式分開儲存，不屬於 App 預設套用範圍。

設定說明由各列或群組標題旁的 ⓘ 開啟，不常駐增加小字。繁簡輸出說明保留組字與候選使用繁體的界線；「字體大小」說明標準保留英文鍵位提示、較大尺寸隱藏提示。iOS 的學習重設在確認前交代 App 編輯器與鍵盤的各自範圍。

Android 候選底色與面板觸控震動依虛擬／實體分開保存，一次性遷移保留原值；實體組適用單排、雙排與浮動候選窗的面板觸控，實際外接按鍵不因此震動。iOS 實體編輯器配色仍維持既有固定外觀。

## 倉頡與簡易

來源：[macOS 倉頡](../Source/PreferenceApplications/OSX/TakaoCangjie.m)、[macOS 簡易](../Source/PreferenceApplications/OSX/TakaoSimplex.m)、[Windows 設定](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml)、[Linux／FreeBSD 倉頡設定](../Source/Loaders/Linux-IME/tools/cangjie_settings.py)、[Android 設定儲存](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/ChineseInputMethodSettings.java)、[iOS 設定儲存](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/ChineseInputMethod.swift)。

| 設定項目 | macOS | Windows | Linux／FreeBSD | Android 虛擬 | iOS 虛擬 | Android 實體 | iOS 實體 |
|---|---|---|---|---|---|---|---|
| 倉頡：即時候選 | ✓ | ✓ | ✓ Fcitx 設定頁 | ✓ | ✓ | ✓ 獨立保存 | ✓ 獨立保存 |
| 倉頡：未打完也能選字（前綴候選） | ✓ | ✓ | ✓ Fcitx 設定頁 | ✓ | ✓ | ✓ 獨立保存 | ✓ 獨立保存 |
| 倉頡：錯碼清除 | ✓ | ✓ | ✓ Fcitx 設定頁 | ✓ | ✓ | ✓ 獨立保存 | ✓ 獨立保存 |
| 倉頡：滿五碼查詢／組字 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ 獨立保存 | ✓ 獨立保存 |
| 倉頡：依選字紀錄排序／動態字頻 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ 獨立保存 | ✓ 獨立保存 |
| 倉頡：標點全形／混合／半形 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ 獨立保存 | ✓ 獨立保存 |
| 倉頡：全字庫／Big5 限制 | ✓ | ✓ | — 無對等倉頡專用開關 | — | — | — | — |
| 簡易：即時候選 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ 獨立保存 | ✓ 獨立保存 |
| 簡易：錯碼清除 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ 獨立保存 | ✓ 獨立保存 |
| 簡易：全字庫／Big5 限制 | ✓ | ✓ | — 無對等簡易專用開關 | — | — | — | — |

倉頡「未打完也能選字」依賴即時候選；即時候選與錯碼清除互斥。桌面與手機實體的前兩項新設定缺值時預設關閉；手機虛擬缺值時預設開啟，已有明確設定則保留。

手機的倉頡與簡易選項依虛擬／實體分開保存，包含即時候選、前綴候選、錯碼清除、滿碼查詢、選字排序與標點。升級時從各自原本生效的選項遷移，不重設舊選擇，也不因此複製詞庫或學習資料。

## 候選外觀、聲音與手機鍵盤操作

來源：[macOS 一般設定](../Source/PreferenceApplications/OSX/TakaoGlobal.m)、[Windows 設定](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml)、[Linux／FreeBSD 設定](../Source/Loaders/Linux-IME/adapters/fcitx5/fcitx5_engine.cpp)、[Android 設定文字](../Source/Loaders/Android-IME/app/src/main/res/values/strings.xml)、[iOS 鍵盤設定](../Source/Loaders/iOS-Keyboard/Keyboard/SettingsPanel.swift)、[iOS 實體編輯器](../Source/Loaders/iOS-Keyboard/ContainerApp/HardwareKeyboardEditorViewController.swift)。

| 設定項目 | macOS | Windows | Linux／FreeBSD | Android 虛擬 | iOS 虛擬 | Android 實體 | iOS 實體 |
|---|---|---|---|---|---|---|---|
| 候選窗垂直／水平 | ✓ | ✓ | ✓ 交由面板呈現 | 固定候選列 | 固定候選列 | ✓ 浮動窗限定 | 固定直排 |
| 候選窗大小／比例 | ✓ | ✓ | 外部 Fcitx／桌面面板 | — | — | — | — |
| 候選反白／底色 | ✓ 四色＋自訂 | ✓ 四色 | 外部 Fcitx／桌面面板 | ✓ 四色、獨立保存 | ✓ 四色 | ✓ 四色、獨立保存 | 固定紫色 |
| 輸入錯誤提示聲開關 | ✓ | ✓ | ✓ | — | — | — | — |
| 錯誤提示聲音效檔案／試聽 | ✓ | — | — | 不適用 | 不適用 | 不適用 | 不適用 |
| 觸控按鍵音開關 | 不適用 | 不適用 | 不適用 | — | ✓ | 不適用 | 不適用 |
| 按鍵／候選面板觸控震動時間 | 不適用 | 不適用 | 不適用 | ✓ 0–100 ms、獨立保存 | — 目前權限方案受限 | ✓ 僅面板觸控、獨立保存 | 不適用 |
| 顯示觸控按鍵預覽的開關 | 不適用 | 不適用 | 不適用 | ✓ | 固定顯示 | 不適用 | 不適用 |
| 直式／橫式虛擬鍵盤高度與底部留白 | 不適用 | 不適用 | 不適用 | ✓ 即時拖曳、分方向儲存 | ✓ 即時拖曳、分方向儲存 | 不適用 | 不適用 |
| 觸控版面：標準／對齊／對齊分離 | 不適用 | 不適用 | 不適用 | ✓ | ✓ | 不適用 | 不適用 |
| 觸控鍵帽間隔：小／中／大 | 不適用 | 不適用 | 不適用 | ✓ | ✓ | 不適用 | 不適用 |
| 觸控鍵盤字體：標準／中／大／特大 | 不適用 | 不適用 | 不適用 | ✓ | ✓ | 不適用 | 不適用 |
| 觸控刪除鍵位置：右側／下方 | 不適用 | 不適用 | 不適用 | ✓ | ✓ | 不適用 | 不適用 |
| 預留底部切換語言空間 | 不適用 | 不適用 | 不適用 | 依系統控制鍵實際占用自動預留 | — 系統安全區 | ✓ 可手動開關 | 不適用 |
| 整合底部控制鍵 | 不適用 | 不適用 | 不適用 | ✓ 預設關閉 | — | 不適用 | 不適用 |
| 使用浮動候選字窗 | 固定桌面候選窗 | 固定桌面候選窗 | 固定 Fcitx 面板 | 不適用 | 不適用 | ✓ | — App 內固定候選區 |
| 實體鍵盤顯示虛擬數字與符號鍵 | 不適用 | 不適用 | 不適用 | 不適用 | 不適用 | ✓ | — |
| 實體鍵盤好打注音雙排選字 | 不適用 | 不適用 | 不適用 | 不適用 | 不適用 | ✓ | — |

標準版面採交錯排列。對齊分離將主按鍵分為左右各六欄，兩側各有空白鍵，組字與候選列也採分離配置。iOS 支援 iPhone、iPad 和 iPhone Duo 內螢幕，Android 支援手機、平板和摺疊裝置，兩者均可直式、橫式使用。Duo 由使用者選擇分離版面。iOS 預設標準版面、刪除鍵在右側，Android 預設對齊版面、刪除鍵在下方。兩者均預設小間隔與標準字體，刪除鍵可與 Shift 互換。

Android 的「整合底部控制鍵」可將收鍵盤與輸入法切換入口整合至觸控鍵盤。在系統支援時可收起輸入法控制列，長按「設」仍可開啟系統輸入法清單。

Android 浮動候選窗開啟時，雙排選字、虛擬數字符號鍵與實體底部空間選項停用並保留值；取得不到可用游標位置或無法附掛視窗時，會退回一般候選列。這是條件式支援，不能把三種面板當成可同時開啟。

iOS App 實體編輯器使用固定紫色與直排候選，支援 Forward Delete 刪除游標右側的組字或已確認文字，並支援按住連續刪除。Android 實體 Delete 已修正刪除組字後舊字再次出現的問題。

## 關聯詞、自訂詞與資料管理

來源：[macOS 詞彙管理](../Source/PreferenceApplications/OSX/TakaoPhrases.m)、[macOS 自訂詞編輯器](../Source/Utilities/PhraseEditor/OSX/PEController.m)、[Windows 設定](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml)、[Linux 命令列工具](../Source/Loaders/Linux-IME/tools/smart-mandarin-phrases.cpp)、[Android 自訂詞](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/UserPhrasesActivity.java)、[iOS App 設定與自訂詞](../Source/Loaders/iOS-Keyboard/ContainerApp/SetupViewController.swift)。

| 設定項目 | macOS | Windows | Linux／FreeBSD | Android 虛擬 | iOS 虛擬 | Android 實體 | iOS 實體 |
|---|---|---|---|---|---|---|---|
| 逐項啟用／停用關聯詞來源 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ 共用 | ✓ |
| 好打注音自訂詞新增／編輯／刪除 | ✓ | ✓ | ✓ 圖形／CLI | ✓ | ✓ App 管理 | ✓ 共用 | ✓ App 管理 |
| 自訂詞匯入／匯出 | ✓ | ✓ | ✓ Guanyinma JSON | ✓ | ✓ App 管理 | ✓ 共用 | ✓ App 管理 |
| 學習資料隨使用者資料庫匯入／匯出 | ✓ | ✓ | ✓ 完整 Guanyinma JSON | — 僅自訂詞 | — 僅自訂詞 | — 僅自訂詞 | — 僅自訂詞 |
| 自訂詞本地讀音輔助／逐字選讀音 | ✓ 編輯讀音 | ✓ 新增時查詞與逐字選擇 | ✓ 模型讀音建議 | — 手動讀音 | — 手動讀音 | — 手動讀音 | — 手動讀音 |

關聯詞來源選擇控制輸入首字後的詞尾建議，**不是切換好打注音的 Bigram 訓練來源或正式詞庫**。

Android 虛擬／實體共用本機自訂詞與學習資料。iOS 自訂詞由 App Group 提供，但虛擬鍵盤和 App 實體編輯器的學習資料各自儲存；App 無法讀回鍵盤私有偏好。App 送出的設定與重設要求在鍵盤下次開啟時套用，不能寫成雙向即時同步。

## 診斷、更新與關於

來源：[Windows 設定](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml)、[macOS 更新設定](../Source/PreferenceApplications/OSX/TakaoUpdate.m)、[Linux／FreeBSD 更新設定](../Source/Loaders/Linux-IME/tools/update_notify_gui.py)、[桌面更新狀態](../update/README.md)。

| 設定項目 | macOS | Windows | Linux／FreeBSD | Android 虛擬 | iOS 虛擬 | Android 實體 | iOS 實體 |
|---|---|---|---|---|---|---|---|
| 使用者可開關的診斷記錄 | — | ✓ 三天到期 | — | — | — | — | — |
| 每週檢查新版並通知 | ✓ 條件式啟用 | ✓ 條件式啟用 | ✓ 通知／下載頁 | 外部 Google Play | 外部 App Store | 外部 Google Play | 外部 App Store |
| 接收 beta 測試版通知 | ✓ | ✓ | ✓ | 外部商店測試管道 | 外部 TestFlight | 外部商店測試管道 | 外部 TestFlight |
| 立即檢查更新 | ✓ 條件式啟用 | ✓ 條件式啟用 | ✓ | 外部 Google Play | 外部 App Store | 外部 Google Play | 外部 App Store |
| 重新安裝目前版本的官方下載頁入口 | — | ✓ | — | 外部 Google Play | 外部 App Store | 外部 Google Play | 外部 App Store |
| 關於／版本／授權資訊入口 | ✓ | ✓ | ✓ | ✓ App | ✓ App | ✓ App | ✓ App |
| 一次付費支持 | 不適用 | 不適用 | 不適用 | ✓ App | ✓ App | ✓ 同 App | ✓ 同 App |
| 恢復購買按鈕 | 不適用 | 不適用 | 不適用 | — 由 Google Play 查詢既有購買 | ✓ App | — 同 App | ✓ 同 App |

桌面正式更新公告已同步至 1.5.0。macOS arm64 與 Windows x64 提供簽章更新套件，Windows x86 公告提供手動下載 ZIP。Linux／FreeBSD 共用公告並開啟官方下載頁，FreeBSD 依 ports／pkg 更新，套件可能較公告晚上架。桌面排程只通知，使用者確認後才進入下載或安裝。

## 功能缺口與後續驗收

以下保留原規劃編號。已交付功能與各平台原生驗收分開列出，候選功能的日期在確認排程後更新。

| 候選 | 建議順序 | 平台與缺口 | 完成條件 | 預計日期 |
|---|---|---|---|---|
| R01 手機實體鍵盤進階設定 | 已接既有核心選項 | 獨立設定頁已提供游標目標、回句尾、Esc、上下文、Caps Lock 與 Shift 選項；選字鍵維持 1–9 | 按 profile 隔離及舊值遷移驗證，Android 雙排保留原策略；不另開發快捷鍵與候選介面 | 1.5.2 |
| R02 Linux／FreeBSD 詞彙管理介面 | 已實作／Linux 已發布 | 圖形 CRUD、讀音建議、重設及完整 JSON 備份／匯入已接上 | 保存最終套件的介面操作證據，補 FreeBSD 原生驗收 | 各平台另定 |
| R03 Linux／FreeBSD 倉頡與簡易設定補齊 | 已實作／Linux 已發布 | Fcitx 頁已提供動態詞頻、滿碼、標點、即時候選與錯碼開關 | 依各平台字型、最終產物與宿主保存驗收紀錄 | 各平台另定 |
| R04 iOS 實體編輯器外觀設定 | 一般 | App 已有候選底色設定，但實體編輯器固定紫色／直排 | 實體編輯器讀取候選配色並提供排列／字級；旋轉及小螢幕可用 | 待定 |
| R05 手機注音配置補齊 | 已實作 | Android 與 iOS 已提供標準、許氏、漢語拼音、倚天、倚天 26 鍵 | 兩端皆驗證帶聲調和觸控好打注音省略聲調。Android 實體鍵盤與 iOS App 實體編輯器的鍵位解析已通過接合測試 | 1.5.2 |
| R06 手機自訂詞讀音輔助 | 一般 | Windows 已能查本地讀音；手機仍手動輸入 | 本地查詞、逐字破音字選擇、缺字提示；不自動覆蓋已編輯讀音 | 待定 |
| R07 中英啟動模式與 Shift 開關 | 一般 | 手機缺啟動模式偏好；Windows 的 Shift 切換無獨立開關 | 明確區分啟動偏好、欄位提示與即時模式，切換先保留組字 | 待定 |
| R08 macOS／手機簡體中文輸出 | 手機已有／macOS 待補 | Android／iOS 已提供繁轉簡，本次分開保存虛擬／實體選擇；macOS 仍無對等設定 | 各平台分別驗證設定與切換邊界，組字、候選及學習維持繁體 | 各平台另定 |
| R09 iOS 虛擬鍵盤按鍵預覽 | 一般 | 目前固定顯示按鍵預覽，缺關閉選項 | 分別檢查直式、橫式與 iPad 的按鍵點擊回饋 | 待定 |
| R10 上下文選字開關評估 | 手機已接既有核心選項 | Android／iOS 虛擬與實體各有選項；桌面沿用各自現況 | 預設維持開啟，關閉不改正式詞庫或學習資料 | 1.5.2 |
| R11 跨平台學習資料可攜性 | 研究 | 手機只匯入自訂詞；iOS 虛擬／實體學習分離 | 先定格式、權限與衝突規則，再評估可支援範圍 | 待定 |
| R12 桌面原生與安裝驗收 | 依平台補齊 | macOS、Windows、Linux 的 1.5.0 安裝包已發布，FreeBSD 與 Linux 共用公告 | 核對 macOS 安裝／升級、Windows x64／x86 宿主、Linux Wayland 及 FreeBSD 原生桌面紀錄 | 各平台另定 |
| R13 組字長度與選字鍵配置 | 部分接線 | Android 一般／浮動與 iOS App 編輯器可調 10～20 音節；選字鍵維持現有 1–9 | 不改雙排格數、候選角標及快捷鍵；選字鍵擴充另行規劃 | 1.5.2 |

iOS 在其他 App 接管 USB／藍牙鍵盤受系統 extension API 限制，不列成可承諾補齊的功能。若規劃震動、App／鍵盤雙向設定或學習同步，須先評估是否改變目前不要求「完整取用」的權限方案。

macOS 舊 XIB 內的一點通、通用表格與外掛等歷史／條件式頁面，不因檔案仍存在就列為標準安裝已支援功能；若要納入 roadmap，須先確認目前安裝內容及可進入入口。

## 功能開發時間表

日期取自功能引入或關鍵調整的 Git commit 提交時間，統一換算為台灣時區，以 `YYYY-MM-DD` 顯示並由新到舊排列。日期表示開發紀錄中的加入或調整時間，正式推出狀態請看前面的平台摘要；同一功能的後續修正另記於備註。

| 日期 | 功能／受影響平台 | 備註 |
|---|---|---|
| 2026-11-17 | Android／iOS 倚天、倚天 26 鍵與共用鍵盤計算 | 手機提供五種注音鍵位，觸控好打注音均支援帶聲調及省略聲調 |
| 2026-11-06 | iOS App 實體編輯器 Forward Delete | 可刪除游標右側的組字與文字，按住連續刪除 |
| 2026-11-05 | iOS／Android 對齊分離版面 | 左右各六欄、雙空白鍵與分離組字候選 |
| 2026-11-03 | iPhone Duo 內螢幕與行動鍵盤外觀設定 | iOS／Android 獨立調整版面、鍵帽間隔、字體與刪除鍵位置 |
| 2026-10-29 | 六平台切換至 Guanyinma 共用核心 | Linux／FreeBSD 共用 Fcitx 5 frontend，各平台保留原生設定與文字宿主 |
| 2026-10-20 | macOS 獨立英文、Shift 開關與啟動模式 | 可設定啟動時中文／英文 |
| 2026-10-20 | Windows 三組選字鍵、組字長度滑桿 | 進階設定的控制介面調整 |
| 2026-10-19 | Windows 中文忽略 Caps Lock | 中文模式預設開啟 |
| 2026-10-18 | macOS Emoji 與符號表比例 | 符號表加入 Emoji 並跟隨候選窗比例 |
| 2026-10-18 | 桌面倉頡即時／前綴候選 | macOS、Windows、Linux；FreeBSD 共用實作，另需原生驗收 |
| 2026-10-18 | 手機虛擬倉頡前綴候選 | Android／iOS 虛擬鍵盤 |
| 2026-10-18 | 手機實體倉頡前綴候選 | 虛擬／實體設定分開保存；iOS 僅 App 編輯器 |
| 2026-10-18 | 手機倉頡前綴依賴即時候選、恢復錯碼互斥 | 前綴候選的配套約束 |
| 2026-10-17 | Linux／FreeBSD 空白開候選、游標目標、Esc 整句 | 好打注音進階設定 |
| 2026-10-17 | 桌面改每週檢查 | 2026-10-18 修正排程保存；只通知，不預先下載 |
| 2026-10-17 | Windows 可關閉的符號表快捷鍵 | 中文模式限定 |
| 2026-10-17 | Android 實體好打雙排選字 | 同日調整為固定數字列，不隨候選開關改變高度 |
| 2026-10-17 | Android 實體候選面板收起 | 保留組字後收起面板 |
| 2026-10-15 | 桌面 beta 通知開關 | macOS、Windows、Linux；通知預設關閉 |
| 2026-10-15 | 手機空白鍵選字開關 | Android／iOS；虛擬與實體共用設定 |
| 2026-10-15 | 手機缺字候選過濾／重設快取 | Android／iOS 的固定行為 |
| 2026-10-14 | Linux／FreeBSD 更新通知 | feed 與平台發布驗收另確認 |
| 2026-10-11 | Windows 同版本重新安裝下載頁 | 只開官方下載頁 |
| 2026-10-10 | Windows 診斷記錄 | 使用者開啟後記錄三天，自動到期 |
| 2026-10-10 | macOS／Windows 更新基礎 | 服務啟用與發布驗收另確認 |
| 2026-10-04 | Windows 進階注音、讀音輔助、符號表、簡體輸出 | 四種輸入法與對應設定 |
| 2026-10-02 | 手機倉頡／簡易及選項 | Android／iOS；前綴候選於後續加入 |
| 2026-09-29 | Android 上下文選字開關 | 其他 frontend 是否補齊列為 R10 |
| 2026-09-28 | Android 實體虛擬數字／符號列 | 與浮動候選互斥 |
| 2026-09-28 | macOS／手機許氏配置 | 此為這些平台加入配置的紀錄 |
| 2026-09-25 | Windows TSF 好打注音與自訂詞設定 | 設定、模式切換與自訂詞介面整合 |
| 2026-09-25 | 手機實體好打編輯 | Android 實體鍵盤與 iOS App 編輯器 |
| 2026-09-24 | Linux 好打注音、自訂詞與學習 | 自訂詞介面仍為 CLI |
| 2026-09-24 | 手機虛擬好打、自訂詞、匯入／匯出與學習 | Android／iOS |
| 2026-09-19 | Android 分段震動時間、鍵盤高度 | 直式／橫式高度分開設定 |
| 2026-09-17 | Android 按鍵預覽等鍵盤控制 | 此為既有鍵盤控制的擴充紀錄 |
| 2026-09-06 | iOS App 實體鍵盤編輯器 | 僅限琦琦 App 前景 |
| 2026-09-03 | 手機候選配色 | Android／iOS；iOS App 實體編輯器仍固定紫色 |
| 2026-08-27 | macOS 候選窗比例 | 同日有比例設定修正 |
| 2026-08-23 | Android 浮動候選窗 | 實體鍵盤使用 |
| 2026-08-23 | iOS 初始虛擬注音鍵盤 | 後續新增設定另列 |
| 2026-08-22 | Android 早期鍵盤版面與設定 | 個別新增選項另列 |

舊 macOS 一般／傳統注音／倉頡／簡易設定，以及未在上表逐項列出的既有功能，加入日期仍待考證；不以較晚的修正日期冒充首次加入日期。

## 維護方式

新增設定時同步更新對應欄位、共用／獨立儲存範圍與提交日期；實作完成後更新支援狀態，正式發布後再更新平台摘要。Roadmap 預計日期只在確認排程後填入，避免將「原始碼已有」當成「使用者已取得」。

本表依原始碼與平台文件維護；各次建置、模擬器與實機驗收仍須分別保存證據。盤點來源為 [CHANGELOG](../CHANGELOG.md)、[README](../README.md)、各 frontend 文件與本機 Git；歷史交接測試數字不作現況驗收依據。
