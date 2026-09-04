#!/usr/bin/env bash
# Separa movimento comum, movimento do D.Dark e bombas no residuo OVL-002E.
# Nao compila, nao gera fontes e nao abre/fecha o jogo.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002e_test.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002e-current-runtime.state"
readonly ACTIVE_STATE="$PROJECT_ROOT/local/telemetry/.ovl-002e-ddark-44c7c-active.state"
readonly SOURCE_RESULT="$PROJECT_ROOT/local/telemetry/ovl-002e-ddark-bombs-discovery-01/result.json"
readonly EXPECTED_SOURCE_SHA=DC65D829667A68AB2C1A7C354BBE389DF5258E128C0D92675A7CF9473483AE70
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
PHASE=
RYU_RESULT=
DDARK_MOVE_RESULT=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, mantendo o mesmo runtime OVL-002E aberto:

  bash tools/observer_ddark_44c7c_ovl_002e.sh ryu-move
  bash tools/observer_ddark_44c7c_ovl_002e.sh ddark-move
  bash tools/observer_ddark_44c7c_ovl_002e.sh ddark-bombs
  bash tools/observer_ddark_44c7c_ovl_002e.sh status

Parte 1 - ryu-move:
  D.Dark P1 x Ryu P2, cenario do Ryu. Mantenha D.Dark parado e mova somente
  Ryu, incluindo caminhada, salto e agachamento, sem executar golpes.

Parte 2 - ddark-move:
  D.Dark P1 x Ryu P2, mesmo cenario. Mantenha Ryu parado e mova somente
  D.Dark, incluindo caminhada, salto e agachamento, sem executar golpes.

Parte 3 - ddark-bombs:
  D.Dark P1 x Ryu P2. Repita somente bombas dos dois lados, sem acertar Ryu.
  Faca apenas o movimento minimo necessario para executar e reposicionar.

Cada janela dura 30 s e nao consulta o runtime durante a acao. O comparador
usa os 27 PCs residuais fixados pela coleta OVL-002E e destaca 0x80044C7C.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_runtime() {
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-002E ausente. Execute compile_ovl_002e_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"
    RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002e-test-runtime-*) ;; *) fail "Runtime OVL-002E invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" capture_key)" == 0x00020000:0xF943B63B ]] || fail "Chave OVL-002E divergente."
    [[ "$(state_value "$RUNTIME_STATE" target)" == 0x80044830 ]] || fail "Raiz OVL-002E divergente."
    [[ "$(state_value "$RUNTIME_STATE" image_body_words)" == 2418 ]] || fail "Volume OVL-002E divergente."
    [[ -f "$RUNTIME_EXE" && -f "$CACHE_MANIFEST" ]] || fail "Runtime OVL-002E incompleto."
}

read_debug_port() {
    DEBUG_PORT="$(awk '/^[[:space:]]*\[runtime\]/{ok=1;next} /^[[:space:]]*\[/{ok=0} ok&&/^[[:space:]]*debug_port[[:space:]]*=/{sub(/^[^=]*=/,"");gsub(/[[:space:]]+/,"");print;exit}' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" == 4533 ]] || fail "debug_port OVL-002E divergente."
}

validate_common() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk seq mv; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python; read_runtime; read_debug_port
    for file in "$TEST_CONFIG" "$RANGES_FILE" "$RUNTIME_EXE" "$CACHE_MANIFEST" "$SOURCE_RESULT"; do
        [[ -f "$file" ]] || fail "Arquivo ausente: $file"
    done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel OVL-002E divergiu."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    [[ "$(sha256sum "$SOURCE_RESULT" | awk '{print toupper($1)}')" == "$EXPECTED_SOURCE_SHA" ]] || fail "Coleta residual OVL-002E divergiu."
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" "$SOURCE_RESULT" <<'PY'
import hashlib,json,pathlib,sys
runtime=pathlib.Path(sys.argv[1]); manifest=json.loads(pathlib.Path(sys.argv[2]).read_text(encoding='utf-8'))
source=json.loads(pathlib.Path(sys.argv[3]).read_text(encoding='utf-8'))
if manifest.get('track')!='OVL-002E-DDARK-BOMB-RESIDUAL-CUMULATIVE': raise SystemExit('manifesto nao pertence a OVL-002E')
if int(manifest.get('image_body_words',0))!=2418: raise SystemExit('manifesto OVL-002E com volume divergente')
for item in manifest.get('files',[]):
    path=runtime/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']): raise SystemExit(f'cache ausente: {item["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']: raise SystemExit(f'cache alterado: {item["path"]}')
pcs=[str(row.get('pc','')).lower() for row in source.get('entries',[])]
if source.get('track')!='OVL-002E-DDARK-BOMBS-DISCOVERY' or len(pcs)!=27 or len(set(pcs))!=27:
    raise SystemExit('coleta residual nao contem exatamente os 27 PCs esperados')
if pcs.count('0x80044c7c')!=1: raise SystemExit('0x80044C7C ausente ou duplicado na coleta residual')
PY
}

make_session_dir() {
    local suffix candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-002e-ddark-44c7c-route-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; SESSION_DIR="$candidate"; return; fi
    done
    fail "Nao ha pasta livre para a comparacao de rota."
}

next_phase_dir() {
    local base="$1" suffix candidate
    candidate="$SESSION_DIR/$base"
    if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    for suffix in $(seq -w 2 99); do
        candidate="$SESSION_DIR/$base-retry-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    done
    fail "Nao ha pasta livre para repetir a fase $base."
}

write_state() {
    umask 077
    {
        printf 'session_dir=%s\nruntime_dir=%s\nphase=%s\n' "$SESSION_DIR" "$RUNTIME_DIR" "$1"
        printf 'source_sha256=%s\nryu_result=%s\nddark_move_result=%s\n' "$EXPECTED_SOURCE_SHA" "${2:-}" "${3:-}"
    } >"$ACTIVE_STATE"
}

read_state() {
    [[ -f "$ACTIVE_STATE" ]] || fail "Comparacao ausente. Execute primeiro ryu-move."
    SESSION_DIR="$(state_value "$ACTIVE_STATE" session_dir)"; PHASE="$(state_value "$ACTIVE_STATE" phase)"
    RYU_RESULT="$(state_value "$ACTIVE_STATE" ryu_result)"; DDARK_MOVE_RESULT="$(state_value "$ACTIVE_STATE" ddark_move_result)"
    [[ "$(state_value "$ACTIVE_STATE" runtime_dir)" == "$RUNTIME_DIR" ]] || fail "Runtime mudou entre as fases."
    [[ "$(state_value "$ACTIVE_STATE" source_sha256)" == "$EXPECTED_SOURCE_SHA" ]] || fail "Coleta residual mudou entre as fases."
    case "$SESSION_DIR" in "$PROJECT_ROOT"/local/telemetry/ovl-002e-ddark-44c7c-route-*) ;; *) fail "Diretorio de sessao invalido." ;; esac
}

capture_phase() {
    local mode="$1" output_dir="$2"
    "$PYTHON_BIN" - "$DEBUG_PORT" "$output_dir" "$SOURCE_RESULT" "$RUNTIME_DIR" "$mode" "$PREPARE_SECONDS" "$CAPTURE_SECONDS" <<'PY'
import csv,json,pathlib,socket,struct,sys,time,zlib
port=int(sys.argv[1]); out=pathlib.Path(sys.argv[2]); source_path=pathlib.Path(sys.argv[3]); runtime=pathlib.Path(sys.argv[4])
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
def evidence(targets):
    result={}
    for pc in targets:
        item={'pc':pc}
        words=request('mem_words',addr=pc,count=32).get('words',[]); item['word_count']=len(words)
        if words:
            blob=b''.join(struct.pack('<I',int(word,16)) for word in words)
            item['prefix_crc32']=f'0x{zlib.crc32(blob)&0xffffffff:08X}'
        item['overlay_candidates']=request('overlay_candidates',pc=pc).get('candidates',[])
        result[pc]=item
    return result

source=json.loads(source_path.read_text(encoding='utf-8'))
targets=[f'0x{int(str(row["pc"]),16):08X}' for row in source['entries']]
probe=request('overlay_loader_status'); expected_cache=(runtime/'cache').resolve(); actual_cache=pathlib.Path(str(probe.get('cache_dir',''))).resolve()
errors=[]
if not int(probe.get('active',0) or 0): errors.append('overlay cache OVL-002E inativo')
if actual_cache!=expected_cache: errors.append(f'cache conectado divergiu: {actual_cache}')

expected_live={0x80044830:0x9E9CD462,0x8004485C:0x3596728A,0x800448EC:0xCD23F9BE,0x80044984:0xFE5E309A,
               0x80044A68:0xCE5EABF9,0x80044AF8:0xB9E07A5F,0x80044B8C:0xD7D51FE0,0x80047DE8:0xBEFA5EA1,
               0x80049568:0x9611F1A0,0x80049808:0xCB050F22,0x80049988:0x6D2C8CD6,0x80092C2C:0x1B64D20F,0x80093E4C:0x12FF550F}
identity={'mode':mode,'expected_cache_dir':str(expected_cache),'actual_cache_dir':str(actual_cache),'pcs':{},'errors':errors}
if mode in ('ryu-move','ddark-move','ddark-bombs'):
    for pc,wanted in expected_live.items():
        words=request('mem_words',addr=f'0x{pc:08X}',count=32).get('words',[])
        crc=zlib.crc32(b''.join(struct.pack('<I',int(word,16)) for word in words))&0xffffffff if len(words)==32 else -1
        candidates=request('overlay_candidates',pc=f'0x{pc:08X}').get('candidates',[])
        exact=any(int(item.get('match',0))==1 and int(item.get('state',9))==0 and int(item.get('dll',-1))>=0 and int(item.get('device_touch',1))==0 for item in candidates)
        identity['pcs'][f'0x{pc:08X}']={'crc32':f'0x{crc&0xffffffff:08X}','expected':f'0x{wanted:08X}','candidate_exact_active':exact}
        if crc!=wanted or not exact: errors.append(f'0x{pc:08X}: identidade D.Dark OVL-002E divergente')
identity['errors']=errors
(out/'runtime-identity.json').write_text(json.dumps(identity,indent=2,sort_keys=True)+'\n',encoding='utf-8')
if errors: raise RuntimeError('; '.join(errors))

before_evidence=evidence(targets)
request('pc_watch_clear')
for pc in targets: request('pc_watch_arm',target=pc)
for remaining in range(prepare_s,0,-1): print(f'Prepare-se: {remaining}...',flush=True); time.sleep(1)
before_static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
before_dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
before_diag={name:request(name) for name in ('overlay_loader_status','dirty_ram_stats','dispatch_stats')}
request('pc_watch_reset')
actions={'ryu-move':'mantenha D.Dark parado e mova somente Ryu sem golpes','ddark-move':'mantenha Ryu parado e mova somente D.Dark sem golpes',
         'ddark-bombs':'repita somente bombas sem acertar Ryu'}
print(f'\a[CAPTURANDO] Por {capture_s} s, {actions[mode]}.',flush=True)
started=time.monotonic(); time.sleep(capture_s); elapsed=time.monotonic()-started
request('pc_watch_stop')
after_dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
after_static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
after_diag={name:request(name) for name in ('overlay_loader_status','dirty_ram_stats','dispatch_stats')}; watch=request('pc_watch_dump')
after_evidence=evidence(targets)
print('\a\a[FIM DA CAPTURA] Pare as acoes.',flush=True)

before_s,before_d,after_s,after_d=map(index,(before_static,before_dynamic,after_static,after_dynamic)); rows=[]
for pc in targets:
    s0,s1=before_s.get(pc,{}),after_s.get(pc,{}); d0,d1=before_d.get(pc,{}),after_d.get(pc,{})
    static=sum(delta(s0,s1,key) for key in ('misses','modified','runtime','unknown')); entries=delta(d0,d1,'entry_hits')
    insns=delta(d0,d1,'insns'); blocks=delta(d0,d1,'hits')
    rows.append({'pc':pc,'external_entries':max(static,entries),'static_entries':static,'dynamic_entries':entries,
                 'interpreted_blocks':blocks,'interpreted_insns':insns,'entries_per_s':max(static,entries)/elapsed,'insns_per_s':insns/elapsed})
rows.sort(key=lambda item:(-item['interpreted_insns'],-item['external_entries'],item['pc']))
loader={key:delta(before_diag['overlay_loader_status'],after_diag['overlay_loader_status'],key) for key in ('dispatch_native','unregistered_funcs','invalidations','stale_blocked')}
guards={key:delta(before_diag['dirty_ram_stats'],after_diag['dirty_ram_stats'],key) for key in ('aborts','text_native_blocked','text_diverged_pages','text_exact_mismatches')}
miss=delta(before_diag['dispatch_stats'],after_diag['dispatch_stats'],'miss_total'); fatal=[]
if loader['unregistered_funcs'] or any(guards.values()) or miss: fatal.append('diagnostico de seguranca nao zerado')
changed=[pc for pc in targets if before_evidence.get(pc,{}).get('prefix_crc32')!=after_evidence.get(pc,{}).get('prefix_crc32')]
if changed: fatal.append('corpo vivo mudou durante a janela: '+', '.join(changed))
result={'track':'OVL-002E-DDARK-44C7C-ROUTE-COMPARISON','mode':mode,'duration_s':elapsed,'target_count':len(targets),
        'interpreted_target_count':sum(1 for row in rows if row['interpreted_insns'] or row['external_entries']),
        'target_interpreted_insns':sum(row['interpreted_insns'] for row in rows),'focus_80044C7C':next(row for row in rows if row['pc'].lower()=='0x80044c7c'),
        'loader_deltas':loader,'guard_deltas':guards,'dispatch_miss_delta':miss,'technical_clean':not fatal,'errors':fatal,'entries':rows}
for name,data in [('before-static.json',before_static),('before-dynamic.json',before_dynamic),('after-static.json',after_static),
                  ('after-dynamic.json',after_dynamic),('before-diagnostics.json',before_diag),('after-diagnostics.json',after_diag),
                  ('before-live-evidence.json',before_evidence),('after-live-evidence.json',after_evidence),('pc-watch.json',watch),('result.json',result)]:
    (out/name).write_text(json.dumps(data,indent=2,sort_keys=True)+'\n',encoding='utf-8')
with (out/'targets.csv').open('w',encoding='utf-8',newline='') as handle:
    writer=csv.DictWriter(handle,fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
titles={'ryu-move':'D.Dark parado - Ryu em movimento','ddark-move':'Ryu parado - D.Dark em movimento','ddark-bombs':'D.Dark P1 - bombas sem acerto'}
focus=result['focus_80044C7C']
lines=[f'# {titles[mode]}','',f'- Duracao: {elapsed:.3f} s',f'- PCs-alvo: {len(targets)}',f'- PCs-alvo disparados: {result["interpreted_target_count"]}',
       f'- Instrucoes interpretadas nos alvos: {result["target_interpreted_insns"]}',f'- 0x80044C7C: {focus["interpreted_insns"]} instrucoes',
       f'- Status tecnico: {"CLEAN" if not fatal else "REVIEW"}','','| PC | Entradas | Instrucoes | Instrucoes/s |','|---|---:|---:|---:|']
for row in rows:
    if row['interpreted_insns'] or row['external_entries']: lines.append(f'| `{row["pc"]}` | {row["external_entries"]} | {row["interpreted_insns"]} | {row["insns_per_s"]:.1f} |')
if fatal: lines += ['','## Bloqueios','']+[f'- {item}' for item in fatal]
(out/'summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
if fatal: raise RuntimeError('; '.join(fatal))
print(f'Fase concluida: {out}')
PY
}

compare_results() {
    local bombs_result="$1"
    "$PYTHON_BIN" - "$SESSION_DIR" "$RYU_RESULT" "$DDARK_MOVE_RESULT" "$bombs_result" <<'PY'
import csv,json,pathlib,sys
session=pathlib.Path(sys.argv[1]); paths=[pathlib.Path(item) for item in sys.argv[2:5]]
results=[json.loads(path.read_text(encoding='utf-8')) for path in paths]
evidence=[json.loads((path.parent/'after-live-evidence.json').read_text(encoding='utf-8')) for path in paths]
maps=[{row['pc']:row for row in result['entries']} for result in results]; rows=[]
for pc in maps[0]:
    r,m,b=(item[pc] for item in maps); rr=int(r['interpreted_insns']); mr=int(m['interpreted_insns']); br=int(b['interpreted_insns'])
    rcrc=evidence[0].get(pc,{}).get('prefix_crc32',''); mcrc=evidence[1].get(pc,{}).get('prefix_crc32',''); bcrc=evidence[2].get(pc,{}).get('prefix_crc32','')
    if br>0 and mr==0: route_class='bomb_without_ddark_move_observed'
    elif br>0 and mr>0: route_class='ddark_move_and_bomb_observed'
    elif br==0 and mr>0: route_class='ddark_move_only_observed'
    elif rr>0: route_class='ryu_move_only_observed'
    else: route_class='not_reproduced'
    rows.append({'pc':pc,'ryu_move_insns':rr,'ryu_move_insns_per_s':float(r['insns_per_s']),
                 'ddark_move_insns':mr,'ddark_move_insns_per_s':float(m['insns_per_s']),
                 'ddark_bombs_insns':br,'ddark_bombs_insns_per_s':float(b['insns_per_s']),
                 'bomb_excess_vs_ddark_move_per_s':float(b['insns_per_s'])-float(m['insns_per_s']),
                 'ryu_crc32':rcrc,'ddark_move_crc32':mcrc,'ddark_bombs_crc32':bcrc,
                 'ddark_body_same':bool(mcrc and mcrc==bcrc),'route_class':route_class})
rows.sort(key=lambda row:(-row['bomb_excess_vs_ddark_move_per_s'],-row['ddark_bombs_insns'],row['pc']))
focus=next(row for row in rows if row['pc'].lower()=='0x80044c7c')
errors=[]
if not focus['ddark_body_same']: errors.append('0x80044C7C mudou de corpo entre movimento e bombas do D.Dark')
if any(not result.get('technical_clean') for result in results): errors.append('uma ou mais fases nao terminaram CLEAN')
with (session/'route-comparison.csv').open('w',encoding='utf-8',newline='') as handle:
    writer=csv.DictWriter(handle,fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
bomb_only=[row['pc'] for row in rows if row['route_class']=='bomb_without_ddark_move_observed']
(session/'bomb-without-ddark-move-observed-pcs.txt').write_text('\n'.join(bomb_only)+('\n' if bomb_only else ''),encoding='utf-8')
result={'track':'OVL-002E-DDARK-44C7C-ROUTE-COMPARISON','source_result_sha256':'DC65D829667A68AB2C1A7C354BBE389DF5258E128C0D92675A7CF9473483AE70',
        'target_count':len(rows),'bomb_without_ddark_move_observed_count':len(bomb_only),'focus_80044C7C':focus,
        'technical_clean':not errors,'errors':errors,'rows':rows,
        'interpretation_notice':'A classe observada vale somente para estas tres janelas; nao autoriza root, alias, closure ou credito.'}
(session/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
lines=['# Comparacao de rota de 0x80044C7C - OVL-002E','',f'- PCs comparados: {len(rows)}',
       f'- PCs vistos em bombas e nao no movimento do D.Dark: {len(bomb_only)}',
       f'- 0x80044C7C: Ryu movimento {focus["ryu_move_insns"]}; D.Dark movimento {focus["ddark_move_insns"]}; D.Dark bombas {focus["ddark_bombs_insns"]}.',
       f'- Classe de 0x80044C7C: `{focus["route_class"]}`',f'- Status tecnico: {"CLEAN" if not errors else "REVIEW"}',
       '- A classificacao vale somente para as janelas coletadas e nao promove nenhuma palavra.','',
       '| PC | Ryu mov./s | D.Dark mov./s | Bombas/s | Excesso bomba/s | Classe |','|---|---:|---:|---:|---:|---|']
for row in rows:
    if row['ryu_move_insns'] or row['ddark_move_insns'] or row['ddark_bombs_insns']:
        lines.append(f'| `{row["pc"]}` | {row["ryu_move_insns_per_s"]:.1f} | {row["ddark_move_insns_per_s"]:.1f} | {row["ddark_bombs_insns_per_s"]:.1f} | {row["bomb_excess_vs_ddark_move_per_s"]:.1f} | {row["route_class"]} |')
if errors: lines += ['','## Bloqueios','']+[f'- {item}' for item in errors]
(session/'summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
if errors: raise RuntimeError('; '.join(errors))
print(f'Comparacao concluida: {session}')
PY
}

run_ryu_move() {
    if [[ -f "$ACTIVE_STATE" ]]; then
        local previous_session
        previous_session="$(state_value "$ACTIVE_STATE" session_dir)"
        case "$previous_session" in "$PROJECT_ROOT"/local/telemetry/ovl-002e-ddark-44c7c-route-*) ;; *) fail "Sessao ativa anterior invalida." ;; esac
        [[ -d "$previous_session" ]] || fail "Diretorio da sessao anterior ausente."
        mv "$ACTIVE_STATE" "$previous_session/abandoned.state"
        printf 'Coleta anterior preservada como abandonada: %s\n' "$previous_session"
    fi
    make_session_dir
    local phase_dir; phase_dir="$(next_phase_dir phase-01-ryu-move)"
    {
        printf 'track=OVL-002E-DDARK-44C7C-ROUTE-COMPARISON\nruntime_dir=%s\n' "$RUNTIME_DIR"
        printf 'source_result=%s\nsource_sha256=%s\n' "$SOURCE_RESULT" "$EXPECTED_SOURCE_SHA"
        printf 'phase_1=D.Dark P1 x Ryu P2; D.Dark parado e somente movimento sem golpes do Ryu; 30 s\n'
        printf 'phase_2=D.Dark P1 x Ryu P2; Ryu parado e somente movimento sem golpes do D.Dark; 30 s\n'
        printf 'phase_3=D.Dark P1 x Ryu P2; bombas sem acerto e movimento minimo; 30 s\n'
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
    printf '\nD.Dark P1 x Ryu P2, cenario do Ryu. Mantenha D.Dark parado.\n'
    printf 'Durante a janela, mova, pule e agache somente com Ryu, sem executar golpes.\n'
    read -r -p "Pressione Enter quando o gameplay estiver controlavel: "
    capture_phase ryu-move "$phase_dir"
    RYU_RESULT="$phase_dir/result.json"; write_state ryu_move_complete "$RYU_RESULT" ''
    printf '\nParte 1 concluida. Mantenha D.Dark P1 x Ryu P2 na mesma execucao.\n'
    printf 'Depois execute: bash tools/observer_ddark_44c7c_ovl_002e.sh ddark-move\n'
}

run_ddark_move() {
    read_state; [[ "$PHASE" == ryu_move_complete ]] || fail "ddark-move exige a parte ryu-move concluida; fase atual: $PHASE."
    [[ -f "$RYU_RESULT" ]] || fail "Resultado ryu-move ausente."
    local phase_dir; phase_dir="$(next_phase_dir phase-02-ddark-move)"
    printf '\nD.Dark P1 x Ryu P2, cenario do Ryu. Deixe P2 parado.\n'
    printf 'Durante a janela, mova, pule e agache somente com D.Dark, sem executar golpes.\n'
    read -r -p "Pressione Enter quando o gameplay estiver controlavel: "
    capture_phase ddark-move "$phase_dir"
    DDARK_MOVE_RESULT="$phase_dir/result.json"; write_state ddark_move_complete "$RYU_RESULT" "$DDARK_MOVE_RESULT"
    printf '\nParte 2 concluida. Mantenha D.Dark P1 x Ryu P2 no mesmo cenario.\n'
    printf 'Depois execute: bash tools/observer_ddark_44c7c_ovl_002e.sh ddark-bombs\n'
}

run_ddark_bombs() {
    read_state; [[ "$PHASE" == ddark_move_complete ]] || fail "ddark-bombs exige a parte ddark-move concluida; fase atual: $PHASE."
    [[ -f "$RYU_RESULT" && -f "$DDARK_MOVE_RESULT" ]] || fail "Resultados anteriores ausentes."
    local phase_dir; phase_dir="$(next_phase_dir phase-03-ddark-bombs)"
    printf '\nD.Dark P1 x Ryu P2, cenario do Ryu. Deixe P2 parado.\n'
    printf 'Repita somente bombas dos dois lados, sem acertar Ryu; mova apenas o necessario.\n'
    read -r -p "Pressione Enter quando o gameplay estiver controlavel: "
    capture_phase ddark-bombs "$phase_dir"
    compare_results "$phase_dir/result.json"
    mv "$ACTIVE_STATE" "$SESSION_DIR/completed.state"
    printf '\nParte 3 concluida. Resumo: %s/summary.md\n' "$SESSION_DIR"
}

show_status() {
    if [[ ! -f "$ACTIVE_STATE" ]]; then printf 'Nenhuma comparacao 0x80044C7C ativa.\n'; return; fi
    printf 'Sessao: %s\nFase: %s\n' "$(state_value "$ACTIVE_STATE" session_dir)" "$(state_value "$ACTIVE_STATE" phase)"
}

main() {
    case "${1:-}" in
        ryu-move|ddark-move|ddark-bombs) validate_common ;;
        status) show_status; return ;;
        -h|--help) usage; return ;;
        *) usage; fail "Use ryu-move, ddark-move, ddark-bombs ou status." ;;
    esac
    case "$1" in ryu-move) run_ryu_move ;; ddark-move) run_ddark_move ;; ddark-bombs) run_ddark_bombs ;; esac
}

main "$@"
