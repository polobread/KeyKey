# Windows：各 App 狀態與 TSF 用法研究

研究日期：2026-10-10。檢查基準：`v1.3.2`，commit `ed6572e288c21b250c89d5dacb2cee0b45d9f37d`。

前段保留修正前的研究基準；後續實作記錄見末尾「本輪修正」。

目前把中英文／全半形放在 thread manager、把使用者偏好跨 App 分享，方向合理；候選與組字也不是跨程序共用同一份記憶體。但模式變更回呼、視窗 owner 及 UI 執行緒失焦保護有具體缺口。後兩者值得優先追查候選窗／符號表殘留；目前仍不能據此宣稱已找出使用者白框的根因。

研究階段只產出文件；後續修正仍未安裝或替換使用者正在使用的版本。

## 文件閱讀範圍

從 Microsoft 的 [TSF 官方目錄](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/TSF/toc.yml) 建立完整清單，閱讀主指南 31 頁正文，逐項檢閱目錄連結的 748 個 API 頁之 description / remarks；與本次程式呼叫相關的介面再核對參數、回傳值與限制。另外核對 compartments、conversion flags、categories、properties、status 等參考頁，以及 Windows IME requirements、模式相容性文件與 Microsoft SampleIME 的焦點處理。

完整連結、頁數分組、快照雜湊及閱讀層級見 [官方文件索引](WINDOWS_TSF_OFFICIAL_DOC_INDEX.md)。其餘 140 個 reference／常數／型別／glossary 頁均納入索引，相關項目另讀；不是每一個過時 speech、soft keyboard 或 handwriting API 的所有參數、範例均已精讀或實作驗證。沒有把下載成功當成全文閱讀，也沒有把文件範例視為實機驗收。

官方文件橫跨 Windows XP 至目前 Windows apps。舊控制台畫面、舊版搜尋整合及歷史 ctfmon 說明不能直接推定 Windows 11 的每個宿主行為；本次結論以仍適用的介面契約為主。

## 「每個 App 自己的設定」實際分成哪些層

TSF 的服務是載入宿主程序內的 COM DLL；thread manager 管一個執行緒，document manager 管文件，context 管文字編輯環境。一個 App 可以有多個 UI 執行緒、文件及 context。App 名稱或 exe 並不是 TSF 保存所有狀態的最小單位。[Architecture](https://learn.microsoft.com/en-us/windows/win32/tsf/architecture)、[Thread Manager](https://learn.microsoft.com/en-us/windows/win32/tsf/thread-manager)、[Document Manager](https://learn.microsoft.com/en-us/windows/win32/tsf/document-manager)、[Edit Contexts](https://learn.microsoft.com/en-us/windows/win32/tsf/edit-contexts)

Compartment 有 global、thread、document、context 四個範圍；global 明確用於跨程序分享。[Compartments](https://learn.microsoft.com/en-us/windows/win32/tsf/compartments)

| 狀態 | 系統／產品範圍 | 琦琦目前實作 | 評估 |
|---|---|---|---|
| Windows 選用哪個輸入法／語言 profile | 由 Windows 與使用者的每視窗輸入法選項管理 | 一個正式臺灣中文 profile，四種內部引擎不各自註冊 profile | 合理；不能把內部引擎選單當成四個 Windows profile |
| 中英文開關 | 標準 `KEYBOARD_OPENCLOSE`；thread manager compartment | 每個 `TextService` 有 `chineseMode_`，同步該 thread 的標準 compartment | 範圍合理；外部通知的寫回方式需要修正 |
| 全半形及 conversion mode | 標準 `KEYBOARD_INPUTMODE_CONVERSION`；thread manager compartment | 每個服務有 `fullWidthMode_`，更新 FULLSHAPE／NATIVE 時保留其他 bits | 範圍合理；啟用時固定重設半形是另外的產品政策 |
| 好打注音／傳統注音／倉頡／簡易 | 琦琦自訂偏好 | `SharedInputMethod` 使用 global compartment，並有磁碟偏好 | 刻意跨 App 跟隨最近選擇；TSF 允許此用法 |
| 簡體輸出、啟動中文／英文偏好 | 琦琦自訂偏好 | 使用各自獨立 global compartment；啟動偏好沒有與即時中文狀態共用 GUID | 分離正確 |
| 候選字型、縮放、布局、鍵盤配置、學習資料 | 使用者偏好／資料 | 一般桌面宿主用使用者設定目錄；受限宿主可能用私有可寫目錄 | 可共用，但不能假設 AppContainer 一定能讀寫同一個檔案 |
| 組字、未完成讀音、候選結果、待處理輸入、候選及符號 HWND | 當前服務與 context 的生命週期 | 引擎 session／queue／generation／UI 屬於個別 `TextService` | 基本隔離正確；UI 執行緒失焦的處理尚不完整 |
| 禁止鍵盤、特殊空 context、唯讀、InputScope | 宿主／輸入欄位 | 沒有完整 eligibility 檢查 | 需補宿主條件，不能只看自家中文模式 |

標準 compartment 的指定範圍見 [Predefined Compartments](https://learn.microsoft.com/en-us/windows/win32/tsf/predefined-compartments)。這是 thread manager 介面的即時狀態；宿主／Windows 可以在切換 input context 時保存及還原它，不表示所有同執行緒欄位永遠強制共享同一種行為。

Microsoft 記錄 Windows 8.1 把 conversion／sentence mode 改為保存在 input context；「讓每個 App 視窗使用不同輸入法」只影響輸入法選擇，不代表開啟或關閉這個選項就應把所有 App 的中英文模式同步。此文件描述歷史行為界線，Windows 10／11 與個別宿主仍須實測。[IME mode model changed from per-user to per-thread](https://learn.microsoft.com/en-us/windows/compatibility/ime-mode-model-changed-from-per-user-to-per-thread)

因此可以出現：Codex 用中文、另一個 App 用英文，但兩邊的中文引擎都跟隨最近選的倉頡；字型與大小仍共用。這幾種狀態並不衝突。目前沒有依 exe 名稱建立各 App 設定檔，也不需要靠這種方式修正 TSF 生命週期。

## 需要優先修正的用法

### 1. 模式通知內可能再次寫入正在通知的 compartment

**P1，API 契約問題；有原始碼路徑及獨立 Windows 實驗支持。**

官方說 `OnChange` 中可讀取新值，但在通知內呼叫 `SetValue` 會得到 `E_UNEXPECTED`。[ITfCompartmentEventSink::OnChange](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfcompartmenteventsink-onchange)

目前路徑：

```text
TextService.cpp:1799 OnChange
  → requestModeChange / setChineseMode
  → enqueueInput → pumpInput
  → 無 context 時直接 runInput；有 context 時先要求同步 edit session
  → publishChineseMode / setFullWidthMode
  → 對標準 compartment 再次 SetValue
```

`pumpInput` 在第 419–429 行沒有保證離開通知後再處理；fallback 的 `TF_ES_ASYNCDONTCARE` 也允許同步執行。`updatingModeCompartments_` 只避免自己的通知再次進入，不能解除 TSF 的寫入限制。`publishChineseMode` 第 907 行忽略 `WriteChineseMode` 回傳值；`setFullWidthMode` 第 939 行記錄 HRESULT，但本地布林值已先改動。

在目前 Windows 上，以兩個隨機 GUID 的私有 thread compartments 做隔離實驗，x64／x86 結果一致：同一個 compartment 在通知內寫回被拒絕，通知外原始寫入成功。另一個未在通知中的 compartment 本機允許寫入；不能把它誤報成所有 compartment 都被鎖住。

```text
outer=0x00000000 inner=0x8000FFFF innerOther=0x00000000
notifications=1 read=0x00000000 vt=3 value=1
```

這確認 API 的拒絕行為，沒有重現使用者白框。相同值重寫被拒絕時，原始外部值可能已經正確；不能宣稱每次通知都會造成錯誤。但在需要同步另一個模式欄位或組字送出失敗而試圖還原時，忽略失敗就可能留下本地狀態與宿主狀態不一致。

建議區分「使用者要求改模式」與「宿主通知模式已改」：後者採用外部值，避免立即寫回通知來源。若需要先結束組字、協調 OPENCLOSE／NATIVE 或還原失敗操作，安排在通知結束後執行，再檢查每筆寫入結果；不要只換成 ASYNCDONTCARE 就當成已延後。

### 2. GetWnd 成功但 owner 為空時，可能建立無 owner 的置頂窗

**P1，官方候選 UI 要求的缺口；白框相關性仍是待驗證推論。**

`GetWnd` 成功也可能回傳 NULL HWND，例如 windowless control；不能只檢查 HRESULT。[ITfContextView::GetWnd](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfcontextview-getwnd)

目前兩條路徑都有缺口：

- `TextService.cpp:1641` 以 NULL 初始化 owner，`GetWnd` 成功回傳 NULL 時仍進入 `candidateWindow_.show`。
- `TextService.cpp:1025` 先用 `GetFocus()`，再把同一變數交給 `GetWnd`；若後者成功回傳 NULL，原本的 fallback 就被覆蓋。

`CandidateWindow.cpp:90`／`SymbolPanel.cpp:238` 直接設定 `GWLP_HWNDPARENT`，兩者都使用 `HWND_TOPMOST`，沒有拒絕 NULL owner。缺少擁有者的窗不會得到預期的宿主視窗連帶隱藏／銷毀行為。

官方候選窗要求取得有效 owner，`GetWnd` 失敗或為 NULL 時再呼叫 `GetFocus()`。[IME requirements：Owned window](https://learn.microsoft.com/en-us/windows/apps/develop/input/input-method-editor-requirements#owned-window)

建議共用一個 owner 解析流程，取得後驗證 HWND 仍有效且與當前宿主焦點一致；若 fallback 也無效，暫不顯示。不能把另一個 App 的 `GetForegroundWindow()` 當成替代 owner。

### 3. 沒有 UI 執行緒失焦 sink，延遲回呼也未重新檢查前景

**P1，候選／符號殘留的高優先追查路徑；尚未在 Codex／Edge 實機重現。**

`ITfThreadFocusSink` 專門通知 UI 執行緒取得或失去焦點；`IsThreadFocus` 可查當前狀態。[ITfThreadFocusSink](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nn-msctf-itfthreadfocussink)、[IsThreadFocus](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfthreadmgr-isthreadfocus)

`TextService.h`／`adviseSinks` 沒有實作或訂閱它。已有 `ITfKeyEventSink::OnSetFocus(BOOL)` 和 `ITfThreadMgrEventSink::OnSetFocus(document)`，但它們分別描述按鍵服務與文件焦點，不能據此假設已覆蓋每次 UI 執行緒失焦。[Key event focus](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfkeyeventsink-onsetfocus)、[Document focus](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfthreadmgreventsink-onsetfocus)

`refreshCandidateLayout` 第 1629 行只檢查 candidate generation、context 及 active 狀態，顯示前沒有查 `IsThreadFocus` 或重新比對目前 focused document／top context。若宿主仍保留原文件焦點、UI 執行緒卻已失焦，舊版面回呼有機會重新顯示候選窗。

Microsoft SampleIME 另訂閱 ThreadFocusSink，失焦時隱藏 presenter，回來時只對相符文件還原。[官方 ThreadFocusSink.cpp](https://github.com/microsoft/Windows-classic-samples/blob/main/Samples/IME/cpp/SampleIME/ThreadFocusSink.cpp)

建議訂閱此 sink，失焦立即關閉候選／符號 UI、撤銷過期 UI 回呼；每次延遲顯示及符號插入前再確認 thread focus 與 context。暫時 Alt+Tab 的「隱藏 UI」與「取消或送出組字」要分開定義，不能為了關白框直接丟掉所有未完成文字。

## 其他應補上的宿主相容性

| 項目 | 現況與建議 | 優先程度 |
|---|---|---|
| 禁用／空 context | `OnTestKeyDown` 第 1116 行忽略傳入 context；未讀 `KEYBOARD_DISABLED`／`EMPTYCONTEXT`。在 TestKey、Key、符號入口共用 eligibility 檢查，禁止的 context 不吃鍵、不顯示候選、不插入。`EMPTYCONTEXT` 是 TSF 的特殊狀態，不能把普通空白文字欄位當成禁用。 | P2 |
| 唯讀與欄位提示 | 未使用 context `GetStatus`／InputScope。read/write session 會回報唯讀，但選單／切換鍵仍可能先被吃掉。唯讀先擋編輯；email、URL、數字等 scope 是宿主提示，是否調整行為需另定義。Password scope 不能簡化成所有宿主一律禁用 IME。 | P2 |
| Light dismiss | 候選窗已有 IME_SHOW／IME_HIDE，但移動或縮放未發 IME_CHANGE；每次更新都發 SHOW。符號表沒有這三種通知。依實際可見狀態轉換發送，位置／大小改變發 CHANGE。 | P2 |
| 啟用時預設模式 | `applyStartupInputMode` 第 893 行套用設定並固定重設半形，沒有先採用現存 thread mode。目前 README 明確定義「下次服務啟用生效」，所以不能誤報為每次換 App 都重設。建議明訂已有有效宿主狀態時是否保留，只在需要初始化時用預設值。 | P2／產品政策 |
| UILess／宿主繪製候選 | 未實作 `ITfUIElement`／candidate UIElement，也未註冊 UIELEMENTENABLED category。一般自繪候選仍可使用，但不能宣稱支援要求宿主繪圖的 UILess 場景。實作 Begin／Update／EndUIElement、候選資料與宿主顯示決定後才宣告能力。 | P2／功能範圍 |
| 特殊啟用環境 | 現在只判讀 immersive flag；官方建議用 `ITfThreadMgrEx::GetActiveFlags` 查環境。secure／COM-less 等能力尚未宣告，不能只新增 category 來擴大適用範圍。 | 後續相容性 |

上述欄位狀態依據：[Predefined Compartments](https://learn.microsoft.com/en-us/windows/win32/tsf/predefined-compartments)、[ITfContext::GetStatus](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfcontext-getstatus)、[TS_STATUS](https://learn.microsoft.com/en-us/windows/win32/api/textstor/ns-textstor-ts_status)、[InputScope](https://learn.microsoft.com/en-us/windows/win32/api/inputscope/ne-inputscope-inputscope)。

Light dismiss 的 SHOW／HIDE／CHANGE 及避免常駐 IME 窗要求見 [IME requirements](https://learn.microsoft.com/en-us/windows/apps/develop/input/input-method-editor-requirements#ime-candidate-window-interaction-with-light-dismiss-surfaces)。UILess 接口與能力宣告見 [UILess Mode Overview](https://learn.microsoft.com/en-us/windows/win32/tsf/uiless-mode-overview)、[ITfUIElement](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nn-msctf-itfuielement)、[ITfUIElementMgr](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nn-msctf-itfuielementmgr)。

UILess 文件對轉換候選的分頁資料建議，不是要求符號工具表一定分頁；使用者指定的捲軸符號表可以保留。Windows 搜尋能輸入，也不能當成已支援宿主內嵌候選 UI 的證據。

啟用環境與能力界線見 [GetActiveFlags](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfthreadmgrex-getactiveflags)、[ActivateEx](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itftextinputprocessorex-activateex)、[Predefined Category Values](https://learn.microsoft.com/en-us/windows/win32/tsf/predefined-category-values)。

## 已經合理的設計

- 組字／插字在 edit session 內做；layout 重試使用 async read session。每個服務另有輸入佇列，避免後來的同步操作越過已接受的非同步按鍵。TSF 自身會優先處理同步 session，因此自家佇列仍有必要。[RequestEditSession](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfcontext-requesteditsession)
- session 銷毀時能處理沒有 `DoEditSession` 的取消情境；generation 避免過期結果影響新作業，方向符合服務停用／context 移除時的回呼規則。[ITfEditSession](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nn-msctf-itfeditsession)
- `GetTextExt` 無版面時先藏 UI 等待通知；零高度矩形不顯示，零寬度 caret 則仍可定位。[GetTextExt](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfcontextview-gettextext)
- Deactivate 會取消輸入、結束本地組字狀態、移除 sinks／language bar／function provider，釋放 manager 及 shared compartment 引用。
- x64／x86 以相同 CLSID、同一個產品 profile 註冊各自 DLL。兩種 DLL 可以同時被不同 App 使用，因此共享檔案需要協調；不是切換 App 時把同一個 C++ 物件在 32／64 bit 間重新解讀。[64-Bit Considerations：Text Services](https://learn.microsoft.com/en-us/windows/win32/tsf/64-bit-platform-considerations#64-bit-considerations-for-text-services)
- 先前補上的設定鎖、合併寫入、SQLite 交易與學習清除 generation 保護，處理的是共用資料競爭。候選 HWND／context／COM 指標仍是各自程序與服務內的狀態。兩類問題需要各自驗證，沒有證據可把白框直接歸因於跨位元資料型態。

受限宿主的私有 Temp fallback 有助於維持輸入，但偏好與學習的持久性可能與桌面不同。目前 global compartments 傳的是固定整數偏好，不傳 HWND、指標或位元相依 struct；仍須測可讀取範圍與失敗 fallback，不能把沙箱繞過當成同步方案。

## 建議修正順序與驗收

先完成通知內寫回、owner 解析、UI thread focus 三項，再補 context eligibility 與 light dismiss。保留現有跨 App 偏好政策，避免把穩定性修正與四種引擎是否各 App 記憶混在一起。UILess／搜尋整合另列完整功能工作。

| 驗證層 | 必要情境 | 要證明的行為 |
|---|---|---|
| 真實 TSF compartment | 外部改 OPENCLOSE／NATIVE／FULLSHAPE，包含同時改兩種 bit、組字送出失敗、沒有 context | 通知內不寫回來源；宿主／本地／圖示一致；失敗不被掩蓋 |
| 隔離宿主 | thread focus 失去但 document 仍保留；失焦後 layout 才就緒；舊 async session 延後／重複回呼 | 不在其他 App 上重開舊 UI，不跨 context 重播文字 |
| Owned popup | GetWnd 失敗、S_OK＋NULL、有效 owner、owner 銷毀／重建、最小化／還原 | 有正確 owner 才顯示；取消後不被宿主還原為空窗 |
| Context 受限 | KEYBOARD_DISABLED、EMPTYCONTEXT、正常空白欄位、唯讀、不同 InputScope | 禁用時不吃鍵；正常空白欄位仍可輸入；提示不被錯當硬性禁用 |
| 桌面實機 | Codex／Edge／Firefox／Notepad／Office，x64 與可取得的 x86 文字宿主交錯 Alt+Tab | App 各自中英文／全半形保持一致；候選與符號不遮住別的 App |
| Windows 選項 | 每視窗不同輸入法選項開／關；Win+Space 與內部引擎選單分開測 | OS profile 選擇與琦琦 global 偏好界線正確 |
| 受限宿主 | Windows 搜尋／Store 宿主往返桌面；無可寫 Roaming 目錄 | 沒有越權存取；偏好 fallback 合理；能輸入不等於有內嵌候選 |
| 初次載入／UI 邊界 | 開機後首次輸入、宿主慢 layout、DPI／跨螢幕、light dismiss、鎖定／解鎖與服務停用 | 沒有延遲置頂窗、漏字或重複字；事件與 UI 實際狀態一致 |

這張表是待做的驗收，不是已通過清單。本輪實際執行的是官方契約研究、原始碼核對及下述 compartment 隔離實驗。

現有 `TsfOutputBehaviorTest.cpp:170` 的 mock `GetWnd` 固定回傳 S_OK＋NULL，第 305 行仍期待候選可見；它能驗證延遲定位，但沒有驗證 owner。`IsThreadFocus` mock 固定為 TRUE，沒有真實失焦場景。`PopupLifecycleTest` 有有效 owner 與 ShowOwnedPopups 回歸，應保留並補上述邊界，不能用其通過代替 Codex／Edge 實機白框驗收。

## 本輪 compartment 實驗紀錄

MSVC x64、x86 分別建置並執行單獨 probe：

1. STA 初始化 COM，建立 `ITfThreadMgrEx`。
2. 以 `TF_TMAE_NOACTIVATETIP | TF_TMAE_NOACTIVATEKEYBOARDLAYOUT` 啟用，沒有註冊 TIP 或切換使用者鍵盤。
3. 建立兩個隨機 GUID 的 thread compartments，在其中一個 advise `ITfCompartmentEventSink`。
4. 通知外把第一個值設為 1；其第一次 `OnChange` 內嘗試把同一 compartment 及另一個 compartment 設為 2。
5. 同一 compartment 內部寫入回傳 `0x8000FFFF`，最終讀值仍為 1；另一個 compartment 的寫入成功。
6. Unadvise、清除兩個私有 compartment、Deactivate、釋放 COM。

兩種架構均 exit 0；編譯未報警告。probe、exe、obj 與下載快照放在忽略的 `Source/Loaders/Windows-TSF/out/tsf-review/`，屬本機研究產物。此實驗只證明通知內同一 compartment 的寫入限制，沒有執行完整 KeyKey ActivateEx、切換實際 App，亦沒有重現白框。

## 本輪修正（2026-10-10）

修改範圍限定於 Windows TSF frontend。沒有修改 macOS 或共用 framework／注音引擎／模型，不需要為本次修正分叉共用核心。

- 新增 host-mode operation。收到外部通知時不寫回來源，既有組字與已接受的按鍵依原佇列完成後才採用新模式；有文字 context 時使用強制 async edit session，沒有待送出的文字時以私有 message-only window 延後。另一個 OPENCLOSE／NATIVE 欄位於通知結束後才協調；第一個欄位出現時不會取消尚未採用的模式通知。
- 模式寫入會檢查 HRESULT，本地狀態只在使用者寫入成功後改動；第二個 compartment 寫入失敗時盡力還原第一個。宿主拒絕 mode edit session 時，在通知外還原保留的原模式及組字，不在回呼內嘗試寫回。系統持續拒絕 compartment 寫入仍需記錄錯誤，不能保證外部拒絕時強制改值成功。
- 新增並訂閱 ITfThreadFocusSink。UI 執行緒失焦隱藏候選、關閉符號與撤銷舊 UI generation；保留組字與候選資料。恢復時只對仍為 focused top context 的候選要求重新定位。文件移除、TIP 停用及既有按鍵服務失焦仍依其原本取消／結束流程處理。
- 候選顯示與符號開啟／插入檢查 thread focus、當前 document／top context。GetWnd 失敗或 NULL 時使用 GetFocus；owner 必須為有效、同宿主程序的 HWND，否則不顯示。候選與符號繪圖物件本身也拒絕 NULL／失效 owner。
- 共用 eligibility helper 檢查 context 的 KEYBOARD_DISABLED、EMPTYCONTEXT 與唯讀 status；按鍵查詢／處理、候選及符號入口均使用。正常空白文字欄位不被誤認成 EMPTYCONTEXT。執行延遲按鍵前再檢查，禁用後不重播舊輸入。
- 候選與符號的 Windows IME SHOW／HIDE／CHANGE 依可見狀態及位置／大小變更發送；正常更新不重複 SHOW，宿主 ShowOwnedPopups 隱藏／還原也有對應事件。
- 用 GetActiveFlags 判斷 immersive 環境；啟用失敗清除待處理作業及 shared output 引用，停用／銷毀時清理私有 dispatch window。

保留原本「服務下次啟用套用啟動偏好」與四種中文引擎跨 App 分享的產品政策。InputScope 行為調整、UILess／搜尋內嵌候選及 secure／COM-less 等尚未宣告的能力是後續功能範圍，本輪沒有新增能力宣告。

回歸涵蓋真實 TSF compartments 的無 context 通知、contract mock 的強制 async／來源不回寫／拒絕 session／寫入失敗、原生 popup 的 NULL owner／fallback／失焦晚到回呼／light dismiss，以及原有輸入切換、符號、布局與取消測試。

實際驗證：

- MSVC／Ninja Release x64、x86 建置成功，產品版號仍為 1.3.2.0；本輪建置日志未報編譯警告。
- x64 CTest 的 32 項皆已通過驗證：完整執行先有 31 項通過，行為測試修正首欄位按鍵期待與同程序測試目錄一致性後，重跑通過。x86 完整執行 31／31 通過。CMake 只對 x64 配置 WPF controls 測試，因此兩者數量不同。
- 行為回歸保留 20 組有向輸入模式切換、68 種適用狀態，以及拒絕／取消／FIFO／選字與文字重試；新檢查使用真實 HWND、真實 TSF compartments 及符合已驗證通知限制的 contract mock。
- 正式 DB 的 SHA-256 仍為 `8fc3aead36cefd16a77c0a0d4319f7a305fb712b752db09396c8ac2bd4ebbfdb`，未 cooker 或修改模型。
- 產生本機未簽章測試安裝檔 `chichi77-KeyKey-1.3.2-windows-x64-setup-tsf-focus-20261010.unsigned.exe`（out/store-package，92,280,902 bytes）。SHA-256：`81ef55da17ece6cbcda89bcd029621b2e93799cb332cc9d568ea55f7f42c6af8`。
- 解開實際 EXE，17 個 manifest 檔案雜湊全部符合；8 個主要 payload 與當時建置／正式 DB 逐一符合，包含該輪的 x64／x86 TSF DLL。版號及 checksum 檔符合，診斷設定未預先啟用。此產物不含下節後續兩項修正。

尚未安裝此產物或替換使用者版本。安裝後需登出再登入，讓各宿主重新載入 DLL；以上隔離測試與封裝核對仍不能代替 Codex／Edge／Firefox／Office 的實機白框驗收。

## 後續兩項模式一致性修正（2026-10-10）

- 輸入法切換先準備新引擎並完成原文字，再發布 TSF 模式、偏好與共用方法。只有全部成功才替換原引擎與有效方法／設定簽章。TSF 模式寫入失敗不更換引擎或偏好；共用方法發布失敗回傳其 HRESULT，並還原先前偏好與中英模式。還原失敗會記錄錯誤；持續拒絕還原的宿主仍不能保證外部狀態恢復。
- 取消佇列時，若包含外部 host-mode 或尚待還原的模式，保留重新同步標記，而非保留原作業快照。清理原 context 後，在通知外重新讀 OPENCLOSE／CONVERSION，依最近的通知來源協調中英模式並讀取實際全半形值。私有訊息、下一次焦點及第一個新按鍵均能觸發；讀取失敗保留標記供後續重試。沒有 DoEditSession 的 host-mode 取消會結束原組字追蹤；舊文字作業不重播到新欄位。服務停用／啟用失敗明確關閉重新同步。
- 沿用 Windows frontend 的引擎 API；未修改 macOS、共用 framework 或正式模型。該輪未擴充 InputScope／UILess，第三項「兩個 compartment 回滾本身持續失敗」由下節後續處理。

新增隔離回歸包括三個發布拒絕位置（OPENCLOSE、CONVERSION、共用方法），檢查原引擎物件／有效方法／偏好／共享值／全半形均維持，解除拒絕後可正常切換；另有八組中英雙向、兩種通知來源、換欄位／未執行 session 取消，包含最新值不同於舊快照、第一鍵在訊息處理前抵達、晚到回呼，以及讀取失敗後焦點重試及停用清理。

驗證紀錄在忽略的 `out/tsf-review/build-modes-*.log`、`ctest-modes-*.log`。安裝與實際 App 行為另需驗收，不能由隔離回歸認定白框已完全修復。

最終 DLL 與測試以 MSVC／Ninja Release 建置；x64 完整 CTest 32／32、x86 31／31 通過，正式 DB SHA-256 不變。兩架構同時建置曾使 .NET 設定專案共用 assets 檔互相覆蓋（NETSDK1047），改為序列完成 x64 建置；這是本機建置安排的限制，沒有新增建置流程變更。本節修正尚未重打包安裝檔、安裝、commit 或 push。

## 部分寫入與回滾拒絕的恢復處理（2026-10-10）

- `WriteChineseMode` 保留原始失敗 HRESULT，另回報是否曾部分寫入與回滾 HRESULT。讀取兩個值並檢查資料型態後才寫入，略過已符合目標的值。第二次寫入失敗時檢查回滾結果，不再忽略；VT_EMPTY 無法用 SetValue 還原，不清除預定義欄位以避免破壞宿主訂閱，而由服務恢復保留的邏輯模式。
- 模式發布、全半形寫入、宿主互補欄位協調及方法切換回滾失敗時，服務保留中英／全半形恢復目標。第一次失敗安排一次私有訊息；重試仍失敗保留標記，但不繼續送訊息形成迴圈。後續焦點／輸入重試，只在兩項都成功後解除標記。方法切換回滾被拒絕時仍保留原引擎、原偏好及原本地模式。
- 最新外部模式通知取代舊恢復目標；即使通知的邏輯值與本地相同，也會協調尚未一致的另一個欄位。全半形及其他轉換旗標在復原時保留；VT_I4／VT_EMPTY 以外型態回報錯誤並拒絕覆寫。停用、啟用失敗清除恢復標記。
- 宿主持續拒絕時無法強制它接受寫入，但服務不遺失待恢復狀態、不忙迴圈，也不重播文字。解除拒絕後，下一次焦點或輸入可恢復一致；未新增輪詢計時器、網路行為或預設診斷。

API 邊界見 [SetValue](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfcompartment-setvalue)：允許型態不包含 VT_EMPTY；[ClearCompartment](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfcompartmentmgr-clearcompartment) 會移除 compartment 且受 owner 限制，所以不能當作通用的回滾方式。

新增隔離測試涵蓋中英雙向的第二次寫入／回滾都拒絕、訊息重試上限、仍拒絕時的焦點重試、解除拒絕後恢復、來源欄位已符合目標時不重寫、VT_EMPTY 回滾、方法回滾拒絕、宿主互補欄位與還原都失敗後由按鍵恢復、新通知覆蓋／相同邏輯通知、未知型態保護及停用清理。保留既有輸入與文字回歸；安裝檔與實際 App 白框行為仍須另行驗證。

建置與回歸紀錄在忽略的 `out/tsf-review/build-recovery-*.log` 與 `ctest-recovery-*.log`。修改僅在 Windows frontend；macOS、共用模型與輸入核心未變。

實際驗證：MSVC／Ninja Release x64、x86 完整建置均成功，未報編譯警告；完整 CTest 分別 32／32、31／31 通過。正式 DB SHA-256 仍為 `8fc3aead36cefd16a77c0a0d4319f7a305fb712b752db09396c8ac2bd4ebbfdb`，`git diff --check` 及本輪檔案尾端空白檢查通過。本節未重打包安裝檔、安裝、commit 或 push；隔離測試不代替實機白框驗收。
