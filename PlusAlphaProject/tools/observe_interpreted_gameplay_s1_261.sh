#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly RAW_TCP="$REPO_ROOT/psxrecomp/tools/raw_tcp.py"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly QUARANTINE_FILE="$PROJECT_ROOT/seeds/s1_261_gameplay_quarantine.txt"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-260-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_RUNTIME_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_FUNCTIONS=1059

PYTHON_BIN=
DEBUG_PORT=
CAMPAIGN_DIR=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com a build S1-260 de telemetria aberta:

  bash tools/observe_interpreted_gameplay_s1_261.sh

Fluxo por janela:

  1. Informe uma tag, por exemplo ryu-ken-cenario-ken-idle.
  2. Posicione o jogo no primeiro frame controlavel e pressione Enter.
  3. Aguarde a mensagem [JANELA ATIVA]; somente entao execute a rota.
  4. Pressione Enter novamente para encerrar.
  5. O script coleta e compara os contadores somente antes e depois da janela.

Durante a JANELA ATIVA nao existe polling TCP, Python em segundo plano nem
gravacao em disco. Tags recomendadas para a primeira campanha:

  ryu-ken-cenario-ken-idle
  ryu-ken-cenario-ken-acoes
  ryu-ken-cenario-ken-round-end

Digite fim no prompt de tag para encerrar. O script nao gera fontes, nao
compila, nao abre e nao fecha o jogo.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no PATH do UCRT64."
    fi
}

read_debug_port() {
    DEBUG_PORT="$(awk '
        /^[[:space:]]*\[runtime\][[:space:]]*$/ { ok=1; next }
        /^[[:space:]]*\[/ { ok=0 }
        ok && /^[[:space:]]*debug_port[[:space:]]*=/ {
            sub(/^[^=]*=/, ""); gsub(/[[:space:]]+/, ""); print; exit
        }
    ' "$GAME_TOML")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida em game.toml."
}

raw_command() {
    local output="$1"
    shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 ||
        fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" || fail "Comando rejeitado: $* (veja $output)"
}

make_unique_directory() {
    local parent="$1" base="$2" candidate suffix
    for suffix in $(seq -w 1 99); do
        candidate="$parent/${base}-${suffix}"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            printf '%s\n' "$candidate"
            return
        fi
    done
    fail "Nao ha identificador livre para ${base}-01..99."
}

validate_environment() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum nm awk grep sed tr seq; do
        command -v "$tool" >/dev/null || fail "$tool nao encontrado no UCRT64."
    done
    [[ -f "$RAW_TCP" && -f "$GAME_TOML" && -f "$RANGES_FILE" &&
       -f "$QUARANTINE_FILE" && -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] ||
        fail "Build S1-260 de telemetria, manifesto ou quarentena ausente."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] ||
        fail "Ranges atuais nao correspondem ao checkpoint S1-261/S1-260."
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_RUNTIME_SHA" ]] ||
        fail "Executavel S1-260 de telemetria divergente."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == "$EXPECTED_FUNCTIONS" ]] ||
        fail "A baseline nao possui as 1.059 funcoes esperadas."
    grep -qxF 'CMAKE_BUILD_TYPE:STRING=RelWithDebInfo' "$CMAKE_CACHE" ||
        fail "Build nao esta RelWithDebInfo."
    grep -qxF 'PSX_DEBUG_TOOLS:BOOL=ON' "$CMAKE_CACHE" || fail "PSX_DEBUG_TOOLS nao esta ativo."
    grep -qxF 'PSX_STATIC_RUNTIME:BOOL=ON' "$CMAKE_CACHE" || fail "Runtime estatico nao esta ativo."
    nm -C "$RUNTIME_EXE" | grep -Eq '[[:space:]]T[[:space:]]+func_80103BD8$' ||
        fail "O executavel nao contem a funcao S1-260 promovida."
    select_python
    read_debug_port
    "$PYTHON_BIN" - "$QUARANTINE_FILE" <<'PY'
import pathlib,sys
path=pathlib.Path(sys.argv[1]); rows=[]
for number,line in enumerate(path.read_text(encoding='utf-8').splitlines(),1):
    parts=line.split('#',1)[0].split()
    if not parts: continue
    if parts[0]=='pc' and len(parts)==2:
        int(parts[1],16); rows.append(tuple(parts))
    elif parts[0]=='range' and len(parts)==3:
        lo,hi=int(parts[1],16),int(parts[2],16)
        if hi<=lo: raise SystemExit(f'range invalido na linha {number}')
        rows.append(tuple(parts))
    else: raise SystemExit(f'linha invalida na quarentena: {number}')
expected={
 ('range','0x80103384','0x801038B4'),
 ('range','0x8016EA0C','0x8016F1B0'),
 ('range','0x8016F560','0x8016F668'),
 ('range','0x8016FB64','0x8016FC28'),
 ('pc','0x8019E6D0'),
}
if set(rows)!=expected: raise SystemExit('conteudo da quarentena diverge do gate aprovado')
PY
}

write_campaign_metadata() {
    {
        printf 'campaign=%s\n' "$(basename "$CAMPAIGN_DIR")"
        printf 'baseline=S1-261\nruntime_build=buildClean-ucrt-s1-260-tele\n'
        printf 'runtime_exe_sha256=%s\nranges_sha256=%s\n' \
            "$EXPECTED_RUNTIME_SHA" "$EXPECTED_RANGES_SHA"
        printf 'generated_functions=%s\ndebug_port=%s\n' "$EXPECTED_FUNCTIONS" "$DEBUG_PORT"
        printf 'window_policy=before-after-no-polling\n'
        printf 'quarantine_file=%s\n' "$(basename "$QUARANTINE_FILE")"
        printf 'game_launch=manual\ngame_shutdown=manual\n'
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$CAMPAIGN_DIR/metadata.txt"
}

capture_interpreter_snapshots() {
    local window_dir="$1" phase="$2"
    "$PYTHON_BIN" - "$DEBUG_PORT" "$window_dir" "$phase" <<'PY'
import json,pathlib,socket,sys
port=int(sys.argv[1]); directory=pathlib.Path(sys.argv[2]); phase=sys.argv[3]
if phase not in {'before','after'}: raise SystemExit('fase invalida')
def request(command,**arguments):
    payload={'id':1,'cmd':command,**arguments}
    wire=json.dumps(payload,separators=(',',':'))+'\n'; chunks=[]
    with socket.create_connection(('127.0.0.1',port),timeout=5.0) as sock:
        sock.settimeout(30.0); sock.sendall(wire.encode())
        while True:
            chunk=sock.recv(65536)
            if not chunk: break
            chunks.append(chunk)
    result=json.loads(b''.join(chunks).decode())
    if not result.get('ok'): raise RuntimeError(f'{command} rejeitado: {result}')
    return result
def paged(command,count_key,**arguments):
    offset=0; entries={}; header=None
    while True:
        page=request(command,offset=offset,limit=256,**arguments)
        if header is None: header={k:v for k,v in page.items() if k!='entries'}
        for row in page.get('entries',[]):
            pc=str(row.get('pc','')).upper()
            if pc: entries[pc]=row
        returned=int(page.get('returned',0) or 0); total=int(page.get(count_key,0) or 0)
        offset+=returned
        if returned==0 or offset>=total: break
        if offset>32768: raise RuntimeError(f'paginacao defensiva excedida: {command}')
    if header is None: raise RuntimeError(f'sem resposta: {command}')
    header['entries']=list(entries.values()); header['returned_merged']=len(entries)
    return header
static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
if int(static.get('dropped',0) or 0):
    raise RuntimeError('static_text_misses perdeu entradas; janela incompleta')
dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,
              phys_lo='0x00000000',phys_hi='0x00200000')
(directory/f'{phase}_static_text_misses.json').write_text(
    json.dumps(static,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
(directory/f'{phase}_overlay_interp_hot.json').write_text(
    json.dumps(dynamic,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY
    raw_command "$window_dir/${phase}_dispatch_stats.log" dispatch_stats
    raw_command "$window_dir/${phase}_dirty_ram_stats.log" dirty_ram_stats
}

analyze_window() {
    local window_dir="$1" window_id="$2" duration_ns="$3"
    "$PYTHON_BIN" - "$window_dir" "$window_id" "$duration_ns" \
        "$RANGES_FILE" "$QUARANTINE_FILE" <<'PY'
import csv,json,pathlib,re,sys
directory=pathlib.Path(sys.argv[1]); window_id=sys.argv[2]
duration_s=int(sys.argv[3])/1_000_000_000
ranges_path=pathlib.Path(sys.argv[4]); quarantine_path=pathlib.Path(sys.argv[5])
def load(name): return json.loads((directory/name).read_text(encoding='utf-8'))
def wrapped(name):
    text=(directory/name).read_text(encoding='utf-8',errors='replace')
    match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    return json.loads(match.group(1)) if match else {}
def index(snapshot): return {str(row.get('pc','')).upper():row for row in snapshot.get('entries',[])}
def delta(value,old): return max(0,int(value or 0)-int(old or 0))
before_static,after_static=load('before_static_text_misses.json'),load('after_static_text_misses.json')
before_dynamic,after_dynamic=load('before_overlay_interp_hot.json'),load('after_overlay_interp_hot.json')
old_static,old_dynamic=index(before_static),index(before_dynamic)
static_rows={}
for pc,row in index(after_static).items():
    previous=old_static.get(pc,{})
    values={name:delta(row.get(name),previous.get(name)) for name in ('misses','modified','runtime','unknown')}
    values['selected_hits']=sum(values.values())
    if values['selected_hits']: static_rows[pc]=values
dynamic_rows={}
for pc,row in index(after_dynamic).items():
    previous=old_dynamic.get(pc,{})
    values={'entry_hits':delta(row.get('entry_hits'),previous.get('entry_hits')),
            'hits':delta(row.get('hits'),previous.get('hits')),
            'insns':delta(row.get('insns'),previous.get('insns'))}
    if any(values.values()): dynamic_rows[pc]=values
native_entries=set(); native_ranges=[]
for line in ranges_path.read_text(encoding='utf-8').splitlines():
    parts=line.split()
    if len(parts)==2 and parts[0]=='F': native_entries.add(int(parts[1],16))
    elif len(parts)==3 and parts[0]=='R':
        lo=int(parts[1],16); native_ranges.append((lo,lo+int(parts[2],16)))
quarantine_pcs=set(); quarantine_ranges=[]
for line in quarantine_path.read_text(encoding='utf-8').splitlines():
    parts=line.split('#',1)[0].split()
    if not parts: continue
    if parts[0]=='pc': quarantine_pcs.add(int(parts[1],16))
    else: quarantine_ranges.append((int(parts[1],16),int(parts[2],16)))
def covered(addr): return any(lo<=addr<hi for lo,hi in native_ranges)
def quarantined(addr): return addr in quarantine_pcs or any(lo<=addr<hi for lo,hi in quarantine_ranges)
def classification(static,dynamic):
    names=[name for name in ('pristine','modified','runtime','unknown') if static.get({'pristine':'misses'}.get(name,name),0)]
    if dynamic and not names: names.append('dynamic/ram')
    return '+'.join(names) if names else 'unknown'
entries=[]
for pc in sorted(set(static_rows)|set(dynamic_rows)):
    static=static_rows.get(pc,{}); dynamic=dynamic_rows.get(pc,{})
    addr=int(pc,16); static_entries=int(static.get('selected_hits',0)); dynamic_entries=int(dynamic.get('entry_hits',0))
    in_main=0x80101000<=addr<0x801C0000; is_covered=covered(addr); is_quarantine=quarantined(addr)
    eligible=bool(static.get('misses',0) and in_main and not is_covered and not is_quarantine and
                  not static.get('modified',0) and not static.get('runtime',0) and not static.get('unknown',0))
    entries.append({
        'pc':pc,'classification':classification(static,dynamic),
        'external_entries':max(static_entries,dynamic_entries),'static_entries':static_entries,
        'dynamic_entries':dynamic_entries,'interpreted_blocks':int(dynamic.get('hits',0)),
        'interpreted_insns':int(dynamic.get('insns',0)),'pristine':int(static.get('misses',0)),
        'modified':int(static.get('modified',0)),'runtime':int(static.get('runtime',0)),
        'unknown':int(static.get('unknown',0)),'in_main_text':in_main,
        'already_generated_entry':addr in native_entries,'covered_by_native_range':is_covered,
        'quarantined':is_quarantine,'candidate_eligible':eligible,
    })
entries.sort(key=lambda row:(-row['external_entries'],-row['interpreted_insns'],row['pc']))
candidates=[row for row in entries if row['candidate_eligible']]
dynamic_only=[row for row in entries if not row['candidate_eligible']]
before_dispatch,after_dispatch=wrapped('before_dispatch_stats.log'),wrapped('after_dispatch_stats.log')
before_dirty,after_dirty=wrapped('before_dirty_ram_stats.log'),wrapped('after_dirty_ram_stats.log')
guards=('aborts','native_handoffs','text_native_blocked','text_diverged_pages','text_exact_mismatches')
guard_deltas={name:delta(after_dirty.get(name),before_dirty.get(name)) for name in guards}
result={'window_id':window_id,'duration_s':round(duration_s,3),'interpreted_pc_count':len(entries),
        'candidate_pc_count':len(candidates),'external_entries':sum(r['external_entries'] for r in entries),
        'candidate_entries':sum(r['external_entries'] for r in candidates),
        'interpreted_insns':sum(r['interpreted_insns'] for r in entries),
        'dispatch_miss_delta':delta(after_dispatch.get('miss_total'),before_dispatch.get('miss_total')),
        'guard_deltas':guard_deltas,'entries':entries,'candidates':candidates}
(directory/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
columns=['pc','classification','external_entries','static_entries','dynamic_entries','interpreted_blocks',
         'interpreted_insns','pristine','modified','runtime','unknown','in_main_text',
         'already_generated_entry','covered_by_native_range','quarantined','candidate_eligible']
for name,rows in [('all-interpreted.csv',entries),('static-candidates.csv',candidates),('excluded-or-dynamic.csv',dynamic_only)]:
    with (directory/name).open('w',encoding='utf-8',newline='') as handle:
        writer=csv.DictWriter(handle,fieldnames=columns); writer.writeheader(); writer.writerows(rows)
lines=[f'# Gameplay interpretado - {window_id}','',f'- Duracao ativa: {duration_s:.3f} s',
       f'- PCs interpretados observados: {len(entries)}',f'- PCs estaticos elegiveis: {len(candidates)}',
       f'- Entradas interpretadas totais: {result["external_entries"]}',
       f'- Entradas dos candidatos estaticos: {result["candidate_entries"]}',
       f'- Instrucoes interpretadas atribuidas: {result["interpreted_insns"]}',
       f'- Delta miss_total do dispatcher: {result["dispatch_miss_delta"]}',
       f'- Gates tecnicos: {guard_deltas}','','## Candidatos estaticos priorizados','',
       '| PC observado | Entradas | Classe | Observacao |','|---|---:|---|---|']
for row in candidates[:40]:
    lines.append(f'| `{row["pc"]}` | {row["external_entries"]} | {row["classification"]} | boundary ainda nao confirmado |')
if not candidates: lines.append('| - | 0 | - | nenhum candidato elegivel nesta janela |')
if len(candidates)>40: lines.append(f'\nA tabela mostra 40 de {len(candidates)} candidatos; veja `static-candidates.csv`.')
lines += ['', 'PC observado nao e seed aprovada. Confirmar boundary formal, callers, corpo, closure e orcamento.',
          'Codigo dinamico, paginas modificadas, ranges ja nativos e quarentena ficam separados do ranking.', '']
(directory/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

update_campaign_summary() {
    "$PYTHON_BIN" - "$CAMPAIGN_DIR" <<'PY'
import csv,json,pathlib,sys
campaign=pathlib.Path(sys.argv[1]); results=[]
for path in sorted(campaign.glob('*/result.json')):
    result=json.loads(path.read_text(encoding='utf-8'))
    note=path.parent/'note.txt'; result['note']=note.read_text(encoding='utf-8').strip() if note.exists() else ''
    results.append(result)
lines=[f'# Descoberta de gameplay: {campaign.name}','',
       '| Janela | Duracao | PCs | Candidatos estaticos | Entradas candidatas | Instrucoes interp. | Observacao |',
       '|---|---:|---:|---:|---:|---:|---|']
for result in results:
    note=result.get('note','').replace('|','/')
    lines.append(f'| `{result["window_id"]}` | {result["duration_s"]:.1f} s | '
                 f'{result["interpreted_pc_count"]} | {result["candidate_pc_count"]} | '
                 f'{result["candidate_entries"]} | {result["interpreted_insns"]} | {note} |')
if not results: lines.append('| - | - | - | - | - | - | nenhuma janela concluida |')
lines += ['', 'A matriz compara PCs observados nas janelas; os enderecos ainda exigem boundary e closure.', '']
(campaign/'campaign-summary.md').write_text('\n'.join(lines),encoding='utf-8')
window_ids=[r['window_id'] for r in results]
all_pcs=sorted({row['pc'] for r in results for row in r.get('candidates',[])})
with (campaign/'candidate-matrix.csv').open('w',encoding='utf-8',newline='') as handle:
    writer=csv.writer(handle); writer.writerow(['pc',*window_ids,'windows_present','total_entries'])
    for pc in all_pcs:
        values=[]; total=0; present=0
        for result in results:
            row=next((item for item in result.get('candidates',[]) if item['pc']==pc),None)
            hits=int(row.get('external_entries',0)) if row else 0
            values.append(hits); total+=hits; present+=int(hits>0)
        writer.writerow([pc,*values,present,total])
all_rows=sorted({row['pc'] for r in results for row in r.get('entries',[])})
with (campaign/'all-interpreted-matrix.csv').open('w',encoding='utf-8',newline='') as handle:
    writer=csv.writer(handle); writer.writerow(['pc',*window_ids,'windows_present','total_entries'])
    for pc in all_rows:
        values=[]; total=0; present=0
        for result in results:
            row=next((item for item in result.get('entries',[]) if item['pc']==pc),None)
            hits=int(row.get('external_entries',0)) if row else 0
            values.append(hits); total+=hits; present+=int(hits>0)
        writer.writerow([pc,*values,present,total])
PY
}

run_window() {
    local window_id="$1" window_dir observation start_ns end_ns duration_ns
    window_dir="$(make_unique_directory "$CAMPAIGN_DIR" "$window_id")"
    {
        printf 'window_id=%s\ncampaign=%s\n' "$window_id" "$(basename "$CAMPAIGN_DIR")"
        printf 'collection_policy=before-after-no-polling\n'
    } >"$window_dir/metadata.txt"
    printf '\nJanela: %s\n' "$window_id"
    printf 'Posicione o jogo no primeiro frame controlavel e deixe os controles neutros.\n'
    read -r -p 'Pressione Enter para preparar a baseline da janela... ' _
    note "Coletando BEFORE; ainda nao execute a rota"
    capture_interpreter_snapshots "$window_dir" before
    start_ns="$("$PYTHON_BIN" -c 'import time; print(time.time_ns())')"
    printf 'started_utc=%s\nstarted_epoch_ns=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$start_ns" \
        >>"$window_dir/metadata.txt"
    printf '\n[JANELA ATIVA] Execute agora a rota %s.\n' "$window_id"
    read -r -p 'Pressione Enter para encerrar esta janela... ' _
    end_ns="$("$PYTHON_BIN" -c 'import time; print(time.time_ns())')"
    duration_ns=$((end_ns-start_ns))
    printf 'ended_utc=%s\nended_epoch_ns=%s\nduration_ns=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$end_ns" "$duration_ns" >>"$window_dir/metadata.txt"
    note "Janela congelada pelo usuario; coletando AFTER"
    capture_interpreter_snapshots "$window_dir" after
    analyze_window "$window_dir" "$window_id" "$duration_ns"
    read -r -p 'Descricao observada (opcional): ' observation
    printf '%s\n' "$observation" >"$window_dir/note.txt"
    update_campaign_summary
    printf 'Resumo: %s/summary.md\n' "$window_dir"
}

interrupt_handler() {
    trap - INT TERM
    printf '\nColeta interrompida; preservando todos os arquivos ja gravados.\n'
    if [[ -n "$CAMPAIGN_DIR" && -d "$CAMPAIGN_DIR" ]]; then
        update_campaign_summary 2>/dev/null || true
        printf 'Campanha parcial: %s\n' "$CAMPAIGN_DIR"
    fi
    exit 130
}

main() {
    local window_id
    case "${1:-}" in '') ;; -h|--help) usage; return ;; *) usage; fail "Argumento desconhecido: $1" ;; esac
    validate_environment
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    CAMPAIGN_DIR="$(make_unique_directory "$PROJECT_ROOT/local/telemetry" \
        's1-261-gameplay-interpreted-discovery')"
    write_campaign_metadata
    trap interrupt_handler INT TERM
    raw_command "$CAMPAIGN_DIR/runtime_dispatch_probe.log" dispatch_stats
    raw_command "$CAMPAIGN_DIR/runtime_static_probe.log" static_text_misses class=all min_hits=1 offset=0 limit=1
    raw_command "$CAMPAIGN_DIR/runtime_dynamic_probe.log" overlay_interp_hot sort=entries min_entries=1 offset=0 limit=1
    printf '\nObservador de gameplay S1-261 pronto.\n'
    printf 'Durante cada JANELA ATIVA nao havera consultas TCP nem gravacao.\n'
    while true; do
        printf '\n'
        read -r -p 'Tag da janela (ou fim): ' window_id
        window_id="${window_id,,}"
        [[ "$window_id" == fim ]] && break
        [[ "$window_id" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || {
            printf 'Tag invalida. Use ate 64 caracteres: a-z, 0-9, ponto, _ ou hifen.\n' >&2
            continue
        }
        run_window "$window_id"
    done
    update_campaign_summary
    printf '\nCampanha encerrada; o jogo continua aberto.\n'
    printf 'Resumo: %s/campaign-summary.md\n' "$CAMPAIGN_DIR"
    printf 'Matriz de candidatos: %s/candidate-matrix.csv\n' "$CAMPAIGN_DIR"
}

main "$@"
