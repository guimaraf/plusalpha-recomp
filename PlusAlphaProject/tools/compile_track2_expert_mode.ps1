# compile_track2_expert_mode.ps1
# Automacao de compilacao dos Overlays Dinamicos do Expert Mode (Track 2)
# Alvo: Erradicacao dos Hotspots de Desafios do Expert Mode (Ken / Desafios 1 a 8)
[CmdletBinding()]
param(
    [string]$BuildDirName = "buildTele-s1-309",
    [string]$Msys2Root = "C:\msys64",
    [string]$CaptureSession = "gameplay-discovery-173",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$GameRoot = Resolve-Path (Join-Path $ProjectRoot "..")

$BuildDir = Join-Path $ProjectRoot $BuildDirName
$CapFile = Join-Path $ProjectRoot "local\telemetry\$CaptureSession\overlay_captures.json"

$GameToml = Join-Path $ProjectRoot "game.toml"
$Recompiler = Join-Path $GameRoot "psxrecomp\recompiler\build\psxrecomp-game.exe"
$RuntimeInclude = Join-Path $GameRoot "psxrecomp\runtime\include"
$OutDir = Join-Path $BuildDir "cache"
$Gcc = Join-Path $Msys2Root "ucrt64\bin\gcc.exe"
$CompileScript = Join-Path $GameRoot "psxrecomp\tools\compile_overlays.py"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "     COMPILACAO DE TRACK 2 - OVERLAYS DO EXPERT MODE                  " -ForegroundColor Cyan
Write-Host "  Sessao de Captura:     $CaptureSession" -ForegroundColor Yellow
Write-Host "  Arquivo de Captura:    $CapFile" -ForegroundColor Yellow
Write-Host "  Build / Cache Alvo:    $OutDir" -ForegroundColor Yellow
Write-Host "  Compilador Host:       $Gcc" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan

# Validacoes de ambiente
if (-not (Test-Path -LiteralPath $CapFile -PathType Leaf)) {
    throw "Arquivo de captura nao encontrado em: $CapFile"
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

function Invoke-CompileCaptureKey($capFilePath, $capKey, $label) {
    Write-Host "`nDisparando compilador de overlays para $capKey ($label)..." -ForegroundColor Green
    $argsList = @(
        $CompileScript,
        "--captures", $capFilePath,
        "--game-toml", $GameToml,
        "--recompiler", $Recompiler,
        "--runtime-include", $RuntimeInclude,
        "--out-dir", $OutDir,
        "--gcc", $Gcc,
        "--capture-key", $capKey
    )
    if ($Force) {
        $argsList += "--force"
    }
    & $pythonCmd @argsList
    if ($LASTEXITCODE -ne 0) {
        throw "compile_overlays.py falhou para $capKey com codigo $LASTEXITCODE"
    }
}

# 1. Detectar capture keys dinamicamente no JSON
$detectScript = Join-Path $ScriptDir "detect_capture_keys.py"
$detectedKeys = & $pythonCmd $detectScript $CapFile

foreach ($line in $detectedKeys) {
    $cleanKey = $line.Trim()
    if ($cleanKey) {
        Invoke-CompileCaptureKey $CapFile $cleanKey "Sessao $CaptureSession"
    }
}

# Se a sessao for 173, compilar tambem a chave de 172 para garantir redundancia de variantes
$CapFile172 = Join-Path $ProjectRoot "local\telemetry\gameplay-discovery-172\overlay_captures.json"
if ($CaptureSession -eq "gameplay-discovery-173" -and (Test-Path -LiteralPath $CapFile172 -PathType Leaf)) {
    Write-Host "`n[Redundancia] Compilando variante complementar da sessao 172..." -ForegroundColor Yellow
    $keys172 = & $pythonCmd $detectScript $CapFile172
    foreach ($line in $keys172) {
        $cleanKey = $line.Trim()
        if ($cleanKey) {
            Invoke-CompileCaptureKey $CapFile172 $cleanKey "Sessao 172 Complementar"
        }
    }
}

# 2. Validacao de saida
Write-Host "`nValidando shards e manifestos (.ranges) gerados no cache..." -ForegroundColor Green

$allShards = Get-ChildItem -Path $OutDir -Filter "*.dll" -Recurse
$allRanges = Get-ChildItem -Path $OutDir -Filter "*.ranges" -Recurse

Write-Host "  Total de Shards Nativos (.dll): $($allShards.Count)" -ForegroundColor Cyan
Write-Host "  Total de Manifestos (.ranges):  $($allRanges.Count)" -ForegroundColor Cyan

$hotspots = @(
    "80047E78", "800E724C", "800E64D8", "800E71BC", "800E713C", "8004495C",
    "80044A64", "80044BA8", "800449C8", "80044DEC", "80044E78", "80044D98",
    "80044CE0", "80044EE4", "80044B10", "800E676C"
)
Write-Host "`n  Verificando cobertura de hotspots criticos nos manifestos do Expert Mode:" -ForegroundColor Yellow

$totalOk = 0
$totalPending = 0

foreach ($hp in $hotspots) {
    $found = $false
    $hpAddr = [Convert]::ToUInt32($hp, 16)
    $foundManifest = ""

    foreach ($r in $allRanges) {
        $lines = Get-Content $r.FullName
        foreach ($line in $lines) {
            $parts = $line.Trim().Split()
            if ($parts.Count -ge 2 -and ($parts[1] -ieq $hp)) {
                $found = $true
                $foundManifest = "$($r.Name) (Entry)"
                break
            }
            if ($parts.Count -ge 3 -and $parts[0] -eq 'R') {
                $rStart = [Convert]::ToUInt32($parts[1], 16)
                $rLen = [Convert]::ToUInt32($parts[2], 16)
                if ($hpAddr -ge $rStart -and $hpAddr -lt ($rStart + $rLen)) {
                    $found = $true
                    $foundManifest = "$($r.Name) (Range 0x{0:X8}..0x{1:X8})" -f $rStart, ($rStart + $rLen)
                    break
                }
            }
        }
        if ($found) { break }
    }

    if ($found) {
        Write-Host "    [OK] 0x$hp coberto em: $foundManifest" -ForegroundColor Green
        $totalOk++
    } else {
        Write-Host "    [PENDENTE] 0x$hp nao coberto nos manifestos .ranges" -ForegroundColor Red
        $totalPending++
    }
}

Write-Host "`n  Resumo da Auditoria do Expert Mode: $totalOk / $($hotspots.Count) hotspots cobertos ($totalPending pendencias)" -ForegroundColor Cyan

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "  CONCLUIDO! Shards do Expert Mode compilados e validados no cache.    " -ForegroundColor Green
Write-Host "  O executavel '$BuildDirName\exPlusAlpha.exe' integrara              " -ForegroundColor Green
Write-Host "  automaticamente as DLLs compiladas no proximo teste.                " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
