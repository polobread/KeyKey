# Shared build/check entry point for local releases and the check-only workflow.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $OutputDirectory,
    [string] $Python = 'python',
    [string] $OpenSslPath
)
$ErrorActionPreference = 'Stop'
$Python = (Get-Command $Python -ErrorAction Stop).Source
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output = [IO.Path]::GetFullPath($OutputDirectory)
$checks = [Collections.Generic.List[object]]::new()
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
    Invoke-Checked 'updater-sdk' $Python @('../../../update/prepare.py', 'fetch', 'windows')
    foreach ($architecture in @('x64', 'x86')) {
        $preset = if ($architecture -eq 'x64') { 'windows-x64-vs2026' } else { 'windows-x86' }
        $build = Join-Path $output $architecture
        Invoke-Checked "configure-$architecture" 'cmake' @('--preset', $preset, '-B', $build, "-DPython3_EXECUTABLE=$Python")
        Invoke-Checked "build-$architecture" 'cmake' @('--build', $build, '--config', 'Release', '--parallel')
        # These two managed cases are run once below, rather than once per bitness.
        Invoke-Checked "ctest-$architecture" 'ctest' @('--test-dir', $build, '-C', 'Release', '--output-on-failure', '--no-tests=error', '-E', '^(KeyKeyDeploymentTransactions|KeyKeySettingsPreferences)$')
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
        Invoke-Checked 'update-metadata' $Python @('-m', 'unittest', 'discover', '-s', '../../../update', '-v')
        foreach ($architecture in @('x64', 'x86')) {
            Invoke-Checked "updater-$architecture" 'dotnet' @('run', '--project', 'DesktopUpdater.Tests/DesktopUpdater.Tests.csproj', '--configuration', 'Release', '-r', "win-$architecture", '--self-contained', '--', '--native', '--openssl', $OpenSslPath)
        }
    } finally { $env:KEYKEY_TEST_OPENSSL = $previousOpenSsl }
    Invoke-Checked 'release-transport' $Python @('-m', 'unittest', 'discover', '-s', '../../../.github/scripts', '-p', 'test_windows_signing.py', '-v')
    Invoke-Checked 'signing-policy' 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'Packaging/Test-Signing.ps1')
    $source = (& git -C $repository rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve build source.' }
    [ordered]@{ schema = 1; source_sha = $source; checks = @($checks.ToArray()) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $report -Encoding UTF8
} finally { Pop-Location }
