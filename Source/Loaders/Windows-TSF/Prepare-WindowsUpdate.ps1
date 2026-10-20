# Windows-only Ed25519 preparation. Never prints private key contents or uploads files.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Manifest,
    [string] $PrivateKeyPath = 'keykey-update-private.pem',
    [Parameter(Mandatory = $true)][string] $OutputDirectory,
    [Parameter(Mandatory = $true)][uri] $BaseUrl,
    [string] $Python = 'python',
    [string] $OpenSslPath = 'openssl'
)
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$keyPath = [IO.Path]::GetFullPath($PrivateKeyPath)
if ([IO.Path]::GetFileName($keyPath) -cne 'keykey-update-private.pem') { throw 'Use the designated Windows update private key file.' }
if (-not (Test-Path -LiteralPath $keyPath -PathType Leaf)) { throw 'The Windows update private key is unavailable.' }
$tracked = & git -C $repository ls-files -- 'keykey-update-private.pem*' '**/keykey-update-private.pem*'
if ($LASTEXITCODE -ne 0 -or $tracked) { throw 'The Windows update private key must never be tracked or staged.' }
$changes = & git -C $repository status --porcelain --untracked-files=normal
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Prepare Windows updates from a clean release checkout.' }
$data = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
if ($data.schema_version -ne 1 -or @($data.releases).Count -ne 1 -or $data.releases[0].target -ne 'windows-x64' -or
    $data.releases[0].windows_signing -ne 'authenticode') {
    throw 'Windows update preparation requires one Authenticode x64 installer entry.'
}
$entry = $data.releases[0]
if ($entry.release_tag -cne "v$($entry.version)" -or $entry.release_tag -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:-beta[1-9][0-9]*)?$') {
    throw 'Windows update version/tag mismatch.'
}
$source = & git -C $repository rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot verify Windows update source.' }
$tagSource = & git -C $repository rev-parse "refs/tags/$($entry.release_tag)^{commit}"
if ($LASTEXITCODE -ne 0 -or $entry.source_sha -ne $source -or $entry.tag_sha -ne $tagSource -or $source -ne $tagSource) {
    throw 'Windows update must match the reviewed tag source.'
}
$origin = & git -C $repository remote get-url origin
if ($LASTEXITCODE -ne 0 -or $origin -notin @('https://github.com/polobread/KeyKey.git', 'https://github.com/polobread/KeyKey', 'git@github.com:polobread/KeyKey.git')) {
    throw 'Windows updates require the official repository origin.'
}
$null = & git -C $repository merge-base --is-ancestor $source origin/master
if ($LASTEXITCODE -ne 0) { throw 'Windows update source must have reached reviewed master.' }
if ($BaseUrl.Scheme -ne 'https') { throw 'Windows update assets require HTTPS.' }
# Only OpenSSL (through the local metadata tool) reads the key. Suppress diagnostics.
$arguments = @((Join-Path $repository 'update/metadata.py'), '--openssl', $OpenSslPath, 'build', '--manifest', [IO.Path]::GetFullPath($Manifest),
    '--key', $keyPath, '--base-url', $BaseUrl.AbsoluteUri.TrimEnd('/'), '--out', [IO.Path]::GetFullPath($OutputDirectory))
try {
    $null = & $Python @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Windows Ed25519 preparation failed; check key/public-key agreement, manifest and tools locally.' }
} catch { throw 'Windows Ed25519 preparation failed. Private key and tool diagnostics were suppressed.' }
Write-Host 'Windows Ed25519 metadata and feed prepared locally. Review the public outputs before the feed PR.'
