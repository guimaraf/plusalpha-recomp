#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly RAW_TCP="$REPO_ROOT/psxrecomp/tools/raw_tcp.py"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_001b_test.toml"
readonly A_TARGET_FILE="$PROJECT_ROOT/seeds/ovl_001a_target_pcs.txt"
readonly B_TARGET_FILE="$PROJECT_ROOT/seeds/ovl_001b_target_pcs.txt"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-001b-current-runtime.state"
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.ovl-001b-test-active.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_A_KEY=0x00020000:0xAC1FF1A4
readonly EXPECTED_B_KEY=0x00020000:0x94E6122F
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
Uso no MSYS2 UCRT64, sempre com a mesma execucao OVL-001B aberta:

  bash tools/telemetry_before_after_ovl_001b.sh prepare
  bash tools/telemetry_before_after_ovl_001b.sh before
  bash tools/telemetry_before_after_ovl_001b.sh after

Rota curta:
  PREPARE: Mode Select, antes de escolher os personagens.
  BEFORE : Ryu x Ken, cenario Ken, 3-5 s de gameplay neutro.
  AFTER  : apos 30-45 s de movimento e golpes somente do Ryu, antes do round acabar.

O BEFORE valida a variante A ja aprovada e zera a janela pc_watch. O AFTER
exige hits nativos acumulados nos quatro gates B-safe, sem fallback interpretado.
EOF
}

select_python() {
    if command -v python >/dev/null; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_runtime_state() {
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-001B ausente. Execute compile_ovl_001b_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"
    RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-001b-test-runtime-*) ;; *) fail "Runtime invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" capture_a_key)" == "$EXPECTED_A_KEY" ]] || fail "Chave A divergente."
    [[ "$(state_value "$RUNTIME_STATE" capture_b_key)" == "$EXPECTED_B_KEY" ]] || fail "Chave B divergente."
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
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" "$A_TARGET_FILE" "$B_TARGET_FILE" "$EXPECTED_CACHE_REL" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); manifest=pathlib.Path(sys.argv[2]); files=[pathlib.Path(sys.argv[3]),pathlib.Path(sys.argv[4])]
expected_rel=pathlib.PurePosixPath(sys.argv[5]); data=json.loads(manifest.read_text(encoding='utf-8'))
if data.get('track')!='OVL-001B-SAFE-CUMULATIVE' or data.get('capture_keys')!=['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F']:
    raise SystemExit('manifesto nao pertence ao runtime A+B-safe')
if data.get('cache_relative')!=expected_rel.as_posix(): raise SystemExit('namespace de cache divergente')
expected={r['path']:(r['sha256'],int(r['size'])) for r in data.get('files',[])}; actual={}
for rel in expected:
    path=root/pathlib.Path(*pathlib.PurePosixPath(rel).parts)
    if path.is_file(): actual[rel]=(hashlib.sha256(path.read_bytes()).hexdigest().upper(),path.stat().st_size)
if not expected or actual!=expected: raise SystemExit('inventario/hashes do cache cumulativo mudaram')
cache=root/pathlib.Path(*expected_rel.parts); entries=set()
for path in cache.glob('*.ranges'):
    for line in path.read_text(encoding='utf-8').splitlines():
        p=line.split()
        if p and p[0]=='F': entries.add(int(p[1],16)&0x1fffffff)
targets=[]
for path in files:
    for line in path.read_text(encoding='utf-8').splitlines():
        p=line.split('#',1)[0].split()
        if p: targets.append(int(p[1],16)&0x1fffffff)
if len(targets)!=8 or set(targets)-entries: raise SystemExit('cache nao cobre os 8 gates A+B-safe')
PY
}

validate_common() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep mv seq; do command -v "$tool" >/dev/null || fail "$tool nao encontrado."; done
    select_python; read_runtime_state; read_debug_port
    for file in "$RAW_TCP" "$TEST_CONFIG" "$A_TARGET_FILE" "$B_TARGET_FILE" "$RANGES_FILE"; do [[ -f "$file" ]] || fail "Arquivo ausente: $file"; done
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
        candidate="$PROJECT_ROOT/local/telemetry/ovl-001b-telemetry-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi
    done
    fail "Nao ha pasta livre para a telemetria OVL-001B."
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
    case "$RUN_DIR" in "$PROJECT_ROOT"/local/telemetry/ovl-001b-telemetry-*) ;; *) fail "Run invalido." ;; esac
}

general_snapshot() {
    local phase="$1"
    raw "$RUN_DIR/${phase}_overlay_loader_status.log" overlay_loader_status
    raw "$RUN_DIR/${phase}_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/${phase}_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/${phase}_overlay_shadow_dump.log" overlay_shadow_dump
    raw "$RUN_DIR/${phase}_overlay_native_ring.log" overlay_native_ring
}

target_counter() {
    local phase="$1" pc="$2" label="$3" phys hi
    phys=$((pc & 0x1FFFFFFF)); printf -v hi '0x%08X' $((phys + 4))
    raw "$RUN_DIR/${phase}_b_interp_${label}.log" overlay_interp_hot \
        sort=insns min_entries=1 offset=0 limit=1 phys_lo="$pc" phys_hi="$hi"
}

arm_b_watch() {
    local pc label
    raw "$RUN_DIR/prepare_pc_watch_clear.log" pc_watch_clear
    while read -r _ pc label; do
        [[ -n "${pc:-}" ]] || continue
        raw "$RUN_DIR/prepare_pc_watch_arm_${label}.log" pc_watch_arm target="$pc"
    done < <(grep -E '^[[:space:]]*target[[:space:]]+' "$B_TARGET_FILE")
    raw "$RUN_DIR/prepare_pc_watch_dump.log" pc_watch_dump
    "$PYTHON_BIN" - "$RUN_DIR/prepare_pc_watch_dump.log" "$B_TARGET_FILE" <<'PY'
import json,pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace')
match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
if not match: raise SystemExit('pc_watch PREPARE sem JSON bruto')
watch=json.loads(match.group(1)); expected=[]
for line in pathlib.Path(sys.argv[2]).read_text(encoding='utf-8').splitlines():
    fields=line.split('#',1)[0].split()
    if fields: expected.append(fields[1].upper())
actual=[str(entry.get('target','')).upper() for entry in watch.get('entries',[])]
if not watch.get('armed') or actual!=expected or int(watch.get('count',0))!=4:
    raise SystemExit('pc_watch PREPARE nao armou exatamente os quatro gates B-safe')
PY
}

snapshot_before() {
    local pc label
    general_snapshot before
    while read -r _ pc label; do [[ -n "${pc:-}" ]] && raw "$RUN_DIR/before_a_candidate_${label}.log" overlay_candidates pc="$pc"; done \
        < <(grep -E '^[[:space:]]*target[[:space:]]+' "$A_TARGET_FILE")
    while read -r _ pc label; do [[ -n "${pc:-}" ]] && target_counter before "$pc" "$label"; done \
        < <(grep -E '^[[:space:]]*target[[:space:]]+' "$B_TARGET_FILE")
    raw "$RUN_DIR/before_pc_watch_dump.log" pc_watch_dump
}

snapshot_after() {
    local pc label
    general_snapshot after
    while read -r _ pc label; do
        [[ -n "${pc:-}" ]] || continue
        target_counter after "$pc" "$label"
        raw "$RUN_DIR/after_b_candidate_${label}.log" overlay_candidates pc="$pc"
    done < <(grep -E '^[[:space:]]*target[[:space:]]+' "$B_TARGET_FILE")
    raw "$RUN_DIR/after_pc_watch_dump.log" pc_watch_dump
}

verify_prepare() {
    "$PYTHON_BIN" - "$RUN_DIR/prepare_overlay_loader_status.log" "$RUN_DIR/prepare_overlay_shadow_dump.log" "$RUNTIME_DIR" <<'PY'
import json,pathlib,re,sys
def raw(p):
 t=pathlib.Path(p).read_text(encoding='utf-8',errors='replace'); m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',t,re.S)
 if not m: raise SystemExit('JSON bruto ausente')
 return json.loads(m.group(1))
l=raw(sys.argv[1]); s=raw(sys.argv[2]).get('shadow',{}); errors=[]
if int(l.get('active',0))!=1: errors.append('overlay cache inativo')
if pathlib.Path(l.get('cache_dir','')).resolve()!=(pathlib.Path(sys.argv[3])/'cache').resolve(): errors.append('cache_dir inesperado')
if int(l.get('lazy_manifests',0))<=0 and int(l.get('registered',0))<=0: errors.append('nenhum manifesto indexado')
for k in ('range_index_overflow','lazy_manifest_overflow'):
 if int(l.get(k,0)): errors.append(f'{k}={l[k]}')
if int(s.get('diff_mode',1)) or int(s.get('shadow_calls',0)) or int(s.get('in_shadow',0)) or int(s.get('native_exec',0))!=1: errors.append('estado shadow/native invalido')
if errors: raise SystemExit('ERRO: PREPARE: '+'; '.join(errors))
print('Gate PREPARE OVL-001B: cache cumulativo ativo e shadow desligado.')
PY
}

verify_before() {
    "$PYTHON_BIN" - "$RUN_DIR" "$A_TARGET_FILE" <<'PY'
import json,pathlib,re,sys
run=pathlib.Path(sys.argv[1]); targets=pathlib.Path(sys.argv[2])
def raw(name):
 t=(run/name).read_text(encoding='utf-8',errors='replace'); m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',t,re.S)
 if not m: raise SystemExit(f'JSON ausente: {name}')
 return json.loads(m.group(1))
ring=raw('before_overlay_native_ring.log').get('ring',{}); pcs={int(x.get('addr','0'),16)&0x1fffffff for x in ring.get('recent',[])}; errors=[]; rows=[]
for line in targets.read_text(encoding='utf-8').splitlines():
 p=line.split('#',1)[0].split()
 if not p: continue
 pc,label=p[1],p[2]; phys=int(pc,16)&0x1fffffff; candidates=raw(f'before_a_candidate_{label}.log').get('candidates',[])
 matched=[c for c in candidates if int(c.get('match',0))==1 and int(c.get('state',9))==0 and int(c.get('dll',-1))>=0 and int(c.get('device_touch',1))==0]
 rows.append({'pc':pc,'candidate_match':bool(matched),'native_ring_seen':phys in pcs})
 if not matched: errors.append(f'{pc}: candidato GCC exato ausente')
 if phys not in pcs: errors.append(f'{pc}: ausente do ring nativo')
l=raw('before_overlay_loader_status.log'); s=raw('before_overlay_shadow_dump.log').get('shadow',{})
if int(l.get('dispatch_native',0))<=0: errors.append('dispatch_native zerado')
if int(ring.get('in_progress','0'),16)!=0: errors.append('chamada nativa em progresso')
if int(s.get('diff_mode',1)) or int(s.get('shadow_calls',0)) or int(s.get('in_shadow',0)) or int(s.get('native_exec',0))!=1: errors.append('estado shadow/native invalido')
if errors:
 print('ERRO: OVL-001B ainda nao esta pronta para BEFORE:',file=sys.stderr)
 for e in errors: print('  - '+e,file=sys.stderr)
 raise SystemExit(2)
(run/'before-a-gate.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
print('Gate BEFORE: OVL-001A preservada e 4/4 gates nativos no gameplay neutro.')
PY
}

analyze() {
    "$PYTHON_BIN" - "$RUN_DIR" "$B_TARGET_FILE" "$START_EPOCH_NS" <<'PY'
import json,pathlib,re,sys,time
run=pathlib.Path(sys.argv[1]); targets=pathlib.Path(sys.argv[2]); start=int(sys.argv[3])
def raw(name):
 t=(run/name).read_text(encoding='utf-8',errors='replace'); m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',t,re.S)
 if not m: raise SystemExit(f'JSON ausente: {name}')
 return json.loads(m.group(1))
def counter(phase,label):
 rows=raw(f'{phase}_b_interp_{label}.log').get('entries',[])
 return rows[0] if rows else {}
bl=raw('before_overlay_loader_status.log'); al=raw('after_overlay_loader_status.log')
bd=raw('before_dirty_ram_stats.log'); ad=raw('after_dirty_ram_stats.log')
bdisp=raw('before_dispatch_stats.log'); adisp=raw('after_dispatch_stats.log')
bs=raw('before_overlay_shadow_dump.log').get('shadow',{}); ass=raw('after_overlay_shadow_dump.log').get('shadow',{})
watch=raw('after_pc_watch_dump.log'); watched={str(x.get('target','')).upper():x for x in watch.get('entries',[])}
ring=raw('after_overlay_native_ring.log').get('ring',{}); recent=ring.get('recent',[])
errors=[]; rows=[]
for line in targets.read_text(encoding='utf-8').splitlines():
 p=line.split('#',1)[0].split()
 if not p: continue
 pc,label=p[1],p[2]; b=counter('before',label); a=counter('after',label)
 de=max(0,int(a.get('entry_hits',0))-int(b.get('entry_hits',0))); di=max(0,int(a.get('insns',0))-int(b.get('insns',0)))
 w=watched.get(pc.upper(),{}); hits=int(w.get('hits',0) or 0); native=int(w.get('native_hits',0) or 0); interp=int(w.get('interpreted_hits',0) or 0)
 candidates=raw(f'after_b_candidate_{label}.log').get('candidates',[])
 matched=[c for c in candidates if int(c.get('match',0))==1 and int(c.get('state',9))==0 and int(c.get('dll',-1))>=0 and int(c.get('device_touch',1))==0]
 row={'pc':pc,'label':label,'candidate_match_after':bool(matched),'watch_hits':hits,'native_hits':native,'interpreted_hits':interp,'first_frame':int(w.get('first_frame',0) or 0),'last_frame':int(w.get('last_frame',0) or 0),'interp_entry_delta':de,'interp_insn_delta':di}; rows.append(row)
 if native<=0: errors.append(f'{pc}: nenhum hit nativo acumulado')
 if interp or de or di: errors.append(f'{pc}: fallback interpretado na janela')
 if hits != native+interp: errors.append(f'{pc}: contadores pc_watch inconsistentes')
def delta(a,b,k): return max(0,int(b.get(k,0) or 0)-int(a.get(k,0) or 0))
loader={k:delta(bl,al,k) for k in ('dispatch_native','dispatch_interp_fallback','stale_blocked','invalidations','unregistered_funcs')}
guards={k:delta(bd,ad,k) for k in ('aborts','native_handoffs','text_native_blocked','text_diverged_pages','text_exact_mismatches')}
fatal_guards={k:v for k,v in guards.items() if k!='native_handoffs'}
miss=delta(bdisp,adisp,'miss_total')
if loader['dispatch_native']<=0: errors.append('dispatch_native nao cresceu')
if loader['stale_blocked'] or loader['invalidations'] or loader['unregistered_funcs']: errors.append('stale/invalidacao/desregistro')
if any(fatal_guards.values()): errors.append('guard dirty-RAM fatal nao zerado')
if miss: errors.append('miss_total cresceu')
if int(ring.get('in_progress','0'),16)!=0 or any(int(x.get('returned',0))!=1 for x in recent): errors.append('chamada nativa sem retorno')
if int(ass.get('diff_mode',1)) or int(ass.get('shadow_calls',0)) or int(ass.get('in_shadow',0)) or int(ass.get('native_exec',0))!=1: errors.append('estado shadow/native invalido')
for k in ('divergences','skipped_device','escapes','escapes_native'):
 if int(ass.get(k,0)): errors.append(f'shadow {k}={ass[k]}')
duration=max(0,(time.time_ns()-start)/1e9); clean=not errors
result={'track':'OVL-001B-SAFE-CUMULATIVE','capture_key':'0x00020000:0x94E6122F','duration_s':round(duration,3),'targets':rows,'loader_deltas':loader,'guard_deltas':guards,'dispatch_miss_delta':miss,'shadow_before':bs,'shadow_after':ass,'errors':errors,'technical_clean':clean}
(run/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
lines=['# OVL-001B-safe cumulativa - shard 94E6122F','',f'- Duracao: {duration:.3f} s','- Corpo B-safe: 5.183 palavras; delta novo sobre A: 620 palavras; 130 em quarentena',f'- Delta dispatch nativo: {loader["dispatch_native"]}',f'- Delta fallback geral: {loader["dispatch_interp_fallback"]}',f'- Guards dirty-RAM fatais: {fatal_guards}',f'- native_handoffs: {guards["native_handoffs"]} (diagnostico; handoff interpretador -> overlay nativo)',f'- Delta miss_total: {miss}',f'- Status tecnico: {"CLEAN" if clean else "REVIEW"}','','## Quatro gates exclusivos B-safe','', '| PC | Hits nativos acumulados | Hits interpretados | Delta instrucoes interp. | Candidato exato ativo no AFTER |','|---|---:|---:|---:|---:|']
for r in rows: lines.append(f'| `{r["pc"]}` | {r["native_hits"]} | {r["interpreted_hits"]} | {r["interp_insn_delta"]} | {"sim" if r["candidate_match_after"] else "nao (lazy/inativo)"} |')
if errors: lines += ['','## Bloqueios','']+[f'- {e}' for e in errors]
lines += ['','A cobertura estatica S1 permanece 56,9469%; overlays usam metrica separada.','']
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

prepare_phase() {
    if [[ -f "$STATE_FILE" ]]; then
        local old_run old_phase
        old_run="$(state_value "$STATE_FILE" run_dir)"; old_phase="$(state_value "$STATE_FILE" phase)"
        case "$old_run" in "$PROJECT_ROOT"/local/telemetry/ovl-001b-telemetry-*) ;; *) fail "Estado ativo anterior invalido." ;; esac
        [[ "$old_phase" == before && -f "$old_run/result.json" ]] || fail "Ja existe coleta OVL-001B ativa."
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
    general_snapshot prepare; verify_prepare; arm_b_watch
    {
        printf 'run_id=%s\ntrack=OVL-001B-SAFE-CUMULATIVE\nbaseline=S1-261+OVL-001A\n' "$(basename "$RUN_DIR")"
        printf 'runtime_dir=%s\nroute=Ryu x Ken; cenario Ken; somente Ryu executa comandos\n' "$RUNTIME_DIR"
        printf 'body_words=5183\nincremental_words=620\nquarantined_words=130\nprepared_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$RUN_DIR/metadata.txt"
    write_state prepared
    printf '\nPREPARE concluido. Entre em Ryu x Ken, espere 3-5 s neutro e execute BEFORE.\n'
}

before_phase() {
    read_state; [[ "$RUN_PHASE" == prepared ]] || fail "Fase atual: $RUN_PHASE; BEFORE exige prepared."
    note "Validando OVL-001A no gameplay neutro antes de acionar a variante B"
    snapshot_before; verify_before
    raw "$RUN_DIR/window_pc_watch_reset.log" pc_watch_reset
    raw "$RUN_DIR/window_pc_watch_dump.log" pc_watch_dump
    START_EPOCH_NS="$("$PYTHON_BIN" -c 'import time; print(time.time_ns())')"
    printf 'before_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$RUN_DIR/metadata.txt"
    write_state before
    printf '\nBEFORE concluido. Por 30-45 s, mova somente Ryu e execute normais, especiais, defesa/dano e knockdown.\n'
    printf 'Execute AFTER antes do fim do round.\n'
}

after_phase() {
    read_state; [[ "$RUN_PHASE" == before ]] || fail "Fase atual: $RUN_PHASE; AFTER exige before."
    note "Coletando os quatro gates exclusivos OVL-001B-safe"
    raw "$RUN_DIR/after_pc_watch_stop.log" pc_watch_stop
    snapshot_after
    raw "$RUN_DIR/after_overlay_shadow_detail.log" overlay_shadow_detail
    raw "$RUN_DIR/after_overlay_diff_off.log" overlay_diff_off
    analyze
    "$PYTHON_BIN" - "$RUN_DIR/result.json" <<'PY'
import json,pathlib,sys
r=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
if not r.get('technical_clean'): raise SystemExit('ERRO: AFTER em REVIEW: '+'; '.join(r.get('errors',[])))
if len(r.get('targets',[]))!=4: raise SystemExit('ERRO: resultado nao possui quatro gates B-safe')
print('Gate AFTER OVL-001B-safe: 4/4 nativos, CRC exato e zero fallback nos alvos.')
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
