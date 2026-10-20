# Exercise the shared orchestration without compiling, signing, network or user keys.
param([string] $Python = 'python')
$ErrorActionPreference = 'Stop'
$frontend = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repository = [IO.Path]::GetFullPath((Join-Path $frontend '..\..\..'))
$testRoot = Join-Path $frontend 'out\workflow-fixtures'
$fixture = Join-Path $testRoot ([Guid]::NewGuid().ToString('N').Substring(0, 8))
$fixtureFrontend = Join-Path $fixture 'Source\Loaders\Windows-TSF'
$oldActions = $env:GITHUB_ACTIONS
$oldConfig = $env:KEYKEY_UPDATE_CONFIG
$global:keykeyBuildFixtureCalls = [Collections.Generic.List[string]]::new()
try {
    $copies = @('Source/Loaders/Windows-TSF/CMakeLists.txt', 'Source/Loaders/Windows-TSF/Packaging/Get-ProductVersion.ps1',
        '.github/scripts/windows-signing.py', 'update/prepare.py', 'update/channels.py', 'update/config.json')
    foreach ($relative in $copies) {
        $target = Join-Path $fixture $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repository $relative) -Destination $target
    }
    $scriptPath = Join-Path $frontend 'Build-WindowsRelease.ps1'
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Shared build script has parse errors.' }
    $invoke = $ast.Find({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Checked'
    }, $true)
    # Only external build/test programs are substituted. The real parameter handling,
    # CTest report parsing, update config, artifact staging and environment cleanup run.
    $substitute = @'
function Invoke-Checked {
    param([string] $Name, [string] $Program, [string[]] $Arguments)
    $global:keykeyBuildFixtureCalls.Add($Name)
    if ($Name -eq 'update-config') {
        & $Program @Arguments
        if ($LASTEXITCODE -ne 0) { throw 'Fixture update configuration failed.' }
    } elseif ($Name -eq 'signing-policy') {
        if ($Arguments[[Array]::IndexOf($Arguments, '-Python') + 1] -ne $Python) { throw 'Shared script dropped the requested Python runtime.' }
    } elseif ($Name -like 'build-*') {
        $arch = $Name.Substring(6)
        $runtime = Join-Path $output "$arch/Release"
        $names = @('KeyKeyTsf.dll','KeyKeySettings.exe','KeyKeySettingsBackend.dll','KeyKeyDeployment.exe',
            'WinSparkle.dll','WinSparkle-LICENSE.txt','Databases/KeyKey.db')
        if ($arch -eq 'x86') { $names += 'KeyKeyRegistration.exe' }
        foreach ($runtimeName in $names) {
            $path = Join-Path $runtime $runtimeName
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            [IO.File]::WriteAllText($path, "synthetic $arch/$runtimeName")
        }
        'not part of the upload allowlist' | Set-Content (Join-Path $output 'excluded-marker.txt')
    } elseif ($Name -like 'ctest-*') {
        $result = $Arguments[[Array]::IndexOf($Arguments, '--output-junit') + 1]
        '<testsuite><testcase name="fixture-pass"/><testcase name="fixture-skip"><skipped/></testcase></testsuite>' |
            Set-Content -LiteralPath $result -Encoding UTF8
    } elseif ($Name -in @('unsigned-x64-zip','unsigned-x86-zip','unsigned-setup')) {
        $unsigned = Join-Path $output 'unsigned'
        New-Item -ItemType Directory -Path $unsigned -Force | Out-Null
        $suffix = if ($Name -eq 'unsigned-setup') { 'x64-setup.unsigned.exe' } elseif ($Name -eq 'unsigned-x64-zip') { 'x64.zip' } else { 'x86.zip' }
        $path = Join-Path $unsigned "chichi77-KeyKey-$version-windows-$suffix"
        [IO.File]::WriteAllText($path, 'synthetic unsigned package')
        [IO.File]::WriteAllText($path + '.sha256', 'synthetic checksum')
        if ($Name -eq 'unsigned-setup' -and $Arguments -notcontains '-UnsignedTest') { throw 'CI packaging requested real signing.' }
    }
    $checks.Add([ordered]@{ name = $Name; passed = $true })
}
'@
    $text = [IO.File]::ReadAllText($scriptPath)
    $text = $text.Substring(0, $invoke.Extent.StartOffset) + $substitute + $text.Substring($invoke.Extent.EndOffset)
    [IO.File]::WriteAllText((Join-Path $fixtureFrontend 'Build-WindowsRelease.ps1'), $text, [Text.UTF8Encoding]::new($false))
    $nsis = Join-Path $fixture 'nsis.ps1'
    "'v3.12'; `$global:LASTEXITCODE = 0" | Set-Content -LiteralPath $nsis
    function cmake {}
    function ctest {}
    function ruby {}
    function dotnet {}
    $env:GITHUB_ACTIONS = 'false'
    $output = Join-Path $fixture 'build'
    & (Join-Path $fixtureFrontend 'Build-WindowsRelease.ps1') -OutputDirectory $output -Python $Python -MakensisPath $nsis
    if ($env:KEYKEY_UPDATE_CONFIG -ne $oldConfig) { throw 'Shared build leaked its update configuration environment.' }
    $manifest = Get-Content (Join-Path $output 'artifact/signing-inputs.json') -Raw | ConvertFrom-Json
    $report = Get-Content (Join-Path $output 'artifact/build-checks.json') -Raw | ConvertFrom-Json
    foreach ($arch in @('x64', 'x86')) {
        if (@($report.test_results.$arch | Where-Object status -EQ 'skipped').Count -ne 1) { throw 'Skipped CTest case became a pass.' }
    }
    $names = @($manifest.files.PSObject.Properties.Name)
    if ($names -contains 'excluded-marker.txt' -or @($names | Where-Object { $_ -match 'private|\.pem$' }).Count) {
        throw 'Non-allowlisted data reached the unsigned artifact.'
    }
    if (@($names | Where-Object { $_ -like 'unsigned/*' }).Count -ne 6 -or $manifest.build_source -ne 'local') { throw 'Incorrect unsigned artifact inventory/source.' }
    foreach ($required in @('configure-x64','build-x64','ctest-x64','configure-x86','build-x86','ctest-x86',
        'settings','deployment','shared-x64-x86','shared-x86-x64','shared-managed-x64','shared-managed-x86',
        'update-metadata','updater-x64','updater-x86','unsigned-x64-zip','unsigned-x86-zip','unsigned-setup','unsigned-packages')) {
        if (@($global:keykeyBuildFixtureCalls | Where-Object { $_ -eq $required }).Count -ne 1) { throw "Missing/duplicated shared step: $required" }
    }
} finally {
    $env:GITHUB_ACTIONS = $oldActions
    $env:KEYKEY_UPDATE_CONFIG = $oldConfig
    Remove-Variable keykeyBuildFixtureCalls -Scope Global
    Remove-Item Function:\cmake, Function:\ctest, Function:\ruby, Function:\dotnet -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixture) {
        $resolved = [IO.Path]::GetFullPath($fixture)
        if ([IO.Path]::GetDirectoryName($resolved) -ne $testRoot -or [IO.Path]::GetFileName($resolved) -notmatch '^[0-9a-f]{8}$') { throw 'Unexpected workflow fixture cleanup path.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Host 'Passed shared local/CI orchestration, unsigned staging, skip reporting and upload allowlist tests.'
