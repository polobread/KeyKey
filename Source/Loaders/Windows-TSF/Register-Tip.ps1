[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $DllPath,

    [switch] $Unregister
)

$ErrorActionPreference = 'Stop'
$resolvedDll = (Resolve-Path -LiteralPath $DllPath).Path

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -DllPath "{1}"' `
        -f $PSCommandPath, $resolvedDll
    if ($Unregister) {
        $arguments += ' -Unregister'
    }
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments `
        -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

$systemDirectory = [Environment]::SystemDirectory
$regsvr32 = Join-Path $systemDirectory 'regsvr32.exe'

if (-not $Unregister) {
    # Modern Windows text hosts run with an app-container identity. Grant the
    # built-in ALL APPLICATION PACKAGES SID read-only access to the TIP and its
    # runtime data so Start/Search can load the DLL and open KeyKey.db.
    $moduleDirectory = Split-Path -Parent $resolvedDll
    $icacls = Join-Path $systemDirectory 'icacls.exe'
    $readableFiles = @(
        $resolvedDll,
        (Join-Path $moduleDirectory 'KeyKeySettings.exe')
    )
    foreach ($file in $readableFiles) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            & $icacls $file /grant '*S-1-15-2-1:(RX)' /q
            if ($LASTEXITCODE -ne 0) {
                throw "Could not grant app-container read access to: $file"
            }
        }
    }

    $databaseDirectory = Join-Path $moduleDirectory 'Databases'
    if (Test-Path -LiteralPath $databaseDirectory -PathType Container) {
        & $icacls $databaseDirectory /grant '*S-1-15-2-1:(OI)(CI)(RX)' /q
        if ($LASTEXITCODE -ne 0) {
            throw "Could not grant app-container read access to: $databaseDirectory"
        }
    }
}

$arguments = @('/s')
if ($Unregister) {
    $arguments += '/u'
}
$arguments += $resolvedDll

& $regsvr32 $arguments
if ($LASTEXITCODE -ne 0) {
    throw "regsvr32 failed with exit code $LASTEXITCODE."
}

$tip = '0404:{828E3CF0-11E9-45FC-A5DB-394991AD0093}{BED5C2CB-27F6-455D-AB13-CD2BB19B670B}'
$languageList = Get-WinUserLanguageList
$languageListChanged = $false
if ($Unregister) {
    foreach ($language in $languageList) {
        if ($language.InputMethodTips -contains $tip) {
            [void]$language.InputMethodTips.Remove($tip)
            $languageListChanged = $true
        }
    }
}
else {
    $traditionalChinese = $languageList |
        Where-Object LanguageTag -eq 'zh-Hant-TW' |
        Select-Object -First 1
    if (-not $traditionalChinese) {
        $traditionalChinese = New-WinUserLanguageList 'zh-Hant-TW'
        $languageList += $traditionalChinese
        $languageListChanged = $true
    }
    if ($traditionalChinese.InputMethodTips -notcontains $tip) {
        [void]$traditionalChinese.InputMethodTips.Add($tip)
        $languageListChanged = $true
    }
}
if ($languageListChanged) {
    Set-WinUserLanguageList $languageList -Force
}

$operation = if ($Unregister) { 'Unregistered' } else { 'Registered' }
# Keep this script ASCII-only because Windows PowerShell 5 treats UTF-8 files
# without a BOM as the current ANSI code page. The registered profile itself
# still uses the Unicode description from Guids.h.
Write-Host "$operation KeyKey TSF: $resolvedDll"
