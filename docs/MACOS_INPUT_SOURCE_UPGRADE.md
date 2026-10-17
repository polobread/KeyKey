# macOS 安裝與升級流程

## 設計與 Apple 依據

安裝器負責將簽章後的 App 放在 `/Library/Input Methods/chichi77 KeyKey.app`，
並通知目前登入帳號的 Text Input Sources 重新註冊。升級保存原本的啟用意圖，
只在覆蓋前需要退出正在使用的舊版時暫切到已啟用的 ASCII 鍵盤；不自動選回琦琦。
檔案已安裝、來源可查詢、舊行程已退出、新 IMK session 可輸入，是不同的驗證層級。

- Apple SDK 的 Carbon/HIToolbox `TextInputSources.h` 定義：
  `TISRegisterInputSource` 供安裝器註冊指定位置的來源、更新必要快取，再以清單查詢取得來源參照；
  `TISEnableInputSource` 讓來源可選，`TISSelectInputSource` 才更換目前來源，
  `TISDisableInputSource` 會將來源從可選介面移除。Apple 沒有要求升級前先停用來源。
- [QA1810](https://developer.apple.com/library/archive/qa/qa1810/_index.html)
  說明鍵盤輸入法由鍵盤設定管理；palette 範例不能作為整套升級順序的保證。
- [Core Foundation Ownership Policy](https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFMemoryMgmt/Concepts/Ownership.html)
  與 SDK 都要求遵循 Get rule：不可釋放 `TISGetInputSourceProperty` 借出的物件。
- [Apple Installer Distribution XML](https://developer.apple.com/library/archive/documentation/DeveloperTools/Reference/DistributionDefinitionRef/Chapters/Distribution_XML_Ref.html)
  提供 `RequireLogout`／`RequireRestart`；是否要求這些動作是套件的選擇。
- [App 正常結束流程](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/AppArchitecture/Tasks/GracefulAppTermination.html)
  也涵蓋登出與關機。更新器的組字延後應限定於 Sparkle 的重啟回呼。

## 1.3.2 相對於正式版 1.3.1 的變更

正式版 1.3.1 的 postinstall 以全域 `pkill` 結束舊行程。
1.3.2 將狀態保存和有範圍的正常退出移到覆蓋前，避免舊行程繼續使用被替換的詞庫；
覆蓋後註冊新版，並只恢復同一帳號原本已啟用的來源。安裝後準備失敗提供可見提示與設定入口。
macOS 可能在覆蓋完成前再次啟動輸入法，因此覆蓋後另查固定位置行程開啟的詞庫檔案身分；
若仍持有已被替換的詞庫，正常退出該行程，避免只剩注音、無法查字。

保留固定安裝路徑、簽章／公證，以及 `CVKeyboardHelper` 的借用物件與空清單修正。
任何階段都不呼叫 disable，不讀寫私有 HIToolbox 偏好、不重建其他來源或其排序。
1.3.2 尚未正式發布，以下流程仍須完成發布前的實機驗收。

## 覆蓋前與覆蓋後的操作

兩個 script 只在開機磁碟且有有效 console 使用者時，透過
`launchctl asuser` 與該帳號憑證執行獨立 helper。

### preinstall：舊 bundle 仍完整時

1. 使用套件附帶、已簽章的 helper，避免依賴舊版不存在的指令。
   複製到唯一、root 擁有的暫存目錄供 GUI 帳號執行，退出時刪除；
   不要求 GUI 帳號能讀取 PackageKit 的私有 Scripts 上層目錄。
2. 以精確 ID 的 inclusive 清單讀取原本的 enabled，並查目前來源。
   首次安裝沒有 KeyKey 視為未啟用；清單或屬性不可讀時中止，不猜測原設定。
3. 若目前選取 KeyKey，將它視為原本已啟用，選取現有已啟用且可選的 ASCII
   鍵盤配置並再次確認目前 ID。沒有可用配置或切換失敗時中止。
   其他來源正在使用時不更換選取。
4. 正常結束開始準備時捕捉到、executable path 符合固定安裝位置的 KeyKey 行程。
   使用保留身分的 `NSRunningApplication`，拒絕無效 PID 與自身，不使用全域 kill。
   每個行程最多等 3 秒；不能確認退出時在覆蓋前中止。
5. 將 console UID 與 enabled／disabled 存在這次安裝的私有 Scripts 目錄，權限 600。
   不使用跨安裝的全域狀態檔。

preinstall 失敗時 Installer 顯示失敗，舊 bundle 尚未被覆蓋。若已切至 ASCII，
使用者可重新選取原本的 KeyKey；不會留下被 helper 停用的來源。

### postinstall：新版 bundle 已安裝時

1. 檢查目前帳號、固定 executable path 的輸入法行程，透過公開 libproc API 比較
   詞庫 descriptor 的 device／inode 與安裝位置。只有持有已替換詞庫的行程才正常退出，
   每個行程最多等 3 秒；已使用目前詞庫的行程保留。無法確認或不能退出時回報準備失敗。
   這處理 preinstall 結束後、payload 覆蓋前被系統重新啟動的行程，不使用全域 kill。
2. 對固定安裝位置呼叫 `TISRegisterInputSource`，檢查 OSStatus 與精確 ID 可查詢。
3. 只有保存的 UID 仍為目前 console 使用者、且原本 enabled 時，才呼叫 enable。
   首次安裝、原本 disabled 或狀態不明時不自動啟用。
4. enable 後重新查詢，再用另一個 helper 行程確認 enabled，避免只靠呼叫端快取。
   不會自動選回 KeyKey，也不結束持有目前詞庫的行程。

每次 helper 操作最多 20 秒，每個失敗階段記錄可識別原因。
獨立行程驗證只代表當下 TIS 狀態，不能保證後續 PackageKit／系統通知或選單行為。

失敗時 payload 仍已完成安裝；postinstall 成功結束，另以相同帳號的 GUI process
顯示「琦琦輸入法需要確認」，提供「開啟鍵盤設定」與「稍後」。
提示不讓 Installer 等待回應，也不自行操作設定介面。無 GUI session 時不顯示提示，
由完成頁與安裝日誌提供加入方式。

使用者完成流程：從輸入法選單選取琦琦，在「文字編輯」試打並核對偏好設定版本。
升級期間可能暫切到 ASCII，完成後選回琦琦；缺少項目才從鍵盤設定加入，已有項目不必先刪除。
能正常輸入即可繼續使用。首次安裝若仍未出現在加入清單，可儲存工作後重新登入一次。
完成頁、更新器訊息與新產生的發行說明使用相同指引，不宣稱 helper 已驗證實際輸入。
已發布的套件及 feed 不因來源訊息變更而改變。

一般 App 結束、登出與關機不再交給更新器否決；未完成組字的更新延後及再次檢查，
保留於 Sparkle 的更新重啟回呼。手動 pkg 安裝及其他登入帳號不經過此組字保護。

## 驗證與限制

```sh
bash Installer/test-input-sources.sh
bash update/test-macos.sh
python3 -m unittest discover -s update -p test_macos_release.py -v
```

隔離驗證覆蓋覆蓋前保存狀態／暫切既有 ASCII／退出順序、不可讀狀態或退出失敗中止、
註冊 noErr 但來源缺少、enable 結果與新行程再次確認、不呼叫 disable、
安裝後不改選取或退出使用目前詞庫的行程、持有舊詞庫的行程正常退出或失敗回報、
真實暫存檔原子替換後的 descriptor 身分比較、行程身分／路徑檢查、無登入帳號／其他磁碟、
帳號切換不沿用狀態，以及失敗時獨立啟動提示。
測試不安裝、不切換真實輸入來源、不終止使用者行程、不登出。
提示的顯示及鍵盤設定按鈕仍需實機 GUI 驗收。

發布前仍須在可恢復的測試 Mac／獨立帳號完成：

| 情境 | 驗收內容 |
| --- | --- |
| 首次安裝 | 可從鍵盤設定加入，從選單選取，在 TextEdit 輸入「台北」並確認版本 |
| 從正式版 1.3.1 升級，KeyKey 作用中 | 覆蓋前暫切 ASCII 且舊行程退出，來源仍可選；選回後啟動新版且可輸入 |
| 升級時選用 ABC／其他來源 | 安裝器不主動更換使用中的來源；可自行切到新版 KeyKey |
| 覆蓋期間系統重新啟動 KeyKey | postinstall 退出持有舊詞庫的行程；選回後可輸入中文且使用目前詞庫 |
| 原本停用 KeyKey | 不自動啟用；可自行從鍵盤設定加入 |
| 覆蓋前準備失敗／舊行程不退出 | Installer 中止、舊 bundle 保留；可重新選取原版本 |
| 安裝後恢復失敗 | 檔案安裝成功；使用者看得到確認提示與鍵盤設定入口 |
| 登出／多帳號／不同文字宿主 | 確認登入畫面可操作、內建／USB 鍵盤可輸入，各帳號獨立驗收 |

登出與登入畫面的鍵盤操作仍須實機驗收。若驗收遇到停滯，應取得系統診斷後分析。

其他已登入帳號的行程未納入目前 console 帳號的準備；無 console 使用者時也不執行準備。
手動安裝前應完成組字並儲存工作；ASCII 暫切不能當成各宿主送出組字的驗證。
編譯、隔離回歸、簽章與來源可查詢，
都不能取代上述實機驗收，也不能保證所有安裝都不需要重新登入。
