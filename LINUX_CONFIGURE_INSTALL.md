# Linux `./configure` 編譯安裝與使用指南

這份指南給想自行從原始碼編譯琦琦輸入法的 Ubuntu 使用者。需要在終端機輸入指令；如果只想安裝使用，請改看[Ubuntu `.deb` 圖文安裝與使用指南](LINUX_INSTALL.md)。編譯完成後，琦琦注音會加入 **Fcitx 5** 的輸入法清單，不會出現獨立的打字主視窗。

以下步驟以 **`v1.2.9`、Ubuntu Desktop 24.04 LTS、GNOME Shell 46、Fcitx 5、amd64** 為準。Ubuntu 24.04 的原始碼安裝已通過 X11 實際輸入測試；本頁沿用的 GNOME Wayland 截圖來自先前套件版，並非原始碼安裝的 Wayland 驗收。Ubuntu 22.04 的原始碼編譯測試已通過，但沒有列入這份指南的桌面使用支援範圍；其他版本、ARM64、IBus 與其他桌面環境也尚未完成相同驗收。

## 1. 安裝前確認

在「設定 → 關於」確認 Ubuntu 版本，並在終端機執行 `dpkg --print-architecture`，結果應為 `amd64`。編譯約需數分鐘，安裝時需要管理員密碼，設定輸入法後需要重新啟動 Ubuntu。

**先確認沒有疊裝琦琦輸入法的 `.deb` 版。** 如果先前依[套件安裝指南](LINUX_INSTALL.md)安裝過 `fcitx5-chichi77-keykey` 和 `chichi77-keykey-data`，請先從 Fcitx 設定清單移除琦琦注音，再執行：

```sh
sudo apt remove fcitx5-chichi77-keykey chichi77-keykey-data
```

這只移除琦琦輸入法的兩個套件；若已安裝 GNOME 候選面板套件，可以保留它。若你先前是用另一份原始碼安裝，先回到**那份原始碼的同一個建置資料夾**執行 `sudo make uninstall`，再開始新版安裝。不要讓原始碼安裝直接覆寫套件管理器或舊原始碼安裝的檔案。

## 2. 下載完整原始碼

打開 [v1.2.9 發布頁](https://github.com/polobread/KeyKey/releases/tag/v1.2.9)，在檔案清單底部下載 GitHub 提供的 **Source code (tar.gz)**，解壓縮後打開所得的專案資料夾。確認裡面同時有 `Source` 和 `DataSource` 資料夾；`./configure` 位於 `Source/Loaders/Linux-IME/`。

**不要下載** Assets 裡名稱含 `gnome-shell-extension-keykey-kimpanel` 的 `_source.tar.gz` 作為輸入法原始碼；該檔只有 GNOME 候選面板。這份指南需要完整的 KeyKey 專案原始碼。

## 3. 安裝編譯工具與 Fcitx 5

在 Ubuntu 終端機執行：

```sh
sudo apt update
sudo apt install build-essential cmake libcanberra-dev libfcitx5core-dev pkg-config \
  fcitx5 fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt6 \
  fcitx5-config-qt im-config
```

這些是編譯與日常輸入需要的工具和 Fcitx 元件。`./configure` 是包住 CMake 的建置入口，**不需要**另裝 Autoconf、Automake、Ninja 或 Docker。

## 4. 編譯、測試並安裝

在剛解壓的 **KeyKey 專案資料夾**開啟終端機，依序執行：

```sh
cd Source/Loaders/Linux-IME
./configure --prefix=/usr
make -j2
make check
sudo make install
```

每行成功後再執行下一行。`make check` 應顯示測試通過；若有錯誤，先不要執行 `sudo make install`。只有最後的安裝指令需要管理員權限。`--prefix=/usr` 讓 Fcitx 使用 Ubuntu 的一般系統搜尋路徑；省略它會安裝到 `/usr/local`，在部分 Fcitx 環境還須另設 addon 與資料搜尋路徑。

**保留解壓後的整個專案資料夾及這次產生的 `Makefile`、`out/build/configure-make/`。** 日後要移除原始碼安裝，仍須從這個資料夾執行 `make uninstall`；不要先執行 `make distclean`。

## 5. 啟用 Fcitx 5 與候選面板

在終端機執行 `im-config`，在出現的圖形精靈選 **fcitx5**。儲存工作後**重新啟動 Ubuntu**，再登入同一帳號。重新啟動能讓新開啟的 App 使用 Fcitx；只關閉終端機不會更新整個登入環境。

`./configure` 安裝的是輸入法與詞庫，**不包含 GNOME 候選面板**。如果你想使用發布版的 GNOME 候選面板，另從同一 [v1.2.9 發布頁](https://github.com/polobread/KeyKey/releases/tag/v1.2.9)下載 `gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_all.deb`。在該 `.deb` 所在資料夾開啟終端機，執行：

```sh
sudo apt install ./gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_all.deb
keykey-gnome-panel enable
keykey-gnome-panel status
```

`status` 顯示 `State: ACTIVE` 代表面板已啟用；若還看不到候選窗，再登出並重新登入一次。面板是**獨立套件**，日後使用 `make uninstall` 不會移除它。

## 6. 加入琦琦注音並試打

從「顯示應用程式」開啟 **Fcitx 5 Configuration**，或在終端機執行 `fcitx5-config-qt`。在「輸入法」頁搜尋 **琦琦注音**（英文介面為 `chichi77 KeyKey Bopomofo`），連按兩下或按加入箭頭，確認它出現在目前使用的清單。第一次使用可保留 **Standard** 注音布局與 **Vertical** 直式候選。

![Fcitx 5 琦琦注音設定畫面](docs/images/keykey-linux-fcitx-bopomofo-settings.png)

*示範畫面取自先前 1.2.8 套件版的 Ubuntu 24.04 X11 測試桌面，用來辨識設定選項；不是這次原始碼安裝的截圖。*

開啟 **文字編輯器（琦琦注音）**，點一下空白文件。先從 Fcitx 選單選琦琦注音；按 **Ctrl + Space** 可以在 Fcitx 英文鍵盤與琦琦注音間切換。選到琦琦注音卻只輸出英文時，按 `Ctrl + \` 或短按 **Shift** 切回注音的中文模式。

使用 Standard 布局時，依序按實體鍵盤的 **`5`、`j`、`/`、`Space`** 輸入 **ㄓㄨㄥ** 並叫出候選，再按 **1** 選「中」。按 **Page Down／Page Up** 翻頁、**Esc** 取消組字、**Ctrl + 0** 開啟符號清單。其他布局、關聯詞、快捷鍵與疑難排解見[日常使用說明](LINUX_INSTALL.md#5-試打與基本操作)。

![Ubuntu 24.04 注音候選畫面](docs/images/keykey-linux-gnome-bopomofo-candidates.png)

*示範畫面取自先前 1.2.8 套件版的 GNOME Wayland 測試欄位；正式使用時，候選窗會出現在目前輸入的 App 旁。*

## 遇到問題時

| 情況 | 檢查方式 |
| --- | --- |
| `./configure` 找不到 CMake、Fcitx5Core 或 libcanberra | 回到第 3 步，確認全部編譯工具已安裝；`./configure` 失敗時不要繼續執行 `make`。 |
| `make check` 失敗 | 保留錯誤訊息與系統版本，先不要安裝。 |
| Fcitx 清單找不到琦琦注音 | 確認 `sudo make install` 已完成、選的是 `--prefix=/usr`，重新啟動 Ubuntu，再取消設定工具的語言篩選。 |
| 選到琦琦注音仍只能輸出英文 | 先確認 Fcitx 選到琦琦注音，再按 `Ctrl + \` 切回中文；一聲注音後須按 **Space** 叫出候選。 |
| 只有文字編輯器可用，其他 App 仍無法輸入 | 重新啟動 Ubuntu，並依[套件指南的輸入環境排除步驟](LINUX_INSTALL.md#遇到問題時)檢查 Fcitx 登入設定。 |
| GNOME 候選面板不顯示 | 若尚未安裝面板套件，先依第 5 步安裝；已安裝則執行 `keykey-gnome-panel status`。 |

## 移除或改回 `.deb` 版

先在 Fcitx 5 Configuration 的目前使用清單移除琦琦注音。回到**當初執行 `./configure` 的同一個 `Source/Loaders/Linux-IME` 資料夾**，執行：

```sh
sudo make uninstall
```

這會依該次安裝留下的清單移除輸入法和詞庫檔案，不刪除你的 Fcitx 個人設定，也不會移除另裝的 GNOME 候選面板 `.deb`。確認移除完成後，才可以執行 `make distclean` 或刪除原始碼資料夾。要改回套件版，接著按[Ubuntu `.deb` 安裝指南](LINUX_INSTALL.md)重新安裝並啟用；如果也要移除面板套件，再執行 `keykey-gnome-panel disable` 和 `sudo apt remove gnome-shell-extension-keykey-kimpanel`。

進階的自訂 prefix、獨立建置資料夾、`DESTDIR` 暫存安裝與完整測試記錄見 [BUILDING.md](BUILDING.md#linux-原始碼建置) 和 [Linux frontend README](Source/Loaders/Linux-IME/README.md#configure-and-gnu-make-source-build)。
