# generate_s1_273_sources.ps1
# Geracao de fontes e auditoria formal do Micro-Lote S1-273 (Clusters A, B e C)
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
Write-Host "        GERACAO DE FONTES - MICRO-LOTE S1-273                         " -ForegroundColor Cyan
Write-Host "  Clusters:   A (NOP Handler), B (Special/Effects), C (Render/Model)  " -ForegroundColor Yellow
Write-Host "  Orcamento:  8 funcoes novas, 1.660 palavras (6.640 bytes)           " -ForegroundColor Yellow
Write-Host "  Meta:       1.139 funcoes nativas, 129.977 palavras (66,4558%)      " -ForegroundColor Yellow
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

EXPECTED_FUNCS = 1139
EXPECTED_WORDS = 129977

if len(funcs) != EXPECTED_FUNCS:
    print(f"ERRO: Contagem de funcoes divergente! Esperado {EXPECTED_FUNCS}, obtido {len(funcs)}", file=sys.stderr)
    sys.exit(1)

if total_words != EXPECTED_WORDS:
    print(f"ERRO: Contagem de palavras divergente! Esperado {EXPECTED_WORDS}, obtido {total_words}", file=sys.stderr)
    sys.exit(1)

expected_cluster = {
    0x8011721C: 8,
    0x801338B8: 1348,
    0x80133DFC: 1064,
    0x80134224: 1880,
    0x8013FF34: 152,
    0x8013FFCC: 552,
    0x801401F4: 1448,
    0x8014079C: 188,
}

for addr, expected_sz in expected_cluster.items():
    if addr not in funcs:
        print(f"ERRO: Funcao 0x{addr:08X} nao encontrada no manifest de funcoes!", file=sys.stderr)
        sys.exit(1)
    sz = next((s for lo, s in ranges if lo == addr), None)
    if sz != expected_sz:
        print(f"ERRO: Tamanho do range de 0x{addr:08X} divergente! Esperado {expected_sz} bytes, obtido {sz}", file=sys.stderr)
        sys.exit(1)

print(f"[OK] Manifest validado com sucesso: {len(funcs)} funcoes, {total_words} palavras (66.4558% de cobertura estatica).")
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
    Write-Host "[+] MICRO-LOTE S1-273 GERADO E AUDITADO COM SUCESSO!" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
