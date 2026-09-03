#!/usr/bin/env bash
# Valida e abre a build limpa S1-261 + cache cumulativo OVL-002C.
# Nao compila, nao gera fontes e nao coleta telemetria.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-261-ovl-002c-clean-test"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly GAME_CONFIG="$PROJECT_ROOT/game_s1_261_clean_ovl_002c_test.toml"
readonly MANIFEST="$BUILD_DIR/s1-261-ovl-002c-clean-test-manifest.json"

PYTHON_BIN=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, sem outra instancia do jogo aberta:

  bash tools/run_s1_261_clean_ovl_002c_test.sh

Valida e abre a build limpa S1-261 + OVL-002C. Nao compila, nao abre
porta de telemetria e nao altera as sessoes de coleta existentes.
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
import hashlib,json,pathlib,socket,sys
root,exe,config,manifest=map(pathlib.Path,sys.argv[1:])
data=json.loads(manifest.read_text(encoding='utf-8'))
if data.get('track')!='S1-261-CLEAN-TEST-OVL-002C': raise SystemExit('manifesto nao pertence a build limpa OVL-002C')
for path,key in ((exe,'exe_sha256'),(config,'game_config_sha256')):
    actual=hashlib.sha256(path.read_bytes()).hexdigest().upper()
    if actual!=data.get(key): raise SystemExit(f'{key} divergente: {actual}')
if data.get('configuration')!='Release; PSX_DEBUG_TOOLS=OFF; PSX_STATIC_RUNTIME=ON':
    raise SystemExit('configuracao de compilacao divergente')
if int(data.get('cache_dll_count',0))!=50 or int(data.get('cache_unique_entries',0))!=126:
    raise SystemExit('metricas do cache OVL-002C divergentes')
if data.get('active_image_key')!='0x00020000:0xF943B63B' or int(data.get('active_image_words',0))!=2074:
    raise SystemExit('imagem D.Dark OVL-002C divergente')
if len(data.get('files',[]))!=100: raise SystemExit('inventario do cache incompleto')
for row in data['files']:
    path=root/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(row['size']): raise SystemExit(f'cache ausente/divergente: {row["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=row['sha256']: raise SystemExit(f'hash divergente: {row["path"]}')
with socket.socket() as sock:
    sock.settimeout(0.25)
    if sock.connect_ex(('127.0.0.1',4531))==0:
        raise SystemExit('porta 4531 em uso; feche o runtime de telemetria antes do teste limpo')
print('Build limpa validada: Release sem telemetria; 50 DLLs e 126 entradas OVL-002C.')
PY
}

launch() {
    local runtime_log="$BUILD_DIR/s1-261-ovl-002c-clean-test-runtime.log"
    printf '\n==> Abrindo buildClean-ucrt-s1-261-ovl-002c-clean-test\n'
    "$EXE" --game "$GAME_CONFIG" >"$runtime_log" 2>&1 &
    printf 'Jogo iniciado em segundo plano (PID MSYS: %s).\n' "$!"
    printf 'Log local: %s\n' "$runtime_log"
    printf 'Telemetria TCP: desabilitada. As sessoes OVL-002C existentes nao foram alteradas.\n'
}

main() {
    case "${1:-}" in '') ;; -h|--help) usage; return ;; *) usage; fail "Argumento desconhecido: $1" ;; esac
    validate
    launch
}

main "$@"
