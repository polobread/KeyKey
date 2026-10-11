$ErrorActionPreference = 'Stop'
$verifier = Join-Path $PSScriptRoot 'verify-windows.ps1'

# Isolate OS trust responses; real signed/timestamped acceptance needs a release certificate.
function Get-AuthenticodeSignature { param($LiteralPath) return $global:keykeyTestSignature }
function Get-Item { param($LiteralPath) return [pscustomobject]@{ VersionInfo = @{ ProductVersion = $global:keykeyTestVersion } } }

$cases = @(
    @{ Mode = 'unsigned-transition'; Status = 'NotSigned'; Accept = $true },
    @{ Status = 'NotSigned'; Accept = $false },
    @{ Mode = 'authenticode'; Status = 'Valid'; Signer = $true; Timestamp = $true; Accept = $true },
    @{ Status = 'Valid'; Signer = $true; Timestamp = $true; Accept = $true },
    @{ Status = 'Valid'; Signer = $true; Accept = $false },
    @{ Status = 'Valid'; Timestamp = $true; Accept = $false },
    @{ Status = 'HashMismatch'; Signer = $true; Timestamp = $true; Accept = $false },
    @{ Status = 'NotTrusted'; Signer = $true; Timestamp = $true; Accept = $false },
    @{ Mode = 'unsigned-transition'; Status = 'HashMismatch'; Accept = $false },
    @{ Mode = 'unsigned-transition'; Status = 'NotTrusted'; Accept = $false },
    @{ Mode = 'unsigned-transition'; Status = 'UnknownError'; Accept = $false },
    @{ Mode = 'unsigned-transition'; Status = 'Valid'; Signer = $true; Timestamp = $true; Accept = $false },
    @{ Mode = 'unsigned-transition'; Status = 'NotSigned'; Version = '1.3.1'; Accept = $false },
    @{ Mode = 'unsigned-transition'; Status = 'NotSigned'; Version = '1.3.2.0'; Accept = $true },
    @{ Status = 'Valid'; Signer = $true; Timestamp = $true; Version = '1.3.2-beta'; Accept = $false },
    @{ Mode = 'optional'; Status = 'NotSigned'; Accept = $false }
)
foreach ($case in $cases) {
    $global:keykeyTestSignature = [pscustomobject]@{
        Status = $case.Status
        SignerCertificate = $(if ($case.Signer) { [pscustomobject]@{} } else { $null })
        TimeStamperCertificate = $(if ($case.Timestamp) { [pscustomobject]@{} } else { $null })
    }
    $global:keykeyTestVersion = $(if ($case.Version) { $case.Version } else { '1.3.2' })
    $arguments = @{ Installer = 'isolated-fixture.exe'; ExpectedVersion = '1.3.2' }
    if ($case.Mode) { $arguments.SigningMode = $case.Mode }
    $accepted = $true
    $failure = ''
    try { & $verifier @arguments } catch { $accepted = $false; $failure = $_.Exception.Message }
    if ($accepted -ne $case.Accept) {
        throw "Unexpected verification result: mode=$($case.Mode), status=$($case.Status), version=$global:keykeyTestVersion; $failure"
    }
}
Write-Output "Passed $($cases.Count) isolated Windows signing/version cases."
