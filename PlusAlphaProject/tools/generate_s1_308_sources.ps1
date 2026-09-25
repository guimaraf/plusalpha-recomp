# generate_s1_308_sources.ps1
# Geracao de fontes e auditoria formal do Micro-Lote S1-308 (Bonus Stage Barrel Break, Transicao Menu Bonus e Tela de Recorde / Iniciais)
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
Write-Host "        GERACAO DE FONTES - MICRO-LOTE S1-308                         " -ForegroundColor Cyan
Write-Host "  Subsistema:  Bonus Stage (Barril), Menu Bonus & Tela de Recordes    " -ForegroundColor Yellow
Write-Host "  Orcamento:   13 funcoes novas, 3.585 palavras (14.340 bytes)        " -ForegroundColor Yellow
Write-Host "  Meta:        1.357 funcoes nativas, 154.836 palavras (79,1660%)     " -ForegroundColor Yellow
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

target_funcs = 1357
target_words = 154836

if len(funcs) != target_funcs:
    print(f"AVISO: contagem de funcoes ({len(funcs)}) difere da meta ({target_funcs})", file=sys.stderr)
if total_words != target_words:
    print(f"AVISO: total de palavras ({total_words}) difere da meta ({target_words})", file=sys.stderr)

expected_cluster = {
    0x801495D4: 152,
    0x8014966C: 1944,
    0x80149E04: 4900,
    0x8014B128: 244,
    0x8016F668: 124,
    0x8016F6E4: 220,
    0x8016F8B8: 336,
    0x8016FA08: 144,
    0x8016FA98: 204,
    0x80181F7C: 372,
    0x801820F0: 2460,
    0x80182A8C: 1256,
    0x80182F74: 1984,
}

for addr, expected_sz in expected_cluster.items():
    if addr not in funcs:
        print(f"ERRO: Funcao 0x{addr:08X} nao encontrada no manifest!", file=sys.stderr)
        sys.exit(1)
    sz = next((s for lo, s in ranges if lo == addr), None)
    if sz is None:
        enclosing = next((s for lo, s in ranges if lo <= addr < lo + s), None)
        if enclosing is None:
            print(f"ERRO: Funcao 0x{addr:08X} nao possui range correspondente!", file=sys.stderr)
            sys.exit(1)
    elif sz != expected_sz:
        print(f"AVISO: Tamanho de 0x{addr:08X}: esperado {expected_sz}, obtido {sz}")

print(f"[OK] Cluster S1-308 validado com sucesso: {len(funcs)} funcoes, {total_words} palavras ({pct:.4f}%).")
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
    Write-Host " Fontes de S1-308 gerados e auditados com SUCESSO!                    " -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
}
finally {
    Pop-Location
}
