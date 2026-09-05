# App Store / Google Play 商店素材

主軸是俏皮的「ㄅ半注音的第一選擇」：保留熟悉的五排標準注音鍵位與固定 `1–9`
候選位置，讓使用者換到不同裝置後仍能延續肌肉記憶。Android 另以實體鍵盤的直式／橫式
浮動候選窗與關閉浮動模式作為平台特色。兩張來源畫面都在記事本輸入
`ㄅ半注音的第一選擇 琦ㄑㄧˊ注音輸入法`；其中 `ㄑㄧˊ` 保持組字與選字狀態，沒有使用
內部 test page，也沒有把候選畫面後製到截圖中。

## 圖片

- `Sources/ios-notes-qi.png`：iPhone Simulator 原始畫面，五排觸控鍵盤與 `ㄑㄧˊ` 候選。
- `Sources/ios-ipad-notes-qi.png`：iPad Simulator 的原生全螢幕 4:3 畫面；系統使用預設
  字體大小與「全螢幕 App」多工設定，完整保留五排鍵盤及固定 `1–9` 候選。
- `Sources/ios-phone-dictionaries.png`：iPhone Simulator 的 30 種關聯詞庫設定實際畫面。
- `Sources/ios-phone-mcbopomofo-associated-ya.png`：iPhone 上只啟用小麥注音詞庫，選定
  `亞` 後停在關聯候選 `1–9` 的實際畫面。
- `Sources/ios-phone-anime-associated-ya.png`：iPhone 上只啟用動漫詞庫，選定 `亞` 後
  停在關聯候選 `1–9` 的實際畫面。
- `Sources/android-notes-floating-qi.png`：Android Virtual Device 原始畫面，實體鍵盤與
  垂直浮動候選。
- `Sources/android-tablet-candidates.png`：Android Tablet Virtual Device 的實際橫式畫面，
  完整保留固定 `1–9` 候選。
- `Sources/android-phone-dictionaries.png`：Android Phone Virtual Device 的 30 種關聯詞庫
  設定畫面。
- `Sources/android-phone-mcbopomofo-associated-ya.png`：只啟用小麥注音詞庫，先輸入並選定
  `亞`，停在關聯候選 `1–9` 的實際畫面。
- `Sources/android-phone-anime-associated-ya.png`：只啟用動漫詞庫，先輸入並選定 `亞`，
  停在關聯候選 `1–9` 的實際畫面。
- `Sources/android-phone-touch-portrait.png`：Android Phone Virtual Device 的直式五排
  觸控鍵盤實際畫面，停在注音組字與候選 `1–9`。
- `Sources/android-phone-touch-landscape.png`：同一台 Android Phone Virtual Device
  真正旋轉後的橫式五排觸控鍵盤畫面；保留原生橫向長寬比。
- `Sources/android-phone-hardware-fixed-portrait.png`：Android Phone Virtual Device 關閉
  浮動候選後的直式實體鍵盤畫面；固定候選列完整顯示 `1–9`。
- `Sources/android-phone-hardware-fixed-landscape.png`：同一台 Android Phone Virtual Device
  真正旋轉後的橫式實體鍵盤畫面；不是把直式圖拉寬或重畫，候選列完整顯示 `1–9`。
- `Sources/comic-devices.png`：透明背景的手機、平板、藍牙鍵盤與觸控操作漫畫插圖。
- `Sources/chichi-macos.png`、`Sources/chichi-windows.png`：桌面版實際輸入畫面。
- `AppStore/iPhone-1206x2622/01.png`～`05.png`：`1206 × 2622` iPhone Simulator
  原生比例素材，保留供 README 與預覽使用。
- `AppStore/iPhone-1242x2688/01.png`～`05.png`：App Store Connect 接受的 6.5 吋
  iPhone 上架素材。
- `AppStore/iPad-2048x2732/01.png`～`05.png`：App Store Connect 接受的 12.9／13 吋
  iPad 上架素材。
- `GooglePlay/Phone/01.png`～`05.png`：`1080 × 1920` Google Play 手機素材。
- `GooglePlay/app-icon-512.png`：Google Play 商店圖示；由 iOS 的無透明背景 1024px
  App Icon 等比例縮小。
- `GooglePlay/feature-graphic-1024x500.png`：Google Play 主圖。

整套圖片使用 macOS 預設候選紫 `#800080` 作為品牌主色。漫畫插圖以各自透明邊界裁切並
等比例縮放，不可拉寬或壓扁；候選列一律完整保留 `1–9`。圖片內容由
`generate-assets.swift` 產生；換過來源截圖後，在 repository 根目錄執行：

```sh
swift -module-cache-path /tmp/keykey-swift-module-cache StoreAssets/generate-assets.swift
```

## App Store 內文

名稱：`琦琦注音輸入法`

副標題：`ㄅ半注音的第一選擇`

宣傳文字：

> 手指記得，就讓它繼續快樂打字！熟悉的五排注音與固定 1–9 候選，換到 iPhone 或
> iPad 也不用重新學；另有 macOS、Windows 與 Android 版可安裝。

說明：

> 琦琦注音是一套讓手指延續肌肉記憶的繁體中文ㄅ半注音輸入法。
>
> 多數手機鍵盤採四排設計，琦琦保留完整五排標準注音位置。候選字固定排列，不會因
> 畫面變化而反覆移動，眼睛不用追、手指也不用重新猜。
> 注音、英文與數字符號模式依序切換，也支援符號、Emoji、30 種關聯詞庫與不同輸入
> 欄位。
>
> 琦琦注音也提供 macOS、Windows 與 Android 版本，讓常用的按鍵配置與選字習慣在
> 四個平台延續。鍵盤不要求完整取用權限，查字與選字都在裝置本機完成。

關鍵字：`注音,繁體中文,五排鍵盤,標準注音,輸入法,候選字,離線鍵盤`

## Google Play 內文

名稱：`琦琦注音輸入法`

簡短說明：

> ㄅ半注音的第一選擇：五排鍵盤、固定候選，觸控與實體鍵盤都能快樂輸入。

完整說明：

> 琦琦注音保留熟悉的五排標準注音鍵位，讓手指不用重新學習位置。多數手機鍵盤只有
> 四排，琦琦把完整注音排回來。候選字固定以
> 1–9 排列，接上 USB 或藍牙鍵盤後也能直接選字；可選擇跟隨游標的垂直或水平浮動
> 候選窗。
>
> 主要功能：
> • 五排標準注音觸控鍵盤
> • 注音、英文、數字符號模式
> • 固定 1–9 候選與 30 種關聯詞庫
> • 實體鍵盤、全形／半形與常用快捷鍵
> • Email、網址、電話、數字、搜尋等欄位模式
> • 按鍵預覽與可調整的震動回饋
>
> 琦琦注音也提供 macOS、Windows 與 iOS 版本，讓熟悉的輸入習慣在四個平台延續。
> 輸入法沒有網路權限，查字與選字都在裝置本機完成。

## 發布管道

- Android 1.2.7 使用簽署 AAB，已送交 Google Play「封閉測試 - Alpha」；測試地區為台灣
  與美國，測試人員透過 Play 提供的加入連結安裝。
- iOS 實機版本與商店素材由 Xcode Cloud／App Store Connect 管理；GitHub Actions 的 iOS
  ZIP 僅供 Apple Silicon Simulator 測試。
- macOS 與 Windows 的版本標籤會把桌面安裝包加入同一個 GitHub Release；商店圖 05
  使用兩個桌面平台的實際輸入畫面。

## 發布前檢查

`1206 × 2622` 是目前 iPhone 17 Pro Simulator 的原生尺寸，不把它誤標為 App Store Connect
接受的 6.5 吋素材；實際上傳使用 `1242 × 2688`。iPad 上傳版使用 `2048 × 2732`，Google
Play 手機圖保留 `1080 × 1920` 直式比例。畫布尺寸不任意縮短，而是放大內容填滿
安全區；所有來源圖與漫畫都等比例縮放，候選列不得裁掉 `1–9`。送審前仍須在 App Store
Connect 與 Play Console 預覽裁切、安全區、實際字數限制與要求的裝置尺寸。若產品頁只接受
真實 App 操作畫面，使用 `Sources` 原圖，不使用加字版。來源截圖使用專為擷取畫面建立的記事本
宿主，不含第三方品牌與商標。
