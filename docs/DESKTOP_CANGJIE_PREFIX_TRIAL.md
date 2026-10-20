# 桌面倉頡前綴候選試用

macOS、Windows TSF 與 Linux／FreeBSD Fcitx 5 已接入程式碼，產品版號維持各平台 1.3.7（未發布）。完整規則見 [跨平台計畫](CANGJIE_PREFIX_CANDIDATES_PLAN.md)。

## 開啟方式

- macOS：偏好設定的「倉頡」，勾選「即時候選」（英文介面為 Realtime candidates）及「未打完也能選字」。
- Windows：設定的「倉頡」，勾選「即時候選」及「未打完也能選字」。
- Linux／FreeBSD：Fcitx 琦琦設定的「倉頡設定」→「開啟倉頡設定…」，勾選兩項後按「套用」。也可執行 `keykey-cangjie-settings`。此視窗另存至 Fcitx 設定並立即要求重新載入；外層 Fcitx 設定視窗的取消不會撤銷已套用的倉頡值，套用後應重新開啟外層設定，避免舊草稿覆寫。

兩項缺值預設關閉，保留使用者已儲存的即時候選選擇。開啟即時候選會關閉錯碼清除；開啟錯碼清除會關閉即時候選。即時候選關閉時，前綴選項變灰、不查前綴，但保留勾選值。

## 選字行為

一至四碼先顯示完整碼候選，保留原排序與完整碼學習；後接嚴格前綴候選，依既有 1,500 字排名取最多 36 字。未排名字沿原字表列序補足，完整碼另計。五碼只查完整碼，預覽只剩一字也不自動送出。每次增碼或刪碼均重新查詢；第六個一般字根沿原流程確認目前候選再開始新碼。

前綴字不寫成短碼的選字偏好；歷史短碼學習也不會把前綴字排到完整碼之前。萬用字元 `?／*` 保留原查詢，不套前綴 36 字上限。桌面沿用原平台空白、Enter、數字鍵、點選及翻頁操作；Linux 空白仍翻頁，Enter 確認。

以本專案字表的「喬」＝竹大口月口（HKRBR）為例：

| 已輸入 | 未套字型／字集限制時的候選總數 | 喬 |
|---|---:|---|
| 竹 H | 38（完整碼 2＋前綴 36） | 未進前綴前 36 字 |
| 竹大 HK | 40（完整碼 4＋前綴 36） | 第 5 字，可提前選 |
| 竹大口 HKR | 11 | 已可選 |
| 竹大口月 HKRB | 2 | 首字 |
| 竹大口月口 HKRBR | 1 | 首字，等待確認 |

這是專案實際字表與固定排名的結果，不等同系統倉頡截圖。macOS／Windows 的字型、字集限制及完整碼個人排序可能改變可見筆數及位置。

## 驗證入口與界線

```sh
python3 tests/generate_cangjie_ranking.py --check
python3 tests/test_desktop_cangjie.py
# macOS 原生設定控制器，使用獨立暫存 plist
python3 tests/test_macos_cangjie_settings.py
```

- 共用 OVIMGeneric 及 WindowsTableInputMethod 以正式 SQLite 字表完成四種開關組合、喬逐碼、增刪碼、翻頁歸零、五碼不自動送出、第六碼、萬用字元、排名／去重／過濾補位、完整碼學習與前綴隔離回歸。Windows adapter 在 macOS 主機可攜測試通過，這不代替 Windows TSF。
- macOS IMK Release 建置通過；實際 AppKit 倉頡控制器通過預設值、雙向互斥、停用保留及重開保存。三種語系 nib 接線檢查通過。尚未替換已安裝輸入法，IMK 文字宿主實測另行進行。
- Ubuntu 24.04 amd64 隔離容器完成 Linux 引擎、Fcitx mode-key、GTK 設定控制器測試及安裝；X11／GTK3 實際宿主通過既有倉頡、錯碼、萬用字元，以及 HK 數字鍵提前選喬與 HKRBR Enter 確認。測試主機為 Apple Silicon，amd64 使用模擬執行，不能作原生效能數據。
- 獨立 Linux 原始碼壓縮檔經解壓後 CMake／Ninja 建置及 /usr/local staged install 通過，確認共用排名、Unicode 資料與設定工具齊備；此項不等同 Debian 套件或 FreeBSD 原生驗收。
- Linux 引擎候選以有序字碼查找，保留原 CIN 列序；SQLite 使用既有 key 索引並串流選出前 36 字。沒有新增無上限候選快取或每鍵排名 DB 查詢。
- Windows 已完成 x64 表格／WPF／組字邊界、x64 與 x86 的跨程序／AppContainer、雙向 x64↔x86 設定同步回歸。使用獨立 profile 與隨機 TSF compartment，涵蓋倉頡四種開關組合、簡易即時候選開關、許氏配置／空白開候選／自訂選字鍵／Esc，以及外觀、顯示與字集設定；不安裝或註冊 TIP。使用者在搜尋列發現的隔離設定差異已於 Windows adapter 補上同步，修正版 Search／記事本實際宿主複測仍待完成。GNOME Wayland、FreeBSD 原生桌面、各平台實際連打效能與焦點切換仍待驗收，未宣稱完成發布驗收。
- 共用好打注音模型、原始 CIN 與平台版號不變。C++ 排名由同一 TSV 產生；漢字去重涵蓋單一 CJK 相容漢字的標準等價對應，顯示仍保留來源字形。

Windows 日常建置範圍為 `tsf＋settings`，另有 `package` 授權檔複製，先建置受影響 x64 target，使用 CTest 篩選表格及 WPF 測試，不需重跑 updater／deployment 或 x86。命令與環境見 [Windows README](../Source/Loaders/Windows-TSF/README.md)。

搜尋列同步修正另涉及 native settings bridge 與跨架構狀態，因此增加 x86 與雙向同步驗證；一般後續變更仍依實際影響選擇範圍。安裝新的 Windows 測試包後登出再登入，在設定按一次「套用」，再分別於搜尋列與記事本測試倉頡 HK 提前選「喬」及簡易即時候選。個人學習內容保持隔離，不能用候選個人排序不同判定設定同步失敗。
