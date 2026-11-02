# Windows／macOS／Linux 共用桌面輸入測試

案例來源為 [`tests/desktop_input/cases.json`](../tests/desktop_input/cases.json)。固定相同模型、案例 ID、設定意圖、參考按鍵、分段檢查點與預期文字，各平台分別接合原生輸入法與文字宿主。指定候選文字的步驟可依該平台實際候選標籤選字；候選位置會因系統字型過濾而不同。不得以核心通過代替 TSF／IMK／Fcitx 實測，也不得將 GTK3／GTK4／Qt6 三個 Linux 宿主寫成三個桌面平台。

## 設定與隔離

執行前明確套用設定並讀回確認。Linux 使用完整 77 項 fixture，再套用共用案例列出的覆寫；Windows 與 macOS 使用隔離 plist 與原生 FE 設定讀回。共同條件為標準注音、中文啟動、半形初始狀態、繁轉簡關閉、關聯詞關閉、好打 8 個選字鍵、空白開候選開啟、組字 10 音節、游標後方選字、選字後不回句尾、Shift 強制大寫關閉、中文忽略 Caps Lock 關閉。每案使用隔離資料，先清除學習，避免先前選字改變結果。

`shared-eight-key` 是共用基準；`linux-nine-key` 明確覆寫好打為 9 鍵，保留 Linux 擴充驗證。B02 的 8／9 鍵與字母鍵案例會再覆寫指定選字鍵，不能把 Windows 的 9→8 鍵回退當成 9 鍵案例通過。

平台原生預設值須另外驗證；不能直接採用各平台預設值作為行為對照條件。文字範圍與游標統一以 Unicode 字元／讀音座標表達，執行器再轉成宿主 API 的 byte／UTF-16 range。原生鍵碼與快捷鍵由平台接合，但不能更改預期文字來使結果通過。`steps[].candidate_targets` 以零起算的按鍵索引指定必須選到的文字；原 `keys` 中的該鍵為參考位置。Windows 與 macOS 執行器已接上實際候選讀回與分頁搜尋；Linux 既有執行器仍使用原本參考鍵序，其字型環境若改變，須另補相同的候選解析，不能直接改預期文字。

目前由原始碼確認的接合差異如下，仍須原生執行才能判定實際結果：

| 功能 | Windows | macOS | Linux |
|---|---|---|---|
| 中文忽略 Caps Lock | Loader 偏好，預設 True；共同比較時明確設 False | adapter 固定 False；True 案例無對等設定 | 可切換，預設 False |
| 選字後回句尾 | adapter 未映射此選項，核心預設 False | adapter 固定 False | 可切換 |
| 好打 9 鍵選字 | adapter 會將非 8 鍵設定退回 8 鍵 | 可傳入設定，隔離 PV 矩陣驗證 | 可設定 8／9 鍵及字母鍵 |
| 倉頡自訂最大碼數 | adapter 固定 5 碼，無對等設定 | `MaximumRadicalLength`，隔離 PV 矩陣驗證 | 可設定 |
| Esc 清除整句 | 同時設定 `ClearComposingTextWithEsc` 與 `ClearComposingTextWithEscUserChoice` | `ClearComposingTextWithEsc` | `SmartMandarin/ClearComposingTextWithEsc` |

參照 `Windows-TSF/GuanyinmaWindowsAdapter.cpp`、`Windows-TSF/FrontendSettings.cpp`、`OSX-IMK/GuanyinmaMacAdapter.mm` 與 `Linux-IME/adapters/fcitx5/fcitx5_engine.cpp`。不支援的組合須列為「無對等設定／待討論」，不能標示通過或直接判定詞庫錯誤。本次不調整上述產品行為。

## 案例內容

- S01～S10：24 個設定案例，驗證 Shift 大小寫、Caps Lock 在中文／英文的行為、Esc 的候選／讀音優先順序、空白開候選、選字後位置及前／後方選字。以「你好／妳好」等有意義文字檢查後續插入位置。
- B01～B07：17 個邊界案例，驗證 10／11、20／21 音節、數字 8／9 鍵與字母選字鍵、分頁和 Home／End、倉頡滿碼、錯碼、即時／前綴候選及自訂通配字。
- R01～R04：傳統全形、好打全形、中英切換、跨 App 焦點隔離，各執行 100 輪。好打全形案例明確關閉空白開候選，並用 Return 送出仍在組字區的標點；傳統案例保留原本全形鍵序。

每個檢查點同時保存已送出文字與組字文字。音節上限案例要求到上限仍未送字；下一音節完成後有文字送出、可編輯尾段未超過上限，兩者合併完全等於輸入內容。倉頡滿碼的預期是查詢候選；有多個候選時仍須明確選字。即時候選與錯碼清除互斥，測試設定不得同時要求兩者開啟。

S09 明確保留學習開啟。選擇單字「妳」後，同一次操作就會產生選字偏好；回到句尾再輸入相同讀音，預期為「妳好妳」，不是未學習時的「妳好你」。不回句尾的對照則為「妳你好」。測試開始前清除學習，不代表當次測試內不會學習；不能因這項互動而放寬游標檢查或把字面結果當成詞庫問題。

## 執行入口與證據

Linux 在已準備好 E2E 環境變數的隔離 D-Bus 內執行：

```sh
bash Source/Loaders/Linux-IME/ci/run-desktop-input-session.sh
```

此入口使用既有 managed Xvfb／Fcitx session 的建立與清理流程。可用 `KEYKEY_E2E_DESKTOP_TOOLKITS=GTK3,GTK4,QT6` 選宿主、`KEYKEY_E2E_DESKTOP_CATEGORIES=settings,boundary,stability` 選類別，`KEYKEY_E2E_DESKTOP_ROUNDS=100` 設定每個穩定性案例的輪數；`KEYKEY_E2E_DESKTOP_PROFILE=linux-nine-key` 可選 Linux 9 鍵擴充，預設為 `shared-eight-key`。僅允許 managed session，不能對個人桌面套用。

使用 CTest 時不需手動準備 session 環境。啟用 `BUILD_TESTING`、`KEYKEY_BUILD_FCITX5` 與 `KEYKEY_BUILD_X11_E2E_HOST` 後，一般 CTest 自動包含三個 `keykey_linux_desktop_GTK3/GTK4/QT6` 測試；每個宿主執行 45 個共用案例與一個 keyboard-us 負向對照。`keykey_linux_desktop_stage` fixture 先安裝到 build 目錄內的私有 DESTDIR，各測試驗證實際載入該 stage 的 addon；不使用系統已安裝的 KeyKey。一般 CTest 另有 `keykey_linux_desktop_core_boundaries`，執行 12 項可攜核心邊界檢查。

```sh
# 建置時啟用 X11 hosts 後，執行日常共用案例；fixture 由 CTest 自動加入。
ctest --test-dir BUILD_DIR -L 'desktop-(core|input)' --parallel 3 --output-on-failure

# 100 輪測試另行啟用；預設不加入日常 CTest。
cmake -S Source/Loaders/Linux-IME -B BUILD_DIR \
  -DKEYKEY_BUILD_FCITX5=ON -DKEYKEY_BUILD_X11_E2E_HOST=ON \
  -DKEYKEY_ENABLE_DESKTOP_STABILITY_TESTS=ON \
  -DKEYKEY_DESKTOP_STABILITY_PROFILE=linux-nine-key
cmake --build BUILD_DIR
ctest --test-dir BUILD_DIR -L desktop-stability --parallel 3 --output-on-failure
```

`desktop-input`、`desktop-core`、`desktop-stability` 是三組 CTest label。新增的 GUI 測試各自使用新的證據目錄，避免重跑時沿用上次結果；位置在 `BUILD_DIR/desktop-input/`。不要同時在同一 build 目錄啟動兩個獨立 CTest 程序，以免重新準備同一 stage；同一個 CTest 的 `--parallel 3` 會依 fixture 正確排序。

正式執行器在每案保存 `reset-learning.json`，讀回確認兩個 Smart 學習表已清空且自訂詞／字表學習未被刪除；拒絕外部使用者 DB 覆寫，模型雜湊也須符合共用 fixture。session 輸出寫入 `session.log`，避免 D-Bus 自動啟動的 portal 持有 CTest pipe 而阻止測試結束。Linux 桌面組以 `setsid` 建立私有程序群組，結束或失敗時清理該組的服務，不操作個人桌面程序；此入口需要 `util-linux`。

既有 `Linux CI` 的 Ubuntu 24.04 PR 與完整建置會透過一般 CTest 執行共用案例，並上傳設定讀回、宿主事件與 CTest 紀錄。`.github/workflows/linux-desktop-stability.yml` 提供獨立的手動 Actions 工作流程，可選 8 鍵或 Linux 9 鍵 profile；執行三個宿主的四種情境各 100 輪，另跑一般共用案例與核心邊界。證據上傳排除私有 stage，不額外上傳模型副本。GitHub 雲端的觸發與結果須另行確認，不能以本地 CTest 通過宣稱 GitHub 已執行通過。

`cases/*/automation.jsonl` 保存送鍵時間、焦點視窗、X11 按鍵按放狀態、Caps Lock／Num Lock 狀態、預期及實際檢查點；`config-*.json` 保存完整設定讀回。另保留原始宿主事件、程序紀錄、每案及總結果。失敗後先保存狀態才清理測試按鍵，不能重試成功就覆蓋第一次失敗。

可攜的 12 項核心邊界補充檢查使用相同模型，接受各平台自行建置的原生 C ABI library：

```sh
python3 tests/desktop_input/core_boundaries.py \
  --library /absolute/path/to/libguanyinma.so \
  --model /absolute/path/to/KeyKey.db \
  --output /absolute/path/to/results
```

library 參數依平台換成原生 `.dll`／`.dylib`／`.so`。這層可精確檢查候選總數、每頁列數、首末頁循環及候選是否已開啟；結果仍屬核心證據。

## Windows 原生 TSF 交易測試

Windows 的 `KeyKeyDesktopInputHost` 使用 Windows 建立的 `ITfThreadMgr`、`ITfDocumentMgr`、`ITfContext`、range、composition 與 edit session，連入正式 `TextService` 及 Windows Guanyinma adapter。測試專用 `ITextStoreACP` 保存 UTF-16 文件；每鍵透過正式 `OnTestKeyDown`／`OnKeyDown`／key-up 回呼輸入。`SetKeyboardState` 與美式鍵盤 layout 僅套用測試執行緒，結束還原，不使用 `SendInput`，不註冊／啟用已安裝 TIP、不操作個人桌面。service 透過既有 test friend 接上測試 context，不經完整的 TIP `ActivateEx`、語言列與系統偏好發布接線。

這層能驗證 TSF 寫入、組字範圍、UTF-16 游標及 FE 設定／事件映射；沒有可見視窗與文字座標，所以不驗證候選窗繪製／定位。R03 僅驗證同一 worker 內兩份原生 TSF 文件的焦點回呼與內容隔離，不能宣稱跨 App 前景焦點已通過。Windows 四法另已完成記事本／Word 的局部真實宿主冒煙，好打注音亦完成使用者手打全文驗收，結果與未涵蓋範圍見 [Windows 桌面宿主驗收](WINDOWS_DESKTOP_HOST_ACCEPTANCE.md)；其證據與這個隔離執行器分開記錄。macOS IMK 宿主驗證仍須另行完成。

在已載入 MSVC 的 Developer PowerShell，從 `Source/Loaders/Windows-TSF` 執行：

```powershell
python ../../../update/prepare.py fetch windows
cmake --preset windows-x64
cmake --build out/build/x64-ninja --target KeyKeyDesktopInputHost
ctest --test-dir out/build/x64-ninja -L '^desktop-input$' --output-on-failure

# 四項穩定性情境各 100 輪，另行啟用。
cmake --preset windows-x64 -DKEYKEY_ENABLE_DESKTOP_STABILITY_TESTS=ON
ctest --test-dir out/build/x64-ninja -L '^desktop-stability$' --output-on-failure
```

一般測試跑 45 個共用案例各一次，另加不經輸入法的美式鍵盤負向對照。每案／每輪各啟動新程序與全新隔離 profile，學習只在該案內保留。執行前核對部署模型的 SHA-256；共用案例及 host executable 的雜湊、原始設定意圖、plist 讀回、原生 Caps Lock／倉頡設定讀回、逐鍵修飾鍵狀態、候選頁、TSF text/preedit／UTF-16 範圍與檢查點均寫至 `BUILD_DIR/desktop-input/windows-tsf-*/`。每次建立新目錄，第一次失敗不會被後續執行覆蓋；產物不提交。

不支援的四個案例明列 `unsupported`：S09 回句尾開啟、B02 好打九鍵、B03 倉頡最大兩碼的兩種設定；不執行回退設定並標為通過。B06 按指定候選文字「喬」解析實際選字鍵，保存參考鍵、實際鍵及各頁候選；找不到指定候選就失敗，最終仍須等於「喬喬」。未指定候選文字的分頁／數字鍵案例照固定鍵序驗證。其他不符預期一律保留為 `failed`，CTest 回傳失敗，不更改預期文字。完整核心矩陣仍由 `guanyinma-core.yml` 負責，此入口不重跑完整 Rust 測試。

## macOS 隔離 controller／PV 接合測試

```sh
python3 Source/Loaders/OSX-IMK/Tests/desktop_input_matrix.py

# 已建置同一來源核心時可略過 Cargo；每次仍重新編譯原生測試宿主。
python3 Source/Loaders/OSX-IMK/Tests/desktop_input_matrix.py \
  --library /absolute/path/to/libguanyinma.a --rounds 100
```

預設執行全部 45 個案例各一次，另有不經輸入法的英文鍵盤負向對照。`--categories settings,boundary` 可縮小範圍；`--rounds 100` 只增加四項 stability 情境的輪數。`--cargo` 指定工具鏈入口，`--offline` 使用已快取的 Cargo 依賴。SDK SQLite 由執行器明確指定。每案／每輪使用新程序、私有 plist 與全新 Guanyinma 使用者 DB，學習在該案內保留；不使用個人偏好、已安裝 IMK、系統 TIS 選取或全域按鍵。

宿主從目前 `OpenVanillaController.mm` 原文擷取 `handleEvent:`、組字更新／送字、中英切換與全形選單方法編譯，連入真正的 `PVLoaderContext`、Guanyinma macOS package／adapter、PV 候選面板、全形 output filter 與 `CVEncodingService` 系統字型判斷。事件為程序內 ANSI US 鍵碼／修飾鍵的 `NSEvent`，key-down／key-up 直接呼叫 controller 方法；Caps Lock 只影響測試事件旗標。UI receiver 為 nil，文字 client 是測試自有的 UTF-16 記憶體實作，驗證 `insertText:replacementRange:` 與 `setMarkedText:selectionRange:replacementRange:` 的實際交易及範圍。

macOS 的中英模式與全半形由原生選單操作接合：共用 `ctrl+backslash` 對應 controller 中英模式操作，`shift+space` 對應 `toggleOutputFilterAction:` 的全形選單。這是相同設定意圖的跨平台接合，不代表 macOS 支援這兩組參考快捷鍵；macOS Ctrl-backslash 是輸入法選擇器，全形選單快捷鍵為 Command+Shift+Space。R03 驗證同一 worker 內兩個 PV context／client 的停用、送字、重新啟用及文字隔離；不宣稱跨 App 焦點通過。

五案明列 `unsupported`：S03／S04 的 smart／traditional 各一案要求「中文忽略 Caps Lock=True」，以及 S09 回句尾開啟。即使該選項不影響英文模式，仍不把無法套用的設定組合列為通過。好打九鍵與倉頡兩碼上限有原生對應設定，正常執行。B06 從實際過濾後的候選清單尋找「喬」，再透過 controller 翻頁及送入實際標籤；未指定候選文字的其他鍵序維持 fixture 原文。

每次建立新的 `Installer/local-builds/desktop-input-macos/macos-pv-*/`，保存來源 controller／生成檔／host／library／模型與 fixture 雜湊、設定意圖、plist 寫入及原生讀回、學習隔離證據、逐鍵事件、候選頁、UTF-16 client 交易、檢查點差異、首個失敗與總結。可用 `--output` 指定產物根目錄；`--host` 供重用同一已建置宿主診斷，須自行確認來源一致。所有產物均不提交。

`macos-symbols.yml` 的 `desktop-input` job 在相關 PR 執行一般矩陣並上傳 JSON／程序紀錄；手動勾選 `desktop_stability` 執行四項情境各 100 輪，不新增排程。不重跑完整 Rust 核心測試。本機結果不能當成 GitHub runner 通過。此層沒有啟動 `IMKServer` 或系統文字宿主，不驗證 TIS 註冊、IMK 連線、候選窗繪製／定位、實體鍵盤或安裝；真正 IMK 驗證仍依 [獨立宿主流程](GUANYINMA_MACOS_IMK_HOST_TEST.md) 進行。
