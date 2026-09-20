# 五平台心經長文 functional test

這個案例使用同一份 [逐字注音稿](heart-sutra.annotated.txt) 檢查 macOS、Windows、Android、iOS、Linux 的**真實輸入法**。共 268 個注音字，包含重複詞、四聲、空格分段、多個標點與少見字。整篇打完才算完成；只打「中」或「你好」不算通過。

## 開始前

1. 安裝並啟用本次要驗的版本，記下平台、產品版號、作業系統版號和測試日期。
2. **將所有關聯詞庫關閉**，包含基本小麥注音詞庫和所有分類詞庫。在 iOS 要改的是 keyboard extension 自己的詞庫設定；容器 App 的實體鍵盤編輯器設定不會同步到 extension。選完一個字後應沒有關聯詞候選。這項前置設定須記在平台報告內。
3. 執行 `python3 tests/heart_sutra.py check-dictionary`，確認這 268 組讀音在共用字表中。用 `python3 tests/heart_sutra.py plan` 查看每個目標字在原始字表的**絕對候選順位**（從 1 起算）。建立 `captures/` 目錄後，用 `python3 tests/heart_sutra.py template > captures/macos.positions.tsv` 建立空白觀測表（其他平台換檔名），逐字將問號填為實際看到的順位。預期順位不能直接當成實際觀測值。
4. 開啟純文字、可輸入多行的欄位。先清空內容並確認切到琦琦注音、繁體、標準注音配置。候選頁預設九字；若平台設定曾改過選字鍵或每頁數量，先還原預設。測試中不要貼上預期全文，也不要由程式直接填入欄位；每個漢字都必須由注音組字與候選選字產生。

| 平台 | 建議的實際輸入欄位 | 擷取檔名 |
| --- | --- | --- |
| macOS | TextEdit 的純文字文件 | `macos.txt` |
| Windows | Notepad 的純文字文件 | `windows.txt` |
| Android | 備忘錄或任何支援多行文字的 App；使用琦琦注音軟鍵盤 | `android.txt` |
| iOS | 備忘錄的多行編輯欄位；使用琦琦注音 keyboard extension | `ios.txt` |
| Linux | Ubuntu 24.04 GNOME Text Editor／gedit 的純文字文件；使用 Fcitx 5 琦琦注音 | `linux.txt` |

iOS 外接鍵盤無法由第三方 keyboard extension 接管；若要另驗 iOS App 內實體鍵盤編輯器，可追加第二輪，但上表的 iOS capture 必須先由 extension 在其他 App 的真實欄位完成。Linux 若測 GNOME Text Editor，應記錄使用的 Wayland／XWayland 與 Fcitx 輸入路徑；某些路徑有已知 active input context 限制。

## 執行與驗收

1. 依逐字注音稿從標題到最後「菩提薩婆訶」逐字輸入。每一組左邊是注音，右邊是目標字；若候選第一個不是目標字，必須在候選列選對。標點也要輸入。稿中的換行只是閱讀分段，輸入時可自行換行。
2. **每一字在選取前記錄實際候選順位**，含重複出現的字。觀測檔每行為 `序號<TAB>注音<TAB>目標字<TAB>實際順位`，無表頭，共 268 行；檔名為 `macos.positions.tsv` 等。單一候選自動提交記為 1。第 2 頁第 9 格記為絕對順位 18；不要把頁內格號 9 誤記成 18。這同時檢查同一平台長文輸入後的順位是否改變。
3. 期間至少在「色不異空」與「菩提薩婆訶」兩處確認候選視窗能顯示、選字後消失、已輸入內容沒有重複或遺失。若發生卡住、閃退、候選失焦、錯字難以選取，記下當時平台、讀音與目標字，並保留畫面或 log。可用同一輸入法修正錯字，再繼續到全文末尾。
4. 從編輯器將**實際輸入結果**存成 UTF-8 純文字，放在同一個 capture 目錄，使用上表檔名。不要用 `render` 的輸出充當實測 capture。
5. 單一平台驗收：`python3 tests/heart_sutra.py check macos captures/macos.txt captures/macos.positions.tsv`（平台名可換成 `windows`、`android`、`ios`、`linux`）。五平台一起驗收：`python3 tests/heart_sutra.py check-all captures/`。

比對器會忽略空白與換行，因為不同編輯器的分段方式可能不同；其餘每個漢字及標點都要與原稿完全相同。它也逐行比對五平台的實際候選順位與共用字表的基準順位；因此五平台通過時，每個純注音選字位置就相同。少字、錯字、順位不同、只打開頭、缺少平台檔案都會失敗，並指出第一處差異。`render` 命令只供查看預期中文全文：`python3 tests/heart_sutra.py render`。

五平台報告須附每個平台的文字 capture、候選順位觀測檔、`check-all` 結果、版本與執行環境。**字表檢查、單元測試、模擬器建置或把預期文字直接貼進欄位，都不能列為五平台 functional test 通過。**

目前的實測紀錄：[macOS 1.2.9／TextEdit（2026-09-20）](results/2026-09-20-macos/README.md)。其餘四平台尚未執行本案例。

## 開發機自動化入口

- **macOS：開發機 MacBook** 先安裝並選用琦琦注音，在設定中關閉全部關聯詞庫，然後執行 `python3 tests/run_macos_heart_sutra.py --output /tmp/keykey-macos-heart-sutra`。腳本先確認目前輸入來源和詞庫設定，不會改動這兩項偏好；接著在 TextEdit 逐鍵打完 268 字，每字提交後讀取實際文字並核對前綴。只有全文成功才留下 `macos.txt`、`macos.positions.tsv`。本機需允許執行腳本的終端機透過 System Events 控制 TextEdit，並保持該文件在前景。
- **iOS：開發機 MacBook** 使用 shared scheme `chichi77 KeyKey` 的 `KeyKeyHeartSutra.xctestplan`，在本機 iOS 17 Simulator 跑 `testHeartSutraKeyboardExtension`。測試自己透過系統設定加入第三方鍵盤，切到真實 extension，從 extension「設」關閉全部關聯詞庫，再逐字點注音與候選；全文及 268 筆順位會附在 `.xcresult`。測資由 [產生器](generate_ios_heart_sutra_fixture.py) 從共用心經稿與 CIN 產生，執行前可用 `--check` 確認一致。完整命令見 [iOS 開發說明](../Source/Loaders/iOS-Keyboard/README.md)。此專用測試不加入 Xcode Cloud。

本機已驗證乾淨的 **iOS 17.0 Simulator** 可由 XCUITest 自動加入並切換到琦琦 extension；**iOS 26.5 Simulator** 可以加入，但既有切換測試被系統略過，不能視為通過。專用心經測試若無法切換到 extension 會直接失敗，不會略過。以上 iOS XCUITest 在容器 App 的真實多行測試欄位中使用系統安裝的 keyboard extension；它不以容器 App 實體鍵盤編輯器替代 extension。

2026-09-20 的 iOS 心經全文試跑依使用者要求中斷；沒有完整 `.xcresult` 驗收或 `ios.txt`／`ios.positions.tsv`，因此 iOS 仍未通過本案例。
