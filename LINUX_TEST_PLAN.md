# Linux 自動化打字與發布驗收計畫

狀態：測試實作中。已有 CTest real-data typing-flow、Ubuntu 22.04／24.04
container build/staged-install checks、Ubuntu 22.04／24.04 Debian package checks，
以及 Ubuntu 24.04 Fcitx 5 → GTK 3 的 L3 X11 真實逐鍵輸入；下列完整
GNOME／Wayland、App、視窗與完整注音 suite 仍待實作。
搭配 [開發計畫](LINUX_DEVELOPMENT_PLAN.md)。

Linux 首版目標為 1.2.8。第一階段驗收 Windows TSF 目前實際提供的全部功能，對應
F01–F02、F05–F11，以及 F16 的 Windows 設定／語系部分；五種注音布局皆為必要。
候選學習／動態頻率、注音自動修正及 F12–F15 不屬 Windows parity。已完成的倉頡、
簡易與繁轉簡切片不拆除，T04／T05 繼續回歸但不阻擋第一階段。原 T13 退役；發布
必要 suite 指 T01–T03、T06–T12、T14–T15。F05 已有內建關聯詞、分類開關與 T07
第一段證據及一條 Fcitx 原生設定視窗點選／保存證據，其他設定、桌面及 App 驗收仍須補齊。

**主要環境：Ubuntu Desktop 24.04 LTS + Fcitx 5 + GNOME，x86_64。**
這一組須有最完整的打字、視窗、App、sandbox、安裝與穩定性測試；先完成此組
再擴充其他環境。IBus 在相同 Ubuntu 版本上的結果與 Fcitx 分開計算。

目前可重現的 L1／build 結果（2026-09-13）：Ubuntu 24.04 x86_64、ARM64 preview
及 Ubuntu 22.04 x86_64 container 均能編譯 engine 與 Fcitx 5 addon；CTest 以 repository
內真實 `bpmf-ext.cin` 驗證五種 Windows 支援布局，四種符號配置另固定
Standard／ETen 各 1,521 組、ETen26 1,495 組、Hsu 1,494 組真實讀音 round-trip 覆蓋，
並測漢語拼音代表性聲母／韻母／聲調、input-context 隔離、pass-through、
Backspace／Escape 在 reading、候選與空狀態的邊界、CIN 邊界、候選分頁、數字選取、
Ctrl 標點與真實符號候選表，以及
`Shift+Space` 全／半形狀態、ASCII 對映與組字／候選保留、Big5-HKSCS 可表示性與
候選順序，以及與現有輸出 filter 同源的 3,058 筆繁轉簡單字對映；關聯詞另以原生 parser 驗證 McBopomofo
基本詞庫、29 個分類詞庫、UTF-8／格式邊界、頻率排序、過濾、來源順序、去重、停用及
`Shift+1–9` 詞尾選取；Ubuntu 24.04 的相同 engine suite
亦已通過 ASan/UBSan。

另有三十二筆可重現的最小 L3 X11 證據：在 Ubuntu 24.04 x86_64 container 以獨立 D-Bus、
Xvfb、Fcitx 5.1.7 與真 GTK 3 Entry，T01 以 Standard `5j/` 選「中」；T02
在 Standard、ETen、ETen26、Hsu、Hanyu Pinyin 五種配置逐鍵輸入二、三、
四、輕聲的「麻馬罵嘛」，固定 ETen26／Hsu 複用鍵的消歧中間態，漢語拼音
另驗證不完整 `zh` 依序退格為 `z` 與空 preedit；五種配置都由聲調鍵立即開啟候選，
不再多按 Space，且每種配置都在第一個 reading 中送裸 `\` 與 `Ctrl+C`，確認無效鍵
不漏入 App、快捷鍵交回 App 並保留 reading，之後仍選出「麻」。T01 另以 `5j/` 開候選後直接輸入
下一 reading `jp6`，精確提交「中文」，並在 `ㄓ` reading 中送 `=`／`Ctrl+C` 後繼續
提交「中」，確認無效一般鍵不漏入 App、快捷鍵不破壞組字；T03 另驗證空狀態
Backspace 交回 GTK 刪除 App 文字、reading 中 Backspace
逐音退回、reading Escape 全部清除、候選中 Backspace 關窗並只退最後一音，以及候選
Escape 清除後可重新組字；整段只提交「中文麻」，沒有殘留 reading 或誤刪已提交文字；
倉頡 `a` 選第一候選「日」，另以直接標點、五碼查無結果清除及單一候選提交精確得到「，用」，再以
`a?`／`a*` 的一碼／零碼以上萬用字元精確得到「昌日」；簡易
`a` 選第二候選「曰」，另以兩碼自動開候選、下一碼提交反白候選並開始新組字、
單一候選自動提交及直接標點候選精確得到「明銖䍤、」；
另以注音 `5j/` 開啟 148 個真實候選，送 PageDown、Down、Enter 選出「妐」；第二個
T06 流程等待直式 Fcitx 候選窗完成展開，以 XTest 真實滑鼠點擊第二列並選出「鐘」，
同時避開候選窗剛 map 時的 1×1 與僅 preedit 大小；
`Shift+Space`、`Shift+A`、`Shift+1`、`Shift+\``、Space 提交精確全形 `Ａ！～　`，
`keyboard-us` 負控制為 ` A!~ `；T08 中英模式另以 `Ctrl+\` 與 300 ms 內的單按
Shift 切換，覆蓋有 reading 時轉英文的清除、Caps Lock、英文全／半形、
長按 Shift 不切換及切回中文；第二案關閉 `Ctrl+\` 選項後驗證快捷鍵交回
GTK3，KeyKey 狀態仍是中文；T09 再長按 `Ctrl+\` 一秒驗證只切換一次，切回中文後
先以兩邊相同的 `Ctrl+A`／Backspace 清除 X11 repeat 時序可能留下的裸反斜線，再於
reading 與候選期間送 Ctrl+C／Alt+F，仍精確提交 `x中文`，`keyboard-us` 負控制為
`x5j/ 1jp61`；T10 在第一欄候選開啟時，依 GTK host 回報的 widget geometry 以真實
滑鼠點擊第二欄，再以 Shift+Tab 切回，依序核對兩欄
preedit 清除及獨立提交「中／文」，候選開啟時關閉 client 後確認 Fcitx/addon 存活，
重啟 Fcitx 再由新 client 選出「中」，同樣含 literal 負控制；T11 先依 macOS、再比對
Windows，於 active reading 中送方向、Home／End、Delete／Tab 與 Shift 變體，確認不移
App caret／selection 或換欄並原位提交「中」，再用 Shift+Right 選取既有「乙」並由
候選替換，最終精確為「甲中中丙」；GTK3
密碼 content purpose 使 Fcitx 自動切回 `keyboard-us` 且拒絕強制選回自訂輸入法，
鍵序只產生 literal `rup 1!`，不可編輯欄收到完整注音鍵序後仍保持「唯讀」；Big-5
限制開啟時輸入
Standard `,4`，從過濾後的
`ㄝˋ` 候選選出 `𤦩`，英文負控制為 `,42`；另以 `Ctrl+0` 開啟真實標點／符號候選並按
`1` 提交「，」，第二案則以 XTest 點擊第一列後接 `!`，精確得到「，!」；兩者的英文
負控制分別只得到 `1` 與 `!`；繁轉簡原生設定開啟後，
以 `w96`、`j0` 分別組成 `ㄊㄞˊ`、`ㄨㄢ`，選原候選「臺灣」並提交「台湾」，
英文負控制為 `w962j0 1`；六個 T07 流程以實體 `Shift+1` 分別驗證預設基本詞庫
得到「今天」、只開 history 分類得到「臺灣史」、全部關閉時得到「臺!」，並驗證
舊逗號格式 migration 後仍得到「中程計畫」；第五案經 Fcitx D-Bus 設定 API 寫入、
核對 INI、重啟 process、讀回設定，
再以實際按鍵得到「中程計畫」；第六案以 AT-SPI 定位已安裝 `fcitx5-config-qt` 的
輸入法列及核取方塊，實際點選只開 agriculture-food、保存、核對 INI、重啟並讀回後，
並關閉、保存及讀回輸入錯誤提示聲與 `Ctrl+\` 切換選項，將候選樣式從直式改為橫式；
以 `yji4` 選「作」再按 `Shift+1` 得到「作物育種」，同時保存切換前後 PNG。
既有五種注音回歸皆依發生順序核對 preedit；Fcitx D-Bus schema 目前亦確認
`BopomofoLayout` 下拉選項含 Standard、ETen、ETen26、Hsu、HanyuPinyin，候選樣式含
Vertical、Horizontal，並包含繁轉簡、
所有 Unicode 字元、輸入錯誤提示聲、`Ctrl+\` 切換與 30 個關聯詞 Boolean 選項。
錯誤鍵案例會走過
libcanberra 的 XDG `bell-window-system` 呼叫，但 Xvfb container 沒有音訊 session，
實際可聽結果須留給 GNOME 桌面驗收。所有案例皆核對實際 GTK buffer，且
`/proc` maps 證明執行中的 Fcitx 載入 `chichi77-keykey.so`；每案切回
`keyboard-us` 重送同鍵序的負控制也通過。這些仍是窄版功能切片，尚未驗證
完整 T01–T06、GNOME、native Wayland、XWayland、Qt／GTK4／瀏覽器或候選視窗畫面。
Hosted Linux workflow run `34742072894` 已在 `d83091d` 通過 Ubuntu 22.04／24.04
兩個 job；後續每個待交付 SHA 仍需用自己的 run 當證據。

Ubuntu 24.04 的目前 slice 也已用 debhelper 拆成架構無關的
`chichi77-keykey-data_1.2.8-1+ubuntu24.04_all.deb` 與 amd64 的
`fcitx5-chichi77-keykey_1.2.8-1+ubuntu24.04_amd64.deb`。乾淨 runtime container
最近一次 package 證據依序安裝受控 `1.2.8~preview1` fixture、跑三十一個非設定視窗案例、
升級至 1.2.8 再跑三十一案例、移除／重裝後跑全部三十二案例；設定視窗只在最後狀態啟動一次，
以節省兩次相同 Qt／AT-SPI
啟動成本；dependency、ELF、安裝清單、資料 hash、授權及移除後
不碰個人設定一併通過。這是 T14 的第一段 package lifecycle 證據，不代表真實舊版
升級、GNOME session、完整功能或正式 release package 已驗收。

2026-09-14 的 WSL2 Ubuntu 24.04.4 手動 smoke 已由使用者在 WSLg XWayland／GTK3 gedit
確認套件可經 Fcitx 5.1.7 輸入中文。此環境在關閉 Fcitx X11 候選窗後會留下約一秒
視覺殘影，與 `microsoft/wslg#1495` 的 `UnmapWindow` A/B 診斷相同；文字與 engine state
已先完成，不列成 KeyKey 效能失敗，也不能當成 GNOME/XWayland 視窗通過。T06／T07 的
候選顯示、切換與立即隱藏仍須在真正 Ubuntu Desktop session 驗收。

同日另於 WSL Ubuntu 啟動獨立 GNOME Shell 46／Mutter／TigerVNC X11 `:21`，以
noVNC 本機瀏覽器顯示，使用相同已安裝的 addon。專用 GTK3 欄位先核對每個注音
preedit，再以 XTest 送 `dj941` 與 `Shift+1`，三次精確提交「快樂」；另一流程先送
`d`／Space，再十次以 `d` 提交目前「ㄎ」並開始下一 reading，間隔 Space 重開候選，
精確得到十個「ㄎ」。這 13 次 GTK commit 為 0.72–1.88 ms，觀察到 X11 已隱藏的時間
為 4.27–6.30 ms，每次剩餘 mapped 候選窗為 0。此時間含跨行程與觀測輪詢成本，
不是效能 SLA。第一個關聯選字與最後一個「ㄎ」另擷取候選區域：約 59 ms 時已改畫，
再過 500 ms 像素一致。切到 `keyboard-us` 後相同關聯鍵序精確得到 `dj941!`。
證據留在 `Source/Loaders/Linux-IME/out/manual-vnc/popup-timing-20260914-011529.json`
與同目錄 before／after PNG；本機 web 連結已從 Windows 確認 HTTP 200。這只補上
隔離 GNOME X11 診斷。同日使用者在此瀏覽器桌面確認一秒延遲與多重殘窗解決，
人工試打成功。後續重現及交付步驟固定見
[Ubuntu 手動試打交接](Source/Loaders/Linux-IME/docs/manual-desktop.md)，啟動入口
已置於版控的 `tools/manual-desktop/`。不增加正式 32 案計數，不代表 native Wayland、
完整登入／桌面服務或發布 gate 通過。

Ubuntu 22.04 的兩個對應 `.deb` 亦已在 Fcitx 5.0.14 userspace 建置，並於另一個
不含開發標頭的乾淨 runtime container 完成安裝、檔案／資料 hash、ELF dependency、
移除後無系統殘檔且保留個人設定 sentinel，以及重裝檢查。此列刻意不宣稱已完成
桌面真實打字；Ubuntu 22.04 的 X11／GNOME 路徑仍須另外驗收。

## 1. 什麼才算「真的打出文字」

至少要走過這條路徑：

```text
鍵盤 press/release → 桌面輸入路徑 → IBus / Fcitx 5
  → Linux engine → preedit / candidate / commit
  → GTK / Qt / 瀏覽器的實際文字欄位 → 讀取欄位內容核對
```

不能用呼叫 engine 得到字串、D-Bus 直接 commit、剪貼簿貼上、DOM `.value`／`fill()`、
JavaScript `KeyboardEvent` 或 toolkit `setText()` 取代 E2E。
瀏覽器自動化可讀取結果與做 assertion，但不能直接灌入預期中文字。
QTest／adapter test frontend 的鍵盤合成是否經過 OS IME 不可假設，預設只算整合測試。

測試必須同時檢查：

- 每步按鍵、press/release／修飾鍵、framework active engine 與 client context。
- 組字中文字／注音、候選文字與順序、反白／頁次、顯示／隱藏及焦點。
- 真正 App 文件的精確 Unicode 文字、cursor／selection、commit 次數；
  不能只檢查 engine log 或「畫面看起來有一個字」。
- 停用琦琦、改成英文鍵盤後重送相同鍵序，不應得到同樣中文字。
  負控制若仍成功，表示測試繞過 IME，整條 E2E 無效。

## 2. 五層測試

| 層級 | 驗證內容 | 可用環境 | 不能取代什麼 |
|---|---|---|---|
| L1 engine/data | 狀態機、表格語意、排序、filter、Unicode、設定、資料生成 | 各 distro container／原生 CPU runner，CTest + ASan/UBSan | framework、桌面、安裝 |
| L2 adapter contract | key 處理、commit/preedit、lookup table、properties、reset/focus、雙 context | 獨立 session D-Bus、IBus test client、Fcitx TestFrontend | 真 App 與 OS 鍵盤路徑 |
| L3 installed X11 E2E | 套件安裝後，在 GTK/Qt 編輯器逐鍵組字與選字 | Xvfb + window manager + D-Bus + 框架；XTest/xdotool 送鍵 | native Wayland |
| L4 desktop Wayland E2E | 優先 Ubuntu 24.04 GNOME/Fcitx 5；另測 GNOME/IBus、Plasma/Fcitx；native Wayland／XWayland、popup/focus | hosted runner 內 QEMU 完整 distro guest，優先 KVM | 其他 compositor、實體 GPU／周邊 |
| L5 app/UI/package | 實際應用程式、sandbox、視窗、安裝升級、持久化與版本 | 對應 distro desktop guest；必要項目補實機 | 未測組合的支援保證 |

Fcitx 官方的 [TestFrontend](https://github.com/fcitx/fcitx5/blob/master/testing/testfrontend/testfrontend.cpp)
可供 L2 參考；[IBus engine 原始碼](https://github.com/ibus/ibus/blob/main/src/ibusengine.c)
提供事件／結果契約。兩者都不是已證實的 L4。

## 3. 鍵盤注入、host app 與證據

### X11

使用真實 test host 視窗，在它取得 focus 且 engine 啟用後，以 XTest／xdotool
傳送固定實體鍵序。禁止 `xdotool type 中文`；傳的是注音／字根鍵與選字鍵。
按下與放開的 modifiers 成對，案例結束釋放所有鍵。採輪詢狀態與有界 timeout，
不要依賴固定長 sleep；啟動、焦點或面板未就緒應直接失敗。

### Wayland

P0 首選 QEMU 的 `input-send-event` 或 `send-key`，注入 guest 的虛擬鍵盤，
讓事件經過 guest compositor 與 IME。QMP 管理 socket 只留在 runner 本機，
不暴露網路。[QEMU QMP 文件](https://www.qemu.org/docs/master/interop/qemu-qmp-ref.html)
定義這些 guest 輸入指令；能發出指令不代表實際 IME 已收到，仍須上述正負控制證明。

記錄 `XDG_SESSION_TYPE`、compositor、framework、toolkit backend／plugin、
程式版本與實際啟動參數；確認被測視窗確實用 Wayland，而非偷偷 fallback X11。
native Wayland 與 XWayland 分開報告。`xdotool` 不當成 native Wayland 注入器。
Nested GNOME／KWin 可做較快子集合，完整 guest 為首版 release 優先驗證方式。

### Test hosts

- 建 GTK 3、GTK 4 與 Qt 6 最小原生編輯器：單行、多行、兩欄位、密碼、唯讀、
  selection、caret 移動與視窗縮放。Qt 5 以仍有可安裝套件的目標作相容性案例。
- Host 透過 toolkit 正常 IM context 收字，只讀回 buffer、cursor、selection，
  並記錄收到的 preedit／commit 訊號。診斷介面沒有「設定目標文字」或直接 commit API。
- 外部 App 優先以 AT-SPI／DOM 讀取文字；無法讀取時，在 App 正常「儲存」後比對 UTF-8
  檔案。避免依 OCR 作唯一文字驗證。可讀性不足的案例標 blocked，不降級成截圖成功。
- Engine 詳細事件 log 為測試 build opt-in，正式版預設不記錄輸入內容；只記錄測試字串，
  不收集開發者的真實剪貼簿、檔案或密碼。

### 每個案例的產物

輸出 `result.json`、JUnit XML、逐步 `events.jsonl`、App 實際文字、關鍵狀態截圖；
失敗另加錄影、框架／compositor／guest journal 與 focus tree。
JSON 至少含：test ID、F IDs、git SHA、套件 SHA-256、來源資料 hash、distro、arch、
session、framework、App/version/backend、config、steps、expected、actual、狀態、耗時。
用 `always()` 保存失敗證據，CI artifacts 初始保留 7 天；正式發布保留摘要及 checksum。
完整輸出需可從 workflow summary 找到，不能只留「Test passed」一行。

## 4. Golden fixtures 與具體按鍵案例

固定乾淨使用者設定、US 實體鍵盤、注音 Standard、關聯詞初始關閉，以及字表的
commit hash。Linux 候選學習已排除，不建立相關 fixture；要測關聯詞時才另外開啟。

真實資料錨點已在目前 `.cin` 確認：`bpmf-ext.cin` 的 `5j/` 第一項為「中」；
`cj-ext.cin` 與 `simplex-ext.cin` 的 `a` 前兩項為「日／曰」，`l` 有「中」。
這只證明資料內容，**不是現行 Windows 按鍵流程已實測**；P0 要凍結 Space、候選
數字鍵等時機，再產生不含模糊分支的 golden。

建議 scenario schema：`id / method / layout / config / dataHash / steps[]`，
每步含 `press/release`、待達成狀態、精確 preedit/candidates/selection/page/commit
及 host text。預期值先來自 macOS 行為，再以 Windows 交叉檢查，並搭配人工
核對的資料；不由被測 Linux 引擎
自動生成。小型合成字表只用於邊界單元測試，正式 E2E 必用實際封裝資料。

| ID | 流程 | 必要 assertion |
|---|---|---|
| T01 | 注音依序 `5` → `j` → `/` → Space → 選「中」；候選開啟時直接接下一 reading；reading 中送無效鍵 | reading 為 `ㄓ` → `ㄓㄨ` → `ㄓㄨㄥ`；選字後 App 精確為「中」、preedit 清空、只 commit 一次；下一 reading 先提交反白字；無效一般鍵保留 reading 且不漏入 App |
| T02 | Standard、ETen、ETen26、Hsu、Hanyu Pinyin | 五布局皆先依 macOS、再比對 Windows 行為驗證 reading、聲調鍵立即開候選、連續輸入、錯誤鍵與設定保存；L1 與 installed Fcitx→GTK3 X11 已逐布局驗證裸 `\` 被吃掉並提示錯誤、`Ctrl+C` 交回 App，兩者都不破壞 reading；不能只用 Standard 結果代替 |
| T03 | reading 中 Backspace／Esc；有候選時 Backspace／Esc；空白狀態再按 | macOS 原始碼 golden 先固定，再以 Windows 交叉檢查；L1 與 X11/GTK3 已驗證逐音退格、整段取消、空狀態 pass-through，沒有殘留注音或誤刪 App 已提交文字；GNOME／Wayland 與多 App 仍待驗收 |
| T04 | 倉頡既有垂直切片回歸 | F03 不在 Windows 第一階段基線；現有案例保護既有實作與擴充結構，目前不繼續功能開發、不列 parity blocker |
| T05 | 簡易既有垂直切片回歸 | F04 不在 Windows 第一階段基線；現有案例保護既有實作與擴充結構，目前不繼續功能開發、不列 parity blocker |
| T06 | 打開大於一頁的真實候選；切換直／橫式；方向鍵、Home/End、Space、PageUp/Down、數字、Enter、滑鼠選字 | 前後頁、首尾、末頁及邊界不越界，反白與 commit 同字；目前已驗證 Home／End 跳整份候選首尾、直／橫設定保存、橫式 hint 下真實候選流程，以及 Xvfb/classic-ui 直式候選第二列真實滑鼠點選「鐘」，仍需 GNOME/Wayland 畫面與滑鼠證據 |
| T07 | 開啟分類 → 提交字 → Shift 選關聯詞 → 接續；全部關閉後重打 | host 是原字加「後綴」，不重複前字；順序／去重／分類保存與停用正確，fixture 固定具體詞與來源 |
| T08 | 中文／英文、Shift/CapsLock、全半形、數字、標點、繁轉簡 | 比對精確 code points；L1 全形對映包含 `Ａｚ０９！～　`；X11 已驗證 `Ctrl+\`、300 ms 單按 Shift、長按不切換、Caps Lock、active composition 清除、英文半／全形與停用快捷鍵交回 App；filter 組合順序有測試；不測注音自動修正 |
| T09 | 組字／候選／關聯詞時送 Ctrl/Alt/Super 快捷鍵、repeat、press/release | macOS 原始碼 golden 先固定、再以 Windows 交叉檢查；L1 已覆蓋 Ctrl+C、Alt+F、Super+L、Ctrl+Left、repeat 及 key-up；X11/GTK3 已驗證長按 `Ctrl+\` 只切換一次，Ctrl／Alt 在 reading／候選期間交回 App 且不破壞狀態；Super/compositor、GNOME／Wayland 與多 App 仍待驗收 |
| T10 | 在兩欄位、兩 App 切 focus；有候選時關閉 client；框架重啟／重新登入 | local X11/GTK3 已以同一視窗兩欄驗證第一欄候選失焦後清空 preedit、第二欄獨立提交「文」、切回第一欄不沿用舊候選並提交「中」；另在候選開啟時正常關閉 client、確認 Fcitx/addon 存活，重啟框架後由新 client 再提交「中」，各段含 `keyboard-us` 負控制。仍須補兩個同時存活的真 App、GNOME 登出登入與 native Wayland／XWayland |
| T11 | 移 caret、選一段字後組字／替換、滑鼠移 selection；密碼／唯讀欄位 | 先依 macOS、再比對 Windows；Local X11/GTK3 已驗證 active reading 中的方向、Home／End、PageUp／PageDown、Delete／Tab 與 Shift 變體不移 App caret／selection、不換欄且保留 reading，並以真鍵盤選取既有單字後由注音候選精確替換；password purpose 使 Fcitx 回到 `keyboard-us`，唯讀欄完整鍵序後不變，adapter 對 Password／Sensitive capability 另清除關聯詞。滑鼠 selection、GTK4／Qt／瀏覽器、GNOME／Wayland 仍待驗收 |
| T12 | 設定 UI 切直橫、比例、配色、錯誤提示聲、五布局、內建關聯詞分類；開符號列表點選／取消 | Windows 對標設定即時套用；縮放後 click hit test 一致；關閉／再開及重登入保存；符號送回原欄位且只一次；local X11/classic-ui 已由 `Ctrl+0` 開表並以真實滑鼠點第一列提交「，」，仍需 GNOME/Wayland 畫面、位置與點擊證據；不新增候選學習、注音自動修正或 F12–F15 佔位 UI |
| T14 | 套件安裝→注音註冊→實打字→升級→再打字→移除→重裝 | ELF deps、UI／資料存在、設定保留、無重複註冊或殘留自啟；無自動改預設框架；倉頡／簡易既有註冊不算支援條件 |
| T15 | 密集連打、長候選、延伸漢字／Emoji 資料、locale 切換、兩 context 交錯 | 無 UTF 截斷、死鎖、串字、崩潰與無界記憶體成長；連打結果逐字一致 |

所有未知的精確預期值在 P0 補齊，標 `pending-baseline`，不先寫 always-pass test。
候選學習／動態頻率、注音自動修正、F12–F15 不列 Windows parity 缺口；T04／T05
保留測試但不列第一階段 blocker，原 T13 不納入測試總數。

### T14-SOURCE：configure／make 原始碼安裝（部分實作）

2026-09-13 新增，對應開發計畫第 5.1 節，屬 T14 的安裝子案例，不改動既有
14 個功能測試 ID。各子案例仍須以自己的結果判定，不得由 CMake／Ninja 或 `.deb`
綠燈推定通過。

| 子案例 | 操作 | 驗收條件 |
|---|---|---|
| T14-SOURCE-BUILD | 乾淨 checkout 及無 `.git` 的 source tarball，分別執行 configure、make -j2、make check | 一般使用者可完成；Ninja／Docker 不在必要工具內；相依套件預先安裝後可離線完成；不讀原 checkout 或 cache；支援 source-directory 入口及獨立 build directory |
| T14-SOURCE-CONFIG | --help、缺失相依套件、未知選項、CXX／編譯與連結旗標；預設及自訂 prefix／libdir／datadir | 說明、錯誤碼與目的地摘要正確；明確要求的 adapter 不靜默停用；包含空白的路徑與重新 configure 不造成錯用 cache |
| T14-SOURCE-STAGE | make DESTDIR=暫存目錄 install | 不寫入 host 系統；清單涵蓋 addon／component、資料、UI 與授權；ELF／metadata 不含 staging 或 build 路徑；核對資料 hash |
| T14-SOURCE-INSTALL | 在隔離 guest 安裝同次建置產物，測 /usr/local、/usr 及自訂 prefix | 框架依文件找到正確 addon／engine／資料；已交付的每個 adapter 均跑注音逐鍵輸入、preedit／候選與英文負控制；原始碼安裝結果獨立記錄 |
| T14-SOURCE-LIFECYCLE | 原始碼安裝後升級、解除安裝、重裝；驗證與原生套件切換 | 依 manifest 無系統殘檔，保留設定及無關 sentinel；衝突先回報且不覆寫套件管理器的檔案；重裝後可打字；首版升級 fixture 明確標示 |
| T14-SOURCE-CLEAN | make clean 後重建，再 make distclean 後重新 configure／make／check | 只清除本次生成檔，不刪來源、唯讀資料或使用者檔案；不影響獨立 Ninja build；兩次重建均通過 |

先在 Ubuntu 22.04／24.04 x86_64 實作以上檢查，P4 擴至全部 9 個 active Ubuntu
版本；ARM64 在同架構執行 build／check／staging，沿用 preview 升格規則。
Source install 的 L3 結果不取代主環境 GNOME／native Wayland／XWayland 桌面 gate。
報告另記錄 `buildMethod=configure-make`、來源 SHA、tarball SHA-256、configure 參數、
compiler／Make／CMake 版本、安裝 manifest 與實際框架載入路徑；保留 configure、build、
check、install／uninstall log。

2026-09-13 Ubuntu 24.04 local amd64 container 已通過 checkout 的
source-directory／out-of-source build、同一 commit 的 2.0 MB source tarball 在無
`.git`／無 cache 的解壓目錄重建、2/2 CTest、`/usr` 與含空白的自訂
prefix／libdir／datadir staging、重新 configure、缺失 compiler／未知選項、manifest
卸載、sentinel 保留、clean 後重建及 distclean 隔離；另以預設 `/usr/local` 真安裝、
明示 session 搜尋路徑後載入 Fcitx 5，通過 T01 X11/GTK 3 注音與英文負控制後解除安裝。這是
T14-SOURCE-BUILD／CONFIG／STAGE／CLEAN 與 INSTALL 的局部證據，不涵蓋
`/usr`／任意 prefix 真打字、注音完整案例、升級／重裝或其他 Ubuntu；後者仍待
P4／P5。Ubuntu 22.04／24.04 hosted jobs 已通過同一局部 source gate，但不得因此將整組
T14-SOURCE 標成通過。

## 5. 桌面與應用程式矩陣

測試矩陣以機器可讀的 `ci/support-matrix.json` 管理並生成文件摘要。
欄位至少為 distro、arch、desktop、session、framework、app/backend、suite、
required/preview、一般／歷史維護狀態與對應 image digest。release 用同一份矩陣，
避免漏掉必要功能路徑或中間 OS 版本；相容窗定義見開發計畫第 2 節。

另加 `phase` 與 `priority` 欄位：Ubuntu 24.04 GNOME + Fcitx 5 為 `active/primary`，
其餘 Ubuntu 為 `active/compatibility`；Debian／Fedora 為 `future-todo/future` 且
`required=false`。目前先完成 Ubuntu，後兩家族不建立 required job、不阻擋 Ubuntu 發布。

### 主要環境完整驗收

Ubuntu 24.04 + Fcitx 5 必須具備以下獨立結果，第一階段涵蓋 Windows 對標的
F01–F02、F05–F11 與 F16 設定／語系部分：

1. GNOME X11、GNOME Wayland + native client、GNOME Wayland + XWayland client
   三條路徑；各自安裝正式待驗 `.deb`，核對 Fcitx process 與 addon，記錄 panel
   provider。GNOME 的 IBus protocol bridge 與本專案 IBus engine 必須明確區分。
2. 全部 12 個範圍內 T cases，在 GTK3／GTK4／Qt6 hosts 跑完；模式專屬案例依其
   定義執行，適用性在矩陣明列，不列為 skipped。加 Qt5 client 相容測試。五布局
   注音、一般／關聯選字、標點與 filters 都要有
   中間狀態、精確 App 文字及負控制，按鍵釋放／長按／焦點／selection 亦包含。
3. Firefox、Chromium、Electron editor、LibreOffice Writer、終端機文字編輯各跑
   適用的完整輸入與焦點流程；瀏覽器補單行、多行、contenteditable，以及 native
   Wayland／XWayland。無對應控制項的案例要在 host 中有證據，不用全列 skip 代替。
4. Snap Firefox、Flatpak GTK editor、Flatpak Qt editor，使用真實 confinement
   與受控 runtime，驗證注音、preedit／候選、滑鼠選字、符號回送、切焦點。
5. 設定、符號、關於、語系與鍵盤可及性；直橫候選 × 全部比例 × 配色的完整
   組合 sweep，含四邊游標、字型裁切、hit test、虛擬混合 DPI。自訂色用固定
   代表值驗證保存與呈現，避免把無限色值當成可窮舉矩陣。
6. 乾淨安裝、注音加入／切換、重新登入、Fcitx 重啟、升級、移除與重裝，
   設定保留；客戶端意外關閉、密集連打、長時間重複切換與恢復。
7. 每項保留 App 文字、event trace、截圖與失敗錄影；整合問題優先在此環境重現。
   PR 跑完整 typing suite 與所有功能的 UI 操作；手動完整測試／發布跑上述所有 App、
   sandbox、視覺組合與壓力項目。主環境結果不得因其他平台成功而被覆蓋。

若 Wayland panel 需額外 Shell 整合，先依開發計畫 P0 決議固定支援的組合及依賴，
再將之列為 required。主要環境有必測未完成時阻擋正式發布。

### Active Ubuntu x86_64 桌面列（每列都要測注音）

| 環境 | 最低 native host | 附加路徑 |
|---|---|---|
| **Ubuntu 24.04 GNOME / Fcitx 5（主要）** | GTK3、GTK4、Qt6、Qt5；X11／native Wayland／XWayland 分開 | 完整驗收清單；所有 App／sandbox／UI／安裝與穩定性 |
| Ubuntu 22.04 GNOME / IBus | GTK3、GTK4、Qt6.2；Wayland 與 X11 分開 | 最低依賴／API 基線、XWayland host |
| Ubuntu 24.04 GNOME / IBus（次要相容） | GTK3、GTK4、Qt6；Wayland 與 X11 分開 | Wayland session 中的 XWayland host |
| Ubuntu 26.04 GNOME / IBus | GTK3、GTK4、Qt6；Wayland | XWayland host |
| Ubuntu 22.10、23.04、23.10、24.10、25.04、25.10（各自一列） | 該版 GTK3、GTK4、Qt6；GNOME Wayland / IBus | 歷史 guest、XWayland host、安裝後打字 |

上表 active 範圍共 9 個 Ubuntu 版本，表格合併顯示不表示合併測試。每個版本另跑
IBus 與 Fcitx 的 installed X11 slice；以 Xvfb／可用的輕量 WM 驗證兩 adapter 真正
被目標套件載入。最舊、最新通過不替代中間 7 版的結果。歷史列與一般列同樣要求
注音和功能測試；差別是來源快照、網路隔離與平日頻率。

### Future TODO：Debian／Fedora

- Debian 12／13：Plasma Wayland + Fcitx 5、Xfce X11 + Fcitx 5，再補兩 adapter 的
  installed X11 slice 與 Flatpak GTK／Qt editor。
- Fedora 36–44：GNOME Wayland + IBus，44 另加 Plasma Wayland + Fcitx 5；每版需
  自己建 RPM，不能重包 Ubuntu ELF。
- 這 11 列保留在 `support-matrix.json`，但 Ubuntu 驗收完成前不排進 PR、手動完整測試
  或 release required jobs；開始 P6 時再依當時日期重算四年範圍與套件來源。

若目標 distro 不提供某 toolkit，必須更新矩陣理由與替代 App，不任意下載來源不明的
runtime。不同 toolkit/backend 的 preedit 呈現差異可記錄，但文字結果不放寬。

### 代表性真實 App

- 所有正式桌面列：至少一個發行版原生 GUI editor，以及 Firefox 的單行、多行、
  contenteditable。原生測試 hosts 跑完整 T01–T03、T06–T12、T14–T15；一般 App 最少
  T01、T02、T06、T07、T08、T10、T11。T04／T05 保留在回歸批次但不列發布缺口。
- Ubuntu 22.04／26.04 GNOME：加 Chromium、Electron editor、
  LibreOffice Writer、終端機內一般文字編輯；Qt 5 相容性視可安裝性補上。
  瀏覽器／Electron 在 native Wayland 與 XWayland 各跑一次，記錄真實 backend。
- Ubuntu 24.04 GNOME + Fcitx 5 依上節完整驗收，涵蓋所有上述 App、Snap 與
  Flatpak，不能因本節把它省寫在代表列中而少跑。
- Ubuntu 22.04／24.04／26.04 LTS：Snap Firefox（完整 snapd/systemd guest，驗證 confinement 未被關閉）。
  Debian／Fedora 的 Flatpak 組合留在上述 future TODO。
  固定 app/runtime revision，確認 sandbox 內外 IM module／D-Bus 路徑。
  普通 container 裝套件的測試不能冒充 Snap 桌面相容性。
- 其他 App／交叉框架組合列 compatibility，不以一次成功推論所有 Linux App 都支援。

EOL 列使用當年可執行的 App/runtime 快照和 localhost 測試頁，不硬裝要求新版
glibc 的最新瀏覽器。軟體來源不可得時保留缺口／阻擋相容宣告，不把「只有舊 App」
說成支援所有現在的 App，也不把歷史系統相容說成仍有上游安全更新。

### ARM64 升格

完整版本矩陣的 aarch64 build／L1／package install 至少在同架構 runner/container 執行；
不要把 x86 的結果掛到 ARM64。先標 preview；某個 ARM64 distro 要升格，需在
其同架構 guest／受控裝置重跑對應正式桌面列、兩 adapter contract 與套件升級。
QEMU 跨架構可補 smoke，但需明確標記 emulation，不能當成實體效能驗證。

## 6. 視窗與持久化驗收

- 畫面比例至少 system、75%、100%、200%、225%、350%；所有設定值在 L1 驗證，
  完整視覺 sweep 放手動完整測試與 release。測候選在四邊、長字、最後一頁、視窗移動、最大化、
  虛擬雙螢幕不同 scaling、符號面板開啟時換 App。
- 預設／自訂色與 light/dark、繁中／簡中／英文，驗證文字未裁切、按鍵角標與頁碼
  可讀、按鈕可及性角色與名稱、Tab 順序。截圖 diff 固定字型與環境並設定合理容差；
  文字提交 assertion 不使用模糊容差。畫面 baseline 更新須人工 review，不能自動批准。
- 特別測 Wayland popup 定位與不搶焦點；自訂 window 無法被 compositor 正確定位時
  應失敗／列明限制，不能只把字型縮小到看得見就算通過。
- 真實多螢幕熱插拔、實體鍵盤、Orca 朗讀等另列人工 smoke。報告區分
  `automated-virtual`／`manual-physical`，未做的標未測，不換算成自動化百分比。
- 設定跨 engine restart／session restart／套件升級保存；schema 舊版、檔案損毀、
  遷移途中失敗均可恢復且不覆寫原檔。Linux 不建立或驗證候選學習資料。

## 7. CI 速度、安全與發布門檻

### 執行分配

- PR／主分支 push：Ubuntu 24.04 + Fcitx 5 設 required job，三條 session 路徑
  各跑 T01–T03、T06–T12、T14–T15，包含注音、所有功能 UI 操作與套件生命週期；
  T04／T05 只屬既有切片回歸，不是發布支援條件。
  可分片並行；主環境不能只有最小 Wayland 四案例或放進輪替。
- PR：L1 全部，兩 adapter L2；Ubuntu 22.04／26.04 最舊／最新邊界 build，並在
  Ubuntu 22.04 跑兩 adapter installed X11 slices；P0 通過後加 Ubuntu 舊／新 GNOME
  的最小 Wayland T01/T10。Debian／Fedora 不排入目前 required jobs。
- 手動完整：`linux-desktop-tests.yml` 只接受 `workflow_dispatch`，不設 `schedule`／`cron`。
  預設完整驗收 Ubuntu 24.04 + Fcitx 5；手動選擇完整矩陣時重跑 9 個 Ubuntu 版本，
  也可只指定受影響的歷史版本。歷史環境不能永遠只留首次成功結果；PR 更動
  compat／最低依賴時加跑受影響歷史列。
- Release：同 SHA／同一批待發布套件重跑 9 個 Ubuntu 版本完整矩陣及 package lifecycle，
  不只依賴 PR quick suite。首版無舊 Linux release 時，以受控舊 schema／套件 fixture
  做遷移測試並註明；第二版起必測真實前版 → 新版。
- P0 每條桌面路徑至少連續三次全新 session 成功並通過負控制，再納入 required。
  失敗重試保留首次結果；不能把 flaky 測試無限重跑到綠。穩定性數據形成後調整
  timeout／切片，先不承諾所有 workflow 幾分鐘內完成。
- configure／make 入口實作後：相關 PR 在既有 Ubuntu 22.04／24.04 CI 執行
  T14-SOURCE 的 build、配置錯誤、staging、clean 及 installed X11 檢查；手動完整與
  release 跑全部 active Ubuntu 的原始碼安裝生命週期。release 必須使用將發布的
  同 SHA source tarball，解壓後獨立離線重建，再安裝該批產物驗證，不能改用 `.deb`。

### 工具與套件檢查

規劃採用 CTest、ASan/UBSan、clang-tidy、ShellCheck、actionlint、lintian、rpmlint；
只掃 Linux 與相關新檔，避免舊 `ExternalLibraries/UnitTest++/UnitTest++` 循環 symlink。
Sanitizers 先在相容 host 跑，其他目標至少執行正常 tests；未跑 sanitizer 要單列。
所有 package 以乾淨環境驗證 architecture、dependency resolution、data hash、
desktop metadata／XML、license、無缺少 `.so`、無 repo/build 絕對路徑洩漏。
加上最低 glibc／GLIBCXX symbol version 與 framework API 檢查，防止新 runner
編出的 binary 意外要求較新系統。container 只能驗證 userspace，舊 kernel／桌面
相容用對應 guest；不要把 host 的新桌面當成舊 distro 桌面。

VM runner 僅使用隔離測試帳號與固定測試字串；不在 PR 開金鑰／簽章／release token。
Guest image 來源、checksum、安裝套件版本與安裝腳本全部可審計；cache 不保存個人
資料或具寫入權限的永久登入環境。Runner 初始化不清除 repo 外的任意資料夾。

### Release 必須全部滿足

- [ ] Ubuntu 24.04 + Fcitx 5 的主要環境完整驗收全綠；三種 session 路徑、注音、
      所有核定功能／App／sandbox／UI／套件生命週期與穩定性皆有證據。
- [ ] 注音、兩 adapter、active Ubuntu／桌面列皆有結果，必測案例無 skip。
- [ ] Debian／Fedora 的 11 列維持 future TODO；開始 P6 後才逐列加入對應驗收與 gate。
- [ ] active Ubuntu 近四年每個版本（含歷史列）有 installed-package 真打字證據，最低依賴未被
      無意提高；一般／EOL 相容標示與實際 OS 安全維護狀態分開。
- [ ] App 精確文字與中間輸入流程通過，且正／負控制都符合預期。
- [ ] 待發布套件本身通過乾淨安裝與打字，不用 build tree 取代 installed artifact。
- [ ] 同 SHA 的待發布 source tarball 通過 T14-SOURCE 全部子案例與 active Ubuntu
      原始碼安裝後的真打字；configure／make 介面、相依套件及安裝／移除文件齊全。
- [ ] F01–F02、F05–F11 與 F16 的 Windows 對應部分有證據或經使用者接受的具體差異；
      五布局與設定均列必要。候選學習／動態頻率、注音自動修正、F12–F15 不計為
      Windows parity 缺口；既有 T04／T05 與註冊保留作額外功能回歸。
- [ ] 原生 Wayland／XWayland、ARM64 preview／正式、虛擬／實體結果清楚分開。
- [ ] Workflow summary 可追溯 SHA、套件、環境、逐案例結果、截圖與失敗記錄。
- [ ] 新套件未變更使用者預設框架，升級保留個人資料，授權與 checksum 齊全。

若 hosted desktop gate 失敗，保留已完成的 L1–L3，記錄 blocker 並回報；
不得把 L4 名稱改成 smoke、隱藏 failed job，再把同一版本標為全平台正式支援。
