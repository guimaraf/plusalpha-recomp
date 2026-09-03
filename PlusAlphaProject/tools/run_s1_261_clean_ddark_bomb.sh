#!/usr/bin/env bash
# Valida e abre a build limpa sem gravar log e sem telemetria.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-261-clean-ddark-bomb"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly CONFIG="$PROJECT_ROOT/game_s1_261_clean_ddark_bomb.toml"
readonly MANIFEST="$BUILD_DIR/s1-261-clean-ddark-bomb-manifest.json"

PYTHON_BIN=
fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    select_python
    for file in "$EXE" "$CONFIG" "$MANIFEST"; do [[ -f "$file" ]] || fail "Arquivo ausente: $file"; done
    "$PYTHON_BIN" - "$BUILD_DIR" "$EXE" "$CONFIG" "$MANIFEST" <<'PY'
import hashlib,json,pathlib,socket,sys
root,exe,config,manifest=map(pathlib.Path,sys.argv[1:]); data=json.loads(manifest.read_text(encoding='utf-8'))
if data.get('track')!='S1-261-CLEAN-DDARK-BOMB': raise SystemExit('manifesto da build limpa divergente')
if data.get('configuration')!='Release; PSX_DEBUG_TOOLS=OFF; PSX_STATIC_RUNTIME=ON; no runtime log':
    raise SystemExit('configuracao limpa divergente')
if hashlib.sha256(exe.read_bytes()).hexdigest().upper()!=data['exe_sha256']: raise SystemExit('executavel alterado')
if hashlib.sha256(config.read_bytes()).hexdigest().upper()!=data['config_sha256']: raise SystemExit('configuracao alterada')
if (int(data.get('cache_dll_count',0)),int(data.get('cache_unique_entries',0)),int(data.get('ddark_image_words',0)))!=(50,126,2074):
    raise SystemExit('cache aprovado divergente')
if len(data.get('files',[]))!=100: raise SystemExit('inventario de cache incompleto')
for row in data['files']:
    path=root/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(row['size']): raise SystemExit(f'cache ausente: {row["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=row['sha256']: raise SystemExit(f'cache alterado: {row["path"]}')
with socket.socket() as sock:
    sock.settimeout(0.25)
    if sock.connect_ex(('127.0.0.1',4531))==0: raise SystemExit('feche a instancia instrumentada que usa a porta 4531')
print('Build limpa D.Dark bomb validada: Release, sem TCP, sem telemetria e sem log.')
PY
}

main() {
    case "${1:-}" in -h|--help) printf 'Uso: bash tools/run_s1_261_clean_ddark_bomb.sh\n'; return ;; '') ;; *) fail "Argumento desconhecido." ;; esac
    validate
    printf '\n==> Abrindo buildClean-ucrt-s1-261-clean-ddark-bomb\n'
    # Nenhum arquivo de log e nenhuma analise em segundo plano.
    "$EXE" --game "$CONFIG" >/dev/null 2>&1 &
    printf 'Jogo iniciado (PID MSYS: %s). Saida descartada; telemetria TCP desabilitada.\n' "$!"
}

main "$@"
