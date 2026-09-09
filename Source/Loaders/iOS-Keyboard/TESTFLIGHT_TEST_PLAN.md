# iOS TestFlight 自動化測試計畫

適用產品：琦琦注音 iOS（容器 App、keyboard extension、App 內實體鍵盤編輯器）

目的：以 automated smoke test 與 functional test 擋住不合格的 TestFlight build。

現況（2026-09-09）：下列為目標計畫，尚未全部啟用。線上的 `Default` workflow
僅於 `master` push 時執行 Archive 並準備分發至 App Store Connect，沒有 Test action
或分發群組後續動作。本機已加入 shared test plans、Release smoke cases 與 archive
驗證腳本；購買流程另以 `SupporterStoreTests` 的替代商店介面測試，尚無 StoreKit
configuration 或真機交易自動化。勿將 Cloud Archive 成功視為通過本文件全部 gate。

## 1. 自動化邊界

Xcode Cloud 的 Test action 會先 `build-for-testing`，再以 `test-without-building` 執行；
Archive action 則在另一個暫存環境執行 `xcodebuild archive`。因此 Test action 驗證的是
**相同 commit、scheme 與 configuration 的測試產物**，不是使用者從 TestFlight 下載的
那一份 archive。

本計畫分三層補齊這個邊界：

1. Archive 前：Swift tests＋XCUITest 自動擋版。
2. Archive 後：自動檢查正式 archive 的 bundle、版本、extension、資料庫、簽章與 entitlement。
3. TestFlight processing 完成後：確認 build 狀態並只發給 Internal Smoke 群組。

若一定要操作「從 TestFlight 安裝的同一份 binary」，另設本機真機 black-box runner：測試者
先安裝 build，獨立 UI test runner 再以 bundle identifier 啟動現有 App。這不能依賴 Xcode
Cloud 的臨時 Simulator，也不作為第一階段必備條件。

Apple 說明：

- [Xcode Cloud workflow actions](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions)
- [XCUIApplication 以 bundle identifier 啟動既有 App](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/init%28bundleidentifier%3A%29)

## 2. Pipeline

```text
Pull request
  └─ Functional Gate（Debug，必要通過）
       ├─ KeyKeyEngine unit tests
       ├─ Container／editor XCUITest
       └─ persistent Simulator extension XCUITest（本機 runner）

main／release candidate
  └─ TestFlight Gate（Release，必要通過）
       ├─ Smoke tests
       ├─ Functional tests
       ├─ Archive
       ├─ Archive structural verification
       └─ TestFlight Internal Smoke distribution

TestFlight build ready
  └─ Post-distribution checks
       ├─ App Store Connect build status／crash feedback
       └─ optional real-device black-box smoke
```

任何 required action 失敗，不得 archive 或分發新的 TestFlight build。

## 3. Smoke suite

目標：**10 分鐘內完成**，驗證「這個 build 值得進一步測」。每次 TestFlight candidate 必跑。

### Automated UI smoke

| ID | 自動案例 | 通過條件 | 現況 |
|---|---|---|---|
| S01 | 冷啟動容器 App | 8 秒內出現首頁，無 crash | 已有，可新增專用 test |
| S02 | Release UI 檢查 | 安裝說明、編輯器、支持、致謝可到達；無 Debug 入口 | 部分已有 |
| S03 | 開啟授權與致謝 | 內容包含 Yahoo! KeyKey 與 McBopomofo | 已有 |
| S04 | 開啟實體鍵盤編輯器 | 輸入區、1–9 候選、複製、分享、清除可操作 | 已有 |
| S05 | 編輯器最小輸入流程 | 以觸控備援鍵產生候選並選字，輸出區更新 | 待補 |
| S06 | extension 註冊 | 系統鍵盤清單能找到「琦琦注音」 | 已有 opt-in 測試 |
| S07 | 正式 App 設定入口 | 可從首頁開啟系統鍵盤設定並返回 | 待補 |
| S08 | 首頁旋轉與重啟 | 直／橫式無裁切；終止再啟動仍正常 | 待補 |

Smoke 不測完整符號表、全部詞庫或長時間壓力；那些屬於 functional suite。

### Automated archive smoke

Archive 完成後執行 shell verification，任何一項失敗即停止分發：

- 容器 App 與 `Keyboard.appex` 都存在。
- `Keyboard.appex/KeyKey.db` 存在、非空且只打包一份。
- App 與 extension 的 `CFBundleShortVersionString`、`CFBundleVersion` 一致。
- bundle identifiers 分別是容器 App 與 keyboard extension 的正式 ID。
- App 與 extension 均有正式 App Group entitlement。
- `RequestsOpenAccess = false`。
- 兩個 target 都含 `PrivacyInfo.xcprivacy`。
- `codesign --verify --deep --strict` 通過。
- Release build settings 不含 `DEBUG` compilation condition；`get-task-allow` 為 false。

## 4. Functional suite

目標：**30 分鐘內完成主要矩陣**。PR、main 更新與 TestFlight candidate 必跑；壓力測試可 nightly。

### A. Engine tests

沿用 `KeyKeyEngine` 現有測試，並以零失敗、零 unexpected skip 為門檻：

- 注音讀音、聲調、選字、退格與組字狀態。
- 候選查詢、翻頁、關聯詞與多字關聯。
- 英文、數字、符號、全半形與鍵盤 layout／metrics。
- 11 種 keyboard type 與 Return policy。
- document mutation guard。
- 候選色、詞庫設定與 supporter state 持久化。
- 記憶體 probe 與資料庫查詢。

命令：

```sh
cd Source/Loaders/iOS-Keyboard/KeyKeyEngine
swift test
```

### B. Container App／editor XCUITest

這組不需要預先選定第三方鍵盤，可在乾淨 Simulator 與 Xcode Cloud 全自動執行：

- 安裝說明、支持按鈕、恢復購買與授權頁。
- Debug host 的 14 種輸入欄位與 Return host。
- 實體鍵盤編輯器的候選、頁碼、詞庫、模式、符號與 emoji。
- 複製、分享、清除確認及 `Ctrl`／`Command` 快捷鍵。
- iPhone SE 直式、一般 iPhone 直／橫式、iPad 橫式四欄。
- 旋轉後 frame 穩定，候選內容不改變固定區塊。

### C. Keyboard extension XCUITest

這組需要 Simulator 已將琦琦注音加入並選成目前鍵盤：

- ㄅ→英→數→ㄅ。
- `ㄋㄧˇ` 選字與 inline marked text。
- 一般候選、關聯候選及多字關聯。
- 關聯候選顯示時 Enter 先關閉候選再換行。
- 詞庫切換後候選立即更新。
- 直／橫式核心按鍵與固定版面。

iOS 沒有受支援的 API 可靜默授予第三方鍵盤 opt-in；目前測試可以自動把鍵盤加入清單，
但在部分 Simulator runtime 無法穩定從 `InputSwitcherView` 切換到琦琦注音。因此：

- Xcode Cloud：跑 Container／editor suite，不把 extension 測試標成成功或 skip 後放行。
- persistent local Simulator：一次人工選定琦琦注音後，由 runner 全自動跑 extension suite。
- runner 發現任何 skipped extension test 時必須回傳非 0。

現有入口：

```sh
# 乾淨環境／Xcode Cloud 可跑
Source/Loaders/iOS-Keyboard/run-simulator-tests.sh --host-only

# 五台 persistent Simulator 已選定琦琦注音後跑完整 functional suite
Source/Loaders/iOS-Keyboard/run-simulator-tests.sh
```

### D. Nightly stability

只在 nightly 或準備 release 時執行，目標 20–30 分鐘：

- 500 次連續按鍵與選字。
- 100 次候選翻頁。
- 50 次 ㄅ／英／數、詞庫及候選色切換。
- 20 次前景／背景與 10 次直／橫旋轉。
- 測試結束後仍可完成 `ㄋㄧˇ` →「你」。
- 無 crash、hang、重複 commit、殘留 marked text 或 extension 終止。

## 5. Xcode test plans

實作時新增兩個 shared test plans：

| Test plan | 內容 | Configuration | 使用時機 |
|---|---|---|---|
| `KeyKeySmoke.xctestplan` | S01–S08；只使用正式 UI，不使用 Debug launch arguments | Release | TestFlight candidate |
| `KeyKeyFunctional.xctestplan` | 全部 UI functional tests | Debug | PR、main、nightly |

不要只靠 test method 名稱手動選取。每個 case 加入明確 test plan membership；Smoke
只能包含快速、可重跑且彼此不依賴順序的案例。測試資料、UserDefaults 與方向在 `setUp`／
`tearDown` 重置，禁止依賴上一個 test 留下的狀態。

建議把現有單一 `KeyKeyUITests` target 拆成：

- `KeyKeyHostSmokeTests`
- `KeyKeyHostFunctionalTests`
- `KeyKeyExtensionFunctionalTests`

若暫時不拆 target，至少在 test plan 內分 suite，避免 `--host-only` 長期依賴硬編碼 method 名稱。

## 6. Xcode Cloud workflows

### Workflow 1：PR Functional

- Trigger：iOS 路徑、共用資料表、DatabaseCooker 或 project 檔案變更的 pull request。
- `ci_post_clone.sh` cook `KeyKey.db`。
- Test action：`KeyKeyFunctional.xctestplan`，Debug。
- Destinations：最低支援 iPhone、最新 iPhone、最新 iPad。
- `Required To Pass = Yes`。
- 不 archive、不發 TestFlight。

### Workflow 2：TestFlight Candidate

- Trigger：合併到 main 或手動執行；建議手動才 distribute。
- Test action 1：`KeyKeySmoke.xctestplan`，Release，required。
- Test action 2：`KeyKeyFunctional.xctestplan`，Release，required。
- Archive action：Deployment Preparation 選 `TestFlight and App Store`。
- Post-action：前面 action 全綠才分發到 `Internal Smoke`。
- 外部群組不自動發佈；由 release owner promote 同一 build。

Xcode Cloud 的每個 action 使用獨立暫存環境，必須以 commit SHA、build number 與 workflow
run ID 串起 test result 與 archive，不能假設 test action 的 build artifact 就是 archive。

### Workflow 3：Nightly Stability

- Trigger：main 每晚或每週。
- Engine＋host functional＋stress tests。
- 只回報結果，不 archive。
- 連續兩次出現相同 flake 就建立缺陷，不以無限 retry 隱藏。

## 7. Post-TestFlight 自動檢查

TestFlight processing 完成後，用 App Store Connect API 或 Xcode Cloud 結果確認：

- marketing version／build number 與觸發的 commit 對得上。
- build 狀態可測，未卡在 invalid binary、missing compliance 或 processing。
- build 只先加入 `Internal Smoke`。
- TestFlight 的 sessions、crashes 與 feedback 可對應到正確 build。

若要全自動 promote，至少等 Internal Smoke 的 exact-binary black-box suite 通過；未建置真機
runner 前保持人工 promote，避免把「archive 成功」誤當成「功能測試成功」。

## 8. Exact-binary black-box smoke（第二階段）

在一台專用 iPhone／iPad 上：

1. 從 TestFlight 安裝指定 build。
2. 確認琦琦注音已加入系統鍵盤，完整取用保持關閉。
3. 由不依賴 App target build product 的獨立 XCUITest runner，以正式 bundle identifier 啟動 App。
4. 執行 S01–S08；若要測 extension，另以備忘錄作正式宿主；不得使用
   `-KeyKeyInputFieldTest` 或其他 Debug launch argument。
5. 將 `.xcresult`、build number、裝置與 OS 上傳為 release evidence。

這個 runner 應只使用正式 UI 可達流程；若測試需要 Debug host 欄位，那是 pre-archive functional
test，不屬於 exact-binary smoke。

## 9. StoreKit 自動化

拆成兩層：

- CI：使用 StoreKit configuration 測成功、取消、pending、恢復、撤銷、離線及 entitlement cache。
- TestFlight：sandbox 商品 availability 與至少一次實際購買／恢復仍需在真機驗證；完成真機
  runner 後再自動化 UI，不能用 CI StoreKit 結果代替 App Store server 路徑。

無論交易結果為何，鍵盤輸入功能都必須保持可用。

## 10. Gate 規則

| Gate | 條件 |
|---|---|
| PR merge | Engine 100% pass；host functional 100% pass；無 unexpected skip |
| Archive | Release smoke＋functional 全綠；archive structural verification 全綠 |
| Internal TestFlight | processing 完成、版本對應、無 invalid binary |
| External TestFlight | internal smoke 通過；無 P0／P1；crash 無新增趨勢 |
| App Store candidate | functional、nightly stability、StoreKit 真機路徑都有結果 |

失敗測試只允許針對已建立 issue、已證明是平台問題的 case 暫時 quarantine；quarantine 必須有
owner、到期日與替代驗證，不能用 skip 讓整體顯示綠燈。

## 11. 實作順序

1. 建立 `KeyKeySmoke.xctestplan` 與 `KeyKeyFunctional.xctestplan`，把現有 10 個 XCUITest 分組。
2. 把冷啟動與 Release UI 檢查補成獨立 smoke tests。
3. 新增 archive verification script，驗證 appex、DB、plist、privacy manifest、簽章與 entitlement。
4. 將五機 runner 改為接受 `--smoke`、`--functional-host`、`--functional-extension`。
5. 在 Xcode Cloud 建立 PR Functional 與 TestFlight Candidate workflows，所有 Test action 設 required。
6. 補 nightly stress tests。
7. 最後建立專用真機 exact-binary runner；在完成前保留 TestFlight 安裝後的短人工 smoke。

## 12. 每次 build 的自動報告

```text
Version / Build:
Commit SHA:
Xcode Cloud run:
Smoke: passed / failed / duration / xcresult
Engine functional: passed / failed / count / duration
Host functional: passed / failed / count / duration
Extension functional: passed / failed / skipped / duration
Archive verification: passed / failed
TestFlight processing: ready / invalid / waiting
Exact-binary smoke: passed / failed / not configured
Crash / hang delta:
Decision: block / internal only / promote external
```

最低完成標準：報告不能只有「Xcode Cloud succeeded」；必須分別顯示 smoke、functional、
extension、archive verification 與 TestFlight processing 狀態。
