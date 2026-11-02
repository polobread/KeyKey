# PR 建置與發布驗證

共用核心、模型或相關平台程式變更時，在 PR 上執行相應驗證。所有 workflow 都提供 PR 驗證入口；此文件描述接線範圍，不能代替特定 commit 的 Actions 結果。

| Workflow | PR 驗證 |
| --- | --- |
| Guanyinma Core | 六平台原生／無視窗模擬器 Rust 與 C ABI，以及唯一的完整核心矩陣與涵蓋率門檻 |
| Linux CI | Ubuntu 24.04 建置、GTK3／GTK4／Qt6 X11、來源壓縮包重建、套件生命週期與 sanitizer；Ubuntu 22.04 最低 API 與套件生命週期 |
| Linux desktop input stability | 相同 staged-addon 案例執行一輪；100 輪壓力測試仍由手動入口執行 |
| Windows Build and Unsigned Inputs | x64／x86 原生測試、設定與部署測試、未簽章封裝檢查 |
| Windows Shared Data / Windows Signing Tools | 跨架構資料保護及既有簽章／封裝工具測試 |
| macOS Symbol Table / Package macOS | 先透過 Core Text 準備 Apple CJK 字型，再做隔離 AppKit／前端接合測試、App 建置及未簽章 PKG 封裝 |
| Package Android / Android Play Release | Debug APK、未簽章 Release AAB、lint、少量 JNI 接合測試與封裝詞庫／授權驗證；共用封裝 workflow |
| Package iOS Simulator | Swift 接合、模擬器 App／extension 建置與封裝內容驗證 |
| Desktop Release Tools | 更新客戶端與發布工具既有測試，以及全部 workflow 的 actionlint 驗證 |
| Mirror Signed Windows Release | 既有 Windows 發布來源、傳輸、簽章及鏡像工具測試 |
| Prepare Linux Stable Update / Prepare macOS Stable Update | 更新公告準備工具既有測試 |
| Sync Update Feeds to CDN | Feed／簽章／公開資產驗證；Windows 原生資產驗證仍依 metadata 變更啟動 |
| Terraform Release Mirror | fmt、無 backend 的 init、validate；不取得雲端角色 |
| Rebuild KeyKey database | 來源工具既有測試、已提交模型及共用資料庫接線驗證；不重建或修改模型 |

同一 PR 的新推送會取消過期的驗證工作；手動及正式發布流程保留原本的排程與發布鎖。

PR 權限維持唯讀。正式簽章、Apple 公證、商店上架、Release／CDN 發布、Terraform plan／apply、公告 PR 及合併後模型重建，仍各自依既有發布事件、分支與環境條件執行。PR 不使用發布環境或其 secrets。

平台 workflow 建置並連結鎖定的 Rust 核心，只執行其前端接合冒煙。交叉編譯、平台套件、模擬器／實機 UI 及安裝測試是不同證據層級；平台建置成功不代表實機或正式發布驗收完成。
