# compile_track2_menus_overlay.ps1
# Automacao de compilacao dos Overlays Dinamicos de Menus (Track 2)
# Modulos Alvo:
#   1. OVL3/OPTS.OVL (0x80020000..0x80026FFF, 28 KB) -> Chave 0x00020000:0xD955BA78 (Hotspot 0x80021FB0)
#   2. Menus de Sistema / Selecao (0x8008C000..0x800ECFFF, 388 KB) -> Chave 0x0008C000:0xD67A9445
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
$ActiveCaptures = Join-Path $BuildDir "overlay_captures.json"
$MenusExplorationCaptures = Join-Path $ProjectRoot "local\telemetry\menus-exploration-01\overlay_captures.json"
$GameToml = Join-Path $ProjectRoot "game.toml"
$Recompiler = Join-Path $GameRoot "psxrecomp\recompiler\build\psxrecomp-game.exe"
$RuntimeInclude = Join-Path $GameRoot "psxrecomp\runtime\include"
$OutDir = Join-Path $BuildDir "cache"
$Gcc = Join-Path $Msys2Root "ucrt64\bin\gcc.exe"
$CompileScript = Join-Path $GameRoot "psxrecomp\tools\compile_overlays.py"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "      COMPILACAO DE TRACK 2 - OVERLAYS DE MENUS DO JOGO              " -ForegroundColor Cyan
Write-Host "  Modulo 1:             OVL3/OPTS.OVL (0x80020000..0x80027000, 28 KB)" -ForegroundColor Yellow
Write-Host "  Modulo 2:             Menus Sistema / Selecao (0x8008C000, 388 KB) " -ForegroundColor Yellow
Write-Host "  Build / Cache Alvo:   $OutDir" -ForegroundColor Yellow
Write-Host "  Compilador Host:      $Gcc" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan

# Validacoes de ambiente
if (-not (Test-Path -LiteralPath $ActiveCaptures -PathType Leaf)) {
    throw "Arquivo de captura ativo nao encontrado em: $ActiveCaptures"
}
if (-not (Test-Path -LiteralPath $MenusExplorationCaptures -PathType Leaf)) {
    throw "Arquivo de captura de menus nao encontrado em: $MenusExplorationCaptures"
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

# 1. Compilar OVL3/OPTS.OVL (0x00020000:0xD955BA78)
$keyOpts = "0x00020000:0xD955BA78"
Write-Host "`n[1/3] Compilando OPTS.OVL (Menu de Opcoes - $keyOpts)..." -ForegroundColor Green
$optsArgs = @(
    $CompileScript,
    "--captures", $ActiveCaptures,
    "--game-toml", $GameToml,
    "--recompiler", $Recompiler,
    "--runtime-include", $RuntimeInclude,
    "--out-dir", $OutDir,
    "--gcc", $Gcc,
    "--capture-key", $keyOpts
)
if ($Force) { $optsArgs += "--force" }

& $pythonCmd @optsArgs
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao compilar OPTS.OVL com codigo $LASTEXITCODE"
}

# 2. Compilar Menus de Sistema / Selecao (0x0008C000:0xD67A9445)
$keyMenus = "0x0008C000:0xD67A9445"
Write-Host "`n[2/3] Compilando Menus de Sistema / Selecao ($keyMenus)..." -ForegroundColor Green
$menuArgs = @(
    $CompileScript,
    "--captures", $MenusExplorationCaptures,
    "--game-toml", $GameToml,
    "--recompiler", $Recompiler,
    "--runtime-include", $RuntimeInclude,
    "--out-dir", $OutDir,
    "--gcc", $Gcc,
    "--capture-key", $keyMenus
)
if ($Force) { $menuArgs += "--force" }

& $pythonCmd @menuArgs
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao compilar Menus de Sistema com codigo $LASTEXITCODE"
}

# 3. Validacao do Cache Consolidado
Write-Host "`n[3/3] Validando catálogo de shards gerados em $OutDir..." -ForegroundColor Green

$allShards = Get-ChildItem -Path $OutDir -Filter "*.dll" -Recurse
$allRanges = Get-ChildItem -Path $OutDir -Filter "*.ranges" -Recurse

Write-Host "  Total de Shards Nativos (.dll): $($allShards.Count)" -ForegroundColor Cyan
Write-Host "  Total de Manifestos (.ranges):  $($allRanges.Count)" -ForegroundColor Cyan

# Validar cobertura de 0x80021FB0
$optsCovered = $false
foreach ($r in $allRanges) {
    if ($r.Name -like "*00020000*") {
        $m = Select-String -Path $r.FullName -Pattern "80021FB0" -SimpleMatch
        if ($m) {
            $optsCovered = $true
            Write-Host "  >>> [CONFIRMADO] Loop de Opcoes 0x80021FB0 coberto em: $($r.Name)" -ForegroundColor Green
            break
        }
    }
}

if (-not $optsCovered) {
    Write-Host "  [AVISO] Loop 0x80021FB0 nao encontrado explicitamente no manifesto de OPTS." -ForegroundColor Yellow
}

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "  PROMOÇÃO DE TRACK 2 (MENUS) CONCLUÍDA COM SUCESSO!                  " -ForegroundColor Green
Write-Host "  O executável '$BuildDirName\exPlusAlpha.exe' carregará              " -ForegroundColor Green
Write-Host "  automaticamente as DLLs de menus e vídeos na inicialização.         " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
