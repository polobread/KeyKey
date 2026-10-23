# iOS 鍵盤切換與開闔訊號可行性審查

日期：2026-10-23。對照[已確認的組字規則](IOS_COMPOSITION_HANDOFF_POLICY.md)，研究基準為文件 commit `468363dd`；相關程式仍以 `c5e04e5c3b2586e9fdf099b9e2bd7c20b43b17f8` 為讀碼基準。範圍為 Apple 公開文件，以及本機 Xcode 27.1、27.2 beta 3 的公開宣告；本輪沒有改程式、建置、操作裝置或執行功能測試。

結論：**目前查閱的公開契約不足以保證，任意 App 中的 keyboard extension 都能可靠區分「真正換鍵盤」「取消系統清單」「開闔後恢復」，並在原輸入位置失效前完成交接。** 琦琦自己的「▼」有明確操作時點；單純版面更新可以保留組字；系統鍵盤清單則仍有原因與時序缺口。以下方案保留已確認的產品規則，不把規格改成一律確認或一律保留。

## 這次所說的可靠

可靠的判定要同時回答三個問題：

1. **發生什麼：** 使用者真的換了鍵盤、取消清單，或只是改變裝置姿態？不能只知道某個 View 不見了。
2. **是否來得及：** 知道原因時，原欄位、原選取與原文字代理是否仍有效？事後通知不能自動當成事前交接機會。
3. **適用到哪裡：** 訊號是否提供給 extension 本身，是否涵蓋同語言鍵盤、所有清單路徑與多顯示器？在本體 App 收到的訊號不能直接推定 extension 也收到。

這是對本產品需求的判定標準。公開 API 可呼叫、通知偶爾觀察得到、或某個 runtime 測試成功，都不單獨滿足全部條件。

## 各種操作能掌握到什麼

| 操作或情況 | 公開 API 能直接說明的事 | 對已確認規則的可行性 |
|---|---|---|
| 按琦琦自己的「▼」 | 琦琦先收到自己的按鍵動作，再呼叫 `dismissKeyboard()` | 可設計為先只確認完成文字、取消未完成碼，再收起。仍須驗證原位置與實際文字結果 |
| 琦琦自己明確呼叫「下一鍵盤」 | 可在 `advanceToNextInputMode()` 前記錄命令與處理文字；下一個鍵盤由系統決定 | 可控制命令順序，但沒有成功 completion。此路徑不等同目前由系統 handler 同時處理短按與長按清單 |
| 系統 handler 的短按或清單選擇 | handler 負責切換；公開方法沒有回傳選擇結果的介面 | 不能從公開契約保證在清單真正選定後、原位置失效前取得回呼 |
| 長按系統清單後取消 | handler 支援清單互動，但未公開取消結果通知 | 保留是已確認的產品結果；不能用普通觸控取消當成系統清單已取消的證明 |
| 同一文字工作階段中，鍵盤仍可用而尺寸／安全區改變 | 可以取得本地 layout、traits、window 等更新 | 可只重排並保留組字，不需要先辨認確切開闔角度；若另有欄位或選取變化，須另行失效處理 |
| 鍵盤消失後再出現，可能同時換顯示器 | appearance 只描述 View 的顯示生命週期 | 不能單靠它分辨真正切換、開闔、焦點移動或其他隱藏；未知時暫停舊位置寫入 |
| 有效的 hinge 更新 | 可知道該 View hierarchy 提供的 hinge 狀態 | 是姿態的正面線索，不證明同時沒有換鍵盤；extension 是否收到資料仍需環境證據 |

依據：[dismissKeyboard](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/dismisskeyboard())、[advanceToNextInputMode](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/advancetonextinputmode())、[handleInputModeList](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/handleinputmodelist(from:with:))、[viewWillDisappear](https://developer.apple.com/documentation/uikit/uiviewcontroller/viewwilldisappear(_:))、[UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction)。表中可行性是依上述契約對本產品需求的推論，未經本輪執行驗證。

## 候選訊號的契約與限制

| 訊號 | 公開契約 | 可以用來做什麼 | 不能直接推定什麼 |
|---|---|---|---|
| [`handleInputModeList(from:with:)`](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/handleinputmodelist(from:with:)) | 短按切換、長按／上滑開清單；回傳 `Void` | 保留系統短按與長按清單互動 | 清單選了誰、是否取消、選定前可提交文字的時點 |
| [`advanceToNextInputMode()`](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/advancetonextinputmode()) | 要求系統切到下一個使用者啟用的鍵盤；回傳 `Void` | 琦琦主導的明確切換命令 | 所有系統清單選取一定會經過這個可覆寫方法，或方法返回代表遠端文字已交接完成 |
| [`currentInputModeDidChangeNotification`](https://developer.apple.com/documentation/uikit/uitextinputmode/currentinputmodedidchangenotification) | 模式改變時發出，posting object 是 `UITextInputMode` | 在確實收到的程序中觀測模式變更 | 是使用者選清單、換欄位或其他原因；更不能保證在原代理失效前通知來源 extension |
| [`CurrentInputModeDidChangeMessage`](https://developer.apple.com/documentation/uikit/uitextinputmode/currentinputmodedidchangemessage) | iOS 26 起的型別化通知；公開 struct 的 Subject 為 `UITextInputMode` | 使用 Swift actor-aware 通知介面 | 新增了事前切換、取消原因或目標 extension ID；本次公開宣告沒有這些欄位 |
| [`primaryLanguage`](https://developer.apple.com/documentation/uikit/uitextinputmode/primarylanguage) | 可為 nil 的語言代碼；不同模式物件可以有相同語言 | 區域與語言配置 | 同語言就等於同鍵盤，或語言不同就代表使用者從地球清單選走 |
| [`activeInputModes`](https://developer.apple.com/documentation/uikit/uitextinputmode/activeinputmodes) | 回傳模式物件陣列，可能為空 | 有需求時檢視模式資訊 | 陣列變化是本次清單選擇結果，或能直接呼叫 UIInputViewController 指定其中某個鍵盤 |
| [`UIResponder.textInputMode`](https://developer.apple.com/documentation/uikit/uiresponder/textinputmode) | 該 responder 啟用時的輸入模式 | 使用鍵盤的 App 查自己擁有的欄位 | extension 能藉此取得另一程序的目前欄位或鍵盤切換原因 |
| proxy 的 [`documentInputMode`](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/documentinputmode) | 用於鍵盤的區域／語言配置；SDK 註解允許 App 在文件 context 保存模式 | 配合目前文件配置輸入 | 一份即時、全域、附有目標鍵盤身分與切換原因的狀態 |
| [`viewWillDisappear`](https://developer.apple.com/documentation/uikit/uiviewcontroller/viewwilldisappear(_:))／`viewDidDisappear` | View 的顯示生命週期 | 暫停手勢、停止對不明位置寫入，並等待核對 | 一定是換鍵盤；或一定有最後一次有效 proxy 提交機會 |
| [`isBeingDismissed`](https://developer.apple.com/documentation/uikit/uiviewcontroller/isbeingdismissed) | controller 是否正由祖先 dismiss | 補充一般 controller 狀態 | 為何移除鍵盤、清單是否取消或是否開闔 |
| [`NSExtensionHost…` 活動通知](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/nsextensionhostwillresignactive) | 使用鍵盤的 App 前景／背景或 active 狀態；WillResignActive 的 object 是 extension context，沒有 userInfo | 暫停 extension 活動、作為重新核對的線索 | 是鍵盤切換、清單取消或折疊；同 App 內換鍵盤不必改 App 活動狀態 |
| [`WillResignActiveMessage`](https://developer.apple.com/documentation/foundation/nsextensioncontext/willresignactivemessage) | iOS 26 起對上述活動通知的型別化介面 | 與通知相同的活動管理用途 | 多了鍵盤清單結果或折疊原因；型別化不會擴大原事件語意 |
| [text／selection delegate 與 context](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards)、[`documentIdentifier`](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/documentidentifier) | 文件文字、選取或文件身分的資訊 | 發現舊組字範圍可能失效 | 同 UUID 就是同游標；沒有變更就證明沒換過鍵盤；通知來源有固定 250ms 分界 |
| [keyboard frame 通知](https://developer.apple.com/documentation/uikit/uiresponder/keyboardwillchangeframenotification)、本地 layout／traits | 鍵盤幾何或可用空間改變 | 版面避讓與幾何觀測 | 尺寸改變一定是開闔；尺寸沒變就一定是鍵盤切換 |
| [`UIHingeInteraction`](https://developer.apple.com/documentation/uikit/uihingeinteraction)／[reserved regions](https://developer.apple.com/documentation/uikit/uiview/reservedregions(kind:options:)) | View hierarchy 的姿態資料或本地有效區域 | 有資料時觀測姿態、處理避讓 | nil／沒有回呼就是沒有開闔；有 hinge 更新就能排除同時切鍵盤 |
| [`.touchCancel`](https://developer.apple.com/documentation/uikit/uicontrol/event/touchcancel) 或手勢 [`.cancelled`](https://developer.apple.com/documentation/uikit/uigesturerecognizer/state-swift.enum/cancelled) | 自己的觸控／連續手勢被取消 | 取消按住狀態、退格連發等本地手勢 | 系統清單最後選了什麼，或確定沒有換鍵盤 |

各 API 的版本與核對範圍另見[官方來源清單](IOS_APP_EXTENSION_HOST_APPLE_SOURCES.md)。未由文件承諾的排他性、時序與程序投遞均未升格為保證。

### 通知不能當成跨程序交接確認

`NotificationCenter` 的傳遞範圍是一個 program。UIKit 或 extension 基礎設施可以在不同程序各自發布訊號，但不能因 App 端收到某通知，就推定它自然廣播到鍵盤程序。本次模式通知文件沒有保證來源 keyboard extension 一定收到、收到時仍可操作舊欄位，或它與 appearance／文字操作之間的次序；這不等於宣稱 extension 永遠收不到。[NotificationCenter](https://developer.apple.com/documentation/foundation/notificationcenter)、[模式通知](https://developer.apple.com/documentation/uikit/uitextinputmode/currentinputmodedidchangenotification)

型別化訊息的 MainActor 保證也不能充當遠端 proxy 的完成回報。文字改動已被 App 接受、輸入來源確實換走、來源 extension 還活著，是不同的驗證項目。

`NSExtensionContext.completeRequest` 的 completion 屬於自己要求完成 extension request 後的工作，布林值描述 completion 是否過期；它不是系統鍵盤清單的成功／取消回報。主動完成 request 也會導致 controller 被 dismiss，不能拿它來訂閱使用者的切換結果。[Apple completeRequest](https://developer.apple.com/documentation/foundation/nsextensioncontext/completerequest(returningitems:completionhandler:))

`NSExtensionHost…` 是通用 extension 活動介面，不是鍵盤清單專用協定；其宣告存在不代表每個 keyboard extension 環境都保證轉送同樣事件。SDK 也已將舊 `UITextInputMode.currentInputMode()` 類別方法自 iOS 7 廢棄，改指向 responder 的 `textInputMode`；查詢自己的 responder 不能代替另一程序的實際文字欄位。

## 為什麼多個線索仍不構成完整分辨保證

以下是依公開契約提出的反例情境，不是本輪新重現：

| 流程 | 返回時可能看到的資料 | 已確認的產品要求 |
|---|---|---|
| 開闔後回原欄位，或系統清單取消 | 同文件、同文字、同選取，原引擎仍在；可能有消失／出現 | 保留組字與未完成輸入 |
| 切到另一鍵盤，未打任何字就切回 | 同文件、同文字、同選取，原程序也可能仍在；可能有消失／出現 | 舊組字已結束，未完成碼已取消，開始新組字 |

公開契約沒有排除這兩個流程返回相同可見文字狀態、而來源 extension 未取得足夠清單結果資訊的情況。因此「文字沒變就恢復」或「消失過就清除」都可能違反其中一條規則。hinge 更新若有送達，只能證明也有姿態訊號；使用者可以同時開闔與切鍵盤，不能讓幾何線索覆蓋已知的文字失效事件或明確操作。

同理，無論選 250ms、等一個 main-loop turn，或延長觀察時間，都不會產生原本未提供的原因與原子交接保證。

## 可行方案與適用範圍

| 方案 | 可以做到的部分 | 限制與規則符合程度 |
|---|---|---|
| A 明確命令先交接 | 自己的「▼」先只確認完成文字、取消未完成碼，再呼叫公開 API；若另有自己主導的下一鍵盤命令，也能安排呼叫順序 | 「▼」有明確事件入口。下一鍵盤命令仍須確認實際結果；不能假設原系統 handler 的所有路徑可被同樣攔截，也不能未經確認改掉目前的地球鍵互動 |
| B 保留系統 handler，多來源觀測與未知狀態暫停 | 保留原生短按／清單；可處理純版面重排、可確認的文件失效與已收到的有效線索；未知時先停寫 | 是安全的分類骨架，尚非完整解。模式通知投遞、清單結果與交接次序仍須補證據；僅靠同文字恢復會漏掉「切出去再回來但沒打字」 |
| C 未完成注音與字根僅保留在 extension | 減少明確離開時回頭取消 App 內未完成 marked text 的需求；未完成碼不會因失去最後一次回呼而被當普通文字送出 | 需另評估目前傳統／倉頡路徑的行內讀音呈現；會改變部分 UI／文字模型，這輪未採用。只能減少依賴，不解決應保留或清空本地組字的分類缺口 |
| D 自家輸入測試頁面協助觀測 | App 可知道自己的焦點、欄位和 Scene，核對原位置；可測受控換欄位與幾何行為 | 不能替其他 App 取得相同資料。欄位仍聚焦時系統鍵盤清單也可能切換，欄位 delegate 並非清單結果通知；配合測試頁成功不能當成全系統成功 |

A 的「先交接」只在原位置仍有效時成立；若原位置已失效，不能靠快取的 proxy 物件或舊 context 當成鎖。B 必須保留原因未知這個狀態，不能為了把每個案例填成成功而任選一種解釋。C 若將來採用，也不能私自把取消清單或開闔改成清空本地未完成碼。

研究後建議：先把 A 的可控操作、B 的文字有效性與未知狀態分離成設計邊界，再評估 C 是否值得採用；保留系統清單的完整相容性缺口，先補驗證與官方釐清。這不是授權開發，也不宣稱 A＋B＋C 已能完整實現所有規則。

### 不足以採用的替代判定

- 在地球 `.touchDown` 一律確認：取消清單也會結束組字，直接違反已確認規則。
- 在所有 `viewWillDisappear` 一律確認／取消：無法保證開闔與清單取消保留。
- 只看 `primaryLanguage`、模式物件地址或清單數量：公開介面沒有提供可據此識別所有 extension 的穩定身分與切換原因。
- 覆寫 `advanceToNextInputMode` 當作唯一離開通知：公開文件沒有保證每條系統清單路徑必經它。既有最小鍵盤對照已出現「空動作 override 攔住短按，但清單仍能選到別的鍵盤」，本輪未重跑。[既有最小對照](IOS_IPHONE_DUO_ADAPTATION.md)
- 先收鍵盤、消失後再切換：既有帶文字對照未證明真正切換完成；也可能失去舊代理，不能當作完整方案。[既有對照](IOS_IPHONE_DUO_ADAPTATION.md)
- 由琦琦本體代收 hinge，再用時間推斷 extension 原因：本體不擁有其他 App 的前景 Scene，也未獲得系統清單結果；不能補出全系統的事前交接保證。

## 版本與本機宣告核對

最低執行系統仍為 iOS 17。舊通知與基本鍵盤 API 在此下限可用；型別化模式／extension 活動訊息為 iOS 26 起，hinge 與 reserved regions 為 iOS 27.1 起。版本較新不代表通知多了清單結果，也不能在缺少 hinge 資料時推定姿態未變。

本輪逐段核對的公開宣告，在 Xcode 27.1 與本機 27.2 beta 3 相同：

| 比對範圍 | 共同 SHA-256 |
|---|---|
| `UIInputViewController.h` 全檔 | `354abc1b382e6f0d1280922f1cd5a6ace3b8b29409f83f7621218ae05121e26e` |
| `UIHingeInteraction.h` 全檔 | `c24b3add564134e4710369cc32e363687d63a4c7454f30d276959597d9793308` |
| `UITextInput.h` 的 UITextInputMode 註解、class 與模式通知宣告片段 | `bca5308def303bf22b5d084f58eaaacae77d1e66023f2146da1f2e172f4238db` |
| `NSExtensionContext.h` 四個活動通知宣告行 | `4813d40aecfd20e1fe3e5f68b64d36af99b837c4fd6398d5dac8919f8907afca` |
| UIKit arm64 Simulator swiftinterface 的 CurrentInputModeDidChangeMessage 所在 extension 區塊 | `85761180ab0f3978cdcdd4617e8885b54f4db9d8cc759b1b6d0ca06db84ce2a5` |

工具 build 與 header 路徑見[來源清單](IOS_APP_EXTENSION_HOST_APPLE_SOURCES.md#本機工具與-sdk-凍結)。片段相同不代表整個 header 或 UIKit 二進位相同，也不表示兩個 runtime 的投遞行為已驗證。本機 Beta 3 SDK 宣告能凍結公開介面；滾動 RC release notes 仍不能補成 Beta 3 當版行為保證。

## 下一步需要的證據

下列是後續若獲准開發或執行探針時的研究入口，本輪沒有新增探針或測試：

- 來源 keyboard extension、使用鍵盤的 App、測試 runner 各自記錄訊號；不要拿 App 收到的通知替代 extension 收到。
- 觀測順序至少包含模式通知、appearance、document／selection 變化、本地幾何、hinge 與程序／controller 存活；時間只作診斷，不作分類契約。
- 案例至少含同語言鍵盤互換、短按、清單選擇、清單取消、切出未打字即返回、純開闔、同時開闔與切換、換欄位、系統接管密碼欄位及程序重建。
- 獨立查證目標鍵盤真的可輸入；只看琦琦消失或輸入框文字不變不算成功。
- 明確離開只留下已完成文字，不留下原始注音／字根，不自動選候選；取消清單與原工作階段的開闔要能繼續未完成輸入及句中候選。另測只有未完成碼、沒有完成文字的案例。
- 若訊號仍無法區分，記為未知或未符合規則；不要用延遲、清除或偷偷恢復組字把它列成通過。Duo Simulator 的已知 extension 限制與真機結果仍分開記錄。

### 待向 Apple 釐清的具體問題

以下只整理問題，沒有送出論壇、DTS 或 Feedback：

1. keyboard extension 是否有公開、受支援的方式，在系統清單選定另一鍵盤前取得交接機會，並可靠區分取消？
2. 模式變更通知是否保證送到來源 keyboard extension？相對於 proxy 改綁、view 消失與程序暫停的次序是否有契約？同語言鍵盤適用嗎？
3. `handleInputModeList` 的每條短按／清單路徑是否保證呼叫可覆寫的 `advanceToNextInputMode`？現有文件沒有這項承諾，既有對照也顯示路徑不同。
4. Duo keyboard extension 的 hierarchy 是否保證供應 hinge／reserved regions？若因開闔重新建立鍵盤，有沒有可辨識且保留文字工作階段身分的公開訊號？

這些是目前缺少的保證，不是對 Apple bug 或永久不支援的宣告。地球鍵 SIGABRT 與組字分類可行性是兩個問題；本研究沒有判定當機已修復。
