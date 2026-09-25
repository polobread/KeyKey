[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-NetworkSource {
    param([Parameter(Mandatory = $true)][string] $Path)

    if ($Path.StartsWith('\\')) {
        return $true
    }
    try {
        $root = [IO.Path]::GetPathRoot($Path)
        if (-not $root) {
            return $false
        }
        $drive = New-Object IO.DriveInfo($root)
        return $drive.DriveType -eq [IO.DriveType]::Network
    }
    catch {
        return $false
    }
}

function Invoke-Regsvr32 {
    param(
        [Parameter(Mandatory = $true)][string] $Tool,
        [Parameter(Mandatory = $true)][string] $Dll,
        [switch] $Unregister
    )

    $arguments = '/s'
    if ($Unregister) {
        $arguments += ' /u'
    }
    $arguments += ' "{0}"' -f $Dll
    $process = Start-Process -FilePath $Tool -ArgumentList $arguments `
        -WindowStyle Hidden -Wait -PassThru
    return $process.ExitCode
}

if (-not (Test-Administrator)) {
    $launchScript = $PSCommandPath
    $stagingDirectory = $null
    if (Test-NetworkSource -Path $PSCommandPath) {
        $stagingDirectory = Join-Path ([IO.Path]::GetTempPath()) (
            'chichi77-keykey-install-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stagingDirectory | Out-Null
        Get-ChildItem -LiteralPath $PSScriptRoot -Force |
            Copy-Item -Destination $stagingDirectory -Recurse -Force
        $launchScript = Join-Path $stagingDirectory 'Install.ps1'
        Write-Host 'Network source detected; copied the installer to a local temporary directory.'
    }

    try {
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' `
            -f $launchScript
        $process = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        exit $process.ExitCode
    }
    finally {
        if ($stagingDirectory -and
            (Test-Path -LiteralPath $stagingDirectory -PathType Container)) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
        }
    }
}

$installLogPath = Join-Path ([IO.Path]::GetTempPath()) `
    'chichi77-keykey-install.log'
$transcriptStarted = $false
try {
    Start-Transcript -Path $installLogPath -Force | Out-Null
    $transcriptStarted = $true
}
catch {
    # Installation must remain possible if transcription is unavailable.
}

try {
$packageInfoPath = Join-Path $PSScriptRoot 'PackageInfo.json'
$payloadDirectory = Join-Path $PSScriptRoot 'Payload'
if (-not (Test-Path -LiteralPath $packageInfoPath -PathType Leaf)) {
    throw 'PackageInfo.json is missing. Extract the complete ZIP before installing.'
}

$packageInfo = Get-Content -LiteralPath $packageInfoPath -Raw | ConvertFrom-Json
$uninstallRegistryPath = `
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\chichi77KeyKey'
$previousVersion = (Get-ItemProperty -LiteralPath $uninstallRegistryPath `
    -Name DisplayVersion -ErrorAction SilentlyContinue).DisplayVersion
$isVersionUpgrade = $previousVersion -and `
    ([string]$previousVersion -ne [string]$packageInfo.version)
if ([Environment]::OSVersion.Version.Major -lt 10) {
    throw 'This package requires Windows 10 or later.'
}
$nativeArchitecture = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITEW6432')
if (-not $nativeArchitecture) {
    $nativeArchitecture = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE')
}
if (($packageInfo.architecture -eq 'x64' -and $nativeArchitecture -ne 'AMD64') -or
    ($packageInfo.architecture -eq 'x86' -and $nativeArchitecture -ne 'x86') -or
    $packageInfo.architecture -notin @('x64', 'x86')) {
    throw "Package architecture $($packageInfo.architecture) does not match Windows architecture $nativeArchitecture."
}

$tipDllNames = if ($packageInfo.architecture -eq 'x64') {
    @('KeyKeyTsf_x64.dll', 'KeyKeyTsf_x86.dll')
} else {
    @('KeyKeyTsf_x86.dll')
}

foreach ($relativePath in @($tipDllNames) + @('KeyKeySettings.exe',
         'KeyKeySettingsBackend.dll',
         'Databases\KeyKey.db')) {
    $sourcePath = Join-Path $payloadDirectory $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "The installation payload is incomplete: $relativePath"
    }
}

$installDirectory = Join-Path $env:ProgramFiles 'chichi77 KeyKey'
$nativeRegsvr32 = Join-Path $env:SystemRoot 'System32\regsvr32.exe'
$x86Regsvr32 = if ($packageInfo.architecture -eq 'x64') {
    Join-Path $env:SystemRoot 'SysWOW64\regsvr32.exe'
} else {
    $nativeRegsvr32
}

# Remove both registry views before replacing an earlier single- or
# dual-architecture installation. A 32-bit Office process can only load the
# x86 in-process TSF DLL, while native Windows applications load the x64 DLL.
foreach ($oldRegistration in @(
    @{ Dll = (Join-Path $installDirectory 'KeyKeyTsf_x86.dll'); Tool = $x86Regsvr32 },
    @{ Dll = (Join-Path $installDirectory 'KeyKeyTsf_x64.dll'); Tool = $nativeRegsvr32 },
    @{ Dll = (Join-Path $installDirectory 'KeyKeyTsf_arm64.dll'); Tool = $nativeRegsvr32 },
    @{ Dll = (Join-Path $installDirectory 'KeyKeyTsf.dll'); Tool = $nativeRegsvr32 }
)) {
    if (Test-Path -LiteralPath $oldRegistration.Dll -PathType Leaf) {
        $registrationExitCode = Invoke-Regsvr32 `
            -Tool $oldRegistration.Tool -Dll $oldRegistration.Dll -Unregister
        if ($registrationExitCode -ne 0) {
            throw "Could not unregister the previous installation ($registrationExitCode): $($oldRegistration.Dll)"
        }
    }
}

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
foreach ($dllName in $tipDllNames) {
    Copy-Item -LiteralPath (Join-Path $payloadDirectory $dllName) `
        -Destination $installDirectory -Force
}
Copy-Item -LiteralPath (Join-Path $payloadDirectory 'KeyKeySettings.exe') `
    -Destination $installDirectory -Force
Copy-Item -LiteralPath (Join-Path $payloadDirectory 'KeyKeySettingsBackend.dll') `
    -Destination $installDirectory -Force
Copy-Item -LiteralPath (Join-Path $payloadDirectory 'Databases') `
    -Destination $installDirectory -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') `
    -Destination $installDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.txt') `
    -Destination $installDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PackageInfo.json') `
    -Destination $installDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'LICENSES') `
    -Destination $installDirectory -Recurse -Force

# Immersive Windows text hosts use an app-container identity. The TIP and its
# database need explicit read-only access when loaded by Start/Search or Store
# apps. S-1-15-2-1 is the built-in ALL APPLICATION PACKAGES SID.
$icacls = Join-Path ([Environment]::SystemDirectory) 'icacls.exe'
& $icacls $installDirectory /grant '*S-1-15-2-1:(OI)(CI)(RX)' /q
if ($LASTEXITCODE -ne 0) {
    throw 'Could not grant app-container read access to the installation.'
}

$registrations = @()
if ($packageInfo.architecture -eq 'x64') {
    $registrations += @{ Dll = 'KeyKeyTsf_x64.dll'; Tool = $nativeRegsvr32 }
}
$registrations += @{ Dll = 'KeyKeyTsf_x86.dll'; Tool = $x86Regsvr32 }
foreach ($registration in $registrations) {
    $installedDll = Join-Path $installDirectory $registration.Dll
    $registrationExitCode = Invoke-Regsvr32 `
        -Tool $registration.Tool -Dll $installedDll
    if ($registrationExitCode -ne 0) {
        throw "TSF registration failed for $($registration.Dll) with exit code $registrationExitCode."
    }
}

$uninstallCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' `
    -f (Join-Path $installDirectory 'Uninstall.ps1')
$displayName = ([char]0x7426).ToString() + [char]0x7426 + [char]0x8F38 + `
    [char]0x5165 + [char]0x6CD5
New-Item -Path $uninstallRegistryPath -Force | Out-Null
New-ItemProperty -Path $uninstallRegistryPath -Name DisplayName `
    -Value $displayName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallRegistryPath -Name DisplayVersion `
    -Value ([string]$packageInfo.version) -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallRegistryPath -Name Publisher `
    -Value 'polobread' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallRegistryPath -Name InstallLocation `
    -Value $installDirectory -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallRegistryPath -Name DisplayIcon `
    -Value (Join-Path $installDirectory 'KeyKeySettings.exe') `
    -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallRegistryPath -Name UninstallString `
    -Value $uninstallCommand -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallRegistryPath -Name NoModify `
    -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $uninstallRegistryPath -Name NoRepair `
    -Value 1 -PropertyType DWord -Force | Out-Null

Write-Host ''
Write-Host 'chichi77 KeyKey was installed successfully.'
Write-Host "Location: $installDirectory"
if ($isVersionUpgrade) {
    Write-Host 'Upgrade complete. Sign out of Windows and sign back in so the taskbar input method menu loads the new settings page.'
} else {
    Write-Host 'Sign out and sign back in if the input method is not listed yet, then add it under'
    Write-Host 'Settings > Time & language > Language & region > Traditional Chinese (Taiwan, Hong Kong, or Macao).'
}
}
catch {
    Write-Host ''
    Write-Host "Installation failed: $($_.Exception.Message)" `
        -ForegroundColor Red
    Write-Host "Diagnostic log: $installLogPath"
    exit 1
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
