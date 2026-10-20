# macOS IMK Shift 訊號實驗

這是獨立工作分支上的暫時診斷，不改中英模式、組字、候選或詞庫。
實驗直接觀察 `OpenVanillaController.handleEvent:client:`，沒有全域事件監聽器。
只有本機測試包的 Info.plist 具備 `KeyKeyIMKShiftProbeEnabled = true`；一般建置預設停用。

## 測試

安裝本機 `KeyKey-1.3.3-IMK-Shift-test.pkg` 後，在鍵盤選單選回琦琦。
新程序首次啟用時應顯示「IMK Shift 訊號測試已啟用（不切換中英）」。
先保存正在編輯的文字，再在 TextEdit、瀏覽器文字框及遠端桌面試按：

- 左右 Shift 各自短按：300 ms 內收到配對變化時，顯示「IMK 已收到左／右 Shift 單按」。
- 長按、Shift＋字母／方向鍵、Ctrl／Option／Command 組合及左右 Shift 同時使用：不顯示單按提示。
- 按住 Shift 時切換 App／輸入法，再回來放開：不得延續舊的單按判定。
- 空組字、未完成注音與候選開啟時分別測試；檢查文字保留、選取、大寫與快捷鍵正常。

提示只證明對應事件送達 IMK。判定依 IMK 實際收到的事件，不能證明它看見了所有實體按鍵。
原事件成對放行；沒有吞掉 Shift 放開事件，也沒有切換中英。

可用終端機觀察啟用、停用、修飾鍵旗標與單按判定：

```sh
/usr/bin/log stream --style compact --predicate 'eventMessage CONTAINS "[KeyKey Shift Probe]"'
```

記錄不含輸入字元或普通按鍵鍵碼，且僅在實驗開啟時產生。
如果有啟用提示但無修飾鍵記錄，應記下宿主與測試情境，不能只憑沒出現單按提示就斷定沒有事件。

## 停用與還原

快速停用實驗：

```sh
defaults write io.github.polobread.inputmethod.chichi77 KeyKeyIMKShiftProbeEnabled -bool false
```

再切到 ABC、切回琦琦，使下一次 `activateServer:` 重讀開關。
重新啟用測試包可將上述值改為 `true`；一般建置仍因缺少 bundle 標記而保持停用。

完整回復請安裝同一產物目錄的 `KeyKey-1.3.3-rollback-previous.pkg`。
該包取自本次修改前的已安裝 App 備份，不是拿目前原始碼重新建置。
`rollback-snapshot.json` 記錄原執行檔與備份雜湊；封裝時依現行流程重簽 ad hoc，簽章可能不同。
保留舊包，不覆寫已發布安裝檔。使用者自訂詞與學習資料不納入備份或修改。

本機產物保存在 `Installer/local-builds/macos-imk-shift-probe-*`，不提交。
原始碼改動集中於 `OpenVanillaController.h/.mm`、`IMKShiftTapProbe.h` 及對應 Tests。

## 開發驗證

```sh
python3 Source/Loaders/OSX-IMK/Tests/run-shift-probe-tests.py
(cd Source && xcodebuild -project Takao.xcodeproj -target 'Takao (Loader OSX-IMK)' \
  -configuration Release -xcconfig Takao-macOS.xcconfig build)
```

隔離測試涵蓋狀態機與從實際 controller 擷取的 observer，不連接已安裝 IMK。
建置和隔離測試成功不等於安裝後實體鍵盤驗收。

## 重複事件處理

實機記錄顯示部分 context 以「按下、重複按下、放開、重複放開」送達 IMK。
初版在第二筆按下取消判定，會出現有事件卻沒有提示的情形。
同側、同狀態的重複通知現在不改變原始按下時間，也不重新啟用已取消的手勢；
每次完整短按只通知一次。另一側 Shift、其他按鍵與長按仍不算單按。
啟用記錄另附宿主 bundle ID，以區分測試程式與一般 App，避免僅憑 context 位址推論宿主。
