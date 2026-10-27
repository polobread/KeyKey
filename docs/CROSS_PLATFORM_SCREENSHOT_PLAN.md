# 六大平台安裝與使用截圖補拍計畫

本清單供 Windows、macOS、iOS／iPadOS、Android、Linux 與 FreeBSD 逐平台補齊安裝指南及媒體素材。拍攝主線為「取得正式版 → 安裝／啟用 → 選用輸入法 → 第一次打字 → 選字與改字」。

規劃基準：2026-10-25 的 `master` 文件與目前正式版 **1.3.7**。Windows 已補齊 23 張，Linux／Ubuntu 已補齊 18 個位置、20 張圖片，FreeBSD 已補齊 15 個位置、新增 20 張圖片；macOS 已入文 18 張，本輪指南補圖已齊，iOS 已加入 App Store 實機商品頁、台灣價格實機首頁、14 張 iPhone 模擬器操作圖及 9 張 iPad 模擬器原圖；Android 已補 10 張手機模擬器原圖及 5 張局部圖。其餘畫面仍待逐一補齊。未完成的子畫面保留待拍，不因同一項已有一張圖而視為全項完成。六平台指南已依相同操作順序整理，缺圖位置以「待補圖｜ID」標示；第 12 節列出每處的缺圖依據與放置段落。

## 1. 使用方式與優先順序

| 優先級 | 要解決的使用者問題 | 完成條件 |
| --- | --- | --- |
| P0：首次使用 | 從哪裡下載、安裝後在哪裡開啟、如何確認已能輸入中文？ | 對照指南可走完安裝到第一次成功輸入，不缺系統啟用或切換步驟。 |
| P1：基本操作與主要特色 | 如何開候選、句中改字、切換好打／傳統注音、使用倉頡提前選字？ | 拍到設定入口、實際操作及結果，圖說能解釋下一步。 |
| P2：進階與補充 | 自訂詞、符號、外接鍵盤不同呈現與特殊版面如何使用？ | 補在對應功能段落，與主線分開呈現。 |

建議執行順序：**Windows → Android → iOS／iPadOS → macOS → Linux → FreeBSD**。Windows 優先補系統新增鍵盤；手機接著更新品牌與設定畫面；FreeBSD 已有一組 1.3.7 桌面素材，可先複核再補前半段。可依可用設備調整順序；每次先完成一個平台的 P0，再完成該平台 P1，最後處理 P2。

| 平台 | P0 已入文 | P1 已入文 | P2 已入文 | 本輪狀態 |
| --- | --- | --- | --- | --- |
| Windows | 已入文 | 已入文 | 已入文 | 2026-10-24 共 23 張入文；維護者補完成頁、Windows 切換前／已選琦琦兩種狀態及四模式選單。本輪指南補圖已齊，未擴大平台驗收範圍 |
| Android | 部分入文 | 部分入文 | ☐ | 2026-10-24 正式 v1.3.7 來源，10 張手機模擬器原圖及 5 張局部圖已引用；商店頁、實機、實體鍵盤與平板另待補 |
| iOS／iPadOS | 部分入文 | iPhone／iPad 模擬器已入文 | 部分入文 | 2026-10-25 共 25 張原圖及 1 張局部裁切圖已引用；正式 1.3.7 來源，App Store 商品頁已補，實機輸入仍待補 |
| macOS | 已入文 | 已入文 | 已入文 | 2026-10-25 共 18 張入文；英文輸入提示已補，更新頁與每週通知合用一張圖；依維護者要求不另拍選字後續打，本輪指南補圖已齊 |
| Linux | 已入文 | 已入文 | 已入文 | 2026-10-24 共 20 張入文、18 個補圖位置已齊；Ubuntu 24.04.5／GNOME 46／Wayland／amd64 VM，1.3.3 升級至 1.3.7，未擴大為全新安裝或 X11 驗收 |
| FreeBSD | 已入文 | 已入文 | 已入文 | 2026-10-24 新增 20 張實拍，原 15 個補圖位置已齊；套件庫刷新後 quarterly 1.3.0、本機 ports 安裝 1.3.7，指定兩組情境已核對 |

各列「待拍／待重拍／待複核」完成後依序改為「已拍待確認 → 已確認待入文 → 已入文」，並在第 11 節登記檔案、實際環境與最終圖說。圖說均為草稿，必須依實際畫面修正，不能為符合圖說而後製產品內容。

## 2. 編輯方式與既有素材盤點

參考[免費資源網的琦琦介紹](https://free.com.tw/chichi-keykey/)所採用的下載、安裝、系統加入輸入來源與首次選字順序，每張圖對應一項操作及可辨認的完成狀態。媒體文章屬外部介紹，正式版本及支援範圍以本專案 Release 與安裝指南為準；新版素材統一說明六平台支援及 1.3.7 商店上架。

| 平台 | 現有素材與指南 | 本輪補拍重點 |
| --- | --- | --- |
| Windows | [安裝指南](../WINDOWS_INSTALL.md)、本輪 23 張圖片（第 11 節） | 已補齊安裝、新增鍵盤、切換前後、指定輸入／候選、四模式及設定；舊 1.3.0 圖未冒充新版。 |
| macOS | [安裝指南](../MACOS_INSTALL.md)、本輪正式版 1.3.7 實拍（第 11 節） | 已替換指南的 1.3.0 候選／設定與新增來源示意；已補解壓後安裝檔、安裝完成頁、Emoji、更新設定及英文輸入提示，本輪指南補圖已齊。 |
| iOS／iPadOS | [安裝指南](../IOS_INSTALL.md)、本輪 1.3.7 實機首頁及 iPhone／iPad 模擬器圖（第 11 節） | 已串起新增鍵盤、切換、指定句中選字與倉頡；已補 iPad 啟用、直橫向版面與指定情境；App Store 商品頁已補，iPhone／iPad 實機輸入及外接鍵盤實機待補。 |
| Android | [安裝指南](../ANDROID_INSTALL.md)、本輪 1.3.7 Pixel 8 Pro 模擬器圖（第 11 節） | 已替換首頁、啟用、選用、句中候選與新版設定；商店頁、實機、雙排選字、浮動窗、面板收合及平板／橫向待補。 |
| Linux | [安裝指南](../LINUX_INSTALL.md)、本輪 1.3.7 的 20 張圖片（第 11 節） | 已補下載、校驗、升級、Fcitx 啟用、面板 ACTIVE、設定、玩與竹大／喬候選及兩個宿主；舊圖未冒充新版。 |
| FreeBSD | [安裝指南](../FREEBSD_INSTALL.md)、本輪 20 張實拍（第 11 節） | 已補套件庫刷新與查詢、既有安裝版號、ports 來源、登入環境、桌面選用及兩組指定情境。 |

後續各平台指南採相同的圖文編排方式：先以短段落說明用途與適用環境，再沿下載、安裝／啟用、試打逐步展開。每段先說要按哪裡，緊接對應截圖，再用圖說指出完成狀態與下一步；避免先列一長串步驟，最後才集中放圖。日常功能與問題排查放在首次使用之後，圖片來源、驗證範圍及進階指令移到後段。參考外部文章的說明技巧，文字依本專案實際操作重新撰寫，不沿用其舊版號、平台狀態或句子。

既有示意 SVG 可保留作路徑說明；圖說需標示「示意圖」。舊版實拍保留真實版本；Windows 與 Linux 主線原有 1.3.0 圖已由新版實拍替換，舊檔未刪除，也未將舊圖改標為 1.3.7。商店素材的來源紀錄見 [StoreAssets README](../StoreAssets/README.md)，其舊版素材也須依本清單複核。

### 指南中的待補圖如何填入

每處使用 `> **待補圖｜平台-ID**`，下一行寫出應拍內容。ID 沿用第 4～9 節，必要時加 a／b／c 拆成不同狀態；每張圖要證明的結果與缺圖理由見第 12 節。只新增占位不會將狀態改成「已拍」或「已入文」。後續補圖時，依序核對來源、完成條件與圖說，再以真實圖片替換該位置並更新第 11 節登記。

缺圖依據分為：**無對應圖片、只有舊版圖片、已有操作前畫面但缺後續結果、只有模擬器而缺實機**。現有圖片仍待複核的項目另保留「待複核」，不等同沒有圖，也不以這次文案編輯代替平台測試。

## 3. 共通拍攝情境

| 情境 | 拍攝方式 | 圖說應說明 |
| --- | --- | --- |
| 好打注音指定兩行 | 第一行輸入「琦琦輸入法」，確認並換行；第二行輸入「請假要去哪裡玩呢去海邊」，先不要按 Enter／Return 或觸控確認，保留組字。 | 第一行已確認、第二行仍有組字；超出組字範圍的前段可能已自動固定。 |
| 「玩」的候選截圖 | 接續上述第二行，依平台操作對「玩」開啟下拉／候選清單，將「玩」反白或保持可選，截圖前不要先確認整句。另補選字後繼續輸入的畫面。 | 同時看得到兩行文字、仍在組字的範圍、展開的候選及「玩」；編號以實拍為準。 |
| 倉頡「竹大 → 喬」 | 拍到「即時候選」與「未打完也能選字」設定；切到倉頡，只輸入「竹大」（實體美式鍵盤 H、K），停在候選清單，拍到「喬」，不要先打完「竹大口月口」或選字送出。必要時翻到對應候選頁再拍。 | 畫面同時可見「竹大」字根與「喬」候選；不宣稱固定在第一頁或固定編號。 |
| 模式切換 | 拍到好打注音、傳統注音、倉頡及簡易的實際入口與目前選項。 | 當前模式與切換方法；名稱依實際 UI。 |
| 送出成功 | 確認文字後拍宿主欄位中的結果。 | 已完成輸入，而非只有開啟 App 或顯示空白鍵盤。 |

倉頡觸控與實體鍵盤設定須分清楚；桌面開關預設關閉，手機螢幕鍵盤的新設定預設開啟，既有使用者可能保有先前選擇。拍攝時記錄實際值，勿為展示而重設使用者資料。

### 六平台共用的實測與交付要求

**Windows、macOS、iOS、Android、Linux、FreeBSD 每個平台都必須親自執行上述兩組指定情境，不能以共用引擎測試、另一平台截圖或舊版本圖片代替。** 本輪先把規格寫入文件，未操作的平台仍列待驗證。

1. 先記錄已安裝版本、來源、OS、裝置、文字宿主及鍵盤型態。iPhone／iPad、觸控／外接鍵盤、X11／Wayland 分別記錄，不共用驗證結果。
2. 好打注音先輸入第一行「琦琦輸入法」，確認後換行；輸入第二行「請假要去哪裡玩呢去海邊」，保持組字，不先送出第二行。
3. 桌面以組字游標及方向下鍵、手機以點組字格等實際入口，在「玩」展開候選；保持「玩」可選或反白後拍攝。只有仍在組字範圍內的字可回頭修改。不要用貼上文字模擬組字。
4. 倉頡先拍實際開關值，必要時依使用者原設定調整並記錄；輸入「竹大」後拍到包含「喬」的候選。若在後頁，保留頁碼；不要為符合圖說改候選順位。
5. 兩張候選圖均須保留文字宿主及完整候選窗；避免其他視窗、個人資料、系統通知。macOS、Windows、Linux 的下載頁使用**未登入 GitHub**的畫面，包含正式版本／檔名與 AWS CDN 入口，不拍入維護者的編輯控制項或下載次數。
6. 額外的「選字後繼續輸入」與「確認送出」另拍，不用它們取代尚未送出的候選截圖。通過後才把對應項目改成已入文。

| 平台 | 本輪「兩行好打注音＋玩候選」 | 本輪「倉頡竹大＋喬候選」 | 對應工作／環境要求 |
| --- | --- | --- | --- |
| Windows | 已實拍入文 | 已實拍入文（含兩開關） | WIN-06／07／09；Windows 11 26H2 x64、已安裝 1.3.7、記事本。玩第 3 項；選字後按 End 回句尾，不追加詞語。 |
| macOS | 已實拍入文 | 已實拍入文（含兩個開關） | MAC-06／07a／09；1.3.7、macOS 27.0.1、文字編輯；維護者提供候選圖；依要求不另拍選字後續打。 |
| iOS／iPadOS | iPhone／iPad 模擬器均已實拍入文 | iPhone／iPad 模擬器均已實拍入文（含兩個開關） | IOS-06／07／09／10；正式 v1.3.7 來源、原本 Debug 組態，觸控輸入；iPhone／iPad 實機另驗。App 前景編輯器另記 IOS-11。 |
| Android | 手機模擬器已實拍入文 | 手機模擬器已實拍入文（含兩個虛擬鍵盤開關） | AND-05／06／08；正式 v1.3.7 來源、Debug 自建，Android 15／Pixel 8 Pro／聯絡人未儲存備註欄／觸控；實機及實體鍵盤另驗。 |
| Linux | 已實拍／已入文 | 已實拍／已入文 | GNOME Wayland：Text Editor 的玩第 1 項、竹大／喬第 5 項；另拍 Terminal／GTK 3，不代替 X11。 |
| FreeBSD | 已實拍／已入文 | 已實拍／已入文 | Mousepad 0.7.0／GTK 3、Xfce／X11：玩第 1 項、竹大／喬第 5 項；實際儲存檔文字一致。 |

### 桌面下載入口與 AWS CDN

下載入口依各平台目前正式版本分開：macOS 使用 [1.3.8](https://github.com/polobread/KeyKey/releases/tag/v1.3.8)，Windows 與 Linux 使用 [1.3.7](https://github.com/polobread/KeyKey/releases/tag/v1.3.7)。GitHub 的 Latest 目前只含 macOS 1.3.8，Windows／Linux 指南須連到仍提供對應檔案的 1.3.7 發布頁。macOS 下載檔名與 CDN 已更新為 1.3.8；既有圖片及來源登記保留實拍的 1.3.7，不改寫圖片中的版號。

Windows、macOS、Linux 的指南同時列出 GitHub Release 與**台灣 AWS CDN**下載路徑；選相同正式版本、架構及檔名，核對 SHA-256 後安裝。Linux 保留三個 .deb、面板原始碼與 SHA256SUMS 完整五檔的流程。下載頁截圖採未登入 GitHub 的視角。

FreeBSD 透過官方 ports／pkg 取得及更新；拍攝套件庫查詢、ports 建置與安裝結果。AWS CDN 下載與相關截圖僅適用 macOS、Windows、Linux。

## 4. Windows

主線先以 Windows 11 x64、已簽章的 1.3.7 安裝程式及記事本拍攝。Windows 10／x86 操作差異留在對應指南；沒有實際環境時，不用 Windows 11 截圖冒充。

2026-10-24 依維護者補充，Windows 指定句只保留「請假要去哪裡玩呢去海邊」，不追加「散步」。本機選字後游標留在選字處，須按 End 回組字末端；WIN-07b 改呈現選字後回到句尾的狀態，不宣稱自動移至句尾或已新增文字。工具只開啟安裝歡迎頁，未執行安裝；維護者另提供完成頁及工作列兩張原圖，已依實際勾選／反白狀態入文。

| ID | 優先 | 狀態 | 要拍的畫面與完成條件 | 建議圖說 |
| --- | --- | --- | --- | --- |
| WIN-01 | P0 | 已入文：Assets／AWS 兩張 | 正式 Release 的 x64 Setup EXE、x64／x86 ZIP 與校驗檔；AWS 三列。 | 選符合架構的檔案及同名校驗檔。 |
| WIN-02 | P0 | 已入文：歡迎頁與維護者提供完成頁 | 安裝精靈最後一頁，保留共用入口與升級後登出／登入提示。 | 按完成結束精靈；不從完成圖推定已登出或重新登入。 |
| WIN-03 | P0 | 已入文 | Windows「語言與地區」中繁體中文的「語言選項」入口。 | 在繁體中文語言的選單開啟「語言選項」。 |
| WIN-04 | P0 | 已入文：清單與既有加入狀態 | 「新增鍵盤」清單與已安裝鍵盤清單；本機已加入，新增項目為灰色，未移除後重加。 | 已安裝清單看得到琦琦就不必重加。 |
| WIN-05 | P0 | 已入文：維護者提供切換前／已選琦琦兩張 | 切換前下列微軟注音反白；WIN-05b 上列琦琦反白且左側有藍色選中指示，保留記事本背景。 | 選上列琦琦，整列反白與藍色指示確認選用，再放開按鍵回到文字區。 |
| WIN-06 | P0 | 已入文：組字／確認兩張 | 指定兩行的實際注音組字與 Enter 確認結果；未追加其他文字。 | 第二行仍有底線時可回頭選字，確認後底線消失。 |
| WIN-07 | P1 | 已入文：玩候選／選字後兩張 | 玩第 3 項反白，選玩後按 End 回句尾；依維護者要求不追加詞語。 | 候選順位依本機實際結果，選字後回句尾須按 End。 |
| WIN-08 | P1 | 已入文：維護者提供原圖 | 四種輸入法與目前勾選項完整；傳統注音有勾，倉頡為滑鼠停留。 | 勾號是目前模式，滑鼠灰底不是已切換。 |
| WIN-09 | P1 | 已入文：兩開關與竹大／喬候選 | 只輸入竹大，喬第 5 項反白；未打完五碼。 | 本機原有兩開關均開啟；候選圖拍於送出前，另選第 5 項核對輸出確為喬。 |
| WIN-10 | P2 | 已入文 | 「重新出發」取得逐字讀音，重選為 ㄔㄨㄥˊ；未新增詞。 | 逐字候選僅供參考，依語境確認破音字。 |
| WIN-11 | P2 | 已入文：Emoji／插入兩張 | Emoji 分類與記事本第三行插入 👍 的結果。 | 符號表保持開啟，可連續選取。 |
| WIN-12 | P2 | 已入文：三張 | 一般頁 Caps Lock、選字窗／快捷鍵及注音進階設定。 | 記錄本機既有設定，不冒充新安裝預設。 |
| WIN-13 | P2 | 已入文 | 更新頁的每週通知、beta、立即檢查與重新安裝入口；實際同版查詢結果。 | 本機 1.3.7 顯示目前已是最新版本；原有每週通知關閉，未切 beta 或安裝更新。 |

## 5. Android

本輪先以 Pixel 8 Pro 手機模擬器補拍 1.3.7 啟用、選用及觸控輸入主線，記錄 Android 15／API 35、英文系統介面與繁體中文琦琦介面。實機仍待獨立補齊；不同品牌的系統設定名稱在圖說說明差異。平板與橫向畫面另補，不能直接拉寬手機截圖。

| ID | 優先 | 狀態 | 要拍的畫面與完成條件 | 建議圖說 |
| --- | --- | --- | --- | --- |
| AND-01 | P0 | 待拍 | Google Play 官方商品頁，名稱、圖示與安裝／開啟入口可辨認。 | 在 Google Play 找到「琦琦輸入法」，下載安裝後開啟 App。 |
| AND-02 | P0 | 已入文：1.3.7 模擬器首頁 | 1.3.7 App 首頁，啟用輸入法、選擇輸入法及調整設定按鈕可見。 | 從 App 首頁依序啟用琦琦，再選擇它作為目前鍵盤。 |
| AND-03 | P0 | 已入文：模擬器啟用開關 | 系統鍵盤管理頁中琦琦的啟用開關。 | 在系統鍵盤清單中開啟琦琦輸入法。 |
| AND-04 | P0 | 已入文：模擬器已選中清單 | 目前鍵盤選擇清單，琦琦已被選中。 | 將目前的輸入法切換為琦琦，回到文字 App 開始輸入。 |
| AND-05 | P0 | 已入文：觸控組字與確認 | 一般文字 App 的完整螢幕鍵盤、組字列及宿主文字；另拍確認結果。 | 連續輸入注音即可組句，上方組字列保留可回頭選字的內容。 |
| AND-06 | P1 | 已入文：玩候選與續打兩張 | 第一行已確認、第二行保留組字；點玩開候選，另拍選玩後續打散步。 | 點玩開候選，本次玩為第 1 項；選字後續打散步仍接在句尾。 |
| AND-07 | P1 | 已入文：新版設定及四模式選單 | 「調整設定」中的輸入法選單及好打／傳統注音入口。 | 在輸入法設定中選擇好打注音、傳統注音、倉頡或簡易。 |
| AND-08 | P1 | 已入文：觸控設定與竹大／喬候選 | 虛擬鍵盤即時候選與未打完也能選字均勾選；只輸入竹大，喬為第 2 項，尚未確認。 | 倉頡開啟提前選字後，輸入竹大即可查看喬；順位以實際清單為準。 |
| AND-09 | P1 | 待拍 | 已連接實體鍵盤，設定雙排選字，並拍組字、候選及恢復數字列三種狀態。 | 關閉浮動候選窗並啟用雙排選字，上排組字、下排在數字與候選之間切換。 |
| AND-10 | P2 | 待拍 | 實體鍵盤浮動候選窗與宿主游標同時可見。 | 外接鍵盤可使用跟隨游標的浮動候選窗，依候選編號選字。 |
| AND-11 | P2 | 待拍 | 非浮動實體模式收合前、按 ▼ 後及恢復後的畫面。 | 不需面板時按 ▼ 收起；再次點選輸入欄位可恢復。 |
| AND-12 | P2 | 待重拍；a 手機橫向／b 平板均已占位 | 平板或橫向的一般文字輸入，記錄裝置與方向。 | 平板／橫向畫面仍可使用好打注音組字與候選選字。 |
| AND-13 | P2 | 待拍，已占位 | 展開關聯詞詞庫，拍到預設小麥注音及其他分類勾選。 | 選好字後的接續詞建議可依分類詞庫調整；先保留預設也能使用。 |

## 6. iOS／iPadOS

本輪依維護者指定，首頁使用其提供的 1.3.7 台灣價格 iPhone 實機截圖，其餘操作已以正式 `v1.3.7` 來源的 iPhone／iPad 模擬器自建版本補拍，依維護者要求保留 Xcode 原本 Debug 組態。App Store 版、模擬器自建版本與開發中功能分開記錄；不能只憑畫面上的版號判斷來源。iPad 模擬器已補自己的啟用與直橫向版面；iPhone／iPad 實機輸入仍各自驗證。實體鍵盤功能僅能以琦琦 App 前景編輯器呈現。

| ID | 優先 | 狀態 | 要拍的畫面與完成條件 | 建議圖說 |
| --- | --- | --- | --- | --- |
| IOS-01 | P0 | 已入文：維護者提供 iPhone 實機商品頁 | App Store 官方商品頁，名稱、圖示、打開入口及新功能版本 1.3.7 可辨認；已安裝狀態，不作重新下載安裝驗證。 | 從 App Store 安裝「琦琦輸入法」，安裝後先開啟一次 App。 |
| IOS-02 | P0 | 已入文（維護者提供實機圖） | 1.3.7 App 首頁、台灣一次付費支持 $90.00 及加入鍵盤引導。 | 首頁顯示台灣價格及鍵盤啟用步驟，未付費也能完整使用。 |
| IOS-03 | P0 | 已入文（iPhone 模擬器） | 系統「鍵盤 → 新增鍵盤」中的琦琦選項。 | 在系統設定新增琦琦輸入法鍵盤。 |
| IOS-04 | P0 | 已入文（iPhone 模擬器） | 已加入的鍵盤清單；正式 1.3.7 不要求完整取用，不要求拍攝不存在的權限開關。 | 清單出現琦琦即完成啟用；沒有「允許完整取用」開關是正常的。 |
| IOS-05 | P0 | 已入文（iPhone 模擬器） | 「記事本」測試 App 內長按地球鍵的清單，已選到琦琦。 | 在文字欄位長按地球鍵，選擇琦琦輸入法。 |
| IOS-06 | P0 | 已入文：組字與確認後 | 「記事本」測試 App 內的完整鍵盤與組字，見 IOS-07a；另有按一次 ↵ 確認後的狀態。 | 連續輸入注音即可組句，組字列中的文字可點選修改。 |
| IOS-07 | P1 | 已入文：候選與續打兩張 | 第一行「琦琦輸入法」已確認、第二行保留組字並在「玩」開候選；另拍選字後續打「散步」。 | 點要修改的字開候選，選字後繼續輸入，前面已確認的文字會保留。 |
| IOS-08 | P1 | 已入文：鍵盤及 App 兩張 | 鍵盤「設」及 App 設定的實際入口，分圖說明。 | 從鍵盤設定或 App 的輸入法設定選擇要使用的輸入方式。 |
| IOS-09 | P1 | 已入文：觸控設定及候選 | 觸控倉頡「即時候選」「未打完也能選字」均勾選，只輸入「竹大」，候選第 2 項可見「喬」。 | 倉頡可在字碼尚未輸入完成時，從候選中提前選字。 |
| IOS-10 | P1 | 已入文：iPad 模擬器 8 張原圖及 1 張局部圖；實機待驗 | 啟用開關、地球鍵清單、直／橫向玩候選、橫向續打與確認、觸控倉頡兩個選項及竹大／喬候選；原圖或連結均附實際方向。 | iPad 在提醒事項附註欄組句與選字，直橫向使用相同入口；只輸入竹大即可看到喬。 |
| IOS-11 | P2 | 部分入文：模擬器編輯器及 iPhone 複製確認；11d 實機／11e 貼上／11f 分享已占位 | 琦琦 App 前景編輯器接收模擬器 Generic Keyboard 按鍵；iPad 另拍橫向四欄與玩候選，複製確認仍為 iPhone。USB／藍牙、分享與跨 App 貼上待實機驗證。 | 外接鍵盤請使用琦琦 App 內的實體鍵盤編輯器，完成後複製或分享文字。 |
| IOS-12 | P2 | 部分入文：App 開關與觸控候選；12c 翻頁已占位 | App 內空白鍵選字關閉見 IOS-08b；暫時開啟並實測完整原句「請假要去哪裡玩呢去海邊」，完成句尾「邊」的一聲後再按空白開候選，兩張入文。完成後恢復關閉；多頁翻頁另驗。 | 可在 App 設定是否以空白鍵開候選與翻頁，設定與 App 內實體鍵盤編輯器共用。 |

## 7. macOS

本輪依維護者指定先從 macOS 開始，使用 Apple Silicon 實機、macOS 27.0.1（26A434）及已安裝的 1.3.7；已核對產品 plist 與偏好設定「關於」，agent 沒有重裝或登出；安裝歡迎頁、解壓後安裝檔及完成頁由維護者提供。宿主為「文字編輯」。系統設定及偏好設定由工具擷取單一目標視窗；兩張候選圖由維護者操作並提供。只裁切相關區域，不改動候選、字根或產品內容。

| ID | 優先 | 狀態 | 要拍的畫面與完成條件 | 建議圖說 |
| --- | --- | --- | --- | --- |
| MAC-01 | P0 | 已入文（兩張） | 未登入 GitHub 的正式 Release Assets，以及台灣 AWS CDN 下載表。 | 選 macOS Apple Silicon 的 .pkg.zip，或 AWS 下載表的 PKG ZIP；右側 .sha256 為校驗檔。 |
| MAC-02 | P0 | 已入文：02a 解壓 .pkg／02b 歡迎頁／02c 完成頁 | 解壓後的 .pkg、安裝程式歡迎畫面及安裝完成頁。 | 開啟 .pkg 後按「繼續」，依安裝程式提示完成安裝。 |
| MAC-03 | P0 | 已入文 | 系統設定「鍵盤 → 文字輸入」的「編輯」入口，參照既有實拍。 | 在「鍵盤」設定的「文字輸入」按「編輯」，管理輸入來源。 |
| MAC-04 | P0 | 已入文 | 輸入來源左下角 ＋、加入視窗中選到琦琦及「加入」按鈕；必要時分兩張。 | 按 ＋ 找到琦琦輸入法，再按「加入」。 |
| MAC-05 | P0 | 已入文：來源清單與選單列 | 加入後的來源清單；另拍選單列選用琦琦。 | 清單出現琦琦後，從選單列選用，並到文字編輯試打。 |
| MAC-06 | P0 | 已入文：組字／確認結果見兩張候選圖 | 文字編輯中的組字與候選；另拍確認後的文字。 | 好打注音可連續組句，完成後按 Enter 確認文字。 |
| MAC-07 | P1 | 已入文：開候選；依維護者要求不另拍續打 | 第一行「琦琦輸入法」已確認，第二行「請假要去哪裡玩呢去海邊」保留組字，在「玩」展開候選。 | 「玩」的候選展開，第 3 項反白；底線為仍可選字的組字範圍。 |
| MAC-08 | P1 | 已入文 | 輸入法選單的四種模式、英文輸入與偏好設定入口。 | 可從選單切換模式，或輕按 Shift 切換中英文；此快捷鍵可在一般設定關閉。 |
| MAC-09 | P1 | 已入文 | 倉頡兩個開關均已開啟；「竹大」候選第 1 頁可見第 2 項「喬」。 | 開啟「即時候選」與「未打完也能選字」，輸入「竹大」即可查看「喬」；順位以實際清單為準。 |
| MAC-10 | P2 | 已入文：一般設定、中文選單及 10b 英文提示 | 一般設定的 Shift 切換及啟動模式，搭配中／英切換的可見狀態；英文提示採維護者提供的原圖，不再重拍。 | 可設定單按 Shift 切換中英文，以及啟動時使用的模式。 |
| MAC-11 | P2 | 已入文：11a 列表／11b 插入結果 | 符號表的 Emoji 分類、可捲動清單及插入結果。 | 從符號表選擇 Emoji，點選後插入目前的文字欄位。 |
| MAC-12 | P2 | 已入文：更新頁及每週通知共用一張圖 | 同一頁顯示目前版本、每週通知、立刻檢查與 beta；依維護者要求合併原 12a／12b。圖中最新版為「－」，不宣稱查詢成功。 | 可手動檢查或開啟每週通知；檢查不預先下載安裝包。 |

## 8. Linux／Ubuntu

主線以 Ubuntu Desktop 24.04、GNOME Shell 46、Fcitx 5、amd64 為準。截圖及圖說記錄 X11 或 Wayland，不將一種 session 的畫面當作另一種的驗收。

2026-10-24 已在既有 VirtualBox「Ubunutu」完成本輪 18 個位置、20 張圖片。實際系統為 Ubuntu 24.04.5 LTS／GNOME Shell 46.0／Wayland／amd64，VirtualBox 的 Ubuntu 24.10 類型標籤不作 OS 證據。官方 1.3.7 套件從 AWS CDN 下載，四檔校驗 OK；由 1.3.3 升級，維護者手動完成 sudo 驗證與重啟後登入。指定句沿用維護者要求，不追加「散步」。

| ID | 優先 | 狀態 | 要拍的畫面與完成條件 | 建議圖說 |
| --- | --- | --- | --- | --- |
| LNX-01 | P0 | 已入文：Assets／AWS 兩張 | 未登入 GitHub 正式下載頁，Linux 三個 .deb、面板原始碼與 SHA256SUMS 可辨認。 | 五檔來自同一版正式發布；AWS 及 GitHub 同名檔案對應。 |
| LNX-02 | P0 | 已入文：校驗／升級兩張 | 四檔均 OK；apt 完成 1.3.3 → 1.3.7 升級，面板原先已安裝。 | 此圖為升級摘要；全新安裝仍使用指南的完整三檔指令。 |
| LNX-03 | P0 | 已入文 | `im-config` 的 fcitx5 實心圓鈕已選；未改成其他框架。 | 依圓鈕判斷已選 fcitx5，列背景只是焦點。 |
| LNX-04 | P0 | 已入文 | 重啟並登入後 `keykey-gnome-panel status` 顯示 `State: ACTIVE`。 | 本次 Wayland 工作階段的候選面板已啟用。 |
| LNX-05 | P0 | 已入文：搜尋／目前清單兩張 | 搜尋 KeyKey 顯示三個可加入項目，另有英文、注音、倉頡、簡易清單。 | 語言篩選先關閉；搜尋時該列隱藏，清空搜尋可再調整。 |
| LNX-06 | P0 | 已入文：目前名稱／清單／組字／確認四張 | GNOME 選用 Bopomofo，Text Editor 46.3 實際注音輸入指定兩行並確認。 | 黑色組字底線消失表示送出；紅色虛線為編輯器拼字檢查。 |
| LNX-07 | P1 | 已入文：候選／選字後兩張 | 玩第 1 項反白；選字後按 End 回句尾，沒有追加文字。 | 選字後保留組字，再按 Enter 確認整段。 |
| LNX-08 | P1 | 已入文 | 1.3.7 中文注音設定頁，標準、好打注音及直式候選可讀。 | 本機升級後保留的設定，不標為全新預設。 |
| LNX-09 | P1 | 已入文：設定／候選兩張 | 原有兩開關皆開；只打竹大，喬第 5 項反白，另選取並核對儲存檔。 | 本機部分罕字顯示方框，保留實際呈現。 |
| LNX-10 | P2 | 已入文：設定局部 | 三項未勾，選字目標為游標後方；裁自 LNX-08 同張原圖。 | 可調整空白鍵開候選、游標目標及 Esc 清除整句。 |
| LNX-11 | P2 | 已入文 | GNOME Terminal 3.52.0／GTK 3／Wayland，直接 Fcitx 路徑的組字與法候選。 | 另一個宿主的實際輸入，不代替其他 App 或 X11。 |

## 9. FreeBSD

以 [FreeBSD 安裝指南](../FREEBSD_INSTALL.md)已驗證的 FreeBSD 15.1-RELEASE-p3 amd64、Xfce／X11、LightDM、Fcitx 5、Mousepad／GTK 3 為起點。FreeBSD 與 Linux 共用 frontend，但需各自的桌面實拍。

| ID | 優先 | 狀態 | 要拍的畫面與完成條件 | 建議圖說 |
| --- | --- | --- | --- | --- |
| BSD-01 | P0 | 已入文 | pkg update 成功後查詢 FreeBSD 15／amd64 quarterly 為 1.3.0；本機既有安裝 1.3.7 分圖，查詢後已退出 root。 | 先查詢套件庫版本；若尚未提供所需版本，可改用 ports。 |
| BSD-02 | P0 | 已入文 | 來源 1.3.7、main 修訂 c69a4d85…、既有 `.pkg` 與已安裝 1.3.7，分圖；本輪未重建或重裝。 | 區分 ports 來源、建置產物與已安裝版號。 |
| BSD-03 | P0 | 已入文 | GTK 3 bridge、Noto Sans CJK TC、重新登入三個環境值與 Fcitx 行程、Xfce 自動啟動，分圖。 | 登入環境與實際 Mousepad 中文輸入均已核對。 |
| BSD-04 | P0 | 已入文 | 已拍搜尋 keykey 的三項可用輸入法與恢復後目前清單；未變更原有輸入法清單。 | 注音、倉頡與簡易均可用。 |
| BSD-05 | P0 | 已入文 | Xfce 面板右鍵選單，Bopomofo 圓點已選取，背景為實際 Mousepad。 | 從 Fcitx 選用琦琦注音。 |
| BSD-06 | P0 | 已入文 | 指定兩行組字與 Enter 確認分圖；保留先前 19 字回歸句圖的來源界線。 | 組字底線與送入宿主後的文字可辨認。 |
| BSD-07 | P1 | 已入文 | 玩第 1 項、選字後游標與確認後分圖；依使用者要求保留原句，不加字。 | 選玩後按 End 回句尾，再 Enter 確認。 |
| BSD-08 | P1 | 已入文 | 新拍標準鍵盤、好打注音與進階選項；未變更既有注音設定。 | 模式與設定名稱已核對。 |
| BSD-09 | P1 | 已入文 | 兩個提前選字開關與竹大／喬第 5 項分圖；選取、儲存及檔案文字已核對，拍後還原設定。 | 第 2～4 項罕字缺字框保留實況。 |
| BSD-10 | P2 | 已入文 | 新拍關於視窗，版本 1.3.7 可辨認。 | 核對已安裝產品的關於版本。 |
| BSD-11 | P2 | 已入文 | 2026-10-24 未登入 FreshPorts 套件頁，port 版本 1.3.7；只作來源資訊圖。 | FreshPorts 提供 port 來源與更新資訊，本機版本仍以 pkg info 為準。 |

不為本清單新增 ports／pkg 定期查詢或更新排程。拍攝時才核對當次結果，不將「已正式支援」寫成所有套件庫同時提供相同版本。

## 10. 素材與圖說規格

- **來源版本**：以正式 1.3.7 安裝包、商店版或對應 Release 來源為準。開發版、模擬器、VM 及實機如實記錄；不得用 1.3.8 畫面標為 1.3.7。若環境只能拍開發版，先記錄為候補素材，不替換正式版教學。
- **畫面內容**：使用乾淨測試文件及示範文字；只裁切、遮蔽無關個資或加操作箭頭，不改候選文字、按鈕、版號或輸入結果。保留辨認 App、系統設定層級與操作位置所需的背景。
- **可讀性**：桌面圖保留目標視窗與必要選單；手機圖保留文字欄位、組字列與完整鍵盤。圖片縮至文件實際顯示寬度時，目標按鈕及候選編號仍須可讀。
- **一圖一目的**：下載、啟用、選用、候選與設定分開拍；跨視窗或有前後狀態的步驟使用 `a／b／c` 圖。箭頭只標當步要按的位置。
- **手機差異**：iPhone 與 iPad、Android 手機與平板使用自己的版面。不要拍入尚未合併或尚未正式發布的裝置適配功能。
- **格式與位置**：確認可用的文件 PNG 放在 `docs/images/`；新檔採 `keykey-平台-v137-項目ID-主題-裝置.png`，例如 `keykey-windows-v137-win04-add-keyboard-win11.png`。既有 Windows 圖不在這次規劃中搬移；替換引用後再評估舊圖是否仍有用途。
- **原始素材**：未採用截圖與錄影保存在忽略的本機產物目錄，例如 `Installer/local-builds/screenshots/`；影片不提交 Git。文件只提交已確認的圖片與必要來源資訊。
- **圖說與替代文字**：圖說寫「在哪裡、做什麼、完成後看到什麼」；alt 描述畫面內容，不只寫「步驟一」。系統版本及實機／模擬器資訊登記於第 11 節。
- **短錄影**：句中選字與倉頡提前選字可各附一段操作錄影，供核對前後狀態；靜態教學仍保留前後圖。錄影不能代替圖說或平台驗證。

## 11. 拍攝登記與逐平台完成清單

拍到圖片後，以每張一列填入下表。多張狀態圖使用原 ID 加 `a／b／c`；如果舊圖通過複核，登記原始檔名與真實來源，無須為了新命名而重存。

| ID | 最終圖片路徑 | App 版本與 build／來源 | OS、桌面／session、宿主 App | 裝置／架構及實機／VM／模擬器 | 拍攝或複核日期 | 最終圖說與放置段落 |
| --- | --- | --- | --- | --- | --- | --- |
| WIN-01 | [圖片](images/keykey-windows-v137-win01-release-assets-win11.png) | 官方 Release v1.3.7／內建瀏覽器未登入擷取 | Windows 11 26H2（26300.9711）／正式發布頁 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 未登入的正式發布頁列出 Windows 安裝程式、ZIP 與校驗檔。／下載 |
| WIN-01b | [圖片](images/keykey-windows-v137-win01b-aws-cdn-win11.png) | 官方 Release v1.3.7／內建瀏覽器未登入擷取 | Windows 11 26H2（26300.9711）／正式發布頁 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | AWS 下載表的 Windows 三列與校驗連結。／AWS CDN |
| WIN-02a | [圖片](images/keykey-windows-v137-win02a-installer-welcome-win11.png) | 官方 AWS CDN 1.3.7 x64；SHA-256 a14b8849…061cc56b，Authenticode 有效 | Windows 11 26H2（26300.9711）／安裝精靈 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 已核對雜湊與簽章的正式安裝精靈歡迎頁；未按安裝。／安裝 |
| WIN-02b | [原圖](images/keykey-windows-v137-win02b-installer-finished-win11.png) | 維護者提供本輪安裝完成頁；畫面未單獨顯示版號 | Windows／安裝精靈 | 沿用本輪 Windows 實機；原圖 496 × 357，未後製 | 2026-10-24 收圖／複核 | 最後一頁有完成按鈕、共用入口及升級後登出再登入提示；不宣稱已登出。另張解壓明細進度圖留本機參考，未入文。／安裝 |
| WIN-03 | [圖片](images/keykey-windows-v137-win03-language-options-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／Windows 設定 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 繁體中文台灣的語言選項入口；裁去帳號側欄。／加入鍵盤 |
| WIN-04a | [圖片](images/keykey-windows-v137-win04a-add-keyboard-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／Windows 設定 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 新增清單中的琦琦因已加入而呈灰色；未移除後重加。／加入鍵盤 |
| WIN-04b | [圖片](images/keykey-windows-v137-win04b-installed-keyboard-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／Windows 設定 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 已安裝的鍵盤列出琦琦。／加入鍵盤 |
| WIN-05 | [原圖](images/keykey-windows-v137-win05-switcher-win11.png) | 維護者提供本輪切換清單；畫面未單獨顯示產品版號 | Windows／記事本與系統切換清單 | 沿用本輪 Windows 實機；原圖 641 × 243，未後製 | 2026-10-24 收圖／複核 | 上列琦琦可選，下列微軟注音反白，作為切換前狀態；選中結果另見 WIN-05b。／選用輸入法 |
| WIN-05b | [原圖](images/keykey-windows-v137-win05b-selected-win11.png) | 維護者提供本輪已選琦琦清單；畫面未單獨顯示產品版號 | Windows／記事本與鍵盤配置切換清單 | 沿用本輪 Windows 實機；原圖 663 × 275，未後製 | 2026-10-24 收圖／複核 | 上列琦琦整列反白，左側有藍色選中指示；下列為微軟注音，記事本背景保留指定兩行。／選用輸入法 |
| WIN-06a | [圖片](images/keykey-windows-v137-win06a-composition-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／記事本 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 第一行已確認，第二行指定 11 音節仍保留組字，未追加文字。／試打 |
| WIN-07a | [圖片](images/keykey-windows-v137-win07a-middle-candidate-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／記事本 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 玩第 3 項反白，第二行尚未確認；完整候選窗。／句中選字 |
| WIN-07b | [圖片](images/keykey-windows-v137-win07b-after-selection-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／記事本 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 選玩後按 End 回組字末尾，候選關閉；不追加其他詞語。／句中選字 |
| WIN-06b | [圖片](images/keykey-windows-v137-win06b-confirmed-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／記事本 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | Enter 後兩行保留，組字底線消失；另存文字已逐字核對。／確認 |
| WIN-08 | [原圖](images/keykey-windows-v137-win08-input-menu-win11.png) | 維護者提供本輪工作列選單；畫面未單獨顯示產品版號 | Windows／琦琦工作列選單 | 沿用本輪 Windows 實機；原圖 228 × 302，未後製 | 2026-10-24 收圖／複核 | 四模式均可見，傳統注音有勾，倉頡為滑鼠停留；符號表與設定入口完整。／切換模式 |
| WIN-09a | [圖片](images/keykey-windows-v137-win09a-cangjie-settings-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／琦琦設定 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 本機即時候選與未打完也能選字原本均開啟，未更動。／倉頡 |
| WIN-09b | [圖片](images/keykey-windows-v137-win09b-cangjie-candidates-win11.png) | 本機既有 1.3.7 x64；實際倉頡輸入 | Windows 11 26H2（26300.9711）／記事本 | x64 實機；只裁切，未改候選文字 | 2026-10-24 | 竹大仍有底線，喬第 5 項反白，未打全碼或送出；另選取並保存文字核對。／倉頡 |
| WIN-10 | [圖片](images/keykey-windows-v137-win10-phrase-readings-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／琦琦設定 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 重新出發的重已選 ㄔㄨㄥˊ；查詢後未新增詞，草稿已清空。／自訂詞 |
| WIN-11a | [圖片](images/keykey-windows-v137-win11a-emoji-panel-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／記事本／符號表 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | Emoji 分類與乾淨記事本文字欄位，符號表可捲動。／符號 |
| WIN-11b | [圖片](images/keykey-windows-v137-win11b-emoji-inserted-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／記事本／符號表 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 點選後 👍 已插入第三行；符號表保持開啟。／符號 |
| WIN-12a | [圖片](images/keykey-windows-v137-win12a-general-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／琦琦設定 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 啟動中文、中文忽略 Caps Lock、四模式顯示；保留原值。／一般設定 |
| WIN-12b | [圖片](images/keykey-windows-v137-win12b-smart-settings-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／琦琦設定 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 標準注音、10 音節、數字選字；空白、游標前方及 Esc 清句未勾選。／注音設定 |
| WIN-12c | [圖片](images/keykey-windows-v137-win12c-candidate-settings-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／琦琦設定 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 100% 垂直選字窗、紫色反白及符號表快捷鍵；保留原值。／一般設定 |
| WIN-13 | [圖片](images/keykey-windows-v137-win13-update-current-win11.png) | 本機既有 1.3.7 x64；InstallationState 與設定頁核對，TSF DLL 簽章有效 | Windows 11 26H2（26300.9711）／琦琦設定 | x64 實機；局部裁切，原圖留本機產物目錄 | 2026-10-24 | 同版查詢回報目前已是最新版本；保留每週通知關閉，beta 未開。／更新 |
| AND-02 | [原圖](images/keykey-android-v137-and02-home-pixel8pro-simulator.png) | v1.3.7 tag a11f1eab／Android Studio 既有 Debug 組態自建；1.3.7（1003007） | Android 15／API 35／琦琦 App | Pixel 8 Pro arm64 手機模擬器；直向 1344 × 2992 | 2026-10-24 | 首頁顯示 1.3.7 與啟用、選用及設定按鈕。／從 Google Play 安裝 |
| AND-03 | [原圖](images/keykey-android-v137-and03-enabled-pixel8pro-simulator.png) | v1.3.7 tag a11f1eab／Android Studio 既有 Debug 組態自建；1.3.7（1003007） | Android 15／API 35／系統 On-screen keyboard | Pixel 8 Pro arm64 手機模擬器；直向 1344 × 2992 | 2026-10-24 | 琦琦開關已開啟；英文系統設定。／啟用鍵盤 |
| AND-04 | [原圖](images/keykey-android-v137-and04-selected-pixel8pro-simulator.png) | v1.3.7 tag a11f1eab／Android Studio 既有 Debug 組態自建；1.3.7（1003007） | Android 15／API 35／系統 Choose input method | Pixel 8 Pro arm64 手機模擬器；直向 1344 × 2992 | 2026-10-24 | 繁體中文標準注音的琦琦已選中。／選用鍵盤 |
| AND-05a／AND-06a | [原圖](images/keykey-android-v137-and06a-middle-candidate-pixel8pro-simulator.png)／[局部圖](images/keykey-android-v137-and06a-middle-candidate-pixel8pro-simulator-detail.png) | v1.3.7 tag a11f1eab／Android Studio 既有 Debug 組態自建；1.3.7（1003007） | Android 15／API 35／聯絡人未儲存備註欄／觸控 | Pixel 8 Pro arm64 手機模擬器；直向 1344 × 2992 | 2026-10-24 | 指定兩行，第一行已確認、第二行保留九字組字；玩第 1 項反白，未先確認第二行。／第一次組句 |
| AND-06b | [原圖](images/keykey-android-v137-and06b-continue-at-end-pixel8pro-simulator.png)／[局部圖](images/keykey-android-v137-and06b-continue-at-end-pixel8pro-simulator-detail.png) | v1.3.7 tag a11f1eab／Android Studio 既有 Debug 組態自建；1.3.7（1003007） | Android 15／API 35／聯絡人未儲存備註欄／觸控 | Pixel 8 Pro arm64 手機模擬器；直向 1344 × 2992 | 2026-10-24 | 選玩後續打散步，文字接在句尾。／句中選字後續打 |
| AND-05b | [原圖](images/keykey-android-v137-and05-confirmed-pixel8pro-simulator.png)／[局部圖](images/keykey-android-v137-and05-confirmed-pixel8pro-simulator-detail.png) | v1.3.7 tag a11f1eab／Android Studio 既有 Debug 組態自建；1.3.7（1003007） | Android 15／API 35／聯絡人未儲存備註欄／觸控 | Pixel 8 Pro arm64 手機模擬器；直向 1344 × 2992 | 2026-10-24 | 一次換行後原文字保留，游標下一行，組字列清空。／確認換行 |
| AND-07a | [原圖](images/keykey-android-v137-and07a-settings-pixel8pro-simulator.png) | v1.3.7 tag a11f1eab／Android Studio 既有 Debug 組態自建；1.3.7（1003007） | Android 15／API 35／琦琦設定 | Pixel 8 Pro arm64 手機模擬器；直向 1344 × 2992 | 2026-10-24 | 設定頁的五個區塊與共用輸入法選單。／調整設定 |
| AND-07b | [原圖](images/keykey-android-v137-and07b-input-methods-pixel8pro-simulator.png) | v1.3.7 tag a11f1eab／Android Studio 既有 Debug 組態自建；1.3.7（1003007） | Android 15／API 35／琦琦設定 | Pixel 8 Pro arm64 手機模擬器；直向 1344 × 2992 | 2026-10-24 | 選單列出好打、傳統注音、倉頡與簡易。／切換輸入法 |
| AND-08a | [原圖](images/keykey-android-v137-and08a-cangjie-settings-pixel8pro-simulator.png)／[局部圖](images/keykey-android-v137-and08a-cangjie-settings-pixel8pro-simulator-detail.png) | v1.3.7 tag a11f1eab／Android Studio 既有 Debug 組態自建；1.3.7（1003007） | Android 15／API 35／琦琦設定／虛擬鍵盤 | Pixel 8 Pro arm64 手機模擬器；直向 1344 × 2992 | 2026-10-24 | 即時候選及未打完也能選字均已勾選；未更動這兩個開關。／倉頡 |
| AND-08b | [原圖](images/keykey-android-v137-and08b-cangjie-candidates-pixel8pro-simulator.png)／[局部圖](images/keykey-android-v137-and08b-cangjie-candidates-pixel8pro-simulator-detail.png) | v1.3.7 tag a11f1eab／Android Studio 既有 Debug 組態自建；1.3.7（1003007） | Android 15／API 35／聯絡人未儲存備註欄／觸控 | Pixel 8 Pro arm64 手機模擬器；直向 1344 × 2992 | 2026-10-24 | 竹大仍有組字底線，候選第 2 項喬可選，未打全碼或確認。／倉頡 |
| IOS-01 | [原圖](images/keykey-ios-v137-ios01-app-store-user-iphone.png) | 維護者提供的 iPhone App Store 商品頁；新功能顯示版本 1.3.7 | iOS／App Store；OS 版號未提供 | iPhone 實機，型號未提供；原圖 1290 × 2796 | 2026-10-25 | 琦琦輸入法名稱、圖示與打開按鈕可辨認；為已安裝裝置，不作重新下載安裝流程驗證。／從 App Store 安裝 |
| IOS-02 | [原圖](images/keykey-ios-v137-ios02-home-user-iphone.png) | 維護者提供的 iPhone 1.3.7 實機首頁；畫面顯示台灣價格 $90.00 | iOS／琦琦輸入法 App；OS 版號未提供 | iPhone 實機，型號未提供；原圖 1290 × 2796 | 2026-10-24 收圖／複核 | 台灣一次付費支持 $90.00，未付費也能完整使用；首頁提供輸入法設定與加入鍵盤步驟。／iOS 指南「從 App Store 安裝」 |
| IOS-03 | [原圖](images/keykey-ios-v137-ios03-add-keyboard-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／系統設定 | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 在新增鍵盤的「第三方鍵盤」選琦琦。／加入鍵盤 |
| IOS-04 | [原圖](images/keykey-ios-v137-ios04-keyboard-list-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／系統設定 | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 已加入琦琦輸入法／中文，沒有完整取用開關。／加入鍵盤 |
| IOS-05 | [原圖](images/keykey-ios-v137-ios05-keyboard-switcher-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／記事本測試 App | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 長按地球鍵，琦琦輸入法／中文已選用。／切換鍵盤 |
| IOS-06a／IOS-07a | [原圖](images/keykey-ios-v137-ios07a-middle-candidate-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／記事本測試 App／觸控鍵盤 | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 第一行已確認，第二行保留組字，在玩展開候選且玩為第 1 項；未先確認第二行。／第一次組句 |
| IOS-07b | [原圖](images/keykey-ios-v137-ios07b-continue-at-end-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／記事本測試 App／觸控鍵盤 | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 選玩後繼續輸入散步，文字接在句尾。／句中選字後續打 |
| IOS-06b | [原圖](images/keykey-ios-v137-ios06b-confirmed-text-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／記事本測試 App／觸控鍵盤 | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 按一次 ↵ 確認並換行，兩行文字保留、組字格清空。／確認結果 |
| IOS-08a | [原圖](images/keykey-ios-v137-ios08a-keyboard-settings-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／記事本測試 App／鍵盤設定 | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 設頁可切四種輸入法，空白鍵選字顯示關閉。／設定入口 |
| IOS-08b／IOS-12 關閉狀態 | [原圖](images/keykey-ios-v137-ios08b-app-settings-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／琦琦 App 設定 | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 四種模式、空白鍵選字關閉及虛擬／實體倉頡設定入口。／App 設定 |
| IOS-09a | [原圖](images/keykey-ios-v137-ios09a-cangjie-keyboard-options-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／記事本測試 App／鍵盤設定 | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 觸控倉頡即時候選、未打完也能選字均勾選。／倉頡 |
| IOS-09b | [原圖](images/keykey-ios-v137-ios09b-cangjie-candidates-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／記事本測試 App／觸控鍵盤 | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 竹大仍在組字，第 2 項喬可選，未完成全碼或送出。／倉頡 |
| IOS-11a | [原圖](images/keykey-ios-v137-ios11a-hardware-editor-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／琦琦 App 前景編輯器／Generic Keyboard | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 請假已固定，後段仍為紫色組字，左側為呢候選，保留複製與分享入口。／實體鍵盤 |
| IOS-11b | [原圖](images/keykey-ios-v137-ios11b-copy-confirmation-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／琦琦 App 前景編輯器／Generic Keyboard | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 按複製後文字確認、候選清空，顯示已複製提示；不作跨 App 貼上驗證。／實體鍵盤 |
| IOS-12a | [原圖](images/keykey-ios-v137-ios12a-space-select-on-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／琦琦 App 設定 | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 使用空白鍵選字暫時開啟；拍攝完成已恢復關閉。／空白鍵選字 |
| IOS-12b | [原圖](images/keykey-ios-v137-ios12b-space-candidates-iphone17pro-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）原本 Debug 組態自建；App／extension 1.3.7（build 1） | iOS 26.5／記事本測試 App／觸控鍵盤 | iPhone 17 Pro arm64 模擬器 | 2026-10-24 | 首行「琦琦輸入法」已確認並換行；次行保留完整原句「請假要去哪裡玩呢去海邊」，後段仍在組字。以空白完成「邊」的一聲，再按空白開候選，未點組字格。／空白鍵選字 |
| IOS-10a／IOS-04 補充 | [原圖](images/keykey-ios-v137-ios10a-enable-keyboard-ipadpro13m5-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）既有 Debug 組態；App／extension 1.3.7（build 1） | iPadOS 26.5／系統設定／直向 | iPad Pro 13 吋（M5）arm64 模擬器 | 2026-10-24 | 從 App 設定的鍵盤開關啟用琦琦，沒有完整取用開關。／iPad 啟用 |
| IOS-10b／IOS-07 補充 | [原圖](images/keykey-ios-v137-ios10b-middle-candidate-portrait-ipadpro13m5-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）既有 Debug 組態；App／extension 1.3.7（build 1） | iPadOS 26.5／提醒事項附註／直向觸控鍵盤 | iPad Pro 13 吋（M5）arm64 模擬器 | 2026-10-24 | 兩行指定文字，第二行未先確認，玩候選展開。／iPad 直向 |
| IOS-10c／IOS-07 補充 | [原圖](images/keykey-ios-v137-ios10c-middle-candidate-landscape-ipadpro13m5-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）既有 Debug 組態；App／extension 1.3.7（build 1） | iPadOS 26.5／提醒事項附註／橫向觸控鍵盤 | iPad Pro 13 吋（M5）arm64 模擬器 | 2026-10-24 | 橫向重新實際輸入兩行，玩候選展開；原圖連結入文。／iPad 橫向 |
| IOS-10d／IOS-07 續打 | [原圖](images/keykey-ios-v137-ios10d-continue-landscape-ipadpro13m5-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）既有 Debug 組態；App／extension 1.3.7（build 1） | iPadOS 26.5／提醒事項附註／橫向觸控鍵盤 | iPad Pro 13 吋（M5）arm64 模擬器 | 2026-10-24 | 選玩後續打散步，接在句尾且最後九格仍保留組字。／iPad 橫向 |
| IOS-10e／IOS-06 確認 | [原圖](images/keykey-ios-v137-ios10e-confirmed-landscape-ipadpro13m5-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）既有 Debug 組態；App／extension 1.3.7（build 1） | iPadOS 26.5／提醒事項附註／橫向觸控鍵盤 | iPad Pro 13 吋（M5）arm64 模擬器 | 2026-10-24 | 按一次 ↵ 確認換行，組字格清空；原圖連結入文。／iPad 確認 |
| IOS-10f／IOS-09 設定 | [原圖](images/keykey-ios-v137-ios10f-cangjie-options-landscape-ipadpro13m5-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）既有 Debug 組態；App／extension 1.3.7（build 1） | iPadOS 26.5／提醒事項附註／橫向鍵盤設定 | iPad Pro 13 吋（M5）arm64 模擬器 | 2026-10-24 | 虛擬倉頡即時候選、未打完也能選字均勾選；原圖連結入文。／iPad 倉頡 |
| IOS-10g／IOS-09 候選 | [原圖](images/keykey-ios-v137-ios10g-cangjie-candidates-landscape-ipadpro13m5-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）既有 Debug 組態；App／extension 1.3.7（build 1） | iPadOS 26.5／提醒事項附註／橫向觸控鍵盤 | iPad Pro 13 吋（M5）arm64 模擬器 | 2026-10-24 | 竹大保持組字，候選第 2 項喬可選，沒有完成全碼或送出。／iPad 倉頡 |
| IOS-10h／IOS-05 切換 | [原圖](images/keykey-ios-v137-ios10h-keyboard-switcher-landscape-ipadpro13m5-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）既有 Debug 組態；App／extension 1.3.7（build 1） | iPadOS 26.5／提醒事項附註／橫向觸控鍵盤 | iPad Pro 13 吋（M5）arm64 模擬器 | 2026-10-24 | 長按鍵盤左下角地球鍵，琦琦輸入法中文已選取；原圖連結入文。／iPad 切換 |
| IOS-11c | [原圖](images/keykey-ios-v137-ios11c-hardware-editor-landscape-ipadpro13m5-simulator.png) | v1.3.7 tag a11f1eab／Xcode 27.1（27A9275）既有 Debug 組態；App／extension 1.3.7（build 1） | iPadOS 26.5／琦琦 App 前景編輯器／橫向 Generic Keyboard | iPad Pro 13 吋（M5）arm64 模擬器 | 2026-10-24 | 四欄版面，第一行已確認、第二行保留紫色組字並在玩開候選。／實體鍵盤編輯器 |
| IOS-10a 局部圖 | [裁切圖](images/keykey-ios-v137-ios10a-enable-keyboard-detail-ipadpro13m5-simulator.png) | 由 IOS-10a 原圖裁切，不改 UI 內容 | 系統設定／直向 | 原圖 2064 × 2752，裁切範圍 (680, 55)–(2064, 465)，輸出 1384 × 410 | 2026-10-24 | 保留鍵盤標題、琦琦綠色開關及第三方鍵盤說明，完整原圖在圖說另附。／iPad 啟用 |
| MAC-01a | [原圖](images/keykey-macos-v137-mac01-release-assets-apple-silicon.png) | GitHub v1.3.7 Release／未登入畫面，維護者提供原圖 | macOS 27.0.1／ChatGPT 瀏覽器 | Apple Silicon arm64 實機 | 2026-10-24 | 正式發布頁 Assets，沒有下載次數；選 .pkg.zip，下一列 .sha256 為校驗檔。／下載 |
| MAC-01b | [原圖](images/keykey-macos-v137-mac01-aws-cdn-apple-silicon.png) | GitHub v1.3.7 Release／未登入畫面，維護者提供原圖 | macOS 27.0.1／ChatGPT 瀏覽器 | Apple Silicon arm64 實機 | 2026-10-24 | 台灣 AWS 下載點的 macOS PKG ZIP 與 .sha256；同版檔案與 GitHub Assets 相同。／下載 |
| MAC-02a | [原圖](images/keykey-macos-v137-mac02a-extracted-pkg.png) | 1.3.7 指南／維護者提供原圖；ZIP 檔名可見 1.3.7 | macOS／Finder 下載項目 | Mac 實機；OS 版號未另核對 | 2026-10-25 | 選取解壓後 chichi77KeyKey.pkg，下方保留原始 .pkg.zip；未修改畫面內容。／執行安裝程式 |
| MAC-02b | [原圖](images/keykey-macos-v137-mac02-installer-welcome-apple-silicon.png) | 1.3.7 指南／維護者提供安裝畫面；此頁未顯示版號 | macOS／安裝程式 | Apple Silicon 實機；同輪拍攝環境 | 2026-10-24 | 「chichi77 KeyKey」安裝歡迎頁，按「繼續」開始；只裁取安裝視窗。這不是安裝成功或版本驗收證明。／執行安裝程式 |
| MAC-02c | [原圖](images/keykey-macos-v137-mac02c-installer-finished.png) | 1.3.7 指南／維護者提供原圖；完成頁未顯示版號 | macOS／安裝程式摘要 | Mac 實機；OS 版號未另核對 | 2026-10-25 | 顯示已成功完成安裝及關閉按鈕；不作重新登入、輸入來源或實際輸入驗收。／執行安裝程式 |
| MAC-03 | [原圖](images/keykey-macos-v137-mac03-keyboard-apple-silicon.png) | 本機已安裝 1.3.7／系統設定實拍 | macOS 27.0.1／系統設定 | Apple Silicon arm64 實機 | 2026-10-24 | 「鍵盤 → 文字輸入」按「編輯…」；已裁去個人側欄。／加入輸入法 |
| MAC-04 | [原圖](images/keykey-macos-v137-mac04-add-input-source-apple-silicon.png) | 本機已安裝 1.3.7／系統設定實拍 | macOS 27.0.1／系統設定 | Apple Silicon arm64 實機 | 2026-10-24 | 繁體中文中選琦琦，按「加入」。／加入輸入法 |
| MAC-05a／MAC-04 入口 | [原圖](images/keykey-macos-v137-mac05-input-source-list-apple-silicon.png) | 本機已安裝 1.3.7／系統設定實拍 | macOS 27.0.1／系統設定 | Apple Silicon arm64 實機 | 2026-10-24 | 左下角 ＋ 為新增入口，左側可確認琦琦已加入。／加入輸入法 |
| MAC-07a／MAC-06a | [原圖](images/keykey-macos-v137-mac07-middle-candidate-apple-silicon.png) | 本機已安裝 1.3.7／維護者提供原圖 | macOS 27.0.1／文字編輯 | Apple Silicon arm64 實機 | 2026-10-24 | 第一行已確認，第二行保留組字，在「玩」開候選且第 3 項反白；第 1/4 頁。／試打 |
| MAC-05b／MAC-08／MAC-10 中文狀態 | [原圖](images/keykey-macos-v137-mac08-input-menu-apple-silicon.png) | 本機已安裝 1.3.7／維護者提供原圖 | macOS 27.0.1／輸入法選單 | Apple Silicon arm64 實機 | 2026-10-24 | 已選琦琦與好打注音，可選英文及其他模式；輕按 Shift 切換中英文，可在一般設定關閉。已裁去頂部無關系統狀態及右側邊緣。／切換輸入法與符號 |
| MAC-09a | [原圖](images/keykey-macos-v137-mac09-cangjie-settings-apple-silicon.png) | 本機已安裝 1.3.7／偏好設定實拍 | macOS 27.0.1／琦琦輸入法偏好設定 | Apple Silicon arm64 實機 | 2026-10-24 | 即時候選與未打完也能選字均開啟。／倉頡 |
| MAC-09b／MAC-06b | [原圖](images/keykey-macos-v137-mac09-cangjie-candidates-apple-silicon.png) | 本機已安裝 1.3.7／維護者提供原圖 | macOS 27.0.1／文字編輯 | Apple Silicon arm64 實機 | 2026-10-24 | 上方兩行已確認；竹大仍在組字，候選第 2 項為喬。／倉頡 |
| MAC-10a | [原圖](images/keykey-macos-v137-mac10-general-settings-apple-silicon.png) | 本機已安裝 1.3.7／偏好設定實拍 | macOS 27.0.1／琦琦輸入法偏好設定 | Apple Silicon arm64 實機 | 2026-10-24 | 本機 125%、垂直選字、Shift 關閉、啟動中文，並非全新安裝預設值。／偏好設定 |
| MAC-10b | [原圖](images/keykey-macos-v137-mac10b-english-mode.png) | 1.3.7 指南／維護者提供原圖；此圖未顯示版號 | macOS／文字編輯與英文模式提示 | Mac 實機；OS 版號未另核對 | 2026-10-25 | 文字欄位旁可見「英文輸入」提示；維護者確認採用此圖，不再重拍。／Shift 切換 |
| MAC-11a | [原圖](images/keykey-macos-v137-mac11a-emoji-panel.png) | 1.3.7 指南／維護者提供原圖；此頁未顯示版號 | macOS／符號表 | Mac 實機；OS 版號未另核對 | 2026-10-25 | Emoji 分類與可捲動列表。／符號 |
| MAC-11b | [原圖](images/keykey-macos-v137-mac11b-emoji-inserted.png) | 1.3.7 指南／維護者提供原圖；此頁未顯示版號 | macOS／文字編輯與符號表 | Mac 實機；OS 版號未另核對 | 2026-10-25 | 文字欄位已插入兩個 Emoji，符號表仍開啟。／符號 |
| MAC-12（原 12a／12b 合併） | [原圖](images/keykey-macos-v137-mac12-update-settings.png) | 維護者提供原圖；更新頁顯示目前版本 1.3.7 | macOS／琦琦偏好設定／更新 | Mac 實機；OS 版號未另核對 | 2026-10-25 | 每週通知已勾選、beta 未勾選；可見立刻檢查與上次檢查時間。最新版為「－」，不作查詢成功或升級驗收。／更新 |
| 版本核對（補充） | [原圖](images/keykey-macos-v137-about-apple-silicon.png) | 本機已安裝 1.3.7／偏好設定實拍 | macOS 27.0.1／琦琦輸入法偏好設定 | Apple Silicon arm64 實機 | 2026-10-24 | 關於頁顯示已安裝版本 1.3.7。／進階檢查 |

### Linux 本輪圖片登記（2026-10-24）

桌面圖共用環境：VirtualBox「Ubunutu」、Ubuntu 24.04.5 LTS、GNOME Shell 46.0、Wayland、amd64；官方 AWS CDN 的 `1.3.7-1+ubuntu24.04` 兩個產品套件，GNOME 面板 `83+keykey1-1+ubuntu24.04`。套件版號及關於頁均已核對。原始 1920 × 1080 客體 PNG 留在本機產物目錄，入文圖只裁切；下載頁另由 Windows 內建瀏覽器未登入擷取。LNX-10 是同張設定原圖的局部，沒有改寫產品文字或候選。

| ID | 最終圖片路徑 | 來源／宿主 | 最終圖說與放置段落 |
| --- | --- | --- | --- |
| LNX-01a | [圖片](images/keykey-linux-v137-lnx01a-release-assets.png) | GitHub v1.3.7 Release／內建瀏覽器未登入 | Linux 三個 deb、面板原始碼及 SHA256SUMS；其他平台檔案略過。／下載 |
| LNX-01b | [圖片](images/keykey-linux-v137-lnx01b-aws-cdn.png) | GitHub v1.3.7 Release／內建瀏覽器未登入 | AWS 四個 Linux 項目共用 SHA256SUMS，合計五檔。／下載 |
| LNX-02a | [圖片](images/keykey-linux-v137-lnx02a-checksums-ubuntu2404-wayland.png) | 官方五檔／GNOME Terminal | 命令及四檔 OK 均可讀。／校驗 |
| LNX-02b | [圖片](images/keykey-linux-v137-lnx02b-upgraded-ubuntu2404-wayland.png) | 官方 1.3.7／apt | 1.3.3 升級至 1.3.7；GNOME 面板原先已安裝，末尾 N 提示保留。／安裝 |
| LNX-03 | [圖片](images/keykey-linux-v137-lnx03-im-config-ubuntu2404-wayland.png) | im-config 0.57-2 | fcitx5 實心圓鈕已選，未改變既有框架。／啟用 |
| LNX-04 | [圖片](images/keykey-linux-v137-lnx04-panel-active-ubuntu2404-wayland.png) | 重啟並登入後／GNOME Terminal | GNOME 面板已啟用且 State 為 ACTIVE。／啟用 |
| LNX-05a | [圖片](images/keykey-linux-v137-lnx05a-search-ubuntu2404-wayland.png) | Fcitx 5 Configuration | 搜尋 KeyKey 後三個可加入項目；搜尋時語言篩選列隱藏。／加入琦琦 |
| LNX-05b | [圖片](images/keykey-linux-v137-lnx05b-current-list-ubuntu2404-wayland.png) | Fcitx 5 Configuration | 英文、注音、倉頡、簡易的目前清單；原順序已保留。／加入琦琦 |
| LNX-08 | [圖片](images/keykey-linux-v137-lnx08-bopomofo-settings-ubuntu2404-wayland.png) | 1.3.7／Bopomofo 設定 | 中文頁的標準鍵盤、好打注音與直式候選。／設定 |
| LNX-06a（目前名稱） | [圖片](images/keykey-linux-v137-lnx06a-selected-ubuntu2404-wayland.png) | GNOME Fcitx 面板 | 目前名稱為 Bopomofo。／選用 |
| LNX-06a（切換清單） | [圖片](images/keykey-linux-v137-lnx06a-input-list-ubuntu2404-wayland.png) | GNOME Fcitx 面板 | 英文及琦琦三種項目；英文反白是滑鼠停留。／選用 |
| LNX-06b | [圖片](images/keykey-linux-v137-lnx06b-composition-ubuntu2404-wayland.png) | Text Editor 46.3／GTK 4.14.5／keykey-fcitx-app | 第一行已確認，第二行請假已固定，其餘仍有組字底線。／試打 |
| LNX-07a | [圖片](images/keykey-linux-v137-lnx07a-middle-candidate-ubuntu2404-wayland.png) | Text Editor 46.3／直接 Fcitx 路徑 | 玩第 1 項反白，第二行未先確認。／句中選字 |
| LNX-07b | [圖片](images/keykey-linux-v137-lnx07b-after-selection-ubuntu2404-wayland.png) | Text Editor 46.3／直接 Fcitx 路徑 | 選玩後按 End 回句尾，仍保留組字，不追加文字。／句中選字 |
| LNX-06c | [圖片](images/keykey-linux-v137-lnx06c-confirmed-ubuntu2404-wayland.png) | Text Editor 46.3／直接 Fcitx 路徑 | Enter 後兩行保留、黑色組字底線消失；儲存檔已核對。／確認 |
| LNX-09a | [圖片](images/keykey-linux-v137-lnx09a-cangjie-settings-ubuntu2404-wayland.png) | 1.3.7／倉頡設定 | 兩個開關原本皆開啟，錯碼清除關閉，未更改。／倉頡 |
| LNX-09b | [圖片](images/keykey-linux-v137-lnx09b-cangjie-candidates-ubuntu2404-wayland.png) | Text Editor 46.3／實際 H、K | 竹大仍在組字，喬第 5 項反白；第 2～4 項罕字為本機實際方框。／倉頡 |
| LNX-10 | [局部圖](images/keykey-linux-v137-lnx10-smart-options-ubuntu2404-wayland.png) | 裁自 LNX-08 原圖 | 三項未勾選，選字目標在游標後方。／日常設定 |
| LNX-11 | [圖片](images/keykey-linux-v137-lnx11-terminal-candidate-ubuntu2404-wayland.png) | GNOME Terminal 3.52.0／VTE 0.76.0／GTK 3／GTK_IM_MODULE=fcitx | 琦琦輸入法保留組字，法第 1 項反白；前方 # 為 shell 註解。／另一宿主 |
| 版本核對（補充） | [圖片](images/keykey-linux-v137-about-ubuntu2404-wayland.png) | 本機 1.3.7／關於頁 | 關於琦琦輸入法顯示 1.3.7。／圖片與適用範圍 |

### FreeBSD 本輪圖片登記（2026-10-24）

VirtualBox「freebsd15」、FreeBSD 15.1-RELEASE-p3 amd64、Xfce／X11（xfce4-session 4.20.4）、LightDM、Mousepad 0.7.0／GTK 3、既有安裝 1.3.7。客體原圖為 1024 × 768，入文圖僅裁切；FreshPorts 另由未登入的內建瀏覽器擷取。

| ID | 最終圖片 | 來源與圖說 |
| --- | --- | --- |
| BSD-01a | [圖片](images/keykey-freebsd-v137-bsd01a-pkg-search.png) | 全部目錄刷新成功，查詢 FreeBSD 15／amd64 quarterly 為 1.3.0；來源 URL 同圖可辨。 |
| BSD-01b | [圖片](images/keykey-freebsd-v137-bsd01b-installed.png) | 本機 pkg info 顯示既有安裝 1.3.7，未冒充本輪 pkg install。 |
| BSD-02a | [圖片](images/keykey-freebsd-v137-bsd02a-ports.png) | make 查詢 1.3.7／套件名稱，本機 main 修訂 c69a4d85da0e2cfe08250d120d6aacaffac6b5182。 |
| BSD-02b | [圖片](images/keykey-freebsd-v137-bsd02b-package-installed.png) | 既有 ports `.pkg` 與本機安裝版號，未重新建置或安裝。 |
| BSD-03a | [圖片](images/keykey-freebsd-v137-bsd03a-gtk.png) | common 5.1.5、GTK 3 5.1.7_1、GTK 4 5.1.5。 |
| BSD-03b | [圖片](images/keykey-freebsd-v137-bsd03b-fonts.png) | fc-list 包含 Noto Sans CJK TC；指定中文在後續 Mousepad 圖可讀。 |
| BSD-03c（登入） | [圖片](images/keykey-freebsd-v137-bsd03c-login.png) | 三個輸入環境值、X11 與 Fcitx 行程；使用者已手動登入。 |
| BSD-03c（自動啟動） | [圖片](images/keykey-freebsd-v137-bsd03c-autostart.png) | Xfce 的 Fcitx 5 已勾選 on login，未新增重複項目。 |
| BSD-04a | [圖片](images/keykey-freebsd-v137-bsd04a-search.png) | 取消語言篩選並搜尋 keykey，三項可加入；搜尋時篩選列收起。 |
| BSD-04（目前清單） | [圖片](images/keykey-freebsd-v137-bsd04-current-list.png) | 原有英文、注音、倉頡、簡易清單已恢復，未套用拍攝中的暫時移除。 |
| BSD-05 | [圖片](images/keykey-freebsd-v137-bsd05-selected.png) | Xfce 面板右鍵選單，Bopomofo 圓點已選取。 |
| BSD-06b | [圖片](images/keykey-freebsd-v137-bsd06b-composition.png) | 第一行已確認，第二行仍有組字底線。 |
| BSD-07a | [圖片](images/keykey-freebsd-v137-bsd07a-middle-candidate.png) | 玩第 1 項，候選前組字仍保留。 |
| BSD-07b | [圖片](images/keykey-freebsd-v137-bsd07b-after-selection.png) | 選玩後游標留在玩後方，未追加文字。 |
| BSD-06c | [圖片](images/keykey-freebsd-v137-bsd06c-confirmed.png) | End 回句尾、Enter 確認後兩行文字保留，底線消失。 |
| BSD-08 | [圖片](images/keykey-freebsd-v137-bsd08-settings.png) | 標準鍵盤、好打注音及三項進階選項，保留原設定。 |
| BSD-09a | [圖片](images/keykey-freebsd-v137-bsd09a-cangjie-settings.png) | 即時候選與前綴選字開啟、錯碼清除關閉；拍後恢復原值。 |
| BSD-09b | [圖片](images/keykey-freebsd-v137-bsd09b-cangjie-candidates.png) | 實際 H、K 的竹大，喬第 5 項反白；罕字缺字框保留。 |
| BSD-10 | [圖片](images/keykey-freebsd-v137-bsd10-about.png) | 關於頁顯示版本 1.3.7。 |
| BSD-11 | [圖片](images/keykey-freebsd-v137-bsd11-freshports.png) | FreshPorts 的 port 來源資訊 1.3.7，不能代替本機或 pkg 套件庫。 |

每完成一個平台，依序勾選：

- [ ] 該平台 P0 的「取得 → 安裝／啟用 → 選用 → 成功輸入」已連成完整路徑。
- [ ] P1 的句中選字包含前後狀態，倉頡示範包含設定入口及真實候選。
- [ ] 圖片、圖說、alt、來源資訊與目標安裝指南一致；舊版截圖未被冒充為新版本。
- [ ] 第 4～9 節的對應狀態已更新，登記表已有檔案與實際環境，完成的優先級已勾選。
- [ ] README 的該平台代表圖已挑選，完整步驟仍留在平台安裝指南。
- [ ] 若產出媒體／商店圖，已使用確認過的原圖並更新 [StoreAssets 來源紀錄](../StoreAssets/README.md)，區分教學圖與宣傳排版。
- [ ] 已檢查圖片引用、Markdown 連結、縮圖可讀性與 `git diff --check`，由維護者 review PR 後合併。

每平台完成時，在登記表後保留一份具平台名稱與完成日期的勾選紀錄，並同步更新第 1 節總表；保留已完成平台的紀錄，不共用同一份勾選結果。單張截圖可供教學與媒體介紹，不足以宣稱整個平台或未拍攝環境已通過功能驗收。

### Windows 本輪紀錄（2026-10-24）

- [x] 23 張已入文，涵蓋未登入下載頁、安裝歡迎／完成頁、系統鍵盤、Windows 切換前／已選琦琦兩種狀態、四模式選單、好打注音指定兩行／玩候選／選字後／確認、倉頡設定與竹大／喬候選、自訂詞、Emoji、一般／注音設定及更新。
- [x] 官方安裝包 SHA-256 為 a14b88494ea07d6c9e343b66dedd1db24ec6472323e29b3af9a69bd7061cc56b，與同名校驗檔及發布頁一致；Authenticode 有效。build-info 指向正式 tag v1.3.7 的 a11f1eab381dda3b29d59f0ec8c201599fdadeaf。
- [x] 原有安裝由 InstallationState、設定頁 1.3.7 與有效 TSF DLL 簽章核對；工具僅開啟官方安裝包歡迎頁，未執行安裝。維護者另提供完成頁；圖片不代替新安裝產物版號、登出或重新登入的核對。
- [x] 實際注音輸入並修正同音字；保存的文字核對為兩行「琦琦輸入法／請假要去哪裡玩呢去海邊」。不追加「散步」，錯字與先前補充文字畫面未採用。
- [x] 玩第 3 項反白；選字後須按 End 回句尾。WIN-07b 是選字後回句尾的狀態，不宣稱自動接尾。Enter 確認後底線消失。
- [x] 自訂詞僅查讀音、未新增；本次草稿已清空。原有倉頡兩開關、選字窗、每週通知關閉與 beta 關閉均保留，未重設使用者學習資料。
- [x] Emoji 分類與插入 👍 已實測。更新查詢實際回報「目前已是最新版本」；未下載或安裝更新。macOS 更新畫面另由維護者提供，不以 Windows 圖作該平台驗收。
- [x] 倉頡只打竹大，喬第 5 項反白；候選圖未先送出。拍攝後選取第 5 項，保存文字核對確為喬。
- [x] 維護者補三張原圖：完成頁、系統切換清單與四模式選單。清單反白微軟注音、模式勾選傳統注音，圖說未誤寫為琦琦／倉頡已選中。
- [x] P1 的玩候選前後狀態、四模式入口與倉頡設定／竹大喬候選均已入文；Windows 本輪依維護者要求不追加詞語。
- [x] WIN-05b 已補上列琦琦反白與藍色選中指示的原圖，P0「取得 → 安裝／啟用 → 選用 → 成功輸入」的指南圖片已連成完整路徑。
- [x] 本輪 Windows 指南補圖位置已補齊，P0／P1／P2 圖片及來源登記完成。Windows 10／x86、新安裝後登入與版本核對仍不以本輪圖片代替。

### macOS 本輪紀錄（2026-10-25）

- [x] 18 張圖片已入文：下載頁／AWS CDN 兩張、安裝三張、系統設定三張、候選兩張、輸入法選單一張、一般／倉頡設定兩張、英文提示一張、Emoji 兩張、更新一張及版號一張。
- [x] 維護者指定的好打注音兩行文字、「玩」下拉候選及倉頡「竹大 → 喬」均採用真實原圖。
- [x] 圖片只包含目標設定／文字編輯／候選視窗；系統設定裁去個人帳號側欄，未拍入無關視窗。
- [x] 安裝指南已替換舊版候選及設定圖片，並更正 1.3.7 的發布狀態。
- [x] P0 圖片已入文：MAC-02 解壓後 .pkg、歡迎頁及完成頁均由維護者提供。MAC-05 來源清單與選單列已入文；agent 未執行安裝或登出，不將圖片補齊當成完整發布驗收。
- [x] P1 圖片已入文：MAC-07 玩候選、MAC-08 輸入法選單與倉頡兩張已完成。依維護者要求移除選字後續打說明與 MAC-07b 補拍項目。
- [x] P2 圖片：MAC-10b 英文輸入提示、MAC-11 Emoji 分類與插入結果、MAC-12 更新頁與每週通知均已入文。英文提示依維護者確認採用，不再重拍。更新查詢與實際升級不由設定圖代替驗收。
- [ ] 全平台完成與 README／商店素材另行評估；本輪依要求不在 README 加入本規劃，也未更換商店圖片。

工具限制：本輪原生操作無法用模擬按鍵產生注音組字，也無法擷取輸入法獨立候選窗；候選示範改由維護者操作並提供圖片。單一 App 截圖不包含選單列；MAC-05b／08 已由維護者提供選單原圖補齊，本輪 macOS 指南所需圖片已補齊。

### iPhone 本輪紀錄（2026-10-25）

- [x] 共 16 張圖片已入文：App Store 實機商品頁 1 張、台灣價格實機首頁 1 張，系統新增／清單 2 張，地球鍵 1 張，好打注音候選／續打／確認 3 張，兩處設定 2 張，倉頡 2 張，App 實體編輯器／複製確認 2 張，空白鍵設定／候選 2 張。
- [x] 首頁採維護者提供的 1.3.7 台灣價格原圖，原始 1290 × 2796，保留 $90.00；未使用模擬器的美元價格首頁。
- [x] 操作圖來源為正式 tag `v1.3.7`（`a11f1eab381dda3b29d59f0ec8c201599fdadeaf`），使用獨立來源副本，未改產品原始碼。依維護者要求沿用 Xcode 原本 Debug 組態，不將自建模擬器版本稱為 App Store 安裝或 Release 組態建置。
- [x] 安裝後核對 App／extension 均為 1.3.7（build 1），Xcode build 為 27A9275；extension 的 `RequestsOpenAccess=false`。內附 `KeyKey.db` SHA-256 為 `8fc3aead36cefd16a77c0a0d4319f7a305fb712b752db09396c8ac2bd4ebbfdb`，與正式共用 DB 相同；以上核對與實際觸控操作分開記錄。
- [x] 好打注音指定兩行、玩候選、選字後續打散步及確認換行均已操作；宿主為模擬器的「記事本」測試 App，使用實際注音鍵輸入，未貼上文字模擬組字。
- [x] 倉頡兩個觸控選項均開啟，只打竹大即拍到第 2 項喬；沒有先完成全碼或確認送出。
- [x] App 設定暫時開啟空白鍵選字，實測空白開候選後恢復關閉。鍵盤模式恢復好打注音，記事本原有示範內容已還原；未重設學習資料或詞庫。
- [x] App 前景編輯器使用模擬器 Generic Keyboard 的實際按鍵組句、開候選及按複製；已拍複製確認。未完成跨 App 貼上，未宣稱分享或 USB／藍牙實機驗證。
- [x] 透過 Device Hub 的 Screenshot 按鈕保存 1206 × 2622 iPhone 原圖；不包含外側控制列、截圖通知、游標提示或其他 macOS 視窗。先前來源不符的鍵盤圖未採用，舊版圖片引用已替換。
- [x] IOS-01 App Store 商品頁已入文，可見「打開」及 1.3.7 新功能；沒有重新下載安裝，該流程不以已安裝畫面代替驗證。
- [ ] iPhone／iPad 實機輸入、實際 USB／藍牙連線、跨 App 貼上與分享，以及 IOS-12 多頁翻頁仍待補；iPad 模擬器補拍見下方紀錄。
- [ ] 全平台 P0／P1／P2 完成仍維持未勾選；iPhone 本輪完成模擬器可取得的畫面、App Store 實機商品頁與台灣實機首頁；iPad 另見下方紀錄。README 與商店素材未修改。

### iPad 本輪紀錄（2026-10-24）

- [x] 已引用 9 張 iPad 原圖：系統啟用 1 張，直向玩候選 1 張，橫向玩候選／續打／確認 3 張，倉頡設定／候選 2 張，地球鍵清單 1 張，App 橫向編輯器 1 張。啟用頁另提供 1 張局部裁切圖；其餘原圖保持完整裝置畫面，部分以圖說連結呈現以減少重複。
- [x] 使用 Xcode 已開啟的正式 v1.3.7 來源與原先選好的 iPad Pro 13 吋（M5）目的地直接執行；沒有更改 Scheme、建置組態、Debugger 或目的地。執行前後 LaunchAction 與原 tag 一致，主工作區 Xcode 專案沒有 diff。
- [x] iPadOS 26.5、arm64 模擬器，App／extension 均為 1.3.7（build 1）、Xcode build 27A9275；`RequestsOpenAccess=false`。已安裝 DB 的 SHA-256 為 `8fc3aead36cefd16a77c0a0d4319f7a305fb712b752db09396c8ac2bd4ebbfdb`，與正式共用 DB 相同。
- [x] 系統設定從「App → 琦琦輸入法 → 鍵盤」啟用；正常觸控輸入宿主為系統「提醒事項」的附註欄，已收起側欄，只使用新建測試項目。
- [x] 直向與橫向指定兩行、玩候選、橫向選字後續打散步及一次 ↵ 確認換行均已實際操作。句中候選沒有先確認第二行；未貼上文字模擬組字。
- [x] 倉頡觸控的即時候選與未打完也能選字均勾選，只打竹大即出現第 2 項喬，保持未送出的字根；沒有先完成全碼。
- [x] App 橫向前景編輯器另以 Generic Keyboard 實際按鍵輸入同樣兩行，在玩開候選，保留四欄版面；不將此圖當作 USB／藍牙實機證明。
- [x] 原圖由 Device Hub Screenshot 保存：直向 2064 × 2752、橫向 2752 × 2064；沒有其他 macOS 視窗、外側工具列、游標提示或截圖通知。拍攝後恢復直向、好打注音，移除本次新建提醒事項並清空本次 App 編輯器內容，沒有重設學習資料。
- [ ] 商店安裝、iPhone／iPad 實機觸控、USB／藍牙連線、跨 App 貼上、分享及多頁翻頁仍待獨立驗證。本輪完成 iPad 模擬器的正常直橫向版面與指定情境，未將全部 iOS 優先級標為完成。

### Android 手機本輪紀錄（2026-10-24）

- [x] 已引用 10 張裝置原圖：1.3.7 首頁、系統啟用、目前鍵盤清單、新版設定、四模式選單、玩候選、續打散步、一次換行、倉頡觸控設定與竹大／喬候選；另有 5 張局部圖。舊名稱與舊設定圖片引用已替換，README 未變更。
- [x] 使用正式 tag `v1.3.7`（`a11f1eab381dda3b29d59f0ec8c201599fdadeaf`）獨立來源副本，透過 Android Studio 既有 Debug 組態建置安裝；未改產品原始碼或 Xcode 設定，不將自建模擬器 APK 稱為 Google Play 安裝。
- [x] 首頁及 APK metadata 均核對 1.3.7、versionCode 1003007；APK 內 `assets/KeyKey.db` SHA-256 為 `8fc3aead36cefd16a77c0a0d4319f7a305fb712b752db09396c8ac2bd4ebbfdb`，與正式共用 DB 相同。版本／詞庫核對與實際觸控行為分開記錄。
- [x] Pixel 8 Pro、Android 15（API 35）、arm64 模擬器；系統設定為英文，琦琦為繁體中文。宿主為系統聯絡人的未儲存 Notes 多行欄，未登入帳號、未儲存聯絡人。
- [x] 指定兩行透過實際螢幕注音鍵輸入，第一行確認換行，第二行未先確認；點組字列玩，候選第 1 項玩反白。另拍選玩後續打散步接在句尾及一次換行清空組字列，沒有貼上文字模擬組字。
- [x] 倉頡虛擬鍵盤的即時候選與未打完也能選字原已勾選；只打竹大即拍到第 2 項喬，沒有先完成全碼或選字送出。實體鍵盤選項未變更。
- [x] 透過 Running Devices 的 Take Screenshot／Save 保存 1344 × 2992 原圖，只含 Android 裝置畫面。局部圖裁切範圍：玩候選／續打 `(0,1600)–(1344,2992)`；確認／倉頡候選 `(0,1540)–(1344,2992)`；倉頡設定 `(60,1740)–(1280,2860)`。原圖保留，局部圖未修改內容。
- [x] 拍攝時以 macOS 文字編輯暫將該 AVD 的 `hw.keyboard` 從 yes 改為 no，重啟後實測觸控鍵盤；結束後停止模擬器並恢復 yes。好打注音已恢復，本次聯絡人草稿已捨棄，沒有重設學習或自訂詞。
- [ ] AND-01 Google Play 商品頁與商店安裝、Android 實機觸控、AND-09 雙排、AND-10 浮動窗、AND-11 面板收合及 AND-12 平板／橫向仍待補；不能以本輪手機觸控模擬器畫面代表上述驗證。平台 P0／P1／P2 不全項勾選。

### Linux 本輪紀錄（2026-10-24）

- [x] 18 個補圖位置已補齊，共 20 張入文；P0／P1／P2 圖片、alt、圖說與來源已登記。
- [x] 實際 `/etc/os-release` 為 Ubuntu 24.04.5 LTS，`XDG_SESSION_TYPE=wayland`、GNOME Shell 46.0、amd64；未使用 VirtualBox 的 24.10 類型標籤判定系統版本。
- [x] 從正式 AWS CDN 下載五檔，四個檔案均通過 SHA256SUMS；套件由 1.3.3 升級至 1.3.7，面板原先已安裝。維護者自行輸入 sudo 密碼及重啟後登入；未取得密碼。
- [x] 重新登入後面板 ACTIVE，已安裝版號與關於頁為 1.3.7。Fcitx 清單完成搜尋、加入及儲存，保留原本英文、注音、倉頡、簡易順序；沒有重設學習或自訂詞。
- [x] 指定兩行均以實際注音鍵輸入；先選對「琦」與「假」，再完成整句。玩第 1 項，選字後游標留在玩後方，按 End 回句尾；不追加散步。Enter 確認及黑色底線消失均已實拍。
- [x] 倉頡兩開關原本開啟，只輸入 H、K，喬第 5 項反白；拍攝後選字保存。儲存檔位元組與「琦琦輸入法／請假要去哪裡玩呢去海邊／喬」逐行核對相符，末尾換行保留。
- [x] 主線為 Text Editor 46.3／GTK 4.14.5／直接 Fcitx 輸入路徑；另在 GNOME Terminal 3.52.0／GTK 3 實際組字、選字及確認。原有編輯器恢復草稿未覆寫，本輪另存專用下載資料夾的 typing-result.txt。
- [x] 僅裁切實際畫面；倉頡罕字方框保留。原圖、下載及操作紀錄留本機產物目錄，不提交。
- [x] 四份本輪文件共 181 個本機引用均存在；Linux 指南引用 20 張可讀 PNG，沒有待補圖占位。已檢查 diff 與 `git diff --check`，未因純文件變更重跑建置或功能測試全套。
- [ ] 全新安裝、X11、其他 App、實體多螢幕與完整發布矩陣未由本輪驗證；圖片補齊不等於上述驗收通過。README 代表圖與 StoreAssets 素材未變更。

### FreeBSD 本輪紀錄（2026-10-24）

- [x] 原 15 個補圖位置已補齊，共新增 20 張入文，指南沒有待補圖占位。
- [x] 已確認核心與 userland 均為 15.1-RELEASE-p3、amd64、X11，pkg 的本機安裝版號為 1.3.7；ports 來源、既有產物與安裝狀態分開拍攝。
- [x] GTK 3 bridge、繁體中文字型、手動登入後三個環境值、Fcitx 行程與 Xfce 自動啟動均已實拍。
- [x] Fcitx 搜尋與目前清單分圖，拍攝用暫時移除未套用，原英文、注音、倉頡、簡易清單已恢復。
- [x] Mousepad 逐鍵輸入指定兩行，先選對琦與假；玩第 1 項，選字後按 End 回句尾，原句未加字，確認前後均已拍攝。
- [x] 倉頡只輸入 H、K，喬第 5 項反白；選取後儲存檔的三行文字核對一致。ComposeWhileTyping=False、PrefixCandidates=False、ClearOnError=True 已恢復並重新載入。
- [x] 只裁切真實畫面，罕字缺字框保留；沒有重建套件、重裝、重設詞庫或改寫產品程式。原圖及操作產物不提交。
- [x] BSD-01a 由管理員手動驗證後執行 pkg update，全部目錄刷新成功，查詢 FreeBSD 15／amd64 quarterly 仍為 1.3.0；來源 URL 同圖保留。僅更新目錄，沒有變更分支或安裝套件，完成後已退出 root。
- [x] 五份本輪文件共 218 個本機引用均存在；FreeBSD 新增 20 張 PNG 可讀、21 張指南圖片包含一張先前素材，沒有待補圖占位。diff 與 git diff --check 已檢查。
- [ ] 本輪未重新執行 ports 建置、套件安裝或先前 19 字長句；其他桌面、Wayland、其他 App 與完整發布矩陣不在本輪範圍。README 及 StoreAssets 未變更。

## 12. 指南缺圖依據與待補位置

本節盤點六份指南實際引用的圖片與可見狀態，對照第 4～9 節完成條件，作為後續補拍依據。每列的「待補畫面」同時是拍攝完成條件；尚未取得圖片時只保留占位。新拍與先前素材各自標示驗證範圍。

macOS 的本輪指南補圖已齊。安裝、英文輸入提示、Emoji 列表與插入結果、更新頁及每週通知均已入文；更新說明及原 12a／12b 合用一張圖。依維護者要求不再列選字後續打補圖。

### Windows（本輪補圖已齊）

指南：[WINDOWS_INSTALL.md](../WINDOWS_INSTALL.md)。23 張圖片已逐張登記於第 11 節，完成頁、四模式選單及切換前／已選琦琦兩種狀態均已入文，沒有待補圖占位。圖片完成不等於新增 Windows 10／x86、安裝後登入或整體發布驗收。

### macOS（本輪補圖已齊）

指南：[MACOS_INSTALL.md](../MACOS_INSTALL.md)。共 18 張圖片已入文並登記於第 11 節，沒有待補圖占位。最後補上的英文模式提示採用維護者提供的原圖；依確認不再重拍。圖片補齊不代替更新查詢、端到端升級或完整發布驗收。

### iOS／iPadOS（6 個待補位置）

指南：[IOS_INSTALL.md](../IOS_INSTALL.md)。

| 占位 ID | 優先 | 指南放置段落 | 待補畫面／完成條件 | 判定依據 |
| --- | --- | --- | --- | --- |
| IOS-12c | P2 | 6. 想用空白鍵開候選 | 空白鍵開候選後再按空白，顯示另一頁候選；保留翻頁前後兩種狀態。 | 已拍空白開候選，缺再次按空白翻頁的前後畫面。 |
| IOS-11d | P2 | 7. 接上 USB／藍牙鍵盤時 | iPhone／iPad 實機接 USB 或藍牙鍵盤，App 編輯器顯示已連線並實際輸入；不能用 Generic Keyboard 模擬器圖代替。 | 已有模擬器編輯器及複製確認，缺實機連線、跨 App 貼上與分享頁。 |
| IOS-11e | P2 | 7. 接上 USB／藍牙鍵盤時 | 複製後在另一個文字 App 貼上，文字與原編輯器一致。 | 已有模擬器編輯器及複製確認，缺實機連線、跨 App 貼上與分享頁。 |
| IOS-11f | P2 | 7. 接上 USB／藍牙鍵盤時 | 分享文字的系統分享頁；避開個人聯絡人及無關 App 內容。 | 已有模擬器編輯器及複製確認，缺實機連線、跨 App 貼上與分享頁。 |
| IOS-10i | P1 | 倉頡也能從部分字根選字 | iPad 實機的直／橫向玩候選及倉頡竹大／喬，保留真實裝置及版本；既有模擬器圖繼續標明來源。 | iPad 版面已有模擬器圖，實機觸控仍待驗。 |
| IOS-07c | P1 | 圖片來源與驗證範圍 | iPhone 實機的指定兩行玩候選與倉頡竹大／喬，分圖；首頁實機圖不能代替觸控輸入。 | 除 App Store 商品頁與首頁外，既有 iPhone 操作圖均為模擬器來源。 |

### Android（8 個待補位置）

指南：[ANDROID_INSTALL.md](../ANDROID_INSTALL.md)。

| 占位 ID | 優先 | 指南放置段落 | 待補畫面／完成條件 | 判定依據 |
| --- | --- | --- | --- | --- |
| AND-01 | P0 | 1. 從 Google Play 安裝 | Google Play 正式商品頁及安裝／開啟入口，避開帳號與個人推薦內容。 | 已有 App 首頁，缺 Google Play 商品與安裝入口。 |
| AND-13 | P2 | 5. 依習慣調整設定 | 展開關聯詞詞庫，預設小麥注音與其他分類的勾選位置可辨認。 | 設定首頁的關聯詞區塊收合，沒有展開分類圖。 |
| AND-10 | P2 | 6. 使用 USB／藍牙實體鍵盤 | 實體鍵盤浮動候選窗與宿主游標同時可見；標註真實鍵盤或模擬器。 | 沒有本輪實體鍵盤浮動窗及宿主游標圖。 |
| AND-09 | P1 | 6. 使用 USB／藍牙實體鍵盤 | 實體鍵盤雙排設定、組字、候選及恢復數字列，分圖呈現；關閉浮動窗。 | 本輪圖是觸控鍵盤，不能表示實體雙排選字已完成。 |
| AND-11 | P2 | 6. 使用 USB／藍牙實體鍵盤 | 面板收合前、按 ▼ 後與再次顯示的三種狀態。 | 沒有面板收合前後及恢復的三狀態圖。 |
| AND-12a | P2 | 7. 手機橫向與平板 | 手機橫向的完整觸控鍵盤與玩候選，保留文字宿主。 | 本輪只有手機直向，不能代替橫向或平板。 |
| AND-12b | P2 | 7. 手機橫向與平板 | Android 平板自己的版面與候選；不得拉寬手機截圖代替。 | 本輪只有手機直向，不能代替橫向或平板。 |
| AND-06c | P1 | 圖片來源與本輪驗證範圍 | Android 手機實機的指定兩行玩候選與倉頡竹大／喬，分圖；記錄裝置、OS 與安裝來源。 | 既有 1.3.7 操作圖為 Pixel 8 Pro 模擬器，實機仍待驗。 |

### Linux／Ubuntu（本輪補圖已齊）

指南：[LINUX_INSTALL.md](../LINUX_INSTALL.md)。原 18 個補圖位置已補齊，共引用 20 張圖片，逐張來源在第 11 節登記。涵蓋正式下載、四檔校驗、1.3.3 升級至 1.3.7、Fcitx／GNOME 面板、設定、指定兩行及玩候選前後、倉頡竹大／喬與另一文字宿主。

實拍範圍為 Ubuntu 24.04.5／GNOME 46／Wayland／amd64 VM、Text Editor 46.3 的直接 Fcitx 路徑與 GNOME Terminal／GTK 3。全新安裝、X11、其他 App 與完整發布矩陣仍須另驗，不能由圖片補齊推定通過。

### FreeBSD（本輪補圖已齊）

指南：[FREEBSD_INSTALL.md](../FREEBSD_INSTALL.md)。原 15 個位置已補齊，新增 20 張圖片；兩組指定情境均以 FreeBSD 自己的 Mousepad 實際操作，檔案文字已核對。

套件庫刷新後的 FreeBSD 15／amd64 quarterly 為 1.3.0；本機既有 ports 產物與安裝版號均為 1.3.7，來源、產物及安裝狀態分別標示。本輪未重新建置或安裝，其他桌面、Wayland、其他 App 與完整發布矩陣仍需另驗。
