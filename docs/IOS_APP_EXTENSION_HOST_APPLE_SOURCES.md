# iOS 架構審查的 Apple 來源與版本清單

查閱日期：2026-10-23。對應[架構審查](IOS_APP_EXTENSION_HOST_REVIEW.md)與[狀態矩陣](IOS_APP_EXTENSION_HOST_STATE_MATRIX.md)。範圍為三種角色用到的 API、相關 OS／SDK 行為、螢幕與工具限制；不是把所有無關 Apple frameworks 都列為已審查。

現行 API 文章以 Apple 提供的 `.md` 正文閱讀；表中保留一般文件網址供瀏覽器開啟。影片使用相關章節的官方逐字稿；範例閱讀說明與 API 使用方式，本輪沒有下載建置或執行範例。舊 Extension Programming Guide 作歷史架構參考，遇到現行鍵盤文件不同時不直接套用舊限制。

## 官方來源索引

| 編號 | 官方來源 | 核對範圍與使用界線 |
|---|---|---|
| A01 | [Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard) | 獨立程序、宿主可以是 containing app、寬度可在顯示中變化、浮動鍵盤、隱藏不一定結束程序、記憶體限制依裝置不同 |
| A02 | [Configuring a custom keyboard interface](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface) | 系統決定寬度、高度可用 constraint；欄位類型與系統接管；收鍵盤與含容器 App 的分工 |
| A03 | [Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) | 未開 Full Access 仍可讀 App Group；寫入 shared container 與網路能力需另外授權 |
| A04 | [Handling text interactions in custom keyboards](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards) | proxy 插入、刪除、context、selection 與 nil delegate 參數；marked text 及 unmark 語意 |
| A05 | [UIInputViewController](https://developer.apple.com/documentation/uikit/uiinputviewcontroller) | keyboard extension 主要 controller；代理、切換與隱藏入口 |
| A06 | [UITextDocumentProxy](https://developer.apple.com/documentation/uikit/uitextdocumentproxy) | 介面能力、traits、context、marked text 與文件身分的範圍 |
| A07 | [documentIdentifier](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/documentidentifier) | 區分文件；沒有承諾它能識別同文件的選取或交易 |
| A08 | [setMarkedText](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/setmarkedtext(_:selectedrange:)) | 取代既有 marked text；否則作用於目前 selection |
| A09 | [documentContextBeforeInput](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/documentcontextbeforeinput) | 可得的是目前插入點前的 optional context，不能據此宣稱擁有完整文件 |
| A10 | [needsInputModeSwitchKey](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/needsinputmodeswitchkey) | 系統要求 custom keyboard 提供切換鍵的屬性 |
| A11 | [handleInputModeList](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/handleinputmodelist(from:with:)) | 長按／上滑清單與短按切換；A01 的範例用 `.allTouchEvents` |
| A12 | [dismissKeyboard](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/dismisskeyboard()) | extension 不直接呼叫宿主欄位的 resignFirstResponder |
| A13 | [becomeFirstResponder](https://developer.apple.com/documentation/uikit/uiresponder/becomefirstresponder()) | 請求可能失敗；active hierarchy、key window 與硬體／軟體鍵盤條件 |
| A14 | [Handling key presses made on a physical keyboard](https://developer.apple.com/documentation/uikit/handling-key-presses-made-on-a-physical-keyboard) | active App 的 responder chain；處理與轉送 presses 的責任 |
| A15 | [playInputClick](https://developer.apple.com/documentation/uikit/uidevice/playinputclick())、[UIInputViewAudioFeedback](https://developer.apple.com/documentation/uikit/uiinputviewaudiofeedback) | 系統標準 click 的可見性、設定與 protocol 條件；不混同任意 speaker 能力 |
| B01 | [App Extension Programming Guide 的架構章](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html) | extension、host、containing app 的歷史概念；通用 request 生命週期不能直接當鍵盤每次隱藏的規格 |
| B02 | [舊 Custom Keyboard 章](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) | 歷史基礎與畫面界線；共享存取敘述依 A03 校正，避免把舊「不能共享」解讀成現行不能唯讀 |
| B03 | [Transitioning to the UIKit scene-based life cycle](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle) | App 程序與 Scene 分工；靜態／動態設定；多 Scene 選用；新 SDK 要求 |
| B04 | [Managing your app’s life cycle](https://developer.apple.com/documentation/uikit/managing-your-app-s-life-cycle) | Scene 與 App 狀態處理的相關段落；不套成 extension 的 AppDelegate 生命週期 |
| B05 | [UIWindowScene](https://developer.apple.com/documentation/uikit/uiwindowscene) | 視窗所屬 Scene 與其幾何、畫面、生命週期責任 |
| B06 | [viewIsAppearing](https://developer.apple.com/documentation/uikit/uiviewcontroller/viewisappearing(_:))、[viewWillDisappear](https://developer.apple.com/documentation/uikit/uiviewcontroller/viewwilldisappear(_:)) | appearance 的幾何有效時點與消失前可提交編輯的責任；與文件身分及反覆 layout 分開 |
| B07 | [Adapting your app when traits change](https://developer.apple.com/documentation/uikit/adapting-your-app-when-traits-change) | 指定 traits 註冊、初始更新與自動追蹤的使用方式 |
| B08 | [Automatic trait tracking](https://developer.apple.com/documentation/uikit/automatic-trait-tracking)、[layoutSubviews](https://developer.apple.com/documentation/uikit/uiview/layoutsubviews()) | 支援的更新方法；iOS 18 起自動追蹤不能直接當成 iOS 17 行為 |
| B09 | [UIKeyboardLayoutGuide](https://developer.apple.com/documentation/uikit/uikeyboardlayoutguide)、[官方配置範例](https://developer.apple.com/documentation/uikit/adjusting-your-layout-with-keyboard-layout-guide) | 宿主避讓固定／浮動／未固定鍵盤、tracking constraints 與本視窗相交區域 |
| B10 | [safeAreaInsets](https://developer.apple.com/documentation/uikit/uiview/safeareainsets) | 本地 insets、未進入可見階層的零值；不能當全域裝置常數 |
| B11 | [UserDefaults.didChangeNotification](https://developer.apple.com/documentation/foundation/userdefaults/didchangenotification) | 目前程序的變更通知；不能宣稱它保證跨程序設定即時同步 |
| C01 | [WWDC23 Keep up with the keyboard](https://developer.apple.com/videos/play/wwdc2023/10281/) | 1:29 起的 iPhone iOS 17 鍵盤程序重構與非同步時序，及 3:47 起的多視窗／避讓 |
| C02 | [WWDC24 What’s new in UIKit](https://developer.apple.com/videos/play/wwdc2024/10118/) | automatic trait tracking 與文字互動相關章節；確認 iOS 18 的功能界線 |
| C03 | [WWDC25 Elevate the design of your iPad app](https://developer.apple.com/videos/play/wwdc2025/208/) | 版面縮放、window controls 與保持狀態的相關章節；不是要求本產品變成多文件 App |
| C04 | [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/) | SDK linked-on 差異、traits、screen assumptions、safe area、系統容器與 regions |
| C05 | [Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/) | reserved regions、displacement、arrangement 的相關章節；不將 App 範例直接視為 extension 回呼保證 |
| C06 | [Leverage multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/) | hinge 的用途、視窗與多顯示器；資料互動與 layout API 分工 |
| C07 | [HIG Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) | 裝置姿態、可調尺寸、折線、非對稱安全區與側邊控制 |
| C08 | [HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout) | 空間條件、size class、Dynamic Type 與縮放的設計建議 |
| C09 | [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | 文字可讀性、VoiceOver 與控制項可操作性的相關段落；不以固定一個 pt 值代替鍵盤可用性驗證 |
| C10 | [UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction)、[UIHinge](https://developer.apple.com/documentation/uikit/uihinge) | view hierarchy 的資料供應、nil、status、角度與更新限制；以公開 SDK 補足宣告 |
| C11 | [reservedRegions](https://developer.apple.com/documentation/uikit/uiview/reservedregions(kind:options:)) | 本地座標、active／inactive、區域變更與配置觸發 |
| C12 | [UIArrangementViewController](https://developer.apple.com/documentation/uikit/uiarrangementviewcontroller) | UIKit 新容器與 split／overlay；不是 keyboard extension 的模式切換方法 |
| D01 | [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes) | Swift 6.4 與 SDK 27 的組合；compiler 版本不能代替 SDK 檢查 |
| D02 | [Xcode 27.1 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes) | SDK 組合與 Duo Simulator 限制，尤其 `187708767` |
| D03 | [Xcode 27.2 rolling release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes) | 查閱時為 RC；只作版本差異線索，不當作 Beta 3 凍結規格 |
| D04 | [iOS 與 iPadOS release notes 索引](https://developer.apple.com/documentation/ios-ipados-release-notes) | 下表 23 份公開文件的 UIKit／keyboard／Simulator 與相關 SwiftUI 輸入、視窗段落 |
| D05 | [Device Hub 操作文件](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub) | Closed／Partially Open／Open、方向與操作介面；工具可操作範圍仍另確認 |
| D06 | [XCUIScreen](https://developer.apple.com/documentation/xcuiautomation/xcuiscreen) | active screens 與 main screen 的區別；所有螢幕截圖入口 |
| D07 | [Duo 地球鍵的 Apple DTS 回覆](https://developer.apple.com/forums/thread/849736) | Apple staff 確認 false 回報錯誤與切換入口責任；沒有確認本案 SIGABRT 根因 |

## 版本時序與適用條件

| 執行系統或工具世代 | 本次確認的相關變化 | 對目前實作的意義 |
|---|---|---|
| iOS 17 | Apple 在 iPhone 將系統鍵盤主要移出 App 程序；新增 trait 註冊方式；keyboard layout guide 有更多控制選項 | 不能假設同步文字時序。最低 17 可以使用目前的 trait registration；extension 本來就有自己的程序，不是 17 才獨立 |
| iOS 18 | 在支援的 view／controller 更新方法內有 automatic trait tracking | 17 路徑仍需明確更新或註冊；不是所有 method 都自動追蹤 |
| iOS／iPadOS 26 | 可調視窗與新控制區域擴大情境；`updateProperties`、新 geometry 回呼等 API 可用 | `.pad` 不代表固定大視窗。舊 scene orientation／coordinateSpace 存取開始被新 effectiveGeometry 介面取代，但不等於舊 OS 路徑可以直接刪除 |
| iOS／iPadOS 26.4 | UIKit notes 列出 keyboard notification 可能未送出的修正 `165479264` | 是特定問題紀錄，不證明本案缺鍵盤的原因或保證所有通知順序 |
| iOS／iPadOS 27 | 用最新 SDK 建置的 App 要採 Scene lifecycle；有 launch screen 要求；presented controller 的 trait 傳遞與可調視窗規則有 linked-on 變更 | 現有 App 有靜態 scene manifest 與 `UILaunchScreen`。Scene lifecycle 與支援多 Scene 是兩件事 |
| iOS 27.1 與 Xcode 27.1 | Duo 支援；hinge／reserved-region／arrangement API；iOS 27.1 SDK，其他 OS 的 SDK 並非一律 27.1 | 新能力必須有 SDK 宣告與 runtime 支援。大部分新 API 沒有文件保證 extension 取得與宿主一樣的資料 |
| 本機 Xcode 27.2 beta 3 所附 SDK | canonical name 為 `iphonesimulator27.2`，並非目前 Duo 的 27.1 runtime | 能使用哪些公開宣告可從本機 SDK 凍結；不能由此宣稱已測 iOS 27.2 beta runtime |
| 官方目前回傳的 27.2 RC 文件 | 已晚於本次要研究的 Beta 3 節點 | 只列作後續版本資料；不能把其 Device Hub 修復、已知問題狀態倒填成 Beta 3 結論 |

基礎 API 可能早於 17：這不妨礙在最低 iOS 17 使用。重點是「在每個受支援 runtime 上能否使用」及「當版 SDK 是否宣告」，而非只看文件最新頁面的措辭。

### 核心公開 API 的版本界線

下表以本機兩版 SDK 的 UIKit 公開 headers 交叉核對；與目前部署下限 17.0 一起閱讀。

| API | 宣告版本 | 使用條件與責任 |
|---|---|---|
| `UIInputViewController` | iOS 8 | systemwide keyboard extension 入口 |
| `handleInputModeList` | iOS 10 | `.allTouchEvents` 接線；不是自行模擬 UIEvent |
| `needsInputModeSwitchKey`、`documentIdentifier` | iOS 11 | 主動切換入口與文件識別；不是游標識別 |
| proxy 的 `setMarkedText`／`unmarkText` | iOS 13 | 操作目前文件與 selection；要保護跨欄位交接 |
| `viewIsAppearing` | iOS 13 | 已接到 hierarchy、traits／geometry 更新的 appearance 時點 |
| `UIKeyboardLayoutGuide` | iOS 15 | 宿主避讓；`usesBottomSafeArea`、`keyboardDismissPadding` 為 iOS 17 |
| `UIWindowScene.effectiveGeometry` | iOS 16 | 讀目前 resolved geometry；其 `coordinateSpace` 為 iOS 26 |
| `registerForTraitChanges` | iOS 17 | 只監聽指定 traits；初始配置仍須安排 |
| 更新方法內的 automatic trait tracking | iOS 18 | 只在官方支援的方法；見 C02 與 B08 |
| `updateProperties`、`didUpdateEffectiveGeometry` | iOS 26 | 不可未隔離就代替所有 iOS 17 路徑 |
| `UIHingeInteraction`、`UIHinge`、`UIView.ReservedRegion` | iOS 27.1 | 資料屬 view hierarchy；可用性宣告不等於 extension 保證有回呼 |
| `UIArrangementViewController`、split／overlay arrangement | iOS 27.1 | UI 容器的選項，不是採用 Duo 的必要開關，也不是系統鍵盤分離控制 |

## 公開 release notes 的核對清單

由 D04 索引取得下列 23 份文件。檢索及閱讀的重點為 UIKit、Keyboard／Keyboards、Simulator，以及 SwiftUI 的文字、焦點、safe-area、Scene 與 window 相關段落；沒有相關條目不表示沒有 bug。SwiftUI 變更用來辨認外部宿主環境，不能直接套成目前 UIKit 實作已受影響。

| 文件 | 與本案相關的閱讀結果 |
|---|---|
| [iOS 與 iPadOS 27.2](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27_2-release-notes) | 查閱時為 RC；Simulator clone 問題與 UIKit margins 條目只作後續版本線索 |
| [iOS 與 iPadOS 27](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes) | Scene／launch screen、presented traits 與 resize／screen 行為 |
| [iOS 與 iPadOS 26.6](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_6-release-notes) | 未找到需改變本輪核心責任模型的對應條目 |
| [iOS 與 iPadOS 26.5](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_5-release-notes) | 未找到需改變本輪核心責任模型的對應條目 |
| [iOS 與 iPadOS 26.4](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_4-release-notes) | UIKit 列出 keyboard notification 修正 165479264 |
| [iOS 與 iPadOS 26.3](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_3-release-notes) | 未找到需改變本輪核心責任模型的對應條目 |
| [iOS 與 iPadOS 26.2](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_2-release-notes) | 未找到需改變本輪核心責任模型的對應條目 |
| [iOS 與 iPadOS 26.1](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_1-release-notes) | 鍵盤變音字選擇修正；SwiftUI focus 條目不直接套為 UIKit bug |
| [iOS 與 iPadOS 26](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26-release-notes) | 鍵盤顯示／旋轉修正；UIKit layout 與文字欄位的變更 |
| [iOS 與 iPadOS 18.6](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-18_6-release-notes) | 未找到需改變本輪核心責任模型的對應條目 |
| [iOS 與 iPadOS 18.5](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-18_5-release-notes) | 未找到需改變本輪核心責任模型的對應條目 |
| [iOS 與 iPadOS 18.4](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-18_4-release-notes) | 另以 B03 核對 Scene 遷移警告的起始版本 |
| [iOS 與 iPadOS 18.3](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-18_3-release-notes) | 未找到需改變本輪核心責任模型的對應條目 |
| [iOS 與 iPadOS 18.2](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-18_2-release-notes) | 相關段落沒有本案地球鍵或 hinge 的保證 |
| [iOS 與 iPadOS 18.1](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-18_1-release-notes) | 相關 SwiftUI Scene 修正不直接套為目前 UIKit 行為 |
| [iOS 與 iPadOS 18](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-18-release-notes) | 鍵盤設定／extension 加入刪除及 Simulator 相關修正 |
| [iOS 與 iPadOS 17.6](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-17_6-release-notes) | 未找到需改變本輪核心責任模型的對應條目 |
| [iOS 與 iPadOS 17.5](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-17_5-release-notes) | 未找到需改變本輪核心責任模型的對應條目 |
| [iOS 與 iPadOS 17.4](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-17_4-release-notes) | 相關 SwiftUI safe-area／popover 條目；不直接套為本案根因 |
| [iOS 與 iPadOS 17.3](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-17_3-release-notes) | 未找到需改變本輪核心責任模型的對應條目 |
| [iOS 與 iPadOS 17.2](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-17_2-release-notes) | 未找到需改變本輪核心責任模型的對應條目 |
| [iOS 與 iPadOS 17.1](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-17_1-release-notes) | 未找到需改變本輪核心責任模型的對應條目 |
| [iOS 與 iPadOS 17](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-17-release-notes) | UIKit 的 SDK linked-on 輸入行為；非同步鍵盤架構以 C01 補足 |

27.2 該列是查閱時可取得的 RC 正文，不計為 Beta 3 當版已知問題審查完成。官方索引沒有提供獨立 iOS／iPadOS 27.1 release notes 入口；直接嘗試的同名路徑為 404，因此 27.1 由 Xcode 27.1、公開 SDK 與 Duo 官方文件交叉支撐，不自行填寫一份不存在於本次來源的發行說明。

## 本機工具與 SDK 凍結

| 項目 | 實際讀取的 metadata |
|---|---|
| 程式基準 | `c5e04e5c3b2586e9fdf099b9e2bd7c20b43b17f8` |
| App／extension 最低執行版本 | Xcode project 的 `IPHONEOS_DEPLOYMENT_TARGET=17.0` |
| 裝置 family | `TARGETED_DEVICE_FAMILY=1,2`；不是把 Duo 的 `.phone` 變成 `.pad` |
| Xcode.app | `version.plist`：27.1，build `27A9275`；Simulator SDK `iphonesimulator27.1` |
| Xcode-27.2-beta3.app | `version.plist`：27.2，build `27B5038j`；Simulator SDK `iphonesimulator27.2` |
| 既有 Duo 執行證據 | iOS 27.1 build `24A94232`；資料來自既有測試紀錄，本輪未啟動或操作裝置 |

本文件中的「Beta 3 SDK」特指本機 `Xcode-27.2-beta3.app`、build `27B5038j` 所附 SDK。資料夾名稱不拿來推定 iOS runtime 的 beta 輪次。

公開 header 位置為兩個 Xcode 安裝目錄下的 `Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/System/Library/Frameworks/UIKit.framework/Headers/`。以下檔案在兩版中逐 byte 相同，記錄共同 SHA-256：

- `UIInputViewController.h`：`354abc1b382e6f0d1280922f1cd5a6ace3b8b29409f83f7621218ae05121e26e`
- `UIInputView.h`：`83b8221db4de3a56b1823de92e57cc106aff8152c3fcc6efb5a3d37072db699a`
- `UIKeyboardLayoutGuide.h`：`a011b6a649fe4641604b15366bb0d57b0af8ed966e432ba222929188d615ee5a`
- `UIWindowSceneGeometry.h`：`ebaf041f9d8311ab193403ef0a2005dd7bfdcceadfae4e37486abea8074a687b`
- `UIHinge.h`：`f2d0bc6590644c7444be638a9b35f9b697899872d9630adfe3a03570feaca406`
- `UIHingeInteraction.h`：`c24b3add564134e4710369cc32e363687d63a4c7454f30d276959597d9793308`
- `UIViewReservedRegion.h`：`e245a0c635645ccc50c0f19a90d7b259b36195b80a9dd1addd95de2dad2505ec`
- `UIArrangementViewController.h`：`dbd0c34812be66b5f05d0858e3626b61981302f6d212ece24de5b261bfd4e339`
- `UISplitArrangement.h`：`901f5b57a6773d08b7054ea830d53471bed338e9d0029de0e70a45258b4c7472`
- `UIOverlayArrangement.h`：`33bd541514824cb63e88d80799384b28aeb5cf9b9718a07fd6041055af3bb8ae`

另外檢視了 `UIView.h`、`UIViewController.h`、`UITraitCollection.h`、`UIWindowScene.h`、`UIScene.h`、`UIScreen.h` 與 XCUIAutomation 的 `XCUIScreen.h`。UIView／UIViewController headers 有其他文字差異；沒有將文字 diff 直接當作某 API 已刪除或 runtime 行為改變的證明。

header 相同只證明這些公開宣告相同，不代表 UIKit 二進位、Simulator 服務、宿主連線或 ABI 行為相同。這也是「換 SDK 後是否還崩」與「API 定義是否不同」必須分開的原因。

## 文件內容差異的處理

- 舊 Custom Keyboard 文件對共享資料的敘述較粗略；本輪以現行 A03 明確寫出的「可唯讀共享容器、寫入另需 Full Access」解釋目前權限。
- A02 有將 traits 的 protocol 關係簡化到 controller 的敘述；公開 header 顯示 controller 採 `UITextInputDelegate`，實際欄位 traits 從 proxy 取得。現有程式取 `textDocumentProxy.keyboardType`，不因文件簡化敘述而判錯。
- Duo 教材中用 hinge 驅動互動的範例，不能代替 UIHingeInteraction 對 view hierarchy 與 nil 的精確定義。無資料不直接判為「硬體沒有 hinge」或 fullyOpen。
- Scene 遷移文章的檢查條列容易被讀成必須同時實作 manifest 與動態 configuration method；同一文章的完整範例與說明則提供靜態 manifest 或動態配置路徑。現況是前者。
- HIG 的 navigation 容器與 arrangement 層級建議，和 arrangement API 對 split／tab 容器巢狀的限制需要一起讀。若未來選擇重構為 arrangement，先核對目標容器組合與官方範例；本輪沒有建議直接套用到所有 App 畫面或 keyboard extension。
- A01 連出的舊 `onscreen-keyboards` HIG 路徑在本輪直接讀取為 404；設計依據改用可讀的 A02、C07–C09，不宣稱該失效頁已完整閱讀。

## 版本資料缺口

1. **27.2 beta 3 當版 release notes。** 官方 Xcode 27.2 與 OS 27.2 的同網址回傳 RC 題名，沒有可驗證的當版凍結內容。URL 上的 `changes` 參數與搜尋快取不是版本封存證據。Beta 3 的公開 API 宣告已用本機 SDK 核對；當版修復／已知問題清單仍缺，不用 RC 內容補成已知事實。
2. **27.1 的 extension 已知限制範圍。** `187708767` 明列「多數 extension」，未逐一列出 custom keyboard。不能宣稱鍵盤完全不支援，也不能忽略這項限制後以此模擬器作唯一發布驗收。
3. **keyboard extension 的 hinge／regions 資料保證。** 查閱的公開宣告沒有 extension-unavailable 標記，但未找到保證與宿主同資料的文字。既有 Simulator 缺回呼只屬該環境證據；真機與官方釐清尚待後續。
4. **本案 SIGABRT 的官方狀態。** DTS 的 false 回報確認不包含 `activationIndicatorView` 的根因或修補承諾；目前不宣稱已有 Apple acknowledgment。

本輪回傳的兩份 rolling notes 題名與 SHA-256 可用來辨認此次讀到的正文，不能作為 Beta 3 發布檔：

- [Xcode 27.2 RC Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)：`533bdc870b212b81480b127f0ab37e9cd72b416dbd64e2e38e7315be4ae976f3`
- [iOS & iPadOS 27.2 RC Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27_2-release-notes)：`627fea47544a5e836ee319cc57a03c80dbd0d104d4547244fbb16af7eeed63d2`

以上缺口不以測試命令、網路搜尋摘要或推測補成官方契約。研究報告已能提供角色與 API 定義的對照；若要據此開發相容處理，須先確認缺口對該修補的影響與[驗證入口](IOS_APP_EXTENSION_HOST_STATE_MATRIX.md#後續驗證方案)。
