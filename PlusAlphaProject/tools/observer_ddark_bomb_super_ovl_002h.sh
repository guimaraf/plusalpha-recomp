#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002h_test.toml"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002h-current-runtime.state"
readonly SOURCE_RESULT="$PROJECT_ROOT/local/telemetry/ovl-002g-ddark-bomb-states-01/phase-04-special/result.json"
readonly EXPECTED_SOURCE_SHA=1E5D7DA94BE9A7CC9441D2EBCE5E9ED38968A45C5328AA3E0429797A84180DC3
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly PREPARE_SECONDS=5
readonly CAPTURE_SECONDS=30

PYTHON_BIN=
DEBUG_PORT=
RUNTIME_DIR=
RUNTIME_EXE=
CACHE_MANIFEST=
SESSION_DIR=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com o runtime OVL-002H aberto:

  bash tools/observer_ddark_bomb_super_ovl_002h.sh

D.Dark P1 x Ryu P2, cenario do Ryu. Ryu parado. Durante 30 s, faca somente o
especial da bomba explosiva acertar Ryu, uma vez de cada lado. Pare apos o
segundo impacto e antes do KO; nao use facas, bombas comuns ou golpes normais.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk seq; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-002H ausente. Execute compile_ovl_002h_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"; RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002h-test-runtime-*) ;; *) fail "Runtime OVL-002H invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" target)" == 0x800465A8 && "$(state_value "$RUNTIME_STATE" helper)" == 0x80047DB8 ]] || fail "Raiz/helper divergentes."
    [[ "$(state_value "$RUNTIME_STATE" incremental_words)" == 239 && "$(state_value "$RUNTIME_STATE" image_body_words)" == 2802 ]] || fail "Volume divergente."
    for file in "$TEST_CONFIG" "$RUNTIME_EXE" "$CACHE_MANIFEST" "$SOURCE_RESULT"; do [[ -f "$file" ]] || fail "Arquivo ausente: $file"; done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel divergiu."
    [[ "$(sha256sum "$PROJECT_ROOT/generated/SLUS_005.48_full.ranges" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    [[ "$(sha256sum "$SOURCE_RESULT" | awk '{print toupper($1)}')" == "$EXPECTED_SOURCE_SHA" ]] || fail "Baseline do especial divergiu."
    DEBUG_PORT="$(awk '/^[[:space:]]*\[runtime\]/{ok=1;next} /^[[:space:]]*\[/{ok=0} ok&&/^[[:space:]]*debug_port[[:space:]]*=/{sub(/^[^=]*=/,"");gsub(/[[:space:]]+/,"");print;exit}' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" == 4535 ]] || fail "debug_port divergente."
}

make_session_dir() {
    local suffix candidate; mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-002h-ddark-bomb-super-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; SESSION_DIR="$candidate"; return; fi
    done
    fail "Nao ha pasta livre para o observador OVL-002H."
}

observe() {
    "$PYTHON_BIN" - "$DEBUG_PORT" "$SESSION_DIR" "$RUNTIME_DIR" "$CACHE_MANIFEST" "$PREPARE_SECONDS" "$CAPTURE_SECONDS" <<'PY'
import csv,hashlib,json,pathlib,socket,struct,sys,time,zlib
port=int(sys.argv[1]); session=pathlib.Path(sys.argv[2]); runtime=pathlib.Path(sys.argv[3]); manifest_path=pathlib.Path(sys.argv[4]); prepare_s=int(sys.argv[5]); capture_s=int(sys.argv[6])
def request(command,**arguments):
    wire=json.dumps({'id':1,'cmd':command,**arguments},separators=(',',':'))+'\n'; chunks=[]
    with socket.create_connection(('127.0.0.1',port),timeout=5.0) as sock:
        sock.settimeout(30.0); sock.sendall(wire.encode())
        while True:
            chunk=sock.recv(65536)
            if not chunk: break
            chunks.append(chunk)
    if not chunks: raise RuntimeError(f'{command}: resposta vazia')
    result=json.loads(b''.join(chunks).decode())
    if not result.get('ok'): raise RuntimeError(f'{command} rejeitado: {result}')
    return result
def paged(command,count_key,**arguments):
    offset=0; rows={}; header={}
    while True:
        page=request(command,offset=offset,limit=256,**arguments)
        if not header: header={k:v for k,v in page.items() if k!='entries'}
        for item in page.get('entries',[]):
            if item.get('pc'): rows[f'0x{int(str(item["pc"]),16):08X}']=item
        returned=int(page.get('returned',0) or 0); total=int(page.get(count_key,0) or 0); offset+=returned
        if returned==0 or offset>=total: break
        if offset>65536: raise RuntimeError(f'{command}: paginacao excedida')
    header['entries']=list(rows.values()); return header
def index(snapshot): return {f'0x{int(str(x["pc"]),16):08X}':x for x in snapshot.get('entries',[]) if x.get('pc')}
def delta(a,b,key): return max(0,int(b.get(key,0) or 0)-int(a.get(key,0) or 0))

manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
aliases=['0x80046634','0x800466A8','0x800466D8','0x800466FC','0x80046704','0x80046710','0x80046724','0x800467BC','0x80046810','0x8004681C','0x80046830','0x800468A0','0x800468CC','0x800468EC','0x800468F8','0x80046920','0x80047DD8']
if manifest.get('track')!='OVL-002H-DDARK-BOMB-SUPER-CUMULATIVE' or manifest.get('new_aliases')!=aliases or int(manifest.get('image_body_words',0))!=2802: raise RuntimeError('manifesto conectado nao e OVL-002H')
for item in manifest.get('files',[]):
    path=runtime/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']) or hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']: raise RuntimeError(f'cache alterado: {item["path"]}')
probe=request('overlay_loader_status')
if not int(probe.get('active',0) or 0): raise RuntimeError('overlay cache OVL-002H inativo')
expected_cache=(runtime/'cache').resolve(); actual=pathlib.Path(str(probe.get('cache_dir',''))).resolve()
if actual!=expected_cache: raise RuntimeError(f'cache conectado divergiu: {actual}')
native_required={0x800465A8,0x800466A8,0x800466D8,0x800466FC,0x80046710,0x80046724,0x800467BC,0x8004681C,0x80046830,0x800468EC,0x800468F8,0x80047DD8}
native_optional={0x80046634,0x80046704,0x80046810,0x800468A0,0x800468CC,0x80046920,0x80047DB8}
excluded={0x80046934,0x80046998,0x80046C38,0x80047000,0x80046034}
live={0x800465A8:0xA4BAA4E5,0x80046634:0x552A0E10,0x800466A8:0xE49C03BE,0x800466D8:0xF5B287E1,
0x800466FC:0x01A8412B,0x80046704:0x0C5259B0,0x80046710:0x8ADC57E4,0x80046724:0x6BD51855,
0x800467BC:0xBD49CA0E,0x80046810:0x7331E727,0x8004681C:0xCEA306E4,0x80046830:0x8ADCB28B,
0x800468A0:0xA21D3720,0x800468CC:0xDF864C64,0x800468EC:0x1EA8267F,0x800468F8:0x8200F878,
0x80046920:0x6BD8118B,0x80047DB8:0x4C8755A2,0x80047DD8:0x4C4C0DFB}
errors=[]; identity={'expected_cache_dir':str(expected_cache),'actual_cache_dir':str(actual),'pcs':{}}
for pc,wanted in live.items():
    words=request('mem_words',addr=f'0x{pc:08X}',count=32).get('words',[])
    crc=zlib.crc32(b''.join(struct.pack('<I',int(x,16)) for x in words))&0xffffffff if len(words)==32 else -1
    candidates=request('overlay_candidates',pc=f'0x{pc:08X}').get('candidates',[])
    exact=any(int(x.get('match',0))==1 and int(x.get('state',9))==0 and int(x.get('dll',-1))>=0 and int(x.get('device_touch',1))==0 for x in candidates)
    identity['pcs'][f'0x{pc:08X}']={'crc32':f'0x{crc&0xffffffff:08X}','expected':f'0x{wanted:08X}','candidate_exact_active':exact}
    if crc!=wanted or not exact: errors.append(f'0x{pc:08X}: identidade viva divergente')
external=[int(x,16) for x in request('mem_words',addr='0x800431C0',count=12).get('words',[])]
local=[int(x,16) for x in request('mem_words',addr='0x8004A610',count=18).get('words',[])]
wanted_external=[0x80044CBC,0x80045124,0x80045868,0x80045A1C,0x80045A1C,0x80045C14,0x80045E30,0x80046034,0x800465A8,0x80046C38,0x80046998,0x80047000]
wanted_local=[0x80046634,0x80046704,0x80046810]+[0x80046920]*13+[0x800468A0,0x800468CC]
if external!=wanted_external: errors.append('tabela externa divergente')
if local!=wanted_local: errors.append('tabela local divergente')
identity['external_table']=[f'0x{x:08X}' for x in external]; identity['local_jump_table']=[f'0x{x:08X}' for x in local]; identity['errors']=errors
(session/'runtime-identity.json').write_text(json.dumps(identity,indent=2,sort_keys=True)+'\n')
if errors: raise RuntimeError('; '.join(errors))

request('pc_watch_clear')
for pc in sorted(native_required|native_optional|excluded): request('pc_watch_arm',target=f'0x{pc:08X}')
request('pc_watch_reset')
print('\nRuntime OVL-002H confirmado.',flush=True)
for remaining in range(prepare_s,0,-1): print(f'Prepare-se: {remaining}...',flush=True); time.sleep(1)
before_static=paged('static_text_misses','total',**{'class':'all','min_hits':1}); before_dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
before_diag={name:request(name) for name in ('overlay_loader_status','dirty_ram_stats','dispatch_stats')}
print(f'\a[CAPTURANDO] Por {capture_s} s, faca o especial da bomba explosiva acertar Ryu uma vez de cada lado.',flush=True)
started=time.monotonic(); time.sleep(capture_s); elapsed=time.monotonic()-started
request('pc_watch_stop')
after_dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000'); after_static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
after_diag={name:request(name) for name in ('overlay_loader_status','dirty_ram_stats','dispatch_stats')}; watch=request('pc_watch_dump')
print('\a\a[FIM DA CAPTURA] Pare as acoes.',flush=True)
before_s,before_d,after_s,after_d=map(index,(before_static,before_dynamic,after_static,after_dynamic)); rows=[]
for pc in sorted(set(after_s)|set(after_d)):
    s0,s1=before_s.get(pc,{}),after_s.get(pc,{}); d0,d1=before_d.get(pc,{}),after_d.get(pc,{})
    static=sum(delta(s0,s1,k) for k in ('misses','modified','runtime','unknown')); entries=delta(d0,d1,'entry_hits'); insns=delta(d0,d1,'insns'); blocks=delta(d0,d1,'hits')
    if static or entries or insns: rows.append({'pc':pc,'external_entries':max(static,entries),'static_entries':static,'dynamic_entries':entries,'interpreted_blocks':blocks,'interpreted_insns':insns,'entries_per_s':max(static,entries)/elapsed,'insns_per_s':insns/elapsed})
rows.sort(key=lambda x:(-x['interpreted_insns'],-x['external_entries'],x['pc']))
seen={str(x.get('target','')).upper():x for x in watch.get('entries',[])}; targets={}; fatal=[]
for pc in sorted(native_required|native_optional|excluded):
    item=seen.get(f'0X{pc:08X}',{}); native=int(item.get('native_hits',0) or 0); interp=int(item.get('interpreted_hits',0) or 0)
    targets[f'0x{pc:08X}']={'native_hits':native,'interpreted_hits':interp}
    if pc in native_required and native<=0: fatal.append(f'0x{pc:08X} nao teve hit nativo')
    if pc in native_required|native_optional and interp: fatal.append(f'0x{pc:08X} teve {interp} hit(s) interpretado(s)')
    if pc in excluded and native: fatal.append(f'0x{pc:08X} excluido teve {native} hit(s) nativo(s)')
for pc in (0x80046934,0x80047000):
    if targets[f'0x{pc:08X}']['interpreted_hits']<=0: fatal.append(f'0x{pc:08X} excluido nao foi exercitado')
if sum(targets[f'0x{x:08X}']['native_hits'] for x in (0x80046634,0x80046704,0x80046810,0x800468A0,0x800468CC,0x80046920))<=0: fatal.append('nenhum destino da tabela local executou nativo')
focus_before={'0x800465A8':3740,'0x800466A8':17,'0x800466D8':16,'0x800466FC':10,'0x80046710':472,'0x80046724':2258,'0x800467BC':32,'0x8004681C':40,'0x80046830':154,'0x800468EC':4,'0x800468F8':28,'0x80047DD8':220}
focus_after={pc:next((x['interpreted_insns'] for x in rows if x['pc']==pc),0) for pc in focus_before}
for pc,value in focus_after.items():
    if value: fatal.append(f'{pc} ainda acumulou {value} instrucoes interpretadas')
loader={k:delta(before_diag['overlay_loader_status'],after_diag['overlay_loader_status'],k) for k in ('dispatch_native','unregistered_funcs','invalidations','stale_blocked')}
guards={k:delta(before_diag['dirty_ram_stats'],after_diag['dirty_ram_stats'],k) for k in ('aborts','text_native_blocked','text_diverged_pages','text_exact_mismatches')}; miss=delta(before_diag['dispatch_stats'],after_diag['dispatch_stats'],'miss_total')
if loader['unregistered_funcs'] or any(guards.values()) or miss: fatal.append('diagnostico de seguranca nao zerado')
total=sum(x['interpreted_insns'] for x in rows); baseline=4535489
result={'track':'OVL-002H-DDARK-BOMB-SUPER','duration_s':elapsed,'pcs':len(rows),'interpreted_insns':total,'ovl_002g_baseline_insns':baseline,'delta_vs_ovl_002g_baseline':total-baseline,'selected_family_ovl_002g_insns':focus_before,'selected_family_ovl_002h_insns':focus_after,'selected_family_baseline_total':sum(focus_before.values()),'targets':targets,'loader_deltas':loader,'guard_deltas':guards,'dispatch_miss_delta':miss,'technical_clean':not fatal,'errors':fatal,'entries':rows}
for name,data in [('before_static_text_misses.json',before_static),('before_overlay_interp_hot.json',before_dynamic),('after_static_text_misses.json',after_static),('after_overlay_interp_hot.json',after_dynamic),('before_diagnostics.json',before_diag),('after_diagnostics.json',after_diag),('pc-watch.json',watch),('result.json',result)]: (session/name).write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
with (session/'interpreted.csv').open('w',newline='',encoding='utf-8') as output:
    columns=list(rows[0]) if rows else ['pc','external_entries','static_entries','dynamic_entries','interpreted_blocks','interpreted_insns','entries_per_s','insns_per_s']; writer=csv.DictWriter(output,fieldnames=columns); writer.writeheader(); writer.writerows(rows)
lines=['# OVL-002H - observador do especial da bomba','',f'- Duracao: {elapsed:.3f} s',f'- Instrucoes interpretadas: {total}',f'- Delta bruto contra OVL-002G: {total-baseline:+d}',f'- Familia selecionada: {sum(focus_before.values())} -> {sum(focus_after.values())}',f'- Status tecnico: {"CLEAN" if not fatal else "REVIEW"}','','| PC | Entradas | Instrucoes | Instrucoes/s |','|---|---:|---:|---:|']
for item in rows: lines.append(f'| `{item["pc"]}` | {item["external_entries"]} | {item["interpreted_insns"]} | {item["insns_per_s"]:.1f} |')
if fatal: lines += ['','## Bloqueios','']+[f'- {x}' for x in fatal]
(session/'summary.md').write_text('\n'.join(lines)+'\n')
if fatal: raise RuntimeError('; '.join(fatal))
print(f'Observador OVL-002H CLEAN. Sessao: {session}')
PY
}

main() {
    case "${1:-}" in '') ;; -h|--help) usage; return ;; *) usage; fail "Argumento desconhecido." ;; esac
    validate; make_session_dir
    printf '\nD.Dark P1 x Ryu P2, cenario do Ryu. Ryu parado.\n'
    printf 'Faca somente o especial da bomba explosiva acertar Ryu uma vez de cada lado. Pare apos o segundo impacto.\n'
    read -r -p "Pressione Enter quando o gameplay estiver controlavel: "
    observe
}

main "$@"
