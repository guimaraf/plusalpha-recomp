#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly RAW_TCP="$REPO_ROOT/psxrecomp/tools/raw_tcp.py"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002h_test.toml"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002h-current-runtime.state"
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.ovl-002h-test-active.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly REQUIRED_NATIVE_PCS="800465A8 800466A8 800466D8 800466FC 80046710 80046724 800467BC 8004681C 80046830 800468EC 800468F8 80047DD8"
readonly OPTIONAL_NATIVE_PCS="80046634 80046704 80046810 800468A0 800468CC 80046920 80047DB8 80045E30 80044C7C 80044830 80047DE8 80049568 80092C2C 80093E4C"
readonly NATIVE_PCS="$REQUIRED_NATIVE_PCS $OPTIONAL_NATIVE_PCS"
readonly EXCLUDED_PCS="80044CBC 80045124 80045868 80045A1C 80045C14 80046034 80046934 80046998 80046C38 80047000"
readonly WATCH_PCS="$NATIVE_PCS $EXCLUDED_PCS"

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
Uso no MSYS2 UCRT64, com a mesma execucao OVL-002H aberta:

  bash tools/telemetry_before_after_ovl_002h.sh prepare
  bash tools/telemetry_before_after_ovl_002h.sh before
  bash tools/telemetry_before_after_ovl_002h.sh after
  bash tools/telemetry_before_after_ovl_002h.sh retry

PREPARE: Mode Select.
BEFORE : Versus, D.Dark P1 x Ryu P2, cenario Ryu; aguarde 3-5 s neutros.
AFTER  : no mesmo round, faca o especial da bomba explosiva acertar Ryu uma
         vez de cada lado. Pare apos o segundo impacto e antes do KO.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_runtime() {
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-002H ausente. Execute compile_ovl_002h_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"; RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002h-test-runtime-*) ;; *) fail "Runtime OVL-002H invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" target)" == 0x800465A8 && "$(state_value "$RUNTIME_STATE" helper)" == 0x80047DB8 ]] || fail "Raiz/helper divergentes."
    [[ "$(state_value "$RUNTIME_STATE" incremental_words)" == 239 && "$(state_value "$RUNTIME_STATE" image_body_words)" == 2802 ]] || fail "Volume divergente."
    [[ -f "$RUNTIME_EXE" && -f "$CACHE_MANIFEST" ]] || fail "Runtime incompleto."
}

validate_common() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep find mv seq; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python; read_runtime
    [[ -f "$RAW_TCP" && -f "$TEST_CONFIG" ]] || fail "Infraestrutura ausente."
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel divergiu."
    [[ "$(sha256sum "$PROJECT_ROOT/generated/SLUS_005.48_full.ranges" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    DEBUG_PORT="$(awk '/^[[:space:]]*\[runtime\]/{ok=1;next} /^[[:space:]]*\[/{ok=0} ok&&/^[[:space:]]*debug_port[[:space:]]*=/{sub(/^[^=]*=/,"");gsub(/[[:space:]]+/,"");print;exit}' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" == 4535 ]] || fail "debug_port divergente."
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); data=json.loads(pathlib.Path(sys.argv[2]).read_text(encoding='utf-8'))
aliases=['0x80046634','0x800466A8','0x800466D8','0x800466FC','0x80046704','0x80046710','0x80046724','0x800467BC','0x80046810','0x8004681C','0x80046830','0x800468A0','0x800468CC','0x800468EC','0x800468F8','0x80046920','0x80047DD8']
if data.get('track')!='OVL-002H-DDARK-BOMB-SUPER-CUMULATIVE' or int(data.get('image_body_words',0))!=2802: raise SystemExit('manifesto nao pertence a OVL-002H')
if data.get('new_root')!='0x800465A8' or data.get('direct_helper')!='0x80047DB8' or data.get('new_aliases')!=aliases: raise SystemExit('manifesto OVL-002H divergente')
for item in data.get('files',[]):
    path=root/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']) or hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']: raise SystemExit(f'cache alterado: {item["path"]}')
PY
}

raw() {
    local output="$1"; shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 || fail "Falha TCP: $*"
    grep -q '"ok":true' "$output" || fail "Resposta TCP invalida: $*"
    grep -q '^OK keys:' "$output" || fail "JSON truncado: $*"
}

require_debug_server() {
    if ! "$PYTHON_BIN" - "$DEBUG_PORT" <<'PY'
import socket,sys
try:
    with socket.create_connection(('127.0.0.1',int(sys.argv[1])),timeout=1.0):
        pass
except OSError:
    raise SystemExit(1)
PY
    then
        fail "Runtime OVL-002H nao esta escutando na porta $DEBUG_PORT. Abra-o com tools/run_ovl_002h_test.sh, entre no jogo e so entao execute prepare. Nenhuma sessao foi criada."
    fi
}

make_run_dir() {
    local suffix candidate; mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-002h-telemetry-$suffix"
        if [[ -d "$candidate" && -z "$(find "$candidate" -mindepth 1 -print -quit)" ]]; then
            RUN_DIR="$candidate"
            return
        fi
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi
    done
    fail "Nao ha pasta livre para telemetria OVL-002H."
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
    case "$RUN_DIR" in "$PROJECT_ROOT"/local/telemetry/ovl-002h-telemetry-*) ;; *) fail "Run invalido." ;; esac
}

archive_review_phase() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta ativa para arquivar."
    local review_dir review_phase
    review_dir="$(state_value "$STATE_FILE" run_dir)"; review_phase="$(state_value "$STATE_FILE" phase)"
    case "$review_dir" in "$PROJECT_ROOT"/local/telemetry/ovl-002h-telemetry-*) ;; *) fail "Run ativo invalido." ;; esac
    mv "$STATE_FILE" "$review_dir/review.state"
    printf 'Coleta %s preservada em REVIEW (fase %s).\n' "$review_dir" "$review_phase"
}

general_snapshot() {
    local phase="$1"
    raw "$RUN_DIR/${phase}_overlay_loader_status.log" overlay_loader_status
    raw "$RUN_DIR/${phase}_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/${phase}_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/${phase}_overlay_shadow_dump.log" overlay_shadow_dump
}

live_snapshot() {
    local phase="$1" pc
    for pc in $NATIVE_PCS; do
        raw "$RUN_DIR/${phase}_${pc}_words.log" mem_words addr="0x$pc" count=32
        raw "$RUN_DIR/${phase}_${pc}_candidate.log" overlay_candidates pc="0x$pc"
    done
    raw "$RUN_DIR/${phase}_external_table.log" mem_words addr=0x800431C0 count=12
    raw "$RUN_DIR/${phase}_local_jump_table.log" mem_words addr=0x8004A610 count=18
}

verify_live() {
    "$PYTHON_BIN" - "$RUN_DIR" "$1" <<'PY'
import json,pathlib,re,struct,sys,zlib
run=pathlib.Path(sys.argv[1]); phase=sys.argv[2]
expected={'800465A8':0xA4BAA4E5,'80046634':0x552A0E10,'800466A8':0xE49C03BE,'800466D8':0xF5B287E1,
 '800466FC':0x01A8412B,'80046704':0x0C5259B0,'80046710':0x8ADC57E4,'80046724':0x6BD51855,
 '800467BC':0xBD49CA0E,'80046810':0x7331E727,'8004681C':0xCEA306E4,'80046830':0x8ADCB28B,
 '800468A0':0xA21D3720,'800468CC':0xDF864C64,'800468EC':0x1EA8267F,'800468F8':0x8200F878,
 '80046920':0x6BD8118B,'80047DB8':0x4C8755A2,'80047DD8':0x4C4C0DFB,'80045E30':0x95AB7D43,
 '80044C7C':0xD929A55E,'80044830':0x9E9CD462,'80047DE8':0xBEFA5EA1,'80049568':0x9611F1A0,
 '80092C2C':0x1B64D20F,'80093E4C':0x12FF550F}
wanted_external=['0x80044CBC','0x80045124','0x80045868','0x80045A1C','0x80045A1C','0x80045C14','0x80045E30','0x80046034','0x800465A8','0x80046C38','0x80046998','0x80047000']
wanted_local=['0x80046634','0x80046704','0x80046810']+['0x80046920']*13+['0x800468A0','0x800468CC']
def raw(name):
    text=(run/name).read_text(encoding='utf-8',errors='replace'); match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not match: raise SystemExit(f'JSON ausente: {name}')
    return json.loads(match.group(1))
errors=[]; crcs={}; matches={}
for pc,wanted in expected.items():
    words=raw(f'{phase}_{pc}_words.log').get('words',[])
    if len(words)!=32: errors.append(f'0x{pc}: leitura incompleta'); continue
    crc=zlib.crc32(b''.join(struct.pack('<I',int(item,16)) for item in words))&0xffffffff; crcs['0x'+pc]=f'0x{crc:08X}'
    if crc!=wanted: errors.append(f'0x{pc}: CRC divergente')
    candidates=raw(f'{phase}_{pc}_candidate.log').get('candidates',[])
    exact=any(int(item.get('match',0))==1 and int(item.get('state',9))==0 and int(item.get('dll',-1))>=0 and int(item.get('device_touch',1))==0 for item in candidates)
    matches['0x'+pc]=exact
    if not exact: errors.append(f'0x{pc}: candidato GCC exato ausente/inativo')
external=[f'0x{int(item,16):08X}' for item in raw(f'{phase}_external_table.log').get('words',[])]
local=[f'0x{int(item,16):08X}' for item in raw(f'{phase}_local_jump_table.log').get('words',[])]
if external!=wanted_external: errors.append('tabela externa divergente')
if local!=wanted_local: errors.append('tabela local 0x8004A610 divergente')
if errors: raise SystemExit('ERRO: gate vivo '+phase.upper()+': '+'; '.join(errors))
(run/f'{phase}-live-gate.json').write_text(json.dumps({'phase':phase,'prefix_crc32':crcs,'candidate_match':matches,'external_table':external,'local_jump_table':local},indent=2,sort_keys=True)+'\n')
print(f'Gate {phase.upper()}: closure, sentinelas e tabelas possuem identidade exata.')
PY
}

arm_watch() {
    raw "$RUN_DIR/prepare_pc_watch_clear.log" pc_watch_clear
    local pc
    for pc in $WATCH_PCS; do raw "$RUN_DIR/prepare_pc_watch_arm_${pc}.log" pc_watch_arm target="0x$pc"; done
    raw "$RUN_DIR/prepare_pc_watch_dump.log" pc_watch_dump
}

analyze() {
    "$PYTHON_BIN" - "$RUN_DIR" "$START_EPOCH_NS" "$REQUIRED_NATIVE_PCS" "$OPTIONAL_NATIVE_PCS" "$EXCLUDED_PCS" <<'PY'
import json,pathlib,re,sys,time
run=pathlib.Path(sys.argv[1]); start=int(sys.argv[2]); required=['0X'+x for x in sys.argv[3].split()]; optional=['0X'+x for x in sys.argv[4].split()]; excluded=['0X'+x for x in sys.argv[5].split()]
def raw(name):
    text=(run/name).read_text(encoding='utf-8',errors='replace'); match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not match: raise SystemExit(f'JSON ausente: {name}')
    return json.loads(match.group(1))
def delta(a,b,key): return max(0,int(b.get(key,0) or 0)-int(a.get(key,0) or 0))
before_loader=raw('before_overlay_loader_status.log'); after_loader=raw('after_overlay_loader_status.log')
before_dirty=raw('before_dirty_ram_stats.log'); after_dirty=raw('after_dirty_ram_stats.log')
before_dispatch=raw('before_dispatch_stats.log'); after_dispatch=raw('after_dispatch_stats.log')
shadow=raw('after_overlay_shadow_dump.log').get('shadow',{}); watch=raw('after_pc_watch_dump.log')
seen={str(item.get('target','')).upper():item for item in watch.get('entries',[])}; targets={}; errors=[]; coverage=[]
for pc in required+optional+excluded:
    item=seen.get(pc,{}); native=int(item.get('native_hits',0) or 0); interp=int(item.get('interpreted_hits',0) or 0); hits=int(item.get('hits',0) or 0)
    targets[pc]={'hits':hits,'native_hits':native,'interpreted_hits':interp}
    if hits!=native+interp: errors.append(f'{pc}: contadores inconsistentes')
    if pc in required and native<=0: errors.append(f'{pc}: nenhum hit nativo')
    if pc in required+optional and interp: errors.append(f'{pc}: {interp} hit(s) interpretado(s)')
    if pc in excluded and native: errors.append(f'{pc}: excluido teve {native} hit(s) nativo(s)')
for pc in ('0X80046934','0X80047000'):
    if targets[pc]['interpreted_hits']<=0: errors.append(f'{pc}: rota interpretada excluida nao foi exercitada')
jump=['0X80046634','0X80046704','0X80046810','0X800468A0','0X800468CC','0X80046920']
if sum(targets[pc]['native_hits'] for pc in jump)<=0: coverage.append('nenhum destino da tabela local foi exercitado')
loader={k:delta(before_loader,after_loader,k) for k in ('dispatch_native','dispatch_interp_fallback','stale_blocked','invalidations','unregistered_funcs')}
guards={k:delta(before_dirty,after_dirty,k) for k in ('aborts','native_handoffs','text_native_blocked','text_diverged_pages','text_exact_mismatches')}
fatal={k:v for k,v in guards.items() if k!='native_handoffs'}; miss=delta(before_dispatch,after_dispatch,'miss_total')
if loader['dispatch_native']<=0: errors.append('dispatch_native nao cresceu')
if loader['unregistered_funcs'] or any(fatal.values()) or miss: errors.append('diagnostico de seguranca nao zerado')
if int(shadow.get('diff_mode',1)) or int(shadow.get('shadow_calls',0)) or int(shadow.get('in_shadow',0)) or int(shadow.get('native_exec',0))!=1: errors.append('estado shadow/native invalido')
before=json.loads((run/'before-live-gate.json').read_text()); after=json.loads((run/'after-live-gate.json').read_text())
if before.get('prefix_crc32')!=after.get('prefix_crc32') or before.get('external_table')!=after.get('external_table') or before.get('local_jump_table')!=after.get('local_jump_table'): errors.append('bytes vivos ou tabelas mudaram')
duration=max(0,(time.time_ns()-start)/1e9); clean=not errors
result={'track':'OVL-002H-DDARK-BOMB-SUPER-CUMULATIVE','duration_s':round(duration,3),'word_limit':252,'incremental_words':239,'prior_image_words':2563,'image_body_words':2802,'targets':targets,'loader_deltas':loader,'guard_deltas':guards,'dispatch_miss_delta':miss,'coverage_notes':coverage,'errors':errors,'technical_clean':clean}
(run/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
lines=['# OVL-002H - especial da bomba explosiva','',f'- Duracao: {duration:.3f} s','- Incremento: 239 palavras; limite: 252; corpo cumulativo: 2.802',f'- Dispatch nativo: +{loader["dispatch_native"]}',f'- Miss total: {miss}',f'- Status tecnico: {"CLEAN" if clean else "REVIEW"}','','| PC | Nativos | Interpretados |','|---|---:|---:|']
for pc in required+optional+excluded:
    item=targets[pc]; lines.append(f'| `{pc}` | {item["native_hits"]} | {item["interpreted_hits"]} |')
if coverage: lines += ['','## Cobertura nao bloqueante','']+[f'- {x}' for x in coverage]
if errors: lines += ['','## Bloqueios','']+[f'- {x}' for x in errors]
(run/'summary.md').write_text('\n'.join(lines)+'\n')
PY
}

prepare_phase() {
    [[ ! -f "$STATE_FILE" ]] || fail "Ja existe coleta OVL-002H ativa."
    make_run_dir
    raw "$RUN_DIR/prepare_native_block_clear.log" overlay_native_block clear=1
    raw "$RUN_DIR/prepare_overlay_diff_off.log" overlay_diff_off
    general_snapshot prepare; arm_watch
    printf 'track=OVL-002H-DDARK-BOMB-SUPER-CUMULATIVE\nruntime_dir=%s\nroute=D.Dark P1 x Ryu P2; cenario Ryu; especial da bomba explosiva\n' "$RUNTIME_DIR" >"$RUN_DIR/metadata.txt"
    write_state prepared
    printf '\nPREPARE concluido. Entre no Versus, aguarde 3-5 s neutros e execute BEFORE.\n'
}

before_phase() {
    read_state; [[ "$RUN_PHASE" == prepared ]] || fail "BEFORE exige fase prepared."
    general_snapshot before; live_snapshot before; verify_live before
    raw "$RUN_DIR/window_pc_watch_reset.log" pc_watch_reset
    START_EPOCH_NS="$("$PYTHON_BIN" -c 'import time; print(time.time_ns())')"; write_state before
    printf '\nBEFORE concluido. Faca somente o especial da bomba explosiva acertar Ryu uma vez de cada lado. Pare apos o segundo impacto e execute AFTER.\n'
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
print('Gate AFTER OVL-002H: closure nativa; 0x80046934 e 0x80047000 permaneceram interpretadas.')
PY
    )"; then
        mv "$STATE_FILE" "$RUN_DIR/review.state"; printf '%s\n' "$result_status" >&2
        fail "Coleta preservada em REVIEW. O proximo prepare usara outro sufixo."
    fi
    printf '%s\n' "$result_status"; mv "$STATE_FILE" "$RUN_DIR/completed.state"
    printf '\nAFTER concluido. Resumo: %s/summary.md\n' "$RUN_DIR"
}

main() {
    case "${1:-}" in retry) archive_review_phase; return ;; prepare|before|after) ;; *) usage; fail "Use prepare, before, after ou retry." ;; esac
    validate_common
    require_debug_server
    case "$1" in prepare) prepare_phase ;; before) before_phase ;; after) after_phase ;; esac
}

main "$@"
