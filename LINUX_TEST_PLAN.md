# Linux 自動化打字與發布驗收計畫

狀態：測試實作中。已有 CTest real-data typing-flow、Ubuntu 22.04／24.04
container build/staged-install checks、Ubuntu 22.04／24.04 Debian package checks，
以及 Ubuntu 24.04 Fcitx 5 → GTK 3／GTK 4／Qt 6 各自適用的第一階段 L3 X11
完整真實逐鍵矩陣；隔離 GNOME X11 session 另已通過 76 個不重啟桌面 Fcitx 的
desktop-safe 案例。2026-09-20 已在 Ubuntu 24.04.5 GNOME Wayland KVM guest
通過 20 案 × 八條 native Wayland／XWayland 的打字與滑鼠矩陣（160/160），另以 gedit 和 GNOME
Text Editor 驗證真實文件欄位；Firefox Snap／Epiphany 的五條瀏覽器路徑
與三種欄位亦已通過真實 DOM 事件 15/15。更多 sandbox／App／視窗 suite
仍待實作。
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

2026-09-20 本機 WSL2/KVM 中以官方 SHA-256 驗證的 Ubuntu 24.04.5 amd64 映像
建立完整 GDM／GNOME Shell 46 Wayland login，實裝
`fcitx5-chichi77-keykey`／`chichi77-keykey-data` 1.2.8-1+ubuntu24.04；
Fcitx 5.1.7 行程 maps 確認 KeyKey addon、Wayland 與 IBus frontend。
QMP 的 VM 鍵盤事件經 GTK3、GTK4、Qt6 原生 Wayland 欄位各自提交「中」，
三段 preedit 為「ㄓ／ㄓㄨ／ㄓㄨㄥ」，改用 `keyboard-us` 後同鍵序精確提交
`5j/ 1`；GTK3／GTK4 另各以未設 `GTK_IM_MODULE` 的預設 Wayland IM 路徑
通過相同案例，合計 5/5。事件 trace 在 guest 的 `/tmp/keykey-wayland-smoke-*`；
入口與重建流程見 [VM 手冊](Source/Loaders/Linux-IME/docs/gnome-wayland-vm.md)。
一次 GTK3 直式候選的 QMP 截圖顯示完整九列候選窗緊鄰欄位下方；同時出現
Fcitx「Wayland Diagnose」建議安裝 GNOME Shell Input Method Panel 的通知。
畫面保存在忽略版控的 `out/gnome-vm/wayland-popup-before.png` 與
`wayland-popup-candidate.png`，只算單一虛擬解析度的目視樣本。
guest 經 QEMU ACPI 停止並重新 KVM 啟動後，SSH、GNOME Wayland、Fcitx addon
自動恢復；五個 T01 smoke 再次 5/5 通過。這驗證 VM 重啟，不代替使用者登出／再登入。
此後的 VM runner 擴為 20 個案例 × 8 種 GTK3／GTK4／Qt6 native Wayland／XWayland
模式，逐案核對 preedit、App 文字與 `keyboard-us` literal 負控制；涵蓋五布局、
T03 編輯取消、T06 直／橫鍵盤候選與真滑鼠點第二列、T07 關聯詞、T08 模式／全形／
繁轉簡、T09 Ctrl 快捷鍵及 T12 符號表。滑鼠案例另用 QMP 截圖比對候選顯示與
點選後約半秒的畫面清除；8 條路徑的第二列皆選出「鐘」，候選顯示與點選後
畫面的差異大於候選出現時的 60%。背景 App 的提示框亦可能改變像素，
故保留前／中／後截圖供檢查。真實 gedit 四條 native／XWayland 路徑都通過
「中」與英文 literal 負控制；GNOME Text Editor 的直接 Fcitx native Wayland 與
XWayland 通過，未設 `GTK_IM_MODULE` 與明設 `wayland` 兩條則在文件已聚焦並接受
普通按鍵時，`fcitx5-remote` 仍回報沒有 active input context。這是尚未關閉的
GTK4 真實 App 缺口。GDM 重啟後新 Wayland session 的 T01 與 T06 滑鼠案例 16/16
通過；後續另已明確登出／登入再跑 16/16。瀏覽器首段、兩個同時存活 App
與 client／Fcitx recovery 的實測見下文；popup 四邊與多螢幕的新增實測
及未解缺口見下一段，其他瀏覽器互動／其他 sandbox、長時間穩定性及
hosted runner 仍未驗證。

2026-09-20 另在同一 GNOME Wayland guest 為 QEMU 加第二 virtio output，
以 Mutter DisplayConfig 實切 1280×800 主螢幕加 1024×768／100% 或
1920×1080／200% 副螢幕，QMP 個別擷取兩個 head。官方 Input Method Panel
GNOME Shell extension (`kimpanel@kde.org` v83) 在專用 guest 啟用後，
`gnome-vm-popup-smoke.py --mouse` 的八模式 × 四角 32/32 通過九列候選
不裁切、欄位避讓、第二列滑鼠提交「鐘」、點後清除及英文 literal 控制。
在 extension 未安裝時，GTK3／GTK4 native Wayland 的右緣候選裁切，
Qt6 候選蓋住欄位；extension 仍未納入產品套件。
雙螢幕 runner 的 16 組均在副螢幕提交「中」與英文 literal，
候選定位 10/16 通過（100% 6/8、200% 4/8）；
但 200% 副螢幕的 GTK3／GTK4 direct Wayland 直接移窗後候選可能還留
主螢幕；GTK3 額外移窗後曾蓋住欄位。另由截圖發現 GTK3／GTK4
XWayland 直接跨螢幕移窗後候選仍留主螢幕，額外移窗後可停在舊
cursor rectangle，
已補入 caret 距離斷言。這些為尚未關閉的視覺驗收缺口，不能將
「有提交文字」等同多螢幕定位通過。完整結果及重建方式見 VM 手冊。
其中一個 200% GTK3 direct Wayland 失敗案另以篩選 D-Bus trace 驗證：
GTK frontend 已送新 `SetCursorRectV2` 且 Fcitx 已轉送相同的
`SetRelativeSpotRectV2`，候選仍在主螢幕右緣；不能歸因於 KeyKey 沒有
更新候選內容，也尚未證明確切座標換算出錯的元件。
同日停用 Kimpanel v83 後由 Classic UI 重跑 16 案，定位僅 6/16；
新 `--panel` guard 會把實際 provider 記入報告，`--mouse` 可透過 QMP
在副螢幕真點第二列。Classic UI 的混合 DPI GTK3 direct Wayland 單案
已以「鐘」提交及候選清除通過，並不代表整體方案通過。
Kimpanel 逐事件紀錄另確認舊 scale=1 caret 矩形先用於候選顯示，
新 scale=2 矩形到達時候選已隱藏；後續應同時修事件時序及定位。
固定官方 Kimpanel v83 來源 hash 的 GPL-2.0 補丁已修正 VM 所見的
relative 縮放與同焦點視窗 XWayland absolute rect 移位：由乾淨補丁
產物重跑，兩種副螢幕布局 × 八條路徑的真滑鼠第二列「鐘」、候選清除與
英文負控制 16/16；單螢幕四角 32/32 回歸亦通過。Qt6 200% 案
原先把白色 App 上方的白色候選幾列漏算，runner 已以較低像素差補足
popup 頂界後真點第二列，不再誤點第四列。這是 GNOME Shell 46 VM
證據，尚非實體雙螢幕、Ubuntu 22.04 或正式套件發布證據。

同一 guest 的 T10 雙欄焦點 runner 又完成 8 模式 × 正負控制 16/16：第一欄有
active 候選時以 VM 指標切第二欄，第二欄精確提交「文」，切回第一欄再提交「中」；
`keyboard-us` 兩欄 literal 為 `5j/ 1|jp61`。六條直接 Fcitx native Wayland／
XWayland 路徑在失焦時由 client 提交原始 preedit，最後第一欄為「ㄓㄨㄥ中」；
未設 `GTK_IM_MODULE` 的 GTK3／GTK4 原生 Wayland 路徑則清空 preedit，第一欄
為「中」。這只證明兩欄隔離及可重現的路徑差異；與既有 X11 T10 的 focus-out
語意不同，正式 parity 決策仍待完成。兩個同時存活 App、client/Fcitx
recovery 與明確登出登入的後續結果見下文。

T11 真實編輯欄位另以八模式各跑選取替換、`keyboard-us` 負控制及 active-reading
編輯鍵：VM 指標先清除初始全選，再拖曳精確得到 `1:2`，候選把「甲乙丙」改為
「甲中丙」；後續送 Home／End、PageUp／PageDown、方向、Delete／Tab 與 Shift
變體，仍在原欄得到「甲中中丙」。密碼欄只產生 `rup 1!`、沒有 preedit，唯讀欄
保持「唯讀」。乾淨輸出第一次完成 21/24；GNOME Shell 46 在最後 Qt6 XWayland
host 啟動時 signal 11 崩潰，重建圖形 session 後同三階段 3/3 通過。
T12 符號表再以真 VM 指標點第一列，八路徑 8/8 提交「，」，英文負控制為 `!`。
這些是實際 App buffer 與 Fcitx addon 載入的證據，尚未覆蓋所有視窗位置。

T10 兩個同時存活 App 的 runner 量到另一項路徑差異：六條直接 Fcitx
native Wayland／XWayland 路徑正負控制 12/12 通過，App A 先切英文全形、
App B 仍獨立提交「文」，回到 A 得到 `ａｂ中|文`；兩條 GTK 未設
`GTK_IM_MODULE` 的原生 Wayland bridge 負控制 2/2 通過，正向 0/2。
乾淨 Fcitx 行程下兩者的 App B 都繼承 A 的英文全形並輸出 `ｊｐ６１`；
`Controller1.DebugInfo` 同時顯示 GNOME Wayland 群組只有一個 `frontend:ibus`
input context、沒有 program 名稱。bridge 無法以目前 context 身分區分兩 App，
此差異仍是發布驗收缺口；直接 Fcitx 的結果不可外推到預設 GTK bridge。
真實 gedit／GNOME Text Editor 同時存活的 Alt+Tab 測試補上 App 層證據：
直接 Fcitx 的 native Wayland 與 XWayland 各通過一案，gedit 失焦提交
原始「ㄓㄨㄥ」，Text Editor 接著提交「文」，回切 gedit 仍提交「中」，
兩者英文負控制皆通過；兩個真實 gedit 視窗走 GNOME bridge 時亦通過
中文與負控制，但失焦會清除 preedit。這不修復 Text Editor bridge
沒有 active context 的缺口。

同一 guest 的 T10 client recovery runner 在八路徑都先截到真正候選 popup，
候選中關閉 client 後 Fcitx/addon PID 保持不變，新 client 的 T01「中」與
`keyboard-us` 負控制 8/8 通過；再由使用者 session 建立新的 Fcitx 行程，
D-Bus owner `:1.801`→`:1.824`、PID `551961`→`553445`，八路徑新 client
再 8/8 通過。這驗證 client 關閉與框架重啟。
之後再從 GNOME session 主動登出，經 GDM 帳戶／密碼畫面用 VM 鍵盤登入，
新 Wayland session ID `7085`→`8481`，新 Fcitx PID `559719`；
測試帳戶恢復原本 password lock。登入後 T01「中」與 T06 第二列真滑鼠「鐘」
各八路徑共 16/16 通過。這仍是登入後的功能抽樣，不代替長時間穩定性或完整
App／popup sweep。

瀏覽器的本機 HTTP fixture 在真正 `<textarea>`、單行 `<input>` 與
`contenteditable` 記錄 DOM focus／input，不直接灌入中文字。2026-09-20
合併跑過 Firefox Snap native Wayland 的直接 Fcitx／GNOME bridge、
Epiphany native Wayland 的直接／bridge 與 Epiphany XWayland，
五條路徑 × 三種欄位 15/15 都以 VM 鍵盤輸入「中」，再切 `keyboard-us`
精確輸出 `5j/ 1`；
Firefox 候選窗另有真實畫面截圖。Snap Firefox 在這台 VM 強制 XWayland
時回報 `cannot open display: :0`，故 XWayland 以發行版 Epiphany 驗證，
不能外推為 Firefox Snap XWayland 已過。更多瀏覽器操作及 sandbox
組合仍需補齊；執行入口與證據位置見 VM 手冊。

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

另有八十三筆可重現的最小 L3 X11 證據：在 Ubuntu 24.04 x86_64 container 以獨立 D-Bus、
Xvfb、Fcitx 5.1.7 與真 GTK 3 Entry、GTK 4 `GtkText`、Qt 6 Widgets，T01 都以
Standard `5j/` 選「中」，精確核對三段 preedit、提交與 `keyboard-us` literal
`5j/ 1`；T02 則在三套 toolkit 都以
Standard、ETen、ETen26、Hsu、Hanyu Pinyin 五種配置逐鍵輸入二、三、
四、輕聲的「麻馬罵嘛」，固定 ETen26／Hsu 複用鍵的消歧中間態，漢語拼音
另驗證不完整 `zh` 依序退格為 `z` 與空 preedit；五種配置都由聲調鍵立即開啟候選，
不再多按 Space，且每種配置都在第一個 reading 中送裸 `\` 與 `Ctrl+C`，確認無效鍵
不漏入 App、快捷鍵交回 App 並保留 reading，之後仍選出「麻」。T01 另以 `5j/` 開候選後直接輸入
下一 reading `jp6`，精確提交「中文」，並在 `ㄓ` reading 中送 `=`／`Ctrl+C` 後繼續
提交「中」，確認無效一般鍵不漏入 App、快捷鍵不破壞組字；T03 另驗證空狀態
Backspace 交回 GTK 刪除 App 文字、reading 中 Backspace
逐音退回、reading Escape 全部清除、候選中 Backspace 關窗並只退最後一音，以及候選
Escape 清除後可重新組字；GTK3、GTK4 與 Qt6 皆以相同鍵序完成，整段只提交
「中文麻」，沒有殘留 reading 或誤刪已提交文字；
倉頡 `a` 選第一候選「日」，另以直接標點、五碼查無結果清除及單一候選提交精確得到「，用」，再以
`a?`／`a*` 的一碼／零碼以上萬用字元精確得到「昌日」；簡易
`a` 選第二候選「曰」，另以兩碼自動開候選、下一碼提交反白候選並開始新組字、
單一候選自動提交及直接標點候選精確得到「明銖䍤、」；
另以注音 `5j/` 開啟 148 個真實候選，三套 toolkit 都送 End、Home、PageDown、Down、
Enter 選出「妐」，也都等待直式 Fcitx 候選窗完成展開後，以 XTest 真實滑鼠點擊第二列
並選出「鐘」，同時避開候選窗剛 map 時的 1×1 與僅 preedit 大小；GTK4 與 Qt6 再切成橫式，
依 Windows 對標語意送 End、Home、PageDown、PageUp、Right、Left、Space、Down、Enter，
確認方向樣式只改畫面、不改直式鍵盤角色，最後仍選出「妐」；
`Shift+Space`、`Shift+A`、`Shift+1`、`Shift+\``、Space 提交精確全形 `Ａ！～　`，
`keyboard-us` 負控制為 ` A!~ `；T08 在三套 toolkit 都以 `Ctrl+\` 與 300 ms 內的
單按 Shift 切換，覆蓋有 reading 時轉英文的清除、Caps Lock、英文全／半形、
長按 Shift 不切換、切回中文、全形 `Ａ！～　` 與繁轉簡 `台湾`；第二案關閉
`Ctrl+\` 選項後驗證快捷鍵交回 client 且 KeyKey 狀態仍是中文。active preedit 被
client 接收後，GTK3 依序得到 `ㄓ翁`，GTK4 `GtkText` 則因後續 commit 插在其前而得到
`翁ㄓ`，Qt6 另固定自己的 client 插入順序，不由 addon 統一這項 toolkit 行為；T09
在 GTK3 與 GTK4 長按 `Ctrl+\` 一秒，Qt6 則驗證一次完整 press/release 切換，
驗證只切換一次，切回中文後
先以兩邊相同的 `Ctrl+A`／Backspace 清除 X11 repeat 時序可能留下的裸反斜線，再於
reading 與候選期間送 Ctrl+C／Alt+F，仍精確提交 `x中文`，`keyboard-us` 負控制為
`x5j/ 1jp61`；Qt6 會把交回 App 的 `Alt+F` 文字 `f` 寫入欄位，故使用對應的
`xff中f文`／`x5fj/ f1jp6f1` golden；T10 在三套 toolkit 的第一欄候選開啟時，依各自 host 回報的 widget geometry 以真實
滑鼠點擊第二欄，再以 Shift+Tab 切回，依序核對兩欄
preedit 清除及獨立提交「中／文」，候選開啟時關閉 client 後確認 Fcitx/addon 存活，
重啟 Fcitx 再由新 client 選出「中」，同樣含 literal 負控制；另一 T10 流程在三套 toolkit
各自保持兩個 App process 同時存活，在空 composition 跨 App 切焦點，確認 App A 的英文全形狀態與
App B 的預設中文半形狀態彼此隔離，精確得到 `ａｂ中|文`，負控制為
`ab5j/ 1|jp61`；T11 先依 macOS、再比對
Windows，以 XTest 指標拖曳選取既有「乙」並由候選替換為「中」，精確觀測 selection
`1:2` 與中間結果「甲中丙」；接著於 active reading 中送方向、Home／End、Delete／Tab
與 Shift 變體，確認不移 App caret／selection 或換欄並原位提交，最終精確為
「甲中中丙」。三套 toolkit 都完成相同 selection／替換／active-reading 編輯邊界；GTK3
密碼 content purpose 使 Fcitx 自動切回 `keyboard-us` 且拒絕強制選回自訂輸入法，
Qt6 則保留 engine 名稱但同樣無 preedit、只產生 literal `rup 1!`。Qt6 的唯讀多行欄
透過標準 `Qt::ImEnabled=false` query 發布狀態，完整注音鍵序交回 widget 且內容保持
「唯讀」，不需 KeyKey addon 特例；Big-5
限制開啟時輸入
Standard `,4`，從過濾後的
`ㄝˋ` 候選選出 `𤦩`，英文負控制為 `,42`；另以 `Ctrl+0` 開啟真實標點／符號候選並按
`1` 提交「，」，第二案則以 XTest 點擊第一列後接 `!`，精確得到「，!」；兩者的英文
負控制分別只得到 `1` 與 `!`；繁轉簡原生設定開啟後，
以 `w96`、`j0` 分別組成 `ㄊㄞˊ`、`ㄨㄢ`，選原候選「臺灣」並提交「台湾」，
英文負控制為 `w962j0 1`；GTK3 的六個 T07 流程以實體 `Shift+1` 分別驗證預設基本詞庫
得到「今天」、只開 history 分類得到「臺灣史」、全部關閉時得到「臺!」，並驗證
舊逗號格式 migration 後仍得到「中程計畫」；第五案經 Fcitx D-Bus 設定 API 寫入、
核對 INI、重啟 process、讀回設定，
再以實際按鍵得到「中程計畫」；GTK4 與 Qt6 各以五案重跑上述預設、分類、停用、舊設定遷移
與 D-Bus 保存／重啟流程，精確得到相同文字及 literal 負控制；GTK3 第六案以 AT-SPI
定位已安裝 `fcitx5-config-qt` 的
輸入法列及核取方塊，實際點選只開 agriculture-food、保存、核對 INI、重啟並讀回後，
並關閉、保存及讀回輸入錯誤提示聲與 `Ctrl+\` 切換選項，將候選樣式從直式改為橫式；
以 `yji4` 選「作」再按 `Shift+1` 得到「作物育種」，同時保存切換前後 PNG。
既有五種注音回歸皆依發生順序核對 preedit；Fcitx D-Bus schema 目前亦確認
`BopomofoLayout` 下拉選項含 Standard、ETen、ETen26、Hsu、HanyuPinyin，候選樣式含
Vertical、Horizontal，並包含繁轉簡、
所有 Unicode 字元、輸入錯誤提示聲、`Ctrl+\` 切換與 30 個關聯詞 Boolean 選項。
錯誤鍵案例會走過
libcanberra 的 XDG `bell-window-system` 呼叫，但 Xvfb container 沒有音訊 session，
實際可聽結果須留給 GNOME 桌面驗收。所有案例皆核對實際 toolkit buffer，且
`/proc` maps 證明執行中的 Fcitx 載入 `chichi77-keykey.so`；每案切回
`keyboard-us` 重送同鍵序的負控制也通過。這些仍是 Xvfb 功能切片，尚未驗證
GNOME、native Wayland、XWayland、瀏覽器或候選視窗畫面。
Hosted Linux workflow run `34742072894` 已在 `d83091d` 通過 Ubuntu 22.04／24.04
兩個 job；後續每個待交付 SHA 仍需用自己的 run 當證據。

Ubuntu 24.04 的目前 slice 也已用 debhelper 拆成架構無關的
`chichi77-keykey-data_1.2.8-1+ubuntu24.04_all.deb` 與 amd64 的
`fcitx5-chichi77-keykey_1.2.8-1+ubuntu24.04_amd64.deb`。乾淨 runtime container
最近一次 package gate 依序安裝受控 `1.2.8~preview1` fixture 並通過八十二個非設定視窗案例、
升級至 1.2.8 再通過八十二案例、移除／重裝後通過全部八十三案例；設定視窗只在最後狀態啟動一次，
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
已置於版控的 `tools/manual-desktop/`。不增加正式 83 案計數，不代表 native Wayland、
完整登入／桌面服務或發布 gate 通過。

2026-09-16 新增可重現的 existing-session GNOME X11 runner，沿用版控內的
`tools/manual-desktop/start-desktop.sh`，並以 PID 與 `xdotool search --all` 排除同名
Mutter 外框。系統安裝的 `fcitx5-chichi77-keykey` 1.2.8、Fcitx 5.1.7、Classic UI，
配合 GTK 3、GTK 4、Qt 6 hosts 跑過 76/76 desktop-safe 案例；涵蓋五布局、候選鍵盤／
滑鼠、關聯詞、模式、兩 App、編輯／敏感／唯讀欄與符號表，每案都有 exact toolkit
buffer 與 `keyboard-us` 負控制。runner 保留承載桌面的 Fcitx PID，測後還原設定與
active engine，並記錄 addon／host SHA-256。三個 D-Bus process-restart persistence、
一個設定視窗 persistence 及三個內含 Fcitx restart 的 input-context recovery 案仍由
managed Xvfb／package gate 負責，不能把 76/76 寫成完整 83 案 GNOME 通過；完整登入、
畫面 sweep、音訊、真實外部 App、XWayland 與 native Wayland 也仍待驗收。本機 Qt 6
runtime 使用 Ubuntu 24.04 官方套件 payload 解壓到忽略版控的 `out/`，release gate
仍需正常安裝套件。

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

2026-09-20 WSL2 Ubuntu 24.04 主機已可讓一般使用者透過 KVM 12 啟動
QEMU 8.2.2 空機，並具備 OVMF；這是建立完整 guest 的前置條件，尚未取得
GNOME Wayland、XWayland 或虛擬鍵盤注入的驗收結果。受限行程可能用
`nodev` `/dev` 隱藏 `/dev/kvm`，判定前須在正常 WSL 行程重查。
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
| T01 | 注音依序 `5` → `j` → `/` → Space → 選「中」；候選開啟時直接接下一 reading；reading 中送無效鍵 | reading 為 `ㄓ` → `ㄓㄨ` → `ㄓㄨㄥ`；選字後 App 精確為「中」、preedit 清空、只 commit 一次；下一 reading 先提交反白字；無效一般鍵保留 reading 且不漏入 App。installed X11 已以 GTK3、GTK4 `GtkText` 與 Qt6 Widgets 跑適用流程及負控制 |
| T02 | Standard、ETen、ETen26、Hsu、Hanyu Pinyin | 五布局皆先依 macOS、再比對 Windows 行為驗證 reading、聲調鍵立即開候選、連續輸入、錯誤鍵與設定保存；L1 及 installed Fcitx→GTK3／GTK4／Qt6 X11 已逐布局驗證四聲／輕聲、裸 `\` 被吃掉並提示錯誤、`Ctrl+C` 交回 App，兩種事件都不破壞 reading；不能只用 Standard 結果代替 |
| T03 | reading 中 Backspace／Esc；有候選時 Backspace／Esc；空白狀態再按 | macOS 原始碼 golden 先固定，再以 Windows 交叉檢查；L1 與 X11/GTK3／GTK4／Qt6 已驗證逐音退格、整段取消、空狀態 pass-through，沒有殘留注音或誤刪 App 已提交文字；GNOME Wayland VM 八路徑已驗證 T03 代表鍵序，多 App 與完整編輯邊界仍待驗收 |
| T04 | 倉頡既有垂直切片回歸 | F03 不在 Windows 第一階段基線；現有案例保護既有實作與擴充結構，目前不繼續功能開發、不列 parity blocker |
| T05 | 簡易既有垂直切片回歸 | F04 不在 Windows 第一階段基線；現有案例保護既有實作與擴充結構，目前不繼續功能開發、不列 parity blocker |
| T06 | 打開大於一頁的真實候選；切換直／橫式；方向鍵、Home/End、Space、PageUp/Down、數字、Enter、滑鼠選字 | 先查 macOS，再比對 Windows：macOS 橫式會讓 Left／Right 移動反白、Up／Down 翻頁；Windows 只把候選畫成橫式，核心仍維持 Up／Down 反白、Left／Right 翻頁，Linux 第一階段跟隨 Windows。L1 驗證首尾與頁界；X11/GTK3／GTK4／Qt6 直式皆以 End、Home、PageDown、Down、Enter 選出「妐」，並以真實滑鼠點第二列選出「鐘」；GTK4／Qt6 橫式另完整送 End、Home、PageDown、PageUp、Right、Left、Space、Down、Enter 並選出「妐」。直／橫設定保存亦已通過；GNOME Wayland VM 八路徑另以鍵盤與真滑鼠點第二列選出「鐘」並抽樣檢查關窗後像素清除；四邊位置、多螢幕與完整視覺驗收仍待完成 |
| T07 | 開啟分類 → 提交字 → Shift 選關聯詞 → 接續；全部關閉後重打 | host 是原字加「後綴」，不重複前字；順序／去重／分類保存與停用正確，fixture 固定具體詞與來源。X11/GTK3／GTK4／Qt6 已驗證預設「今天」、history-only「臺灣史」、全部停用「臺!」、舊設定遷移與 D-Bus 保存／重啟後「中程計畫」；GTK3 另完成原生設定視窗保存後「作物育種」。關聯詞滑鼠不是 macOS／Windows 對標要求；GNOME Wayland VM 八路徑已驗證三種詞庫設定的鍵盤選字，桌面設定 UI 與登出登入仍待驗收 |
| T08 | 中文／英文、Shift/CapsLock、全半形、數字、標點、繁轉簡 | 先查 macOS，再比對 Windows：macOS 的 `Ctrl+\` 輪替內建輸入法、單按 Shift 不切內部中英文、全形選單用 Command+Shift+Space；Linux 第一階段跟隨 Windows 的內部模式、可停用 `Ctrl+\`、固定 Ctrl+Space、短按 Shift、Shift+Space 與 Caps Lock。L1 全形對映包含 `Ａｚ０９！～　`；X11/GTK3／GTK4／Qt6 已驗證模式切換、active composition 清除、英文半／全形、全形 `Ａ！～　`、繁轉簡 `台湾` 與停用快捷鍵交回 client。停用案依各 client 插入規則固定自己的 golden，不由 addon 統一；filter 組合順序有測試；不測注音自動修正 |
| T09 | 組字／候選／關聯詞時送 Ctrl/Alt/Super 快捷鍵、repeat、press/release | macOS 原始碼 golden 先固定、再以 Windows 交叉檢查：兩者都在 engine 前放行一般 App shortcut，普通 key-up 不處理；macOS Command 與 Windows Alt 的平台 modifier 不同，短按 Shift 只有 Windows 另作模式切換。L1 已覆蓋 Ctrl+C、Alt+F、Super+L、Ctrl+Left、repeat 及 key-up；X11/GTK3／GTK4 驗證長按 `Ctrl+\` 只切換一次，Qt6 驗證完整 press/release；三者都讓 Ctrl／Alt 在 reading／候選期間交回 App 且不破壞狀態，並按 toolkit 是否插入 `Alt+F` 的 `f` 固定 exact golden；GNOME Wayland VM 八路徑另驗證 Ctrl+C pass-through；Super/compositor、repeat 與多 App 仍待驗收 |
| T10 | 在兩欄位、兩 App 切 focus；有候選時關閉 client；框架重啟／重新登入 | local X11/GTK3、GTK4 與 Qt6 已以同一視窗兩欄驗證第一欄候選失焦後清空 preedit、第二欄獨立提交「文」、切回第一欄不沿用舊候選並提交「中」；另在候選開啟時正常關閉 client、確認 Fcitx/addon 存活，重啟框架後由新 client 再提交「中」，各段含 `keyboard-us` 負控制。三套 toolkit 的兩個同時存活 App 另在空 composition 切焦點，驗證 App A 的英文全形與 App B 的中文半形狀態隔離，精確得到 `ａｂ中|文`，負控制為 `ab5j/ 1|jp61`。GTK4 失焦會短暫回報 client preedit 文字，切回後清除且最終 buffer 正確。macOS 失焦會 commit composing buffer，Windows TSF 則 abandon composition；GNOME Wayland VM 雙欄 16/16 已量到直接 Fcitx 路徑失焦提交原始 preedit、GTK 原生預設路徑清除 preedit。VM 兩個同時存活 App 的直接 Fcitx 六路徑 12/12 通過；GTK Wayland bridge 兩路徑的負控制 2/2、正向 0/2，後者共用一個 IBus context 而跨 App 泄漏模式。候選中關閉 client、addon 存活及新 client 恢復八路徑 8/8，框架新 PID 後再 8/8；明確登出再登入後 T01／T06 八路徑 16/16；瀏覽器、sandbox 與長時間穩定性仍待補齊 |
| T11 | 移 caret、選一段字後組字／替換、滑鼠移 selection；密碼／唯讀欄位 | 先依 macOS、再比對 Windows；local X11/GTK3／GTK4／Qt6 已驗證 active reading 中的方向、Home／End、PageUp／PageDown、Delete／Tab 與 Shift 變體不移 App caret／selection、不換欄且保留 reading；另依各 toolkit layout/cursor geometry 取得 hit point，以 XTest 真實拖曳選取既有「乙」、觀測 selection `1:2`，再由注音候選精確替換為「中」。密碼欄皆只收 literal 且不出現關聯詞；GTK3 會切到 `keyboard-us`，Qt6 則可能保留 engine 名稱。Qt6 唯讀多行欄以標準 `ImEnabled=false` query 發布狀態，三套唯讀欄完整鍵序後均不變。GNOME Wayland VM 八路徑的指標替換、負控制與 active-reading 編輯鍵另以乾淨輸出 21/24 加中斷後補跑 3/3 通過；密碼欄無 preedit，唯讀欄不變。active composition 期間改變指標 selection、瀏覽器仍待驗收 |
| T12 | 設定 UI 切直橫、比例、配色、錯誤提示聲、五布局、內建關聯詞分類；開符號列表點選／取消 | Windows 對標設定即時套用；縮放後 click hit test 一致；關閉／再開及重登入保存；符號送回原欄位且只一次；local X11/classic-ui 已在 GTK3／GTK4／Qt6 由 `Ctrl+0` 開表，分別以鍵盤或真實滑鼠點第一列提交「，」，GNOME Wayland VM 八路徑已驗證符號表鍵盤選字，另以真 VM 指標點第一列 8/8 提交「，」並檢查 popup 清除；仍需多視窗位置、設定 UI 與視覺驗收；不新增候選學習、注音自動修正或 F12–F15 佔位 UI |
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

2026-09-20 Ubuntu 24.04 local amd64 另以 source build 分別在 `/usr/local`、`/usr`
與含空白的自訂 prefix／libdir／datadir 真安裝，每組經 Fcitx 5 實際載入該路徑的
addon，GTK3／GTK4／Qt6 跑完 82 個非設定視窗 X11 案例，皆通過，並依 manifest
卸載確認檔案消失。自訂 prefix 中的無關 sentinel 在卸載後保留，重裝後三套 toolkit
的 T01 再通過。`/usr` 與自訂 prefix 使用乾淨的一次性 Ubuntu container；
`/usr/local` 使用長駐開發 container。這補上 24.04 的三種 prefix、完整 X11
打字與重裝局部證據，仍不涵蓋原始碼跨版本升級、Ubuntu 22.04 的對等系統安裝、
其他 active Ubuntu 或 GNOME／Wayland。

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
   PR 只跑 build、unit、staged install 與一個 GTK3/Fcitx 真打字 smoke；合併進
   `master` 後才跑完整 hosted typing suite、UI 操作與套件生命週期。手動完整測試／
   發布再跑上述所有 App、sandbox、視覺組合與壓力項目。主環境結果不得因其他平台
   成功而被覆蓋。

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

- PR：Ubuntu 24.04 + Fcitx 5 的 required smoke job 執行 build、L1 unit、staged
  install 檢查，並以 GTK3 跑一個 Standard 注音真實逐鍵 T01 與 `keyboard-us`
  負控制；不在 PR 建套件、跑完整 toolkit 矩陣、sanitizer、source archive 或
  Ubuntu 22.04 package lifecycle。Debian／Fedora 不排入目前 required jobs。
- 合併進 `master` 後的 push：Ubuntu 24.04 跑完整 hosted X11 typing suite、UI、
  sanitizer、source build/archive 與套件升級／移除／重裝；Ubuntu 22.04 跑最低 API
  build、source gate 及 package lifecycle。桌面三條 session 路徑實作完成後也只在
  主分支完整 gate 與手動／release 流程跑，不塞回 PR smoke。
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
- configure／make 入口的 T14-SOURCE build、配置錯誤、staging、clean、installed
  X11 與 source archive 重建在合併後的主分支完整 gate 執行；手動完整與 release 跑
  全部 active Ubuntu 的原始碼安裝生命週期。release 必須使用將發布的同 SHA source
  tarball，解壓後獨立離線重建，再安裝該批產物驗證，不能改用 `.deb`。

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
