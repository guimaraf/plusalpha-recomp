#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly SOURCE_STATE="$PROJECT_ROOT/local/overlay/.ovl-002a-current-runtime.state"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002b-current-runtime.state"
readonly TELEMETRY_STATE="$PROJECT_ROOT/local/telemetry/.ovl-002b-test-active.state"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002b_test.toml"
readonly TARGET_FILE="$PROJECT_ROOT/seeds/ovl_002b_target_pcs.txt"
readonly COMPILE_OVERLAYS="$REPO_ROOT/psxrecomp/tools/compile_overlays.py"
readonly RECOMPILER="$REPO_ROOT/psxrecomp/recompiler/build/psxrecomp-game.exe"
readonly RUNTIME_INCLUDE="$REPO_ROOT/psxrecomp/runtime/include"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly DISPATCH_FILE="$PROJECT_ROOT/generated/SLUS_005.48_dispatch.c"
readonly GCC_BIN=/ucrt64/bin/gcc.exe
readonly RUNTIME_PARENT="$PROJECT_ROOT/local/overlay"
readonly CAPTURE_KEY=0x00020000:0xF943B63B
readonly EXPECTED_IMAGE_SHA=603A2A697D5CCCE74E6AFF3E4A5621F868C587E896410BC68A5275F01E57F3BF
readonly EXPECTED_NEW_SHA=F355D348E55F4E41FCF4211A355F59B00DB135C77C0D374A73F0E47C65D13E01
readonly EXPECTED_PRIOR_SHA=A02CD4A887B4CC31A81BE9815A007D51635070447FBE5F5200188DEA2003A5DC
readonly EXPECTED_CUMULATIVE_SHA=4C4FAFE76654E302D0F542AB03DD167B3D4D7B19DCBD2A30FB0E30CCB7F893B6
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

  bash tools/compile_ovl_002b_test_runtime.sh

O script copia o runtime OVL-002A aprovado e recompila somente a imagem
F943B63B de forma cumulativa: preserva as 226 palavras da OVL-002A e acrescenta
as 882 palavras da OVL-002B. Nao recompila o executavel principal, nao gera
fontes S1 e nao altera BIOS, entry_funcs.txt ou generated/. A recompilacao do
shard selecionado e forcada porque a copia-base ja contem o DLL da OVL-002A.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_source_runtime() {
    [[ -f "$SOURCE_STATE" ]] || fail "Runtime OVL-002A ausente."
    SOURCE_RUNTIME_DIR="$(state_value "$SOURCE_STATE" runtime_dir)"
    SOURCE_RUNTIME_EXE="$(state_value "$SOURCE_STATE" runtime_exe)"
    SOURCE_CACHE_MANIFEST="$(state_value "$SOURCE_STATE" cache_manifest)"
    local capture_runtime
    capture_runtime="$(state_value "$SOURCE_STATE" source_runtime)"
    SOURCE_CAPTURE_FILE="$capture_runtime/overlay_captures.json"
    case "$SOURCE_RUNTIME_DIR" in
        "$PROJECT_ROOT"/local/overlay/ovl-002a-test-runtime-*) ;;
        *) fail "Estado OVL-002A aponta para runtime invalido." ;;
    esac
    case "$capture_runtime" in
        "$PROJECT_ROOT"/local/overlay/ovl-001b-test-runtime-*) ;;
        *) fail "Origem da captura F943B63B invalida." ;;
    esac
    [[ "$(state_value "$SOURCE_STATE" capture_key)" == "$CAPTURE_KEY" ]] || fail "Chave OVL-002A divergente."
    [[ "$(state_value "$SOURCE_STATE" owner_root)" == 0x80093BB8 ]] || fail "Raiz OVL-002A divergente."
    [[ "$(state_value "$SOURCE_STATE" dispatch_interior)" == 0x80093E4C ]] || fail "Alias OVL-002A divergente."
}

validate_inputs() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep cp mkdir seq tee env; do
        command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado no UCRT64."
    done
    select_python
    [[ ! -f "$TELEMETRY_STATE" ]] || fail "Existe uma coleta OVL-002B ativa."
    read_source_runtime
    for file in "$SOURCE_RUNTIME_EXE" "$SOURCE_CACHE_MANIFEST" "$SOURCE_CAPTURE_FILE" \
                "$TEST_CONFIG" "$TARGET_FILE" "$COMPILE_OVERLAYS" "$RECOMPILER" \
                "$RUNTIME_INCLUDE/psx_runtime.h" "$RANGES_FILE" "$DISPATCH_FILE" "$GCC_BIN"; do
        [[ -f "$file" ]] || fail "Arquivo obrigatorio ausente: $file"
    done
    [[ "$(sha256sum "$SOURCE_RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] ||
        fail "Executavel-base OVL-002A divergiu."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] ||
        fail "Ranges do EXE principal divergiram do checkpoint S1-261."
    [[ "$(sha256sum "$RECOMPILER" | awk '{print toupper($1)}')" == "$EXPECTED_RECOMPILER_SHA" ]] ||
        fail "Recompilador divergiu do binario pre-auditado."
    grep -Eq '^[[:space:]]*overlay_cache[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$TEST_CONFIG" ||
        fail "A config OVL-002B nao habilita overlay_cache."
    ! grep -Eq '^[[:space:]]*overlay_autocompile_cmd(_tcc)?[[:space:]]*=' "$TEST_CONFIG" ||
        fail "Autocompilacao nao e permitida."

    "$PYTHON_BIN" - "$SOURCE_RUNTIME_DIR" "$SOURCE_CACHE_MANIFEST" "$SOURCE_CAPTURE_FILE" \
        "$TEST_CONFIG" "$COMPILE_OVERLAYS" "$TARGET_FILE" "$RANGES_FILE" "$DISPATCH_FILE" <<'PY'
import base64,binascii,copy,hashlib,importlib.util,json,pathlib,struct,sys,tomllib
runtime=pathlib.Path(sys.argv[1]); manifest_path=pathlib.Path(sys.argv[2]); capture_path=pathlib.Path(sys.argv[3])
config=pathlib.Path(sys.argv[4]); compiler=pathlib.Path(sys.argv[5]); target_path=pathlib.Path(sys.argv[6])
ranges_path=pathlib.Path(sys.argv[7]); dispatch_path=pathlib.Path(sys.argv[8])
manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
if manifest.get('track')!='OVL-002A-DDARK-CUMULATIVE': raise SystemExit('cache-base nao e OVL-002A aprovado')
if manifest.get('capture_keys')!=['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F','0x00020000:0xF943B63B']:
    raise SystemExit('chaves do cache-base divergiram')
if int(manifest.get('body_words',0))!=226: raise SystemExit('corpo OVL-002A divergente')
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
if len(data)!=860160 or hashlib.sha256(data).hexdigest().upper()!='603A2A697D5CCCE74E6AFF3E4A5621F868C587E896410BC68A5275F01E57F3BF':
    raise SystemExit('imagem F943B63B divergente')
new_body=data[0x80092138-load:0x80092F00-load]
prior_body=data[0x80093BB8-load:0x80093F40-load]
if len(new_body)!=3528 or hashlib.sha256(new_body).hexdigest().upper()!='F355D348E55F4E41FCF4211A355F59B00DB135C77C0D374A73F0E47C65D13E01':
    raise SystemExit('corpo incremental OVL-002B divergente')
if len(prior_body)!=904 or hashlib.sha256(prior_body).hexdigest().upper()!='A02CD4A887B4CC31A81BE9815A007D51635070447FBE5F5200188DEA2003A5DC':
    raise SystemExit('corpo aprovado OVL-002A divergente')
if hashlib.sha256(new_body+prior_body).hexdigest().upper()!='4C4FAFE76654E302D0F542AB03DD167B3D4D7B19DCBD2A30FB0E30CCB7F893B6':
    raise SystemExit('hash cumulativo A+B divergente')
new_roots=[0x80092138,0x80092524,0x80092740,0x80092800,0x800929D4,0x80092C2C]
all_roots=new_roots+[0x80093BB8]
filtered=copy.deepcopy(row)
filtered['executed_pcs']=['0x80092C2C','0x80093E4C']; filtered['observed_pcs']=filtered['executed_pcs'][:]
filtered['dispatch_entry_pcs']=filtered['executed_pcs'][:]
filtered['function_entry_pcs']=[f'0x{x:08X}' for x in all_roots]; filtered['seeds']=filtered['executed_pcs'][:]
spec=importlib.util.spec_from_file_location('compile_overlays_preaudit',compiler)
co=importlib.util.module_from_spec(spec); spec.loader.exec_module(co)
toml_doc=tomllib.loads(config.read_text(encoding='utf-8'))
_,audit=co.classify_overlay_seeds(filtered,data,load,len(data),0xF943B63B,toml_doc)
expected_reasons={**{x:'FUNCTION_POINTER_TARGET' for x in all_roots},0x80092C2C:'DISPATCH_ENTRY',0x80093E4C:'DISPATCH_INTERIOR'}
if audit['included_reasons']!=expected_reasons: raise SystemExit(f'classificacao cumulativa divergente: {audit["included_reasons"]}')
bounds=[0x80092524,0x80092740,0x80092800,0x800929D4,0x80092C2C,0x80092F00]
counts=[251,135,48,117,150,181]
hashes=['7768292DD1C1AA1077CA34DC89E57FA1DCD988B61E3169ED4890B3CB7877D291','CC309F0A92FD7D97BE39AB9D37519AAD684E4654946C2A1147A2CF1B8063E975','79514577D32E4357A26A7D2241543869282C8DA278ECE07E6BD280AC7D6234E8','8D86D93AAD5E18FB95EEF98263A3A1FB5558016B4D46A8BB98B9A4499766A5AE','43B267F40F08E3FCA8AA1113CFED806DA2AE002333033D5D6AA231CED3AA7F31','29F21B590D2CCA11848C1E8288E9EC52FA2623B0EA1BF7E0D360311EB23B0452']
visited=set(); direct=set(); tables=set()
for root,bound,count,expected_hash in zip(new_roots,bounds,counts,hashes):
    walk=co._walk_overlay_function(data,load,len(data),root,bound)
    if len(walk['visited'])!=count: raise SystemExit(f'closure 0x{root:08X}: {len(walk["visited"])} != {count}')
    blob=b''.join(data[pc-load:pc-load+4] for pc in sorted(walk['visited']))
    if hashlib.sha256(blob).hexdigest().upper()!=expected_hash: raise SystemExit(f'hash da raiz 0x{root:08X} divergente')
    visited.update(walk['visited']); direct.update(walk['direct_jals']); tables.update(walk['jump_table_targets'])
old_walk=co._walk_overlay_function(data,load,len(data),0x80093BB8,0x80093F40)
visited.update(old_walk['visited']); direct.update(old_walk['direct_jals']); tables.update(old_walk['jump_table_targets'])
if len(visited)!=1108 or tables: raise SystemExit('closure cumulativa nao e exatamente 1.108 palavras sem jump table')
special={'break':0,'syscall':0,'cop2':0,'jalr':0}; external=[]
for pc in sorted(visited):
    word=struct.unpack_from('<I',data,pc-load)[0]; op=word>>26; fn=word&0x3f
    if op==0 and fn==0x0D: special['break']+=1
    if op==0 and fn==0x0C: special['syscall']+=1
    if op==0 and fn==0x09: special['jalr']+=1
    if op==0x12: special['cop2']+=1
    if op==3:
        target=((pc+4)&0xF0000000)|((word&0x03FFFFFF)<<2)
        if target not in visited: external.append(target)
if special!={'break':0,'syscall':0,'cop2':80,'jalr':0}: raise SystemExit(f'instrucoes especiais divergiram: {special}')
expected_external={0x8010C72C,0x801938B0,0x8019497C,0x8019CB60,0x8019DBE8,0x8019E440}
if set(external)!=expected_external: raise SystemExit(f'JAL externos divergiram: {[hex(x) for x in sorted(set(external))]}')
ranges=[]
for line in ranges_path.read_text(encoding='utf-8').splitlines():
    p=line.split()
    if len(p)==3 and p[0]=='R': ranges.append((int(p[1],16),int(p[1],16)+int(p[2],16)))
if any(not any(a<=target<b for a,b in ranges) for target in expected_external): raise SystemExit('JAL externo fora dos ranges S1-261')
dispatch=dispatch_path.read_text(encoding='utf-8',errors='replace')
if any(f'0x{target:08X}u' not in dispatch for target in expected_external): raise SystemExit('JAL externo ausente do dispatch estatico')
targets=[]
for line in target_path.read_text(encoding='utf-8').splitlines():
    p=line.split('#',1)[0].split()
    if p: targets.append(int(p[1],16))
if targets!=[0x80092C2C]: raise SystemExit('target OVL-002B deve conter somente 0x80092C2C')
if {0x80092F00,0x80047DE8}&set(audit['included_reasons']): raise SystemExit('alvo em quarentena entrou no lote')
print('Pre-auditoria OVL-002B: +882 palavras, 7 roots cumulativas, 80 COP2 totais, zero BREAK/JALR/jump table.')
PY
}

make_runtime_dir() {
    local suffix candidate
    mkdir -p "$RUNTIME_PARENT"
    for suffix in $(seq -w 1 99); do
        candidate="$RUNTIME_PARENT/ovl-002b-test-runtime-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    done
    fail "Nao ha runtime livre para OVL-002B."
}

copy_source_runtime() {
    local runtime_dir="$1" file
    cp "$SOURCE_RUNTIME_EXE" "$runtime_dir/StreetFighterEXPlusAlphaRecomp.exe"
    for file in input.ini keybinds.ini settings.toml launcher.rml; do
        [[ -f "$SOURCE_RUNTIME_DIR/$file" ]] && cp "$SOURCE_RUNTIME_DIR/$file" "$runtime_dir/$file"
    done
    mkdir -p "$runtime_dir/cache"
    cp -R "$SOURCE_RUNTIME_DIR/cache/." "$runtime_dir/cache/"
    cp "$SOURCE_CACHE_MANIFEST" "$runtime_dir/ovl-002a-cache-source-manifest.json"
}

derive_capture() {
    local runtime_dir="$1" output="$runtime_dir/ovl-002b-filtered-capture.json"
    "$PYTHON_BIN" - "$SOURCE_CAPTURE_FILE" "$output" <<'PY'
import base64,binascii,copy,json,pathlib,sys
source=pathlib.Path(sys.argv[1]); output=pathlib.Path(sys.argv[2]); found=[]
for row in json.loads(source.read_text(encoding='utf-8')):
    data=base64.b64decode(row['bytes_b64'])
    if (int(row['load_addr'],0)&0x1fffffff)==0x20000 and (binascii.crc32(data)&0xffffffff)==0xF943B63B:
        found.append(row)
if len(found)!=1: raise SystemExit(f'imagem F943B63B aparece {len(found)} vez(es)')
row=copy.deepcopy(found[0])
row['executed_pcs']=['0x80092C2C','0x80093E4C']; row['observed_pcs']=row['executed_pcs'][:]
row['dispatch_entry_pcs']=row['executed_pcs'][:]
row['function_entry_pcs']=['0x80092138','0x80092524','0x80092740','0x80092800','0x800929D4','0x80092C2C','0x80093BB8']
row['seeds']=row['executed_pcs'][:]
row['micro_lot']='OVL-002B cumulative: preserve OVL-002A 226 words + add 0x80092C2C closure 882 words'
output.write_text(json.dumps([row],indent=2)+'\n',encoding='utf-8')
print('Captura privada OVL-002B derivada: sete roots, dois dispatch PCs, 1.108 palavras cumulativas.')
PY
}

compile_shard() {
    local runtime_dir="$1" log="$runtime_dir/ovl-002b-compile.log"
    printf '\n==> Compilando OVL-002A+002B na imagem %s\n' "$CAPTURE_KEY"
    env -u PSX_OVERLAY_CACHE_DIR -u PSX_OVERLAY_CAPTURES \
        "$PYTHON_BIN" "$COMPILE_OVERLAYS" \
        --captures "$runtime_dir/ovl-002b-filtered-capture.json" --capture-key "$CAPTURE_KEY" \
        --game-toml "$TEST_CONFIG" --recompiler "$RECOMPILER" \
        --runtime-include "$RUNTIME_INCLUDE" --out-dir "$runtime_dir/cache" \
        --gcc "$GCC_BIN" --compiler gcc --cps --jobs 1 --force 2>&1 | tee "$log"
}

audit_combined_cache() {
    local runtime_dir="$1"
    "$PYTHON_BIN" - "$runtime_dir" "$TARGET_FILE" "$CAPTURE_KEY" "$EXPECTED_CACHE_REL" <<'PY'
import hashlib,json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); targets_path=pathlib.Path(sys.argv[2]); key=sys.argv[3]
expected_rel=pathlib.PurePosixPath(sys.argv[4]); cache=root/pathlib.Path(*expected_rel.parts)
source=json.loads((root/'ovl-002a-cache-source-manifest.json').read_text(encoding='utf-8'))
log=(root/'ovl-002b-compile.log').read_text(encoding='utf-8',errors='replace')
if f'({key})' not in log or 'Capture filter: 1/' not in log: raise SystemExit('ERRO: log nao confirma filtro OVL-002B exato')
if 'SKIP: DLL already exists' in log: raise SystemExit('ERRO: shard F943B63B foi pulado; --force nao foi aplicado')
if 'OK ->' not in log: raise SystemExit('ERRO: log nao confirma a compilacao do shard F943B63B')
if re.search(r'(?:RECOMPILER ERROR|GENERATED-C AUDIT FAILED|RANGE AUDIT FAILED|COMPILE ERROR|\bFAILED\b)',log):
    raise SystemExit('ERRO: compilador/auditoria OVL-002B reportou falha')
old={item['path']:item for item in source.get('files',[])}; changed=[]
for rel,item in old.items():
    path=root/pathlib.Path(*pathlib.PurePosixPath(rel).parts)
    if not path.is_file(): raise SystemExit(f'cache-base ausente: {rel}')
    now=hashlib.sha256(path.read_bytes()).hexdigest().upper()
    if 'F943B63B' in rel:
        if now!=item['sha256'] or path.stat().st_size!=int(item['size']): changed.append(rel)
    elif now!=item['sha256'] or path.stat().st_size!=int(item['size']):
        raise SystemExit(f'artefato anterior fora de F943B63B foi alterado: {rel}')
for suffix in ('.dll','.ranges'):
    if not (cache/f'00020000_F943B63B{suffix}').is_file(): raise SystemExit(f'shard OVL-002B ausente: {suffix}')
if not any(p.endswith('.dll') for p in changed) or not any(p.endswith('.ranges') for p in changed):
    raise SystemExit('DLL/ranges F943B63B nao foram ambos substituidos cumulativamente')
dlls=sorted(cache.glob('*.dll')); manifests=sorted(cache.glob('*.ranges'))
if not dlls or len(dlls)!=len(manifests): raise SystemExit('inventario cumulativo incompleto')
entries=set(); image_entries=set(); f_lines=0
for path in manifests:
    if not path.with_suffix('.dll').is_file(): raise SystemExit(f'DLL ausente para {path.name}')
    for line in path.read_text(encoding='utf-8').splitlines():
        p=line.split()
        if p and p[0]=='F':
            entry=int(p[1],16)&0x1fffffff; f_lines+=1; entries.add(entry)
            if path.name=='00020000_F943B63B.ranges': image_entries.add(entry)
required={0x00092138,0x00092524,0x00092740,0x00092800,0x000929D4,0x00092C2C,0x00093BB8,0x00093E4C}
if required-image_entries: raise SystemExit('boundaries/alias cumulativos ausentes do shard F943B63B: '+','.join(f'0x{x:08X}' for x in sorted(required-image_entries)))
if {0x00092F00,0x00047DE8}&image_entries: raise SystemExit('alvo excluido entrou no shard F943B63B')
targets=[]
for line in targets_path.read_text(encoding='utf-8').splitlines():
    p=line.split('#',1)[0].split()
    if p: targets.append(int(p[1],16)&0x1fffffff)
if targets!=[0x00092C2C] or set(targets)-image_entries: raise SystemExit('gate dinamico OVL-002B divergente')
files=[]
for path in sorted(dlls+manifests,key=lambda p:p.as_posix()):
    files.append({'path':path.relative_to(root).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest().upper(),'size':path.stat().st_size})
(root/'ovl-002b-cache-manifest.json').write_text(json.dumps({
    'track':'OVL-002B-DDARK-CUMULATIVE','capture_keys':['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F',key],
    'incremental_words':882,'prior_ovl002a_words':226,'image_body_words':1108,
    'new_roots':['0x80092138','0x80092524','0x80092740','0x80092800','0x800929D4','0x80092C2C'],
    'prior_root':'0x80093BB8','prior_alias':'0x80093E4C','cop2_incremental':71,'cop2_total_image':80,
    'cache_relative':expected_rel.as_posix(),'dll_count':len(dlls),'ranges_count':len(manifests),
    'manifest_f_lines':f_lines,'unique_entries':len(entries),'replaced_source_files':sorted(changed),'files':files
},indent=2,sort_keys=True)+'\n',encoding='utf-8')
print(f'Cache OVL-002B auditado: {len(dlls)} DLL(s), {len(entries)} entradas; OVL-002A preservada e +882 palavras presentes.')
PY
}

write_state() {
    local runtime_dir="$1"
    umask 077
    {
        printf 'runtime_dir=%s\n' "$runtime_dir"
        printf 'runtime_exe=%s\n' "$runtime_dir/StreetFighterEXPlusAlphaRecomp.exe"
        printf 'test_config=%s\n' "$TEST_CONFIG"
        printf 'cache_manifest=%s\n' "$runtime_dir/ovl-002b-cache-manifest.json"
        printf 'capture_key=%s\nimage_sha256=%s\n' "$CAPTURE_KEY" "$EXPECTED_IMAGE_SHA"
        printf 'incremental_sha256=%s\nprior_sha256=%s\ncumulative_sha256=%s\n' \
            "$EXPECTED_NEW_SHA" "$EXPECTED_PRIOR_SHA" "$EXPECTED_CUMULATIVE_SHA"
        printf 'target=0x80092C2C\nprior_root=0x80093BB8\nprior_alias=0x80093E4C\n'
        printf 'incremental_words=882\nprior_words=226\nimage_body_words=1108\n'
        printf 'cop2_incremental=71\ncop2_total_image=80\n'
        printf 'runtime_exe_sha256=%s\nranges_sha256=%s\nrecompiler_sha256=%s\ncodegen_hash=%s\n' \
            "$EXPECTED_EXE_SHA" "$EXPECTED_RANGES_SHA" "$EXPECTED_RECOMPILER_SHA" "$EXPECTED_CODEGEN_HASH"
        printf 'source_runtime=%s\nsource_capture=%s\ncreated_utc=%s\n' \
            "$SOURCE_RUNTIME_DIR" "$SOURCE_CAPTURE_FILE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
    printf '\nOVL-002B compilada em runtime cumulativo isolado. O executavel principal nao foi recompilado.\n'
    printf 'Abra o jogo com:\n\n  bash tools/run_ovl_002b_test.sh\n\n'
    printf 'Depois, ainda no Mode Select, execute:\n  bash tools/telemetry_before_after_ovl_002b.sh prepare\n'
}

main "$@"
