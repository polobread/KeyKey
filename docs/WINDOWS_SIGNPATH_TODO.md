# Windows SignPath TODO

依維護者確認，KeyKey 目前未達 SignPath Foundation 的申請門檻，因此暫緩整合。
目前 Windows 採 Certum／SimplySign 本機半自動簽章，
正式政策見 [CODE_SIGNING_POLICY.md](../CODE_SIGNING_POLICY.md)，操作見
[Windows Certum 發布指南](WINDOWS_CERTUM_RELEASE.md)。
以下工作僅在專案條件或方案要求改變後重新評估，現階段不追蹤等待核准或安排整合。

## 專案條件或方案要求改變後的待辦

- [ ] 專案條件或方案要求改變後，向 SignPath Foundation 重新確認申請門檻；
  確認符合且服務可用後，才恢復後續整合工作。
- [ ] 重新確認 [SignPath Foundation 條件](https://signpath.org/terms.html)、
  原始碼／建置來源要求、變更審查及人工簽章核准流程。
- [ ] 確認 repository、SignPath project、signing policy 與憑證的對應；
  簽章憑據只放受保護環境，不進 Git、聊天或執行日誌。
- [ ] 以 PR 審查 CI／建置腳本與簽章整合，保留維護者 review／merge 及獨立的簽章核准。
- [ ] 驗證 x64／x86 TSF DLL、設定程式／後端、部署程式、x86 registration bridge、
  WinSparkle 與外層 NSIS 安裝器的簽章覆蓋；解除安裝器沿用已簽部署程式。
- [ ] 驗證 SHA-256、RFC 3161 時間戳記、憑證信任鏈與驗簽失敗即停止發布；
  完成 Authenticode 後才計算最終雜湊及 Ed25519 更新簽章。
- [ ] 在乾淨 Windows VM 驗收實際安裝、升級、x64／32 位元文字宿主輸入及移除。
- [ ] 釐清與 Certum、unsigned 備援的啟用條件，避免同次發布混用或簽章失敗時自動降級。
- [ ] 確認實際服務已提供且正式發布驗收完成後，再更新 README、正式簽章政策、
  發布文件與服務致謝；已發布資產不原地替換。

## 暫存的致謝文字

下列文字原列於 README，現移至此處作為未來啟用後的候選文案。
完成上述確認前，不作為目前專案已獲服務的宣告：

> Free code signing provided by [SignPath.io](https://signpath.io/), certificate
> by [SignPath Foundation](https://signpath.org/).
