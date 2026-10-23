# iOS 螢幕與輸入模式切換處理矩陣

日期：2026-10-23。程式基準與疑點編號見[架構審查](IOS_APP_EXTENSION_HOST_REVIEW.md)。本文件是待確認的行為規格與後續驗證方案；本輪沒有執行下列測試，也沒有變更既有通過紀錄。地球鍵、取消清單、收鍵盤、換欄位與開闔的產品行為已依[組字保留與確認規則](IOS_COMPOSITION_HANDOFF_POLICY.md)確認，實作方式仍待驗證；其他輸入方法與鍵面切換仍需各自確認。

## 使用矩陣前的共同定義

「窄螢幕」「標準螢幕」「平板螢幕」是測試分組，不是三個 Apple API 類別。每次都記錄實際 View／Window／Scene bounds、size class 與 safe area。相同機型可能落入不同空間條件，iPad 可以有窄視窗，Duo 內螢幕也可以只分到部分畫面。[HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout)

本體 App、使用鍵盤的 App 與 extension 的紀錄分開。裝置方向、Scene 介面方向、視窗長寬比也分開；設定方向或要求旋轉成功，並不證明畫面已變成預期大小。[UIWindowScene](https://developer.apple.com/documentation/uikit/uiwindowscene)

處理依據的優先順序是：目前角色能取得的本地幾何與系統狀態、該 API 的版本條件、產品模式政策。沒有 hinge 資料時記為未知，不從「寬」「regular」或無回呼推算折疊狀態。

## 三種角色各自記錄的狀態

| 項目 | 本體 App 與使用鍵盤的 App | keyboard extension |
|---|---|---|
| UI 工作階段 | Scene session、activationState、window 與是否為 key window | 當前 view／window 及連線可用性；不假設擁有使用鍵盤的 App 的 Scene |
| 版面 | 本地 bounds、safe area、layout margins、traits、有效 geometry | 自己的 bounds、safe area、traits、系統提供寬度與實際容許高度 |
| 區域 | 可取得時查本地 active division／occlusion | 只採自己取得的區域；缺資料明列未知 |
| 文字 | 欄位身分、first responder、selection、marked range、內容與欄位 traits | proxy 的 documentIdentifier、可得 context／selectedText，及自己的暫態組字 |
| 鍵盤 | 已聚焦、要求何種輸入、系統或第三方鍵盤、硬體鍵盤與工具列 | 自己是否可見、地球鍵屬性、目前輸入方法與鍵面 |
| 保存 | 自己的文件及 App 設定；測試輸入文字由 fixture 管理 | 私有學習與偏好；App Group 唯讀資料不由 extension 回寫 |

first responder 是請求結果，不等於軟體鍵盤可見；keyboard view 可見也不等於文字代理已能完成所有操作。後者要以實際輸入／切換證據判讀。[becomeFirstResponder](https://developer.apple.com/documentation/uikit/uiresponder/becomefirstresponder())、[Custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard)

## 螢幕與視窗配置矩陣

| 分組與情境 | 處理依據 | 本體與輸入測試頁面 | extension | 現況／待補 |
|---|---|---|---|---|
| 窄版手機視窗 | 本地寬高、compact width、文字大小 | 可捲動內容、Return 與關閉控制保持可到達；避讓當前鍵盤 | 在分配寬度內維持可操作按鍵，按實際高度選緊湊配置 | 既有窄版與 155 pt 樣式是基線；需測候選、設定、長文字和大字體 |
| 一般手機視窗 | 本地 bounds 與 traits，不能靠螢幕型號 | 使用標準 navigation、sheet 與安全區 | 同時支援寬度持續變化與 class 跨界 | 330 pt 是鍵盤的產品偏好，不是所有使用鍵盤的 App 都會提供這個鍵盤高度 |
| 寬而矮的視窗 | 高度與垂直 class；同 class 內仍會改尺寸 | 依可用空間重排／捲動，避免固定底列遮住欄位 | 面板、候選與功能鍵在系統實際高度下可用 | iPad metrics 先判 idiom，需針對此分支驗證，見 R06 |
| iPad 全螢幕 | 實際視窗大小、安全區 | 標準導覽與欄位避讓；保存目前編輯位置 | 內容上限與間距是產品選擇，不能只看 `.pad` | 既有 iPad 固定姿態結果不等於多工與浮動已完成 |
| iPad 多工／Windowed Apps／Stage Manager | 目前 window 與鍵盤相交區域 | 優先採 keyboard layout guide；若使用通知，須轉換座標並求與本視窗的交集 | 寬度由系統決定，不能要求跟使用鍵盤的 App 等寬或全螢幕 | 增加同一 size class 內連續縮放、矮窗與移動視窗 |
| iPad 浮動、未固定或系統分離鍵盤 | OS 是否提供該呈現，以及 keyboard layout guide | 明訂是否跟隨 undocked keyboard；浮動鍵盤在本窗外時不能當成窗內遮擋 | 支援實際送來的 compact 寬度；自己的左右分離是另一項外觀設定 | Apple 明確要求 custom keyboard 測浮動呈現；不推定 extension 可控制所有系統鍵盤形態 |
| Duo 外螢幕與闔上 | 當前 Scene／View，可能含側邊控制的非對稱 safe area | 標準 bars 可自行適應；前景控制逐邊避讓，背景可延伸 | 使用自己的 safe area，不能套 App 的側邊 inset | 既有外螢幕資料可作基線，不作所有 runtime 的尺寸常數 |
| Duo 內螢幕全開 | 本地 regular／regular 和實際分配區域 | 保存功能與編輯狀態；大視窗可顯示更多內容 | `.phone` 不阻止寬版配置；十二欄依產品條件選用 | 全開不是固定視窗大小，多工還要另測 |
| Duo 半開如書本 | 本地 active division，而非僅看 hinge angle | 重要控制可移到有效區域；連續文件／列表不應任意整塊跳動 | 若取得區域則在本地避讓；未取得時維持明確的手動外觀能力 | 固定比例中央縫不能被當成實際折線保證，見 R07 |
| Duo 半開置於桌面、直向或倒置 | 實際 region 方向、scene geometry 和 safe area | 依內容用途配置上下區域，不由「橫／直式」名字推定手勢位置 | 是否與折線相交以自身區域為準；不一定需要上下分離 | 需用真實姿態及本地資料確認，不只送 orientation 指令 |
| Duo 內螢幕多工左右窗 | 每個 App 自己的 window、bars 與區域 | 左右兩個 App 的控制側可能不同；不能假設只避讓右側 | 重新確認 keyboard surface 與使用鍵盤的 App 的螢幕歸屬 | 目前不能從全螢幕 sheet 的結果推定多工正確 |
| 連接／切換另一顯示器 | windowScene 所屬 screen 與 scene geometry | 不快取全域 main screen；按 Scene 處理焦點與版面 | 不複製使用鍵盤的 App 所在螢幕的假設；文字工作階段與顯示器歸屬分開 | 已有錯接內外螢幕紀錄；需先辨認路由，再測輸入 |

依據：[keyboard interface](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface)、[keyboard layout guide 範例](https://developer.apple.com/documentation/uikit/adjusting-your-layout-with-keyboard-layout-guide)、[iPadOS 26 windowing 教材](https://developer.apple.com/videos/play/wwdc2025/208/)、[Duo HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)、[本地 reserved regions](https://developer.apple.com/documentation/uikit/uiview/reservedregions(kind:options:))。表中的驗證需求是本專案依據上述規則提出的待審方案。

### 區域避讓的計算界線

`safeAreaInsets` 依 view 而定，未進入可見階層時可能是零。零值不能直接推論沒有系統遮擋。[Apple safe area](https://developer.apple.com/documentation/uikit/uiview/safeareainsets)

division／occlusion 的 frame 在查詢 view 的座標中；已包含 interactive margins。只應使用當下有效區域安排互動內容，避免再把 App、window、view 或標準容器已套過的安全區重複扣除。`includeInactive` 用於了解存在但未啟用的區域，不能把 inactive 區域當成正在遮住內容。[Apple region API](https://developer.apple.com/documentation/uikit/uiview/reservedregions(kind:options:))

hinge 的 nil／無更新只代表未取得可用的 hierarchy 資料；status 的 unknown、closed、partiallyOpen、fullyOpen 需要有資料後才能判定。角度的更新頻率與精度也由系統決定，不應用事件次數或固定角度等待取代狀態辨識。[UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction)、[UIHinge](https://developer.apple.com/documentation/uikit/uihinge)

## 模式分類與切換責任

| 模式層級 | 包含哪些狀態 | 誰決定 | 需要保存／交接什麼 |
|---|---|---|---|
| 系統輸入來源 | 琦琦、系統注音、英文、Emoji 等已啟用鍵盤 | 使用者與系統 | 只確認已完成文字，未完成注音／字根取消；實際切換的證據另行確認 |
| 硬體與軟體輸入 | 軟體鍵盤、硬體鍵盤工具列、App 內 raw-key 編輯器 | 系統與目前 first responder；編輯器屬 App 功能 | 焦點、按住鍵狀態、App 內文字；不能把 App raw-key 測試當成 extension 測試 |
| 琦琦輸入方法 | 好打注音、傳統注音、倉頡、簡易；標準／許氏鍵位 | 使用者與引擎 | 切換前的文字、未完成讀音／字根、候選及學習時機 |
| 琦琦鍵面 | 中文、英文、數字、Shift、暫時英文、符號、Emoji | 使用者與欄位政策 | 引擎規定的提交／保留行為；不是呼叫系統地球切換 |
| 琦琦呈現 | 完整／左右分離、十一／十二個視覺位置、候選列、設定面板 | 使用者與可用空間 | 除了有語意的設定變更，重排不能清除組字或重複插入文字 |
| 欄位意圖 | keyboardType、returnKeyType、secure、大小寫與其他 traits | 使用鍵盤的 App | 回應支援的 traits；驗證輸入內容與執行送出動作仍由使用鍵盤的 App 負責 |

iPadOS 系統分離／浮動鍵盤與琦琦自己的分離外觀，須各有測項。視覺多一格不增加引擎音節數：目前觸控仍維持九／十音節邊界；「十一個組字位置」「十二個控制位置」「九個可修改音節」也不是同一個計數。[現有產品規格](IOS_IPHONE_DUO_ADAPTATION.md#手動分離鍵盤)

## 文字與選取的起始狀態

以下每項切換至少選取適用的起始狀態；不能只輸入空字串或單一完成字。

| 編號 | 起始狀態 | 切換後必須分別檢查 |
|---|---|---|
| C0 | 空欄位、沒有組字 | 焦點、鍵面、是否真的有可操作鍵盤 |
| C1 | 未完成注音／字根 | 明確切換／收起／換欄位時未完成碼取消；取消清單或單純開闔時仍可接續；App 文字結果分開檢查 |
| C2 | 已完成但仍可修改的組字 | 完整輸出與可修改範圍；兩者分開斷言 |
| C3 | 句中開候選、已選字或翻頁，尾端另有未完成內容 | 候選目標、頁面、選字結果與句尾接續位置 |
| C4 | 接近第九／十音節邊界，已有固定前段 | 固定前段不得因候選、Backspace 或重建而改動；無重複字 |
| C5 | 游標／選取被使用鍵盤的 App 或使用者改變 | 舊尾段是否仍有效；不可對新位置重播舊刪除操作 |
| C6 | 英文、數字、符號或 Emoji，含非 BMP 與組合字元 | 刪除與選取語意、文字完整、模式恢復 |

App 輸入框中的普通文字與 extension 的 marked text 必須另查。好打觸控目前鏡射普通文字，傳統路徑使用 marked text；「畫面上有字」不能替代這項區分。[官方 text interactions](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards)

## 事件切換矩陣

下表保留跨功能的待審項目；本輪五種操作已確認為「明確離開時只確認完成文字、取消未完成碼；取消清單與單純開闔保留」。這是產品決策，不是 Apple 對所有輸入法的強制規定，實作仍未變更。

| 事件 | 應依據的系統資訊 | 待審處理與不變條件 | 現況／疑點 |
|---|---|---|---|
| 初次聚焦一般欄位 | key window、first responder 回傳值、欄位 traits、proxy 可用狀態 | 建立新的文字工作階段；啟用清單、目前選中鍵盤及鍵盤可見各自確認 | R05；不能把有游標或已安裝當成 extension 已可輸入 |
| 同一 view 改尺寸、safe area 或 class | layout／traits／有效 geometry；27.1 可有 regions 變更 | 重排介面、取消仍在進行的按住手勢；保持文字及引擎語意狀態 | 現有 full／split 重排可作基線；R06／R07 |
| 外螢幕到內螢幕或反向 | 目前 Scene、screen、window、proxy 文件身分 | 原位置仍有效且引擎存活時保留組字、只改版面；暫時未知先停寫；新文件或已失效位置不沿用舊尾段 | 不保證同一 controller、程序或 proxy 永遠存活；R04 |
| 同欄位移動游標／選取／App 修改輸入框文字 | text／selection delegate 與目前 context | 已知外部改變後停止舊尾段替換；保留 App 已有文字；不把原未完成內容補到新游標位置 | 250 ms guard 可能忽略同文件外部事件，R01 |
| 換欄位或切換使用鍵盤的 App | 文件身分及目前輸入環境 | 舊位置仍有效時只確認完成文字、取消未完成碼；已換走不向新欄位補送或倒刪；新組字開始 | nil UUID 與非同步切換須另驗證，R04 |
| 單點地球切換出去 | 系統 handler、實際目標鍵盤與使用鍵盤的 App 是否仍正常執行 | 真正切換時在原位置只確認完成文字一次、取消未完成碼；回來新組字開始；目標鍵盤須可輸入 | false fallback 與 SIGABRT 分開驗證，R08 |
| 長按地球開清單再取消 | 清單是否開／關，輸入法是否實際改變 | 已確認保留完整組字、候選目標與未完成讀音／字根；須檢查 C1／C3 可接續；取消的公開 API 辨認方式仍待驗證 | 現況 touch-down 已 finish，R02 |
| 從清單選另一個鍵盤再切回 | 實際來源與目標、欄位文字 | 與真正短按切換採同一政策：只確認完成文字、取消未完成碼；仍須分開驗證清單路徑，不能從清單出現推定完成 | 最小版曾清單選取成功，不能推定完整版／所有使用鍵盤的 App 皆正常 |
| 按琦琦「▼」收鍵盤再聚焦 | `dismissKeyboard`、文字交接及重新聚焦結果 | 只安全確認完成文字、取消未完成碼再收起；重新聚焦從新組字開始；不觸發 Return，也不直接操作 App 的欄位物件 | 呼叫 API 正確，main queue 延後不是 proxy 完成確認，R04 |
| 系統被動收起鍵盤、App 切換或鎖定 | view appearance、Scene activity 與文件狀態各自判讀 | 已確定換 App 時依換欄位規則；其他原因未知時暫停且不寫入；原位置仍有效才恢復；不假設最後一次回呼能提交 | 不假設 disappearance 等於程序結束 |
| 完整／左右分離互換 | 使用者設定與本地空間 | 保留 C1–C4；左右空白作用相同；視覺欄數不改音節上限 | 現有方向可保留；增加跨 600 pt 門檻和無地球列組合 |
| 開／關候選或翻頁 | 引擎候選狀態與目標音節 | 不把 App 輸入框中的游標移到錯誤位置；關候選後仍接句尾；固定前段不變 | 每頁九候選與十二控制位置分開檢查 |
| 開／關鍵盤設定面板 | overlay 可見狀態、系統實際高度 | 單純開關與外觀設定不結束組字；輸入方法／字根選項變更另做語意交接 | 目前設定面板是 subview；高度可變，不能把 viewDidLayout 當作新 session |
| 切好打／傳統／倉頡／簡易或標準／許氏 | 引擎輸入方法與目前文件 | 按確認過的政策完成舊輸入；保存使用者已接受的文字；不重複學習與送字 | 現有 setChineseInputMethod／setKeyboardLayout 有交接；需從使用鍵盤的 App 確認文字結果 |
| 切中文／英文／數字／符號／Emoji | 琦琦內部鍵面、Shift 與欄位政策 | 正確處理未完成輸入；不呼叫系統輸入法切換來代替鍵面切換 | ASCII／數字只是鍵盤提示，MODE 解鎖是產品政策 |
| 聚焦 secure／phonePad／namePhonePad 後返回 | 使用鍵盤的 App 設定的 secure 與 keyboardType | 預期系統接管；返回一般欄位時重新確認琦琦狀態 | 不把 extension 不出現當作這些欄位的產品故障 |
| 按 Return／搜尋／傳送／下一個 | returnKeyType 與使用鍵盤的 App 的 delegate | 分開查鍵帽、提交文字、真正執行的動作；多行欄位才驗證換行 | 原輸入測試頁面一律 endEditing，不能證明搜尋／傳送／Next 正確 |
| 接上／拔除外接鍵盤 | 硬體鍵盤狀態、key window 與軟體鍵盤可見狀態 | 允許系統不顯示軟鍵盤；App raw-key 編輯器只處理自己取得的事件 | 連線回呼不能取代焦點成功的確認 |
| App 內編輯器失去活動、顯示其他 UI 或返回 | 所屬 Scene 與 capture responder | 停止退格重複；未處理鍵傳給 responder chain；恢復時確認焦點 | 現有 App-level notification 屬 aggregate 狀態；若支援多 Scene，要另審局部狀態 |
| App 設定／自訂詞改變後返回鍵盤 | App Group 可讀設定、revision 與 appearance | 明訂下次開啟時套用；不要求 extension 回寫；語意設定變更先處理舊組字 | `UserDefaults.didChangeNotification` 不提供跨程序變更通知 |
| 記憶體壓力、extension 被終止再建立 | 真正的程序身分、App 輸入框中的文字、可讀設定 | 新引擎不得把舊尾段當成自己已擁有；保留的設定從各自儲存重載 | 未測得的終止原因不可從「鍵盤不見了」直接推定 |
| App 自身被終止／重啟 | 使用鍵盤的 App 自己的文件保存政策 | 測試 fixture 可以清空；產品 App 編輯器是否保存草稿需另決定 | extension 無權替任意使用鍵盤的 App 保存完整文件 |

依據：[UITextDocumentProxy](https://developer.apple.com/documentation/uikit/uitextdocumentproxy)、[UIInputViewController](https://developer.apple.com/documentation/uikit/uiinputviewcontroller)、[first responder](https://developer.apple.com/documentation/uikit/uiresponder/becomefirstresponder())、[Scene lifecycle](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle)、[defaults notification](https://developer.apple.com/documentation/foundation/userdefaults/didchangenotification)。具體琦琦政策與風險的讀碼依據見主報告 R01–R10。

## 版本與環境驗證軸

| 軸 | 分組 | 要回答的問題 |
|---|---|---|
| 最低執行系統 | iOS 17；實際已有的 18、26.x；後續 27.x | 新 API 是否正確隔離；同一語意在舊 runtime 是否仍成立 |
| SDK 與 Xcode | Xcode 27.1／SDK 27.1；本機 27.2 beta 3／SDK 27.2 | linked-on 行為是否不同；不能以 compiler 版本推定 SDK symbols |
| 實際 runtime | 每台 OS 完整版本與 build | 27.2 SDK 建置、27.1 runtime 執行，仍是 27.1 行為證據 |
| 使用鍵盤的 App | 最小原生欄位、原容器 Debug 頁、WebKit／外部 App | 同樣鍵盤與姿態下，哪些 traits、呈現、生命週期影響結果 |
| 鍵盤來源 | 系統鍵盤、最小 custom extension、完整琦琦 | 確定故障發生在哪個必要條件；最小版成功也不能替完整產品驗收 |
| 實體或模擬 | 受控普通 Simulator、Duo Simulator、Duo 真機 | 避免把工具已知限制當成產品規格；也不能用 Simulator 成功代替真機 |

已知舊證據的 Duo runtime 是 iOS 27.1 build `24A94232`，不是 iOS 27.2 beta 3。Xcode 27.1 的套件包含 iOS 27.1 與 iPadOS 27 SDK；不能因此憑空建立「iPadOS 27.1 已驗證」一列。[Xcode 27.1 說明](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes)

不要求無意義地窮舉所有機型乘上所有模式。先固定一個因素做對照，再測空間／版本邊界及真實跨狀態鏈；相依性不同的案例不能合併成一個「鍵盤測試通過」。

## 後續驗證方案

### 先確認環境能提供什麼證據

1. 固定 source commit、App／extension bundle、簽署與 App Group entitlement，以及各自安裝版本。
2. 記錄 Xcode build、SDK canonical name、OS runtime build、使用鍵盤的 App 的類型與 Device Hub 硬體鍵盤模擬狀態。
3. 確認 enabled keyboard、目前選中鍵盤、first responder、key window、實際可見鍵盤和目標螢幕。任何一項缺少就不能算已開始地球鍵或版面驗證。
4. Duo 記錄實際顯示器與 geometry。截圖可使用 `XCUIScreen.screens`，但不能假設陣列順序就是內／外螢幕名稱；仍須以畫面與幾何核對。[Apple](https://developer.apple.com/documentation/xcuiautomation/xcuiscreen)
5. 將 `187708767` 的 extension 限制列入環境註記；待確認是否涵蓋 custom keyboard。不能把有疑慮的模擬器當成唯一驗收入口。

### 依目的選擇對照

| 目的 | 對照方法 | 成功必須證明什麼 |
|---|---|---|
| 使用鍵盤的 App 的差異 | 同一 extension、runtime、姿態，依序比較最小原生、容器頁與 WebKit | 同一鍵盤確實出現；輸入／切換都實際完成；記錄兩者欄位 traits 差異 |
| 系統路徑差異 | 在同一個使用鍵盤的 App 中，比較系統鍵盤、最小 extension 與完整琦琦的切換 | 有原生目標按鍵可用；使用鍵盤的 App 與 extension 的程序結果分開 |
| API 與工具差異 | 同 source、同 runtime，以明確 SDK 組合對照；Duo 真機另列 | 一次只改一個因素；不把新 SDK 當作新 runtime |
| 文字安全 | C1–C6 中移動游標、換欄位、切 App、返回、被動隱藏 | 無遺失、重複、錯誤位置刪除；未擠出的／已固定文字範圍正確 |
| 取消後保留組字 | C1／C3 長按清單後取消，再回頭選字或完成讀音 | 除了全文相同，原目標與可修改狀態也符合已確認政策 |
| 版面完整性 | 同 session 連續縮放與跨完整／分離門檻，包含設定和候選 | 按鍵 frame、命中範圍、功能可達性及全文／組字各自正確 |
| 權限與保存 | App 未先初始化時使用 extension，再重建其程序 | first-use 和本地偏好按政策保存；沒有依賴 App Group 寫入成功 |
| 可用性 | 淺深色、大字體、VoiceOver、窄版及實際觸控 | 標籤、焦點順序、可操作性與可讀性；不只查 accessibility tree 有沒有元素 |

後續可用最小輸入測試 App 作辨因工具，現有 Debug 頁作多欄位整合，並保留在其他使用鍵盤的 App 中驗證。三者各有用途，新增 target 與測試程式都須在研究確認後才執行。

### 判定與停止條件

- 通過：前提成立、指定轉換真的完成、文字與必要組字狀態皆符合規格，且沒有新增對應 crash。
- 失敗：保留失敗當時的前提、階段、App／extension 程序結果與報告。現有 extension-required 測試的啟用失敗仍為 fail。
- 預期系統接管：僅用於官方不允許 custom keyboard 的欄位／使用鍵盤的 App；不能泛用到所有無鍵盤畫面。
- 環境受限：標記為缺少驗收證據並保留測試失敗，不改成產品通過或跳過。另用有支援的環境補證據。
- 已知成功不重跑到沒有新資訊：僅在改動因素、新失敗或未解疑點需要時增加測試。

Duo 開闔驗證要明確觀察 closed，再觀察回到指定的穩定狀態與顯示器；事件數增加或途經 partiallyOpen 不算完成整段操作。測試開始與結束都應保留實際狀態。

## 審查確認清單

- 依[已確認的五種操作規則](IOS_COMPOSITION_HANDOFF_POLICY.md#五種操作的規則)驗證實作可行性：明確離開只確認完成文字、取消未完成碼；取消清單與單純開闔保留；位置失效後停止沿用。
- 確認獨立的最小輸入測試 App 是否納入開發，以及原 Debug 頁保留哪些整合責任。
- 確認 offline／Full Access 關閉維持不變時，first-use 日期的所有權。
- 確認本地幾何、有效區域與可用高度的配置原則；缺少 hinge 資料時的能力界線。
- 確認 SDK 工具下限、Beta 3 資料缺口與真機驗收條件。

以上確認完成後才決定實作順序；本矩陣沒有授權部署、發布或直接合併工作分支。
