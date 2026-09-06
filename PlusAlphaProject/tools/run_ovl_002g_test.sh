#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002g-current-runtime.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E

PYTHON_BIN=
RUNTIME_DIR=
RUNTIME_EXE=
TEST_CONFIG=
CACHE_MANIFEST=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

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
        partial="$(find "$PROJECT_ROOT/local/overlay" -maxdepth 1 -type d -name 'ovl-002g-test-runtime-*' 2>/dev/null | sort | tail -n 1 || true)"
        [[ -z "$partial" ]] || fail "Compilacao OVL-002G incompleta em $partial. Execute novamente compile_ovl_002g_test_runtime.sh."
        fail "Runtime OVL-002G ausente. Execute compile_ovl_002g_test_runtime.sh."
    fi
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"; RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    TEST_CONFIG="$(state_value "$RUNTIME_STATE" test_config)"; CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002g-test-runtime-*) ;; *) fail "Runtime OVL-002G invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" capture_key)" == 0x00020000:0xF943B63B ]] || fail "Chave divergente."
    [[ "$(state_value "$RUNTIME_STATE" target)" == 0x80045E30 ]] || fail "Raiz divergente."
    [[ "$(state_value "$RUNTIME_STATE" alias_1)" == 0x80045E70 && "$(state_value "$RUNTIME_STATE" alias_9)" == 0x80046020 ]] || fail "Aliases divergentes."
    [[ "$(state_value "$RUNTIME_STATE" incremental_words)" == 129 && "$(state_value "$RUNTIME_STATE" image_body_words)" == 2563 ]] || fail "Volume divergente."
    for file in "$RUNTIME_EXE" "$TEST_CONFIG" "$CACHE_MANIFEST"; do [[ -f "$file" ]] || fail "Arquivo ausente: $file"; done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel divergiu."
    grep -Eq '^[[:space:]]*overlay_cache[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$TEST_CONFIG" || fail "overlay_cache desabilitado."
    ! grep -Eq '^[[:space:]]*overlay_autocompile_cmd(_tcc)?[[:space:]]*=' "$TEST_CONFIG" || fail "Autocompilacao nao permitida."
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" <<'PY'
import hashlib,json,pathlib,socket,sys
root=pathlib.Path(sys.argv[1]); data=json.loads(pathlib.Path(sys.argv[2]).read_text(encoding='utf-8'))
if data.get('track')!='OVL-002G-DDARK-BOMB-HANDLER-CUMULATIVE' or int(data.get('image_body_words',0))!=2563:
    raise SystemExit('manifesto nao pertence a OVL-002G')
for item in data.get('files',[]):
    path=root/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']): raise SystemExit(f'cache ausente: {item["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']: raise SystemExit(f'cache alterado: {item["path"]}')
with socket.socket() as sock:
    sock.settimeout(0.25)
    if sock.connect_ex(('127.0.0.1',4534))==0: raise SystemExit('porta 4534 em uso; feche a outra instancia')
print(f'Runtime OVL-002G validado: {data.get("dll_count",0)} DLL(s), {data.get("unique_entries",0)} entradas.')
PY
}

main() {
    case "${1:-}" in '') ;; -h|--help) printf 'Uso: bash tools/run_ovl_002g_test.sh\n'; return ;; *) fail "Argumento desconhecido." ;; esac
    validate
    local log="$RUNTIME_DIR/ovl-002g-runtime.log"
    printf '\n==> Abrindo o runtime experimental OVL-002G\n'
    "$RUNTIME_EXE" --game "$TEST_CONFIG" >"$log" 2>&1 &
    printf 'Jogo iniciado em segundo plano (PID MSYS: %s).\nLog: %s\n' "$!" "$log"
    printf '\nNo Mode Select, execute:\n  bash tools/telemetry_before_after_ovl_002g.sh prepare\n'
}

main "$@"
