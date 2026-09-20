# macOS 心經 functional test：PASS

- 日期：2026-09-20（Asia/Taipei）
- 系統：macOS 27.0，build 26A428
- 輸入法：已安裝的琦琦注音 1.2.9（`io.github.polobread.inputmethod.chichi77`）
- 實際欄位：TextEdit 新建文件；標準注音配置
- 測試設定：`EnabledCollections` 暫設空字串，基本與分類關聯詞庫全部關閉

測試將 [逐字注音稿](../../heart-sutra.annotated.txt) 的 268 組讀音轉成標準配置的 macOS 實體鍵碼，逐鍵送入 TextEdit。每個字依共用字表的絕對候選順位翻頁、選字；若 macOS 直接提交唯一可顯示候選，記為第 1 位。每次選字都讀取 TextEdit 的實際文字，核對**從開頭到該字的完整前綴**，並確認候選窗已關閉；`，。、；` 由琦琦注音的 Control 標點快捷鍵輸入，逐個核對。中途任何不符就停止。測試完整跑到最後「菩提薩婆訶。」才保存下列資料：

- [macos.txt](macos.txt)：TextEdit accessibility 讀到的實際輸入全文（未保留閱讀分行）。
- [macos.positions.tsv](macos.positions.tsv)：268 次送出的候選絕對順位；每一筆選字後都已通過文字前綴檢查。

`python3 tests/heart_sutra.py check macos tests/results/2026-09-20-macos/macos.txt tests/results/2026-09-20-macos/macos.positions.tsv` 結果為全文 331 個非空白字元與標點相符，268 筆順位相符。`ㄅㄛ→波` 多次使用第二頁第 9 格，即絕對第 18 位。

結束後已將原先的關聯詞庫勾選值與 ABC 輸入來源恢復；只關閉本次建立的兩份暫存 TextEdit 文件。
