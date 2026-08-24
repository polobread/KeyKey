# 分類關聯詞詞庫

本目錄收錄 KeyKey 內建的 29 份分類關聯詞詞庫。資料以自動化方式生成、推論與整理，
沒有逐筆人工校正，可能包含錯詞、錯音、錯誤分類、頻率誤差或其他不適當內容；不保證
正確性、完整性或適合特定用途，重要用途請自行查證。

公開匯入時會排除非中文字首、少於 2 個或多於 20 個 Unicode code point 的詞條。
`phrase.*.tsv` 的前四欄依序為詞、頻率、讀音與分類；部分資料另有第五欄來源說明。
四個平台建置時都會納入這些檔案，Android 保留 TSV 作為 generated asset，其他平台
則在建置時寫入 SQLite 資料庫。

本目錄以 [MIT License](LICENSE.txt) 授權，但僅涵蓋著作權人有權授權的部分，包括在
具著作權保護時的原創選擇、分類與編排。一般用語、事實、公有領域或其他不受著作權
保護的內容不主張專有權利；本授權也不授予商標權。

## Categorized associated-phrase data

This directory contains the 29 categorized associated-phrase collections built
into KeyKey. The data was generated, inferred, and normalized automatically. It
has not been reviewed or corrected item by item and may contain incorrect terms,
readings, categories, frequencies, or other unsuitable material. Accuracy,
completeness, and fitness for any particular purpose are not guaranteed; verify
important uses independently.

The public import excludes entries that do not start with a Han character or
whose length is outside 2–20 Unicode code points. The first four TSV columns are
term, frequency, reading, and category; some data has a fifth source-description
column.

The [MIT License](LICENSE.txt) applies only to material the copyright holder can
license, including original selection, classification, and arrangement where
copyrightable. No exclusive rights are claimed in common expressions, facts,
public-domain material, or other uncopyrightable content, and no trademark rights
are granted.
