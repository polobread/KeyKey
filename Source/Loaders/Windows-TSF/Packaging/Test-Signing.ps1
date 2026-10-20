# Isolated tests: no certificate store access, real signing, installation or network.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Get-ProductVersion.ps1')
$scriptPath = Join-Path $PSScriptRoot '..\Package-Store-Windows.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
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
        } else { @('KeyKeyTsf.dll', 'KeyKeyRegistration.exe') }
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
if ($manifest.Version -ne $global:keykeySigningExpectedVersion) { throw 'Unexpected package product version.' }
foreach ($entry in $manifest.Files) {
    $path = Join-Path $defines.PAYLOAD_DIR $entry.Path
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Sha256) {
        throw 'Manifest was generated before signing.'
    }
}
[IO.File]::WriteAllText($defines.OUTPUT_FILE, 'test-only NSIS output')
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath $fakeNsis
    $testVersion = '9.8.7'
    $versionFixture = Join-Path $fixture 'product-version.cmake'
    "project(KeyKeyWindowsTsf VERSION $testVersion LANGUAGES C CXX)" | Set-Content -LiteralPath $versionFixture
    if ((Get-KeyKeyProductVersion -CMakePath $versionFixture) -ne $testVersion) { throw 'Product version was not read from CMake.' }
    $global:keykeySigningExpectedVersion = $testVersion
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
    # The retained unsigned workflow still calls this same packaging entry point.
    $global:keykeySigningExpectedSigned = $false
    $unsignedArguments = $packageArguments.Clone()
    foreach ($key in @('CertificateThumbprint', 'TimestampUrl', 'SignToolPath', 'Version')) { $unsignedArguments.Remove($key) }
    $global:keykeySigningExpectedVersion = Get-KeyKeyProductVersion
    $unsignedArguments.OutputDirectory = Join-Path $fixture 'unsigned'
    $unsignedArguments.UnsignedTest = $true
    $null = & $scriptPath @unsignedArguments *>&1
    $unsignedPackage = Join-Path $fixture "unsigned\chichi77-KeyKey-$($global:keykeySigningExpectedVersion)-windows-x64-setup.unsigned.exe"
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
    Remove-Variable -Name keykeySigningExpectedVersion -Scope Global
}
Write-Output 'Passed isolated signing privacy, identity, timestamp and complete packaging gates.'
