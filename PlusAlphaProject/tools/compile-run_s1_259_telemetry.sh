#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-259-tele"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_SHA=C0E7A0A37DB76E98E731D4E9CA5A0882DE02802E8CDADA5805E07C83DE15999F

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
require_range() { grep -q "^${1}$" "$RANGES_FILE" || fail "Range/funcao ausente: $1"; }
require_symbol() {
    nm -C "$EXE" | grep -E "[[:space:]]T[[:space:]]+${1}$" >/dev/null ||
        fail "O executavel nao contem o simbolo $1."
}

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/compile-run_s1_259_telemetry.sh

Configura e compila somente a build isolada S1-259 de telemetria. Nao abre o
jogo e nao executa prepare, before ou after.
EOF
}

validate_environment() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    for tool in cmake ninja objdump nm nproc sha256sum; do
        command -v "$tool" >/dev/null || fail "$tool nao encontrado no UCRT64."
    done
    [[ -f "$RANGES_FILE" ]] || fail "Fontes S1-259 ausentes. Execute primeiro generate_s1_259_sources.ps1 no PowerShell."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_SHA" ]] ||
        fail "SHA-256 do manifesto nao corresponde ao S1-259 aprovado."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1058 ]] ||
        fail "A quantidade de funcoes nao corresponde ao S1-259 esperado (1058)."
    require_range 'F 801939A0'; require_range 'R 801939A0 78'
    require_range 'F 8017566C'; require_range 'R 8017566C 25C'
    require_range 'F 8019FC6C'; require_range 'R 8019FC6C 78'
    ! grep -Eq '^F (80103384|801912D8|801932AC|801932BC|8019E6D0)$' "$RANGES_FILE" ||
        fail "Uma funcao proibida apareceu nos fontes S1-259."
}

configure_and_build() {
    printf '\n==> Configurando S1-259 com telemetria e runtime estatico\n'
    cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DPSX_DEBUG_TOOLS=ON \
        -DPSX_STATIC_RUNTIME=ON
    printf '\n==> Compilando S1-259 de telemetria\n'
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
}

audit_runtime() {
    [[ -f "$EXE" ]] || fail "Executavel nao foi produzido: $EXE"
    local imports
    imports="$(objdump -p "$EXE" | awk '/DLL Name:/ { print $3 }')"
    ! printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$' ||
        fail "A build importa uma DLL que deveria estar estatica."
    require_symbol func_801939A0
    require_symbol func_8017566C
    require_symbol func_8019FC6C
    ! nm -C "$EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_(80103384|801912D8|801932AC|801932BC|8019E6D0)$' ||
        fail "O executavel contem uma funcao proibida no S1-259."
    printf '\n==> Runtime S1-259 validado; 0x801939A0 e 30 palavras presentes\n%s\n\nExecutavel: %s\nEste script nao abrira o jogo.\n' \
        "$imports" "$EXE"
}

main() {
    case "${1:-}" in
        '') ;;
        -h|--help) usage; return ;;
        *) usage; fail "Argumento desconhecido: $1" ;;
    esac
    validate_environment
    configure_and_build
    audit_runtime
}

main "$@"
