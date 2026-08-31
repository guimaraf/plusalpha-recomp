#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-001a-current-runtime.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_CAPTURE_KEY=0x00020000:0xAC1FF1A4

PYTHON_BIN=
RUNTIME_DIR=
RUNTIME_EXE=
TEST_CONFIG=
CACHE_MANIFEST=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com nenhuma outra instancia do jogo aberta:

  bash tools/run_ovl_001a_test.sh

O script valida e abre o runtime OVL-001A mais recente. Nao compila, nao gera
fontes e nao executa automaticamente prepare, before ou after.
EOF
}

state_value() {
    local file="$1" key="$2"
    awk -F= -v wanted="$key" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$file"
}

select_python() {
    if command -v python >/dev/null; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao foi encontrado no UCRT64."
    fi
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep; do
        command -v "$tool" >/dev/null || fail "$tool nao encontrado no UCRT64."
    done
    select_python
    [[ -f "$RUNTIME_STATE" ]] ||
        fail "Runtime OVL-001A ausente. Execute primeiro compile_ovl_001a_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"
    RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    TEST_CONFIG="$(state_value "$RUNTIME_STATE" test_config)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    local capture_key
    capture_key="$(state_value "$RUNTIME_STATE" capture_key)"
    case "$RUNTIME_DIR" in
        "$PROJECT_ROOT"/local/overlay/ovl-001a-test-runtime-*) ;;
        *) fail "Diretorio do runtime OVL-001A e invalido." ;;
    esac
    [[ "$capture_key" == "$EXPECTED_CAPTURE_KEY" ]] ||
        fail "O runtime atual nao pertence a captura AC1FF1A4."
    for file in "$RUNTIME_EXE" "$TEST_CONFIG" "$CACHE_MANIFEST"; do
        [[ -f "$file" ]] || fail "Arquivo do runtime ausente: $file"
    done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] ||
        fail "Executavel OVL-001A diverge da build validada."
    grep -Eq '^[[:space:]]*overlay_cache[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$TEST_CONFIG" ||
        fail "A configuracao nao habilita overlay_cache."
    ! grep -Eq '^[[:space:]]*overlay_autocompile_cmd(_tcc)?[[:space:]]*=' "$TEST_CONFIG" ||
        fail "A configuracao OVL-001A nao pode conter autocompilacao."
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" <<'PY'
import hashlib,json,pathlib,socket,sys
root=pathlib.Path(sys.argv[1]); manifest_path=pathlib.Path(sys.argv[2])
data=json.loads(manifest_path.read_text(encoding='utf-8'))
if data.get('track')!='OVL-001A' or data.get('capture_key')!='0x00020000:0xAC1FF1A4':
    raise SystemExit('manifesto de cache nao pertence a OVL-001A')
expected={row['path']:(row['sha256'],int(row['size'])) for row in data.get('files',[])}
actual={}
for rel in expected:
    path=root/pathlib.Path(*pathlib.PurePosixPath(rel).parts)
    if not path.is_file(): raise SystemExit(f'arquivo de cache ausente: {rel}')
    actual[rel]=(hashlib.sha256(path.read_bytes()).hexdigest().upper(),path.stat().st_size)
if not expected or actual!=expected:
    raise SystemExit('hash ou tamanho do cache OVL-001A mudou')
with socket.socket() as sock:
    sock.settimeout(0.25)
    if sock.connect_ex(('127.0.0.1',4531))==0:
        raise SystemExit('a porta 4531 ja esta em uso; feche a outra instancia do jogo')
print(f'Runtime validado: {data.get("dll_count",0)} DLL(s), '
      f'{data.get("unique_entries",0)} entradas, captura AC1FF1A4.')
PY
}

launch() {
    local runtime_log="$RUNTIME_DIR/ovl-001a-runtime.log"
    printf '\n==> Abrindo o runtime OVL-001A\n'
    "$RUNTIME_EXE" --game "$TEST_CONFIG" >"$runtime_log" 2>&1 &
    local game_pid=$!
    printf 'Jogo iniciado em segundo plano (PID MSYS: %s).\n' "$game_pid"
    printf 'Log do runtime: %s\n\n' "$runtime_log"
    printf 'Quando chegar ao Mode Select, execute:\n'
    printf '  bash tools/telemetry_before_after_ovl_001a.sh prepare\n'
}

main() {
    case "${1:-}" in
        '') ;;
        -h|--help) usage; return ;;
        *) usage; fail "Argumento desconhecido: $1" ;;
    esac
    validate
    launch
}

main "$@"
