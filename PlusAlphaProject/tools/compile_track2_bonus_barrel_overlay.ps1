# compile_track2_bonus_barrel_overlay.ps1
# Automacao de compilacao dos Shards Dinamicos do Bonus Stage (Track 2 - Bonus Barril, Replay e Tela de Recorde)
# Alvo: Erradicacao dos Hotspots de Bonus Stage / Replay / Ranking (0x8001D4B4 [260M], 0x80047E78 [26.4M], 0x8001BF44 [14M], 0x8001BD70 [6M])
# Modulos:
#   - Sessao 167: 0x00018000:0x19B8E508 (720 KB, 153 seeds, 8.276 PCs executados)
#   - Sessao 166: 0x00016000:0x21A4041B (892 KB, 192 seeds, 9.758 PCs executados)
[CmdletBinding()]
param(
    [string]$BuildDirName = "buildTele-s1-308",
    [string]$Msys2Root = "C:\msys64",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$GameRoot = Resolve-Path (Join-Path $ProjectRoot "..")

$BuildDir = Join-Path $ProjectRoot $BuildDirName
$Captures167 = Join-Path $ProjectRoot "local\telemetry\gameplay-discovery-167\overlay_captures.json"
$Captures166 = Join-Path $ProjectRoot "local\telemetry\gameplay-discovery-166\overlay_captures.json"

$GameToml = Join-Path $ProjectRoot "game.toml"
$Recompiler = Join-Path $GameRoot "psxrecomp\recompiler\build\psxrecomp-game.exe"
$RuntimeInclude = Join-Path $GameRoot "psxrecomp\runtime\include"
$OutDir = Join-Path $BuildDir "cache"
$Gcc = Join-Path $Msys2Root "ucrt64\bin\gcc.exe"
$CompileScript = Join-Path $GameRoot "psxrecomp\tools\compile_overlays.py"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  COMPILACAO DE TRACK 2 - OVERLAY (BONUS BARRIL, REPLAY & RECORDE)    " -ForegroundColor Cyan
Write-Host "  Capture Key (Run 167): 0x00018000:0x19B8E508 (720 KB)               " -ForegroundColor Yellow
Write-Host "  Capture Key (Run 166): 0x00016000:0x21A4041B (892 KB)               " -ForegroundColor Yellow
Write-Host "  Top Hotspots Alvo:     0x8001D4B4, 0x80047E78, 0x8001BF44, 0x8001BD70" -ForegroundColor Yellow
Write-Host "  Build / Cache Alvo:    $OutDir" -ForegroundColor Yellow
Write-Host "  Compilador Host:       $Gcc" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan

# Validacoes de ambiente
if (-not (Test-Path -LiteralPath $Captures167 -PathType Leaf)) {
    throw "Arquivo de captura 167 nao encontrado em: $Captures167"
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

# 1. Compilar variante principal 0x00018000:0x19B8E508 (Sessao 167)
$Key167 = "0x00018000:0x19B8E508"
Write-Host "`n[1/3] Disparando compilador de overlays para $Key167 (Sessao 167)..." -ForegroundColor Green
$cmdArgs167 = @(
    $CompileScript,
    "--captures", $Captures167,
    "--game-toml", $GameToml,
    "--recompiler", $Recompiler,
    "--runtime-include", $RuntimeInclude,
    "--out-dir", $OutDir,
    "--gcc", $Gcc,
    "--capture-key", $Key167
)
if ($Force) {
    $cmdArgs167 += "--force"
}
& $pythonCmd @cmdArgs167
if ($LASTEXITCODE -ne 0) {
    throw "compile_overlays.py falhou para $Key167 com codigo $LASTEXITCODE"
}

# 2. Compilar variante adjacente 0x00016000:0x21A4041B (Sessao 166) se disponivel
if (Test-Path -LiteralPath $Captures166 -PathType Leaf) {
    $Key166 = "0x00016000:0x21A4041B"
    Write-Host "`n[2/3] Disparando compilador de overlays para $Key166 (Sessao 166)..." -ForegroundColor Green
    $cmdArgs166 = @(
        $CompileScript,
        "--captures", $Captures166,
        "--game-toml", $GameToml,
        "--recompiler", $Recompiler,
        "--runtime-include", $RuntimeInclude,
        "--out-dir", $OutDir,
        "--gcc", $Gcc,
        "--capture-key", $Key166
    )
    if ($Force) {
        $cmdArgs166 += "--force"
    }
    & $pythonCmd @cmdArgs166
    if ($LASTEXITCODE -ne 0) {
        throw "compile_overlays.py falhou para $Key166 com codigo $LASTEXITCODE"
    }
}

# 3. Validacao de saida
Write-Host "`n[3/3] Validando shards e manifestos (.ranges) gerados no cache..." -ForegroundColor Green

$allShards = Get-ChildItem -Path $OutDir -Filter "*.dll" -Recurse
$allRanges = Get-ChildItem -Path $OutDir -Filter "*.ranges" -Recurse

Write-Host "  Total de Shards Nativos (.dll): $($allShards.Count)" -ForegroundColor Cyan
Write-Host "  Total de Manifestos (.ranges):  $($allRanges.Count)" -ForegroundColor Cyan

$hotspots = @("8001D4B4", "80047E78", "8001BF44", "8001BD70", "8001C1C0", "8001C530", "8001B90C", "8004495C")
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
Write-Host "  COMPILACAO DE TRACK 2 (BONUS BARRIL & REPLAY) CONCLUIDA!            " -ForegroundColor Green
Write-Host "  O executavel '$BuildDirName\exPlusAlpha.exe' carregara              " -ForegroundColor Green
Write-Host "  automaticamente as novas DLLs de Bonus Stage no proximo teste.      " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
