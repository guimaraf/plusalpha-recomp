#!/usr/bin/env bash
# Valida e abre a build limpa S1-261 + cache cumulativo OVL-001A+B.
# Nao compila, nao gera fontes e nao coleta telemetria.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-261-clean-test"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly GAME_CONFIG="$PROJECT_ROOT/game_s1_261_clean_test.toml"
readonly MANIFEST="$BUILD_DIR/s1-261-clean-test-manifest.json"

PYTHON_BIN=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, sem outra instancia do jogo aberta:

  bash tools/run_s1_261_clean_test.sh

Valida e abre buildClean-ucrt-s1-261-clean-test. Nao compila e nao coleta.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    select_python
    for file in "$EXE" "$GAME_CONFIG" "$MANIFEST"; do [[ -f "$file" ]] || fail "Arquivo ausente: $file"; done
    "$PYTHON_BIN" - "$BUILD_DIR" "$EXE" "$GAME_CONFIG" "$MANIFEST" <<'PY'
import hashlib,json,pathlib,sys
root,exe,config,manifest=map(pathlib.Path,sys.argv[1:])
data=json.loads(manifest.read_text(encoding='utf-8'))
if data.get('track')!='S1-261-CLEAN-TEST-OVL-001AB': raise SystemExit('manifesto nao pertence a build limpa esperada')
checks=((exe,'exe_sha256'),(config,'game_config_sha256'))
for path,key in checks:
    actual=hashlib.sha256(path.read_bytes()).hexdigest().upper()
    if actual!=data.get(key): raise SystemExit(f'{key} divergente: {actual}')
if data.get('configuration')!='Release; PSX_DEBUG_TOOLS=OFF; PSX_STATIC_RUNTIME=ON': raise SystemExit('configuracao de compilacao divergente')
if int(data.get('cache_dll_count',0))!=49 or int(data.get('cache_unique_entries',0))!=108: raise SystemExit('metricas do cache divergentes')
for row in data.get('files',[]):
    path=root/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(row['size']): raise SystemExit(f'cache ausente/divergente: {row["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=row['sha256']: raise SystemExit(f'hash divergente: {row["path"]}')
print('Build limpa validada: Release sem telemetria; 49 DLLs e 108 entradas de overlay.')
PY
}

launch() {
    local runtime_log="$BUILD_DIR/s1-261-clean-test-runtime.log"
    printf '\n==> Abrindo buildClean-ucrt-s1-261-clean-test\n'
    "$EXE" --game "$GAME_CONFIG" >"$runtime_log" 2>&1 &
    printf 'Jogo iniciado em segundo plano (PID MSYS: %s).\n' "$!"
    printf 'Log local: %s\n' "$runtime_log"
}

main() {
    case "${1:-}" in '') ;; -h|--help) usage; return ;; *) usage; fail "Argumento desconhecido: $1" ;; esac
    validate
    launch
}

main "$@"
