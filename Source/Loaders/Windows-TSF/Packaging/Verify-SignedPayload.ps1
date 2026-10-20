# Verify extracted ZIP executables without executing or installing them.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Directory,
    [Parameter(Mandatory = $true)][string] $ExpectedVersion,
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'x86')][string] $Architecture,
    [string] $ReferenceInstaller,
    [string] $SignToolPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Authenticode.ps1')
$tool = Resolve-SignTool -RequestedPath $SignToolPath
$files = @(Get-ChildItem -LiteralPath $Directory -File -Recurse | Where-Object { $_.Extension -in @('.exe', '.dll') })
$expected = @('KeyKeyTsf_x86.dll', 'KeyKeySettings.exe', 'KeyKeySettingsBackend.dll', 'KeyKeyDeployment.exe', 'KeyKeyRegistration_x86.exe', 'WinSparkle.dll')
if ($Architecture -eq 'x64') { $expected += 'KeyKeyTsf_x64.dll' }
if ($files.Count -ne $expected.Count -or @(Compare-Object ($files.Name | Sort-Object) ($expected | Sort-Object)).Count) {
    throw 'Unexpected executable set in signed ZIP.'
}
$reference = if ($ReferenceInstaller) { $ReferenceInstaller } else { $files[0].FullName }
$signature = Get-AuthenticodeSignature -LiteralPath $reference
if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) { throw 'Reference publisher signature is invalid.' }
$signer = $signature.SignerCertificate.Thumbprint
if (-not $signer) { throw 'ZIP payload is not signed.' }
foreach ($file in $files) {
    Invoke-VerifySignature -FilePath $file.FullName -ToolPath $tool -ExpectedThumbprint $signer
    if ($file.Name -ne 'WinSparkle.dll') {
        $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName)
        # These native helper targets currently have no version resource in CMake.
        # If a later build adds one, it must still match the release version.
        $unversionedHelper = $file.Name -in @('KeyKeySettingsBackend.dll', 'KeyKeyRegistration_x86.exe') -and
            [string]::IsNullOrEmpty($version.ProductVersion)
        if (-not $unversionedHelper -and $version.ProductVersion -notmatch ('^' + [regex]::Escape($ExpectedVersion) + '(?:[.+-]|$)')) {
            throw "ZIP payload product version mismatch: $($file.Name)"
        }
    }
}
