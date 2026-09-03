#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly SOURCE_STATE="$PROJECT_ROOT/local/overlay/.ovl-002b-current-runtime.state"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002c-current-runtime.state"
readonly TELEMETRY_STATE="$PROJECT_ROOT/local/telemetry/.ovl-002c-test-active.state"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002c_test.toml"
readonly TARGET_FILE="$PROJECT_ROOT/seeds/ovl_002c_target_pcs.txt"
readonly COMPILE_OVERLAYS="$REPO_ROOT/psxrecomp/tools/compile_overlays.py"
readonly RECOMPILER="$REPO_ROOT/psxrecomp/recompiler/build/psxrecomp-game.exe"
readonly RUNTIME_INCLUDE="$REPO_ROOT/psxrecomp/runtime/include"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly DISPATCH_FILE="$PROJECT_ROOT/generated/SLUS_005.48_dispatch.c"
readonly GCC_BIN=/ucrt64/bin/gcc.exe
readonly CAPTURE_KEY=0x00020000:0xF943B63B
readonly EXPECTED_IMAGE_SHA=603A2A697D5CCCE74E6AFF3E4A5621F868C587E896410BC68A5275F01E57F3BF
readonly EXPECTED_NEW_SHA=744CD7A64502F3E9FC01A43732EE20D3E6A2FC70077EB2B546437C1ED81B47A8
readonly EXPECTED_CUMULATIVE_SHA=483ACB7679B05D29B1C011A75A64E31DEED5CAA957985DACBE12FA3F9C6409E0
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_RECOMPILER_SHA=3FA9DBAA2312F833C221BBA3BF17099BBD856754D440255E18DB6DD4A3F6D091
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

  bash tools/compile_ovl_002c_test_runtime.sh

Compila somente o shard F943B63B em runtime isolado. Preserva as 1.108
palavras OVL-002A+B e acrescenta 966 palavras da familia da bomba. Nao
recompila o executavel principal, nao gera fontes S1 e nao altera BIOS,
entry_funcs.txt ou generated/.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_source_state() {
    [[ -f "$SOURCE_STATE" ]] || fail "Runtime OVL-002B aprovado ausente."
    SOURCE_RUNTIME_DIR="$(state_value "$SOURCE_STATE" runtime_dir)"
    SOURCE_RUNTIME_EXE="$(state_value "$SOURCE_STATE" runtime_exe)"
    SOURCE_CACHE_MANIFEST="$(state_value "$SOURCE_STATE" cache_manifest)"
    SOURCE_CAPTURE_FILE="$(state_value "$SOURCE_STATE" source_capture)"
    case "$SOURCE_RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002b-test-runtime-*) ;; *) fail "Estado OVL-002B invalido." ;; esac
    case "$SOURCE_CAPTURE_FILE" in "$PROJECT_ROOT"/local/overlay/ovl-001b-test-runtime-*/overlay_captures.json) ;; *) fail "Captura F943B63B invalida." ;; esac
    [[ "$(state_value "$SOURCE_STATE" capture_key)" == "$CAPTURE_KEY" ]] || fail "Chave OVL-002B divergente."
    [[ "$(state_value "$SOURCE_STATE" image_body_words)" == 1108 ]] || fail "Corpo OVL-002B divergente."
}

validate_inputs() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep cp mkdir seq tee env; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python; read_source_state
    [[ ! -f "$TELEMETRY_STATE" ]] || fail "Existe coleta OVL-002C ativa."
    for file in "$SOURCE_RUNTIME_EXE" "$SOURCE_CACHE_MANIFEST" "$SOURCE_CAPTURE_FILE" "$TEST_CONFIG" "$TARGET_FILE" \
                "$COMPILE_OVERLAYS" "$RECOMPILER" "$RUNTIME_INCLUDE/psx_runtime.h" "$RANGES_FILE" "$DISPATCH_FILE" "$GCC_BIN"; do
        [[ -f "$file" ]] || fail "Arquivo obrigatorio ausente: $file"
    done
    [[ "$(sha256sum "$SOURCE_RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel-base divergiu."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    [[ "$(sha256sum "$RECOMPILER" | awk '{print toupper($1)}')" == "$EXPECTED_RECOMPILER_SHA" ]] || fail "Recompilador divergiu."
    grep -Eq '^[[:space:]]*overlay_cache[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$TEST_CONFIG" || fail "overlay_cache desabilitado."
    ! grep -Eq '^[[:space:]]*overlay_autocompile_cmd(_tcc)?[[:space:]]*=' "$TEST_CONFIG" || fail "Autocompilacao nao permitida."

    "$PYTHON_BIN" - "$SOURCE_RUNTIME_DIR" "$SOURCE_CACHE_MANIFEST" "$SOURCE_CAPTURE_FILE" "$COMPILE_OVERLAYS" \
        "$TEST_CONFIG" "$TARGET_FILE" "$RANGES_FILE" "$DISPATCH_FILE" <<'PY'
import base64,binascii,copy,hashlib,importlib.util,json,pathlib,struct,sys,tomllib
runtime=pathlib.Path(sys.argv[1]); manifest_path=pathlib.Path(sys.argv[2]); capture_path=pathlib.Path(sys.argv[3])
compiler=pathlib.Path(sys.argv[4]); config=pathlib.Path(sys.argv[5]); target_path=pathlib.Path(sys.argv[6])
ranges_path=pathlib.Path(sys.argv[7]); dispatch_path=pathlib.Path(sys.argv[8])
manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
if manifest.get('track')!='OVL-002B-DDARK-CUMULATIVE': raise SystemExit('cache-base nao e OVL-002B aprovado')
if int(manifest.get('image_body_words',0))!=1108: raise SystemExit('volume OVL-002B divergente')
for item in manifest.get('files',[]):
    path=runtime/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']): raise SystemExit(f'cache-base ausente: {item["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']: raise SystemExit(f'cache-base alterado: {item["path"]}')
found=[]
for row in json.loads(capture_path.read_text(encoding='utf-8')):
    data=base64.b64decode(row['bytes_b64']); load=int(row['load_addr'],0); crc=binascii.crc32(data)&0xffffffff
    if (load&0x1fffffff)==0x20000 and crc==0xF943B63B: found.append((row,data,load))
if len(found)!=1: raise SystemExit(f'imagem F943B63B aparece {len(found)} vez(es)')
row,data,load=found[0]
if len(data)!=860160 or hashlib.sha256(data).hexdigest().upper()!='603A2A697D5CCCE74E6AFF3E4A5621F868C587E896410BC68A5275F01E57F3BF':
    raise SystemExit('imagem F943B63B divergente')
body=data[0x80049568-load:0x8004A480-load]
if len(body)!=3864 or hashlib.sha256(body).hexdigest().upper()!='744CD7A64502F3E9FC01A43732EE20D3E6A2FC70077EB2B546437C1ED81B47A8':
    raise SystemExit('corpo novo OVL-002C divergente')
old_roots=[0x80092138,0x80092524,0x80092740,0x80092800,0x800929D4,0x80092C2C,0x80093BB8]
filtered=copy.deepcopy(row)
filtered['executed_pcs']=['0x80092C2C','0x80093E4C','0x80049568','0x80049808','0x80049988']
filtered['observed_pcs']=filtered['executed_pcs'][:]
filtered['dispatch_entry_pcs']=filtered['executed_pcs'][:]
filtered['function_entry_pcs']=[f'0x{x:08X}' for x in old_roots]
filtered['seeds']=filtered['executed_pcs'][:]
spec=importlib.util.spec_from_file_location('compile_overlays_preaudit',compiler)
co=importlib.util.module_from_spec(spec); spec.loader.exec_module(co)
toml_doc=tomllib.loads(config.read_text(encoding='utf-8'))
seed_lines,audit=co.classify_overlay_seeds(filtered,data,load,len(data),0xF943B63B,toml_doc)
new_roots=[0x80049568,0x8004964C,0x800497E4,0x80049B9C,0x80049D24,0x80049E70,0x80049E90,0x80049E9C]
expected={**{x:'FUNCTION_POINTER_TARGET' for x in old_roots},0x80092C2C:'DISPATCH_ENTRY',0x80093E4C:'DISPATCH_INTERIOR',
          0x80049568:'DISPATCH_ENTRY',0x80049808:'DISPATCH_INTERIOR',0x80049988:'DISPATCH_INTERIOR',
          **{x:'DIRECT_JAL_TARGET' for x in new_roots[1:]}}
if audit['included_reasons']!=expected: raise SystemExit(f'classificacao cumulativa divergente: {audit["included_reasons"]}')
if 'interior 0x80049808' not in seed_lines or 'interior 0x80049988' not in seed_lines:
    raise SystemExit('aliases novos perderam classificacao interior')
counts=[57,102,238,98,83,8,3,377]
hashes=['2DC88239EEAC988824A97927EEF7706D75F4D0492CD7120ADE9317C94C5C44BA','868563252F7FCF589EEC6E78C6151669D7B6C943C21AE6389C11B8D0A72EC37A','506AF8908284A8E3021372F31FB3FE8408A895B75762B6030B6765D25E279E3B','2294365645DEE8ED2D4931E9A0F83174F7C4F9F7B142B989F8CACCD3A7C8B811','4192AA5560B00A6079D77774827CD8786A792DDB4FD07315DD9CEE633CE4D6D8','B731B0CF800CBD93593B62E1A6BE51067A2E31B6ADD26BA907A121B79773EB2A','5E5D29712D87F23CFAC414C497EA12FB9D5D5DFC49B1498E2955433307D4CFEF','632887006C0D3F5A8449C4ABECB5F46B94230AEBA5051B7AF54A934F0B29F4AC']
visited=set(); tables=set()
for i,(root,count,wanted) in enumerate(zip(new_roots,counts,hashes)):
    cap=new_roots[i+1] if i+1<len(new_roots) else load+len(data)
    walk=co._walk_overlay_function(data,load,len(data),root,cap); raw=b''.join(data[x-load:x-load+4] for x in sorted(walk['visited']))
    if len(walk['visited'])!=count or hashlib.sha256(raw).hexdigest().upper()!=wanted: raise SystemExit(f'closure 0x{root:08X} divergente')
    visited.update(walk['visited']); tables.update(walk['jump_table_targets'])
if len(visited)!=966 or tables!={0x800495CC,0x800495D4,0x800495E4,0x800495F4,0x80049604,0x80049614}:
    raise SystemExit('closure/jump table OVL-002C divergente')
old_ranges=runtime/pathlib.Path(*pathlib.PurePosixPath(manifest['cache_relative']).parts)/'00020000_F943B63B.ranges'
old_words=set()
for line in old_ranges.read_text(encoding='utf-8').splitlines():
    p=line.split()
    if len(p)==3 and p[0]=='R':
        start=int(p[1],16); old_words.update(range(start,start+int(p[2],16),4))
combined=old_words|visited
combined_raw=b''.join(data[x-load:x-load+4] for x in sorted(combined))
if len(old_words)!=1108 or old_words&visited or len(combined)!=2074:
    raise SystemExit('sobreposicao/volume cumulativo OVL-002C divergente')
if hashlib.sha256(combined_raw).hexdigest().upper()!='483ACB7679B05D29B1C011A75A64E31DEED5CAA957985DACBE12FA3F9C6409E0':
    raise SystemExit('hash cumulativo OVL-002C divergente')
special={'break':0,'syscall':0,'jalr':0,'cop2':0}; external=set()
for pc in visited:
    word=struct.unpack_from('<I',data,pc-load)[0]; op=word>>26; fn=word&0x3f
    if op==0 and fn==0x0d: special['break']+=1
    if op==0 and fn==0x0c: special['syscall']+=1
    if op==0 and fn==0x09: special['jalr']+=1
    if op==0x12: special['cop2']+=1
    if op==3:
        target=((pc+4)&0xf0000000)|((word&0x03ffffff)<<2)
        if target not in visited: external.add(target)
if special!={'break':0,'syscall':0,'jalr':0,'cop2':35}: raise SystemExit(f'instrucoes especiais divergiram: {special}')
expected_external={0x8010C72C,0x80123BA8,0x80125024,0x8012C288,0x80159E90,0x80159F18,0x80159F3C,0x8015A080,0x80168788,0x801690D4,0x801938B0,0x801948DC,0x80194990,0x8019528C,0x8019D740,0x8019D7D0}
if external!=expected_external: raise SystemExit('JAL externos divergiram')
ranges=[]
for line in ranges_path.read_text(encoding='utf-8').splitlines():
    p=line.split()
    if len(p)==3 and p[0]=='R': ranges.append((int(p[1],16),int(p[1],16)+int(p[2],16)))
if any(not any(a<=x<b for a,b in ranges) for x in external): raise SystemExit('JAL externo fora dos ranges S1-261')
dispatch=dispatch_path.read_text(encoding='utf-8',errors='replace')
if any(f'0x{x:08X}u' not in dispatch for x in external): raise SystemExit('JAL externo ausente do dispatch S1-261')
targets=[int(line.split('#',1)[0].split()[1],16) for line in target_path.read_text().splitlines() if line.split('#',1)[0].split()]
if targets!=[0x80049568]: raise SystemExit('target OVL-002C divergente')
print('Pre-auditoria OVL-002C: +966 palavras, 8 roots, 2 aliases interiores, 35 COP2, zero BREAK/SYSCALL/JALR.')
PY
}

make_runtime_dir() {
    local suffix candidate
    mkdir -p "$PROJECT_ROOT/local/overlay"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/overlay/ovl-002c-test-runtime-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    done
    fail "Nao ha runtime livre para OVL-002C."
}

copy_source_runtime() {
    local dst="$1" file
    cp "$SOURCE_RUNTIME_EXE" "$dst/StreetFighterEXPlusAlphaRecomp.exe"
    for file in input.ini keybinds.ini settings.toml launcher.rml; do [[ -f "$SOURCE_RUNTIME_DIR/$file" ]] && cp "$SOURCE_RUNTIME_DIR/$file" "$dst/$file"; done
    mkdir -p "$dst/cache"; cp -R "$SOURCE_RUNTIME_DIR/cache/." "$dst/cache/"
    cp "$SOURCE_CACHE_MANIFEST" "$dst/ovl-002b-cache-source-manifest.json"
}

derive_capture() {
    "$PYTHON_BIN" - "$SOURCE_CAPTURE_FILE" "$1/ovl-002c-filtered-capture.json" <<'PY'
import base64,binascii,copy,json,pathlib,sys
source=pathlib.Path(sys.argv[1]); output=pathlib.Path(sys.argv[2]); found=[]
for row in json.loads(source.read_text(encoding='utf-8')):
    data=base64.b64decode(row['bytes_b64'])
    if (int(row['load_addr'],0)&0x1fffffff)==0x20000 and (binascii.crc32(data)&0xffffffff)==0xF943B63B: found.append(row)
if len(found)!=1: raise SystemExit('imagem F943B63B nao e unica')
row=copy.deepcopy(found[0])
row['executed_pcs']=['0x80092C2C','0x80093E4C','0x80049568','0x80049808','0x80049988']; row['observed_pcs']=row['executed_pcs'][:]
row['dispatch_entry_pcs']=row['executed_pcs'][:]
row['function_entry_pcs']=['0x80092138','0x80092524','0x80092740','0x80092800','0x800929D4','0x80092C2C','0x80093BB8']
row['seeds']=row['executed_pcs'][:]
row['micro_lot']='OVL-002C cumulative: preserve 1108 words and add 966-word D.Dark bomb family'
output.write_text(json.dumps([row],indent=2)+'\n',encoding='utf-8')
print('Captura privada OVL-002C derivada: 15 roots formais, 3 aliases, 2.074 palavras cumulativas.')
PY
}

compile_shard() {
    local dst="$1" log="$1/ovl-002c-compile.log"
    printf '\n==> Compilando shard cumulativo OVL-002C em %s\n' "$CAPTURE_KEY"
    env -u PSX_OVERLAY_CACHE_DIR -u PSX_OVERLAY_CAPTURES "$PYTHON_BIN" "$COMPILE_OVERLAYS" \
        --captures "$dst/ovl-002c-filtered-capture.json" --capture-key "$CAPTURE_KEY" \
        --game-toml "$TEST_CONFIG" --recompiler "$RECOMPILER" --runtime-include "$RUNTIME_INCLUDE" \
        --out-dir "$dst/cache" --gcc "$GCC_BIN" --compiler gcc --cps --jobs 1 --force 2>&1 | tee "$log"
}

audit_cache() {
    "$PYTHON_BIN" - "$1" "$EXPECTED_CACHE_REL" <<'PY'
import hashlib,json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); rel=pathlib.PurePosixPath(sys.argv[2]); cache=root/pathlib.Path(*rel.parts)
source=json.loads((root/'ovl-002b-cache-source-manifest.json').read_text(encoding='utf-8'))
log=(root/'ovl-002c-compile.log').read_text(encoding='utf-8',errors='replace')
if '(0x00020000:0xF943B63B)' not in log or 'Capture filter: 1/' not in log or 'OK ->' not in log: raise SystemExit('ERRO: log nao confirma compilacao filtrada OVL-002C')
if 'SKIP: DLL already exists' in log or re.search(r'(?:RECOMPILER ERROR|GENERATED-C AUDIT FAILED|RANGE AUDIT FAILED|COMPILE ERROR|\bFAILED\b)',log):
    raise SystemExit('ERRO: compilador/auditoria OVL-002C reportou falha')
old={x['path']:x for x in source.get('files',[])}; changed=[]
for name,item in old.items():
    path=root/pathlib.Path(*pathlib.PurePosixPath(name).parts)
    if not path.is_file(): raise SystemExit(f'cache-base ausente: {name}')
    same=path.stat().st_size==int(item['size']) and hashlib.sha256(path.read_bytes()).hexdigest().upper()==item['sha256']
    if 'F943B63B' in name:
        if not same: changed.append(name)
    elif not same: raise SystemExit(f'artefato anterior alterado: {name}')
for suffix in ('.dll','.ranges'):
    if not (cache/f'00020000_F943B63B{suffix}').is_file(): raise SystemExit(f'shard ausente: {suffix}')
if not any(x.endswith('.dll') for x in changed) or not any(x.endswith('.ranges') for x in changed): raise SystemExit('DLL/ranges F943B63B nao foram substituidos')
image=cache/'00020000_F943B63B.ranges'; entries=set(); words=set()
for line in image.read_text(encoding='utf-8').splitlines():
    p=line.split()
    if len(p)==3 and p[0]=='F': entries.add(int(p[1],16)&0x1fffffff)
    if len(p)==3 and p[0]=='R':
        start=int(p[1],16); size=int(p[2],16); words.update(range(start,start+size,4))
required={0x00092138,0x00092524,0x00092740,0x00092800,0x000929D4,0x00092C2C,0x00093BB8,0x00093E4C,
          0x00049568,0x0004964C,0x000497E4,0x00049808,0x00049988,0x00049B9C,0x00049D24,0x00049E70,0x00049E90,0x00049E9C}
if required-entries: raise SystemExit('roots/aliases cumulativos ausentes: '+','.join(f'0x{x:08X}' for x in sorted(required-entries)))
if {0x00092F00,0x00047DE8}&entries: raise SystemExit('alvo em quarentena entrou no shard')
if len(words)!=2074: raise SystemExit(f'corpo cumulativo tem {len(words)} palavras, esperado 2074')
dlls=sorted(cache.glob('*.dll')); ranges=sorted(cache.glob('*.ranges'))
if not dlls or len(dlls)!=len(ranges): raise SystemExit('inventario cumulativo incompleto')
all_entries=set(); files=[]
for path in ranges:
    for line in path.read_text(encoding='utf-8').splitlines():
        p=line.split()
        if p and p[0]=='F': all_entries.add(int(p[1],16)&0x1fffffff)
for path in sorted(dlls+ranges,key=lambda p:p.as_posix()):
    files.append({'path':path.relative_to(root).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest().upper(),'size':path.stat().st_size})
(root/'ovl-002c-cache-manifest.json').write_text(json.dumps({
 'track':'OVL-002C-DDARK-BOMBS-CUMULATIVE','capture_keys':['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F','0x00020000:0xF943B63B'],
 'incremental_words':966,'prior_image_words':1108,'image_body_words':2074,'new_root':'0x80049568',
 'new_aliases':['0x80049808','0x80049988'],'cop2_incremental':35,'cop2_total_image':115,
 'new_body_sha256':'744CD7A64502F3E9FC01A43732EE20D3E6A2FC70077EB2B546437C1ED81B47A8',
 'cumulative_body_sha256':'483ACB7679B05D29B1C011A75A64E31DEED5CAA957985DACBE12FA3F9C6409E0',
 'cache_relative':rel.as_posix(),'dll_count':len(dlls),'ranges_count':len(ranges),'unique_entries':len(all_entries),
 'replaced_source_files':sorted(changed),'files':files},indent=2,sort_keys=True)+'\n',encoding='utf-8')
print(f'Cache OVL-002C auditado: {len(dlls)} DLL(s), {len(all_entries)} entradas e 2.074 palavras na imagem F943B63B.')
PY
}

write_state() {
    local dst="$1"; umask 077
    {
        printf 'runtime_dir=%s\nruntime_exe=%s\ntest_config=%s\ncache_manifest=%s\n' "$dst" "$dst/StreetFighterEXPlusAlphaRecomp.exe" "$TEST_CONFIG" "$dst/ovl-002c-cache-manifest.json"
        printf 'capture_key=%s\nimage_sha256=%s\n' "$CAPTURE_KEY" "$EXPECTED_IMAGE_SHA"
        printf 'target=0x80049568\nalias_1=0x80049808\nalias_2=0x80049988\n'
        printf 'incremental_words=966\nprior_words=1108\nimage_body_words=2074\ncop2_incremental=35\ncop2_total_image=115\n'
        printf 'incremental_sha256=%s\ncumulative_sha256=%s\n' "$EXPECTED_NEW_SHA" "$EXPECTED_CUMULATIVE_SHA"
        printf 'runtime_exe_sha256=%s\nranges_sha256=%s\nrecompiler_sha256=%s\n' "$EXPECTED_EXE_SHA" "$EXPECTED_RANGES_SHA" "$EXPECTED_RECOMPILER_SHA"
        printf 'source_runtime=%s\nsource_capture=%s\ncreated_utc=%s\n' "$SOURCE_RUNTIME_DIR" "$SOURCE_CAPTURE_FILE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$RUNTIME_STATE"
}

main() {
    local dst
    case "${1:-}" in '') ;; -h|--help) usage; return ;; *) usage; fail "Argumento desconhecido: $1" ;; esac
    validate_inputs
    dst="$(make_runtime_dir)"; copy_source_runtime "$dst"; derive_capture "$dst"
    compile_shard "$dst"; audit_cache "$dst"; write_state "$dst"
    printf '\nOVL-002C compilada em runtime cumulativo isolado. O executavel principal nao foi recompilado.\n'
    printf 'Abra com:\n  bash tools/run_ovl_002c_test.sh\n\nDepois, no Mode Select:\n  bash tools/telemetry_before_after_ovl_002c.sh prepare\n'
}

main "$@"
