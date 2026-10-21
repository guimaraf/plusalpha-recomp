# Executar manualmente. Online completo com diagnostico, em uma pasta nova.
[CmdletBinding()]
param(
    [switch]$Generate,
    [switch]$RunRegressionTests,
    [ValidatePattern('^build-online-diagnostics(?:-[A-Za-z0-9_-]+)?$')]
    [string]$BuildDirName = '',
    [ValidateRange(1, 64)][int]$Jobs = 2,
    [string]$Msys2Root = 'C:\msys64',
    [ValidateSet('SDL3', 'SDL2')][string]$SdlBackend = 'SDL3',
    [string]$BiosPath = '',
    [string]$RetainedOverlayDir = ''
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $BuildDirName) {
    $BuildDirName = 'build-online-diagnostics-sync-trace-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
}
$BuildDir = Join-Path $ProjectRoot $BuildDirName
if (Test-Path -LiteralPath $BuildDir) {
    throw "Build existente preservada: $BuildDir. Escolha outro -BuildDirName."
}
$BuildArgs = @{
    Generate = [bool]$Generate
    BuildDirName = $BuildDirName
    StaticOverlayDir = (Join-Path $BuildDir 'static-overlays')
    Jobs = $Jobs
    Msys2Root = $Msys2Root
    SdlBackend = $SdlBackend
}
if ($BiosPath) { $BuildArgs.BiosPath = $BiosPath }
if ($RetainedOverlayDir) { $BuildArgs.RetainedOverlayDir = $RetainedOverlayDir }
# Sem -Release e sem -SetupHost: RelWithDebInfo, jogo completo e debug server.
& (Join-Path $PSScriptRoot 'build_online.ps1') @BuildArgs

$Cache = Get-Content -LiteralPath (Join-Path $BuildDir 'CMakeCache.txt') -Raw
foreach ($Required in @('PSX_NETPLAY', 'PSX_RECOMP_UI', 'PSX_DEBUG_TOOLS', 'RNET_ENABLE_ICE')) {
    if ($Cache -notmatch ('(?m)^{0}:BOOL=ON\r?$' -f $Required)) {
        throw "Build incompleta para diagnostico: $Required precisa estar ON."
    }
}
$Executable = Join-Path $BuildDir 'exPlusAlpha.exe'
if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "Executavel nao encontrado: $Executable"
}
if ($RunRegressionTests) {
    $Python = (Get-Command python -ErrorAction Stop).Source
    $Compiler = Join-Path $Msys2Root 'ucrt64\bin\gcc.exe'
    $Test = Join-Path $ProjectRoot '..\psxrecomp\runtime\tests\test_netplay_fmv_media_detection.py'
    & $Python -B $Test --compiler $Compiler
    if ($LASTEXITCODE -ne 0) { throw "Regressao FMV/XA falhou: $LASTEXITCODE" }
}
Write-Host "Build online com diagnostico pronta: $Executable" -ForegroundColor Green
Write-Host 'Use a mesma build nos dois pares, com --debug-port 4531 e --debug-port 4532.'
Write-Host 'Ao iniciar, PSX_DEBUG_TOGGLES=0 desativa apenas as teclas experimentais de renderizacao; o debug server continua ativo.'
Write-Host 'Durante a luta, netplay_status deve mostrar xa_stream_active=1 e fmv_media_active=0; video_info deve mostrar gl_swap_interval=0.'

Write-Host 'Para o estudo de sincronismo, inicie ambas com PSX_NET_SYNC_TRACE=1 e execute capture_net_sync.ps1 antes de criar a sala.'
