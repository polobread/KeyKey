# Linux 1.3.0 `./configure` 編譯安裝指南

這份指南給想從 1.3.0 原始碼自行編譯琦琦輸入法的 Ubuntu 使用者。只想安裝並使用輸入法，請看 [Ubuntu `.deb` 安裝與使用指南](LINUX_INSTALL.md)。編譯完成後，琦琦注音會出現在 Fcitx 5 的輸入法清單，不會開啟獨立的打字視窗。

以下步驟以 **Ubuntu Desktop 24.04 LTS、GNOME Shell 46、Fcitx 5、amd64** 為準。其他 Ubuntu 版本、ARM64、IBus 與其他桌面環境尚未列入這份指南的驗證範圍。

## 1. 安裝前確認

在「設定 → 關於」確認 Ubuntu 版本，並執行 `dpkg --print-architecture`，結果應為 `amd64`。編譯約需數分鐘；安裝時需要管理員密碼，設定輸入法後需要重新啟動 Ubuntu。

**先確認沒有疊裝琦琦輸入法的 `.deb` 版。** 若先前安裝了 `fcitx5-chichi77-keykey` 和 `chichi77-keykey-data`，先從 Fcitx 設定清單移除琦琦注音，再執行：

```sh
sudo apt remove fcitx5-chichi77-keykey chichi77-keykey-data
```

這只移除輸入法及資料套件；已安裝的 GNOME 候選面板可以保留。若先前用另一份原始碼安裝，先到**原本的建置資料夾**執行 `sudo make uninstall`。不要讓原始碼安裝直接覆寫套件管理器或舊安裝的檔案。

## 2. 取得完整的 1.3.0 原始碼

開啟 [v1.3.0 發布頁](https://github.com/polobread/KeyKey/releases/tag/v1.3.0)，在檔案清單底部下載 GitHub 提供的 **Source code (tar.gz)**，解壓縮後進入專案資料夾。確認其中同時有 `Source` 與 `DataSource`；`./configure` 位於 `Source/Loaders/Linux-IME/`。

不要把 Assets 裡的 `gnome-shell-extension-keykey-kimpanel_*_source.tar.gz` 當作輸入法原始碼；那個檔案只有 GNOME 候選面板。此處需要完整的 KeyKey 專案原始碼。

## 3. 安裝編譯工具與 Fcitx 5

```sh
sudo apt update
sudo apt install build-essential cmake libcanberra-dev libfcitx5core-dev \
  libsqlite3-dev pkg-config python3 fcitx5 fcitx5-frontend-gtk3 \
  fcitx5-frontend-gtk4 fcitx5-frontend-qt6 fcitx5-config-qt im-config
```

**`libsqlite3-dev` 是編譯好打注音所需的 SQLite 開發套件。** 只安裝發布版 `.deb` 的使用者不需要手動安裝它；套件安裝時，`apt` 會處理執行期的 `libsqlite3-0`。`./configure` 是 CMake 的建置入口，不需要另裝 Autoconf、Automake、Ninja 或 Docker。

## 4. 編譯、測試並安裝

在剛解壓的 **KeyKey 專案資料夾**開啟終端機，依序執行：

```sh
cd Source/Loaders/Linux-IME
./configure --prefix=/usr
make -j2
make check
sudo make install
```

每行成功後再執行下一行。`make check` 應顯示測試通過；若失敗，先不要執行 `sudo make install`。只有最後的安裝指令需要管理員權限。`--prefix=/usr` 讓 Fcitx 使用 Ubuntu 的系統搜尋路徑；省略它會安裝到 `/usr/local`，在部分環境須另設 addon 與資料搜尋路徑。

**保留這份原始碼、產生的 `Makefile` 與 `out/build/configure-make/`。** 日後若要移除，仍須從同一資料夾執行 `make uninstall`；移除前不要執行 `make distclean`。

## 5. 啟用 Fcitx 5 與候選面板

執行 `im-config`，在圖形精靈選 **fcitx5**，儲存工作後**重新啟動 Ubuntu**。重新登入後，新開啟的 App 才會取得 Fcitx 登入環境。

`./configure` 安裝的是輸入法與詞庫，**不包含 GNOME 候選面板**。若要使用發布版的候選面板，從同一 [v1.3.0 發布頁](https://github.com/polobread/KeyKey/releases/tag/v1.3.0)下載 `gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_all.deb`，在下載資料夾執行：

```sh
sudo apt install ./gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_all.deb
keykey-gnome-panel enable
keykey-gnome-panel status
```

`status` 顯示 `State: ACTIVE` 表示面板已啟用；若還看不到候選窗，再登出並登入一次。面板是獨立套件，日後執行 `make uninstall` 不會移除它。

## 6. 加入琦琦注音並試打

開啟 **Fcitx 5 Configuration**，或執行 `fcitx5-config-qt`。在「輸入法」頁搜尋 **KeyKey**，把 **chichi77 KeyKey Bopomofo** 加入目前使用清單。若找不到，取消「只顯示目前語言」的篩選。選取 Bopomofo 並開啟設定；1.3.0 預設的「注音模式」是**好打注音**，也可改成**傳統注音**。先保留 **Standard** 鍵盤布局和 **Vertical** 候選排列即可。

開啟 **文字編輯器（琦琦注音）** 並點選空白文件。從 Fcitx 選單選 **chichi77 KeyKey Bopomofo**；按 **Ctrl + Space** 可在 Fcitx 英文鍵盤與琦琦注音間切換。若已選琦琦注音卻只輸出英文，按 `Ctrl + \` 或短按 **Shift** 切回中文。

好打注音可連續輸入音節，按 **Enter** 送出整段組字；按 **Space** 或 **↓** 可為目前游標位置開啟候選，選字後繼續組字。傳統注音則逐字選字。完整按鍵、1.3.0 實拍畫面與疑難排解見 [日常使用說明](LINUX_INSTALL.md#5-試打與基本操作)。

## 遇到問題時

| 情況 | 檢查方式 |
| --- | --- |
| `./configure` 找不到 CMake、Fcitx5Core、libcanberra 或 SQLite3 | 回到第 3 步，確認編譯工具及 `libsqlite3-dev` 已安裝；失敗時不要繼續執行 `make`。 |
| `make check` 失敗 | 保留錯誤訊息與系統版本，先不要安裝。 |
| Fcitx 清單找不到琦琦注音 | 確認 `sudo make install` 完成、使用 `--prefix=/usr`，重新啟動 Ubuntu，再取消語言篩選。 |
| 選到琦琦注音仍只能輸出英文 | 確認 Fcitx 選到 Bopomofo，再按 `Ctrl + \` 切回中文；第一聲讀音後按 **Space** 完成音節。 |
| 其他 App 仍無法輸入 | 重新啟動 Ubuntu，依[套件指南的輸入環境排除步驟](LINUX_INSTALL.md#遇到問題時)檢查 Fcitx 登入設定。 |
| GNOME 候選面板不顯示 | 若尚未安裝面板套件，先依第 5 步安裝；已安裝則執行 `keykey-gnome-panel status`。 |

## 移除或改回 `.deb` 版

先在 Fcitx 5 Configuration 移除琦琦注音。回到**當初執行 `./configure` 的同一個 `Source/Loaders/Linux-IME` 資料夾**，執行：

```sh
sudo make uninstall
```

此指令會依該次建置的安裝清單移除輸入法和詞庫，不會刪除 Fcitx 個人設定，也不會移除另裝的 GNOME 候選面板 `.deb`。確認移除後，才可執行 `make distclean` 或刪除原始碼。要改回套件版，按 [Ubuntu `.deb` 安裝指南](LINUX_INSTALL.md)重新安裝；若也要移除面板，執行 `keykey-gnome-panel disable` 和 `sudo apt remove gnome-shell-extension-keykey-kimpanel`。

進階的自訂 prefix、獨立建置資料夾、`DESTDIR` 暫存安裝與完整測試紀錄，見 [BUILDING.md](BUILDING.md#linux-原始碼建置) 和 [Linux frontend README](Source/Loaders/Linux-IME/README.md#configure-and-gnu-make-source-build)。
