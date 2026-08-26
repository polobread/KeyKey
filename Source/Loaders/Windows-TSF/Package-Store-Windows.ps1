[CmdletBinding(DefaultParameterSetName = 'Signed')]
param(
    [string] $BuildDirectory = (Join-Path $PSScriptRoot 'out\build\x64-ninja'),

    [string] $X86BuildDirectory = (Join-Path $PSScriptRoot 'out\build\x86'),

    [ValidatePattern('^[0-9]+(?:\.[0-9]+){1,3}$')]
    [string] $Version,

    [ValidatePattern('^[^"\r\n]+$')]
    [string] $Publisher = 'chichi77 KeyKey',

    [string] $MakensisPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Signed')]
    [string] $CertificateThumbprint,

    [Parameter(Mandatory = $true, ParameterSetName = 'Signed')]
    [uri] $TimestampUrl,

    [Parameter(ParameterSetName = 'Signed')]
    [ValidateSet('CurrentUser', 'LocalMachine')]
    [string] $CertificateStoreLocation = 'CurrentUser',

    [Parameter(ParameterSetName = 'Signed')]
    [string] $SignToolPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'UnsignedTest')]
    [switch] $UnsignedTest
)

$ErrorActionPreference = 'Stop'
$requiredNsisVersion = [version]'3.12'

if (-not $Version) {
    $cmakeContents = Get-Content -LiteralPath `
        (Join-Path $PSScriptRoot 'CMakeLists.txt') -Raw -Encoding UTF8
    if ($cmakeContents -notmatch
        'project\(KeyKeyWindowsTsf VERSION ([0-9]+(?:\.[0-9]+){1,3}) LANGUAGES C CXX\)') {
        throw 'Could not read the Windows product version from CMakeLists.txt.'
    }
    $Version = $Matches[1]
}

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
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Required build output was not found under $Directory`: $RelativePath"
}

function Assert-PeMachine {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][uint16] $ExpectedMachine,
        [Parameter(Mandatory = $true)][string] $Description
    )

    $stream = [IO.File]::Open($FilePath, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object IO.BinaryReader($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a Windows PE file: $FilePath"
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0 -or $peOffset -gt ($stream.Length - 6)) {
            throw "Invalid Windows PE header offset: $FilePath"
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Invalid Windows PE signature: $FilePath"
        }
        $machine = $reader.ReadUInt16()
        if ($machine -ne $ExpectedMachine) {
            throw ('{0} has PE machine 0x{1:x4}; expected 0x{2:x4}: {3}' -f
                $Description, $machine, $ExpectedMachine, $FilePath)
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Resolve-Makensis {
    param([string] $RequestedPath)

    if ($RequestedPath) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "makensis.exe was not found: $RequestedPath"
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) `
            'NSIS\makensis.exe'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) `
            'NSIS\makensis.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    if ($candidates.Count -gt 0) {
        return (Resolve-Path -LiteralPath $candidates[0]).Path
    }

    throw 'makensis.exe was not found. Install NSIS 3.12 or pass -MakensisPath.'
}

function Assert-MakensisVersion {
    param(
        [Parameter(Mandatory = $true)][string] $ToolPath,
        [Parameter(Mandatory = $true)][version] $RequiredVersion
    )

    $versionOutput = (& $ToolPath /VERSION 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or
        $versionOutput -notmatch '(?i)^v?([0-9]+\.[0-9]+)') {
        throw "Could not determine the NSIS version from: $ToolPath"
    }
    $actualVersion = [version]$Matches[1]
    if ($actualVersion -ne $RequiredVersion) {
        throw "NSIS $RequiredVersion is required; found $actualVersion at $ToolPath."
    }
}

function Resolve-SignTool {
    param([string] $RequestedPath)

    if ($RequestedPath) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "SignTool was not found: $RequestedPath"
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $sdkBinRoot = Join-Path $programFilesX86 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $sdkBinRoot -PathType Container) {
        $candidates = @(Get-ChildItem -LiteralPath $sdkBinRoot -Directory |
            Where-Object Name -Match '^\d+\.\d+\.\d+\.\d+$' |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\signtool.exe' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
        if ($candidates.Count -gt 0) {
            return $candidates[0]
        }
    }

    throw 'SignTool.exe was not found. Install the Windows SDK or pass -SignToolPath.'
}

function Assert-SigningCertificate {
    param(
        [Parameter(Mandatory = $true)][string] $Thumbprint,
        [Parameter(Mandatory = $true)][string] $StoreLocation
    )

    $certificatePath = "Cert:\$StoreLocation\My\$Thumbprint"
    if (-not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) {
        throw "The signing certificate was not found: $certificatePath"
    }

    $certificate = Get-Item -LiteralPath $certificatePath
    if (-not $certificate.HasPrivateKey) {
        throw 'The selected certificate does not expose an accessible private key.'
    }
    if ($certificate.NotBefore -gt (Get-Date) -or
        $certificate.NotAfter -lt (Get-Date)) {
        throw 'The selected certificate is not currently valid.'
    }

    $codeSigningOid = '1.3.6.1.5.5.7.3.3'
    $hasCodeSigningUsage = $certificate.EnhancedKeyUsageList |
        Where-Object { $_.ObjectId.Value -eq $codeSigningOid }
    if (-not $hasCodeSigningUsage) {
        throw 'The selected certificate is not valid for code signing.'
    }
}

function Invoke-SignFiles {
    param(
        [Parameter(Mandatory = $true)][string[]] $FilePath,
        [Parameter(Mandatory = $true)][string] $ToolPath,
        [Parameter(Mandatory = $true)][string] $Thumbprint,
        [Parameter(Mandatory = $true)][uri] $Rfc3161TimestampUrl,
        [Parameter(Mandatory = $true)][string] $StoreLocation
    )

    $arguments = @('sign', '/sha1', $Thumbprint, '/s', 'My')
    if ($StoreLocation -eq 'LocalMachine') {
        $arguments += '/sm'
    }
    $arguments += @(
        '/fd', 'SHA256',
        '/tr', $Rfc3161TimestampUrl.AbsoluteUri,
        '/td', 'SHA256',
        '/d', 'chichi77 KeyKey',
        '/v'
    )
    $arguments += $FilePath

    & $ToolPath @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Signing failed: $($FilePath -join ', ')"
    }
}

function Invoke-VerifySignature {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string] $ToolPath
    )

    & $ToolPath verify /pa /all /v $FilePath
    if ($LASTEXITCODE -ne 0) {
        throw "Signature verification failed: $FilePath"
    }
}

$resolvedBuildDirectory = (Resolve-Path -LiteralPath $BuildDirectory).Path
$resolvedX86BuildDirectory = (Resolve-Path -LiteralPath $X86BuildDirectory).Path
$x64DllPath = Resolve-BuildArtifact $resolvedBuildDirectory 'KeyKeyTsf.dll'
$x86DllPath = Resolve-BuildArtifact $resolvedX86BuildDirectory 'KeyKeyTsf.dll'
$settingsPath = Resolve-BuildArtifact $resolvedBuildDirectory 'KeyKeySettings.exe'
$databasePath = Resolve-BuildArtifact $resolvedBuildDirectory 'Databases\KeyKey.db'
Assert-PeMachine -FilePath $x64DllPath -ExpectedMachine 0x8664 `
    -Description 'The x64 TSF DLL'
Assert-PeMachine -FilePath $x86DllPath -ExpectedMachine 0x014C `
    -Description 'The x86 TSF DLL'
Assert-PeMachine -FilePath $settingsPath -ExpectedMachine 0x8664 `
    -Description 'The settings executable'
$resolvedMakensis = Resolve-Makensis -RequestedPath $MakensisPath
Assert-MakensisVersion -ToolPath $resolvedMakensis `
    -RequiredVersion $requiredNsisVersion

$versionParts = @($Version.Split('.') | ForEach-Object { [int]$_ })
if ($versionParts | Where-Object { $_ -gt 65535 }) {
    throw 'Each installer version component must be between 0 and 65535.'
}
while ($versionParts.Count -lt 4) {
    $versionParts += 0
}
$productVersion = $versionParts[0..3] -join '.'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$packagingDirectory = Join-Path $PSScriptRoot 'Packaging'
$nsisSourcePath = Join-Path $packagingDirectory 'Store-Installer.nsi'
$outputDirectory = Join-Path $PSScriptRoot 'out\store-package'
$workDirectory = Join-Path $outputDirectory (
    '.work-' + [Guid]::NewGuid().ToString('N'))
$payloadDirectory = Join-Path $workDirectory 'Payload'
$databaseDirectory = Join-Path $payloadDirectory 'Databases'
$licenseDirectory = Join-Path $workDirectory 'LICENSES'
$unsignedSuffix = if ($UnsignedTest) { '.unsigned' } else { '' }
$installerPath = Join-Path $outputDirectory (
    "chichi77-KeyKey-$Version-windows-x64-setup$unsignedSuffix.exe")
$checksumPath = "$installerPath.sha256"
$builtInstallerPath = Join-Path $workDirectory (
    "chichi77-KeyKey-$Version-windows-x64-setup$unsignedSuffix.exe")

$normalizedThumbprint = $null
$resolvedSignTool = $null
if (-not $UnsignedTest) {
    if ($TimestampUrl.Scheme -notin @('http', 'https')) {
        throw 'The RFC 3161 timestamp URL must use HTTP or HTTPS.'
    }
    $normalizedThumbprint = $CertificateThumbprint -replace '[^0-9A-Fa-f]', ''
    if ($normalizedThumbprint.Length -ne 40) {
        throw 'The certificate thumbprint must be a 40-character SHA-1 hexadecimal value.'
    }
    Assert-SigningCertificate -Thumbprint $normalizedThumbprint `
        -StoreLocation $CertificateStoreLocation
    $resolvedSignTool = Resolve-SignTool -RequestedPath $SignToolPath
}

try {
    New-Item -ItemType Directory -Path $databaseDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $licenseDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

    $stagedX64Dll = Join-Path $payloadDirectory 'KeyKeyTsf_x64.dll'
    $stagedX86Dll = Join-Path $payloadDirectory 'KeyKeyTsf_x86.dll'
    $stagedSettings = Join-Path $payloadDirectory 'KeyKeySettings.exe'
    Copy-Item -LiteralPath $x64DllPath -Destination $stagedX64Dll
    Copy-Item -LiteralPath $x86DllPath -Destination $stagedX86Dll
    Copy-Item -LiteralPath $settingsPath -Destination $stagedSettings
    Copy-Item -LiteralPath $databasePath -Destination $databaseDirectory

    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'README.md') `
        -Destination (Join-Path $licenseDirectory 'KeyKey-README.md')
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'LICENSE.txt') `
        -Destination (Join-Path $licenseDirectory 'KeyKey-LICENSE.txt')
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'LICENSING.md') `
        -Destination $licenseDirectory
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'LICENSES\MIT.txt') `
        -Destination (Join-Path $licenseDirectory 'Windows-Frontend-MIT.txt')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'LICENSE.txt') `
        -Destination (Join-Path $licenseDirectory 'Windows-TSF-LICENSE.txt')
    Copy-Item -LiteralPath (
        Join-Path $repositoryRoot 'DataSource\chichi77Collection\LICENSE.txt') `
        -Destination (Join-Path $licenseDirectory `
            'chichi77Collection-LICENSE.txt')
    Copy-Item -LiteralPath (
        Join-Path $repositoryRoot 'THIRD-PARTY-NOTICES.md') `
        -Destination $licenseDirectory

    if (-not $UnsignedTest) {
        $peFiles = @($stagedX64Dll, $stagedX86Dll, $stagedSettings)
        Invoke-SignFiles -FilePath $peFiles -ToolPath $resolvedSignTool `
            -Thumbprint $normalizedThumbprint `
            -Rfc3161TimestampUrl $TimestampUrl `
            -StoreLocation $CertificateStoreLocation
        foreach ($file in $peFiles) {
            Invoke-VerifySignature -FilePath $file -ToolPath $resolvedSignTool
        }
    }

    if (-not (Test-Path -LiteralPath $nsisSourcePath -PathType Leaf)) {
        throw "The NSIS source is missing: $nsisSourcePath"
    }
    $makensisArguments = @(
        '/V4',
        "/DVERSION=$Version",
        "/DPRODUCT_VERSION=$productVersion",
        "/DPUBLISHER=$Publisher",
        "/DPAYLOAD_DIR=$payloadDirectory",
        "/DLICENSE_DIR=$licenseDirectory",
        "/DICON_PATH=$(Join-Path $PSScriptRoot 'chichi77.ico')",
        "/DOUTPUT_FILE=$builtInstallerPath",
        $nsisSourcePath
    )
    & $resolvedMakensis @makensisArguments
    if ($LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $builtInstallerPath -PathType Leaf)) {
        throw 'NSIS could not build the installer.'
    }

    if (-not $UnsignedTest) {
        Invoke-SignFiles -FilePath $builtInstallerPath `
            -ToolPath $resolvedSignTool `
            -Thumbprint $normalizedThumbprint `
            -Rfc3161TimestampUrl $TimestampUrl `
            -StoreLocation $CertificateStoreLocation
        Invoke-VerifySignature -FilePath $builtInstallerPath `
            -ToolPath $resolvedSignTool
    }

    if (Test-Path -LiteralPath $installerPath -PathType Leaf) {
        Remove-Item -LiteralPath $installerPath -Force
    }
    if (Test-Path -LiteralPath $checksumPath -PathType Leaf) {
        Remove-Item -LiteralPath $checksumPath -Force
    }
    Move-Item -LiteralPath $builtInstallerPath -Destination $installerPath

    $hash = (Get-FileHash -LiteralPath $installerPath `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $(Split-Path -Leaf $installerPath)" |
        Set-Content -LiteralPath $checksumPath -Encoding ascii
}
finally {
    if (Test-Path -LiteralPath $workDirectory -PathType Container) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force
    }
}

if ($UnsignedTest) {
    Write-Warning 'Created an unsigned test EXE. It is not eligible for Store submission.'
}
else {
    Write-Host 'Created and verified signed Store installer:'
}
Write-Host $installerPath
Write-Host $checksumPath
