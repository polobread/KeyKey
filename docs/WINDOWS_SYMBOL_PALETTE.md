# Windows 符號表浮動與送字

Windows 符號表原本已使用 `HWND_TOPMOST`，但 TSF 文件／輸入執行緒失焦時會主動
呼叫 `closeSymbols()` 銷毀視窗。點選 App 非輸入區或切換 App 因而使符號表消失。
另可透過宿主 `SetWindowPos(HWND_NOTOPMOST)` 重現連帶移除 owned popup 置頂狀態。

macOS 的 `CVDictionaryWindow` 使用非啟用浮動 `NSPanel`、`NSStatusWindowLevel`，
`OpenVanillaController::deactivateServer:` 刻意不關閉符號表。Windows 改為同樣保留
浮動表面，並分開處理顯示生命週期及送字目標。

- 符號表使用獨立、不可啟用的隱藏 owner，不跟著原編輯視窗最小化；
  顯示期間於 `WM_WINDOWPOSCHANGING` 保持 topmost，不搶鍵盤焦點。
- 文件、欄位、輸入執行緒與中英模式變動只撤銷舊送字目標；一般打字和選取符號後
  保留符號表、分類與捲動位置，可連續選取。關閉按鈕或前景琦琦收到 Esc 時關閉；
  同一桌面再次開啟會重用可見符號表。
- 沒有可寫輸入區時，只停用符號按鈕並顯示「請先點選可輸入文字的區域」，分類、
  捲動與關閉仍可操作。每 250 毫秒重新確認前景目標，恢復可寫欄位後自動啟用，
  提示「可連續選取符號；點 × 或按 Esc 關閉」。查詢總等待上限 80 毫秒，點選時
  再確認一次；關閉視窗時停止計時器。此查詢只在本機 TSF 間交換可輸入狀態。
- 每個 TSF 服務以系統 `STATIC` 視窗類別建立隱藏送字入口，停用或析構時銷毀。
  符號表仍由開啟它的宿主程序持有，該服務停用或程序結束時會關閉，不是常駐外部程序。
- 選取時找目前前景視窗執行緒的琦琦入口，以有時限的 `WM_COPYDATA` 傳送完整 UTF-16。
  接收端只接受有長度上限的內建符號清單，並重新確認前景程序／執行緒、啟用中的
  琦琦及可寫 TSF context。沒有有效目標時不送字，不使用剪貼簿或模擬鍵盤作後備。
- 接收端排入既有有序輸入佇列，非同步取得 TSF 寫入權限；先保留目前組字再送符號。
  同一欄位的連續點選依序排入，不互相撤銷；真正寫入前再次核對 context 及 generation，
  切換焦點後的過期選取不寫回舊欄位。
  IPC 逾時不重送，避免重複插入；Windows UIPI 權限限制維持不變。

Win32 契約：[SetWindowPos](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos)、
[WM_WINDOWPOSCHANGING](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-windowposchanging)、
[TSF 文件焦點](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfthreadmgreventsink-onsetfocus)。

## 驗證入口

在已載入 MSVC 的 Developer PowerShell，從 Windows-TSF 目錄執行：

```powershell
cmake --build out/build/x64-ninja --target KeyKeyTsf KeyKeyTsfOutputBehaviorTest KeyKeyPopupLifecycleTest KeyKeySymbolPanelTest
ctest --test-dir out/build/x64-ninja -C Release --output-on-failure --no-tests=error -R '^(KeyKeySymbolPaletteRouting|KeyKeyTsfOutputCommitBehavior|KeyKeyPopupLifecycle|KeyKeySymbolPanelResourcesAndFocus)$'
```

`KeyKeySymbolPaletteRouting` 使用可見的隔離原生宿主及真實子程序，測試非輸入區、
最小化、唯讀及非輸入區停用／恢復、無效 IPC、欄位切換、延後選取取消、快速連點
與跨程序連續選字；無互動前景桌面時
回傳 77，由 CTest 明確標為 skipped，不能算通過。測試不註冊或安裝 TIP，不讀寫使用者詞庫。

跨 x64／x86 時先建置兩邊的 `KeyKeyTsfOutputBehaviorTest`，再指定另一邊的完整路徑：

```powershell
$env:KEYKEY_SYMBOL_TEST_PEER = (Resolve-Path out/build/x86-ninja/KeyKeyTsfOutputBehaviorTest.exe).Path
ctest --test-dir out/build/x64-ninja -C Release --output-on-failure -R '^KeyKeySymbolPaletteRouting$'
Remove-Item Env:KEYKEY_SYMBOL_TEST_PEER
```

反方向交換兩個架構。隔離 TSF provider 不是 Office 實機驗收；已安裝版本仍須在
Word／Excel 開啟符號表，點功能區、切換 App、最小化原視窗後，選字確認只插入目前
可寫欄位一次，連選多個符號後仍可操作；點非輸入區時確認停用與提示，點回欄位
確認恢復。另查 Esc、關閉、不同 DPI、一般／系統管理員權限及原宿主結束。
