#!/usr/bin/env bash
# Descoberta diferencial de codigo interpretado em janelas BEFORE/AFTER.
# A primeira janela concluida e a baseline; as demais sao comparadas a ela.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002c_test.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002c-current-runtime.state"
readonly ACTIVE_STATE="$PROJECT_ROOT/local/telemetry/.ovl-002c-special-events-active.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F

PYTHON_BIN=
DEBUG_PORT=
RUNTIME_DIR=
RUNTIME_EXE=
CACHE_MANIFEST=
SESSION_DIR=
PHASE=
EVENT_COUNT=0
PENDING_DIR=
BASELINE_EVENT=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com o runtime OVL-002C aberto:

  bash tools/observe_interpreted_special_events_ovl_002c.sh prepare
  bash tools/observe_interpreted_special_events_ovl_002c.sh before
  bash tools/observe_interpreted_special_events_ovl_002c.sh after
  bash tools/observe_interpreted_special_events_ovl_002c.sh finish

PREPARE e executado dentro do primeiro gameplay Versus, com Ryu P1 x Ryu P2.
A primeira janela BEFORE/AFTER deve manter ambos neutros e vira a referencia
automatica. Training e recusado porque carrega outra variante de overlay.
Depois de cada AFTER o script solicita a tag, preserva a janela e fica pronto
para outro BEFORE. Durante a janela de gameplay nao ocorre polling TCP.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_runtime() {
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-002C ausente. Execute compile_ovl_002c_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"; RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002c-test-runtime-*) ;; *) fail "Runtime OVL-002C invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" capture_key)" == 0x00020000:0xF943B63B ]] || fail "Chave OVL-002C divergente."
    [[ "$(state_value "$RUNTIME_STATE" target)" == 0x80049568 ]] || fail "Raiz OVL-002C divergente."
    [[ "$(state_value "$RUNTIME_STATE" image_body_words)" == 2074 ]] || fail "Volume OVL-002C divergente."
    [[ -f "$RUNTIME_EXE" && -f "$CACHE_MANIFEST" ]] || fail "Runtime OVL-002C incompleto."
}

read_debug_port() {
    DEBUG_PORT="$(awk '/^[[:space:]]*\[runtime\]/{ok=1;next} /^[[:space:]]*\[/{ok=0} ok&&/^[[:space:]]*debug_port[[:space:]]*=/{sub(/^[^=]*=/,"");gsub(/[[:space:]]+/,"");print;exit}' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida."
}

validate_common() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep mkdir mv seq; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python; read_runtime; read_debug_port
    for file in "$TEST_CONFIG" "$RANGES_FILE" "$RUNTIME_EXE" "$CACHE_MANIFEST"; do [[ -f "$file" ]] || fail "Arquivo ausente: $file"; done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel OVL-002C divergiu."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); data=json.loads(pathlib.Path(sys.argv[2]).read_text(encoding='utf-8'))
if data.get('track')!='OVL-002C-DDARK-BOMBS-CUMULATIVE': raise SystemExit('manifesto nao pertence a OVL-002C')
if int(data.get('incremental_words',0))!=966 or int(data.get('image_body_words',0))!=2074: raise SystemExit('volumes OVL-002C divergiram')
if data.get('new_aliases')!=['0x80049808','0x80049988']: raise SystemExit('aliases OVL-002C divergiram')
for item in data.get('files',[]):
    path=root/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']): raise SystemExit(f'cache ausente: {item["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']: raise SystemExit(f'cache alterado: {item["path"]}')
PY
}

make_session_dir() {
    local suffix candidate; mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-002c-special-events-discovery-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; SESSION_DIR="$candidate"; return; fi
    done
    fail "Nao ha pasta livre para a descoberta de especiais."
}

write_state() {
    umask 077
    {
        printf 'session_dir=%s\nruntime_dir=%s\nphase=%s\nevent_count=%s\n' "$SESSION_DIR" "$RUNTIME_DIR" "$1" "$2"
        printf 'pending_dir=%s\nbaseline_event=%s\n' "${3:-}" "${4:-}"
    } >"$ACTIVE_STATE"
}

read_state() {
    [[ -f "$ACTIVE_STATE" ]] || fail "Nao existe sessao ativa; execute prepare."
    SESSION_DIR="$(state_value "$ACTIVE_STATE" session_dir)"; PHASE="$(state_value "$ACTIVE_STATE" phase)"
    EVENT_COUNT="$(state_value "$ACTIVE_STATE" event_count)"; PENDING_DIR="$(state_value "$ACTIVE_STATE" pending_dir)"
    BASELINE_EVENT="$(state_value "$ACTIVE_STATE" baseline_event)"
    [[ "$(state_value "$ACTIVE_STATE" runtime_dir)" == "$RUNTIME_DIR" ]] || fail "Runtime mudou durante a sessao."
    case "$SESSION_DIR" in "$PROJECT_ROOT"/local/telemetry/ovl-002c-special-events-discovery-*) ;; *) fail "Sessao ativa invalida." ;; esac
    [[ "$EVENT_COUNT" =~ ^[0-9]+$ ]] || fail "Contador de eventos invalido."
}

runtime_prepare() {
    "$PYTHON_BIN" - "$DEBUG_PORT" "$SESSION_DIR" "$RUNTIME_DIR" <<'PY'
import json,pathlib,socket,sys,time
port=int(sys.argv[1]); session=pathlib.Path(sys.argv[2]); runtime=pathlib.Path(sys.argv[3])
def request(command,**args):
 wire=json.dumps({'id':1,'cmd':command,**args},separators=(',',':'))+'\n'; chunks=[]
 with socket.create_connection(('127.0.0.1',port),timeout=5) as sock:
  sock.settimeout(30); sock.sendall(wire.encode())
  while True:
   part=sock.recv(65536)
   if not part: break
   chunks.append(part)
 if not chunks: raise RuntimeError(f'{command}: resposta vazia')
 out=json.loads(b''.join(chunks).decode())
 if not out.get('ok'): raise RuntimeError(f'{command} rejeitado: {out}')
 return out
request('overlay_native_block',clear=1); request('overlay_diff_off')
loader=request('overlay_loader_status'); shadow=request('overlay_shadow_dump').get('shadow',{})
errors=[]
if not int(loader.get('active',0) or 0): errors.append('overlay cache inativo')
if pathlib.Path(str(loader.get('cache_dir',''))).resolve()!=(runtime/'cache').resolve(): errors.append('cache_dir inesperado')
if int(loader.get('range_index_overflow',0) or 0) or int(loader.get('lazy_manifest_overflow',0) or 0): errors.append('overflow do loader')
if int(shadow.get('diff_mode',1)) or int(shadow.get('shadow_calls',0)) or int(shadow.get('in_shadow',0)) or int(shadow.get('native_exec',0))!=1: errors.append('estado shadow/native invalido')
result={'prepared_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'loader':loader,'shadow':shadow,'errors':errors}
(session/'prepare-runtime.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
if errors: raise RuntimeError('; '.join(errors))
print('Runtime OVL-002C confirmado; shadow desligado e cache cumulativo ativo.')
PY
}

take_snapshot() {
    local moment="$1" output="$2"
    "$PYTHON_BIN" - "$DEBUG_PORT" "$moment" "$output" <<'PY'
import json,pathlib,socket,struct,sys,time,zlib
port=int(sys.argv[1]); moment=sys.argv[2]; output=pathlib.Path(sys.argv[3])
def request(command,**args):
 wire=json.dumps({'id':1,'cmd':command,**args},separators=(',',':'))+'\n'; chunks=[]
 with socket.create_connection(('127.0.0.1',port),timeout=5) as sock:
  sock.settimeout(30); sock.sendall(wire.encode())
  while True:
   part=sock.recv(65536)
   if not part: break
   chunks.append(part)
 if not chunks: raise RuntimeError(f'{command}: resposta vazia')
 out=json.loads(b''.join(chunks).decode())
 if not out.get('ok'): raise RuntimeError(f'{command} rejeitado: {out}')
 return out
def paged(command,count_key,**args):
 offset=0; rows={}; header={}
 while True:
  page=request(command,offset=offset,limit=256,**args)
  if not header: header={k:v for k,v in page.items() if k!='entries'}
  for row in page.get('entries',[]):
   if row.get('pc'): rows[f'0x{int(str(row["pc"]),16):08X}']=row
  returned=int(page.get('returned',0) or 0); total=int(page.get(count_key,0) or 0); offset+=returned
  if returned==0 or offset>=total: break
  if offset>65536: raise RuntimeError(f'{command}: paginacao excedida')
 header['entries']=list(rows.values()); return header
expected={0x80049568:0x9611F1A0,0x80049808:0xCB050F22,0x80049988:0x6D2C8CD6,0x80092C2C:0x1B64D20F,0x80093E4C:0x12FF550F}
boundary_ns=time.monotonic_ns() if moment=='after' else 0
if moment=='after':
 dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
 static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
diagnostics={x:request(x) for x in ('overlay_loader_status','dirty_ram_stats','dispatch_stats','overlay_shadow_dump')}
live={}; errors=[]
for pc,wanted in expected.items():
 words=request('mem_words',addr=f'0x{pc:08X}',count=32).get('words',[])
 crc=zlib.crc32(b''.join(struct.pack('<I',int(x,16)) for x in words))&0xffffffff if len(words)==32 else -1
 candidates=request('overlay_candidates',pc=f'0x{pc:08X}').get('candidates',[])
 exact=any(int(x.get('match',0))==1 and int(x.get('state',9))==0 and int(x.get('dll',-1))>=0 and int(x.get('device_touch',1))==0 for x in candidates)
 live[f'0x{pc:08X}']={'crc32':f'0x{crc&0xffffffff:08X}','expected_crc32':f'0x{wanted:08X}','candidate_exact_active':exact}
 if crc!=wanted or not exact: errors.append(f'0x{pc:08X}: identidade viva divergente')
if moment=='before':
 static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
 dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
 boundary_ns=time.monotonic_ns()
result={'moment':moment,'boundary_monotonic_ns':boundary_ns,'captured_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
        'static':static,'dynamic':dynamic,'diagnostics':diagnostics,'live_gate':live,'errors':errors}
output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
if errors: raise RuntimeError('; '.join(errors))
print(f'Snapshot {moment.upper()} concluido; limite temporal registrado.')
PY
}

sanitize_tag() {
    "$PYTHON_BIN" -c 'import re,sys,unicodedata; s=unicodedata.normalize("NFKD",sys.argv[1]).encode("ascii","ignore").decode().lower(); s=re.sub(r"[^a-z0-9]+","-",s).strip("-")[:48]; print(s or "evento")' "$1"
}

finalize_event() {
    local tag="$1" event_dir="$2"
    "$PYTHON_BIN" - "$PENDING_DIR/before.json" "$PENDING_DIR/after.json" "$event_dir" "$tag" "$BASELINE_EVENT" "$RANGES_FILE" <<'PY'
import csv,json,pathlib,sys
before=json.loads(pathlib.Path(sys.argv[1]).read_text()); after=json.loads(pathlib.Path(sys.argv[2]).read_text())
out=pathlib.Path(sys.argv[3]); tag=sys.argv[4]; baseline_path=pathlib.Path(sys.argv[5]) if sys.argv[5] else None
ranges_path=pathlib.Path(sys.argv[6]); out.mkdir(parents=False,exist_ok=False)
def index(snapshot): return {f'0x{int(str(x["pc"]),16):08X}':x for x in snapshot.get('entries',[]) if x.get('pc')}
def delta(a,b,key): return max(0,int(b.get(key,0) or 0)-int(a.get(key,0) or 0))
bs=index(before['static']); ns=index(after['static']); bd=index(before['dynamic']); nd=index(after['dynamic'])
duration=max(0.001,(int(after['boundary_monotonic_ns'])-int(before['boundary_monotonic_ns']))/1e9)
native_ranges=[]
for line in ranges_path.read_text().splitlines():
 p=line.split()
 if len(p)==3 and p[0]=='R': native_ranges.append((int(p[1],16),int(p[1],16)+int(p[2],16)))
baseline={}
if baseline_path and (baseline_path/'result.json').is_file():
 baseline={x['pc']:x for x in json.loads((baseline_path/'result.json').read_text()).get('entries',[])}
rows=[]
for pc in sorted(set(ns)|set(nd)):
 s0,s1=bs.get(pc,{}),ns.get(pc,{}); d0,d1=bd.get(pc,{}),nd.get(pc,{})
 static=sum(delta(s0,s1,k) for k in ('misses','modified','runtime','unknown')); dynamic=delta(d0,d1,'entry_hits')
 insns=delta(d0,d1,'insns'); blocks=delta(d0,d1,'hits')
 if not static and not dynamic and not insns: continue
 rate=insns/duration; base=float(baseline.get(pc,{}).get('insns_per_s',0) or 0); addr=int(pc,16)
 rows.append({'pc':pc,'external_entries':max(static,dynamic),'static_entries':static,'dynamic_entries':dynamic,
              'interpreted_blocks':blocks,'interpreted_insns':insns,'insns_per_s':rate,'baseline_insns_per_s':base,
              'excess_insns_per_s':max(0.0,rate-base),'new_vs_baseline':bool(baseline_path and rate>0 and base==0),
              'covered_by_static_range':any(a<=addr<b for a,b in native_ranges)})
rows.sort(key=lambda x:(not x['new_vs_baseline'],-x['excess_insns_per_s'],-x['interpreted_insns'],x['pc']))
def diag_delta(group,key): return delta(before['diagnostics'][group],after['diagnostics'][group],key)
loader={k:diag_delta('overlay_loader_status',k) for k in ('dispatch_native','dispatch_interp_fallback','stale_blocked','invalidations','unregistered_funcs')}
guards={k:diag_delta('dirty_ram_stats',k) for k in ('aborts','native_handoffs','text_native_blocked','text_diverged_pages','text_exact_mismatches')}
miss=diag_delta('dispatch_stats','miss_total'); errors=[]
if loader['unregistered_funcs']: errors.append('funcoes nativas desregistradas')
if any(v for k,v in guards.items() if k!='native_handoffs'): errors.append('guard dirty-RAM fatal nao zerado')
if miss: errors.append('miss_total cresceu')
if before.get('errors') or after.get('errors'): errors.append('identidade viva divergente')
if before.get('live_gate')!=after.get('live_gate'): errors.append('CRC/candidato vivo mudou na janela')
result={'tag':tag,'duration_s':duration,'baseline_event':str(baseline_path) if baseline_path else None,'is_baseline':baseline_path is None,
        'entries':rows,'pc_count':len(rows),'new_vs_baseline_count':sum(x['new_vs_baseline'] for x in rows),
        'interpreted_insns':sum(x['interpreted_insns'] for x in rows),'loader_deltas':loader,'guard_deltas':guards,
        'dispatch_miss_delta':miss,'technical_clean':not errors,'errors':errors}
(out/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
(out/'before.json').write_text(json.dumps(before,indent=2,sort_keys=True)+'\n'); (out/'after.json').write_text(json.dumps(after,indent=2,sort_keys=True)+'\n')
cols=['pc','external_entries','static_entries','dynamic_entries','interpreted_blocks','interpreted_insns','insns_per_s','baseline_insns_per_s','excess_insns_per_s','new_vs_baseline','covered_by_static_range']
with (out/'interpreted.csv').open('w',newline='',encoding='utf-8') as f:
 w=csv.DictWriter(f,fieldnames=cols); w.writeheader(); w.writerows(rows)
lines=[f'# Evento {tag}','',f'- Duracao: {duration:.3f} s',f'- PCs interpretados: {len(rows)}',
       f'- PCs novos contra baseline: {result["new_vs_baseline_count"]}',f'- Instrucoes interpretadas: {result["interpreted_insns"]}',
       f'- Status tecnico: {"CLEAN" if result["technical_clean"] else "REVIEW"}','','| PC | Novo | Instr./s | Baseline/s | Excesso/s |','|---|---|---:|---:|---:|']
for x in rows[:40]: lines.append(f'| `{x["pc"]}` | {"sim" if x["new_vs_baseline"] else "nao"} | {x["insns_per_s"]:.1f} | {x["baseline_insns_per_s"]:.1f} | {x["excess_insns_per_s"]:.1f} |')
if errors: lines += ['','## Bloqueios','']+[f'- {x}' for x in errors]
(out/'summary.md').write_text('\n'.join(lines)+'\n')
print(f'Evento preservado: {out}')
print(f'PCs interpretados: {len(rows)}; novos contra baseline: {result["new_vs_baseline_count"]}; status: {"CLEAN" if result["technical_clean"] else "REVIEW"}.')
PY
}

finish_session() {
    "$PYTHON_BIN" - "$SESSION_DIR" <<'PY'
import csv,json,pathlib,sys,time
session=pathlib.Path(sys.argv[1]); events=[]
for path in sorted(session.glob('event-*')):
 if (path/'result.json').is_file(): events.append((path,json.loads((path/'result.json').read_text())))
pcs=sorted({x['pc'] for _,e in events for x in e.get('entries',[])})
matrix=[]
for pc in pcs:
 row={'pc':pc}
 for path,event in events:
  found=next((x for x in event.get('entries',[]) if x['pc']==pc),None)
  row[path.name]=float(found.get('insns_per_s',0)) if found else 0.0
 matrix.append(row)
cols=['pc']+[p.name for p,_ in events]
with (session/'event-matrix.csv').open('w',newline='',encoding='utf-8') as f:
 w=csv.DictWriter(f,fieldnames=cols); w.writeheader(); w.writerows(matrix)
summary={'track':'OVL-002C-SPECIAL-EVENTS-DISCOVERY','events':len(events),'event_names':[p.name for p,_ in events],
         'baseline_event':events[0][0].name if events else None,'completed_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
(session/'result.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n')
lines=['# Descoberta diferencial de especiais - OVL-002C','',f'- Eventos: {len(events)}',f'- Baseline: `{summary["baseline_event"]}`','','| Evento | Duracao | PCs | Novos vs baseline | Status |','|---|---:|---:|---:|---|']
for path,event in events: lines.append(f'| `{path.name}` | {event["duration_s"]:.3f} s | {event["pc_count"]} | {event["new_vs_baseline_count"]} | {"CLEAN" if event["technical_clean"] else "REVIEW"} |')
(session/'summary.md').write_text('\n'.join(lines)+'\n')
print(f'Sessao finalizada: {session}')
PY
}

prepare_phase() {
    [[ ! -f "$ACTIVE_STATE" ]] || fail "Ja existe sessao ativa; conclua com finish."
    make_session_dir; runtime_prepare
    {
        printf 'track=OVL-002C-SPECIAL-EVENTS-DISCOVERY\nruntime_dir=%s\n' "$RUNTIME_DIR"
        printf 'baseline_route=Versus Ryu P1 x Ryu P2 neutros; tempo infinito\nprepared_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
    write_state prepared 0 '' ''
    printf '\nPREPARE concluido no Versus Ryu P1 x Ryu P2. Deixe ambos neutros.\n'
    printf 'Execute BEFORE no primeiro trecho controlavel. Training nao e compativel com este gate.\n'
}

before_phase() {
    read_state
    [[ "$PHASE" == prepared || "$PHASE" == ready ]] || fail "BEFORE exige fase prepared/ready; fase atual: $PHASE."
    local next=$((EVENT_COUNT+1)); PENDING_DIR="$SESSION_DIR/.pending-event-$(printf '%02d' "$next")"
    [[ ! -e "$PENDING_DIR" ]] || fail "Diretorio pendente ja existe: $PENDING_DIR"
    mkdir "$PENDING_DIR"
    note "Capturando BEFORE do evento $next"
    if ! take_snapshot before "$PENDING_DIR/before.json"; then
        local failed_dir="$SESSION_DIR/failed-before-$(printf '%02d' "$next")-imagem-incompativel"
        mv "$PENDING_DIR" "$failed_dir"
        fail "BEFORE rejeitado e preservado em $failed_dir. A familia OVL-002C exige Versus/F943B63B; Training usa outra imagem."
    fi
    write_state capturing "$EVENT_COUNT" "$PENDING_DIR" "$BASELINE_EVENT"
    printf '\nBEFORE concluido: a janela esta aberta. Execute somente a acao desejada.\n'
    printf 'No final exato da acao, execute AFTER.\n'
}

after_phase() {
    read_state; [[ "$PHASE" == capturing ]] || fail "AFTER exige fase capturing; fase atual: $PHASE."
    [[ -d "$PENDING_DIR" && -f "$PENDING_DIR/before.json" ]] || fail "Snapshot BEFORE pendente ausente."
    note "Fechando a janela no primeiro instante do AFTER"
    take_snapshot after "$PENDING_DIR/after.json"
    printf '\nJanela encerrada e congelada. Agora informe o contexto sem risco de contaminar a coleta.\n'
    local raw_tag tag next event_dir
    read -r -p "Tag deste evento: " raw_tag || fail "Nao foi possivel ler a tag."
    tag="$(sanitize_tag "$raw_tag")"; next=$((EVENT_COUNT+1)); event_dir="$SESSION_DIR/event-$(printf '%02d' "$next")-$tag"
    [[ ! -e "$event_dir" ]] || fail "Evento ja existe: $event_dir"
    finalize_event "$tag" "$event_dir"
    if [[ "$EVENT_COUNT" -eq 0 ]]; then BASELINE_EVENT="$event_dir"; fi
    mv "$PENDING_DIR" "$event_dir/raw-pending"
    EVENT_COUNT="$next"; write_state ready "$EVENT_COUNT" '' "$BASELINE_EVENT"
    printf '\nEvento concluido. Prepare a proxima rota e execute BEFORE novamente.\n'
    printf 'Quando terminar todas as rotas, execute: bash tools/observe_interpreted_special_events_ovl_002c.sh finish\n'
}

finish_phase() {
    read_state; [[ "$PHASE" == prepared || "$PHASE" == ready ]] || fail "Nao finalize durante uma janela aberta."
    [[ "$EVENT_COUNT" -gt 0 ]] || fail "Nenhum evento foi coletado."
    finish_session
    mv "$ACTIVE_STATE" "$SESSION_DIR/completed.state"
    printf 'Resumo: %s/summary.md\n' "$SESSION_DIR"
}

main() {
    case "${1:-}" in prepare|before|after|finish) ;; -h|--help) usage; return ;; *) usage; fail "Use prepare, before, after ou finish." ;; esac
    validate_common
    case "$1" in prepare) prepare_phase ;; before) before_phase ;; after) after_phase ;; finish) finish_phase ;; esac
}

main "$@"
