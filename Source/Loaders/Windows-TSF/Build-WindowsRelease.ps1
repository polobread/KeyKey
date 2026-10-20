# Shared Windows build/test/unsigned packaging commands.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $OutputDirectory,
    [string] $Python = 'python',
    [string] $OpenSslPath,
    [string] $MakensisPath,
    [ValidatePattern('^(?:|v[0-9]+\.[0-9]+\.[0-9]+(?:-beta[1-9][0-9]*)?)$')][string] $ReleaseTag = ''
)
$ErrorActionPreference = 'Stop'
$Python = (Get-Command $Python -ErrorAction Stop).Source
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output = [IO.Path]::GetFullPath($OutputDirectory)
if ($output.Length -gt 120) { throw 'Use a shorter build output path (for example update/out/windows-checks).' }
if (Test-Path -LiteralPath $output) { throw 'Build output exists. Preserve it and use a fresh output directory.' }
foreach ($program in @('cmake', 'ctest', 'ruby', 'dotnet', 'powershell.exe', 'git')) { $null = Get-Command $program -ErrorAction Stop }
if (-not $OpenSslPath) { $OpenSslPath = Join-Path $env:ProgramFiles 'Git/usr/bin/openssl.exe' }
if (-not (Test-Path -LiteralPath $OpenSslPath -PathType Leaf)) { throw 'OpenSSL 3 is required.' }
if (-not $MakensisPath) {
    $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($command) { $MakensisPath = $command.Source }
    else {
        $MakensisPath = @((Join-Path ${env:ProgramFiles(x86)} 'NSIS/makensis.exe'),
            (Join-Path $env:ProgramFiles 'NSIS/makensis.exe')) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }
}
if (-not $MakensisPath -or -not (Test-Path -LiteralPath $MakensisPath -PathType Leaf)) { throw 'Install NSIS 3.12 or pass -MakensisPath.' }
$nsisVersion = (& $MakensisPath /VERSION 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $nsisVersion -notmatch '^v?3\.12(?:\D|$)') { throw 'NSIS 3.12 is required.' }
. (Join-Path $PSScriptRoot 'Packaging/Get-ProductVersion.ps1')
$version = Get-KeyKeyProductVersion
if (-not $ReleaseTag) { $ReleaseTag = "v$version" }
$checks = [Collections.Generic.List[object]]::new()
$testResults = @{}
$previousConfig = $env:KEYKEY_UPDATE_CONFIG
$report = Join-Path $output 'build-checks.json'
if (Test-Path -LiteralPath $report) { throw 'Build checks already exist. Use a fresh output directory.' }
New-Item -ItemType Directory -Path $output -Force | Out-Null
function Invoke-Checked {
    param([string] $Name, [string] $Program, [string[]] $Arguments)
    Write-Host "Windows release check: $Name"
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Windows release check failed: $Name" }
    $checks.Add([ordered]@{ name = $Name; passed = $true })
}
Push-Location $PSScriptRoot
try {
    $config = Join-Path $output 'update-config.json'
    Invoke-Checked 'update-config' $Python @('../../../update/prepare.py', 'select-release', '--tag', $ReleaseTag, '--version', $version, '--out', $config)
    $env:KEYKEY_UPDATE_CONFIG = $config
    Invoke-Checked 'updater-sdk' $Python @('../../../update/prepare.py', 'fetch', 'windows')
    foreach ($architecture in @('x64', 'x86')) {
        $preset = if ($architecture -eq 'x64') { 'windows-x64-vs2026' } else { 'windows-x86' }
        $build = Join-Path $output $architecture
        Invoke-Checked "configure-$architecture" 'cmake' @('--preset', $preset, '-B', $build, "-DPython3_EXECUTABLE=$Python")
        Invoke-Checked "build-$architecture" 'cmake' @('--build', $build, '--config', 'Release', '--parallel')
        # These two managed cases are run once below, rather than once per bitness.
        $testReport = Join-Path $output "ctest-$architecture.xml"
        Invoke-Checked "ctest-$architecture" 'ctest' @('--test-dir', $build, '-C', 'Release', '--output-on-failure', '--no-tests=error', '-E', '^(KeyKeyDeploymentTransactions|KeyKeySettingsPreferences)$', '--output-junit', $testReport)
        [xml]$results = Get-Content -LiteralPath $testReport -Raw
        $testResults[$architecture] = @($results.SelectNodes('//testcase') | ForEach-Object {
            [ordered]@{ name = $_.GetAttribute('name'); status = if ($_.SelectSingleNode('skipped')) { 'skipped' } elseif ($_.SelectSingleNode('failure|error')) { 'failed' } else { 'passed' } }
        })
        if (-not $testResults[$architecture].Count) { throw 'CTest produced no test results.' }
    }
    Invoke-Checked 'settings' 'dotnet' @('run', '--project', 'SettingsModern.Tests/SettingsModern.Tests.csproj', '--configuration', 'Release')
    Invoke-Checked 'deployment' 'dotnet' @('run', '--project', 'Deployment.Tests/Deployment.Tests.csproj', '--configuration', 'Release')
    $x64 = Join-Path $output 'x64/Release/KeyKeySharedDataProtectionTest.exe'
    $x86 = Join-Path $output 'x86/Release/KeyKeySharedDataProtectionTest.exe'
    Invoke-Checked 'shared-x64-x86' $x64 @($x86)
    Invoke-Checked 'shared-x86-x64' $x86 @($x64)
    $managed = Join-Path $PSScriptRoot 'SettingsModern.Tests/bin/Release/net10.0/SettingsModern.Tests.dll'
    $dotnet = (Get-Command dotnet -ErrorAction Stop).Source
    Invoke-Checked 'shared-managed-x64' $x64 @('--managed', $dotnet, $managed)
    Invoke-Checked 'shared-managed-x86' $x86 @('--managed', $dotnet, $managed)
    if (-not $OpenSslPath) { $OpenSslPath = Join-Path $env:ProgramFiles 'Git/usr/bin/openssl.exe' }
    if (-not (Test-Path -LiteralPath $OpenSslPath -PathType Leaf)) { throw 'OpenSSL 3 is required for release checks.' }
    $previousOpenSsl = $env:KEYKEY_TEST_OPENSSL
    try {
        $env:KEYKEY_TEST_OPENSSL = $OpenSslPath
        Push-Location (Join-Path $repository 'update')
        try {
            Invoke-Checked 'update-metadata' $Python @('-m', 'unittest', '-v', 'test_channels', 'test_metadata')
        } finally { Pop-Location }
        foreach ($architecture in @('x64', 'x86')) {
            Invoke-Checked "updater-$architecture" 'dotnet' @('run', '--project', 'DesktopUpdater.Tests/DesktopUpdater.Tests.csproj', '--configuration', 'Release', '-r', "win-$architecture", '--self-contained', '--', '--native', '--openssl', $OpenSslPath)
        }
    } finally { $env:KEYKEY_TEST_OPENSSL = $previousOpenSsl }
    Invoke-Checked 'release-transport' $Python @('-m', 'unittest', 'discover', '-s', '../../../.github/scripts', '-p', 'test_windows_signing.py', '-v')
    Invoke-Checked 'signing-policy' 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'Packaging/Test-Signing.ps1', '-Python', $Python)
    # Validate unsigned packages with the existing packagers. Final packages are
    # rebuilt after local signing.
    $unsigned = Join-Path $output 'unsigned'
    foreach ($architecture in @('x64', 'x86')) {
        Invoke-Checked "unsigned-$architecture-zip" 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'Package-Windows.ps1',
            '-BuildDirectory', (Join-Path $output 'x64'), '-X86BuildDirectory', (Join-Path $output 'x86'),
            '-Architecture', $architecture, '-Version', $version, '-OutputDirectory', $unsigned)
    }
    Invoke-Checked 'unsigned-setup' 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'Package-Store-Windows.ps1',
        '-BuildDirectory', (Join-Path $output 'x64'), '-X86BuildDirectory', (Join-Path $output 'x86'), '-Version', $version,
        '-OutputDirectory', $unsigned, '-MakensisPath', $MakensisPath, '-UnsignedTest')
    Invoke-Checked 'unsigned-packages' $Python @('Packaging/verify-package.py',
        (Join-Path $unsigned "chichi77-KeyKey-$version-windows-x64.zip"), (Join-Path $unsigned "chichi77-KeyKey-$version-windows-x86.zip"))
    $source = (& git -C $repository rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve build source.' }
    [ordered]@{ schema = 1; source_sha = $source; checks = @($checks.ToArray()); test_results = $testResults } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $report -Encoding UTF8
    & $Python (Join-Path $repository '.github/scripts/windows-signing.py') stage --directory (Join-Path $output 'artifact') --build $output --tag $ReleaseTag
    if ($LASTEXITCODE -ne 0) { throw 'Unsigned artifact staging failed.' }
} finally { $env:KEYKEY_UPDATE_CONFIG = $previousConfig; Pop-Location }
