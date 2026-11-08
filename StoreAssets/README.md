# 琦琦輸入法商店圖準備

2026-09-26 選定 **A 版**：延續深紫色版面。主軸是好打注音，並保留傳統注音與接上實體鍵盤各自的介紹。Apple 圖只呈現 iPhone／iPad 的使用方式；Google Play 第五張介紹 Android、iOS、macOS、Windows、Linux 五平台。

本次 Google Play／App Store 發布版本統一為 `1.5.0`，實際上架狀態另於各商店核對；下方素材包含 1.3.0 與 1.3.2 的實拍來源，素材版號不代表最新 App 版號。Google Play A 版主視覺已改為「琦琦輸入法」；iPhone／iPad 的第三張實體鍵盤與第四張設定頁使用 1.3.2 Release 模擬器，第四張文案為「好打注音・傳統注音／倉頡・簡易，隨你切換」。以下保留真實來源版本，不將舊圖片標成新版重拍。

## 1.5.0 上架準備

新版主軸為 Guanyinma（觀音嬤）六平台共用核心、集中維護，以及行動鍵盤的版面、鍵帽間隔、四級字體與刪除鍵位置。對外說明可參考 [1.5.0 發布準備](../docs/CROSS_PLATFORM_V1_5_0_RELEASE.md)與[更新紀錄](../CHANGELOG.md#150)。既有 iPhone／iPad 與 Google Play 素材保留；Duo 專用圖組使用 1.5.0 重新拍攝，詳見下方說明。

送審前以最終 archive／AAB 補核實際畫面、版本與商店文案；現有「五平台」圖是歷史素材，不能當成新版六平台架構圖。iOS 實體鍵盤仍只限容器 App 前景編輯器，不宣稱在其他 App 接管 USB／藍牙鍵盤。舊截圖保留來源版號；若新版外觀不同，另拍真正 App 畫面再更新素材。

## 上架圖位置

| 用途 | 目錄或檔案 | 尺寸 | 順序 |
| --- | --- | --- | --- |
| App Store iPhone 中型顯示器上架 | `AppStore/iPhone-1206x2622/01.png`～`04.png` | 1206 × 2622 | 好打、傳統、實體鍵盤、四種輸入法切換 |
| App Store iPhone 上架 | `AppStore/iPhone-1242x2688/01.png`～`04.png` | 1242 × 2688 | 同上 |
| App Store iPad 上架 | `AppStore/iPad-2048x2732/01.png`～`04.png` | 2048 × 2732 | 同上 |
| App Store iPhone Duo 上架 | `AppStore/iPhone-Duo-2007x2853/01.png`～`05.png` | 2007 × 2853 | 分離鍵盤、好打、傳統、實體鍵盤、設定 |
| Google Play 手機 | `GooglePlay/Phone/01.png`～`05.png` | 1080 × 1920 | 好打整句、句中改字、傳統、實體鍵盤、五平台 |
| Google Play 主視覺 | `GooglePlay/feature-graphic-1024x500.png` | 1024 × 500 | 好打、傳統、實體鍵盤 |
| 五平台獨立圖 | `FivePlatforms/five-platforms.png` | 1080 × 1920 | 與 Google Play `05.png` 相同 |

PNG 均為無 alpha 的 RGB 畫面。App Store Connect 的 iPhone 中型顯示器組使用 `1206 × 2622`，大型顯示器組使用 `1242 × 2688`；iPad 13 吋組使用 `2048 × 2732`。正式上傳前仍須以 App Store Connect／Play Console 的實際預覽核對裁切、尺寸和文字可讀性。

## 截圖來源

- iPhone 好打注音沿用 `docs/images/keykey-ios-v130-smart-typing.png`，傳統注音沿用 `Sources/ios-notes-qi.png`；實體鍵盤與設定頁使用 1.3.2 Release 模擬器實拍 `Sources/ios-iphone-v132-hardware-editor.png`、`ios-iphone-v132-settings.png`。
- iPad 好打注音沿用 `Sources/ios-ipad-v130-smart-full.png`，傳統注音沿用 `Sources/ios-ipad-notes-qi.png`；實體鍵盤與設定頁使用 1.3.2 Release 模擬器實拍 `Sources/ios-ipad-v132-hardware-editor.png`、`ios-ipad-v132-settings.png`，設定頁可見「琦琦輸入法」及 1.3.2 版號。
- Android 好打注音：新拍的 Android 模擬器畫面 `Sources/android-v130-smart-full.png` 與 `android-v130-smart-middle-candidate.png`；傳統注音、實體鍵盤沿用先前實拍的 `android-phone-touch-portrait.png` 與 `android-notes-floating-qi.png`。
- 五平台圖：Android、iOS 使用上述好打注音實拍；macOS、Linux 使用 `docs/images/keykey-macos-v130-candidates.png`、`keykey-linux-v130-smart-candidates.png`；Windows 使用 `Sources/chichi-windows.png`。Linux 格不再標「開發中」。

來源截圖保留真實鍵盤與候選畫面，沒有後製候選字。iOS 的一般鍵盤 extension 不接收實體鍵盤事件；實體鍵盤頁呈現的是琦琦 App 前景的編輯器，完成後可複製或分享。Android 的實體鍵盤頁則呈現跟隨游標的浮動候選窗。

## 重新產圖

在儲存庫根目錄執行：

```sh
swift -module-cache-path /private/tmp/keykey-store-v131-module-cache StoreAssets/generate-assets.swift
```

此腳本會依來源截圖產生已選定的 A 版、兩種 iPhone 尺寸、iPad、Google Play 五張手機圖、主視覺及獨立五平台圖。`generate-five-platforms.py` 只會把現有的 Google Play 第五張同步到獨立五平台圖，不會重畫舊版「Linux 開發中」圖。

先前的商店文案與發布紀錄可在 Git 歷史查閱；發布前應重新核對上架圖與各平台目前實際介面。`1.3.2` 只描述上述部分素材來源，不是目前商店或待發布版本。

## 行動版 App 圖示

Android 啟動器與 iOS App 統一使用白底黑字「琦」，與 Google Play
`GooglePlay/app-icon-512.png` 的商店圖示一致。共用圖稿來源為
`Source/Loaders/iOS-Keyboard/ContainerApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
（1024 × 1024、無 alpha）；iOS 的 Debug／Release 均指定此 `AppIcon`。

在儲存庫根目錄執行以下指令，從 iOS 原圖重新產生 Android
透明前景及單色主題圖層：

```sh
swift -module-cache-path /private/tmp/keykey-mobile-icon-module-cache Source/Utilities/generate-mobile-app-icons.swift
```

Android 最低支援 API 26，所有支援版本均使用 adaptive icon，無須舊版點陣備援。
Android manifest 的 `icon` 與 `roundIcon` 均指向 `@mipmap/ic_launcher`。
[Adaptive icon](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive) 使用白色背景，整個「琦」字位於中央 66 dp 安全圓內，避免圓形或其他
啟動器遮罩裁掉筆畫；Android 13 以上單色主題也使用相同字形。
修改品牌圖稿時須同步核對 Google Play 商店圖示。送審前另檢查 APK／AAB 與 iOS
archive 的圖示及安裝後主畫面，不能以原始碼圖示替代已上架版本的驗證。

## 行動版改名

Android 與 iOS 的 App／系統鍵盤名稱統一為「琦琦輸入法」。商店圖產生器及
Google Play 主視覺的品牌文字同步更新；iPhone／iPad 第三、第四張已更新為 1.3.2 的實體鍵盤編輯器與設定頁；第四張介紹好打注音、傳統注音、倉頡與簡易四種輸入方式；第一、第二張保留原始畫面。
上架時須同步更新 Google Play 與 App Store 的名稱及使用新版介面截圖。

## iPhone Duo 專用商店圖

Duo 圖組獨立放在 `AppStore/iPhone-Duo-2007x2853/01.png`～`05.png`，尺寸為 **2007 × 2853**，不覆寫既有 iPhone／iPad 圖組。延續 A 版深紫色風格，第一張主打分離鍵盤，其餘依序介紹好打注音、傳統注音、App 實體鍵盤編輯器與設定。

拍攝日期為 **2026-11-09**，來源為 **iOS 1.5.0／`v1.5.0`（`b2f73e4`）**，使用 Release／arm64 的 iPhone Duo 模擬器產物與 iOS 27.2 runtime。產物 plist 為 1.5.0（build 1），來源與拍攝資訊另存 manifest，不由檔名推定。原始截圖保存在 `Sources/`：

| 上架順序 | 原始截圖 | 畫面 |
| --- | --- | --- |
| 01 | `ios-duo-v150-split.png` | 內螢幕橫式，Safari 本機輸入頁中的分離鍵盤 |
| 02 | `ios-duo-v150-smart.png` | 內螢幕直式，Safari 本機輸入頁中的好打注音連續組句 |
| 03 | `ios-duo-v150-traditional.png` | 內螢幕直式，Safari 本機輸入頁中的傳統注音候選與鍵位 |
| 04 | `ios-duo-v150-hardware-editor.png` | 內螢幕直式，琦琦 App 實體鍵盤編輯器，連接模擬器 Generic Keyboard |
| 05 | `ios-duo-v150-settings.png` | 內螢幕直式，琦琦 App 設定中的四種輸入法與版面選項 |

上述候選文字與組字均為實際輸入畫面，未後製候選內容。

第二至第五張來源使用 Duo 內螢幕直式 **2007 × 2853**；第一張另接受橫式 **2853 × 2007**。產生器完整等比例放入原始畫面，不重畫、拼接或更換鍵盤與候選字；輸出為無 alpha 的 RGB PNG。[Apple 官方截圖規格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) 列有 Duo 內外螢幕尺寸，正式上傳仍須核對 App Store Connect 的對應裝置組與實際預覽。

從儲存庫根目錄獨立產生 Duo 五張圖：

```sh
swift -module-cache-path /private/tmp/keykey-store-duo-module-cache StoreAssets/generate-duo-assets.swift
```

同一次命令也會產生 `AppStore/iPhone-Duo-preview.jpg` 五圖總覽，放在上架圖目錄之外供檢視，不列入上傳的五張 PNG。

可使用 `--sources DIRECTORY` 與 `--output DIRECTORY` 指定其他來源及輸出目錄；未提供時使用上表來源與 Duo 專用目錄。此入口不會執行既有 `generate-assets.swift`，也不重產其他商店素材。
