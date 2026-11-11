# KeyKey 1.5.1 六平台發布準備

1.5.1 是 Windows、macOS、iOS、Android、Linux 與 FreeBSD 的產品版號。本版新增 Android 與 iOS 的鍵盤高度拖曳、漢語拼音鍵盤和好打注音的「省略聲調」選項。功能與使用方式見 [1.5.1 更新紀錄](../CHANGELOG.md#151)。

好打注音共用 [1.5.0 模型](../DataSource/AISyntheticBigram/smart-mandarin-model-manifest.json)。Guanyinma 核心沿用既有資料格式，從舊核心升級及各平台驗收方式見 [1.5.0 發布準備](CROSS_PLATFORM_V1_5_0_RELEASE.md)。舊版的測試與發布紀錄可用於比對。1.5.1 須用本版產物重新確認建置、安裝或宿主行為。

| 平台 | 產品版號來源 | 發布管道 |
|---|---|---|
| macOS | [IMK plist](../Source/Loaders/OSX-IMK/Takao-Info.plist) 的兩項版號，並核對偏好設定、詞彙編輯器、安裝說明三份 plist | GitHub Release，Developer ID 簽章與公證 |
| Windows | [TSF CMakeLists.txt](../Source/Loaders/Windows-TSF/CMakeLists.txt) | GitHub Release，Certum 本機簽章與人工發布 |
| Linux／FreeBSD | [Linux CMakeLists.txt](../Source/Loaders/Linux-IME/CMakeLists.txt) | Linux 使用 GitHub Release，FreeBSD 透過 ports／pkg |
| iOS | [Xcode 專案](../Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj/project.pbxproj) 中 App 與鍵盤的 `MARKETING_VERSION` | App Store Connect 送審 |
| Android | [app/build.gradle.kts](../Source/Loaders/Android-IME/app/build.gradle.kts) 的 `keyKeyVersionName` 與 `keyKeyVersionCode`（`1005001`） | Google Play 內部測試後由 Play Console 推廣 |

驗收手機版時，請確認能拖曳鍵盤上下緣，直式與橫式分開儲存高度。也請用好打注音與傳統注音檢查漢語拼音，並在好打注音確認「省略聲調」預設關閉。開啟後，用標準注音輸入 `ㄋㄧㄏㄠ` 或用漢語拼音輸入 `nihao`，應能看到「你好」候選，仍可使用聲調鍵。

桌面 [v1.5.1 Release](https://github.com/polobread/KeyKey/releases/tag/v1.5.1) 資產、商店上架與 FreeBSD 套件須各自確認。正式資產建置後，按[建置與打包流程](../BUILDING.md)驗證來源、版號、簽章與校驗檔。依[桌面更新流程](../update/README.md)在正式資產驗證後推進公告。
