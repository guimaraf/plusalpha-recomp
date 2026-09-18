# generate_s1_285_sources.ps1
# Geracao de fontes e auditoria formal do Micro-Lote S1-285
[CmdletBinding()]
param(
    [string]$RecompilerPath
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$GameRoot = Resolve-Path (Join-Path $ScriptDir "..")
$ConfigPath = Join-Path $GameRoot "game.toml"
$AuditScript = Join-Path $GameRoot "..\psxrecomp\tools\codegen_audit_game.py"
$RangesFile = Join-Path $GameRoot "generated\SLUS_005.48_full.ranges"

if (-not $RecompilerPath) {
    $RecompilerPath = [IO.Path]::GetFullPath((Join-Path $GameRoot "..\psxrecomp\recompiler\build\psxrecomp-game.exe"))
}

if (-not (Test-Path -LiteralPath $RecompilerPath -PathType Leaf)) {
    throw "psxrecomp-game nao encontrado em: $RecompilerPath"
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "game.toml nao encontrado em: $ConfigPath"
}
if (-not (Test-Path -LiteralPath $AuditScript -PathType Leaf)) {
    throw "Script de auditoria ausente em: $AuditScript"
}

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "        GERACAO DE FONTES - MICRO-LOTE S1-285                         " -ForegroundColor Cyan
Write-Host "  Subsistema:  Acrobatic Action, Trajectory & Combat (Skullomania)      " -ForegroundColor Yellow
Write-Host "  Orcamento:   6 funcoes novas, 947 palavras (3.788 bytes)            " -ForegroundColor Yellow
Write-Host "  Meta:        1.214 funcoes nativas, 138.356 palavras (70,7400%)     " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan

Push-Location $GameRoot
try {
    Write-Host "[1/3] Executando psxrecomp-game..." -ForegroundColor Green
    & $RecompilerPath --config $ConfigPath
    if ($LASTEXITCODE -ne 0) {
        throw "psxrecomp-game falhou com codigo $LASTEXITCODE"
    }

    Write-Host "[2/3] Validando manifest de ranges gerado..." -ForegroundColor Green
    $pythonCmd = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $pythonCmd) {
        $pythonCmd = (Get-Command python3 -ErrorAction SilentlyContinue).Source
    }
    if (-not $pythonCmd) {
        throw "Python nao encontrado no PATH."
    }

    $validateScript = @'
import sys

ranges_path = "generated/SLUS_005.48_full.ranges"
funcs = []
ranges = []
total_words = 0

with open(ranges_path, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if parts[0] == "F":
            funcs.append(int(parts[1], 16))
        elif parts[0] == "R":
            start = int(parts[1], 16)
            length = int(parts[2], 16)
            ranges.append((start, length))
            total_words += length // 4

print(f"[OK] Total de funcoes declaradas: {len(funcs)}")
print(f"[OK] Total de palavras compiladas: {total_words}")
pct = (total_words / 195584.0) * 100.0
print(f"[OK] Cobertura alcancada: {pct:.4f}%")

target_funcs = 1214
target_words = 138356

if len(funcs) != target_funcs:
    print(f"ERRO: contagem de funcoes ({len(funcs)}) difere da meta ({target_funcs})", file=sys.stderr)
    sys.exit(1)
if total_words != target_words:
    print(f"ERRO: total de palavras ({total_words}) difere da meta ({target_words})", file=sys.stderr)
    sys.exit(1)

expected_cluster = {
    0x8012A7E4: 656,
    0x801441B0: 156,
    0x8014424C: 332,
    0x80144398: 1856,
    0x80160790: 80,
    0x801607E0: 708,
}

for addr, expected_sz in expected_cluster.items():
    if addr not in funcs:
        print(f"ERRO: Funcao 0x{addr:08X} nao encontrada no manifest!", file=sys.stderr)
        sys.exit(1)
    sz = next((s for lo, s in ranges if lo == addr), None)
    if sz != expected_sz:
        print(f"ERRO: Tamanho de 0x{addr:08X} divergente! Esperado {expected_sz}, obtido {sz}", file=sys.stderr)
        sys.exit(1)

print(f"[OK] Todas as 6 sementes do S1-285 validadas com sucesso: 1.214 funcoes, {total_words} palavras (70.7400%).")
'@

    $valResult = $validateScript | & $pythonCmd -
    if ($LASTEXITCODE -ne 0) {
        throw "Validacao de ranges falhou."
    }
    Write-Host $valResult -ForegroundColor Gray

    Write-Host "[3/3] Executando auditoria formal de codegen..." -ForegroundColor Green
    & $pythonCmd $AuditScript --config $ConfigPath
    if ($LASTEXITCODE -ne 0) {
        throw "Auditoria de codegen acusou inconformidades."
    }

    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host " Fontes de S1-285 gerados e auditados com SUCESSO!                    " -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
}
finally {
    Pop-Location
}
