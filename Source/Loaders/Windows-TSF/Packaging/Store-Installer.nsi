!include "LogicLib.nsh"
!include "MUI2.nsh"
!include "WordFunc.nsh"
!include "x64.nsh"

!insertmacro VersionCompare

!ifndef VERSION
  !error "VERSION is required."
!endif
!ifndef PRODUCT_VERSION
  !error "PRODUCT_VERSION is required."
!endif
!ifndef PUBLISHER
  !error "PUBLISHER is required."
!endif
!ifndef PAYLOAD_DIR
  !error "PAYLOAD_DIR is required."
!endif
!ifndef LICENSE_DIR
  !error "LICENSE_DIR is required."
!endif
!ifndef ICON_PATH
  !error "ICON_PATH is required."
!endif
!ifndef OUTPUT_FILE
  !error "OUTPUT_FILE is required."
!endif

!define PRODUCT_NAME "chichi77 KeyKey"
!define PRODUCT_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\chichi77KeyKey"
!define PRODUCT_URL "https://github.com/polobread/KeyKey"
!define VERSION_DIRECTORY "$INSTDIR\${VERSION}"

Unicode true
RequestExecutionLevel admin
ManifestDPIAware true
SetCompressor /SOLID lzma
SetCompressorDictSize 32
CRCCheck on
XPStyle on

Name "${PRODUCT_NAME}"
OutFile "${OUTPUT_FILE}"
InstallDir "$PROGRAMFILES64\chichi77 KeyKey"
Icon "${ICON_PATH}"
UninstallIcon "${ICON_PATH}"
ShowInstDetails show
ShowUninstDetails show
AutoCloseWindow true

VIProductVersion "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "FileDescription" "${PRODUCT_NAME} installer"
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "CompanyName" "${PUBLISHER}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "See bundled license notices"

!define MUI_ABORTWARNING
!define MUI_ICON "${ICON_PATH}"
!define MUI_UNICON "${ICON_PATH}"
!define MUI_FINISHPAGE_NOAUTOCLOSE
!define MUI_UNFINISHPAGE_NOAUTOCLOSE
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSE_DIR}\LICENSING.md"
!insertmacro MUI_PAGE_LICENSE "${LICENSE_DIR}\Windows-Frontend-MIT.txt"
!insertmacro MUI_PAGE_LICENSE "${LICENSE_DIR}\KeyKey-LICENSE.txt"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "TradChinese"
!insertmacro MUI_LANGUAGE "English"

Var PreviousVersionDirectory

!macro UnregisterTsfAt DIRECTORY
  ${If} ${FileExists} "${DIRECTORY}\KeyKeyTsf_x86.dll"
    ExecWait '"$WINDIR\SysWOW64\regsvr32.exe" /s /u "${DIRECTORY}\KeyKeyTsf_x86.dll"' $0
    ${If} $0 != 0
      SetErrorLevel $0
      Abort "Could not unregister the previous x86 text service (error $0)."
    ${EndIf}
  ${EndIf}

  ${If} ${FileExists} "${DIRECTORY}\KeyKeyTsf_x64.dll"
    ${DisableX64FSRedirection}
    ExecWait '"$SYSDIR\regsvr32.exe" /s /u "${DIRECTORY}\KeyKeyTsf_x64.dll"' $0
    ${EnableX64FSRedirection}
    ${If} $0 != 0
      SetErrorLevel $0
      Abort "Could not unregister the previous x64 text service (error $0)."
    ${EndIf}
  ${EndIf}

  ${If} ${FileExists} "${DIRECTORY}\KeyKeyTsf.dll"
    ${DisableX64FSRedirection}
    ExecWait '"$SYSDIR\regsvr32.exe" /s /u "${DIRECTORY}\KeyKeyTsf.dll"' $0
    ${EnableX64FSRedirection}
    ${If} $0 != 0
      SetErrorLevel $0
      Abort "Could not unregister the previous text service (error $0)."
    ${EndIf}
  ${EndIf}
!macroend

!macro RemoveKnownPayload DIRECTORY
  Delete /REBOOTOK "${DIRECTORY}\KeyKeyTsf_x64.dll"
  Delete /REBOOTOK "${DIRECTORY}\KeyKeyTsf_x86.dll"
  Delete /REBOOTOK "${DIRECTORY}\KeyKeyTsf_arm64.dll"
  Delete /REBOOTOK "${DIRECTORY}\KeyKeyTsf.dll"
  Delete /REBOOTOK "${DIRECTORY}\KeyKeySettings.exe"
  Delete /REBOOTOK "${DIRECTORY}\Install.cmd"
  Delete /REBOOTOK "${DIRECTORY}\Install.ps1"
  Delete /REBOOTOK "${DIRECTORY}\Uninstall.cmd"
  Delete /REBOOTOK "${DIRECTORY}\Uninstall.ps1"
  Delete /REBOOTOK "${DIRECTORY}\PackageInfo.json"
  Delete /REBOOTOK "${DIRECTORY}\README.txt"
  RMDir /r /REBOOTOK "${DIRECTORY}\Databases"
  RMDir /r /REBOOTOK "${DIRECTORY}\LICENSES"
!macroend

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "${PRODUCT_NAME} requires x64 Windows." /SD IDOK
    SetErrorLevel 1633
    Quit
  ${EndIf}

  SetShellVarContext all
  SetRegView 64
  ReadRegStr $0 HKLM "${PRODUCT_KEY}" "InstallLocation"
  ${If} $0 != ""
    StrCpy $INSTDIR $0
  ${EndIf}
  ReadRegStr $3 HKLM "${PRODUCT_KEY}" "DisplayVersion"
  ${If} $3 != ""
    ${VersionCompare} $3 "${VERSION}" $4
    ${If} $4 == 1
      MessageBox MB_OK|MB_ICONSTOP \
        "A newer version of ${PRODUCT_NAME} is already installed." /SD IDOK
      SetErrorLevel 1638
      Quit
    ${EndIf}
  ${EndIf}
  ReadRegStr $PreviousVersionDirectory HKLM "${PRODUCT_KEY}" "VersionLocation"
  ${If} $PreviousVersionDirectory == ""
    StrCpy $PreviousVersionDirectory $INSTDIR
  ${ElseIf} $PreviousVersionDirectory != $INSTDIR
    StrLen $1 $INSTDIR
    StrCpy $2 $PreviousVersionDirectory $1
    ${If} $2 != $INSTDIR
      StrCpy $PreviousVersionDirectory $INSTDIR
    ${Else}
      StrCpy $2 $PreviousVersionDirectory 1 $1
      ${If} $2 != "\"
        StrCpy $PreviousVersionDirectory $INSTDIR
      ${EndIf}
    ${EndIf}
  ${EndIf}
FunctionEnd

Function un.onInit
  ${IfNot} ${RunningX64}
    SetErrorLevel 1633
    Quit
  ${EndIf}
  SetShellVarContext all
  SetRegView 64
FunctionEnd

Section "Install"
  SetShellVarContext all
  SetRegView 64

  !insertmacro UnregisterTsfAt "$PreviousVersionDirectory"
  ${If} $PreviousVersionDirectory != $INSTDIR
    !insertmacro UnregisterTsfAt "$INSTDIR"
  ${EndIf}

  SetOutPath "${VERSION_DIRECTORY}"
  File "/oname=KeyKeyTsf_x64.dll" "${PAYLOAD_DIR}\KeyKeyTsf_x64.dll"
  File "/oname=KeyKeyTsf_x86.dll" "${PAYLOAD_DIR}\KeyKeyTsf_x86.dll"
  File "/oname=KeyKeySettings.exe" "${PAYLOAD_DIR}\KeyKeySettings.exe"
  File "/oname=README.md" "${LICENSE_DIR}\KeyKey-README.md"

  SetOutPath "${VERSION_DIRECTORY}\Databases"
  File "/oname=KeyKey.db" "${PAYLOAD_DIR}\Databases\KeyKey.db"

  SetOutPath "${VERSION_DIRECTORY}\LICENSES"
  File /r "${LICENSE_DIR}\*.*"

  ExecWait '"$SYSDIR\icacls.exe" "${VERSION_DIRECTORY}" /grant "*S-1-15-2-1:(OI)(CI)(RX)" /q' $0
  ${If} $0 != 0
    SetErrorLevel $0
    Abort "Could not grant read access to Windows text hosts (error $0)."
  ${EndIf}

  ${DisableX64FSRedirection}
  ExecWait '"$SYSDIR\regsvr32.exe" /s "${VERSION_DIRECTORY}\KeyKeyTsf_x64.dll"' $0
  ${EnableX64FSRedirection}
  ${If} $0 != 0
    SetErrorLevel $0
    Abort "Could not register the x64 text service (error $0)."
  ${EndIf}

  ExecWait '"$WINDIR\SysWOW64\regsvr32.exe" /s "${VERSION_DIRECTORY}\KeyKeyTsf_x86.dll"' $0
  ${If} $0 != 0
    ${DisableX64FSRedirection}
    ExecWait '"$SYSDIR\regsvr32.exe" /s /u "${VERSION_DIRECTORY}\KeyKeyTsf_x64.dll"' $1
    ${EnableX64FSRedirection}
    SetErrorLevel $0
    Abort "Could not register the x86 text service (error $0)."
  ${EndIf}

  ${If} $PreviousVersionDirectory != "${VERSION_DIRECTORY}"
    !insertmacro RemoveKnownPayload "$PreviousVersionDirectory"
    ${If} $PreviousVersionDirectory != $INSTDIR
      RMDir /REBOOTOK "$PreviousVersionDirectory"
    ${EndIf}
  ${EndIf}
  ${If} $PreviousVersionDirectory != $INSTDIR
    !insertmacro RemoveKnownPayload "$INSTDIR"
  ${EndIf}

  SetOutPath $INSTDIR
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortcut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME} Settings.lnk" \
    "${VERSION_DIRECTORY}\KeyKeySettings.exe"

  WriteRegStr HKLM "${PRODUCT_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "${PRODUCT_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${PRODUCT_KEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKLM "${PRODUCT_KEY}" "DisplayIcon" '"${VERSION_DIRECTORY}\KeyKeySettings.exe",0'
  WriteRegStr HKLM "${PRODUCT_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${PRODUCT_KEY}" "VersionLocation" "${VERSION_DIRECTORY}"
  WriteRegStr HKLM "${PRODUCT_KEY}" "URLInfoAbout" "${PRODUCT_URL}"
  WriteRegStr HKLM "${PRODUCT_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${PRODUCT_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${PRODUCT_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${PRODUCT_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  SetShellVarContext all
  SetRegView 64

  !insertmacro UnregisterTsfAt "${VERSION_DIRECTORY}"
  !insertmacro RemoveKnownPayload "${VERSION_DIRECTORY}"
  RMDir /REBOOTOK "${VERSION_DIRECTORY}"

  Delete "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME} Settings.lnk"
  RMDir "$SMPROGRAMS\${PRODUCT_NAME}"
  DeleteRegKey HKLM "${PRODUCT_KEY}"
  Delete /REBOOTOK "$INSTDIR\Uninstall.exe"
  RMDir /REBOOTOK "$INSTDIR"
SectionEnd
