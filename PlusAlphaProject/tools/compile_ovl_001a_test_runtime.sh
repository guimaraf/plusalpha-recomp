#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly SOURCE_BUILD="$PROJECT_ROOT/buildClean-ucrt-s1-260-tele"
readonly SOURCE_EXE="$SOURCE_BUILD/StreetFighterEXPlusAlphaRecomp.exe"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_001a_test.toml"
readonly TARGET_FILE="$PROJECT_ROOT/seeds/ovl_001a_target_pcs.txt"
readonly CAPTURE_FILE="$PROJECT_ROOT/local/telemetry/ovl-001-capture-04/before_overlay_captures.json"
readonly COMPILE_OVERLAYS="$REPO_ROOT/psxrecomp/tools/compile_overlays.py"
readonly RECOMPILER="$REPO_ROOT/psxrecomp/recompiler/build/psxrecomp-game.exe"
readonly RUNTIME_INCLUDE="$REPO_ROOT/psxrecomp/runtime/include"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly GCC_BIN=/ucrt64/bin/gcc.exe
readonly RUNTIME_PARENT="$PROJECT_ROOT/local/overlay"
readonly RUNTIME_STATE="$RUNTIME_PARENT/.ovl-001a-current-runtime.state"
readonly TELEMETRY_STATE="$PROJECT_ROOT/local/telemetry/.ovl-001a-test-active.state"
readonly CAPTURE_KEY=0x00020000:0xAC1FF1A4
readonly EXPECTED_CAPTURE_SHA=4887205263E55EA4272D04809906237DD0C80D3DD9DD8F0167557CFDC3102379
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_RECOMPILER_SHA=3FA9DBAA2312F833C221BBA3BF17099BBD856754D440255E18DB6DD4A3F6D091
readonly EXPECTED_CODEGEN_HASH=562d908f
readonly EXPECTED_CACHE_REL=cache/SLUS-00548/gcc/win-x64/cg5_562d908f

PYTHON_BIN=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com o jogo fechado:

  bash tools/compile_ovl_001a_test_runtime.sh

O script cria um runtime isolado e compila somente o shard GCC da captura
0x00020000:0xAC1FF1A4. Ele nao recompila o executavel principal, nao gera fontes
S1 e nao altera BIOS, seeds principais ou generated/.
EOF
}

select_python() {
    if command -v python >/dev/null; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao foi encontrado no UCRT64."
    fi
}

validate_inputs() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep cp mkdir seq tee find sort env; do
        command -v "$tool" >/dev/null || fail "$tool nao encontrado no UCRT64."
    done
    select_python
    [[ ! -f "$TELEMETRY_STATE" ]] ||
        fail "Existe uma coleta OVL-001A ativa; conclua ou preserve a sessao antes de recompilar."
    for file in "$SOURCE_EXE" "$TEST_CONFIG" "$TARGET_FILE" "$CAPTURE_FILE" \
                "$COMPILE_OVERLAYS" "$RECOMPILER" "$RANGES_FILE" "$GCC_BIN"; do
        [[ -f "$file" ]] || fail "Arquivo obrigatorio ausente: $file"
    done
    [[ "$(sha256sum "$SOURCE_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] ||
        fail "Executavel-base diverge da build S1-261/S1-260-tele validada."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] ||
        fail "Ranges do EXE principal divergem do checkpoint S1-261."
    [[ "$(sha256sum "$CAPTURE_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_CAPTURE_SHA" ]] ||
        fail "Captura privada OVL-001A diverge do artefato aprovado."
    [[ "$(sha256sum "$RECOMPILER" | awk '{print toupper($1)}')" == "$EXPECTED_RECOMPILER_SHA" ]] ||
        fail "Recompilador diverge do binario pre-auditado."
    grep -Eq '^[[:space:]]*overlay_cache[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$TEST_CONFIG" ||
        fail "A config OVL-001A nao habilita overlay_cache."
    ! grep -Eq '^[[:space:]]*overlay_autocompile_cmd(_tcc)?[[:space:]]*=' "$TEST_CONFIG" ||
        fail "A config OVL-001A nao pode conter autocompilacao."
    "$PYTHON_BIN" - "$CAPTURE_FILE" "$TARGET_FILE" <<'PY'
import base64,binascii,json,pathlib,sys
capture_path,target_path=map(pathlib.Path,sys.argv[1:])
rows=json.loads(capture_path.read_text(encoding='utf-8'))
selected=[]
for row in rows:
    raw=base64.b64decode(row['bytes_b64'])
    phys=int(row['load_addr'],16)&0x1fffffff
    crc=binascii.crc32(raw)&0xffffffff
    if phys==0x00020000 and crc==0xAC1FF1A4:
        selected.append(row)
if len(selected)!=1:
    raise SystemExit(f'captura exata AC1FF1A4 aparece {len(selected)} vez(es), esperado 1')
row=selected[0]
if int(row['size'])!=860160:
    raise SystemExit('tamanho da captura OVL-001A divergente')
observed={int(x,16)&0x1fffffff for k in ('executed_pcs','dispatch_entry_pcs')
          for x in row.get(k,[])}
targets=[]
for line in target_path.read_text(encoding='utf-8').splitlines():
    parts=line.split('#',1)[0].split()
    if parts: targets.append(int(parts[1],16)&0x1fffffff)
expected={0x0004A44C,0x00091878,0x0004922C,0x00049500}
if set(targets)!=expected or len(targets)!=4:
    raise SystemExit('watchlist OVL-001A divergente')
missing=expected-observed
if missing:
    raise SystemExit('targets ausentes da captura: '+', '.join(f'0x{x|0x80000000:08X}' for x in sorted(missing)))
print('Captura OVL-001A validada: chave, tamanho e 4/4 targets corretos.')
PY
}

make_runtime_dir() {
    local suffix candidate
    mkdir -p "$RUNTIME_PARENT"
    for suffix in $(seq -w 1 99); do
        candidate="$RUNTIME_PARENT/ovl-001a-test-runtime-$suffix"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            printf '%s\n' "$candidate"
            return
        fi
    done
    fail "Nao ha runtime livre entre ovl-001a-test-runtime-01 e 99."
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

compile_shard() {
    local runtime_dir="$1" log="$runtime_dir/ovl-001a-compile.log"
    printf '\n==> Compilando somente OVL-001A (%s)\n' "$CAPTURE_KEY"
    env -u PSX_OVERLAY_CACHE_DIR -u PSX_OVERLAY_CAPTURES \
        "$PYTHON_BIN" "$COMPILE_OVERLAYS" \
        --captures "$CAPTURE_FILE" \
        --capture-key "$CAPTURE_KEY" \
        --game-toml "$TEST_CONFIG" \
        --recompiler "$RECOMPILER" \
        --runtime-include "$RUNTIME_INCLUDE" \
        --out-dir "$runtime_dir/cache" \
        --gcc "$GCC_BIN" \
        --compiler gcc \
        --cps \
        --jobs 1 2>&1 | tee "$log"
}

audit_cache() {
    local runtime_dir="$1"
    "$PYTHON_BIN" - "$runtime_dir" "$TARGET_FILE" "$CAPTURE_KEY" "$EXPECTED_CACHE_REL" <<'PY'
import hashlib,json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); targets_path=pathlib.Path(sys.argv[2])
capture_key=sys.argv[3]; expected_rel=pathlib.PurePosixPath(sys.argv[4])
cache_dir=root/pathlib.Path(*expected_rel.parts)
log=(root/'ovl-001a-compile.log').read_text(encoding='utf-8',errors='replace')
if f'({capture_key})' not in log or 'Capture filter: 1/' not in log:
    raise SystemExit('ERRO: log nao confirma o filtro exato de uma captura OVL-001A')
fatal=re.compile(r'(?:RECOMPILER ERROR|GENERATED-C AUDIT FAILED|RANGE AUDIT FAILED|\bFAILED\b)')
if fatal.search(log):
    raise SystemExit('ERRO: compilador reportou falha/audit failure; revise ovl-001a-compile.log')
base_dll=cache_dir/'00020000_AC1FF1A4.dll'
base_ranges=cache_dir/'00020000_AC1FF1A4.ranges'
if not base_dll.is_file() or not base_ranges.is_file():
    raise SystemExit('ERRO: shard principal AC1FF1A4 ou ranges ausente')
dlls=sorted(cache_dir.glob('*.dll')); manifests=sorted(cache_dir.glob('*.ranges'))
if not dlls or len(dlls)!=len(manifests):
    raise SystemExit(f'ERRO: inventario incompleto: dlls={len(dlls)}, ranges={len(manifests)}')
for dll in dlls:
    if not dll.with_suffix('.ranges').is_file():
        raise SystemExit(f'ERRO: {dll.name} nao possui .ranges correspondente')
for ranges in manifests:
    if not ranges.with_suffix('.dll').is_file():
        raise SystemExit(f'ERRO: {ranges.name} nao possui .dll correspondente')
entries=set(); f_lines=0
for ranges in manifests:
    for line in ranges.read_text(encoding='utf-8').splitlines():
        parts=line.split()
        if parts and parts[0]=='F':
            f_lines+=1; entries.add(int(parts[1],16)&0x1fffffff)
targets=[]
for line in targets_path.read_text(encoding='utf-8').splitlines():
    parts=line.split('#',1)[0].split()
    if parts: targets.append(int(parts[1],16)&0x1fffffff)
missing=sorted(set(targets)-entries)
if missing:
    raise SystemExit('ERRO: targets sem entrada nativa: '+', '.join(f'0x{x|0x80000000:08X}' for x in missing))
inventory=[]
for path in sorted(dlls+manifests,key=lambda p:p.as_posix()):
    rel=path.relative_to(root).as_posix()
    inventory.append({'path':rel,'sha256':hashlib.sha256(path.read_bytes()).hexdigest().upper(),
                      'size':path.stat().st_size})
(root/'ovl-001a-cache-manifest.json').write_text(json.dumps({
    'track':'OVL-001A','capture_key':capture_key,'cache_relative':expected_rel.as_posix(),
    'dll_count':len(dlls),'ranges_count':len(manifests),'manifest_f_lines':f_lines,
    'unique_entries':len(entries),'targets':[f'0x{x|0x80000000:08X}' for x in sorted(targets)],
    'files':inventory},indent=2,sort_keys=True)+'\n',encoding='utf-8')
print(f'Cache OVL-001A auditado: {len(dlls)} DLL(s), {len(entries)} entradas unicas, 4/4 targets.')
PY
}

write_state() {
    local runtime_dir="$1"
    umask 077
    {
        printf 'runtime_dir=%s\n' "$runtime_dir"
        printf 'runtime_exe=%s\n' "$runtime_dir/StreetFighterEXPlusAlphaRecomp.exe"
        printf 'test_config=%s\n' "$TEST_CONFIG"
        printf 'cache_manifest=%s\n' "$runtime_dir/ovl-001a-cache-manifest.json"
        printf 'capture_key=%s\n' "$CAPTURE_KEY"
        printf 'capture_sha256=%s\n' "$EXPECTED_CAPTURE_SHA"
        printf 'runtime_exe_sha256=%s\n' "$EXPECTED_EXE_SHA"
        printf 'ranges_sha256=%s\n' "$EXPECTED_RANGES_SHA"
        printf 'recompiler_sha256=%s\n' "$EXPECTED_RECOMPILER_SHA"
        printf 'codegen_hash=%s\n' "$EXPECTED_CODEGEN_HASH"
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
    validate_inputs
    runtime_dir="$(make_runtime_dir)"
    copy_runtime "$runtime_dir"
    compile_shard "$runtime_dir"
    audit_cache "$runtime_dir"
    write_state "$runtime_dir"
    printf '\nOVL-001A compilado e isolado. O executavel principal nao foi recompilado.\n'
    printf 'Abra o jogo com:\n\n'
    printf '  bash tools/run_ovl_001a_test.sh\n\n'
    printf 'Depois, ainda no Mode Select, execute:\n'
    printf '  bash tools/telemetry_before_after_ovl_001a.sh prepare\n'
}

main "$@"
