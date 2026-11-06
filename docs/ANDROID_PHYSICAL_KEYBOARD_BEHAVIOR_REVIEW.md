# Android 實體鍵盤行為差異調查

## 範圍與證據層級

本輪五項已獲使用者明確同意的接合修正已實作；13 項 Android 模擬器原生／宿主回歸與 6 項聚焦 JVM 測試通過。Pixel 11 接上 USB Ducky One2 SF RGB 後，
在垂直／水平浮窗與底部候選的原生測試中出現殘留浮窗，已中止操作並保存畫面、視窗、按鍵來源與宿主狀態。
手機的 App 設定與測試前保存的使用者學習 DB 已還原，候選殘窗確認為 0。
真正 USB 按鍵的人工對照尚未執行，不能把注入事件稱為 USB 傳輸驗收。

後續比較使用兩個 `hw.keyboard=yes` 的 Android 17／API 37、Pixel_9_Pro_XL 唯讀 AVD：

- 目前 Android 版本：工作分支 `codex/ios-iphone-duo-adaptation`，調查開始時 HEAD `3055d4e14632b2589dd0710e327b2d1ddc290616`；APK SHA-256 `31b8f500e92bd107f231fc00f5b4d9ae126bdbc0408cf7c7e9c53398fae408fd`。
- 舊 Java 核心：首次導入雙核心前的 `185f5dcde4722100879055fdd8285ad9eee2088d`。
- 相同測試模型：目前 APK 的 `assets/KeyKey.db`，SHA-256 `cbe2e1018842797610b71a4f4b479332aa4508b32df629dd0ad7fa8075ee6c7c`。舊 APK 正常通過自身原始驗證建置，A/B 執行時只在臨時模擬器私有快取換成此模型；不修改正式 DB 或 cooker。
- 舊版 debug 測試宿主的旋轉保留設定與目前宿主一致，避免 Activity 重建清空輸入框；舊核心與 IME 產品碼不改。
- 每個獨立案例清空臨時 App 資料與學習狀態。輸入經 Android 系統 KeyEvent，Enter 另以 `InputManagerGlobal` 分開注入 KeyDown／KeyUp。Emulator console 的 EV_KEY 在此輪未驗證成功送達，不列入有效證據。
- macOS 比對依現有 adapter 與保留的 Manjusri 行為來源，未重新操作真實 IMK 宿主。

## 修正前已確認的行為

下表保留修正前的 A/B 結果，不能當成修正後狀態。

| 項目 | 重現 | 舊 Android | 目前 Android | 判讀 |
|---|---|---|---|---|
| 句中選字目標 | 輸入「你好」，左移成「你｜好」，下鍵開候選，按 2 | `你郝` | `妳好` | 候選目標由游標右側變成左側，屬接合設定回歸 |
| 句尾選字範圍 | 「你好｜」下鍵開候選、按 2 | `你郝` | `妳好` | 新映射也改變句尾候選的詞段範圍 |
| 選字後插入 | 前項選完再輸入 `ㄇㄚ` | `你郝媽` | `妳媽好` | 選字目標與選後游標策略連動改變 |
| 組字中Delete（游標右側） | 「你｜好」按 Delete，再輸入 `ㄇㄚ` | 先 `你`，後 `你媽好` | 先 `你`，後 `你媽好` | 兩版皆有，宿主刪字未同步核心讀音，下一次重畫舊字回來 |
| 旋轉浮窗 | 開候選後旋轉、再轉回 | 也可殘留多窗 | 已觀測 1 → 2 → 3 個候選窗 | 既有 Android 視窗生命週期問題，不能單歸因於 Rust 演算法 |
| Enter 按放 | 輸入「你好」，分開按下與放開 Enter | Down 保持原欄，Up 跳到 Email | 同左 | IME 處理 Down 後原始 Up 透傳，造成欄位導航；不是 Backspace 直接失效的證據 |

最後一項的後續 Backspace 實際送往空白 Email 欄，所以原欄「你好」保持不變。
原生探索性測試若固定檢查原欄，會把這個現象誤記成退格未刪字。
倉頡打完完整碼後的關聯詞，也必須與尚未選取的字根候選分開，不能把普通數字當成關聯詞選字。

句首、句中、句尾的 Backspace 與後續插入，在乾淨學習狀態下兩版一致。
句首與句中的Delete（游標右側） 都會讓刪除的字在下一次組字時重新出現；句尾無可刪字時兩版維持原字。
三位置共 42 個 A/B 觀測節點，另有 16 個差異重現與 8 個 Enter 按放節點，均保存實際文字、焦點與視窗框。

## 修正前設定映射核對

| SmartOptions 欄位 | Android 普通實體 | 舊 Android／macOS 基準 | 說明 |
|---|---|---|---|
| `candidate_cursor_at_end` | 固定 `true` | 舊 Android 取右側；macOS 預設 `false` | 已定位的選字回歸 |
| `selection_returns_to_end` | `false` | macOS `false`；舊 Android 移到所選範圍末端 | 須配合正確的候選目標方向 |
| `max_completed_syllables` | 明確設為 `10` | `10` | 十／十一音節邊界 |
| `shift_at_limit` | 明確設為 `false` | `false` | 一般實體超過上限才擠字；觸控另有九／十規則 |
| `clear_composing_with_escape` | 未傳，Rust 預設 `false` | macOS 預設 `false` | 已有預設，未發現此欄漏值造成差異 |
| `shift_always_uppercase` | 未傳，Rust 預設 `false` | macOS 預設 `false` | 已有預設 |
| `space_opens_candidates` | 沿 App 的空白選字偏好 | 舊 Android 同偏好；macOS 預設開啟 | 既有平台偏好差異，不自動改掉已存設定 |
| `candidate_selection_keys` | `123456789` | Android 九格；macOS 通常八格 | 平台既有格數差異 |

`SmartOptions` 與 `SessionConfig` 使用 `serde(default, deny_unknown_fields)`，每個選項都有預設與有效值檢查。
目前證據指向具體 FE 映射與事件／宿主同步問題，不能概括為 Rust 所有功能缺少預設值。

## 已核准並實作的五項修正

1. Android 普通實體的候選目標恢復右側規則，維持既有觸控行為及已存空白選字偏好。
2. 鍵盤 view 重建時先關閉舊浮窗、取消其重試，再建立新 owner；旋轉、收放與切換排列後最多保留一窗。
3. 組字中的 `KEYCODE_FORWARD_DEL` 接到 Rust 既有 `Delete` 操作；無組字時維持宿主的普通向後刪除。
4. 完整配對 IME 已處理的 Enter 按下／放開；只有需要普通 Enter 時才向宿主送一次配對事件。候選長按不重複選字，前次 Up 遺失時不吃掉新的 Ctrl／Alt／Meta+Enter。
5. 旋轉／重新連線後，先核對宿主內已知範圍的文字，再以 `setComposingRegion` 重掛標記與恢復核心游標；不重新送出整句。無法核對則保留宿主文字、放棄舊核心組字。

五項產品修改均限定於 Android frontend，未修改 Rust 演算法、模型、其他平台或使用者偏好預設。
Delete 刪空時另明確移除宿主 composing range；Enter 保留候選長按抑制，並配對跨欄位的原始 KeyUp。

## 旋轉組字同步的根因與修正

只完成前四項時，六個宿主案例都在旋轉後確認／重開失敗：預期 `你好`，實際 `你好你`。
外部分步腳本在新舊 APK 都重現：輸入「你」→開候選→旋轉 1 → 0 → Esc → Enter，變成 `你你`；
不旋轉的對照仍是 `你`。舊 APK 的 Enter KeyUp 還會跳到 Email，因此不能直接比較其後續「好」的原欄輸入。

原生分步紀錄進一步量到：旋轉後 App 的 composing span 為 `-1/-1`，而前端仍保留 `appliedComposingText = 你`、起點 0；
原連線已結束標記，後續 `commitText` 就追加一次舊字。Android framework 的 configuration replay 也可能帶入欄位最初的選取位置，
不能把它當成目前組字游標。

`restoreMarkedComposition()` 僅在 restarting 路徑核對已知文字範圍，處理 `ExtractedText.startOffset`、截斷回應及 UTF-16 座標。
核對通過後重新標記既有範圍並恢復核心 caret；configuration replay 不因過時的起始游標在範圍外而丟掉已驗證的尾段。
普通 restart 仍要求宿主游標在原範圍內。無法取得快照或文字不符時，結束標記、abandon 舊引擎狀態並保留 App 現有文字。
觸控 host-text 尾段不套用實體 composing range。

## 最終模擬器驗證

測試使用同一個產品 APK，SHA-256 `d74e7dfb34d2705c206a35932ad56c4ddb1eab5277e09ba10de17b7adc173af8`。
裝置為 Android 17／API 37、arm64-v8a、`hw.keyboard=yes` 的 Pixel_9_Pro_XL 唯讀 AVD。
每項測試使用全新臨時 App 設定／學習資料，未操作或更新 Pixel。

- `lintDebug`、`assembleDebug`、`assembleDebugAndroidTest` 通過；APK 內的 DB 與來源核對為相同 `cbe2e…c7c`。
- `HardwareShortcutTest` 2 項與 `TextDeletionTest` 4 項 JVM 測試通過，無略過或失敗。
  命令排除 `buildGuanyinmaHostJNI`；不是完整 unit 套件或 host JNI smoke 的宣稱。
- **13 項 instrumentation 測試全部通過，無略過或失敗**：4 項 native adapter、2 項真實重新連線、1 項 Enter 回呼所有權契約、6 項宿主情境。
  adapter 涵蓋三位置右側選字與插入、三位置 Delete、刪空最後一字後繼續輸入，以及觸控選字回到句尾。
  重新連線涵蓋前後文與句中游標、連續兩次 restart、未完成讀音，及快照 null／文字不符時保留宿主、不重播。
  Enter 所有權案例直接模擬 service 回呼，驗證前次 Up 未送達後，新的 Ctrl+Enter 按下／放開均交回宿主。

| 宿主情境 | 直式 | 橫式 | 候選中連續旋轉 |
|---|---|---|---|
| 垂直浮窗 | 通過 | 通過 | 維持一窗 |
| 水平浮窗 | 通過 | 通過 | 維持一窗 |
| 關閉浮窗／底部候選 | 通過 | 通過 | 維持零窗 |

六個宿主案例各保存 30 個通過的觀測節點，涵蓋四法基本送字、候選／翻頁、句中右側選字後插入與 Backspace、
Delete 後接續輸入與刪空、Enter 確認與一般按放、候選長按、中英／全半形／符號快捷鍵，以及旋轉／收起重開。
固定 19 音節句在第七音節明確選「玩」，再檢查第 10／11／19 音節全文及可修改尾段；
第 19 音節旋轉後只重掛原尾段，不重播已擠出的前綴。乾淨模型可能先排「完」，此測試不以自動同音選字順位判定宿主接合。
選「郝」的案例放在各情境末尾，避免學習結果污染後續同音字的預期。

另以相同產品 APK、另一個隔離 AVD 執行四法未完成輸入的旋轉接續對照，共四個情境、20 個 XML／截圖觀測節點：
好打 `你ㄏ → 你好`、傳統 `ㄋㄧ → 你`、倉頡 `人弓 → 你`、簡易 `人 → 人火 → 鴒`。
每法橫直旋轉前後保留可見組字，完成／確認後無重複或漏字，焦點都留在原欄。

原生紀錄確認修正後旋轉保留正確 span、Enter 後仍只有 `你`，收起／重開再輸入得到 `你好`。
InputDispatcher 注入可驗證 Android 事件／宿主接合，不能稱為真正 USB／藍牙傳輸驗收；
本輪未涵蓋所有鍵盤外觀組合、其他 App、其他裝置或 iOS／桌面平台。
真實宿主 `setComposingRegion` 的 boolean 不會經 Binder 原樣回傳；本輪故障測試驗證的是快照不可核對的退路，未宣稱驗證所有宿主拒絕操作的情況。

## 來源與本機產物

關鍵入口：

- [Android 接合](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/GuanyinmaInputEngine.java) 的 `smartOptions()`。
- [Android service](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/BopomofoImeService.java) 的 `onCreateInputView()`、`onStartInput()`、`restoreMarkedComposition()`、`onKeyDown()`、`onKeyUp()`。
- [Rust SmartOptions](../Source/Guanyinma/src/smart.rs) 的 `Default`、`open_candidates()`、`select()` 與 `Key::Delete`。
- [macOS adapter](../Source/Loaders/OSX-IMK/GuanyinmaMacAdapter.mm) 的 SmartOptions 映射。
- [保留的 Manjusri 基準](../Source/ModulePackages/OVIMMandarin/OVIMSmartMandarin.cpp) 的候選目標、Return、Backspace、Delete。

未提交的本機證據位於 `Installer/local-builds/android-physical-ab-20261106/`：
`behavior-review.json`、`current-clean/`、`legacy-clean/`、固定舊來源、建置日誌及 A/B 腳本。
Pixel 原始異常與還原核對位於 `Installer/local-builds/android-pixel11-physical-20261106/`。
最終結果與來源／產物雜湊位於 `Installer/local-builds/android-physical-fix-20261106/final/`：
`runtime-results.json`、`build-evidence.json` 與各情境 `.log` 保存斷言、文字、span、游標及浮窗數量。
`span-before-fix.log` 保存修正前 `-1/-1` 標記的直接觀測；上層舊 `validation.json` 是前四項完成但旋轉仍失敗的中間證據，不代表最終狀態。
旋轉分步對照位於前述 A/B 目錄的 `fixed-rotation/` 與 `legacy-rotation/`，包括 JSON、XML、截圖及視窗框。

四法未完成輸入的平行對照位於 A/B 目錄的 `fixed-pending-methods/pending-methods.json`，該 AVD 收尾也確認殘窗為 0。
