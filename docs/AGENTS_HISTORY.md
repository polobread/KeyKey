# 歷史開發交接紀錄

此檔保留其他平台整理前的實驗、測試與待辦；已淘汰的 Linux 自製核心紀錄已移除。它是歷史參考資料，不是目前開發規則；執行前請以根目錄 `AGENTS.md`、程式碼及各平台現行文件核對。

---

# AGENTS.md — 開發交接

**2026-09-24 macOS 中文數字與單位資料試打版：** `v1.2.10` 保持輸入事件與排序程式不變；
`numeric-unit-lexicon.tsv` 窮舉 1,157 筆中文數字、常用單位與大寫金額位值，現有高詞頻保留。
另在試打語料加入大寫金額情境。重煮的 DB 為 114,235 unigram／885,614 bigram rows，
比原 2,300 篇 DB 多 73,728 bytes；`PRAGMA integrity_check` 為 ok。macOS arm64 試打包為
`Installer/local-builds/chichi77-KeyKey-1.2.10-bigram2300-numeric-units-enum-20260924-macos-arm64.pkg`，
SHA-256 `becd50b0755067eed9b7b8a5ad16b99b2807cfaa50476657c90d951bb50a5caa`。
套件內 DB SHA-256 為 `fd7be3f53d15c511ceb2bbfce299e94895b6865a83552143a2fff877690de853`；
四個 app 版號 1.2.10、ad hoc 簽章、固定安裝路徑及 ZIP 完整性均已檢查。
待使用者試打「二片／二篇／兩片／兩篇」及大寫金額上下文；阿拉伯數字開頭的
`0分／1份／2篇／10號` 無法靠此資料路徑直接改善，不能記為已驗收。

**2026-09-24 macOS 2,300 篇試打包：** 已在 `v1.2.10` branch 重新編譯 arm64／macOS
15+ app，並以固定安裝路徑封裝成本機測試 pkg：
`Installer/local-builds/chichi77-KeyKey-1.2.10-bigram2300-v3v4-20260924-macos-arm64.pkg`。
套件內四個 app 版號均為 1.2.10，DB 為 113,599 unigram／882,666 bigram rows，
SHA-256 `88a32b9e7e952523ad84d5680effda835b800126a52fbd95ded4afa1cf95f456`；
`PRAGMA integrity_check`、ad hoc app deep/strict 簽章、pkg `relocatable=false`、ZIP
完整性均已核對。pkg 未做 Developer ID 簽章或 notarization；舊 1,650 篇套件保留。

**2026-09-24 v2／v3／v4 文章納入好打注音 bigram：** v2 1,650、v3 350、v4 300
篇正文已驗證，`build-versioned-article-corpus.py` 合成 2,300 篇語料並逐字去除
7,212 行重複文字。預設 DatabaseCooker Makefile 現在讀取
`article-corpus-2300-exact-dedup.txt`；已重煮本機 `KeyKey.db`，共有 882,666 筆
bigram rows、559,913 組文字 pair，`PRAGMA integrity_check` 為 ok。相同詞庫與
bootstrap 條件下，v3 新增 62,247 組文字 pair，v4 再增 76,971 組，均無詞對流失；
最小 LM DB 依序增加 4.88 與 6.08 MiB。完整量測見
`DataSource/AISyntheticBigram/versioned-article-bigram-impact.md`。已另建 2,300 篇試打包。

**2026-09-26 AI 繁中語料 v4 詞庫導向規劃：** `DataSource/AISyntheticArticles/`
新增獨立的 300 題 v4 prompt set。候選詞池固定為 6,000 個不同詞：完整納入 28 份
非動漫分類詞庫的 4,012 筆有效列、跨庫及大小寫／全半形正規化去重後 3,758 詞，另由
McBopomofo 以固定 seed 的詞頻加權抽樣補 2,242 詞。6,000 詞先分為 200 組、每組 30 詞，
其中 100 組另配一篇互補題目，共 300 篇、9,000 個分配詞槽；每題指定 15 個必用詞，
全體共有 4,500 個不重複必用詞。同義／近義種子不拆組，且不會被分到不同 15 詞半組；
其餘詞依領域及共同雙字核心盡量同篇。動漫詞庫明確排除。產物為
`generate-typing-prompts-v4.py`、JSONL、preview、stats、plan 與逐詞 assignment TSV；
已完成並驗證 300 篇 v4 正文，納入預設 SmartMandarin bigram corpus 與新試打包。

**2026-09-25 AI 繁中語料 v3 補強規劃：** `DataSource/AISyntheticArticles/`
新增獨立的 350 題 v3 prompt set，保留 v2 的 10,000 題與 1,650 篇正文不動。
v3 依屬性分析補入工作公事 70、法律公文 70、情緒關係 55、社群口語 50、
日常短訊息 50、消費交易 30、數位混合輸入 25；近 30 年維持 245／350（70%）。
內容形態包含 95 篇短訊息包、75 篇正式文件，120 篇保持未解決或部分解決，
110 篇明確要求日期時間、數字金額／編號、英文詞、網址／路徑、Emoji 或注音語助詞；
另有 8 題使用「蝦皮購物」。語氣改為依主題配額，全部題目輪替補入又／再／也、
和／與／以及等連接詞情境；舊年代已用活動最早年代、媒介及地區 gate 檢查。
產物為 `generate-typing-prompts-v3.py`、`typing-prompts-v3.jsonl`、preview、stats 與 plan；
已完成並驗證 350 篇 v3 正文，納入預設 SmartMandarin bigram corpus 與新試打包。

**2026-09-24 macOS 好打注音自訂詞可靠性：** 好打注音啟用時，輸入法選單新增
「編輯自訂詞…」直接開啟內附 PhraseEditor。詞庫列表不再以 `rowid == index + 1`
尋址，改用 `ORDER BY rowid LIMIT/OFFSET`，所以刪除或匯入造成 rowid 缺口時不會讀錯列；
沒有讀音的字會略過新增／修改，損壞讀音不再讓編輯 sheet 越界，多音字組合上限為依
詞頻順序的 256 組，避免長詞組合爆炸。英文、繁中、簡中字串 lint 與 macOS arm64
Release app（含 Preferences、PhraseEditor）完整建置通過。
好打注音選單也提供有確認步驟的「重設學習紀錄」；只以 transaction 清除
`user_bigram_cache` 與 `user_candidate_override_cache`，保留 `user_unigrams`，並在重新
載入前呼叫 `flushUserCache()`，避免記憶體中的舊資料寫回。
新的本機測試包為
`Installer/local-builds/chichi77-KeyKey-1.2.10-bigram1650-smartfeatures3-20260924-macos-arm64.pkg`；
套件內四個 app 版號均為 1.2.10、安裝路徑 `relocatable=false`、DB integrity 與 app
ad hoc deep/strict 簽章檢查通過。此本機套件未做 Developer ID 簽章或 notarization。

**2026-09-24 iOS／Android 好打注音：** 兩個 mobile frontend 都新增「好打注音／傳統注音」
模式，新安裝預設好打注音，並以 cook 好的 `KeyKey.db` 做懶查詢 Viterbi 整句組字。iOS
KeyKeyEngine 104 tests 全過，iPhone 16／iOS 18.6 的鍵盤加入與好打注音 UI tests 2/2
通過；容器實體鍵盤編輯器新增注音模式選單後的版面與控制項 UI test 1/1 通過。Android
JVM tests、`lintDebug`、`assembleDebug` 全過，Pixel 9a／API 37 實測設定切換、
`你好` 連打、Enter 確定後繼續輸入通過。Android 完整六 AVD A–L 發布矩陣尚未執行，
不可將這次單機 smoke test 記成完整 Android 驗收。

**2026-09-24 好打注音周邊功能稽核：** 與 Yahoo KeyKey 1.1.2528 比對後，候選覆寫學習、
使用者 bigram、Shift 選取後 Enter 加詞、使用者詞庫增刪改讀音、匯入匯出與好打注音設定
原本都仍在；實際遺漏是偏好設定的「啟動詞彙編輯工具」按鈕仍接到 `launchEditor:`，但
`TakaoPhrases.m` 的 method 在重建時被刪除。現已恢復，以 SharedSupport 內的
`PhraseEditor.app` 為主、新 bundle id 為備援，缺檔時顯示三語提示。三語 strings lint、
selector wiring audit 與 macOS arm64 Release build 通過。Yahoo 線上字典／更新／追蹤、
MobileMe 備份及舊 Extra Modules 與 SmartMandarin 詞庫無直接關係，未混入本次恢復；詳見
`docs/SMART_MANDARIN_FEATURE_AUDIT.md`。

**2026-09-24 macOS 1650 篇試打包：** 已在 `v1.2.10` branch 以三份 bootstrap corpus、
`corpus-typing-feedback.txt` 與 `article-corpus-1650.txt` 重煮 SmartMandarin；核心詞彙僅用
McBopomofo 與本專案 `supplemental-lexicon.tsv`，29 份分類 AI 詞庫未併入核心斷詞，但仍按
既有設計保留為關聯詞 collections。套件內 DB 為 113,599 unigram rows、668,698 bigram
rows、420,820 組文字 pair，`PRAGMA integrity_check` 通過，SHA-256 為
`3c75e17996b50b04a6b04746539beb1e97acd0d36dde8e31f6668dfcb1b5fd0d`。arm64 app build 與
套件內 app 的 ad hoc deep/strict 簽章檢查通過，component `relocatable=false`；本機測試 pkg
未做 Developer ID 簽章或 notarization。產物在 `Installer/local-builds/`，檔名前綴為
`chichi77-KeyKey-1.2.10-bigram1650-smartfeatures1-20260924-macos-arm64`。五平台產品與建置版號
已正式同步為 1.2.10；新 macOS 套件內主程式及三個輔助 app 的 bundle version、pkg metadata
均已驗證為 1.2.10。本次透過 make command-line override 加入 1650
篇；這是當時的套件建置方式，目前預設 Makefile 已改用 2,300 篇去重語料。

**2026-09-24 合成文章 bigram 成長實驗：** 文章 1–1650 已通過標題、1050–1350 漢字、
指定名稱、重複正文與台灣慣用詞檢查；只有明確的「中國繁中地名與旅行」類別可略過
台灣詞彙 gate。`typing-articles-v2.jsonl` 有 1,650 篇有效文章、0 篇退件、0 API token。
`build-article-corpora.py` 會建 100／200／300／400／450／500／700／900／1100／1300／
1500／1650 篇累積快照；正式 `SmartMandarinCooker.rb` 量到 1650 篇相對 bootstrap 新增
416,642 個文字 bigram、668,529 筆 reading-expanded rows，最小 LM database 增加
33.45 MiB。500→700 新增 53,014 個文字 pair、84,480 筆 rows、4.27 MiB；後段
1551–1650 的留出 coverage 從 500 篇的 39.03% 升到 700 篇的 44.27%，1500 篇為
55.61%。每篇新增 pair 從 501–700 的 265.1 降至 1501–1650 的 187.5，已有遞減但未
飽和。以 501–1650 六區段作 power-law 規劃估計，降到每篇 150／125／100 新 pair 約在
2982／5116／9903 篇，僅供推估。
精確正規化去重可刪 5,709／46,749 行，保守 near dedup 再刪 37 行，但 SQLite 大小都仍
為 41.30 MiB；near dedup 保留 99.9993% text pair，1551–1650 留出 coverage 不變。
原因是 cooker 已把每組合成 pair 上限設為 1，段落去重只改善 corpus 衛生，不能實質控制
DB 大小。完整流程與結果見 `build-article-corpora.py`、`analyze-article-bigram-growth.py`、
`build-filtered-article-corpora.py`、`analyze-corpus-filtering.py` 與兩份 `.md` 報告。
100–1,650 篇的中途 snapshots 仍只供實驗；目前 2,300 篇去重語料已納入 Makefile 的
`SMART_BIGRAM_CORPORA`。封裝前仍須做候選順位與實際輸入 A/B；若要控體積應選較小
snapshot 或另做 bigram row pruning。

**2026-09-24 29 份 AI 分類詞庫實驗：** `analyze-ai-lexicon-impact.py` 已用相同 bootstrap、
typing feedback、文章 1–1650 與 1551–1650 留出集比較目前小麥模型、動漫、其餘 28 份與
全部 29 份。全部加入會新增 4,806 個 SmartMandarin 詞、1,134 個文字 pair，同時因重新斷詞
失去 800 個 pair，DB 增加 0.41 MiB；留出 coverage 由 55.615% 降至 55.552%。動漫單獨新增
2,197 詞，但一般文章只命中 43 詞，新增／失去 pair 為 149／102，coverage 微降 0.008 個
百分點。動漫檔含「到我」「同學是」等作品名殘片與「相信你」「任務完成」等一般片語，會
把 `約／成`、`借／物`、`物／主`、`任務／完成` 等一般 bigram 合成單詞；維持 opt-in，未經
專名／殘片 review 不得併入核心 SmartMandarin。其餘 28 份共 2,616 個新詞，只有 104 個在
文章語料出現，後續應先 review 這 104 個再建精選 allowlist。`--lexicon-preserve-counts` 與
直接合併結果相同，表示差異來自新增詞／讀音，不是覆寫小麥詞頻。分類 TSV 的第四／第五欄
已可安全忽略；18 筆含英數符號、不能編成注音 qstring 的詞會計數後略過，仍保留在關聯詞
系統。詳細數據見 `DataSource/AISyntheticBigram/ai-lexicon-impact-report.md`。29 份詞庫目前
**未加入**預設 SmartMandarin Makefile。

**2026-09-23 macOS 好打注音：** `v1.2.10` 恢復 macOS 的 SmartMandarin／「好打注音」
整句組字，新安裝預設為 SmartMandarin，既有使用者的 `PrimaryInputMethod` 不強制覆寫。
`SmartMandarinCooker.rb` 會把 MIT 授權的 McBopomofo `phrase.occ`、`BPMFMappings.txt`
及 `bpmf-ext.cin` 轉成 Manjusri 的 `unigrams`，並以 `--lexicon` 載入
`DataSource/AISyntheticBigram/supplemental-lexicon.tsv` 的本專案補充詞；`DataSource/AISyntheticBigram/corpus-v1.txt`
、`corpus-v2.txt` 與 `corpus-v3.txt` 提供 AI 合成 bootstrap corpora；同一文字 bigram
無論因模板重複出現幾次都只計一次，再以 unigram prior strength 1,000 做平滑並寫入
`bigrams` 與 unigram backoff。這份合成語料只供工程與 A/B 測試，上下文選字仍可能與舊
Yahoo KeyKey 不同。資料庫 unigram 實建為 113,593 筆（含 BOS／EOS／UNK），
三份 corpus 共 11,180 句、131,838 tokens，bigram 為 6,236 筆，1,224 筆 unigram 有非零
backoff；138,946 次模板重複相鄰詞未重複加權，`PRAGMA integrity_check` 通過；
ManjusriBuilder 的「今天被強制升級到」八音節測試首選依序為
「今天／被／強制／升級／到」，路徑分數從純 unigram 的 -18.9313 提升為 -14.6229。
以 `make SMART_BIGRAM_CORPORA=` 可建純 unigram 對照組。macOS Release 無簽章 build 通過。
Windows、Linux、Android、iOS 仍維持既有 TraditionalMandarin 行為。

**2026-09-24 實際試打回饋詞：** `supplemental-lexicon.tsv` 目前補入「蝦皮購物」及公文法律
語境缺少的完整詞，`corpus-typing-feedback.txt` 提供下單、訂單、賣場、賣家、聊聊、客服、
物流、超商取貨、退貨、退款與公文法律搭配。`phrase.general.tsv` 也加入「蝦皮購物」，使
跨平台分類關聯詞能在「蝦」後提供「皮購物」。不得直接改動標示為 McBopomofo 上游逐位元
副本的 `phrase.occ` 與 `BPMFMappings.txt`；本專案新增詞固定放在補充詞檔。

**2026-09-21 macOS App Store Connect 可行性：** 新增
[macOS App Store Connect 上架可行性與發行計畫](MACOS_APP_STORE_PLAN.md)。Apple DTS
對 macOS InputMethodKit IME 的 accepted answer 是沒有 Mac App Store sanctioned
distribution path，只能商店外發行；2026 年 4 月再問時仍建議提交 enhancement request。
現有 app 必須由 `.pkg` 安裝到 `/Library/Input Methods`，且沒有 sandbox entitlement，
也會直接寫入 `~/Library` 並透過 registered `NSConnection` 連接三個 nested helper；但即使
完成 sandbox 化，也不會解決 App Store 缺少 IME 安裝／註冊 extension point 的主阻礙。
因此不得製作會從商店內複製、下載或啟動外部 `.pkg` 的殼 App。macOS 正式版維持
Developer ID、notarization、stapling 與 GitHub Release；先以 Apple Feedback／DTS 書面
回覆作 Gate 0，Apple 若未提供 documented extension path 就是 NO-GO。計畫另列出 direct
distribution 安裝驗收、per-user 安裝與 sandbox spike、Intel／universal build、隱私政策、
以及只有 Gate 0 通過後才執行的 App Store target、App Group migration、素材與 review gate。

**2026-09-21 iOS／Windows／Linux 顯示版本：** iOS container app 首頁標題下方從
`CFBundleShortVersionString` 顯示 `版本 1.2.9`，並以 `app.version` accessibility id
加入 smoke UI test。Windows `KeyKeySettings.exe` footer 從 CMake `PROJECT_VERSION`
編譯出的 `KEYKEY_MARKETING_VERSION` 顯示版本，static frontend validator 會檢查接線。
Linux 沒有獨立 container app，因此在琦琦注音的 Fcitx 設定頁最上方，以 read-only
information group 顯示 CMake `PROJECT_VERSION`；X11 schema gate 會核對文字。三平台 UI
都不另外硬編版號來源，升版時跟既有 build metadata 一起更新。

**2026-09-21 1.3.x 候選順位參考計畫：** 新增
[1.3.x 跨平台候選字順位計畫](CANDIDATE_ORDER_1_3_PLAN.md)。這是未排期、未承諾實作的
完整參考文件，不改變 1.2.9 執行行為。計畫將 macOS 凍結順位定為主基準、Windows
「ㄅ半」凍結順位定為補充基準，要求五平台不因 glyph／字型／Big5 支援刪除候選；缺字
須保留原 Unicode、slot、編號與分頁並顯示方框。文件記錄三份 CIN 自 2012 年未改內容的
hash、基礎／全字表關係與六組歷史例外，提出多模式、profile version、明確 ordinal／
`ORDER BY`、全 1,541 讀音 golden digest、字型安裝前後順位不變及 Big5 僅作進階舊系統
相容模式。真正開發前仍須由使用者指定可接受的 macOS 與 Windows 參考 build／設定，
匯出完整序列後才能凍結 profile；不可直接依目前字型過濾結果或單一截圖推算。
後續調查另確認三份 CIN 本身均為無 BOM、LF 的 UTF-8，不需轉碼或修改；不同國家／地區
使用者的 OS 語言、OEM／發行版、選用字型及 rendering stack 會造成 glyph／tofu 與地區
字形差異，但不得改變候選序列。計畫已加入 `zh-TW`、`zh-HK`、`ja-JP`、`ko-KR`、英文
環境及 Android OEM／Linux 字型套件對照矩陣；PUA 必須搭配相同私用對應的字型，系統日後
擴充標準 Unicode 字型不保證補上。是否隨產品提供可散布的罕字 fallback font 留待實作前
另案決定。

**2026-09-21 Android 欄位提示與首頁版本：** 在本機 `v1.2.9` branch 上，首頁標題下方
會從已安裝 package 顯示 `版本 1.2.9`。Android 的 `EditorInfo.inputType` 只決定
第一次進入欄位的模式：一般文字與 URI 一開始就是完整三模式，URI 即使帶
`IME_FLAG_FORCE_ASCII` 也保留中文搜尋；Email、password、visible password、web
variants 與 `IME_FLAG_FORCE_ASCII` 先用原本的英文精簡模式，phone、number、datetime
先用原本的數字精簡模式。所有精簡模式的 MODE 鍵都可按；第一次按下時解除這次 editor
session 的限制並進入完整注音／英文／數字循環，後續 input-view restart 不會重新鎖定，
離開欄位才重設。debug test host、README 與 AVD 計畫已同步。
觸控英文模式按 Shift 後，末四個小寫符號 `; , . /` 會對應成 `: < > ?`，顯示與
實際送出字元共用同一份 shifted layout。
`lintDebug testDebugUnitTest assembleDebug` 已通過，APK metadata 為
`versionCode=1002009`、`versionName=1.2.9`；六台 AVD 的 A–L 人工矩陣尚未重跑。
遠端 `refs/heads/v1.2.9` 已刪除，所以 `git pull origin refs/heads/v1.2.9` 會失敗；
本機 branch 與遠端已發布 `v1.2.9` tag 的 peeled commit 都是 `20a2f19`。

**2026-09-21 Android Fragment Play 警告：** Billing 9.1.0 經由
`play-services-basement:18.9.0` 間接帶入已過時的 `androidx.fragment:fragment:1.1.0`；
`app/build.gradle.kts` 已用 dependency constraint 將 release runtime 解析到官方穩定版
`fragment:1.9.0`。`dependencyInsight` 已確認 1.1.0 僅顯示為 requested、實際 selected
為 1.9.0；該 AAR 的 Manifest 宣告 `minSdkVersion=23`，低於專案與 Android 8.0 的 API
26。`lintDebug testDebugUnitTest assembleDebug` 與 `bundleRelease` 均已通過；Play Console
警告仍須上傳這個新 AAB 後由 Google 重新掃描才會更新。

**2026-09-21 Android 設定順序：** 「虛擬鍵盤高度」標題、說明及直式／橫式控制項已從
震動設定後方移到候選設定之後、「支持開發」之前；偏好 key、預設值與滑桿行為未改。

**2026-09-21 iOS 欄位提示與英文 Shift：** iOS 已對齊 Android 的觸控欄位策略：URL
從一開始提供完整注音／英文／數字與全部功能；ASCII、Email、姓名電話及各種數字欄位
仍保留原本的英文或數字起始精簡模式，但 MODE 永遠可按，第一次按下會解除該欄位限制，
之後在同一 document/editor 重顯鍵盤仍保持完整三模式，切換欄位才重設。英文小寫模式按
Shift 後，四個標點已由 ASCII `; , . /` 改為 `: < > ?`；顯示與送字
共用 shifted layout。2026-09-21 `KeyKeyEngine` 的 97 個 Swift tests 與 generic iOS
Simulator Debug build 已通過；五台 Simulator A–K 與實機仍未重跑。

**2026-09-21 v1.2.9 發布現況：** 首次 `v1.2.9` tag／Release 曾因 Linux CI 失敗撤下；修正後已重新發布。`v1.2.9` tag 與 Release 存在，Linux 三個 `.deb`、面板原始碼及 `SHA256SUMS` 均在 Assets，Release 標為 latest；Linux CI 的 2026-09-20 手動完整驗證與後續分支執行成功。Android 與 iOS 繼續走商店發行，GitHub Release 不放 debug APK 或 Simulator 包。

**2026-09-20 Windows 使用者文件：** `WINDOWS_INSTALL.md` 以 `v1.2.9` Windows x64 ZIP 為主要安裝流程，說明完整解壓縮、連按兩下 `Install.cmd`、管理員提示、`Win + Space`、記事本試打、候選字、設定與解除安裝。README 和 Windows TSF 技術 README 已設入口。`docs/images/windows-install-flow.svg` 是明確標示的示意圖，另沿用 `Source/Loaders/Windows-TSF/IMAGES/` 的四張 Windows 實際畫面。ZIP 的安裝腳本會加入目前使用者的輸入法清單；`.unsigned.exe` 也會在 Release，但本指南以 ZIP 為主。Windows 發行檔目前未簽章，未測實機安裝或 SmartScreen 畫面；若套件簽章、發行方式或設定 UI 改變，需重新核對指南。

**2026-09-20 Android 使用者文件：** `ANDROID_INSTALL.md` 說明 Google 測試群組、Google Play 封閉測試加入與安裝，三步須用同一 Google 帳號且至少保留測試資格 14 天；另含 App 首頁啟用、觸控與實體鍵盤、設定及排除問題。README 與 Android 技術 README 已加入入口。`docs/images/android-enable-ime.svg` 是明確標示的操作示意圖；六張 `docs/images/keykey-android-pixel9a-*.png` 是 Pixel 9a 實拍，系統已切到繁體中文（台灣），觸控鍵盤取自系統設定搜尋欄。使用指南不再展示 DEBUG 測試輸入框／測試記事本畫面。若改為公開發行，需重新查證並更新安裝段落；debug APK 不應作為一般使用者安裝包。GitHub `v1.2.9` Release 不代表 Google Play 上架版號已同步。

**2026-09-20 iOS 使用者文件：** `IOS_INSTALL.md` 是 iPhone／iPad 的安裝與日常使用指南，連到已上架的 App Store 產品頁；兩張 `docs/images/keykey-ios-iphone17pro-*.png` 是 iPhone 17 Pro／iOS 26.5 的實拍系統鍵盤列表與正式 App 橫向編輯器。移除以測試記事本示範輸入的圖。使用者確認台灣商店支持開發金額 NT$90；模擬器 Apple 商店帳號回傳美元 $2.99，故不可把該首頁截圖放入指南。裝置語言 `zh_TW` 不等於商店帳號地區。README 與 iOS 技術 README 已設入口。若 App 設定路徑或商店狀態改變，應重新核對官方說明及產品頁；GitHub `v1.2.9` Release 不代表 App Store 上架版號已同步。

**2026-09-20 macOS 使用者文件：** `v1.2.9` 分支的 `MACOS_INSTALL.md` 已改成一般使用者的圖文安裝與日常使用指南，包含選字、翻頁、關聯詞、切換輸入法及偏好設定；README 與安裝完成頁連回該文件。`docs/images/` 的兩張 SVG 是明確標示的操作示意圖；兩張 `keykey-macos-*.png` 是 macOS 27.0 系統鍵盤設定和輸入來源清單的實拍，取景避開個人帳號側欄，另沿用 `StoreAssets/Sources/chichi-macos.png` 的候選字截圖。截圖與 1.2.9 套件驗收須分開標示。

**2026-09-20 下一版工作：** 工作分支 `v1.2.9` 的產品與建置版號同步升為
1.2.9；`v1.2.9` tag 與 Release 現已發布並設為 latest。
已發布的 1.2.8 套件、來源與 GNOME VM 測試紀錄仍屬 1.2.8。
Linux CI 已有 tag 自動上傳流程；1.2.9 的 GNOME 實機相容性仍待擴大驗收。

**2026-09-20 五平台長文驗收：** 新增 `tests/heart-sutra.annotated.txt`（使用者提供
的完整心經注音稿，268 字）、`tests/heart_sutra.py` 與
`tests/HEART_SUTRA_FUNCTIONAL.md`。五平台執行前必須把基本及分類關聯詞庫
全部關閉，以標準注音實際逐字輸入；每平台須保存全文 capture 及 268 筆
實際候選絕對順位，`check-all` 會依共用 CIN 比對全部文字與順位。
共用字表已驗證 268/268 讀音存在；「ㄅㄛ→波」在第 18 位，須跨頁。
2026-09-20 已在已安裝的 macOS 1.2.9／macOS 27.0 TextEdit 以標準注音、關閉
全部關聯詞庫實際輸入全篇，逐字檢查 268 次選字前綴、標點與候選窗關閉，
`tests/results/2026-09-20-macos/` 保留 331 字元與標點的 capture、順位與環境紀錄；
比對器通過。`ㄙˇ→死` 在 macOS 因其餘罕字被系統濾掉而直接提交，順位仍記 1；
測試送鍵時若另送候選鍵會誤產生下一個注音，後續自動化應先檢查候選窗是否存在。
使用者原本的關聯詞設定與 ABC 輸入來源已恢復。**Windows、Android、iOS、Linux
仍無心經實際輸入紀錄**，不得標成五平台 functional test 通過。下一步依文件收集
其餘平台 capture，特別注意 iOS extension
詞庫設定與容器 App 設定不共用，以及 Linux GNOME Text Editor 的輸入路徑差異。
後續使用者指定 macOS／iOS 心經全文測試只在開發機 MacBook 執行，不加入
macOS GitHub Actions 或 iOS Xcode Cloud。macOS 本機腳本
`tests/run_macos_heart_sutra.py` 在執行前檢查已選用琦琦注音、關聯詞庫全關；
`--generate-only` 已通過九段 AppleScript 編譯。iOS 專用的
`KeyKeyHeartSutra.xctestplan` 使用 iOS 17 Simulator 和真實 keyboard extension；
2026-09-20 的全文試跑依使用者要求中斷，沒有通過紀錄或全文 capture。

已知陷阱：從受限 WSL 行程執行 `gh` 可能顯示網路與憑證失效；同一環境在
允許連線的行程可正常查詢 `v1.2.8` Release。不要據此重新登入或更換 token。

macOS、Windows、Android 與 iOS 由不同環境輪流開發，這份檔案是各平台的交接點。

**接手時：** 先讀完本檔，再讀 [BUILDING.md](BUILDING.md)。動任何 `Source/Frameworks`
或 `Source/ModulePackages` 底下的檔案前，先看「跨平台影響」。

**交接前：** 更新本檔的 TODO 與「已知陷阱」。調查出來的結論寫進來，下一個代理才
不會重跑一遍。

## 硬規則

1. commit 訊息與任何檔案內容都**不得出現 AI 工具或模型名稱**，也不要加
   `Co-Authored-By` trailer。
2. 產品內（UI、About 視窗、字串資源）**不得出現開發者或工具署名**。
3. commit author／committer 沿用 repo 既有 commit 的身分
   （`git log -1 --format='%an <%ae>'`），**不可用公司信箱**。
4. `git add` **逐檔指定**，不要用 `git add -A` 或 `git add .`。工作區常有未追蹤的
   編輯器暫存檔。
5. 以下是 BSD 條款要求，**移除會違反授權**：各原始檔的
   `Copyright (c) 2012, Yahoo! Inc.` 標頭、`LICENSE.txt`、About 視窗的出處標示、
   Info.plist 的「非 Yahoo 官方產品」聲明。README 只需連到 `LICENSE.txt`，不重複
   收錄 BSD 全文。
6. 本專案是混合授權：Android、iOS 與 Windows TSF 目錄內的原創 frontend 以目錄級
   MIT License 授權；Yahoo 舊碼與其衍生修改仍是 BSD 3-Clause，第三方素材維持各自
   授權。範圍以 `LICENSING.md` 為準，不要逐檔補 MIT 標頭，也不要把整個
   `Source/Loaders/OSX-IMK` 改標成 MIT。
7. 調查或實作 Linux 行為對標時，固定先查 macOS 的 OSX-IMK、PlainVanilla 與實際
   模組事件流，再查 Windows TSF；兩者不同時明列平台差異，不得先以 Windows 推定
   macOS 行為。第一階段功能範圍仍以 Windows TSF 已提供的功能為界。

---

## 改版號要動的地方

宣告版號的位置是 `README.md` 標題。改版時**以下全部要一起改**，否則 macOS
「關於」視窗會與 Windows 套件不一致。

### macOS — 4 個 plist，每檔 `CFBundleVersion` + `CFBundleShortVersionString`（共 8 處）

| 檔案 | 產出 |
|---|---|
| `Source/Loaders/OSX-IMK/Takao-Info.plist` | 主程式 |
| `Source/PreferenceApplications/OSX/Info.plist` | Preferences.app |
| `Source/Utilities/PhraseEditor/OSX/Info.plist` | PhraseEditor.app |
| `Source/Distributions/Takao/Installer-OSX-Help/Info.plist` | InstallerHelp.app |

`Installer/build.sh` 從主程式的 `CFBundleVersion` 取值，不需另外改。

### Windows — 2 處

| 檔案 | 位置 |
|---|---|
| `Source/Loaders/Windows-TSF/CMakeLists.txt` | `project(... VERSION x.y.z)`；同時產生 DLL／EXE 的 `VERSIONINFO` |
| `Source/Loaders/Windows-TSF/Package-Windows.ps1` | `$Version` 參數預設值 |

### Android — 2 個本機預設值

`Source/Loaders/Android-IME/app/build.gradle.kts` 的 `keyKeyVersionName` 預設值與
由 `major * 1,000,000 + minor * 1,000 + patch` 算出的 `keyKeyVersionCode` 預設值。
GitHub Actions 仍會從 `README.md` 解析並以 Gradle properties 覆寫這兩個值。

### iOS — 1 處

| 檔案 | 位置 |
|---|---|
| `Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj/project.pbxproj` | 兩個 target 共用的 `MARKETING_VERSION` |

### 文件 — 非建置輸入，但會過期

`README.md` 標題、`BUILDING.md` 與 `Source/Loaders/Windows-TSF/README.md` 裡的範例
zip 檔名。

### 改完自我檢查

```sh
# 應該只看到同一個版號
grep -rn "CFBundleShortVersionString" -A 1 --include='*.plist' Source/ \
  | grep -v Source/build | grep string
grep -n "VERSION" Source/Loaders/Windows-TSF/CMakeLists.txt
grep -n 'Version = ' Source/Loaders/Windows-TSF/Package-Windows.ps1
```

---

## 跨平台影響

改到共用區就等於同時改另一邊。**單邊測過不代表沒事。**

| 路徑 | 影響範圍 |
|---|---|
| `Source/Frameworks/` （OpenVanilla、PlainVanilla、Formosa、Manjusri） | 兩平台 |
| `Source/ModulePackages/OVIMMandarin/` | 兩平台 |
| `Source/DataTables/*.cin` | 兩平台（各自的 DatabaseCooker） |
| `Source/Loaders/OSX-IMK/` | 僅 macOS |
| `Source/Loaders/Windows-TSF/` | 僅 Windows |
| `Source/Loaders/Android-IME/` | 僅 Android；建置時唯讀 `Source/DataTables`、`DataSource/McBopomofo` 與公開的 `DataSource/chichi77Collection` |
| `Source/Loaders/iOS-Keyboard/` | 僅 iOS；建置時把已 cook 好的 `KeyKey.db` 打包進 extension |
| `Source/Branding/enter.svg` | Android 與 iOS 兩個觸控鍵盤（各自照座標描邊，不直接讀檔） |

模組註冊不對稱，看共用模組時要記得：

- **macOS** 載入 TraditionalMandarin、SmartMandarin、AssociatedPhrase、Generic、
  FullWidthCharacter、HanConvert、BopomofoCorrection、YKAFOneKey、OVAFEval
- **Windows** 只載入 TraditionalMandarin 與 AssociatedPhrase；本次產生的 SmartMandarin
  unigram 模型只接回既有 macOS frontend
- **Android** 以 Java 重作 TraditionalMandarin 的單音節組字、選字與 AssociatedPhrase
  關聯詞，直接解析 `bpmf-ext.cin` 與詞庫文字資產；目前不載入 C++ framework 或
  SmartMandarin
- **iOS** 以 Swift 重作同一組行為，但**資料層走已 cook 好的 `KeyKey.db`**（系統
  `libsqlite3`），不在執行時解析 `.cin`；同樣不載入 C++ framework

所以「SmartMandarin 裡的某段邏輯」在 Windows 上是死碼，反之 TraditionalMandarin
沒實作的功能在 Windows 就不存在。

---

## 建置前置條件

完整說明在 BUILDING.md，這裡只列最容易踩的。

### macOS

```sh
cd Source
(cd Distributions/Takao/DatabaseCooker && make)
xcodebuild -project Takao.xcodeproj -target "Takao (Loader OSX-IMK)" \
  -configuration Release -xcconfig Takao-macOS.xcconfig build
```

- **DatabaseCooker 一定要先跑。** 產出的 `CookedDatabase/KeyKey.db` 不在版控內，
  缺了 xcodebuild 會在最後 copy 步驟失敗，錯誤訊息誤導成建置環境壞掉。
- `-xcconfig Takao-macOS.xcconfig` 不可省略。該檔沒有被 pbxproj 引用，用 Xcode.app
  直接建置拿不到 SDK／arch／OpenSSL 設定。
- 目前僅支援 arm64。

### Windows

```powershell
cd Source\Loaders\Windows-TSF
cmake --preset windows-x64
cmake --build --preset windows-x64-release
ctest --test-dir .\out\build\x64-ninja --output-on-failure
cmake --preset windows-x86
cmake --build --preset windows-x86-release --target KeyKeyTsf
```

x86 也必須建，32-bit Office 需要。

### Android

```powershell
cd Source\Loaders\Android-IME
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug
```

- 使用 Android SDK 36.1 時，`compileSdk` 必須用 `release(36)` 加
  `minorApiLevel = 1` 的區塊寫法；寫成 `compileSdk = 36` 會另找未安裝的
  `platforms;android-36`。
- `bpmf-ext.cin` 與 `bpmf-punctuations.cin` 由 `generateBopomofoAssets` 在建置時
  從共用 `Source/DataTables` 複製，不要在 app 內另存一份。
- 關聯詞由 `generateAssociatedPhraseAssets` 從 `DataSource/McBopomofo/phrase.occ`
  與公開的 `DataSource/chichi77Collection/phrase.*.tsv` 複製到 generated assets；
  `generateIndexedDictionaryAssets` 再把 CIN 與關聯詞編成 `.kki`。執行時直接讀索引，
  關聯詞索引由單一背景執行緒載入；原始文字檔才是資料來源，不要手改 generated 索引。

### iOS

```sh
cd Source/Loaders/iOS-Keyboard
xcodebuild -project KeyKeyiOS.xcodeproj -scheme "chichi77 KeyKey" \
  -configuration Debug -destination 'platform=iOS Simulator,name=KeyKey iOS 26 iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

- 引擎測試不需要模擬器：`cd KeyKeyEngine && swift test`。
- **必須用 `-scheme`，不能用 `-target`** —— Swift Package 依賴只有透過 scheme 才會
  被建置。`xcshareddata/xcschemes` 內的 shared scheme 因此必須留在版控中；缺了它，
  新 clone 會由 xcodebuild 自動產生到 gitignore 的 `xcuserdata`，換機就壞。
- 新機器要先取得模擬器 runtime：`xcodebuild -downloadPlatform iOS`（約 8.5 GB）。
- 需要先有 cook 好的 `KeyKey.db`；它會被複製進 **extension** bundle，不要放進容器
  App，否則 10 MB 會打包兩次。
- Xcode Cloud 的 `ci_scripts` 必須位於 `Source/Loaders/iOS-Keyboard/`（與 xcodeproj
  同層），`ci_post_clone.sh` 也必須保留 executable bit。腳本會在乾淨 checkout cook
  `KeyKey.db`，再以 `CI_BUILD_NUMBER` 搭配 Apple Generic Versioning 同步 App 與
  extension 的 build number；不要把 cook 後的資料庫提交進版控。
- 容器 App target 的 `COPY_PHASE_STRIP` 必須保持 `NO`。Keyboard extension 在自己的
  target 已完成 Release strip 與簽章，Embed Foundation Extensions 階段若再次 strip，
  Xcode 只會跳過並警告 `not stripping binary because it is signed`；這個設定不會關閉
  extension 自己的 `STRIP_INSTALLED_PRODUCT`。
- 配色只在 `Keyboard/Palette.swift`，全部是 `UIColor(dynamicProvider:)`，深色模式
  跟著系統走。淺色值與 Android 相同，深色值只有 iOS 有。
- App 圖示來自 `Source/Branding/chichi77.png`，縮成 1024×1024 放在
  `ContainerApp/Assets.xcassets/AppIcon.appiconset`（單一尺寸，Xcode 自行衍生）。
- 兩個 target 各有 `PrivacyInfo.xcprivacy`，也都宣告 `UserDefaults`（required reason
  `CA92.1`）：extension 自己保存按鍵音、候選底色與關聯詞庫，容器 App 自己保存實體
  鍵盤編輯器的關聯詞庫；只有首次使用與支持 entitlement cache 透過 App Group 在兩個
  target 間共用。兩份都宣告不追蹤、不收集。

---

## 已知陷阱（不要重複調查）

- **阿拉伯數字＋單位不能靠現有詞庫窮舉生效**：SmartMandarin 直接送出數字，
  cooker 只擷取漢字；分類關聯詞的首字也必須是漢字。`numeric-unit-lexicon.tsv`
  因此只列中文數字形式。大寫數字如「參仟／壹萬」與一般寫法同音，資料能提供
  候選及特定上下文 bigram，但孤立輸入時仍可能排在「三千／一萬」後面。
- **macOS 記憶體與 KeyKey.db 不能只看檔案大小**：2026-09-20 review 確認
  直式候選 `CVVerticalCandidateController.mm` 的 `NSAttributedString *c`
  及通知文字有未平衡的 alloc ownership；詞彙編輯器的
  `userPhraseDBDictionaryAtRow:` 另遺漏 `delete select`，隔離呼叫 1,000 次
  留下 1,000 個 statement、約 3.39 MiB，並使 SQLite close 回 SQLITE_BUSY。
  2026-09-20 已修正這三處 ownership；修後隔離重複 1,000 次留下 0 個
  statement、close 回 SQLITE_OK，arm64 Release build／analyze 通過；其他舊碼
  仍有 analyzer warning。現有 1.2.8
  行程實測 footprint 55.1 MiB、leaks 3.01 MiB；不能
  把所有用量都歸給資料庫。新 cook 的 db 9.812 MiB，4 KiB + VACUUM 副本為
  9.141 MiB（-6.85%）；WITHOUT ROWID 實驗為 7.352 MiB，但 iOS 明確依賴
  `ORDER BY rowid`，不可只換 db。系統 SQLite 預設 cache_size 在此 Mac 是
  2000 pages，與上游常見的 -2000 不同；本機 512 KiB 建議預算的資料層
  抽樣已完成，仍需真實 IMK 與跨平台回歸。完整證據、其他候選窗問題與
  後續順序見 [macOS review](MACOS_CODE_REVIEW.md)，不要把副本實驗當成
  已套用的產品優化。
- **五平台記憶體策略不能只改 KeyKey.db**：2026-09-20 使用者要求綜合各平台
  使用情況，並認為 db 瘦身影響有限；目前已修 macOS 已確認的洩漏，接著量測
  長時間快取成長，保留資料格式。Windows TSF 直接編譯 SQLite 3.6.11，
  原生 cooker 仍讀共用 Schema.sql；隔離 probe 確認 WITHOUT ROWID 副本回
  malformed schema，cache_size=-512 代表 512 pages 而非 KiB，不可直接搬用
  Mac 設定。iOS CandidateStore 與 Android IndexedDictionary 的候選 cache
  均沒有淘汰機制，需量不同讀音，不能只重複同一讀音。Android 使用 .kki，
  Linux 使用 CIN／詞庫 maps，都不讀 KeyKey.db；Linux 已共享字典，但啟動
  會解析全部輸入法及詞庫。注音專用 db 副本雖可由 9.812 降至 3.082 MiB，
  此為安裝空間可行性實驗，並非等量 RAM 收益，尚未改任何平台打包流程。
- **Windows TraditionalMandarin 已有逐音節連續輸入與錯誤鍵處理**：候選窗開啟時若
  直接按下一個合法注音鍵，`candidateNonPanelKeyReceived` 會先提交目前反白候選，再以
  該鍵開始下一個 reading；這不是 SmartMandarin 的整句組字。reading 中的無效一般鍵
  會提示錯誤並保留 reading，Ctrl／Alt 等應用程式快捷鍵則放行。Windows 有五布局
  設定，Linux 第一階段須維持相同選項。Windows module package
  只註冊 TraditionalMandarin 與 AssociatedPhrase，雖 cooker 含 correction table，
  實際未載入 BopomofoCorrection，所以 Linux 也不需實作注音自動修正。
- **五布局錯誤鍵使用裸 `\` 作共同 E2E 錨點**：macOS TraditionalMandarin 在 reading
  非空時會吃掉無法組入的普通鍵、保留 reading 並 beep；Ctrl／Alt 組合則放行且不改
  reading。Windows 沿用同一 module 行為，TSF 另在送入引擎前排除 Ctrl／Alt 應用程式
  快捷鍵。裸 `\` 不在 Standard、ETen、ETen26、Hsu 或 Hanyu Pinyin 的 reading key
  集合內，且不會觸發只接受 `Ctrl+\` 的中英切換，因此可跨五布局固定這條契約；英文
  負控制必須保留 literal `\`，才能證明事件確實走過真 App。
- **Windows TraditionalMandarin 輸入明示聲調後立即查詢**：二、三、四、輕聲鍵由
  `hasToneMarker()` 觸發 `queryAndCompose()`，不需再按 Space。Linux 五布局亦須如此；
  無聲調的一聲仍以 Space／Enter 查詢。真實按鍵負控制要同步移除聲調後多餘空白，
  否則會把候選翻到下一頁，掩蓋實際差異。
- **授權按來源而不是路徑歷史判斷**：`Source/Loaders/Android-IME`、
  `Source/Loaders/iOS-Keyboard` 與 `Source/Loaders/Windows-TSF` 的原創 frontend
  由各目錄 `LICENSE.txt` 套用 MIT，不需逐檔標頭；其中引用、複製或打包的 Yahoo、
  OpenVanilla、McBopomofo、Gradle wrapper 與資料庫不會因此變成 MIT。
  `Source/Loaders/OSX-IMK` 雖在 2026 重整路徑，但大量檔案與 Yahoo 原碼相同或由其
  修改，整體仍維持 BSD。全新且未含舊碼的 macOS 檔案若要用 MIT，必須逐項加入
  `LICENSING.md`，不能用整個目錄覆蓋。
- **macOS framework 的 Headers 封印**：framework target 在 `Headers` 還在的狀態下簽好
  自己的產物，app 的 Copy Files phase 再把 header 砍掉，封印就留著已經不存在的檔案，
  `codesign --verify --deep --strict` 必定回報 `a sealed resource is missing or invalid`，
  notarize 也會被退。已由
  `Installer/build.sh` 在 stage 之後、簽章之前刪掉 `Versions/A/Headers` 與最上層的
  `Headers` symlink 處理掉（header 對執行期沒有用途）。本機未提供 Developer ID
  時也必須重新 ad hoc 簽 nested frameworks／helper apps／外層 app，否則移除
  headers 後封印失效；2026-09-20 本機 package 已補此步並通過 deep strict verify。
  修掉之前 `build.sh` 的
  `DEVELOPER_ID_APPLICATION` 分支其實跑不完：`set -euo pipefail` 加上必定失敗的
  `--verify --deep --strict` 會直接中斷整個腳本。
- **舊 macOS TSM component ID 有三份同步點**：雖然 `Source/Loaders/OSX-TSM` 已不在
  目前支援的建置路徑，`io.github.polobread.inputmethod.chichi77.tsm` 仍同時出現在
  component plist、`Component.m` 與 `Source/Takao.xcodeproj/project.pbxproj`。pbxproj
  的 `TSMC_BUNDLE_ID_LENGTH` 是字串長度的十六進位 byte，目前 44 bytes 必須寫成
  `$"2c"`；只換 ID 不改長度會產生損壞的舊式 TSM 資源。
- **macOS 首次安裝看不到輸入法**：Text Input Services 只在登入時掃
  `/Library/Input Methods`，換過 bundle id 就等於首次安裝，必須登出再登入，
  `lsregister` 手動註冊無效。確認是否註冊：
  `defaults read com.apple.HIToolbox | grep -c chichi77`。`distribution.plist` 刻意不設
  `RequireLogout`：完成頁要求首次安裝者方便時自行登出，但升級由 postinstall 結束舊
  process 後立即生效，不應每次安裝都中斷工作階段。
- **macOS pkg 安裝**：`pkgbuild` 預設把 app bundle 標成 relocatable，`installer`
  會把 payload 寫到別處卻回報成功。已用 `Installer/build.sh` 的
  `BundleIsRelocatable false` 處理；2026-09-20 本機 `pkgbuild --analyze` 未輸出該欄位，
  腳本已改成缺席時新增，不可只用 PlistBuddy `Set`。安裝後仍務必
  `ls -ld "/Library/Input Methods/chichi77 KeyKey.app"` 確認。
- **Windows ZIP 安裝**：ZIP 版必須先完整解壓縮、複製到本機 `C:\` 路徑，才執行
  `Install.cmd`；UAC 提升權限後可能存取不到網路磁碟／NAS／UNC 來源。NSIS EXE 是
  獨立離線安裝器，不受這個解壓縮限制，也不要再包進另一層 ZIP 才交給 Partner Center。
- **Windows NSIS 完成頁只在必要時要求重啟**：`Delete /REBOOTOK`／`RMDir /REBOOTOK`
  遇到被鎖定的舊檔才設 reboot flag，完成頁此時預設「稍後重新啟動」；一般安裝不應
  主動要求重啟。互動模式預設開啟琦琦設定，另可選開啟 `ms-settings:regionlanguage`；
  `/S` 靜默安裝不可啟動兩者。
- **Android Studio agent shell 的 x86 preset 可能撞到重複環境變數**：這個環境同時
  傳入 `Path` 與 `PATH` 時，Visual Studio generator 的 MSBuild 會以 MSB6001／
  `ArgumentException` 停在編譯器偵測。不是 x86 原始碼錯誤；用
  `VsDevCmd.bat -arch=x86 -host_arch=x64` 後以 Ninja 設定 `out/build/x86-ninja`
  可正常完成 DLL、測試與連結。
- **Windows TSF 的 Ctrl 白名單必須精確**：`IsInputMethodControlKey` 只放行
  `bpmf-punctuations.cin` 保證存在的 Ctrl+0／Ctrl+1、Ctrl+標點，以及
  Ctrl+Alt+字母／五個標點；一般 Ctrl+C、Ctrl+方向鍵、Alt 快捷鍵仍交給應用程式。
  Ctrl+0／Ctrl+1 會與瀏覽器縮放／分頁及 Excel 快捷鍵衝突，這是目前依產品需求
  選擇由輸入法優先處理的行為。不要把白名單擴成所有 Ctrl／Alt 鍵，否則
  `OnTestKeyDown` 與實際引擎處理結果不一致時，某些 host 會把按鍵吃掉。
- **Windows TSF 必須監看外部游標移動**：`ITfTextEditSink::OnEndEdit` 在 selection
  離開 composition range 或無組字候選的 anchor 時清掉引擎狀態。移除這個 sink
  會讓滑鼠／應用程式移動游標後仍沿用舊 range，Enter 可能只移動游標而文字留在
  原行。切換 document context 時也必須同步重掛 sink。
- **Windows TSF 單按 Shift 依賴 key-up opt-in**：`OnTestKeyUp` 必須先回 TRUE，TSF
  才會呼叫 `OnKeyUp`；目前採 Windows-IMM 相同的 300ms 單按判定。Shift 與其他鍵
  組合時要取消 pending，不能誤切中英文模式。
- **Windows 設定共用 PlainVanilla plist**：一般設定寫在
  `%APPDATA%\chichi77 KeyKey\org.openvanilla.chichi77-keykey.windows.plist`，必須保留
  loader 已有的 `PrimaryInputMethod`、`ActivatedAroundFilters` 等陣列，不能整檔覆寫。
  注音與關聯詞則各自使用 `TraditionalMandarin.plist`、`AssociatedPhrase.plist`。
- **Windows 的 Big-5 候選限制需要自訂 encoding service**：舊的
  `PVDefaultEncodingService` 只宣告 UTF-8，會把 TraditionalMandarin 設定的 `BIG-5`
  清空，讓「使用全字庫罕用字」永遠無法關閉。Windows TSF 現在用 CP950 搭配
  `WC_NO_BEST_FIT_CHARS` 判斷候選是否真能以 Big-5 表示，不要改回預設 service。
- **Windows 候選窗的 DPI 由 host 決定**：TSF DLL 載入應用程式行程，不能呼叫
  `SetProcessDpiAwareness*` 改掉 host 的 DPI 模式。候選窗以 owner 的
  `GetDpiForWindow()` 建立對應字型並縮放 padding／間距／邊框，另以
  `WM_DPICHANGED` 處理跨螢幕移動。DPI-unaware host 會回報 96 DPI 並由系統整體
  virtualization；不要再乘一次實體螢幕比例，否則會雙重放大。
- **Windows 候選窗比例可覆寫 host DPI**：一般設定的「比例」預設跟隨 Windows；
  選擇 `75%` 到 `350%` 時是候選窗自己的絕對縮放比例，讓高 DPI 螢幕可以把候選窗
  調得比系統比例小。設定值存為 `CandidateWindowScalePercent`；只有清單內的值有效，
  缺少或無效時回到跟隨 Windows。自訂值會用 `GetScaleFactorForMonitor` 對 host 回報
  DPI 做反向正規化，抵消 DPI-unaware／system-aware host 的 bitmap virtualization；
  不可直接把自訂百分比當 DPI，也不可再和 host DPI 相乘。
- **macOS 候選窗比例沿用同一個設定鍵與選項**：Preferences 的一般設定以程式建立
  「跟隨顯示器、75%–350%」選單，值同樣存為 `CandidateWindowScalePercent`。AppKit
  已負責 point 到 Retina pixel 的映射，所以「跟隨顯示器」維持原本 1 倍 point 尺寸；
  指定百分比則以 content view 的 bounds 等比例放大直式與橫式候選窗，不能再乘
  `backingScaleFactor`，否則 Retina 螢幕會雙重放大。設定在下次輸入法 activate 時套用。
  比例列與 XIB 原有的「可隱藏部分輸入法模組」說明佔用同一列；建立控制項時必須先把
  說明移到比例列上方並縮短模組清單，否則比例 popup 會直接蓋住說明文字。
  三份 `MainMenu.xib` 都必須把 `_candidateWindowStyleMatrix` 接到 `TakaoGlobal`；簡中曾
  漏接，會讓程式建立的比例列使用零座標並且無法保存直／橫式選擇。
- **macOS 標準 UI 要使用系統動態色**：Preferences、PhraseEditor、About、搜尋輸入框、
  符號表及候選提示的 window/table/text/header 不可寫死 calibrated white、black 或 gray；
  分別使用 `windowBackgroundColor`、`controlBackgroundColor`、`textBackgroundColor`、
  `controlTextColor`、`secondaryLabelColor` 與 `headerColor`。三份語系 XIB 必須一起改。
  黑底白字候選窗、通知窗等自訂浮動 UI 是刻意的固定主題，前景與背景必須成對設定，
  不要只把其中一色改成動態色。
- **macOS 直式候選布局與捲動要在顯示前完成**：先設定視窗的物理 frame 與未縮放
  content bounds，再明確設定子視圖 frame；最後設定選取、校正 clip view 位置並重畫。
  換頁／換候選／隱藏再顯示回到頂端，同頁重畫保留合法的手動捲動；內容已全部放得下
  時必須將殘留 offset 限制為零。這些是防護，不能直接當作舊截圖的已證實根因。
  2026-09-20 使用實際 controller／NIB 的隔離 AppKit 測試，新版 100%、200%、350%
  與切換倍率後的首列垂直範圍正常，200% 離屏渲染可見第 1–9 列；舊 `a3b838f`
  在首次 200% 及 100%／150%／200% 切換也未重現「從第 3 列開始、底部留白」。
  使用者確認截圖來自先前版本，並指出周圍文字仍是正常大小；不要把 200%
  當作主要原因。尚未重現原始操作序列，不得宣稱該截圖問題已通過修復前後對照。
  2026-09-20 後續隔離測試於 100% 人為建立舊 table 高度及捲動位置，新控制器
  重畫後可恢復零 offset；大字級有捲軸時同頁保留位置、翻頁／換內容／隱藏重開歸零，
  鍵盤反白末列可見。隔離測試未包含實際 IMK 事件與滑鼠。
- **macOS 直式候選的提示列與候選內容要分開計算寬度**：候選欄只需按鍵欄、最長候選、
  cell padding 與外框；`SHIFT + 數字鍵` 等 prompt 另以其文字寬度和翻頁按鈕空間決定
  minimum window width。不可先把 prompt 寫進候選 `_width` 再固定加 50 點，也不可交給
  `NSTableView sizeToFit` 重新分配欄寬，否則外框留下大塊空白但提示仍可能被截斷。
  自訂比例改變 window frame 時要暫停 content view 的 subview autoresizing，並先以未縮放
  bounds 明確排好 scroll view、table、prompt 與翻頁控制，避免 AppKit 依前一次實體 frame
  累積縮窄子視圖。
- **macOS 輸入法浮動視窗不可蓋過系統安全 UI 或搶焦點**：候選窗、提示泡泡與一般
  浮動窗使用 `NSStatusWindowLevel`，並加入所有 Space／全螢幕輔助行為；只有需要互動的
  字典視窗可成為 key window。候選窗顯示用 `orderFront:`，不要改回
  `makeKeyAndOrderFront:`。多螢幕定位必須用完整的 `NSPointInRect` 同時判斷 x、y，否則
  上下排列的螢幕會選錯 visible frame。
- **macOS OneKey 啟動程式不可經過 shell**：`LaunchApp` 的值以 tab 分隔程式名稱／路徑
  和參數，必須交給 `NSWorkspaceOpenConfiguration.arguments`；不要拼成 `open ...` 再呼叫
  `system()`，否則設定值中的 shell metacharacter 會被執行。
- **Windows 語言列通知可能重入或跨執行緒**：2026-08-24 的 Android Studio
  `studio64.exe` 在 `Ctrl+Space` 切換模式時連續三次以 `0xc0000005` 崩潰；WER 的
  faulting module 是 `KeyKeyTsf_x64.dll`，固定 offset `0xA087` 經同版 map 確認為
  `LangBarButton::update()` 讀取已失效物件。`refreshLangBar()` 必須在鎖內取得每個
  button 的暫時 COM reference，再於鎖外通知；button 的 sink vector 也必須同步，
  且 `OnUpdate` 不可在持鎖時呼叫（會重入 `UnadviseSink`／`Deactivate`）。不要改回
  未同步的 raw pointer 逐一呼叫。
- **三平台詞庫顯示名稱以共用 mapping 為準**：唯一來源是
  `DataSource/AssociatedPhraseCollectionNames.tsv`，目前把 `McBopomofo`、`chinese`、
  `general` 顯示為「小麥注音」、「中文文學」、「一般生活」。macOS 的
  `collection-name.rb`、Windows 的 `DatabaseCooker.cpp` 與 Android generated assets
  都必須讀同一檔；不要修改分類 TSV 的分類欄位，也不要在 frontend 另寫名稱常數。
- **Android 主程式不要用 Java `record`**：AGP 9.2.0 曾把 record 轉譯成
  `com.android.tools.r8.RecordTag`，卻未把該合成類別包進 debug APK；Android 17
  會在建立 `BopomofoImeService` 時以 `NoClassDefFoundError` 崩潰。`assembleDebug`
  與 JVM 單元測試都不會發現。現行程式改用一般 immutable class；工具鏈修正並經
  實機驗證前不要改回 record。
- **Android 選字不可先結束 composing**：`InputConnection.finishComposingText()` 會把
  當前注音讀音直接確定送出；若再 `commitText()` 候選字，輸入區會變成
  `ㄋㄧˇ你`。選字時應直接以 `commitText()` 取代 composing region，之後再依引擎
  狀態更新或結束組字。
- **Android 候選翻頁是循環式**：觸控鍵盤的 ▲、▼、左右滑動，以及外接鍵盤的
  `Page Up`、`Page Down` 與空白鍵都共用 `changePage()`；第一頁的上一頁是最後一頁，最後一頁
  的下一頁是第一頁。空白只有在尚未開啟候選時才用來查詢讀音或輸入空格。
- **Android TraditionalMandarin 選字鍵是 `1–9`**：與共用模組
  `OVIMTraditionalMandarin.cpp` 的 `setCandidateKeys("123456789")` 一致，每頁 9 個。
  觸控版有獨立候選列，必須直接點候選，四排注音鍵即使候選開啟也仍是注音輸入；
  外接鍵盤的一般候選才用 `1–9`。關聯詞依 Windows 行為用外接鍵盤 `Shift+1–9`
  選取，未按 Shift 的數字須關閉關聯詞並交給標準注音鍵位；`0` 不是選字鍵。
- **Android 軟體鍵盤要保留底部系統區**：targetSdk 36 的 IME 視窗會延伸到導覽區，
  系統的多國語系地球鍵與手勢橫條可能蓋住最底列。繪製內容須靠上，底部空白留給
  系統控制項；直式固定保留 40dp、橫式固定保留 35dp，不要把按鍵重新畫滿整個
  view 高度。
- **Android 觸控鍵盤是 11 欄注音版面**：直橫式都由候選列、四排 11 個等寬輸入鍵與
  一排功能鍵組成；四排依序結束於 `ㄦ`、`@`、Emoji、Shift。功能列的長空白是刻意
  的唯一寬鍵。注音鍵必須同時顯示注音與實體鍵位（如 `ㄅ／1`、`ㄉ／2`）。100% 時
  橫式內容為一般比例的 230dp；直式與橫式可各自調為 50%–200%，但 40dp／35dp
  系統區固定不縮放，
  實體鍵盤候選列與浮窗也不套用此比例。六排使用橫式小字級，不要恢復舊的左右分割候選。
  左下模式鍵隨目前模式分別顯示「英/數」、「數/ㄅ」、「ㄅ/英」，不要改回「中」或固定
  「中/英/數」。
- **Android 字典索引由文字來源產生**：`app/tools/DictionaryCompiler.java` 會產生 `KKI1`
  格式；core 在 IME 建立時讀索引，關聯詞索引在背景載入並於查詢時才解碼候選。
  修改解析、過濾、排序或人名 exclusion 時，必須同步更新 compiler 及逐項一致性測試；
  不可提交 `app/build/generated` 內容或把 `.kki` 當成手工資料來源。
- **Android 的 `EditorInfo` 只限制初始觸控模式**：一般文字與 URI 一開始使用完整
  三模式；Email、password／ASCII 先用英文精簡模式，phone、number（含 decimal、
  signed）、datetime 先用數字精簡模式。精簡模式不可停用 MODE；第一次按 MODE 要先把
  policy 解鎖，再依完整 `ㄅ → 英 → 數` 順序切到下一模式，之後同一 editor session
  不得因 `onStartInputView` 或 restarting input 重新鎖定，只有離開欄位才重設。
  URI 即使帶 `IME_FLAG_FORCE_ASCII` 也維持完整模式，讓網址列可輸入中文搜尋。
  USB／藍牙實體鍵盤同樣維持完整字元與快捷鍵，不要在 `onKeyDown` 用 `inputType`
  擋實體鍵；欄位最後接受哪些內容仍由 App 驗證。
- **Android 測試完成以完整 AVD 計畫為準**：Android IME 行為、版面、設定、字典或建置有變更時，
  必須依 `docs/ANDROID_VIRTUAL_DEVICE_TEST_PLAN.md` 在 API 26、28、30、33、35、37
  六台 AVD 跑完 A–L 矩陣；只跑 JVM test、安裝 APK、打出一個字或只測實體鍵盤都不算完成。
  debug-only `ImeTestActivity` 是欄位型態與 Enter action 的 host，不能加入 release source set。
- **Android 軟 Enter action 與實體 Enter 必須分流**：直橫式觸控 Enter 在沒有 reading／
  一般候選時，依 `imeOptions & IME_MASK_ACTION` 呼叫 `performEditorAction(DONE/NEXT/SEARCH/
  SEND/GO/PREVIOUS)`，並顯示中文 action 名；若 App 提供 `actionLabel`／`actionId`，要顯示
  自訂標籤並以該 ID 呼叫 action。`IME_FLAG_NO_ENTER_ACTION`、無 action 或 App 拒絕時才
  送 Enter key event。關聯候選已是額外推薦，不是待確定的組字；Enter 必須關閉關聯候選後
  直接執行 action，不可插入反白關聯詞。外接鍵盤 Enter 永遠走 key event，不可套 editor action，
  也不可選入關聯詞。
- **Android 外部 selection 變動必須清掉組字狀態**：`onUpdateSelection` 在 reading 或
  候選存在時偵測游標／選取變更，重設引擎並結束 composing，否則下一鍵會在新游標沿用
  舊讀音。為避免把游標拉回去或刪錯 App 文字，已顯示的 raw 注音會由
  `finishComposingText()` 留在原處；只清引擎狀態。IME 自己的 `commitText`／
  `setComposingText` 也會觸發 callback；必須以短期
  mutation guard 略過自己的更新，而且只在真的修改 InputConnection 時啟用，否則按空白
  開候選後立刻移動游標可能被誤判為自己的 callback。
- **Android 觸控按鍵預覽不新增 hit target**：`BopomofoKeyboardView` 只為單一文字、注音
  與符號鍵畫 1.4 倍 Canvas overlay，滑出原鍵、放開或取消即隱藏；功能鍵、候選列與實體
  鍵盤模式不顯示。設定鍵 `key_preview_enabled` 預設 true，變更後由既有
  `ime_settings` listener 立即刷新；不要讓預覽框本身可點擊或改變原按鍵範圍。
- **Android 觸控 Shift 不等於實體 Shift**：注音版按 Shift 只暫時顯示英文小寫，
  並把雙標籤從「注音在上、鍵位在下」交換成「鍵位在上、注音在下」，輸入下一個
  觸控字元後立即回注音；由功能列切入的英文版按 Shift 才會持續切換大小寫，且大寫時
  數字排換成 `!@#…`。數字符號模式的 Shift 不離開該模式，只切換兩套各 44 鍵的
  符號頁。實體 Shift 只當該次硬體按鍵的修飾鍵，不能改變觸控版面。
- **Android 聲調符號要單獨放大並校正位置**：`ˊˇˋ˙` 是 spacing modifier letter，
  在系統字型中以一般注音字級繪製會顯得過小，直接放大又會因字型 baseline 偏高而超出
  按鍵。`drawBopomofoKey` 固定將四個聲調放大 1.8 倍，再依實際 glyph bounds 下移，
  讓上緣與一般注音符號對齊。直式鍵位提示使用共同的固定 baseline，讓聲調鍵下方的
  `3467` 與其他鍵的 `125890` 對齊；不要把兩個標籤重新合成單一字串繪製。
- **Android 符號與 Emoji 候選各固定 10 頁**：「符」開啟 90 個標點、括號、數學、
  單位、貨幣、箭頭及圖形符號；第三排 Emoji 開啟 90 個常用表情，兩者每頁 9 個。
  與文字候選共用翻頁與空白循環；觸控直接點候選，外接鍵盤一般候選仍可用 `1–9`
  選取，不是 AssociatedPhrase 關聯詞。
- **Android 首頁與設定頁要避開前相機挖孔**：targetSdk 36 的 Activity 會 edge-to-edge，
  兩頁由 `UiInsets` 把 system bars 與 display cutout 加到既有 padding；不要改回固定
  上邊距。首頁第三個按鈕開啟震動設定，`HapticSettings` 使用
  `0/1/2/3/5/10/20/30/50/100ms` 十段並以 SharedPreferences 共用給 IME；舊值對應
  最接近的一段，等距時選較短的一段。`0` 表示關閉，震動需要 manifest 的 `VIBRATE` 權限。
- **Android Backspace 要以完整文字圖形為單位**：有注音 reading 時由引擎逐步刪除
  聲調、韻母、介音、聲母，候選開啟也不可只關候選而不退音；reading 為空時才由
  `TextDeletion` 計算游標前完整 grapheme 的 UTF-16 長度，讓代理字元、變體選擇符、
  膚色與 ZWJ Emoji 一次刪乾淨，不要改回固定 `deleteSurroundingText(1, 0)`。刪掉最後
  一個注音 component 時也不可呼叫 `finishComposingText()`，因為它只移除 composing
  樣式並原樣保留 `ㄅ`；引擎必須回報丟棄 composing text，讓 loader 以
  `commitText("", 1)` 取代並結束 composing region。
- **Android 外接鍵盤候選列也要保留底部系統區**：候選列有 12 個等寬按鍵：9 個候選、
  Emoji、`ㄅ／英` 與 `半／全`；後兩鍵不可再塞進同一欄縮成半寬。語言鍵點擊等同
  `Ctrl+Space`，右格點擊等同 `Shift+Space`。輸入模式格只有兩種，NUMBER 也顯示為
  `英`，點擊後切到 `ㄅ`；不可加回第三種「數」。候選列不顯示 ▲／▼，
  翻頁使用 `Page Up`／`Page Down` 或空白。直式／橫式分別在下方保留 40dp／35dp，
  避免 Android 的多國語系地球鍵遮住控制項。Emoji 必須在沒有中文字候選時仍可按。
  所有候選角標都固定顯示 `1–9`；
  關聯詞雖以 Windows 式 `Shift+1–9` 選取，也不可把角標改成 `!@#$%^&*(`。
- **Android 浮動候選依賴 App 回報游標座標**：設定啟用後以
  `requestCursorUpdates()`／`onUpdateCursorAnchorInfo()` 跟隨插入點，候選 Window
  必須附掛 IME token、不可取得焦點，否則觸控選字會讓原文字欄位失焦。部分自訂 editor
  不回報 `CursorAnchorInfo`，此時固定退回可用畫面底部中央，不要因此恢復底部候選列。
  浮動模式只把 IME input view 留成 1dp 以維持 window token；這不是待清理的空白。
  垂直窗用上下移動反白／左右換頁，水平窗相反，Enter 選反白，ESC 取消整個讀音。
  若系統拒絕附掛浮窗，或 IME token 經約 1.5 秒重試仍拿不到，必須自動關閉浮窗設定、
  記錄並在設定頁顯示原因，直接改用一般實體鍵盤候選列；原因持續保留至使用者重新勾選，
  重新勾選才清除並允許再試一次，不能靜默吃掉候選。
- **Android 外接鍵盤的 Ctrl 快捷鍵要先於修飾鍵攔截判斷**：`Ctrl+Space` 只在注音與
  英文間切換，`Ctrl+,`／`Ctrl+.` 輸入全型 `，`／`。`；`Ctrl+0` 與 `Ctrl+1` 則比照
  macOS `OVIMTraditionalMandarin.cpp` 的 `_punctuation_list`，開啟與觸控「符」相同的
  90 個符號候選。組字 reading 尚未清空時，標點與符號快捷鍵須保留 reading，不可
  丟掉使用者正在組的注音。快捷鍵的 keydown 與 keyup 都要吃掉，長按不可重複觸發。
- **Android 實體鍵盤全半形比照 Windows**：`Shift+Space` 切換 `半／全`，切換時保留
  目前 reading／候選；全形模式將實體鍵盤提交的 ASCII 空白映成 U+3000，`!`–`~`
  依序映成 U+FF01–U+FF5E，非 ASCII 與中文字不變。這個狀態不影響觸控鍵盤。
  `Shift+Space` 必須先於一般 Space 處理，keydown／keyup 與 repeat 都要吃掉；即使使用者
  先放開 Shift，按住 Space 產生的 repeat 也不可漏成空白。
- **Android 關聯詞庫是固定 30 個文字資產**：`generateAssociatedPhraseAssets` 從
  `DataSource/McBopomofo/phrase.occ` 加入顯示為「小麥注音」的基本詞庫，再從公開的
  `DataSource/chichi77Collection` 加入 29 個 `phrase.*.tsv`。設定首次預設
  `McBopomofo`，但 SharedPreferences 已存在空集合時代表使用者
  刻意全部關閉，不能偷偷恢復預設。基本詞庫中與三個 `people-*` 詞庫重疊的人名必須先排除，
  否則關閉人名詞庫仍會漏出候選。
- **Android 關聯詞只在確定單一中文字後開啟**：候選內容是已輸入首字後的詞尾，
  選取時只 commit 詞尾；輸入下一個注音鍵會關閉關聯詞但不可自動送出第一個詞尾。
  30 個全不選時 `AssociatedPhraseDictionary.load` 必須直接回空詞庫，不解析資產。
- **macOS 拿不到 Ctrl+Shift+標點**：macOS 不會把 Ctrl 組合的 shift 變體交給輸入法，
  `Ctrl+,` 與 `Ctrl+Shift+,` 都以 `,` 送達，`charactersIgnoringModifiers` 也一樣。
  所以 `bpmf-punctuations.cin` 的 `_ctrl_:`、`_ctrl_"`、`_ctrl_<`、`_ctrl_>`、
  `_ctrl_?` 在 macOS **無法觸發**，`Ctrl+[`、`Ctrl+]` 也根本收不到。已實測確認，
  不要再嘗試用 `charactersIgnoringModifiers` 或改寫 `unicharCode` remap 表去救。
  這幾條在 **Windows 仍可用** —— TSF loader 的 `PrintableAsciiFromVirtualKey`
  是從 virtual key 推導字元（`VK_OEM_1` + shift → `:`），不受此限。macOS 端的
  白名單只列真的收得到的組合，`OVCIsInputMethodCtrlKey` 的註解有完整說明。
- **選字鍵的 US 佈局隱性契約**：`OVAFAssociatedPhrase` 的聯想詞選字鍵表
  `"!@#$%^&*("` 依賴上游把鍵盤正規化成 US——macOS 靠 `activateServer:` 的
  `overrideKeyboardWithKeyboardNamed:`（預設 `com.apple.keylayout.US`），Windows 靠
  `PrintableAsciiFromVirtualKey` 的 `")!@#$%^&*("` VK 對照。三處必須一致但彼此看
  不到對方，改任一處要一併檢查。目前是正確的，不要當成 bug 去「修」。
- **iOS extension 收不到實體鍵盤按鍵**：`UIInputViewController` 的
  `pressesBegan`／`pressesEnded` 不會被呼叫，第三方鍵盤也只能在自己的 input view 內
  繪製。Android 的系統級實體鍵盤支援與浮動候選窗在 iOS **做不到**，不要再嘗試。
  iOS 容器 App 另有「實體鍵盤編輯器」：前景 App 的非文字 responder 以
  `pressesBegan` 攔截按鍵，直接唯讀內嵌 `Keyboard.appex` 的同一份 `KeyKey.db`，完成後
  直式可用固定底部按鈕或 `Ctrl+C`／`⌘C` 複製全文，並可用分享按鈕或
  `Ctrl+S`／`⌘S` 開啟系統分享面板；`Ctrl+K`／`⌘K` 開啟清除全文確認窗，
  並以 Enter 確認、Esc 取消。候選窗固定直排
  1–9，不放觸控上一／下一頁按鈕；一般候選
  以 `1–9` 選取、關聯詞以 `Shift+1–9`
  （`!@#$%^&*(`）選取；沒有候選與組字時，方向鍵移動容器編輯器自己的可見插入游標。
  控制列不重複顯示「準備輸入／組字」，有候選時把 `1/n` 頁碼放在第 9 個候選字下方；右側固定提供
  ㄅ／英、半／全、符號與 `🙂` 按鈕；詞庫與
  Esc、Backspace、Enter、四方向、空白等觸控備援鍵置於候選窗右側。
  橫式固定由左到右使用輸入區、1–9 候選區、操作按鍵區、清除／複製／分享文字四欄，
  最右欄三個動作按鈕由上到下排列；iPad 保留方向鍵與空白鍵，iPhone 橫式高度不足時可收起
  方向鍵與空白鍵。4.7 吋 iPhone SE 的直式輸入區使用緊湊高度，仍須讓 1–9 候選、頁碼與
  全部操作鍵留在固定底部動作列上方。候選內容只能改文字與反白，不得改欄寬或高度，直式
  轉橫式再轉回直式時各區塊也必須精確恢復原尺寸。
  一般候選狀態下
  ↑／↓逐列移動、←／→換頁；快捷鍵說明只在點擊右上角資訊按鈕時顯示。容器編輯器能獨立選擇並保存
  關聯詞庫，但 extension 不開完整取用，因此兩邊設定不可宣稱同步。這只能在琦琦 App
  內工作，不可宣稱能在其他 App 直接輸入。
- **iOS 關聯候選按 Enter 不可選入反白詞尾**：關聯詞已是確定單字後的額外推薦，觸控
  keyboard extension 與容器實體鍵盤編輯器都必須先關閉關聯候選，再把 Enter 當作換行；
  只有一般候選狀態下 Enter 才選取目前反白候選。這條與 Android 的軟 Enter 原則一致。
- **iOS 欄位模式由 `textDocumentProxy.keyboardType` 決定**：11 種 `UIKeyboardType`
  先映成 UIKit-free 的 `KeyboardTypeHint`／`InputFieldPolicy`，才能用 macOS SwiftPM
  測試。限制型欄位保留固定 11 欄位置，將無效按鍵設為 `isEnabled = false` 並淡化；
  controller 也要再次拒絕 disabled key。欄位類型改變時選 preferred mode，同類欄位間
  則保留使用者手動選的 mode。
- **iOS secure／phone pad 欄位禁止第三方鍵盤**：Apple 明定 secure text field、
  `UIKeyboardType.phonePad` 與 `namePhonePad` 都會切回內建鍵盤，App 也能透過 extension
  policy 全面禁用第三方鍵盤。對應 `InputFieldPolicy` 仍需保留作純邏輯測試與防禦性處理，
  但不可宣稱 extension 能在這些欄位實際出現。
- **iOS 13 起可使用 inline 組字**：`UITextDocumentProxy.setMarkedText`／`unmarkText`
  自 iOS 13 可用，本專案最低 iOS 17。loader 把 reading 寫成 marked text；確定候選時
  必須先以候選取代同一 marked range 再 `unmarkText`，不可先 unmark 原始注音，否則會
  產生 `ㄋㄧˇ你`。取消組字則以空字串取代 marked range，不能用 `unmarkText` 接受讀音。
- **iOS 外部文字／選取變動要清掉組字狀態**：`textDidChange`、`selectionDidChange` 與
  鍵盤離開畫面時清除 reading、候選、關聯詞和暫時狀態；外部游標移動後不能沿用舊的
  marked range。loader 自己呼叫 `insertText`／`deleteBackward`／`setMarkedText` 造成的
  callback 必須以短期 mutation generation 略過；同一按鍵可能連續替換舊 marked text
  與建立新 reading，較早的非同步清除不可解除較新 mutation 的 guard。切換欄位時用
  `documentIdentifier` 強制失效舊 guard，但不要在新游標位置刪除舊 marked range。
- **實機可能讓 `documentIdentifier` 違反 nonnull 宣告**：iPhone 16 Plus／iOS 26.6.1
  在 keyboard proxy 剛啟動時實際回傳 Objective-C nil，直接讀 Swift 的非 optional
  `UUID` 會在 `_unconditionallyBridgeFromObjectiveC` trap，造成輸入法立即跳回上一個。
  必須經 `currentDocumentIdentifier()` 的 KVC optional bridge 讀取；不要改回直接存取。
  proxy 後續第一次從 nil 取得 UUID 只是在完成初始化，不是切換輸入欄位，必須先建立
  identifier 基準而不能 reset engine，否則選字後的關聯候選會閃現後立刻消失。
- **實機 document callback 可能晚於下一個 main-loop**：選字時的
  `setMarkedText + unmarkText` 在 iPhone 上可能延遲回報 `textDidChange`／
  `selectionDidChange`。`mutateDocument` 的 guard 必須涵蓋這段短暫 grace period；這只用來
  分類 callback，不可把文件 mutation 或候選顯示本身延遲。
- **候選文字不可決定鍵盤內層寬度**：`KeyboardView` 的 root stack 必須以 999 priority
  填滿手機可用寬度，再由 required maximum 把 iPad 限在 820pt。只放 leading/trailing
  inequality 會讓 Auto Layout 依候選 intrinsic width 排版；動漫的「的名字」會把 11 欄
  鍵盤撐寬，選完關聯詞後又縮回。UI test 必須用僅啟用 `anime` 的多字候選覆蓋這條路徑。
- **iOS SQLite 順序不可依賴未指定的 row order**：單字候選查詢明確以 `rowid` 排序；
  多個關聯詞庫一次查詢後，還要依使用者啟用的 source 順序重組並去重，不能把 SQL
  `IN (...)` 的回傳順序當成詞庫優先權。變更 source 清單時需同步清掉 statement cache。
- **iOS `deleteBackward()` 已經是 grapheme 感知，不要移植 `TextDeletion`**：
  2026-08-23 在模擬器實測，一次 `deleteBackward()` 可完整刪除 👍🏻（膚色修飾符，
  4 個 UTF-16 unit）與 👨‍👩‍👧（ZWJ 家庭序列，8 個 unit／5 個 scalar），沒有殘骸。
  Android 需要 `TextDeletion` 是因為 `deleteSurroundingText(1, 0)` 刪的是**一個
  UTF-16 碼元**；`deleteBackward()` 是「刪除鍵」動作，層級不同。自己再算長度補刪會
  **刪過頭**。
- **iOS 按鍵震動需要 Full Access**：`UIFeedbackGenerator` 在 extension 內被
  `RequestsOpenAccess` 把關，沒開就靜靜失效。本專案選擇不開，改用
  `UIDevice.playInputClick()`（聲音，不需權限）。設定值本身存在 extension 自己的
  `UserDefaults`，那不需要任何權限 —— 別把「存設定」和「產生震動」混為一談。
- **iOS 鍵盤約 60 MB 就會被 jetsam 終止，且沒有 crash log**：不要學 Android 把
  1.2 MB／98k 行的 `.cin` 解析進記憶體。實測 SQLite 只映射查詢用到的頁，資料層常駐
  足跡不到 1 MB。
- **`Mandarin-bpmf-cin` 的 key 是 absolute-order 編碼，不是鍵盤按鍵**：兩個桌面
  cooker 都透過 Formosa 把 `1ji6` 這種按鍵序列轉成 2 字元 base-79 碼，所以 iOS 的
  `BopomofoSyllable` 必須實作同一套編碼（`Mandarin.h:190-227`）才查得到東西。附帶
  好處是與鍵盤佈局無關。
- **Simulator 的 Connect Hardware Keyboard 會讓軟體鍵盤整個消失**：連地球鍵一起，
  看起來像鍵盤掛掉。關法是 Simulator 的 Cmd+Shift+K，或寫
  `defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false`
  再重開 Simulator 視窗。注意 `killall Simulator` 會把 booted 的裝置一起關掉。
- **iOS XCUITest 能加入第三方鍵盤，但不保證能把它設為目前鍵盤**：五機入口是
  `Source/Loaders/iOS-Keyboard/run-simulator-tests.sh`。`--host-only` 會自動跑引擎、
  設定 opt-in 與 14 種宿主欄位；不加參數會要求 extension 的模式／組字／直橫測試。
  iOS 26 的 `InputSwitcherView` 對合成 tap／drag 可能只反白不切換，不能把兩個
  extension test 靜默 skip 後宣稱完整通過。iOS 26 設定頁文字是「新增鍵盤」，舊系統
  可能是「加入新的鍵盤」；UI test 同時接受中英文與兩種標籤。
- **iOS 按鍵標籤是兩個 UILabel，不是一個兩行的 attributed title**：注音鍵要同時顯示
  注音與鍵位，而聲調符號（ˊ ˇ ˋ ˙）是 spacing modifier letter，字級要放大約 1.8 倍
  才看得清。放大後若用兩行 label，第二行的鍵位數字會被推出按鍵外；改用
  `.baselineOffset` 想把符號往下拉也一樣 —— TextKit 會連帶把行框加高，結果照樣裁掉。
  所以兩個 label 各自用固定高度定位（`KeyboardView.configure`），鍵位數字才會與同排
  其他鍵齊高。改這段一定要截圖檢查整排數字是否對齊。
- **Enter 鍵是描邊畫出來的，不是字元**：`↵` 在 Android 與 iOS 系統字體下都偏細且不
  一致。座標在 `Source/Branding/enter.svg`，兩個平台各自照抄同一組數字描邊
  （`EnterGlyph.swift`／`BopomofoKeyboardView.drawEnterKey`）。**三個檔要一起改。**
  Android 端不從 SVG 讀檔 —— 該 View 全部是 Canvas 手繪，多帶一個 drawable 反而不一致。
- **iPad 不會替鍵盤畫地球鍵，iPhone 會**：iPhone 由系統在 input view 下方另外畫一排
  地球＋聽寫，iPad 沒有那一排。`TARGETED_DEVICE_FAMILY = "1,2"`，所以這支在 iPad 上
  是原生安裝、跑得起來 —— 但少了地球鍵就**出不去鍵盤**（只能去「設定」關掉它）。
  判斷依據是 `UIInputViewController.needsInputModeSwitchKey`，iPhone false／iPad true，
  照它決定功能列要不要多一顆。按鍵要用
  `addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)`
  接到 controller，才會有系統行為（點一下換下一個、長按出鍵盤清單）；自己呼叫
  `advanceToNextInputMode()` 只有點一下。接對了的話系統第一次會自己跳出
  「快速更改鍵盤」說明卡。
- **iPad 橫式不會進 compact 版面**：iPad 全螢幕時 `verticalSizeClass` 兩個方向都是
  `.regular`，所以 metrics 必須另外判斷 `userInterfaceIdiom == .pad`。iPad 使用 330pt
  高度、最大 820pt 的置中鍵盤內容；iPhone 仍依 compact height 切換 330／155pt，
  不要只靠 size class 判斷 iPad 版面。
- **在乾淨的模擬器上啟用第三方鍵盤不必手動點設定**：啟用清單是
  `.GlobalPreferences.plist` 的 `AppleKeyboards`，第三方項目就是 extension 的
  bundle ID。
  `xcrun simctl spawn <udid> defaults write -g AppleKeyboards -array "zh_Hant-Zhuyin@sw=Zhuyin;hw=Automatic" "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji" "io.github.polobread.inputmethod.chichi77.ios.keyboard"`
  重裝 App 會把選中的鍵盤重設回系統的，每次重裝都要重選一次。
- **Slack／Electron 按 ESC 會多送一個 Escape**：組字中按 ESC，Slack 取消組字後
  editor 又收到 Escape。**macOS 內建注音行為完全相同**，而原生 app（Line、
  TextEdit）正常，所以這是 Chromium 端行為：keydown 會被 mask 成 `keyCode 229` +
  `isComposing=true`，但 keyup 不經輸入法、原樣送到 DOM，輸入法端攔不到。
  **不要再往本專案查這題。**
- **公開分類詞庫必須維持匯入界線**：`DataSource/chichi77Collection` 是自動化生成、
  推論與整理的資料；長詞拆分於 2026-08-24 做過專項 review，但整體沒有全面逐筆人工
  校正，不可宣稱正確或完整。公開資料只保留中文字首、2–5 個 Unicode code point 的
  詞條；較長原詞必須依明確 review 結果選取有意義的連續片段，不可再用統計斷詞器直接
  拆分。中文字首後混有拉丁字母的詞可保留。授權與免責說明在該目錄的 `README.md` 與
  `LICENSE.txt`，更新資料時不可覆蓋。
- **GitHub Actions 封裝與 Release**：Android 與 iOS workflow 只有 `workflow_dispatch`；
  macOS 與 Windows 在推送 `v*` tag 時會先驗證 tag 必須精確等於 repository 版號
  （例如 `v1.2.4`），再發布到公開 GitHub Release。publishing run 需要 `contents: write`；
  Release 已存在就沿用，不存在才建立，workflow 絕不建立 tag 或覆寫同名資產。
  repository 是公開的，所以 artifact 在保留期間仍可能被讀者下載。workflow 會封裝包含
  `chichi77Collection` 在內的全部公開詞庫。
  - macOS 拆成兩個 job。`build` 沒有 environment 也拿不到 secret，永遠會跑，產出未簽章
    pkg 的 7 天 artifact，另外用 `ditto` 把建好的 app 打包成保留 1 天的交棒 artifact
    （`upload-artifact` 不保留 symlink 與執行權限，framework 會壞，一定要先 `ditto`）。
    `publish` 只在 `github.ref_type == 'tag'` 時跑，掛 `release` environment，簽章、
    notarize、staple 之後把 pkg zip 與 SHA-256 發布到 Release。
  - macOS 與 iOS 沒有 Windows 那個 `release_tag` 手動輸入。`release` environment 的
    tag rule 會擋掉在 branch 上跑的 `workflow_dispatch`；補救失敗的 tag run 要從 Actions
    頁面 re-run（ref 仍是 tag），或用 Run workflow 直接選那個 tag。
  - Windows 兩種產物都未簽章，`.unsigned.exe` 只供測試；Android 是 debug APK；iOS 只產
    Apple Silicon Simulator app。GitHub Actions 的 iOS TestFlight／商店上傳尚未處理，
    那需要 App Store Connect API key（`xcodebuild -allowProvisioningUpdates` 只吃 API
    key，app-specific password 餵不了）。Xcode Cloud 則由 `ci_post_clone.sh` cook 資料庫
    並以 Cloud build number 覆寫 `CURRENT_PROJECT_VERSION`；出口合規宣告已固定為不使用
    non-exempt encryption。
- **Apple 簽章刻意把私鑰放進 GitHub Actions，Windows 不放**：這是明知的破例。hosted
  runner 沒有 Windows 憑證存放區的對等機制，notarization 也只能在 macOS 上跑，所以
  `Developer ID` 的 `.p12` 以 base64 存成 secret。收斂方式：secret 一律掛在 `release`
  environment 而不是 repository secrets，該 environment 的 deployment rule 只允許
  **ref type 為 tag** 的 `v*`（設成 branch 會讓 tag 觸發的 job 全部被擋）；所有
  `actions/*` pin 到 commit SHA，避免上游搬動 tag 就等於私鑰外洩；`if: always()` 收尾
  刪掉臨時 keychain。5 個 secret：`APPLE_DEVELOPER_ID_P12`、
  `APPLE_DEVELOPER_ID_P12_PASSWORD`、`APPLE_ID`、`APPLE_APP_SPECIFIC_PASSWORD`、
  `APPLE_TEAM_ID`。簽章身分字串含法定姓名，不進 secret，在 runner 上用
  `security find-identity` 查——注意 `Developer ID Installer` 不是 codesigning 用途，
  `-p codesigning` 撈不到它。
- **臨時 keychain 有兩個一定要做的動作**：`set-key-partition-list`（不做的話 codesign
  與 productbuild 會等 GUI 授權，job 掛到 timeout），以及匯入 Apple 的中介憑證。
  Keychain Access 匯出的 `.p12` 只帶 leaf identity，不含簽發者，臨時 keychain 裡沒有
  中介 codesign 就建不出憑證鏈；workflow 直接抓
  `https://www.apple.com/certificateauthority/DeveloperIDCA.cer`，不依賴 runner image
  剛好裝了什麼。另外，本機要驗 `.p12` 時測試用的 keychain **不要放在 `mktemp -d` 底下**：
  `/var` 是 `private/var` 的 symlink，`securityd` 存正規化後的路徑，再用 `/var/...`
  去找會回報 `The specified keychain could not be found`。CI 不受影響，`$RUNNER_TEMP`
  在 `/Users/runner/work/_temp`。
- **Windows Store EXE 採 NSIS 3.12＋本機手動簽章**：`windows-2025` image 不內建
  NSIS，workflow 會透過 Chocolatey 固定安裝 3.12；不要降回 3.11，3.12 修正 elevated
  installer 使用低 integrity 暫存目錄的安全問題。`Package-Store-Windows.ps1` 正式模式
  只從 Windows 憑證存放區依 thumbprint 使用憑證，不把私鑰或密碼放進 GitHub Actions；
  會先簽 x64 DLL、x86 DLL、設定 EXE，再建立並簽署 NSIS EXE。`-UnsignedTest` 只供
  Actions／本機檢查，絕對不可上架。NSIS 使用 `/S`（大小寫有別）靜默安裝，payload
  放在版本子目錄，避免升級時已載入的舊 TSF DLL 阻擋覆寫。Partner Center 使用不可
  覆寫的版本化 HTTPS URL；自動 Release 只含 unsigned 測試資產，已簽 EXE 必須以不同
  檔名手動上傳到對應版本的既有 Release；
  ZIP 與 EXE 都必須保留 `Windows-TSF/LICENSE.txt`、
  `chichi77Collection/LICENSE.txt` 與其餘授權告知。NSIS 的同意頁順序固定為
  `LICENSING.md`（混合授權範圍）→ Windows frontend MIT → Yahoo BSD；不可把 MIT
  放在範圍說明之前而誤導成整個產品只有 MIT。
- **GitHub 的 `windows-2025` 目前是 VS2026 image**：2026-08-24 實跑得到
  `windows-2025-vs2026`，只有 Visual Studio 18 2026；用 `Visual Studio 17 2022`
  generator 會立即回報找不到 Visual Studio。hosted workflow 必須使用
  `windows-x64-vs2026` 與 `windows-x86` preset；VS2022 presets 只留給仍安裝
  Visual Studio 2022 的本機環境。
- **Android workflow 不可啟用 `setup-java` 的 Gradle cache**：repo 內歷史檔案
  `Source/ExternalLibraries/UnitTest++/UnitTest++` 在 Unix checkout 是指向自己的 symlink；
  `setup-java@v5` 的 cache dependency 掃描會跟隨它並以 `ELOOP` 失敗，早於 Gradle
  建置。Android 不讀該目錄，目前刻意不啟用這層 cache；不要在未排除循環 symlink
  前加回 `cache: gradle`。
- **Android 的 `gradlew` 必須保留 Git executable bit**：Windows 工作目錄不會直接
  顯示 Unix 執行權限，提交前以
  `git ls-files -s Source/Loaders/Android-IME/gradlew` 確認模式是 `100755`。若變成
  `100644`，Ubuntu runner 執行 `./gradlew` 會立刻以 exit 126／Permission denied
  失敗；用 `git add --chmod=+x Source/Loaders/Android-IME/gradlew` 修復。
- **Android Google Play 發布只走獨立 environment**：
  `.github/workflows/android-play-release.yml` 使用 `google-play-release` environment 的
  5 個 upload key／service account secrets，建 signed AAB 後只推 internal track；
  package name 必須是 `tw.chichi77.keykey.android`，不是舊範例的
  `com.polosoft.chichi`。tag 觸發時必須精確等於 repository 版號，manual run 則使用所選
  ref 的版號；重跑相同 versionCode 會被 Play 拒絕。upload certificate 本來就是
  self-signed，`jarsigner -verify -strict` 會因沒有公有 CA chain 誤判失敗，workflow
  只能用 `jarsigner -verify` 確認 AAB 有簽章。正式 keystore 只還原到 runner temp，
  Gradle 關閉 configuration cache，job 收尾刪除該檔。
- **Android Supporter entitlement 與 IME 必須保持分離**：Google Play Billing 9.1.0
  只由 `SupporterBillingManager` 在設定頁建立；`BopomofoImeService` 只能讀
  `SupporterState` 的 SharedPreferences cache，Billing／網路失敗不得進入輸入路徑。
  `chichi_supporter` 是非消耗性 one-time product，不可 consume；只有 `PURCHASED` 才
  授權並補 acknowledge，`PENDING` 不授權。PBL 9 的一次性商品要從
  `OneTimePurchaseOfferDetails` 選 `purchaseOptionId == "buy"`，並把該項的 offer token
  傳入 `BillingFlowParams`；不要退回舊式只傳 ProductDetails 的做法。試用期固定以
  `PackageInfo.firstInstallTime` 算 30 天，滿 30 天的邊界即 expired，解除安裝重裝重算。
- **iOS Supporter entitlement 與 keyboard extension 必須保持分離**：StoreKit 2 只由
  容器 App 的 `SupporterStore` 查詢商品、監聽／驗證交易與執行恢復購買；extension 只能
  讀 App Group `group.io.github.polobread.inputmethod.chichi77.ios` 的 `SupporterState`
  cache，不可在輸入路徑建立 StoreKit 或網路工作。產品 ID 同樣是非消耗型
  `chichi_supporter`，未購買也不能限制任何輸入功能；首次使用滿 30 天後只在空白注音狀態
  顯示支持提示。Apple Developer 的 App Group 必須同時指派給容器與 extension bundle ID。
- **iOS 商品未載入時不能顯示可購買狀態**：`Product.products(for:)` 可能拋錯，也可能成功
  回傳空陣列。這兩種情況都要保留恢復購買，但主按鈕只能顯示「重新載入價格」，不可顯示
  「付費支持」後再必然跳錯誤。App Store Connect 的「付費 App 協議」也必須先顯示「有效」；
  2026-09-09 送審被 Guideline 2.1(b) 拒絕時，該協議仍顯示「新」。
- **App Store 描述欄不接受注音符號「ㄅ」**：App Store Connect 會以「此欄位包含一個或多個
  無效的字元」拒絕儲存含「ㄅ半注音」的描述。商店描述固定寫「傳統注音」，不要把
  `StoreAssets/README.md` 的這個用語改回「ㄅ半注音」。副標題目前可使用「ㄅ半注音的第一選擇」，
  這項限制不要擴大套用到未出錯的欄位。
- **iOS 購買／恢復／商品重載必須共用互斥狀態**：`SupporterStore` 在第一個 await 前
  設定 `operation`，以 `defer` 回到 idle；不能只停用 UI，因為連點可能已排入多個 Task。
  `iOS-Keyboard/Package.swift` 直接編譯容器的 `SupporterStore.swift` 並注入商店介面，
  用 `swift test --scratch-path /tmp/keykey-supporter-flow-tests` 驗證，不把 StoreKit
  放進共用引擎。這些流程測試不會連到 App Store，不能取代 Sandbox 真實交易。
- **iOS 新版以 commit／push 觸發 Xcode Cloud**：2026-09-09 確認 App Store Connect 的
  `Default` workflow 監看 `master` 任意檔案變更，執行 iOS Archive 並準備分發至
  App Store Connect；目前沒有 Test action 或後續動作。依使用者要求，正式新版走這條
  流程，不另從本機上傳。`testFlight` 只是本機工作分支；推送前核對 `origin/master`
  並使用正常快轉，不要 force push。Cloud 由 `CI_BUILD_NUMBER` 設定兩個 target 版號。
- **macOS／iOS cooker 的 people exclusion 來自公開分類詞庫**：
  `DatabaseCooker/Makefile` 會從 `DataSource/chichi77Collection/phrase.people-*.tsv`
  產生人名 exclusion，再匯入 McBopomofo 與 29 個分類詞庫。不要移除檔案存在時才執行
  `awk` 的保護；資料目錄暫時不完整時仍應能產生空 exclusion，避免錯誤訊息誤導。
- **五平台商店圖與 iPhone App Store 圖分開生成**：2026-09-20 將 Linux GNOME
  原始候選截圖放在 `StoreAssets/Sources/chichi-linux.png`，由
  `StoreAssets/generate-five-platforms.py` 生成 Google Play 手機圖 05 與
  `StoreAssets/FivePlatforms/five-platforms.png`。Linux 格明示開發中；
  `generate-assets.swift` 只生成各圖組的 01–04，不可再讓它覆蓋五平台圖，
  也不可把五平台圖放進 `AppStore/iPhone-*`。

---

## TODO

### 商店圖庫

- [x] 2026-09-20 以既有 Google Play 05 的紫色版型新增 Linux 實際畫面，
      產生 Android、iOS、macOS、Windows、Linux 五平台圖與獨立存放副本；
      iPhone App Store 上架素材維持原四張。
- [ ] 正式使用五平台圖前，在 Play Console 預覽縮圖與裁切，並確認 Linux
      「開發中」標示在實際商店頁清楚可見。

### GitHub Actions

- [x] 2026-08-27 的 `v1.2.4` tag 已實跑 macOS 與 Windows workflow：兩者都成功，
      Windows 公開 Release 含 ZIP、unsigned EXE 與各自 SHA-256；macOS build artifact
      也包含公開詞庫，Windows 的 VS2026 修正已由該次 run 驗證。
- [ ] 從 GitHub Actions 頁面手動重跑 Android 與 iOS Simulator workflow，確認 hosted
      runner 的工具版本、7 天 artifact 與公開 `chichi77Collection` 都被封裝；Android
      的循環 symlink 修正仍待 hosted runner 驗證。

### iOS 發布

- [x] 2026-09-09 補上購買／恢復／重載共用忙碌狀態、連點防護與取消／錯誤復原；
      容器購買流程 7 組測試（15 個情境）通過，iOS Simulator Debug App 建置通過。
      同日 iPhone 17 Pro Simulator Release smoke 5／5 通過、零 skip；本機 Release
      archive 與匯出 IPA 的發佈簽章、App Group、資料庫與無 Debug 入口檢查均通過。
- [ ] App Store Connect 付費 App 協議確認為「有效」，完成必要稅務／銀行資料，再驗證
      Sandbox 購買並上傳含修正的新 build；更新審查備註中的錄影附件說明後重新送審。
- [ ] 用 Sandbox Apple ID 實測 `chichi_supporter` 的購買、待處理、取消、恢復與退款／撤銷，
      並確認容器 App 與 keyboard extension 透過 App Group 同步 entitlement；Simulator 的
      狀態與 UI 測試不能取代 App Store 伺服器交易驗證。

### macOS 發布

- [x] macOS `publish` job 已於 2026-08-27 的 `v1.2.4` 首次實跑成功（run
      `33031272995`，build 18m25s、publish 31m20s）：臨時 keychain、
      `set-key-partition-list`、Apple 中介憑證鏈、簽章、notarytool、staple、
      `stapler validate`、`spctl --assess --type install -vv` 與 Release 上傳全部通過；
      Release 含 signed pkg zip 與 SHA-256。
- [ ] 從 `v1.2.4` Release 下載 signed pkg zip，在另一台 Mac 實際安裝並確認不再觸發
      Gatekeeper 警告。
- [ ] 兩張 Developer ID 憑證掛在 G1 中介之下，`notAfter` 被 CA 自己的到期日砍到
      **2027-02-01**（不是常見的 5 年；G2 中介到 2031）。到期後簽不出新版本，已 staple
      的舊產物仍有效。值得從 developer.apple.com 網頁重新申請，看 Apple 是否改簽在 G2。

### 舊碼清理

- [ ] **已確認可在未來刪除的舊碼**：下列目錄不在目前支援的 macOS IMK、Windows
      TSF、Android、iOS 建置或封裝路徑內，只屬於已淘汰的 Windows IMM／macOS TSM
      frontend、其附屬工具或獨立實驗。刪除時必須在同一個 commit 清掉
      `Source/Takao.sln`、`Source/Takao.xcodeproj` 的 legacy target、
      `Source/Distributions/Takao/makeall-osx.sh` 與 `Source/Utilities/version-upper.rb`
      等留下的失效引用，再完整驗證四平台目前的建置入口：
      - `Source/Loaders/Windows-IMM`
      - `Source/PreferenceApplications/Windows`
      - `Source/Loaders/OSX-TSM`
      - `Source/Studies`
      - `Source/Utilities/CinInstaller`
      - `Source/Utilities/HomophoneFilter`
      - `Source/Utilities/PhraseEditor/Windows`（只刪 Windows 子目錄；OSX 仍在打包）
      - `Source/Distributions/Takao/Installer-OSX-TSM`
      - `Source/Distributions/Takao/Installer-Windows`
- [ ] **需要再確認才能刪除**：下列目錄沒有出現在目前四平台的自動建置／封裝入口，
      但可能仍供人工簽章、更新資料、舊式 DMG 製作或一次性維護使用。刪除前先確認
      本機／外部發布流程沒有依賴，並追查動態路徑與預編譯工具的來源：
      - `Source/Utilities/SignatureMaker`
      - `Source/Utilities/TextOverlay`
      - `Source/Utilities/VersionInfoMaker`
      - `Source/Distributions/Takao/Installer-OSX-DB`
      - `Source/Distributions/Takao/Installer-OSX-ExtraModules`
      - `Source/Distributions/Takao/Installer-OSX-IMK`
      - `Source/Distributions/Takao/OnlineDataTemplates`
      - `Source/Distributions/Takao/PrecompiledTools`
      - `Source/Distributions/Takao/VersionInfo`
- `DataSource/chichi77Collection` 仍供四平台資料生成與封裝使用；
  `Source/Loaders/CrossPlatform`、`Source/WebResources`、
  `Source/Distributions/Takao/Installer-OSX-UI`、
  `Source/Distributions/Takao/Installer-OSX-Help` 與 `Source/Utilities/PhraseEditor/OSX`
  仍由目前 macOS IMK target 編譯、複製或打包。以上均**不在刪除範圍內**。

### macOS

- [x] 2026-09-20 完成 macOS 候選／loader／SQLite 與 cooker 專項 review，
      重建資料庫並完成副本大小、順序、快取及 statement 洩漏實驗；結果在
      `docs/MACOS_CODE_REVIEW.md`；後續同日另依使用者要求修正三項 P2。
- [x] 修正直式候選與通知 attributed-string ownership，以及詞彙編輯器查詢
      statement 洩漏；arm64 Release build／analyze 與 1,000 次資料層 probe 通過。
- [ ] 在實際 1.2.9 IMK 行程反覆重畫候選、開關通知、詞彙編輯 save／close，
      重新量測 leaks／footprint 及確認長時間不再累積；目前執行的 1.2.8
      行程不能代表修復後結果。
- [ ] 修復洩漏後再量長時間使用及 SQLite cache 成本；目前保留 db 格式，
      4 KiB／VACUUM／注音專用產物作後續空間選項。共用改動須包含 Windows
      SQLite 3.6.11 相容性及 macOS／iOS 候選／反查順序回歸。
- [ ] 按五平台實際架構量記憶體：iOS／Android 多讀音候選 cache 與載入峰值、
      Windows x86／x64 多 host 用量、Linux Fcitx 字典常駐與切換成本；
      依 MACOS_CODE_REVIEW.md 跨平台專節決定是否需要限制快取或延後載入。
- [x] 候選窗依 visible frame 限制可用尺寸；直式超高時捲動、橫式超界時
      降低實際縮放，且最終位置雙軸限制。幾何／捲動測試與 Release build 通過。
- [x] 2026-09-20 直式候選改為先確定縮放 frame／bounds、再排子視圖，最後才選取、
      校正捲動與重畫；同頁保留合法捲動，反白列變更時才自動揭露，
      換候選／翻頁／隱藏重開清除舊位置。
      實際 controller／NIB 隔離測試通過 100% 舊 table 高度／offset 恢復、
      200% 大字級捲動與反白末列、100%／200%／350% 切換。
- [x] 已產生本機第二版 arm64 1.2.9 測試包
      `Installer/local-builds/chichi77-KeyKey-1.2.9-local-20260920-r2-macos-arm64.pkg`；
      內含此次直式候選順序與捲動改動，app UUID
      `97C08D88-FCD6-3892-A807-793D3C03619F`，套件固定安裝路徑、
      ad hoc deep strict 簽章及 SQLite integrity check 通過。尚未在系統安裝。
- [x] 2026-09-20 產生本機 arm64 1.2.9 測試安裝包，位於
      `Installer/local-builds/chichi77-KeyKey-1.2.9-local-20260920-macos-arm64.pkg`；
      pkg 內版號／固定安裝路徑、db integrity 及 app ad hoc deep strict 簽章均通過。
      此本機產物被 `.gitignore` 忽略，未提交或發布；後續確認使用者系統的
      1.2.9 app Mach-O UUID 與這一版相同，但未確認當時執行中的輸入法是否已重載。
- [ ] 實際 Mac 補驗 350%、小螢幕、邊緣／雙螢幕定位、翻頁、捲動條與
      滑鼠命中；靜態幾何測試不能代替真實視覺驗收。
- [ ] 追查網友「新增 macOS 輸入法後叫不出來」：使用者後續確認網友下載的
      是正式 1.2.8，仍待取得 CPU、macOS、是否首次安裝後重新登入，
      以及無法切換或切換後無法輸入的區別。使用者稍後會找時間登出測試。
      目前產物僅 arm64／macOS 15+，distribution 只有 OS 檢查，尚缺明確 CPU
      安裝門檻；不能因唯音正常就排除 KeyKey 相容性，也未有兩者衝突的證據。
      postinstall 已結束舊 KeyKey 行程，升級通常由系統重啟；首次安裝仍提示重新登入。
- [ ] Intel macOS 封裝：2026-09-20 以獨立 `Intel.xcconfig` 強制 `ARCHS=x86_64`
      實際編譯，前置 target 完成，主程式連結失敗的具體阻礙是現有
      `/opt/homebrew/opt/openssl@3/lib/libcrypto.a` 僅 arm64；缺少 x86_64
      `_BIO_*`、`_PEM_read_bio_RSA*`、`_RSA_*`、`_SHA1`。需要相同版本的
      x86_64 OpenSSL 靜態庫，再做完整 x86_64 app／nested code／pkg 驗證與
      Intel macOS 15 實機輸入測試。Xcode 27 在 deployment target 15 下可編
      x86_64 空物件，`-xcconfig` 的 `ARCHS=x86_64` 必須寫在 include 原設定之後；
      僅在 xcodebuild 命令列加 `ARCHS=x86_64` 會被現有 xcconfig 的 arm64 覆蓋。
- [x] 2026-09-17 修正 Preferences 深色模式的白底白字，三種語系的表格改用系統動態底色；
      同時在直式候選每次更新後重設 scroll origin，避免放大候選窗時第 1、2 列移出可視範圍。
      三份 XIB 已通過 `ibtool --compile`，並以 Xcode 27／macOS 27 SDK 完成 arm64 Release
      target 建置。
- [x] 2026-09-17 重作 macOS 直式候選的寬度與子視圖布局：候選內容和 prompt 分別量測，
      明確配置兩欄、scroll view、提示列及翻頁控制，避免短候選仍保留多餘寬度以及
      `SHIFT + 數字鍵` 被截斷；已完成 arm64 Release target 建置。
- [x] 2026-09-17 完成 macOS UI 深色模式稽核：Preferences 與 PhraseEditor 三種語系的
      table/header、About 視窗、搜尋輸入框、符號表及橫／直式候選 XIB 均改用系統動態色；
      所有受影響 XIB 已通過 `ibtool --compile`，並完成 arm64 Release target 建置。
- [ ] 在實體 Mac 截圖確認 Preferences 三種語系新增的候選窗比例列不再覆蓋模組說明，
      以及直式／橫式候選窗在「跟隨顯示器、75%、90%、100%、200%、350%」下的字體、
      按鍵角標、翻頁控制與點選
      hit testing 都一起縮放；Windows 環境只能做原始碼與 plist 靜態檢查。
- [ ] 版號集中：`Takao-macOS.xcconfig` 設 `MARKETING_VERSION` 與
      `CURRENT_PROJECT_VERSION`，4 個 plist 改用 `$(MARKETING_VERSION)`（8 處 → 1 處）。
      注意 Xcode.app 建置路徑吃不到該 xcconfig，改完會拿到空版號。
- [ ] `Takao-macOS.xcconfig` 未接進 pbxproj 當 project 層級的
      `baseConfigurationReference`（專案有 5 個 configuration：Debug／Debug64／
      DebugPPC／Release／Release64）。接進去可讓兩種建置路徑一致，代價是手改 pbxproj。
- [ ] 去 Yahoo 化未完成：隨主程式打包的 Preferences、PhraseEditor、DownloadUpdate、
      InstallerHelp 仍有使用者可見的 Yahoo 字串（如「Yahoo! KeyKey is not running」、
      `NSHumanReadableCopyright`）。注意硬規則第 5 條，BSD 要求保留的部分不能動。

### Windows

- [ ] Windows 11 設定 UI 與 SQLite／Defender 的後續評估見
      [Windows SQLite／Defender 評估交接](WINDOWS_SQLITE_EVALUATION.md)。建議保留
      `ITfFnConfigure` 啟動獨立 `KeyKeySettings.exe`，在 Windows 上比較既有 Win32 與
      C++/WinRT WinUI 3 原型；先抽出共用 `SettingsStore`，並以建置產生的 manifest／
      resource 取代 Settings EXE 為讀取 `collection_names` 而直接連結 SQLite。這只是
      建議，不代表已決定改寫、改用 WinSQLite，或已解決 Defender 誤判。
- [ ] 取得受信任的正式程式碼簽章憑證後，實跑 `Package-Store-Windows.ps1`，確認三個
      PE 與 NSIS EXE 的 RFC 3161 時間戳記；目前只驗證 `-UnsignedTest` 能編譯並含完整
      payload。還要在乾淨 Windows 11 VM 測 `/S` 安裝、靜默解除安裝、升級、x64
      應用程式及 32-bit Office 載入，再把已簽 EXE 手動放到不可覆寫的版本化
      GitHub Release URL 供 Partner Center 抓取。
- [ ] `Package-Windows.ps1` 的 `$Version` 與 `CMakeLists.txt` 重複，可改成從
      `CMakeLists.txt` regex 讀取。
- [x] 2026-08-24 的語言列生命週期修正版已完成 x64／x86 Release 建置，x64 的 3 個
      CTest 也已通過。
- [ ] 安裝該修正版後，在 Android Studio 反覆以 `Ctrl+Space` 切換中英文，確認不再產生
      `studio64.exe`／`KeyKeyTsf_x64.dll` Application Error。
- [ ] 為 `KeyKeySettings.exe` 增加 UI automation：目前只有啟動 smoke test，仍需人工
      驗證一般／注音／關聯詞三頁、五種注音鍵盤、直橫選字窗、十種比例、四種配色、Ctrl+\\、
      提示聲與 CNS11643 開關在實際 TSF host 中會即時套用；候選窗另需在 100%／225%
      與兩台不同縮放比例的螢幕間移動驗證字型、間距及游標定位。
- [x] 已確認 Ctrl／Alt 快捷鍵放行時保留候選或聯想詞面板是設計決定：引擎收不到該鍵，
      `updateCandidateWindow` 不會被呼叫，且行為與 macOS 對稱。未來若改須兩平台一起改，
      不可單邊處理。

### iOS

- [ ] 完成 App Store Connect 的付費 App 協議、銀行與稅務資料，等狀態變成「有效」後，
      用 Sandbox 實測 `chichi_supporter` 的商品載入、購買與恢復，再上傳包含商品重試流程的
      新 build。2026-09-09 已修正商品查詢失敗仍顯示「付費支持」的流程，並清除 App Store
      文案與截圖中的 Android／Windows 資訊。
- [x] 五台 Simulator 已加入共用 XCUITest target 與 `run-simulator-tests.sh`；
      2026-09-02 的 `--host-only` 基線為 79 個 Swift tests 與五台各 3 個 UI tests 全部
      通過（含 App 內授權告知）。
- [ ] 逐台切到琦琦注音跑 extension-required 模式，完成 A–K 並把結果記進
      `IOS_SIMULATOR_TEST_PLAN.md`。系統輸入切換器不能由 XCUITest 穩定選定，不得把
      opt-in 成功當成 extension 功能通過。
- [x] 2026-09-06 的實體鍵盤編輯器針對性回歸已通過 93 個 Swift tests；iOS 26.5
      iPhone 17 Pro 與 4.7 吋 iPhone SE 通過入口、控制項與直橫旋轉復原測試，iOS 26.5
      iPad 通過橫式四欄測試。這只涵蓋編輯器本次改版，不可取代五台 A–K。
- [ ] 用實體 USB／藍牙鍵盤驗證容器編輯器的注音、一般候選 `1–9`、關聯詞
      `Shift+1–9`、Space／Page Up／Page Down 翻頁、方向鍵、全半形、Ctrl／Command
      複製／分享／清除與清除確認；後續版面改動至少重跑兩台 iPhone 的
      `testHardwareKeyboardEditorHasCopyAndShareActions` 與 iPad 的
      `testHardwareKeyboardEditorLandscapeColumns`，並把結果同步到 iOS test plan。
- [x] 11 種 `UIKeyboardType` 的純邏輯測試與 iOS 26.5 iPhone 17 Pro Simulator
      App／extension build 已於 2026-09-02 通過；當時整套為 79 個 Swift tests。
- [ ] 在實機或 Simulator 測試 `default`、`asciiCapable`、`numbersAndPunctuation`、URL、
      numberPad、phonePad、namePhonePad、emailAddress、decimalPad、webSearch、
      asciiCapableNumberPad；確認直橫式 disabled key 無法點擊、VoiceOver 朗讀為 disabled，
      並確認 secure、phonePad、namePhonePad 由 iOS 換回系統鍵盤。`selectionDidChange`
      的游標移動清理、inline marked text 與 MODE／SHIFT 預覽仍須依
      `IOS_SIMULATOR_TEST_PLAN.md` 在五台受控 Simulator 跑完 A–K 才算完整驗證。

- [ ] 版號集中：`MARKETING_VERSION` 目前寫在 pbxproj 的 Debug／Release 兩個 project
      configuration 裡，可抽成 xcconfig（2 處 → 1 處）。
- [x] 2026-08-23 已用 hierarchy dump 驗證 VoiceOver 元素樹：直式共 57 個元素，順序為
      狀態列 → 候選列（上一頁／「第 n 個候選，字」／下一頁）→ 四排注音鍵 → 功能列；
      每個都有中文標籤，聲調鍵唸注音符號而不是鍵位數字，空候選格已排除。
- [ ] 實際開 VoiceOver 聽朗讀與 rotor 行為，並執行 accessibility audit；元素樹檢查
      不能取代真人聽測。
- [ ] 設定面板每列的文字與開關是兩個獨立元素，VoiceOver 會把詞庫名稱唸兩次
      （系統「設定」App 是合併成一個元素）。要修就把整列包成一個
      `UIAccessibilityElement`，或改用 `UITableViewCell`。
- [x] iPad keyboard extension 已使用專用 `.pad` metrics（330pt 高、最大 820pt 置中），
      實體鍵盤編輯器的橫式四欄也已通過 iPad UI 測試。
- [ ] 依 A–K 在 iPad 人工檢查直橫式實際字級、Dynamic Type、VoiceOver 與長時間輸入；
      frame assertion 不能取代視覺驗證。
- [x] 直式聲調符號已放大 1.8 倍；橫式刻意維持正常字級，因為橫式把注音與鍵位併成
      一行（`ㄅ 1`），只放大其中一個字會高低不齊，且橫式該排只有 26pt。未來若要放大，
      必須先拆成兩個 label。

### Android

- [x] 2026-09-19 震動時間改為 0、1、2、3、5、10、20、30、50、100ms 十段；直橫式
      鍵盤高度各改為 50%、75%、90%、100%、110%、125%、150%、175%、200% 九段；
      舊的任意數值讀取時對應到最近段。設定頁只在放開震動滑桿後試震一次，0 不震動。
      `lintDebug testDebugUnitTest assembleDebug` 已通過；API 26 `Medium_Phone` 已安裝
      debug APK，檢查設定頁初始值與滑桿切換到 100ms、110% 的顯示，未見崩潰或權限錯誤。
      真機短震動手感與六台 AVD 完整矩陣仍需驗收。
- [x] 2026-09-17 已將注音字表與 30 個關聯詞庫改為建置時產生 `.kki` 索引；core 不再於
      IME 啟動時解析 CIN，關聯詞改用低優先序背景載入及按鍵延遲解碼。另加入直式／橫式
      各自 50%–200% 的虛擬鍵盤高度、0–100ms 每 1ms 的震動設定與舊震動設定遷移；
      JVM 測試會逐項比對原始字典與產生索引。`lintDebug testDebugUnitTest assembleDebug`
      已通過。API 26 `Medium_Phone` 的單次 cold-process smoke 中，`ime set` 在詞庫全關為
      0.11 秒、30 庫全開為 0.09 秒，全開後可輸入「今」並顯示關聯候選，crash buffer 為空；
      API 35 `Medium_Tablet` 已目視橫式 75%／150%、直式 150%，API 26 實體候選列也未被
      虛擬鍵盤比例改變。這些是抽樣 smoke，不是 Pixel C 實機或下列六台 AVD 完整矩陣。
- [x] 2026-09-17 已把手機與平板共用的橫式 100% 內容高度由特別縮小的 155dp 改為一般
      比例 230dp；API 35 `Medium_Tablet`（2560×1600）與 API 30 `Pixel_4a`
      （2340×1080）皆已在橫式 100% 目視確認候選列、四排注音鍵、功能列與系統區完整，
      沒有裁切或重疊。
- [ ] 在 Pixel C／Android 8 分別以詞庫全部啟用與全部關閉量測冷啟動及再次叫出鍵盤時間，
      確認沒有原本約 10 秒與 1–3 秒的等待；再以 1、5、10ms 比對 Gboard 短震動手感，並
      目視確認直式／橫式 50%、100%、200% 與實體候選窗不受比例影響。
- [x] Android 欄位與 Enter action 的 JVM 策略測試已加入，並於 2026-08-30 通過
      `lintDebug testDebugUnitTest assembleDebug`。
- [ ] 在 Android 實機依序測一般、Email、URL、電話、整數、小數、日期時間、密碼、姓名、
      地址、搜尋、簡訊／長文字、可見密碼與要求 ASCII 鍵盤欄位；直橫式各確認限制型欄位
      的 MODE 仍可點，第一次按下後完整解鎖，重顯同一 editor 不會再鎖回；URL 從一開始
      就可用注音／英文／數字與完整功能，
      軟 Enter 的完成、下一個、搜尋、傳送、前往、上一個及 App 自訂 `actionLabel`／
      `actionId` 會觸發正確 action，而 USB／藍牙 Enter 仍送 plain Enter，且實體字元不受
      欄位提示限制。

- [x] 2026-08-30 已在 Pixel 9a 驗證設定列正常顯示、觸控按住預覽鍵無執行期錯誤；
      composing `ㄅ` 移到字首後輸入 `ㄚ` 得到 `ㄚㄅ`，`ㄅㄚ` 選取尾字後輸入 `ㄉ`
      得到 `ㄅㄉ`，確認游標與 selection range 都沒有沿用舊 reading。
- [ ] 在 Android 實機補測組字／候選開啟時由滑鼠及 App 程式改變游標或選取範圍，確認會
      清除舊引擎狀態，而 IME 自己逐鍵更新 composing、確定候選與建立關聯詞不會被誤清；
      人工畫面確認直橫式文字／注音／符號鍵預覽約放大 1.4 倍、邊緣鍵不超出畫面、滑出與
      放開會消失，設定關閉後不再顯示。該裝置的 ADB 截圖輸出全黑，不能取代目視檢查。

- [x] 2026-08-30 已加入 Android modifier bit、全形映射與引擎單元測試，並通過
      `lintDebug testDebugUnitTest assembleDebug`。
- [ ] 接上真正的 USB／藍牙鍵盤，確認底部候選列為 12 個等寬按鍵（9 候選、Emoji、
      `ㄅ／英`、`半／全`），沒有 ▲／▼；驗證點擊後兩鍵可切換，並再驗證 `Ctrl+Space`、
      `Shift+Space` 的 keydown／keyup／長按，以及全形 `Ａｚ０９！～　`、切回半形和
      reading／候選保留。ADB `input keycombination` 直接送到 editor，不會經過
      `InputMethodService.onKeyDown`，不能代替實體鍵盤驗證。

- [ ] 先在 Play Console 手動完成首次 app／AAB、Play App Signing 與 upload certificate
      登記（Publishing API 不能代替首次建立 app），再把 5 個 secrets 放進
      `google-play-release` environment 並實跑 `Android Play Release`。首次手動上傳若已
      使用目前 versionCode，workflow 必須等下一版，不能重送相同 code。成功進 internal
      testing 後，用 license tester 實測 purchase option `buy` 的 localized formatted
      price、新購、取消、PENDING 轉 PURCHASED、acknowledge、清除 app data／換機後恢復
      購買，以及離線或沒有 Play Store 時仍可完整輸入。直接 sideload 的 debug APK 無法
      完整驗證 Play 商品設定。

- [x] Android 直式聲調符號已比照 iOS 放大 1.8 倍並以 glyph bounds 校正上緣；橫式兩端
      都維持同列正常字級，於 2026-08-30 完成。
- [x] Android Enter 鍵描邊繪製（`drawEnterKey`）已於 2026-08-24 通過
      `lintDebug testDebugUnitTest assembleDebug` 編譯驗證。
- [ ] 在 Android 模擬器或實機截圖，比對 Enter 鍵外觀與 iOS 一致。
- [x] 2026-08-24 已在 Pixel 9a 的 Google 搜尋欄實測單一 composing `ㄅ` 按 Backspace
      會完整移除，不會留下失去底線的 `ㄅ`。
- [ ] 增加會在模擬器或實機啟動 `BopomofoImeService`，並驗證組字、觸控候選列、
      外接鍵盤一般候選 `1–9`／關聯詞 `Shift+1–9`、一次性注音 Shift、英文大小寫與
      兩套數字符號版面、`ㄋㄧˇ` Backspace 退音及複合 Emoji 一次刪除、
      關聯詞接續與全部關閉、符號／Emoji 各 10 頁及循環翻頁、外接鍵盤
      `Ctrl+Space`／`Shift+Space`／`Ctrl+,`／`Ctrl+.`／`Ctrl+0`／`Ctrl+1` 與全半形的
      smoke test；另需驗證實體鍵盤浮動候選預設關閉、直橫排列、游標四邊翻轉、
      不支援 `CursorAnchorInfo` 時的底部中央備援、觸控選字、方向鍵反白、Enter 與 ESC；
      目前 JVM 單元測試與 APK 建置無法攔截 D8／R8 合成類別漏包及
      `InputConnection` 互動之類的執行期問題；也應截圖檢查底列沒有與系統導覽區重疊，
      並確認直橫式 11 欄按鍵等寬、橫式文字沒有裁切。
