#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002b-current-runtime.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_CAPTURE_KEY=0x00020000:0xF943B63B

PYTHON_BIN=
RUNTIME_DIR=
RUNTIME_EXE=
TEST_CONFIG=
CACHE_MANIFEST=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, sem outra instancia do jogo aberta:

  bash tools/run_ovl_002b_test.sh

Valida e abre o runtime cumulativo OVL-002B. Este script nao compila.
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
    for tool in sha256sum awk grep find sort tail; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python
    if [[ ! -f "$RUNTIME_STATE" ]]; then
        local partial
        partial="$(find "$PROJECT_ROOT/local/overlay" -maxdepth 1 -type d -name 'ovl-002b-test-runtime-*' 2>/dev/null | sort | tail -n 1 || true)"
        if [[ -n "$partial" ]]; then
            fail "Compilacao OVL-002B anterior ficou incompleta em $partial. Execute novamente compile_ovl_002b_test_runtime.sh; o script criara um novo runtime isolado."
        fi
        fail "Runtime OVL-002B ainda nao compilado. Execute compile_ovl_002b_test_runtime.sh."
    fi
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"
    RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    TEST_CONFIG="$(state_value "$RUNTIME_STATE" test_config)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002b-test-runtime-*) ;; *) fail "Runtime OVL-002B invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" capture_key)" == "$EXPECTED_CAPTURE_KEY" ]] || fail "Chave OVL-002B divergente."
    [[ "$(state_value "$RUNTIME_STATE" target)" == 0x80092C2C ]] || fail "Alvo OVL-002B divergente."
    [[ "$(state_value "$RUNTIME_STATE" prior_alias)" == 0x80093E4C ]] || fail "Alias preservado divergente."
    [[ "$(state_value "$RUNTIME_STATE" incremental_words)" == 882 ]] || fail "Volume incremental divergente."
    [[ "$(state_value "$RUNTIME_STATE" image_body_words)" == 1108 ]] || fail "Volume cumulativo divergente."
    for file in "$RUNTIME_EXE" "$TEST_CONFIG" "$CACHE_MANIFEST"; do [[ -f "$file" ]] || fail "Arquivo ausente: $file"; done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel divergiu."
    grep -Eq '^[[:space:]]*overlay_cache[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$TEST_CONFIG" || fail "overlay_cache desabilitado."
    ! grep -Eq '^[[:space:]]*overlay_autocompile_cmd(_tcc)?[[:space:]]*=' "$TEST_CONFIG" || fail "Autocompilacao nao permitida."
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" <<'PY'
import hashlib,json,pathlib,socket,sys
root=pathlib.Path(sys.argv[1]); manifest=pathlib.Path(sys.argv[2]); data=json.loads(manifest.read_text(encoding='utf-8'))
if data.get('track')!='OVL-002B-DDARK-CUMULATIVE': raise SystemExit('manifesto nao pertence a OVL-002B')
if data.get('capture_keys')!=['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F','0x00020000:0xF943B63B']:
    raise SystemExit('chaves cumulativas divergiram')
if int(data.get('incremental_words',0))!=882 or int(data.get('prior_ovl002a_words',0))!=226 or int(data.get('image_body_words',0))!=1108:
    raise SystemExit('volumes OVL-002B divergiram')
for item in data.get('files',[]):
    path=root/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']): raise SystemExit(f'cache ausente: {item["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']: raise SystemExit(f'cache alterado: {item["path"]}')
with socket.socket() as sock:
    sock.settimeout(0.25)
    if sock.connect_ex(('127.0.0.1',4531))==0: raise SystemExit('porta 4531 em uso; feche a outra instancia')
print(f'Runtime OVL-002B validado: {data.get("dll_count",0)} DLL(s), {data.get("unique_entries",0)} entradas.')
PY
}

launch() {
    local runtime_log="$RUNTIME_DIR/ovl-002b-runtime.log"
    printf '\n==> Abrindo o runtime cumulativo OVL-002B\n'
    "$RUNTIME_EXE" --game "$TEST_CONFIG" >"$runtime_log" 2>&1 &
    printf 'Jogo iniciado em segundo plano (PID MSYS: %s).\n' "$!"
    printf 'Log: %s\n\n' "$runtime_log"
    printf 'No Mode Select, execute:\n  bash tools/telemetry_before_after_ovl_002b.sh prepare\n'
}

main() {
    case "${1:-}" in '') ;; -h|--help) usage; return ;; *) usage; fail "Argumento desconhecido: $1" ;; esac
    validate
    launch
}

main "$@"
