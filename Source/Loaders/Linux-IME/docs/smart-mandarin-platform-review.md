# 好打注音跨平台行為檢查

本紀錄保留先前 Linux 修正階段的比較與驗證歷史；本次十／十一音節界線、19 音節完整句與現況見 [實體鍵盤好打注音交接](../../../../docs/SMART_MANDARIN_PHYSICAL_KEYBOARD_HANDOFF.md)。macOS 與 Windows 共用 `OVIMSmartMandarin`、PlainVanilla 和 Manjusri；iOS、Android、Linux 有各自的 walker。下表區分桌面、手機實體鍵盤與觸控，不能把五者視為完全相同。

## 本輪 Linux 問題與修正

| 嚴重度 | 重現條件與原本問題 | 修正與驗證 |
| --- | --- | --- |
| P1 | GTK 4 以藍底顯示整段好打注音組字；GNOME Text Editor 中組字「你好」後移窗並失焦，文件變成「你好你好」 | preedit 改用底線格式。Fcitx 客戶端宣告自行處理失焦送字時，引擎只清除狀態；主動切換輸入法仍提交組字。以隔離 GTK 4 宿主建立修正前失敗案例（重複兩次）與修正後通過案例，並用真實 GNOME Text Editor 的 X11 直接 Fcitx 路徑確認只留一次。 |
| P1 | 學習單字「假」後，再打「請假要去哪裡玩呢去海邊」，到海只擠出「請」 | 保留詞跨度；檢查畫面開頭與詞庫相符的完整詞，一次擠出「請假」，固定下一段。以實際學習資料備份重現，另建可重複的 SQLite fixture，驗證第二次擠出、後續改選和插入／刪除。 |
| P1 | 組字中更改好打／傳統或鍵盤配置，下個鍵直接清空組字；更改設定後直接切換輸入法也可能漏字 | 每個 input context 保存當前引擎設定，在套用新模式／配置前由原引擎完成組字；驗證三種設定切換次序。 |
| P1 | 輸入「你好」後輸入「ㄒㄧㄣˇ」（`vup3`），傳統字表有「伈」但模型無此讀音，誤開傳統候選；選字會清空前句，只送出候選字 | 移除破壞整句狀態的傳統候選 fallback，與桌面模組插入失敗時相同：保留句子與讀音並提示，可繼續修正或 Esc 取消讀音。 |
| P2 | 點第三字的 preedit action 被當成 UTF-8 byte offset，可能選到第二字 | 輸入位置改用 Unicode 字元索引，輸出 preedit 游標仍為 byte offset。驗證點第三字後選字及繼續輸入的位置，經過 Qt 6／Fcitx D-Bus 路徑。 |
| P2 | 句中有未完成注音時按 Delete 刪掉後方中文字；Esc 刪掉整句 | Delete 保留狀態並提示；Esc 只取消未完成讀音，沒有讀音時保留整句。 |
| P2 | 候選窗仍開著時，Backspace、Delete、注音鍵繼續改動句子；符號候選可遮住偷偷建立的新讀音 | 候選窗統一處理選字、翻頁、反白和取消，其餘編輯鍵提示，不修改組字。Ctrl／Alt／Super 應用程式快捷鍵仍可交回宿主。 |
| P2 | 候選中的 Home／End 移動組字游標；換點另一字沿用舊頁碼；橫式候選的左右鍵翻頁 | Home／End 移到整份候選首尾，換字回到第一頁；橫式左右鍵移反白、上下鍵翻頁。 |
| P2 | Shift 大寫穿過活躍組字；不帶 Shift 的大寫字母又被當成注音 | ASCII 大寫與 Shift 字元按字面處理，先送出已完成組字；未完成讀音仍攔截提示。 |
| P2 | 有未完成首聲讀音時 Down 只提示，與桌面模組不同 | Down 和 Space 一樣先完成讀音，不提前送出整句。 |
| P2 | 「只顯示 Big5 字元」只作用於傳統注音 | 好打 walker 和詞候選也套用 Big5-HKSCS 過濾；驗證 Unicode 模式仍能顯示被排除的字。 |
| P1 | 「中國地方」在第三字重新選「地方」後，舊路徑仍是一個四字詞，Linux 卻記成「國→地方」 | 先套用選字、重新分詞，再按新路徑記「中國→地方」；回歸測試直接檢查資料庫中沒有舊前詞紀錄。 |
| P1 | 學過單字「夜」後，「熬夜」仍顯示相同文字，但固定 `+5` 分使它被拆成「熬／夜」，後續擠字及詞組修正可能受影響 | 學習候選的該步分數只提高到 `0`，與 iOS／Android walker 一致；以真實模型驗證「熬夜」仍是一個詞段，並保留既有「請假」擠字回歸。 |
| P2 | 語言模型若沒有 Bigram 表，或表為空／不完整，原本仍成功載入，輸入時靜默退化為 unigram 回退 | 載入時檢查表格欄位及 885,627 筆 Bigram；測試覆蓋無表、空表和部分資料。 |

先前只測乾淨詞庫，未涵蓋「選字學習 → 再打長句」。實際資料中的單字「假」學習分數會使 Linux walker 把畫面上的「請假」走訪成兩個單字，舊流程直接按第一節點長度擠出。因此這次同時保留有學習的回歸案例和獨立的操作案例。隔離 E2E 的一般案例會清除**測試目錄**內的學習紀錄；指定外部資料 fixture 或既有桌面工作階段時不清除。原使用者資料庫不修改。

## 五平台事件對照

| 事件 | macOS | Windows | iOS | Android | Linux 本輪處理 |
| --- | --- | --- | --- | --- | --- |
| 讀音完成與組句 | Manjusri 插入節點 | 同 macOS 模組 | Swift walker | Java walker | C++ walker |
| 詞候選 | 保留詞的節點與跨度 | 同 macOS | `SmartMandarinCandidate.length` | `SmartMandarinCandidate.length()` | 保留候選與選擇的詞跨度，不再固定只有一字 |
| Enter 選字 | 候選面板先選字，保留組字 | 同 macOS | 實體鍵盤先選字；觸控 Enter 完成文字及 editor action | 實體鍵盤先選字；觸控另有送出流程 | 候選時先選字，下一次 Enter 才送出 |
| 選字後游標 | 預設移到選詞後；另有配置可不移 | 同共用模組配置 | 實體鍵盤移到詞後，觸控不改後續插入游標 | 同 iOS 的兩種操作區分 | 桌面操作移到選詞後 |
| 候選中其他編輯鍵 | PlainVanilla 攔截並提示 | 同共用候選面板 | 引擎可開始新讀音；由實體／觸控路徑分派 | 可開始新讀音；由實體／觸控路徑分派 | 採桌面面板行為，不讓按鍵改動面板後方組字 |
| 候選 Home／End、方向 | 面板首尾；沿排列方向移反白 | 同共用候選面板 | 自己的按鍵分派 | 自己的按鍵分派 | 首尾及橫／直式方向分開處理 |
| 未完成讀音的 Esc | 只清讀音 | 只清讀音 | 實體鍵盤只清讀音 | 實體鍵盤只清讀音 | 只清讀音 |
| 已完成整句的 Esc | 預設不清句子 | 預設可清句子 | 實體鍵盤保留 | 實體鍵盤保留 | 採 macOS 預設保留 |
| 未完成讀音的 Delete | 提示，保留 | 同模組 | 不從觸控 Backspace 推論 Delete | 不從觸控 Backspace 推論 Delete | 提示，保留後方字 |
| 長句擠字界線 | 實體鍵盤保留十個已完成音節，第十一個移出開頭完整節點 | 同 macOS | 容器 App 實體編輯器十／十一；虛擬鍵盤九／十 | 外接實體鍵盤十／十一；虛擬鍵盤九／十 | 實體鍵盤十／十一，另保護被單字學習拆開的可見完整詞 |
| 切換輸入法／模式 | IMK 送出組合顯示內容再清理 | TSF 用保留文字的 EndComposition 結束組字 | 先完成有效讀音，失敗時保留原注音；觸控另外管理宿主已寫入尾段 | 同樣先完成有效讀音；觸控另管理宿主尾段 | 完成有效讀音、保留無法完成者；重複回呼不重複送字 |

## 尚未相同的行為與驗證界線

- Linux 的 Ctrl 符號候選仍先送出前面的句子，符號使用獨立候選狀態；macOS／Windows 可把符號節點保留在同一組字圖內。這是已知差異，不能宣稱符號編輯完全一致。
- Linux 固定九個數字選字鍵；桌面共用模組預設八個，並支援許氏／倚天 26 鍵的字母選字鍵及其他配置。Linux 尚未提供所有這些配置、Shift 選取組字區新增詞等桌面功能。
- Linux 保留桌面版的「明確候選改選」學習時機；iOS／Android 還會在確認整句時呼叫 `learnConfirmedComposition`。Linux 已移除固定 `+5` 的學習加分，但未改動語料、詞頻或 Bigram 資料列，也不宣稱所有候選排序相同。
- macOS／Windows 的 Manjusri 在首詞回退時使用 BOS backoff，學過的 Bigram 會取代同一組讀音的內建 Bigram 列；Linux 與 iOS／Android walker 在首詞回退時用 unigram 分數，並以完整前後詞比對學過的 Bigram。直接照搬桌面 BOS backoff 會改變 Linux 1,345 組單音節讀音中的 112 組首選，包括已驗證的「ㄇㄧˋ→密」；本輪維持目前首選，並把實體鍵盤界線調整為十／十一，沒有把評分差異當成局部補丁。
- 手機觸控會把完成中文字即時寫進 App，再維護可替換尾段；Linux 使用 Fcitx preedit。手機觸控的選字游標契約不能直接套到 Linux。
- 已執行 Linux CTest、隔離 Ubuntu 24.04 X11／GTK3 操作案例，並加入 Qt 6 preedit action 整合測試。Qt 測試由宿主呼叫點擊所用的 `QInputMethod::invokeAction`，不是實體滑鼠定位測試。Fcitx 組字點擊仍需要客戶端送出此事件。
- 先前 Linux 修正階段沒有 macOS／Windows／iOS／Android SDK 或實機驗證；本次新測試與未測範圍另見上述交接。GNOME 原生 Wayland 的移窗行為尚未以自動化重驗。GTK 4 宿主及真實 GNOME Text Editor 先前已用 X11 直接 Fcitx 路徑測試失焦送字。原始碼、staged addon、安裝包和系統已安裝版本分開記錄。

## 參考入口

- macOS：[OpenVanillaController.mm](../../OSX-IMK/OpenVanillaController.mm) 的 `commitComposition`、`deactivateServer`；共用 [OVIMSmartMandarin.cpp](../../../ModulePackages/OVIMMandarin/OVIMSmartMandarin.cpp) 的 `handleKey`、`candidateSelected`；PlainVanilla 的 `PVCandidate.h` 和 `PVLoaderSystem.h`；Manjusri `Graph.h` 的 `shiftNodeAndMaintainPathWalk`。
- Windows：[KeyKeyEngine.cpp](../../Windows-TSF/KeyKeyEngine.cpp) 和 `TextService.cpp` 的 `endComposition`。
- iOS：[BopomofoEngine.swift](../../iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/BopomofoEngine.swift) 的 `selectDisplayedCandidate`、`finishSmartReading`、`finishCompositionForModeSwitch`。
- Android：[BopomofoEngine.java](../../Android-IME/app/src/main/java/tw/chichi77/keykey/android/BopomofoEngine.java) 的同名流程及 `hardwareSmartEditing` 條件。
- Linux：`engine/src/engine.cpp`、`smart_mandarin_store.cpp`、`adapters/fcitx5/fcitx5_engine.cpp`、`tests/engine_tests.cpp`、`ci/run-x11-e2e-session.sh`。
- Fcitx 字元座標核對：[官方 Qt 前端的 invokeAction](https://github.com/fcitx/fcitx5-qt/blob/master/qt5/platforminputcontext/qfcitxplatforminputcontext.cpp) 將 Qt 索引轉成 UCS-4 長度；[官方拼音引擎](https://github.com/fcitx/fcitx5-chinese-addons/blob/master/im/pinyin/pinyin.cpp) 將 `event.cursor()` 與 UTF-8 字元數比較。
