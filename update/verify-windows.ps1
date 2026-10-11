param([Parameter(Mandatory=$true)][string]$Installer,
      [Parameter(Mandatory=$true)][string]$ExpectedVersion,
      [ValidateSet('authenticode', 'unsigned-transition')]
      [string]$SigningMode = 'authenticode')
$ErrorActionPreference = 'Stop'
$signature = Get-AuthenticodeSignature -LiteralPath $Installer
if ($SigningMode -eq 'unsigned-transition') {
    # An invalid/untrusted signature must never be relabeled as an unsigned release.
    if ($signature.Status -ne 'NotSigned' -or $signature.SignerCertificate -or
        $signature.TimeStamperCertificate) {
        throw 'Unsigned transition requires an installer with no Authenticode signature.'
    }
} elseif ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
          -not $signature.TimeStamperCertificate) {
    throw 'Automatic updates require a valid, timestamped Authenticode installer.'
}
$actualVersion = (Get-Item -LiteralPath $Installer).VersionInfo.ProductVersion
if ($actualVersion -notmatch ('^' + [regex]::Escape($ExpectedVersion) + '(?:\.0)?$')) {
    throw 'Installer product version does not match update metadata.'
}
