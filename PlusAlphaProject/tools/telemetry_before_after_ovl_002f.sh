#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly RAW_TCP="$REPO_ROOT/psxrecomp/tools/raw_tcp.py"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002f_test.toml"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002f-current-runtime.state"
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.ovl-002f-test-active.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly NATIVE_PCS="80044C7C 80044CAC 80044830 80044B8C 80047DE8 80049568 80049808 80049988 80092C2C 80093E4C"
readonly HANDLER_PCS="80044CBC 80045124 80045868 80045A1C 80045C14 80045E30 80046034 800465A8 80046998 80046C38 80047000"
readonly WATCH_PCS="$NATIVE_PCS $HANDLER_PCS"

PYTHON_BIN=
DEBUG_PORT=
RUNTIME_DIR=
RUNTIME_EXE=
CACHE_MANIFEST=
RUN_DIR=
RUN_PHASE=
START_EPOCH_NS=0

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com a mesma execucao OVL-002F aberta:

  bash tools/telemetry_before_after_ovl_002f.sh prepare
  bash tools/telemetry_before_after_ovl_002f.sh before
  bash tools/telemetry_before_after_ovl_002f.sh after

Para liberar uma coleta que terminou em REVIEW, preservando seus arquivos:

  bash tools/telemetry_before_after_ovl_002f.sh retry

PREPARE: Mode Select.
BEFORE : Versus, D.Dark P1 x Ryu P2, cenario Ryu; aguarde 3-5 s neutros.
AFTER  : no mesmo round, depois de 10 bombas sem acertar Ryu, 5 de cada lado.

Use somente o movimento minimo necessario para soltar as bombas.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_runtime() {
    if [[ ! -f "$RUNTIME_STATE" ]]; then
        local candidate partial=
        for candidate in "$PROJECT_ROOT"/local/overlay/ovl-002f-test-runtime-*; do
            [[ -d "$candidate" ]] && partial="$candidate"
        done
        [[ -z "$partial" ]] || fail "Compilacao OVL-002F incompleta em $partial. Execute novamente compile_ovl_002f_test_runtime.sh."
        fail "Runtime OVL-002F ausente. Execute compile_ovl_002f_test_runtime.sh."
    fi
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"; RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002f-test-runtime-*) ;; *) fail "Runtime OVL-002F invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" capture_key)" == 0x00020000:0xF943B63B ]] || fail "Chave divergente."
    [[ "$(state_value "$RUNTIME_STATE" target)" == 0x80044C7C && "$(state_value "$RUNTIME_STATE" continuation)" == 0x80044CAC ]] || fail "Raiz/retorno JALR divergente."
    [[ "$(state_value "$RUNTIME_STATE" alias_1)" == 0x80044CAC ]] || fail "Alias interno do retorno ausente. Recompile OVL-002F."
    [[ "$(state_value "$RUNTIME_STATE" incremental_words)" == 16 && "$(state_value "$RUNTIME_STATE" image_body_words)" == 2434 ]] || fail "Volume divergente."
    [[ -f "$RUNTIME_EXE" && -f "$CACHE_MANIFEST" ]] || fail "Runtime incompleto."
}

validate_common() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep mv seq; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python; read_runtime
    [[ -f "$RAW_TCP" && -f "$TEST_CONFIG" ]] || fail "Infraestrutura ausente."
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel divergiu."
    [[ "$(sha256sum "$PROJECT_ROOT/generated/SLUS_005.48_full.ranges" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    DEBUG_PORT="$(awk '/^[[:space:]]*\[runtime\]/{ok=1;next} /^[[:space:]]*\[/{ok=0} ok&&/^[[:space:]]*debug_port[[:space:]]*=/{sub(/^[^=]*=/,"");gsub(/[[:space:]]+/,"");print;exit}' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" == 4534 ]] || fail "debug_port divergente."
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); data=json.loads(pathlib.Path(sys.argv[2]).read_text(encoding='utf-8'))
if data.get('track')!='OVL-002F-DDARK-BOMB-DISPATCH-CUMULATIVE' or int(data.get('image_body_words',0))!=2434:
    raise SystemExit('manifesto nao pertence a OVL-002F')
if data.get('new_root')!='0x80044C7C' or data.get('new_aliases')!=['0x80044CAC'] or data.get('jalr_continuation')!='0x80044CAC': raise SystemExit('manifesto OVL-002F divergente')
for item in data.get('files',[]):
    path=root/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']) or hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']:
        raise SystemExit(f'cache alterado: {item["path"]}')
PY
}

raw() {
    local output="$1"; shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 || fail "Falha TCP: $*"
    grep -q '"ok":true' "$output" || fail "Resposta TCP invalida: $*"
    grep -q '^OK keys:' "$output" || fail "JSON truncado: $*"
}

make_run_dir() {
    local suffix candidate; mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-002f-telemetry-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi
    done
    fail "Nao ha pasta livre para telemetria OVL-002F."
}

write_state() {
    umask 077
    printf 'run_dir=%s\nruntime_dir=%s\nphase=%s\nstart_epoch_ns=%s\n' "$RUN_DIR" "$RUNTIME_DIR" "$1" "$START_EPOCH_NS" >"$STATE_FILE"
    RUN_PHASE="$1"
}

read_state() {
    [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta ativa; execute prepare."
    RUN_DIR="$(state_value "$STATE_FILE" run_dir)"; RUN_PHASE="$(state_value "$STATE_FILE" phase)"; START_EPOCH_NS="$(state_value "$STATE_FILE" start_epoch_ns)"
    [[ "$(state_value "$STATE_FILE" runtime_dir)" == "$RUNTIME_DIR" ]] || fail "Runtime mudou durante a coleta."
    case "$RUN_DIR" in "$PROJECT_ROOT"/local/telemetry/ovl-002f-telemetry-*) ;; *) fail "Run invalido." ;; esac
}

archive_review_phase() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in awk mv; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta ativa para arquivar."
    local review_dir review_phase
    review_dir="$(state_value "$STATE_FILE" run_dir)"; review_phase="$(state_value "$STATE_FILE" phase)"
    case "$review_dir" in "$PROJECT_ROOT"/local/telemetry/ovl-002f-telemetry-*) ;; *) fail "Run ativo invalido." ;; esac
    [[ -d "$review_dir" && ! -e "$review_dir/review.state" ]] || fail "Destino REVIEW invalido ou ja existente."
    mv "$STATE_FILE" "$review_dir/review.state"
    printf 'Coleta %s preservada em REVIEW (fase %s). O proximo prepare criara um novo sufixo.\n' "$review_dir" "$review_phase"
}

general_snapshot() {
    local phase="$1"
    raw "$RUN_DIR/${phase}_overlay_loader_status.log" overlay_loader_status
    raw "$RUN_DIR/${phase}_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/${phase}_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/${phase}_overlay_shadow_dump.log" overlay_shadow_dump
    raw "$RUN_DIR/${phase}_overlay_native_ring.log" overlay_native_ring
}

live_snapshot() {
    local phase="$1" pc
    for pc in $NATIVE_PCS; do
        raw "$RUN_DIR/${phase}_${pc}_words.log" mem_words addr="0x$pc" count=32
        raw "$RUN_DIR/${phase}_${pc}_candidate.log" overlay_candidates pc="0x$pc"
    done
    raw "$RUN_DIR/${phase}_indirect_table.log" mem_words addr=0x800431C0 count=12
}

verify_live() {
    "$PYTHON_BIN" - "$RUN_DIR" "$1" <<'PY'
import json,pathlib,re,struct,sys,zlib
run=pathlib.Path(sys.argv[1]); phase=sys.argv[2]
expected={'80044C7C':0xD929A55E,'80044CAC':0x990698B6,'80044830':0x9E9CD462,'80044B8C':0xD7D51FE0,
          '80047DE8':0xBEFA5EA1,'80049568':0x9611F1A0,'80049808':0xCB050F22,'80049988':0x6D2C8CD6,
          '80092C2C':0x1B64D20F,'80093E4C':0x12FF550F}
wanted_table=['0x80044CBC','0x80045124','0x80045868','0x80045A1C','0x80045A1C','0x80045C14',
              '0x80045E30','0x80046034','0x800465A8','0x80046C38','0x80046998','0x80047000']
def raw(name):
    text=(run/name).read_text(encoding='utf-8',errors='replace'); match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not match: raise SystemExit(f'JSON ausente: {name}')
    return json.loads(match.group(1))
errors=[]; crcs={}; matches={}
for pc,wanted in expected.items():
    words=raw(f'{phase}_{pc}_words.log').get('words',[])
    if len(words)!=32: errors.append(f'0x{pc}: leitura incompleta'); continue
    crc=zlib.crc32(b''.join(struct.pack('<I',int(item,16)) for item in words))&0xffffffff; crcs['0x'+pc]=f'0x{crc:08X}'
    if crc!=wanted: errors.append(f'0x{pc}: CRC 0x{crc:08X}, esperado 0x{wanted:08X}')
    candidates=raw(f'{phase}_{pc}_candidate.log').get('candidates',[])
    exact=any(int(item.get('match',0))==1 and int(item.get('state',9))==0 and int(item.get('dll',-1))>=0 and int(item.get('device_touch',1))==0 for item in candidates)
    matches['0x'+pc]=exact
    if not exact: errors.append(f'0x{pc}: candidato GCC exato ausente/inativo')
table=[f'0x{int(item,16):08X}' for item in raw(f'{phase}_indirect_table.log').get('words',[])]
if table!=wanted_table: errors.append('tabela indireta 0x800431C0 divergente')
if errors: raise SystemExit('ERRO: gate vivo '+phase.upper()+': '+'; '.join(errors))
(run/f'{phase}-live-gate.json').write_text(json.dumps({'phase':phase,'prefix_crc32':crcs,'candidate_match':matches,'indirect_table':table},indent=2,sort_keys=True)+'\n')
print(f'Gate {phase.upper()}: raiz, retorno JALR, sentinelas e tabela indireta possuem identidade exata.')
PY
}

arm_watch() {
    raw "$RUN_DIR/prepare_pc_watch_clear.log" pc_watch_clear
    local pc
    for pc in $WATCH_PCS; do raw "$RUN_DIR/prepare_pc_watch_arm_${pc}.log" pc_watch_arm target="0x$pc"; done
    raw "$RUN_DIR/prepare_pc_watch_dump.log" pc_watch_dump
    "$PYTHON_BIN" - "$RUN_DIR/prepare_pc_watch_dump.log" <<'PY'
import json,pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text(errors='replace'); match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
if not match: raise SystemExit('pc_watch PREPARE sem JSON')
watch=json.loads(match.group(1)); targets={str(item.get('target','')).upper() for item in watch.get('entries',[])}
expected={f'0X{x:08X}' for x in (0x80044C7C,0x80044CAC,0x80044830,0x80044B8C,0x80047DE8,0x80049568,0x80049808,
          0x80049988,0x80092C2C,0x80093E4C,0x80044CBC,0x80045124,0x80045868,0x80045A1C,0x80045C14,0x80045E30,
          0x80046034,0x800465A8,0x80046998,0x80046C38,0x80047000)}
if not watch.get('armed') or targets!=expected: raise SystemExit(f'pc_watch divergente: {targets}')
PY
}

analyze() {
    "$PYTHON_BIN" - "$RUN_DIR" "$START_EPOCH_NS" <<'PY'
import json,pathlib,re,sys,time
run=pathlib.Path(sys.argv[1]); start=int(sys.argv[2])
def raw(name):
    text=(run/name).read_text(encoding='utf-8',errors='replace'); match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not match: raise SystemExit(f'JSON ausente: {name}')
    return json.loads(match.group(1))
def delta(before,after,key): return max(0,int(after.get(key,0) or 0)-int(before.get(key,0) or 0))
before_loader=raw('before_overlay_loader_status.log'); after_loader=raw('after_overlay_loader_status.log')
before_dirty=raw('before_dirty_ram_stats.log'); after_dirty=raw('after_dirty_ram_stats.log')
before_dispatch=raw('before_dispatch_stats.log'); after_dispatch=raw('after_dispatch_stats.log')
shadow=raw('after_overlay_shadow_dump.log').get('shadow',{}); watch=raw('after_pc_watch_dump.log')
seen={str(item.get('target','')).upper():item for item in watch.get('entries',[])}
native_roles={'0X80044C7C':'nova raiz OVL-002F','0X80044CAC':'retorno apos JALR',
 '0X80044830':'sentinela raiz OVL-002E','0X80044B8C':'sentinela alias OVL-002E','0X80047DE8':'sentinela OVL-002D',
 '0X80049568':'sentinela raiz OVL-002C','0X80049808':'sentinela alias OVL-002C 1','0X80049988':'sentinela alias OVL-002C 2',
 '0X80092C2C':'sentinela OVL-002B','0X80093E4C':'sentinela OVL-002A'}
handler_roles={'0X80044CBC':'handler 0','0X80045124':'handler 1','0X80045868':'handler 2','0X80045A1C':'handlers 3/4',
 '0X80045C14':'handler 5','0X80045E30':'handler 6 - familia da bomba','0X80046034':'handler 7','0X800465A8':'handler 8',
 '0X80046998':'handler 10','0X80046C38':'handler 9','0X80047000':'handler 11'}
targets={}; errors=[]
for pc,role in {**native_roles,**handler_roles}.items():
    item=seen.get(pc,{}); hits=int(item.get('hits',0) or 0); native=int(item.get('native_hits',0) or 0); interp=int(item.get('interpreted_hits',0) or 0)
    targets[pc]={'role':role,'hits':hits,'native_hits':native,'interpreted_hits':interp}
    if hits!=native+interp: errors.append(f'{pc}: contadores inconsistentes')
    if pc in native_roles:
        if native<=0: errors.append(f'{pc}: nenhum hit nativo')
        if interp: errors.append(f'{pc}: {interp} hit(s) interpretado(s)')
    elif native:
        errors.append(f'{pc}: handler excluido teve {native} hit(s) nativo(s)')
if sum(targets[pc]['interpreted_hits'] for pc in handler_roles)<=0:
    errors.append('nenhum handler indireto excluido foi observado')
loader={key:delta(before_loader,after_loader,key) for key in ('dispatch_native','dispatch_interp_fallback','stale_blocked','invalidations','unregistered_funcs')}
guards={key:delta(before_dirty,after_dirty,key) for key in ('aborts','native_handoffs','text_native_blocked','text_diverged_pages','text_exact_mismatches')}
fatal={key:value for key,value in guards.items() if key!='native_handoffs'}; miss=delta(before_dispatch,after_dispatch,'miss_total')
if loader['dispatch_native']<=0: errors.append('dispatch_native nao cresceu')
if loader['unregistered_funcs']: errors.append('funcoes nativas desregistradas')
if any(fatal.values()): errors.append('guard dirty-RAM fatal nao zerado')
if miss: errors.append('miss_total cresceu')
if int(shadow.get('diff_mode',1)) or int(shadow.get('shadow_calls',0)) or int(shadow.get('in_shadow',0)) or int(shadow.get('native_exec',0))!=1:
    errors.append('estado shadow/native invalido')
before=json.loads((run/'before-live-gate.json').read_text()); after=json.loads((run/'after-live-gate.json').read_text())
if before.get('prefix_crc32')!=after.get('prefix_crc32') or before.get('indirect_table')!=after.get('indirect_table'):
    errors.append('bytes vivos ou tabela indireta mudaram')
duration=max(0,(time.time_ns()-start)/1e9); clean=not errors
result={'track':'OVL-002F-DDARK-BOMB-DISPATCH-CUMULATIVE','duration_s':round(duration,3),'incremental_words':16,
        'prior_image_words':2418,'image_body_words':2434,'jalr_pc':'0x80044CA4','jalr_continuation':'0x80044CAC',
        'targets':targets,'loader_deltas':loader,'guard_deltas':guards,'dispatch_miss_delta':miss,'errors':errors,'technical_clean':clean}
(run/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
lines=['# OVL-002F - wrapper de despacho da bomba','',f'- Duracao: {duration:.3f} s','- Incremento: 16 palavras; corpo cumulativo: 2.434',
       f'- Dispatch nativo: +{loader["dispatch_native"]}',f'- Fallback geral informativo: +{loader["dispatch_interp_fallback"]}',
       f'- Guards fatais: {fatal}',f'- Stale/invalidation informativos: {loader["stale_blocked"]}/{loader["invalidations"]}',
       f'- Miss total: {miss}',f'- Status tecnico: {"CLEAN" if clean else "REVIEW"}','','| PC | Papel | Nativos | Interpretados |',
       '|---|---|---:|---:|']
for pc in [*native_roles,*handler_roles]:
    item=targets[pc]; lines.append(f'| `{pc}` | {item["role"]} | {item["native_hits"]} | {item["interpreted_hits"]} |')
if errors: lines += ['','## Bloqueios','']+[f'- {item}' for item in errors]
(run/'summary.md').write_text('\n'.join(lines)+'\n')
PY
}

prepare_phase() {
    [[ ! -f "$STATE_FILE" ]] || fail "Ja existe coleta OVL-002F ativa."
    make_run_dir
    raw "$RUN_DIR/prepare_native_block_clear.log" overlay_native_block clear=1
    raw "$RUN_DIR/prepare_overlay_diff_off.log" overlay_diff_off
    general_snapshot prepare; arm_watch
    printf 'track=OVL-002F-DDARK-BOMB-DISPATCH-CUMULATIVE\nruntime_dir=%s\nroute=D.Dark P1 x Ryu P2; cenario Ryu; bombas sem acerto\n' "$RUNTIME_DIR" >"$RUN_DIR/metadata.txt"
    write_state prepared
    printf '\nPREPARE concluido. Entre no Versus, aguarde 3-5 s neutros e execute BEFORE.\n'
}

before_phase() {
    read_state; [[ "$RUN_PHASE" == prepared ]] || fail "BEFORE exige fase prepared."
    general_snapshot before; live_snapshot before; verify_live before
    raw "$RUN_DIR/window_pc_watch_reset.log" pc_watch_reset
    START_EPOCH_NS="$("$PYTHON_BIN" -c 'import time; print(time.time_ns())')"; write_state before
    printf '\nBEFORE concluido. Execute 10 bombas sem acertar Ryu, 5 de cada lado, com movimento minimo. Depois execute AFTER.\n'
}

after_phase() {
    read_state; [[ "$RUN_PHASE" == before ]] || fail "AFTER exige fase before."
    raw "$RUN_DIR/after_pc_watch_stop.log" pc_watch_stop
    general_snapshot after; live_snapshot after; verify_live after
    raw "$RUN_DIR/after_pc_watch_dump.log" pc_watch_dump
    raw "$RUN_DIR/after_overlay_diff_off.log" overlay_diff_off
    analyze
    local result_status
    if ! result_status="$("$PYTHON_BIN" - "$RUN_DIR/result.json" 2>&1 <<'PY'
import json,pathlib,sys
result=json.loads(pathlib.Path(sys.argv[1]).read_text())
if not result.get('technical_clean'): raise SystemExit('ERRO: AFTER em REVIEW: '+'; '.join(result.get('errors',[])))
print('Gate AFTER OVL-002F: raiz e retorno JALR nativos; handlers indiretos permaneceram fora do lote.')
PY
    )"; then
        mv "$STATE_FILE" "$RUN_DIR/review.state"
        printf '%s\n' "$result_status" >&2
        fail "Coleta preservada em REVIEW. O proximo prepare usara outro sufixo."
    fi
    printf '%s\n' "$result_status"
    mv "$STATE_FILE" "$RUN_DIR/completed.state"
    printf '\nAFTER concluido. Resumo: %s/summary.md\n' "$RUN_DIR"
}

main() {
    case "${1:-}" in retry) archive_review_phase; return ;; prepare|before|after) ;; *) usage; fail "Use prepare, before, after ou retry." ;; esac
    validate_common
    case "$1" in prepare) prepare_phase ;; before) before_phase ;; after) after_phase ;; esac
}

main "$@"

