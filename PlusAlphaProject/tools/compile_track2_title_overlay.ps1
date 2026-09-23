# compile_track2_title_overlay.ps1
# Automacao de compilacao do Overlay Dinamico da Tela Titulo e Attract (Track 2)
# Alvo: Eliminacao dos Hotspots de Tela Titulo (0x8004A44C, 0x8004922C, 0x80091878, 0x8004AF94, 0x80049500)
# Modulo: 0x80020000..0x800F5000 (872 KB) -> Capture Key: 0x00020000:0xCD5EAEA6
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
$CaptureKey = "0x00020000:0xCD5EAEA6"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "      COMPILACAO DE TRACK 2 - OVERLAY DE TELA TITULO & ATTRACT        " -ForegroundColor Cyan
Write-Host "  Modulo:               Tela Titulo / Attract (0x80020000, 872 KB)    " -ForegroundColor Yellow
Write-Host "  Capture Key:          $CaptureKey" -ForegroundColor Yellow
Write-Host "  Hotspots Alvo:        0x8004A44C, 0x8004922C, 0x80091878, 0x8004AF94" -ForegroundColor Yellow
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

Write-Host "  Shards Nativos (.dll):    $($allShards.Count)" -ForegroundColor Cyan
Write-Host "  Manifestos (.ranges):     $($allRanges.Count)" -ForegroundColor Cyan

# Validar cobertura de 0x8004A44C
$covered = $false
foreach ($r in $allRanges) {
    if ($r.Name -like "*00020000*") {
        $m = Select-String -Path $r.FullName -Pattern "8004A44C" -SimpleMatch
        if ($m) {
            $covered = $true
            Write-Host "  >>> [CONFIRMADO] Hotspot 0x8004A44C coberto em: $($r.Name)" -ForegroundColor Green
            break
        }
    }
}

if (-not $covered) {
    Write-Host "  [AVISO] Hotspot 0x8004A44C nao foi encontrado explicitamente em nenhum manifesto .ranges." -ForegroundColor Yellow
}

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "  COMPILACAO DE TRACK 2 (TELA TITULO) CONCLUIDA COM SUCESSO!          " -ForegroundColor Green
Write-Host "  O executavel '$BuildDirName\exPlusAlpha.exe' carregara              " -ForegroundColor Green
Write-Host "  automaticamente as DLLs de cache na Tela Titulo.                    " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
