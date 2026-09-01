#!/usr/bin/env bash
# Janelas temporizadas de descoberta de funcoes interpretadas na OVL-002B.
# Nao compila, nao gera fontes e nao abre/fecha o jogo.

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
readonly DEFAULT_WINDOW_SECONDS="${DISCOVERY_WINDOW_SECONDS:-5}"
readonly COUNTDOWN_SECONDS="${DISCOVERY_COUNTDOWN_SECONDS:-3}"
readonly EVIDENCE_LIMIT="${DISCOVERY_EVIDENCE_LIMIT:-16}"

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
Uso no MSYS2 UCRT64, com o runtime OVL-002B aberto:

  bash tools/run_ovl_002b_test.sh
  bash tools/observe_interpreted_function_events_ovl_002b.sh

Prepare Versus com D.Dark no P1 e Ryu no P2, cenario do Ryu. O script captura
primeiro um controle neutro automatico. Depois, cada linha aceita:

  tag [segundos]

Exemplos:
  ddark-bomba-ciclo-completo 5
  ddark-faca-no-chao 4
  ddark-dano-pesado 4

A duracao padrao e 5 segundos. Depois de confirmar a tag, use a contagem
regressiva para voltar ao jogo. Durante [CAPTURANDO], o observador nao consulta
o runtime. Ao ouvir o segundo aviso, volte ao neutro e aguarde o processamento.
Digite q para encerrar preservando todas as janelas.
EOF
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
        candidate="$PROJECT_ROOT/local/telemetry/ovl-002b-interpreted-window-discovery-$suffix"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            SESSION_DIR="$candidate"
            return
        fi
    done
    fail "Nao ha pasta livre para a descoberta OVL-002B."
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk seq; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python
    read_runtime_state
    read_debug_port
    for file in "$TEST_CONFIG" "$RANGES_FILE" "$QUARANTINE_FILE" "$RUNTIME_EXE" "$CACHE_MANIFEST"; do
        [[ -f "$file" ]] || fail "Arquivo ausente: $file"
    done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel OVL-002B divergente."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); manifest=pathlib.Path(sys.argv[2])
data=json.loads(manifest.read_text(encoding='utf-8'))
if data.get('track')!='OVL-002B-DDARK-CUMULATIVE': raise SystemExit('manifesto nao pertence a OVL-002B cumulativa')
if data.get('capture_keys')!=['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F','0x00020000:0xF943B63B']:
    raise SystemExit('chaves A+B+OVL-002B divergentes')
if int(data.get('incremental_words',0))!=882 or int(data.get('prior_ovl002a_words',0))!=226 or int(data.get('image_body_words',0))!=1108:
    raise SystemExit('volumes cumulativos OVL-002B divergentes')
for row in data.get('files',[]):
    path=root/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(row['size']): raise SystemExit(f'cache ausente/divergente: {row["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=row['sha256']: raise SystemExit(f'hash divergente: {row["path"]}')
rel=pathlib.PurePosixPath(data['cache_relative']); ranges=root/pathlib.Path(*rel.parts)/'00020000_F943B63B.ranges'
entries=set()
for line in ranges.read_text(encoding='utf-8').splitlines():
    fields=line.split()
    if fields and fields[0]=='F': entries.add(int(fields[1],16))
required={0x80092138,0x80092524,0x80092740,0x80092800,0x800929D4,0x80092C2C,0x80093BB8,0x80093E4C}
if required-entries: raise SystemExit('oito entradas OVL-002B nao estao presentes no shard')
if {0x80092F00,0x80047DE8}&entries: raise SystemExit('alvo excluido entrou indevidamente no shard')
print(f'Cache OVL-002B validado: {data.get("dll_count",0)} DLLs, {data.get("unique_entries",0)} entradas.')
PY
}

write_metadata() {
    {
        printf 'track=OVL-002B-INTERPRETED-WINDOW-DISCOVERY\n'
        printf 'runtime_dir=%s\n' "$RUNTIME_DIR"
        printf 'runtime_exe_sha256=%s\n' "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')"
        printf 'ranges_sha256=%s\n' "$EXPECTED_RANGES_SHA"
        printf 'capture_key=%s\ndefault_window_seconds=%s\ncountdown_seconds=%s\nevidence_limit=%s\n' \
            "$EXPECTED_CAPTURE_KEY" "$DEFAULT_WINDOW_SECONDS" "$COUNTDOWN_SECONDS" "$EVIDENCE_LIMIT"
        printf 'match=ddark-ryu-scenario-ryu\nplayer1=ddark\nplayer2=ryu\n'
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
}

run_observer() {
    "$PYTHON_BIN" - "$DEBUG_PORT" "$SESSION_DIR" "$RANGES_FILE" \
        "$QUARANTINE_FILE" "$RUNTIME_DIR" "$CACHE_MANIFEST" \
        "$DEFAULT_WINDOW_SECONDS" "$COUNTDOWN_SECONDS" "$EVIDENCE_LIMIT" 3<&0 <<'PY'
import csv
import hashlib
import json
import os
import pathlib
import re
import socket
import struct
import sys
import time
import unicodedata
import zlib

port=int(sys.argv[1]); session=pathlib.Path(sys.argv[2]); ranges_path=pathlib.Path(sys.argv[3])
quarantine_path=pathlib.Path(sys.argv[4]); runtime=pathlib.Path(sys.argv[5]); cache_manifest=pathlib.Path(sys.argv[6])
default_window=min(15.0,max(1.0,float(sys.argv[7]))); countdown=min(10,max(0,int(sys.argv[8])))
evidence_limit=min(32,max(1,int(sys.argv[9]))); event_number=0; completed=[]; neutral_rates={}
try:
    terminal=os.fdopen(3,'r',encoding='utf-8',errors='replace',closefd=False)
except OSError:
    terminal=open('CONIN$','r',encoding='utf-8',errors='replace')

def prompt(message):
    global terminal
    print(message,end='',flush=True)
    line=terminal.readline()
    if line=='' and os.name=='nt':
        terminal=open('CONIN$','r',encoding='utf-8',errors='replace'); line=terminal.readline()
    if line=='': raise EOFError('entrada interativa do terminal foi encerrada')
    return line.rstrip('\r\n')

def request(command,**arguments):
    payload={'id':1,'cmd':command,**arguments}; wire=json.dumps(payload,separators=(',',':'))+'\n'; chunks=[]
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
            raw_pc=str(row.get('pc',''))
            if raw_pc: entries[f'0x{int(raw_pc,16):08X}']=row
        returned=int(page.get('returned',0) or 0); total=int(page.get(count_key,0) or 0); offset+=returned
        if returned==0 or offset>=total: break
        if offset>65536: raise RuntimeError(f'{command}: paginacao defensiva excedida')
    if header is None: raise RuntimeError(f'{command}: sem cabecalho')
    header['entries']=list(entries.values()); header['returned_merged']=len(entries)
    return header

def static_snapshot():
    result=paged('static_text_misses','total',**{'class':'all','min_hits':1})
    if int(result.get('dropped',0) or 0): raise RuntimeError('static_text_misses perdeu entradas')
    return result

def dynamic_snapshot():
    return paged('overlay_interp_hot','total',sort='entries',min_entries=1,
                 phys_lo='0x00000000',phys_hi='0x00200000')

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

def deltas(base_static,now_static,base_dynamic,now_dynamic,duration):
    bs,ns=index(base_static),index(now_static); bd,nd=index(base_dynamic),index(now_dynamic); result=[]
    for pc in sorted(set(ns)|set(nd)):
        sr,so=ns.get(pc,{}),bs.get(pc,{}); dr,do=nd.get(pc,{}),bd.get(pc,{})
        static_fields={name:delta(sr.get(name),so.get(name)) for name in ('misses','modified','runtime','unknown')}
        static_entries=sum(static_fields.values()); dynamic_entries=delta(dr.get('entry_hits'),do.get('entry_hits'))
        if not static_entries and not dynamic_entries: continue
        addr=int(pc,16); classes=[name for name,value in static_fields.items() if value]
        if dynamic_entries and not classes: classes.append('dynamic/overlay')
        entries=max(static_entries,dynamic_entries); insns=delta(dr.get('insns'),do.get('insns'))
        neutral=neutral_rates.get(pc,{'entries_per_s':0.0,'insns_per_s':0.0})
        result.append({
            'pc':pc,'classification':'+'.join(classes) if classes else 'unknown',
            'external_entries':entries,'static_entries':static_entries,'dynamic_entries':dynamic_entries,
            'interpreted_blocks':delta(dr.get('hits'),do.get('hits')),'interpreted_insns':insns,
            'entries_per_s':entries/duration,'insns_per_s':insns/duration,
            'neutral_entries_per_s':neutral['entries_per_s'],'neutral_insns_per_s':neutral['insns_per_s'],
            'excess_entries_per_s':max(0.0,entries/duration-neutral['entries_per_s']),
            'excess_insns_per_s':max(0.0,insns/duration-neutral['insns_per_s']),
            'in_main_text':0x80101000<=addr<0x801C0000,'already_generated_entry':addr in native_entries,
            'covered_by_native_range':covered(addr),'quarantined':quarantined(addr),
            'cache_address_present':(addr&0x1fffffff) in cache_entries,
        })
    result.sort(key=lambda row:(-row['excess_insns_per_s'],-row['interpreted_insns'],-row['external_entries'],row['pc']))
    return result

def slug(raw):
    text=unicodedata.normalize('NFKD',raw).encode('ascii','ignore').decode().lower()
    text=re.sub(r'[^a-z0-9._-]+','-',text).strip('-')
    return text[:48].rstrip('-')

def read_window_spec():
    while True:
        raw=prompt(f'Digite tag [segundos; padrao {default_window:g}] ou q: ').strip()
        if raw.lower()=='q': return None
        duration=default_window; label=raw
        parts=raw.rsplit(None,1)
        if len(parts)==2:
            try:
                parsed=float(parts[1].replace(',','.'))
                if 1.0<=parsed<=15.0: label=parts[0]; duration=parsed
            except ValueError: pass
        tag=slug(label)
        if label and len(label)<=80 and tag: return tag,duration
        print('Tag invalida. Exemplo: ddark-bomba-ciclo-completo 5')

def live_evidence(pc):
    evidence={'pc':pc}
    try:
        mem=request('mem_words',addr=pc,count=32); words=mem.get('words',[])[:32]; evidence['words']=words
        if words:
            blob=b''.join(struct.pack('<I',int(word,16)) for word in words)
            evidence['prefix_words']=len(words); evidence['prefix_crc32']=f'0x{zlib.crc32(blob)&0xffffffff:08X}'
            evidence['prefix_sha256']=hashlib.sha256(blob).hexdigest().upper()
    except Exception as exc: evidence['mem_words_error']=str(exc)
    try: evidence['overlay_candidates']=request('overlay_candidates',pc=pc)
    except Exception as exc: evidence['overlay_candidates_error']=str(exc)
    return evidence

def write_summary(reason='running'):
    ranking={}
    for event in completed:
        for row in event['entries']:
            item=ranking.setdefault(row['pc'],{'events':0,'entries':0,'insns':0,'max_excess':0.0,'tags':[],'classification':row['classification']})
            item['events']+=1; item['entries']+=row['external_entries']; item['insns']+=row['interpreted_insns']
            item['max_excess']=max(item['max_excess'],row['excess_insns_per_s'])
            if event['tag'] not in item['tags']: item['tags'].append(event['tag'])
    ordered=sorted(ranking.items(),key=lambda item:(-item[1]['max_excess'],-item[1]['events'],-item[1]['insns'],item[0]))
    lines=[f'# Janelas de funcoes interpretadas - {session.name}','',f'- Estado: {reason}',
           f'- Janelas concluidas: {len(completed)}',f'- PCs distintos: {len(ranking)}',
           '- Referencia: primeira janela `ddark-neutro-controle`','',
           '## Janelas','', '| Janela | Tag | Duracao | PCs | Instrucoes |','|---:|---|---:|---:|---:|']
    for event in completed:
        lines.append(f'| {event["event"]:03d} | `{event["tag"]}` | {event["duration_s"]:.3f} s | '
                     f'{len(event["entries"])} | {sum(row["interpreted_insns"] for row in event["entries"])} |')
    if not completed: lines.append('| - | - | 0 | 0 | 0 |')
    lines += ['','## Ranking por excesso sobre o neutro','',
              '| PC | Janelas | Entradas | Instrucoes | Max. excesso insns/s | Classe | Tags |',
              '|---|---:|---:|---:|---:|---|---|']
    for pc,item in ordered:
        lines.append(f'| `{pc}` | {item["events"]} | {item["entries"]} | {item["insns"]} | '
                     f'{item["max_excess"]:.1f} | {item["classification"]} | {", ".join(item["tags"])} |')
    if not ordered: lines.append('| - | 0 | 0 | 0 | 0 | - | - |')
    lines += ['','PC observado nao e seed aprovada. Boundary, imagem viva, callers, closure e orcamento ainda devem ser auditados.','']
    (session/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
    with (session/'pc-ranking.csv').open('w',encoding='utf-8',newline='') as handle:
        writer=csv.writer(handle); writer.writerow(['pc','events','entries','interpreted_insns','max_excess_insns_per_s','classification','tags'])
        for pc,item in ordered:
            writer.writerow([pc,item['events'],item['entries'],item['insns'],f'{item["max_excess"]:.3f}',item['classification'],';'.join(item['tags'])])

def save_event(tag,duration,rows,before_static,after_static,before_dynamic,after_dynamic):
    global event_number,neutral_rates
    event_number+=1; event_id=f'{event_number:03d}'; final=session/f'window-{event_id}-{tag}'; final.mkdir()
    for name,data in (('before_static_text_misses.json',before_static),('after_static_text_misses.json',after_static),
                      ('before_overlay_interp_hot.json',before_dynamic),('after_overlay_interp_hot.json',after_dynamic)):
        (final/name).write_text(json.dumps(data,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    if event_number==1:
        neutral_rates={row['pc']:{'entries_per_s':row['entries_per_s'],'insns_per_s':row['insns_per_s']} for row in rows}
        for row in rows:
            row['neutral_entries_per_s']=row['entries_per_s']; row['neutral_insns_per_s']=row['insns_per_s']
            row['excess_entries_per_s']=0.0; row['excess_insns_per_s']=0.0
    evidence=[]
    for row in sorted(rows,key=lambda item:(-item['interpreted_insns'],-item['external_entries']))[:evidence_limit]:
        evidence.append(live_evidence(row['pc']))
    for name,command in (('overlay_loader_status.json','overlay_loader_status'),('dirty_ram_stats.json','dirty_ram_stats'),
                         ('dispatch_stats.json','dispatch_stats')):
        try: data=request(command)
        except Exception as exc: data={'ok':False,'error':str(exc)}
        (final/name).write_text(json.dumps(data,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    result={'event':event_number,'tag':tag,'duration_s':duration,
            'captured_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'entries':rows,'live_evidence':evidence}
    (final/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    columns=['pc','classification','external_entries','static_entries','dynamic_entries','interpreted_blocks','interpreted_insns',
             'entries_per_s','insns_per_s','neutral_entries_per_s','neutral_insns_per_s','excess_entries_per_s','excess_insns_per_s',
             'in_main_text','already_generated_entry','covered_by_native_range','quarantined','cache_address_present']
    with (final/'interpreted.csv').open('w',encoding='utf-8',newline='') as handle:
        writer=csv.DictWriter(handle,fieldnames=columns); writer.writeheader(); writer.writerows(rows)
    lines=[f'# Janela {event_id} - {tag}','',f'- Duracao: {duration:.3f} s',f'- PCs: {len(rows)}','',
           '| PC | Entradas | Instrucoes | Insns/s | Excesso sobre neutro/s | Classe |',
           '|---|---:|---:|---:|---:|---|']
    for row in rows:
        lines.append(f'| `{row["pc"]}` | {row["external_entries"]} | {row["interpreted_insns"]} | '
                     f'{row["insns_per_s"]:.1f} | {row["excess_insns_per_s"]:.1f} | {row["classification"]} |')
    if not rows: lines.append('| - | 0 | 0 | 0 | 0 | - |')
    lines += ['','O excesso usa a taxa da primeira janela neutra como referencia. PC observado ainda nao define boundary.','']
    (final/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
    completed.append(result); write_summary()
    print(f'Janela salva em: {final}')
    print('Top candidatos por excesso de instrucoes/s:')
    for row in rows[:12]:
        print(f'  {row["pc"]}: entradas={row["external_entries"]}; insns={row["interpreted_insns"]}; excesso/s={row["excess_insns_per_s"]:.1f}')

def capture_window(tag,duration):
    for remaining in range(countdown,0,-1):
        print(f'Captura em {remaining}...',flush=True); time.sleep(1)
    print('Mantenha neutro por um instante; criando baseline da janela...',flush=True)
    before_static=static_snapshot(); before_dynamic=dynamic_snapshot()
    print(f'\a[CAPTURANDO {tag}] execute a acao agora por {duration:g} s.',flush=True)
    started=time.monotonic(); time.sleep(duration)
    after_dynamic=dynamic_snapshot(); after_static=static_snapshot()
    elapsed=time.monotonic()-started
    print('\a[FIM DA JANELA] volte ao neutro; processando resultados...',flush=True)
    rows=deltas(before_static,after_static,before_dynamic,after_dynamic,duration)
    save_event(tag,duration,rows,before_static,after_static,before_dynamic,after_dynamic)
    print(f'Tempo de parede ate o snapshot dinamico: {elapsed:.3f} s.')

try:
    probe=request('overlay_loader_status')
    if not int(probe.get('active',0) or 0): raise RuntimeError('overlay cache nao esta ativo nesta execucao')
    expected=(runtime/'cache').resolve(); actual=pathlib.Path(str(probe.get('cache_dir',''))).resolve()
    if actual!=expected: raise RuntimeError(f'runtime conectado usa cache inesperado: {actual}')
    if int(probe.get('registered',0) or 0)<8: raise RuntimeError('imagem OVL-002B ainda nao registrou as oito entradas nativas')
    request('dispatch_stats')
    print('\nObservador conectado ao runtime OVL-002B correto.')
    print('Prepare D.Dark P1 x Ryu P2 no cenario do Ryu; deixe ambos neutros.')
    choice=prompt('No gameplay controlavel, pressione Enter para o controle neutro ou digite q: ').strip().lower()
    if choice=='q':
        write_summary('encerrado antes do controle neutro'); raise SystemExit(0)
    capture_window('ddark-neutro-controle',default_window)
    while True:
        spec=read_window_spec()
        if spec is None: break
        capture_window(*spec)
    write_summary('encerramento normal')
except KeyboardInterrupt:
    print('\nCtrl+C recebido; preservando janelas concluidas...')
    write_summary('interrompido por Ctrl+C')
except SystemExit:
    raise
except Exception as exc:
    (session/'observer-error.txt').write_text(f'{type(exc).__name__}: {exc}\n',encoding='utf-8')
    write_summary(f'erro: {type(exc).__name__}')
    raise
finally:
    (session/'final.txt').write_text(
        f'ended_utc={time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime())}\nwindows={len(completed)}\n',encoding='utf-8')

print(f'\nSessao preservada em: {session}')
PY
}

main() {
    case "${1:-}" in '') ;; -h|--help) usage; return ;; *) usage; fail "Este script nao recebe argumentos." ;; esac
    validate
    make_session_dir
    write_metadata
    run_observer
}

main "$@"
