# Ubuntu／Fcitx 5 手動試打交接

此流程在專用 WSL2／Ubuntu GNOME X11 桌面試打目前安裝的 Fcitx addon。
使用待驗證版本建置並安裝套件，記錄實際 addon 路徑、版號與雜湊；不沿用舊核心
測試結果。它與 Xvfb、GNOME Wayland 及日常桌面各自隔離。

## 啟動

從 WSL Ubuntu 24.04 的 repository 根目錄執行。先依 [BUILDING.md](../../../../BUILDING.md)
與 [frontend README](../README.md) 安裝待測的資料與 Fcitx addon 套件。
不要用 system Fcitx 搭配別份不明 build；記錄實際載入路徑與套件版本。

全新環境補上 Ubuntu 官方桌面元件，已安裝者可略過：

```sh
sudo apt-get install --no-install-recommends \
  gnome-shell gnome-session gedit dbus-x11 \
  fcitx5 fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 \
  fcitx5-frontend-qt6 fcitx5-config-qt \
  libqt6widgets6t64 qt6-qpa-plugins fonts-wqy-zenhei \
  tigervnc-standalone-server novnc libgl1-mesa-dri \
  xauth xdotool x11-utils x11-xkb-utils curl
```

先檢查是否已有使用中的桌面：

```sh
systemctl --user status keykey-manual-desktop.service --no-pager
```

若已執行就沿用，不重啟或清空編輯器。尚未啟動時：

```sh
systemd-run --user --unit=keykey-manual-desktop --collect \
  --property=Type=exec --property=KillMode=control-group \
  /usr/bin/bash "$PWD/Source/Loaders/Linux-IME/tools/manual-desktop/start-desktop.sh"
journalctl --user -u keykey-manual-desktop.service -n 30 --no-pager
```

腳本等待 X11、GNOME、addon、gedit 焦點及本機網頁就緒；首次設定將 gedit 字體放大
為 18，啟用 Fcitx，並明確選擇 `chichi77-keykey-bopomofo`。之後保留這個獨立桌面的
設定。預設狀態與 log 位於 `Source/Loaders/Linux-IME/out/manual-vnc/`。

在使用者的瀏覽器開啟：

[Ubuntu 試打桌面](http://localhost:6080/vnc.html?autoconnect=true&resize=scale)

若有內嵌瀏覽器可直接開啟，並在回覆保留此連結。從 Windows 端確認網址可連線；
僅在 WSL 內取得 HTTP 200 不夠。這是本機地址，不能拿到另一台電腦直接連入。
讓使用者在新桌面內的 gedit 試打，避免仍回到原本的 WSLg gedit。

## 切換輸入法與查看狀態

每個桌面的 D-Bus 與 X display 都獨立。必須透過以下入口操作新桌面：

```sh
Source/Loaders/Linux-IME/tools/manual-desktop/session-command.sh fcitx5-remote -o
Source/Loaders/Linux-IME/tools/manual-desktop/session-command.sh \
  fcitx5-remote -s chichi77-keykey-bopomofo
Source/Loaders/Linux-IME/tools/manual-desktop/session-command.sh fcitx5-remote -n
```

最後一行須得到 `chichi77-keykey-bopomofo`。不要讓使用者反覆按 `Shift+Space`：
Windows 輸入法可能攔走按鍵，而且 KeyKey 的 `Shift+Space` 是全半形切換。
若 Windows 的本機組字攔住普通按鍵，請先將 Windows 端切到英文，再由 Linux
琦琦注音處理實體鍵。不要擅自修改 Windows 全域輸入法設定。

可用同一入口開 Fcitx 設定工具或執行 X11 診斷。不要直接沿用 WSLg 原 session 的
`DBUS_SESSION_BUS_ADDRESS`，否則指令可能顯示成功，實際卻切到另一個桌面。
若執行環境限制本機 socket，允許該操作存取本機 session；不要改用 root 的 Fcitx。

## GNOME X11 自動驗收

先以乾淨的 `ci/run-debian-package.sh ubuntu-24.04` package gate 建好同一候選版本的
GTK 3、GTK 4、Qt 6 test hosts，並把待測 `.deb` 正常安裝進桌面。上述桌面保持執行時，
從 repository 根目錄執行：

```sh
Source/Loaders/Linux-IME/tools/manual-desktop/run-gnome-x11-e2e.sh
```

入口會先以 `ldd` 拒絕缺少 toolkit runtime 的環境，再確認目前 display 是由
GNOME Shell 管理、Fcitx 已載入系統安裝的 `chichi77-keykey.so` 與 Classic UI panel。
GNOME 的 Mutter 外框與 client 可能同名；runner 同時核對 host PID，且使用
`xdotool search --all`，不能省略 `--all`，否則多條搜尋條件會成為 OR 而再次選到外框。
新 client 可能在搜尋完成前已成為 active window，runner 會先讀取 active window，再以
非阻塞 `windowactivate` 有界輪詢；不可改成會等待下一次焦點變更的 `--sync`。
每案都透過實際 client 逐鍵輸入，並切到 `keyboard-us` 重送負控制。

`desktop-safe` 批次涵蓋 GTK 3、GTK 4、Qt 6 的五種注音布局、候選
鍵盤／滑鼠操作、關聯詞、模式、兩 App、編輯／密碼／唯讀欄與符號表。它刻意排除
Fcitx process-restart persistence、設定視窗 persistence 與 input-context recovery 案；承載桌面的 Fcitx 一旦被停止，launcher
就會結束整個 session。runner 也會拒絕在 existing desktop 直接指定會重啟 Fcitx 的案例。這些案例
仍由 managed Xvfb／package gate 執行，日後完整登入桌面需以能重建 session 的外層
orchestrator 驗證。

指定不會重啟 Fcitx 的單一案例可用：

```sh
KEYKEY_E2E_CASES=T06-X11-GTK4-CANDIDATE-MOUSE \
  Source/Loaders/Linux-IME/tools/manual-desktop/run-gnome-x11-e2e.sh
```

結果寫入 `out/e2e/ubuntu-24.04-gnome-x11-amd64/`，其中 `environment.txt` 固定記錄
GNOME／Fcitx 版本、addon／panel 路徑、套件版本、addon SHA-256 與三個 host SHA-256。
測試前的 KeyKey 設定與 active engine 會在成功或失敗後還原；不會停止桌面的 Fcitx。
若 GNOME 已沒有 active window，入口會要求重啟這個隔離桌面，不以 `windowfocus`
繞過 Mutter 的 active-window 規則。

## 排查與驗證順序

1. 取得使用者的完整按鍵流程。區分文字晚提交、候選狀態晚清除、視窗已關閉但畫面
   殘留；「仍然一樣」表示問題尚未解決，不能因為測試綠燈就宣稱修好。
2. 比對行為時，先查 macOS 的實際事件流，再查 Windows TSF。確認正常提交／
   隱藏契約後，核對 Linux addon 與框架。
3. 記錄 GTK 真實文字／preedit、按鍵時間、候選 X window 的 map/unmap。快換候選
   而慢關窗時，特別檢查 compositor；四張殘影不等於引擎真的建立了四個活視窗。
4. 以同一 addon 在上述獨立桌面 A/B 比較。自動驗證送實體鍵序，禁止直接設定中文
   buffer 或貼上預期文字。用 `keyboard-us` 重送同一鍵序作負控制。
5. 如需驗證視覺時序，擷取候選區域的關閉前／後像素，不能只看 unmap 或數視窗。
   GNOME 外框與 GTK client 可能同名，須定位 client；map 早於 compositor paint，
   必須先確定關閉前的圖真的包含候選。準備畫面的等待不加入產品按鍵處理。
6. 把可用畫面交給使用者重試原案例，記錄使用者確認。若新環境也慢，繼續量測、
   保留失敗證據；不可無條件套用這次結論。

不要因這個 WSLg 問題加入 sleep、重複 commit、虛構候選、定時強制關窗或全面
更換 Fcitx；若產品修改沒有改善實際案例，撤回該修改並更新診斷。

## 生命週期與隔離

預設使用 display `:21`；VNC 僅開 0600 Unix socket，noVNC 只綁
`127.0.0.1:6080` 並限制 WebSocket Origin 為 localhost。只服務 noVNC 的靜態資產，
不暴露 repository。關閉 gedit 或任一主要行程會結束這個測試 session。
若需停止，先讓使用者儲存新桌面裡的文字，再執行：

```sh
systemctl --user stop keykey-manual-desktop.service
```

只停止指定 service，不用 `pkill fcitx5`、不殺原 WSLg 的 gedit、不刪設定或測試文字。
要另開隔離驗證，給不同的 service 名，並用 `systemd-run --setenv=...` 指定
`KEYKEY_MANUAL_DISPLAY=:22`、`KEYKEY_MANUAL_PORT=6081` 與絕對路徑的
`KEYKEY_MANUAL_DESKTOP_DIR`。`session-command.sh` 使用相同 state-directory 變數，
會讀取該 session 的 display。不可讓兩個 session 共用 runtime／D-Bus／設定目錄。
