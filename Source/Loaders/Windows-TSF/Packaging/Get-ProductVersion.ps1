function Get-KeyKeyProductVersion {
    param([string] $CMakePath = (Join-Path $PSScriptRoot '..\CMakeLists.txt'))

    $contents = Get-Content -LiteralPath $CMakePath -Raw -Encoding UTF8
    if ($contents -notmatch 'project\(KeyKeyWindowsTsf VERSION ([0-9]+(?:\.[0-9]+){2,3}) LANGUAGES C CXX\)') {
        throw 'Could not read the Windows product version from CMakeLists.txt.'
    }
    return $Matches[1]
}
