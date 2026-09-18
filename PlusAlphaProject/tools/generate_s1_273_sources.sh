#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly GAME_ROOT="$PROJECT_ROOT"
readonly CONFIG_PATH="$GAME_ROOT/game.toml"
readonly RECOMPILER="${RECOMPILER_PATH:-$GAME_ROOT/../psxrecomp/recompiler/build/psxrecomp-game.exe}"
readonly AUDIT_SCRIPT="$GAME_ROOT/../psxrecomp/tools/codegen_audit_game.py"
readonly RANGES_FILE="$GAME_ROOT/generated/SLUS_005.48_full.ranges"

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

validate_env() {
    [[ -f "$RECOMPILER" ]] || fail "psxrecomp-game nao encontrado em: $RECOMPILER"
    [[ -f "$CONFIG_PATH" ]] || fail "game.toml nao encontrado em: $CONFIG_PATH"
    [[ -f "$AUDIT_SCRIPT" ]] || fail "Script de auditoria ausente: $AUDIT_SCRIPT"

    if command -v python >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3)"
    else
        fail "Python nao encontrado no PATH."
    fi
}

validate_env

printf '======================================================================\n'
printf '        GERACAO DE FONTES - MICRO-LOTE S1-273                         \n'
printf '  Clusters: A (NOP Handler), B (Special/Effects), C (Render/Model)    \n'
printf '  Orcamento: 8 funcoes novas, 1.660 palavras (6.640 bytes)            \n'
printf '  Meta: 1.139 funcoes nativas, 129.977 palavras (66,4558%%)           \n'
printf '======================================================================\n'

cd "$GAME_ROOT"
printf '[1/3] Executando psxrecomp-game...\n'
"$RECOMPILER" --config "$CONFIG_PATH"

printf '[2/3] Validando manifest de ranges gerado...\n'
"$PYTHON_BIN" - <<'EOF'
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
EOF

printf '[3/3] Executando auditoria formal do codigo C gerado (codegen audit)...\n'
"$PYTHON_BIN" "$AUDIT_SCRIPT" --config "$CONFIG_PATH"

printf '\n[+] MICRO-LOTE S1-273 GERADO E AUDITADO COM SUCESSO!\n'
