# Isolated Windows Ed25519 wrapper tests; never reads a user key or calls OpenSSL.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Get-ProductVersion.ps1')
$testVersion = Get-KeyKeyProductVersion
$testRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\out\update-preparation-fixtures'))
$fixture = Join-Path $testRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$scriptPath = Join-Path $PSScriptRoot '..\Prepare-WindowsUpdate.ps1'
$global:keykeyUpdateTestState = @{ Tracked = $false; Failure = $false; Calls = 0; Marker = 'synthetic-provider-output-must-not-escape' }
function git {
    if ($args -contains 'ls-files') {
        if ($global:keykeyUpdateTestState.Tracked) { 'keykey-update-private.pem' }
    } elseif ($args -contains 'rev-parse') { 'a' * 40 }
    elseif ($args -contains 'get-url') { 'https://github.com/polobread/KeyKey.git' }
    $global:LASTEXITCODE = 0
}
function Fake-UpdatePython {
    $global:keykeyUpdateTestState.Calls++
    if ($args[1] -ne '--openssl' -or $args[3] -ne 'build') { throw 'Incorrect metadata argument ordering.' }
    $key = $args[$args.IndexOf('--key') + 1]
    if ([IO.Path]::GetFileName($key) -cne 'keykey-update-private.pem') { throw 'Wrong key passed to local signer.' }
    Write-Output $global:keykeyUpdateTestState.Marker
    $global:LASTEXITCODE = if ($global:keykeyUpdateTestState.Failure) { 1 } else { 0 }
}
try {
    $keyPath = Join-Path $fixture 'keykey-update-private.pem'
    # A synthetic placeholder; no user key is located or copied by this test.
    [IO.File]::WriteAllText($keyPath, 'synthetic test placeholder')
    $manifest = Join-Path $fixture 'manifest.json'
    $data = @{ schema_version = 1; channel = 'stable'; releases = @(@{
        target = 'windows-x64'; windows_signing = 'authenticode'; version = $testVersion; release_tag = "v$testVersion"
        source_sha = 'a' * 40; tag_sha = 'a' * 40
    }) }
    $data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest -Encoding UTF8
    $arguments = @{ Manifest = $manifest; PrivateKeyPath = $keyPath; OutputDirectory = Join-Path $fixture 'out'
        BaseUrl = [uri]'https://cdn.example.invalid/keykey/releases/download'; Python = 'Fake-UpdatePython' }
    $output = & $scriptPath @arguments *>&1 | Out-String
    if ($global:keykeyUpdateTestState.Calls -ne 1 -or $output.Contains($global:keykeyUpdateTestState.Marker)) { throw 'Local update wrapper exposed tool diagnostics.' }
    $global:keykeyUpdateTestState.Failure = $true
    try { $null = & $scriptPath @arguments *>&1; throw 'Failed Ed25519 signer accepted.' }
    catch {
        if ($_.Exception.Message -eq 'Failed Ed25519 signer accepted.' -or ($_ | Out-String).Contains($global:keykeyUpdateTestState.Marker)) { throw }
    }
    $global:keykeyUpdateTestState.Failure = $false
    $global:keykeyUpdateTestState.Tracked = $true
    $calls = $global:keykeyUpdateTestState.Calls
    try { $null = & $scriptPath @arguments *>&1; throw 'Tracked update private key accepted.' }
    catch { if ($_.Exception.Message -eq 'Tracked update private key accepted.') { throw } }
    $global:keykeyUpdateTestState.Tracked = $false
    $data.releases[0].target = 'macos-arm64'
    $data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest -Encoding UTF8
    try { $null = & $scriptPath @arguments *>&1; throw 'Other-platform manifest accepted.' }
    catch { if ($_.Exception.Message -eq 'Other-platform manifest accepted.') { throw } }
    if ($calls -ne $global:keykeyUpdateTestState.Calls) { throw 'Signer was called after rejecting private-key/platform policy.' }
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ([IO.Path]::GetDirectoryName($resolved) -ne $testRoot -or [IO.Path]::GetFileName($resolved) -notmatch '^[0-9a-f]{32}$') {
        throw 'Unexpected update-preparation fixture cleanup path.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
    Remove-Item Function:\git, Function:\Fake-UpdatePython
    Remove-Variable -Name keykeyUpdateTestState -Scope Global
}
Write-Host 'Passed Windows-only Ed25519 wrapper, tracked-key rejection and diagnostic privacy tests.'
