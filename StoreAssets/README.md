# 琦琦注音 v1.3.0 商店圖

2026-09-26 選定 **A 版**：延續深紫色版面。主軸是好打注音，並保留傳統注音與接上實體鍵盤各自的介紹。Apple 圖只呈現 iPhone／iPad 的使用方式；Google Play 第五張介紹 Android、iOS、macOS、Windows、Linux 五平台。

## 上架圖位置

| 用途 | 目錄或檔案 | 尺寸 | 順序 |
| --- | --- | --- | --- |
| App Store iPhone 預覽 | `AppStore/iPhone-1206x2622/01.png`～`04.png` | 1206 × 2622 | 好打、傳統、實體鍵盤、切換模式 |
| App Store iPhone 上架 | `AppStore/iPhone-1242x2688/01.png`～`04.png` | 1242 × 2688 | 同上 |
| App Store iPad 上架 | `AppStore/iPad-2048x2732/01.png`～`04.png` | 2048 × 2732 | 同上 |
| Google Play 手機 | `GooglePlay/Phone/01.png`～`05.png` | 1080 × 1920 | 好打整句、句中改字、傳統、實體鍵盤、五平台 |
| Google Play 主視覺 | `GooglePlay/feature-graphic-1024x500.png` | 1024 × 500 | 好打、傳統、實體鍵盤 |
| 五平台獨立圖 | `FivePlatforms/five-platforms.png` | 1080 × 1920 | 與 Google Play `05.png` 相同 |

PNG 均為無 alpha 的 RGB 畫面。`1206 × 2622` 保留作 iPhone 模擬器比例預覽；既有 App Store Connect 上架組使用 `1242 × 2688`。正式上傳前仍須以 App Store Connect／Play Console 的實際預覽核對裁切、尺寸和文字可讀性。

## 截圖來源

- iPhone 好打注音、實體鍵盤、設定：`docs/images/keykey-ios-v130-smart-typing.png`、`keykey-ios-v130-hardware-editor-boundary.png`、`keykey-ios-v130-keyboard-settings.png`；傳統注音沿用 `Sources/ios-notes-qi.png`。
- iPad 好打注音：`Sources/ios-ipad-v130-smart-full.png`，從 iPad 模擬器實際輸入「請假要去哪裡玩呢去海邊」並擷取。傳統注音沿用 `Sources/ios-ipad-notes-qi.png`；實體鍵盤與設定來自 iPad 模擬器的 `Sources/ios-ipad-v130-hardware-editor.png`、`ios-ipad-v130-settings.png`。
- Android 好打注音：新拍的 Android 模擬器畫面 `Sources/android-v130-smart-full.png` 與 `android-v130-smart-middle-candidate.png`；傳統注音、實體鍵盤沿用先前實拍的 `android-phone-touch-portrait.png` 與 `android-notes-floating-qi.png`。
- 五平台圖：Android、iOS 使用上述好打注音實拍；macOS、Linux 使用 `docs/images/keykey-macos-v130-candidates.png`、`keykey-linux-v130-smart-candidates.png`；Windows 使用 `Sources/chichi-windows.png`。Linux 格不再標「開發中」。

來源截圖保留真實鍵盤與候選畫面，沒有後製候選字。iOS 的一般鍵盤 extension 不接收實體鍵盤事件；實體鍵盤頁呈現的是琦琦 App 前景的編輯器，完成後可複製或分享。Android 的實體鍵盤頁則呈現跟隨游標的浮動候選窗。

## 重新產圖

在儲存庫根目錄執行：

```sh
swift -module-cache-path /private/tmp/keykey-store-v130-module-cache StoreAssets/generate-assets.swift
```

此腳本會依來源截圖產生已選定的 A 版、兩種 iPhone 尺寸、iPad、Google Play 五張手機圖、主視覺及獨立五平台圖。`generate-five-platforms.py` 只會把現有的 Google Play 第五張同步到獨立五平台圖，不會重畫舊版「Linux 開發中」圖。

先前的商店文案與 1.2.7 發布紀錄可在 Git 歷史查閱；本目錄圖片的內容與版號以這份 v1.3.0 說明為準。
