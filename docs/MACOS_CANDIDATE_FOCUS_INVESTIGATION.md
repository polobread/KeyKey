# macOS 候選點擊與焦點中斷

## 已確認的問題與修正範圍

直式與橫式候選原本把選字鍵交給 `CVSendKey`，等待 0.1 秒後用 `CGEventPost` 投遞到當下的全域焦點。這個操作沒有綁定顯示候選時的 IMK client，而且受 macOS 的 PostEvent／輔助使用權限限制。

在獨立 Tart 的真 IMK 宿主，已確認舊版把候選的選字鍵送進新欄位。依使用者同意，只為此 VM 的未修正版暫時開啟輔助使用權限後，以正常候選點擊確認合成選字鍵能送達；再用同一宿主內的原生 100 ms timer 切到 B 欄，並點原候選的第二項。相同條件兩次都在 B 已取得焦點後收到 `keyCode=0`、`characters="2"` 的合成 keyDown，接著 `insertText:"2"`，最終 A 為「你好」、B 多出「2」。修正版用相同計時條件，新欄維持空白，沒有合成選字鍵。

修正限於 macOS frontend：

- 候選顯示時保存原 controller、client、啟用世代、panel、頁碼、本頁內容和選字鍵；保留 owner／client 生命週期。
- 點選時核對這些資料仍有效，直接同步把原 `OVKey` 交給原 controller 的 PV 管線；不使用全域事件、延遲、合成 `NSEvent` 或直接插入候選中文字。
- 原生按鍵與候選點擊共用既有 commit／marked text／候選更新程式。抽出程式的 tokens 忽略空白後與原來相同；普通 `commitComposition:` 與 `_updateClient:` 語意未變。
- hide、候選重繪和啟用世代變動會使舊 binding 失效。點擊不改真實硬體按鍵的 key-up 追蹤。

Rust core、詞庫與產品版號未改。

## Tart 真 IMK 證據

測試使用 macOS 15.6.1、獨立 VM `keykey-focus-before-20261120`，VM 資料及建置產物位於外接 SSD。來源基底為 `e6a0757fd`；未修正與修正版各用不同 namespace 的 App，透過正常 TIS／IMK／NSTextInputClient 輸入。宿主包含兩個獨立 `NSTextView` 和可輸入的原生 `NSAlert` sheet，逐筆記錄時間、欄位、輸入來源、selection、marked range 與送字回呼。F7 僅在此測試宿主排程原生提示，不偽造 IMK 回呼。

| 情境 | 未修正 | 修正後 |
| --- | --- | --- |
| 直式滑鼠點第二候選 | 未授權時 PostEvent 被拒；暫授後可記錄原欄收到合成 `2`，但該控制案例未改變候選 | 正常把原欄「你好」改為「妳好」，沒有額外的選字鍵 keyDown |
| 直式點候選後換欄 | 暫授權後，100 ms 原生 timer 條件兩次都把合成選字鍵 `2` 寫進 B 欄 | 一般連續點擊在原欄完成選字；相同 timer 條件下，失效的舊點擊被取消，B 欄維持空白；原欄失焦僅提交一次 |
| 橫式點第二候選後換欄 | 本輪未另測舊版橫式 | 原欄更新為「妳好」；另一欄既有「你好」保持不變 |
| 純打字、完整音節、原生提示打斷 | 原欄提交一次，提示欄獨立組字，返回可接續輸入，未見重複或編碼亂碼 | 同樣可接續；最終原欄「妳好妳好」、游標 `{4, 0}`，另一欄內容未變 |
| 純打字、未完成 `su`、提示打斷 | 失焦將可見「ㄋㄧ」提交為文字，沒有送進提示欄 | 本輪未另測；普通提交語意未改 |

補測的兩次錯送事件，在 B 的 `becomeFirstResponder` 後約 **108.8 ms、109.1 ms** 出現選字鍵 keyDown，且紀錄均為正確的測試輸入來源、`field=B`、`firstResponder=1`，隨後真的插入「2」。fixture 沒有記候選 mouseDown，因此這些數字是「B 取得焦點至錯送按鍵」的量測，不是點擊到送鍵的精確延遲；0.1 秒延遲本身依 `CVSendKey` 原碼判定。

未授權的第一階段也保留：`tccd` 記錄 `kTCCServicePostEvent` 為 `authValue=0`，導致點選無效；這與授權後確認的跨欄誤送是同一全域送鍵路徑的兩種問題。補測使用者只授權此 VM 的舊 namespace，沒有為修正版或主機授權。權限已在 UI 關閉、輸入來源還原，並停止測試 VM，讓暫授期間的程序一併結束。

修正版的兩種候選皆未授予輔助使用／PostEvent 控制權限。第一輪註冊還遇到來源清單同步及啟用確認逾時，修正版於 VM 重新登入、確認正確 namespace 後才列入驗收。曾出現返回 App 時 TIS／inputContext 均為 ABC 的樣本，列為輸入來源控制因素，不當成 IME 編碼失敗。

候選學習只發生在隔離 VM 的私有資料，所以後續同讀音首位可能由「你好」變為「妳好」；驗證依點擊時實際候選、欄位與回呼判定，不作詞頻或模型準確率結論。未切換、安裝或操作主機使用者正在用的輸入法。

原始證據保留在 `Installer/local-builds/macos-focus-safety-20261120/` 的 `evidence/`、`before-imk/`、`after-imk/` 與 `candidate-regression/`，不提交影片、事件紀錄或建置產物。授權補測另保存 `evidence/permission-repro-*.jsonl`、`permission-repro-tcc.log` 與量測摘要，不覆寫初次未授權紀錄。

## 無 UI 回歸與 CI

```sh
python3 Source/Loaders/OSX-IMK/Tests/run-candidate-selection-tests.py
python3 Source/Loaders/OSX-IMK/Tests/run-input-mode-tests.py
```

候選 suite 抽取正式 target、驗證及 dispatch 方法，以及直式／橫式 action、hide 與翻頁入口；renderer 與 core 邊界使用記錄替身，不建立 IMKServer、不註冊 TIS、不送全域事件。42 個案例通過，涵蓋原 client 一次選字、自訂 ASCII 鍵、分頁、owner／client／世代／內容失效、hide 及同步釋放最後一份 UI binding。此證據與上述真 IMK 測試分開記錄。

既有輸入模式 suite 通過；前端 Release 建置及 namespace／簽章核對通過。新 suite 接入 `package-macos.yml` 的既有隔離測試階段。核心未變，本輪不重跑核心完整矩陣或模型 131 篇計分。

## 尚未確認的情境

「純打字被提示打斷後出現亂碼」未在此次原生 Cocoa 宿主重現，不能宣稱已修好。未完成讀音固定為注音文字，是已觀察到的失焦行為，與 UTF-8／UTF-16 編碼損壞或跨 client 錯送不同；若要改成其他行為，須先確認輸入語意。

本輪沒有證明 Safari、Electron／Codex 或其他真實 App 的特定提示流程皆正常。若再次發生，應保存實際 App、輸入來源、是否有未完成讀音、原欄與新焦點、組字及游標回呼時間，再針對已確認的 frontend 邊界修正，不以假設改寫核心或普通提交流程。
