# compile_track2_bison_boss_overlay.ps1
# Automacao de compilacao dos Shards Dinamicos de Gameplay / Combate (Track 2 - M. Bison Boss CPU)
# Alvo: Erradicacao dos Hotspots de Chefe Final e Teleportes Continuos (PL25_1 / Bison Boss)
# Modulo: 0x80020000..0x800F2000 (840 KB) -> Capture Key: 0x00020000:0x1B719044
[CmdletBinding()]
param(
    [string]$BuildDirName = "buildTele-s1-304",
    [int]$SessionId = 156,
    [string]$Msys2Root = "C:\msys64",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$GameRoot = Resolve-Path (Join-Path $ProjectRoot "..")

$BuildDir = Join-Path $ProjectRoot $BuildDirName
$SessionCaptures = Join-Path $ProjectRoot "local\telemetry\gameplay-discovery-$SessionId\overlay_captures.json"
$BuildCaptures = Join-Path $BuildDir "overlay_captures.json"

if (Test-Path -LiteralPath $SessionCaptures -PathType Leaf) {
    $Captures = $SessionCaptures
} elseif (Test-Path -LiteralPath $BuildCaptures -PathType Leaf) {
    $Captures = $BuildCaptures
} else {
    throw "Arquivo overlay_captures.json nao encontrado nem na sessao $SessionId nem em $BuildDir"
}

$GameToml = Join-Path $ProjectRoot "game.toml"
$Recompiler = Join-Path $GameRoot "psxrecomp\recompiler\build\psxrecomp-game.exe"
$RuntimeInclude = Join-Path $GameRoot "psxrecomp\runtime\include"
$OutDir = Join-Path $BuildDir "cache"
$Gcc = Join-Path $Msys2Root "ucrt64\bin\gcc.exe"
$CompileScript = Join-Path $GameRoot "psxrecomp\tools\compile_overlays.py"
$CaptureKey = "0x00020000:0x1B719044"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  COMPILACAO DE TRACK 2 - OVERLAY (M. BISON BOSS CPU - FINAL ROSTER)  " -ForegroundColor Cyan
Write-Host "  Modulo:               Gameplay / Combate (0x80020000, 840 KB)       " -ForegroundColor Yellow
Write-Host "  Capture Key:          $CaptureKey" -ForegroundColor Yellow
Write-Host "  Origem Capturas:      $Captures" -ForegroundColor Yellow
Write-Host "  Top Hotspots Alvo:    0x8004A370, 0x80049B88, 0x80049E5C, 0x8009125C" -ForegroundColor Yellow
Write-Host "  Subsistemas Cobertos: Chefe Final, Psycho Crusher e Teleporte       " -ForegroundColor Yellow
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

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

# Executar compile_overlays.py
Write-Host "`n[1/2] Disparando compilador de overlays para $CaptureKey..." -ForegroundColor Green
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
    throw "compile_overlays.py falhou com codigo $LASTEXITCODE"
}

# Validacao de saida
Write-Host "`n[2/2] Validando shards e manifestos (.ranges) gerados no cache..." -ForegroundColor Green

$allShards = Get-ChildItem -Path $OutDir -Filter "*.dll" -Recurse
$allRanges = Get-ChildItem -Path $OutDir -Filter "*.ranges" -Recurse

Write-Host "  Total de Shards Nativos (.dll): $($allShards.Count)" -ForegroundColor Cyan
Write-Host "  Total de Manifestos (.ranges):  $($allRanges.Count)" -ForegroundColor Cyan

# Validar cobertura dos top hotspots de combate
$hotspots = @("8004A370", "80049B88", "80049E5C", "8009125C", "8008E25C", "8004501C", "8008E954")
Write-Host "`n  Verificando cobertura de hotspots criticos nos manifestos:" -ForegroundColor Yellow

foreach ($hp in $hotspots) {
    $found = $false
    foreach ($r in $allRanges) {
        $m = Select-String -Path $r.FullName -Pattern $hp -SimpleMatch
        if ($m) {
            $found = $true
            Write-Host "    [OK] 0x$hp coberto em: $($r.Name)" -ForegroundColor Green
            break
        }
    }
    if (-not $found) {
        Write-Host "    [AVISO] 0x$hp nao encontrado diretamente como entrada nos manifestos .ranges" -ForegroundColor DarkYellow
    }
}

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "  COMPILACAO DE TRACK 2 (M. BISON BOSS CPU) CONCLUIDA!                " -ForegroundColor Green
Write-Host "  O executavel '$BuildDirName\exPlusAlpha.exe' carregara              " -ForegroundColor Green
Write-Host "  automaticamente as novas DLLs de combate durante o gameplay.        " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
