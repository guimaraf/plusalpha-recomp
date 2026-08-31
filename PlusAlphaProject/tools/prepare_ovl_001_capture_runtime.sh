#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly SOURCE_BUILD="$PROJECT_ROOT/buildClean-ucrt-s1-260-tele"
readonly SOURCE_EXE="$SOURCE_BUILD/StreetFighterEXPlusAlphaRecomp.exe"
readonly CAPTURE_CONFIG="$PROJECT_ROOT/game_ovl_001_capture.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RUNTIME_PARENT="$PROJECT_ROOT/local/overlay"
readonly RUNTIME_STATE="$RUNTIME_PARENT/.ovl-001-current-runtime.state"
readonly TELEMETRY_STATE="$PROJECT_ROOT/local/telemetry/.ovl-001-capture-active.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com o jogo fechado:

  bash tools/prepare_ovl_001_capture_runtime.sh

O script nao compila nem abre o jogo. Ele cria uma copia isolada da build de
telemetria aprovada e mostra o comando exato para inicia-la.
EOF
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep cp mkdir seq; do
        command -v "$tool" >/dev/null || fail "$tool nao encontrado no UCRT64."
    done
    [[ ! -f "$TELEMETRY_STATE" ]] ||
        fail "Existe uma coleta OVL-001 ativa; conclua o AFTER antes de preparar outra."
    [[ -f "$SOURCE_EXE" && -f "$CAPTURE_CONFIG" && -f "$RANGES_FILE" ]] ||
        fail "Build de telemetria, config OVL-001 ou ranges ausentes."
    [[ "$(sha256sum "$SOURCE_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] ||
        fail "Executavel-base diverge da build S1-261/S1-260-tele validada."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] ||
        fail "Ranges divergem do checkpoint S1-261."
    grep -Eq '^[[:space:]]*overlay_cache[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$CAPTURE_CONFIG" ||
        fail "A config OVL-001 nao habilita captura de overlays."
    grep -Eq '^[[:space:]]*overlay_backend[[:space:]]*=[[:space:]]*"tcc"[[:space:]]*$' "$CAPTURE_CONFIG" ||
        fail "A config OVL-001 nao esta no backend de captura isolada."
    ! grep -Eq '^[[:space:]]*overlay_autocompile_cmd(_tcc)?[[:space:]]*=' "$CAPTURE_CONFIG" ||
        fail "A config OVL-001 nao pode conter autocompilacao."
}

make_runtime_dir() {
    local suffix candidate
    mkdir -p "$RUNTIME_PARENT"
    for suffix in $(seq -w 1 99); do
        candidate="$RUNTIME_PARENT/ovl-001-capture-runtime-$suffix"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            printf '%s\n' "$candidate"
            return
        fi
    done
    fail "Nao ha runtime livre entre ovl-001-capture-runtime-01 e 99."
}

copy_runtime() {
    local runtime_dir="$1" file
    cp "$SOURCE_EXE" "$runtime_dir/StreetFighterEXPlusAlphaRecomp.exe"
    for file in input.ini keybinds.ini settings.toml launcher.rml; do
        [[ -f "$SOURCE_BUILD/$file" ]] && cp "$SOURCE_BUILD/$file" "$runtime_dir/$file"
    done
    [[ "$(sha256sum "$runtime_dir/StreetFighterEXPlusAlphaRecomp.exe" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] ||
        fail "A copia isolada do executavel falhou no gate SHA-256."
    [[ ! -e "$runtime_dir/cache" && ! -e "$runtime_dir/overlay_captures.json" ]] ||
        fail "O novo runtime isolado nasceu com cache/captura preexistente."
}

write_state() {
    local runtime_dir="$1"
    umask 077
    {
        printf 'runtime_dir=%s\n' "$runtime_dir"
        printf 'runtime_exe=%s\n' "$runtime_dir/StreetFighterEXPlusAlphaRecomp.exe"
        printf 'capture_config=%s\n' "$CAPTURE_CONFIG"
        printf 'runtime_exe_sha256=%s\n' "$EXPECTED_EXE_SHA"
        printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$RUNTIME_STATE"
}

main() {
    local runtime_dir
    case "${1:-}" in
        '') ;;
        -h|--help) usage; return ;;
        *) usage; fail "Argumento desconhecido: $1" ;;
    esac
    validate
    runtime_dir="$(make_runtime_dir)"
    copy_runtime "$runtime_dir"
    write_state "$runtime_dir"
    printf '\nRuntime OVL-001 isolado e validado. Nenhum build foi iniciado.\n'
    printf 'Abra o jogo manualmente com este comando:\n\n'
    printf '  "%s" --game "%s"\n\n' \
        "$runtime_dir/StreetFighterEXPlusAlphaRecomp.exe" "$CAPTURE_CONFIG"
    printf 'Depois, no Mode Select, execute:\n'
    printf '  bash tools/telemetry_capture_ovl_001.sh prepare\n'
    printf 'Nao execute BEFORE no Mode Select. Entre em Ryu x Ken, aguarde o gameplay\n'
    printf 'ficar controlavel por 2 segundos e somente entao execute BEFORE.\n'
}

main "$@"
