!include "LogicLib.nsh"
!include "MUI2.nsh"
!include "x64.nsh"
!include "WinVer.nsh"

!define PRODUCT_NAME "chichi77 KeyKey"
Unicode true
RequestExecutionLevel admin
ManifestDPIAware true
SetCompressor /SOLID lzma
CRCCheck on
Name "${PRODUCT_NAME}"
OutFile "${OUTPUT_FILE}"
Icon "${ICON_PATH}"
VIProductVersion "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "FileDescription" "${PRODUCT_NAME} installer"
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "CompanyName" "${PUBLISHER}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "See bundled license notices"
ShowInstDetails show
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_NOAUTOCLOSE
!define MUI_FINISHPAGE_REBOOTLATER_DEFAULT
!define MUI_FINISHPAGE_TEXT "$(FinishInstructions)"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSE_DIR}\LICENSING.md"
!insertmacro MUI_PAGE_LICENSE "${LICENSE_DIR}\Windows-Frontend-MIT.txt"
!insertmacro MUI_PAGE_LICENSE "${LICENSE_DIR}\KeyKey-LICENSE.txt"
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "TradChinese"
!insertmacro MUI_LANGUAGE "English"
LangString FinishInstructions ${LANG_TRADCHINESE} "台灣、香港、澳門共用一個琦琦入口。首次使用或原本選用舊香港／澳門入口者，請至 Windows 設定 → 時間與語言 → 繁體中文的語言選項 → 新增鍵盤，加入並選用琦琦輸入法。已加入共用入口者不必重加。升級後請登出再登入，載入新版。"
LangString FinishInstructions ${LANG_ENGLISH} "All regions share one KeyKey entry. New users and users of the retired Hong Kong/Macao entries: add and select KeyKey in Windows Settings > Time & language > Language options > Add a keyboard. Existing shared-entry users need not add it again. After upgrading, sign out and back in."

Function .onInit
  SetErrorLevel 0
  ${IfNot} ${AtLeastWin10}
    SetErrorLevel 1633
    Quit
  ${EndIf}
  ${IfNot} ${RunningX64}
    SetErrorLevel 1633
    Quit
  ${EndIf}
FunctionEnd

Section "Install"
  InitPluginsDir
  SetOutPath "$PLUGINSDIR\Package"
  File /oname=PackageManifest.json "${MANIFEST_PATH}"
  SetOutPath "$PLUGINSDIR\Package\Payload"
  File /r "${PAYLOAD_DIR}\*.*"
  ; The signed, self-contained tool is also the installed uninstaller.
  ; No unsigned NSIS-generated Uninstall.exe is embedded or generated.
  ClearErrors
  ExecWait '"$PLUGINSDIR\Package\Payload\KeyKeyDeployment.exe" install --package "$PLUGINSDIR\Package" --quiet' $0
  ${If} ${Errors}
    SetErrorLevel 1
    Abort "Could not start the deployment tool. Installation did not complete."
  ${EndIf}
  ${If} $0 == 3010
    SetRebootFlag true
    SetErrorLevel 3010
  ${ElseIf} $0 != 0
    SetErrorLevel $0
    Abort "Installation failed (error $0). Retain the package and error code; rerun to retry recovery."
  ${EndIf}
SectionEnd
