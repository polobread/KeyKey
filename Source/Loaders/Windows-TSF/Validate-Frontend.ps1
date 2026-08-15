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
    'Guids.h',
    'KeyKeyEngine.cpp',
    'KeyKeySettings.rc',
    'KeyKeyTsf.rc',
    'KeyKeyTsf.def',
    'LangBarButton.cpp',
    'LangBarButton.h',
    'Resource.h',
    'SettingsApp.cpp',
    'TextService.cpp',
    'TsfInterfaceSmokeTest.cpp'
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
                        'ITfFunctionProvider', 'ITfFnConfigure') {
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
