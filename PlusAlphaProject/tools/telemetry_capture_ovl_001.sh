#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly RAW_TCP="$REPO_ROOT/psxrecomp/tools/raw_tcp.py"
readonly CAPTURE_CONFIG="$PROJECT_ROOT/game_ovl_001_capture.toml"
readonly TARGET_FILE="$PROJECT_ROOT/seeds/ovl_001_target_pcs.txt"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-001-current-runtime.state"
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.ovl-001-capture-active.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F

PYTHON_BIN=
DEBUG_PORT=
RUNTIME_DIR=
RUNTIME_EXE=
CAPTURE_JSON=
RUN_DIR=
RUN_PHASE=
START_EPOCH_NS=0

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, sempre com a mesma execucao OVL-001 aberta:

  bash tools/telemetry_capture_ovl_001.sh prepare
  bash tools/telemetry_capture_ovl_001.sh before
  bash tools/telemetry_capture_ovl_001.sh after

Rota:
  PREPARE: no Mode Select, antes de escolher os personagens.
  BEFORE : gameplay controlavel de Ryu x Ken, cenario do Ken; aguarde 2 s sem input.
  AFTER  : apos 20-30 s de movimentos/golpes somente do Ryu, antes do round acabar.

Ken deve permanecer sem comandos; ele pode receber golpes e reagir normalmente.
O BEFORE falha sem mudar a fase se os quatro PCs de gameplay nao estiverem ativos.
O coletor nao compila, nao abre e nao fecha o jogo.
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
        fail "Runtime OVL-001 nao preparado. Execute prepare_ovl_001_capture_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"
    RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    case "$RUNTIME_DIR" in
        "$PROJECT_ROOT"/local/overlay/ovl-001-capture-runtime-*) ;;
        *) fail "Diretorio do runtime OVL-001 e invalido." ;;
    esac
    [[ -d "$RUNTIME_DIR" && -f "$RUNTIME_EXE" ]] || fail "Runtime OVL-001 incompleto."
    CAPTURE_JSON="$RUNTIME_DIR/overlay_captures.json"
}

read_debug_port() {
    DEBUG_PORT="$(awk '
        /^[[:space:]]*\[runtime\][[:space:]]*$/ { ok=1; next }
        /^[[:space:]]*\[/ { ok=0 }
        ok && /^[[:space:]]*debug_port[[:space:]]*=/ {
            sub(/^[^=]*=/, ""); gsub(/[[:space:]]+/, ""); print; exit
        }
    ' "$CAPTURE_CONFIG")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida."
}

validate_common() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep cp mv seq find cygpath; do
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
    "$PYTHON_BIN" - "$TARGET_FILE" <<'PY'
import pathlib,sys
rows=[]
for number,line in enumerate(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8').splitlines(),1):
    parts=line.split('#',1)[0].split()
    if not parts: continue
    if len(parts)!=3 or parts[0]!='target': raise SystemExit(f'linha target invalida: {number}')
    rows.append(int(parts[1],16))
expected={0x8004A44C,0x80091878,0x8004922C,0x80049500}
if set(rows)!=expected or len(rows)!=4: raise SystemExit('gate de targets OVL-001 divergente')
PY
}

raw() {
    local output="$1"; shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 ||
        fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" || fail "Resposta TCP invalida: $*"
}

json_from_raw() {
    "$PYTHON_BIN" - "$1" "$2" <<'PY'
import json,pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace')
field=sys.argv[2]
match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
rows=([match.group(1).strip()] if match else [])+[x for x in text.splitlines() if x.startswith('{')]
for row in rows:
    try:
        value=json.loads(row).get(field)
        if isinstance(value,bool): print(int(value))
        elif value is not None: print(value)
        break
    except (json.JSONDecodeError,TypeError,ValueError): pass
PY
}

make_run_dir() {
    local suffix candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-001-capture-$suffix"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"; RUN_DIR="$candidate"; return
        fi
    done
    fail "Nao ha run livre entre ovl-001-capture-01 e 99."
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
    [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta OVL-001 ativa. Execute prepare."
    RUN_DIR="$(state_value "$STATE_FILE" run_dir)"
    local saved_runtime
    saved_runtime="$(state_value "$STATE_FILE" runtime_dir)"
    RUN_PHASE="$(state_value "$STATE_FILE" phase)"
    START_EPOCH_NS="$(state_value "$STATE_FILE" start_epoch_ns)"
    [[ "$saved_runtime" == "$RUNTIME_DIR" ]] || fail "O runtime mudou durante a coleta."
    case "$RUN_DIR" in
        "$PROJECT_ROOT"/local/telemetry/ovl-001-capture-*) ;;
        *) fail "Estado OVL-001 aponta para run invalido." ;;
    esac
    [[ -d "$RUN_DIR" && "$START_EPOCH_NS" =~ ^[0-9]+$ ]] || fail "Estado incompleto."
}

copy_capture() {
    local destination="$1"
    [[ -s "$CAPTURE_JSON" ]] || fail "overlay_captures.json nao foi gerado pelo runtime."
    cp "$CAPTURE_JSON" "$destination"
    "$PYTHON_BIN" - "$destination" <<'PY'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1]); data=json.loads(path.read_text(encoding='utf-8'))
if not isinstance(data,list) or not data: raise SystemExit('captura vazia ou schema invalido')
for i,row in enumerate(data):
    for key in ('load_addr','size','bytes_b64'):
        if key not in row: raise SystemExit(f'captura {i} sem {key}')
print(len(data))
PY
}

snapshot() {
    local phase="$1"
    raw "$RUN_DIR/${phase}_overlay_loader_status.log" overlay_loader_status
    raw "$RUN_DIR/${phase}_overlay_interp_hot.log" overlay_interp_hot sort=insns min_entries=1 offset=0 limit=256
    raw "$RUN_DIR/${phase}_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/${phase}_dispatch_stats.log" dispatch_stats
}

verify_gameplay_baseline() {
    "$PYTHON_BIN" - "$RUN_DIR/before_overlay_interp_hot.log" \
        "$RUN_DIR/before_overlay_captures.json" "$TARGET_FILE" <<'PY'
import base64,json,pathlib,re,sys
hot_path,capture_path,target_path=map(pathlib.Path,sys.argv[1:])
text=hot_path.read_text(encoding='utf-8',errors='replace')
match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
if not match: raise SystemExit('ERRO: snapshot overlay_interp_hot sem JSON bruto')
hot=json.loads(match.group(1))
hot_pcs={(int(row.get('pc','0'),16)&0x1fffffff)
         for row in hot.get('entries',[]) if int(row.get('entry_hits',0) or 0)>0}
targets=[]
for line in target_path.read_text(encoding='utf-8').splitlines():
    parts=line.split('#',1)[0].split()
    if parts: targets.append((int(parts[1],16)&0x1fffffff,parts[2]))
captures=json.loads(capture_path.read_text(encoding='utf-8'))
captured=set()
for row in captures:
    load=int(row['load_addr'],16)&0x1fffffff; size=int(row['size'])
    observed={(int(pc,16)&0x1fffffff) for key in ('executed_pcs','dispatch_entry_pcs')
              for pc in row.get(key,[])}
    captured.update(pc for pc,_ in targets if load<=pc<load+size and pc in observed)
missing_hot=[pc for pc,_ in targets if pc not in hot_pcs]
missing_capture=[pc for pc,_ in targets if pc not in captured]
if missing_hot or missing_capture:
    print('ERRO: gameplay OVL-001 ainda nao foi confirmado.',file=sys.stderr)
    if missing_hot:
        print('  PCs sem execucao: '+', '.join(f'0x{pc|0x80000000:08X}' for pc in missing_hot),file=sys.stderr)
    if missing_capture:
        print('  PCs fora da captura: '+', '.join(f'0x{pc|0x80000000:08X}' for pc in missing_capture),file=sys.stderr)
    print('Entre em Ryu x Ken, aguarde 2 segundos com controles neutros e repita BEFORE.',file=sys.stderr)
    raise SystemExit(2)
print('Gate de gameplay OVL-001: 4/4 PCs ativos e capturados.')
PY
}

prepare_phase() {
    [[ ! -f "$STATE_FILE" ]] || fail "Ja existe uma coleta OVL-001 ativa."
    make_run_dir
    raw "$RUN_DIR/prepare_overlay_loader_status.log" overlay_loader_status
    local active registered cache_dir
    active="$(json_from_raw "$RUN_DIR/prepare_overlay_loader_status.log" active)"
    registered="$(json_from_raw "$RUN_DIR/prepare_overlay_loader_status.log" registered)"
    cache_dir="$(json_from_raw "$RUN_DIR/prepare_overlay_loader_status.log" cache_dir)"
    cache_dir="$(cygpath -u "$cache_dir")"
    [[ "$active" == 1 ]] || fail "Overlay cache nao esta ativo; abra usando game_ovl_001_capture.toml."
    [[ "${registered:-0}" == 0 ]] || fail "Runtime isolado carregou funcoes nativas de cache antigo."
    [[ "$cache_dir" == "$RUNTIME_DIR/cache" ]] ||
        fail "Cache ativo nao pertence ao runtime isolado: $cache_dir"
    [[ ! -d "$RUNTIME_DIR/cache" ]] ||
        [[ -z "$(find "$RUNTIME_DIR/cache" -type f -print -quit 2>/dev/null)" ]] ||
        fail "Runtime isolado possui arquivos de cache."
    raw "$RUN_DIR/prepare_overlay_capture_dump.log" overlay_capture_dump
    if [[ -s "$CAPTURE_JSON" ]]; then
        cp "$CAPTURE_JSON" "$RUN_DIR/prepare_overlay_captures.json"
    fi
    snapshot prepare
    {
        printf 'run_id=%s\ntrack=OVL-001\nbaseline=S1-261\n' "$(basename "$RUN_DIR")"
        printf 'runtime_dir=%s\nruntime_exe_sha256=%s\n' "$RUNTIME_DIR" "$EXPECTED_EXE_SHA"
        printf 'ranges_sha256=%s\nconfig=%s\n' "$EXPECTED_RANGES_SHA" "$CAPTURE_CONFIG"
        printf 'route=Ryu x Ken; cenario Ken; somente Ryu executa comandos\n'
        printf 'capture_policy=private; no autocompile; no cache; no polling during window\n'
        printf 'prepared_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$RUN_DIR/metadata.txt"
    write_state prepared
    printf '\nPREPARE concluido.\n'
    printf 'Escolha Ryu x Ken. No primeiro frame controlavel, sem inputs, execute BEFORE.\n'
}

before_phase() {
    read_state
    [[ "$RUN_PHASE" == prepared ]] || fail "Fase atual: $RUN_PHASE; BEFORE exige prepared."
    note "Congelando a baseline do primeiro frame controlavel"
    raw "$RUN_DIR/before_overlay_capture_dump.log" overlay_capture_dump
    copy_capture "$RUN_DIR/before_overlay_captures.json" >/dev/null
    snapshot before
    verify_gameplay_baseline
    START_EPOCH_NS="$("$PYTHON_BIN" -c 'import time; print(time.time_ns())')"
    printf 'before_utc=%s\nbefore_epoch_ns=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$START_EPOCH_NS" >>"$RUN_DIR/metadata.txt"
    write_state before
    printf '\nBEFORE concluido; a janela esta ativa.\n'
    printf 'Execute movimentos e golpes somente com Ryu por 20-30 segundos.\n'
    printf 'Mantenha Ken sem comandos e execute AFTER antes do fim do round.\n'
}

analyze() {
    "$PYTHON_BIN" - "$RUN_DIR" "$TARGET_FILE" "$START_EPOCH_NS" <<'PY'
import base64,binascii,csv,json,pathlib,re,sys,time
run=pathlib.Path(sys.argv[1]); target_path=pathlib.Path(sys.argv[2]); start=int(sys.argv[3])
targets=[]
for line in target_path.read_text(encoding='utf-8').splitlines():
    parts=line.split('#',1)[0].split()
    if parts: targets.append((int(parts[1],16),parts[2]))
def captures(name):
    return json.loads((run/name).read_text(encoding='utf-8'))
def raw_json(name):
    text=(run/name).read_text(encoding='utf-8',errors='replace')
    match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not match: raise SystemExit(f'JSON bruto ausente em {name}')
    return json.loads(match.group(1))
def describe(rows):
    out=[]
    for row in rows:
        raw=base64.b64decode(row['bytes_b64']); load=int(row['load_addr'],16)
        size=int(row['size']); phys=load & 0x1fffffff; crc=binascii.crc32(raw)&0xffffffff
        executed={int(x,16) for x in row.get('executed_pcs',[])}
        dispatched={int(x,16) for x in row.get('dispatch_entry_pcs',[])}
        matches=[]
        for pc,label in targets:
            pc_phys=pc&0x1fffffff
            if phys <= pc_phys < phys+size:
                matches.append((pc,label,pc in executed,pc in dispatched))
        out.append({'load':load,'phys':phys,'size':size,'crc':crc,'executed':executed,
                    'dispatched':dispatched,'matches':matches})
    return out
before=describe(captures('before_overlay_captures.json'))
after=describe(captures('private-overlay-captures.json'))
rows=[]
for cap in after:
    if not cap['matches']: continue
    observed=[m for m in cap['matches'] if m[2] or m[3]]
    rows.append({
        'capture_key':f'0x{cap["phys"]:08X}:0x{cap["crc"]:08X}',
        'load_addr':f'0x{cap["load"]:08X}','size':cap['size'],
        'range_end':f'0x{cap["load"]+cap["size"]:08X}',
        'target_count_in_range':len(cap['matches']),'target_count_observed':len(observed),
        'targets_in_range':' '.join(f'0x{x[0]:08X}' for x in cap['matches']),
        'targets_observed':' '.join(f'0x{x[0]:08X}' for x in observed),
        'executed_pcs':len(cap['executed']),'dispatch_entry_pcs':len(cap['dispatched']),
    })
columns=['capture_key','load_addr','size','range_end','target_count_in_range',
         'target_count_observed','targets_in_range','targets_observed','executed_pcs','dispatch_entry_pcs']
with (run/'capture-candidates.csv').open('w',encoding='utf-8',newline='') as handle:
    writer=csv.DictWriter(handle,fieldnames=columns); writer.writeheader(); writer.writerows(rows)
observed_targets={pc for cap in after for pc,_,ex,di in cap['matches'] if ex or di}
missing=[pc for pc,_ in targets if pc not in observed_targets]
duration=max(0,(time.time_ns()-start)/1e9)
before_keys={(x['phys'],x['crc']) for x in before}
after_keys={(x['phys'],x['crc']) for x in after}
before_dirty=raw_json('before_dirty_ram_stats.log'); after_dirty=raw_json('after_dirty_ram_stats.log')
before_dispatch=raw_json('before_dispatch_stats.log'); after_dispatch=raw_json('after_dispatch_stats.log')
guard_names=('aborts','native_handoffs','text_native_blocked','text_diverged_pages','text_exact_mismatches')
guard_deltas={name:max(0,int(after_dirty.get(name,0) or 0)-int(before_dirty.get(name,0) or 0))
              for name in guard_names}
dispatch_miss_delta=max(0,int(after_dispatch.get('miss_total',0) or 0)-
                          int(before_dispatch.get('miss_total',0) or 0))
before_loader=raw_json('before_overlay_loader_status.log')
after_loader=raw_json('after_overlay_loader_status.log')
native_dispatch_delta=max(0,int(after_loader.get('dispatch_native',0) or 0)-
                            int(before_loader.get('dispatch_native',0) or 0))
technical_clean=(not any(guard_deltas.values()) and dispatch_miss_delta==0 and
                 native_dispatch_delta==0 and int(after_loader.get('registered',0) or 0)==0)
lines=['# OVL-001 - captura Ryu x Ken','',f'- Duracao da janela: {duration:.3f} s',
       f'- Regioes BEFORE: {len(before)}',f'- Regioes AFTER: {len(after)}',
       f'- Variantes novas/trocadas durante a janela: {len(after_keys-before_keys)}',
       f'- Targets observados: {len(observed_targets)}/4',
       f'- Candidatos exatos de captura: {len(rows)}',
       f'- Delta miss_total: {dispatch_miss_delta}',
       f'- Delta dispatch nativo de overlay: {native_dispatch_delta}',
       f'- Gates de dirty RAM: {guard_deltas}',
       f'- Status tecnico: {"CLEAN" if technical_clean else "REVIEW"}','','',
       '## Regioes candidatas','',
       '| Capture key | Range | Targets observados | PCs executados | Entradas dispatch |',
       '|---|---|---:|---:|---:|']
for row in rows:
    lines.append(f'| `{row["capture_key"]}` | `{row["load_addr"]}..{row["range_end"]}` | '
                 f'{row["target_count_observed"]} | {row["executed_pcs"]} | {row["dispatch_entry_pcs"]} |')
if not rows: lines.append('| - | - | 0 | 0 | 0 |')
if missing:
    lines += ['', 'Targets dominantes ausentes: '+', '.join(f'`0x{x:08X}`' for x in missing)+'.']
lines += ['', 'A captura e privada e nao deve ser publicada. Nenhum overlay foi compilado nesta rodada.', '']
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
result={'track':'OVL-001','duration_s':round(duration,3),'before_regions':len(before),
        'after_regions':len(after),'changed_variants':len(after_keys-before_keys),
        'observed_targets':[f'0x{x:08X}' for x in sorted(observed_targets)],
        'missing_targets':[f'0x{x:08X}' for x in missing],'capture_candidates':rows,
        'dispatch_miss_delta':dispatch_miss_delta,'native_dispatch_delta':native_dispatch_delta,
        'guard_deltas':guard_deltas,'technical_clean':technical_clean}
(run/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY
}

verify_after_result() {
    "$PYTHON_BIN" - "$RUN_DIR/result.json" <<'PY'
import json,pathlib,sys
result=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
errors=[]
if len(result.get('observed_targets',[]))!=4: errors.append('targets observados diferentes de 4/4')
if not result.get('capture_candidates'): errors.append('nenhum capture-key candidato')
if not result.get('technical_clean'): errors.append('gates tecnicos em REVIEW')
if errors:
    raise SystemExit('ERRO: AFTER OVL-001 incompleto: '+'; '.join(errors))
print('Gate AFTER OVL-001: 4/4 targets, capture-key presente e status CLEAN.')
PY
}

after_phase() {
    read_state
    [[ "$RUN_PHASE" == before ]] || fail "Fase atual: $RUN_PHASE; AFTER exige before."
    note "Encerrando a janela e persistindo a captura privada"
    raw "$RUN_DIR/after_overlay_capture_dump.log" overlay_capture_dump
    copy_capture "$RUN_DIR/private-overlay-captures.json" >/dev/null
    snapshot after
    analyze
    verify_after_result
    printf 'after_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$RUN_DIR/metadata.txt"
    mv "$STATE_FILE" "$RUN_DIR/completed.state"
    printf '\nAFTER concluido. O jogo continua aberto; nenhum overlay foi compilado.\n'
    printf 'Resumo: %s/summary.md\n' "$RUN_DIR"
    printf 'Capture keys: %s/capture-candidates.csv\n' "$RUN_DIR"
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
