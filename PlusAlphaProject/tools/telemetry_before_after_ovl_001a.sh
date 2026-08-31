#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly RAW_TCP="$REPO_ROOT/psxrecomp/tools/raw_tcp.py"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_001a_test.toml"
readonly TARGET_FILE="$PROJECT_ROOT/seeds/ovl_001a_target_pcs.txt"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-001a-current-runtime.state"
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.ovl-001a-test-active.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_CAPTURE_KEY=0x00020000:0xAC1FF1A4
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

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, sempre com a mesma execucao OVL-001A aberta:

  bash tools/telemetry_before_after_ovl_001a.sh prepare
  bash tools/telemetry_before_after_ovl_001a.sh before
  bash tools/telemetry_before_after_ovl_001a.sh after

Rota:
  PREPARE: Mode Select, antes de escolher os personagens.
  BEFORE : Ryu x Ken, cenario Ken, gameplay controlavel; aguarde 3-5 s neutro.
  AFTER  : apos 30 s de movimento e golpes somente do Ryu, antes do fim do round.

Ken fica sem comandos, mas pode receber golpes e reagir. O BEFORE so avanca
quando os quatro targets possuem candidato GCC exato e execucao nativa
comprovada. O coletor nao compila, nao abre e nao fecha o jogo.
EOF
}

select_python() {
    if command -v python >/dev/null; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao foi encontrado no UCRT64."
    fi
}

state_value() {
    local file="$1" key="$2"
    awk -F= -v wanted="$key" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$file"
}

read_runtime_state() {
    [[ -f "$RUNTIME_STATE" ]] ||
        fail "Runtime OVL-001A nao compilado. Execute compile_ovl_001a_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"
    RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    local capture_key
    capture_key="$(state_value "$RUNTIME_STATE" capture_key)"
    case "$RUNTIME_DIR" in
        "$PROJECT_ROOT"/local/overlay/ovl-001a-test-runtime-*) ;;
        *) fail "Diretorio do runtime OVL-001A e invalido." ;;
    esac
    [[ "$capture_key" == "$EXPECTED_CAPTURE_KEY" ]] || fail "Estado aponta para outra captura."
    [[ -d "$RUNTIME_DIR" && -f "$RUNTIME_EXE" && -f "$CACHE_MANIFEST" ]] ||
        fail "Runtime OVL-001A incompleto."
}

read_debug_port() {
    DEBUG_PORT="$(awk '
        /^[[:space:]]*\[runtime\][[:space:]]*$/ { ok=1; next }
        /^[[:space:]]*\[/ { ok=0 }
        ok && /^[[:space:]]*debug_port[[:space:]]*=/ {
            sub(/^[^=]*=/, ""); gsub(/[[:space:]]+/, ""); print; exit
        }
    ' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida."
}

verify_cache_manifest() {
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" "$TARGET_FILE" "$EXPECTED_CACHE_REL" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); manifest_path=pathlib.Path(sys.argv[2])
target_path=pathlib.Path(sys.argv[3]); expected_rel=pathlib.PurePosixPath(sys.argv[4])
data=json.loads(manifest_path.read_text(encoding='utf-8'))
if data.get('track')!='OVL-001A' or data.get('capture_key')!='0x00020000:0xAC1FF1A4':
    raise SystemExit('manifesto nao pertence a OVL-001A/AC1FF1A4')
if data.get('cache_relative')!=expected_rel.as_posix():
    raise SystemExit('namespace de cache divergente')
expected={row['path']:(row['sha256'],int(row['size'])) for row in data.get('files',[])}
cache_dir=root/pathlib.Path(*expected_rel.parts)
actual_files=sorted(list(cache_dir.glob('*.dll'))+list(cache_dir.glob('*.ranges')))
actual={p.relative_to(root).as_posix():
        (hashlib.sha256(p.read_bytes()).hexdigest().upper(),p.stat().st_size)
        for p in actual_files}
if not expected or actual!=expected:
    raise SystemExit('inventario/hashes do cache mudaram depois da compilacao')
entries=set()
for ranges in cache_dir.glob('*.ranges'):
    for line in ranges.read_text(encoding='utf-8').splitlines():
        parts=line.split()
        if parts and parts[0]=='F': entries.add(int(parts[1],16)&0x1fffffff)
targets=[]
for line in target_path.read_text(encoding='utf-8').splitlines():
    parts=line.split('#',1)[0].split()
    if parts: targets.append(int(parts[1],16)&0x1fffffff)
if len(targets)!=4 or set(targets)-entries:
    raise SystemExit('cache nao oferece entradas nativas para os 4 targets')
PY
}

validate_common() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep mv seq cygpath; do
        command -v "$tool" >/dev/null || fail "$tool nao encontrado no UCRT64."
    done
    select_python
    read_runtime_state
    read_debug_port
    [[ -f "$RAW_TCP" && -f "$TARGET_FILE" && -f "$RANGES_FILE" ]] ||
        fail "Ferramenta, targets ou ranges ausentes."
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] ||
        fail "Executavel isolado diverge da build validada."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] ||
        fail "Ranges divergem do checkpoint S1-261."
    verify_cache_manifest
}

raw() {
    local output="$1"; shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 ||
        fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" || fail "Resposta TCP invalida: $*"
    grep -q '^OK keys:' "$output" || fail "Resposta TCP incompleta ou JSON truncado: $*"
}

json_from_raw() {
    "$PYTHON_BIN" - "$1" "$2" <<'PY'
import json,pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace')
match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
if not match: raise SystemExit(2)
value=json.loads(match.group(1)).get(sys.argv[2])
if isinstance(value,bool): print(int(value))
elif value is not None: print(value)
PY
}

make_run_dir() {
    local suffix candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-001a-telemetry-$suffix"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"; RUN_DIR="$candidate"; return
        fi
    done
    fail "Nao ha run livre entre ovl-001a-telemetry-01 e 99."
}

write_state() {
    umask 077
    {
        printf 'run_dir=%s\n' "$RUN_DIR"
        printf 'runtime_dir=%s\n' "$RUNTIME_DIR"
        printf 'phase=%s\n' "$1"
        printf 'start_epoch_ns=%s\n' "$START_EPOCH_NS"
    } >"$STATE_FILE"
    RUN_PHASE="$1"
}

read_state() {
    [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta OVL-001A ativa. Execute prepare."
    RUN_DIR="$(state_value "$STATE_FILE" run_dir)"
    local saved_runtime
    saved_runtime="$(state_value "$STATE_FILE" runtime_dir)"
    RUN_PHASE="$(state_value "$STATE_FILE" phase)"
    START_EPOCH_NS="$(state_value "$STATE_FILE" start_epoch_ns)"
    [[ "$saved_runtime" == "$RUNTIME_DIR" ]] || fail "O runtime mudou durante a coleta."
    case "$RUN_DIR" in
        "$PROJECT_ROOT"/local/telemetry/ovl-001a-telemetry-*) ;;
        *) fail "Estado OVL-001A aponta para run invalido." ;;
    esac
    [[ -d "$RUN_DIR" && "$START_EPOCH_NS" =~ ^[0-9]+$ ]] || fail "Estado incompleto."
}

snapshot() {
    local phase="$1" pc label
    raw "$RUN_DIR/${phase}_overlay_loader_status.log" overlay_loader_status
    raw "$RUN_DIR/${phase}_overlay_interp_hot.log" overlay_interp_hot sort=insns min_entries=1 offset=0 limit=256
    raw "$RUN_DIR/${phase}_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/${phase}_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/${phase}_overlay_shadow_dump.log" overlay_shadow_dump
    raw "$RUN_DIR/${phase}_overlay_native_ring.log" overlay_native_ring
    while read -r _ pc label; do
        [[ -n "${pc:-}" ]] || continue
        raw "$RUN_DIR/${phase}_candidate_${label}.log" overlay_candidates pc="$pc"
    done < <(grep -E '^[[:space:]]*target[[:space:]]+' "$TARGET_FILE")
}

verify_prepare() {
    "$PYTHON_BIN" - "$RUN_DIR/prepare_overlay_loader_status.log" \
        "$RUNTIME_DIR" "$RUN_DIR/prepare_overlay_shadow_dump.log" <<'PY'
import json,pathlib,re,sys
def raw_json(path):
    text=pathlib.Path(path).read_text(encoding='utf-8',errors='replace')
    m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not m: raise SystemExit(f'ERRO: JSON bruto ausente em {path}')
    return json.loads(m.group(1))
s=raw_json(sys.argv[1]); expected=(pathlib.Path(sys.argv[2])/'cache').resolve()
shadow=raw_json(sys.argv[3]).get('shadow',{})
actual=pathlib.Path(s.get('cache_dir','')).resolve()
errors=[]
if int(s.get('active',0))!=1: errors.append('overlay cache inativo')
if actual!=expected: errors.append(f'cache_dir inesperado: {actual}')
if int(s.get('lazy_manifests',0))<=0 and int(s.get('registered',0))<=0:
    errors.append('nenhum manifesto do shard foi indexado')
for key in ('range_index_overflow','lazy_manifest_overflow'):
    if int(s.get(key,0)): errors.append(f'{key}={s[key]}')
if int(shadow.get('diff_mode',1))!=0: errors.append('shadow-diff ainda ligado')
if int(shadow.get('in_shadow',0))!=0: errors.append('runtime preso dentro do shadow')
if int(shadow.get('native_exec',0))!=1: errors.append('execucao nativa desabilitada')
if int(shadow.get('shadow_calls',0))!=0: errors.append('runtime reutilizado apos shadow-diff')
if errors: raise SystemExit('ERRO: gate PREPARE: '+'; '.join(errors))
print('Gate PREPARE OVL-001A: cache exato, native habilitado e shadow desligado.')
PY
}

verify_before() {
    "$PYTHON_BIN" - "$RUN_DIR" "$TARGET_FILE" <<'PY'
import json,pathlib,re,sys
run=pathlib.Path(sys.argv[1]); target_path=pathlib.Path(sys.argv[2])
def raw_json(path):
    text=path.read_text(encoding='utf-8',errors='replace')
    m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not m: raise SystemExit(f'JSON bruto ausente em {path.name}')
    return json.loads(m.group(1))
errors=[]; rows=[]
for line in target_path.read_text(encoding='utf-8').splitlines():
    parts=line.split('#',1)[0].split()
    if not parts: continue
    pc,label=parts[1],parts[2]
    candidates=raw_json(run/f'before_candidate_{label}.log').get('candidates',[])
    matched=[c for c in candidates if int(c.get('match',0))==1 and int(c.get('state',9))==0]
    if not matched:
        errors.append(f'{pc}: candidato exato/VALID ausente'); continue
    best=max(matched,key=lambda c:int(c.get('diff_passes',0)))
    row={'pc':pc,'label':label,'diff_passes':int(best.get('diff_passes',0)),
         'device_touch':int(best.get('device_touch',0)),'dll':int(best.get('dll',-99))}
    rows.append(row)
    if row['dll']<0: errors.append(f'{pc}: candidato nao veio de DLL GCC')
    if row['device_touch']!=0: errors.append(f'{pc}: marcado como device_touch')
loader=raw_json(run/'before_overlay_loader_status.log')
shadow=raw_json(run/'before_overlay_shadow_dump.log').get('shadow',{})
ring=raw_json(run/'before_overlay_native_ring.log').get('ring',{})
ring_pcs={int(e.get('addr','0'),16)&0x1fffffff for e in ring.get('recent',[])}
for row in rows:
    pc=int(row['pc'],16)&0x1fffffff
    row['native_ring_seen']=pc in ring_pcs
    if pc not in ring_pcs: errors.append(f'{row["pc"]}: ausente do ring nativo')
if int(loader.get('registered',0))<4: errors.append('menos de 4 funcoes registradas')
if int(loader.get('dispatch_native',0))<=0: errors.append('dispatch_native ainda zerado')
if int(shadow.get('diff_mode',1))!=0: errors.append('shadow-diff ligado')
if int(shadow.get('shadow_calls',0))!=0: errors.append('shadow foi executado nesta sessao')
if int(shadow.get('in_shadow',0)): errors.append('runtime preso dentro do shadow')
if int(shadow.get('native_exec',0))!=1: errors.append('execucao nativa desabilitada')
if errors:
    print('ERRO: OVL-001A ainda nao esta pronta para BEFORE:',file=sys.stderr)
    for error in errors: print('  - '+error,file=sys.stderr)
    print('Se apenas o ring estiver incompleto, aguarde 3-5 segundos e repita BEFORE.',file=sys.stderr)
    raise SystemExit(2)
(run/'before-target-gate.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
print('Gate BEFORE OVL-001A: 4/4 candidatos GCC no ring nativo, sem shadow-diff.')
PY
}

recover_stuck_shadow_state() {
    [[ -f "$STATE_FILE" ]] || return 0
    local old_run old_phase shadow_log ring_log
    old_run="$(state_value "$STATE_FILE" run_dir)"
    old_phase="$(state_value "$STATE_FILE" phase)"
    case "$old_run" in
        "$PROJECT_ROOT"/local/telemetry/ovl-001a-telemetry-*) ;;
        *) fail "Estado anterior aponta para run invalido; preserve-o para analise." ;;
    esac
    shadow_log="$old_run/before_overlay_shadow_dump.log"
    ring_log="$old_run/before_overlay_native_ring.log"
    [[ "$old_phase" == prepared && -f "$shadow_log" ]] ||
        fail "Ja existe uma coleta OVL-001A ativa na fase $old_phase."
    if [[ -f "$ring_log" ]] && grep -q 'KeyboardInterrupt' "$ring_log"; then
        mv "$STATE_FILE" "$old_run/rejected-native-ring-client-stall.state"
        printf 'Estado do cliente TCP interrompido anterior arquivado em:\n'
        printf '  %s/rejected-native-ring-client-stall.state\n' "$old_run"
        return 0
    fi
    "$PYTHON_BIN" - "$shadow_log" <<'PY'
import json,pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace')
m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
if not m: raise SystemExit(2)
s=json.loads(m.group(1)).get('shadow',{})
if not (int(s.get('in_shadow',0))==1 and int(s.get('native_exec',1))==0):
    raise SystemExit(3)
PY
    local rc=$?
    [[ "$rc" == 0 ]] || fail "A coleta ativa nao corresponde ao incidente shadow-stuck conhecido."
    mv "$STATE_FILE" "$old_run/rejected-shadow-stuck.state"
    printf 'Estado shadow-stuck anterior arquivado em:\n  %s/rejected-shadow-stuck.state\n' "$old_run"
}

prepare_phase() {
    recover_stuck_shadow_state
    [[ ! -f "$STATE_FILE" ]] || fail "Ja existe uma coleta OVL-001A ativa."
    make_run_dir
    raw "$RUN_DIR/prepare_native_block_clear.log" overlay_native_block clear=1
    raw "$RUN_DIR/prepare_overlay_diff_off.log" overlay_diff_off
    snapshot prepare
    verify_prepare
    {
        printf 'run_id=%s\ntrack=OVL-001A\nbaseline=S1-261\n' "$(basename "$RUN_DIR")"
        printf 'runtime_dir=%s\nruntime_exe_sha256=%s\n' "$RUNTIME_DIR" "$EXPECTED_EXE_SHA"
        printf 'ranges_sha256=%s\ncapture_key=%s\n' "$EXPECTED_RANGES_SHA" "$EXPECTED_CAPTURE_KEY"
        printf 'route=Ryu x Ken; cenario Ken; somente Ryu executa comandos\n'
        printf 'policy=isolated GCC shard; no autocompile; shadow diff disabled\n'
        printf 'prepared_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$RUN_DIR/metadata.txt"
    write_state prepared
    printf '\nPREPARE concluido; cache nativo ativo e shadow-diff desligado.\n'
    printf 'Entre em Ryu x Ken, aguarde 3-5 segundos neutro no gameplay e execute BEFORE.\n'
}

before_phase() {
    read_state
    [[ "$RUN_PHASE" == prepared ]] || fail "Fase atual: $RUN_PHASE; BEFORE exige prepared."
    if [[ -f "$RUN_DIR/before_overlay_loader_status.log" && \
          ! -f "$RUN_DIR/before-target-gate.json" ]]; then
        printf 'Tentativa BEFORE parcial detectada; os snapshots serao substituidos com seguranca.\n'
    fi
    note "Validando a variante OVL-001A no gameplay neutro"
    snapshot before
    verify_before
    START_EPOCH_NS="$("$PYTHON_BIN" -c 'import time; print(time.time_ns())')"
    printf 'before_utc=%s\nbefore_epoch_ns=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$START_EPOCH_NS" >>"$RUN_DIR/metadata.txt"
    write_state before
    printf '\nBEFORE concluido; a janela formal esta ativa.\n'
    printf 'Por 30 segundos, mova Ryu e execute normais, especial, defesa/dano e knockdown.\n'
    printf 'Nao controle Ken. Execute AFTER antes do fim do round.\n'
}

analyze() {
    "$PYTHON_BIN" - "$RUN_DIR" "$TARGET_FILE" "$START_EPOCH_NS" <<'PY'
import json,pathlib,re,sys,time
run=pathlib.Path(sys.argv[1]); target_path=pathlib.Path(sys.argv[2]); start=int(sys.argv[3])
def raw_json(name):
    text=(run/name).read_text(encoding='utf-8',errors='replace')
    m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not m: raise SystemExit(f'JSON bruto ausente em {name}')
    return json.loads(m.group(1))
targets=[]
for line in target_path.read_text(encoding='utf-8').splitlines():
    parts=line.split('#',1)[0].split()
    if parts: targets.append((int(parts[1],16)&0x1fffffff,parts[2]))
before_loader=raw_json('before_overlay_loader_status.log')
after_loader=raw_json('after_overlay_loader_status.log')
before_dirty=raw_json('before_dirty_ram_stats.log'); after_dirty=raw_json('after_dirty_ram_stats.log')
before_dispatch=raw_json('before_dispatch_stats.log'); after_dispatch=raw_json('after_dispatch_stats.log')
before_shadow=raw_json('before_overlay_shadow_dump.log').get('shadow',{})
after_shadow=raw_json('after_overlay_shadow_dump.log').get('shadow',{})
after_ring=raw_json('after_overlay_native_ring.log').get('ring',{})
def hot(name):
    return {int(e.get('phys','0'),16):e for e in raw_json(name).get('entries',[])}
bh=hot('before_overlay_interp_hot.log'); ah=hot('after_overlay_interp_hot.log')
ring_pcs={int(e.get('addr','0'),16)&0x1fffffff for e in after_ring.get('recent',[])}
target_rows=[]
for pc,label in targets:
    b=bh.get(pc,{}); a=ah.get(pc,{})
    delta_entries=max(0,int(a.get('entry_hits',0))-int(b.get('entry_hits',0)))
    delta_insns=max(0,int(a.get('insns',0))-int(b.get('insns',0)))
    candidates=raw_json(f'after_candidate_{label}.log').get('candidates',[])
    matched=[c for c in candidates if int(c.get('match',0))==1 and int(c.get('state',9))==0]
    best=max(matched,key=lambda c:int(c.get('diff_passes',0))) if matched else {}
    target_rows.append({'pc':f'0x{pc|0x80000000:08X}','label':label,
        'native_ring_seen':pc in ring_pcs,'interp_entry_delta':delta_entries,
        'interp_insn_delta':delta_insns,'candidate_match':bool(matched),
        'diff_passes':int(best.get('diff_passes',0)) if best else 0,
        'device_touch':int(best.get('device_touch',0)) if best else -1})
def delta(a,b,key): return max(0,int(b.get(key,0) or 0)-int(a.get(key,0) or 0))
guard_names=('aborts','native_handoffs','text_native_blocked','text_diverged_pages','text_exact_mismatches')
guard_deltas={k:delta(before_dirty,after_dirty,k) for k in guard_names}
loader_deltas={k:delta(before_loader,after_loader,k) for k in
               ('dispatch_native','dispatch_interp_fallback','stale_blocked','invalidations','unregistered_funcs')}
dispatch_miss_delta=delta(before_dispatch,after_dispatch,'miss_total')
shadow_fields=('divergences','skipped_device','escapes','escapes_native')
shadow_values={k:int(after_shadow.get(k,0) or 0) for k in shadow_fields}
errors=[]
if loader_deltas['dispatch_native']<=0: errors.append('dispatch_native nao cresceu')
if loader_deltas['stale_blocked'] or loader_deltas['invalidations'] or loader_deltas['unregistered_funcs']:
    errors.append('cache invalidou, ficou stale ou desregistrou funcoes')
if dispatch_miss_delta: errors.append('miss_total cresceu')
if any(guard_deltas.values()): errors.append('gate dirty-RAM nao zerado')
if any(shadow_values.values()): errors.append('shadow diff registrou divergencia/MMIO/escape')
if int(after_shadow.get('diff_mode',1))!=0: errors.append('shadow-diff foi ligado')
if int(after_shadow.get('shadow_calls',0))!=0: errors.append('shadow foi executado')
if int(after_shadow.get('in_shadow',0)): errors.append('runtime preso dentro do shadow')
if int(after_shadow.get('native_exec',0))!=1: errors.append('execucao nativa desabilitada')
for row in target_rows:
    if not row['candidate_match']: errors.append(f'{row["pc"]}: candidato exato ausente')
    if row['device_touch']!=0: errors.append(f'{row["pc"]}: device_touch')
    if not row['native_ring_seen']: errors.append(f'{row["pc"]}: nao apareceu no ring nativo')
    if row['interp_entry_delta'] or row['interp_insn_delta']:
        errors.append(f'{row["pc"]}: fallback interpretado durante a janela')
duration=max(0,(time.time_ns()-start)/1e9)
clean=not errors
result={'track':'OVL-001A','capture_key':'0x00020000:0xAC1FF1A4','duration_s':round(duration,3),
        'targets':target_rows,'loader_deltas':loader_deltas,'dispatch_miss_delta':dispatch_miss_delta,
        'guard_deltas':guard_deltas,'shadow_before':before_shadow,'shadow_after':after_shadow,
        'errors':errors,'technical_clean':clean}
(run/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
lines=['# OVL-001A - shard AC1FF1A4','',f'- Duracao: {duration:.3f} s',
       f'- Delta dispatch nativo: {loader_deltas["dispatch_native"]}',
       f'- Delta fallback geral de overlays: {loader_deltas["dispatch_interp_fallback"]}',
       f'- Shadow-diff habilitado: {int(after_shadow.get("diff_mode",0))}',
       f'- Shadow calls: {int(after_shadow.get("shadow_calls",0))}',
       f'- Gates dirty-RAM: {guard_deltas}',f'- Delta miss_total: {dispatch_miss_delta}',
       f'- Status tecnico: {"CLEAN" if clean else "REVIEW"}','','## Quatro targets','',
       '| PC | Ring nativo | Delta entradas interp. | Delta instrucoes interp. | CRC exato |',
       '|---|---:|---:|---:|---:|']
for row in target_rows:
    lines.append(f'| `{row["pc"]}` | {"sim" if row["native_ring_seen"] else "nao"} | '
                 f'{row["interp_entry_delta"]} | {row["interp_insn_delta"]} | '
                 f'{"sim" if row["candidate_match"] else "nao"} |')
if errors:
    lines += ['','## Bloqueios','']+[f'- {e}' for e in errors]
lines += ['','A porcentagem estatica S1 permanece 56,9469%; este lote usa metrica separada de overlay.','']
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

verify_after_result() {
    "$PYTHON_BIN" - "$RUN_DIR/result.json" <<'PY'
import json,pathlib,sys
r=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
if not r.get('technical_clean'):
    raise SystemExit('ERRO: AFTER OVL-001A em REVIEW: '+'; '.join(r.get('errors',[])))
if len(r.get('targets',[]))!=4:
    raise SystemExit('ERRO: resultado nao possui os quatro targets')
print('Gate AFTER OVL-001A: 4/4 nativos, CRC exato e zero fallback nos alvos.')
PY
}

after_phase() {
    read_state
    [[ "$RUN_PHASE" == before ]] || fail "Fase atual: $RUN_PHASE; AFTER exige before."
    note "Encerrando a janela OVL-001A"
    snapshot after
    raw "$RUN_DIR/after_overlay_shadow_detail.log" overlay_shadow_detail
    raw "$RUN_DIR/after_overlay_diff_off.log" overlay_diff_off
    analyze
    verify_after_result
    printf 'after_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$RUN_DIR/metadata.txt"
    mv "$STATE_FILE" "$RUN_DIR/completed.state"
    printf '\nAFTER concluido. O jogo continua aberto e o shadow-diff permaneceu desligado.\n'
    printf 'Resumo: %s/summary.md\n' "$RUN_DIR"
}

main() {
    local phase="${1:-}"
    case "$phase" in prepare|before|after) ;; *) usage; fail "Use prepare, before ou after." ;; esac
    validate_common
    case "$phase" in
        prepare) prepare_phase ;;
        before) before_phase ;;
        after) after_phase ;;
    esac
}

main "$@"
