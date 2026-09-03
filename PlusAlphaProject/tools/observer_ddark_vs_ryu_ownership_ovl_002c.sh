#!/usr/bin/env bash
# Compara os 38 PCs residuais da bomba entre Ryu x Ryu e D.Dark x Ryu.
# Nao compila, nao gera fontes e nao abre/fecha o jogo.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002c_test.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002c-current-runtime.state"
readonly ACTIVE_STATE="$PROJECT_ROOT/local/telemetry/.ovl-002c-ddark-ownership-active.state"
readonly SOURCE_RESULT="$PROJECT_ROOT/local/telemetry/ovl-002c-ddark-bombs-discovery-01/result.json"
readonly EXPECTED_SOURCE_SHA=737A485D4736481DF36A210195209F5773655E64B63448231733AB350D1F34C7
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
Uso no MSYS2 UCRT64, com o runtime OVL-002C aberto manualmente:

  bash tools/observer_ddark_vs_ryu_ownership_ovl_002c.sh ryu
  bash tools/observer_ddark_vs_ryu_ownership_ovl_002c.sh ddark
  bash tools/observer_ddark_vs_ryu_ownership_ovl_002c.sh status

Parte 1 (ryu):
  Entre no Versus com Ryu P1 x Ryu P2, cenario do Ryu, e deixe ambos neutros.
  O script aguarda Enter, conta 5 s e mede 30 s sem polling.

Parte 2 (ddark):
  Na mesma execucao, troque para D.Dark P1 x Ryu P2, cenario do Ryu.
  O script aguarda Enter, conta 5 s e mede 30 s de bombas repetidas, sem
  acertar Ryu e sem usar outra acao.

O resultado compara somente os 38 PCs da baseline
ovl-002c-ddark-bombs-discovery-01. Endereco igual com CRC vivo diferente e
classificado como reutilizacao de endereco, nao como a mesma funcao.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_runtime() {
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-002C ausente. Execute primeiro compile_ovl_002c_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"
    RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002c-test-runtime-*) ;; *) fail "Runtime OVL-002C invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" capture_key)" == 0x00020000:0xF943B63B ]] || fail "Chave OVL-002C divergente."
    [[ "$(state_value "$RUNTIME_STATE" image_body_words)" == 2074 ]] || fail "Volume OVL-002C divergente."
    [[ -f "$RUNTIME_EXE" && -f "$CACHE_MANIFEST" ]] || fail "Runtime OVL-002C incompleto."
}

read_debug_port() {
    DEBUG_PORT="$(awk '/^[[:space:]]*\[runtime\]/{ok=1;next} /^[[:space:]]*\[/{ok=0} ok&&/^[[:space:]]*debug_port[[:space:]]*=/{sub(/^[^=]*=/,"");gsub(/[[:space:]]+/,"");print;exit}' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida."
}

validate_common() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk seq mv; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python; read_runtime; read_debug_port
    for file in "$TEST_CONFIG" "$RANGES_FILE" "$RUNTIME_EXE" "$CACHE_MANIFEST" "$SOURCE_RESULT"; do
        [[ -f "$file" ]] || fail "Arquivo ausente: $file"
    done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel OVL-002C divergiu."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    [[ "$(sha256sum "$SOURCE_RESULT" | awk '{print toupper($1)}')" == "$EXPECTED_SOURCE_SHA" ]] || fail "Baseline residual da bomba divergiu."
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" "$SOURCE_RESULT" <<'PY'
import hashlib,json,pathlib,sys
runtime=pathlib.Path(sys.argv[1]); manifest=json.loads(pathlib.Path(sys.argv[2]).read_text(encoding='utf-8'))
source=json.loads(pathlib.Path(sys.argv[3]).read_text(encoding='utf-8'))
if manifest.get('track')!='OVL-002C-DDARK-BOMBS-CUMULATIVE': raise SystemExit('manifesto nao pertence a OVL-002C')
if int(manifest.get('image_body_words',0))!=2074: raise SystemExit('manifesto OVL-002C com volume divergente')
for item in manifest.get('files',[]):
    path=runtime/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']): raise SystemExit(f'cache ausente: {item["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']: raise SystemExit(f'cache alterado: {item["path"]}')
pcs=[str(row.get('pc','')).lower() for row in source.get('entries',[])]
if source.get('track')!='OVL-002C-DDARK-BOMBS-DISCOVERY' or len(pcs)!=38 or len(set(pcs))!=38:
    raise SystemExit('baseline residual nao contem exatamente os 38 PCs esperados')
PY
}

make_session_dir() {
    local suffix candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-002c-ddark-ownership-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; SESSION_DIR="$candidate"; return; fi
    done
    fail "Nao ha pasta livre para a coleta comparativa."
}

write_state() {
    umask 077
    {
        printf 'session_dir=%s\nruntime_dir=%s\nphase=ryu_complete\n' "$SESSION_DIR" "$RUNTIME_DIR"
        printf 'source_sha256=%s\nryu_result=%s\n' "$EXPECTED_SOURCE_SHA" "$SESSION_DIR/phase-01-ryu-neutral/result.json"
    } >"$ACTIVE_STATE"
}

read_state() {
    [[ -f "$ACTIVE_STATE" ]] || fail "Parte Ryu ausente. Execute primeiro o modo ryu."
    SESSION_DIR="$(state_value "$ACTIVE_STATE" session_dir)"
    [[ "$(state_value "$ACTIVE_STATE" runtime_dir)" == "$RUNTIME_DIR" ]] || fail "Runtime mudou entre as duas partes."
    [[ "$(state_value "$ACTIVE_STATE" phase)" == ryu_complete ]] || fail "Estado da coleta comparativa invalido."
    [[ "$(state_value "$ACTIVE_STATE" source_sha256)" == "$EXPECTED_SOURCE_SHA" ]] || fail "Baseline mudou entre as duas partes."
    case "$SESSION_DIR" in "$PROJECT_ROOT"/local/telemetry/ovl-002c-ddark-ownership-*) ;; *) fail "Diretorio de sessao invalido." ;; esac
    [[ -f "$SESSION_DIR/phase-01-ryu-neutral/result.json" ]] || fail "Resultado Ryu ausente."
}

next_ddark_dir() {
    local suffix candidate
    candidate="$SESSION_DIR/phase-02-ddark-bombs"
    if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    for suffix in $(seq -w 2 99); do
        candidate="$SESSION_DIR/phase-02-ddark-bombs-retry-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; printf '%s\n' "$candidate"; return; fi
    done
    fail "Nao ha pasta livre para repetir a parte D.Dark."
}

capture_phase() {
    local mode="$1" output_dir="$2"
    "$PYTHON_BIN" - "$DEBUG_PORT" "$output_dir" "$SOURCE_RESULT" "$RANGES_FILE" "$mode" "$PREPARE_SECONDS" "$CAPTURE_SECONDS" <<'PY'
import csv,json,pathlib,re,socket,struct,sys,time,zlib
port=int(sys.argv[1]); out=pathlib.Path(sys.argv[2]); source_path=pathlib.Path(sys.argv[3])
ranges_path=pathlib.Path(sys.argv[4]); mode=sys.argv[5]; prepare_s=int(sys.argv[6]); capture_s=int(sys.argv[7])

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
        for row in page.get('entries',[]):
            if row.get('pc'): rows[f'0x{int(str(row["pc"]),16):08X}']=row
        returned=int(page.get('returned',0) or 0); total=int(page.get(count_key,0) or 0); offset+=returned
        if returned==0 or offset>=total: break
        if offset>65536: raise RuntimeError(f'{command}: paginacao excedida')
    header['entries']=list(rows.values()); return header

def index(snapshot): return {f'0x{int(str(x["pc"]),16):08X}':x for x in snapshot.get('entries',[]) if x.get('pc')}
def delta(a,b,key): return max(0,int(b.get(key,0) or 0)-int(a.get(key,0) or 0))

source=json.loads(source_path.read_text(encoding='utf-8'))
targets=[f'0x{int(str(row["pc"]),16):08X}' for row in source['entries']]
native_ranges=[]
for line in ranges_path.read_text(encoding='utf-8').splitlines():
    fields=line.split()
    if len(fields)==3 and fields[0]=='R': native_ranges.append((int(fields[1],16),int(fields[1],16)+int(fields[2],16)))

probe=request('overlay_loader_status')
(out/'preflight-loader-status.json').write_text(json.dumps(probe,indent=2,sort_keys=True)+'\n',encoding='utf-8')
if mode=='ddark':
    expected_live={0x80049568:0x9611F1A0,0x80049808:0xCB050F22,0x80049988:0x6D2C8CD6}
    gate={}; gate_errors=[]
    for pc,wanted in expected_live.items():
        words=request('mem_words',addr=f'0x{pc:08X}',count=32).get('words',[])
        crc=zlib.crc32(b''.join(struct.pack('<I',int(word,16)) for word in words))&0xffffffff if len(words)==32 else -1
        candidates=request('overlay_candidates',pc=f'0x{pc:08X}').get('candidates',[])
        exact=any(int(candidate.get('match',0))==1 and int(candidate.get('state',9))==0 and
                  int(candidate.get('dll',-1))>=0 and int(candidate.get('device_touch',1))==0
                  for candidate in candidates)
        gate[f'0x{pc:08X}']={'crc32':f'0x{crc&0xffffffff:08X}','expected_crc32':f'0x{wanted:08X}',
                             'crc_match':crc==wanted,'candidate_exact_active':exact}
        if crc!=wanted: gate_errors.append(f'0x{pc:08X}: bytes vivos do D.Dark divergentes')
    (out/'preflight-ddark-live-gate.json').write_text(json.dumps({'pcs':gate,'errors':gate_errors},indent=2,sort_keys=True)+'\n',encoding='utf-8')
    if gate_errors: raise RuntimeError('; '.join(gate_errors))
for remaining in range(prepare_s,0,-1): print(f'Prepare-se: {remaining}...',flush=True); time.sleep(1)
action='mantenha os dois Ryus neutros' if mode=='ryu' else 'repita somente bombas sem acertar Ryu'
before_static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
before_dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
before_diag={name:request(name) for name in ('overlay_loader_status','dirty_ram_stats','dispatch_stats')}
print(f'\a[CAPTURANDO] Por {capture_s} s, {action}.',flush=True)
started=time.monotonic(); time.sleep(capture_s); elapsed=time.monotonic()-started
after_dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
after_static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
after_diag={name:request(name) for name in ('overlay_loader_status','dirty_ram_stats','dispatch_stats')}
print('\a\a[FIM DA CAPTURA] Pare as acoes.',flush=True)

bs,bd,ns,nd=map(index,(before_static,before_dynamic,after_static,after_dynamic)); rows=[]; evidence={}
for pc in targets:
    s0,s1=bs.get(pc,{}),ns.get(pc,{}); d0,d1=bd.get(pc,{}),nd.get(pc,{})
    static=sum(delta(s0,s1,key) for key in ('misses','modified','runtime','unknown'))
    entries=delta(d0,d1,'entry_hits'); insns=delta(d0,d1,'insns'); blocks=delta(d0,d1,'hits'); addr=int(pc,16)
    rows.append({'pc':pc,'external_entries':max(static,entries),'static_entries':static,'dynamic_entries':entries,
                 'interpreted_blocks':blocks,'interpreted_insns':insns,'entries_per_s':max(static,entries)/elapsed,
                 'insns_per_s':insns/elapsed,'covered_by_static_range':any(a<=addr<b for a,b in native_ranges)})
    item={'pc':pc}
    try:
        words=request('mem_words',addr=pc,count=32).get('words',[]); item['word_count']=len(words)
        if words:
            blob=b''.join(struct.pack('<I',int(word,16)) for word in words)
            item['prefix_crc32']=f'0x{zlib.crc32(blob)&0xffffffff:08X}'
        item['overlay_candidates']=request('overlay_candidates',pc=pc).get('candidates',[])
    except Exception as exc: item['error']=str(exc)
    evidence[pc]=item
rows.sort(key=lambda row:(-row['interpreted_insns'],-row['external_entries'],row['pc']))
for name,data in [('before-static.json',before_static),('before-dynamic.json',before_dynamic),('after-static.json',after_static),
                  ('after-dynamic.json',after_dynamic),('before-diagnostics.json',before_diag),('after-diagnostics.json',after_diag),
                  ('live-evidence.json',evidence)]:
    (out/name).write_text(json.dumps(data,indent=2,sort_keys=True)+'\n',encoding='utf-8')
result={'track':'OVL-002C-DDARK-OWNERSHIP-COMPARISON','mode':mode,'duration_s':elapsed,'target_count':len(targets),
        'interpreted_target_count':sum(1 for row in rows if row['interpreted_insns'] or row['external_entries']),
        'target_interpreted_insns':sum(row['interpreted_insns'] for row in rows),'entries':rows}
(out/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
with (out/'targets.csv').open('w',encoding='utf-8',newline='') as handle:
    writer=csv.DictWriter(handle,fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
title='Ryu P1 x Ryu P2 neutros' if mode=='ryu' else 'D.Dark P1 x Ryu P2 - bombas'
lines=[f'# {title}','',f'- Duracao: {elapsed:.3f} s',f'- PCs-alvo: {len(targets)}',
       f'- PCs-alvo disparados: {result["interpreted_target_count"]}',f'- Instrucoes interpretadas nos alvos: {result["target_interpreted_insns"]}',
       '','| PC | Entradas | Instrucoes | Instrucoes/s |','|---|---:|---:|---:|']
for row in rows:
    if row['interpreted_insns'] or row['external_entries']:
        lines.append(f'| `{row["pc"]}` | {row["external_entries"]} | {row["interpreted_insns"]} | {row["insns_per_s"]:.1f} |')
if result['interpreted_target_count']==0: lines.append('| - | 0 | 0 | 0.0 |')
(out/'summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
PY
}

compare_results() {
    local ddark_dir="$1"
    "$PYTHON_BIN" - "$SESSION_DIR" "$ddark_dir" <<'PY'
import csv,json,pathlib,sys
session=pathlib.Path(sys.argv[1]); ddark_dir=pathlib.Path(sys.argv[2]); ryu_dir=session/'phase-01-ryu-neutral'
ryu=json.loads((ryu_dir/'result.json').read_text(encoding='utf-8')); ddark=json.loads((ddark_dir/'result.json').read_text(encoding='utf-8'))
ryu_e=json.loads((ryu_dir/'live-evidence.json').read_text(encoding='utf-8')); ddark_e=json.loads((ddark_dir/'live-evidence.json').read_text(encoding='utf-8'))
ri={row['pc']:row for row in ryu['entries']}; di={row['pc']:row for row in ddark['entries']}; rows=[]
for pc in ri:
    r=ri[pc]; d=di[pc]; rr=int(r['interpreted_insns']); dr=int(d['interpreted_insns'])
    rcrc=ryu_e.get(pc,{}).get('prefix_crc32',''); dcrc=ddark_e.get(pc,{}).get('prefix_crc32','')
    body='same_crc' if rcrc and rcrc==dcrc else ('different_crc' if rcrc and dcrc else 'crc_unavailable')
    if dr>0 and rr==0: execution='ddark_only_observed'
    elif dr>0 and rr>0: execution='both_observed'
    elif dr==0 and rr>0: execution='ryu_only_observed'
    else: execution='not_reproduced'
    rows.append({'pc':pc,'ryu_insns':rr,'ryu_insns_per_s':float(r['insns_per_s']),'ddark_insns':dr,
                 'ddark_insns_per_s':float(d['insns_per_s']),'ryu_crc32':rcrc,'ddark_crc32':dcrc,
                 'body_relation':body,'execution_class':execution})
rows.sort(key=lambda row:(-row['ddark_insns'],row['ryu_insns'],row['pc']))
with (session/'ownership-comparison.csv').open('w',encoding='utf-8',newline='') as handle:
    writer=csv.DictWriter(handle,fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
candidates=[row['pc'] for row in rows if row['execution_class']=='ddark_only_observed']
(session/'ddark-only-observed-pcs.txt').write_text('\n'.join(candidates)+('\n' if candidates else ''),encoding='utf-8')
result={'track':'OVL-002C-DDARK-OWNERSHIP-COMPARISON','ryu_result':str(ryu_dir/'result.json'),
        'ddark_result':str(ddark_dir/'result.json'),'target_count':len(rows),'ddark_only_observed_count':len(candidates),
        'rows':rows,'interpretation_notice':'Zero no Ryu vale somente para a janela coletada; nao prova impossibilidade global. CRC diferente indica reutilizacao do endereco por outro corpo.'}
(session/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
lines=['# Comparacao de ownership: Ryu x Ryu versus D.Dark x Ryu','',f'- PCs comparados: {len(rows)}',
       f'- PCs observados somente com D.Dark: {len(candidates)}','- Escopo: Ryu neutro versus bombas repetidas do D.Dark, 30 s por janela.',
       '- Importante: zero no Ryu prova apenas ausencia na janela coletada; nao prova impossibilidade em todas as rotas.','',
       '| PC | Ryu instr./s | D.Dark instr./s | Corpos | Classe |','|---|---:|---:|---|---|']
for row in rows:
    if row['ryu_insns'] or row['ddark_insns']:
        lines.append(f'| `{row["pc"]}` | {row["ryu_insns_per_s"]:.1f} | {row["ddark_insns_per_s"]:.1f} | {row["body_relation"]} | {row["execution_class"]} |')
(session/'summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(f'Comparacao concluida: {session}')
PY
}

run_ryu() {
    if [[ -f "$ACTIVE_STATE" ]]; then
        local previous_session
        previous_session="$(state_value "$ACTIVE_STATE" session_dir)"
        case "$previous_session" in "$PROJECT_ROOT"/local/telemetry/ovl-002c-ddark-ownership-*) ;; *) fail "Sessao ativa anterior invalida." ;; esac
        [[ -d "$previous_session" ]] || fail "Diretorio da sessao ativa anterior ausente."
        [[ ! -e "$previous_session/abandoned.state" ]] || fail "A sessao anterior ja possui abandoned.state."
        mv "$ACTIVE_STATE" "$previous_session/abandoned.state"
        printf 'Coleta anterior preservada como abandonada: %s\n' "$previous_session"
    fi
    make_session_dir
    mkdir "$SESSION_DIR/phase-01-ryu-neutral"
    {
        printf 'track=OVL-002C-DDARK-OWNERSHIP-COMPARISON\nruntime_dir=%s\n' "$RUNTIME_DIR"
        printf 'source_result=%s\nsource_sha256=%s\n' "$SOURCE_RESULT" "$EXPECTED_SOURCE_SHA"
        printf 'phase_1=Ryu P1 x Ryu P2; ambos neutros; 30 s\n'
        printf 'phase_2=D.Dark P1 x Ryu P2; somente bombas sem acerto; 30 s\n'
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
    printf '\nPosicione o jogo em Versus: Ryu P1 x Ryu P2, cenario do Ryu, ambos neutros.\n'
    read -r -p "Pressione Enter quando o gameplay estiver controlavel: "
    capture_phase ryu "$SESSION_DIR/phase-01-ryu-neutral"
    write_state
    printf '\nParte 1 concluida. Volte a selecao na mesma execucao e escolha D.Dark P1 x Ryu P2.\n'
    printf 'Depois execute: bash tools/observer_ddark_vs_ryu_ownership_ovl_002c.sh ddark\n'
}

run_ddark() {
    read_state
    local ddark_dir
    ddark_dir="$(next_ddark_dir)"
    printf '\nPosicione o jogo em Versus: D.Dark P1 x Ryu P2, cenario do Ryu.\n'
    printf 'Mantenha Ryu parado; durante a janela, repita somente bombas sem acerta-lo.\n'
    read -r -p "Pressione Enter quando o gameplay estiver controlavel: "
    capture_phase ddark "$ddark_dir"
    compare_results "$ddark_dir"
    mv "$ACTIVE_STATE" "$SESSION_DIR/completed.state"
    printf '\nParte 2 concluida. Resumo: %s/summary.md\n' "$SESSION_DIR"
}

show_status() {
    if [[ ! -f "$ACTIVE_STATE" ]]; then printf 'Nenhuma comparacao Ryu/D.Dark ativa.\n'; return; fi
    printf 'Sessao: %s\nFase: %s\n' "$(state_value "$ACTIVE_STATE" session_dir)" "$(state_value "$ACTIVE_STATE" phase)"
}

main() {
    case "${1:-}" in
        ryu|ddark) validate_common ;;
        status) show_status; return ;;
        -h|--help) usage; return ;;
        *) usage; fail "Use ryu, ddark ou status." ;;
    esac
    case "$1" in ryu) run_ryu ;; ddark) run_ddark ;; esac
}

main "$@"
