# Linux／Ubuntu 安裝與使用指南

琦琦輸入法在 Ubuntu 透過 Fcitx 5 提供好打注音、傳統注音、倉頡與簡易。完成最新版套件安裝後，啟用 Fcitx、加入琦琦，再開啟文字 App 試打。

本頁帶你依序完成 **下載五檔 → 校驗安裝 → 啟用並重啟 → 加入琦琦 → 第一次選字**。[設定導覽](#設定導覽)介紹最新版的設定與「省略聲調」。自行編譯另見 [Linux `./configure` 編譯安裝指南](LINUX_CONFIGURE_INSTALL.md)。

## 新核心升級準備

最新版使用 Guanyinma（觀音嬤）共用核心，提供桌面偏好、圖形自訂詞／學習管理，以及完整 JSON 備份與匯入。使用者資料存於 `guanyinma-user.db`。從舊 C++ 核心升級前請先備份，舊詞庫保留原檔。詳細資料說明見 [Linux／FreeBSD 核心接合](docs/GUANYINMA_LINUX_ADAPTER.md)。

## 安裝前確認

本版的 Linux 安裝步驟適用於 **Ubuntu Desktop 24.04 LTS、GNOME Shell 46、Fcitx 5、amd64**。在「設定 → 關於」確認 Ubuntu 版本，並執行 `dpkg --print-architecture`，結果應為 `amd64`。安裝需要管理員密碼，設定完成後需要重新啟動 Ubuntu。其他 Ubuntu 版本、ARM64、IBus 與其他桌面環境尚未列入這份指南的驗證範圍。

## 1. 下載最新版套件

開啟 [官方發布列表](https://github.com/polobread/KeyKey/releases)，選擇最新提供 **Ubuntu 24.04／amd64** 套件的 Linux 發布頁，從 **Assets** 或該頁提供的台灣 AWS 下載點取得以下五個檔案。

每次下載都建立一個新的空白資料夾，例如 `~/Downloads/keykey-linux`，只放這一個 Linux 發布頁的檔案，避免混用不同版本。

| 檔案 | 用途 |
| --- | --- |
| `chichi77-keykey-data_…_all.deb` | 注音、詞庫與語言模型資料 |
| `fcitx5-chichi77-keykey_…_amd64.deb` | Fcitx 5 輸入法與好打注音 |
| `gnome-shell-extension-keykey-kimpanel_…_all.deb` | GNOME 候選字面板 |
| `gnome-shell-extension-keykey-kimpanel_…_source.tar.gz` | 面板對應原始碼，供校驗與查閱 |
| `SHA256SUMS` | 上述四個檔案的校驗值 |

檔名中的 `…` 代表發布頁列出的版本。輸入法與資料套件須來自同一版，GNOME 面板使用獨立版號，以該頁提供的配套檔案為準。

## 2. 校驗並安裝

在下載資料夾開啟終端機。若使用上面的範例路徑，執行：

```sh
cd ~/Downloads/keykey-linux
sha256sum -c SHA256SUMS
```

四個檔案都顯示 `OK` 後再安裝。若資料夾不同，將 `cd` 改成實際路徑；若顯示 `FAILED`，重新下載對應檔案。

![Ubuntu 終端顯示套件與面板原始碼均通過 SHA-256 校驗](docs/images/keykey-linux-v151-package-checksums.png)

確認這個專用資料夾中，每種套件都只有一個 `.deb`，接著安裝三個套件與需要的輸入橋接：

```sh
sudo apt install \
  ./chichi77-keykey-data_*_all.deb \
  ./fcitx5-chichi77-keykey_*_amd64.deb \
  ./gnome-shell-extension-keykey-kimpanel_*_all.deb \
  fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt6 \
  fcitx5-config-qt im-config
```

安裝後執行 `dpkg-query -W chichi77-keykey-data fcitx5-chichi77-keykey gnome-shell-extension-keykey-kimpanel`，確認已安裝版本與各自下載檔相同。輸入法與資料套件的版本應一致，面板沿用自己的版號。也可從應用程式選單開啟琦琦輸入法的關於頁，核對產品版本。

![琦琦輸入法關於頁可核對已安裝版本](docs/images/keykey-linux-v151-about.png)

**不必另外安裝 SQLite。** 輸入法套件依賴執行期的 `libsqlite3-0`，上面的 `apt install` 會一併處理。`libsqlite3-dev` 只供[從原始碼編譯](LINUX_CONFIGURE_INSTALL.md)使用；一般安裝 `.deb` 不需要它，也不需要 `sqlite3` 命令列程式。

## 3. 啟用 Fcitx 5 與 GNOME 候選面板

執行 `im-config`，在圖形精靈選 **fcitx5**，依提示儲存。

![im-config 精靈的 fcitx5 圓鈕已選取](docs/images/keykey-linux-v137-lnx03-im-config-ubuntu2404-wayland.png)

以 **fcitx5 左側的實心圓鈕**判斷選取狀態；上圖已選 fcitx5，橘色列背景不是框架啟用指示。

儲存手邊文件後**重新啟動 Ubuntu**，再登入同一個帳號。重新啟動可讓新開啟的 App 取得 Fcitx 的登入環境；只關閉終端機不會套用設定。Fcitx 的 [Ubuntu 設定說明](https://fcitx-im.org/wiki/Setup_Fcitx_5)也使用 `im-config`。

重新登入後執行：

```sh
keykey-gnome-panel enable
keykey-gnome-panel status
```

`status` 顯示 `State: ACTIVE` 表示面板已啟用。若啟用後仍看不到候選窗，再登出並登入一次。

![重新啟動並登入後，GNOME 候選面板顯示 State ACTIVE](docs/images/keykey-linux-v137-lnx04-panel-active-ubuntu2404-wayland.png)

上圖為 GNOME Wayland 工作階段，重啟並登入後面板仍為 `ACTIVE`。


## 4. 加入琦琦注音並設定模式

從「顯示應用程式」開啟 **Fcitx 5 Configuration**，或執行 `fcitx5-config-qt`。在「輸入法」頁取消 **Only Show Current Language／只顯示目前語言**。繁體中文介面搜尋 **琦琦**，英文介面搜尋 **KeyKey**，將 **琦琦注音（chichi77 KeyKey Bopomofo）** 加入目前使用清單。

![Fcitx 搜尋畫面，右側顯示 Bopomofo、Cangjie 與 Simplex 三個可加入項目](docs/images/keykey-linux-v137-lnx05a-search-ubuntu2404-wayland.png)

選取右側的 Bopomofo，再按中間的 **←** 加入。搜尋時這版工具會隱藏語言篩選列；先清空搜尋欄即可找到該選項。

加入後，確認左側清單出現 **琦琦注音**。若也要用倉頡或簡易，再分別加入 **琦琦倉頡**、**琦琦簡易**，並保留英文鍵盤供切換。

![Fcitx 目前清單，包含英文鍵盤、琦琦注音、琦琦倉頡與琦琦簡易](docs/images/keykey-linux-v151-fcitx-current-list.png)

左側出現項目表示已加入；已加入的項目不會重複出現在右側可用清單。完成後按 **Apply／套用**儲存。

選取清單中的 Bopomofo，開啟設定。**「注音模式」預設為「好打注音」**，可在此改成「傳統注音」。第一次使用可先保留 **標準（Standard）** 鍵盤配置和 **直式（Vertical）** 候選；習慣倚天、倚天 26 鍵、許氏或漢語拼音時，再切換鍵盤布局。此頁也可調整繁轉簡、Big-5 範圍外候選、打字錯誤提示音、中英文快捷鍵和關聯詞庫。

設定依「一般、注音、倉頡、簡易、自訂詞、詞庫」分組，可向下捲動；視窗最上方可查看版本與檢查更新。

![Fcitx 設定的一般分組，包含啟動語言、Caps Lock、數字鍵盤與中英切換](docs/images/keykey-linux-v152-fcitx-general.png)

「中文模式忽略 Caps Lock」預設關閉；英文模式保留大小寫功能。候選字窗方向在此設定，字型與外觀由 Fcitx／GNOME 主題調整。

## 5. 試打與基本操作

開啟 **文字編輯器（琦琦注音）**，新增空白文件並點選文字區。此啟動器讓 GNOME 文字編輯器使用 Fcitx 的輸入路徑；若找不到，先確認已安裝 GNOME 文字編輯器，也可在其他一般文字欄位試打。

從桌面右上角的 Fcitx 選單選 **琦琦注音（chichi77 KeyKey Bopomofo）**。按 **Ctrl + Space** 可以在 Fcitx 的英文鍵盤和琦琦注音間切換。快捷鍵若已自行更改，以 Fcitx 5 Configuration 的「全域選項」為準。

![GNOME Fcitx 選單顯示目前使用 chichi77 KeyKey Bopomofo](docs/images/keykey-linux-v137-lnx06a-selected-ubuntu2404-wayland.png)

![點選目前名稱後展開英文鍵盤及琦琦三種輸入法](docs/images/keykey-linux-v137-lnx06a-input-list-ubuntu2404-wayland.png)

兩張切換圖沿用既有的 GNOME Wayland 實拍。第一張顯示目前使用 Bopomofo，點選名稱可展開第二張的切換清單。

### 先試打「請假」

使用好打注音的標準鍵盤，依序按 `F U / 3 R U 8 4` 輸入「ㄑㄧㄥˇ ㄐㄧㄚˋ」。按 **↓** 可查看候選，再選「請假」並按 **Enter** 確認。

![在 GTK 3 文字欄輸入請假，開啟候選窗且第一項為請假](docs/images/keykey-linux-v151-smart-phrase-gtk3-x11.png)

### 輸入兩行文字，保留組字

先輸入「**琦琦輸入法**」，按 Enter 確認，再按 Enter 換行。第二行輸入「**請假要去哪裡玩呢去海邊**」，先保留組字。一聲讀音以空白完成，其他聲調用聲調鍵。有底線的部分仍可回頭改字。以下長句流程沿用既有的 GNOME Wayland 實拍。

![文字編輯器的兩行指定文字，第一行已確認，第二行仍保留部分組字](docs/images/keykey-linux-v137-lnx06b-composition-ubuntu2404-wayland.png)

第一行已確認；第二行的「請假」已先固定，其餘仍有黑色組字底線，尚未確認整句。

### 在「玩」開候選，選字後回句尾

用方向鍵移動組字游標，按 **↓** 開候選，再確認反白目標為「玩」。選字目標預設在游標後方；若已開啟「選字目標在游標前方」，請依實際反白位置操作。支援組字點擊的 App 也可點字開候選。

![第二行保留組字，在玩開啟候選，第 1 項玩反白](docs/images/keykey-linux-v137-lnx07a-middle-candidate-ubuntu2404-wayland.png)

本機的「玩」為第 **1** 項，順位會隨詞庫、上下文與學習紀錄改變。

按候選編號或點選 **玩**，再按 **End** 回到組字末端。本例只保留「請假要去哪裡玩呢去海邊」，不追加文字。候選窗開著時 Enter 是選字；關閉後再按 Enter，才會確認整段。

![選玩後候選窗已關閉，按 End 回句尾，組字仍保留](docs/images/keykey-linux-v137-lnx07b-after-selection-ubuntu2404-wayland.png)

本機選字後游標停在「玩」後方；上圖已按 End 回句尾，尚未送出整段。

![Enter 確認後保留兩行文字，黑色組字底線與候選窗已結束](docs/images/keykey-linux-v137-lnx06c-confirmed-ubuntu2404-wayland.png)

按 Enter 後，兩行文字保留，黑色組字底線消失；紅色虛線是文字編輯器的拼字檢查。

**Backspace／Delete** 可修正目前組字位置的讀音或文字；**Esc** 可先關閉候選或取消未完成讀音。

桌面好打注音保留最多十個已完成音節；第十一個音節完成時，最前方完整詞段會先固定，其餘仍可組字。已固定的前段要用文字 App 自己的編輯功能修改。

### 傳統注音

在 Fcitx 的 Bopomofo 設定頁把「注音模式」改成 **傳統注音**。傳統注音以逐字選字為主：輸入完整讀音和聲調後顯示候選；第一聲讀音可按 **Space** 開啟候選，再按候選編號或用滑鼠選字。選字後若出現關聯詞，可按 **Shift + 1–9** 選取對應詞，也可直接開始輸入下一個字。

### 倉頡打到「竹大」，就能提前選「喬」

從琦琦設定開啟 **倉頡設定…**，勾選 **即時候選**及 **未打完也能選字**，依視窗提示儲存。桌面版這兩項預設關閉，即時候選與錯碼清除互斥。

![Linux 倉頡工具的即時候選及未打完也能選字均已勾選](docs/images/keykey-linux-v137-lnx09a-cangjie-settings-ubuntu2404-wayland.png)

上圖沿用既有的獨立倉頡工具實拍，兩項均已開啟、錯碼清除關閉。完整設定見下方[設定導覽](#倉頡與簡易進階設定)。

回文字編輯器，從 Fcitx 清單選 **Cangjie**，只輸入 H、K，也就是 **竹、大**，從候選找 **喬**。不必先輸入完整「竹大口月口」，按實際候選編號即可選字。

![只輸入竹大，喬在第 5 項反白，尚未送出](docs/images/keykey-linux-v137-lnx09b-cangjie-candidates-ubuntu2404-wayland.png)

這張既有實拍中，只打 H、K 時「喬」為第 **5** 項，選取後輸出「喬」。實際順位依詞庫與可顯示字型而異，第 2～4 項罕字在圖中顯示為方框。

### 常用按鍵

| 按鍵 | 用法 |
| --- | --- |
| **Ctrl + Space** | 切換 Fcitx 的英文鍵盤與琦琦注音。 |
| `Ctrl + \` 或短按 **Shift** | 已選琦琦注音時，切換其中文／英文模式；`Ctrl + \` 可在設定中關閉。 |
| **Shift + Space** | 切換半形與全形。 |
| **↓** | 好打注音組字時，開啟目前選字目標的候選。 |
| **1–9**、滑鼠或方向鍵後按 **Enter** | 選取候選字；選字後可繼續組字。 |
| 候選窗中的 **Space／Page Down**、**Page Up** | 候選有多頁時翻頁。 |
| **Enter** | 候選窗開啟時選字；好打注音沒有候選窗時送出整段組字。 |
| **Ctrl + 0** | 開啟符號候選清單。 |

已選琦琦注音卻仍直接輸出英文字母時，按 `Ctrl + \` 或短按 **Shift** 切回中文；這和 **Ctrl + Space** 切換 Fcitx 輸入法是兩種不同操作。

好打注音會在目前 Linux 使用者的資料目錄保存自訂詞和選字學習紀錄。進階使用者可用 `keykey-smart-phrases list` 查看自訂詞，或執行 `man keykey-smart-phrases` 查看新增、移除與重設學習紀錄的指令。

## 日常設定與已知情況

「好打注音進階設定」可調整 **空白鍵開啟候選**、選字目標在游標前／後，以及 **Esc 清除整句**。**省略聲調**可連打讀音並自動分音節。空白開候選、Esc 清句與省略聲調預設關閉；未啟用空白選字時仍可按 ↓ 開候選。啟用方式見下方[省略聲調說明](#省略聲調)。

在不同 App 或桌面 session 的鍵盤操作相同，但輸入橋接與候選窗位置可能不同。請先用上述文字編輯器主線試打，再比較其他 App。

![GNOME Terminal 中實際注音組字並開啟法的候選](docs/images/keykey-linux-v137-lnx11-terminal-candidate-ubuntu2404-wayland.png)

另一宿主為 **GNOME Terminal／GTK 3／Wayland**，使用登入環境的 `GTK_IM_MODULE=fcitx`。圖中「琦琦輸入法」仍在組字，「法」候選第 1 項反白；`#` 是終端機註解前綴。


- 在 Fcitx 5 Configuration 的 Bopomofo 設定頁可切換好打／傳統注音、五種鍵盤布局、直／橫式候選、繁轉簡與關聯詞庫。候選窗字體和外觀也受 Fcitx／GNOME 主題影響。
- GNOME 文字編輯器 46 的一般啟動方式，在某些 Wayland 輸入路徑可能無法啟用 Fcitx；可改用套件附的 **文字編輯器（琦琦注音）** 啟動器。其他 GTK App 遇到相同情況時，可用 `keykey-fcitx-app 程式名稱` 啟動。
- 切換輸入法或中英文模式時，好打注音會先完成可辨識的讀音並送出目前的組字文字。尚未完成的讀音會以原始按鍵保留。
- 實體雙螢幕、熱插拔、所有 GNOME 主題與所有 App 尚未逐一驗證；若遇到問題，請記下環境與重現步驟。

## 設定導覽

以下介紹最新版的設定。從 Fcitx 清單選琦琦輸入法並按設定齒輪，可在同一個長頁中調整各分組；改好後按 **OK／確定**或 **Apply／套用**儲存。若當下仍有組字，先完成或取消，再試新的設定。

### 一般設定

「一般」可設定啟動中／英文、中文模式的 Caps Lock 行為、數字鍵盤直接輸入、候選字窗方向、中英文切換快捷鍵、錯誤提示音與繁簡輸出。「中文模式忽略 Caps Lock」預設關閉，英文模式仍保留 Caps Lock 大小寫功能；候選窗字型與外觀由 Fcitx／桌面主題調整。

### 注音與好打組字

「注音」可切換好打／傳統模式、五種鍵盤配置、Big5 以外候選與傳統注音選字鍵。「好打注音進階設定」另有空白開候選、省略聲調、選字目標位置、**選字鍵**、**10～20 音節組字長度**、Esc 清句、選字後回句尾及 Shift 字母強制大寫，並分別控制上下文組句、記憶選字偏好與學習相鄰詞。

![注音與好打進階設定，示範啟用空白開候選與省略聲調](docs/images/keykey-linux-v152-fcitx-bopomofo.png)

好打預設使用 `123456789` 九個選字鍵、十音節組字；也可改用八鍵或字母鍵。空白開候選、省略聲調、Esc 清整句、選字後回句尾與 Shift 強制大寫預設關閉，三個組句／學習選項預設開啟。上圖為省略聲調的示範設定。

#### 省略聲調

在「注音模式」選 **好打注音**，再於「好打注音進階設定」勾選 **省略聲調**。想用空白鍵選字時，一併勾選 **空白鍵開啟候選**，然後按 **OK／確定**或 **Apply／套用**儲存。

例如標準鍵盤可連打 `ㄋㄧㄏㄠ`（`sucl`）組出「你好」，按 **Enter** 確認整句；也可照常輸入聲調指定讀音，如 `ㄋㄧˇㄏㄠˇ`（`su3cl3`）。需要改字時按 **↓** 開候選，再用目前的選字鍵或滑鼠選擇。空白鍵依「空白鍵開啟候選」設定運作；仍有未完成讀音時，會先完成一聲音節。這個選項只影響好打注音，傳統注音仍照原本逐字輸入與選字。

### 倉頡與簡易進階設定

「倉頡」可調整滿碼查詢、動態詞頻、即時與前綴候選、錯碼清除、標點、選字鍵、最長字根數及空白鍵行為；通配字可設定為 `?`／`*`，留空停用。要打「竹大」提前選「喬」，仍須開啟 **即時候選**與 **未打完也能選字**。

![原生倉頡設定，含最長字根數、空白鍵選字與通配字](docs/images/keykey-linux-v152-fcitx-cangjie.png)

「簡易」也有獨立的選字鍵、動態詞頻、標點與空白鍵設定，最長字根數可設為一或二；不提供倉頡的前綴候選。兩種輸入法的預設不同，請分別確認。

![簡易設定，包含滿碼處理、動態詞頻、選字鍵與最長字根數](docs/images/keykey-linux-v152-fcitx-simplex.png)

### 自訂詞與詞庫

「使用自訂詞庫」可控制自訂詞；按 **管理自訂詞與學習資料…**可新增、修改、刪除自訂詞，重設學習，或匯入／備份完整 Guanyinma JSON。「詞庫」分組可逐項開關 **小麥注音與 33 組分類**的關聯詞，包含常見名字、港澳用語、台灣用語及中國用語。

![自訂詞管理入口與分類詞庫開關](docs/images/keykey-linux-v152-fcitx-phrases.png)

繼續向下捲動可看到詞庫尾端；這些開關控制關聯詞提示，與「使用自訂詞庫」及好打注音的學習開關分開設定。

![詞庫尾端，包含常見名字、港澳用語、台灣用語與中國用語](docs/images/keykey-linux-v152-fcitx-phrases-bottom.png)

新版自訂詞與學習使用獨立的 `guanyinma-user.db`；舊 Linux 使用者資料不會自動匯入或刪除。完整設定及資料說明見 [Linux／FreeBSD Guanyinma 接合](docs/GUANYINMA_LINUX_ADAPTER.md)。

## 遇到問題時

| 情況 | 先檢查 |
| --- | --- |
| `sha256sum` 顯示 `FAILED` | 停止安裝，確認五個檔案都來自同一版正式發布頁，重新下載失敗的檔案。 |
| Fcitx 清單找不到琦琦注音 | 確認三個 `.deb` 已安裝、取消語言篩選，重新登入後再開設定工具。 |
| 找得到輸入法，但打字只有英文 | 確認選到 Bopomofo，按 `Ctrl + \` 切回中文；第一聲讀音後按 **Space** 完成音節。 |
| 只有「文字編輯器（琦琦注音）」可用，Firefox 或終端機只輸出英文 | 重新啟動 Ubuntu 後再開啟這些 App。執行 `printenv GTK_IM_MODULE QT_IM_MODULE XMODIFIERS`，三行應依序為 `fcitx`、`fcitx`、`@im=fcitx`；若仍是 `ibus`，重新執行 `im-config` 選 **fcitx5** 並重啟。 |
| 候選窗位置或滑鼠操作異常 | 執行 `keykey-gnome-panel status`，確認 `State: ACTIVE`；若曾自行安裝同名 GNOME 擴充，檢查是否存在重複版本。 |
| 只有 GNOME 文字編輯器無法輸入 | 用 **文字編輯器（琦琦注音）** 啟動器重試，並到其他文字欄位比較。 |

仍無法使用時，請記下 Ubuntu 版本、`dpkg --print-architecture` 的輸出、安裝檔名、`keykey-gnome-panel status` 的結果，以及無法輸入的 App 和文字欄位。

## 移除

先在 Fcitx 5 Configuration 的目前使用清單移除琦琦注音，再執行：

```sh
keykey-gnome-panel disable
sudo apt remove fcitx5-chichi77-keykey chichi77-keykey-data \
  gnome-shell-extension-keykey-kimpanel
```

登出並重新登入後，GNOME 會重新載入擴充狀態。這不會刪除其他 Fcitx 輸入法或 Fcitx 個人設定。

## 圖片與適用範圍

設定圖為最新版原始碼在 Ubuntu／X11（Xvfb）隔離工作階段實拍；注音圖示範開啟空白選字與省略聲調，兩者預設均關閉。

套件校驗、關於頁及桌面輸入流程沿用既有實拍，包含 GNOME Wayland 與 GTK 文字欄。畫面可能因已安裝版本或桌面主題而略有不同；圖片記錄與平台範圍見 [跨平台截圖計畫](docs/CROSS_PLATFORM_SCREENSHOT_PLAN.md)。
