# Isolated tests: no certificate store access, real signing, installation or network.
param([string] $Python = 'python')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Get-ProductVersion.ps1')
function Test-SignedPayloadVerification {
    param([Parameter(Mandatory = $true)][string] $PackagingDirectory)
    . (Join-Path $PackagingDirectory 'Get-ProductVersion.ps1')
    $testVersion = Get-KeyKeyProductVersion
    $source = [IO.File]::ReadAllText((Join-Path $PackagingDirectory 'Verify-SignedPayload.ps1'))
    $versionCall = '[Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName)'
    if (-not $source.Contains($versionCall)) { throw 'Signed payload version fixture no longer matches its public dependency.' }
    # Substitute only OS/tool dependencies; run the actual complete ZIP verification policy.
    $source = $source.Replace(". (Join-Path `$PSScriptRoot 'Authenticode.ps1')", '')
    $verification = [scriptblock]::Create($source.Replace($versionCall, '(Get-SyntheticPayloadVersion -Path $file.FullName)'))
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PackagingDirectory 'Authenticode.ps1'), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Authenticode helper has syntax errors.' }
    $definition = $ast.Find({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-VerifySignature'
    }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
    $syntheticSigner = '01' * 20
    function Resolve-SignTool { param($RequestedPath); 'Synthetic-PayloadVerificationTool' }
    function Synthetic-PayloadVerificationTool {
        Write-Output "synthetic provider diagnostic $syntheticSigner"
        $global:LASTEXITCODE = $nativeExitCode
    }
    function Get-ChildItem { param($LiteralPath, [switch]$File, [switch]$Recurse); $payloadFiles }
    function Get-SyntheticPayloadVersion {
        param($Path)
        [pscustomobject]@{ ProductVersion = $versions[[IO.Path]::GetFileName($Path)] }
    }
    function Get-AuthenticodeSignature {
        param($LiteralPath, $ErrorAction)
        $name = [IO.Path]::GetFileName($LiteralPath)
        $invalid = $name -eq $signatureFailureFile
        [pscustomobject]@{
            Status = if ($invalid) { $signatureStatus } else { 'Valid' }
            SignerCertificate = [pscustomobject]@{ Thumbprint = if ($invalid -and $wrongSigner) { '02' * 20 } else { $syntheticSigner } }
            TimeStamperCertificate = if ($invalid -and $missingTimestamp) { $null } else { [pscustomobject]@{ Present = $true } }
        }
    }
    function Invoke-SyntheticPayloadCase {
        param([string] $Architecture = 'x64', [hashtable] $VersionChanges = @{}, [string] $ExpectedError,
              [string] $SignatureFailureFile, [string] $SignatureStatus = 'Valid', [switch] $WrongSigner,
              [switch] $MissingTimestamp, [int] $NativeExitCode = 0, [string] $RemoveFile, [switch] $ExtraFile)
        $names = @('KeyKeyTsf_x86.dll', 'KeyKeySettings.exe', 'KeyKeySettingsBackend.dll', 'KeyKeyDeployment.exe', 'KeyKeyRegistration_x86.exe', 'WinSparkle.dll')
        if ($Architecture -eq 'x64') { $names += 'KeyKeyTsf_x64.dll' }
        if ($RemoveFile) { $names = @($names | Where-Object { $_ -ne $RemoveFile }) }
        if ($ExtraFile) { $names += 'unexpected.exe' }
        $payloadFiles = @($names | ForEach-Object { [pscustomobject]@{ Name = $_; FullName = $_; Extension = [IO.Path]::GetExtension($_) } })
        $versions = @{}
        foreach ($name in $names) { $versions[$name] = $testVersion }
        $versions['KeyKeySettingsBackend.dll'] = $null
        $versions['KeyKeyRegistration_x86.exe'] = ''
        $versions['WinSparkle.dll'] = 'third-party-version'
        foreach ($name in $VersionChanges.Keys) { $versions[$name] = $VersionChanges[$name] }
        $failure = $null
        try { & $verification -Directory 'synthetic-payload' -ExpectedVersion $testVersion -Architecture $Architecture -ReferenceInstaller 'synthetic-setup.exe' }
        catch { $failure = $_.Exception.Message }
        if ($ExpectedError) {
            if ($failure -cne $ExpectedError) { throw "Signed payload fixture expected '$ExpectedError'; received '$failure'." }
        } elseif ($failure) { throw $failure }
    }
    foreach ($architecture in @('x64', 'x86')) { Invoke-SyntheticPayloadCase -Architecture $architecture }
    Invoke-SyntheticPayloadCase -VersionChanges @{ 'KeyKeySettingsBackend.dll' = $testVersion; 'KeyKeyRegistration_x86.exe' = "$testVersion.0" }
    foreach ($name in @('KeyKeySettingsBackend.dll', 'KeyKeyRegistration_x86.exe')) {
        Invoke-SyntheticPayloadCase -VersionChanges @{ $name = 'wrong-version' } -ExpectedError "ZIP payload product version mismatch: $name"
        Invoke-SyntheticPayloadCase -SignatureFailureFile $name -WrongSigner -ExpectedError "Signature verification failed: $name"
        Invoke-SyntheticPayloadCase -SignatureFailureFile $name -MissingTimestamp -ExpectedError "Signature verification failed: $name"
        Invoke-SyntheticPayloadCase -SignatureFailureFile $name -SignatureStatus 'NotTrusted' -ExpectedError "Signature verification failed: $name"
    }
    foreach ($name in @('KeyKeyTsf_x64.dll', 'KeyKeyTsf_x86.dll', 'KeyKeySettings.exe', 'KeyKeyDeployment.exe')) {
        Invoke-SyntheticPayloadCase -VersionChanges @{ $name = $null } -ExpectedError "ZIP payload product version mismatch: $name"
        Invoke-SyntheticPayloadCase -VersionChanges @{ $name = 'wrong-version' } -ExpectedError "ZIP payload product version mismatch: $name"
    }
    Invoke-SyntheticPayloadCase -RemoveFile 'KeyKeySettingsBackend.dll' -ExpectedError 'Unexpected executable set in signed ZIP.'
    Invoke-SyntheticPayloadCase -ExtraFile -ExpectedError 'Unexpected executable set in signed ZIP.'
    Invoke-SyntheticPayloadCase -SignatureFailureFile 'synthetic-setup.exe' -MissingTimestamp -ExpectedError 'Reference publisher signature is invalid.'
    Invoke-SyntheticPayloadCase -NativeExitCode 1 -ExpectedError 'Signature verification failed: KeyKeyTsf_x86.dll'
    Write-Output 'Passed isolated signed ZIP versions, native helpers, identity, timestamp and executable-set gates.'
}
Test-SignedPayloadVerification -PackagingDirectory $PSScriptRoot
function Test-SigningCertificateSelection {
    param([Parameter(Mandatory = $true)][string] $PackagingDirectory)
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PackagingDirectory 'Authenticode.ps1'), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Authenticode helper has syntax errors.' }
    $definition = $ast.Find({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Read-SigningCertificateIdentifier'
    }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
    $syntheticIdentifier = '01' * 20
    $fallbackIdentifier = '02' * 20
    function Get-ChildItem { param($LiteralPath, $ErrorAction); $selectionCandidates }
    function Read-Host {
        param($Prompt, [switch] $AsSecureString)
        if (-not $allowFallback -or -not $AsSecureString) { throw 'Unexpected certificate identifier prompt.' }
        ConvertTo-SecureString $fallbackIdentifier -AsPlainText -Force
    }
    $valid = [pscustomobject]@{ Issuer='Synthetic Certum issuer'; HasPrivateKey=$true;
        NotBefore=(Get-Date).AddDays(-1); NotAfter=(Get-Date).AddDays(1); Thumbprint=$syntheticIdentifier;
        EnhancedKeyUsageList=@([pscustomobject]@{ ObjectId='1.3.6.1.5.5.7.3.3' }) }
    foreach ($case in @('unique','none','multiple','expired','wrong-usage','different-issuer')) {
        $candidate = $valid.PSObject.Copy()
        $selectionCandidates = @($candidate)
        $allowFallback = $case -ne 'unique'
        switch ($case) {
            'none' { $selectionCandidates = @() }
            'multiple' { $selectionCandidates = @($valid, $candidate) }
            'expired' { $candidate.NotAfter=(Get-Date).AddDays(-1) }
            'wrong-usage' { $candidate.EnhancedKeyUsageList=@([pscustomobject]@{ ObjectId='1.3.6.1.5.5.7.3.1' }) }
            'different-issuer' { $candidate.Issuer='Other synthetic issuer' }
        }
        $secure = Read-SigningCertificateIdentifier -StoreLocation CurrentUser
        if ($secure -isnot [Security.SecureString]) { throw 'Certificate selection exposed a plain identifier.' }
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $expected = if ($allowFallback) { $fallbackIdentifier } else { $syntheticIdentifier }
            if ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) -cne $expected) { throw 'Certificate selection chose the wrong candidate.' }
        } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
    }
    Write-Output 'Passed isolated unique Certum selection and masked fallback gates.'
}
Test-SigningCertificateSelection -PackagingDirectory $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot '..\Package-Store-Windows.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Authenticode.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Packaging script has syntax errors.' }
foreach ($name in @('Invoke-SignFiles', 'Invoke-VerifySignature', 'Assert-SigningCertificate')) {
    $definition = $ast.Find({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
$syntheticIdentifier = ('01' * 20)
function Fake-SignTool {
    Write-Output "provider diagnostic $syntheticIdentifier"
    $global:LASTEXITCODE = $script:fakeExitCode
}
function Get-AuthenticodeSignature {
    param($LiteralPath, $ErrorAction)
    return $global:keykeySigningTestSignature
}
$fakeExitCode = 0
$fakeStatus = 'Valid'
$fakeSigner = $syntheticIdentifier
$fakeTimestamp = [pscustomobject]@{ Present = $true }
$global:keykeySigningTestSignature = [pscustomobject]@{
    Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Thumbprint = $syntheticIdentifier }
    TimeStamperCertificate = $fakeTimestamp
}
$signArguments = @{
    FilePath = @('example.dll', 'example.exe'); ToolPath = 'Fake-SignTool'
    Thumbprint = $syntheticIdentifier; Rfc3161TimestampUrl = [uri]'https://timestamp.invalid'
    StoreLocation = 'CurrentUser'
}
$output = @(Invoke-SignFiles @signArguments)
if ($output.Count) { throw 'Signing exposed native output.' }
Invoke-VerifySignature -FilePath 'example.exe' -ToolPath 'Fake-SignTool' -ExpectedThumbprint $syntheticIdentifier
$cases = @(
    @{ Exit = 1; Status = 'Valid'; Signer = $syntheticIdentifier; Timestamp = $fakeTimestamp },
    @{ Exit = 0; Status = 'NotTrusted'; Signer = $syntheticIdentifier; Timestamp = $fakeTimestamp },
    @{ Exit = 0; Status = 'Valid'; Signer = ('02' * 20); Timestamp = $fakeTimestamp },
    @{ Exit = 0; Status = 'Valid'; Signer = $syntheticIdentifier; Timestamp = $null }
)
foreach ($case in $cases) {
    $fakeExitCode = $case.Exit; $fakeStatus = $case.Status
    $fakeSigner = $case.Signer; $fakeTimestamp = $case.Timestamp
    $global:keykeySigningTestSignature.Status = $fakeStatus
    $global:keykeySigningTestSignature.SignerCertificate.Thumbprint = $fakeSigner
    $global:keykeySigningTestSignature.TimeStamperCertificate = $fakeTimestamp
    $failed = $false
    try { Invoke-VerifySignature -FilePath 'example.exe' -ToolPath 'Fake-SignTool' -ExpectedThumbprint $syntheticIdentifier }
    catch {
        $failed = $true
        if ($_ | Out-String | Select-String -SimpleMatch $syntheticIdentifier) { throw 'Verification exposed a certificate identifier.' }
    }
    if (-not $failed) { throw 'Invalid signature state was accepted.' }
}
# Explicitly test a failed signing call.
$fakeExitCode = 1
try { Invoke-SignFiles @signArguments; throw 'Failed signer was accepted.' }
catch {
    if ($_.Exception.Message -eq 'Failed signer was accepted.') { throw }
    if ($_ | Out-String | Select-String -SimpleMatch $syntheticIdentifier) { throw 'Signing failure exposed an identifier.' }
}
function Get-Item { throw "provider error $syntheticIdentifier" }
try { Assert-SigningCertificate -Thumbprint $syntheticIdentifier -StoreLocation 'CurrentUser'; throw 'Missing certificate accepted.' }
catch {
    if ($_.Exception.Message -eq 'Missing certificate accepted.') { throw }
    if ($_ | Out-String | Select-String -SimpleMatch $syntheticIdentifier) { throw 'Certificate error exposed an identifier.' }
}
Remove-Item Function:\Get-Item
$global:keykeySigningTestUsageOid = '1.3.6.1.5.5.7.3.3'
function Get-Item {
    param($LiteralPath, $ErrorAction)
    if ($LiteralPath -like 'Cert:*') {
        return [pscustomobject]@{
            HasPrivateKey = $true; NotBefore = (Get-Date).AddDays(-1); NotAfter = (Get-Date).AddDays(1)
            EnhancedKeyUsageList = @([pscustomobject]@{ ObjectId = $global:keykeySigningTestUsageOid })
        }
    }
    return Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath
}
# The Windows certificate provider exposes ObjectId as a string; Oid objects
# from other callers expose Value. Both must pass without weakening the EKU check.
foreach ($usage in @('1.3.6.1.5.5.7.3.3', [Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))) {
    $global:keykeySigningTestUsageOid = $usage
    Assert-SigningCertificate -Thumbprint $syntheticIdentifier -StoreLocation 'CurrentUser'
}
$global:keykeySigningTestUsageOid = '1.3.6.1.5.5.7.3.1'
try { Assert-SigningCertificate -Thumbprint $syntheticIdentifier -StoreLocation 'CurrentUser'; throw 'Wrong certificate usage accepted.' }
catch {
    if ($_.Exception.Message -eq 'Wrong certificate usage accepted.') { throw }
    if ($_ | Out-String | Select-String -SimpleMatch $syntheticIdentifier) { throw 'Usage validation exposed an identifier.' }
}
$global:keykeySigningTestUsageOid = '1.3.6.1.5.5.7.3.3'
$fakeExitCode = 0; $fakeStatus = 'Valid'; $fakeSigner = $syntheticIdentifier
$fakeTimestamp = [pscustomobject]@{ Present = $true }
$global:keykeySigningTestSignature.Status = 'Valid'
$global:keykeySigningTestSignature.SignerCertificate.Thumbprint = $syntheticIdentifier
$global:keykeySigningTestSignature.TimeStamperCertificate = $fakeTimestamp
$global:keykeySigningExpectedSigned = $true
$testRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\out\signing-fixtures'))
$fixture = Join-Path $testRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
try {
    foreach ($architecture in @('x64', 'x86')) {
        $runtime = Join-Path $fixture $architecture
        New-Item -ItemType Directory -Path (Join-Path $runtime 'Databases') -Force | Out-Null
        $machine = if ($architecture -eq 'x64') { 0x8664 } else { 0x014c }
        $names = if ($architecture -eq 'x64') {
            @('KeyKeyTsf.dll', 'KeyKeySettings.exe', 'KeyKeySettingsBackend.dll', 'KeyKeyDeployment.exe', 'WinSparkle.dll')
        } else { @('KeyKeyTsf.dll', 'KeyKeyRegistration.exe', 'KeyKeySettings.exe', 'KeyKeySettingsBackend.dll', 'KeyKeyDeployment.exe', 'WinSparkle.dll') }
        foreach ($name in $names) {
            $bytes = New-Object byte[] 128
            $bytes[0] = 0x4d; $bytes[1] = 0x5a; $bytes[0x3c] = 0x40
            $bytes[0x40] = 0x50; $bytes[0x41] = 0x45
            $bytes[0x44] = $machine -band 255; $bytes[0x45] = $machine -shr 8
            [IO.File]::WriteAllBytes((Join-Path $runtime $name), $bytes)
        }
        'test data' | Set-Content -LiteralPath (Join-Path $runtime 'Databases\KeyKey.db')
        'test license' | Set-Content -LiteralPath (Join-Path $runtime 'WinSparkle-LICENSE.txt')
    }
    $fakeTool = Join-Path $fixture 'sign-tool.ps1'
    @'
if ($args[0] -eq 'sign') {
    foreach ($argument in $args) {
        if ($argument -match '\.(exe|dll)$') {
            [IO.File]::AppendAllText($argument, 'signed-test-bytes')
        }
    }
}
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath $fakeTool
    $fakeNsis = Join-Path $fixture 'makensis.ps1'
    @'
if ($args[0] -eq '/VERSION') { 'v3.12'; $global:LASTEXITCODE = 0; return }
$defines = @{}
foreach ($argument in $args) {
    if ($argument -match '^/D([^=]+)=(.*)$') { $defines[$Matches[1]] = $Matches[2] }
}
$manifest = Get-Content -LiteralPath $defines.MANIFEST_PATH -Raw | ConvertFrom-Json
if ($manifest.Signed -ne $global:keykeySigningExpectedSigned) { throw 'Unexpected manifest signing state.' }
foreach ($entry in $manifest.Files) {
    $path = Join-Path $defines.PAYLOAD_DIR $entry.Path
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Sha256) {
        throw 'Manifest was generated before signing.'
    }
}
[IO.File]::WriteAllText($defines.OUTPUT_FILE, 'test-only NSIS output')
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath $fakeNsis
    $testVersion = Get-KeyKeyProductVersion
    $packageArguments = @{
        BuildDirectory = Join-Path $fixture 'x64'; X86BuildDirectory = Join-Path $fixture 'x86'
        MakensisPath = $fakeNsis; SignToolPath = $fakeTool; OutputDirectory = Join-Path $fixture 'signed'
        Version = $testVersion; CertificateThumbprint = $syntheticIdentifier; TimestampUrl = [uri]'https://timestamp.invalid'
    }
    $allOutput = & $scriptPath @packageArguments *>&1 | Out-String
    if ($allOutput.Contains($syntheticIdentifier)) { throw 'Packaging output exposed an identifier.' }
    $package = Join-Path $fixture "signed\chichi77-KeyKey-$testVersion-windows-x64-setup.exe"
    if (-not (Test-Path -LiteralPath $package)) { throw 'Packaging did not produce an installer.' }
    $expectedHash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not (Get-Content -LiteralPath "$package.sha256" -Raw).StartsWith($expectedHash)) {
        throw 'Final checksum does not describe signed bytes.'
    }
    if (@(Get-ChildItem -LiteralPath (Join-Path $fixture 'signed') -Directory -Force).Count) {
        throw 'Signing staging directory was retained.'
    }
    # Local releases sign both architecture runtimes before producing either ZIP.
    $runtimeFiles = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'x64'), (Join-Path $fixture 'x86') -File -Recurse |
        Where-Object { $_.Extension -in @('.exe', '.dll') })
    Invoke-SignFiles -FilePath $runtimeFiles.FullName -ToolPath $fakeTool -Thumbprint $syntheticIdentifier -Rfc3161TimestampUrl ([uri]'https://timestamp.invalid') -StoreLocation 'CurrentUser'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($architecture in @('x64', 'x86')) {
        $zipArguments = @{
            BuildDirectory = Join-Path $fixture 'x64'; X86BuildDirectory = Join-Path $fixture 'x86'
            Architecture = $architecture; Version = $testVersion; Signed = $true
            OutputDirectory = Join-Path $fixture 'zip'; SignToolPath = $fakeTool
        }
        $null = & (Join-Path $PSScriptRoot '..\Package-Windows.ps1') @zipArguments
        $zipPath = Join-Path $fixture "zip\chichi77-KeyKey-$testVersion-windows-$architecture.zip"
        $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $manifestEntry = @($archive.Entries | Where-Object { $_.FullName.Replace('\', '/').EndsWith('/PackageManifest.json') })[0]
            $reader = [IO.StreamReader]::new($manifestEntry.Open())
            try { $zipManifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
            if (-not $zipManifest.Signed -or $zipManifest.Architecture -ne $architecture) { throw 'ZIP manifest is not signed.' }
            foreach ($entry in $zipManifest.Files) {
                if ($entry.Path -notmatch '\.(exe|dll)$') { continue }
                $relative = $entry.Path.Replace('\', '/')
                $match = @($archive.Entries | Where-Object { $_.FullName.Replace('\', '/').EndsWith('/Payload/' + $relative) })
                if ($match.Count -ne 1) { throw 'Signed executable missing from ZIP.' }
                $reader = [IO.StreamReader]::new($match[0].Open())
                try { $bytes = $reader.ReadToEnd() } finally { $reader.Dispose() }
                if (-not $bytes.EndsWith('signed-test-bytes')) { throw 'ZIP contains bytes from before signing.' }
            }
        } finally { $archive.Dispose() }
        $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if (-not (Get-Content -LiteralPath "$zipPath.sha256" -Raw).StartsWith($zipHash)) { throw 'ZIP checksum mismatch.' }
        try { $null = & (Join-Path $PSScriptRoot '..\Package-Windows.ps1') @zipArguments; throw 'Signed ZIP was overwritten.' }
        catch { if ($_.Exception.Message -eq 'Signed ZIP was overwritten.') { throw } }
    }
    # Exercise the actual local Sign entry point, with provider/helper substitutes.
    $releaseFixture = Join-Path $fixture 'local-release'
    New-Item -ItemType Directory -Path (Join-Path $releaseFixture 'inputs') -Force | Out-Null
    foreach ($architecture in @('x64', 'x86')) {
        Copy-Item -LiteralPath (Join-Path $fixture $architecture) -Destination (Join-Path $releaseFixture 'inputs') -Recurse
    }
    @{ version = $testVersion; release_tag = "v$testVersion"; source_sha = ('a' * 40); run_id = 101 } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $releaseFixture 'context.json') -Encoding UTF8
    $global:keykeyReleaseHelperCalls = [Collections.Generic.List[string]]::new()
    function git { 'ignored-output'; $global:LASTEXITCODE = 0 }
    function Read-Host { param($Prompt, [switch]$AsSecureString); ConvertTo-SecureString ('01' * 20) -AsPlainText -Force }
    function Get-ChildItem {
        [CmdletBinding()]
        param([Parameter(Position=0)]$LiteralPath, [switch]$File, [switch]$Recurse, [switch]$Directory)
        if ($LiteralPath -like 'Cert:*') { return }
        Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters
    }
    function Fake-ReleasePython {
        $command = $args[1]
        $global:keykeyReleaseHelperCalls.Add($command)
        if ($command -eq 'download') {
            Get-Content -LiteralPath (Join-Path $releaseFixture 'context.json') -Raw
        } elseif ($command -eq 'record') {
            $directory = $args[[Array]::IndexOf($args, '--directory') + 1]
            '{}' | Set-Content -LiteralPath (Join-Path $directory "signed\chichi77-KeyKey-$testVersion-windows-build-info.json")
        } elseif ($command -ne 'verify-built') { throw 'Unexpected release-helper command.' }
        $global:LASTEXITCODE = 0
    }
    try {
        $releaseArguments = @{
            Action = 'Sign'; RunId = '101'; ReleaseTag = "v$testVersion"; Python = 'Fake-ReleasePython'; OutputDirectory = $releaseFixture
            MakensisPath = $fakeNsis; SignToolPath = $fakeTool; TimestampUrl = [uri]'https://timestamp.invalid'
        }
        $releaseOutput = & (Join-Path $PSScriptRoot '..\Release-Windows.ps1') @releaseArguments *>&1 | Out-String
        if ($releaseOutput.Contains($syntheticIdentifier)) { throw 'Local release exposed a signing identifier.' }
        $publicFiles = @(Get-ChildItem -LiteralPath (Join-Path $releaseFixture 'signed') -File)
        if ($publicFiles.Count -ne 7 -or @($publicFiles | Where-Object Name -Like '*unsigned*').Count -or
            ($global:keykeyReleaseHelperCalls -join ',') -ne 'download,verify-built,record') {
            throw "Local release asset count=$($publicFiles.Count); files=$($publicFiles.Name -join ','); helper calls=$($global:keykeyReleaseHelperCalls -join ',')"
        }
    } finally {
        Remove-Item Function:\git, Function:\Read-Host, Function:\Get-ChildItem, Function:\Fake-ReleasePython
        Remove-Variable -Name keykeyReleaseHelperCalls -Scope Global
    }
    $global:keykeySigningTestSignature.Status = 'NotSigned'
    $zipArguments.OutputDirectory = Join-Path $fixture 'rejected-zip'
    try { $null = & (Join-Path $PSScriptRoot '..\Package-Windows.ps1') @zipArguments; throw 'Unsigned ZIP payload accepted.' }
    catch { if ($_.Exception.Message -eq 'Unsigned ZIP payload accepted.') { throw } }
    $global:keykeySigningTestSignature.Status = 'Valid'
    # UnsignedTest remains available only for isolated installer/updater fixtures.
    $global:keykeySigningExpectedSigned = $false
    $unsignedArguments = $packageArguments.Clone()
    foreach ($key in @('CertificateThumbprint', 'TimestampUrl', 'SignToolPath', 'Version')) { $unsignedArguments.Remove($key) }
    $unsignedArguments.OutputDirectory = Join-Path $fixture 'unsigned'
    $unsignedArguments.UnsignedTest = $true
    $null = & $scriptPath @unsignedArguments *>&1
    $unsignedPackage = Join-Path $fixture "unsigned\chichi77-KeyKey-$testVersion-windows-x64-setup.unsigned.exe"
    if (-not (Test-Path -LiteralPath $unsignedPackage)) { throw 'Unsigned fallback packaging no longer works.' }
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if ([IO.Path]::GetDirectoryName($resolvedFixture) -ne $testRoot -or
        [IO.Path]::GetFileName($resolvedFixture) -notmatch '^[0-9a-f]{32}$') {
        throw 'Unexpected fixture cleanup path.'
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    Remove-Item Function:\Get-Item
    Remove-Variable -Name keykeySigningTestSignature -Scope Global
    Remove-Variable -Name keykeySigningExpectedSigned -Scope Global
    Remove-Variable -Name keykeySigningTestUsageOid -Scope Global
}
Write-Output 'Passed isolated signing privacy, identity, timestamp and complete packaging gates.'
& (Join-Path $PSScriptRoot 'Test-WindowsUpdatePreparation.ps1')
& (Join-Path $PSScriptRoot 'Test-BuildWindowsRelease.ps1') -Python $Python
