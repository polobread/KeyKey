# Android Virtual Device 完整測試計畫

這份文件是琦琦注音 Android 版的必要回歸規格。只跑 JVM test、成功安裝 APK、打出一個字，
或只測實體鍵盤，都不能稱為「Android 測試完成」。每次準備提交 Android IME 行為、版面、
設定、字典或建置工具變更時，都必須依本文件完成自動檢查及六台 AVD 的人工功能矩陣。

## 完成條件

測試完成必須同時符合以下條件：

1. `lintDebug`、`testDebugUnitTest`、`assembleDebug` 全部成功。
2. API 26、28、30、33、35、37 六台 AVD 都以 cold boot 啟動，安裝同一個本次產生的 APK。
3. 每台 AVD 都完成「每台必測矩陣」全部項目；不可用另一個 API 的結果代替。
4. 每個方向都測觸控鍵盤；每台都測實體鍵盤的一般候選列與兩種浮動候選排列。
5. 所有欄位型態與 Enter action 都在 debug test host 實際取得焦點並驗證，不只看單元測試。
6. 沒有 KeyKey crash、ANR、`BadTokenException`、`InvalidDisplayException` 或持續 layout error。
7. 測試紀錄填入 commit、APK SHA-256、AVD/API、結果與失敗證據。任何必測項目為 `FAIL` 或
   `SKIP`，整輪結果就是未完成。

AVD 對應表：

| API | AVD 名稱 | 主要相容性界線 |
|---:|---|---|
| 26 | `Medium_Phone` | `minSdk`、舊 Window/InputMethod 行為 |
| 28 | `Medium_Phone_2` | Android 9、舊導覽列與 Play image |
| 30 | `Pixel_4a` | Android 11、edge-to-edge 前期行為 |
| 33 | `Pixel_5` | Android 13、通知與新 IME 行為 |
| 35 | `Pixel_8_Pro` | Android 15、display cutout／手勢導覽 |
| 37 | `Pixel_9_Pro_XL` | 最新預覽 API 的前向相容性 |

每台 AVD 都要跑兩個 cold-boot 階段：

1. `hw.keyboard=no`：驗證觸控鍵盤的直式、橫式、按鍵預覽、欄位模式及 Enter action。
2. `hw.keyboard=yes`：驗證一般實體候選列、浮動候選、全半形及實體按鍵行為。

只改 Android 的「顯示虛擬鍵盤」設定不夠，因為 IME 會依 `Configuration.keyboard` 正確判斷
實體鍵盤；兩階段必須在 AVD 停機後改 `config.ini` 並 cold boot。整輪結束要把六台 AVD 都
恢復為原本的 `hw.keyboard=yes`。測試期間不要操作同時連線的實體手機，ADB 指令一律指定
`-s emulator-XXXX`。

## 測試前準備

在 `Source/Loaders/Android-IME` 執行：

```sh
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
  ./gradlew lintDebug testDebugUnitTest assembleDebug
shasum -a 256 app/build/outputs/apk/debug/app-debug.apk
```

每台 AVD 的兩個鍵盤階段都必須 cold boot，等待 `sys.boot_completed=1` 後再執行：

```sh
adb -s emulator-XXXX install -r app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-XXXX shell ime enable tw.chichi77.keykey.android/.BopomofoImeService
adb -s emulator-XXXX shell ime set tw.chichi77.keykey.android/.BopomofoImeService
adb -s emulator-XXXX shell am start -n \
  tw.chichi77.keykey.android/.ImeTestActivity
```

`ImeTestActivity` 只存在 debug APK，集中提供所有 `inputType`、標準 Enter action、自訂 action
與 `IME_FLAG_NO_ENTER_ACTION`。release APK 不包含它。為了讓 ADB 回歸可重複設定狀態，test host
接受 `--es floating off|vertical|horizontal`、`--ez keyPreview true|false`、
`--ei hapticLevel 0..8` 及 `--es phrases none|base`；這些 hook 也只存在 debug build。

每次開始一台 AVD 前清除 logcat；完成後保留截圖、畫面錄影或文字紀錄，並檢查：

```sh
adb -s emulator-XXXX logcat -c
adb -s emulator-XXXX logcat -d -b crash
adb -s emulator-XXXX shell dumpsys input_method
adb -s emulator-XXXX shell dumpsys window | rg 'KeyKey candidate window|BadToken|InvalidDisplay'
```

## 每台必測矩陣

以下 A 到 L 必須在六台 AVD 各跑一次。

### A. 安裝、首頁與設定

- 首頁可啟動，狀態列、cutout、導覽列不遮住標題、說明與三個按鈕。
- 「啟用輸入法」、「選擇琦琦注音」、「調整設定」都能開啟正確頁面。
- 設定頁可完整捲動，九段震動、觸控按鍵預覽、實體浮動候選、直／橫排列與 30 個詞庫均存在。
- 重開 App／切換輸入欄位後，震動、預覽、浮窗排列、全半形及詞庫選擇維持預期狀態。

### B. 觸控鍵盤直式與橫式

直式與橫式各自驗證：

- 候選列、四排 11 個等寬鍵及功能列完整；沒有裁切、重疊、跳位或被系統地球鍵／手勢條遮住。
- 直式保留 40dp、橫式保留 35dp 系統區；橫式內容高度及小字仍清楚可讀。
- 注音與實體鍵位雙標籤正確，直式聲調 `ˊˇˋ˙` 大小、位置及鍵位 baseline 正常。
- Enter 外框、Backspace、Shift、Emoji、符、設、逗號、空白、句號均正常顯示。
- 旋轉時正在組的字、候選與鍵盤模式不會 crash；旋轉後再重新輸入可正常選字。

### C. 注音組字、候選與編輯

- 輸入 `ㄋㄧˇ`，reading、composing 與候選正確；選第一個候選只送出中文字，不留下原始注音。
- 候選可直接點選；▲／▼、左右滑動與候選開啟時的空白可循環翻頁，首尾頁能互相循環。
- `Backspace` 依序移除聲調、韻母、介音、聲母；reading 空後才刪 editor 文字。
- 送出含變體、膚色或 ZWJ 的 Emoji，Backspace 一次刪除一個完整可見圖形。
- 組字／候選開啟時，以觸控改游標及建立 selection，舊 reading 必須清除；IME 自己更新 composing、
  確定候選及產生關聯詞時不可被誤清。
- 一般候選角標為 1–9；沒有候選時角標仍留在候選格中，不閃爍或被清空。

### D. `ㄅ → 英 → 數 → ㄅ` 與 Shift

- 模式鍵依序切換注音、英文、數字符號並循環；三態文字分別為 `英/數`、`數/ㄅ`、`ㄅ/英`。
- 注音模式按 Shift 暫時切英文小寫，雙標籤上下交換；輸入一個觸控字元後立刻回注音。
- 英文模式 Shift 在小寫／大寫間持續切換；大寫時數字排顯示 `!@#…`。
- 數字符號模式 Shift 只切兩套 44 鍵符號頁，不離開數字符號模式。
- 實體 Shift 不得改變觸控鍵盤模式。

### E. 觸控按鍵預覽與震動回饋

- 預覽開啟時，按住文字、注音、英文、數字及符號鍵，手未離開前附近顯示約 1.4 倍大字。
- 左右邊緣鍵的預覽不超出螢幕；滑出原鍵、放開或取消時立刻消失。
- 功能鍵、候選字及實體鍵盤候選列不顯示按鍵預覽；預覽本身不新增可點擊範圍。
- 關閉設定後不再顯示，重新開啟立即恢復。
- 九段震動逐段可設定；0 不震動，非 0 的可用鍵有回饋；disabled key、滑出取消與預覽 overlay
  不可額外震動。AVD 無法代表真機手感，但仍須確認沒有 vibrator/security error；實際強度另列真機驗收。

### F. 符號、Emoji 與標點

- 「符」開啟 90 個符號，共 10 頁，每頁 9 個；可點選、循環翻頁及返回一般候選狀態。
- Emoji 開啟 90 個表情，共 10 頁，每頁 9 個；沒有中文字候選時仍可開啟。
- 逗號、句號及兩套數字符號頁能送出畫面所示字元。
- 選符號或 Emoji 後不殘留舊 reading，也不誤進關聯詞選字規則。

### G. 欄位型態

在 debug test host 逐欄取得焦點，直式與橫式各驗一次；位置固定，不能用移除按鍵造成跳版。
淡化的鍵必須無 hit、無輸入、無震動：

| test host 欄位 | 預設模式 | 可循環模式 | 必查按鍵 |
|---|---|---|---|
| 一般文字、姓名、地址、搜尋欄、簡訊、長文字 | ㄅ | ㄅ／英／數 | 全功能可用 |
| Email | 英 | 英／數 | `@._-` 可用；空白、注音、Emoji 淡化 |
| 網址 URL | 英 | 英／數 | `:/?&=._-` 可用；空白、注音、Emoji 淡化 |
| 密碼、ASCII 限定 | 英 | 英／數 | 僅 ASCII；注音、Emoji 淡化 |
| 電話 | 數 | 僅數 | `0–9 +-*#() 空白` 規則正確 |
| 整數 | 數 | 僅數 | 只有數字；無號整數的 `-` 淡化 |
| 有號整數 | 數 | 僅數 | 數字與 `-` 可用 |
| 小數 | 數 | 僅數 | 數字與 `.` 可用；無號小數的 `-` 淡化 |
| 有號小數 | 數 | 僅數 | 數字、`.`、`-` 可用 |
| 日期、時間、日期／時間 | 數 | 僅數 | `0–9 / : - . 空白` 規則正確 |

App 若錯報或不報 `inputType`，確認安全退回一般文字，不 crash。實體鍵盤在上述所有欄位仍保留
完整按鍵與快捷鍵，不由 IME 擋字；欄位是否接受內容由 host 決定。

### H. Enter action

在 debug test host 的八個 action 欄位，直式與橫式各驗一次：

- `DONE/NEXT/SEARCH/SEND/GO/PREVIOUS` 顯示「完成／下一個／搜尋／傳送／前往／上一個」，
  點擊後上方 `Action result` 顯示正確 action ID。
- 自訂 action 顯示「送出表單」，點擊後回報 action ID 42；長標籤不得裁切鍵盤。
- `IME_FLAG_NO_ENTER_ACTION` 顯示普通 Enter，送 key event，不呼叫標準 action。
- 有 reading 或候選時 Enter 先確定輸入；沒有 reading／候選才執行 editor action。
- 實體鍵盤 Enter 在所有 action 欄位永遠維持 plain Enter key event。

### I. 實體鍵盤一般候選列

先關閉「實體鍵盤使用浮動候選字窗」：

- 直式／橫式都是 12 個等寬格：9 候選、Emoji、`ㄅ／英`、`半／全`，沒有 ▲／▼。
- 空候選格仍固定顯示 1–9 小角標；模式格只有 `ㄅ／英`，不可出現第三個「數」。
- `1–9` 選一般候選，`Shift+1–9` 選關聯詞，`Page Up/Down` 與空白循環翻頁。
- 點擊語言與全半形格可切換；Emoji 在沒有候選時仍可點。
- `Ctrl+Space` 切注音／英文；`Ctrl+0`、`Ctrl+1` 開符號；`Ctrl+,`、`Ctrl+.` 送全型逗句號。
- 所有 shortcut 的 keydown/keyup/長按不重複或漏字。AVD console 無法忠實產生的 modifier 組合，
  必須另以真實 USB／藍牙鍵盤驗收，不能用 `adb shell input keycombination` 冒充通過。

### J. 全形／半形

- 點候選列的 `半／全` 及實體 `Shift+Space` 都能切換，且保留目前 reading／候選。
- 全形模式依序驗證 `Ａｚ０９！～　`；切回半形後同鍵輸出 ASCII。
- 中文與非 ASCII 不轉換；空白 repeat 不得在切換全形時漏進 editor。
- 全半形只影響實體鍵盤，不改觸控鍵盤輸出。

### K. 實體鍵盤浮動候選

開啟浮動候選，垂直與水平排列都測：

- IME 底部只保留維持 token 的 1dp view；候選出現時 Window 附掛成功且原欄位不失焦。
- 有 `CursorAnchorInfo` 時跟隨游標，靠近上下左右邊界時不超出可用畫面；沒有座標時落在底部中央。
- 垂直：上下移反白、左右換頁；水平：左右移反白、上下換頁。
- 1–9、方向鍵、Enter、ESC、Page Up/Down、觸控選字皆正確；長候選省略但送出完整文字。
- 切換直／橫排列立即套用；旋轉畫面、切換 App、收放鍵盤後可重新附掛，不累積殘留 Window。
- 若附掛/token 失敗，約 1.5 秒後自動關閉浮窗、切回一般實體候選列，設定頁持續顯示原因。
  重新勾選時原因暫時清掉並再試；再次失敗要再次記錄。成功環境不可被錯誤停用。

### L. 詞庫切換、關聯詞與穩定性

- 初次安裝為「僅小麥注音」；驗證「全部啟用」、「僅小麥注音」、「全部關閉」及任選多詞庫。
- 已啟用數量與 30 個 checkbox 一致；重開設定頁及重新顯示鍵盤後仍保持。
- 確定單一中文字才顯示關聯詞尾；選取只接上詞尾。輸入下一個注音會關閉關聯詞且不偷送第一項。
- 全部關閉時沒有關聯詞；多詞庫混合依設定中的 source 順序排序、跨庫重複只留第一筆。
- 一般候選用 1–9；關聯詞實體選字用 Shift+1–9，但角標仍顯示 1–9。
- 連續切換欄位、App、方向、模式、詞庫與浮窗至少 10 次，不能 crash、ANR、黑屏、候選消失或
  SharedPreferences 狀態損壞。

## 測試紀錄模板

每輪複製下表到 issue、commit note 或測試紀錄，附上失敗截圖／log 路徑：

| 日期 | commit | APK SHA-256 | API/AVD | A–L | crash/ANR | 證據／備註 |
|---|---|---|---|---|---|---|
| YYYY-MM-DD | `<sha>` | `<sha256>` | 26 / Medium_Phone | PASS/FAIL | PASS/FAIL |  |
| YYYY-MM-DD | `<sha>` | `<sha256>` | 28 / Medium_Phone_2 | PASS/FAIL | PASS/FAIL |  |
| YYYY-MM-DD | `<sha>` | `<sha256>` | 30 / Pixel_4a | PASS/FAIL | PASS/FAIL |  |
| YYYY-MM-DD | `<sha>` | `<sha256>` | 33 / Pixel_5 | PASS/FAIL | PASS/FAIL |  |
| YYYY-MM-DD | `<sha>` | `<sha256>` | 35 / Pixel_8_Pro | PASS/FAIL | PASS/FAIL |  |
| YYYY-MM-DD | `<sha>` | `<sha256>` | 37 / Pixel_9_Pro_XL | PASS/FAIL | PASS/FAIL |  |

真實 USB／藍牙 modifier、震動手感、Play Billing 及不同廠牌客製 editor 是實機／服務驗收，
不能由 AVD 證明；它們不取代本文件的 AVD 矩陣，AVD 也不取代這些發布前驗收。
