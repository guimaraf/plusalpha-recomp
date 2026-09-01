#!/usr/bin/env bash
# Sequencia automatica e especifica: bombas, dano recebido e especial da faca.
# Usa o runtime OVL-002B; nao compila, nao gera fontes e nao abre/fecha o jogo.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002b_test.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly QUARANTINE_FILE="$PROJECT_ROOT/seeds/s1_261_gameplay_quarantine.txt"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002b-current-runtime.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_CAPTURE_KEY=0x00020000:0xF943B63B
readonly PREPARE_SECONDS=5
readonly EVIDENCE_LIMIT=16

PYTHON_BIN=
DEBUG_PORT=
RUNTIME_DIR=
RUNTIME_EXE=
CACHE_MANIFEST=
SESSION_DIR=
OBSERVER_MODE=actions
SESSION_STEM=ovl-002b-ddark-actions-discovery
TRACK_NAME=OVL-002B-DDARK-ACTIONS-DISCOVERY

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, ja dentro do gameplay D.Dark P1 x Ryu P2:

  bash tools/observer_ddark_actions_ovl_002b.sh
  bash tools/observer_ddark_actions_ovl_002b.sh bombas

Sequencia totalmente automatica:
  1. 5 s de preparo + 10 s para lancar cinco bombas.
  2. 5 s de preparo + 10 s para D.Dark sofrer danos variados.
  3. 5 s de preparo + 20 s para o especial da faca no chao dos dois lados.

Execute somente a acao indicada em cada janela. Um aviso simples marca o
inicio; um aviso duplo marca o fim. Durante a captura nao ha consultas TCP.
O script nao recebe tags nem exige Enter entre as fases.

O modo "bombas" executa somente 5 s de preparo e uma janela continua de
30 s. Durante essa janela, mantenha a posicao e repita apenas a bomba.
EOF
}

configure_mode() {
    case "${1:-}" in
        ''|acoes)
            OBSERVER_MODE=actions
            SESSION_STEM=ovl-002b-ddark-actions-discovery
            TRACK_NAME=OVL-002B-DDARK-ACTIONS-DISCOVERY
            ;;
        bombas)
            OBSERVER_MODE=bombs
            SESSION_STEM=ovl-002b-ddark-bombs-discovery
            TRACK_NAME=OVL-002B-DDARK-BOMBS-DISCOVERY
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            fail "Modo desconhecido: $1"
            ;;
    esac
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_debug_port() {
    DEBUG_PORT="$(awk '
        /^[[:space:]]*\[runtime\][[:space:]]*$/ {ok=1; next}
        /^[[:space:]]*\[/ {ok=0}
        ok && /^[[:space:]]*debug_port[[:space:]]*=/ {
            sub(/^[^=]*=/,""); gsub(/[[:space:]]+/,""); print; exit
        }
    ' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida."
}

read_runtime_state() {
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-002B ausente. Execute primeiro compile_ovl_002b_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"
    RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002b-test-runtime-*) ;; *) fail "Runtime OVL-002B invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" capture_key)" == "$EXPECTED_CAPTURE_KEY" ]] || fail "Chave OVL-002B divergente."
    [[ "$(state_value "$RUNTIME_STATE" target)" == 0x80092C2C ]] || fail "Alvo OVL-002B divergente."
    [[ "$(state_value "$RUNTIME_STATE" prior_alias)" == 0x80093E4C ]] || fail "Alias OVL-002A divergente."
    [[ "$(state_value "$RUNTIME_STATE" incremental_words)" == 882 ]] || fail "Volume OVL-002B divergente."
    [[ -f "$RUNTIME_EXE" && -f "$CACHE_MANIFEST" ]] || fail "Runtime OVL-002B incompleto."
}

make_session_dir() {
    local suffix candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/$SESSION_STEM-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; SESSION_DIR="$candidate"; return; fi
    done
    fail "Nao ha pasta livre para a descoberta especifica do D.Dark."
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk seq; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python; read_runtime_state; read_debug_port
    for file in "$TEST_CONFIG" "$RANGES_FILE" "$QUARANTINE_FILE" "$RUNTIME_EXE" "$CACHE_MANIFEST"; do
        [[ -f "$file" ]] || fail "Arquivo ausente: $file"
    done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel OVL-002B divergente."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); manifest=pathlib.Path(sys.argv[2]); data=json.loads(manifest.read_text(encoding='utf-8'))
if data.get('track')!='OVL-002B-DDARK-CUMULATIVE': raise SystemExit('manifesto nao pertence a OVL-002B')
if data.get('capture_keys')!=['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F','0x00020000:0xF943B63B']:
    raise SystemExit('chaves cumulativas divergentes')
if int(data.get('incremental_words',0))!=882 or int(data.get('prior_ovl002a_words',0))!=226 or int(data.get('image_body_words',0))!=1108:
    raise SystemExit('volumes cumulativos divergentes')
for row in data.get('files',[]):
    path=root/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(row['size']): raise SystemExit(f'cache ausente: {row["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=row['sha256']: raise SystemExit(f'cache alterado: {row["path"]}')
rel=pathlib.PurePosixPath(data['cache_relative']); ranges=root/pathlib.Path(*rel.parts)/'00020000_F943B63B.ranges'; entries=set()
for line in ranges.read_text(encoding='utf-8').splitlines():
    fields=line.split()
    if fields and fields[0]=='F': entries.add(int(fields[1],16))
required={0x80092138,0x80092524,0x80092740,0x80092800,0x800929D4,0x80092C2C,0x80093BB8,0x80093E4C}
if required-entries: raise SystemExit('oito entradas cumulativas ausentes')
if {0x80092F00,0x80047DE8}&entries: raise SystemExit('alvo excluido entrou no shard')
print(f'Cache OVL-002B validado: {data.get("dll_count",0)} DLLs, {data.get("unique_entries",0)} entradas.')
PY
}

write_metadata() {
    {
        printf 'track=%s\nmode=%s\n' "$TRACK_NAME" "$OBSERVER_MODE"
        printf 'runtime_dir=%s\nruntime_exe_sha256=%s\nranges_sha256=%s\ncapture_key=%s\n' \
            "$RUNTIME_DIR" "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" "$EXPECTED_RANGES_SHA" "$EXPECTED_CAPTURE_KEY"
        printf 'prepare_seconds=%s\nevidence_limit=%s\n' "$PREPARE_SECONDS" "$EVIDENCE_LIMIT"
        if [[ "$OBSERVER_MODE" == bombs ]]; then
            printf 'phase_1=ddark-bombas-isoladas-longas:30\n'
        else
            printf 'phase_1=ddark-bombas-repetidas:10\nphase_2=ddark-danos-diversos:10\nphase_3=ddark-especial-faca-chao:20\n'
        fi
        printf 'match=ddark-ryu-scenario-ryu\nplayer1=ddark\nplayer2=ryu\nstarted_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
}

run_observer() {
    "$PYTHON_BIN" - "$DEBUG_PORT" "$SESSION_DIR" "$RANGES_FILE" "$QUARANTINE_FILE" \
        "$RUNTIME_DIR" "$CACHE_MANIFEST" "$PREPARE_SECONDS" "$EVIDENCE_LIMIT" "$OBSERVER_MODE" "$TRACK_NAME" <<'PY'
import csv,hashlib,json,pathlib,re,socket,struct,sys,time,zlib

port=int(sys.argv[1]); session=pathlib.Path(sys.argv[2]); ranges_path=pathlib.Path(sys.argv[3])
quarantine_path=pathlib.Path(sys.argv[4]); runtime=pathlib.Path(sys.argv[5]); cache_manifest=pathlib.Path(sys.argv[6])
prepare_seconds=int(sys.argv[7]); evidence_limit=int(sys.argv[8]); observer_mode=sys.argv[9]; track_name=sys.argv[10]; completed=[]
if observer_mode=='bombs':
    phases=[{'tag':'ddark-bombas-isoladas-longas','duration':30.0,
             'instruction':'Durante toda a janela, mantenha D.Dark em posicao fixa e repita somente a bomba. Nao use outro golpe.'}]
else:
    phases=[
     {'tag':'ddark-bombas-repetidas','duration':10.0,'instruction':'Lance cinco bombas, repetindo dos dois lados. Nao use outro golpe.'},
     {'tag':'ddark-danos-diversos','duration':10.0,'instruction':'Controle o P2 e faca D.Dark sofrer danos variados. D.Dark nao deve atacar.'},
     {'tag':'ddark-especial-faca-chao','duration':20.0,'instruction':'Execute o especial da faca no chao pelo menos uma vez de cada lado.'},
    ]

def request(command,**arguments):
    wire=json.dumps({'id':1,'cmd':command,**arguments},separators=(',',':'))+'\n'; chunks=[]
    with socket.create_connection(('127.0.0.1',port),timeout=5.0) as sock:
        sock.settimeout(30.0); sock.sendall(wire.encode('utf-8'))
        while True:
            chunk=sock.recv(65536)
            if not chunk: break
            chunks.append(chunk)
    if not chunks: raise RuntimeError(f'{command}: resposta vazia')
    result=json.loads(b''.join(chunks).decode('utf-8'))
    if not result.get('ok'): raise RuntimeError(f'{command} rejeitado: {result}')
    return result

def paged(command,count_key,**arguments):
    offset=0; entries={}; header=None
    while True:
        page=request(command,offset=offset,limit=256,**arguments)
        if header is None: header={k:v for k,v in page.items() if k!='entries'}
        for row in page.get('entries',[]):
            raw=str(row.get('pc',''))
            if raw: entries[f'0x{int(raw,16):08X}']=row
        returned=int(page.get('returned',0) or 0); total=int(page.get(count_key,0) or 0); offset+=returned
        if returned==0 or offset>=total: break
        if offset>65536: raise RuntimeError(f'{command}: paginacao excedida')
    if header is None: raise RuntimeError(f'{command}: sem cabecalho')
    header['entries']=list(entries.values()); header['returned_merged']=len(entries); return header

def static_snapshot():
    result=paged('static_text_misses','total',**{'class':'all','min_hits':1})
    if int(result.get('dropped',0) or 0): raise RuntimeError('static_text_misses perdeu entradas')
    return result

def dynamic_snapshot():
    return paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')

def index(snapshot):
    result={}
    for row in snapshot.get('entries',[]):
        raw=str(row.get('pc',''))
        if raw: result[f'0x{int(raw,16):08X}']=row
    return result

def delta(value,old): return max(0,int(value or 0)-int(old or 0))

native_entries=set(); native_ranges=[]
for line in ranges_path.read_text(encoding='utf-8').splitlines():
    fields=line.split()
    if len(fields)==2 and fields[0]=='F': native_entries.add(int(fields[1],16))
    elif len(fields)==3 and fields[0]=='R':
        lo=int(fields[1],16); native_ranges.append((lo,lo+int(fields[2],16)))
quarantine_pcs=set(); quarantine_ranges=[]
for line in quarantine_path.read_text(encoding='utf-8').splitlines():
    fields=line.split('#',1)[0].split()
    if not fields: continue
    if fields[0]=='pc': quarantine_pcs.add(int(fields[1],16))
    elif fields[0]=='range': quarantine_ranges.append((int(fields[1],16),int(fields[2],16)))
cache_entries=set(); manifest=json.loads(cache_manifest.read_text(encoding='utf-8'))
for item in manifest.get('files',[]):
    if not str(item.get('path','')).endswith('.ranges'): continue
    path=runtime/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    for line in path.read_text(encoding='utf-8',errors='replace').splitlines():
        fields=line.split()
        if fields and fields[0]=='F': cache_entries.add(int(fields[1],16)&0x1fffffff)

def covered(addr): return any(lo<=addr<hi for lo,hi in native_ranges)
def quarantined(addr): return addr in quarantine_pcs or any(lo<=addr<hi for lo,hi in quarantine_ranges)

def window_deltas(bs,ns,bd,nd,duration):
    bs,ns=index(bs),index(ns); bd,nd=index(bd),index(nd); rows=[]
    for pc in sorted(set(ns)|set(nd)):
        sr,so=ns.get(pc,{}),bs.get(pc,{}); dr,do=nd.get(pc,{}),bd.get(pc,{})
        sf={name:delta(sr.get(name),so.get(name)) for name in ('misses','modified','runtime','unknown')}
        se=sum(sf.values()); de=delta(dr.get('entry_hits'),do.get('entry_hits'))
        if not se and not de: continue
        addr=int(pc,16); insns=delta(dr.get('insns'),do.get('insns')); entries=max(se,de)
        classes=[name for name,value in sf.items() if value]
        if de and not classes: classes.append('dynamic/overlay')
        rows.append({'pc':pc,'classification':'+'.join(classes) if classes else 'unknown','external_entries':entries,
          'static_entries':se,'dynamic_entries':de,'interpreted_blocks':delta(dr.get('hits'),do.get('hits')),
          'interpreted_insns':insns,'entries_per_s':entries/duration,'insns_per_s':insns/duration,
          'in_main_text':0x80101000<=addr<0x801C0000,'already_generated_entry':addr in native_entries,
          'covered_by_native_range':covered(addr),'quarantined':quarantined(addr),
          'cache_address_present':(addr&0x1fffffff) in cache_entries})
    rows.sort(key=lambda r:(-r['interpreted_insns'],-r['external_entries'],r['pc'])); return rows

def live_evidence(pc):
    evidence={'pc':pc}
    try:
        words=request('mem_words',addr=pc,count=32).get('words',[])[:32]; evidence['words']=words
        if words:
            blob=b''.join(struct.pack('<I',int(word,16)) for word in words)
            evidence['prefix_crc32']=f'0x{zlib.crc32(blob)&0xffffffff:08X}'
            evidence['prefix_sha256']=hashlib.sha256(blob).hexdigest().upper()
    except Exception as exc: evidence['mem_words_error']=str(exc)
    try: evidence['overlay_candidates']=request('overlay_candidates',pc=pc)
    except Exception as exc: evidence['overlay_candidates_error']=str(exc)
    return evidence

def countdown(phase):
    print(f'\nFASE {phase["tag"]}: {phase["instruction"]}',flush=True)
    for remaining in range(prepare_seconds,0,-1):
        print(f'Prepare-se: {remaining}...',flush=True); time.sleep(1)

def capture_phase(number,phase):
    countdown(phase)
    print('Mantenha os personagens parados enquanto a baseline e lida...',flush=True)
    before_static=static_snapshot(); before_dynamic=dynamic_snapshot()
    print(f'\a[CAPTURANDO] {phase["instruction"]} Janela de {phase["duration"]:.0f} s.',flush=True)
    started=time.monotonic(); time.sleep(phase['duration'])
    after_dynamic=dynamic_snapshot(); dynamic_elapsed=time.monotonic()-started; after_static=static_snapshot()
    print('\a\a[FIM DA CAPTURA] Pare as acoes e aguarde a proxima contagem.',flush=True)
    rows=window_deltas(before_static,after_static,before_dynamic,after_dynamic,phase['duration'])
    folder=session/f'phase-{number:02d}-{phase["tag"]}'; folder.mkdir()
    for name,data in (('before_static_text_misses.json',before_static),('after_static_text_misses.json',after_static),
                      ('before_overlay_interp_hot.json',before_dynamic),('after_overlay_interp_hot.json',after_dynamic)):
        (folder/name).write_text(json.dumps(data,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    evidence=[live_evidence(row['pc']) for row in rows[:evidence_limit]]
    diagnostics={}
    for command in ('overlay_loader_status','dirty_ram_stats','dispatch_stats'):
        try: diagnostics[command]=request(command)
        except Exception as exc: diagnostics[command]={'ok':False,'error':str(exc)}
        (folder/f'{command}.json').write_text(json.dumps(diagnostics[command],ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    result={'phase':number,'tag':phase['tag'],'duration_s':phase['duration'],'dynamic_snapshot_elapsed_s':dynamic_elapsed,
            'instruction':phase['instruction'],'captured_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
            'entries':rows,'live_evidence':evidence,'diagnostics':diagnostics}
    (folder/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    columns=['pc','classification','external_entries','static_entries','dynamic_entries','interpreted_blocks','interpreted_insns',
             'entries_per_s','insns_per_s','in_main_text','already_generated_entry','covered_by_native_range','quarantined','cache_address_present']
    with (folder/'interpreted.csv').open('w',encoding='utf-8',newline='') as handle:
        writer=csv.DictWriter(handle,fieldnames=columns); writer.writeheader(); writer.writerows(rows)
    completed.append(result)

def finalize(reason):
    all_pcs=sorted({row['pc'] for event in completed for row in event['entries']}); rates={}
    for pc in all_pcs:
        values=[]
        for event in completed:
            row=next((r for r in event['entries'] if r['pc']==pc),None)
            values.append(row['insns_per_s'] if row else 0.0)
        floor=min(values) if len(values)>1 else 0.0
        rates[pc]={'floor':floor,'values':values,'excess':[max(0.0,v-floor) for v in values]}
    ranking=[]
    for pc in all_pcs:
        rows=[next((r for r in event['entries'] if r['pc']==pc),None) for event in completed]
        classification=next(r['classification'] for r in rows if r)
        ranking.append({'pc':pc,'classification':classification,'rates':rates[pc]['values'],'floor':rates[pc]['floor'],
                        'excess':rates[pc]['excess'],'max_excess':max(rates[pc]['excess']),
                        'total_insns':sum(r['interpreted_insns'] for r in rows if r)})
    ranking.sort(key=lambda r:(-r['max_excess'],-r['total_insns'],r['pc']))
    ranking_evidence=[live_evidence(row['pc']) for row in ranking[:evidence_limit]]
    (session/'ranking-live-evidence.json').write_text(
        json.dumps(ranking_evidence,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    summary={'track':track_name,'mode':observer_mode,'state':reason,'phases':len(completed),
             'phase_tags':[e['tag'] for e in completed],'ranking':ranking,
             'ranking_live_evidence_file':'ranking-live-evidence.json'}
    (session/'result.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    title='Descoberta isolada de bombas do D.Dark - OVL-002B' if observer_mode=='bombs' else 'Descoberta especifica D.Dark - OVL-002B'
    lines=[f'# {title}','',f'- Estado: {reason}',f'- Fases concluidas: {len(completed)}','',
           '## Fases','', '| Fase | Tag | Duracao | PCs | Instrucoes |','|---:|---|---:|---:|---:|']
    for e in completed:
        lines.append(f'| {e["phase"]} | `{e["tag"]}` | {e["duration_s"]:.0f} s | {len(e["entries"])} | '
                     f'{sum(r["interpreted_insns"] for r in e["entries"])} |')
    if not completed: lines.append('| - | - | 0 | 0 | 0 |')
    tags=[e['tag'] for e in completed]
    lines += ['','## Ranking comparativo','',
              '| PC | '+ ' | '.join(tags) +' | Base comum/s | Max. excesso/s | Classe |',
              '|---|'+ '|'.join(['---:']*len(tags)) +'|---:|---:|---|']
    for row in ranking:
        lines.append(f'| `{row["pc"]}` | '+' | '.join(f'{v:.1f}' for v in row['rates'])+
                     f' | {row["floor"]:.1f} | {row["max_excess"]:.1f} | {row["classification"]} |')
    if not ranking: lines.append('| - | 0 | 0 | 0 | - |')
    if observer_mode=='bombs':
        lines += ['','A coluna da bomba mostra instrucoes interpretadas por segundo durante a janela isolada. O ranking identifica PCs observados, mas nao define boundary.','']
    else:
        lines += ['','As colunas das acoes sao instrucoes interpretadas por segundo. A base comum e o menor valor entre as tres fases; o excesso destaca comportamento especifico, mas nao define boundary.','']
    (session/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
    with (session/'pc-ranking.csv').open('w',encoding='utf-8',newline='') as handle:
        writer=csv.writer(handle); writer.writerow(['pc',*tags,'common_floor_insns_per_s','max_excess_insns_per_s','classification'])
        for row in ranking: writer.writerow([row['pc'],*[f'{v:.3f}' for v in row['rates']],f'{row["floor"]:.3f}',f'{row["max_excess"]:.3f}',row['classification']])

try:
    probe=request('overlay_loader_status')
    if not int(probe.get('active',0) or 0): raise RuntimeError('overlay cache nao esta ativo')
    expected_cache=(runtime/'cache').resolve(); actual_cache=pathlib.Path(str(probe.get('cache_dir',''))).resolve()
    path_match=actual_cache==expected_cache
    expected_live={
      0x80092138:0x3FBB24A5,0x80092524:0x8B3CD3B6,0x80092740:0x5E2B8811,0x80092800:0xD3698FD1,
      0x800929D4:0x0776DC7A,0x80092C2C:0x1B64D20F,0x80093BB8:0xE9D28991,0x80093E4C:0x12FF550F,
    }
    live_gate={}; live_errors=[]
    for pc,wanted_crc in expected_live.items():
        words=request('mem_words',addr=f'0x{pc:08X}',count=32).get('words',[])
        if len(words)!=32:
            live_errors.append(f'0x{pc:08X}: esperado 32 words, veio {len(words)}'); continue
        blob=b''.join(struct.pack('<I',int(word,16)) for word in words)
        crc=zlib.crc32(blob)&0xffffffff
        candidates=request('overlay_candidates',pc=f'0x{pc:08X}').get('candidates',[])
        exact=any(int(candidate.get('match',0))==1 and int(candidate.get('state',9))==0 and
                  int(candidate.get('dll',-1))>=0 and int(candidate.get('device_touch',1))==0
                  for candidate in candidates)
        live_gate[f'0x{pc:08X}']={'crc32':f'0x{crc:08X}','expected_crc32':f'0x{wanted_crc:08X}',
                                  'crc_match':crc==wanted_crc,'candidate_exact_active':exact}
        if crc!=wanted_crc: live_errors.append(f'0x{pc:08X}: CRC vivo 0x{crc:08X}, esperado 0x{wanted_crc:08X}')
        if not exact: live_errors.append(f'0x{pc:08X}: candidato GCC exato ausente ou inativo')
    identity={'expected_cache_dir':str(expected_cache),'actual_cache_dir':str(actual_cache),'cache_path_match':path_match,
              'registered':int(probe.get('registered',0) or 0),'live_gate':live_gate,'errors':live_errors}
    (session/'runtime-identity.json').write_text(json.dumps(identity,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    (session/'overlay-loader-status.json').write_text(json.dumps(probe,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    if live_errors: raise RuntimeError('runtime conectado falhou no gate vivo OVL-002B: '+'; '.join(live_errors))
    if int(probe.get('registered',0) or 0)<8: raise RuntimeError('imagem D.Dark ainda nao registrou as oito entradas nativas')
    if not path_match:
        print(f'AVISO: cache_dir usa caminho equivalente/alternativo ({actual_cache}); identidade confirmada pelos oito gates vivos.',flush=True)
    if observer_mode=='bombs':
        print('\nRuntime OVL-002B confirmado por CRC e candidatos exatos. A janela isolada de bombas comecara agora.')
    else:
        print('\nRuntime OVL-002B confirmado por CRC e candidatos exatos. A sequencia comecara agora e nao exigira entrada adicional.')
    for number,phase in enumerate(phases,1): capture_phase(number,phase)
    finalize('encerramento normal')
except KeyboardInterrupt:
    print('\nCtrl+C recebido; preservando fases concluidas...'); finalize('interrompido por Ctrl+C')
except Exception as exc:
    (session/'observer-error.txt').write_text(f'{type(exc).__name__}: {exc}\n',encoding='utf-8'); finalize(f'erro: {type(exc).__name__}'); raise
finally:
    (session/'final.txt').write_text(f'ended_utc={time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime())}\nphases={len(completed)}\n',encoding='utf-8')

print(f'\nColeta concluida. Sessao: {session}')
PY
}

main() {
    [[ "$#" -le 1 ]] || { usage; fail "Use no maximo um modo."; }
    configure_mode "${1:-}"
    validate; make_session_dir; write_metadata; run_observer
}

main "$@"
