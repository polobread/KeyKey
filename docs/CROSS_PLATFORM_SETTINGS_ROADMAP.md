# 跨平台輸入法設定支援表與 Roadmap

盤點日期：2026-10-20。各平台目前開發版為 **1.3.7**，共用好打注音模型為 **1.3.1**。

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

Linux 與 FreeBSD 共用 Fcitx 5 frontend，依使用者要求合併一欄；相同原始碼不代表相同驗收程度。Linux 的 X11、GNOME Wayland 與 FreeBSD 原生桌面須分別驗證；FreeBSD 不套用 Linux 已發布版號或測試結果。

目前發布狀態依儲存庫紀錄整理，未即時查詢商店或套件庫：

| 平台 | 開發版 | 已知正式發布狀態 |
|---|---|---|
| macOS | 1.3.7 | 正式版 1.3.1 |
| Windows TSF | 1.3.7 | 目前產品線尚未正式發布 |
| Linux | 1.3.7 | 正式版 1.3.1 |
| FreeBSD | 共用 1.3.7 frontend | 原生桌面待驗收；ports／pkg 上架版號未在本次確認 |
| Android（虛擬／實體） | 1.3.7 | Google Play 1.3.6；另有 1.3.2、1.3.3、1.3.5 正式發布紀錄 |
| iOS（虛擬／App 內實體） | 1.3.7 | App Store 1.3.2，build 41 |

## 一般、輸入法與鍵盤配置

來源：[macOS 一般設定](../Source/PreferenceApplications/OSX/TakaoGlobal.m)、[Windows 設定](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml)、[Linux／FreeBSD 設定](../Source/Loaders/Linux-IME/adapters/fcitx5/fcitx5_engine.cpp)、[Android 設定](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/SettingsActivity.java)、[iOS App 設定](../Source/Loaders/iOS-Keyboard/ContainerApp/SetupViewController.swift)。

| 設定項目 | macOS | Windows | Linux／FreeBSD | Android 虛擬 | iOS 虛擬 | Android 實體 | iOS 實體 |
|---|---|---|---|---|---|---|---|
| 選用好打注音 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 選用傳統注音 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 選用倉頡 | ✓ | ✓ | ✓ Fcitx 輸入法 | ✓ | ✓ | ✓ | ✓ |
| 選用簡易 | ✓ | ✓ | ✓ Fcitx 輸入法 | ✓ | ✓ | ✓ | ✓ |
| 在輸入法選單顯示／隱藏個別中文輸入法 | ✓ | ✓ | 外部 Fcitx 輸入法清單 | — | — | — | — |
| 啟動時預設中文／英文 | ✓ | ✓ | — | — | — | — | — |
| 單按 Shift 切換中英文的開關 | ✓ | 固定可切換 | 固定可切換 | 不適用 | 不適用 | — | — |
| Ctrl+反斜線切換中英文的開關 | ✓ | ✓ | ✓ | 不適用 | 不適用 | — | — |
| Ctrl+Alt+逗號開啟符號表的開關 | — | ✓ 中文模式限定 | — | 不適用 | 不適用 | — | — |
| 中文模式忽略 Caps Lock 的開關 | — | ✓ 預設開啟 | — | 不適用 | 不適用 | — | — |
| 實體鍵盤類型對應（非注音排列） | ✓ 系統鍵盤配置 | 固定美式 | 外部系統／Fcitx | 不適用 | 不適用 | 外部 Android | 外部 iOS |
| 注音配置：標準 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 注音配置：許氏 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 注音配置：倚天／倚天 26 鍵／漢語拼音 | ✓ | ✓ | ✓ | — | — | — | — |
| 簡體中文輸出 | — | ✓ 四種輸入法 | ✓ 繁轉簡 | — | — | — | — |

手機的輸入法與注音配置可由設定選擇；「啟動時預設中文／英文」是另一項偏好，不能把切換輸入法或依欄位類型自動選擇英文／數字視為支援該設定。Windows、Linux 已有 Shift 切換行為，但缺少 macOS 的獨立啟用開關。

## 注音與好打注音進階設定

來源：[macOS 好打注音](../Source/PreferenceApplications/OSX/TakaoSmartPhonetic.m)、[Windows 設定與選項](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml.cs)、[Linux／FreeBSD frontend](../Source/Loaders/Linux-IME/adapters/fcitx5/fcitx5_engine.cpp)、[Android README](../Source/Loaders/Android-IME/README.md)、[iOS README](../Source/Loaders/iOS-Keyboard/README.md)。

| 設定項目 | macOS | Windows | Linux／FreeBSD | Android 虛擬 | iOS 虛擬 | Android 實體 | iOS 實體 |
|---|---|---|---|---|---|---|---|
| 好打注音：空白鍵開候選／使用空白鍵選字 | ✓ | ✓ | ✓ | ✓ | ✓ App 調整 | ✓ 與虛擬共用 | ✓ 與虛擬共用 |
| 好打注音：選字目標在游標前方／後方 | ✓ | ✓ | ✓ | — 點字指定 | — 點字指定 | — | — |
| 好打注音：選字按鍵配置 | ✓ | ✓ 三組 | 固定 1–9 | 不適用 觸控點選 | 不適用 觸控點選 | 固定 1–9 | 固定 1–9 |
| 好打注音：組字區長度 | ✓ 10–20 | ✓ 10–20 | 固定十／十一音節 | 固定九／十音節 | 固定九／十音節 | 固定，依雙排模式不同 | 固定十／十一音節 |
| 好打注音：Esc 清除整句的開關 | ✓ | ✓ | ✓ | 不適用 | 不適用 | — | — |
| 好打注音：使用上下文選字（Bigram）開關 | 固定開啟 | 固定開啟 | 固定開啟 | ✓ | 固定開啟 | ✓ 與虛擬共用 | 固定開啟 |
| 注音：全字庫／Big5 字集限制 | ✓ | ✓ | ✓ 注音與符號過濾 | — | — | — | — |
| 重設好打注音學習紀錄，保留自訂詞 | ✓ 輸入法選單 | ✓ | 外部命令列 | ✓ | ✓ | ✓ 共用學習資料 | ✓ 獨立學習資料 |

Windows 的三組選字鍵為 `12345678`、`asdfghjk`、`asdfzxcv`。Linux／FreeBSD 的字集設定是 Big5-HKSCS 過濾，不能視為與其他桌面平台完全相同的編碼範圍。

Android 實體一般模式保留十個完成音節，第十一個完成時擠出前段完整詞；啟用好打注音雙排選字後改走虛擬鍵盤的九／十音節流程。這是模式差異，沒有可自由選擇任意長度的滑桿。

手機未提供桌面的字集限制開關；iOS／Android 已自動隱藏系統字型不能顯示的候選，此為固定行為，與使用者選擇 Big5 字集不同。

## 倉頡與簡易

來源：[macOS 倉頡](../Source/PreferenceApplications/OSX/TakaoCangjie.m)、[macOS 簡易](../Source/PreferenceApplications/OSX/TakaoSimplex.m)、[Windows 設定](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml)、[Linux／FreeBSD 倉頡設定](../Source/Loaders/Linux-IME/tools/cangjie_settings.py)、[Android 設定儲存](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/ChineseInputMethodSettings.java)、[iOS 設定儲存](../Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/ChineseInputMethod.swift)。

| 設定項目 | macOS | Windows | Linux／FreeBSD | Android 虛擬 | iOS 虛擬 | Android 實體 | iOS 實體 |
|---|---|---|---|---|---|---|---|
| 倉頡：即時候選 | ✓ | ✓ | ✓ 獨立設定窗 | ✓ | ✓ | ✓ 獨立保存 | ✓ 獨立保存 |
| 倉頡：未打完也能選字（前綴候選） | ✓ | ✓ | ✓ 獨立設定窗 | ✓ | ✓ | ✓ 獨立保存 | ✓ 獨立保存 |
| 倉頡：錯碼清除 | ✓ | ✓ | ✓ 獨立設定窗 | ✓ | ✓ | ✓ 獨立保存 | ✓ 獨立保存 |
| 倉頡：滿五碼查詢／組字 | ✓ | ✓ | 固定，不自動滿碼查詢 | ✓ | ✓ | ✓ 沿用共用值 | ✓ 沿用共用值 |
| 倉頡：依選字紀錄排序／動態字頻 | ✓ | ✓ | — | ✓ | ✓ | ✓ 沿用共用值 | ✓ 沿用共用值 |
| 倉頡：標點全形／混合／半形 | ✓ | ✓ | — 原字表 | ✓ | ✓ | ✓ 沿用共用值 | ✓ 沿用共用值 |
| 倉頡：全字庫／Big5 限制 | ✓ | ✓ | — 無對等倉頡專用開關 | — | — | — | — |
| 簡易：即時候選 | ✓ | ✓ | — | ✓ | ✓ | ✓ 共用 | ✓ 共用 |
| 簡易：錯碼清除 | ✓ | ✓ | 固定保留錯碼 | ✓ | ✓ | ✓ 共用 | ✓ 共用 |
| 簡易：全字庫／Big5 限制 | ✓ | ✓ | — 無對等簡易專用開關 | — | — | — | — |

倉頡「未打完也能選字」依賴即時候選；即時候選與錯碼清除互斥。桌面與手機實體的前兩項新設定缺值時預設關閉；手機虛擬缺值時預設開啟，已有明確設定則保留。

手機分開保存的是倉頡的「即時候選、前綴候選、錯碼清除」。滿五碼查詢、選字排序與標點仍共用；Android 在「虛擬鍵盤」區塊調整這三個共用值，實體鍵盤也讀取。iOS 雖在兩組選單都顯示這些共用值，仍不能算各自獨立。簡易的設定也共用。

## 候選外觀、聲音與手機鍵盤操作

來源：[macOS 一般設定](../Source/PreferenceApplications/OSX/TakaoGlobal.m)、[Windows 設定](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml)、[Linux／FreeBSD 設定](../Source/Loaders/Linux-IME/adapters/fcitx5/fcitx5_engine.cpp)、[Android 設定文字](../Source/Loaders/Android-IME/app/src/main/res/values/strings.xml)、[iOS 鍵盤設定](../Source/Loaders/iOS-Keyboard/Keyboard/SettingsPanel.swift)、[iOS 實體編輯器](../Source/Loaders/iOS-Keyboard/ContainerApp/HardwareKeyboardEditorViewController.swift)。

| 設定項目 | macOS | Windows | Linux／FreeBSD | Android 虛擬 | iOS 虛擬 | Android 實體 | iOS 實體 |
|---|---|---|---|---|---|---|---|
| 候選窗垂直／水平 | ✓ | ✓ | ✓ 交由面板呈現 | 固定候選列 | 固定候選列 | ✓ 浮動窗限定 | 固定直排 |
| 候選窗大小／比例 | ✓ | ✓ | 外部 Fcitx／桌面面板 | — | — | — | — |
| 候選反白／底色 | ✓ 四色＋自訂 | ✓ 四色 | 外部 Fcitx／桌面面板 | ✓ 四色 | ✓ 四色 | ✓ 四色 | 固定紫色 |
| 輸入錯誤提示聲開關 | ✓ | ✓ | ✓ | — | — | — | — |
| 錯誤提示聲音效檔案／試聽 | ✓ | — | — | 不適用 | 不適用 | 不適用 | 不適用 |
| 觸控按鍵音開關 | 不適用 | 不適用 | 不適用 | — | ✓ | 不適用 | 不適用 |
| 觸控按鍵震動時間 | 不適用 | 不適用 | 不適用 | ✓ 0–100 ms | — 目前權限方案受限 | 不適用 | 不適用 |
| 顯示觸控按鍵預覽的開關 | 不適用 | 不適用 | 不適用 | ✓ | 固定顯示 | 不適用 | 不適用 |
| 直式／橫式虛擬鍵盤高度 | 不適用 | 不適用 | 不適用 | ✓ 各自 50–200% | 固定依裝置適配 | 不適用 | 不適用 |
| 預留底部切換語言空間 | 不適用 | 不適用 | 不適用 | ✓ | — 系統安全區 | ✓ 與虛擬分開 | 不適用 |
| 使用浮動候選字窗 | 固定桌面候選窗 | 固定桌面候選窗 | 固定 Fcitx 面板 | 不適用 | 不適用 | ✓ | — App 內固定候選區 |
| 實體鍵盤顯示虛擬數字與符號鍵 | 不適用 | 不適用 | 不適用 | 不適用 | 不適用 | ✓ | — |
| 實體鍵盤好打注音雙排選字 | 不適用 | 不適用 | 不適用 | 不適用 | 不適用 | ✓ | — |

Android 浮動候選窗開啟時，雙排選字、虛擬數字符號鍵與實體底部空間選項停用並保留值；取得不到可用游標位置或無法附掛視窗時，會退回一般候選列。這是條件式支援，不能把三種面板當成可同時開啟。

iOS App 設定中的候選底色與按鍵音不等於 App 實體編輯器也套用；目前實體編輯器使用自己的固定紫色與直排候選。

## 關聯詞、自訂詞與資料管理

來源：[macOS 詞彙管理](../Source/PreferenceApplications/OSX/TakaoPhrases.m)、[macOS 自訂詞編輯器](../Source/Utilities/PhraseEditor/OSX/PEController.m)、[Windows 設定](../Source/Loaders/Windows-TSF/SettingsModern/MainWindow.xaml)、[Linux 命令列工具](../Source/Loaders/Linux-IME/tools/smart-mandarin-phrases.cpp)、[Android 自訂詞](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/UserPhrasesActivity.java)、[iOS App 設定與自訂詞](../Source/Loaders/iOS-Keyboard/ContainerApp/SetupViewController.swift)。

| 設定項目 | macOS | Windows | Linux／FreeBSD | Android 虛擬 | iOS 虛擬 | Android 實體 | iOS 實體 |
|---|---|---|---|---|---|---|---|
| 逐項啟用／停用關聯詞來源 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ 共用 | ✓ |
| 好打注音自訂詞新增／編輯／刪除 | ✓ | ✓ | 外部 CLI，修改需刪除再新增 | ✓ | ✓ App 管理 | ✓ 共用 | ✓ App 管理 |
| 自訂詞匯入／匯出 | ✓ | ✓ | — | ✓ | ✓ App 管理 | ✓ 共用 | ✓ App 管理 |
| 學習資料隨使用者資料庫匯入／匯出 | ✓ | ✓ | — 無對等匯入／匯出入口 | — 僅自訂詞 | — 僅自訂詞 | — 僅自訂詞 | — 僅自訂詞 |
| 自訂詞本地讀音輔助／逐字選讀音 | ✓ 編輯讀音 | ✓ 新增時查詞與逐字選擇 | — | — 手動讀音 | — 手動讀音 | — 手動讀音 | — 手動讀音 |

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

macOS／Windows 的 key、feed 與正式啟用尚須依發布流程完成；存在設定介面不代表現在能從正式服務取得更新。Linux／FreeBSD 使用官方下載頁與套件管理器，FreeBSD 套件可能較公告晚上架。桌面排程只通知，不預先下載或自動安裝。

## 待規劃的功能缺口

以下是依目前設定差異提出的規劃候選，**尚未承諾採用或指定開發日期**。優先順序供討論；先保留各平台合適的預設，不為追求表格一致而改變輸入行為。

| 候選 | 建議順序 | 平台與缺口 | 完成條件 | 預計日期 |
|---|---|---|---|---|
| R01 手機實體鍵盤進階設定 | 優先 | Android 實體、iOS App 實體缺少游標前後目標、Esc 整句清除及選字鍵設定 | 各自有設定入口，保留目前組字後套用；Android 一般／雙排／浮動模式分別驗證 | 待定 |
| R02 Linux／FreeBSD 詞彙管理介面 | 優先 | 目前新增／刪除／重設需 CLI，無匯入／匯出介面 | GUI 編輯、自訂詞匯入／匯出、重設保留自訂詞；Linux／FreeBSD 分別驗收 | 待定 |
| R03 Linux／FreeBSD 倉頡與簡易設定補齊 | 優先 | 缺動態排序、滿碼查詢開關、標點樣式與簡易即時候選／錯碼清除開關 | 先確認需新增的引擎能力，再提供對應設定與候選順序回歸 | 待定 |
| R04 iOS 實體編輯器外觀設定 | 一般 | App 已有候選底色設定，但實體編輯器固定紫色／直排 | 實體編輯器讀取候選配色並提供排列／字級；旋轉及小螢幕可用 | 待定 |
| R05 手機注音配置補齊 | 一般 | 虛擬／實體只提供標準、許氏，缺倚天、倚天 26 鍵、漢語拼音 | 按四種手機輸入方式分別設計鍵帽、讀音解析、退格及候選流程 | 待定 |
| R06 手機自訂詞讀音輔助 | 一般 | Windows 已能查本地讀音；手機仍手動輸入 | 本地查詞、逐字破音字選擇、缺字提示；不自動覆蓋已編輯讀音 | 待定 |
| R07 中英啟動模式與 Shift 開關 | 一般 | Linux／手機缺啟動模式偏好；Windows／Linux 的 Shift 切換無獨立開關 | 明確區分啟動偏好、欄位提示與即時模式，切換先保留組字 | 待定 |
| R08 macOS／手機簡體中文輸出 | 一般 | Windows、Linux 有，macOS 與手機未提供對等設定 | 設定與切換邊界、四種輸入法及關聯詞完整驗證；學習仍用繁體 | 待定 |
| R09 iOS 虛擬鍵盤操作選項 | 一般 | 缺高度比例與按鍵預覽開關 | 檢查小螢幕、橫式、iPad 與安全區；維持按鍵／候選可點擊尺寸 | 待定 |
| R10 上下文選字開關評估 | 研究 | Android 以外固定開啟 Bigram | 先確認使用需求與跨 frontend 學習語意，再決定是否提供；不可只複製介面 | 待定 |
| R11 跨平台學習資料可攜性 | 研究 | 手機只匯入自訂詞；iOS 虛擬／實體學習分離 | 先定格式、權限與衝突規則，再評估可支援範圍 | 待定 |
| R12 桌面發布驗收 | 發布前必要 | 1.3.7 原始碼與實際正式推出仍有距離 | Windows 宿主、Linux Wayland、FreeBSD 原生桌面與更新服務分別驗收 | 各平台另定 |
| R13 組字長度與選字鍵配置 | 一般 | Linux／FreeBSD 及手機實體缺桌面的組字長度、選字鍵設定 | 分 frontend 評估長句擠詞、候選數量及按鍵衝突；不以改設定檔取代完整輸入回歸 | 待定 |

iOS 在其他 App 接管 USB／藍牙鍵盤受系統 extension API 限制，不列成可承諾補齊的功能。若規劃震動、App／鍵盤雙向設定或學習同步，須先評估是否改變目前不要求「完整取用」的權限方案。

macOS 舊 XIB 內的一點通、通用表格與外掛等歷史／條件式頁面，不因檔案仍存在就列為標準安裝已支援功能；若要納入 roadmap，須先確認目前安裝內容及可進入入口。

## 功能開發時間表

日期取自功能引入或關鍵調整的 Git commit 提交時間，統一換算為台灣時區，以 `YYYY-MM-DD` 顯示並由新到舊排列。日期表示開發紀錄中的加入或調整時間，正式推出狀態請看前面的平台摘要；同一功能的後續修正另記於備註。

| 日期 | 功能／受影響平台 | 備註 |
|---|---|---|
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

本次是文件與原始碼盤點，未執行各平台建置、安裝或實機功能驗收。盤點來源為 [CHANGELOG](../CHANGELOG.md)、[README](../README.md)、各 frontend 文件與本機 Git；歷史交接測試數字不作現況驗收依據。
