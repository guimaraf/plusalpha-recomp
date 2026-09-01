#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly A_RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-001a-current-runtime.state"
readonly B_RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-001b-current-runtime.state"
readonly TELEMETRY_STATE="$PROJECT_ROOT/local/telemetry/.ovl-001b-test-active.state"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_001b_test.toml"
readonly A_TARGET_FILE="$PROJECT_ROOT/seeds/ovl_001a_target_pcs.txt"
readonly B_TARGET_FILE="$PROJECT_ROOT/seeds/ovl_001b_target_pcs.txt"
readonly A_CAPTURE_FILE="$PROJECT_ROOT/local/telemetry/ovl-001-capture-04/before_overlay_captures.json"
readonly B_CAPTURE_FILE="$PROJECT_ROOT/local/telemetry/ovl-001-capture-04/private-overlay-captures.json"
readonly COMPILE_OVERLAYS="$REPO_ROOT/psxrecomp/tools/compile_overlays.py"
readonly RECOMPILER="$REPO_ROOT/psxrecomp/recompiler/build/psxrecomp-game.exe"
readonly RUNTIME_INCLUDE="$REPO_ROOT/psxrecomp/runtime/include"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly GCC_BIN=/ucrt64/bin/gcc.exe
readonly RUNTIME_PARENT="$PROJECT_ROOT/local/overlay"
readonly A_CAPTURE_KEY=0x00020000:0xAC1FF1A4
readonly B_CAPTURE_KEY=0x00020000:0x94E6122F
readonly EXPECTED_A_CAPTURE_SHA=4887205263E55EA4272D04809906237DD0C80D3DD9DD8F0167557CFDC3102379
readonly EXPECTED_B_CAPTURE_SHA=9E53BBE4D6F22E53F963BDF1090829C36E3A7653B6A804817D154614A01E99B5
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_RECOMPILER_SHA=3FA9DBAA2312F833C221BBA3BF17099BBD856754D440255E18DB6DD4A3F6D091
readonly EXPECTED_CODEGEN_HASH=562d908f
readonly EXPECTED_CACHE_REL=cache/SLUS-00548/gcc/win-x64/cg5_562d908f

PYTHON_BIN=
A_RUNTIME_DIR=
A_RUNTIME_EXE=
A_CACHE_MANIFEST=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com o jogo fechado:

  bash tools/compile_ovl_001b_test_runtime.sh

O script valida e copia o cache OVL-001A ja aprovado, deriva o subconjunto
OVL-001B-safe sem a raiz que contem BREAK e compila somente esse subconjunto
no runtime isolado cumulativo. Nao recompila o executavel principal nem gera
fontes S1.
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

read_a_runtime() {
    [[ -f "$A_RUNTIME_STATE" ]] ||
        fail "Runtime OVL-001A aprovado ausente; execute o compilador OVL-001A primeiro."
    A_RUNTIME_DIR="$(state_value "$A_RUNTIME_STATE" runtime_dir)"
    A_RUNTIME_EXE="$(state_value "$A_RUNTIME_STATE" runtime_exe)"
    A_CACHE_MANIFEST="$(state_value "$A_RUNTIME_STATE" cache_manifest)"
    case "$A_RUNTIME_DIR" in
        "$PROJECT_ROOT"/local/overlay/ovl-001a-test-runtime-*) ;;
        *) fail "Estado OVL-001A aponta para runtime invalido." ;;
    esac
    [[ "$(state_value "$A_RUNTIME_STATE" capture_key)" == "$A_CAPTURE_KEY" ]] ||
        fail "Estado OVL-001A nao pertence a AC1FF1A4."
    for file in "$A_RUNTIME_EXE" "$A_CACHE_MANIFEST"; do
        [[ -f "$file" ]] || fail "Artefato OVL-001A ausente: $file"
    done
}

validate_inputs() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep cp mkdir seq tee find sort env; do
        command -v "$tool" >/dev/null || fail "$tool nao encontrado no UCRT64."
    done
    select_python
    [[ ! -f "$TELEMETRY_STATE" ]] ||
        fail "Existe uma coleta OVL-001B ativa; conclua-a antes de recompilar."
    read_a_runtime
    for file in "$TEST_CONFIG" "$A_TARGET_FILE" "$B_TARGET_FILE" \
                "$A_CAPTURE_FILE" "$B_CAPTURE_FILE" "$COMPILE_OVERLAYS" \
                "$RECOMPILER" "$RANGES_FILE" "$GCC_BIN"; do
        [[ -f "$file" ]] || fail "Arquivo obrigatorio ausente: $file"
    done
    [[ "$(sha256sum "$A_RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] ||
        fail "Executavel-base OVL-001A diverge da build validada."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] ||
        fail "Ranges do EXE principal divergem do checkpoint S1-261."
    [[ "$(sha256sum "$A_CAPTURE_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_A_CAPTURE_SHA" ]] ||
        fail "Captura privada OVL-001A diverge do artefato aprovado."
    [[ "$(sha256sum "$B_CAPTURE_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_B_CAPTURE_SHA" ]] ||
        fail "Captura privada OVL-001B diverge do artefato pre-auditado."
    [[ "$(sha256sum "$RECOMPILER" | awk '{print toupper($1)}')" == "$EXPECTED_RECOMPILER_SHA" ]] ||
        fail "Recompilador diverge do binario pre-auditado."
    grep -Eq '^[[:space:]]*overlay_cache[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$TEST_CONFIG" ||
        fail "A config OVL-001B nao habilita overlay_cache."
    ! grep -Eq '^[[:space:]]*overlay_autocompile_cmd(_tcc)?[[:space:]]*=' "$TEST_CONFIG" ||
        fail "A config OVL-001B nao pode conter autocompilacao."
    "$PYTHON_BIN" - "$A_RUNTIME_DIR" "$A_CACHE_MANIFEST" "$A_CAPTURE_FILE" \
        "$B_CAPTURE_FILE" "$TEST_CONFIG" "$COMPILE_OVERLAYS" "$B_TARGET_FILE" <<'PY'
import base64,binascii,copy,hashlib,importlib.util,json,pathlib,sys,tomllib
a_runtime=pathlib.Path(sys.argv[1]); a_manifest=pathlib.Path(sys.argv[2])
a_capture=pathlib.Path(sys.argv[3]); b_capture=pathlib.Path(sys.argv[4])
config=pathlib.Path(sys.argv[5]); compiler=pathlib.Path(sys.argv[6]); target_path=pathlib.Path(sys.argv[7])
manifest=json.loads(a_manifest.read_text(encoding='utf-8'))
if manifest.get('track')!='OVL-001A' or manifest.get('capture_key')!='0x00020000:0xAC1FF1A4':
    raise SystemExit('manifesto-base nao pertence a OVL-001A aprovada')
for row in manifest.get('files',[]):
    path=a_runtime/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(row['size']):
        raise SystemExit(f'cache A ausente/divergente: {row["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=row['sha256']:
        raise SystemExit(f'hash do cache A divergiu: {row["path"]}')
spec=importlib.util.spec_from_file_location('compile_overlays_preaudit',compiler)
co=importlib.util.module_from_spec(spec); spec.loader.exec_module(co)
toml_doc=tomllib.loads(config.read_text(encoding='utf-8'))
def select(path,want):
    found=[]
    for cap in json.loads(path.read_text(encoding='utf-8')):
        data=base64.b64decode(cap['bytes_b64']); load=int(cap['load_addr'],0)
        crc=binascii.crc32(data)&0xffffffff
        if (load&0x1fffffff)==0x20000 and crc==want: found.append((cap,data,load,crc))
    if len(found)!=1: raise SystemExit(f'captura {want:08X}: {len(found)} ocorrencias')
    cap,data,load,crc=found[0]
    _,audit=co.classify_overlay_seeds(cap,data,load,len(data),crc,toml_doc)
    roots=sorted(a for a,r in audit['included_reasons'].items() if r!='DISPATCH_INTERIOR')
    interiors={a for a,r in audit['included_reasons'].items() if r=='DISPATCH_INTERIOR'}
    visited=set()
    for i,entry in enumerate(roots):
        hard=roots[i+1] if i+1<len(roots) else load+len(data)
        visited |= co._walk_overlay_function(data,load,len(data),entry,hard)['visited']
    return cap,data,roots,interiors,visited
a=select(a_capture,0xAC1FF1A4); b=select(b_capture,0x94E6122F)
if (len(a[2]),len(a[3]),len(a[4]))!=(22,42,4563):
    raise SystemExit('metricas OVL-001A divergiram da baseline aprovada')
if (len(b[2]),len(b[3]),len(b[4]))!=(32,90,5313):
    raise SystemExit('metricas OVL-001B divergiram da pre-auditoria')
if len(b[4]-a[4])!=750 or a[4]-b[4]:
    raise SystemExit('delta incremental OVL-001B nao e exatamente 750 palavras')
changed=[]
for addr in b[4]:
    off=addr-0x80020000
    if a[1][off:off+4]!=b[1][off:off+4]: changed.append(addr)
if changed: raise SystemExit('bytes de codigo mudaram entre A e B')
safe_cap=copy.deepcopy(b[0])
blocked=set(range(0x8004B154,0x8004B35C,4))
safe_cap['dispatch_entry_pcs']=[x for x in safe_cap.get('dispatch_entry_pcs',[])
                                if int(x,16) not in blocked]
safe_cap['function_entry_pcs']=[f'0x{x:08X}' for x in (
    0x8004B35C,0x8004B528,0x8004B8C8,0x8004B934,
    0x8004B9E4,0x8004BA98,0x8004BB30)]
_,sa=co.classify_overlay_seeds(safe_cap,b[1],int(safe_cap['load_addr'],0),
                               len(b[1]),0x94E6122F,toml_doc)
sr=sorted(x for x,r in sa['included_reasons'].items() if r!='DISPATCH_INTERIOR')
si={x for x,r in sa['included_reasons'].items() if r=='DISPATCH_INTERIOR'}
sv=set(); breaks=[]
for i,entry in enumerate(sr):
    hard=sr[i+1] if i+1<len(sr) else int(safe_cap['load_addr'],0)+len(b[1])
    walk=co._walk_overlay_function(b[1],int(safe_cap['load_addr'],0),len(b[1]),entry,hard)
    sv |= walk['visited']
    for pc in walk['visited']:
        off=pc-int(safe_cap['load_addr'],0)
        word=int.from_bytes(b[1][off:off+4],'little')
        if (word>>26)==0 and (word&0x3f)==0x0D: breaks.append(pc)
if (len(sr),len(si),len(sv))!=(31,88,5183):
    raise SystemExit('metricas OVL-001B-safe divergiram de 31/88/5183')
if len(sv-a[4])!=620 or a[4]-sv:
    raise SystemExit('delta incremental OVL-001B-safe nao e exatamente 620 palavras')
if breaks: raise SystemExit('OVL-001B-safe ainda contem BREAK: '+', '.join(hex(x) for x in breaks))
if any(x in sa['function_entry_pcs'] for x in (0x8004B154,0x8004B310,0x8004B328)):
    raise SystemExit('raiz/aliases em quarentena ainda foram classificados')
targets=[]
for line in target_path.read_text(encoding='utf-8').splitlines():
    parts=line.split('#',1)[0].split()
    if parts: targets.append(int(parts[1],16))
expected_targets={0x80045440,0x80044664,0x8004590C,0x8004596C}
if len(targets)!=4 or set(targets)!=expected_targets:
    raise SystemExit('watchlist OVL-001B-safe diverge dos quatro gates aprovados')
if set(targets)-sa['function_entry_pcs'] or set(targets)-sa['dispatch_entry_pcs']:
    raise SystemExit('gate OVL-001B-safe nao e entrada compilavel/observada')
print('Pre-auditoria OVL-001B-safe: 5183 palavras totais; 620 incrementais; 130 em quarentena; zero BREAK.')
PY
}

make_runtime_dir() {
    local suffix candidate
    mkdir -p "$RUNTIME_PARENT"
    for suffix in $(seq -w 1 99); do
        candidate="$RUNTIME_PARENT/ovl-001b-test-runtime-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    done
    fail "Nao ha runtime livre entre ovl-001b-test-runtime-01 e 99."
}

copy_approved_a_runtime() {
    local runtime_dir="$1" file
    cp "$A_RUNTIME_EXE" "$runtime_dir/StreetFighterEXPlusAlphaRecomp.exe"
    for file in input.ini keybinds.ini settings.toml launcher.rml; do
        [[ -f "$A_RUNTIME_DIR/$file" ]] && cp "$A_RUNTIME_DIR/$file" "$runtime_dir/$file"
    done
    mkdir -p "$runtime_dir/cache"
    cp -R "$A_RUNTIME_DIR/cache/." "$runtime_dir/cache/"
    cp "$A_CACHE_MANIFEST" "$runtime_dir/ovl-001a-cache-source-manifest.json"
}

derive_safe_capture() {
    local runtime_dir="$1" output="$runtime_dir/ovl-001b-safe-capture.json"
    "$PYTHON_BIN" - "$B_CAPTURE_FILE" "$output" <<'PY'
import base64,binascii,copy,json,pathlib,sys
source=pathlib.Path(sys.argv[1]); output=pathlib.Path(sys.argv[2]); found=[]
for row in json.loads(source.read_text(encoding='utf-8')):
    data=base64.b64decode(row['bytes_b64'])
    if ((int(row['load_addr'],0)&0x1fffffff)==0x20000 and
            (binascii.crc32(data)&0xffffffff)==0x94E6122F):
        found.append(row)
if len(found)!=1: raise SystemExit(f'captura B exata aparece {len(found)} vez(es)')
row=copy.deepcopy(found[0]); blocked=set(range(0x8004B154,0x8004B35C,4))
before={int(x,16) for x in row.get('dispatch_entry_pcs',[])}
row['dispatch_entry_pcs']=[x for x in row.get('dispatch_entry_pcs',[])
                           if int(x,16) not in blocked]
removed=before-{int(x,16) for x in row['dispatch_entry_pcs']}
expected={0x8004B154,0x8004B310,0x8004B328}
if removed!=expected: raise SystemExit('conjunto removido diverge da quarentena aprovada')
row['function_entry_pcs']=[f'0x{x:08X}' for x in (
    0x8004B35C,0x8004B528,0x8004B8C8,0x8004B934,
    0x8004B9E4,0x8004BA98,0x8004BB30)]
row['safe_policy']='exclude 0x8004B154..0x8004B35B: psx_break unsupported by overlay ABI v12'
output.write_text(json.dumps([row],indent=2)+'\n',encoding='utf-8')
print(f'Captura derivada OVL-001B-safe: {len(row["dispatch_entry_pcs"])} dispatch entries; 3 entradas em quarentena.')
PY
}

compile_b_shard() {
    local runtime_dir="$1" log="$runtime_dir/ovl-001b-compile.log"
    local safe_capture="$runtime_dir/ovl-001b-safe-capture.json"
    [[ -f "$safe_capture" ]] || fail "Captura derivada OVL-001B-safe ausente."
    printf '\n==> Compilando somente OVL-001B-safe (%s) sobre o cache A aprovado\n' "$B_CAPTURE_KEY"
    env -u PSX_OVERLAY_CACHE_DIR -u PSX_OVERLAY_CAPTURES \
        "$PYTHON_BIN" "$COMPILE_OVERLAYS" \
        --captures "$safe_capture" --capture-key "$B_CAPTURE_KEY" \
        --game-toml "$TEST_CONFIG" --recompiler "$RECOMPILER" \
        --runtime-include "$RUNTIME_INCLUDE" --out-dir "$runtime_dir/cache" \
        --gcc "$GCC_BIN" --compiler gcc --cps --jobs 1 2>&1 | tee "$log"
}

audit_combined_cache() {
    local runtime_dir="$1"
    "$PYTHON_BIN" - "$runtime_dir" "$A_TARGET_FILE" "$B_TARGET_FILE" \
        "$B_CAPTURE_KEY" "$EXPECTED_CACHE_REL" <<'PY'
import hashlib,json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); a_targets=pathlib.Path(sys.argv[2]); b_targets=pathlib.Path(sys.argv[3])
b_key=sys.argv[4]; expected_rel=pathlib.PurePosixPath(sys.argv[5])
cache=root/pathlib.Path(*expected_rel.parts); log=(root/'ovl-001b-compile.log').read_text(encoding='utf-8',errors='replace')
if f'({b_key})' not in log or 'Capture filter: 1/' not in log:
    raise SystemExit('ERRO: log nao confirma o filtro exato OVL-001B')
if re.search(r'(?:RECOMPILER ERROR|GENERATED-C AUDIT FAILED|RANGE AUDIT FAILED|\bFAILED\b)',log):
    raise SystemExit('ERRO: compilador reportou falha/audit failure')
break_sources=[p.name for p in cache.glob('*patched.c')
               if 'psx_break(' in p.read_text(encoding='utf-8',errors='replace')]
if break_sources:
    raise SystemExit('ERRO: shard safe ainda referencia psx_break: '+', '.join(break_sources))
for stem in ('00020000_AC1FF1A4','00020000_94E6122F'):
    if not (cache/f'{stem}.dll').is_file() or not (cache/f'{stem}.ranges').is_file():
        raise SystemExit(f'ERRO: shard principal ausente: {stem}')
a_manifest=json.loads((root/'ovl-001a-cache-source-manifest.json').read_text(encoding='utf-8'))
for row in a_manifest.get('files',[]):
    path=root/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(row['size']) or hashlib.sha256(path.read_bytes()).hexdigest().upper()!=row['sha256']:
        raise SystemExit(f'ERRO: artefato aprovado A foi alterado: {row["path"]}')
dlls=sorted(cache.glob('*.dll')); ranges=sorted(cache.glob('*.ranges'))
if not dlls or len(dlls)!=len(ranges): raise SystemExit('ERRO: inventario cumulativo incompleto')
entries=set(); f_lines=0
for path in ranges:
    if not path.with_suffix('.dll').is_file(): raise SystemExit(f'ERRO: DLL ausente para {path.name}')
    for line in path.read_text(encoding='utf-8').splitlines():
        parts=line.split()
        if parts and parts[0]=='F': f_lines+=1; entries.add(int(parts[1],16)&0x1fffffff)
def read_targets(path):
    result=[]
    for line in path.read_text(encoding='utf-8').splitlines():
        parts=line.split('#',1)[0].split()
        if parts: result.append(int(parts[1],16)&0x1fffffff)
    return result
at=read_targets(a_targets); bt=read_targets(b_targets)
if len(at)!=4 or len(bt)!=4 or set(at+bt)-entries:
    raise SystemExit('ERRO: cache cumulativo nao oferece todos os 8 gates A+B-safe')
files=[]
for path in sorted(dlls+ranges,key=lambda p:p.as_posix()):
    files.append({'path':path.relative_to(root).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest().upper(),'size':path.stat().st_size})
(root/'ovl-001b-cache-manifest.json').write_text(json.dumps({
    'track':'OVL-001B-SAFE-CUMULATIVE','capture_keys':['0x00020000:0xAC1FF1A4',b_key],
    'body_words':5183,'incremental_words':620,'quarantined_words':130,
    'cache_relative':expected_rel.as_posix(),'dll_count':len(dlls),'ranges_count':len(ranges),
    'manifest_f_lines':f_lines,'unique_entries':len(entries),
    'a_targets':[f'0x{x|0x80000000:08X}' for x in sorted(at)],
    'b_targets':[f'0x{x|0x80000000:08X}' for x in sorted(bt)],'files':files
},indent=2,sort_keys=True)+'\n',encoding='utf-8')
print(f'Cache cumulativo A+B-safe auditado: {len(dlls)} DLL(s), {len(entries)} entradas, 8/8 gates.')
PY
}

write_state() {
    local runtime_dir="$1"
    umask 077
    {
        printf 'runtime_dir=%s\n' "$runtime_dir"
        printf 'runtime_exe=%s\n' "$runtime_dir/StreetFighterEXPlusAlphaRecomp.exe"
        printf 'test_config=%s\n' "$TEST_CONFIG"
        printf 'cache_manifest=%s\n' "$runtime_dir/ovl-001b-cache-manifest.json"
        printf 'capture_a_key=%s\ncapture_b_key=%s\n' "$A_CAPTURE_KEY" "$B_CAPTURE_KEY"
        printf 'capture_b_sha256=%s\nruntime_exe_sha256=%s\n' "$EXPECTED_B_CAPTURE_SHA" "$EXPECTED_EXE_SHA"
        printf 'body_words=%s\nincremental_words=%s\nquarantined_words=%s\n' 5183 620 130
        printf 'ranges_sha256=%s\nrecompiler_sha256=%s\ncodegen_hash=%s\n' \
            "$EXPECTED_RANGES_SHA" "$EXPECTED_RECOMPILER_SHA" "$EXPECTED_CODEGEN_HASH"
        printf 'source_a_runtime=%s\ncreated_utc=%s\n' "$A_RUNTIME_DIR" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$B_RUNTIME_STATE"
}

main() {
    local runtime_dir
    case "${1:-}" in '') ;; -h|--help) usage; return ;; *) usage; fail "Argumento desconhecido: $1" ;; esac
    validate_inputs
    runtime_dir="$(make_runtime_dir)"
    copy_approved_a_runtime "$runtime_dir"
    derive_safe_capture "$runtime_dir"
    compile_b_shard "$runtime_dir"
    audit_combined_cache "$runtime_dir"
    write_state "$runtime_dir"
    printf '\nOVL-001B-safe compilada no runtime cumulativo A+B. O executavel principal nao foi recompilado.\n'
    printf 'Abra o jogo com:\n\n  bash tools/run_ovl_001b_test.sh\n\n'
    printf 'Depois, ainda no Mode Select, execute:\n  bash tools/telemetry_before_after_ovl_001b.sh prepare\n'
}

main "$@"
