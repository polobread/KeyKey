[CmdletBinding()]
param([switch] $Quiet)

$ErrorActionPreference = 'Stop'
try {
    $tool = Join-Path $PSScriptRoot 'Payload\KeyKeyDeployment.exe'
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        $tool = Join-Path $PSScriptRoot 'Uninstall.exe'
    }
    $arguments = @('uninstall', '--package', $PSScriptRoot)
    if ($Quiet) { $arguments += '--quiet' }
    & $tool @arguments
    exit $LASTEXITCODE
}
catch {
    Write-Error $_
    exit 1
}
