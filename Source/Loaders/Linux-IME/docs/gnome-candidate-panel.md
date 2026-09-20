# GNOME Wayland 候選面板決策與驗收門檻

狀態：2026-09-20 完成實機路徑診斷，正式發布整合仍未完成。

## 決策

Ubuntu GNOME Wayland 的候選呈現以 Fcitx 5 的 Kimpanel 協定與 GNOME Shell
面板為主要整合方向。候選內容、反白、方向、選取回呼仍由現有 Linux-only engine
及 Fcitx addon 提供；螢幕座標及可見性由面板處理。KeyKey engine 不猜測絕對螢幕座標，
也不把 `GTK_IM_MODULE`、縮放或配色全域設定改給其他輸入法。

目前官方 `kimpanel@kde.org` v83 是**驗證基線**，不是套件依賴或已完成的產品元件。
GNOME Shell 46 的 1280×800 四角矩陣 32/32 通過，但雙螢幕候選定位只有
10/16。停用 extension、由 Fcitx Classic UI 呈現時，雙螢幕定位只有 6/16，
所以不能直接把 Classic UI 定為 GNOME 正式解法。兩個後端都必須保留在測試矩陣，
由 runner 記錄實際 provider、Kimpanel bus owner 及 Classic UI 是否載入。

正式交付路線是先向 Kimpanel／Fcitx 上游提出可重現的移窗與縮放修正，並在專用
GNOME extension 整合套件中固定已驗證的來源版本、授權、Shell 相容範圍及升級路徑。
若上游版本未在發布前修好，該整合套件需維護一份最小修補，與 KeyKey 的 BSD／MIT
原始碼分開標示 GPL-2.0 授權及上游出處。沒有取得全部矩陣證據前，不把 extension
列為必要依賴，也不把現有 `.deb` 稱為正式 GNOME 發布版。

## 已定位的責任邊界

- KeyKey Fcitx adapter 只更新 preedit、候選及 input panel；cursor rectangle
  由 toolkit frontend 提供。混合 DPI 的 GTK3 direct Wayland 失敗案中，GTK
  frontend 送出移窗後的 `SetCursorRectV2(100,122,0,196,2)`，Fcitx 亦轉送
  `SetRelativeSpotRectV2`。
- 在官方 extension 的 200% 螢幕實測，Kimpanel 先用移窗前的
  `(35,61,0,98,scale=1)` 顯示候選。新的 `(100,122,0,196,scale=2)`
  到達時，`ShowLookupTable` 已為 false；單純改座標除法或改用 window frame
  只會移動已隱藏的 actor，不能修復當前候選的顯示時機。一次改用 frame origin
  雖讓候選出現在第二螢幕，卻蓋住輸入欄位。
- Classic UI 在同一 GTK3 direct Wayland 混合 DPI 案正確顯示，且 QMP
  指標點第二列提交「鐘」並在點選後清除。但其完整 16 案仍有 10 案失敗：
  GTK4 bridge 與 GTK3／GTK4 XWayland 會留在主螢幕；GTK4 direct 與 Qt6
  direct 另有貼邊或遮欄位問題。
- GNOME 預設 GTK Wayland bridge 的多 App 中英／全形狀態共用單一 IBus
  input context；GNOME Text Editor 46.3 的 bridge／`GTK_IM_MODULE=wayland`
  路徑也沒有 active context。已驗證的直接 Fcitx 啟動路徑是
  `GTK_IM_MODULE=fcitx`。面板修正不能代替 input context 修正。

## 修正工作與通過條件

1. 在 Fcitx GTK／Qt frontend 與 Kimpanel 的事件時序中，讓候選首次顯示前就
   取得目前視窗及螢幕的 caret rectangle。視窗跨螢幕後、尚未再輸入按鍵時，
   不得沿用舊螢幕座標。分別處理 relative Wayland rectangle 與 XWayland
   absolute rectangle；不要在 KeyKey engine 添加 toolkit 專屬座標推測。
2. 在 Shell 面板依目前焦點視窗、monitor、實際 scale 及 work area 選擇位置；
   驗證 100%→100%、100%→200%、視窗再次移動、焦點切換、九列直式與橫式，
   並檢查不裁切、不蓋欄位、無重複殘影及不搶焦點。
3. 用 `gnome-vm-popup-smoke.py --panel kimpanel --mouse` 完成八條路徑 ×
   四角；用 `gnome-vm-multimonitor-smoke.py --panel kimpanel --mouse`
   完成兩布局 × 八條路徑的第二列實際滑鼠選字、候選清除及
   `keyboard-us` 負控制。runner 保存兩個 QMP head 截圖，單純文字提交
   不計入視覺通過。
4. 重跑 gedit、GNOME Text Editor、Firefox Snap、Epiphany 的真實欄位與
   `gnome-vm-real-focus-smoke.py`，分別記錄 direct Fcitx／GNOME bridge／
   XWayland 的失焦語意及多 App 模式隔離。最後在 Ubuntu 22.04 與 24.04
   的 GNOME session、實體雙螢幕與混合 DPI 重驗；VM 通過不取代實體螢幕。

Kimpanel 上游為 GPL-2.0，現有 extension 下載及測試步驟見
[GNOME VM 手冊](gnome-wayland-vm.md)。這份決策不宣稱 F07 專屬比例／配色
已完成；該功能仍須獨立的 renderer 與設定驗收。
