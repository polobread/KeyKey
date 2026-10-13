# 琦琦輸入法商店圖準備

2026-09-26 選定 **A 版**：延續深紫色版面。主軸是好打注音，並保留傳統注音與接上實體鍵盤各自的介紹。Apple 圖只呈現 iPhone／iPad 的使用方式；Google Play 第五張介紹 Android、iOS、macOS、Windows、Linux 五平台。

Android／iOS `1.3.2` 已分別在 Google Play／App Store 正式上線（iOS build 41）。Android 於 2026-10-08 正式發布，可直接從商店安裝，不需加入封閉測試。Google Play A 版主視覺已改為「琦琦輸入法」；iPhone／iPad 的第三張實體鍵盤與第四張設定頁已使用 1.3.2 Release 模擬器重拍，第四張文案為「好打注音・傳統注音／倉頡・簡易，隨你切換」。其餘上架 PNG 與來源截圖主要沿用 1.3.0 時期素材，以下保留真實來源版本。

## 上架圖位置

| 用途 | 目錄或檔案 | 尺寸 | 順序 |
| --- | --- | --- | --- |
| App Store iPhone 中型顯示器上架 | `AppStore/iPhone-1206x2622/01.png`～`04.png` | 1206 × 2622 | 好打、傳統、實體鍵盤、四種輸入法切換 |
| App Store iPhone 上架 | `AppStore/iPhone-1242x2688/01.png`～`04.png` | 1242 × 2688 | 同上 |
| App Store iPad 上架 | `AppStore/iPad-2048x2732/01.png`～`04.png` | 2048 × 2732 | 同上 |
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

先前的商店文案與發布紀錄可在 Git 歷史查閱；發布前應重新核對上架圖與各平台目前實際介面；行動版以 `1.3.2` 為準。

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
