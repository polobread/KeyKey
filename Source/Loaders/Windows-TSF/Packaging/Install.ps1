[CmdletBinding()]
param([switch] $Quiet, [switch] $Repair)

$ErrorActionPreference = 'Stop'
try {
    $tool = Join-Path $PSScriptRoot 'Payload\KeyKeyDeployment.exe'
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw 'Extract the complete ZIP before installing.'
    }
    $operation = if ($Repair) { 'repair' } else { 'install' }
    $arguments = @($operation, '--package', $PSScriptRoot)
    if ($Quiet) { $arguments += '--quiet' }
    & $tool @arguments
    exit $LASTEXITCODE
}
catch {
    Write-Error $_
    exit 1
}
