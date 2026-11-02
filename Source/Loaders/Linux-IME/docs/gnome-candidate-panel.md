# GNOME Wayland 候選面板接合與驗證

GNOME Wayland 的候選呈現使用 Fcitx 5 Kimpanel 協定與獨立 GNOME Shell 面板。
Guanyinma 產生候選，Fcitx adapter 提供內容、反白、方向與選取回呼；toolkit frontend
提供游標矩形，面板負責螢幕座標與可見性。輸入核心不猜測絕對螢幕座標。

## 面板與套件界線

[GNOME panel 套件](../gnome-panel/README.md)固定上游來源及修補，採 GPL-2.0，
與 KeyKey 的 BSD／MIT 輸入法程式分開建置及標示授權。
`gnome-shell-extension-keykey-kimpanel` 目前只宣告 GNOME Shell 46 相容範圍。
同 UUID 的 user-local extension 可能遮住系統套件；驗證時記錄實際 extension path、
版號與 `org.kde.impanel` bus owner，不能只看到面板就當成正確套件已載入。

候選字型、縮放與配色由 renderer 管理。Fcitx input-method addon 的直／橫 layout
hint 不能代替專屬縮放或配色功能，也不應在設定頁提供不會生效的選項。

## 定位與狀態契約

- Wayland relative rectangle 與 XWayland absolute rectangle 由原生接合區分；
  混合 DPI 要保留 rectangle scale 與目前 monitor scale。
- 視窗移到另一個螢幕時，候選首次出現與後續 cursor rectangle 更新都要定位正確。
  XWayland 的 frame 位移只在同一焦點視窗內有效；焦點變更時清除參考。
- 候選隱藏、切 App、關閉 client 與新 client 恢復都要清掉舊狀態，不留下殘窗或
  把舊候選送給新 context。
- input context 是否獨立屬 toolkit／Fcitx 接合。面板修正不能代替中英模式隔離、
  preedit 失焦處理或送字驗證。

## 專用桌面驗證

```sh
Source/Loaders/Linux-IME/tools/gnome-vm-popup-smoke.py --panel kimpanel --mouse
Source/Loaders/Linux-IME/tools/gnome-vm-multimonitor-smoke.py --panel kimpanel --mouse
```

在 [GNOME VM](gnome-wayland-vm.md) 或專用實機使用同一候選版本，記錄工具包、
Wayland／XWayland 路徑、panel provider、縮放、輸出布局與套件雜湊。檢查四角、
跨螢幕、混合 DPI、再次移窗、焦點切換、直／橫候選、點選、清除與 `keyboard-us`
負控制，保留前／中／後及各 display 截圖。Classic UI 與 Kimpanel 分別記錄。

套件安裝、升級、停用／啟用、GNOME Shell 相容範圍、實體螢幕、熱插拔與長時間
使用各自驗證。舊核心、虛擬螢幕或單一 toolkit 的結果不能取代這些驗收。
