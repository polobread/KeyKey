# FreeBSD 琦琦輸入法安裝與使用指南

本指南以最新版琦琦輸入法的功能為主，帶你完成 **安裝套件 → 設定桌面環境 → 加入 Fcitx → 在 Mousepad 試打**，並介紹[共用設定](#共用設定導覽)與省略聲調。軟體透過 FreeBSD 官方 ports／pkg 安裝及更新；套件可能較晚上架，請先查詢可用版本。

需要可登入的圖形桌面、網路及管理員權限；下方桌面操作以 **Xfce／X11、LightDM、Fcitx 5 與 Mousepad／GTK 3** 為例。安裝套件用 root，設定與打字使用一般帳號。

套件資訊可先看 [FreshPorts：chinese/fcitx5-keykey](https://www.freshports.org/chinese/fcitx5-keykey/)，查看 port 版本、相依套件及更新紀錄；本機已安裝版本以 `pkg info` 核對。

![FreshPorts 的 chinese/fcitx5-keykey 套件資訊頁](docs/images/keykey-freebsd-v137-bsd11-freshports.png)

最新版使用 Guanyinma（觀音嬤，Rust）共用核心。升級前先備份既有使用者資料；新核心使用 `guanyinma-user.db`，不提供舊 C++ 詞庫的讀寫或匯入，也不會自動刪除舊檔。

## 1. 從套件庫直接安裝

開啟桌面終端機，切換 root 後先更新目錄並查詢：

```sh
su -
pkg update
pkg search -x '^zh-fcitx5-keykey'
```

![刷新套件庫後查詢琦琦輸入法的可用版本](docs/images/keykey-freebsd-v137-bsd01a-pkg-search.png)

可用版本依 FreeBSD 版本、架構與套件庫分支而異；若套件庫較舊，可依下一節確認 ports 版本後編譯。

若清單已提供你要的版本，繼續安裝，完成後查看本機版本：

```sh
pkg install zh-fcitx5-keykey
pkg info -x keykey
```

![用 pkg info 確認本機已安裝的琦琦版本](docs/images/keykey-freebsd-v137-bsd01b-installed.png)

**確認版本符合需求後，可直接前往第 3 節設定桌面。** 若需要的新版尚未進入套件庫，改走下一節 ports 流程。

安裝寫入 `/usr/local` 與系統套件資料庫，需要 root；字型、個人設定與打字則用一般帳號。`pkg install` 依套件名稱安裝；`pkg add` 用於本機 `.pkg` 或完整 URL，範例見下一節。

## 2. 從 ports 編譯安裝

ports tree 是 FreeBSD 軟體的建置配方集合。`chinese/fcitx5-keykey` 會下載對應版本的琦琦原始碼、校驗、編譯並產生可由 pkg 管理的套件。

已從套件庫安裝所需版本的人可跳過本節。需要編譯時，依下方步驟先確認 port 版號，再建置與安裝。

### 2.1 用 net/gitup 取得或更新 /usr/ports

以 root 安裝輕量的 [net/gitup](https://github.com/johnmehr/gitup)：

```sh
pkg install net/gitup
```

首次使用前，確認 `/usr/local/etc/gitup.conf` 的 `ports` 區段指向官方 `git.freebsd.org` 的 `/ports.git`、`main` 分支及本機 `/usr/ports`；這是[上游預設設定](https://github.com/johnmehr/gitup/blob/main/gitup.conf)。若設定檔不存在，可從同目錄的 `gitup.conf.sample` 複製建立。

**`/usr/ports` 不存在、為空目錄，或已由 net/gitup 管理時**，執行：

```sh
gitup ports
```

這個指令會依設定取得或更新 ports tree，日後更新也使用同一指令。更新後仍須依下方步驟確認 port 版號、編譯並安裝，才會更新琦琦。

若 `/usr/ports` 已有 `.git`，請沿用原本的 Git 更新方式；net/gitup 不會接管 Git checkout。其他已有內容的目錄也先保留，可將 `ports` 的 `target_directory` 改成尚未使用的目錄（例如 `/usr/ports-keykey`），並將後續路徑一併改成該目錄。若選用 quarterly 分支，port 可能仍是舊版，更新後仍須確認版號。

### 2.2 確認 port 版號與來源

```sh
cd /usr/ports/chinese/fcitx5-keykey
make -V DISTVERSION
make -V PKGNAME
```

確認 port 提供你要的版本，再繼續編譯；若仍較舊，先等待 port 更新。`PKGNAME` 是完成後的套件名稱，可能包含 `_1` 等套件修訂尾碼。

![查詢 port 的來源版本與套件名稱](docs/images/keykey-freebsd-v137-bsd02a-ports.png)

最新版採用 Rust 核心，port 配方需包含鎖定 Rust 工具鏈、Cargo 來源、json-c、PangoFT2／Fontconfig、SQLite 與 Fcitx 等相依及安裝清單。請使用已更新的 port 配方建置。

### 2.3 設定編譯選項與相依套件

查看目前選項；需要調整時開啟設定：

```sh
make showconfig
make config
```

若顯示沒有可設定選項，正常繼續。若希望先設定所有相依 port，可執行 `make config-recursive`，依畫面選項設定後再編譯。

本指南使用 `BATCH=yes`，採用已儲存的選項，尚未設定者使用預設值，避免編譯途中反覆出現選項視窗；`MAKE_JOBS_NUMBER=4` 限制單一 port 的平行編譯工作數，可依可用記憶體調低。這些值直接寫在命令中即可，不必改全域 `/etc/make.conf`。

ports 會處理缺少的建置與執行相依套件；缺少的相依 port 也可能需要編譯。既有套件應與所選 ports tree 相容，若遇到函式庫版本錯誤，先處理失敗原因再安裝。

### 2.4 編譯並產生套件

```sh
make BATCH=yes MAKE_JOBS_NUMBER=4 package
make BATCH=yes check-plist
make -V PKGNAME
ls -l work/pkg/
```

第一行會下載原始碼並校驗、安裝缺少的相依套件、編譯及封裝。確認建置與 `check-plist` 均無錯誤，再核對 `work/pkg/` 中的 `.pkg` 檔名與 `PKGNAME` 相符。`check-plist` 檢查安裝檔案與 port 清單是否一致。

### 2.5 安裝編好的套件

先儲存正在編輯的文件並關閉琦琦設定視窗。將下方 `PACKAGE_FILE` 換成上一節顯示的實際檔名（含 `.pkg`），只指定本次建置的單一套件：

```sh
pkg add -f ./work/pkg/PACKAGE_FILE
pkg info -x keykey
```

`-f` 用於替換已安裝的舊套件；確認 `pkg info` 的結果與剛建置的版本一致。安裝後由 pkg 記錄與管理，不需要手動複製程式至 `/usr/local`。

![ports 產生的套件與本機已安裝版本](docs/images/keykey-freebsd-v137-bsd02b-package-installed.png)

若是尚未安裝琦琦的系統，也可在同一個 port 目錄使用 `make BATCH=yes MAKE_JOBS_NUMBER=4 install clean` 直接編譯安裝；前面已完成 `pkg add` 時不需重做。

若要保留套件供重裝，先將 `.pkg` 複製到其他目錄；不需保留工作目錄時再執行 `make clean`。下一步補齊桌面整合後，登出並重新登入，以載入新版輸入法。

## 3. 補上 GTK 3 輸入橋接

Mousepad 使用 GTK 3，需要對應的 Fcitx 模組；只裝 GTK 4 bridge 仍不足。在 root shell 執行：

```sh
pkg install -y fcitx5 fcitx5-configtool fcitx5-gtk3
pkg info -x fcitx5-gtk
```

![已安裝的 Fcitx GTK common、GTK 3 與 GTK 4 bridge 版本](docs/images/keykey-freebsd-v137-bsd03a-gtk.png)

若安裝出現 `GLib version too old (micro mismatch)`，先看文末的 GLib 排除方式，完成後再重新開啟 App。

安裝結束：

```sh
exit
```

## 4. 確認中文字型

若中文或注音顯示為缺字方框，先檢查：

```sh
fc-list :lang=zh family
```

可在一般使用者的字型目錄安裝 [Noto 官方繁體中文字型](https://github.com/notofonts/noto-cjk/blob/main/Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf)：

```sh
mkdir -p ~/.local/share/fonts
fetch -o ~/.local/share/fonts/NotoSansCJKtc-Regular.otf \
  https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf
fc-cache -f ~/.local/share/fonts
```

![字型查詢包含 Noto Sans CJK TC](docs/images/keykey-freebsd-v137-bsd03b-fonts.png)

本機已有 Noto Sans CJK TC，不需重複下載；下方 Mousepad 圖可見指定中文正常顯示。倉頡清單的少數罕字仍缺字，見第 8 節。

完成字型與下一步環境設定後，儲存文件並登出／登入，使 Fcitx、設定視窗與編輯器都載入新字型。

## 5. 設定環境變數，重新登入

使用 LightDM 登入 Xfce 時，可檢查登入腳本是否載入 `~/.xprofile`，再用一般帳號開啟該檔案：

```sh
grep -n xprofile /usr/local/etc/lightdm/Xsession
ee ~/.xprofile
```

檔案不存在時可建立。在檔案加入以下三行，保留其他既有設定，儲存後離開編輯器：

```sh
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
```

確認 `/usr/local/etc/xdg/autostart/org.fcitx.Fcitx5.desktop` 存在；Xfce 的「設定 → 工作階段與啟動 → 應用程式自動啟動」中也應啟用 Fcitx 5。若沒有自動啟動項目，可在該介面新增，名稱填 `Fcitx 5`、命令填 `/usr/local/bin/fcitx5 -d`，已有項目時不必重複新增。

接著**儲存文件、登出 Xfce，再重新登入**。其他登入管理器應先確認其環境設定入口；`~/.xprofile` 只有被登入流程讀取才會生效。

重新登入後開啟終端機：

```sh
env | grep -E '^(GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS)='
pgrep -laf fcitx5
```

三個值應分別為 `fcitx`、`fcitx`、`@im=fcitx`，並能看到 Fcitx 行程。

![重新登入後三個輸入環境值正確，X11 工作階段中已有 Fcitx 行程](docs/images/keykey-freebsd-v137-bsd03c-login.png)

![Xfce 應用程式自動啟動已勾選 Fcitx 5](docs/images/keykey-freebsd-v137-bsd03c-autostart.png)

之後直接從桌面開啟 App 試打；只用單次環境變數啟動 App，不能代替登入環境驗證。

## 6. 加入琦琦輸入法

從 Applications → Settings → Fcitx 5 Configuration 開啟設定，或在一般使用者的終端機執行：

```sh
fcitx5-config-qt
```

取消右下方 **Only Show Current Language**，在搜尋欄輸入 `keykey`，將需要的輸入法加入左側清單並按 **Apply**：

| 清單名稱 | 用途 |
|---|---|
| chichi77 KeyKey Bopomofo | 注音，包含好打注音與傳統注音 |
| chichi77 KeyKey Cangjie | 倉頡 |
| chichi77 KeyKey Simplex | 簡易 |

保留 Keyboard – English (US) 作為英文鍵盤。

![搜尋 keykey 後可加入注音、倉頡與簡易三個項目](docs/images/keykey-freebsd-v137-bsd04a-search.png)

先取消語言篩選，再搜尋；搜尋時介面會收起語言篩選列。這張圖呈現加入前的清單。


![重新登入後保留的琦琦注音、倉頡與簡易](docs/images/keykey-freebsd-v137-bsd04-current-list.png)

*左側是目前可切換的輸入法，重新登入後仍應保留。*

單擊左側 **Bopomofo**，再按齒輪開啟設定。先保留「標準」注音鍵盤配置與「好打注音」模式；需要逐字選字時，再改成傳統注音。

設定依「一般、注音、倉頡、簡易、自訂詞、詞庫」分組，可向下捲動。

![共用 Fcitx 設定的一般分組](docs/images/keykey-linux-v152-fcitx-general.png)

## 7. 在 Mousepad 試打與選字

直接從桌面開啟 Mousepad，新增空白文件並點選文字區。按 **Ctrl+Space** 切到琦琦注音；新文件若仍輸出英文鍵碼，先確認該文件的輸入法啟用狀態。

在 Xfce 上方面板的 Fcitx 圖示按右鍵，可看到目前輸入法；圓點應在 **chichi77 KeyKey Bopomofo**。

![Xfce 面板的 Fcitx 選單已選用 KeyKey Bopomofo](docs/images/keykey-freebsd-v137-bsd05-selected.png)

### 用兩行文字練習句中選字

先輸入「**琦琦輸入法**」，按 Enter 確認，再按 Enter 換行；第二行輸入「**請假要去哪裡玩呢去海邊**」，先不要確認。用方向鍵移動組字游標，按 **↓** 開候選，依反白目標確認正在修改「玩」。

![第一行已確認，第二行仍在好打注音組字區](docs/images/keykey-freebsd-v137-bsd06b-composition.png)

![在句中的玩開啟候選，第 1 項為玩](docs/images/keykey-freebsd-v137-bsd07a-middle-candidate.png)

選 **玩**後，組字游標會停在「玩」後方，第二行仍有底線。按 **End** 回到句尾，再按 **Enter** 確認，保留原句。候選開著時 Enter 是選字，關閉後才確認整段。

![選玩後候選關閉，組字游標停在玩後方](docs/images/keykey-freebsd-v137-bsd07b-after-selection.png)

![Enter 確認後，兩行文字保留在 Mousepad，組字底線消失](docs/images/keykey-freebsd-v137-bsd06c-confirmed.png)

### 常用操作與長句示範

常用操作：

| 按鍵 | 用途 |
|---|---|
| Ctrl+Space | 切換琦琦與英文鍵盤 |
| ↓ | 在好打注音組字中開候選 |
| Page Down／Page Up | 候選翻頁與返回 |
| 數字鍵 | 選取該頁候選，修改組字內容 |
| Enter | 候選關閉時提交組字 |
| Backspace | 刪除未完成讀音的末碼 |
| Esc | 取消未完成讀音 |

也可用長句「請假要去哪裡玩呢去海邊因為那裡有比基尼」練習連續組字、句中選字與確認，再切回英文輸入 `abc 123`。

![完整回歸句、候選選字與英文切換結果](docs/images/keykey-freebsd-v137-typing-result.png)

## 8. 確認關於與設定工具

從琦琦設定的「關於琦琦輸入法」開啟關於視窗，也可執行：

```sh
keykey-about
```

![FreeBSD 的琦琦輸入法關於視窗](docs/images/keykey-freebsd-v137-bsd10-about.png)

關於頁可確認本機版本與專案連結。

### 倉頡：只輸入「竹大」，提前選「喬」

從注音設定內點 **開啟倉頡設定…**，開啟 **即時候選**與 **未打完也能選字**。桌面版預設關閉，即時候選與錯碼清除互斥；改好依提示儲存。

![倉頡工具已開啟即時候選與未打完也能選字，錯碼清除關閉](docs/images/keykey-freebsd-v137-bsd09a-cangjie-settings.png)

完整倉頡選項也可在下方[共用設定](#倉頡與簡易)中調整。

回 Mousepad，從 Fcitx 選 **Cangjie**，只輸入 H、K，也就是 **竹、大**，查看包含 **喬**的候選。想選喬時按實際編號或點選，不必先打完「竹大口月口」。

![只輸入竹大後顯示候選，第 5 項喬已反白，尚未確認](docs/images/keykey-freebsd-v137-bsd09b-cangjie-candidates.png)

候選順序依詞庫與設定而異，請按實際編號或用滑鼠選取；若罕字顯示方框，先確認中文字型。

更新通知只提醒有新版，FreeBSD 仍透過 ports／pkg 更新，套件可能較晚上架。

## 共用設定導覽

Linux／FreeBSD 共用 Fcitx 5 前端與 Guanyinma（Rust）核心。以下介紹最新版的設定；若本機找不到某個選項，先確認安裝版本與 ports／pkg 的更新狀態。

從 Fcitx 清單選取琦琦輸入法並按齒輪，即可在同一長頁調整各分組；改好按 **OK／確定**或 **Apply／套用**儲存。若當下仍有組字，先完成或取消，再試新的設定。

### 一般與注音

「一般」可調整啟動中／英文、Caps Lock、數字鍵盤、候選字窗方向、中英切換、提示音與繁簡輸出；「中文模式忽略 Caps Lock」預設關閉，英文模式保留大小寫功能。

「注音」可選好打／傳統模式、五種鍵盤配置、字集與傳統選字鍵。「好打注音進階設定」包括空白開候選、省略聲調、選字目標、選字鍵、**10～20 音節組字長度**、Esc 清句、選字後回句尾、Shift 字母強制大寫，以及上下文組句、記憶選字偏好與學習相鄰詞。預設為九個數字選字鍵、十音節；空白開候選、省略聲調與 Shift 強制大寫預設關閉。

![共用注音與好打進階設定，示範空白開候選與省略聲調](docs/images/keykey-linux-v152-fcitx-bopomofo.png)

#### 省略聲調

將「注音模式」選為 **好打注音**，於「好打注音進階設定」勾選 **省略聲調**；想用空白鍵選字時，一併勾選 **空白鍵開啟候選**，再儲存。上圖即為這組示範設定。

例如標準鍵盤可連打 `ㄋㄧㄏㄠ`（`sucl`）組出「你好」，按 **Enter** 確認整句；也可照常輸入聲調指定讀音，如 `ㄋㄧˇㄏㄠˇ`（`su3cl3`）。需要改字時按 **↓** 開候選，沿用目前的選字鍵或滑鼠選字。空白鍵依「空白鍵開啟候選」設定運作；仍有未完成讀音時，會先完成一聲音節。這個選項只影響好打注音，傳統注音仍照原本逐字輸入與選字。

### 倉頡與簡易

「倉頡」可調整滿碼查詢、動態詞頻、即時／前綴候選、錯碼清除、標點、選字鍵、最長字根數、空白鍵行為及通配字；開啟 **即時候選**與 **未打完也能選字**，即可使用前述「竹大 → 喬」功能。

![共用倉頡進階設定](docs/images/keykey-linux-v152-fcitx-cangjie.png)

「簡易」有獨立的滿碼、動態詞頻、標點、選字鍵與空白鍵設定，最長字根數為一至二；不提供倉頡的前綴候選。

![共用簡易設定](docs/images/keykey-linux-v152-fcitx-simplex.png)

### 自訂詞與詞庫

「使用自訂詞庫」控制自訂詞；按 **管理自訂詞與學習資料…**可新增／修改／刪除自訂詞、重設學習及匯入／備份完整 Guanyinma JSON。「詞庫」可逐項開關 **小麥注音與 33 組分類**的關聯詞，包含常見名字、港澳用語、台灣用語與中國用語。

![共用自訂詞管理入口與分類詞庫開關](docs/images/keykey-linux-v152-fcitx-phrases.png)

向下捲動可看更多分類。這些開關控制關聯詞提示，與自訂詞及好打學習選項分開設定。

![共用詞庫尾端，包含常見名字與地區用語](docs/images/keykey-linux-v152-fcitx-phrases-bottom.png)

新版自訂詞與學習使用獨立的 `guanyinma-user.db`，既有舊資料不會自動匯入或刪除。依賴、設定與資料路徑詳見 [Linux／FreeBSD Guanyinma 接合](docs/GUANYINMA_LINUX_ADAPTER.md)；另可參考 [Linux 設定導覽](LINUX_INSTALL.md#設定導覽)。

## 常見環境問題

### GTK 3 bridge 回報 GLib 太舊

若安裝 GTK 3 bridge 時回報 `GLib version too old (micro mismatch)`，使用 root 先預覽更新範圍，確認適合後才執行：

```sh
pkg install -n glib
pkg install -y glib
pkg install -y -f fcitx5-gtk3
```

更新完成後重新安裝 bridge，確認 GTK 模組註冊成功，再登出並登入。此步驟用於處理特定相依版本不相容。

### 一般帳號不能使用 su

由管理者登入 root 後，將要授權的帳號加入 wheel，保留既有成員：

```sh
pw groupmod wheel -m YOUR_USER
id YOUR_USER
```

將 `YOUR_USER` 替換成要授權的帳號；確認群組包含 `0(wheel)`，再重新登入該帳號。密碼由帳號持有人自行輸入。


### 移除或更新輸入法

移除系統套件時執行：

```sh
su -
pkg delete zh-fcitx5-keykey
exit
```

一般帳號的設定與學習資料仍會保留。日後更新可重新走 ports 流程，或在套件庫提供需要的版本後透過 pkg 更新；先查看安裝計畫，確認版號。

## 圖片來源

安裝與桌面操作圖取自較早版本的 FreeBSD 實機，共用設定圖取自 Ubuntu 的最新版隔離工作階段；後者供介面參考，不代表新版已完成 FreeBSD 原生驗收。

## 參考

- [FreshPorts：chinese/fcitx5-keykey](https://www.freshports.org/chinese/fcitx5-keykey/)
- [FreeBSD Handbook：Packages and Ports](https://docs.freebsd.org/en/books/handbook/ports/)
- [官方 ports 原始碼](https://cgit.freebsd.org/ports/tree/chinese/fcitx5-keykey)
- [Linux／FreeBSD frontend](Source/Loaders/Linux-IME/README.md)
- [更新通知與 ports 整合](Source/Loaders/Linux-IME/docs/update-notifications.md)
- [實體鍵盤固定回歸句](docs/SMART_MANDARIN_PHYSICAL_KEYBOARD_HANDOFF.md)
- 圖文編排參考：[琦琦注音介紹與使用教學](https://free.com.tw/chichi-keykey/)
