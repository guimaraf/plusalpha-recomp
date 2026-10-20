# Executar manualmente. Compila em pasta separada e prepara um pacote novo.
[CmdletBinding()]
param(
    [switch]$Generate,
    [switch]$PackageOnly,
    [ValidateRange(1, 64)][int]$Jobs = 4,
    [string]$Msys2Root = 'C:\msys64',
    [string]$BiosPath = '',
    [string]$OutputDir = ''
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ($Generate -and $PackageOnly) { throw '-Generate nao pode ser usado com -PackageOnly.' }
if ($BiosPath -and $PackageOnly) { throw '-BiosPath nao se aplica a -PackageOnly; nenhuma compilacao ocorre nesse modo.' }
if (-not $OutputDir) {
    $OutputDir = Join-Path $ProjectRoot ('dist\exPlusAlpha-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (-not $PackageOnly) {
    & (Join-Path $PSScriptRoot 'build_online.ps1') -Release -BuildDirName build-release-online `
        -Generate:$Generate -Jobs $Jobs -Msys2Root $Msys2Root -BiosPath $BiosPath
}
$Python = (Get-Command python -ErrorAction Stop).Source
& $Python -B (Join-Path $PSScriptRoot 'package_release.py') `
    --build (Join-Path $ProjectRoot 'build-release-online') --output $OutputDir `
    --ucrt-bin (Join-Path $Msys2Root 'ucrt64\bin')
if ($LASTEXITCODE -ne 0) { throw "Empacotamento falhou: $LASTEXITCODE" }
