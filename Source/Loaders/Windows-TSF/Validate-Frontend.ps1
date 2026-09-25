[CmdletBinding()]
param()

$frontend = $PSScriptRoot
$requiredFiles = @(
    'CMakeLists.txt',
    'CandidateWindow.cpp',
    'ComServer.cpp',
    'DatabaseCooker.cpp',
    'Diagnostics.cpp',
    'Diagnostics.h',
    'EngineSmokeTest.cpp',
    'FrontendSettings.cpp',
    'FrontendSettings.h',
    'Guids.h',
    'KeyKeyEngine.cpp',
    'KeyKeyTsf.rc',
    'KeyKeyTsf.def',
    'LangBarButton.cpp',
    'LangBarButton.h',
    'Resource.h',
    'SettingsModern\App.xaml',
    'SettingsModern\KeyKeySettings.csproj',
    'SettingsModern\MainWindow.xaml',
    'SettingsModern\MainWindow.xaml.cs',
    'SettingsModern\SettingsBackend.cpp',
    'TextService.cpp',
    'TsfInterfaceSmokeTest.cpp',
    'VersionInfo.rcinc'
)

$errors = [System.Collections.Generic.List[string]]::new()
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $frontend $file) -PathType Leaf)) {
        $errors.Add("Missing required file: $file")
    }
}

$requiredBinaryFiles = @('chichi77.ico')
foreach ($file in $requiredBinaryFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $frontend $file) -PathType Leaf)) {
        $errors.Add("Missing required binary resource: $file")
    }
}

$textService = Get-Content -LiteralPath (Join-Path $frontend 'TextService.h') -Raw
foreach ($interface in 'ITfTextInputProcessorEx', 'ITfKeyEventSink', 'ITfCompositionSink',
                        'ITfTextEditSink', 'ITfFunctionProvider', 'ITfFnConfigure') {
    if ($textService -notmatch [regex]::Escape($interface)) {
        $errors.Add("TextService does not declare $interface")
    }
}

$exports = Get-Content -LiteralPath (Join-Path $frontend 'KeyKeyTsf.def') -Raw
foreach ($export in 'DllGetClassObject', 'DllCanUnloadNow', 'DllRegisterServer', 'DllUnregisterServer') {
    if ($exports -notmatch [regex]::Escape($export)) {
        $errors.Add("Missing COM export: $export")
    }
}

$comServer = Get-Content -LiteralPath (Join-Path $frontend 'ComServer.cpp') -Raw
if ($comServer -notmatch 'GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT') {
    $errors.Add('TSF registration does not declare immersive-app support')
}

$nativeFiles = Get-ChildItem -LiteralPath $frontend -File |
    Where-Object { $_.Extension -in '.cpp', '.h' }
$nativeSources = $nativeFiles | Get-Content -Raw
$legacyEntryPoints = @('ImeInquire', 'ImeProcessKey', 'ImeToAsciiEx', 'ImmSetCompositionString')
foreach ($entryPoint in $legacyEntryPoints) {
    if ($nativeSources -match [regex]::Escape($entryPoint)) {
        $errors.Add("Modern frontend unexpectedly references legacy IMM32 API: $entryPoint")
    }
}

$cmake = Get-Content -LiteralPath (Join-Path $frontend 'CMakeLists.txt') -Raw
if ($cmake -notmatch 'KEYKEY_MARKETING_VERSION') {
    $errors.Add('CMake does not expose the marketing version to the settings UI')
}
$versionMatch = [regex]::Match($cmake, 'project\(KeyKeyWindowsTsf VERSION ([0-9]+\.[0-9]+\.[0-9]+)')
$settingsView = Get-Content -LiteralPath (Join-Path $frontend 'SettingsModern\MainWindow.xaml') -Raw
if (-not $versionMatch.Success -or
    $settingsView -notmatch [regex]::Escape("版本 $($versionMatch.Groups[1].Value)")) {
    $errors.Add('Settings app does not display the build marketing version')
}
$sourceReferences = [regex]::Matches($cmake, '"\$\{KEYKEY_SOURCE\}/([^"$]+)"')
$repositorySource = Resolve-Path -LiteralPath (Join-Path $frontend '..\..')
foreach ($match in $sourceReferences) {
    $relativePath = $match.Groups[1].Value -replace '/', '\'
    if ([System.IO.Path]::GetExtension($relativePath) -eq '.db') {
        continue
    }
    if (-not (Test-Path -LiteralPath (Join-Path $repositorySource $relativePath))) {
        $errors.Add("CMake references a missing source path: $relativePath")
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Windows TSF frontend static validation passed.'
