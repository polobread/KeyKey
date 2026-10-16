# macOS 安裝註冊與登出異常調查

## 現況與證據界線

2026-10-16 使用者回報：手動下載並執行 1.3.2-beta4 的 pkg 後，若沒有先在
「系統設定 → 鍵盤」移除再加入琦琦，登出會只剩背景與滑鼠游標，沒有登入欄位。
多次測試須強制關機；重新開機時 USB 鍵盤也無法登入，須用內建鍵盤登入後重新連接。
這是嚴重的實機回報，不能以程序正在執行或目前可打字認定已排除。

唯讀取得的同日紀錄：

- 08:26:56、08:31:20、08:34:23 左右，loginwindow 已完成關閉 App 的階段，
  隨後記錄建立新登入工作階段。這不能證明登入畫面實際顯示或可操作，
  也不支持直接把問題歸因於 KeyKey 的 applicationShouldTerminate 回傳取消。
- 08:29:02、08:33:11、08:35:44 有 ResetCounter 記錄；已檢視的最後一份含
  force_off。這不是可定位 KeyKey stack 的 crash report。
- 安裝後 TIS 即時狀態曾顯示 KeyKey enabled/selected，而 defaults 讀出的
  AppleEnabledInputSources 沒有 KeyKey。該偏好是未公開的儲存細節；
  差異只能列為診斷，不能單憑它判定資料遺失或直接寫回修復。

原始紀錄僅存在 Installer/local-builds/macos-logout-investigation-20261016，
不提交使用者系統紀錄。尚未重現登入卡住的呼叫堆疊，也未證明 USB 問題與
輸入法有共同根因。

## Apple 官方依據

- Apple 隨 Xcode SDK 提供的 Carbon/HIToolbox **TextInputSources.h**：
  TISRegisterInputSource 明確提供給輸入法安裝程式，讓系統重新找到安裝的
  bundle 並更新必要快取；支援 /Library/Input Methods 與使用者同名目錄。
  TISEnableInputSource / TISDisableInputSource 管理是否可供選用，
  TISSelectInputSource 管理目前選擇，三者不是同一件事。
- [QA1810：第三方輸入法管理](https://developer.apple.com/library/archive/qa/qa1810/_index.html)：
  Apple 的範例以 TIS API 啟用／停用輸入來源；鍵盤輸入法仍由鍵盤設定管理。
  此文件的主要範例是 palette input method，不是新版 macOS 升級流程的保證。
- [Core Foundation Ownership Policy](https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFMemoryMgmt/Concepts/Ownership.html)：
  Get rule 回傳物件不屬於呼叫者。TextInputSources.h 也明列
  TISGetInputSourceProperty 的結果不可由呼叫者直接 release。
- [Graceful Application Termination](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/AppArchitecture/Tasks/GracefulAppTermination.html)：
  登出、重啟、關機都可能進入 App 結束流程；更新重啟的保護不能直接當成
  系統登出卡住的證據。
- [允許 USB 與其他配件連接](https://support.apple.com/zh-tw/102282)：
  Apple Silicon 筆電的配件授權可能要求先解鎖。此說明只是 USB 排查依據，
  不能據此認定本次失效是正常行為，也不能把「一律允許」當作輸入法修正。

以下更新順序是依 API 契約與本次回報設計的候選修正，並非 Apple 保證可修復
所有登出或 USB 異常的官方配方。

## 候選修正

舊 postinstall 在覆蓋 bundle 後，以全域 pkill 直接終止輸入法；沒有處理
仍被選取的舊來源，也沒有更新 TIS 註冊。

新的獨立 KeyKeyInputSourceTool 隨 App 由內而外簽章；不啟動 IMK、
不載入詞庫、不開網路、不修改 HIToolbox plist。postinstall 在目前 console
使用者的 GUI bootstrap 與帳號權限下執行，避免以 Installer 的 root 身分操作 TIS。

1. 用精確 input-source ID 讀取 TIS enabled 與目前 selection；無法取得目前來源 ID、
   或目前琦琦不在來源清單時停止，不把讀取失敗推定為未選取。
2. 若目前選取琦琦，先切到已啟用、可選取的 ASCII 鍵盤配置。
3. 只有原本已啟用的琦琦才暫時停用；確認停用後，結束同一使用者、
   相同安裝 executable path 的舊程序。使用 NSRunningApplication 正常 terminate，
   拒絕無效 PID 與自身，確認程序已退出，最多等 3 秒；不送原始 kill 或 SIGKILL。
4. 對固定安裝 bundle 呼叫 TISRegisterInputSource。
5. 恢復原先啟用狀態；只有原本正在使用琦琦時才選回。
6. 失敗時盡力恢復 enabled。尚未進入停止程序／重新註冊前，才嘗試恢復原選取；
   進入該階段後若失敗，維持已切換的 ASCII，不自動選回未證實安全的琦琦。
   最後選回琦琦若只部分成功，也再次盡力切回 ASCII；系統 API 仍可能失敗，
   不能保證恢復成功。TIS 選取驗證成功也不代表 IMK 已能實際輸入。
   整個 helper 最多 20 秒。逾時可能已完成部分步驟，不能宣告註冊成功；
   安裝記錄要求使用者在登出前透過鍵盤設定重新加入。

首次安裝或原本停用者只註冊，不自動啟用。沒有登入使用者、設定帳號、
非開機磁碟安裝都不碰目前使用者來源。其他快速切換使用者工作階段不會被
全域終止，也尚未涵蓋自動更新其註冊。啟用清單中的排序可能因重新加入而改變。
安裝失敗提示不代表 payload 已回復；檔案可能已安裝，註冊尚未完成。
postinstall 是在 payload 覆蓋後執行，尚未解決覆蓋期間舊 IMK 程序可能載入
新舊混合資源的問題；多使用者範圍只保證不主動終止其他工作階段，
不宣稱所有已登入工作階段都完成升級。

另修正 CVKeyboardHelper：不再 release TIS 借出的 type/source ID，
查詢限於鍵盤配置，並處理 NULL 清單、缺少 ID 與重載快取。這是可獨立確認的
記憶體管理錯誤，但尚不能宣稱是本次系統卡住的根因。

## 驗證與發布門檻

隔離入口：

```sh
bash Installer/test-input-sources.sh
```

測試以 fake TIS/假命令覆蓋首次安裝、原本停用、原本選取、其他來源仍被選取、
各階段失敗的恢復與套件腳本帳號路由。正式 helper 僅執行拒絕參數的入口；
測試不安裝、不切換輸入法、不登出。macOS target 另需編譯，
macOS 僅支援 arm64；封裝會拒絕其他架構或 universal App，helper 固定編譯 arm64。
封裝需確認 helper 與 App 均為 arm64、已被簽章且存在於安裝 payload。

2026-10-16 本機隔離驗證：32 項生命週期 policy、43 項真實 adapter 接假 TIS／
假程序、9 項鍵盤 helper 借用物件與快取、4 項 postinstall 路由測試全部通過。
包含持續 enable 失敗、部分 disable／select 後失敗、無法讀取目前來源、無效 PID、
拒絕終止與終止逾時。正式 helper 以 arm64 編譯通過；shell syntax 與
git diff --check 通過。macOS IMK Release target 已編譯通過。

另由既有 arm64 Release App 在獨立目錄產生 ad hoc 簽章 pkg，僅展開、不安裝：
helper 與主程式均為 arm64，展開 App 通過 codesign --verify --deep --strict
--all-architectures，postinstall 與來源內容相同。PackageInfo 為 relocatable=false，
relocate 清單為空；建置紀錄曾出現 PlistBuddy 的 write: Permission denied 診斷，
但展開結果未啟用 relocation，不能僅依該診斷判斷封裝失效。
此處是 ad hoc 封裝證據，尚未完成 Developer ID／notarization；Intel 不在支援範圍。

目前屬候選修正，不能因隔離測試或編譯成功宣告實機問題已排除。仍需在可恢復的
測試 Mac／獨立測試帳號驗證：beta4 手動升級、首次安裝、原本停用、其他來源被選取、
組字中安裝、每份文件自動切換輸入來源的設定、快速使用者切換，以及登出後登入欄位、
內建／USB 鍵盤輸入。背景 helper 的選取及 IMK deactivation 時序仍須平台觀察。
測試遇到相同背景與游標
停滯應停止重複操作，取得安全的系統診斷再分析。不得要求使用者反覆強制關機驗收。

已發布 beta4、商店版號與已安裝 App 不因原始碼修改而改變；此修正須先經 PR
人工 review，完成實機與簽章驗收後另行發布。
