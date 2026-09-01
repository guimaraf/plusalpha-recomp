#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly RAW_TCP="$REPO_ROOT/psxrecomp/tools/raw_tcp.py"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002b_test.toml"
readonly TARGET_FILE="$PROJECT_ROOT/seeds/ovl_002b_target_pcs.txt"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002b-current-runtime.state"
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.ovl-002b-test-active.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_CAPTURE_KEY=0x00020000:0xF943B63B
readonly EXPECTED_CACHE_REL=cache/SLUS-00548/gcc/win-x64/cg5_562d908f

PYTHON_BIN=
DEBUG_PORT=
RUNTIME_DIR=
RUNTIME_EXE=
CACHE_MANIFEST=
RUN_DIR=
RUN_PHASE=
START_EPOCH_NS=0

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, sempre com a mesma execucao OVL-002B aberta:

  bash tools/telemetry_before_after_ovl_002b.sh prepare
  bash tools/telemetry_before_after_ovl_002b.sh before
  bash tools/telemetry_before_after_ovl_002b.sh after

Rota:
  PREPARE: Mode Select.
  BEFORE : Versus, D.Dark P1 x Ryu P2, cenario Ryu; 3-5 s neutros.
  AFTER  : no mesmo round, depois de 5 bombas e 5 Killing Blades.

Alterne lado, acerto, erro e bloqueio. Se houver barra, inclua Death Trump e
Dark Shackle. Ryu deve permanecer sem comandos. O coletor nao gera, nao
compila, nao abre e nao fecha o jogo.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_runtime_state() {
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-002B ausente. Execute compile_ovl_002b_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"
    RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002b-test-runtime-*) ;; *) fail "Runtime OVL-002B invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" capture_key)" == "$EXPECTED_CAPTURE_KEY" ]] || fail "Chave OVL-002B divergente."
    [[ "$(state_value "$RUNTIME_STATE" target)" == 0x80092C2C ]] || fail "Alvo OVL-002B divergente."
    [[ "$(state_value "$RUNTIME_STATE" prior_root)" == 0x80093BB8 ]] || fail "Raiz OVL-002A divergente."
    [[ "$(state_value "$RUNTIME_STATE" prior_alias)" == 0x80093E4C ]] || fail "Alias OVL-002A divergente."
    [[ "$(state_value "$RUNTIME_STATE" incremental_words)" == 882 ]] || fail "Volume incremental divergente."
    [[ "$(state_value "$RUNTIME_STATE" image_body_words)" == 1108 ]] || fail "Volume cumulativo divergente."
    [[ -d "$RUNTIME_DIR" && -f "$RUNTIME_EXE" && -f "$CACHE_MANIFEST" ]] || fail "Runtime incompleto."
}

read_debug_port() {
    DEBUG_PORT="$(awk '
        /^[[:space:]]*\[runtime\][[:space:]]*$/ {ok=1; next}
        /^[[:space:]]*\[/ {ok=0}
        ok && /^[[:space:]]*debug_port[[:space:]]*=/ {sub(/^[^=]*=/,""); gsub(/[[:space:]]+/,""); print; exit}
    ' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida."
}

verify_cache_manifest() {
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" "$TARGET_FILE" "$EXPECTED_CACHE_REL" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); manifest=pathlib.Path(sys.argv[2]); targets_path=pathlib.Path(sys.argv[3])
expected_rel=pathlib.PurePosixPath(sys.argv[4]); data=json.loads(manifest.read_text(encoding='utf-8'))
if data.get('track')!='OVL-002B-DDARK-CUMULATIVE': raise SystemExit('manifesto nao pertence a OVL-002B')
if data.get('capture_keys')!=['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F','0x00020000:0xF943B63B']:
    raise SystemExit('chaves cumulativas divergiram')
if data.get('cache_relative')!=expected_rel.as_posix(): raise SystemExit('namespace de cache divergente')
if int(data.get('incremental_words',0))!=882 or int(data.get('prior_ovl002a_words',0))!=226 or int(data.get('image_body_words',0))!=1108:
    raise SystemExit('volumes do manifesto divergiram')
for item in data.get('files',[]):
    path=root/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']): raise SystemExit(f'cache ausente: {item["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']: raise SystemExit(f'cache alterado: {item["path"]}')
image=root/pathlib.Path(*expected_rel.parts)/'00020000_F943B63B.ranges'; entries=set()
for line in image.read_text(encoding='utf-8').splitlines():
    p=line.split()
    if p and p[0]=='F': entries.add(int(p[1],16)&0x1fffffff)
required={0x00092138,0x00092524,0x00092740,0x00092800,0x000929D4,0x00092C2C,0x00093BB8,0x00093E4C}
if required-entries: raise SystemExit('boundaries/alias ausentes do shard F943B63B')
if {0x00092F00,0x00047DE8}&entries: raise SystemExit('alvo excluido presente no shard F943B63B')
targets=[]
for line in targets_path.read_text(encoding='utf-8').splitlines():
    p=line.split('#',1)[0].split()
    if p: targets.append(int(p[1],16)&0x1fffffff)
if targets!=[0x00092C2C] or set(targets)-entries: raise SystemExit('watch target OVL-002B divergente')
PY
}

validate_common() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep mv seq; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python; read_runtime_state; read_debug_port
    for file in "$RAW_TCP" "$TEST_CONFIG" "$TARGET_FILE" "$RANGES_FILE"; do [[ -f "$file" ]] || fail "Arquivo ausente: $file"; done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel divergiu."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    verify_cache_manifest
}

raw() {
    local output="$1"; shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 || fail "Falha TCP: $*"
    grep -q '"ok":true' "$output" || fail "Resposta TCP invalida: $*"
    grep -q '^OK keys:' "$output" || fail "JSON truncado: $*"
}

make_run_dir() {
    local suffix candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-002b-telemetry-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi
    done
    fail "Nao ha pasta livre para a telemetria OVL-002B."
}

write_state() {
    umask 077
    printf 'run_dir=%s\nruntime_dir=%s\nphase=%s\nstart_epoch_ns=%s\n' \
        "$RUN_DIR" "$RUNTIME_DIR" "$1" "$START_EPOCH_NS" >"$STATE_FILE"
    RUN_PHASE="$1"
}

read_state() {
    [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta ativa; execute prepare."
    RUN_DIR="$(state_value "$STATE_FILE" run_dir)"; RUN_PHASE="$(state_value "$STATE_FILE" phase)"
    START_EPOCH_NS="$(state_value "$STATE_FILE" start_epoch_ns)"
    [[ "$(state_value "$STATE_FILE" runtime_dir)" == "$RUNTIME_DIR" ]] || fail "Runtime mudou durante a coleta."
    case "$RUN_DIR" in "$PROJECT_ROOT"/local/telemetry/ovl-002b-telemetry-*) ;; *) fail "Run invalido." ;; esac
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
    for pc in 80092138 80092524 80092740 80092800 800929D4 80092C2C 80093BB8 80093E4C; do
        raw "$RUN_DIR/${phase}_${pc}_words.log" mem_words addr="0x$pc" count=32
        raw "$RUN_DIR/${phase}_${pc}_candidate.log" overlay_candidates pc="0x$pc"
    done
}

arm_watch() {
    raw "$RUN_DIR/prepare_pc_watch_clear.log" pc_watch_clear
    raw "$RUN_DIR/prepare_pc_watch_arm_new.log" pc_watch_arm target=0x80092C2C
    raw "$RUN_DIR/prepare_pc_watch_arm_prior.log" pc_watch_arm target=0x80093E4C
    raw "$RUN_DIR/prepare_pc_watch_dump.log" pc_watch_dump
    "$PYTHON_BIN" - "$RUN_DIR/prepare_pc_watch_dump.log" <<'PY'
import json,pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace')
m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
if not m: raise SystemExit('pc_watch PREPARE sem JSON')
w=json.loads(m.group(1)); entries=w.get('entries',[])
targets={str(x.get('target','')).upper() for x in entries}
if not w.get('armed') or int(w.get('count',0))!=2 or len(entries)!=2 or targets!={'0X80092C2C','0X80093E4C'}:
    raise SystemExit('pc_watch nao armou exatamente o alvo novo e o alias preservado')
PY
}

verify_prepare() {
    "$PYTHON_BIN" - "$RUN_DIR/prepare_overlay_loader_status.log" "$RUN_DIR/prepare_overlay_shadow_dump.log" "$RUNTIME_DIR" <<'PY'
import json,pathlib,re,sys
def raw(path):
 t=pathlib.Path(path).read_text(encoding='utf-8',errors='replace'); m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',t,re.S)
 if not m: raise SystemExit('JSON bruto ausente')
 return json.loads(m.group(1))
l=raw(sys.argv[1]); s=raw(sys.argv[2]).get('shadow',{}); errors=[]
if int(l.get('active',0))!=1: errors.append('overlay cache inativo')
if pathlib.Path(l.get('cache_dir','')).resolve()!=(pathlib.Path(sys.argv[3])/'cache').resolve(): errors.append('cache_dir inesperado')
if int(l.get('lazy_manifests',0))<=0 and int(l.get('registered',0))<=0: errors.append('nenhum manifesto indexado')
for key in ('range_index_overflow','lazy_manifest_overflow'):
 if int(l.get(key,0)): errors.append(f'{key}={l[key]}')
if int(s.get('diff_mode',1)) or int(s.get('shadow_calls',0)) or int(s.get('in_shadow',0)) or int(s.get('native_exec',0))!=1:
 errors.append('estado shadow/native invalido')
if errors: raise SystemExit('ERRO: PREPARE: '+'; '.join(errors))
print('Gate PREPARE OVL-002B: cache cumulativo ativo, dois watches armados e shadow desligado.')
PY
}

verify_live() {
    local phase="$1"
    "$PYTHON_BIN" - "$RUN_DIR" "$phase" <<'PY'
import json,pathlib,re,struct,sys,zlib
run=pathlib.Path(sys.argv[1]); phase=sys.argv[2]
expected={'80092138':0x3FBB24A5,'80092524':0x8B3CD3B6,'80092740':0x5E2B8811,'80092800':0xD3698FD1,
          '800929D4':0x0776DC7A,'80092C2C':0x1B64D20F,'80093BB8':0xE9D28991,'80093E4C':0x12FF550F}
def raw(name):
 t=(run/name).read_text(encoding='utf-8',errors='replace'); m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',t,re.S)
 if not m: raise SystemExit(f'JSON ausente: {name}')
 return json.loads(m.group(1))
errors=[]; crcs={}; matches={}
for pc,wanted in expected.items():
 words=raw(f'{phase}_{pc}_words.log').get('words',[])
 if len(words)!=32: errors.append(f'0x{pc}: esperado 32 words, veio {len(words)}'); continue
 blob=b''.join(struct.pack('<I',int(x,16)) for x in words); crc=zlib.crc32(blob)&0xffffffff; crcs['0x'+pc]=f'0x{crc:08X}'
 if crc!=wanted: errors.append(f'0x{pc}: CRC vivo 0x{crc:08X}, esperado 0x{wanted:08X}')
 candidates=raw(f'{phase}_{pc}_candidate.log').get('candidates',[])
 matched=any(int(c.get('match',0))==1 and int(c.get('state',9))==0 and int(c.get('dll',-1))>=0 and int(c.get('device_touch',1))==0 for c in candidates)
 matches['0x'+pc]=matched
 if not matched: errors.append(f'0x{pc}: candidato GCC exato ausente/inativo')
if errors:
 print(f'ERRO: imagem OVL-002B incorreta no {phase.upper()}:',file=sys.stderr)
 for error in errors: print('  - '+error,file=sys.stderr)
 raise SystemExit(2)
(run/f'{phase}-live-gate.json').write_text(json.dumps({'phase':phase,'prefix_crc32':crcs,'candidate_match':matches},indent=2,sort_keys=True)+'\n',encoding='utf-8')
print(f'Gate {phase.upper()}: oito PCs cumulativos possuem CRC vivo e candidato GCC exatos.')
PY
}

snapshot_before() {
    general_snapshot before
    live_snapshot before
    raw "$RUN_DIR/before_pc_watch_dump.log" pc_watch_dump
}

snapshot_after() {
    general_snapshot after
    live_snapshot after
    raw "$RUN_DIR/after_pc_watch_dump.log" pc_watch_dump
}

analyze() {
    "$PYTHON_BIN" - "$RUN_DIR" "$START_EPOCH_NS" <<'PY'
import json,pathlib,re,sys,time
run=pathlib.Path(sys.argv[1]); start=int(sys.argv[2])
def raw(name):
 t=(run/name).read_text(encoding='utf-8',errors='replace'); m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',t,re.S)
 if not m: raise SystemExit(f'JSON ausente: {name}')
 return json.loads(m.group(1))
def delta(before,after,key): return max(0,int(after.get(key,0) or 0)-int(before.get(key,0) or 0))
bl=raw('before_overlay_loader_status.log'); al=raw('after_overlay_loader_status.log')
bd=raw('before_dirty_ram_stats.log'); ad=raw('after_dirty_ram_stats.log')
bdisp=raw('before_dispatch_stats.log'); adisp=raw('after_dispatch_stats.log')
bs=raw('before_overlay_shadow_dump.log').get('shadow',{}); ass=raw('after_overlay_shadow_dump.log').get('shadow',{})
ring=raw('after_overlay_native_ring.log').get('ring',{}); watch=raw('after_pc_watch_dump.log')
watched={str(x.get('target','')).upper():x for x in watch.get('entries',[])}
targets={}
errors=[]
for pc,role in (('0X80092C2C','novo'),('0X80093E4C','preservado')):
 w=watched.get(pc,{})
 hits=int(w.get('hits',0) or 0); native=int(w.get('native_hits',0) or 0); interp=int(w.get('interpreted_hits',0) or 0)
 targets[pc]={'role':role,'watch_hits':hits,'native_hits':native,'interpreted_hits':interp,
              'first_frame':int(w.get('first_frame',0) or 0),'last_frame':int(w.get('last_frame',0) or 0)}
 if native<=0: errors.append(f'{pc}: nenhum hit nativo acumulado')
 if interp: errors.append(f'{pc}: {interp} hit(s) interpretado(s)')
 if hits!=native+interp: errors.append(f'{pc}: contadores pc_watch inconsistentes')
loader={key:delta(bl,al,key) for key in ('dispatch_native','dispatch_interp_fallback','stale_blocked','invalidations','unregistered_funcs')}
guards={key:delta(bd,ad,key) for key in ('aborts','native_handoffs','text_native_blocked','text_diverged_pages','text_exact_mismatches')}
fatal_guards={key:value for key,value in guards.items() if key!='native_handoffs'}; miss=delta(bdisp,adisp,'miss_total')
if loader['dispatch_native']<=0: errors.append('dispatch_native nao cresceu')
if loader['unregistered_funcs']: errors.append('funcoes nativas desregistradas durante a janela')
if any(fatal_guards.values()): errors.append('guard dirty-RAM fatal nao zerado')
if miss: errors.append('miss_total cresceu')
if int(ring.get('in_progress','0'),16)!=0 or any(int(x.get('returned',0))!=1 for x in ring.get('recent',[])):
 errors.append('chamada nativa sem retorno')
if int(ass.get('diff_mode',1)) or int(ass.get('shadow_calls',0)) or int(ass.get('in_shadow',0)) or int(ass.get('native_exec',0))!=1:
 errors.append('estado shadow/native invalido')
for key in ('divergences','skipped_device','escapes','escapes_native'):
 if int(ass.get(key,0)): errors.append(f'shadow {key}={ass[key]}')
before_live=json.loads((run/'before-live-gate.json').read_text(encoding='utf-8'))
after_live=json.loads((run/'after-live-gate.json').read_text(encoding='utf-8'))
if before_live.get('prefix_crc32')!=after_live.get('prefix_crc32'): errors.append('bytes vivos mudaram durante a janela')
if not all(after_live.get('candidate_match',{}).values()): errors.append('candidato exato perdido no AFTER')
duration=max(0,(time.time_ns()-start)/1e9); clean=not errors
result={'track':'OVL-002B-DDARK-CUMULATIVE','capture_key':'0x00020000:0xF943B63B','duration_s':round(duration,3),
 'incremental_words':882,'prior_ovl002a_words':226,'image_body_words':1108,'cop2_incremental':71,'cop2_total_image':80,
 'targets':targets,'loader_deltas':loader,'loader_policy':{'stale_blocked':'informativo fora do alvo','invalidations':'informativo fora do alvo','unregistered_funcs':'fatal'},
 'guard_deltas':guards,'dispatch_miss_delta':miss,'live_before':before_live,'live_after':after_live,
 'shadow_before':bs,'shadow_after':ass,'errors':errors,'technical_clean':clean}
(run/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
lines=['# OVL-002B - D.Dark F943B63B','',f'- Duracao: {duration:.3f} s','- Incremento novo: 882 palavras em seis roots',
 '- OVL-002A preservada: 226 palavras; raiz 0x80093BB8; alias 0x80093E4C','- Corpo cumulativo desta imagem: 1.108 palavras',
 '- Risco especial: 71 COP2 novas; 80 COP2 cumulativas',f'- Delta dispatch nativo: {loader["dispatch_native"]}',
 f'- Delta fallback geral (informativo): {loader["dispatch_interp_fallback"]}',f'- Guards dirty-RAM fatais: {fatal_guards}',
 f'- Stale/invalidation gerais (informativos): {loader["stale_blocked"]}/{loader["invalidations"]}',
 f'- Funcoes desregistradas: {loader["unregistered_funcs"]}',f'- native_handoffs: {guards["native_handoffs"]} (diagnostico)',
 f'- Delta miss_total: {miss}',f'- Status tecnico: {"CLEAN" if clean else "REVIEW"}','','## Gates dinamicos','',
 '| PC | Papel | Hits nativos | Hits interpretados |','|---|---|---:|---:|']
for pc in ('0X80092C2C','0X80093E4C'):
 t=targets[pc]; lines.append(f'| `{pc}` | {t["role"]} | {t["native_hits"]} | {t["interpreted_hits"]} |')
if errors: lines += ['','## Bloqueios','']+[f'- {error}' for error in errors]
lines += ['','A cobertura estatica S1 permanece 56,9469%. As 882 palavras OVL-002B nao recebem credito antes da aprovacao manual.','']
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

prepare_phase() {
    if [[ -f "$STATE_FILE" ]]; then
        local old_run old_phase
        old_run="$(state_value "$STATE_FILE" run_dir)"; old_phase="$(state_value "$STATE_FILE" phase)"
        case "$old_run" in "$PROJECT_ROOT"/local/telemetry/ovl-002b-telemetry-*) ;; *) fail "Estado ativo anterior invalido." ;; esac
        [[ "$old_phase" == before && -f "$old_run/result.json" ]] || fail "Ja existe coleta OVL-002B ativa."
        "$PYTHON_BIN" - "$old_run/result.json" <<'PY'
import json,pathlib,sys
r=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
if r.get('technical_clean') is not False: raise SystemExit('coleta anterior nao esta em REVIEW')
PY
        mv "$STATE_FILE" "$old_run/review.state"
        printf 'Coleta REVIEW anterior preservada em %s.\n' "$old_run"
    fi
    make_run_dir
    raw "$RUN_DIR/prepare_native_block_clear.log" overlay_native_block clear=1
    raw "$RUN_DIR/prepare_overlay_diff_off.log" overlay_diff_off
    general_snapshot prepare
    arm_watch
    verify_prepare
    {
        printf 'run_id=%s\ntrack=OVL-002B-DDARK-CUMULATIVE\n' "$(basename "$RUN_DIR")"
        printf 'runtime_dir=%s\ncapture_key=%s\n' "$RUNTIME_DIR" "$EXPECTED_CAPTURE_KEY"
        printf 'route=D.Dark P1 x Ryu P2; cenario Ryu; Ryu sem comandos\n'
        printf 'incremental_words=882\nprior_ovl002a_words=226\nimage_body_words=1108\n'
        printf 'new_target=0x80092C2C\nprior_alias=0x80093E4C\ncop2_incremental=71\ncop2_total_image=80\n'
        printf 'prepared_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$RUN_DIR/metadata.txt"
    write_state prepared
    printf '\nPREPARE concluido. Entre em D.Dark P1 x Ryu P2, espere 3-5 s neutro e execute BEFORE.\n'
}

before_phase() {
    read_state; [[ "$RUN_PHASE" == prepared ]] || fail "Fase atual: $RUN_PHASE; BEFORE exige prepared."
    note "Validando as oito entradas cumulativas da imagem F943B63B"
    snapshot_before
    verify_live before
    raw "$RUN_DIR/window_pc_watch_reset.log" pc_watch_reset
    raw "$RUN_DIR/window_pc_watch_dump.log" pc_watch_dump
    START_EPOCH_NS="$("$PYTHON_BIN" -c 'import time; print(time.time_ns())')"
    printf 'before_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$RUN_DIR/metadata.txt"
    write_state before
    printf '\nBEFORE concluido. Execute com D.Dark 5 bombas e 5 Killing Blades.\n'
    printf 'Alterne lados, acerto, erro e bloqueio; inclua Death Trump/Dark Shackle se houver barra.\n'
    printf 'Ryu permanece sem comandos. Execute AFTER ainda neste round.\n'
}

after_phase() {
    read_state; [[ "$RUN_PHASE" == before ]] || fail "Fase atual: $RUN_PHASE; AFTER exige before."
    note "Coletando o alvo novo OVL-002B e o alias preservado OVL-002A"
    raw "$RUN_DIR/after_pc_watch_stop.log" pc_watch_stop
    snapshot_after
    verify_live after
    raw "$RUN_DIR/after_overlay_shadow_detail.log" overlay_shadow_detail
    raw "$RUN_DIR/after_overlay_diff_off.log" overlay_diff_off
    analyze
    "$PYTHON_BIN" - "$RUN_DIR/result.json" <<'PY'
import json,pathlib,sys
r=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
if not r.get('technical_clean'): raise SystemExit('ERRO: AFTER em REVIEW: '+'; '.join(r.get('errors',[])))
print('Gate AFTER OVL-002B: alvo novo e alias anterior nativos, CRCs exatos e zero fallback nos dois PCs.')
PY
    printf 'after_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$RUN_DIR/metadata.txt"
    mv "$STATE_FILE" "$RUN_DIR/completed.state"
    printf '\nAFTER concluido. Resumo: %s/summary.md\n' "$RUN_DIR"
}

main() {
    local phase="${1:-}"
    case "$phase" in prepare|before|after) ;; *) usage; fail "Use prepare, before ou after." ;; esac
    validate_common
    case "$phase" in prepare) prepare_phase ;; before) before_phase ;; after) after_phase ;; esac
}

main "$@"
