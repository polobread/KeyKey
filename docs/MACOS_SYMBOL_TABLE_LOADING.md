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
- 既有 `CVDictionaryWindow` 未編入會使 NIB 回退成一般 `NSWindow`，
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
若資料完整但 `window-loaded` 筆數不符，查視窗載入；
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
