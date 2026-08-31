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
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.ovl-001a-soak-active.state"
readonly SHORT_STATE_FILE="$PROJECT_ROOT/local/telemetry/.ovl-001a-test-active.state"
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

  bash tools/telemetry_soak_ovl_001a_3matches.sh prepare
  bash tools/telemetry_soak_ovl_001a_3matches.sh before
  bash tools/telemetry_soak_ovl_001a_3matches.sh after

Rota:
  PREPARE: Mode Select, antes da primeira partida.
  BEFORE : inicio controlavel da primeira partida, Ryu x Ken/cenario Ken,
           ambos neutros por 3-5 segundos.
  JANELA : jogar tres partidas completas, sem fechar o jogo.
  AFTER  : de volta ao Mode Select depois da terceira partida.

Este ensaio mede estabilidade acumulada. O AFTER nao exige que o codigo da luta
continue residente no Mode Select. O script nao compila, nao abre e nao fecha o
jogo.
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
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-001A ausente."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"
    RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    local capture_key
    capture_key="$(state_value "$RUNTIME_STATE" capture_key)"
    case "$RUNTIME_DIR" in
        "$PROJECT_ROOT"/local/overlay/ovl-001a-test-runtime-*) ;;
        *) fail "Diretorio do runtime OVL-001A invalido." ;;
    esac
    [[ "$capture_key" == "$EXPECTED_CAPTURE_KEY" ]] || fail "Runtime aponta para outra captura."
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
actual={}
for rel in expected:
    path=root/pathlib.Path(*pathlib.PurePosixPath(rel).parts)
    if not path.is_file(): raise SystemExit(f'arquivo de cache ausente: {rel}')
    actual[rel]=(hashlib.sha256(path.read_bytes()).hexdigest().upper(),path.stat().st_size)
if not expected or actual!=expected:
    raise SystemExit('inventario/hashes do cache mudaram')
entries=set()
cache_dir=root/pathlib.Path(*expected_rel.parts)
for ranges in cache_dir.glob('*.ranges'):
    for line in ranges.read_text(encoding='utf-8').splitlines():
        parts=line.split()
        if parts and parts[0]=='F': entries.add(int(parts[1],16)&0x1fffffff)
targets=[]
for line in target_path.read_text(encoding='utf-8').splitlines():
    parts=line.split('#',1)[0].split()
    if parts: targets.append(int(parts[1],16)&0x1fffffff)
if len(targets)!=4 or set(targets)-entries:
    raise SystemExit('cache nao oferece os quatro targets')
PY
}

validate_common() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep mv seq; do
        command -v "$tool" >/dev/null || fail "$tool nao encontrado no UCRT64."
    done
    select_python
    read_runtime_state
    read_debug_port
    [[ ! -f "$SHORT_STATE_FILE" ]] ||
        fail "Existe uma coleta curta OVL-001A ativa; conclua-a antes do soak."
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

make_run_dir() {
    local suffix candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-001a-soak-3matches-$suffix"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"; RUN_DIR="$candidate"; return
        fi
    done
    fail "Nao ha run livre para o soak OVL-001A."
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
    [[ -f "$STATE_FILE" ]] || fail "Nao existe soak OVL-001A ativo. Execute prepare."
    RUN_DIR="$(state_value "$STATE_FILE" run_dir)"
    local saved_runtime
    saved_runtime="$(state_value "$STATE_FILE" runtime_dir)"
    RUN_PHASE="$(state_value "$STATE_FILE" phase)"
    START_EPOCH_NS="$(state_value "$STATE_FILE" start_epoch_ns)"
    [[ "$saved_runtime" == "$RUNTIME_DIR" ]] || fail "O runtime mudou durante o soak."
    case "$RUN_DIR" in
        "$PROJECT_ROOT"/local/telemetry/ovl-001a-soak-3matches-*) ;;
        *) fail "Estado do soak aponta para run invalido." ;;
    esac
    [[ -d "$RUN_DIR" && "$START_EPOCH_NS" =~ ^[0-9]+$ ]] || fail "Estado incompleto."
}

snapshot() {
    local phase="$1" pc label phys hi
    raw "$RUN_DIR/${phase}_overlay_loader_status.log" overlay_loader_status
    raw "$RUN_DIR/${phase}_overlay_interp_hot.log" overlay_interp_hot sort=insns min_entries=1 offset=0 limit=256
    raw "$RUN_DIR/${phase}_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/${phase}_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/${phase}_overlay_shadow_dump.log" overlay_shadow_dump
    raw "$RUN_DIR/${phase}_overlay_native_ring.log" overlay_native_ring
    while read -r _ pc label; do
        [[ -n "${pc:-}" ]] || continue
        phys=$((pc & 0x1FFFFFFF))
        printf -v hi '0x%08X' $((phys + 4))
        raw "$RUN_DIR/${phase}_target_interp_${label}.log" overlay_interp_hot \
            sort=insns min_entries=1 offset=0 limit=1 phys_lo="$pc" phys_hi="$hi"
        if [[ "$phase" == before ]]; then
            raw "$RUN_DIR/${phase}_candidate_${label}.log" overlay_candidates pc="$pc"
        fi
    done < <(grep -E '^[[:space:]]*target[[:space:]]+' "$TARGET_FILE")
}

verify_prepare() {
    "$PYTHON_BIN" - "$RUN_DIR/prepare_overlay_loader_status.log" \
        "$RUNTIME_DIR" "$RUN_DIR/prepare_overlay_shadow_dump.log" <<'PY'
import json,pathlib,re,sys
def raw_json(path):
    text=pathlib.Path(path).read_text(encoding='utf-8',errors='replace')
    m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not m: raise SystemExit(f'JSON bruto ausente em {path}')
    return json.loads(m.group(1))
loader=raw_json(sys.argv[1]); shadow=raw_json(sys.argv[3]).get('shadow',{})
expected=(pathlib.Path(sys.argv[2])/'cache').resolve()
actual=pathlib.Path(loader.get('cache_dir','')).resolve()
errors=[]
if int(loader.get('active',0))!=1: errors.append('overlay cache inativo')
if actual!=expected: errors.append(f'cache_dir inesperado: {actual}')
if int(loader.get('lazy_manifests',0))<=0 and int(loader.get('registered',0))<=0:
    errors.append('nenhum manifesto indexado')
for key in ('range_index_overflow','lazy_manifest_overflow'):
    if int(loader.get(key,0)): errors.append(f'{key}={loader[key]}')
if int(shadow.get('diff_mode',1))!=0: errors.append('shadow-diff ligado')
if int(shadow.get('shadow_calls',0))!=0: errors.append('shadow ja foi executado')
if int(shadow.get('in_shadow',0))!=0: errors.append('runtime dentro do shadow')
if int(shadow.get('native_exec',0))!=1: errors.append('execucao nativa desabilitada')
if errors: raise SystemExit('ERRO: gate PREPARE soak: '+'; '.join(errors))
print('Gate PREPARE soak: cache exato, nativo ativo e shadow desligado.')
PY
}

verify_before() {
    "$PYTHON_BIN" - "$RUN_DIR" "$TARGET_FILE" <<'PY'
import json,pathlib,re,sys
run=pathlib.Path(sys.argv[1]); targets=pathlib.Path(sys.argv[2])
def raw_json(name):
    text=(run/name).read_text(encoding='utf-8',errors='replace')
    m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not m: raise SystemExit(f'JSON bruto ausente em {name}')
    return json.loads(m.group(1))
rows=[]; errors=[]
ring=raw_json('before_overlay_native_ring.log').get('ring',{})
recent=ring.get('recent',[])
ring_pcs={int(e.get('addr','0'),16)&0x1fffffff for e in recent}
for line in targets.read_text(encoding='utf-8').splitlines():
    parts=line.split('#',1)[0].split()
    if not parts: continue
    pc,label=parts[1],parts[2]; phys=int(pc,16)&0x1fffffff
    candidates=raw_json(f'before_candidate_{label}.log').get('candidates',[])
    matched=[c for c in candidates if int(c.get('match',0))==1 and int(c.get('state',9))==0]
    best=matched[0] if matched else {}
    row={'pc':pc,'label':label,'candidate_match':bool(matched),
         'dll':int(best.get('dll',-99)) if best else -99,
         'device_touch':int(best.get('device_touch',-1)) if best else -1,
         'native_ring_seen':phys in ring_pcs}
    rows.append(row)
    if not row['candidate_match']: errors.append(f'{pc}: candidato exato ausente')
    if row['dll']<0: errors.append(f'{pc}: candidato nao veio de DLL GCC')
    if row['device_touch']!=0: errors.append(f'{pc}: device_touch')
    if not row['native_ring_seen']: errors.append(f'{pc}: ausente do ring nativo')
loader=raw_json('before_overlay_loader_status.log')
shadow=raw_json('before_overlay_shadow_dump.log').get('shadow',{})
if int(loader.get('registered',0))<4: errors.append('menos de 4 funcoes registradas')
if int(loader.get('dispatch_native',0))<=0: errors.append('dispatch_native zerado')
if int(ring.get('in_progress','0'),16)!=0: errors.append('funcao nativa em progresso no snapshot')
if any(int(e.get('returned',0))!=1 for e in recent): errors.append('ring contem chamada sem retorno')
if int(shadow.get('diff_mode',1))!=0 or int(shadow.get('shadow_calls',0))!=0:
    errors.append('shadow ligado ou executado')
if int(shadow.get('in_shadow',0))!=0 or int(shadow.get('native_exec',0))!=1:
    errors.append('estado de execucao nativa invalido')
if errors:
    print('ERRO: BEFORE soak rejeitado:',file=sys.stderr)
    for error in errors: print('  - '+error,file=sys.stderr)
    raise SystemExit(2)
(run/'before-target-gate.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
print('Gate BEFORE soak: 4/4 targets GCC exatos e ativos no ring nativo.')
PY
}

prepare_phase() {
    [[ ! -f "$STATE_FILE" ]] || fail "Ja existe um soak OVL-001A ativo."
    make_run_dir
    raw "$RUN_DIR/prepare_native_block_clear.log" overlay_native_block clear=1
    raw "$RUN_DIR/prepare_overlay_diff_off.log" overlay_diff_off
    raw "$RUN_DIR/prepare_overlay_loader_status.log" overlay_loader_status
    raw "$RUN_DIR/prepare_overlay_shadow_dump.log" overlay_shadow_dump
    verify_prepare
    {
        printf 'run_id=%s\ntrack=OVL-001A-SOAK-3MATCHES\nbaseline=S1-261\n' "$(basename "$RUN_DIR")"
        printf 'runtime_dir=%s\nruntime_exe_sha256=%s\n' "$RUNTIME_DIR" "$EXPECTED_EXE_SHA"
        printf 'ranges_sha256=%s\ncapture_key=%s\n' "$EXPECTED_RANGES_SHA" "$EXPECTED_CAPTURE_KEY"
        printf 'route=Ryu x Ken; cenario Ken; tres partidas completas\n'
        printf 'after_location=Mode Select depois da terceira partida\n'
        printf 'policy=isolated GCC shard; cumulative soak; shadow diff disabled\n'
        printf 'prepared_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$RUN_DIR/metadata.txt"
    write_state prepared
    printf '\nPREPARE concluido no Mode Select.\n'
    printf 'Inicie Ryu x Ken/cenario Ken. No primeiro round controlavel, aguarde 3-5 s\n'
    printf 'com ambos neutros e execute BEFORE.\n'
}

before_phase() {
    read_state
    [[ "$RUN_PHASE" == prepared ]] || fail "Fase atual: $RUN_PHASE; BEFORE exige prepared."
    note "Armando o soak no inicio controlavel da primeira partida"
    snapshot before
    verify_before
    START_EPOCH_NS="$("$PYTHON_BIN" -c 'import time; print(time.time_ns())')"
    printf 'before_utc=%s\nbefore_epoch_ns=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$START_EPOCH_NS" >>"$RUN_DIR/metadata.txt"
    write_state before
    printf '\nBEFORE concluido; a janela acumulada esta ativa.\n'
    printf 'Jogue tres partidas COMPLETAS sem fechar o jogo. Depois da terceira, volte\n'
    printf 'ao Mode Select e execute AFTER.\n'
}

analyze() {
    "$PYTHON_BIN" - "$RUN_DIR" "$TARGET_FILE" "$START_EPOCH_NS" <<'PY'
import json,pathlib,re,sys,time
run=pathlib.Path(sys.argv[1]); targets_path=pathlib.Path(sys.argv[2]); start=int(sys.argv[3])
def raw_json(name):
    text=(run/name).read_text(encoding='utf-8',errors='replace')
    m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not m: raise SystemExit(f'JSON bruto ausente em {name}')
    return json.loads(m.group(1))
def value(obj,key): return int(obj.get(key,0) or 0)
def delta(before,after,key,errors):
    b=value(before,key); a=value(after,key)
    if a<b: errors.append(f'contador {key} regrediu/resetou ({b}->{a})')
    return a-b
def target_counter(phase,label):
    rows=raw_json(f'{phase}_target_interp_{label}.log').get('entries',[])
    if not rows: return {'entry_hits':0,'insns':0}
    return {'entry_hits':value(rows[0],'entry_hits'),'insns':value(rows[0],'insns')}

before_loader=raw_json('before_overlay_loader_status.log')
after_loader=raw_json('after_overlay_loader_status.log')
before_dirty=raw_json('before_dirty_ram_stats.log'); after_dirty=raw_json('after_dirty_ram_stats.log')
before_dispatch=raw_json('before_dispatch_stats.log'); after_dispatch=raw_json('after_dispatch_stats.log')
before_shadow=raw_json('before_overlay_shadow_dump.log').get('shadow',{})
after_shadow=raw_json('after_overlay_shadow_dump.log').get('shadow',{})
before_ring=raw_json('before_overlay_native_ring.log').get('ring',{})
after_ring=raw_json('after_overlay_native_ring.log').get('ring',{})
errors=[]
loader_keys=('dispatch_native','dispatch_interp_fallback','loads','invalidations',
             'revalidations','unregistered_funcs','stale_blocked','gen_fastpath')
loader_deltas={k:delta(before_loader,after_loader,k,errors) for k in loader_keys}
guard_keys=('aborts','native_handoffs','text_native_blocked','text_diverged_pages',
            'text_exact_mismatches')
guard_deltas={k:delta(before_dirty,after_dirty,k,errors) for k in guard_keys}
dispatch_miss_delta=delta(before_dispatch,after_dispatch,'miss_total',errors)
native_call_delta=value(after_ring,'calls_total')-value(before_ring,'calls_total')
if native_call_delta<0: errors.append('contador calls_total regrediu/resetou')
if native_call_delta<=0: errors.append('nenhuma chamada nativa durante o soak')
if loader_deltas['dispatch_native']<=0: errors.append('dispatch_native nao cresceu')
if dispatch_miss_delta: errors.append('miss_total cresceu')
if any(guard_deltas.values()): errors.append('gate dirty-RAM nao zerado')
if int(after_shadow.get('diff_mode',1))!=0: errors.append('shadow-diff foi ligado')
if int(after_shadow.get('shadow_calls',0))!=0: errors.append('shadow foi executado')
if int(after_shadow.get('in_shadow',0))!=0: errors.append('runtime dentro do shadow')
if int(after_shadow.get('native_exec',0))!=1: errors.append('execucao nativa desabilitada')
if any(value(after_shadow,k) for k in ('divergences','skipped_device','escapes','escapes_native')):
    errors.append('shadow registrou divergencia/MMIO/escape')
recent=after_ring.get('recent',[])
if int(after_ring.get('in_progress','0'),16)!=0: errors.append('funcao nativa em progresso no AFTER')
unreturned=sum(1 for e in recent if int(e.get('returned',0))!=1)
if unreturned: errors.append(f'{unreturned} chamada(s) sem retorno no ring AFTER')
after_ring_pcs={int(e.get('addr','0'),16)&0x1fffffff for e in recent}
target_rows=[]
for line in targets_path.read_text(encoding='utf-8').splitlines():
    parts=line.split('#',1)[0].split()
    if not parts: continue
    pc,label=parts[1],parts[2]; phys=int(pc,16)&0x1fffffff
    before=target_counter('before',label); after=target_counter('after',label)
    entry_delta=after['entry_hits']-before['entry_hits']
    insn_delta=after['insns']-before['insns']
    if entry_delta<0 or insn_delta<0:
        errors.append(f'{pc}: contador interpretado regrediu/resetou')
    elif entry_delta or insn_delta:
        errors.append(f'{pc}: fallback interpretado durante o soak')
    target_rows.append({'pc':pc,'label':label,'interp_entry_delta':entry_delta,
                        'interp_insn_delta':insn_delta,
                        'present_in_after_ring':phys in after_ring_pcs})
duration=max(0,(time.time_ns()-start)/1e9)
clean=not errors
result={'track':'OVL-001A-SOAK-3MATCHES','capture_key':'0x00020000:0xAC1FF1A4',
        'duration_s':round(duration,3),'expected_matches':3,'targets':target_rows,
        'native_call_delta':native_call_delta,'loader_deltas':loader_deltas,
        'dispatch_miss_delta':dispatch_miss_delta,'guard_deltas':guard_deltas,
        'after_ring_entries':len(recent),'after_ring_unreturned':unreturned,
        'shadow_before':before_shadow,'shadow_after':after_shadow,
        'transition_counters_informational':['loads','invalidations','revalidations',
                                             'unregistered_funcs','stale_blocked'],
        'errors':errors,'technical_clean':clean}
(run/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
lines=['# OVL-001A - soak de tres partidas','',f'- Duracao acumulada: {duration:.3f} s',
       f'- Delta de chamadas nativas: {native_call_delta}',
       f'- Delta dispatch nativo: {loader_deltas["dispatch_native"]}',
       f'- Delta fallback geral de overlays: {loader_deltas["dispatch_interp_fallback"]}',
       f'- Transicoes (informativas): loads={loader_deltas["loads"]}, '
       f'invalidations={loader_deltas["invalidations"]}, revalidations={loader_deltas["revalidations"]}, '
       f'unregistered={loader_deltas["unregistered_funcs"]}, stale={loader_deltas["stale_blocked"]}',
       f'- Gates dirty-RAM: {guard_deltas}',f'- Delta miss_total: {dispatch_miss_delta}',
       f'- Chamadas sem retorno no ring AFTER: {unreturned}',
       f'- Status tecnico: {"CLEAN" if clean else "REVIEW"}','','## Quatro targets','',
       '| PC | Delta entradas interpretadas | Delta instrucoes interpretadas | Presente no ring final |',
       '|---|---:|---:|---:|']
for row in target_rows:
    lines.append(f'| `{row["pc"]}` | {row["interp_entry_delta"]} | {row["interp_insn_delta"]} | '
                 f'{"sim" if row["present_in_after_ring"] else "nao"} |')
if errors: lines += ['','## Bloqueios','']+[f'- {error}' for error in errors]
lines += ['','A quantidade de tres partidas depende da confirmacao manual do operador.',
          'A porcentagem estatica S1 permanece 56,9469%; overlays usam metrica separada.','']
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

verify_after_result() {
    "$PYTHON_BIN" - "$RUN_DIR/result.json" <<'PY'
import json,pathlib,sys
result=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
if not result.get('technical_clean'):
    raise SystemExit('ERRO: soak OVL-001A em REVIEW: '+'; '.join(result.get('errors',[])))
if len(result.get('targets',[]))!=4:
    raise SystemExit('ERRO: resultado nao possui os quatro targets')
print('Gate AFTER soak: chamadas nativas acumuladas, 4/4 alvos sem fallback e guards limpos.')
PY
}

after_phase() {
    read_state
    [[ "$RUN_PHASE" == before ]] || fail "Fase atual: $RUN_PHASE; AFTER exige before."
    note "Encerrando o soak de tres partidas no Mode Select"
    snapshot after
    raw "$RUN_DIR/after_overlay_shadow_detail.log" overlay_shadow_detail
    raw "$RUN_DIR/after_overlay_diff_off.log" overlay_diff_off
    analyze
    verify_after_result
    printf 'after_utc=%s\noperator_completed_matches=3\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$RUN_DIR/metadata.txt"
    write_state completed
    mv "$STATE_FILE" "$RUN_DIR/completed.state"
    printf '\nAFTER concluido. O jogo continua aberto.\n'
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
