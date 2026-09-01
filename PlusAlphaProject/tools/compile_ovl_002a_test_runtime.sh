#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly SOURCE_STATE="$PROJECT_ROOT/local/overlay/.ovl-001b-current-runtime.state"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002a-current-runtime.state"
readonly TELEMETRY_STATE="$PROJECT_ROOT/local/telemetry/.ovl-002a-test-active.state"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002a_test.toml"
readonly TARGET_FILE="$PROJECT_ROOT/seeds/ovl_002a_target_pcs.txt"
readonly COMPILE_OVERLAYS="$REPO_ROOT/psxrecomp/tools/compile_overlays.py"
readonly RECOMPILER="$REPO_ROOT/psxrecomp/recompiler/build/psxrecomp-game.exe"
readonly RUNTIME_INCLUDE="$REPO_ROOT/psxrecomp/runtime/include"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly DISPATCH_FILE="$PROJECT_ROOT/generated/SLUS_005.48_dispatch.c"
readonly GCC_BIN=/ucrt64/bin/gcc.exe
readonly RUNTIME_PARENT="$PROJECT_ROOT/local/overlay"
readonly CAPTURE_KEY=0x00020000:0xF943B63B
readonly EXPECTED_IMAGE_SHA=603A2A697D5CCCE74E6AFF3E4A5621F868C587E896410BC68A5275F01E57F3BF
readonly EXPECTED_BODY_SHA=A02CD4A887B4CC31A81BE9815A007D51635070447FBE5F5200188DEA2003A5DC
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_RECOMPILER_SHA=3FA9DBAA2312F833C221BBA3BF17099BBD856754D440255E18DB6DD4A3F6D091
readonly EXPECTED_CODEGEN_HASH=562d908f
readonly EXPECTED_CACHE_REL=cache/SLUS-00548/gcc/win-x64/cg5_562d908f

PYTHON_BIN=
SOURCE_RUNTIME_DIR=
SOURCE_RUNTIME_EXE=
SOURCE_CACHE_MANIFEST=
SOURCE_CAPTURE_FILE=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com o jogo fechado:

  bash tools/compile_ovl_002a_test_runtime.sh

O script copia e audita o runtime cumulativo OVL-001B aprovado, extrai somente
a raiz 0x80093BB8 e o alias 0x80093E4C da imagem F943B63B e compila esse shard
no novo runtime isolado. Nao recompila o executavel principal, nao gera fontes
S1 e nao altera BIOS, entry_funcs.txt ou generated/.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_source_runtime() {
    [[ -f "$SOURCE_STATE" ]] || fail "Runtime OVL-001B ausente."
    SOURCE_RUNTIME_DIR="$(state_value "$SOURCE_STATE" runtime_dir)"
    SOURCE_RUNTIME_EXE="$(state_value "$SOURCE_STATE" runtime_exe)"
    SOURCE_CACHE_MANIFEST="$(state_value "$SOURCE_STATE" cache_manifest)"
    SOURCE_CAPTURE_FILE="$SOURCE_RUNTIME_DIR/overlay_captures.json"
    case "$SOURCE_RUNTIME_DIR" in
        "$PROJECT_ROOT"/local/overlay/ovl-001b-test-runtime-*) ;;
        *) fail "Estado OVL-001B aponta para runtime invalido." ;;
    esac
    [[ "$(state_value "$SOURCE_STATE" capture_a_key)" == 0x00020000:0xAC1FF1A4 ]] || fail "Chave A divergente."
    [[ "$(state_value "$SOURCE_STATE" capture_b_key)" == 0x00020000:0x94E6122F ]] || fail "Chave B divergente."
}

validate_inputs() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep cp mkdir seq tee find sort env; do
        command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado no UCRT64."
    done
    select_python
    [[ ! -f "$TELEMETRY_STATE" ]] || fail "Existe uma coleta OVL-002A ativa."
    read_source_runtime
    for file in "$SOURCE_RUNTIME_EXE" "$SOURCE_CACHE_MANIFEST" "$SOURCE_CAPTURE_FILE" \
                "$TEST_CONFIG" "$TARGET_FILE" "$COMPILE_OVERLAYS" "$RECOMPILER" \
                "$RUNTIME_INCLUDE/psx_runtime.h" "$RANGES_FILE" "$DISPATCH_FILE" "$GCC_BIN"; do
        [[ -f "$file" ]] || fail "Arquivo obrigatorio ausente: $file"
    done
    [[ "$(sha256sum "$SOURCE_RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] ||
        fail "Executavel-base OVL-001B divergiu."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] ||
        fail "Ranges do EXE principal divergiram do checkpoint S1-261."
    [[ "$(sha256sum "$RECOMPILER" | awk '{print toupper($1)}')" == "$EXPECTED_RECOMPILER_SHA" ]] ||
        fail "Recompilador divergiu do binario pre-auditado."
    grep -Eq '^[[:space:]]*overlay_cache[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$TEST_CONFIG" ||
        fail "A config OVL-002A nao habilita overlay_cache."
    ! grep -Eq '^[[:space:]]*overlay_autocompile_cmd(_tcc)?[[:space:]]*=' "$TEST_CONFIG" ||
        fail "Autocompilacao nao e permitida."

    "$PYTHON_BIN" - "$SOURCE_RUNTIME_DIR" "$SOURCE_CACHE_MANIFEST" "$SOURCE_CAPTURE_FILE" \
        "$TEST_CONFIG" "$COMPILE_OVERLAYS" "$TARGET_FILE" "$RANGES_FILE" "$DISPATCH_FILE" <<'PY'
import base64,binascii,copy,hashlib,importlib.util,json,pathlib,struct,sys,tomllib
runtime=pathlib.Path(sys.argv[1]); manifest_path=pathlib.Path(sys.argv[2]); capture_path=pathlib.Path(sys.argv[3])
config=pathlib.Path(sys.argv[4]); compiler=pathlib.Path(sys.argv[5]); target_path=pathlib.Path(sys.argv[6])
ranges_path=pathlib.Path(sys.argv[7]); dispatch_path=pathlib.Path(sys.argv[8])
manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
if manifest.get('track')!='OVL-001B-SAFE-CUMULATIVE': raise SystemExit('cache-base nao e OVL-001B aprovado')
if manifest.get('capture_keys')!=['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F']:
    raise SystemExit('chaves do cache-base divergiram')
for item in manifest.get('files',[]):
    path=runtime/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']): raise SystemExit(f'cache-base ausente: {item["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']: raise SystemExit(f'cache-base alterado: {item["path"]}')
found=[]
for row in json.loads(capture_path.read_text(encoding='utf-8')):
    data=base64.b64decode(row['bytes_b64']); load=int(row['load_addr'],0); crc=binascii.crc32(data)&0xffffffff
    if (load&0x1fffffff)==0x20000 and crc==0xF943B63B: found.append((row,data,load))
if len(found)!=1: raise SystemExit(f'imagem F943B63B aparece {len(found)} vez(es), esperado 1')
row,data,load=found[0]
if len(data)!=860160: raise SystemExit('tamanho da imagem F943B63B divergente')
if hashlib.sha256(data).hexdigest().upper()!='603A2A697D5CCCE74E6AFF3E4A5621F868C587E896410BC68A5275F01E57F3BF':
    raise SystemExit('SHA-256 da imagem F943B63B divergente')
lo,hi=0x80093BB8,0x80093F40; body=data[lo-load:hi-load]
if len(body)!=904 or hashlib.sha256(body).hexdigest().upper()!='A02CD4A887B4CC31A81BE9815A007D51635070447FBE5F5200188DEA2003A5DC':
    raise SystemExit('boundary/hash do corpo OVL-002A divergiu')
observed={int(x,16) for x in row.get('dispatch_entry_pcs',[])}
if 0x80093E4C not in observed: raise SystemExit('alias quente nao aparece no dispatch observado')
filtered=copy.deepcopy(row)
filtered['executed_pcs']=['0x80093E4C']; filtered['observed_pcs']=['0x80093E4C']
filtered['dispatch_entry_pcs']=['0x80093E4C']; filtered['function_entry_pcs']=['0x80093BB8']; filtered['seeds']=['0x80093E4C']
spec=importlib.util.spec_from_file_location('compile_overlays_preaudit',compiler)
co=importlib.util.module_from_spec(spec); spec.loader.exec_module(co)
toml_doc=tomllib.loads(config.read_text(encoding='utf-8'))
_,audit=co.classify_overlay_seeds(filtered,data,load,len(data),0xF943B63B,toml_doc)
reasons=audit['included_reasons']
if reasons!={0x80093BB8:'FUNCTION_POINTER_TARGET',0x80093E4C:'DISPATCH_INTERIOR'}:
    raise SystemExit(f'classificacao raiz/alias divergente: {reasons}')
walk=co._walk_overlay_function(data,load,len(data),0x80093BB8,0x80093F40)
if len(walk['visited'])!=226 or walk['direct_jals'] or walk['jump_table_targets']:
    raise SystemExit('closure overlay nao e exatamente 226 palavras independentes')
special={'break':0,'syscall':0,'cop2':0,'jalr':0}; jal_targets=[]
for pc in sorted(walk['visited']):
    word=struct.unpack_from('<I',data,pc-load)[0]; op=word>>26; fn=word&0x3f
    if op==0 and fn==0x0D: special['break']+=1
    if op==0 and fn==0x0C: special['syscall']+=1
    if op==0 and fn==0x09: special['jalr']+=1
    if op==0x12: special['cop2']+=1
    if op==3: jal_targets.append(((pc+4)&0xF0000000)|((word&0x03FFFFFF)<<2))
if special!={'break':0,'syscall':0,'cop2':9,'jalr':0}: raise SystemExit(f'instrucoes especiais divergiram: {special}')
if sorted(jal_targets)!=[0x8019CB60,0x8019E440]: raise SystemExit('JAL externos divergiram')
ranges=[]
for line in ranges_path.read_text(encoding='utf-8').splitlines():
    p=line.split()
    if len(p)==3 and p[0]=='R': ranges.append((int(p[1],16),int(p[1],16)+int(p[2],16)))
if any(not any(a<=target<b for a,b in ranges) for target in jal_targets): raise SystemExit('JAL externo ainda fora dos ranges S1-261')
dispatch=dispatch_path.read_text(encoding='utf-8',errors='replace')
if '0x8019CB60u' not in dispatch or '0x8019E440u' not in dispatch: raise SystemExit('JAL externo ausente do dispatch estatico')
targets=[]
for line in target_path.read_text(encoding='utf-8').splitlines():
    p=line.split('#',1)[0].split()
    if p: targets.append(int(p[1],16))
if targets!=[0x80093E4C]: raise SystemExit('target OVL-002A deve conter somente o alias quente')
print('Pre-auditoria OVL-002A: raiz+alias, 226 palavras, 2 JAL ja nativos, 9 COP2, zero BREAK/JALR.')
PY
}

make_runtime_dir() {
    local suffix candidate
    mkdir -p "$RUNTIME_PARENT"
    for suffix in $(seq -w 1 99); do
        candidate="$RUNTIME_PARENT/ovl-002a-test-runtime-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    done
    fail "Nao ha runtime livre para OVL-002A."
}

copy_source_runtime() {
    local runtime_dir="$1" file
    cp "$SOURCE_RUNTIME_EXE" "$runtime_dir/StreetFighterEXPlusAlphaRecomp.exe"
    for file in input.ini keybinds.ini settings.toml launcher.rml; do
        [[ -f "$SOURCE_RUNTIME_DIR/$file" ]] && cp "$SOURCE_RUNTIME_DIR/$file" "$runtime_dir/$file"
    done
    mkdir -p "$runtime_dir/cache"
    cp -R "$SOURCE_RUNTIME_DIR/cache/." "$runtime_dir/cache/"
    cp "$SOURCE_CACHE_MANIFEST" "$runtime_dir/ovl-001b-cache-source-manifest.json"
}

derive_capture() {
    local runtime_dir="$1" output="$runtime_dir/ovl-002a-filtered-capture.json"
    "$PYTHON_BIN" - "$SOURCE_CAPTURE_FILE" "$output" <<'PY'
import base64,binascii,copy,json,pathlib,sys
source=pathlib.Path(sys.argv[1]); output=pathlib.Path(sys.argv[2]); found=[]
for row in json.loads(source.read_text(encoding='utf-8')):
    data=base64.b64decode(row['bytes_b64'])
    if (int(row['load_addr'],0)&0x1fffffff)==0x20000 and (binascii.crc32(data)&0xffffffff)==0xF943B63B:
        found.append(row)
if len(found)!=1: raise SystemExit(f'imagem F943B63B aparece {len(found)} vez(es)')
row=copy.deepcopy(found[0])
row['executed_pcs']=['0x80093E4C']; row['observed_pcs']=['0x80093E4C']
row['dispatch_entry_pcs']=['0x80093E4C']; row['function_entry_pcs']=['0x80093BB8']; row['seeds']=['0x80093E4C']
row['micro_lot']='OVL-002A: owner 0x80093BB8 + dispatch interior 0x80093E4C only'
output.write_text(json.dumps([row],indent=2)+'\n',encoding='utf-8')
print('Captura privada OVL-002A derivada: uma raiz e uma entrada interior.')
PY
}

compile_shard() {
    local runtime_dir="$1" log="$runtime_dir/ovl-002a-compile.log"
    printf '\n==> Compilando somente OVL-002A (%s) sobre o cache OVL-001B aprovado\n' "$CAPTURE_KEY"
    env -u PSX_OVERLAY_CACHE_DIR -u PSX_OVERLAY_CAPTURES \
        "$PYTHON_BIN" "$COMPILE_OVERLAYS" \
        --captures "$runtime_dir/ovl-002a-filtered-capture.json" --capture-key "$CAPTURE_KEY" \
        --game-toml "$TEST_CONFIG" --recompiler "$RECOMPILER" \
        --runtime-include "$RUNTIME_INCLUDE" --out-dir "$runtime_dir/cache" \
        --gcc "$GCC_BIN" --compiler gcc --cps --jobs 1 2>&1 | tee "$log"
}

audit_combined_cache() {
    local runtime_dir="$1"
    "$PYTHON_BIN" - "$runtime_dir" "$TARGET_FILE" "$CAPTURE_KEY" "$EXPECTED_CACHE_REL" <<'PY'
import hashlib,json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); targets_path=pathlib.Path(sys.argv[2]); key=sys.argv[3]
expected_rel=pathlib.PurePosixPath(sys.argv[4]); cache=root/pathlib.Path(*expected_rel.parts)
source_manifest=json.loads((root/'ovl-001b-cache-source-manifest.json').read_text(encoding='utf-8'))
log=(root/'ovl-002a-compile.log').read_text(encoding='utf-8',errors='replace')
if f'({key})' not in log or 'Capture filter: 1/' not in log: raise SystemExit('ERRO: log nao confirma filtro OVL-002A exato')
if re.search(r'(?:RECOMPILER ERROR|GENERATED-C AUDIT FAILED|RANGE AUDIT FAILED|COMPILE ERROR|\bFAILED\b)',log):
    raise SystemExit('ERRO: compilador/auditoria OVL-002A reportou falha')
old_paths=set()
for item in source_manifest.get('files',[]):
    path=root/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts); old_paths.add(item['path'])
    if not path.is_file() or path.stat().st_size!=int(item['size']): raise SystemExit(f'cache B ausente: {item["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']: raise SystemExit(f'cache B alterado: {item["path"]}')
for suffix in ('.dll','.ranges'):
    if not (cache/f'00020000_F943B63B{suffix}').is_file(): raise SystemExit(f'shard principal OVL-002A ausente: {suffix}')
dlls=sorted(cache.glob('*.dll')); manifests=sorted(cache.glob('*.ranges'))
if not dlls or len(dlls)!=len(manifests): raise SystemExit('inventario cumulativo incompleto')
entries=set(); f_lines=0
for path in manifests:
    if not path.with_suffix('.dll').is_file(): raise SystemExit(f'DLL ausente para {path.name}')
    for line in path.read_text(encoding='utf-8').splitlines():
        p=line.split()
        if p and p[0]=='F': f_lines+=1; entries.add(int(p[1],16)&0x1fffffff)
required={0x00093BB8,0x00093E4C}
if required-entries: raise SystemExit('raiz/alias OVL-002A ausente do cache')
targets=[]
for line in targets_path.read_text(encoding='utf-8').splitlines():
    p=line.split('#',1)[0].split()
    if p: targets.append(int(p[1],16)&0x1fffffff)
if targets!=[0x00093E4C] or set(targets)-entries: raise SystemExit('gate dinamico OVL-002A divergente')
files=[]
for path in sorted(dlls+manifests,key=lambda p:p.as_posix()):
    files.append({'path':path.relative_to(root).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest().upper(),'size':path.stat().st_size})
new_paths={x['path'] for x in files}-old_paths
if not any('F943B63B' in p for p in new_paths): raise SystemExit('nenhum artefato novo F943B63B no cache')
(root/'ovl-002a-cache-manifest.json').write_text(json.dumps({
    'track':'OVL-002A-DDARK-CUMULATIVE','capture_keys':['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F',key],
    'body_words':226,'owner_root':'0x80093BB8','dispatch_interior':'0x80093E4C','cop2_instructions':9,
    'cache_relative':expected_rel.as_posix(),'dll_count':len(dlls),'ranges_count':len(manifests),
    'manifest_f_lines':f_lines,'unique_entries':len(entries),'new_files':sorted(new_paths),'files':files
},indent=2,sort_keys=True)+'\n',encoding='utf-8')
print(f'Cache OVL-002A auditado: {len(dlls)} DLL(s), {len(entries)} entradas; raiz+alias presentes.')
PY
}

write_state() {
    local runtime_dir="$1"
    umask 077
    {
        printf 'runtime_dir=%s\n' "$runtime_dir"
        printf 'runtime_exe=%s\n' "$runtime_dir/StreetFighterEXPlusAlphaRecomp.exe"
        printf 'test_config=%s\n' "$TEST_CONFIG"
        printf 'cache_manifest=%s\n' "$runtime_dir/ovl-002a-cache-manifest.json"
        printf 'capture_key=%s\nimage_sha256=%s\nbody_sha256=%s\n' "$CAPTURE_KEY" "$EXPECTED_IMAGE_SHA" "$EXPECTED_BODY_SHA"
        printf 'owner_root=0x80093BB8\ndispatch_interior=0x80093E4C\nbody_words=226\ncop2_instructions=9\n'
        printf 'runtime_exe_sha256=%s\nranges_sha256=%s\nrecompiler_sha256=%s\ncodegen_hash=%s\n' \
            "$EXPECTED_EXE_SHA" "$EXPECTED_RANGES_SHA" "$EXPECTED_RECOMPILER_SHA" "$EXPECTED_CODEGEN_HASH"
        printf 'source_runtime=%s\ncreated_utc=%s\n' "$SOURCE_RUNTIME_DIR" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$RUNTIME_STATE"
}

main() {
    local runtime_dir
    case "${1:-}" in '') ;; -h|--help) usage; return ;; *) usage; fail "Argumento desconhecido: $1" ;; esac
    validate_inputs
    runtime_dir="$(make_runtime_dir)"
    copy_source_runtime "$runtime_dir"
    derive_capture "$runtime_dir"
    compile_shard "$runtime_dir"
    audit_combined_cache "$runtime_dir"
    write_state "$runtime_dir"
    printf '\nOVL-002A compilada no runtime cumulativo. O executavel principal nao foi recompilado.\n'
    printf 'Abra o jogo com:\n\n  bash tools/run_ovl_002a_test.sh\n\n'
    printf 'Depois, ainda no Mode Select, execute:\n  bash tools/telemetry_before_after_ovl_002a.sh prepare\n'
}

main "$@"
