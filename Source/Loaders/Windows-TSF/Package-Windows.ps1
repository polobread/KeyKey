[CmdletBinding()]
param(
    [string] $BuildDirectory = (Join-Path $PSScriptRoot 'out\build\x64-ninja'),

    [ValidateSet('x64', 'arm64')]
    [string] $Architecture = 'x64',

    [ValidatePattern('^[0-9]+(?:\.[0-9]+){1,3}$')]
    [string] $Version = '1.2'
)

$ErrorActionPreference = 'Stop'

$resolvedBuildDirectory = (Resolve-Path -LiteralPath $BuildDirectory).Path
$databasePath = Join-Path $resolvedBuildDirectory 'Databases\KeyKey.db'
$requiredFiles = @(
    (Join-Path $resolvedBuildDirectory 'KeyKeyTsf.dll'),
    (Join-Path $resolvedBuildDirectory 'KeyKeySettings.exe'),
    $databasePath
)

foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required build output was not found: $requiredFile"
    }
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

    Copy-Item -LiteralPath (Join-Path $resolvedBuildDirectory 'KeyKeyTsf.dll') `
        -Destination $payloadDirectory
    Copy-Item -LiteralPath (Join-Path $resolvedBuildDirectory 'KeyKeySettings.exe') `
        -Destination $payloadDirectory
    Copy-Item -LiteralPath $databasePath -Destination $databaseDirectory

    foreach ($template in 'Install.cmd', 'Install.ps1', 'Uninstall.cmd',
             'Uninstall.ps1', 'README.txt') {
        Copy-Item -LiteralPath (Join-Path $templateDirectory $template) `
            -Destination $packageRoot
    }

    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'README.md') `
        -Destination (Join-Path $licenseDirectory 'KeyKey-README.md')
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
