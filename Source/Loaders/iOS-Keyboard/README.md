# iOS 鍵盤

一般使用者的 App Store 下載、啟用、試打與實體鍵盤操作，請先看[《iPhone、iPad 安裝與使用指南》](../../../IOS_INSTALL.md)。以下是開發與測試資訊。

琦琦注音的 iOS 版：一個 custom keyboard extension，加上帶安裝引導與實體鍵盤編輯器的
容器 App。
首頁會從 container app bundle 的 `CFBundleShortVersionString` 顯示目前版本，避免畫面
版號和 Xcode 的 `MARKETING_VERSION` 失同步。

為熟悉五排標準注音鍵位的使用者保留完整排列與固定 `1–9` 候選位置，讓輸入延續
肌肉記憶。觸控好打注音把已完成的中文字寫入宿主欄位，最近九個音節仍顯示在鍵盤
上方的組字格，可點句中音節重新選字。

鍵盤設定可選「好打注音」或「傳統注音」，新安裝預設好打注音。好打注音以同一份
`KeyKey.db` Bigram 模型連續組句，輸入下一個音節前不必先選字；觸控鍵盤的 Enter／搜尋／
前往會在確認組字後立即執行欄位動作，組字列中間的音節仍可選字。傳統注音維持原本
逐字選字與關聯詞流程。

容器 App 首頁的「輸入法設定」進入與鍵盤「設」頁相同的注音模式、候選字底色、
按鍵音、關聯詞詞庫、自訂詞及學習重設選項。App 將選項寫入 App Group；鍵盤在
下次開啟時唯讀套用。鍵盤「設」頁仍可調整並存入鍵盤私有資料；App 無法讀回
該私有值，所以 App 設定頁顯示的是上次從 App 設定的值。再次從 App 更改該選項
會覆蓋較早的鍵盤私有值。App 送出的學習重設要求也在鍵盤下次開啟時執行。

容器 App 的「管理好打注音自訂詞」可新增、編輯、刪除詞句，也可匯入／匯出 macOS
`MJSR version 1.0.0` 檔案的自訂詞段落。輸入每字一組注音，例如 `ㄋㄧˇ ㄏㄠˇ`，
或用標準鍵位 `su3cl3`。自訂詞存在 App Group，鍵盤只讀取；好打注音在選字及確定
整句後學習候選與相鄰詞關係。因為維持 `RequestsOpenAccess = false`，鍵盤的學習資料
只存於鍵盤自己的沙箱，App 內實體鍵盤編輯器的學習資料也獨立儲存。鍵盤「設」頁可重設
鍵盤學習紀錄；重設不刪自訂詞。macOS 匯出檔內加密的學習資料區塊不會匯入行動版。

![iPhone 備忘錄中已輸入請假要去哪裡玩呢去海邊，鍵盤上方保留最近九個可修改的組字格](../../../docs/images/keykey-ios-v130-smart-typing.png)

實機輸入「請假要去哪裡玩呢去海邊」時，備忘錄欄位已有整句文字；最前面的詞組
「請假」已移出可修改範圍，後面的九個音節仍可點選候選。切換 App 或輸入法時，
已寫入欄位的中文字不會因組字列消失而遺失。

```
KeyKeyEngine/     Swift Package，純邏輯，可用 swift test 在 Mac 上驗
ContainerApp/     容器 App（安裝引導、實體鍵盤編輯器）
Keyboard/         UIInputViewController extension
KeyKeyiOS.xcodeproj
```

## 建置

```sh
make -C ../../Distributions/Takao/DatabaseCooker
xcodebuild -project KeyKeyiOS.xcodeproj -scheme "chichi77 KeyKey" \
  -configuration Debug -destination 'platform=iOS Simulator,name=KeyKey iOS 26 iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

`KeyKey.db` 是建置輸入，但不進版控。Xcode Cloud 會自動執行
`ci_scripts/ci_post_clone.sh` cook 資料庫，並以 `CI_BUILD_NUMBER` 同步容器 App 與
Keyboard extension 的 build number；本機建置維持專案內的預設 build number。

引擎的測試不需要模擬器：

```sh
cd KeyKeyEngine && swift test
```

容器 App 的購買流程測試也可在 Mac 執行；在本目錄執行：

```sh
swift test --scratch-path /tmp/keykey-supporter-flow-tests
```

測試直接編譯 `ContainerApp/SupporterStore.swift`，以替代的商店介面驗證商品載入失敗與
重試、購買／恢復／載入互斥、取消與錯誤後解除忙碌，以及授權快取更新。
此測試套件不加入 keyboard extension 或 `KeyKeyEngine`；仍須另用 Sandbox Apple ID
驗證真實交易與 App Store Connect 商品設定。

首次在一台新機器上需要先取得模擬器 runtime：`xcodebuild -downloadPlatform iOS`。

### 本機 MacBook 心經長文測試

在開發機的 iOS 17 Simulator 執行 shared scheme `chichi77 KeyKey` 的
`KeyKeyHeartSutra.xctestplan`。測試會在乾淨 Simulator 透過「設定」加入並切換到
琦琦注音 keyboard extension，關閉全部關聯詞庫，逐字點完 268 個心經注音字與標點；
每字檢查提交後全文前綴和候選絕對順位，最後在 `.xcresult` 留下 `ios.txt` 與
`ios.positions.tsv` attachments。若鍵盤沒真正啟動會失敗，不能以 skip 當通過。

```sh
python3 ../../../tests/generate_ios_heart_sutra_fixture.py --check
xcodebuild test -project KeyKeyiOS.xcodeproj -scheme 'chichi77 KeyKey' \
  -testPlan KeyKeyHeartSutra -configuration Debug \
  -destination 'platform=iOS Simulator,name=KeyKey iOS 17 iPhone 12' \
  -resultBundlePath "/tmp/keykey-ios-heart-sutra-$(date +%Y%m%d-%H%M%S).xcresult" \
  CODE_SIGNING_ALLOWED=YES
```

測試資料由 `tests/generate_ios_heart_sutra_fixture.py` 從共用原稿及 CIN 產生並編入
UI test。若心經稿或字表變動，先在 repository 根目錄執行
`python3 tests/generate_ios_heart_sutra_fixture.py` 更新它。本機乾淨 iOS 17.0
Simulator 的自動加入及切換已有 2/2 測試通過；iOS 26.5 Simulator 雖能加入鍵盤，
但既有切換測試被系統略過。這個完整測試保留給開發機執行，不列入 Xcode Cloud。

送審用的 iPhone 16 Plus 實機錄影步驟見
[`APP_REVIEW_RECORDING_PLAN.md`](APP_REVIEW_RECORDING_PLAN.md)。

## 與其他平台的差異

- **引擎是 Swift 重寫**，不載入 `Source/Frameworks` 的 C++ core。
- **但資料層走已 cook 好的 `KeyKey.db`**，不像 Android 在執行時解析 `.cin`。
  keyboard extension 的記憶體上限約 60 MB，超過會被系統直接終止且沒有 crash
  log；SQLite 只映射查詢用到的頁，資料層常駐足跡不到 1 MB。
- `Mandarin-bpmf-cin` 的 key 是 Formosa 的 absolute-order 編碼，不是鍵盤按鍵，
  所以 `BopomofoSyllable` 必須實作該編碼才查得到東西。
- **`RequestsOpenAccess = false`**：不連網，鍵盤可唯讀 App Group 的設定，
  鍵盤內修改的設定與學習資料則存在 extension 自己的沙箱。代價是
  iOS 把 `UIFeedbackGenerator` 綁在這個權限後面，因此沒有按鍵震動。
- **keyboard extension 沒有實體鍵盤支援與浮動候選窗**：extension 收不到硬體按鍵
  事件，也只能在自己的 input view 內繪製。容器 App 的「實體鍵盤編輯器」只能在琦琦
  App 前景接收 USB／藍牙鍵盤，不能讓琦琦在備忘錄、LINE 或 Safari 內接管實體鍵盤。
- **inline 組字**：好打注音把已組好的中文字即時寫入 App，並只保留最近九個音節
  作為可修改範圍；超出範圍的詞留在 App，不再受退格或選字影響。切換 App 或輸入法時，
  尚未完成的讀音也會先送到 App。傳統注音使用 `UITextDocumentProxy.setMarkedText`
  標記目前讀音，選字時以候選字取代讀音。
- **欄位動作**：觸控好打注音有組字時，第一次按 Enter／搜尋／前往就先確認剩餘讀音，
  再對宿主送出換行或欄位動作；已寫入欄位的中文字不會再插入一次。
- 會讀取 `textDocumentProxy.keyboardType` 的 11 種 UIKit 提示。`default`、URL 與
  `webSearch` 一開始就提供完整注音／英文／數字模式，URL 可直接輸入中文搜尋；ASCII、
  Email 與姓名電話鍵盤先用英文精簡模式，數字符號、數字、電話、小數與 ASCII 數字鍵盤
  先用數字精簡模式。不適用的鍵會淡化並停用，但 MODE 保持可按；第一次按 MODE 後即解除
  該輸入欄位的提示限制，切回完整三模式與全部功能，直到離開該欄位。
- 英文小寫按 Shift 後，字母改為大寫，末四個符號也依序由 `; , . /` 改為
  `: < > ?`。
- **密碼與電話欄位是 iOS 系統限制**：第三方鍵盤不會出現在 secure text field、
  `phonePad` 或 `namePhonePad`，系統會自動換回內建鍵盤。引擎仍保留這三種映射，方便
  測試與處理 host 實際提供相同 trait 的情況，但 extension 無法繞過系統封鎖；App 也能
  選擇全面禁止第三方鍵盤。
- 候選選取底色可在鍵盤的「設」中選擇紫、綠、黃、紅；預設為與 macOS 相同的紫色，
  黃底自動使用黑字，其餘使用白字。設定重開 extension 後仍會保留。
- 容器 App 提供產品 ID `chichi_supporter` 的非消耗型一次性支持。未購買不會鎖住任何
  輸入功能；首次使用滿 30 天後，注音鍵盤只會在尚未輸入、沒有候選字時顯示
  「歡迎付費支持」。購買或恢復購買成功後，容器 App 透過 App Group
  `group.io.github.polobread.inputmethod.chichi77.ios` 將授權快取給 extension，提示便會
  永久隱藏。實際售價由 App Store 依地區顯示，設定頁也提供 Apple 要求的「恢復購買」。

## 實體鍵盤編輯器

容器 App 直接唯讀內嵌 `Keyboard.appex` 的同一份 `KeyKey.db`。從首頁「輸入法設定」
調整的注音模式與關聯詞詞庫也會在下次開啟編輯器時套用；編輯器內調整的值則存在
容器 App 自己的 `UserDefaults`。
編輯中的文字留在 App 內，只有使用者主動按下複製或分享時才交給 iOS 系統功能。

- 候選固定直排 `1–9`，一般候選用 `1–9`，關聯詞用 `Shift+1–9`
  （`!@#$%^&*(`）。好打注音下可連續輸入下一個音節，數字列不會搶先選字；
  `Space` 開啟目前音節的候選後才用 `1–9` 選字，候選開啟後 `Space`、`Page Up`、
  `Page Down` 可循環翻頁，`Enter` 確定整句。組字最多保留十個音節；第十一個音節完成時，
  會和 macOS 一樣把最前面的完整詞段送到編輯器文字區，例如一起擠出「請假」。
- 一般候選用 `↑`／`↓` 移動反白、`←`／`→` 翻頁；沒有組字與候選時，四方向鍵移動
  編輯器自己的可見插入游標。
- `Ctrl+Space` 切換ㄅ／英、`Shift+Space` 切換半／全形；`Ctrl+0`／`Ctrl+1` 開啟符號，
  `Ctrl+,`／`Ctrl+.` 輸入全形逗號／句號。
- `Ctrl+C`／`⌘C` 複製全文，`Ctrl+S`／`⌘S` 開啟分享面板，`Ctrl+K`／`⌘K` 開啟
  清除全文確認，並以 Enter 確認、Esc 取消。右上角資訊按鈕也列出完整快捷鍵。
- 右側提供詞庫、ㄅ／英、半／全、符號、`🙂`、Esc、Backspace、Enter、四方向與空白等
  觸控備援鍵。關聯候選顯示時，Enter 會先關閉推薦再換行，不會誤選反白詞尾。
- 虛擬鍵盤與 App 內實體鍵盤編輯器的 Backspace 按下時先刪一次；持續按住約
  450 毫秒後開始連續刪除，逐步加快但最多約每 70 毫秒一次。放開時立即停止，
  虛擬鍵盤的按鍵預覽也會收起。
- 橫式固定由左到右排列輸入、候選、按鍵、清除／複製／分享四欄；iPad 保留方向鍵與
  空白鍵，iPhone 高度不足時收起這組輔助鍵。4.7 吋 iPhone SE 直式會縮短輸入區，保留
  完整候選與操作鍵。候選內容與裝置旋轉不應改變各區塊的固定尺寸。

![iPhone 實體鍵盤編輯器中請假已成為黑字，後段仍以紫色底線組字](../../../docs/images/keykey-ios-v130-hardware-editor-boundary.png)

實機畫面中的「請假」已由長句輸入擠出；其後的組字可移動游標，並在候選列修正
「邊」等句中音節。使用者操作步驟見[安裝與使用指南](../../../IOS_INSTALL.md)。

正式簽署前，Apple Developer 帳號必須建立上述 App Group，並同時指派給容器 App
`io.github.polobread.inputmethod.chichi77.ios` 與 keyboard extension
`io.github.polobread.inputmethod.chichi77.ios.keyboard`。StoreKit 查詢、驗證與交易監聽只在
容器 App 執行；extension 只讀本機 entitlement cache，不會在輸入路徑連線。

`KeyKeyiOS.xcodeproj/xcshareddata/xcschemes` 內的 scheme 必須保留在版控中 ——
Swift Package 依賴只有透過 scheme 才會被建置，`-target` 不會。

## 授權

本目錄的原創 iOS frontend 程式碼以 MIT License 釋出，著作權為
Copyright (c) 2026 Chui-Ping Cheng。打包進 extension 的 `KeyKey.db` 維持其
輸入資料的原授權。完整範圍見本目錄的 `LICENSE.txt` 與 repository 根目錄的
`LICENSING.md`。
App 內的「授權與致謝」會顯示二進位散布所需的完整授權條款。
