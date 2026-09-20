# GNOME Wayland 候選面板決策與驗收門檻

狀態：2026-09-20 已完成 GNOME Shell 46 VM 的 16/16 雙螢幕真滑鼠定位及
32/32 單螢幕四角回歸；獨立 GNOME Shell 46 `.deb` 已完成固定來源重建、
lintian error gate、預覽版初裝→正式版升級、停用→啟用，以及以系統套件跑
32/32 四角、16/16 雙螢幕真滑鼠案例。Ubuntu 22.04、實體螢幕、熱插拔和
其他視覺／App 組合仍須另列結果。

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
固定官方 v83 原檔 SHA 的
[Kimpanel 修補產物](../gnome-panel/README.md)在同一 VM 將雙螢幕提升為
16/16，並重跑四角 32/32。每個雙螢幕案例都在副螢幕點第二列提交「鐘」、
檢查候選清除與 `keyboard-us` 負控制；這是 VM 證據，不是實體螢幕證據。

正式交付路線是將可重現的移窗與縮放修正送回 Kimpanel／Fcitx 上游，並在專用
GNOME extension 整合套件中固定已驗證的來源版本、授權、Shell 相容範圍及升級路徑。
目前的 `gnome-shell-extension-keykey-kimpanel` 僅允許 GNOME Shell 46，與
Fcitx addon 分開建置；同 UUID 的 user-local extension 必須移開，避免遮住
系統套件。安裝、更新與停用指令見 `gnome-panel/README.md`。
目前的最小修補已與 KeyKey 的 BSD／MIT 原始碼分開標示 GPL-2.0 授權及上游出處。
沒有完成套件與跨版本驗收前，不把 extension 列為必要依賴，也不把現有 `.deb`
稱為正式 GNOME 發布版。

## 已定位的責任邊界

- KeyKey Fcitx adapter 只更新 preedit、候選及 input panel；cursor rectangle
  由 toolkit frontend 提供。混合 DPI 的 GTK3 direct Wayland 失敗案中，GTK
  frontend 送出移窗後的 `SetCursorRectV2(100,122,0,196,2)`，Fcitx 亦轉送
  `SetRelativeSpotRectV2`。
- 在官方 extension 的 200% 螢幕實測，Kimpanel 先用移窗前的
  `(35,61,0,98,scale=1)` 顯示候選。新的 `(100,122,0,196,scale=2)`
  到達時，`ShowLookupTable` 已為 false；單純改座標除法或改用 window frame
  只會移動已隱藏的 actor，不能修復當前候選的顯示時機。一次改用 frame origin
  雖讓候選出現在第二螢幕，卻蓋住輸入欄位。正式修補改用
  `current monitor geometry_scale / reported rectangle scale`，讓舊 rect
  在首次顯示時跟隨新螢幕，之後收到新 rect 亦保持同一位置。
- XWayland 的 GTK3 frontend 在移窗後仍保留舊絕對 rect `(75,70,0,98)`；
  候選結束後才更新到新螢幕 `(1304,38,0,98)`。修補記住同一焦點視窗
  收到 rect 時的 frame origin，顯示候選時補上 frame 位移；新 rect
  到達後重設 reference。不同焦點視窗不共用此位移。
- Classic UI 在同一 GTK3 direct Wayland 混合 DPI 案正確顯示，且 QMP
  指標點第二列提交「鐘」並在點選後清除。但其完整 16 案仍有 10 案失敗：
  GTK4 bridge 與 GTK3／GTK4 XWayland 會留在主螢幕；GTK4 direct 與 Qt6
  direct 另有貼邊或遮欄位問題。
- GNOME 預設 GTK Wayland bridge 的多 App 中英／全形狀態共用單一 IBus
  input context；GNOME Text Editor 46.3 的 bridge／`GTK_IM_MODULE=wayland`
  路徑也沒有 active context。已驗證的直接 Fcitx 啟動路徑是
  `GTK_IM_MODULE=fcitx`。面板修正不能代替 input context 修正。

## 修正工作與通過條件

1. 已完成 VM 的 relative Wayland rectangle 與 XWayland absolute rectangle
   移窗修補；不在 KeyKey engine 添加 toolkit 專屬座標推測。仍需讓上游評估
   frontend 為何要到候選結束後才更新 rect，以及更多移窗時序。
2. 已完成兩種縮放的直式九列首次移窗與真滑鼠矩陣。仍需補視窗再次移動、
   焦點切換、橫式、熱插拔、不同 theme、實體 GPU／雙螢幕與長時間閃爍檢查。
3. `gnome-vm-popup-smoke.py --panel kimpanel --mouse` 八路徑 × 四角
   32/32，`gnome-vm-multimonitor-smoke.py --panel kimpanel --mouse`
   兩布局 × 八路徑 16/16；runner 保存 QMP head 截圖。此結果使用由
   `build-patched-extension.py` 生成的乾淨產物，並非臨時診斷碼。
4. 已以真實 gedit／GNOME Text Editor 的 direct Fcitx 與兩個 gedit
   bridge 視窗完成焦點差異驗證；系統面板套件下另以已安裝 helper 重跑
   兩編輯器 Alt+Tab 2/2、Firefox Snap／Epiphany 真實 DOM 欄位 15/15，
   以及六條直接 Fcitx 路徑的兩個同時存活 App 正負控制 12/12。
   預設 GTK bridge 的共用 context 與其他 App／sandbox 組合仍待處理。
5. 已完成固定來源與獨立 GPL `.deb` 的重建、payload／版號順序／lintian
   檢查，及專用 Ubuntu 24.04 GNOME VM 的預覽版初裝、正式版升級、停用、
   再啟用與候選真滑鼠定位。停用後 `org.kde.impanel` bus owner 為 false，
   啟用後為 true；extension path 指向系統套件。copyright metadata 修正
   後的最終 `.deb` 已重新安裝並通過 `dpkg --verify` 與 T01／T06 真滑鼠
   四案；其 GNOME extension payload 與完整 168 案使用的版本逐位元相同。
   仍須於 Ubuntu 22.04 的
   GNOME session 及實體雙螢幕／混合 DPI 重驗；VM 通過不取代實體螢幕。

Kimpanel 上游為 GPL-2.0，現有 extension 下載及測試步驟見
[GNOME VM 手冊](gnome-wayland-vm.md)。這份決策不宣稱 F07 專屬比例／配色
已完成；該功能仍須獨立的 renderer 與設定驗收。
