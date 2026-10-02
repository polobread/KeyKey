# 分類關聯詞詞庫

本目錄收錄 KeyKey 內建的 29 份分類關聯詞詞庫。資料以自動化方式生成、推論與整理；
長詞拆分曾做專項 review，但整體沒有全面逐筆人工校正，仍可能包含錯詞、錯音、錯誤
分類、頻率誤差或其他不適當內容。不保證正確性、完整性或適合特定用途，重要用途請
自行查證。

公開資料只保留中文字首、2–5 個 Unicode code point 的詞條。較長原詞只匯入專項
review 明確保留的連續片段，未列出的句子殘片或不完整專名會排除。
`phrase.*.tsv` 的前四欄依序為詞、頻率、讀音與分類；部分資料另有第五欄來源說明。
四個平台建置時都會納入這些檔案，Android 保留 TSV 作為 generated asset，其他平台
則在建置時寫入 SQLite 資料庫。

本目錄以 [MIT License](LICENSE.txt) 授權，但僅涵蓋著作權人有權授權的部分，包括在
具著作權保護時的原創選擇、分類與編排。一般用語、事實、公有領域或其他不受著作權
保護的內容不主張專有權利；本授權也不授予商標權。

## Categorized associated-phrase data

This directory contains the 29 categorized associated-phrase collections built
into KeyKey. The data was generated, inferred, and normalized automatically.
Segmentation of long source terms received a targeted review, but the collection
as a whole has not been comprehensively reviewed or corrected item by item. It may
contain incorrect terms, readings, categories, frequencies, or other unsuitable
material. Accuracy, completeness, and fitness for any particular purpose are
not guaranteed; verify important uses independently.

Public data is limited to entries that start with a Han character and contain
2–5 Unicode code points. Longer source terms contribute only contiguous
fragments explicitly retained by the targeted review; sentence remnants and
incomplete names omitted by that review are excluded. The first four TSV columns
are term, frequency, reading, and category; some data has a fifth
source-description column.

The [MIT License](LICENSE.txt) applies only to material the copyright holder can
license, including original selection, classification, and arrangement where
copyrightable. No exclusive rights are claimed in common expressions, facts,
public-domain material, or other uncopyrightable content, and no trademark rights
are granted.

These collections were built for categorized associated-phrase lookup. The reproducible
experiment in `../AISyntheticBigram/analyze-ai-lexicon-impact.py` found that
loading all 29 collections slightly reduced held-out general-text bigram
coverage because new words and readings changed segmentation. In particular,
the anime collection contains proper names together with work-title fragments
and ordinary phrases.

`bigram` 分支以小麥詞庫為主體，將中文化後的分類詞與搜尋詞依完整詞文字去重。
完整同音的新詞保留低順位候選；兩字碰撞詞降權，長詞的兩字部分重疊只列診斷。
來源檔案維持原樣；重建工具分別產生採用、重複跳過、降權及部分重疊清單，列出小麥衝突詞。
動漫新詞及降權碰撞詞不參與 Bigram 訓練，詞頻至多 0.01；
低於既有完整同音詞，但不強制低於拆字路徑，使用者仍能選字學習。
三份 `phrase.people-contemporary.tsv`、`phrase.people-oldnews.tsv`、`phrase.people-history.tsv`
的人名新詞也在 Bigram 完成後才加入 Unigram；普通人名詞頻至多 1，碰撞／動漫人名至多 0.01。
同一人名若也在搜尋清單，仍按此規則處理；已存在的小麥詞不重複加分。
詳見 [匯入紀錄](../AISyntheticBigram/COLLECTION_UNIGRAM_IMPORT.md)與
[自動重建流程](../../docs/KEYKEY_DATABASE_WORKFLOW.md)。

保留同音候選後，131 篇相對原 DB 增加 16 次，通過 30 次門檻；
人名移至訓練後加入則 131 篇全部不變。最終模型已套用至本機共用 DB，
分類詞新增 4,765 詞，其中三份人名新增 10 詞，其餘 304 筆人名跳過重複。
