function New-KeyKeyPackageManifest {
    param(
        [Parameter(Mandatory = $true)][string] $PackageDirectory,
        [Parameter(Mandatory = $true)][string] $Version,
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'x86')][string] $Architecture,
        [bool] $Signed = $false
    )
    $payload = Join-Path $PackageDirectory 'Payload'
    $files = @(Get-ChildItem -LiteralPath $payload -File -Recurse |
        Sort-Object FullName | ForEach-Object {
            [ordered]@{
                Path = $_.FullName.Substring($payload.Length + 1)
                Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        })
    [ordered]@{
        SchemaVersion = 1
        Version = $Version
        Architecture = $Architecture
        Signed = $Signed
        Files = $files
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath `
        (Join-Path $PackageDirectory 'PackageManifest.json') -Encoding UTF8
}
