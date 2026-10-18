# Requires Windows PowerShell 5.1 or PowerShell 7 on Windows.
[CmdletBinding()]
param(
    [ValidateSet('Sign', 'Publish')][string] $Action = 'Sign',
    [Parameter(Mandatory = $true)][ValidatePattern('^[1-9][0-9]*$')][string] $RunId,
    [Parameter(Mandatory = $true)][ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+(?:-beta[1-9][0-9]*)?$')]
    [string] $ReleaseTag,
    [string] $Python = 'python',
    [string] $MakensisPath,
    [string] $SignToolPath,
    [ValidateSet('CurrentUser', 'LocalMachine')][string] $CertificateStoreLocation = 'CurrentUser',
    [uri] $TimestampUrl = 'http://time.certum.pl'
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$helper = Join-Path $repositoryRoot '.github\scripts\windows-signing.py'
$releaseDirectory = Join-Path $PSScriptRoot "out\local-release\$RunId-$ReleaseTag"

function Invoke-ReleaseHelper {
    param([string[]] $Arguments)
    $helperOutput = & $Python $helper @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Windows release operation stopped. No signing credentials were recorded.' }
    return $helperOutput
}

if ($Action -eq 'Publish') {
    $contextPath = Join-Path $releaseDirectory 'context.json'
    if (-not (Test-Path -LiteralPath $contextPath)) { throw 'Sign this run/tag before publishing.' }
    $context = Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json
    $installerName = "chichi77-KeyKey-$($context.version)-windows-x64-setup.exe"
    $installer = Join-Path $releaseDirectory "signed\$installerName"
    $digest = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host "Release: $ReleaseTag; CI run: $RunId"
    Write-Host "Installer: $installerName"
    Write-Host "SHA-256: $digest"
    Write-Host 'Confirm the signed installer has passed clean-VM installation, upgrade, input and removal checks.'
    $confirmation = Read-Host "Type PUBLISH $ReleaseTag $digest to upload and request the CDN mirror"
    if ($confirmation -cne "PUBLISH $ReleaseTag $digest") { throw 'Publication was not approved.' }
    Invoke-ReleaseHelper -Arguments @('publish', '--run-id', $RunId, '--tag', $ReleaseTag,
        '--directory', $releaseDirectory, '--approved-sha256', $digest)
    return
}

$context = (Invoke-ReleaseHelper -Arguments @('download', '--run-id', $RunId, '--tag', $ReleaseTag,
    '--directory', $releaseDirectory)) | ConvertFrom-Json
Write-Host "Verified CI source: $($context.source_sha); version: $($context.version)"
Write-Host 'Connect SimplySign Desktop using your phone token. Enter any PIN only in the provider dialog.'
$packageArguments = @{
    BuildDirectory = Join-Path $releaseDirectory 'inputs\x64'
    X86BuildDirectory = Join-Path $releaseDirectory 'inputs\x86'
    OutputDirectory = Join-Path $releaseDirectory 'signed'
    Version = $context.version
    TimestampUrl = $TimestampUrl
    CertificateStoreLocation = $CertificateStoreLocation
}
if ($MakensisPath) { $packageArguments.MakensisPath = $MakensisPath }
if ($SignToolPath) { $packageArguments.SignToolPath = $SignToolPath }
# Same-process invocation: the hidden thumbprint is never supplied on a process command line here.
& (Join-Path $PSScriptRoot 'Package-Store-Windows.ps1') @packageArguments
Invoke-ReleaseHelper -Arguments @('record', '--directory', $releaseDirectory)
Write-Host 'Signed package is ready for VM review. Run this script with -Action Publish after acceptance.'
