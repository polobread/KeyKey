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

$packageInfoPath = Join-Path $PSScriptRoot 'PackageInfo.json'
$payloadDirectory = Join-Path $PSScriptRoot 'Payload'
if (-not (Test-Path -LiteralPath $packageInfoPath -PathType Leaf)) {
    throw 'PackageInfo.json is missing. Extract the complete ZIP before installing.'
}

$packageInfo = Get-Content -LiteralPath $packageInfoPath -Raw | ConvertFrom-Json
$nativeArchitecture = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITEW6432')
if (-not $nativeArchitecture) {
    $nativeArchitecture = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE')
}
if ($packageInfo.architecture -eq 'x64' -and $nativeArchitecture -ne 'AMD64') {
    throw "This is an x64 package, but Windows reports $nativeArchitecture."
}
if ($packageInfo.architecture -eq 'arm64' -and $nativeArchitecture -ne 'ARM64') {
    throw "This is an ARM64 package, but Windows reports $nativeArchitecture."
}

foreach ($relativePath in 'KeyKeyTsf.dll', 'KeyKeySettings.exe',
         'Databases\KeyKey.db') {
    $sourcePath = Join-Path $payloadDirectory $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "The installation payload is incomplete: $relativePath"
    }
}

$installDirectory = Join-Path $env:ProgramFiles 'chichi77 KeyKey'
$classId = '{828E3CF0-11E9-45FC-A5DB-394991AD0093}'
$classRegistryPath = "Registry::HKEY_CLASSES_ROOT\CLSID\$classId\InprocServer32"
$regsvr32 = Join-Path ([Environment]::SystemDirectory) 'regsvr32.exe'

if (Test-Path -LiteralPath $classRegistryPath) {
    $registeredDll = (Get-Item -LiteralPath $classRegistryPath).GetValue('')
    if ($registeredDll -and (Test-Path -LiteralPath $registeredDll -PathType Leaf)) {
        & $regsvr32 /s /u $registeredDll
        if ($LASTEXITCODE -ne 0) {
            throw "Could not unregister the previous installation: $registeredDll"
        }
    }
}

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $payloadDirectory 'KeyKeyTsf.dll') `
    -Destination $installDirectory -Force
Copy-Item -LiteralPath (Join-Path $payloadDirectory 'KeyKeySettings.exe') `
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

$installedDll = Join-Path $installDirectory 'KeyKeyTsf.dll'
& $regsvr32 /s $installedDll
if ($LASTEXITCODE -ne 0) {
    throw "TSF registration failed with exit code $LASTEXITCODE."
}

$tip = '0404:{828E3CF0-11E9-45FC-A5DB-394991AD0093}{BED5C2CB-27F6-455D-AB13-CD2BB19B670B}'
$languageList = Get-WinUserLanguageList
$traditionalChinese = $languageList |
    Where-Object LanguageTag -eq 'zh-Hant-TW' |
    Select-Object -First 1
if (-not $traditionalChinese) {
    $traditionalChinese = New-WinUserLanguageList 'zh-Hant-TW'
    $languageList += $traditionalChinese
}
if ($traditionalChinese.InputMethodTips -notcontains $tip) {
    [void]$traditionalChinese.InputMethodTips.Add($tip)
    Set-WinUserLanguageList $languageList -Force
}

$uninstallRegistryPath = `
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\chichi77KeyKey'
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
Write-Host 'Sign out and sign back in, then add the input method under'
Write-Host 'Settings > Time & language > Language & region > Chinese (Traditional).'
