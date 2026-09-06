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

實體鍵盤編輯器最近一次針對性版面回歸（2026-09-06）：93 個 Swift 測試通過；iOS 26.5 的 iPhone 17 Pro 與 4.7 吋 iPhone SE 通過入口、直橫式控制項與旋轉復原 UI 測試，iOS 26.5 iPad 通過橫式四欄測試。這是針對本次編輯器改版的回歸結果，不等於五台 Simulator 的完整 A–K 矩陣。

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
| E. 候選與詞庫 | 9 候選、翻頁、滑動翻頁、選關聯詞、設定啟用／關閉／全部操作 | 頁碼與候選正確；詞庫調整即時生效；關聯詞不鏈式重複出現；一般候選第一項反白；關聯候選顯示時 Enter 關閉推薦並換行，不誤選詞尾 |
| F. 英數與符號 | 英文 Shift、數字兩面、90 符號、90 emoji、全半形標點 | Shift／模式狀態正確；頁面可完整選取；禁用鍵淡化且不可點 |
| G. 輸入欄位 | Debug host 的一般、Email、URL、電話、整數、小數、日期時間、密碼、姓名、地址、搜尋、長文字、ASCII、ASCII 數字 | keyboardType 對應模式與可按字元正確；密碼／電話被 iOS 換成系統鍵盤時記為預期系統限制 |
| H. Return 鍵 | 逐一選一般、Email、URL、姓名、搜尋、地址、ASCII、ASCII 數字欄位 | 顯示換行、傳送、前往、加入、搜尋、繼續、路線、緊急等對應短標示；按下不 crash，組字中先選字 |
| I. 可用性 | VoiceOver、Dynamic Type 最大、淺色／深色；紫／綠／黃／紅四種候選底色 | 禁用鍵不在可操作焦點；候選與功能鍵有可理解標籤；黃底黑字、其餘白字，文字與選取色可讀 |
| J. 設定、支持與隱私 | 按鍵音與候選底色重開 extension 後仍維持；extension 與容器編輯器各自保存詞庫且不互相覆寫；新安裝候選底色為紫色；一次性支持在未滿 30 天、滿 30 天、已購買、恢復購買、待處理、取消、退款／撤銷及離線狀態；Full Access 關閉 | 各 target 的設定持久且切換後立即套用，只有首次使用與支持狀態透過 App Group 共用；未購買仍可完整使用；只有滿 30 天且未支持時在空白注音狀態顯示提示；成功購買／恢復後 extension 讀到 App Group 授權並永久隱藏；待處理或取消不誤授權；不要求完整取用；不宣稱支援震動 |
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
| 候選底色設定單元測試 | I、J 的純邏輯 | 驗證預設紫色、未知值降級與四種設定持久化 |
| 一次性支持狀態單元測試 | J 的純邏輯 | 驗證未滿／剛滿 30 天、已支持與 App Group UserDefaults 持久化 |
| 支持開發入口 UI 測試 | J 宿主側 | 驗證容器 App 的購買與恢復購買控制項可捲動到且可操作 |
| 實體鍵盤編輯器入口 UI 測試 | J 宿主側 | 驗證共用字庫成功載入、固定直排 1–9 候選、`1/n` 頁碼、插入游標、詞庫、ㄅ／英、半／全、符號、`🙂`、Esc／Backspace／Enter／四方向／空白、右上角快捷鍵說明，以及直式底部橫排的清除／複製／分享控制項；直式候選有無不可造成任何區塊位移；4.7 吋 iPhone SE 直式須套用緊湊輸入區，讓 1–9 候選、頁碼及全部操作鍵保持可見可點；橫式固定由左至右為輸入、候選、按鍵、動作四欄，最右欄由上至下排列清除／複製／分享文字；iPad 保留方向鍵與空白，iPhone 高度不足時收起這組輔助鍵；直式轉橫式再轉回直式後，各區塊須精確恢復旋轉前的 frame；一般候選 1–9、關聯詞 `Shift+1–9`、Space／Page Up／Page Down 翻頁、`Ctrl+C`／`⌘C` 複製、`Ctrl+S`／`⌘S` 分享、`Ctrl+K`／`⌘K` 開啟清除確認窗及以 Enter 確認／Esc 取消、無候選時方向鍵移動游標須另用真機人工測試 |
| 設定導覽與鍵盤 opt-in | A、J 前置 | XCUITest 只操作受控 Simulator；iOS 26 的標籤是「新增鍵盤」 |
| 14 種 Debug host 欄位可到達 | G、H 宿主側 | 驗證欄位存在、可捲動到且可點擊 |
| ㄅ→英→數→ㄅ、`ㄋㄧˇ` 選字 | C、D、F | 只有目前軟體鍵盤已是琦琦注音時執行 |
| 直式／橫式核心按鍵可見可點 | B | iPhone 與 iPad 都執行；要求 extension 已選定 |

iOS 的第三方鍵盤 opt-in 與「目前輸入法」是兩件事。XCUITest 可以自動把琦琦注音加入系統清單，但 iOS 26 的 `InputSwitcherView` 可能只把選項反白而不接受合成 tap／drag，因此 runner 不會把「已加入」誤當成「已切換」。無人值守時用 `--host-only`；完整模式會要求 extension，不能取得 `keyboard.status` 就直接失敗。

按住時的放大預覽、按鍵音、VoiceOver 實際朗讀、顏色視認、連續壓力與 iOS 強制換回 secure／phone 系統鍵盤等仍需依 A–K 人工確認。每次在 commit／PR 說明記錄：runner 模式、實際 runtime patch、五台裝置、自動結果、人工通過區塊及任何已知系統限制；不能只寫「XCUITest 通過」就宣稱 A–K 完成。

StoreKit 真實交易必須另用 Sandbox Apple ID 或 Xcode StoreKit 測試環境驗證：確認商品顯示
地區化價格、成功交易只授權一次、`pending`／取消不授權、重新安裝後可恢復、退款或撤銷後
會移除 entitlement，以及商店暫時無法連線時不會阻塞鍵盤輸入。Simulator runner 不會代替
App Store 的伺服器交易驗證。

## 平台邊界

- iOS keyboard extension 不接收硬體鍵盤事件，也不能提供 Android 的系統級實體鍵盤候選列或浮動候選窗；不列為 iOS 缺陷。容器 App 的「實體鍵盤編輯器」只能在琦琦 App 前景接管 USB／藍牙鍵盤，完成後以複製或分享把文字送往其他 App。
- `secureTextEntry`、`phonePad` 與部分 `namePhonePad` 欄位可由 iOS 強制換回內建鍵盤；這是系統安全策略。
- `returnKeyType` 讓鍵盤顯示宿主意圖；第三方鍵盤只能送出換行文字，宿主是否把它當作「下一個／搜尋／傳送」由宿主 App 決定。
