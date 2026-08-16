[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Regsvr32 {
    param(
        [Parameter(Mandatory = $true)][string] $Tool,
        [Parameter(Mandatory = $true)][string] $Dll
    )

    $arguments = '/s /u "{0}"' -f $Dll
    $process = Start-Process -FilePath $Tool -ArgumentList $arguments `
        -WindowStyle Hidden -Wait -PassThru
    return $process.ExitCode
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

$nativeRegsvr32 = Join-Path $env:SystemRoot 'System32\regsvr32.exe'
$x86Regsvr32 = Join-Path $env:SystemRoot 'SysWOW64\regsvr32.exe'
$registrations = @(
    @{ Dll = 'KeyKeyTsf_x86.dll'; Tool = $x86Regsvr32 },
    @{ Dll = 'KeyKeyTsf_x64.dll'; Tool = $nativeRegsvr32 },
    @{ Dll = 'KeyKeyTsf_arm64.dll'; Tool = $nativeRegsvr32 },
    @{ Dll = 'KeyKeyTsf.dll'; Tool = $nativeRegsvr32 }
)
foreach ($registration in $registrations) {
    $installedDll = Join-Path $installDirectory $registration.Dll
    if (-not (Test-Path -LiteralPath $installedDll -PathType Leaf)) {
        continue
    }
    $registrationExitCode = Invoke-Regsvr32 `
        -Tool $registration.Tool -Dll $installedDll
    if ($registrationExitCode -ne 0) {
        throw "TSF unregistration failed for $($registration.Dll) with exit code $registrationExitCode."
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
