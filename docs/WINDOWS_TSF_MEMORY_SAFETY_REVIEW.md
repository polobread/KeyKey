# Windows TSF 記憶體安全檢查（2026-10-10）

原始檢查針對 `v1.3.2` 工作樹，包含尚未提交的候選／符號生命週期與模式恢復修正。範圍是 Windows TSF adapter、候選窗、符號表／emoji、引擎 adapter、共用設定／模式讀寫及設定 backend 的主要緩衝區入口；共用核心以 Windows 原生輸入回歸覆蓋，沒有逐行審查儲存庫全部平台與第三方程式碼。原始檢查未修改產品程式碼；後續修正如下。兩輪均未安裝、註冊或選取 TIP。

## 修正與驗證（2026-10-10）

三項問題已在目前工作樹修正；原生建置與隔離回歸通過，尚未替換已安裝 DLL 或完成實際 App 驗收。

- `WindowClass.h` 管理可重試、可清理及可重新註冊的類別。遇到 `ERROR_CLASS_ALREADY_EXISTS` 時核對模組與 WNDPROC，不直接接受同名類別；符號類別只註冊一半時也可清理／重試。`DllCanUnloadNow` 在物件與 server lock 計數歸零後解除三個類別，解除失敗則回傳 `S_FALSE`。新 class factory 與閒置清理互斥；TextService 以基底生命週期計數，直到 HWND、引擎及其他成員全部析構後才減少計數。符合 [UnregisterClassW 的視窗銷毀前提](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-unregisterclassw)。
- `ShutdownEngineRuntime` 在 loader lock 外明確釋放引擎、loader 與 DB 連線，live session 或有序輸入尚未結束時拒絕清理。runtime 建立、操作及清理共用同一個不隨 runtime 刪除的 mutex。成功清理後可以重建；`DllMain` 不執行 User32 清理或完整引擎析構。程序直接終止時仍由作業系統收回資源。
- `RangeText` 每次讀取前重設 count，append 前先檢查單次 capacity 與剩餘總量，拒絕超過 1,024 字元的回傳值及超過 65,536 字元的總長。回歸涵蓋第一次／中途回傳 1,025 或 `0xffffffff`、同步切換／延後結束／宿主終止三條路徑，以及 1,024、65,536、65,537 的邊界；不把異常或部分文字寫回宿主。

### 本次結果

| 驗證 | x64 | x86 |
|---|---|---|
| Release 選定原生回歸 | 27/27 | 27/27 |
| ASan 選定回歸 | 15/15 | 15/15 |
| DLL 卸載／重載 | 10/10 | 10/10 |
| 同模組 runtime／類別清理後重建 | 20/20 | 20/20 |

Release 27 項包含新增的 `KeyKeyModuleLifetime`，本次未跑安裝、註冊、AppContainer 或設定 WPF 驗收。ASan 各先在沙箱通過 14 項；`KeyKeyTsfSystemTrayModes` 因隔離設定檔建立受阻，以一般使用者權限重跑後通過。不是單次沙箱 15/15。ASan 建置也因沙箱中的 MSVC PDB 錯誤改於一般使用者環境完成；測試啟動需載入對應 MSVC 工具環境，讓 ASan runtime DLL 可被找到。

`ModuleLifetimeProbe.cpp` 與產品的 ComServer、TextService、候選／符號及 engine 原始碼連結成測試專用 DLL，host 使用真正的 `DllCanUnloadNow`／`DllGetClassObject`。每次確認 live factory、service、server lock、engine session、有序輸入及 HWND 阻止卸載；清理後三個類別消失、正式 DB 可獨占開啟，`FreeLibrary` 後模組確實不再載入。另驗證多執行緒初次初始化及同名不同 WNDPROC 的部分註冊失敗。ASan 建置停用此 DLL 卸載案例，改由 `TsfOutputBehaviorTest` 驗證三輪同一模組內的引擎重建與清理。

十輪卸載後 PrivateUsage：x64 為 3,170,304 → 2,854,912 bytes（期間 2,158,592–3,694,592）；x86 為 3,096,576 → 2,985,984 bytes（期間 2,232,320–3,096,576）。未重現修正前每輪增加一份 runtime 的走勢。這仍不是完整 heap 洩漏證明；確認釋放入口與 DB handle、類別及模組生命週期才是主要證據。

本次紀錄在 `Source/Loaders/Windows-TSF/out/tsf-review/`：`build-memory-fix-{x64,x86}-{ninja,asan}.log`、`release-fixed-{x64,x86}.log`、`asan-fixed-{x64,x86}.log`、`asan-tray-fixed-{x64,x86}.log`、`lifetime-fixed-{x64,x86}.log`。建置產物與執行紀錄不提交；測試原始碼與 CMake 入口保留在工作樹。`git diff --check` 通過。下方 100 輪 GDI／USER 數字是修正前的基線，本次未重新量測同一個 100 輪探針。

## 原始檢查確認的問題（修正前）

### P1：DLL 卸載後保留視窗類別與失效的 WNDPROC

`CandidateWindow::ensureWindowClass` 與 `SymbolPanel::show` 以 DLL 的 `g_module` 和函數位址註冊三個視窗類別。物件析構會銷毀 HWND，但沒有 `UnregisterClassW`；`ComServer.cpp` 的 `DllCanUnloadNow` 只看 COM 物件與 server lock 數量。類別與回呼因此比 DLL 的載入生命週期更長，重新使用舊類別時可能呼叫已卸載或已變更的程式碼。

[RegisterClassExW 官方說明](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerclassexw) 明確指出 DLL 卸載不會自動解除其視窗類別註冊。不能只在析構時刪除視窗，也不能忽略重新載入時的 ERROR_CLASS_ALREADY_EXISTS。

隔離 Release 探針把未修改的候選／符號 object files 與引擎 library 放入私有 DLL，建立及銷毀物件後採用與產品相同的計數判定，再卸載 DLL。三輪均觀察到：計數判定允許卸載、類別仍存在、回呼仍是原位址，`VirtualQuery` 回報該回呼位址為 `MEM_FREE (0x10000)`。沒有呼叫失效回呼；每輪量測後由隔離 host 解除三個舊類別，避免下一輪意外執行它們。這不是對已安裝 KeyKey 或 Codex 的實機重現。

應建立可重用且與 DLL 生命週期一致的類別註冊／清理流程，並在相關資源尚未清理時阻止卸載。不要在 loader lock 下任意呼叫 User32 或執行完整引擎析構。

### P2：EngineRuntime 的跨 DLL 重載洩漏

`KeyKeyEngine.cpp` 的 `Runtime()` 使用 `static EngineRuntime* runtime = new EngineRuntime()`，刻意不執行析構，以避開程序終止時的 loader lock。單次載入下這是程序常駐的引擎；但目前 DLL 可以卸載，卸載後這個指標消失，原引擎圖及 DB／loader 資源沒有釋放，下一次載入會再配置一份。

同一隔離探針每輪初始化 SmartMandarin controlled session，正常銷毀 session 與 UI，再卸載 DLL。卸載後 PrivateUsage 為 `4,341,760 → 6,680,576 → 9,261,056` bytes，持續上升。數字包含程序／系統配置器保留的記憶體，不能把全部差額當成精確洩漏量；沒有釋放入口的 runtime 指標及其重載生命週期則是程式碼可確認的問題。

應讓引擎／視窗類別採一致的 DLL 生命週期政策：提供 loader lock 外的安全清理，或明確保留一次程序常駐的模組，避免可卸載模組每次留下無法再使用的引擎。

### P2：RangeText 缺少回傳字元數的邊界檢查

`TextService.cpp` 的 `RangeText` 向 `ITfRange::GetText` 傳入 `wchar_t buffer[1024]`，成功後直接 `text.append(buffer, count)`。若宿主違反契約，回報超過 capacity 的字元數，append 會越界讀取 stack；目前的 65,536 字元總長限制在 append 之後，不能保護單次讀取。

隔離 COM mock 仍只複製合法的文字量到緩衝區，但刻意將回傳 count 改成 `capacity + 1`。x64 ASan 在產品原始 `RangeText` 第 41 行抓到 `stack-buffer-overflow`，`READ of size 2050`，對應 2048-byte stack buffer。這是已重現的條件式越界讀取，沒有證據顯示正常 TSF 或實際 App 會回傳該錯誤值，也不是越界寫入或已知跨程序攻擊。

應在 append 前檢查 `count <= std::size(buffer)`，並於配置／複製前檢查剩餘總長；異常回傳應失敗並保留原組字，不接受超出緩衝區的內容。

## 驗證與限制

- 獨立 `out/build/x64-asan`、`x86-asan`：MSVC `/fsanitize=address`，保留原 Windows 定義、`/EHsc` 與 static CRT，使用 RelWithDebInfo、停用 incremental linking。原 Release 建置未替換成 ASan，也沒有產生 ASan 安裝檔。
- 兩架構各 15／15 正常回歸通過，涵蓋候選生命週期、符號／emoji、模式與延遲回呼、進階設定、表格輸入／學習與候選狀態。沒有在這些合法資料路徑抓到越界、use-after-free 或配置／釋放不一致；不代表所有分支或宿主安全。
- 非 ASan 的原生 popup 回歸重複 100 輪：GDI `12 → 12`、USER `2 → 2`。這只證明所測候選／符號開關及銷毀沒有持續增加這兩種資源，不等於完整 heap 洩漏檢查。
- DLL 卸載探針使用 Release，避免 [ASan 官方已知的部分插樁／DLL 卸載限制](https://learn.microsoft.com/en-us/cpp/sanitizers/asan-known-issues)。一般 ASan 回歸不提供本輪的洩漏量結論；洩漏判斷使用程式碼生命週期、獨立探針及資源計數。
- 故意違反 count 契約的額外探針會預期失敗，與 15 項正常回歸結果分開記錄。
- 探針及紀錄皆在忽略的 `out/tsf-review/`：`memory-unload-x64.log`、`popup-memory-stress-x64.log`、`ctest-asan-x64.log`、`ctest-asan-x86.log`、`asan-malformed-range-x64.log`，以及相應 C++／產生腳本。均使用隔離設定目錄。

上述三項在原始檢查時仍待修正，後續修正與本次結果見上節。未確認它們就是既有白框的觸發原因；實際 App、DLL 更新後重載及安裝驗收仍需另測。
