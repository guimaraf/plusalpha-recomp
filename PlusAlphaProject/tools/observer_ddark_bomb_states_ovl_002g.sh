#!/usr/bin/env bash
# Comparador de quatro estados da bomba sobre o runtime OVL-002G.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002g_test.toml"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002g-current-runtime.state"
readonly ACTIVE_STATE="$PROJECT_ROOT/local/telemetry/.ovl-002g-ddark-bomb-states-active.state"
readonly SOURCE_RESULT="$PROJECT_ROOT/local/telemetry/ovl-002g-ddark-bombs-discovery-01/result.json"
readonly EXPECTED_SOURCE_SHA=9D43B880FD0897E388A5EBF4FDFD0E1ED0E35701B8C52462B2E6AB7A37301B52
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
NO_HIT_RESULT=
HIT_RESULT=
BLOCK_RESULT=
SPECIAL_RESULT=
OTHER_SPECIAL_RESULT=

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, mantendo o mesmo runtime OVL-002G aberto:

  bash tools/observer_ddark_bomb_states_ovl_002g.sh no-hit
  bash tools/observer_ddark_bomb_states_ovl_002g.sh hit
  bash tools/observer_ddark_bomb_states_ovl_002g.sh block
  bash tools/observer_ddark_bomb_states_ovl_002g.sh special
  bash tools/observer_ddark_bomb_states_ovl_002g.sh other-special
  bash tools/observer_ddark_bomb_states_ovl_002g.sh compare
  bash tools/observer_ddark_bomb_states_ovl_002g.sh status

Use sempre D.Dark P1 x Ryu P2 no cenario do Ryu e uma acao por janela:
  no-hit : bombas dos dois lados sem colisao; aguarde o ciclo completo.
  hit    : Ryu neutro; faca somente as bombas acertarem Ryu.
  block  : Ryu defendendo; faca somente as bombas atingirem a defesa.
  special: execute somente o especial/super do D.Dark relacionado a bombas,
           permitindo o acerto, sem golpes normais.
  other-special: execute somente o outro especial/super do D.Dark, diferente
                 da bomba explosiva que lanca o adversario.

Cada janela dura 30 s e nao consulta o runtime durante a acao. Uma fase pode
ser repetida enquanto a comparacao estiver ativa; sempre sera criada nova pasta.
O comando compare reaproveita as fases ja coletadas e nao captura gameplay.
EOF
}

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk seq mv; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-002G ausente. Execute compile_ovl_002g_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"; RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002g-test-runtime-*) ;; *) fail "Runtime OVL-002G invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" target)" == 0x80045E30 && "$(state_value "$RUNTIME_STATE" alias_1)" == 0x80045E70 && "$(state_value "$RUNTIME_STATE" alias_9)" == 0x80046020 && "$(state_value "$RUNTIME_STATE" image_body_words)" == 2563 ]] || fail "Estado OVL-002G divergente."
    for file in "$TEST_CONFIG" "$RUNTIME_EXE" "$CACHE_MANIFEST" "$SOURCE_RESULT"; do [[ -f "$file" ]] || fail "Arquivo ausente: $file"; done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel divergiu."
    [[ "$(sha256sum "$PROJECT_ROOT/generated/SLUS_005.48_full.ranges" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    [[ "$(sha256sum "$SOURCE_RESULT" | awk '{print toupper($1)}')" == "$EXPECTED_SOURCE_SHA" ]] || fail "Baseline OVL-002G divergiu."
    DEBUG_PORT="$(awk '/^[[:space:]]*\[runtime\]/{ok=1;next} /^[[:space:]]*\[/{ok=0} ok&&/^[[:space:]]*debug_port[[:space:]]*=/{sub(/^[^=]*=/,"");gsub(/[[:space:]]+/,"");print;exit}' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" == 4534 ]] || fail "debug_port divergente."
}

make_session_dir() {
    local suffix candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-002g-ddark-bomb-states-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; SESSION_DIR="$candidate"; return; fi
    done
    fail "Nao ha pasta livre para a comparacao de estados."
}

next_phase_dir() {
    local base="$1" suffix candidate="$SESSION_DIR/$1"
    if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    for suffix in $(seq -w 2 99); do
        candidate="$SESSION_DIR/$base-retry-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    done
    fail "Nao ha pasta livre para repetir $base."
}

write_state() {
    umask 077
    {
        printf 'session_dir=%s\nruntime_dir=%s\nsource_sha256=%s\n' "$SESSION_DIR" "$RUNTIME_DIR" "$EXPECTED_SOURCE_SHA"
        printf 'no_hit_result=%s\nhit_result=%s\nblock_result=%s\nspecial_result=%s\nother_special_result=%s\n' \
            "$NO_HIT_RESULT" "$HIT_RESULT" "$BLOCK_RESULT" "$SPECIAL_RESULT" "$OTHER_SPECIAL_RESULT"
    } >"$ACTIVE_STATE"
}

read_state() {
    [[ -f "$ACTIVE_STATE" ]] || fail "Comparacao ausente. Execute primeiro no-hit."
    SESSION_DIR="$(state_value "$ACTIVE_STATE" session_dir)"
    NO_HIT_RESULT="$(state_value "$ACTIVE_STATE" no_hit_result)"
    HIT_RESULT="$(state_value "$ACTIVE_STATE" hit_result)"
    BLOCK_RESULT="$(state_value "$ACTIVE_STATE" block_result)"
    SPECIAL_RESULT="$(state_value "$ACTIVE_STATE" special_result)"
    OTHER_SPECIAL_RESULT="$(state_value "$ACTIVE_STATE" other_special_result)"
    [[ "$(state_value "$ACTIVE_STATE" runtime_dir)" == "$RUNTIME_DIR" ]] || fail "Runtime mudou entre as fases."
    [[ "$(state_value "$ACTIVE_STATE" source_sha256)" == "$EXPECTED_SOURCE_SHA" ]] || fail "Baseline mudou entre as fases."
    case "$SESSION_DIR" in "$PROJECT_ROOT"/local/telemetry/ovl-002g-ddark-bomb-states-*) ;; *) fail "Sessao invalida." ;; esac
    [[ -d "$SESSION_DIR" ]] || fail "Diretorio da sessao ausente."
}

observe() {
    local mode="$1" output_dir="$2"
    "$PYTHON_BIN" - "$DEBUG_PORT" "$output_dir" "$RUNTIME_DIR" "$CACHE_MANIFEST" "$mode" "$PREPARE_SECONDS" "$CAPTURE_SECONDS" <<'PY'
import csv,hashlib,json,pathlib,socket,struct,sys,time,zlib
port=int(sys.argv[1]); session=pathlib.Path(sys.argv[2]); runtime=pathlib.Path(sys.argv[3]); manifest_path=pathlib.Path(sys.argv[4])
mode=sys.argv[5]; prepare_s=int(sys.argv[6]); capture_s=int(sys.argv[7])

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
        if not header: header={key:value for key,value in page.items() if key!='entries'}
        for item in page.get('entries',[]):
            if item.get('pc'): rows[f'0x{int(str(item["pc"]),16):08X}']=item
        returned=int(page.get('returned',0) or 0); total=int(page.get(count_key,0) or 0); offset+=returned
        if returned==0 or offset>=total: break
        if offset>65536: raise RuntimeError(f'{command}: paginacao excedida')
    header['entries']=list(rows.values()); return header

def index(snapshot): return {f'0x{int(str(item["pc"]),16):08X}':item for item in snapshot.get('entries',[]) if item.get('pc')}
def delta(before,after,key): return max(0,int(after.get(key,0) or 0)-int(before.get(key,0) or 0))

manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
aliases=['0x80045E70','0x80045EB4','0x80045EDC','0x80045F00','0x80045F38','0x80045F80','0x80045F94','0x80045FF8','0x80046020']
if manifest.get('track')!='OVL-002G-DDARK-BOMB-HANDLER-CUMULATIVE' or int(manifest.get('image_body_words',0))!=2563 or manifest.get('new_aliases')!=aliases:
    raise RuntimeError('manifesto conectado nao e OVL-002G')
for item in manifest.get('files',[]):
    path=runtime/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']) or hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']:
        raise RuntimeError(f'cache alterado: {item["path"]}')
probe=request('overlay_loader_status')
if not int(probe.get('active',0) or 0): raise RuntimeError('overlay cache OVL-002G inativo')
expected_cache=(runtime/'cache').resolve(); actual=pathlib.Path(str(probe.get('cache_dir',''))).resolve()
if actual!=expected_cache: raise RuntimeError(f'cache conectado divergiu: {actual}')
live={0x80045E30:0x95AB7D43,0x80045E70:0x17150306,0x80045EB4:0x87E45D08,0x80045EDC:0x130F0F62,
      0x80045F00:0x7291F211,0x80045F38:0x2DF55CC3,0x80045F80:0xA8F4C52C,0x80045F94:0xC6AEDCB3,
      0x80045FF8:0x97ED45B7,0x80046020:0xB30CC5EF,0x80044C7C:0xD929A55E,0x80044CAC:0x990698B6,
      0x80044830:0x9E9CD462,0x80044B8C:0xD7D51FE0,
      0x80047DE8:0xBEFA5EA1,0x80049568:0x9611F1A0,0x80049808:0xCB050F22,0x80049988:0x6D2C8CD6,
      0x80092C2C:0x1B64D20F,0x80093E4C:0x12FF550F}
required_group={0x80045E30,0x80045EB4,0x80045EDC,0x80045F00,0x80045F38,0x80046020}
optional_group={0x80045E70,0x80045F80,0x80045F94,0x80045FF8}
native_group=required_group|optional_group
handlers={0x80044CBC,0x80045124,0x80045868,0x80045A1C,0x80045C14,
          0x80046034,0x800465A8,0x80046998,0x80046C38,0x80047000}
identity={'expected_cache_dir':str(expected_cache),'actual_cache_dir':str(actual),'pcs':{}}; errors=[]
for pc,wanted in live.items():
    words=request('mem_words',addr=f'0x{pc:08X}',count=32).get('words',[])
    crc=zlib.crc32(b''.join(struct.pack('<I',int(item,16)) for item in words))&0xffffffff if len(words)==32 else -1
    candidates=request('overlay_candidates',pc=f'0x{pc:08X}').get('candidates',[])
    exact=any(int(item.get('match',0))==1 and int(item.get('state',9))==0 and int(item.get('dll',-1))>=0 and int(item.get('device_touch',1))==0 for item in candidates)
    identity['pcs'][f'0x{pc:08X}']={'crc32':f'0x{crc&0xffffffff:08X}','expected':f'0x{wanted:08X}','candidate_exact_active':exact}
    if crc!=wanted or exact is False: errors.append(f'0x{pc:08X}: identidade viva divergente')
wanted_external=[0x80044CBC,0x80045124,0x80045868,0x80045A1C,0x80045A1C,0x80045C14,
                 0x80045E30,0x80046034,0x800465A8,0x80046C38,0x80046998,0x80047000]
wanted_local=[0x80045E70,0x80045F00,0x80045F80,0x80045F94,0x80045FF8]
external=[int(item,16) for item in request('mem_words',addr='0x800431C0',count=12).get('words',[])]
local=[int(item,16) for item in request('mem_words',addr='0x8004A5C0',count=5).get('words',[])]
identity['external_table']=[f'0x{x:08X}' for x in external]; identity['local_jump_table']=[f'0x{x:08X}' for x in local]
if external!=wanted_external: errors.append('tabela externa 0x800431C0 divergente')
if local!=wanted_local: errors.append('tabela local 0x8004A5C0 divergente')
identity['errors']=errors; (session/'runtime-identity.json').write_text(json.dumps(identity,indent=2,sort_keys=True)+'\n')
if errors: raise RuntimeError('; '.join(errors))

request('pc_watch_clear')
for pc in sorted(native_group|handlers): request('pc_watch_arm',target=f'0x{pc:08X}')
request('pc_watch_reset')
print(f'\nRuntime OVL-002G confirmado. Fase: {mode}.',flush=True)
for remaining in range(prepare_s,0,-1): print(f'Prepare-se: {remaining}...',flush=True); time.sleep(1)
before_static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
before_dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
before_diag={name:request(name) for name in ('overlay_loader_status','dirty_ram_stats','dispatch_stats')}
actions={'no-hit':'repita bombas dos dois lados sem colisao e aguarde o ciclo completo',
         'hit':'faca somente as bombas acertarem Ryu neutro',
         'block':'faca somente as bombas atingirem Ryu defendendo',
         'special':'execute somente o especial/super do D.Dark relacionado a bombas',
         'other-special':'execute somente o outro especial/super do D.Dark'}
print(f'\a[CAPTURANDO] Por {capture_s} s, {actions[mode]}.',flush=True)
started=time.monotonic(); time.sleep(capture_s); elapsed=time.monotonic()-started
request('pc_watch_stop')
after_dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
after_static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
after_diag={name:request(name) for name in ('overlay_loader_status','dirty_ram_stats','dispatch_stats')}; watch=request('pc_watch_dump')
print('\a\a[FIM DA CAPTURA] Pare as acoes.',flush=True)

before_s,before_d,after_s,after_d=map(index,(before_static,before_dynamic,after_static,after_dynamic)); rows=[]
for pc in sorted(set(after_s)|set(after_d)):
    s0,s1=before_s.get(pc,{}),after_s.get(pc,{}); d0,d1=before_d.get(pc,{}),after_d.get(pc,{})
    static=sum(delta(s0,s1,key) for key in ('misses','modified','runtime','unknown')); entries=delta(d0,d1,'entry_hits')
    insns=delta(d0,d1,'insns'); blocks=delta(d0,d1,'hits')
    if not static and not entries and not insns: continue
    rows.append({'pc':pc,'external_entries':max(static,entries),'static_entries':static,'dynamic_entries':entries,
                 'interpreted_blocks':blocks,'interpreted_insns':insns,'entries_per_s':max(static,entries)/elapsed,'insns_per_s':insns/elapsed})
rows.sort(key=lambda item:(-item['interpreted_insns'],-item['external_entries'],item['pc']))
seen={str(item.get('target','')).upper():item for item in watch.get('entries',[])}; group={}; handler_hits={}; fatal=[]
for pc in sorted(native_group):
    item=seen.get(f'0X{pc:08X}',{}); native=int(item.get('native_hits',0) or 0); interp=int(item.get('interpreted_hits',0) or 0)
    group[f'0x{pc:08X}']={'native_hits':native,'interpreted_hits':interp}
    if interp: fatal.append(f'0x{pc:08X} teve {interp} hit(s) interpretado(s)')
for pc in sorted(handlers):
    item=seen.get(f'0X{pc:08X}',{}); native=int(item.get('native_hits',0) or 0); interp=int(item.get('interpreted_hits',0) or 0)
    handler_hits[f'0x{pc:08X}']={'native_hits':native,'interpreted_hits':interp}
    if native: fatal.append(f'0x{pc:08X} deveria permanecer fora do lote, mas teve hit nativo')
loader={key:delta(before_diag['overlay_loader_status'],after_diag['overlay_loader_status'],key) for key in ('dispatch_native','unregistered_funcs','invalidations','stale_blocked')}
dirty={key:delta(before_diag['dirty_ram_stats'],after_diag['dirty_ram_stats'],key) for key in ('aborts','text_native_blocked','text_diverged_pages','text_exact_mismatches')}
miss=delta(before_diag['dispatch_stats'],after_diag['dispatch_stats'],'miss_total')
if loader['unregistered_funcs'] or any(dirty.values()) or miss: fatal.append('diagnostico de seguranca nao zerado')
total=sum(item['interpreted_insns'] for item in rows); baseline=4531472
focus_before={'0x80045E30':10896,'0x80045EB4':92,'0x80045EDC':96,'0x80045F00':96,'0x80045F38':240,'0x80046020':48}
focus_after={pc:next((item['interpreted_insns'] for item in rows if item['pc']==pc),0) for pc in focus_before}
for pc,value in focus_after.items():
    if value: fatal.append(f'{pc} ainda acumulou {value} instrucoes interpretadas')
result={'track':'OVL-002G-DDARK-BOMB-STATES','mode':mode,'duration_s':elapsed,'pcs':len(rows),'interpreted_insns':total,
        'ovl_002f_baseline_insns':baseline,'delta_vs_ovl_002f_baseline':total-baseline,
        'focus_family_ovl_002f_insns':focus_before,'focus_family_ovl_002g_insns':focus_after,
        'new_group':group,'indirect_handlers':handler_hits,'loader_deltas':loader,
        'guard_deltas':dirty,'dispatch_miss_delta':miss,'technical_clean':not fatal,'errors':fatal,'entries':rows}
for name,data in [('before_static_text_misses.json',before_static),('before_overlay_interp_hot.json',before_dynamic),
                  ('after_static_text_misses.json',after_static),('after_overlay_interp_hot.json',after_dynamic),
                  ('before_diagnostics.json',before_diag),('after_diagnostics.json',after_diag),('pc-watch.json',watch),('result.json',result)]:
    (session/name).write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
with (session/'interpreted.csv').open('w',newline='',encoding='utf-8') as output:
    columns=list(rows[0]) if rows else ['pc','external_entries','static_entries','dynamic_entries','interpreted_blocks','interpreted_insns','entries_per_s','insns_per_s']
    writer=csv.DictWriter(output,fieldnames=columns); writer.writeheader(); writer.writerows(rows)
native_total=sum(item['native_hits'] for item in group.values()); interp_total=sum(item['interpreted_hits'] for item in group.values())
handler_interp=sum(item['interpreted_hits'] for item in handler_hits.values())
focus_before_total=sum(focus_before.values()); focus_after_total=sum(focus_after.values())
titles={'no-hit':'Bombas sem acerto','hit':'Bombas com acerto','block':'Bombas contra defesa',
        'special':'Especial/super relacionado a bombas','other-special':'Outro especial/super'}
lines=[f'# OVL-002G - {titles[mode]}','',f'- Duracao: {elapsed:.3f} s',f'- PCs interpretados: {len(rows)}',
       f'- Instrucoes interpretadas: {total}',f'- Delta bruto contra OVL-002F: {total-baseline:+d}',
       f'- Familia 0x80045E30: {focus_before_total} -> {focus_after_total} instrucoes interpretadas',
       f'- Handler/aliases: {native_total} hits nativos / {interp_total} interpretados',
       f'- Handlers excluidos: {handler_interp} hits interpretados',f'- Status tecnico: {"CLEAN" if not fatal else "REVIEW"}',
       '','| PC | Entradas | Instrucoes | Instrucoes/s |','|---|---:|---:|---:|']
for item in rows: lines.append(f'| `{item["pc"]}` | {item["external_entries"]} | {item["interpreted_insns"]} | {item["insns_per_s"]:.1f} |')
if fatal: lines += ['','## Bloqueios','']+[f'- {item}' for item in fatal]
(session/'summary.md').write_text('\n'.join(lines)+'\n')
if fatal: raise RuntimeError('; '.join(fatal))
print(f'Coleta concluida. Sessao: {session}')
PY
}

compare_results() {
    "$PYTHON_BIN" - "$SESSION_DIR" "$NO_HIT_RESULT" "$HIT_RESULT" "$BLOCK_RESULT" "$SPECIAL_RESULT" "$OTHER_SPECIAL_RESULT" <<'PY'
import csv,json,pathlib,sys
session=pathlib.Path(sys.argv[1]); all_modes=('no-hit','hit','block','special','other-special')
pairs=[(mode,item) for mode,item in zip(all_modes,sys.argv[2:7]) if item]
modes=tuple(mode for mode,_ in pairs); paths=[pathlib.Path(item) for _,item in pairs]
if modes[:4]!=all_modes[:4]: raise SystemExit('As quatro fases-base ainda nao estao completas.')
results={mode:json.loads(path.read_text(encoding='utf-8')) for mode,path in zip(modes,paths)}
group_pcs=['0x80045E30','0x80045E70','0x80045EB4','0x80045EDC','0x80045F00',
           '0x80045F38','0x80045F80','0x80045F94','0x80045FF8','0x80046020']
jump_targets={'0x80045E70','0x80045F00','0x80045F80','0x80045F94','0x80045FF8'}
coverage=[]; safety_errors=[]; coverage_gaps=[]
for pc in group_pcs:
    row={'pc':pc}
    for mode in modes:
        item=results[mode].get('new_group',{}).get(pc,{})
        row[f'{mode}_native_hits']=int(item.get('native_hits',0) or 0)
        row[f'{mode}_interpreted_hits']=int(item.get('interpreted_hits',0) or 0)
    row['native_total']=sum(row[f'{mode}_native_hits'] for mode in modes)
    row['interpreted_total']=sum(row[f'{mode}_interpreted_hits'] for mode in modes)
    row['covered']=row['native_total']>0
    if row['interpreted_total']: safety_errors.append(f'{pc}: {row["interpreted_total"]} hit(s) interpretado(s)')
    coverage.append(row)
uncovered=sorted(row['pc'] for row in coverage if row['pc'] in jump_targets and not row['covered'])
if uncovered: coverage_gaps.append('alvos da tabela local nao exercitados: '+', '.join(uncovered))
root=next(row for row in coverage if row['pc']=='0x80045E30')
if not root['covered']: coverage_gaps.append('handler 0x80045E30 nao foi exercitado')
for mode,result in results.items():
    if not result.get('technical_clean'): safety_errors.append(f'fase {mode} terminou em REVIEW tecnico')

entry_maps={mode:{row['pc']:row for row in result.get('entries',[])} for mode,result in results.items()}
all_pcs=sorted(set().union(*(set(items) for items in entry_maps.values())))
comparison=[]
for pc in all_pcs:
    row={'pc':pc}
    for mode in modes:
        item=entry_maps[mode].get(pc,{})
        row[f'{mode}_insns']=int(item.get('interpreted_insns',0) or 0)
        row[f'{mode}_insns_per_s']=float(item.get('insns_per_s',0) or 0)
    active=[mode for mode in modes if row[f'{mode}_insns']>0]
    row['observed_modes']=','.join(active); comparison.append(row)
comparison.sort(key=lambda row:(-max(row[f'{mode}_insns_per_s'] for mode in modes),row['pc']))

with (session/'jump-table-coverage.csv').open('w',encoding='utf-8',newline='') as handle:
    writer=csv.DictWriter(handle,fieldnames=list(coverage[0])); writer.writeheader(); writer.writerows(coverage)
with (session/'interpreted-comparison.csv').open('w',encoding='utf-8',newline='') as handle:
    writer=csv.DictWriter(handle,fieldnames=list(comparison[0])); writer.writeheader(); writer.writerows(comparison)
phase_exclusive={mode:[row['pc'] for row in comparison if row['observed_modes']==mode] for mode in modes}
clean=not safety_errors
coverage_complete=not coverage_gaps
result={'track':'OVL-002G-DDARK-BOMB-STATE-COVERAGE','modes':list(modes),'jump_table_targets':sorted(jump_targets),
        'covered_jump_targets':sorted(row['pc'] for row in coverage if row['pc'] in jump_targets and row['covered']),
        'uncovered_jump_targets':uncovered,'coverage':coverage,'phase_exclusive_interpreted_pcs':phase_exclusive,
        'phase_interpreted_insns':{mode:int(results[mode].get('interpreted_insns',0)) for mode in modes},
        'technical_clean':clean,'coverage_complete':coverage_complete,
        'coverage_gaps':coverage_gaps,'errors':safety_errors}
(session/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
lines=['# Cobertura dos estados da bomba - OVL-002G','',
       f'- Alvos da tabela cobertos: {len(result["covered_jump_targets"])}/5',
       f'- Alvos nao exercitados: {", ".join(uncovered) if uncovered else "nenhum"}',
       f'- Hits interpretados na familia: {sum(row["interpreted_total"] for row in coverage)}',
       f'- Status tecnico: {"CLEAN" if clean else "ERRO"}',
       f'- Cobertura: {"CLEAN" if coverage_complete else "REVIEW"}','']
labels={'no-hit':'Sem acerto','hit':'Acerto','block':'Defesa','special':'Especial da bomba','other-special':'Outro especial'}
lines += ['| PC | '+' | '.join(labels[mode] for mode in modes)+' | Interpretados |',
          '|---|'+'---:|'*(len(modes)+1)]
for row in coverage:
    lines.append('| `'+row['pc']+'` | '+' | '.join(str(row[f'{mode}_native_hits']) for mode in modes)+f' | {row["interpreted_total"]} |')
if coverage_gaps: lines += ['','## Lacunas de cobertura','']+[f'- {item}' for item in coverage_gaps]
if safety_errors: lines += ['','## Erros tecnicos','']+[f'- {item}' for item in safety_errors]
(session/'summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
if safety_errors:
    print('ERRO tecnico: '+'; '.join(safety_errors),file=sys.stderr)
    raise SystemExit(1)
if coverage_gaps:
    print('Comparacao tecnicamente CLEAN; cobertura em REVIEW: '+'; '.join(coverage_gaps))
    raise SystemExit(2)
print(f'Comparacao CLEAN: {session}')
PY
}

finish_comparison() {
    local result
    if compare_results; then
        mv "$ACTIVE_STATE" "$SESSION_DIR/completed.state"
        printf '\nCobertura concluida. Resumo: %s/summary.md\n' "$SESSION_DIR"
        return
    else
        result=$?
    fi
    if [[ "$result" -eq 2 ]]; then
        printf '\nColetas tecnicamente validas; cobertura incompleta.\n'
        printf 'A sessao ativa foi preservada: %s\n' "$SESSION_DIR"
        return
    fi
    return "$result"
}

create_session() {
    make_session_dir
    {
        printf 'track=OVL-002G-DDARK-BOMB-STATE-COVERAGE\nruntime_dir=%s\n' "$RUNTIME_DIR"
        printf 'source_result=%s\nsource_sha256=%s\n' "$SOURCE_RESULT" "$EXPECTED_SOURCE_SHA"
        printf 'prepare_seconds=%s\nduration_seconds=%s\n' "$PREPARE_SECONDS" "$CAPTURE_SECONDS"
        printf 'route=D.Dark P1 x Ryu P2; cenario Ryu; quatro janelas controladas\nstarted_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
    write_state
}

run_phase() {
    local mode="$1" base phase_dir result_path
    if [[ -f "$ACTIVE_STATE" ]]; then read_state
    else
        [[ "$mode" == no-hit ]] || fail "Inicie a comparacao com no-hit."
        create_session
    fi
    case "$mode" in
        no-hit) base=phase-01-no-hit ;;
        hit) base=phase-02-hit ;;
        block) base=phase-03-block ;;
        special) base=phase-04-special ;;
        other-special) base=phase-05-other-special ;;
    esac
    phase_dir="$(next_phase_dir "$base")"
    printf '\nD.Dark P1 x Ryu P2, cenario do Ryu. Fase: %s.\n' "$mode"
    case "$mode" in
        no-hit) printf 'Repita bombas dos dois lados sem colisao e aguarde o ciclo completo.\n' ;;
        hit) printf 'Ryu neutro: use somente bombas e faca-as acertarem Ryu.\n' ;;
        block) printf 'Ryu defendendo: use somente bombas e faca-as atingir a defesa.\n' ;;
        special) printf 'Execute somente o especial/super do D.Dark relacionado a bombas, permitindo acertos.\n' ;;
        other-special) printf 'Execute somente o outro especial/super do D.Dark, diferente da bomba explosiva que lanca Ryu.\nExecute no maximo uma vez de cada lado e pare antes do KO.\n' ;;
    esac
    read -r -p "Pressione Enter quando o gameplay estiver controlavel: "
    observe "$mode" "$phase_dir"
    result_path="$phase_dir/result.json"
    case "$mode" in
        no-hit) NO_HIT_RESULT="$result_path" ;;
        hit) HIT_RESULT="$result_path" ;;
        block) BLOCK_RESULT="$result_path" ;;
        special) SPECIAL_RESULT="$result_path" ;;
        other-special) OTHER_SPECIAL_RESULT="$result_path" ;;
    esac
    write_state
    if [[ -n "$NO_HIT_RESULT" && -n "$HIT_RESULT" && -n "$BLOCK_RESULT" && -n "$SPECIAL_RESULT" ]]; then
        finish_comparison
    else
        printf '\nFase %s concluida. Execute status para ver as partes pendentes.\n' "$mode"
    fi
}

compare_existing() {
    read_state
    for result in "$NO_HIT_RESULT" "$HIT_RESULT" "$BLOCK_RESULT" "$SPECIAL_RESULT"; do
        [[ -n "$result" && -f "$result" ]] || fail "As quatro fases ainda nao estao completas."
    done
    finish_comparison
}

show_status() {
    if [[ ! -f "$ACTIVE_STATE" ]]; then printf 'Nenhuma comparacao de estados ativa.\n'; return; fi
    printf 'Sessao: %s\n' "$(state_value "$ACTIVE_STATE" session_dir)"
    for key in no_hit_result hit_result block_result special_result other_special_result; do
        local value; value="$(state_value "$ACTIVE_STATE" "$key")"
        printf '%s: %s\n' "$key" "${value:-PENDENTE}"
    done
}

main() {
    case "${1:-}" in
        no-hit|hit|block|special|other-special) validate; run_phase "$1" ;;
        compare) validate; compare_existing ;;
        status) show_status ;;
        -h|--help) usage ;;
        *) usage; fail "Use no-hit, hit, block, special, other-special, compare ou status." ;;
    esac
}

main "$@"
