#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly SOURCE_STATE="$PROJECT_ROOT/local/overlay/.ovl-002g-current-runtime.state"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002h-current-runtime.state"
readonly TELEMETRY_STATE="$PROJECT_ROOT/local/telemetry/.ovl-002h-test-active.state"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002h_test.toml"
readonly TARGET_FILE="$PROJECT_ROOT/seeds/ovl_002h_target_pcs.txt"
readonly COMPILE_OVERLAYS="$REPO_ROOT/psxrecomp/tools/compile_overlays.py"
readonly RECOMPILER="$REPO_ROOT/psxrecomp/recompiler/build/psxrecomp-game.exe"
readonly RUNTIME_INCLUDE="$REPO_ROOT/psxrecomp/runtime/include"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly DISPATCH_FILE="$PROJECT_ROOT/generated/SLUS_005.48_dispatch.c"
readonly GCC_BIN=/ucrt64/bin/gcc.exe
readonly CAPTURE_KEY=0x00020000:0xF943B63B
readonly EXPECTED_IMAGE_SHA=603A2A697D5CCCE74E6AFF3E4A5621F868C587E896410BC68A5275F01E57F3BF
readonly EXPECTED_PRIMARY_SHA=E35BE10F7BA889CED32DD5A0AD6CE8C505E562E9634B811B5801D3CCCEAF0466
readonly EXPECTED_HELPER_SHA=47E3896F16BADCFF45B7D5871ED3A486938A05EA9FC760A96086EFFB0E666E21
readonly EXPECTED_NEW_SHA=06177D4AB270F914DDD1B3D0FDCED67009A95623231DAFA17CC6CE042D356825
readonly EXPECTED_CUMULATIVE_SHA=34F2CF64C7D2D74E231A65A7D7F58F48C1097CBF9DA6870DF0C66FB33A42E92E
readonly EXPECTED_TABLE_SHA=6CFA63DD09A9FB9B111F6B57D76865F17A595AB155DAD5DCDBEBF3CAB3489206
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

  bash tools/compile_ovl_002h_test_runtime.sh

Preserva as 2.563 palavras OVL-002G e acrescenta uma closure de 239 palavras:
0x800465A8..0x80046933 e o helper 0x80047DB8..0x80047DE7.
O limite rigido predefinido e 252 palavras. 0x80046934 permanece fora.
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
    [[ -f "$SOURCE_STATE" ]] || fail "Runtime OVL-002G aprovado ausente."
    SOURCE_RUNTIME_DIR="$(state_value "$SOURCE_STATE" runtime_dir)"
    SOURCE_RUNTIME_EXE="$(state_value "$SOURCE_STATE" runtime_exe)"
    SOURCE_CACHE_MANIFEST="$(state_value "$SOURCE_STATE" cache_manifest)"
    SOURCE_CAPTURE_FILE="$SOURCE_RUNTIME_DIR/ovl-002g-filtered-capture.json"
    case "$SOURCE_RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002g-test-runtime-*) ;; *) fail "Estado OVL-002G invalido." ;; esac
    [[ "$(state_value "$SOURCE_STATE" capture_key)" == "$CAPTURE_KEY" ]] || fail "Chave OVL-002G divergente."
    [[ "$(state_value "$SOURCE_STATE" target)" == 0x80045E30 ]] || fail "Raiz OVL-002G divergente."
    [[ "$(state_value "$SOURCE_STATE" image_body_words)" == 2563 ]] || fail "Corpo OVL-002G divergente."
}

validate_inputs() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep cp mkdir seq tee env; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python; read_source_state
    [[ ! -f "$TELEMETRY_STATE" ]] || fail "Existe coleta OVL-002H ativa."
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
if manifest.get('track')!='OVL-002G-DDARK-BOMB-HANDLER-CUMULATIVE' or int(manifest.get('image_body_words',0))!=2563:
    raise SystemExit('cache-base nao e OVL-002G aprovado')
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
root,end=0x800465A8,0x80046934; helper,helper_end=0x80047DB8,0x80047DE8
if struct.unpack_from('<II',data,root-load-8)!=(0x03E00008,0) or struct.unpack_from('<I',data,end-load)[0]!=0x3C02801F:
    raise SystemExit('boundary principal OVL-002H divergente')
if struct.unpack_from('<II',data,helper-load-8)!=(0x03E00008,0) or struct.unpack_from('<I',data,helper_end-load)[0]!=0x90830004:
    raise SystemExit('boundary do helper OVL-002H divergente')
walk=co._walk_overlay_function(data,load,len(data),root,end); helper_walk=co._walk_overlay_function(data,load,len(data),helper,helper_end)
primary=set(walk['visited']); helper_words=set(helper_walk['visited']); closure=primary|helper_words
if primary!=set(range(root,end,4)) or len(primary)!=227 or helper_words!=set(range(helper,helper_end,4)) or len(helper_words)!=12:
    raise SystemExit('closure OVL-002H excedeu o limite ou perdeu palavras')
if len(closure)!=239 or len(closure)>252: raise SystemExit(f'closure OVL-002H invalida: {len(closure)} palavras')
primary_raw=b''.join(data[x-load:x-load+4] for x in sorted(primary)); helper_raw=b''.join(data[x-load:x-load+4] for x in sorted(helper_words))
closure_raw=b''.join(data[x-load:x-load+4] for x in sorted(closure))
if hashlib.sha256(primary_raw).hexdigest().upper()!='E35BE10F7BA889CED32DD5A0AD6CE8C505E562E9634B811B5801D3CCCEAF0466': raise SystemExit('SHA principal divergente')
if hashlib.sha256(helper_raw).hexdigest().upper()!='47E3896F16BADCFF45B7D5871ED3A486938A05EA9FC760A96086EFFB0E666E21': raise SystemExit('SHA helper divergente')
if hashlib.sha256(closure_raw).hexdigest().upper()!='06177D4AB270F914DDD1B3D0FDCED67009A95623231DAFA17CC6CE042D356825': raise SystemExit('SHA closure divergente')
jump_targets={0x80046634,0x80046704,0x80046810,0x800468A0,0x800468CC,0x80046920}
if walk['direct_jals']!={helper} or walk['jump_table_targets']!=jump_targets or helper_walk['direct_jals'] or helper_walk['jump_table_targets']:
    raise SystemExit('dependencia/tabela OVL-002H divergente')
table=struct.unpack_from('<18I',data,0x8004A610-load); table_raw=struct.pack('<18I',*table)
if set(table)!=jump_targets or hashlib.sha256(table_raw).hexdigest().upper()!='6CFA63DD09A9FB9B111F6B57D76865F17A595AB155DAD5DCDBEBF3CAB3489206':
    raise SystemExit('tabela local OVL-002H divergente')
special={'break':0,'syscall':0,'jalr':0,'cop2':0,'jr_non_ra':0}; local_jals=set(); external_jals=set(); bad=[]; jr=set()
for pc in closure:
    word=struct.unpack_from('<I',data,pc-load)[0]; op=word>>26; fn=word&0x3f; rs=(word>>21)&0x1f
    kind,target=co._classify_cf(pc,word)
    if kind=='jal': (local_jals if load<=target<load+len(data) else external_jals).add(target)
    if kind in ('j','branch') and target not in closure: bad.append((pc,target))
    if op==0 and fn==0x0d: special['break']+=1
    if op==0 and fn==0x0c: special['syscall']+=1
    if op==0 and fn==0x09: special['jalr']+=1
    if op==0 and fn==0x08 and rs!=31: special['jr_non_ra']+=1; jr.add(pc)
    if op==0x12: special['cop2']+=1
expected_external={0x801154EC,0x80115574,0x8011618C,0x80123BA8,0x80159E44,0x80159F18,0x8015A0E8,0x8015A180,0x8015A428,0x8015AFEC,0x8015E12C,0x80168788}
if special!={'break':0,'syscall':0,'jalr':0,'cop2':0,'jr_non_ra':1} or jr!={0x8004662C} or local_jals!={helper} or external_jals!=expected_external or bad:
    raise SystemExit(f'fluxo OVL-002H divergente: {special}, {jr}, {local_jals}, {external_jals}, {bad}')
ranges=[]
for line in ranges_path.read_text(encoding='utf-8').splitlines():
    parts=line.split()
    if len(parts)==3 and parts[0]=='R': ranges.append((int(parts[1],16),int(parts[1],16)+int(parts[2],16)))
dispatch=dispatch_path.read_text(encoding='utf-8',errors='replace')
if any(not any(a<=target<b for a,b in ranges) or f'0x{target:08X}u' not in dispatch for target in external_jals):
    raise SystemExit('JAL externo fora do codigo estatico S1-261')
prior_ranges=runtime/pathlib.Path(*pathlib.PurePosixPath(manifest['cache_relative']).parts)/'00020000_F943B63B.ranges'; prior=set()
for line in prior_ranges.read_text(encoding='utf-8').splitlines():
    parts=line.split()
    if len(parts)==3 and parts[0]=='R':
        start=int(parts[1],16); prior.update(range(start,start+int(parts[2],16),4))
combined=prior|closure; combined_raw=b''.join(data[x-load:x-load+4] for x in sorted(combined))
if len(prior)!=2563 or prior&closure or len(combined)!=2802: raise SystemExit('sobreposicao/volume cumulativo OVL-002H divergente')
if hashlib.sha256(combined_raw).hexdigest().upper()!='34F2CF64C7D2D74E231A65A7D7F58F48C1097CBF9DA6870DF0C66FB33A42E92E':
    raise SystemExit('SHA cumulativo OVL-002H divergente')
aliases=[0x80046634,0x800466A8,0x800466D8,0x800466FC,0x80046704,0x80046710,0x80046724,0x800467BC,
         0x80046810,0x8004681C,0x80046830,0x800468A0,0x800468CC,0x800468EC,0x800468F8,0x80046920,0x80047DD8]
filtered=copy.deepcopy(row)
for key in ('executed_pcs','observed_pcs','dispatch_entry_pcs','seeds'):
    filtered[key]=list(filtered.get(key,[]))+[f'0x{x:08X}' for x in [root,*aliases]]
toml_doc=tomllib.loads(config.read_text(encoding='utf-8')); _,audit=co.classify_overlay_seeds(filtered,data,load,len(data),0xF943B63B,toml_doc)
reasons=audit['included_reasons']; expected={root:'DISPATCH_ENTRY',helper:'DIRECT_JAL_TARGET',**{a:'DISPATCH_INTERIOR' for a in aliases}}
if len(reasons)!=57 or any(reasons.get(addr)!=reason for addr,reason in expected.items()):
    raise SystemExit(f'classificacao OVL-002H divergente: {reasons}')
targets=[int(line.split('#',1)[0].split()[1],16) for line in target_path.read_text().splitlines() if line.split('#',1)[0].split()]
if targets!=[root,*aliases]: raise SystemExit('targets OVL-002H divergentes')
print('Pre-auditoria OVL-002H: limite 252; closure 239; 2 funcoes; 17 aliases; tabela de 18 slots; 12 JAL externos nativos.')
PY
}

make_runtime_dir() {
    local suffix candidate; mkdir -p "$PROJECT_ROOT/local/overlay"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/overlay/ovl-002h-test-runtime-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    done
    fail "Nao ha runtime livre para OVL-002H."
}

copy_source_runtime() {
    local dst="$1" file
    cp "$SOURCE_RUNTIME_EXE" "$dst/StreetFighterEXPlusAlphaRecomp.exe"
    for file in input.ini keybinds.ini settings.toml launcher.rml; do [[ -f "$SOURCE_RUNTIME_DIR/$file" ]] && cp "$SOURCE_RUNTIME_DIR/$file" "$dst/$file"; done
    mkdir -p "$dst/cache"; cp -R "$SOURCE_RUNTIME_DIR/cache/." "$dst/cache/"
    cp "$SOURCE_CACHE_MANIFEST" "$dst/ovl-002g-cache-source-manifest.json"
}

derive_capture() {
    "$PYTHON_BIN" - "$SOURCE_CAPTURE_FILE" "$1/ovl-002h-filtered-capture.json" <<'PY'
import base64,binascii,copy,json,pathlib,sys
source=pathlib.Path(sys.argv[1]); output=pathlib.Path(sys.argv[2]); found=[]
for row in json.loads(source.read_text(encoding='utf-8')):
    data=base64.b64decode(row['bytes_b64'])
    if (int(row['load_addr'],0)&0x1fffffff)==0x20000 and (binascii.crc32(data)&0xffffffff)==0xF943B63B: found.append(row)
if len(found)!=1: raise SystemExit('imagem F943B63B nao e unica')
row=copy.deepcopy(found[0])
new=['0x800465A8','0x80046634','0x800466A8','0x800466D8','0x800466FC','0x80046704','0x80046710','0x80046724',
     '0x800467BC','0x80046810','0x8004681C','0x80046830','0x800468A0','0x800468CC','0x800468EC','0x800468F8',
     '0x80046920','0x80047DD8']
for key in ('executed_pcs','observed_pcs','dispatch_entry_pcs','seeds'): row[key]=list(row.get(key,[]))+new
row['micro_lot']='OVL-002H cumulative: preserve 2563 words; add 239-word closure rooted at 0x800465A8; 0x80046934 excluded'
output.write_text(json.dumps([row],indent=2)+'\n',encoding='utf-8')
print('Captura privada OVL-002H derivada: 57 entradas no shard e 2.802 palavras cumulativas.')
PY
}

compile_shard() {
    local dst="$1" log="$1/ovl-002h-compile.log"
    printf '\n==> Compilando shard cumulativo OVL-002H em %s\n' "$CAPTURE_KEY"
    env -u PSX_OVERLAY_CACHE_DIR -u PSX_OVERLAY_CAPTURES "$PYTHON_BIN" "$COMPILE_OVERLAYS" \
        --captures "$dst/ovl-002h-filtered-capture.json" --capture-key "$CAPTURE_KEY" \
        --game-toml "$TEST_CONFIG" --recompiler "$RECOMPILER" --runtime-include "$RUNTIME_INCLUDE" \
        --out-dir "$dst/cache" --gcc "$GCC_BIN" --compiler gcc --cps --jobs 1 --force 2>&1 | tee "$log"
}

audit_cache() {
    "$PYTHON_BIN" - "$1" "$EXPECTED_CACHE_REL" <<'PY'
import hashlib,json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); rel=pathlib.PurePosixPath(sys.argv[2]); cache=root/pathlib.Path(*rel.parts)
source=json.loads((root/'ovl-002g-cache-source-manifest.json').read_text(encoding='utf-8'))
log=(root/'ovl-002h-compile.log').read_text(encoding='utf-8',errors='replace')
if '(0x00020000:0xF943B63B)' not in log or 'Capture filter: 1/' not in log or 'OK ->' not in log: raise SystemExit('ERRO: log nao confirma compilacao filtrada OVL-002H')
if 'SKIP: DLL already exists' in log or re.search(r'(?:RECOMPILER ERROR|GENERATED-C AUDIT FAILED|RANGE AUDIT FAILED|COMPILE ERROR|\bFAILED\b)',log): raise SystemExit('ERRO: compilador/auditoria OVL-002H reportou falha')
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
    if len(parts)>=2 and parts[0]=='F': entries.add(int(parts[1],16)&0x1fffffff)
    if len(parts)==3 and parts[0]=='R':
        start=int(parts[1],16); words.update(range(start,start+int(parts[2],16),4))
prior={0x00044C7C,0x00044CAC,0x00044830,0x0004485C,0x000448EC,0x00044984,0x00044A68,0x00044AF8,0x00044B8C,
       0x00047DE8,0x00049568,0x0004964C,0x000497E4,0x00049808,0x00049988,0x00049B9C,0x00049D24,0x00049E70,
       0x00049E90,0x00049E9C,0x00092138,0x00092524,0x00092740,0x00092800,0x000929D4,0x00092C2C,0x00093BB8,0x00093E4C,
       0x00045E30,0x00045E70,0x00045EB4,0x00045EDC,0x00045F00,0x00045F38,0x00045F80,0x00045F94,0x00045FF8,0x00046020}
new={0x000465A8,0x00046634,0x000466A8,0x000466D8,0x000466FC,0x00046704,0x00046710,0x00046724,0x000467BC,
     0x00046810,0x0004681C,0x00046830,0x000468A0,0x000468CC,0x000468EC,0x000468F8,0x00046920,0x00047DB8,0x00047DD8}
required=prior|new
forbidden={0x000442DC,0x0004438C,0x00044CBC,0x00045124,0x00045868,0x00045A1C,0x00045C14,0x00046034,0x00046934,0x00046998,0x00046C38,0x00047000}
if required-entries: raise SystemExit('roots/aliases cumulativos ausentes: '+','.join(f'0x{x:08X}' for x in sorted(required-entries)))
if entries-required: raise SystemExit('entrada inesperada fora da pre-auditoria: '+','.join(f'0x{x:08X}' for x in sorted(entries-required)))
if forbidden&entries: raise SystemExit('handler/PC fora do lote entrou no shard: '+','.join(f'0x{x:08X}' for x in sorted(forbidden&entries)))
if len(words)!=2802 or not set(range(0x800465A8,0x80046934,4))<=words or not set(range(0x80047DB8,0x80047DE8,4))<=words: raise SystemExit(f'corpo cumulativo invalido: {len(words)} palavras')
dlls=sorted(cache.glob('*.dll')); ranges=sorted(cache.glob('*.ranges'))
if not dlls or len(dlls)!=len(ranges): raise SystemExit('inventario cumulativo incompleto')
all_entries=set(); files=[]
for path in ranges:
    for line in path.read_text(encoding='utf-8').splitlines():
        parts=line.split()
        if parts and parts[0]=='F': all_entries.add(int(parts[1],16)&0x1fffffff)
if len(all_entries)!=165: raise SystemExit(f'inventario cumulativo tem {len(all_entries)} entradas, esperado 165')
for path in sorted(dlls+ranges,key=lambda item:item.as_posix()): files.append({'path':path.relative_to(root).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest().upper(),'size':path.stat().st_size})
(root/'ovl-002h-cache-manifest.json').write_text(json.dumps({
 'track':'OVL-002H-DDARK-BOMB-SUPER-CUMULATIVE','capture_keys':['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F','0x00020000:0xF943B63B'],
 'word_limit':252,'incremental_words':239,'prior_image_words':2563,'image_body_words':2802,'new_root':'0x800465A8','direct_helper':'0x80047DB8',
 'new_aliases':['0x80046634','0x800466A8','0x800466D8','0x800466FC','0x80046704','0x80046710','0x80046724','0x800467BC','0x80046810','0x8004681C','0x80046830','0x800468A0','0x800468CC','0x800468EC','0x800468F8','0x80046920','0x80047DD8'],
 'jump_table_pc':'0x8004662C','jump_table_addr':'0x8004A610','jump_table_slots':18,'jump_table_sha256':'6CFA63DD09A9FB9B111F6B57D76865F17A595AB155DAD5DCDBEBF3CAB3489206',
 'jump_table_targets':['0x80046634','0x80046704','0x80046810','0x800468A0','0x800468CC','0x80046920'],
 'excluded_handlers':['0x80044CBC','0x80045124','0x80045868','0x80045A1C','0x80045C14','0x80046034','0x80046934','0x80046998','0x80046C38','0x80047000'],
 'cop2_incremental':0,'cop2_total_image':115,'new_body_sha256':'06177D4AB270F914DDD1B3D0FDCED67009A95623231DAFA17CC6CE042D356825',
 'cumulative_body_sha256':'34F2CF64C7D2D74E231A65A7D7F58F48C1097CBF9DA6870DF0C66FB33A42E92E',
 'cache_relative':rel.as_posix(),'dll_count':len(dlls),'ranges_count':len(ranges),'unique_entries':len(all_entries),
 'replaced_source_files':sorted(changed),'files':files},indent=2,sort_keys=True)+'\n',encoding='utf-8')
print(f'Cache OVL-002H auditado: {len(dlls)} DLL(s), {len(all_entries)} entradas e 2.802 palavras na imagem F943B63B.')
PY
}

write_state() {
    local dst="$1"; umask 077
    {
        printf 'runtime_dir=%s\nruntime_exe=%s\ntest_config=%s\ncache_manifest=%s\n' "$dst" "$dst/StreetFighterEXPlusAlphaRecomp.exe" "$TEST_CONFIG" "$dst/ovl-002h-cache-manifest.json"
        printf 'capture_key=%s\nimage_sha256=%s\ntarget=0x800465A8\nhelper=0x80047DB8\n' "$CAPTURE_KEY" "$EXPECTED_IMAGE_SHA"
        printf 'alias_1=0x80046634\nalias_17=0x80047DD8\nword_limit=252\nincremental_words=239\nprior_words=2563\nimage_body_words=2802\n'
        printf 'cop2_incremental=0\ncop2_total_image=115\nincremental_sha256=%s\ncumulative_sha256=%s\njump_table_sha256=%s\n' "$EXPECTED_NEW_SHA" "$EXPECTED_CUMULATIVE_SHA" "$EXPECTED_TABLE_SHA"
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
    printf '\nOVL-002H criada em runtime experimental isolado. O executavel principal nao foi recompilado.\n'
    printf 'Abra com:\n  bash tools/run_ovl_002h_test.sh\n\nDepois, no Mode Select:\n  bash tools/telemetry_before_after_ovl_002h.sh prepare\n'
}

main "$@"
