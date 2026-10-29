# AGENTS.md — 開發指引

此檔只記錄目前仍適用的規則、模型決策與驗證入口。逐日進度、舊版測試數字及已完成的除錯紀錄在 [歷史交接紀錄](docs/AGENTS_HISTORY.md)，不能當成現況或發布驗收。開始工作時先看目前分支、程式碼、`CHANGELOG.md` 與相關平台文件。

工作分支以 `git status --short --branch` 的實際結果為準。正式支援 Windows、macOS、iOS、Android、Linux 與 FreeBSD 六大平台。macOS 正式版為 1.3.8，安裝包與 stable 更新公告皆已發布並同步 CDN；Windows、Linux／FreeBSD、iOS 與 Android 正式版維持 1.3.7，iOS App Store 與 Android Google Play 皆已上架 1.3.7。FreeBSD 1.3.7 已在 FreeBSD 15.1-RELEASE-p3 amd64、Xfce／X11、LightDM、Fcitx 5 與 Mousepad／GTK 3 驗證，透過 ports／pkg 安裝，套件庫版本可能較晚上架。Guanyinma 工作分支的六平台原始碼開發版號統一為 `1.5.0`；正式發布版號仍依前述狀態；FreeBSD 沿用 Linux-IME 的版本來源，共用好打注音模型維持 v1.3.1。README 只記錄正式 Release／商店版本與支援範圍，不列開發版號。各平台仍須依各自流程建置與驗證；原始碼、建置產物、已安裝版本及實機行為是不同層級，不可互相代替。

## 好打注音模型決策

- 本儲存庫五個 frontend 共用預先產生的 `Source/Distributions/Takao/CookedDatabase/KeyKey.db`；平台建置只驗證及複製，不得自行 cooker。正式資料庫有 **119,159 筆 Unigram、883,372 筆 Bigram**，SHA-256 為 `8fc3aead36cefd16a77c0a0d4319f7a305fb712b752db09396c8ac2bd4ebbfdb`。
- Bigram 建模固定使用 `typing-articles-v2.jsonl`、`v3.jsonl`、`v4.jsonl` 共 **2,300 篇**。正式驗證固定使用 `typing-articles-v5-seed/tw-corpus-0001.md` 至 `0131.md` 共 **131 篇**，排除 `chat.md`；訓練與驗證沒有相同文章或 20 字以上相同段落。800／750／750 只屬已結束的 unigram 實驗分割，不再作為目前 Bigram 的建模或驗證依據。
- 每篇文章、每個模型都啟動全新引擎程序，關閉 user table、Bigram learning 與 candidate override，測試間不得共享記憶。正式動作模型採 5 音節穩定、10 音節組字範圍、每頁 8 個候選；注音鍵、確認、點字開候選、選字及翻頁都計入。輸出須包含總動作、額外修正動作、修正字及各自成本；總動作越少越好。
- Bigram 約只能影響仍在組字區內的 9～10 個字，不能期待後文完全救回前面的同音字。優先降低核心 83 字、前 100 名基本字與第 101～1,000 名一般字的修正；第 1,001～1,500 名、未排名罕字、專業詞及專有名詞只列診斷，不決定基礎模型是否採用，這些內容可由使用者學習改善。
- 調整前先分析整批錯誤分布，再訂一條適用全體的規則並重跑完整驗證。不得看一篇修一篇、對單一 Bigram 邊加補丁，或只用總分掩蓋基本字、題材或個別文章的退步。隨機 50 篇可作快速探索，不能取代目前固定 131 篇驗收。
- v1.3.1 以 McBopomofo unigram 為基準，只依 2,300 篇的跨文章證據調整既有 Bigram；122 個基本／常用字的 191 個讀音保留基準 Bigram，共保護 208,222 筆。另收錄經整體驗證的 7 個常用詞補充，以及搜尋熱門詞 550 詞去除 393 個既有詞後的 157 詞保守補充。
- 固定 130 篇結果為總動作 **331,619 → 331,062（-557）**、額外修正動作 **11,000 → 10,443（-557）**；97 篇改善、19 篇相同、14 篇退步，節省 623、增加 66。搜尋熱門詞層另少 6 次動作，3 篇改善、127 篇相同、0 篇退步。正式細節在 `DataSource/AISyntheticBigram/SMART_MANDARIN_MODEL_V1_3_1.md` 與 `DataSource/AISyntheticArticles/typing-articles-v5-manifest.json`。
- 自建 unigram、全域混合、剪枝、字級先驗及順位校準雖曾降低總動作，但在基本字分布、跨題材穩定性或外部驗證門檻失敗，因此都未取代正式基準。直接 unigram 順位問題主要集中於「做／作、新／心、裡／理、向／像」；「在／再、是／事、時／十」多數是上下文、多字候選或斷詞問題，應由整體語料與 Bigram 處理。既有 3,000 份外部提示已全部用過，下一次採用新規則需要新的完整自然文章 holdout，不能再宣稱舊資料是盲測。
- 慣用讀音先依本地詞庫與臺灣輸入習慣判斷，可先請 ChatGPT 分析；只有仍有疑義或本地資料互相衝突時才個別查教育部辭典，不批次查詢。破音字須依文章語境固定實際慣用讀音。

- `bigram` 分支另依使用者指定加入完整詞「舊的」的 Unigram 補償；「新的」保留既有詞頻。130 篇由 331,062 降至 331,058 動作，2 篇改善、128 篇相同、0 篇退步，基本字不變。明確詞條補充只經固定回歸驗證，不是新的盲測。全域 Bigram 候選尚未採用，詳見 `docs/SMART_MANDARIN_BIGRAM_LEARNING_REVIEW.md`。
- 歷史完整匯入（已由後續來源重建取代）：使用者曾要求匯入 29 份分類詞庫並接受當次回歸：中文化後新增 4,765 詞，1,745 筆已有詞及 50 筆重複跳過。當時新增詞一律詞頻 1，既有詞與 Bigram 不改。固定 130 篇總動作 331,058 → 331,068，1 篇改善、122 篇相同、7 篇退步，基本字「裡」多修 2 次。後續採用依使用者最新 30 次總動作門檻。逐筆清單見 `DataSource/AISyntheticBigram/COLLECTION_UNIGRAM_IMPORT.md`。

## 模型維護

- 三份 `phrase.people-*.tsv` 及「人名…」分類的新詞在 Bigram 訓練完成後才加入 Unigram；普通人名詞頻至多 1，動漫／碰撞人名至多 0.01。即使人名也出現在搜尋來源，仍排除於訓練；已存在小麥的同文字詞保留原模型處理。

- 自訂詞以小麥正詞頻詞為主體，僅同文字去重；完整同音詞保留低順位候選供選字學習。雙方連續兩字同音異字列診斷：新詞只有兩字時降權，三字以上詞不因部分碰撞刪除或額外降權。動漫新詞及需降權的碰撞詞不參與 Bigram 訓練，詞頻至多 0.01 且低於既有完整同音詞，不強制低於拆詞路徑。使用者指定固定 131 篇總動作增加 **至多 30 次可採用、超過 30 次不採用**，文章與基本字差異列診斷、不另設硬門檻。超標時保留原 DB、只 commit 候選清單與拒用原因；最新結果見 `DataSource/AISyntheticBigram/rebuild-review/latest.json`。
- 自訂詞來源合併進 master 後由 `.github/workflows/rebuild-keykey-db.yml` 重建；來源界線、固定 Git 基底與本機入口見 `docs/KEYKEY_DATABASE_WORKFLOW.md`。重建產物與拒用報告須在工作分支提交，再以 PR 合併，不另存 DB artifact。既有 workflow 的直接回存 master 步驟尚待遷移；遷移前不得按舊流程執行；總動作增加超過 30 次時僅提交拒用報告，DB 維持原版。`collection-unigram.tsv` 是產物，修改原始分類詞庫及覆寫表；不可對同一 DB 反覆累加補償。
- 不直接改 `DataSource/McBopomofo/phrase.occ` 或 `BPMFMappings.txt`；專案補充詞、讀音覆寫及語料放在 `DataSource/AISyntheticBigram/`。
- 變更模型時同步更新正式 DB、`smart-mandarin-model-manifest.json`、目前 131 篇驗證結果及內容雜湊。不能只看資料列數判斷新舊；所有字級／文章差異需明列，採用依使用者最新 30 次總動作門檻。
- 量測工具入口與動作定義見 `DataSource/AISyntheticBigram/TYPING_COST.md`。`measure-typing-cost.py ARTICLE VERSION` 量單篇；批次工具先固定樣本、完整分析，再比較全域候選。模型調整程式不得覆寫來源 DB。
- `verify-smart-mandarin-db.py` 驗證固定雜湊、完整性、資料列與首音節；`verify-shared-database-wiring.py` 驗證本儲存庫五個 frontend 都使用同一份 DB。iOS archive、Android asset、macOS App、Windows 打包目錄及 Linux 安裝後改名檔仍須各自核對。
- Android 私有 DB 檔名是更新快取邊界；換模型時必須變更檔名或加入內容校驗。Windows 的 `keykey_database_deploy` 必須在 DB 更新但 DLL 未重新連結時同步打包目錄。

## 工作區與提交

- 不得直接在 `master` commit，也不得直接 push 到 `master`。所有變更（包括修正、文件與 CI workflow）都在工作分支 commit 和 push，再透過 PR merge 合併到 `master`。同步 `master` 時在工作分支拉取 `origin/master`；拉取不代表可以直接在 `master` 提交。
- PR 必須由使用者親自 review 和 merge；agent 不得自行合併 PR、啟用 auto-merge 或繞過使用者審查。
- macOS 正式版發布成功後，自動驗證原包與簽章並建立更新 feed 工作分支／PR；Linux 正式 Release 的 CI／套件發布成功後，自動核對來源、套件生命週期、版本／架構與 GitHub／CDN 校驗資料，再建立 Linux／FreeBSD stable 公告 PR。兩者都保留手動補救入口；其他平台由維護者請 AI 準備 feed PR。所有 feed PR 仍須由使用者親自 review／merge，不直接回存 master 或部署 CDN；merge master 後才由 Actions 同步 CDN。保留 SHA-256 內容位址副本，不覆蓋已發布的 beta 安裝包。Linux／FreeBSD 共用 `update/CHANNEL/unix-fcitx5.xml`，每週檢查並同步公告；不延後 FreeBSD 公告，不檢查 ports/pkg 可用性、不新增排程，須提示透過 ports/pkg 更新且套件可能較晚上架。
- 使用者文件與更新紀錄按正式產品版號整理，不記錄 beta 輪次與逐次測試／除錯過程。`CHANGELOG.md` 以版號識別版本，不加「未發布」標示；實際發布狀態另於 README、安裝指南及平台文件維護。發布工具需要的測試頻道規格使用通用 `X.Y.Z-betaN` 格式，不綁定某次測試版或公告時間。
- 開發計畫、測試規劃與開發評估文件集中於根目錄 `docs/`；集中後的檔名須包含可辨識的平台或功能前綴。根目錄保留 README、安裝／建置指南、更新紀錄、重要宣告與 AGENTS；搬移時同步修正連結、CI、封裝與文件產生器路徑。
- 此流程配合 Certum 本機簽章、人工發布核准與變更審查要求；原始碼、建置腳本及 CI 設定都納入審查。角色與簽章流程見 [CODE_SIGNING_POLICY.md](CODE_SIGNING_POLICY.md)。
- 先執行 `git status --short --branch`，保留使用者既有修改。只逐檔 `git add` 本次內容，不用 `git add .` 或 `git add -A`。
- 提交前檢查 diff、`git diff --check` 與測試結果。提交身分沿用儲存庫設定，不加入工具署名或 `Co-Authored-By`。
- 建置目錄、`.typing-cache/`、`typing-benchmarks/`、`Installer/local-builds/`、影片、API 請求與執行紀錄是產物，不提交。不要提交 API 金鑰。
- 授權範圍以 [LICENSING.md](LICENSING.md) 為準；Yahoo 舊碼與衍生修改保留 BSD 3-Clause 標頭，原創 frontend 與第三方資料維持各自授權。

## 平台架構

| 平台 | 好打注音執行路徑 | 語言模型來源 |
|---|---|---|
| macOS | `OSX-IMK` 與 Guanyinma Rust core | 共用 `KeyKey.db` |
| Windows | `Windows-TSF` 與 Guanyinma Rust core | 共用 `KeyKey.db` |
| iOS | `iOS-Keyboard/KeyKeyEngine` Swift adapter 與 Guanyinma Rust core | 鍵盤 extension 內的共用 `KeyKey.db` |
| Android | `Android-IME` Java／JNI adapter 與 Guanyinma Rust core | APK asset 內的共用 `KeyKey.db`，安裝時複製到私有目錄 |
| Linux／FreeBSD | `Linux-IME` 的 Fcitx 5 adapter 與 Guanyinma Rust core | 共用 DB 安裝時改名為 `smart-mandarin.db` |

六平台固定使用 Guanyinma 單核心，不提供舊輸入引擎選擇或失敗回退。各 FE 的設定、事件與宿主交易仍有差異；修改詞頻、Bigram、backoff、候選排序或 9／10／11 音節邊界時，核心在各目標無 UI 驗證，受影響 FE 分別做接合檢查，不能從單一平台推定其他平台。

## 輸入行為界線

- 「中文模式忽略 Caps Lock（微軟新舊注音）」在 Windows 一般設定預設開啟，涵蓋四種中文輸入法；英文模式保留 Caps Lock 大小寫功能。其他平台若日後實作同選項，預設須關閉。
- 桌面與實體鍵盤保留最多十個已完成音節，第十一音節完成時擠出最前方完整詞段並固定下一詞段。固定回歸句為「請假要去哪裡玩呢去海邊因為那裡有比基尼」；檢查第 10、11、19 音節及全文無漏字或重複字。詳見 `docs/SMART_MANDARIN_PHYSICAL_KEYBOARD_HANDOFF.md`。
- iOS／Android 觸控鍵盤維持九／十音節邊界；已擠出的前段不可被後續選字或 Backspace 修改。句中選字只改候選目標，後續輸入仍接在句尾。候選窗開關、切換 App／輸入法、未完成讀音及生命週期重複回呼都須另測。
- Android 實體鍵盤的「啟用好打注音雙排選字」預設關閉，僅在未使用浮動候選窗時生效；啟用後沿用觸控好打注音的九／十音節與 host-text 流程，上排 9 格組字區及 Emoji、ㄅ／英、▼。下方固定保留既有數字鍵列，候選覆蓋同一列、不動態增高；數字符號鍵選項控制是否另保留符號列。一般實體模式仍依前述十／十一音節規則；切換模式須先保留舊組字。
- iOS extension 不接收一般 USB／藍牙鍵盤事件；實體鍵盤編輯器只存在容器 App 前景。引擎測試不能代替 App、extension、模擬器或實機驗證。
- Linux 的 unit、staged install、X11 與 GNOME Wayland 是不同證據層級；Windows TSF 必須在 Windows 文字宿主驗證。詳細平台差異見 `Source/Loaders/Linux-IME/docs/` 與各 frontend README。

## 建置與驗證入口

```sh
# 共用模型，只驗證、不重建
make -C Source/Distributions/Takao/DatabaseCooker
python3 Source/Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py \
  Source/Distributions/Takao/CookedDatabase/KeyKey.db
python3 Source/Distributions/Takao/DatabaseCooker/verify-shared-database-wiring.py

# macOS
python3 update/prepare.py fetch macos
bash update/test-macos.sh
(cd Source && xcodebuild -project Takao.xcodeproj \
  -target 'Takao (Loader OSX-IMK)' -configuration Release \
  -xcconfig Takao-macOS.xcconfig build)

# macOS 符號表（隔離 AppKit 初始化順序，不連已安裝 IMK）
python3 Source/Loaders/OSX-IMK/Tests/run-symbol-controller-tests.py

# iOS 引擎
bash Source/Guanyinma/tools/test-ios-swift-package.sh

# Android
(cd Source/Loaders/Android-IME && ./gradlew lintDebug testDebugUnitTest assembleDebug)

# Linux（需 Fcitx 5 開發依賴）
(cd Source/Loaders/Linux-IME && ci/build-and-test.sh)
```

完整依賴與發布流程見 [BUILDING.md](BUILDING.md)。Windows 使用 `Source/Loaders/Windows-TSF` 的 CMake presets。
Windows 建置前準備 `python update/prepare.py fetch windows`。桌面自動更新檢查預設開啟，保留使用者既有關閉設定；所有桌面版按上次嘗試時間每 7 天檢查一次，更新程式啟動後至少等 10 分鐘；未到期直接排至滿 7 天，不逐分鐘輪詢，保留上次嘗試與關閉設定。beta 頻道仍預設關閉，
key／feed 未設定時不得連網；正式啟用與各平台簽章驗收見 [update/README.md](update/README.md)。
Windows／macOS／Linux 的排程檢查只通知新版，不預先下載安裝包或自動安裝；使用者按下更新後才下載與安裝。Linux／FreeBSD 維持官方下載頁及套件管理器流程。
macOS preinstall 退出舊行程後，系統仍可能在 payload 覆蓋完成前重啟 IMK；postinstall 須比較執行中詞庫 descriptor 與安裝位置的 device／inode，只正常退出持有已替換詞庫的固定位置行程。安裝器不自動註冊或恢復啟用狀態；全新、手動升級與程式內更新完成後均須登出再登入。升級保留原有來源，不以移除重加通過驗收。
手動同版本下載入口只有使用者明確按下「重新安裝目前版本…」時才查詢官方 Release，
不依賴自動更新 key／feed；只開啟相同版號／架構的下載頁，不自行下載或啟動安裝器。
Windows stable 在 Authenticode 尚未就緒時可逐版明確宣告 `unsigned-transition`，仍須
Ed25519 安裝包簽章、HTTPS、review／tag／版本驗證與不可變資產；無效或不受信任簽章不得
降級成 unsigned。日後 signed EXE 使用更高版號，沿用原 stable feed 與 Ed25519 金鑰。

### macOS 安裝程式的 VM 實測

- 修改 macOS 安裝 helper、`preinstall`／`postinstall`、Distribution 或封裝腳本時，必須用可恢復的 VM 快照完成實際安裝與中文輸入驗證，不能只以單元測試、建置成功、安裝前置評估或 receipt 版號判定通過。
- 快照 a 是已備妥中文字型、尚未安裝 KeyKey 的乾淨系統；快照 b 須先安裝可全新安裝的正式 1.3.1，再升級至正式 1.3.7，確認原有輸入法已啟用且可輸入中文。保留兩份基準快照，每個情境各自建立工作副本。
- 三條必測路徑：快照 a 全新安裝最新版；快照 b 以最新版 PKG 手動安裝升級；快照 b 從 1.3.7 輸入法內下載更新並按「安裝並重新啟動」。程式內更新須實際走下載、驗章、管理員授權及安裝，不能以 CLI 安裝代替。
- 三條路徑使用與最終提交來源相同的安裝包，記錄來源 commit、SHA-256、已安裝 App／receipt 版本、安裝日誌、啟用狀態及實際中文組字、候選、選字與提交結果；另記錄是否需登出再登入或重新開機。含未提交修正的測試包，不能當成 PR 相同來源已驗收。
- **僅修改 GitHub Actions workflow 時，不要求為該次 workflow 變更額外跑 VM**；按 workflow 的實際變更做相應檢查。若同時修改安裝程式，安裝程式部分仍須完成上述 VM 實測。
- 建置環境、字型補齊、關機快照與還原、三條驗收路徑及注意事項見 [macOS 安裝器 VM 操作指南](docs/MACOS_INSTALLER_VM_TESTING.md)。

### Windows 日常開發測試範圍

- 開始修改前依實際 diff 分類：`tsf` 輸入／候選／原生視窗、`settings` 設定介面／儲存、
  `deployment` 安裝／移除／遷移、`updater` 更新客戶端／feed／簽章、`package` 封裝／CI、
  `docs` 文件。先簡述本次類型與必要驗證，再執行；跨類型只取實際受影響項目的聯集。
- 只建置受影響 target、跑對應測試；TSF 也用 `ctest -R` 選出受影響功能，不預設全套。
  updater 的 feed、發布工具、客戶端分別驗證，不因更動其中一項就全跑三項。
- 日常先驗證目前開發架構（通常 x64）；只有 bitness、ABI、P/Invoke、SDK、平台條件或
  架構打包受影響時才加 x86。既有原生後端未變時可供設定 UI 回歸使用，不重建 TSF。
- 純文件只檢查 diff／連結；單純搬移路徑只檢查引用與必要建置，不重跑功能全套。
  測試通過後，沒有相關新修改、失敗或未解疑慮就不重跑；不要重複執行 CTest 已涵蓋的
  dotnet 測試，也不為 Windows 專屬改動跑其他平台、模型或 release-assets 全套。
- 只有明確進入發布驗收才跑 Windows 完整矩陣；不為了結束一次開發修改就打包／安裝。
  共用引擎或模型變更仍按前述跨平台／模型規則驗證。各類命令與必要擴充條件見
  [Windows 開發型態與測試](Source/Loaders/Windows-TSF/README.md#windows-日常開發型態與測試)。

## Guanyinma 核心與 Rust 遷移行為基準

- Guanyinma 正式 Rust 程式碼的無 UI 行涵蓋率維持 **92% 以上**，以 `tools/test-coverage.py` 在原生 macOS／system SQLite 的參考量測為準（本機基準為 arm64），排除測試與依賴，僅補有價值的行為測試、不強追 100%，門檻只接在 `guanyinma-core.yml`。六平台 Rust workflow 接線與不編譯核心的發布／同步流程界線見 `Source/Guanyinma/README.md` 的測試分工表；macOS 正式打包固定連入 Rust、只跑少量 integration FE 接合測試。

- **核心測試範圍**：Guanyinma 核心專注無 UI 的公開介面與行為契約測試，以 Rust unit／整合、真實 C consumer 與無 UI 的原生對照，涵蓋四法、候選排序、選字學習、組字邊界、設定／語意操作、快照／effects、字型接受回呼及資料生命週期。核心在各支援平台編譯時都要有足夠的無 UI 測試可執行；交叉編譯成功只算編譯，必須在相應原生 runner／無視窗模擬器執行才算測試通過。
- **六平台 FE 分工**：各平台另測設定與事件映射、座標／宿主交易、原生字型／儲存接合；不要在每個 FE 重跑整套核心演算法矩陣。UI 僅保留少量（數十個）的自動化冒煙案例，於該 FE 接合或修改時執行。核心工作不以大量 FE／實機端到端驗收作完成門檻，不操作使用者桌面或反覆切換其系統輸入法，也不要求使用者逐項代打測試；完整 FE／安裝驗收另行處理。

- 產品全名為 **chichi77 KeyKey／琦琦輸入法**，英文簡稱 **KeyKey**。**Guanyinma** 是新的 Rust 共用核心代號，目標取代 macOS／Windows 的 Manjusri，以及 iOS、Android、Linux／FreeBSD 的既有核心；各平台原生 frontend 接上新核心。Guanyinma 屬於 KeyKey 的核心模組，目錄固定為 `Source/Guanyinma`；局部 Rust／C ABI 驗證見該目錄 README，分階段範圍見 `docs/GUANYINMA_IMPLEMENTATION_PLAN.md`。

- 核心演算法疑義以 macOS Manjusri／Formosa／OpenVanilla 為主要來源；其他平台既有核心與六平台 frontend 作接合及差異參考。核心按互動行為與狀態分類，不新增 OS 專屬演算法分支。平台預設值、實體事件辨識與宿主操作留在 frontend。
- Guanyinma 已提供四種輸入法的共用 session；好打注音組句、候選排序、選詞及整詞擠字以 macOS Manjusri 為準。組字音節上限由 FE 設定 **10～20**，到達或超過上限才擠字由 `shift_at_limit` 行為設定；使用者詞庫及學習使用獨立 Guanyinma DB，按 FE 行為設定啟用；reset 保留自訂詞，舊資料只明確唯讀異檔匯入，不覆寫唯一副本。macOS 四法直接由 Guanyinma package 建立 session，不編譯 Manjusri／Generic 輸入核心，不提供核心選單、建置開關或失敗回退。FE 設定變更等待組字、候選及待送 commit 完成；不重播事件。詞庫管理固定使用 GuanyinmaUserData.db，舊 backend token 必須拒絕；既有舊檔不自動開啟、改寫或刪除。建置與原生隔離測試見 `docs/GUANYINMA_MACOS_ADAPTER.md`；IMK 宿主與其他 frontend 接合仍待完成。macOS 可匯入舊 MJSR 並輸出完整 Guanyinma JSON 備份；容器解碼留在 FE，共用 `UserArchive`／`import_user_data` 先驗證再原子提交，備份不匯入 generation／revision，不覆蓋唯一舊副本。`behaviors` 可開關忽略 Caps Lock 與數字鍵盤直接送字；主鍵盤不能因全域 NumLock 被誤判。單按 Shift 沿用 frontend 判定，再送共用中英切換操作。普通 Rust unit／整合／C ABI 測試驗證實作契約，不讀取遷移基準。
- 快捷鍵辨識及綁定留在 FE；核心提供 `set_full_width(enabled: true/false)`／`toggle_full_width` 與 `set_english(enabled: true/false)`／`toggle_english` 等語意操作。同值 setter 冪等，核心不綁 Shift+Space 或角括號翻頁。macOS 設定／事件覆蓋見 `docs/GUANYINMA_MACOS_BEHAVIOR_COVERAGE.md`；真正 TIS／IMK 宿主與隔離還原流程見 `docs/GUANYINMA_MACOS_IMK_HOST_TEST.md`，不能用 unit 或 mock client 代替。
- 六平台候選可顯示性由 FE 經 `CandidateFilter`／`guanyinma_session_open_with_candidate_filter` 提供；四種輸入法在候選、前綴上限、分頁與好打 graph 之前過濾，不在 UI 另刪候選。macOS 沿用既有字型／編碼服務，iOS 接上原生 CoreText 判斷，Android 接上原生 Paint 字型判斷，Windows 接上 DirectWrite fallback／字集判斷；Linux 共用 Fcitx 5 frontend 已加入 PangoFT2／Fontconfig 與既有注音字集 callback；FreeBSD 原生接合與各桌面宿主驗證仍各自記錄。政策固定於 session，變更時在安全邊界重新建立；不寫入使用者備份。
- **iOS Guanyinma 單核心**：鍵盤 extension 與 App 實體鍵盤編輯器共用 `KeyboardInputEngine`，固定使用 Rust，不建置舊 Swift 解析／walker／排序／學習引擎，不提供核心切換或失敗回退。Swift 僅保留 FE 型別、事件與宿主效果接合。App Group 的 `SharedPhrasePublication` 只由 App 寫入，extension 唯讀同步至私有 `GuanyinmaUser.db`，維持不要求完整取用；詞庫發布沒有學習演算法。舊詞庫與學習檔不自動改刪，保留明確 MJSR 自訂詞交換。接合與建置入口見 `docs/GUANYINMA_IOS_ADAPTER.md`；host smoke、iOS 編譯與真正宿主驗證分開記錄。
- **Android Guanyinma 單核心**：同一 IME service／FE 固定使用 Rust，不建置舊 Java 解析／walker／排序／學習引擎，不提供核心切換或失敗回退。觸控與實體雙排用 touch 行為，一般實體鍵盤用 desktop 行為。只有原 `InputConnection` 接受本次宿主效果後才 acknowledge，無宿主／拒絕操作不重播，於真正新宿主邊界明確 abandon。App／IME 在同沙箱共用 `GuanyinmaUser.db`；舊 Java 資料不自動改刪，保留明確 MJSR 自訂詞交換的薄轉換。JNI 使用標準 UTF-8、明確所有權及原生字型 callback，Android 使用私有 bundled SQLite，不連結平台私有 SQLite。建置及少量 host JNI smoke 見 `docs/GUANYINMA_ANDROID_ADAPTER.md`；不得把 host JNI 或交叉編譯稱為 Android runtime／實機驗收。
- **核心 CI 權責與增量方式**：完整 Guanyinma Rust unit／整合、C ABI 與跨平台核心矩陣，在 CI 中統一由 `.github/workflows/guanyinma-core.yml` 負責。其他平台 workflow 直接依鎖定工具鏈與 `Cargo.lock` 編譯、連結並使用核心，只跑少量 FE 串接冒煙（載入／建立 session、設定或事件映射、一次送字及釋放），不重跑完整核心測試，也不轉呼叫完整核心 workflow。新增接合採小幅增量，保留既有平台建置、封裝與發布 workflow 的結構；本機核心開發仍可使用獨立測試入口。
- **Linux／FreeBSD Guanyinma**：Fcitx 5 frontend 只使用 Guanyinma Rust 核心，不再建置 Legacy C++ walker、排序或可寫學習庫，也不提供核心切換或失敗回退。C++ 僅保留 Fcitx／原生字型、關聯詞、繁簡輸出及資料轉換接合。Rust 是必要建置依賴；`linux-release` 與無視窗 `engine-only` 均使用同一核心。設定參考 macOS／Windows 桌面偏好；關聯詞只使用 `[AssociatedPhrases]` Boolean 分組，建置與 CLI 不提供核心選擇相容參數。使用者資料固定 `guanyinma-user.db`，CLI 預設操作 Guanyinma；不再支援舊 Linux C++ 使用者資料庫的讀寫、匯入或相容命令，既有舊檔不自動刪除。FE 設定變更仍等待組字、候選及待送效果完成；不重播宿主效果。完整核心矩陣不在 Linux FE workflow 重跑。FreeBSD 與 GNOME Wayland 原生驗收各自記錄，不能由 Linux X11 推定通過。建置與設定見 `docs/GUANYINMA_LINUX_ADAPTER.md`。
- **Windows Guanyinma 單核心**：同一 TSF FE 的四種輸入法固定使用 Guanyinma，不提供核心切換、舊核心建置或失敗回退；舊 `InputCore` 偏好與 v3 快照欄位不影響核心選擇。Rust 使用 `GuanyinmaUserData.db`；完整 JSON 備份及明確唯讀匯入舊 Windows 詞庫均經 C ABI，舊檔不自動修改。DirectWrite fallback／字集 callback 在核心排序前過濾。x64／x86 的 Rust 與原生 FE 共用鎖定 bundled SQLite／靜態 CRT，不混用 WinSQLite 的 x86 stdcall ABI。設定及宿主 retained effects 仍沿用既有有序交易邊界，不重播。入口與驗證界線見 `docs/GUANYINMA_WINDOWS_ADAPTER.md`。
- `tests/run_core_functional.py` 與 `tests/fixtures/core-functional/` 僅供 Rust 重寫／升級時手動擷取和比較現有行為；不得加入日常驗證、預設 CTest、CI gate 或發布驗收。一般測試維持既有入口。
- 基準分別保存各核心的四種輸入法、完整候選順序與選字學習；既有平台差異及已觀察到的不穩定排序也保留，不將其自動統一成新產品規則。重新擷取不得自動覆寫，須明確指定並審查差異。使用方式及邊界見 `docs/CROSS_PLATFORM_CORE_FUNCTIONAL_TESTS.md`。

## 改版號清單

程式、封裝與測試不得另行寫死產品版號，一律讀取各平台既有版號來源；測試需要版號時也沿用該來源，不新增專門驗證版號解析、字串或同步傳遞的案例，不因升版重跑這類測試。

`README.md` 只列正式 Release／商店版本，不在標題或內文列開發版號；封裝與測試讀取各平台版號來源，不解析 README。macOS 封裝從 IMK plist 讀取版本並核對四份產品 plist；Windows 封裝從 TSF `CMakeLists.txt` 讀取版本，Android 封裝從 `Android-IME/app/build.gradle.kts` 讀取版本，iOS 封裝從 Xcode project 的 `MARKETING_VERSION` 讀取版本。個別平台升版時不可連帶修改其他平台或模型版號。升版時同步檢查：

| 平台 | 版號來源 |
|---|---|
| macOS | 四份產品 plist 的 `CFBundleVersion`、`CFBundleShortVersionString` |
| Windows | TSF `CMakeLists.txt` 為唯一來源；封裝、設定組件與可見 footer 自動取用，升版時核對產物 |
| iOS | Xcode project 的 App／extension `MARKETING_VERSION` |
| Android | `build.gradle.kts` 的 `keyKeyVersionName`、`keyKeyVersionCode` |
| Linux | `Linux-IME/CMakeLists.txt`、支援矩陣及版本化套件／測試腳本 |

再核對文件範例、打包後的實際版本及發行流程；GitHub Release、App Store、Google Play 的現況不能由原始碼版號推定。

## 專題文件

- [CHANGELOG.md](CHANGELOG.md)：各平台版本變更。
- `DataSource/AISyntheticBigram/SMART_MANDARIN_MODEL_V1_3_1.md`：正式模型來源與固定 130 篇結果。
- `DataSource/AISyntheticBigram/TYPING_COST.md`：動作數工具與可重現評估方式。
- [Linux／FreeBSD Guanyinma 接合](docs/GUANYINMA_LINUX_ADAPTER.md)：現行桌面偏好、使用者資料及聚焦驗證。
- [歷史交接紀錄](docs/AGENTS_HISTORY.md)：舊版逐日紀錄與已完成除錯細節。
