#!/usr/bin/env bash
# Checkpoint limpo cumulativo S1-261: Release sem telemetria.
# Incorpora a baseline S1-260. Este script nunca gera fontes nem abre o jogo.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-261"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly DISPATCH_FILE="$PROJECT_ROOT/generated/SLUS_005.48_dispatch.c"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly AUDIT_SCRIPT="$FRAMEWORK_ROOT/tools/codegen_audit_game.py"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_RANGES_SHA256=0b63b7672129c4a357100d5de97dab762910705faabc4580880c291ad14de69f
readonly EXPECTED_FUNCTIONS=1059
readonly EXPECTED_DISPATCH_ENTRIES=16667
readonly EXPECTED_MAIN_SHA256=1a932f2cf286930a967cf4ef03595b487480b84887f6630f5d3b57472401d8b0
readonly EXPECTED_CDROM_C_SHA256=2af1a59a2c18e0ebb47ec3fd614aaefeacd82fb0042440fbcd03652c18f4e845
readonly EXPECTED_CDROM_H_SHA256=75ccd4e0d03d6a407af55e6852cb9346b55233fb96b3a662dc0f15a8bf0b9186
readonly EXPECTED_DEBUG_SERVER_SHA256=40c2bd97e242ca6048227ba02e6af4327259bdb28f9c65969c2c72faea1f50d6
readonly EXPECTED_GITIGNORE_SHA256=12933e7f49a9c16a0c8bff015f99d56ba0202059c9b3b50bf0933d418f3e6218
readonly EXPECTED_BIOS_EMITTER_SHA256=b17ad5560a4a8c1a289c90f0a05babf17980fe3185eb05e13b4ce7c4a0d422ec

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
require_range() { grep -qxF "$1" "$RANGES_FILE" || fail "Range/funcao ausente: $1"; }
require_symbol() {
    nm -C "$EXE" | grep -Eq "[[:space:]]T[[:space:]]+$1$" ||
        fail "Simbolo emitido ausente no executavel: $1"
}
require_sha256() {
    local path="$1" expected="$2" actual
    [[ -f "$path" ]] || fail "Arquivo protegido ausente: $path"
    actual="$(sha256sum "$path" | awk '{print tolower($1)}')"
    [[ "$actual" == "$expected" ]] || fail "SHA-256 inesperado em $path: $actual"
}

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/compile-run_s1_261_checkpoint.sh

Compila o checkpoint limpo cumulativo S1-261 em Release, com
PSX_DEBUG_TOOLS=OFF e runtime estatico. O script nao gera fontes, nao regenera
a BIOS e nao abre ou fecha o jogo.
EOF
}

validate_sources() {
    [[ -f "$PROJECT_ROOT/CMakeLists.txt" ]] || fail "Raiz CMake invalida: $PROJECT_ROOT"
    [[ -f "$RANGES_FILE" && -f "$DISPATCH_FILE" ]] ||
        fail "Fontes S1-260 ausentes. Execute primeiro generate_s1_260_sources.ps1."
    [[ -f "$GAME_TOML" && -f "$AUDIT_SCRIPT" ]] || fail "Arquivos de auditoria ausentes."

    require_range 'F 8018F10C'; require_range 'R 8018F10C 1D60'
    require_range 'F 8016FC28'; require_range 'R 8016FC28 9C'
    require_range 'F 801910A4'; require_range 'R 801910A4 234'
    require_range 'F 801914C0'; require_range 'R 801914C0 C8'
    require_range 'F 80191C84'; require_range 'R 80191C84 4A4'
    require_range 'F 80192D6C'; require_range 'R 80192D6C EC'
    require_range 'F 801930BC'; require_range 'R 801930BC 90'
    require_range 'F 8019FC6C'; require_range 'R 8019FC6C 78'
    require_range 'F 8017566C'; require_range 'R 8017566C 25C'
    require_range 'F 801939A0'; require_range 'R 801939A0 78'
    require_range 'F 80103BD8'; require_range 'R 80103BD8 D0'

    ! grep -Eq '^F (80103384|8016EA0C|8016EA60|8016EAE8|8016F560|8016FB64|801912D8|801932AC|801932BC|8019E6D0)$' "$RANGES_FILE" ||
        fail "Uma funcao fora da closure aprovada apareceu nos fontes S1-261."

    local function_count ranges_hash dispatch_entries
    function_count="$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")"
    [[ "$function_count" == "$EXPECTED_FUNCTIONS" ]] ||
        fail "Esperadas $EXPECTED_FUNCTIONS funcoes; obtidas $function_count."
    ranges_hash="$(sha256sum "$RANGES_FILE" | awk '{print tolower($1)}')"
    [[ "$ranges_hash" == "$EXPECTED_RANGES_SHA256" ]] ||
        fail "Hash dos ranges S1-260 inesperado: $ranges_hash"
    dispatch_entries="$(awk '
        /^static const PsxGameDispatchEntry k_psx_game_dispatch\[\] = \{/ { inside=1; next }
        inside && /^};$/ { print count+0; exit }
        inside && /^[[:space:]]*\{/ { count++ }
    ' "$DISPATCH_FILE")"
    [[ "$dispatch_entries" == "$EXPECTED_DISPATCH_ENTRIES" ]] ||
        fail "Dispatcher deveria conter $EXPECTED_DISPATCH_ENTRIES entradas; obtidas $dispatch_entries."

    require_sha256 "$FRAMEWORK_ROOT/runtime/src/main.cpp" "$EXPECTED_MAIN_SHA256"
    require_sha256 "$FRAMEWORK_ROOT/runtime/src/cdrom.c" "$EXPECTED_CDROM_C_SHA256"
    require_sha256 "$FRAMEWORK_ROOT/runtime/include/cdrom.h" "$EXPECTED_CDROM_H_SHA256"
    require_sha256 "$FRAMEWORK_ROOT/runtime/src/debug_server.c" "$EXPECTED_DEBUG_SERVER_SHA256"
    require_sha256 "$REPO_ROOT/.gitignore" "$EXPECTED_GITIGNORE_SHA256"
    require_sha256 "$FRAMEWORK_ROOT/generated/SCPH1001.emitter.sha" "$EXPECTED_BIOS_EMITTER_SHA256"

    printf '\n==> Auditando fontes S1-260 para o checkpoint S1-261\n'
    python "$AUDIT_SCRIPT" --config "$GAME_TOML"
}

configure_and_build() {
    printf '\n==> Configurando checkpoint limpo S1-261 (Release, PSX_DEBUG_TOOLS=OFF)\n'
    cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DPSX_DEBUG_TOOLS=OFF \
        -DPSX_STATIC_RUNTIME=ON
    printf '\n==> Compilando checkpoint limpo S1-261\n'
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
}

audit_runtime() {
    [[ -f "$EXE" ]] || fail "Executavel nao foi produzido: $EXE"
    local cache imports exe_hash
    cache="$BUILD_DIR/CMakeCache.txt"
    [[ -f "$cache" ]] || fail "CMakeCache ausente: $cache"
    grep -qxF 'CMAKE_BUILD_TYPE:STRING=Release' "$cache" || fail "Checkpoint nao esta em Release."
    grep -qxF 'PSX_DEBUG_TOOLS:BOOL=OFF' "$cache" || fail "Checkpoint ainda possui telemetria."
    grep -qxF 'PSX_STATIC_RUNTIME:BOOL=ON' "$cache" || fail "Runtime estatico nao esta ativo."

    for symbol in \
        func_8018F10C func_8016FC28 func_801910A4 func_801914C0 \
        func_80191C84 func_80192D6C func_801930BC func_8019FC6C \
        func_8017566C func_801939A0 func_80103BD8; do
        require_symbol "$symbol"
    done
    ! nm -C "$EXE" | grep -Eq '[[:space:]]T[[:space:]]+func_(80103384|8016EA0C|8016EA60|8016EAE8|8016F560|8016FB64|801912D8|801932AC|801932BC|8019E6D0)$' ||
        fail "O executavel contem funcao fora da closure aprovada."

    imports="$(objdump -p "$EXE" | awk '/DLL Name:/ { print $3 }')"
    ! printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$' ||
        fail "O checkpoint importa DLL de runtime que deveria estar estatica."
    exe_hash="$(sha256sum "$EXE" | awk '{print toupper($1)}')"

    printf '\nCHECKPOINT RELEASE S1-261 PRONTO PARA SMOKE\n'
    printf '  Build:              %s\n' "$BUILD_DIR"
    printf '  Executavel:         %s\n' "$EXE"
    printf '  SHA-256 EXE:        %s\n' "$exe_hash"
    printf '  Configuracao:       Release, PSX_DEBUG_TOOLS=OFF, runtime estatico\n'
    printf '  Funcoes:            %s\n' "$EXPECTED_FUNCTIONS"
    printf '  Dispatcher entries: %s\n' "$EXPECTED_DISPATCH_ENTRIES"
    printf '  Cobertura:          111379/195584 palavras (56,9469%%)\n'
    printf '  Ranges SHA-256:     %s\n' "${EXPECTED_RANGES_SHA256^^}"
    printf '\nAbra o executavel manualmente para o smoke final.\n'
}

main() {
    case "${1:-}" in
        '') ;;
        -h|--help) usage; return ;;
        *) usage; fail "Argumento desconhecido: $1" ;;
    esac
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    for command_name in cmake ninja nm objdump nproc sha256sum python awk grep; do
        command -v "$command_name" >/dev/null 2>&1 || fail "Comando ausente no UCRT64: $command_name"
    done
    validate_sources
    configure_and_build
    audit_runtime
}

main "$@"
