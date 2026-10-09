param([Parameter(Mandatory=$true)][string]$Installer,
      [Parameter(Mandatory=$true)][string]$ExpectedVersion)
$ErrorActionPreference = 'Stop'
$signature = Get-AuthenticodeSignature -LiteralPath $Installer
if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
    -not $signature.TimeStamperCertificate) {
    throw 'Automatic updates require a valid, timestamped Authenticode installer.'
}
$actualVersion = (Get-Item -LiteralPath $Installer).VersionInfo.ProductVersion
if ($actualVersion -notmatch ('^' + [regex]::Escape($ExpectedVersion) + '(?:\.0)?$')) {
    throw 'Installer product version does not match update metadata.'
}
