# Windows v1.3.2 功能分支驗證

2026-10-04，以 `c44a3a5eb06703381eb37f2ec82a3e698ec0db9f` 為基底，在本機 `v1.3.2` 開發。
產品版號維持 1.3.1；沒有 push、發布、註冊或替換使用者已安裝的輸入法。

## 已實作

- 好打注音進階設定：空白開候選、候選目標在游標前／後、8 個唯一可輸入 ASCII 鍵、10–20 音節。
  留空候選鍵沿用許氏／倚天26／其餘配置原預設。非法 profile 值由 Windows adapter 收斂。
  UI 在任何設定寫入前驗證所有新值；下一次輸入保留舊組字後才使用新設定。
- 讀音輔助：唯讀正式 DB 完整詞優先、逐字選單與人工修改、缺字提示。
  每次最多 64 Unicode code points、每字與完整詞各最多 32 讀音，不展開笛卡兒積。
  Native snapshot 有明確 free、buffer 容量包含 NUL，空查詢與 DB 錯誤可區分。
  存詞沿用既有 rowid、去重與音節數驗證，不改模型或既有個人資料。
- 符號表：原生不啟動 WPF CLR、非啟用面板、17 分類／733 Buttons／74 Messages。
  從原 plist 在各 build directory 生成並內嵌，共 807 個完整字串。
  選取經 TSF edit session 先完成組字再插入；保留全半形，取消與焦點生命週期使回呼失效。
- 簡體輸出：一般提交、長句擠出、模式切換、失焦保字與符號使用同一文件輸出轉換。
  組字／候選／學習維持繁體；組字快照保留其開始時的輸出設定，後續輸入使用新值。
  只對漢字使用既有 OVOFHanConvert 表，標點／英文／數字／emoji 維持原樣。
  UI 直接發佈 TSF 全域狀態，桌面採用受限宿主的新狀態後保存設定；測試 profile 使用獨立 GUID。
  字表授權與來源通知包含在 ZIP。

## 本機環境與命令

Windows 11（SDK 10.0.26100.0，目標 10.0.26200），Visual Studio 18 Community、.NET 10 SDK。
CMake／CTest 使用 Visual Studio 內附版本，Python 使用 Codex bundled Python 3.12.14。
以 `windows-x64-vs2026` 與 `windows-x86` configure/build presets 建置；x64 額外 clean-first
排除既存 object，建置／測試全程使用隔離 profile。TSF broker 在 sandbox token 下拒絕
臨時 compartment 寫入，需在 sandbox 外執行隔離回歸；不觸及正式使用者 GUID。

```powershell
cmake --preset windows-x64-vs2026 -DPython3_EXECUTABLE=<bundled-python>
cmake --preset windows-x86 -DPython3_EXECUTABLE=<bundled-python>
cmake --build --preset windows-x64-vs2026-release
cmake --build --preset windows-x86-release
ctest --test-dir out/build/x64-vs2026 -C Release --output-on-failure
ctest --test-dir out/build/x86 -C Release --output-on-failure
dotnet run --project SettingsModern.UiTests --configuration Release -p:KeyKeyRuntimeDirectory=<fresh-x64-Release>
dotnet publish SettingsModern.UiTests --runtime win-x86 --self-contained true --output out/ui-tests-x86
# 將新 x86 backend 與正式 DB 複製到隔離 test runtime，再執行 SettingsModern.UiTests.exe。
./Validate-Frontend.ps1
python ../../Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py ../../Distributions/Takao/CookedDatabase/KeyKey.db
python ../../Distributions/Takao/DatabaseCooker/verify-shared-database-wiring.py
./Package-Windows.ps1 -BuildDirectory out/build/x64-vs2026 -X86BuildDirectory out/build/x86
./Package-Windows.ps1 -BuildDirectory out/build/x64-vs2026 -X86BuildDirectory out/build/x86 -Architecture x86
python Packaging/verify-package.py out/package/chichi77-KeyKey-1.3.1-windows-x64.zip out/package/chichi77-KeyKey-1.3.1-windows-x86.zip
```

## 驗證結果

兩架構完整建置成功。既有 engine／candidate／table、TSF interface／工作列／隔離 registration、
deployment、共享輸入法與 AppContainer 回歸通過。
最後 x64 CTest **28／28** 通過（10.86 秒）、x86 **27／27** 通過（8.25 秒）；
x86 自含 WPF 測試另行通過。四種輸入法均以「車」確認引擎維持繁體、共用輸出得到「车」。
TSF mock 行為測試在兩架構通過一般提交、長句前段／繁體 preedit、舊狀態保字、
同步鎖拒絕後的延後提交、失焦、符號輸出、舊回呼與 read／write 失敗不截斷。
進階 engine 測試包含非數字鍵選字、許氏／倚天26自動候選鍵、非法設定收斂、
12 音節的完整詞段擠出、19 音節全句保存及組字中修改設定。
原有固定長句測試確認預設第10／11音節和全文不遺失／重複。

WPF 真實控制項與 native backend 在 x64、x86 均通過：非法值零寫入、保存後重開、
讀音完整詞／破音字／缺字／補充平面漢字／長詞、人工讀音保留、rowid／去重／重新讀取，
以及 P/Invoke sizing／容量不足不截斷／無效索引／釋放契約。
原生設定持久化測試在兩架構通過快速開關、未來 mtime、XML escaping、其他設定與 array 保留。

符號面板在 x64、x86 通過完整807項、長顏文字、滑鼠選取不奪焦點、翻頁、單次回呼、
取消、owner 銷毀後重新開啟。簡體共享隔離 GUID 在 x64、x86 的跨程序與 AppContainer、
以及 x64→x86 子程序通過。轉換測試確認原標點寬度、emoji 與補充平面字保持。

正式 DB 與新 build runtime copy 都保持 SHA-256
`8fc3aead36cefd16a77c0a0d4319f7a305fb712b752db09396c8ac2bd4ebbfdb`；
119,159 Unigram、883,372 Bigram，完整性及五 frontend wiring 驗證通過。
本機原 checkout 部分文字檔有 CRLF 與既有 `eol=lf` attributes 不一致，僅落盤回 LF
即通過既有來源雜湊 gate；這些檔案與 HEAD bytes 相符且無來源 diff。

## 產物與未驗證界線

開發 DLL、settings、backend、部署程式及測試在
`Source/Loaders/Windows-TSF/out/build/x64-vs2026/Release`、`out/build/x86/Release`。
x86 自含 WPF 測試在 `out/ui-tests-x86`；ZIP 在 `out/package`，維持 1.3.1 檔名以反映未升產品版號。
所有 build、測試記錄與 ZIP 都是 ignored 產物。
x64 ZIP verifier 通過 15 個 payload 檔案，x86 通過 14 個；逐檔 SHA／PE 架構／正式 DB／
設定指南與 HanConvert 授權通知皆核對。打包時依 CMake generator 選擇同一 runtime directory，
避免 Visual Studio 的新 Release DLL 與 build root 殘留舊 DB 混包。
NSIS Store 腳本同步相同 runtime 選擇與通知，但本輪未建置或驗收 Store EXE。

Mock TSF edit-session 行為、引擎、真實 WPF 控制項、broker compartment、原生面板與已安裝版本
是不同證據層級。本輪沒有替換已安裝版本，未驗收新 DLL 在 Notepad／Search／Word／Edge／
Windows Terminal 的真實文字宿主、x86 實際宿主、高 DPI、多螢幕、Windows 10、secure desktop
或實機焦點／長句組字行為。發布前仍需在隔離 VM／測試機完成這些項目；
本輪原始碼與自動測試不等於已安裝產品或全面實機驗收。
