# Executar manualmente. O agente prepara os fontes, mas nunca executa build.
[CmdletBinding()]
param(
    [ValidatePattern('^build-input-observation(?:-[A-Za-z0-9_-]+)?$')]
    [string]$BuildDirName = 'build-input-observation',
    [string]$Msys2Root = 'C:\msys64',
    [ValidateSet('SDL3', 'SDL2')][string]$SdlBackend = 'SDL3',
    [ValidateRange(1, 64)][int]$Jobs = 2,
    [string]$BiosPath = '',
    [string]$RetainedOverlayDir = ''
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$BuildDir = Join-Path $ProjectRoot $BuildDirName
if (Test-Path -LiteralPath $BuildDir) {
    throw 'Pasta ja existe e foi preservada. Escolha outro -BuildDirName build-input-observation-N.'
}
# Overlays preparados tambem ficam isolados; nao reutilizar generated-online/retained-overlays.
$BuildArgs = @{
    BuildDirName = $BuildDirName
    StaticOverlayDir = (Join-Path $BuildDir 'static-overlays')
    Msys2Root = $Msys2Root
    SdlBackend = $SdlBackend
    Jobs = $Jobs
}
if ($BiosPath) { $BuildArgs.BiosPath = $BiosPath }
if ($RetainedOverlayDir) { $BuildArgs.RetainedOverlayDir = $RetainedOverlayDir }
& (Join-Path $PSScriptRoot 'build_online.ps1') @BuildArgs
Write-Host 'Build observacional pronta. Use VS OFFLINE, Ryu P1 e Square/soco fraco.' -ForegroundColor Cyan
Write-Host '.\PlusAlphaProject\tools\capture_input_response.ps1 -Button square -CollectOnly -Timing'
