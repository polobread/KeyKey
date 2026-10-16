# macOS 安裝與升級流程

## 設計與 Apple 依據

安裝器負責將簽章後的 App 放在 `/Library/Input Methods/chichi77 KeyKey.app`，
並通知目前登入帳號的 Text Input Sources 重新註冊。啟用與選取由系統及使用者管理。
檔案已安裝、來源可查詢、舊行程已退出、新 IMK session 可輸入，是不同的驗證層級。

- Apple SDK 的 Carbon/HIToolbox `TextInputSources.h` 定義：
  `TISRegisterInputSource` 供安裝器註冊指定位置的來源，更新必要快取並取得來源參照；
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

## 從 1.3.1 收斂的範圍

`c771e96` 的 postinstall 直接以全域 `pkill` 結束舊行程。
`603f2a6b` 加入讀取狀態、切 ASCII、停用、結束、註冊、啟用及選回；
`e9504db7` 補部分替換後快照，並讓 session refresh 失敗不再使整包安裝失敗。
後兩者仍無法從覆蓋後的狀態還原原本意圖，也可能在逾時後留下已停用的來源。
只有安裝日誌提示失敗，不能作為一般使用者的復原介面。

目前移除上述啟用／選取管理，保留固定安裝路徑、簽章／公證、來源註冊、
有範圍的正常行程退出，以及 `CVKeyboardHelper` 的借用物件與空清單修正。
安裝 helper 沒有 enable、disable、select 或目前來源查詢呼叫，
也不讀寫私有 HIToolbox 偏好。來源排序不由安裝器重建。

## 安裝後的操作

postinstall 只在開機磁碟且有有效 console 使用者時，透過
`launchctl asuser` 與該帳號憑證執行已簽章的獨立 helper。

1. 捕捉執行當下的 KeyKey 行程身分，避免結束註冊後才啟動的行程。
2. 對固定安裝位置呼叫 `TISRegisterInputSource`，檢查 OSStatus。
3. 以精確 source ID 查 inclusive 清單。找得到就接受，即使來源尚未啟用；
   找不到或清單不可讀則回報失敗，不停止既有行程。無須先取得目前選取來源。
4. 正常結束捕捉到、executable path 符合固定安裝位置的行程。
   使用保留身分的 `NSRunningApplication`，拒絕無效 PID 與自身，不使用全域 kill。
   每個行程最多等 3 秒；macOS 可在之後選取 KeyKey 時啟動新版。

整個操作最多 20 秒。逾時直接返回失敗；因 helper 從未停用或切換來源，
不需要再用另一組 TIS 變更回滾。每個失敗階段記錄可識別的原因。

失敗時 payload 仍已完成安裝；postinstall 成功結束，另以相同帳號的 GUI process
顯示「琦琦輸入法需要確認」，提供「開啟鍵盤設定」與「稍後」。
提示不讓 Installer 等待回應，也不自動加入或切換來源。無 GUI session 時不顯示提示，
由完成頁與安裝日誌提供加入方式。

使用者完成流程：從輸入法選單選取琦琦，在「文字編輯」試打並核對偏好設定版本。
升級時可先選 ABC 再切回琦琦；缺少項目才從鍵盤設定加入，已有項目不必先刪除。
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

隔離驗證覆蓋註冊失敗不停止舊行程、註冊 noErr 但來源缺少、不可讀快照、
無目前來源也能註冊、不呼叫 enable／disable／select、行程身分／路徑檢查、
拒絕終止、退出逾時、無登入帳號／其他磁碟，以及失敗時獨立啟動可見提示。
測試不安裝、不切換真實輸入來源、不終止使用者行程、不登出。
提示的顯示及鍵盤設定按鈕仍需實機 GUI 驗收。

發布前仍須在可恢復的測試 Mac／獨立帳號完成：

| 情境 | 驗收內容 |
| --- | --- |
| 首次安裝 | 可從鍵盤設定加入，從選單選取，在 TextEdit 輸入「台北」並確認版本 |
| 1.3.1／既有 beta 升級，KeyKey 作用中 | 來源仍可選；切 ABC 再選回後啟動新版且可輸入 |
| 升級時選用 ABC／其他來源 | 安裝器不主動更換使用中的來源；可自行切到新版 KeyKey |
| 原本停用 KeyKey | 不自動啟用；可自行從鍵盤設定加入 |
| 準備失敗／舊行程不退出 | Installer 不等待提示回應；使用者看得到原因與鍵盤設定入口 |
| 登出／多帳號／不同文字宿主 | 確認登入畫面可操作、內建／USB 鍵盤可輸入，各帳號獨立驗收 |

使用者曾回報 beta4 安裝後登出停在背景與游標，以及 USB 鍵盤登入失效；
目前未取得足以定位共同根因的呼叫堆疊。更新器拒絕結束是程式碼可確認的風險，
尚不能宣稱就是該實機問題的根因。測試若再次遇到停滯，應停止反覆登出或強制關機，
取得系統診斷後分析。

postinstall 仍發生在 payload 替換後，覆蓋期間舊 IMK 可能讀取新舊混合資源；
其他已登入帳號不會自動更新其行程。編譯、隔離回歸、簽章與來源可查詢，
都不能取代上述實機驗收，也不能保證所有安裝都不需要重新登入。
