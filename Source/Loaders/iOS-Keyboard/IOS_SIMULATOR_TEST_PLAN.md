# iOS Simulator 測試計畫

每次 iOS 鍵盤有功能、版面、資料庫或 Xcode 基礎調整時，完成本計畫才可標記為「iOS 測試完成」。引擎單元測試與 App 建置是必要前置，但不能取代實際 keyboard extension 測試。

## 受控 Simulator

| 名稱 | 用途 | 必測項目 |
|---|---|---|
| KeyKey iOS 17 iPhone 12 | 最低可取得 iOS 17 runtime、舊一代裝置 | 全部 A–K |
| KeyKey iOS 18 iPhone 15 | 中間系統版本 | 全部 A–K |
| KeyKey iOS 26 iPhone 17 Pro | 最新系統、主要開發機 | 全部 A–K |
| KeyKey iOS 26 iPhone SE | 小螢幕與窄鍵位 | 全部 A–K，尤其 B、C |
| KeyKey iOS 26 iPad | iPad 尺寸與橫式 | 全部 A–K，尤其 B、C、J |

在 `Window → Devices and Simulators` 記錄每台實際 Runtime patch 版；名稱中的「iOS 17」不等同保證 17.0。若之後 Xcode 能安裝 17.0 Runtime，另建一台 iPhone 12 並把 A–K 全跑一次。

目前已確認的 Runtime（2026-09-02）：iPhone 12 是 **iOS 17.0**、iPhone 15 是 **iOS 18.6**、三台 iOS 26 裝置是 **iOS 26.5**。

最近一次自動基線（2026-09-02）：`run-simulator-tests.sh --host-only` 的 79 個 Swift 測試與五台 Simulator 各 3 個 UI tests 全部通過；每台都驗證宿主／extension 安裝註冊、設定 opt-in、14 種欄位可到達，以及 App 內完整授權告知可開啟。這不是 A–K 完成紀錄，extension-required 與下列人工項目仍須另跑。

## 前置

1. 在每台 Simulator 安裝 Debug container app。
2. 到 `設定 → 一般 → 鍵盤 → 鍵盤 → 加入新的鍵盤` 啟用「琦琦注音」；不開啟完整取用權限。
3. 開啟 container app 的「開啟輸入欄位測試」，點選欄位後用地球鍵切到琦琦注音。
4. 每個項目先跑淺色，再切深色重跑與顏色有關的檢查。

## 矩陣

| 區塊 | 檢查內容 | 通過條件 |
|---|---|---|
| A. 啟動與切換 | 冷啟動、App 前後切換、切換系統鍵盤再切回 | 不 crash、不白畫面、不遺留舊讀音或候選 |
| B. 方向與尺寸 | 各機直式與橫式；iPad 直橫式 | 11 欄完整、無裁切／重疊；SE 按鍵仍可按；iPad 鍵盤置中且不過寬 |
| C. 按鍵回饋 | ㄅ、英、數模式、Shift、符、Enter 長按與放開 | 按住顯示放大內容；模式依序 ㄅ→英→數→ㄅ；鬆手即消失；按鍵音開關立即生效 |
| D. 注音與組字 | 輸入讀音、聲調、空白開候選、選候選、退格、取消、連續輸入 | 欄位中顯示 marked 讀音；選字取代讀音，不得出現 `ㄋㄧˇ你`；退格／取消不把讀音留在欄位 |
| E. 候選與詞庫 | 9 候選、翻頁、滑動翻頁、選關聯詞、設定啟用／關閉／全部操作 | 頁碼與候選正確；詞庫調整即時生效；關聯詞不鏈式重複出現 |
| F. 英數與符號 | 英文 Shift、數字兩面、90 符號、90 emoji、全半形標點 | Shift／模式狀態正確；頁面可完整選取；禁用鍵淡化且不可點 |
| G. 輸入欄位 | Debug host 的一般、Email、URL、電話、整數、小數、日期時間、密碼、姓名、地址、搜尋、長文字、ASCII、ASCII 數字 | keyboardType 對應模式與可按字元正確；密碼／電話被 iOS 換成系統鍵盤時記為預期系統限制 |
| H. Return 鍵 | 逐一選一般、Email、URL、姓名、搜尋、地址、ASCII、ASCII 數字欄位 | 顯示換行、傳送、前往、加入、搜尋、繼續、路線、緊急等對應短標示；按下不 crash，組字中先選字 |
| I. 可用性 | VoiceOver、Dynamic Type 最大、淺色／深色 | 禁用鍵不在可操作焦點；候選與功能鍵有可理解標籤；文字與選取色可讀 |
| J. 設定與隱私 | 按鍵音重開 extension 後仍維持；Full Access 關閉 | 設定持久；不要求完整取用；不宣稱支援震動 |
| K. 壓力與資料 | 快速連按、連續輸入、頻繁切換詞庫、背景／前景循環 | 無 crash、無卡死、無重複 commit、無記憶體警告／extension 被系統終止 |

## 自動化與記錄

### 五機 runner

先跑可無人值守的基線（引擎單元測試、安裝／啟用 extension、14 種宿主欄位）：

```sh
Source/Loaders/iOS-Keyboard/run-simulator-tests.sh --host-only
```

在五台都已切到琦琦注音後，跑 extension-required 套件：

```sh
Source/Loaders/iOS-Keyboard/run-simulator-tests.sh
```

runner 會依名稱尋找本計畫的五台 Simulator、等待開機、共用 DerivedData，並為每台留下獨立 `.xcresult`。可用 `KEYKEY_IOS_TEST_OUTPUT=/path` 指定輸出目錄；否則寫入暫存目錄。任何找不到的裝置、啟動失敗或測試失敗都會繼續跑剩餘裝置，最後以非 0 結束並列出五機摘要。

### 目前自動涵蓋

| 自動項目 | 對應區塊 | 說明 |
|---|---|---|
| Swift 引擎單元測試 | D–H、K 的純邏輯 | runner 開始時只跑一次 |
| 設定導覽與鍵盤 opt-in | A、J 前置 | XCUITest 只操作受控 Simulator；iOS 26 的標籤是「新增鍵盤」 |
| 14 種 Debug host 欄位可到達 | G、H 宿主側 | 驗證欄位存在、可捲動到且可點擊 |
| ㄅ→英→數→ㄅ、`ㄋㄧˇ` 選字 | C、D、F | 只有目前軟體鍵盤已是琦琦注音時執行 |
| 直式／橫式核心按鍵可見可點 | B | iPhone 與 iPad 都執行；要求 extension 已選定 |

iOS 的第三方鍵盤 opt-in 與「目前輸入法」是兩件事。XCUITest 可以自動把琦琦注音加入系統清單，但 iOS 26 的 `InputSwitcherView` 可能只把選項反白而不接受合成 tap／drag，因此 runner 不會把「已加入」誤當成「已切換」。無人值守時用 `--host-only`；完整模式會要求 extension，不能取得 `keyboard.status` 就直接失敗。

按住時的放大預覽、按鍵音、VoiceOver 實際朗讀、顏色視認、連續壓力與 iOS 強制換回 secure／phone 系統鍵盤等仍需依 A–K 人工確認。每次在 commit／PR 說明記錄：runner 模式、實際 runtime patch、五台裝置、自動結果、人工通過區塊及任何已知系統限制；不能只寫「XCUITest 通過」就宣稱 A–K 完成。

## 平台邊界

- iOS keyboard extension 不接收硬體鍵盤事件，也不能提供 Android 的實體鍵盤候選列或浮動候選窗；不列為 iOS 缺陷。
- `secureTextEntry`、`phonePad` 與部分 `namePhonePad` 欄位可由 iOS 強制換回內建鍵盤；這是系統安全策略。
- `returnKeyType` 讓鍵盤顯示宿主意圖；第三方鍵盤只能送出換行文字，宿主是否把它當作「下一個／搜尋／傳送」由宿主 App 決定。
