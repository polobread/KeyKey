# AGENTS.md — 開發指引

此檔只記錄目前仍適用的規則、模型決策與驗證入口。逐日進度、舊版測試數字及已完成的除錯紀錄在 [歷史交接紀錄](docs/AGENTS_HISTORY.md)，不能當成現況或發布驗收。開始工作時先看目前分支、程式碼、`CHANGELOG.md` 與相關平台文件。

目前工作分支及產品版號為 `v1.3.1`。macOS、Windows、iOS、Android、Linux 必須依各自流程建置與驗證；原始碼、建置產物、已安裝版本及實機行為是不同層級，不可互相代替。

## 好打注音模型決策

- 本儲存庫五個 frontend 共用預先產生的 `Source/Distributions/Takao/CookedDatabase/KeyKey.db`；平台建置只驗證及複製，不得自行 cooker。正式資料庫有 **114,392 筆 Unigram、885,627 筆 Bigram**，SHA-256 為 `28b18de318ac13eece6a0631c92d5e468c8bb4c5eeba11283287493b81bcc252`。
- Bigram 建模固定使用 `typing-articles-v2.jsonl`、`v3.jsonl`、`v4.jsonl` 共 **2,300 篇**。正式驗證固定使用 `typing-articles-v5-seed/tw-corpus-0001.md` 至 `0130.md` 共 **130 篇**，排除 `chat.md`；訓練與驗證沒有相同文章或 20 字以上相同段落。800／750／750 只屬已結束的 unigram 實驗分割，不再作為目前 Bigram 的建模或驗證依據。
- 每篇文章、每個模型都啟動全新引擎程序，關閉 user table、Bigram learning 與 candidate override，測試間不得共享記憶。正式動作模型採 5 音節穩定、10 音節組字範圍、每頁 8 個候選；注音鍵、確認、點字開候選、選字及翻頁都計入。輸出須包含總動作、額外修正動作、修正字及各自成本；總動作越少越好。
- Bigram 約只能影響仍在組字區內的 9～10 個字，不能期待後文完全救回前面的同音字。優先降低核心 83 字、前 100 名基本字與第 101～1,000 名一般字的修正；第 1,001～1,500 名、未排名罕字、專業詞及專有名詞只列診斷，不決定基礎模型是否採用，這些內容可由使用者學習改善。
- 調整前先分析整批錯誤分布，再訂一條適用全體的規則並重跑完整驗證。不得看一篇修一篇、對單一 Bigram 邊加補丁，或只用總分掩蓋基本字、題材或個別文章的退步。隨機 50 篇可作快速探索，不能取代固定 130 篇驗收。
- v1.3.1 以 McBopomofo unigram 為基準，只依 2,300 篇的跨文章證據調整既有 Bigram；122 個基本／常用字的 191 個讀音保留基準 Bigram，共保護 208,222 筆。另收錄經整體驗證的 7 個常用詞補充，以及搜尋熱門詞 550 詞去除 393 個既有詞後的 157 詞保守補充。
- 固定 130 篇結果為總動作 **331,619 → 331,062（-557）**、額外修正動作 **11,000 → 10,443（-557）**；97 篇改善、19 篇相同、14 篇退步，節省 623、增加 66。搜尋熱門詞層另少 6 次動作，3 篇改善、127 篇相同、0 篇退步。正式細節在 `DataSource/AISyntheticBigram/SMART_MANDARIN_MODEL_V1_3_1.md` 與 `DataSource/AISyntheticArticles/typing-articles-v5-manifest.json`。
- 自建 unigram、全域混合、剪枝、字級先驗及順位校準雖曾降低總動作，但在基本字分布、跨題材穩定性或外部驗證門檻失敗，因此都未取代正式基準。直接 unigram 順位問題主要集中於「做／作、新／心、裡／理、向／像」；「在／再、是／事、時／十」多數是上下文、多字候選或斷詞問題，應由整體語料與 Bigram 處理。既有 3,000 份外部提示已全部用過，下一次採用新規則需要新的完整自然文章 holdout，不能再宣稱舊資料是盲測。
- 慣用讀音先依本地詞庫與臺灣輸入習慣判斷，可先請 ChatGPT 分析；只有仍有疑義或本地資料互相衝突時才個別查教育部辭典，不批次查詢。破音字須依文章語境固定實際慣用讀音。

## 模型維護

- 不直接改 `DataSource/McBopomofo/phrase.occ` 或 `BPMFMappings.txt`；專案補充詞、讀音覆寫及語料放在 `DataSource/AISyntheticBigram/`。
- 變更模型時同步更新正式 DB、`smart-mandarin-model-manifest.json`、130 篇驗證結果及內容雜湊。不能只看資料列數判斷新舊，也不能把罕見字改善換成基本字退步。
- 量測工具入口與動作定義見 `DataSource/AISyntheticBigram/TYPING_COST.md`。`measure-typing-cost.py ARTICLE VERSION` 量單篇；批次工具先固定樣本、完整分析，再比較全域候選。模型調整程式不得覆寫來源 DB。
- `verify-smart-mandarin-db.py` 驗證固定雜湊、完整性、資料列與首音節；`verify-shared-database-wiring.py` 驗證本儲存庫五個 frontend 都使用同一份 DB。iOS archive、Android asset、macOS App、Windows 打包目錄及 Linux 安裝後改名檔仍須各自核對。
- Android 私有 DB 檔名是更新快取邊界；換模型時必須變更檔名或加入內容校驗。Windows 的 `keykey_database_deploy` 必須在 DB 更新但 DLL 未重新連結時同步打包目錄。

## 工作區與提交

- 先執行 `git status --short --branch`，保留使用者既有修改。只逐檔 `git add` 本次內容，不用 `git add .` 或 `git add -A`。
- 提交前檢查 diff、`git diff --check` 與測試結果。提交身分沿用儲存庫設定，不加入工具署名或 `Co-Authored-By`。
- 建置目錄、`.typing-cache/`、`typing-benchmarks/`、`Installer/local-builds/`、影片、API 請求與執行紀錄是產物，不提交。不要提交 API 金鑰。
- 授權範圍以 [LICENSING.md](LICENSING.md) 為準；Yahoo 舊碼與衍生修改保留 BSD 3-Clause 標頭，原創 frontend 與第三方資料維持各自授權。

## 平台架構

| 平台 | 好打注音執行路徑 | 語言模型來源 |
|---|---|---|
| macOS | `OSX-IMK`、`OVIMSmartMandarin`、Manjusri C++ | 共用 `KeyKey.db` |
| Windows | `Windows-TSF`、`OVIMSmartMandarin`、Manjusri C++ | 共用 `KeyKey.db` |
| iOS | `iOS-Keyboard/KeyKeyEngine` Swift walker | 鍵盤 extension 內的共用 `KeyKey.db` |
| Android | `Android-IME` Java walker | APK asset 內的共用 `KeyKey.db`，安裝時複製到私有目錄 |
| Linux | `Linux-IME` 的 Fcitx 5 C++ walker 與 adapter | 共用 DB 安裝時改名為 `smart-mandarin.db` |

macOS 與 Windows 共用框架和注音模組；iOS、Android、Linux 各有組句 frontend。修改詞頻、Bigram、backoff、候選排序或 9／10／11 音節邊界時，必須分別驗證，不能從單一平台推定其他平台。

## 輸入行為界線

- 桌面與實體鍵盤保留最多十個已完成音節，第十一音節完成時擠出最前方完整詞段並固定下一詞段。固定回歸句為「請假要去哪裡玩呢去海邊因為那裡有比基尼」；檢查第 10、11、19 音節及全文無漏字或重複字。詳見 `docs/SMART_MANDARIN_PHYSICAL_KEYBOARD_HANDOFF.md`。
- iOS／Android 觸控鍵盤維持九／十音節邊界；已擠出的前段不可被後續選字或 Backspace 修改。句中選字只改候選目標，後續輸入仍接在句尾。候選窗開關、切換 App／輸入法、未完成讀音及生命週期重複回呼都須另測。
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
(cd Source && xcodebuild -project Takao.xcodeproj \
  -target 'Takao (Loader OSX-IMK)' -configuration Release \
  -xcconfig Takao-macOS.xcconfig build)

# iOS 引擎
(cd Source/Loaders/iOS-Keyboard/KeyKeyEngine && swift test)

# Android
(cd Source/Loaders/Android-IME && ./gradlew lintDebug testDebugUnitTest assembleDebug)

# Linux（需 Fcitx 5 開發依賴）
(cd Source/Loaders/Linux-IME && ci/build-and-test.sh)
```

完整依賴與發布流程見 [BUILDING.md](BUILDING.md)。Windows 使用 `Source/Loaders/Windows-TSF` 的 CMake presets。

## 改版號清單

`README.md` 標題是對外版本入口。升版時同步檢查：

| 平台 | 版號來源 |
|---|---|
| macOS | 四份產品 plist 的 `CFBundleVersion`、`CFBundleShortVersionString` |
| Windows | TSF `CMakeLists.txt`、`Package-Windows.ps1`、設定專案與可見 footer |
| iOS | Xcode project 的 App／extension `MARKETING_VERSION` |
| Android | `build.gradle.kts` 的 `keyKeyVersionName`、`keyKeyVersionCode` |
| Linux | `Linux-IME/CMakeLists.txt`、支援矩陣及版本化套件／測試腳本 |

再核對文件範例、打包後的實際版本及發行流程；GitHub Release、App Store、Google Play 的現況不能由原始碼版號推定。

## 專題文件

- [CHANGELOG.md](CHANGELOG.md)：各平台版本變更。
- `DataSource/AISyntheticBigram/SMART_MANDARIN_MODEL_V1_3_1.md`：正式模型來源與固定 130 篇結果。
- `DataSource/AISyntheticBigram/TYPING_COST.md`：動作數工具與可重現評估方式。
- `Source/Loaders/Linux-IME/docs/smart-mandarin-platform-review.md`：跨平台好打注音行為差異。
- [歷史交接紀錄](docs/AGENTS_HISTORY.md)：舊版逐日紀錄與已完成除錯細節。
