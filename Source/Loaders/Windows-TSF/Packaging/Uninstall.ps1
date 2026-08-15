[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments `
        -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

$uninstallRegistryPath = `
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\chichi77KeyKey'
$installDirectory = Join-Path $env:ProgramFiles 'chichi77 KeyKey'
if (Test-Path -LiteralPath $uninstallRegistryPath) {
    $registeredLocation = (Get-ItemProperty -LiteralPath $uninstallRegistryPath `
        -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
    if ($registeredLocation) {
        $installDirectory = $registeredLocation
    }
}

$installedDll = Join-Path $installDirectory 'KeyKeyTsf.dll'
if (Test-Path -LiteralPath $installedDll -PathType Leaf) {
    $regsvr32 = Join-Path ([Environment]::SystemDirectory) 'regsvr32.exe'
    & $regsvr32 /s /u $installedDll
    if ($LASTEXITCODE -ne 0) {
        throw "TSF unregistration failed with exit code $LASTEXITCODE."
    }
}

$tip = '0404:{828E3CF0-11E9-45FC-A5DB-394991AD0093}{BED5C2CB-27F6-455D-AB13-CD2BB19B670B}'
$languageList = Get-WinUserLanguageList
$languageListChanged = $false
foreach ($language in $languageList) {
    if ($language.InputMethodTips -contains $tip) {
        [void]$language.InputMethodTips.Remove($tip)
        $languageListChanged = $true
    }
}
if ($languageListChanged) {
    Set-WinUserLanguageList $languageList -Force
}

if (Test-Path -LiteralPath $uninstallRegistryPath) {
    Remove-Item -LiteralPath $uninstallRegistryPath -Recurse -Force
}
if (Test-Path -LiteralPath $installDirectory -PathType Container) {
    Remove-Item -LiteralPath $installDirectory -Recurse -Force
}

Write-Host ''
Write-Host 'chichi77 KeyKey was uninstalled successfully.'
Write-Host 'User preferences were kept in the current user profile.'
Write-Host 'Sign out and sign back in if the input method still appears temporarily.'
