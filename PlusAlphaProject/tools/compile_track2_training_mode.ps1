# compile_track2_training_mode.ps1
# Automacao de compilacao dos Overlays Dinamicos do Training Mode (Track 2)
# Alvo: Erradicacao dos Hotspots de Treinamento (Ken x Ryu / Combos / Pause de Treino)
[CmdletBinding()]
param(
    [string]$BuildDirName = "buildTele-s1-309",
    [string]$Msys2Root = "C:\msys64",
    [string]$CaptureSession = "gameplay-discovery-178",
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
Write-Host "     COMPILACAO DE TRACK 2 - OVERLAYS DO TRAINING MODE                " -ForegroundColor Cyan
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

# 1. Compilar sessoes de treinamento (178 principal, 177 e 176 complementares)
$detectScript = Join-Path $ScriptDir "detect_capture_keys.py"
$sessions = @($CaptureSession, "gameplay-discovery-177", "gameplay-discovery-176") | Select-Object -Unique

foreach ($sess in $sessions) {
    $sessionCapFile = Join-Path $ProjectRoot "local\telemetry\$sess\overlay_captures.json"
    if (Test-Path -LiteralPath $sessionCapFile -PathType Leaf) {
        Write-Host "`nDetectando chaves para $sess..." -ForegroundColor Cyan
        $detectedKeys = & $pythonCmd $detectScript $sessionCapFile
        foreach ($line in $detectedKeys) {
            $cleanKey = $line.Trim()
            if ($cleanKey) {
                Invoke-CompileCaptureKey $sessionCapFile $cleanKey "Sessao $sess"
            }
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
    "8004809C", "80047E78", "80046BC8", "8004649C", "80044818", "8004488C",
    "800454DC", "800451B0", "8004479C", "8004610C", "8004563C", "80044F24",
    "80045D08", "800467F8", "80046964", "80046640", "800467B0", "80044900",
    "80046B90", "800466D4", "800468C4", "800469C8"
)
Write-Host "`n  Verificando cobertura de hotspots criticos nos manifestos do Training Mode:" -ForegroundColor Yellow

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

Write-Host "`n  Resumo da Auditoria do Training Mode: $totalOk / $($hotspots.Count) hotspots cobertos ($totalPending pendencias)" -ForegroundColor Cyan

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "  CONCLUIDO! Shards do Training Mode compilados e validados no cache.  " -ForegroundColor Green
Write-Host "  O executavel '$BuildDirName\exPlusAlpha.exe' integrara              " -ForegroundColor Green
Write-Host "  automaticamente as DLLs compiladas no proximo teste.                " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
