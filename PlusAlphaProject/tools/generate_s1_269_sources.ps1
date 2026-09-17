# generate_s1_269_sources.ps1
# Geracao de fontes e auditoria formal do Micro-Lote S1-269
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
Write-Host "        GERACAO DE FONTES - MICRO-LOTE S1-269                         " -ForegroundColor Cyan
Write-Host "  Raiz:       0x8014FE30 (3D Projectile / Particle & Effect Processor)" -ForegroundColor Yellow
Write-Host "  Orcamento:  1 funcao nova, 298 palavras (1.192 bytes)               " -ForegroundColor Yellow
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
            lo = int(parts[1], 16)
            sz = int(parts[2], 16)
            ranges.append((lo, sz))
            total_words += sz // 4

EXPECTED_FUNCS = 1114
EXPECTED_WORDS = 127128

if len(funcs) != EXPECTED_FUNCS:
    print(f"ERRO: Contagem de funcoes divergente! Esperado {EXPECTED_FUNCS}, obtido {len(funcs)}", file=sys.stderr)
    sys.exit(1)

if total_words != EXPECTED_WORDS:
    print(f"ERRO: Contagem de palavras divergente! Esperado {EXPECTED_WORDS}, obtido {total_words}", file=sys.stderr)
    sys.exit(1)

expected_cluster = {
    0x8014FE30: 1192,
}

for addr, expected_sz in expected_cluster.items():
    if addr not in funcs:
        print(f"ERRO: Funcao 0x{addr:08X} nao encontrada no manifest de funcoes!", file=sys.stderr)
        sys.exit(1)
    sz = next((s for lo, s in ranges if lo == addr), None)
    if sz != expected_sz:
        print(f"ERRO: Tamanho do range de 0x{addr:08X} divergente! Esperado {expected_sz} bytes, obtido {sz}", file=sys.stderr)
        sys.exit(1)

print(f"[OK] Manifest validado com sucesso: {len(funcs)} funcoes, {total_words} palavras (64.9991% de cobertura estatica).")
'@

    $valResult = $validateScript | & $pythonCmd -
    if ($LASTEXITCODE -ne 0) {
        throw "Falha na validacao do manifest de ranges!"
    }
    Write-Host $valResult -ForegroundColor Gray

    Write-Host "[3/3] Executando auditoria formal do codigo C gerado (codegen audit)..." -ForegroundColor Green
    & $pythonCmd $AuditScript --config $ConfigPath
    if ($LASTEXITCODE -ne 0) {
        throw "Falha no codegen audit!"
    }

    Write-Host ""
    Write-Host "[+] MICRO-LOTE S1-269 GERADO E AUDITADO COM SUCESSO!" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
