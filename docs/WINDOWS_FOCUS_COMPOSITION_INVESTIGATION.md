# Windows TSF 焦點與組字安全調查

調查日期：2026-11-20。分支：`codex/windows-focus-composition-safety`；來源基底：`5f002cb4a5d370930580c1b1cbb7149b3dfbefd2` 加本分支的 Windows 前端與測試修改。使用者已分別同意修正游標同步，以及提示返回後延續未完成讀音。

## 重現與修正

1. **移動組字內游標後，下一鍵仍接舊句尾。** 真正 `ITfContext::SetSelection` 交易將「你好」改為「你｜好」，原版按 `a`（ㄇ）成為「你好ㄇ」，修正版為「你ㄇ好」。三句各 20 次的正式 TSF 原版對照，60／60 次錯位；最終來源修正版 60／60 次正確，也涵蓋長句已擠出前段的位置。
2. **未完成讀音被可輸入提示打斷，返回後無法補聲調。** 游標修正階段的 60 次補充檢查，原欄「你ㄏㄠ」返回補 `3` 成為「你ㄏㄠˇ」。新增恢復處理後，三句各 20 次，60／60 次正確完成原讀音；提示內輸入與原欄分離。一聲空白亦有檢查，沒有把整段重複提交。

本次只修改 Windows 前端與相關測試；核心、詞庫、版號及滑鼠選字功能沒有修改。沒有使用 gh，也沒有安裝、停用或切換主機正在使用的輸入法。

**證據分類更正：** 最初 600 次調查包含 120 次直接 `EM_EXSETSEL` 移動原生 caret 的案例。診斷發現 Win32 caret 已到 1，但 TSF `GetSelection` 仍為 2，不能將這 120 次全部歸因於前端。正式對照改用宿主 TSF 選取交易，另以記事本 Ctrl+Home 驗證移出組字後輸入；不宣稱原始 `EM_EXSETSEL` 相容路徑已修好。一般輸入沒有以特定 App 的原生 caret 覆蓋 TSF selection。

## 修正方式與既有防護

| 入口 | 確認結果與本次處理 |
| --- | --- |
| `cancelInput` | 沿用 input generation、作業取消、queue／retained effects 清除。恢復保存的是引擎狀態，不保存或重播待送按鍵／效果。 |
| `enqueueInput`／`pumpInput`／`runInput` | 保留原 context、token、generation 與有序 edit session。每次操作前新增宿主文字及 selection 核對，不只依賴 OnEndEdit。 |
| `OnEndEdit` | 舊版接受組字內 collapsed caret，未同步引擎位置。Windows adapter 現將安全 UTF-16 位置對映到完成音節邊界，呼叫既有 `set_cursor`；歧義位置、未完成讀音、外部改字及移出範圍時保留可見內容，結束舊組字。 |
| `retryInputResult` | 保留寫字、caret、結束組字階段。結果另持有本機副本，宿主呼叫重入取消後檢查 generation，停止後續寫入／移動 caret，避免使用失效物件；已處理按鍵不重播。 |
| `OnSetFocus`／`OnCompositionTerminated` | 只有閒置、沒有待送效果的好打注音未完成讀音可保存。返回原 context、原欄及未變文字／selection，且模式設定一致時才恢復同一核心 session。 |
| `OnKillThreadFocus`／`OnSetThreadFocus` | 保留候選退役／世代與重新定位核對；記錄已離開原欄，沒有焦點中斷的一般終止不自行恢復。 |
| 延遲 layout | 沿用原 context、候選 generation、focused top context、thread focus 與可輸入性核對；過期回呼不另建立候選。 |
| 退離組字 | 仍向原 context 取得 edit cookie 結束舊 composition，不轉到新欄提交。 |

恢復資料最多保存 8 份。一般持續存在的 TSF context 使用原 range 與複製的 selection；會重用同一 transitory context 的 RichEdit／IMM 宿主，另核對原 HWND、私有視窗 token、原文字範圍及 caret，避免欄位銷毀後 HWND 重用造成錯認。只有核對成功的原欄會以 `EM_SETSEL` 選取原範圍，再由正常 TSF 管線建立組字並處理下一鍵；沒有全域送字鍵或直接注入字串。外部改字、游標改位、欄位重建及明確模式切換會放棄舊狀態，保留可見文字。

宿主 selection／文字查詢也可能重入取消；恢復前先移出保存集合、局部持有快照，建立 composition 後再確認 generation。新增測試涵蓋這些讀取與寫入中的重入，不能只用執行前取消代替。

Windows 候選窗 `WM_MOUSEACTIVATE` 回傳 `MA_NOACTIVATE`，未見滑鼠按鈕選字或 macOS 舊版延遲送全域選字鍵路徑；本次沒有新增此功能。[前端來源](../Source/Loaders/Windows-TSF/TextService.cpp)、[Windows adapter](../Source/Loaders/Windows-TSF/GuanyinmaWindowsAdapter.cpp)、[候選窗](../Source/Loaders/Windows-TSF/CandidateWindow.cpp)。

## 最終來源與環境

| 項目 | 識別 |
| --- | --- |
| 原版 DLL SHA-256 | `880ca540b0c631e7b60570f06518fa75ab6704c457bcd2a92eed78f3692cae40` |
| 最終修正版 DLL SHA-256 | `eb888c6c7f82881cc3fa2b520ac61dc6a540bf6f766804fad68f7ab10a4065ac` |
| 共用 DB SHA-256 | `9c5443cc5a03b3f7fbe2adfa5f8ae26a2becb1b4b750ba195a40b02946a9ea1b` |
| 最終診斷宿主 SHA-256 | `6934dbb919da5d6eb007fc93fc0fdc6a2de84288716754e9998f9ee2b843407` |
| 來源固定紀錄 | 7 份修改檔案的 SHA-256（`final-source-hashes.json`） |
| 來賓 | Windows 11 26H2 build 26300.9457、x64，獨立 VM `KeyKey-Win11-focus-safety-20261120`；系統識別（`final-guest-os.json`） |
| 實際載入 DLL | `C:\FocusSafetyResume4\KeyKeyTsf.dll`，測試帳號既有 TIP profile 及專用 COM 對應 |
| 設定 | 好打注音、標準注音配置、繁體輸出、關閉省略聲調、10 音節組字 |

VM 是既有測試快照的獨立連結複本，網路、共用剪貼簿與拖放關閉。使用者已同意 VirtualBox 虛擬鍵盤 CLI，只對該 VM 送正常按鍵；這不是人工實體鍵盤代打。真正 RichEdit 雙欄宿主、可輸入原生 modal dialog 與記事本經 Windows TSF 輸入，不直接呼叫引擎或模擬產品 sink。宿主記錄文字、UTF-16 selection／composition、焦點、候選視窗及被動鍵盤事件；F7 在真正 edit session 內執行 `ITfContext::SetSelection`。

| 測試句 | 標準注音按鍵，␠ 為一聲空白 |
| --- | --- |
| 你好 | `su3cl3` |
| 放在這邊 | `z;4y945k41u0␠` |
| 請假要去哪裡玩呢去海邊 | `fu/3ru84ul4fm4s83xu3j06sk7fm4c931u0␠` |

長句預設實際文字可能為「請假要去哪裡**完**呢去海邊」。依使用者接受完／玩，只將這一對視為等價；原始紀錄保留實際文字，不改候選排序。

## 最終來源的宿主矩陣

最終來源 **780 次全部通過**，共 39 組，各組 iteration 1～20 完整且不重複。只使用標籤 `after-fix-combined-final3` 的來源對應紀錄，三句每情境各 20 次；先前版本及工具試跑不累加到最終驗收。完整彙總（`combined-final-summary.json`）。

| 情境 | 次數 | 核對重點（全部通過） |
| --- | --- | --- |
| 同 App：A 組字 → B 立即輸入 | 60 | 新欄不收到舊字 |
| 同 App：A 開候選 → B 立即輸入 | 60 | 沒有舊選字數字或候選復活 |
| RichEdit → 記事本 → 返回原欄 | 60 | 文字、焦點、重複提交及漏字 |
| 記事本 → RichEdit → 返回記事本 | 60 | 同上，明確送出的換行另行核對 |
| 正式 TSF 移動組字內 caret → 輸入 | 60 | 在新位置插入 |
| 記事本 Ctrl+Home 移出組字 → 輸入 | 60 | 原內容保留，新輸入在文件開頭 |
| 銷毀 A 欄 → B 輸入 | 60 | 舊操作不寫入 B |
| 最小化／還原 → 繼續輸入 | 60 | 游標與組字位置 |
| 完整讀音 → 可輸入提示 → 返回 | 60 | 原欄與提示文字分離 |
| 未完成讀音 → 提示 → 返回補聲調 | 60 | 延續原組字 |
| 未完成讀音返回後，原欄被改字 | 60 | 不恢復舊讀音、不覆寫新文字 |
| 未完成讀音返回後，原欄 caret 改位 | 60 | 不恢復到舊位置 |
| 未完成讀音返回後，銷毀重建原欄 | 60 | 新欄不恢復舊狀態 |

主矩陣共 600 次，另加恢復邊界 180 次，合計 780 次／39 組。異常旗標 0、返回補聲調未延續 0／60；檢查未見 U+FFFD 或不成對 surrogate，事件 selection／composition range 均未越過相應 TSF context 文字長度。沒有觀察到錯送欄位、舊選字數字、重複提交、漏字或過期候選復活；這是限定矩陣的結果，不代表涵蓋所有競態。

記事本使用獨立空白 fixture，沒有按 Ctrl+S 保存輸入結果；不操作其他草稿。工具、原始事件、截圖、測試包與執行紀錄留在 `Installer/local-builds/`，不提交；下列證據檔名均相對於該目錄，只供本機查閱，不是 GitHub 上的檔案連結。

收尾已關閉獨立來賓內的測試宿主與記事本，再正常關機，確認 VMState="poweroff"（`final-vm-state.txt`）。UI 操作已結束，未保存輸入文件。

## 事件順序與截圖

最終來源「你好」的 caret 案例：checkpoint `n=99, tick=1278781`，caret 2 → 真正 TSF 選取交易 → OnEndEdit `n=104, tick=1279046`，selection `[1,0]`、composition `[0,2]` → checkpoint `n=111, tick=1279062`，原生 caret 1 → 虛擬鍵盤 `a` → OnEndEdit `n=114, tick=1279343`，「你ㄇ好」、selection `[2,0]`、composition `[0,3]` → checkpoint `n=119, tick=1279359`，B 仍空白。

未完成讀音：`n=10990, tick=1368031`，A「你ㄏㄠ」 → `n=10993` 宿主終止原 composition → 提示獨立組字並提交「你好」 → `n=11046, tick=1368921` 關閉提示 → `n=11057` 返回 A，文字仍是「你ㄏㄠ」 → 按 `3` → `n=11061, tick=1369156`，A「你好」、selection `[2,0]`、composition `[0,2]` → `n=11068` checkpoint，提示仍「你好」、B 仍空白。

原始事件包含多次程序啟動，須合併檔名、tick 與情境判讀，不能把 n 當跨程序唯一序號。

- 原版正式 TSF 60 次（`matrix-cursor-after-fix-tsf-baseline-relative-all.jsonl`）、最終 caret 60 次（`matrix-cursor-after-fix-combined-final3-all.jsonl`）、最終提示返回 60 次（`matrix-prompt-incomplete-after-fix-combined-final3-all.jsonl`）。
- 原版錯位截圖（`screenshots/after-fix-tsf-baseline-relative-cursor-nihao-01-after.png`）、最終 caret 正確截圖（`screenshots/after-fix-combined-final3-cursor-nihao-01-after.png`）、最終返回補聲調截圖（`screenshots/after-fix-combined-final3-prompt-incomplete-nihao-01-resume.png`）。
- 最終記事本跨 App 截圖（`screenshots/after-fix-combined-final3-cross-app-nihao-notepad.png`）、反向跨 App 返回記事本（`screenshots/after-fix-combined-final3-cross-app-reverse-nihao-20-notepad-source.png`）。
- caret 事件（`events-cursor-after-fix-combined-final3-all-nihao.jsonl`）、提示事件（`events-prompt-incomplete-after-fix-combined-final3-all-nihao.jsonl`）、三種恢復邊界紀錄（`matrix-resume-safety-after-fix-combined-final3-safety-all.jsonl`）。

## 指定 x64 回歸

| CTest | 結果 |
| --- | --- |
| `KeyKeyTsfOutputCommitBehavior` | 通過，6.60 秒 |
| `KeyKeyPopupLifecycle` | 通過，0.37 秒 |
| `KeyKeyCandidateKeyStateMachine` | 通過，0.30 秒 |

[宿主交易測試](../Source/Loaders/Windows-TSF/TsfOutputBehaviorTest.cpp) 新增 20 個行為案例：沒有 OnEndEdit 通知的選取改動、UTF-16／已提交前綴、範圍外、未完成讀音、外部改字、過期候選、部分結果重試、讀寫中重入失焦、提示隔離、補聲調／Backspace 延續、文字／caret 改動拒絕恢復、一般終止與模式切換不復活，以及恢復建立／selection 查詢和保存狀態查詢時重入取消。

只建置受影響 target，沒有跑整套核心、其他平台、x86 或安裝器；建置只驗證／複製共用 DB，沒有 cooker。主要測試紀錄（`test-output.xml`）、候選與 popup 紀錄（`test-extra.xml`）。

## 驗收界線

本次限 Windows x64、上述好打注音設定、RichEdit 與記事本。Word、其他輸入法／配置、省略聲調、x86、其他平台與完整安裝／升級沒有由本次推定通過。

一般持續 TSF context 可以按原 range 恢復；transitory context 需要可驗證的原欄範圍讀取。普通 EDIT 或不提供可靠範圍讀取的宿主採保守處理，保留當時可見的普通文字，不保證延續讀音。已保存的原欄文字、caret、身分或設定改變時也不恢復。

欄位重建的 60 次紀錄中，新舊 HWND 都不同；視窗 token 是防止同值 HWND 重用的額外實作防線，本次沒有強制重現同值重用。

「錯送欄位」「游標錯位」「未完成讀音沒有延續」與真正 Unicode 編碼損壞分別記錄。「純打字被提示打斷後亂碼」仍未確認是相同問題，不能宣稱全面修好。本次只對明確重現的兩種行為做修正與限定驗收。

最初按鍵未抵達 VM、錯誤拼鍵、過快 Alt+Tab、宿主提示未恢復 child 焦點、F10 啟用原生選單、未登入來賓就使用 guestcontrol、舊紀錄快取及來賓自行關機等試跑均排除。正式驗收等待實際可輸入的目標與新的 checkpoint，按鍵釋放與輸入模式均核對後才計數。
