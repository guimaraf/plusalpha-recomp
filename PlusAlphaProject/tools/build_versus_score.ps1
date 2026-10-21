# Executar manualmente pelo usuario. Preserva todas as builds existentes.
[CmdletBinding()]
param(
    [switch]$Generate,
    [ValidateRange(1, 64)][int]$Jobs = 2,
    [string]$Msys2Root = 'C:\msys64',
    [string]$BiosPath = '',
    [string]$RetainedOverlayDir = ''
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$BuildName = 'build-online-diagnostics-versus-score-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$BuildArgs = @{
    Generate = [bool]$Generate
    BuildDirName = $BuildName
    Jobs = $Jobs
    Msys2Root = $Msys2Root
    SdlBackend = 'SDL3'
}
if ($BiosPath) { $BuildArgs.BiosPath = $BiosPath }
if ($RetainedOverlayDir) { $BuildArgs.RetainedOverlayDir = $RetainedOverlayDir }
& (Join-Path $PSScriptRoot 'build_online_diagnostics.ps1') @BuildArgs
$Executable = Join-Path (Join-Path $ProjectRoot $BuildName) 'exPlusAlpha.exe'
if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "Build nao concluiu: executavel ausente em $Executable"
}
Write-Host ''
Write-Host 'Build com placar acumulado do Versus pronta.' -ForegroundColor Green
Write-Host 'Teste: P1 vence -> 1 x 0; P2 vence -> 1 x 1; revanche preserva.'
Write-Host 'Menu de modos, load manual e desconexao devem zerar; replay nao duplica.'
Write-Host "Executavel completo: $Executable"
Write-Host "Script completo: $PSCommandPath"
