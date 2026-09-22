# Windows SQLite／Defender 評估交接

> 日期：2026-09-23
> 狀態：留待 Windows 11 開發環境重新評估，本文件不承諾實作。

## 已確認現況

- 現代 Windows TSF 使用 repository 內嵌的 SQLite **3.6.11**。
- 正式發布的 x64 `KeyKeyTsf.dll`、x86 `KeyKeyTsf.dll` 與
  `KeyKeySettings.exe` 都會靜態包含這一版 SQLite。
- `KeyKeySettings.exe` 只用 SQLite 查詢 `collection_names`。
- Windows 10／11 內建 `winsqlite3.dll`，Windows SDK 提供 `winsqlite3.h` 與
  `winsqlite3.lib`；它可作為類似 iOS 系統 SQLite 的依賴，但實際 SQLite 版本會隨
  Windows Update 改變。
- 目前優先候選為改用系統 **WinSQLite**；備用方案才是固定內嵌官方 SQLite
  **3.53.4**。
- 非 Windows 的初步 size benchmark 顯示，3.53.4 約使每個靜態連結 binary 增加
  **0.4–0.6 MiB**；三個正式 binary 合計預估增加約 **1.3–1.8 MiB**，仍須以 MSVC
  Release build 實測。
- Defender 曾將 `KeyKeySettings.exe` 判為 Wacatac ML 類別；檔案已送 Microsoft 分析。
- SignPath Foundation 申請已送出，正式簽章資格仍待核准。

## 到 Windows 後再決定

先建立未修改的 3.6.11 x64／x86 Release baseline，再分別建立 WinSQLite 與內嵌 3.53.4
測試 build，比較：

1. x64／x86 是否能乾淨編譯，CTest 是否全部通過。
2. 舊 `KeyKey.db`、新 cooker、候選順序與 collection 清單是否相容。
3. x64 DLL、x86 DLL、Settings EXE、ZIP 與 NSIS installer 的實際 size delta。
4. 更新 Defender definitions 後，各個 payload 與 installer 的掃描結果。
5. WinSQLite 的 `sqlite3_libversion()` 與 `PRAGMA compile_options`，以及最低支援的
   Windows 11 是否具備 KeyKey 使用的全部 API。
6. SQLite 版本隨 Windows Update 改變時，所有需要固定順序的查詢是否都有明確
   `ORDER BY`。
7. `KeyKeySettings.exe` 是否值得完全移除 SQLite；若要做，應和 runtime 切換分開評估。
8. 既有 Win32 設定程式與 C++/WinRT WinUI 3 原型的安裝依賴、啟動速度、套件大小、
   accessibility、深色模式及 Defender 掃描結果。

Windows 建置基線：

```powershell
cd Source\Loaders\Windows-TSF
cmake --preset windows-x64
cmake --build --preset windows-x64-release
ctest --test-dir .\out\build\x64-ninja --output-on-failure
cmake --preset windows-x86
cmake --build --preset windows-x86-release --target KeyKeyTsf
```

## 暫不決定

- 不因 Defender 誤判而全面重寫 Windows 架構。
- 不先決定採 WinSQLite、內嵌 3.53.4，或移除 Settings 的 SQLite。
- 不改 iOS／macOS 的系統 SQLite，也不改 Android 的 `.kki` 索引。
- 不把 SQLite 升級視為 Wacatac 誤判的保證解法。
- 正式發布仍需簽署 x64 DLL、x86 DLL、Settings EXE 與外層 installer，並掃描最終簽章後
  的同一份檔案。

## Windows 評估方向

優先測試以 `winsqlite3.h`／`winsqlite3.lib` 取代 repository 的 `sqlite3.c`。若基本 API、
舊資料庫、cooker、候選結果及 x86 host 都相容，系統 WinSQLite 可減少三個正式 binary
重複內嵌 SQLite，並由 Windows Update 維護安全修補。若版本差異、compile options 或
行為無法接受，再選擇固定內嵌 3.53.4。

WinSQLite 只可能降低 binary 體積與部分 heuristic 特徵，不能保證消除 Defender 誤判。

## Windows 11 設定 UI 建議

Microsoft 對新 Windows 桌面程式推薦 WinUI 3 與 Windows App SDK；既有 C++ Win32
程式則可保留 Win32，按需要逐步現代化，不必為了 Windows 11 全面重寫。Windows 開發時
建議製作一個小型 C++/WinRT WinUI 3 原型再決定，不把改寫視為目前承諾。

建議架構：

1. 保留獨立的 `KeyKeySettings.exe`，`KeyKeyTsf.dll` 繼續透過 `ITfFnConfigure`
   啟動它。不要把設定 UI 放進 TSF DLL，避免 UI 故障影響載入 DLL 的 x64／x86 host。
2. 若採 WinUI 3，以 XAML、`SettingsCard`、`SettingsExpander`、`ToggleSwitch` 與
   `ComboBox` 建立 app-owned settings page，設定變更立即生效，不另設「套用」按鈕。
3. 抽出共用 `SettingsStore`，集中 schema、預設值、驗證、路徑及讀寫。第一階段保留
   `%APPDATA%\chichi77 KeyKey` 既有 plist，以暫存檔加原子取代寫入；DLL 可在下一次
   按鍵同步時依檔案時間重讀。不要把 UI framework 與設定格式綁在一起。
4. 將 `collection_names` 在建置時輸出成小型 manifest 或 Windows resource，讓
   `KeyKeySettings.exe` 不再為顯示清單而連結 SQLite；TSF runtime 的 SQLite／
   WinSQLite 選擇仍按前述矩陣獨立評估。
5. Windows App SDK 並非 Windows 11 內建元件，WinUI 3 方案必須比較 framework-dependent
   與 self-contained 部署的 runtime、安裝與 size 成本。若收益不足，保留小型 Win32
   設定程式並套用相同的 Windows 11 設定頁布局及 accessibility 原則。

目前沒有找到 Microsoft 提供給第三方 TSF 輸入法、可把任意設定頁嵌入 Windows 11
「設定」App 的公開 extension point；正式入口仍以 `ITfFnConfigure` 顯示輸入法自己的
設定視窗。不要改用 WebView／HTML、PowerShell、HTA 或 `rundll32` 當設定 UI，這些方案
會增加 runtime、部署或安全掃描變數。

Windows 開發時參考：

- [Choose a Windows development path](https://learn.microsoft.com/en-us/windows/apps/get-started/)
- [Guidelines for app settings](https://learn.microsoft.com/en-us/windows/apps/design/app-settings/guidelines-for-app-settings)
- [Get started with WinUI 3](https://learn.microsoft.com/en-us/windows/apps/get-started/winui-get-started-overview)
- [Text Services Framework interfaces](https://learn.microsoft.com/en-us/windows/win32/tsf/text-services-framework-interfaces)

相關檔案：

- `Source/Loaders/Windows-TSF/CMakeLists.txt`
- `Source/Loaders/Windows-TSF/SettingsApp.cpp`
- `Source/Loaders/Windows-TSF/Package-Store-Windows.ps1`
- `Source/ExternalLibraries/sqlite/sqlite3.c`
- `Source/ExternalLibraries/sqlite/sqlite3.h`
