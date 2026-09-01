#!/usr/bin/env bash
# Descoberta interativa de qualquer entrada interpretada no gameplay S1-261.
# Usa o runtime cumulativo OVL-001B de telemetria; nao compila nem abre o jogo.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_001b_test.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly QUARANTINE_FILE="$PROJECT_ROOT/seeds/s1_261_gameplay_quarantine.txt"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-001b-current-runtime.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_A_KEY=0x00020000:0xAC1FF1A4
readonly EXPECTED_B_KEY=0x00020000:0x94E6122F
readonly DYNAMIC_POLL_SECONDS="${DISCOVERY_DYNAMIC_POLL_SECONDS:-0.5}"
readonly STATIC_POLL_SECONDS="${DISCOVERY_STATIC_POLL_SECONDS:-2.0}"

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
Uso no MSYS2 UCRT64, com o runtime OVL-001B de telemetria aberto:

  bash tools/run_ovl_001b_test.sh
  bash tools/observe_interpreted_function_events_s1_261.sh

Rota inicial recomendada:
  - Player 1: D.Dark
  - Player 2: Ryu (cenario do Ryu)
  - Ryu permanece parado
  - Pressione Enter no primeiro frame controlavel, antes de usar a bomba

Ao detectar qualquer nova entrada interpretada, o observador congela a janela,
mostra os PCs e pede uma tag. Volte ao neutro e pressione Enter para rearmar.
A mesma funcao pode disparar em eventos sucessivos. Digite q depois de um
evento ou use Ctrl+C para encerrar preservando a sessao.

O script nao gera fontes, nao compila, nao abre nem fecha o jogo.
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
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-001B ausente. Execute primeiro compile_ovl_001b_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"
    RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-001b-test-runtime-*) ;; *) fail "Runtime OVL-001B invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" capture_a_key)" == "$EXPECTED_A_KEY" ]] || fail "Chave OVL-001A divergente."
    [[ "$(state_value "$RUNTIME_STATE" capture_b_key)" == "$EXPECTED_B_KEY" ]] || fail "Chave OVL-001B divergente."
    [[ -f "$RUNTIME_EXE" && -f "$CACHE_MANIFEST" ]] || fail "Runtime OVL-001B incompleto."
}

make_session_dir() {
    local suffix candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-261-interpreted-event-discovery-$suffix"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            SESSION_DIR="$candidate"
            return
        fi
    done
    fail "Nao ha pasta livre para a descoberta S1-261."
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
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel OVL-001B divergente."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); manifest=pathlib.Path(sys.argv[2])
data=json.loads(manifest.read_text(encoding='utf-8'))
if data.get('track')!='OVL-001B-SAFE-CUMULATIVE': raise SystemExit('manifesto nao pertence a OVL-001B cumulativa')
if data.get('capture_keys')!=['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F']: raise SystemExit('chaves A+B divergentes')
for row in data.get('files',[]):
    path=root/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(row['size']): raise SystemExit(f'cache ausente/divergente: {row["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=row['sha256']: raise SystemExit(f'hash divergente: {row["path"]}')
print(f'Cache A+B validado: {data.get("dll_count",0)} DLLs, {data.get("unique_entries",0)} entradas.')
PY
}

write_metadata() {
    {
        printf 'track=S1-261-INTERPRETED-EVENT-DISCOVERY\n'
        printf 'runtime_dir=%s\n' "$RUNTIME_DIR"
        printf 'runtime_exe_sha256=%s\n' "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')"
        printf 'ranges_sha256=%s\n' "$EXPECTED_RANGES_SHA"
        printf 'dynamic_poll_seconds=%s\nstatic_poll_seconds=%s\n' "$DYNAMIC_POLL_SECONDS" "$STATIC_POLL_SECONDS"
        printf 'suggested_match=ddark-ryu-scenario-ryu\nplayer1=ddark\nplayer2=ryu\n'
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
}

run_observer() {
    "$PYTHON_BIN" - "$DEBUG_PORT" "$SESSION_DIR" "$RANGES_FILE" \
        "$QUARANTINE_FILE" "$RUNTIME_DIR" "$CACHE_MANIFEST" \
        "$DYNAMIC_POLL_SECONDS" "$STATIC_POLL_SECONDS" 3<&0 <<'PY'
import csv
import hashlib
import json
import os
import pathlib
import re
import shutil
import socket
import struct
import sys
import time
import unicodedata
import zlib

port=int(sys.argv[1]); session=pathlib.Path(sys.argv[2]); ranges_path=pathlib.Path(sys.argv[3])
quarantine_path=pathlib.Path(sys.argv[4]); runtime=pathlib.Path(sys.argv[5]); cache_manifest=pathlib.Path(sys.argv[6])
dynamic_poll=max(0.25,float(sys.argv[7])); static_poll=max(1.0,float(sys.argv[8]))
event_number=0; completed=[]
try:
    terminal=os.fdopen(3,'r',encoding='utf-8',errors='replace',closefd=False)
except OSError:
    terminal=open('CONIN$','r',encoding='utf-8',errors='replace')

def prompt(message):
    global terminal
    print(message,end='',flush=True)
    line=terminal.readline()
    if line=='' and os.name=='nt':
        terminal=open('CONIN$','r',encoding='utf-8',errors='replace')
        line=terminal.readline()
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
            if raw_pc:
                pc=f'0x{int(raw_pc,16):08X}'; entries[pc]=row
        returned=int(page.get('returned',0) or 0); total=int(page.get(count_key,0) or 0)
        offset+=returned
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
cache_entries=set()
manifest=json.loads(cache_manifest.read_text(encoding='utf-8'))
for item in manifest.get('files',[]):
    if not str(item.get('path','')).endswith('.ranges'): continue
    path=runtime/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    for line in path.read_text(encoding='utf-8',errors='replace').splitlines():
        fields=line.split()
        if fields and fields[0]=='F': cache_entries.add(int(fields[1],16)&0x1fffffff)

def covered(addr): return any(lo<=addr<hi for lo,hi in native_ranges)
def quarantined(addr): return addr in quarantine_pcs or any(lo<=addr<hi for lo,hi in quarantine_ranges)

def deltas(base_static,now_static,base_dynamic,now_dynamic):
    bs,ns=index(base_static),index(now_static); bd,nd=index(base_dynamic),index(now_dynamic); result=[]
    for pc in sorted(set(ns)|set(nd)):
        sr,so=ns.get(pc,{}),bs.get(pc,{}); dr,do=nd.get(pc,{}),bd.get(pc,{})
        static_fields={name:delta(sr.get(name),so.get(name)) for name in ('misses','modified','runtime','unknown')}
        static_entries=sum(static_fields.values()); dynamic_entries=delta(dr.get('entry_hits'),do.get('entry_hits'))
        if not static_entries and not dynamic_entries: continue
        addr=int(pc,16); in_main=0x80101000<=addr<0x801C0000
        classes=[name for name,value in static_fields.items() if value]
        if dynamic_entries and not classes: classes.append('dynamic/overlay')
        result.append({
            'pc':pc,'classification':'+'.join(classes) if classes else 'unknown',
            'external_entries':max(static_entries,dynamic_entries),'static_entries':static_entries,
            'dynamic_entries':dynamic_entries,'interpreted_blocks':delta(dr.get('hits'),do.get('hits')),
            'interpreted_insns':delta(dr.get('insns'),do.get('insns')),
            'in_main_text':in_main,'already_generated_entry':addr in native_entries,
            'covered_by_native_range':covered(addr),'quarantined':quarantined(addr),
            'cache_address_present':(addr&0x1fffffff) in cache_entries,
        })
    result.sort(key=lambda row:(-row['external_entries'],-row['interpreted_insns'],row['pc']))
    return result

def slug(raw):
    text=unicodedata.normalize('NFKD',raw).encode('ascii','ignore').decode().lower()
    text=re.sub(r'[^a-z0-9._-]+','-',text).strip('-')
    return text[:48].rstrip('-')

def read_tag():
    while True:
        raw=prompt('Digite a tag do golpe/situacao atual: ').strip()
        tag=slug(raw)
        if raw and len(raw)<=80 and tag: return tag
        print('Tag invalida. Use uma descricao curta, como ddark-bomba-forte-sem-hit.')

def live_evidence(pc):
    evidence={'pc':pc}
    try:
        mem=request('mem_words',addr=pc,count=32); words=mem.get('words',[])[:32]
        evidence['words']=words
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
            item=ranking.setdefault(row['pc'],{'events':0,'entries':0,'insns':0,'tags':[],'classification':row['classification']})
            item['events']+=1; item['entries']+=row['external_entries']; item['insns']+=row['interpreted_insns']
            if event['tag'] not in item['tags']: item['tags'].append(event['tag'])
    ordered=sorted(ranking.items(),key=lambda item:(-item[1]['events'],-item[1]['entries'],-item[1]['insns'],item[0]))
    lines=[f'# Eventos de funcoes interpretadas - {session.name}','',f'- Estado: {reason}',
           f'- Eventos concluidos: {len(completed)}',f'- PCs distintos: {len(ranking)}','',
           '## Eventos','', '| Evento | Tag | PCs | Entradas |','|---:|---|---:|---:|']
    for event in completed:
        lines.append(f'| {event["event"]:03d} | `{event["tag"]}` | {len(event["entries"])} | '
                     f'{sum(row["external_entries"] for row in event["entries"])} |')
    if not completed: lines.append('| - | - | 0 | 0 |')
    lines += ['','## Ranking repetido','',
              '| PC | Eventos | Entradas | Instrucoes | Classe | Tags |','|---|---:|---:|---:|---|---|']
    for pc,item in ordered:
        lines.append(f'| `{pc}` | {item["events"]} | {item["entries"]} | {item["insns"]} | '
                     f'{item["classification"]} | {", ".join(item["tags"])} |')
    if not ordered: lines.append('| - | 0 | 0 | 0 | - | - |')
    lines += ['','PC observado nao e seed aprovada. Boundary, imagem viva, callers, closure e orcamento ainda devem ser auditados.','']
    (session/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
    with (session/'pc-ranking.csv').open('w',encoding='utf-8',newline='') as handle:
        writer=csv.writer(handle); writer.writerow(['pc','events','entries','interpreted_insns','classification','tags'])
        for pc,item in ordered: writer.writerow([pc,item['events'],item['entries'],item['insns'],item['classification'],';'.join(item['tags'])])

def save_event(rows,before_static,after_static,before_dynamic,after_dynamic):
    global event_number
    event_number+=1; event_id=f'{event_number:03d}'; staging=session/f'.event-{event_id}-pending'
    staging.mkdir()
    for name,data in (('before_static_text_misses.json',before_static),('after_static_text_misses.json',after_static),
                      ('before_overlay_interp_hot.json',before_dynamic),('after_overlay_interp_hot.json',after_dynamic)):
        (staging/name).write_text(json.dumps(data,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('\a\nEVENTO INTERPRETADO ENCONTRADO — observacao congelada.')
    print('  PC          entradas  insns       classe')
    for row in rows:
        print(f'  {row["pc"]}  {row["external_entries"]:8d}  {row["interpreted_insns"]:10d}  {row["classification"]}')
    evidence=[]
    for row in rows:
        item=live_evidence(row['pc']); evidence.append(item)
        shown=item.get('prefix_crc32','indisponivel')
        print(f'    {row["pc"]}: CRC32 das primeiras 32 palavras = {shown}')
    for name,command in (('overlay_loader_status.json','overlay_loader_status'),('dirty_ram_stats.json','dirty_ram_stats'),
                         ('dispatch_stats.json','dispatch_stats')):
        try: data=request(command)
        except Exception as exc: data={'ok':False,'error':str(exc)}
        (staging/name).write_text(json.dumps(data,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    tag=read_tag(); final=session/f'event-{event_id}-{tag}'; staging.rename(final)
    result={'event':event_number,'tag':tag,'captured_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
            'entries':rows,'live_evidence':evidence}
    (final/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    columns=['pc','classification','external_entries','static_entries','dynamic_entries','interpreted_blocks',
             'interpreted_insns','in_main_text','already_generated_entry','covered_by_native_range','quarantined','cache_address_present']
    with (final/'interpreted.csv').open('w',encoding='utf-8',newline='') as handle:
        writer=csv.DictWriter(handle,fieldnames=columns); writer.writeheader(); writer.writerows(rows)
    lines=[f'# Evento {event_id} - {tag}','',
           '| PC | Entradas | Blocos | Instrucoes | Classe | CRC32 prefixo |','|---|---:|---:|---:|---|---|']
    by_pc={item['pc']:item for item in evidence}
    for row in rows:
        lines.append(f'| `{row["pc"]}` | {row["external_entries"]} | {row["interpreted_blocks"]} | '
                     f'{row["interpreted_insns"]} | {row["classification"]} | '
                     f'`{by_pc[row["pc"]].get("prefix_crc32","indisponivel")}` |')
    lines += ['','A tag descreve o contexto informado pelo operador. O CRC cobre somente as primeiras 32 palavras e nao define boundary.','']
    (final/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
    completed.append(result); write_summary()
    print(f'Evento salvo em: {final}')

try:
    probe=request('overlay_loader_status')
    if not int(probe.get('active',0) or 0): raise RuntimeError('overlay cache nao esta ativo nesta execucao')
    request('dispatch_stats')
    print('\nObservador conectado ao runtime OVL-001B.')
    print('Prepare D.Dark como P1 e Ryu como P2; deixe Ryu parado.')
    choice=prompt('No primeiro frame controlavel, pressione Enter para criar a baseline ou digite q: ').strip().lower()
    if choice=='q':
        write_summary('encerrado antes da baseline'); raise SystemExit(0)
    print('\nColetando baseline; ainda nao execute a bomba...')
    base_static=static_snapshot(); base_dynamic=dynamic_snapshot()
    (session/'baseline_static_text_misses.json').write_text(json.dumps(base_static,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    (session/'baseline_overlay_interp_hot.json').write_text(json.dumps(base_dynamic,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    latest_static=base_static; next_static=time.monotonic()+static_poll
    print('\n[MONITORANDO] Execute uma acao de cada vez. O primeiro incremento interpretado congelara a observacao.')
    while True:
        now=time.monotonic()
        current_dynamic=dynamic_snapshot()
        current_static=latest_static
        if now>=next_static:
            current_static=static_snapshot(); latest_static=current_static; next_static=time.monotonic()+static_poll
        rows=deltas(base_static,current_static,base_dynamic,current_dynamic)
        if rows:
            save_event(rows,base_static,current_static,base_dynamic,current_dynamic)
            choice=prompt('\nVolte ao neutro. Pressione Enter para rearmar ou digite q para encerrar: ').strip().lower()
            if choice=='q': break
            print('Atualizando baseline; nao execute a proxima acao ainda...')
            base_static=static_snapshot(); base_dynamic=dynamic_snapshot(); latest_static=base_static
            next_static=time.monotonic()+static_poll
            print('[MONITORANDO NOVAMENTE] Execute a proxima acao.')
        else:
            time.sleep(dynamic_poll)
    write_summary('encerramento normal')
except KeyboardInterrupt:
    print('\nCtrl+C recebido; preservando eventos concluidos...')
    write_summary('interrompido por Ctrl+C')
except SystemExit:
    raise
except Exception as exc:
    (session/'observer-error.txt').write_text(f'{type(exc).__name__}: {exc}\n',encoding='utf-8')
    write_summary(f'erro: {type(exc).__name__}')
    raise
finally:
    (session/'final.txt').write_text(
        f'ended_utc={time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime())}\nevents={len(completed)}\n',encoding='utf-8')

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
