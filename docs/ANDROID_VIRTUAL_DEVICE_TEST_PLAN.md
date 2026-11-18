# Android Virtual Device 完整測試計畫

這份文件是琦琦輸入法 Android 完整發布驗收的回歸規格。只跑 JVM test、成功安裝 APK、打出一個字，
或只測實體鍵盤，都不能稱為完整 Android 驗收。目前採 Guanyinma 單核心，完整核心演算法矩陣由
`guanyinma-core.yml` 負責；日常變更依實際受影響的 FE 設定、事件、宿主、版面或建置範圍執行，
不因純文件或核心局部修改要求六台 AVD 全套。明確進入完整發布驗收時，再依下列裝置矩陣執行並保存
同一最終來源 APK 的證據；來源、版號與正式發布狀態分開核對，建置與發布入口見 [BUILDING.md](../BUILDING.md)。

Pixel 11 開啟「整合底部控制鍵」一段時間後的第一排遮擋症狀與待蒐集資料，見 [Android 直式鍵盤第一排遮擋調查](ANDROID_IME_TOP_ROW_CLIPPING_INVESTIGATION.md)。

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

先依 [Android 建置說明](../Source/Loaders/Android-IME/README.md#建置) 準備已修補的完整 Corretto JDK 25，
把下例 `JAVA_HOME` 換成實際位置，再於 `Source/Loaders/Android-IME` 執行：

```sh
JAVA_HOME='/path/to/patched-corretto-25/Contents/Home' \
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
`--ei hapticDurationMs 0|1|2|3|5|10|20|30|50|100`、
`--ei portraitHeightPercent 50|75|90|100|110|125|150|175|200`、
`--ei landscapeHeightPercent 50|75|90|100|110|125|150|175|200` 及
`--es phrases none|base|all`；這些 hook 也只存在
debug build。另可用 `--ez bigram true|false` 切換上下文選字，
以 `--es cursorUpdates silent|reject` 模擬接受請求卻無回報／拒絕請求的 App；
省略或使用 `normal` 恢復正常游標回報。`--ei hapticLevel 0..8` 只保留給舊自動化相容使用。

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

- 首頁可啟動，標題下顯示與 APK 一致的版本號；狀態列、cutout、導覽列不遮住標題、
  版本、說明與三個按鈕。
- 「啟用輸入法」、「選擇琦琦輸入法」、「調整設定」都能開啟正確頁面。
- 設定頁可選好打注音、傳統注音、倉頡與簡易；「繁體中文轉簡體」位於輸入法下方，預設關閉。
  四個收合區塊為「注音與選字」、「倉頡與簡易」、「外觀與操作」及「實體鍵盤」。
  各選項右側的 ⓘ 可開啟說明窗，關閉後仍留在同一設定位置。「好打注音說明」使用相同入口，
  不再顯示舊版的注音鍵盤／上下文摘要列。「好打注音省略聲調」預設關閉，排在
  「好打注音使用空白鍵選字」之前；五種注音鍵位均可選。
  「外觀與操作」提供「調整鍵盤高度」、版面、鍵帽間隔、字體、刪除鍵位置、震動、按鍵預覽及候選底色。
  高度以拖曳預覽調整，沒有直式／橫式百分比選單；新安裝採目前方向的預設高度與底部留白，候選底色為紫色。
  關聯詞詞庫從琦琦輸入法 App 的獨立頁面調整，鍵盤設定不再列出所有詞庫 checkbox。
  旋轉後保持展開與捲動位置；「支持開發」依未贊助／已贊助狀態顯示原有位置與感謝文字。
- 重開 App／切換輸入欄位後，震動、兩個虛擬鍵盤高度、預覽、候選底色、浮窗排列、
  全半形及詞庫選擇維持預期狀態。

- 「好打注音使用上下文選字（Bigram）」新安裝預設開啟；切換並重開 App 後保留選擇。
  開／關各測一次好打的觸控、實體一般候選與直／橫浮窗；關閉時可整句輸入、選字、
  使用自訂詞，但同音字結果可能不同。切換時保留已輸入文字，不清除既有學習資料。
  傳統注音的候選與輸入不受此開關影響。

### B. 觸控鍵盤直式與橫式

直式與橫式各自驗證：

- 注入螢幕座標前，確認 IME 的顯示動畫已結束，並等待實際 frame／inset 穩定。`getLocationOnScreen()`
  與 view 尺寸穩定時，系統的 Surface／輸入座標轉換仍可能在移動。專用宿主可透過公開
  `WindowInsetsAnimation.Callback` 觀察開始、進度與結束，維持原 insets 與子樹派送；若等待期間
  動畫或視窗 attachment 改變，重新取得穩定位置後只送一次真實點擊。觀測 callback 會讓宿主參與動畫協作，
  診斷須保留原時序的失敗及實際派送座標，不以加入觀測後未重現就宣稱產品已修正。
- 候選列、四排 11 個等寬鍵及功能列完整；沒有裁切、重疊、跳位或被系統地球鍵／手勢條遮住。
- 觸控鍵盤僅保留與鍵盤視窗重疊的底部系統控制列或導覽列空間。Android 8 的獨立導覽列
  上方應緊接鍵帽邊距。Android 17 切換整合模式時，確認地球鍵可用，並分別驗證手勢與三鍵導覽。
  拖曳下緣新增的自訂留白須分方向儲存，貼底後仍能重新往上拖曳。
- 在「調整鍵盤高度」分別拖曳直式與橫式的上下緣。移動上緣時下緣固定，移動下緣時上緣固定；
  貼底後不能再往下拉，仍可往上拉出自訂留白。拖曳期間隱藏鍵帽，放開後按最終尺寸恢復字級與間隔。
  無效的指標座標不得開始拖曳或改寫預覽；放開事件缺少有效座標時，保留最後有效位置並恢復鍵帽。取消拖曳仍回復拖曳前尺寸。
  驗證「取消」、「完成」及「恢復預設」，並比較預覽與真實輸入欄位的高度及留白。
  每個尺寸都可點到最上與最下排；旋轉、重新叫出鍵盤後套用該方向各自保存的高度與留白。
  接上實體鍵盤後，底部候選列與浮動候選字窗不套用觸控鍵盤的自訂高度。
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
- 對同一欄位延遲回報選取位置時，首個注音不可提早成為已確認文字；至少驗證首字讀音與完成「請假」
  後的文字仍在正確組字範圍，不只比較 App 最後的字串。回報合併或超過原有時間窗時仍要保留候選；
  真正移動游標或選取範圍則按既有規則結束舊組字，不吞掉使用者操作。
- 欄位沒有提供初始游標位置時，驗證「你好」仍有兩個可逐字換選的格子，點第一格可改成「妳好」。
  若需取得初始位置，只在未知位置的首次實際寫入前做有界處理；不可憑不完整內容猜絕對位置，
  一般已有位置的打字流程不增加遠端查詢。另驗證同一 App 行程的欄位不會阻塞鍵盤。
- 旋轉或重啟同一欄位時，即使 `EditorInfo` 仍回報舊的正數位置，也須依當前完整快照接續輸入。
  已有「你好」後再打注音或拼音，組字格、候選與宿主範圍都須正確；真正移動游標後不得沿用舊尾段的刪改權。
  重啟校準與 marked-range 驗證共用一次快照，另保留缺少／不符快照及無連線的安全退路。
- 系統返回鍵與鍵盤「▼」都保留已完成中文字、取消未完成注音或字根；重新叫出後不重送舊內容。
  四種輸入法、好打省略聲調開／關、已有前段文字、重複收鍵盤回呼及失去輸入連線分別驗證；
  切換欄位／輸入法與旋轉的既有交接行為另測，不拿正常收鍵盤的規則代替。
  收起完成不能只看宿主 `WindowInsets.Type.ime()` 的 `isVisible=false`：系統可在動畫開始時先更新這個目標狀態。
  應同時等 `InputMethodService.isInputViewShown()` 與實際 IME decor 的 `isShown()` 均為 false，再做原本精確的文字、
  引擎與重開檢查。調查時保留旗標先改與真正隱藏後的兩份狀態，不以盲等固定秒數或放寬輸出掩蓋差異。
- 一般候選角標為 1–9；沒有候選時角標仍留在候選格中，不閃爍或被清空。
- 紫、綠、黃、紅四種候選底色都要逐一切換；一般候選第一項立即反白，黃底使用黑字，
  其他底色使用白字，淺色／深色背景都可讀。

### D. `ㄅ → 英 → 數 → ㄅ` 與 Shift

- 模式鍵依序切換注音、英文、數字符號並循環；三態文字分別為 `英/數`、`數/ㄅ`、`ㄅ/英`。
- 注音模式按 Shift 暫時切英文小寫，雙標籤上下交換；輸入一個觸控字元後立刻回注音。
- 英文模式 Shift 在小寫／大寫間持續切換；大寫時數字排顯示 `!@#…`，小寫
  `; , . /` 的四個位置依序顯示並送出 `: < > ?`。
- 數字符號模式 Shift 只切兩套 44 鍵符號頁，不離開數字符號模式。
- 實體 Shift 不得改變觸控鍵盤模式。

### E. 觸控按鍵預覽與震動回饋

- 預覽開啟時，按住文字、注音、英文、數字及符號鍵，手未離開前附近顯示約 1.4 倍大字。
- 左右邊緣鍵的預覽不超出螢幕；滑出原鍵、放開或取消時立刻消失。
- 功能鍵、候選字及實體鍵盤候選列不顯示按鍵預覽；預覽本身不新增可點擊範圍。
- 關閉設定後不再顯示，重新開啟立即恢復。
- 震動可選 0、1、2、3、5、10、20、30、50、100ms；至少驗證 0、1、5、10、100ms，0 不震動，非 0 的
  可用鍵有回饋；無動作的空候選格、滑出取消與預覽 overlay 不可額外震動。AVD 無法代表真機
  手感，但仍須確認沒有 vibrator/security error；實際短震動手感另列真機驗收。
- 設定頁拖動震動時間滑桿時不連續震動，手指放開後只以選定的時間試震一次；0 不試震。

### F. 符號、Emoji 與標點

- 「符」開啟 90 個符號，共 10 頁，每頁 9 個；可點選、循環翻頁及返回一般候選狀態。
- Emoji 開啟 90 個表情，共 10 頁，每頁 9 個；沒有中文字候選時仍可開啟。
- 逗號、句號及兩套數字符號頁能送出畫面所示字元。
- 選符號或 Emoji 後不殘留舊 reading，也不誤進關聯詞選字規則。

### G. 欄位型態

在 debug test host 逐欄取得焦點，直式與橫式各驗一次。限制型欄位第一次進入時按原本
`inputType` 淡化不適用按鍵，但模式鍵必須可點；第一次點模式鍵後，該欄位要解除限制，
改成完整三模式與全部功能，重新顯示同一 editor 時也不可再鎖回：

| test host 欄位 | 預設模式 | 可循環模式 | 必查按鍵 |
|---|---|---|---|
| 一般文字、姓名、地址、搜尋欄、簡訊、長文字 | ㄅ | ㄅ／英／數 | 全功能可用 |
| Email | 英 | 初始英／數；按一次模式鍵後 ㄅ／英／數 | 初始空白、注音、Emoji 淡化；解鎖後全功能可用 |
| 網址 URL | ㄅ | ㄅ／英／數 | 一開始即可直接輸入中文、空白、符號與 Emoji |
| 密碼、可見密碼、要求 ASCII 鍵盤 | 英 | 初始英／數；按一次模式鍵後 ㄅ／英／數 | 初始只收適用 ASCII；解鎖後全功能可用 |
| 電話、整數、有號整數、小數、有號小數 | 數 | 初始僅數；按一次模式鍵後 ㄅ／英／數 | 初始沿用各類型字元；解鎖後全功能可用 |
| 日期、時間、日期／時間 | 數 | 初始僅數；按一次模式鍵後 ㄅ／英／數 | 初始沿用日期時間字元；解鎖後可輸入本地化文字 |

App 若錯報或不報 `inputType`，確認安全退回一般文字，不 crash。實體鍵盤在上述所有欄位仍保留
完整按鍵與快捷鍵，不由 IME 擋字；欄位是否接受內容由 host 決定。

### H. Enter action

在 debug test host 的八個 action 欄位，直式與橫式各驗一次：

- `DONE/NEXT/SEARCH/SEND/GO/PREVIOUS` 顯示「完成／下一個／搜尋／傳送／前往／上一個」，
  點擊後上方 `Action result` 顯示正確 action ID。
- 自訂 action 顯示「送出表單」，點擊後回報 action ID 42；長標籤不得裁切鍵盤。
- `IME_FLAG_NO_ENTER_ACTION` 顯示普通 Enter，送 key event，不呼叫標準 action。
- 有 reading 或一般候選時 Enter 先確定輸入；顯示關聯候選時不可選入反白關聯詞，應關閉關聯候選後直接執行 Enter／editor action。
- 實體鍵盤 Enter 在所有 action 欄位永遠維持 plain Enter key event。

### I. 實體鍵盤一般候選列

先關閉「實體鍵盤使用浮動候選字窗」：

- 直式／橫式的底部單排為 12 個等寬格：9 候選、Emoji、語言鍵與「▼」。
  點語言鍵開啟第二層四鍵面板，可切換「繁／簡」、「好／ㄅ／倉／簡／英」、「半／全」及進入「設定」。
  從設定返回同一輸入欄位後可繼續輸入。好打注音雙排也使用同一四鍵面板，浮動候選模式另測。
- 空候選格仍固定顯示 1–9 小角標；模式格只有 `ㄅ／英`，不可出現第三個「數」。
- 一般候選第一項使用設定的候選底色；四種顏色切換後立即更新，空候選格不應誤上底色。
- `1–9` 選一般候選，`Shift+1–9` 選關聯詞，`Page Up/Down` 與空白循環翻頁。
- 好打注音以完整 19 音節句「請假要去哪裡玩呢去海邊因為那裡有比基尼」實測：第十音節仍保留前十字，第十一音節送出完整「請假」，直到第十九音節已送出與可編輯尾段合起來仍是全文，無漏字或重複字。剩餘最多十個音節仍可移動組字游標與改選；模型缺字時 Esc 只取消當前讀音，不清掉原句。觸控鍵盤仍在第十音節擠出，不調整其九格已完成音節界線。
- 好打注音實體 Shift 大寫字母直接輸入 ASCII；已有完整組字時先送出組字，讀音未完成時仍保留讀音。
- 語言與全半形從四鍵面板切換；快捷鍵保留。Emoji 在沒有候選時仍可點。
- `Ctrl+Space` 切注音／英文；`Ctrl+0`、`Ctrl+1` 開符號；`Ctrl+,`、`Ctrl+.` 送全型逗句號。
- 所有 shortcut 的 keydown/keyup/長按不重複或漏字。AVD console 無法忠實產生的 modifier 組合，
  必須另以真實 USB／藍牙鍵盤驗收，不能用 `adb shell input keycombination` 冒充通過。

### J. 全形／半形

- 點四鍵面板的 `半／全` 及實體 `Shift+Space` 都能切換，且保留目前 reading／候選。
- 全形模式依序驗證 `Ａｚ０９！～　`；切回半形後同鍵輸出 ASCII。
- 中文與非 ASCII 不轉換；空白 repeat 不得在切換全形時漏進 editor。
- 全半形只影響實體鍵盤，不改觸控鍵盤輸出。

### K. 實體鍵盤浮動候選

開啟浮動候選，垂直與水平排列都測：

- IME 底部只保留維持 token 的 1dp view；候選出現時 Window 附掛成功且原欄位不失焦。
- 有 `CursorAnchorInfo` 時跟隨游標，靠近上下左右邊界時不超出可用畫面；尚未收到座標時暫放底部中央，300ms 後補取一次，再等 300ms 仍無有效座標即自動停用。
- Android 8 快速切回本輸入法後，在標準 EditText 輸入「請假要去哪裡玩呢去海邊因為有」，
  分別在句尾與句中開候選；Bigram 開／關及直／橫排列都須緊鄰游標，不可只驗證視窗存在。
  重複切換輸入法至少五次；重試須有上限，切換欄位及結束輸入時不得沿用前一欄座標。
- 快速以實體鍵輸入 `ㄑㄧˊ` 後至少停留 1 秒；editor 連續回報多次 selection update 時，
  composing 與浮動候選都必須持續顯示，不可只閃一下就被第二個 callback 清除。
- 垂直：上下移反白、左右換頁；水平：左右移反白、上下換頁。
- 好打注音句中開啟候選後也遵守上述方向鍵配置，不能把候選方向鍵交給組字游標。
- 1–9、方向鍵、Enter、ESC、Page Up/Down、觸控選字皆正確；長候選省略但送出完整文字。
- 浮窗反白項使用設定的候選底色；紫／綠／黃／紅切換後重新顯示候選即套用，文字對比正確。
- 切換直／橫排列立即套用；旋轉畫面、切換 App、收放鍵盤後可重新附掛，不累積殘留 Window。
- 使用 `cursorUpdates silent|reject` 時，未開候選不得自動停用；開候選後須切回一般候選列，
  設定保留停用狀態及原因、文字和候選不丟失，數字選字及 Enter 仍可使用。
  重新勾選可再試；正常回報座標的 App 不得誤停用。
- 若附掛/token 失敗，約 1.5 秒後自動關閉浮窗、切回一般實體候選列，設定頁持續顯示原因。
  重新勾選時原因暫時清掉並再試；再次失敗要再次記錄。成功環境不可被錯誤停用。

### L. 詞庫切換、關聯詞與穩定性

- 初次安裝為「僅小麥注音」；驗證「全部啟用」、「僅小麥注音」、「全部關閉」及任選多詞庫。
- App 獨立詞庫頁的已啟用數量與當前打包的詞庫清單一致，不寫死詞庫數；重開頁面及重新顯示鍵盤後仍保持。
- 確定單一中文字才顯示關聯詞尾；選取只接上詞尾。輸入下一個注音會關閉關聯詞且不偷送第一項。
- 全部關閉時沒有關聯詞；多詞庫混合依設定中的 source 順序排序、跨庫重複只留第一筆。
- 每台 cold boot 都分別以「全部啟用」及「全部關閉」記錄從欄位取得焦點到虛擬鍵盤完整
  顯示的時間；兩者都不得因主執行緒解析文字詞庫而出現數秒停頓或 ANR。全部啟用時，
  等背景索引載入完成後仍須能產生關聯詞。
- 一般候選用 1–9；關聯詞實體選字用 Shift+1–9，但角標仍顯示 1–9。
- 關聯候選顯示中按觸控 Enter／搜尋／傳送／完成不可插入任何關聯詞；應關閉候選後只執行欄位 action。實體 Enter 也不可插入關聯詞，並維持普通 Enter key event。
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
