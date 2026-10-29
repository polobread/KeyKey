# macOS 符號表資料載入

此文件記錄空白符號表的成因、回歸入口與診斷界線，非安裝或發布驗收。

## 已確認的機制

符號表的分類及內容依賴 `CVLoaderUpdateCannedMessagesNotification`。
原本 `CVSymbolController` 只在 `awakeFromNib` 訂閱通知，建構時未讀取已載入資料。
`CVApplicationController.symbolController` 又採需要時才建立，因此通知可以先於訂閱完成。
通知不會補送；若之後沒有新的資料變更，分類選單與內容會一直為空。

啟動流程如下：

1. `main.mm` 以背景執行緒啟動 loader，主執行緒運行 AppKit／IMK。
2. loader 在共用鎖內初始化引擎，解鎖後把 `_firstTimeUpdateUserData` 排到主執行緒。
3. IMK 的 `initWithServer:delegate:client:` 等待同一把鎖，但這只能保證引擎初始化，
   不能保證第 2 步排程的符號資料通知已執行。
4. `activateServer:` 同步使用者資料，最後經 `restoreWindowStatus` 取得符號表控制器。
   同步資料自身也可能在控制器建立前送出通知。
5. 若初始資料回呼先完成，之後才建立控制器，就漏接所有初始通知；
   若控制器先建立、初始資料回呼後完成，畫面就正常。

這是同一版程式也能先成功、換一次程序或啟用順序後又失敗的原因；
不必先假設最近有修改符號資料或視窗資源。

## 歷史與證據界線

- 2012 原始碼在 App delegate 的 `awakeFromNib` 就建立 `_symbolController`。
- 2026-08-16 的 `80dca25d` 移除預先建立，改為 getter 內延遲建立，
  卻沿用只等通知的載入方式，導入上述初始化缺口。
- 正式 `v1.3.1` tag、前次 `afdbc00b` 的符號控制器原始碼相同；
  本機保留的 1.3.1／1.3.2 安裝包與目前 1.3.3 的 `SymbolWindow.nib` SHA-256 相同。
- 現有安裝詞庫和使用者快取的 `canned_messages` 都有 17 類、807 筆，內容相同，
  各類沒有 `NotBefore`／`NotAfter` 限制，可排除資料空白或到期。
- 修正前 `CVDictionaryWindow` 未編入會使 NIB 回退成一般 `NSWindow`，
  但同樣回退的隔離案例仍可完整載入分類，不能把它當成空白內容的成因。
- 舊程式未記錄資料通知與視窗訂閱，無法還原使用者本週每一次成功／失敗的實際順序，
  也沒有證據可指定本週某次 commit 是首次觸發點。8 月的缺口引入時間不能冒充故障發生日。

## 修正與診斷

控制器先建立內部陣列，再載入 NIB 並訂閱通知，最後主動讀取現有資料。
訂閱後讀取快照，能涵蓋通知在控制器建立前送出及資料稍後到達兩種順序。
空內容在開啟視窗時補載；引擎 locale 尚未就緒時可安全使用後備 locale。
空資料刷新會清掉舊內容，空選單的選取事件不再存取無效索引。

macOS 統一紀錄以 `KeyKey symbols event=` 識別：

- `initial-data-start`：主執行緒開始處理初始資料。
- `data-notification`：即將送出資料通知，包含來源長度、plist 是否解析成功及合併後分類數。
- `observer-registered`：視窗已訂閱，包含當時已快取分類數。
- `window-load`／`window-loaded`：通知或快照觸發，以及來源、選單、控制器各自筆數。
- `empty-window-retry`：開啟空視窗時補載。

紀錄只包含事件順序與數量，不含符號內容、自訂詞句、輸入文字或宿主 App。
可依系統時間及 PID 區分不同程序：

```sh
/usr/bin/log show --last 10m --style compact \
  --predicate 'process == "chichi77 KeyKey" AND eventMessage CONTAINS "KeyKey symbols event="'
```

若 `data-notification` 顯示解析失敗或分類數 0，先查資料來源；
目前資料庫 17 類另加視窗端 Emoji 1 類，正常 `window-loaded` 為來源 17、選單與控制器各 18；
若不符合「來源分類數 + 1」，查視窗載入；
若筆數皆正確但看不到，另查視窗層級／焦點，勿混成相同原因。

## 隔離回歸

```sh
python3 Source/Loaders/OSX-IMK/Tests/run-symbol-controller-tests.py
# 額外確認修正前同一份程式的成功與失敗路徑
python3 Source/Loaders/OSX-IMK/Tests/run-symbol-controller-tests.py --baseline-ref afdbc00b
```

測試使用真正的 `CVSymbolController`、按鈕／表格控制器、兩份 NIB 與共用 DB 內建資料；
只以可控制通知順序的 provider 取代 loader，不建立 IMK server、不啟用輸入法、
不顯示測試視窗、不讀寫使用者偏好與詞庫。選字送出接至隔離接收器。

原版實測結果：

| 順序 | 資料分類 | 選單項目 | 內容高度 |
| --- | ---: | ---: | ---: |
| 視窗先建立，再通知 | 17 | 17 | 100 |
| 先通知，再建立視窗 | 17 | 0 | 0 |
| 建立空視窗，資料稍後就緒但未收到通知 | 17 | 0 | 0 |

後兩列重現只有視窗標題及空白下拉選單的狀態，排除資料筆數不足與視窗是否能建立。
修正後驗證：通知在先、視窗在先、補載、重複刷新／分類切換、清空後恢復五種案例；
分類和內容須一致，實際按鈕送出的符號也須正確。

PR 的 `macos-symbols.yml` 及 macOS 封裝流程會執行此回歸。
這些證據覆蓋資料與真實 AppKit 視窗的銜接；已安裝 IMK 的啟動、選單顯示及宿主送字
仍是另一層驗證，不能用隔離測試宣稱實機驗收完成。

## 分類間距與 Emoji

下拉選單原本隨視窗自動縮放，但視窗總高度以固定 65 點估算，包含標題列後，
下拉選單下緣與符號區上緣只剩約 2 點；系統控制項外觀會畫到這段空間，形成視覺重疊。
改用 `frameRectForContentRect:` 計算包含標題列的實際視窗尺寸，明確排列內容：
底部 8 點、符號區、12 點間距、26 點下拉選單、頂部 8 點。
分類切換直接套用完整幾何，避免視窗尺寸動畫與內容尺寸更新不同步。

Emoji 加在既有分類後方，來源與 Windows `Generate-SymbolResources.ps1` 相同：
手機 `KeyboardInput.emojis` 的 90 個加 `SymbolEmojiSupplement.json` 的 110 個，
共 200 個且順序相同。生成器輸出 `CVEmojiData.generated.h`，不更動正式 DB。

```sh
# 兩份共用來源更新時重生 macOS 字串表，將來源與生成結果一起提交
python3 Source/Loaders/OSX-IMK/Generate-EmojiResources.py
# CI 原生回歸也會執行這項內容同步檢查
python3 Source/Loaders/OSX-IMK/Generate-EmojiResources.py --check
```

Emoji 使用 10 欄、34 點格子及 Apple Color Emoji 字型，一次顯示最多 8 列並可捲動，
保留所有 200 個完整字串，不按 UTF-16 字元拆開。原有符號仍維持 25 點格子。
資料尚未載入時仍保持空狀態，避免補充分類掩蓋原本的空內容補載條件。

第六個隔離原生案例確認 200 個標題字串與來源逐筆一致、首尾可捲入顯示範圍及送出，
包含 variation selector 的字串不被截斷；所有分類切換皆檢查下拉選單與內容區的間距及邊界。
可用 `run-symbol-controller-tests.py --snapshots Installer/local-builds/macos-symbol-emoji-preview`
輸出隔離內容繪製圖確認 Emoji 字型。圖像不代表已安裝 IMK 或原生下拉控制項的實機驗收。

## 跟隨候選字窗比例

`OpenVanillaController.activateServer:` 將既有 `CandidateWindowScalePercent` 解析結果
同時套到橫式、直式候選窗與符號表。符號表選單開啟時也重新同步設定；
從偏好設定回到輸入宿主後，原本已開啟的符號表會以新比例恢復。
不另設第二個比例值，也不新增輪詢或排程。

符號表沿用候選窗的實體尺寸／邏輯 bounds 縮放方式，包含原有表格、符號按鈕、
Emoji、捲動條及 12 點邏輯間距；系統標題列維持原生尺寸。
展開的分類選單有獨立原生視窗，另依實際比例設定 menu font，避免只有收合控制項變大。
使用相同 `CVFitCandidateScale` 在螢幕可用範圍內限制最大比例，避免視窗超出畫面。
重新套用比例會從原始邏輯尺寸計算，保留目前分類，不累積縮放。
同時修正舊顯示路徑把 Y 座標上限寫成 MaxX、Y 下限寫成 MinX 的錯字。

第七個原生隔離案例涵蓋 75%、100%、150%、350%、切換分類及恢復 100%，
確認一般比例正確、兩軸與間距同比縮放、展開選單字體同步、視窗留在可用範圍、
分類選擇保留且不累積縮放。紀錄 `event=layout` 的 requested／applied scale 可辨識螢幕限制。
已安裝 IMK 的設定頁往返與選單互動仍需實機確認。

## 符號表被其他視窗蓋住

匿名使用者回報 macOS 27.0.1、Apple Silicon M1、1.3.2：符號表被瀏覽器或 Office 壓到後方；
維護者也觀察到輸入法設定視窗會高於符號表。本項與分類空白分開處理。
安裝器部分依維護者指示不納入本次修改。

### 直接原因

- `SymbolWindow.xib` 指定 `CVDictionaryWindow`，但 IMK 產品 target 沒有編入該類別的 `.m`。
  AppKit 實際退回一般 `NSWindow`，原有自訂類別的 `NSStatusWindowLevel` 完全沒有執行。
- 輸入法設定 `TakaoPreference.m` 明確使用 `NSFloatingWindowLevel`，因此高於普通視窗。
  原本符號表使用 `NSWindowController.showWindow:`，背景輸入法還會遇到條件式排序限制。
- `OpenVanillaController.deactivateServer:` 另外主動呼叫 `temporaryHide`，
  即使只提高視窗層級，切換宿主或設定視窗仍可能將符號表收起。
- `v1.3.2` tag（`d9e7f911`）的符號表仍只有通知載入，沒有初始化快照補載；
  該版的分類空白與此文件前述已重現的缺口相符，不能從回報認定 1.3.3 修正又退步。

### 修正行為

1. 將 `CVDictionaryWindow.m` 正式編入 IMK 產品；NIB 從建立時就帶
   `NSWindowStyleMaskNonactivatingPanel`，移除一個沒有接線的重複視窗。
2. 初始化與 `awakeFromNib` 都配置浮動面板，確保 NIB 還原後仍為
   `NSStatusWindowLevel`、`hidesOnDeactivate = NO`、`worksWhenModal = YES`，
   並支援各個 Space 與全螢幕輔助視窗。
3. 以 `orderFrontRegardless` 顯示背景輸入法的面板，不啟用輸入法 App。
   面板不成為 key／main window，符號按鈕與分類下拉支援首次滑鼠點擊，保留宿主輸入目標。
4. 移除輸入法停用時對符號表的自動隱藏。開啟意圖維持到使用者按關閉鈕或再次切換選單；
   宿主切換仍清理原有組字與 active context，沒有輸入目標時不送字。
5. 新增 `event=show` 紀錄實際是否為 panel、視窗層級與 nonactivating style；
   不記錄客戶文字或其他 App 名稱。

這裡的「置頂」是高於一般編輯器、浮動設定與模態面板；不提高到高於系統選單或安全介面。

Apple 行為依據：
[nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)、
[becomesKeyOnlyIfNeeded](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded)、
[NSWindow 視窗排序](https://developer.apple.com/documentation/appkit/nswindow)。
實際層級常數與初始化介面另核對當前 macOS SDK 的 `NSWindow.h`／`NSPanel.h`。

### 防止再發生與驗證界線

原生隔離測試除了編譯測試用面板，也直接解析 Xcode project，檢查真正 IMK target 的
Sources 包含 `CVDictionaryWindow.m`，避免「測試有連結，產品漏連結」再次發生。
PR 路徑監控納入 project 設定。

第八個 `panel` 案例讀取真正 NIB，確認實際類別、層級、非啟用旗標、key／main 限制、
首次點擊、Space／全螢幕旗標、明確關閉與跨宿主恢復意圖。
第九個 `ordering` 案例以測試程式自有的透明、不收滑鼠視窗，在實際 AppKit／WindowServer
先顯示符號表，再把浮動設定與模態層級視窗帶到前方，檢查面板排序仍在其上且沒有啟用 App。
此案例不連接已安裝 IMK，不操作、讀取或列舉使用者其他 App 的視窗。

`NSApplication.orderedWindows` 是 scripting 介面，會排除 `NSPanel`，不能用來驗證面板排序。
排序案例使用 `NSWindow.windowNumbersWithOptions:0`，只取測試程式自身視窗號碼，包含面板；
[Apple orderedWindows 說明](https://developer.apple.com/documentation/appkit/nsapplication/orderedwindows)。
可以只執行受影響案例：

```sh
python3 Source/Loaders/OSX-IMK/Tests/run-symbol-controller-tests.py --scenario panel --scenario ordering
```

瀏覽器／Office 的已安裝 IMK、實際輸入欄位送字、全螢幕與多螢幕仍是獨立驗收層級，
透明測試視窗與層級確認不能代替上述實機驗收。正式 DB、安裝器及其他平台均不修改。

原生排序案例實測包含 4 個測試程式自有視窗，前後索引為符號表 0、模態 1、設定 2、編輯器 3；
設定與模態視窗是在符號表顯示後才被要求帶到前方。視窗 alpha 為 0、不接收滑鼠，
因此不會覆蓋或改變使用者正在操作的 App。
模態測試窗明確關閉 `hidesOnDeactivate`，模擬宿主處於前景時的可見對話框；
否則測試程式保持非啟用狀態時，標準 NSPanel 的自動隱藏會讓排序測試缺少比較對象。
