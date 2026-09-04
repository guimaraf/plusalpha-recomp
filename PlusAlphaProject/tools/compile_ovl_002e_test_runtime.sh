#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly SOURCE_STATE="$PROJECT_ROOT/local/overlay/.ovl-002d-current-runtime.state"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002e-current-runtime.state"
readonly TELEMETRY_STATE="$PROJECT_ROOT/local/telemetry/.ovl-002e-test-active.state"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002e_test.toml"
readonly TARGET_FILE="$PROJECT_ROOT/seeds/ovl_002e_target_pcs.txt"
readonly COMPILE_OVERLAYS="$REPO_ROOT/psxrecomp/tools/compile_overlays.py"
readonly RECOMPILER="$REPO_ROOT/psxrecomp/recompiler/build/psxrecomp-game.exe"
readonly RUNTIME_INCLUDE="$REPO_ROOT/psxrecomp/runtime/include"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly DISPATCH_FILE="$PROJECT_ROOT/generated/SLUS_005.48_dispatch.c"
readonly GCC_BIN=/ucrt64/bin/gcc.exe
readonly CAPTURE_KEY=0x00020000:0xF943B63B
readonly EXPECTED_IMAGE_SHA=603A2A697D5CCCE74E6AFF3E4A5621F868C587E896410BC68A5275F01E57F3BF
readonly EXPECTED_NEW_SHA=ADF1F024D3646B2AF044CB439C53284B520B9284524912C1013001CB8FBCBC53
readonly EXPECTED_CUMULATIVE_SHA=36548803322202BB9F7080F82FDCD5B06CFDD190A1E286D18C611403CD7F4D0A
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

  bash tools/compile_ovl_002e_test_runtime.sh

Preserva as 2.143 palavras OVL-002D e acrescenta somente a familia formal
0x80044830..0x80044C7B: 275 palavras, com seis aliases interiores.
Nao recompila o executavel principal nem altera generated/.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_source_state() {
    [[ -f "$SOURCE_STATE" ]] || fail "Runtime OVL-002D aprovado ausente."
    SOURCE_RUNTIME_DIR="$(state_value "$SOURCE_STATE" runtime_dir)"
    SOURCE_RUNTIME_EXE="$(state_value "$SOURCE_STATE" runtime_exe)"
    SOURCE_CACHE_MANIFEST="$(state_value "$SOURCE_STATE" cache_manifest)"
    SOURCE_CAPTURE_FILE="$(state_value "$SOURCE_STATE" source_capture)"
    case "$SOURCE_RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002d-test-runtime-*) ;; *) fail "Estado OVL-002D invalido." ;; esac
    case "$SOURCE_CAPTURE_FILE" in "$PROJECT_ROOT"/local/overlay/ovl-001b-test-runtime-*/overlay_captures.json) ;; *) fail "Captura-base invalida." ;; esac
    [[ "$(state_value "$SOURCE_STATE" capture_key)" == "$CAPTURE_KEY" ]] || fail "Chave OVL-002D divergente."
    [[ "$(state_value "$SOURCE_STATE" image_body_words)" == 2143 ]] || fail "Corpo OVL-002D divergente."
}

validate_inputs() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep cp mkdir seq tee env; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python; read_source_state
    [[ ! -f "$TELEMETRY_STATE" ]] || fail "Existe coleta OVL-002E ativa."
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
if manifest.get('track')!='OVL-002D-DDARK-47DE8-CUMULATIVE' or int(manifest.get('image_body_words',0))!=2143:
    raise SystemExit('cache-base nao e OVL-002D aprovado')
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
spec=importlib.util.spec_from_file_location('compile_overlays_preaudit',compiler)
co=importlib.util.module_from_spec(spec); spec.loader.exec_module(co)
root,end=0x80044830,0x80044C7C
aliases={0x8004485C,0x800448EC,0x80044984,0x80044A68,0x80044AF8,0x80044B8C}
if struct.unpack_from('<II',data,root-load-8)!=(0x03E00008,0) or struct.unpack_from('<I',data,end-load)[0]!=0x27BDFFE8:
    raise SystemExit('boundaries OVL-002E divergiram')
walk=co._walk_overlay_function(data,load,len(data),root,end); visited=set(walk['visited'])
raw=b''.join(data[x-load:x-load+4] for x in sorted(visited))
if len(visited)!=275 or min(visited)!=root or max(visited)!=end-4 or aliases-visited:
    raise SystemExit('closure OVL-002E excedeu 275 palavras ou perdeu alias')
if hashlib.sha256(raw).hexdigest().upper()!='ADF1F024D3646B2AF044CB439C53284B520B9284524912C1013001CB8FBCBC53':
    raise SystemExit('corpo OVL-002E divergente')
if walk['direct_jals'] or walk['jump_table_targets']: raise SystemExit('closure interna OVL-002E divergente')
special={'break':0,'syscall':0,'jalr':0,'cop2':0,'jr_non_ra':0}; external_jals=set(); bad_flow=[]
for pc in visited:
    word=struct.unpack_from('<I',data,pc-load)[0]; op=word>>26; fn=word&0x3f; rs=(word>>21)&0x1f
    kind,target=co._classify_cf(pc,word)
    if kind=='jal': external_jals.add(target)
    if kind in ('j','branch') and not (root<=target<end): bad_flow.append((pc,target))
    if op==0 and fn==0x0d: special['break']+=1
    if op==0 and fn==0x0c: special['syscall']+=1
    if op==0 and fn==0x09: special['jalr']+=1
    if op==0 and fn==0x08 and rs!=31: special['jr_non_ra']+=1
    if op==0x12: special['cop2']+=1
if special!={'break':0,'syscall':0,'jalr':0,'cop2':0,'jr_non_ra':0} or bad_flow:
    raise SystemExit(f'fluxo/instrucoes especiais OVL-002E divergiram: {special}, {bad_flow}')
if external_jals!={0x8015830C,0x8015D718,0x8015E12C}: raise SystemExit(f'JAL externos divergiram: {external_jals}')
ranges=[]
for line in ranges_path.read_text(encoding='utf-8').splitlines():
    parts=line.split()
    if len(parts)==3 and parts[0]=='R': ranges.append((int(parts[1],16),int(parts[1],16)+int(parts[2],16)))
dispatch=dispatch_path.read_text(encoding='utf-8',errors='replace')
if any(not any(a<=target<b for a,b in ranges) or f'0x{target:08X}u' not in dispatch for target in external_jals):
    raise SystemExit('JAL externo fora do codigo estatico S1-261')
prior_ranges=runtime/pathlib.Path(*pathlib.PurePosixPath(manifest['cache_relative']).parts)/'00020000_F943B63B.ranges'
prior=set()
for line in prior_ranges.read_text(encoding='utf-8').splitlines():
    parts=line.split()
    if len(parts)==3 and parts[0]=='R':
        start=int(parts[1],16); prior.update(range(start,start+int(parts[2],16),4))
combined=prior|visited; combined_raw=b''.join(data[x-load:x-load+4] for x in sorted(combined))
if len(prior)!=2143 or prior&visited or len(combined)!=2418: raise SystemExit('sobreposicao/volume cumulativo OVL-002E divergente')
if hashlib.sha256(combined_raw).hexdigest().upper()!='36548803322202BB9F7080F82FDCD5B06CFDD190A1E286D18C611403CD7F4D0A':
    raise SystemExit('hash cumulativo OVL-002E divergente')
previous=['0x80092C2C','0x80093E4C','0x80049568','0x80049808','0x80049988','0x80047DE8']
new=[f'0x{x:08X}' for x in [root,*sorted(aliases)]]; filtered=copy.deepcopy(row)
for key in ('executed_pcs','observed_pcs','dispatch_entry_pcs','seeds'): filtered[key]=previous+new
filtered['function_entry_pcs']=['0x80092138','0x80092524','0x80092740','0x80092800','0x800929D4','0x80092C2C','0x80093BB8']
toml_doc=tomllib.loads(config.read_text(encoding='utf-8'))
seed_lines,audit=co.classify_overlay_seeds(filtered,data,load,len(data),0xF943B63B,toml_doc)
reasons=audit['included_reasons']
if reasons.get(root)!='DISPATCH_ENTRY' or len(reasons)!=26: raise SystemExit(f'classificacao OVL-002E divergente: {reasons}')
if any(reasons.get(alias)!='DISPATCH_INTERIOR' for alias in aliases): raise SystemExit('alias OVL-002E perdeu classificacao interior')
targets=[int(line.split('#',1)[0].split()[1],16) for line in target_path.read_text().splitlines() if line.split('#',1)[0].split()]
if targets!=[root]: raise SystemExit('target OVL-002E divergente')
print('Pre-auditoria OVL-002E: 275 palavras, 1 raiz, 6 aliases, 3 JAL externos estaticos e zero fluxo indireto/COP2/BREAK/SYSCALL.')
PY
}

make_runtime_dir() {
    local suffix candidate; mkdir -p "$PROJECT_ROOT/local/overlay"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/overlay/ovl-002e-test-runtime-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    done
    fail "Nao ha runtime livre para OVL-002E."
}

copy_source_runtime() {
    local dst="$1" file
    cp "$SOURCE_RUNTIME_EXE" "$dst/StreetFighterEXPlusAlphaRecomp.exe"
    for file in input.ini keybinds.ini settings.toml launcher.rml; do [[ -f "$SOURCE_RUNTIME_DIR/$file" ]] && cp "$SOURCE_RUNTIME_DIR/$file" "$dst/$file"; done
    mkdir -p "$dst/cache"; cp -R "$SOURCE_RUNTIME_DIR/cache/." "$dst/cache/"
    cp "$SOURCE_CACHE_MANIFEST" "$dst/ovl-002d-cache-source-manifest.json"
}

derive_capture() {
    "$PYTHON_BIN" - "$SOURCE_CAPTURE_FILE" "$1/ovl-002e-filtered-capture.json" <<'PY'
import base64,binascii,copy,json,pathlib,sys
source=pathlib.Path(sys.argv[1]); output=pathlib.Path(sys.argv[2]); found=[]
for row in json.loads(source.read_text(encoding='utf-8')):
    data=base64.b64decode(row['bytes_b64'])
    if (int(row['load_addr'],0)&0x1fffffff)==0x20000 and (binascii.crc32(data)&0xffffffff)==0xF943B63B: found.append(row)
if len(found)!=1: raise SystemExit('imagem F943B63B nao e unica')
row=copy.deepcopy(found[0])
previous=['0x80092C2C','0x80093E4C','0x80049568','0x80049808','0x80049988','0x80047DE8']
new=['0x80044830','0x8004485C','0x800448EC','0x80044984','0x80044A68','0x80044AF8','0x80044B8C']; observed=previous+new
row['executed_pcs']=observed; row['observed_pcs']=observed[:]; row['dispatch_entry_pcs']=observed[:]
row['function_entry_pcs']=['0x80092138','0x80092524','0x80092740','0x80092800','0x800929D4','0x80092C2C','0x80093BB8']
row['seeds']=observed[:]
row['micro_lot']='OVL-002E cumulative: preserve 2143 words and add only 275-word 0x80044830 family with six aliases'
output.write_text(json.dumps([row],indent=2)+'\n',encoding='utf-8')
print('Captura privada OVL-002E derivada: 17 roots formais, 9 aliases, 2.418 palavras cumulativas.')
PY
}

compile_shard() {
    local dst="$1" log="$1/ovl-002e-compile.log"
    printf '\n==> Compilando shard cumulativo OVL-002E em %s\n' "$CAPTURE_KEY"
    env -u PSX_OVERLAY_CACHE_DIR -u PSX_OVERLAY_CAPTURES "$PYTHON_BIN" "$COMPILE_OVERLAYS" \
        --captures "$dst/ovl-002e-filtered-capture.json" --capture-key "$CAPTURE_KEY" \
        --game-toml "$TEST_CONFIG" --recompiler "$RECOMPILER" --runtime-include "$RUNTIME_INCLUDE" \
        --out-dir "$dst/cache" --gcc "$GCC_BIN" --compiler gcc --cps --jobs 1 --force 2>&1 | tee "$log"
}

audit_cache() {
    "$PYTHON_BIN" - "$1" "$EXPECTED_CACHE_REL" <<'PY'
import hashlib,json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); rel=pathlib.PurePosixPath(sys.argv[2]); cache=root/pathlib.Path(*rel.parts)
source=json.loads((root/'ovl-002d-cache-source-manifest.json').read_text(encoding='utf-8'))
log=(root/'ovl-002e-compile.log').read_text(encoding='utf-8',errors='replace')
if '(0x00020000:0xF943B63B)' not in log or 'Capture filter: 1/' not in log or 'OK ->' not in log: raise SystemExit('ERRO: log nao confirma compilacao filtrada OVL-002E')
if 'SKIP: DLL already exists' in log or re.search(r'(?:RECOMPILER ERROR|GENERATED-C AUDIT FAILED|RANGE AUDIT FAILED|COMPILE ERROR|\bFAILED\b)',log):
    raise SystemExit('ERRO: compilador/auditoria OVL-002E reportou falha')
old={item['path']:item for item in source.get('files',[])}; changed=[]
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
entries=set(); words=set()
for line in (cache/'00020000_F943B63B.ranges').read_text(encoding='utf-8').splitlines():
    parts=line.split()
    if len(parts)==3 and parts[0]=='F': entries.add(int(parts[1],16)&0x1fffffff)
    if len(parts)==3 and parts[0]=='R':
        start=int(parts[1],16); words.update(range(start,start+int(parts[2],16),4))
required={0x00044830,0x0004485C,0x000448EC,0x00044984,0x00044A68,0x00044AF8,0x00044B8C,
          0x00047DE8,0x00049568,0x0004964C,0x000497E4,0x00049808,0x00049988,0x00049B9C,0x00049D24,0x00049E70,0x00049E90,0x00049E9C,
          0x00092138,0x00092524,0x00092740,0x00092800,0x000929D4,0x00092C2C,0x00093BB8,0x00093E4C}
if required-entries: raise SystemExit('roots/aliases cumulativos ausentes: '+','.join(f'0x{x:08X}' for x in sorted(required-entries)))
if {0x00044C7C,0x00047EFC,0x00092F00,0x00094710}&entries: raise SystemExit('candidato fora do microlote entrou no shard')
if len(words)!=2418: raise SystemExit(f'corpo cumulativo tem {len(words)} palavras, esperado 2418')
dlls=sorted(cache.glob('*.dll')); ranges=sorted(cache.glob('*.ranges'))
if not dlls or len(dlls)!=len(ranges): raise SystemExit('inventario cumulativo incompleto')
all_entries=set(); files=[]
for path in ranges:
    for line in path.read_text(encoding='utf-8').splitlines():
        parts=line.split()
        if parts and parts[0]=='F': all_entries.add(int(parts[1],16)&0x1fffffff)
for path in sorted(dlls+ranges,key=lambda item:item.as_posix()):
    files.append({'path':path.relative_to(root).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest().upper(),'size':path.stat().st_size})
(root/'ovl-002e-cache-manifest.json').write_text(json.dumps({
 'track':'OVL-002E-DDARK-BOMB-RESIDUAL-CUMULATIVE','capture_keys':['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F','0x00020000:0xF943B63B'],
 'incremental_words':275,'prior_image_words':2143,'image_body_words':2418,'new_root':'0x80044830',
 'new_aliases':['0x8004485C','0x800448EC','0x80044984','0x80044A68','0x80044AF8','0x80044B8C'],
 'cop2_incremental':0,'cop2_total_image':115,'new_body_sha256':'ADF1F024D3646B2AF044CB439C53284B520B9284524912C1013001CB8FBCBC53',
 'cumulative_body_sha256':'36548803322202BB9F7080F82FDCD5B06CFDD190A1E286D18C611403CD7F4D0A',
 'cache_relative':rel.as_posix(),'dll_count':len(dlls),'ranges_count':len(ranges),'unique_entries':len(all_entries),
 'replaced_source_files':sorted(changed),'files':files},indent=2,sort_keys=True)+'\n',encoding='utf-8')
print(f'Cache OVL-002E auditado: {len(dlls)} DLL(s), {len(all_entries)} entradas e 2.418 palavras na imagem F943B63B.')
PY
}

write_state() {
    local dst="$1"; umask 077
    {
        printf 'runtime_dir=%s\nruntime_exe=%s\ntest_config=%s\ncache_manifest=%s\n' "$dst" "$dst/StreetFighterEXPlusAlphaRecomp.exe" "$TEST_CONFIG" "$dst/ovl-002e-cache-manifest.json"
        printf 'capture_key=%s\nimage_sha256=%s\ntarget=0x80044830\n' "$CAPTURE_KEY" "$EXPECTED_IMAGE_SHA"
        printf 'alias_1=0x8004485C\nalias_2=0x800448EC\nalias_3=0x80044984\nalias_4=0x80044A68\nalias_5=0x80044AF8\nalias_6=0x80044B8C\n'
        printf 'incremental_words=275\nprior_words=2143\nimage_body_words=2418\ncop2_incremental=0\ncop2_total_image=115\n'
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
    printf '\nOVL-002E criada em runtime experimental isolado. O executavel principal nao foi recompilado.\n'
    printf 'Abra com:\n  bash tools/run_ovl_002e_test.sh\n\nDepois, no Mode Select:\n  bash tools/telemetry_before_after_ovl_002e.sh prepare\n'
}

main "$@"
