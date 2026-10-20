# Local release entry point. Requires Windows, VS 2026 C++, CMake, Ruby and .NET 10.
[CmdletBinding()]
param(
    [ValidateSet('Build', 'Sign', 'Publish')][string] $Action = 'Build',
    [Parameter(Mandatory = $true)][ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+(?:-beta[1-9][0-9]*)?$')][string] $ReleaseTag,
    [string] $Python = 'python',
    [string] $OutputDirectory,
    [string] $MakensisPath,
    [string] $SignToolPath,
    [string] $OpenSslPath,
    [ValidateSet('CurrentUser', 'LocalMachine')][string] $CertificateStoreLocation = 'CurrentUser',
    [uri] $TimestampUrl = 'http://time.certum.pl'
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$helper = Join-Path $repositoryRoot '.github\scripts\windows-signing.py'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot "out\local-release\$ReleaseTag" }
$releaseDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$ignored = & git -C $repositoryRoot check-ignore -- $releaseDirectory
if ($LASTEXITCODE -ne 0) { throw 'Release output directory must be ignored by Git (use out/local-release).' }
function Invoke-ReleaseHelper {
    param([string[]] $Arguments)
    $helperOutput = & $Python $helper @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Windows release operation stopped. No signing credentials were recorded.' }
    return $helperOutput
}
if ($Action -eq 'Publish') {
    $context = Get-Content -LiteralPath (Join-Path $releaseDirectory 'context.json') -Raw | ConvertFrom-Json
    if ($context.release_tag -ne $ReleaseTag) { throw 'Release directory belongs to another tag.' }
    $infoPath = Join-Path $releaseDirectory "signed\chichi77-KeyKey-$($context.version)-windows-build-info.json"
    $info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
    Write-Host "Release: $ReleaseTag; local source: $($context.source_sha)"
    foreach ($asset in $info.assets) { Write-Host "$($asset.name): $($asset.sha256)" }
    $digest = (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host "Build-info SHA-256 (binds all six release files): $digest"
    Write-Host 'Confirm EXE and both ZIPs passed clean-VM installation, upgrade, input and removal checks.'
    $confirmation = Read-Host "Type PUBLISH $ReleaseTag $digest to upload and request the CDN mirror"
    if ($confirmation -cne "PUBLISH $ReleaseTag $digest") { throw 'Publication was not approved.' }
    Invoke-ReleaseHelper -Arguments @('publish', '--tag', $ReleaseTag, '--directory', $releaseDirectory, '--approved-sha256', $digest)
    return
}
if ($Action -eq 'Build') {
    $context = (Invoke-ReleaseHelper -Arguments @('prepare', '--tag', $ReleaseTag, '--directory', $releaseDirectory)) | ConvertFrom-Json
    $config = Join-Path $releaseDirectory 'update-config.json'
    & $Python (Join-Path $repositoryRoot 'update\prepare.py') select-release --tag $ReleaseTag --version $context.version --out $config
    if ($LASTEXITCODE -ne 0) { throw 'Update configuration failed.' }
    $previousConfig = $env:KEYKEY_UPDATE_CONFIG
    try {
        $env:KEYKEY_UPDATE_CONFIG = $config
        $buildArguments = @{ OutputDirectory = Join-Path $releaseDirectory 'build'; Python = $Python }
        if ($OpenSslPath) { $buildArguments.OpenSslPath = $OpenSslPath }
        & (Join-Path $PSScriptRoot 'Build-WindowsRelease.ps1') @buildArguments
    } finally { $env:KEYKEY_UPDATE_CONFIG = $previousConfig }
    Invoke-ReleaseHelper -Arguments @('stage', '--directory', $releaseDirectory)
}
Invoke-ReleaseHelper -Arguments @('verify-built', '--directory', $releaseDirectory)
$context = Get-Content -LiteralPath (Join-Path $releaseDirectory 'context.json') -Raw | ConvertFrom-Json
if ($context.release_tag -ne $ReleaseTag) { throw 'Release directory belongs to another tag.' }
$signedDirectory = Join-Path $releaseDirectory 'signed'
if (Test-Path -LiteralPath $signedDirectory) { throw 'Signing output already exists. Preserve it; use a fresh release directory for a new attempt.' }
. (Join-Path $PSScriptRoot 'Packaging\Authenticode.ps1')
$tool = Resolve-SignTool -RequestedPath $SignToolPath
Write-Host 'Connect SimplySign Desktop using your phone token. Enter any PIN only in the provider dialog.'
$secureThumbprint = Read-Host 'Certificate thumbprint (hidden; memory only)' -AsSecureString
$thumbprintPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureThumbprint)
$thumbprint = $null
try {
    $thumbprint = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($thumbprintPointer) -replace '[^0-9A-Fa-f]', ''
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($thumbprintPointer)
    $secureThumbprint.Dispose()
}
try {
    if ($thumbprint.Length -ne 40) { throw 'Invalid certificate identifier.' }
    Assert-SigningCertificate -Thumbprint $thumbprint -StoreLocation $CertificateStoreLocation
    # Keep the authenticated build snapshot intact; sign disposable copies.
    $signedInputs = Join-Path $releaseDirectory ('signed-inputs-' + [Guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath (Join-Path $releaseDirectory 'inputs') -Destination $signedInputs -Recurse
    $peFiles = @(Get-ChildItem -LiteralPath $signedInputs -File -Recurse | Where-Object { $_.Extension -in @('.exe', '.dll') })
    Invoke-SignFiles -FilePath $peFiles.FullName -ToolPath $tool -Thumbprint $thumbprint -Rfc3161TimestampUrl $TimestampUrl -StoreLocation $CertificateStoreLocation
    foreach ($file in $peFiles) {
        Invoke-VerifySignature -FilePath $file.FullName -ToolPath $tool -ExpectedThumbprint $thumbprint
    }
    $packageArguments = @{
        BuildDirectory = Join-Path $signedInputs 'x64'; X86BuildDirectory = Join-Path $signedInputs 'x86'
        OutputDirectory = $signedDirectory; Version = $context.version
        TimestampUrl = $TimestampUrl; CertificateStoreLocation = $CertificateStoreLocation
        CertificateThumbprint = $thumbprint; SignToolPath = $tool; UseSignedPayload = $true
    }
    if ($MakensisPath) { $packageArguments.MakensisPath = $MakensisPath }
    & (Join-Path $PSScriptRoot 'Package-Store-Windows.ps1') @packageArguments
    foreach ($architecture in @('x64', 'x86')) {
        $zipArguments = @{
            BuildDirectory = Join-Path $signedInputs 'x64'; X86BuildDirectory = Join-Path $signedInputs 'x86'
            OutputDirectory = $signedDirectory; Version = $context.version; Architecture = $architecture
            Signed = $true; SignToolPath = $tool
        }
        & (Join-Path $PSScriptRoot 'Package-Windows.ps1') @zipArguments
    }
} finally {
    $thumbprint = $null
    if ($packageArguments) { $packageArguments.CertificateThumbprint = $null }
}
Invoke-ReleaseHelper -Arguments @('record', '--directory', $releaseDirectory)
Write-Host "Seven signed release files are ready at $signedDirectory"
Write-Host 'Complete VM acceptance, then use -Action Publish with the same tag and output directory.'
