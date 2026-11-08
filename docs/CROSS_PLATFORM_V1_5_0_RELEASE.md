# KeyKey 1.5.0 六平台發布準備

文件整理日期：2026-11-08；來源基底：`f6dd8e3`。這份文件集中整理發布說明、升級注意事項及各平台交付條件。文件整理完成不代表已建置、簽章、通過完整驗收或上架；本輪不執行發布、安裝或更新 feed。

## 發布主軸

琦琦輸入法改採 **Guanyinma（觀音嬤）** 作為 Windows、macOS、iOS、Android、Linux 與 FreeBSD 的單一共用核心。名稱來自臺語對觀世音菩薩的稱呼「觀音嬤」。Rust 核心統一處理好打注音、傳統注音、倉頡與簡易的輸入邏輯、候選排序及學習；各平台保留自己的介面、鍵盤與文字宿主接合。

取名「觀音嬤」，也借用觀音菩薩慈悲照顧眾生的形象。我們希望這套共用核心也能照顧不同平台與裝置，讓大家無論使用哪個平台，都能穩定、順暢地輸入中文。命名靈感參考[艋舺龍山寺官網〈認識奉祀神祇〉](https://www.lungshan.org.tw/tw/02_1_1_gods.php)，實際平台交付仍依下列驗收流程。

原 macOS／Windows 好打注音核心 **Manjusri（文殊菩薩）** 已由 Guanyinma 接替。1.5.0 產品不再內建 Manjusri 或各平台原有的舊輸入引擎，不提供舊核心選擇或失敗回退；已發布舊版本的歷史與授權紀錄仍保留。

集中維護與測試可減少重複實作，讓修正與新能力更容易帶到各平台。這不是六平台介面或全部設定相同的承諾；支援範圍見[跨平台設定支援表](CROSS_PLATFORM_SETTINGS_ROADMAP.md)，完整變更見 [CHANGELOG 1.5.0](../CHANGELOG.md#150)。

可用於 Release／商店說明的摘要：

> 本版導入 Guanyinma（觀音嬤）Rust 共用核心，讓六大平台的四種輸入法共用組字、候選排序與學習機制，降低維護成本，讓各平台更容易獲得功能改進。Linux／FreeBSD 補齊桌面設定與圖形詞庫管理；iOS／Android 改善鍵盤版面、字體與實體鍵盤操作。各平台仍保留原生輸入體驗，詳細功能依平台說明為準。

## 版本與目前發布狀態

六平台來源版號已為 `1.5.0`，本輪只核對既有來源，不更改產品版號或 build number。FreeBSD 共用 Linux 版號。正式下載在實際發布前仍指向既有版本，不預先建立 1.5.0 下載連結。

| 平台 | 1.5.0 唯一版號來源 | 目前正式版與發布入口 |
|---|---|---|
| macOS | [IMK plist](../Source/Loaders/OSX-IMK/Takao-Info.plist)，並核對偏好設定、詞彙編輯器、安裝說明三份產品 plist | [1.3.9 Release](https://github.com/polobread/KeyKey/releases/tag/v1.3.9)；Developer ID／notarization |
| Windows | [TSF CMakeLists.txt](../Source/Loaders/Windows-TSF/CMakeLists.txt) | [1.3.7 Release](https://github.com/polobread/KeyKey/releases/tag/v1.3.7)；Certum 本機簽章及人工發布 |
| Linux／FreeBSD | [Linux CMakeLists.txt](../Source/Loaders/Linux-IME/CMakeLists.txt) | Linux [1.3.7 Release](https://github.com/polobread/KeyKey/releases/tag/v1.3.7)；FreeBSD 透過 ports／pkg，套件版本可能較晚上架 |
| iOS | [Xcode project](../Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj/project.pbxproj) 的 `MARKETING_VERSION` | 儲存庫記錄為 App Store 1.3.7；透過 Xcode archive／App Store Connect 送審 |
| Android | [app/build.gradle.kts](../Source/Loaders/Android-IME/app/build.gradle.kts) 的 `keyKeyVersionName`／`keyKeyVersionCode` | 儲存庫記錄為 Google Play 1.3.7；手動發布 workflow 上傳 internal testing，再由 Play Console 推廣 |

2026-11-08 已唯讀核對公開 GitHub Release：macOS 1.3.9 已發布，其 CDN 安裝包、校驗檔與 build-info URL 均可取得。這次未登入商店後台或查核 FreeBSD 套件庫；商店、ports／pkg 的實際可下載版本仍須在發布時分別確認。

## 升級與資料

升級前先使用原版本提供的匯出功能備份自訂詞與學習資料，並保留唯一舊檔。Guanyinma 使用獨立使用者資料庫，不能把「保留舊檔」寫成「自動沿用舊學習」。

| 平台 | 新核心的資料界線 |
|---|---|
| macOS | 使用 `GuanyinmaUserData.db`；可明確匯入舊 MJSR，提供完整 Guanyinma JSON 備份。安裝後登出再登入，升級保留原有輸入來源，不移除重加 |
| Windows | 使用 `GuanyinmaUserData.db`；舊 Windows 詞庫僅在使用者明確操作時唯讀匯入，提供完整 Guanyinma JSON 備份。安裝後登出再登入並核對 x64／x86 宿主載入的新 DLL |
| iOS | App 發布自訂詞到 App Group，extension 唯讀取得複本；鍵盤與 App 實體編輯器的 `GuanyinmaUser.db` 學習各自獨立。不要求完整取用，不自動搬移舊 Swift 學習；保留明確 MJSR 自訂詞交換 |
| Android | App／IME 共用私有 `GuanyinmaUser.db`，保留明確 MJSR 自訂詞交換；不自動改寫或搬移舊 Java 詞庫與學習。不新增網路權限 |
| Linux／FreeBSD | 使用 `guanyinma-user.db`，圖形工具支援自訂詞及完整 Guanyinma JSON 備份／匯入；不支援舊 Linux C++ 資料庫讀寫或匯入，舊檔不自動刪除 |

同一核心不代表自動跨裝置同步。候選可顯示性由各平台原生字型服務判斷，候選位置可能不同；實際選字按文字與當下候選判定。

## 平台交付與驗收

目前文件中的舊測試是各自來源與環境的證據。尤其 [Windows 真實宿主紀錄](WINDOWS_DESKTOP_HOST_ACCEPTANCE.md) 的 2026-11-01 x64 四法局部測試使用當時已安裝 DLL 與詞庫，不能直接視為本次最終 tag 的發布驗收。其餘平台的範圍以各 adapter 與宿主文件為準。

| 平台 | 發布前仍須核對 | 入口 |
|---|---|---|
| 共用核心／模型 | 最終來源的原生核心 CI、C consumer、參考涵蓋率門檻；共用 DB 雜湊、manifest 與五個 frontend 接線；不重建模型 | [核心測試分工](../Source/Guanyinma/README.md#測試範圍與分工)、[資料庫流程](KEYKEY_DATABASE_WORKFLOW.md) |
| macOS | 最終來源建置／notices／模型；正式簽章與公證；IMK 真實組字、候選、送字；全新、手動升級、程式內更新三條可恢復 VM 路徑，記錄重新登入及保留來源 | [adapter](GUANYINMA_MACOS_ADAPTER.md)、[IMK 宿主](GUANYINMA_MACOS_IMK_HOST_TEST.md)、[VM 安裝](MACOS_INSTALLER_VM_TESTING.md)、[打包](../Installer/README.md) |
| Windows | 發布完整矩陣、x64／x86 產物與宿主、AppContainer／Search、最終安裝包的全新／升級／移除與資料保留；Certum／Ed25519 簽章及不可變資產 | [adapter](GUANYINMA_WINDOWS_ADAPTER.md)、[本機發布](WINDOWS_CERTUM_RELEASE.md)、[宿主紀錄](WINDOWS_DESKTOP_HOST_ACCEPTANCE.md) |
| Linux | 完整 Linux CI、staged install／套件生命週期、Ubuntu 24.04 產物及 22.04 相容性、X11／GNOME Wayland／XWayland 宿主分別驗證 | [adapter](GUANYINMA_LINUX_ADAPTER.md)、[frontend](../Source/Loaders/Linux-IME/README.md)、[桌面測試](../Source/Loaders/Linux-IME/docs/manual-desktop.md) |
| FreeBSD | 原生 Rust／Fcitx 建置與真實文字宿主、ports 的 Cargo 來源／相依／notices／plist；不沿用 Linux 或舊核心 1.3.7 的通過結果 | [FreeBSD 指南](../FREEBSD_INSTALL.md)、[共用 adapter](GUANYINMA_LINUX_ADAPTER.md) |
| iOS | App／extension archive 的版號、build、模型與授權；真實宿主、組字與候選生命週期、App 實體編輯器、手機／平板與直橫式版面；商店上傳及送審資料 | [adapter](GUANYINMA_IOS_ADAPTER.md)、[宿主狀態矩陣](IOS_APP_EXTENSION_HOST_STATE_MATRIX.md)、[frontend](../Source/Loaders/iOS-Keyboard/README.md) |
| Android | 四 ABI 的 JNI／Rust 產物、APK／AAB 模型與 notices；觸控、一般實體／浮動／雙排、旋轉與宿主切換；簽署 AAB、商店測試與正式推廣 | [adapter](GUANYINMA_ANDROID_ADAPTER.md)、[裝置測試](ANDROID_VIRTUAL_DEVICE_TEST_PLAN.md)、[frontend](../Source/Loaders/Android-IME/README.md) |

建置命令與完整依賴以 [BUILDING](../BUILDING.md) 為準。共用核心完整測試集中於 `guanyinma-core.yml`；各 FE workflow 做自身接合與原有封裝驗證。`tests/run_core_functional.py` 是手動遷移參考，不納入發布 gate。

## 發布順序與文件收尾

1. 將本文件及相關修正經工作分支 PR 交由維護者 review／merge；確定最終來源，逐平台完成上表實際驗收並保存 commit、版本、模型、套件雜湊與簽章證據。
2. 桌面使用符合來源版號的 tag 與正式流程；Windows CI 產生待簽輸入，由本機 Certum 流程簽署及人工核准發布。不要把尚未簽署的 artifact 當正式下載。
3. iOS／Android 分別完成商店上傳、測試、審查／推廣；build number 與 versionCode 是否可接受，須由各商店既有上傳紀錄核對，不從原始碼推定。
4. 各平台正式資產可取得後，再更新 README、平台指南的正式版本、檔名、校驗連結及商店文案。截圖保留實際拍攝版號；新版圖片未補齊時明示來源，不修改圖片標註假裝重拍。
5. macOS／Linux 發布流程核對產物後建立 stable feed PR；Windows feed 依本機發布指南準備。所有 feed PR 由維護者 review／merge，之後才同步 CDN。Linux／FreeBSD 共用 Unix feed，FreeBSD 公告不等待 ports／pkg 上架，明示套件可能較晚。

## 文件分工

README 中英文說明產品、Guanyinma 命名與目前可下載正式版；CHANGELOG 依版號記產品變更。六平台安裝指南保留可用下載與真實圖片，新核心升級差異由本文件與 adapter 連結提供。BUILDING、各 frontend README、Installer 與 update 文件記建置／簽章／公告責任；商店素材的真實來源版本見 [StoreAssets](../StoreAssets/README.md)。歷史交接、舊模型報告、遷移 baseline 與舊版宣傳不改寫成 1.5.0 驗收。
