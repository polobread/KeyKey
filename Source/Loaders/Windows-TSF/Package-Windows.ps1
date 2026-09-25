[CmdletBinding()]
param(
    [string] $BuildDirectory = (Join-Path $PSScriptRoot 'out\build\x64-ninja'),

    [string] $X86BuildDirectory = (Join-Path $PSScriptRoot 'out\build\x86'),

    [ValidateSet('x64', 'x86')]
    [string] $Architecture = 'x64',

    [ValidatePattern('^[0-9]+(?:\.[0-9]+){1,3}$')]
    [string] $Version = '1.3.0'
)

$ErrorActionPreference = 'Stop'

$resolvedBuildDirectory = (Resolve-Path -LiteralPath $BuildDirectory).Path
function Resolve-BuildArtifact {
    param(
        [Parameter(Mandatory = $true)][string] $Directory,
        [Parameter(Mandatory = $true)][string] $RelativePath
    )

    foreach ($candidate in @(
        (Join-Path $Directory $RelativePath),
        (Join-Path (Join-Path $Directory 'Release') $RelativePath)
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    throw "Required build output was not found under $Directory`: $RelativePath"
}

$databasePath = Resolve-BuildArtifact $resolvedBuildDirectory 'Databases\KeyKey.db'

if (-not (Test-Path -LiteralPath $X86BuildDirectory -PathType Container)) {
    throw "The x86 build directory was not found: $X86BuildDirectory. Build the windows-x86-release preset before packaging so 32-bit applications are supported."
}
$resolvedX86BuildDirectory = (Resolve-Path -LiteralPath $X86BuildDirectory).Path
$x86DllPath = Resolve-BuildArtifact $resolvedX86BuildDirectory 'KeyKeyTsf.dll'
$settingsBuildDirectory = if ($Architecture -eq 'x86') {
    $resolvedX86BuildDirectory
} else {
    $resolvedBuildDirectory
}
$settingsPath = Resolve-BuildArtifact $settingsBuildDirectory 'KeyKeySettings.exe'
$settingsBackendPath = Resolve-BuildArtifact $settingsBuildDirectory 'KeyKeySettingsBackend.dll'
if ($Architecture -eq 'x64') {
    $nativeDllPath = Resolve-BuildArtifact $resolvedBuildDirectory 'KeyKeyTsf.dll'
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$templateDirectory = Join-Path $PSScriptRoot 'Packaging'
$outputDirectory = Join-Path $PSScriptRoot 'out\package'
$packageName = "chichi77-KeyKey-$Version-windows-$Architecture"
$zipPath = Join-Path $outputDirectory "$packageName.zip"
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'chichi77-keykey-package-' + [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $temporaryRoot $packageName
$payloadDirectory = Join-Path $packageRoot 'Payload'
$databaseDirectory = Join-Path $payloadDirectory 'Databases'
$licenseDirectory = Join-Path $packageRoot 'LICENSES'

try {
    New-Item -ItemType Directory -Path $databaseDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $licenseDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

    if ($Architecture -eq 'x64') {
        Copy-Item -LiteralPath $nativeDllPath `
            -Destination (Join-Path $payloadDirectory 'KeyKeyTsf_x64.dll')
    }
    Copy-Item -LiteralPath $x86DllPath `
        -Destination (Join-Path $payloadDirectory 'KeyKeyTsf_x86.dll')
    Copy-Item -LiteralPath $settingsPath `
        -Destination $payloadDirectory
    Copy-Item -LiteralPath $settingsBackendPath `
        -Destination $payloadDirectory
    Copy-Item -LiteralPath $databasePath -Destination $databaseDirectory

    foreach ($template in 'Install.cmd', 'Install.ps1', 'Uninstall.cmd',
             'Uninstall.ps1', 'README.txt') {
        Copy-Item -LiteralPath (Join-Path $templateDirectory $template) `
            -Destination $packageRoot
    }

    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'README.md') `
        -Destination (Join-Path $licenseDirectory 'KeyKey-README.md')
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'LICENSE.txt') `
        -Destination (Join-Path $licenseDirectory 'KeyKey-LICENSE.txt')
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'LICENSING.md') `
        -Destination $licenseDirectory
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'LICENSES\MIT.txt') `
        -Destination (Join-Path $licenseDirectory 'MIT-Chui-Ping-Cheng.txt')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'LICENSE.txt') `
        -Destination (Join-Path $licenseDirectory 'Windows-TSF-LICENSE.txt')
    Copy-Item -LiteralPath (
        Join-Path $repositoryRoot 'DataSource\chichi77Collection\LICENSE.txt') `
        -Destination (Join-Path $licenseDirectory `
            'chichi77Collection-LICENSE.txt')
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'THIRD-PARTY-NOTICES.md') `
        -Destination $licenseDirectory

    [ordered]@{
        name = 'chichi77 KeyKey'
        version = $Version
        architecture = $Architecture
    } | ConvertTo-Json | Set-Content -LiteralPath `
        (Join-Path $packageRoot 'PackageInfo.json') -Encoding UTF8

    if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $zipPath `
        -CompressionLevel Optimal
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Host "Created Windows installation package:"
Write-Host $zipPath
