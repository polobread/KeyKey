# iOS 鍵盤

琦琦注音的 iOS 版：一個 custom keyboard extension，加上帶安裝引導的容器 App。

```
KeyKeyEngine/     Swift Package，純邏輯，可用 swift test 在 Mac 上驗
ContainerApp/     容器 App（安裝引導）
Keyboard/         UIInputViewController extension
KeyKeyiOS.xcodeproj
```

## 建置

```sh
xcodebuild -project KeyKeyiOS.xcodeproj -scheme "chichi77 KeyKey" \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

引擎的測試不需要模擬器：

```sh
cd KeyKeyEngine && swift test
```

首次在一台新機器上需要先取得模擬器 runtime：`xcodebuild -downloadPlatform iOS`。

## 與其他平台的差異

- **引擎是 Swift 重寫**，不載入 `Source/Frameworks` 的 C++ core。
- **但資料層走已 cook 好的 `KeyKey.db`**，不像 Android 在執行時解析 `.cin`。
  keyboard extension 的記憶體上限約 60 MB，超過會被系統直接終止且沒有 crash
  log；SQLite 只映射查詢用到的頁，資料層常駐足跡不到 1 MB。
- `Mandarin-bpmf-cin` 的 key 是 Formosa 的 absolute-order 編碼，不是鍵盤按鍵，
  所以 `BopomofoSyllable` 必須實作該編碼才查得到東西。
- **`RequestsOpenAccess = false`**：不連網、設定存在 extension 自己的沙箱。代價是
  iOS 把 `UIFeedbackGenerator` 綁在這個權限後面，因此沒有按鍵震動。
- **沒有實體鍵盤支援與浮動候選窗**：extension 收不到硬體按鍵事件，也只能在自己的
  input view 內繪製。
- **沒有 inline 組字**：`UITextDocumentProxy` 沒有 marked text API，注音讀音顯示在
  鍵盤自己的畫面，不會出現在目標 App 的文字欄位。

`KeyKeyiOS.xcodeproj/xcshareddata/xcschemes` 內的 scheme 必須保留在版控中 ——
Swift Package 依賴只有透過 scheme 才會被建置，`-target` 不會。
