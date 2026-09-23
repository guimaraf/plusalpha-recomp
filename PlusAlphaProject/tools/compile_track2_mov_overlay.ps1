# compile_track2_mov_overlay.ps1
# Automacao de compilacao do Overlay Dinamico de Video (OVL3/MOV.OVL - Track 2)
# Alvo: Eliminacao do Hotspot 0x800E78DC (~224M de instrucoes interpretadas)
[CmdletBinding()]
param(
    [string]$BuildDirName = "buildTele-s1-304",
    [string]$Msys2Root = "C:\msys64",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$GameRoot = Resolve-Path (Join-Path $ProjectRoot "..")

$BuildDir = Join-Path $ProjectRoot $BuildDirName
$Captures = Join-Path $BuildDir "overlay_captures.json"
$GameToml = Join-Path $ProjectRoot "game.toml"
$Recompiler = Join-Path $GameRoot "psxrecomp\recompiler\build\psxrecomp-game.exe"
$RuntimeInclude = Join-Path $GameRoot "psxrecomp\runtime\include"
$OutDir = Join-Path $BuildDir "cache"
$Gcc = Join-Path $Msys2Root "ucrt64\bin\gcc.exe"
$CompileScript = Join-Path $GameRoot "psxrecomp\tools\compile_overlays.py"
$CaptureKey = "0x000D6000:0xF06249FB"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "      COMPILACAO DE TRACK 2 - OVERLAY DE VIDEO (MOV.OVL)             " -ForegroundColor Cyan
Write-Host "  Modulo:               OVL3/MOV.OVL (0x800D6000..0x800EA000, 80 KB) " -ForegroundColor Yellow
Write-Host "  Capture Key:          $CaptureKey" -ForegroundColor Yellow
Write-Host "  Hotspots Alvo:        0x800E78DC (Loop Streaming), 0x800E7B04, etc. " -ForegroundColor Yellow
Write-Host "  Build / Cache Alvo:   $OutDir" -ForegroundColor Yellow
Write-Host "  Compilador Host:      $Gcc" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan

# Validacoes de ambiente
if (-not (Test-Path -LiteralPath $Captures -PathType Leaf)) {
    throw "Arquivo de captura nao encontrado em: $Captures"
}
if (-not (Test-Path -LiteralPath $GameToml -PathType Leaf)) {
    throw "game.toml nao encontrado em: $GameToml"
}
if (-not (Test-Path -LiteralPath $Recompiler -PathType Leaf)) {
    throw "psxrecomp-game.exe nao encontrado em: $Recompiler"
}
if (-not (Test-Path -LiteralPath $RuntimeInclude -PathType Container)) {
    throw "psxrecomp runtime/include ausente em: $RuntimeInclude"
}
if (-not (Test-Path -LiteralPath $CompileScript -PathType Leaf)) {
    throw "Script compile_overlays.py ausente em: $CompileScript"
}
if (-not (Test-Path -LiteralPath $Gcc -PathType Leaf)) {
    throw "GCC do MSYS2 UCRT64 nao encontrado em: $Gcc"
}

# Detectar Python
$pythonCmd = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pythonCmd) {
    $pythonCmd = (Get-Command python3 -ErrorAction SilentlyContinue).Source
}
if (-not $pythonCmd) {
    throw "Python 3 nao encontrado no PATH."
}

# Criar pasta de cache de destino se nao existir
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

Write-Host "`n[1/2] Executando compile_overlays.py para o shard $CaptureKey..." -ForegroundColor Green

$cmdArgs = @(
    $CompileScript,
    "--captures", $Captures,
    "--game-toml", $GameToml,
    "--recompiler", $Recompiler,
    "--runtime-include", $RuntimeInclude,
    "--out-dir", $OutDir,
    "--gcc", $Gcc,
    "--capture-key", $CaptureKey
)

if ($Force) {
    $cmdArgs += "--force"
}

& $pythonCmd @cmdArgs
if ($LASTEXITCODE -ne 0) {
    throw "compile_overlays.py falhou com codigo de saida $LASTEXITCODE"
}

Write-Host "`n[2/2] Validando shards e manifestos (.ranges) gerados no cache..." -ForegroundColor Green

$shards = Get-ChildItem -Path $OutDir -Filter "*.dll" -Recurse
$ranges = Get-ChildItem -Path $OutDir -Filter "*.ranges" -Recurse

if ($shards.Count -eq 0) {
    throw "Nenhum arquivo DLL foi emitido em $OutDir."
}

Write-Host "  Shards Nativos (.dll):    $($shards.Count)" -ForegroundColor Cyan
Write-Host "  Manifestos (.ranges):     $($ranges.Count)" -ForegroundColor Cyan

# Validar se o hotspot 0x800E78DC foi coberto nos manifests
$hotspotCovered = $false
foreach ($r in $ranges) {
    $match = Select-String -Path $r.FullName -Pattern "800E78DC" -SimpleMatch
    if ($match) {
        $hotspotCovered = $true
        Write-Host "  >>> [CONFIRMADO] Hotspot 0x800E78DC coberto em: $($r.Name)" -ForegroundColor Green
        break
    }
}

if (-not $hotspotCovered) {
    Write-Host "  [AVISO] Hotspot 0x800E78DC nao encontrado explicitamente nos .ranges principais." -ForegroundColor Yellow
}

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "  COMPILACAO DE TRACK 2 CONCLUIDA COM SUCESSO!                        " -ForegroundColor Green
Write-Host "  O executavel '$BuildDirName\exPlusAlpha.exe' carregara              " -ForegroundColor Green
Write-Host "  automaticamente as DLLs de cache ao iniciar os videos.              " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
