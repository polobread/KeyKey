# Shared Authenticode helpers. Never echo signing-provider diagnostics or certificate identifiers.
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

function Read-SigningCertificateIdentifier {
    param([Parameter(Mandatory = $true)][string] $StoreLocation)

    $now = Get-Date
    $candidates = @(Get-ChildItem -LiteralPath "Cert:\$StoreLocation\My" -ErrorAction SilentlyContinue | Where-Object {
        $_.HasPrivateKey -and $_.NotBefore -le $now -and $_.NotAfter -ge $now -and $_.Issuer -match 'Certum' -and
        @($_.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq '1.3.6.1.5.5.7.3.3' -or $_.ObjectId.Value -eq '1.3.6.1.5.5.7.3.3' }).Count -gt 0
    })
    try {
        if ($candidates.Count -eq 1) {
            return ConvertTo-SecureString -String $candidates[0].Thumbprint -AsPlainText -Force
        }
        return Read-Host 'Certificate thumbprint (hidden; memory only)' -AsSecureString
    } finally { $candidates = $null }
}

function Assert-SigningCertificate {
    param(
        [Parameter(Mandatory = $true)][string] $Thumbprint,
        [Parameter(Mandatory = $true)][string] $StoreLocation
    )

    $certificatePath = "Cert:\$StoreLocation\My\$Thumbprint"
    try {
        $certificate = Get-Item -LiteralPath $certificatePath -ErrorAction Stop
    } catch {
        throw 'The signing certificate could not be opened. Check the store and SimplySign connection.'
    }
    if (-not $certificate.HasPrivateKey) {
        throw 'The selected certificate does not expose an accessible private key.'
    }
    if ($certificate.NotBefore -gt (Get-Date) -or
        $certificate.NotAfter -lt (Get-Date)) {
        throw 'The selected certificate is not currently valid.'
    }

    $codeSigningOid = '1.3.6.1.5.5.7.3.3'
    $hasCodeSigningUsage = $certificate.EnhancedKeyUsageList |
        Where-Object { $_.ObjectId -eq $codeSigningOid -or $_.ObjectId.Value -eq $codeSigningOid }
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
        '/q'
    )
    $arguments += $FilePath

    try {
        # Discard both streams, including provider errors which can contain certificate IDs.
        $null = & $ToolPath @arguments 2>&1
        $signExitCode = $LASTEXITCODE
    } catch {
        throw 'Signing failed. Check the SimplySign session, PIN and timestamp service.'
    }
    if ($signExitCode -ne 0) {
        throw "Signing failed: $($FilePath -join ', ')"
    }
}

function Invoke-VerifySignature {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string] $ToolPath,
        [Parameter(Mandatory = $true)][string] $ExpectedThumbprint
    )

    try {
        $null = & $ToolPath verify /pa /all /tw /q $FilePath 2>&1
        $verifyExitCode = $LASTEXITCODE
        $signature = Get-AuthenticodeSignature -LiteralPath $FilePath -ErrorAction Stop
    } catch {
        throw 'Signature verification failed. Certificate details were suppressed.'
    }
    if ($verifyExitCode -ne 0 -or $signature.Status -ne 'Valid' -or
        -not $signature.TimeStamperCertificate -or
        $signature.SignerCertificate.Thumbprint -ne $ExpectedThumbprint) {
        throw "Signature verification failed: $FilePath"
    }
}
