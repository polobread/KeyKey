# Android 實體鍵盤行為差異調查

## 範圍與證據層級

本次為行為調查，尚未完成修正後驗收。Pixel 11 接上 USB Ducky One2 SF RGB 後，
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

## 已確認的行為

| 項目 | 重現 | 舊 Android | 目前 Android | 判讀 |
|---|---|---|---|---|
| 句中選字目標 | 輸入「你好」，左移成「你｜好」，下鍵開候選，按 2 | `你郝` | `妳好` | 候選目標由游標右側變成左側，屬接合設定回歸 |
| 句尾選字範圍 | 「你好｜」下鍵開候選、按 2 | `你郝` | `妳好` | 新映射也改變句尾候選的詞段範圍 |
| 選字後插入 | 前項選完再輸入 `ㄇㄚ` | `你郝媽` | `妳媽好` | 選字目標與選後游標策略連動改變 |
| 組字中向後 Delete | 「你｜好」按 Delete，再輸入 `ㄇㄚ` | 先 `你`，後 `你媽好` | 先 `你`，後 `你媽好` | 兩版皆有，宿主刪字未同步核心讀音，下一次重畫舊字回來 |
| 旋轉浮窗 | 開候選後旋轉、再轉回 | 也可殘留多窗 | 已觀測 1 → 2 → 3 個候選窗 | 既有 Android 視窗生命週期問題，不能單歸因於 Rust 演算法 |
| Enter 按放 | 輸入「你好」，分開按下與放開 Enter | Down 保持原欄，Up 跳到 Email | 同左 | IME 處理 Down 後原始 Up 透傳，造成欄位導航；不是 Backspace 直接失效的證據 |

最後一項的後續 Backspace 實際送往空白 Email 欄，所以原欄「你好」保持不變。
原生探索性測試若固定檢查原欄，會把這個現象誤記成退格未刪字。
倉頡打完完整碼後的關聯詞，也必須與尚未選取的字根候選分開，不能把普通數字當成關聯詞選字。

句首、句中、句尾的 Backspace 與後續插入，在乾淨學習狀態下兩版一致。
句首與句中的向後 Delete 都會讓刪除的字在下一次組字時重新出現；句尾無可刪字時兩版維持原字。
三位置共 42 個 A/B 觀測節點，另有 16 個差異重現與 8 個 Enter 按放節點，均保存實際文字、焦點與視窗框。

## 設定映射核對

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

## 具體修正方向（待同意）

1. Android 普通實體的候選目標恢復右側規則，維持既有觸控行為及已存空白選字偏好。
2. 鍵盤 view 重建時先關閉舊浮窗、取消其重試，再建立新 owner；旋轉、收放與切換排列後最多保留一窗。
3. 組字中的 `KEYCODE_FORWARD_DEL` 接到 Rust 既有 `Delete` 操作；無組字時維持宿主的普通向後刪除。
4. 完整配對 IME 已處理的 Enter 按下／放開；只有需要普通 Enter 時才向宿主送一次配對事件。

目前尚未修改產品碼。前三項及第四項分別已提出確認；修正後需重跑垂直浮窗、水平浮窗與關閉浮窗，
涵蓋手機直橫式、句首／句中／句尾選字與雙向刪除、短篇第 10／11／19 音節、快捷鍵、旋轉與重開。

## 來源與本機產物

關鍵入口：

- [Android 接合](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/GuanyinmaInputEngine.java) 的 `smartOptions()`。
- [Android service](../Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/BopomofoImeService.java) 的 `onCreateInputView()`、`onKeyDown()`、`onKeyUp()`。
- [Rust SmartOptions](../Source/Guanyinma/src/smart.rs) 的 `Default`、`open_candidates()`、`select()` 與 `Key::Delete`。
- [macOS adapter](../Source/Loaders/OSX-IMK/GuanyinmaMacAdapter.mm) 的 SmartOptions 映射。
- [保留的 Manjusri 基準](../Source/ModulePackages/OVIMMandarin/OVIMSmartMandarin.cpp) 的候選目標、Return、Backspace、Delete。

未提交的本機證據位於 `Installer/local-builds/android-physical-ab-20261106/`：
`behavior-review.json`、`current-clean/`、`legacy-clean/`、固定舊來源、建置日誌及 A/B 腳本。
Pixel 原始異常與還原核對位於 `Installer/local-builds/android-pixel11-physical-20261106/`。
