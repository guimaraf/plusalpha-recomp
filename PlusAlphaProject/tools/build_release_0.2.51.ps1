# Build and verify a fresh 0.2.51 Windows distribution. Run manually.
[CmdletBinding()]
param(
    [ValidateRange(1, 64)][int]$Jobs = 2,
    [string]$Msys2Root = 'C:\msys64',
    [string]$BiosPath = '',
    [string]$RetainedOverlayDir = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
if ($version -ne '0.2.51') { throw "Expected VERSION 0.2.51, found '$version'." }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$output = Join-Path $projectRoot "dist\exPlusAlpha-v0.2.51-Windows-x64-$stamp"
$argsForRelease = @{
    Jobs = $Jobs
    Msys2Root = $Msys2Root
    SdlBackend = 'SDL3'
    OutputDir = $output
}
if ($BiosPath) { $argsForRelease.BiosPath = $BiosPath }
if ($RetainedOverlayDir) { $argsForRelease.RetainedOverlayDir = $RetainedOverlayDir }
& (Join-Path $PSScriptRoot 'build_release.ps1') @argsForRelease

$zipPath = "$output.zip"
$checksumPath = "$zipPath.sha256"
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
    throw 'The distribution ZIP or its checksum is missing.'
}
$expectedHash = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split '\s+')[0]
$actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) { throw 'The ZIP checksum does not match.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $versionEntries = @($archive.Entries | Where-Object { $_.FullName -match '(^|/)psx_game_version\.txt$' })
    if ($versionEntries.Count -ne 1) { throw 'Expected exactly one version file in the ZIP.' }
    $reader = New-Object System.IO.StreamReader($versionEntries[0].Open())
    try { $packagedVersion = $reader.ReadToEnd().Trim() } finally { $reader.Dispose() }
    if ($packagedVersion -ne '0.2.51') { throw "Unexpected packaged version: $packagedVersion" }
    if (@($archive.Entries | Where-Object { $_.FullName -match '(^|/)mods/bundled/psx\.enhancement\.hd-textures/' }).Count -ne 0) {
        throw 'The excluded HD Texture Packs mod is present in the ZIP.'
    }
} finally { $archive.Dispose() }
Write-Host "Verified version 0.2.51; HD Texture Packs absent; SHA-256 $actualHash" -ForegroundColor Green
Write-Host "Distribution ZIP: $zipPath" -ForegroundColor Green
