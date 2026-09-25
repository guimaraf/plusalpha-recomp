# compile_track2_bonus_barrel_overlay.ps1
# Automacao de compilacao dos Shards Dinamicos do Bonus Stage (Track 2 - Bonus Barril, Replay e Tela de Recorde)
# Alvo: Erradicacao dos Hotspots de Bonus Stage / Replay / Ranking
#
# Uso padrao (Lote 1 historico 167/166):
#   .\compile_track2_bonus_barrel_overlay.ps1
#
# Uso com nova sessao limpa intra-gameplay (Lote 2 - Ex: Teste 169):
#   .\compile_track2_bonus_barrel_overlay.ps1 -CleanCaptureSession "gameplay-discovery-169"
[CmdletBinding()]
param(
    [string]$BuildDirName = "buildTele-s1-308",
    [string]$Msys2Root = "C:\msys64",
    [string]$CleanCaptureSession = "",
    [switch]$Force,
    [switch]$SyncOnly
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
if ($CleanCaptureSession) {
    Write-Host "  Modo:                  Lote 2 (Sessao Limpa: $CleanCaptureSession)" -ForegroundColor Green
} else {
    Write-Host "  Modo:                  Lote 1 (Sessoes Base 167 / 166)" -ForegroundColor Yellow
}
Write-Host "  Build / Cache Alvo:    $OutDir" -ForegroundColor Yellow
Write-Host "  Compilador Host:       $Gcc" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan

# Validacoes de ambiente
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

function Invoke-CompileCaptureKey($capFile, $capKey, $label) {
    Write-Host "`nDisparando compilador de overlays para $capKey ($label)..." -ForegroundColor Green
    $argsList = @(
        $CompileScript,
        "--captures", $capFile,
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

if (-not $SyncOnly) {
    if ($CleanCaptureSession) {
        $CleanCapFile = Join-Path $ProjectRoot "local\telemetry\$CleanCaptureSession\overlay_captures.json"
        if (-not (Test-Path -LiteralPath $CleanCapFile -PathType Leaf)) {
            throw "Arquivo de captura da sessao limpa nao encontrado em: $CleanCapFile"
        }

        # Detectar capture keys dinamicamente no JSON
        $detectScript = Join-Path $ScriptDir "detect_capture_keys.py"
        $detectedKeys = & $pythonCmd $detectScript $CleanCapFile
        
        foreach ($line in $detectedKeys) {
            $cleanKey = $line.Trim()
            if ($cleanKey) {
                Invoke-CompileCaptureKey $CleanCapFile $cleanKey "Sessao Limpa $CleanCaptureSession"
            }
        }
    } else {
        # 1. Compilar variante principal 0x00018000:0x19B8E508 (Sessao 167)
        if (Test-Path -LiteralPath $Captures167 -PathType Leaf) {
            Invoke-CompileCaptureKey $Captures167 "0x00018000:0x19B8E508" "Sessao 167"
        }
        # 2. Compilar variante adjacente 0x00016000:0x21A4041B (Sessao 166)
        if (Test-Path -LiteralPath $Captures166 -PathType Leaf) {
            Invoke-CompileCaptureKey $Captures166 "0x00016000:0x21A4041B" "Sessao 166"
        }
    }
} else {
    Write-Host "`nModo SyncOnly ativo: pulando compilador host e partindo direto para sincronizacao e auditoria..." -ForegroundColor Yellow
}

# 3. Sincronizacao de paridade dual-base de overlays (0x00016000 <-> 0x00018000)
Write-Host "`nSincronizando paridade de bases dinamicas de overlay (0x00016000 <-> 0x00018000)..." -ForegroundColor Yellow

$allDlls16 = Get-ChildItem -Path $OutDir -Filter "00016000_*.dll" -Recurse
foreach ($d16 in $allDlls16) {
    $baseName = $d16.Name.Substring(9)
    $targetDllName = "00018000_" + $baseName
    $targetDllPath = Join-Path $d16.DirectoryName $targetDllName
    if (-not (Test-Path -LiteralPath $targetDllPath)) {
        Copy-Item -LiteralPath $d16.FullName -Destination $targetDllPath
        Write-Host "  [SYNC 16->18] DLL espelhada: $targetDllName" -ForegroundColor Cyan
    }
    
    $r16Name = $d16.BaseName + ".ranges"
    $r16Path = Join-Path $d16.DirectoryName $r16Name
    if (Test-Path -LiteralPath $r16Path) {
        $targetRangesName = "00018000_" + [System.IO.Path]::GetFileNameWithoutExtension($baseName) + ".ranges"
        $targetRangesPath = Join-Path $d16.DirectoryName $targetRangesName
        if (-not (Test-Path -LiteralPath $targetRangesPath)) {
            Copy-Item -LiteralPath $r16Path -Destination $targetRangesPath
            Write-Host "  [SYNC 16->18] Ranges espelhado: $targetRangesName" -ForegroundColor Cyan
        }
    }
}

$allDlls18 = Get-ChildItem -Path $OutDir -Filter "00018000_*.dll" -Recurse
foreach ($d18 in $allDlls18) {
    $baseName = $d18.Name.Substring(9)
    $targetDllName = "00016000_" + $baseName
    $targetDllPath = Join-Path $d18.DirectoryName $targetDllName
    if (-not (Test-Path -LiteralPath $targetDllPath)) {
        Copy-Item -LiteralPath $d18.FullName -Destination $targetDllPath
        Write-Host "  [SYNC 18->16] DLL espelhada: $targetDllName" -ForegroundColor Cyan
    }
    
    $r18Name = $d18.BaseName + ".ranges"
    $r18Path = Join-Path $d18.DirectoryName $r18Name
    if (Test-Path -LiteralPath $r18Path) {
        $targetRangesName = "00016000_" + [System.IO.Path]::GetFileNameWithoutExtension($baseName) + ".ranges"
        $targetRangesPath = Join-Path $d18.DirectoryName $targetRangesName
        if (-not (Test-Path -LiteralPath $targetRangesPath)) {
            Copy-Item -LiteralPath $r18Path -Destination $targetRangesPath
            Write-Host "  [SYNC 18->16] Ranges espelhado: $targetRangesName" -ForegroundColor Cyan
        }
    }
}

# 4. Validacao de saida e auditoria estrita de cobertura
Write-Host "`nValidando shards e manifestos (.ranges) gerados no cache..." -ForegroundColor Green

$allShards = Get-ChildItem -Path $OutDir -Filter "*.dll" -Recurse
$allRanges = Get-ChildItem -Path $OutDir -Filter "*.ranges" -Recurse

Write-Host "  Total de Shards Nativos (.dll): $($allShards.Count)" -ForegroundColor Cyan
Write-Host "  Total de Manifestos (.ranges):  $($allRanges.Count)" -ForegroundColor Cyan

$hotspots = @(
    "8001D4B4", "80047E78", "8001BF44", "8001BD70", "8001C530", "8001B90C", "8004495C",
    "8001910C", "80019B30", "8001BA70", "8001952C", "80018DE0", "8001AB70", "8001C1C0",
    "8001B4C8", "8001C260", "8001C1EC", "8001B6C0", "8001C180", "8001B740", "8001B598",
    "8001B604", "8001B7C0", "8001B670"
)
Write-Host "`n  Verificando cobertura de hotspots criticos nos manifestos (Checagem Dual-Base):" -ForegroundColor Yellow

$totalOk = 0
$totalPending = 0

foreach ($hp in $hotspots) {
    $hpAddr = [Convert]::ToUInt32($hp, 16)
    $cov16 = ""
    $cov18 = ""

    foreach ($r in $allRanges) {
        $rName = $r.Name
        $is16 = $rName.StartsWith("00016000_")
        $is18 = $rName.StartsWith("00018000_")
        if (-not ($is16 -or $is18)) { continue }

        $lines = Get-Content $r.FullName
        foreach ($line in $lines) {
            $parts = $line.Trim().Split()
            if ($parts.Count -ge 2 -and ($parts[1] -ieq $hp)) {
                if ($is16 -and -not $cov16) { $cov16 = "$rName (Entry)" }
                if ($is18 -and -not $cov18) { $cov18 = "$rName (Entry)" }
                break
            }
            if ($parts.Count -ge 3 -and $parts[0] -eq 'R') {
                $rStart = [Convert]::ToUInt32($parts[1], 16)
                $rLen = [Convert]::ToUInt32($parts[2], 16)
                if ($hpAddr -ge $rStart -and $hpAddr -lt ($rStart + $rLen)) {
                    if ($is16 -and -not $cov16) { $cov16 = "$rName (Range 0x{0:X8}..0x{1:X8})" -f $rStart, ($rStart + $rLen) }
                    if ($is18 -and -not $cov18) { $cov18 = "$rName (Range 0x{0:X8}..0x{1:X8})" -f $rStart, ($rStart + $rLen) }
                    break
                }
            }
        }
        if ($cov16 -and $cov18) { break }
    }

    if ($cov16 -and $cov18) {
        Write-Host "    [OK - Dual Base] 0x$hp coberto em:" -ForegroundColor Green
        Write-Host "      Base 0x00016000: $cov16" -ForegroundColor Green
        Write-Host "      Base 0x00018000: $cov18" -ForegroundColor Green
        $totalOk++
    } elseif ($cov16) {
        Write-Host "    [ALERTA - Base Unica] 0x$hp coberto SOMENTE em 0x00016000 ($cov16)" -ForegroundColor Yellow
        $totalPending++
    } elseif ($cov18) {
        Write-Host "    [ALERTA - Base Unica] 0x$hp coberto SOMENTE em 0x00018000 ($cov18)" -ForegroundColor Yellow
        $totalPending++
    } else {
        Write-Host "    [PENDENTE] 0x$hp nao coberto nos manifestos .ranges" -ForegroundColor Red
        $totalPending++
    }
}

Write-Host "`n  Resumo da Auditoria de Hotspots: $totalOk / $($hotspots.Count) com Dual-Base OK ($totalPending pendencias)" -ForegroundColor Cyan

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "  CONCLUIDO! Shards de Track 2 sincronizados e validados no cache.    " -ForegroundColor Green
Write-Host "  O executavel '$BuildDirName\exPlusAlpha.exe' integrara              " -ForegroundColor Green
Write-Host "  automaticamente as DLLs compiladas no proximo teste.                " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan

