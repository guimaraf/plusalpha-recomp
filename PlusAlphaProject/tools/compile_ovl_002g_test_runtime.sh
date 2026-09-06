#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly SOURCE_STATE="$PROJECT_ROOT/local/overlay/.ovl-002f-current-runtime.state"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002g-current-runtime.state"
readonly TELEMETRY_STATE="$PROJECT_ROOT/local/telemetry/.ovl-002g-test-active.state"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002g_test.toml"
readonly TARGET_FILE="$PROJECT_ROOT/seeds/ovl_002g_target_pcs.txt"
readonly COMPILE_OVERLAYS="$REPO_ROOT/psxrecomp/tools/compile_overlays.py"
readonly RECOMPILER="$REPO_ROOT/psxrecomp/recompiler/build/psxrecomp-game.exe"
readonly RUNTIME_INCLUDE="$REPO_ROOT/psxrecomp/runtime/include"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly DISPATCH_FILE="$PROJECT_ROOT/generated/SLUS_005.48_dispatch.c"
readonly GCC_BIN=/ucrt64/bin/gcc.exe
readonly CAPTURE_KEY=0x00020000:0xF943B63B
readonly EXPECTED_IMAGE_SHA=603A2A697D5CCCE74E6AFF3E4A5621F868C587E896410BC68A5275F01E57F3BF
readonly EXPECTED_NEW_SHA=365E6F1263836718ABA1E8F66EB12B014DAC10586B2291B28074833C7A5ACE73
readonly EXPECTED_CUMULATIVE_SHA=36DD3A48D0A8777E1449EAC941A239EC8EDB6D4CA427B136D2AA2B4E97299B5E
readonly EXPECTED_TABLE_SHA=4226C5CF1230376AEFEAE73A73B64D95BF8F4DFB8753607A65ED332A259CF498
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

  bash tools/compile_ovl_002g_test_runtime.sh

Preserva as 2.434 palavras OVL-002F e acrescenta somente a funcao formal
0x80045E30..0x80046033: limite rigido de 129 palavras.
Emite nove aliases internos: cinco observados e quatro adicionais da tabela
local de cinco destinos. Os outros dez handlers externos permanecem fora.
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
    [[ -f "$SOURCE_STATE" ]] || fail "Runtime OVL-002F aprovado ausente."
    SOURCE_RUNTIME_DIR="$(state_value "$SOURCE_STATE" runtime_dir)"
    SOURCE_RUNTIME_EXE="$(state_value "$SOURCE_STATE" runtime_exe)"
    SOURCE_CACHE_MANIFEST="$(state_value "$SOURCE_STATE" cache_manifest)"
    SOURCE_CAPTURE_FILE="$SOURCE_RUNTIME_DIR/ovl-002f-filtered-capture.json"
    case "$SOURCE_RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002f-test-runtime-*) ;; *) fail "Estado OVL-002F invalido." ;; esac
    [[ "$(state_value "$SOURCE_STATE" capture_key)" == "$CAPTURE_KEY" ]] || fail "Chave OVL-002F divergente."
    [[ "$(state_value "$SOURCE_STATE" target)" == 0x80044C7C && "$(state_value "$SOURCE_STATE" alias_1)" == 0x80044CAC ]] || fail "Raiz/alias OVL-002F divergentes."
    [[ "$(state_value "$SOURCE_STATE" image_body_words)" == 2434 ]] || fail "Corpo OVL-002F divergente."
}

validate_inputs() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep cp mkdir seq tee env; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python; read_source_state
    [[ ! -f "$TELEMETRY_STATE" ]] || fail "Existe coleta OVL-002G ativa."
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
manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
if (manifest.get('track')!='OVL-002F-DDARK-BOMB-DISPATCH-CUMULATIVE' or
        int(manifest.get('image_body_words',0))!=2434 or manifest.get('new_aliases')!=['0x80044CAC']):
    raise SystemExit('cache-base nao e OVL-002F aprovado')
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
root,end=0x80045E30,0x80046034
if struct.unpack_from('<II',data,root-load-8)!=(0x03E00008,0) or struct.unpack_from('<I',data,end-load)[0]!=0x27BDFFE8:
    raise SystemExit('boundaries OVL-002G divergiram')
walk=co._walk_overlay_function(data,load,len(data),root,end); visited=set(walk['visited'])
raw=b''.join(data[x-load:x-load+4] for x in sorted(visited))
if visited!=set(range(root,end,4)) or len(visited)!=129: raise SystemExit('closure OVL-002G excedeu 129 palavras')
if hashlib.sha256(raw).hexdigest().upper()!='365E6F1263836718ABA1E8F66EB12B014DAC10586B2291B28074833C7A5ACE73':
    raise SystemExit('hash do corpo OVL-002G divergente')
jump_targets={0x80045E70,0x80045F00,0x80045F80,0x80045F94,0x80045FF8}
if walk['direct_jals'] or walk['jump_table_targets']!=jump_targets:
    raise SystemExit(f'closure/tabela local OVL-002G divergente: {walk}')
special={'break':0,'syscall':0,'jalr':0,'cop2':0,'jr_non_ra':0}; jr_pcs=set(); bad_flow=[]
for pc in visited:
    word=struct.unpack_from('<I',data,pc-load)[0]; op=word>>26; fn=word&0x3f; rs=(word>>21)&0x1f
    kind,target=co._classify_cf(pc,word)
    if kind in ('j','branch') and not (root<=target<end): bad_flow.append((pc,target))
    if op==0 and fn==0x0d: special['break']+=1
    if op==0 and fn==0x0c: special['syscall']+=1
    if op==0 and fn==0x09: special['jalr']+=1
    if op==0 and fn==0x08 and rs!=31: special['jr_non_ra']+=1; jr_pcs.add(pc)
    if op==0x12: special['cop2']+=1
if special!={'break':0,'syscall':0,'jalr':0,'cop2':0,'jr_non_ra':1} or jr_pcs!={0x80045E68} or bad_flow:
    raise SystemExit(f'fluxo/instrucoes especiais OVL-002G divergiram: {special}, {jr_pcs}, {bad_flow}')
table_addr=0x8004A5C0
table=struct.unpack_from('<5I',data,table_addr-load); table_raw=struct.pack('<5I',*table)
if set(table)!=jump_targets or hashlib.sha256(table_raw).hexdigest().upper()!='4226C5CF1230376AEFEAE73A73B64D95BF8F4DFB8753607A65ED332A259CF498':
    raise SystemExit('tabela local OVL-002G divergente')
prior_ranges=runtime/pathlib.Path(*pathlib.PurePosixPath(manifest['cache_relative']).parts)/'00020000_F943B63B.ranges'
prior=set()
for line in prior_ranges.read_text(encoding='utf-8').splitlines():
    parts=line.split()
    if len(parts)==3 and parts[0]=='R':
        start_addr=int(parts[1],16); prior.update(range(start_addr,start_addr+int(parts[2],16),4))
combined=prior|visited; combined_raw=b''.join(data[x-load:x-load+4] for x in sorted(combined))
if len(prior)!=2434 or prior&visited or len(combined)!=2563: raise SystemExit('sobreposicao/volume cumulativo OVL-002G divergente')
if hashlib.sha256(combined_raw).hexdigest().upper()!='36DD3A48D0A8777E1449EAC941A239EC8EDB6D4CA427B136D2AA2B4E97299B5E':
    raise SystemExit('hash cumulativo OVL-002G divergente')
aliases=[0x80045E70,0x80045EB4,0x80045EDC,0x80045F00,0x80045F38,0x80045F80,0x80045F94,0x80045FF8,0x80046020]
filtered=copy.deepcopy(row)
for key in ('executed_pcs','observed_pcs','dispatch_entry_pcs','seeds'):
    filtered[key]=list(filtered.get(key,[]))+[f'0x{x:08X}' for x in [root,*aliases]]
toml_doc=tomllib.loads(config.read_text(encoding='utf-8'))
seed_lines,audit=co.classify_overlay_seeds(filtered,data,load,len(data),0xF943B63B,toml_doc)
reasons=audit['included_reasons']; expected={root:'DISPATCH_ENTRY',**{a:'DISPATCH_INTERIOR' for a in aliases}}
if len(reasons)!=38 or any(reasons.get(addr)!=reason for addr,reason in expected.items()):
    raise SystemExit(f'classificacao OVL-002G divergente: {reasons}')
targets=[int(line.split('#',1)[0].split()[1],16) for line in target_path.read_text().splitlines() if line.split('#',1)[0].split()]
if targets!=[root,*aliases]: raise SystemExit('targets OVL-002G divergentes')
print('Pre-auditoria OVL-002G: limite/closure de 129 palavras; 1 JR com 5 alvos internos; 9 aliases; outros handlers excluidos.')
PY
}

make_runtime_dir() {
    local suffix candidate; mkdir -p "$PROJECT_ROOT/local/overlay"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/overlay/ovl-002g-test-runtime-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    done
    fail "Nao ha runtime livre para OVL-002G."
}

copy_source_runtime() {
    local dst="$1" file
    cp "$SOURCE_RUNTIME_EXE" "$dst/StreetFighterEXPlusAlphaRecomp.exe"
    for file in input.ini keybinds.ini settings.toml launcher.rml; do [[ -f "$SOURCE_RUNTIME_DIR/$file" ]] && cp "$SOURCE_RUNTIME_DIR/$file" "$dst/$file"; done
    mkdir -p "$dst/cache"; cp -R "$SOURCE_RUNTIME_DIR/cache/." "$dst/cache/"
    cp "$SOURCE_CACHE_MANIFEST" "$dst/ovl-002f-cache-source-manifest.json"
}

derive_capture() {
    "$PYTHON_BIN" - "$SOURCE_CAPTURE_FILE" "$1/ovl-002g-filtered-capture.json" <<'PY'
import base64,binascii,copy,json,pathlib,sys
source=pathlib.Path(sys.argv[1]); output=pathlib.Path(sys.argv[2]); found=[]
for row in json.loads(source.read_text(encoding='utf-8')):
    data=base64.b64decode(row['bytes_b64'])
    if (int(row['load_addr'],0)&0x1fffffff)==0x20000 and (binascii.crc32(data)&0xffffffff)==0xF943B63B: found.append(row)
if len(found)!=1: raise SystemExit('imagem F943B63B nao e unica')
row=copy.deepcopy(found[0])
new=['0x80045E30','0x80045E70','0x80045EB4','0x80045EDC','0x80045F00',
     '0x80045F38','0x80045F80','0x80045F94','0x80045FF8','0x80046020']
for key in ('executed_pcs','observed_pcs','dispatch_entry_pcs','seeds'):
    row[key]=list(row.get(key,[]))+new
row['micro_lot']='OVL-002G cumulative: preserve 2434 words; add 129-word 0x80045E30 handler and nine internal aliases; other handlers excluded'
output.write_text(json.dumps([row],indent=2)+'\n',encoding='utf-8')
print('Captura privada OVL-002G derivada: 19 roots formais, 19 aliases, 2.563 palavras cumulativas.')
PY
}

compile_shard() {
    local dst="$1" log="$1/ovl-002g-compile.log"
    printf '\n==> Compilando shard cumulativo OVL-002G em %s\n' "$CAPTURE_KEY"
    env -u PSX_OVERLAY_CACHE_DIR -u PSX_OVERLAY_CAPTURES "$PYTHON_BIN" "$COMPILE_OVERLAYS" \
        --captures "$dst/ovl-002g-filtered-capture.json" --capture-key "$CAPTURE_KEY" \
        --game-toml "$TEST_CONFIG" --recompiler "$RECOMPILER" --runtime-include "$RUNTIME_INCLUDE" \
        --out-dir "$dst/cache" --gcc "$GCC_BIN" --compiler gcc --cps --jobs 1 --force 2>&1 | tee "$log"
}

audit_cache() {
    "$PYTHON_BIN" - "$1" "$EXPECTED_CACHE_REL" <<'PY'
import hashlib,json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); rel=pathlib.PurePosixPath(sys.argv[2]); cache=root/pathlib.Path(*rel.parts)
source=json.loads((root/'ovl-002f-cache-source-manifest.json').read_text(encoding='utf-8'))
log=(root/'ovl-002g-compile.log').read_text(encoding='utf-8',errors='replace')
if '(0x00020000:0xF943B63B)' not in log or 'Capture filter: 1/' not in log or 'OK ->' not in log:
    raise SystemExit('ERRO: log nao confirma compilacao filtrada OVL-002G')
if 'SKIP: DLL already exists' in log or re.search(r'(?:RECOMPILER ERROR|GENERATED-C AUDIT FAILED|RANGE AUDIT FAILED|COMPILE ERROR|\bFAILED\b)',log):
    raise SystemExit('ERRO: compilador/auditoria OVL-002G reportou falha')
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
if not any(x.endswith('.dll') for x in changed) or not any(x.endswith('.ranges') for x in changed):
    raise SystemExit('DLL/ranges F943B63B nao foram substituidos')
entries=set(); words=set()
for line in (cache/'00020000_F943B63B.ranges').read_text(encoding='utf-8').splitlines():
    parts=line.split()
    if len(parts)==3 and parts[0]=='F': entries.add(int(parts[1],16)&0x1fffffff)
    if len(parts)==3 and parts[0]=='R':
        start_addr=int(parts[1],16); words.update(range(start_addr,start_addr+int(parts[2],16),4))
required={0x00044C7C,0x00044CAC,0x00044830,0x0004485C,0x000448EC,0x00044984,0x00044A68,0x00044AF8,0x00044B8C,
          0x00047DE8,0x00049568,0x0004964C,0x000497E4,0x00049808,0x00049988,0x00049B9C,0x00049D24,0x00049E70,
          0x00049E90,0x00049E9C,0x00092138,0x00092524,0x00092740,0x00092800,0x000929D4,0x00092C2C,0x00093BB8,0x00093E4C,
          0x00045E30,0x00045E70,0x00045EB4,0x00045EDC,0x00045F00,0x00045F38,0x00045F80,0x00045F94,0x00045FF8,0x00046020}
forbidden={0x000442DC,0x0004438C,0x00044CBC,0x00045124,0x00045868,0x00045A1C,0x00045C14,
           0x00046034,0x000465A8,0x00046998,0x00046C38,0x00047000}
if required-entries: raise SystemExit('roots/aliases cumulativos ausentes: '+','.join(f'0x{x:08X}' for x in sorted(required-entries)))
if entries-required: raise SystemExit('entrada inesperada fora da pre-auditoria: '+','.join(f'0x{x:08X}' for x in sorted(entries-required)))
if forbidden&entries: raise SystemExit('handler/PC fora do microlote entrou no shard: '+','.join(f'0x{x:08X}' for x in sorted(forbidden&entries)))
if len(words)!=2563 or not set(range(0x80045E30,0x80046034,4))<=words:
    raise SystemExit(f'corpo cumulativo tem {len(words)} palavras ou perdeu a funcao nova')
dlls=sorted(cache.glob('*.dll')); ranges=sorted(cache.glob('*.ranges'))
if not dlls or len(dlls)!=len(ranges): raise SystemExit('inventario cumulativo incompleto')
all_entries=set(); files=[]
for path in ranges:
    for line in path.read_text(encoding='utf-8').splitlines():
        parts=line.split()
        if parts and parts[0]=='F': all_entries.add(int(parts[1],16)&0x1fffffff)
if len(all_entries)!=146: raise SystemExit(f'inventario cumulativo tem {len(all_entries)} entradas, esperado 146')
for path in sorted(dlls+ranges,key=lambda item:item.as_posix()):
    files.append({'path':path.relative_to(root).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest().upper(),'size':path.stat().st_size})
(root/'ovl-002g-cache-manifest.json').write_text(json.dumps({
 'track':'OVL-002G-DDARK-BOMB-HANDLER-CUMULATIVE','capture_keys':['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F','0x00020000:0xF943B63B'],
 'incremental_words':129,'prior_image_words':2434,'image_body_words':2563,'new_root':'0x80045E30',
 'new_aliases':['0x80045E70','0x80045EB4','0x80045EDC','0x80045F00','0x80045F38','0x80045F80','0x80045F94','0x80045FF8','0x80046020'],
 'jump_table_pc':'0x80045E68','jump_table_addr':'0x8004A5C0','jump_table_sha256':'4226C5CF1230376AEFEAE73A73B64D95BF8F4DFB8753607A65ED332A259CF498',
 'jump_table_targets':['0x80045E70','0x80045F00','0x80045F80','0x80045F94','0x80045FF8'],
 'excluded_handlers':['0x80044CBC','0x80045124','0x80045868','0x80045A1C','0x80045C14','0x80046034','0x800465A8','0x80046998','0x80046C38','0x80047000'],
 'cop2_incremental':0,'cop2_total_image':115,'new_body_sha256':'365E6F1263836718ABA1E8F66EB12B014DAC10586B2291B28074833C7A5ACE73',
 'cumulative_body_sha256':'36DD3A48D0A8777E1449EAC941A239EC8EDB6D4CA427B136D2AA2B4E97299B5E',
 'cache_relative':rel.as_posix(),'dll_count':len(dlls),'ranges_count':len(ranges),'unique_entries':len(all_entries),
 'replaced_source_files':sorted(changed),'files':files},indent=2,sort_keys=True)+'\n',encoding='utf-8')
print(f'Cache OVL-002G auditado: {len(dlls)} DLL(s), {len(all_entries)} entradas e 2.563 palavras na imagem F943B63B.')
PY
}

write_state() {
    local dst="$1"; umask 077
    {
        printf 'runtime_dir=%s\nruntime_exe=%s\ntest_config=%s\ncache_manifest=%s\n' "$dst" "$dst/StreetFighterEXPlusAlphaRecomp.exe" "$TEST_CONFIG" "$dst/ovl-002g-cache-manifest.json"
        printf 'capture_key=%s\nimage_sha256=%s\ntarget=0x80045E30\nalias_1=0x80045E70\nalias_2=0x80045EB4\nalias_3=0x80045EDC\nalias_4=0x80045F00\nalias_5=0x80045F38\nalias_6=0x80045F80\nalias_7=0x80045F94\nalias_8=0x80045FF8\nalias_9=0x80046020\n' "$CAPTURE_KEY" "$EXPECTED_IMAGE_SHA"
        printf 'incremental_words=129\nprior_words=2434\nimage_body_words=2563\ncop2_incremental=0\ncop2_total_image=115\n'
        printf 'incremental_sha256=%s\ncumulative_sha256=%s\njump_table_sha256=%s\n' "$EXPECTED_NEW_SHA" "$EXPECTED_CUMULATIVE_SHA" "$EXPECTED_TABLE_SHA"
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
    printf '\nOVL-002G criada em runtime experimental isolado. O executavel principal nao foi recompilado.\n'
    printf 'Abra com:\n  bash tools/run_ovl_002g_test.sh\n\nDepois, no Mode Select:\n  bash tools/telemetry_before_after_ovl_002g.sh prepare\n'
}

main "$@"
