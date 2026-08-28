#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-254-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_SHA=2A1B157977603D23A886102BE01A2B7A4B12B7514F450FD893CC96E26B4C4991
readonly TRACE_MAX=4096
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.s1-254-telemetry-active.state"
readonly TRACE_SPEC=$'leaf_a 0x8017DA9C 0x8017DAA0\nleaf_b 0x80190EB8 0x80190EBC\nleaf_c 0x80190FAC 0x80190FB0'
readonly WATCH_TARGETS=$'0x8017DA9C\n0x80190EB8\n0x80190FAC'

PYTHON_BIN=
DEBUG_PORT=
RUN_DIR=
RUN_PHASE=
RUN_START_EPOCH=0
PRESERVE_SESSION=0

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }
require_range() {
    grep -q "^$1$" "$RANGES_FILE" || fail "Range/funcao ausente: $1"
}
require_symbol() {
    nm -C "$RUNTIME_EXE" |
        grep -E "[[:space:]]T[[:space:]]+$1$" >/dev/null ||
        fail "O executavel nao contem $1."
}

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64 e com a mesma execucao aberta do jogo:

  bash tools/telemetry_before_after_s1_254.sh prepare
  bash tools/telemetry_before_after_s1_254.sh before
  bash tools/telemetry_before_after_s1_254.sh after

Fluxo direcionado do Expert Mode:

  1. Abra manualmente a build S1-254 de telemetria.
  2. No menu de modos, destaque Expert Mode sem entrar e execute prepare.
  3. Entre no Expert Mode. Na selecao de personagem, antes de escolher o
     lutador e sem inputs, execute before.
  4. Escolha um personagem, entre em uma tarefa curta, conclua ou tente a
     tarefa e volte para a selecao de personagem do Expert Mode.
  5. Sem inputs na selecao, execute after.

Mantenha a janela BEFORE->AFTER preferencialmente abaixo de 45 segundos para
preservar integralmente o ring fntrace. O coletor nao gera, compila, abre nem
fecha o jogo.
EOF
}

cleanup() {
    (( PRESERVE_SESSION == 0 )) || return
    if [[ -n "$PYTHON_BIN" && -n "$DEBUG_PORT" && -f "$RAW_TCP" ]]; then
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" pc_watch_stop \
            >/dev/null 2>&1 || true
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" fn_disable \
            >/dev/null 2>&1 || true
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" fntrace_arm_clear \
            >/dev/null 2>&1 || true
    fi
}

select_python() {
    if command -v python >/dev/null; then
        PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null; then
        PYTHON_BIN="$(command -v python3)"
    else
        fail "Python nao foi encontrado no PATH do UCRT64."
    fi
}

read_debug_port() {
    DEBUG_PORT="$(awk '
        /^[[:space:]]*\[runtime\][[:space:]]*$/ { ok=1; next }
        /^[[:space:]]*\[/ { ok=0 }
        ok && /^[[:space:]]*debug_port[[:space:]]*=/ {
            sub(/^[^=]*=/, "")
            gsub(/[[:space:]]+/, "")
            print
            exit
        }
    ' "$GAME_TOML")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] ||
        fail "debug_port invalida em game.toml."
}

validate_build() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] ||
        fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v objdump >/dev/null || fail "objdump nao encontrado no UCRT64."
    command -v nm >/dev/null || fail "nm nao encontrado no UCRT64."
    command -v sha256sum >/dev/null ||
        fail "sha256sum nao encontrado no UCRT64."
    [[ -f "$GAME_TOML" && -f "$RANGES_FILE" && -f "$RAW_TCP" &&
       -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] ||
        fail "Arquivos da build S1-254 de telemetria estao ausentes."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_SHA" ]] ||
        fail "SHA-256 do manifest nao corresponde ao S1-254 aprovado."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1048 ]] ||
        fail "A quantidade de funcoes geradas nao corresponde ao S1-254 esperado (1048)."

    require_range 'F 8017D860'; require_range 'R 8017D860 1A8'
    require_range 'F 8017DA08'; require_range 'R 8017DA08 94'
    require_range 'F 80191000'; require_range 'R 80191000 A4'
    require_range 'F 8017DA9C'; require_range 'R 8017DA9C 124'
    require_range 'F 80190EB8'; require_range 'R 80190EB8 F4'
    require_range 'F 80190FAC'; require_range 'R 80190FAC 54'
    ! grep -Eq '^F (80103384|8016FC28|8017566C|8018F10C|801910A4|801914C0|80191C84|80192D6C|8019E6D0)$' "$RANGES_FILE" ||
        fail "Uma funcao fora da closure S1-254 apareceu nos fontes."

    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" ||
        fail "A build S1-254 nao esta RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" ||
        fail "A build S1-254 nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" ||
        fail "A build S1-254 nao possui PSX_STATIC_RUNTIME=ON."

    local imports
    imports="$(objdump -p "$RUNTIME_EXE" | awk '/DLL Name:/ { print $3 }')"
    ! printf '%s\n' "$imports" |
        grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$' ||
        fail "O executavel importa uma DLL de runtime nao-sistema."

    require_symbol func_8017D860
    require_symbol func_8017DA08
    require_symbol func_80191000
    require_symbol func_8017DA9C
    require_symbol func_80190EB8
    require_symbol func_80190FAC
    ! nm -C "$RUNTIME_EXE" |
        grep -q -E '[[:space:]]T[[:space:]]+func_(80103384|8016FC28|8017566C|8018F10C|801910A4|801914C0|80191C84|80192D6C|8019E6D0)$' ||
        fail "O executavel contem uma funcao fora da closure S1-254."

    select_python
    read_debug_port
}

raw() {
    local output="$1"
    shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 ||
        fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" ||
        fail "Resposta TCP invalida em $(basename "$output")."
}

integer() {
    "$PYTHON_BIN" - "$1" "$2" <<'PY'
import json,pathlib,re,sys
t=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace')
field=sys.argv[2]
m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',t,re.S)
rows=[m.group(1).strip()] if m else []
rows += [x for x in t.splitlines() if x.startswith('{')]
for row in rows:
    try:
        print(int(json.loads(row).get(field,0) or 0))
        break
    except (ValueError,TypeError,json.JSONDecodeError):
        pass
else:
    print(0)
PY
}

static_misses() {
    local prefix="$1" output returned total dropped
    output="$RUN_DIR/${prefix}_static_text_misses_offset_000000.log"
    raw "$output" static_text_misses class=all min_hits=1 offset=0 limit=256
    returned="$(integer "$output" returned)"
    total="$(integer "$output" total)"
    dropped="$(integer "$output" dropped)"
    (( dropped == 0 && total <= 256 && returned == total )) ||
        fail "Snapshot $prefix de static_text_misses incompleto (total=$total returned=$returned dropped=$dropped)."
}

make_run_dir() {
    local n candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for n in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-254-telemetry-$n"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            RUN_DIR="$candidate"
            return
        fi
    done
    fail "Nao ha run-id livre entre s1-254-telemetry-01 e 99."
}

write_state() {
    local phase="$1"
    umask 077
    printf 'run_dir=%s\nphase=%s\nstart_epoch=%s\n' \
        "$RUN_DIR" "$phase" "$RUN_START_EPOCH" >"$STATE_FILE"
    RUN_PHASE="$phase"
}

read_state() {
    [[ -f "$STATE_FILE" ]] ||
        fail "Nao existe coleta S1-254 preparada. Execute primeiro prepare."
    RUN_DIR="$(awk -F= '$1 == "run_dir" { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE")"
    RUN_PHASE="$(awk -F= '$1 == "phase" { print $2; exit }' "$STATE_FILE")"
    RUN_START_EPOCH="$(awk -F= '$1 == "start_epoch" { print $2; exit }' "$STATE_FILE")"
    [[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] ||
        fail "Estado S1-254 invalido: run_dir ausente."
    case "$RUN_DIR" in
        "$PROJECT_ROOT"/local/telemetry/s1-254-telemetry-*) ;;
        *) fail "Estado S1-254 fora de local/telemetry." ;;
    esac
    [[ "$RUN_PHASE" == prepared || "$RUN_PHASE" == before ]] ||
        fail "Estado S1-254 invalido: fase $RUN_PHASE."
    [[ "$RUN_START_EPOCH" =~ ^[0-9]+$ ]] ||
        fail "Estado S1-254 invalido: start_epoch."
}

clear_state() { rm -f "$STATE_FILE"; }

metadata() {
    cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-254
functions=0x8017DA9C,0x80190EB8,0x80190FAC
words=73,61,21; total=155
parent=0x8018F10C (permanece interpretada)
ranges_sha256=$(sha256sum "$RANGES_FILE" | awk '{print $1}')
runtime_exe_sha256=$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')
runtime_build=buildClean-ucrt-s1-254-tele
mode=Expert Mode
route=prepare no menu com Expert destacado; BEFORE na selecao de personagem sem inputs; escolher personagem e executar uma tarefa curta; voltar para a selecao; AFTER sem inputs
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

arm_instrumentation() {
    local target label lo hi suffix
    raw "$RUN_DIR/prepare_pc_watch_clear.log" pc_watch_clear
    while read -r target; do
        suffix="${target#0x}"
        raw "$RUN_DIR/prepare_pc_watch_arm_${suffix}.log" \
            pc_watch_arm target="$target"
    done <<<"$WATCH_TARGETS"
    raw "$RUN_DIR/prepare_pc_watch_dump.log" pc_watch_dump

    raw "$RUN_DIR/prepare_fntrace_arm_clear.log" fntrace_arm_clear
    while read -r label lo hi; do
        raw "$RUN_DIR/prepare_fntrace_arm_${label}.log" fntrace_arm target="$lo"
    done <<<"$TRACE_SPEC"
    raw "$RUN_DIR/prepare_fntrace_armed.log" fntrace_armed
    raw "$RUN_DIR/prepare_fntrace_clear.log" fntrace_clear
}

dump_traces() {
    local prefix="$1" label lo hi
    while read -r label lo hi; do
        raw "$RUN_DIR/${prefix}_fntrace_${label}.log" \
            fntrace_dump target_lo="$lo" target_hi="$hi" count="$TRACE_MAX"
    done <<<"$TRACE_SPEC"
}

collect_before() {
    note "Coletando BEFORE na selecao de personagem do Expert Mode"
    raw "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/before_phase_profile.log" phase_profile window=1
    static_misses before
    raw "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/before_fn_stats.log" fn_stats
    raw "$RUN_DIR/before_pc_watch_dump.log" pc_watch_dump
    dump_traces before
    raw "$RUN_DIR/window_pc_watch_reset.log" pc_watch_reset
    raw "$RUN_DIR/window_fntrace_clear.log" fntrace_clear
}

collect_after() {
    local seconds="$1" window
    window="$seconds"
    (( window < 1 )) && window=1
    (( window > 60 )) && window=60

    note "Congelando contadores e coletando AFTER"
    raw "$RUN_DIR/after_pc_watch_stop.log" pc_watch_stop
    raw "$RUN_DIR/after_fn_disable.log" fn_disable
    raw "$RUN_DIR/after_pc_watch_dump.log" pc_watch_dump
    raw "$RUN_DIR/after_fn_stats.log" fn_stats
    dump_traces after
    raw "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/after_phase_profile.log" phase_profile window="$window"
    static_misses after
    raw "$RUN_DIR/after_fntrace_arm_clear.log" fntrace_arm_clear
}

summary() {
    "$PYTHON_BIN" - "$RUN_DIR" "$TRACE_MAX" <<'PY'
import collections,json,pathlib,re,sys

run=pathlib.Path(sys.argv[1])
trace_max=int(sys.argv[2])
targets={
    'leaf_a':('0X8017DA9C',{'0X80190E30'}),
    'leaf_b':('0X80190EB8',{'0X801909D0','0X80190A80','0X80190B64'}),
    'leaf_c':('0X80190FAC',{'0X801909D8','0X80190B6C'}),
}

def payload(name):
    path=run/name
    if not path.exists(): return {}
    text=path.read_text(encoding='utf-8',errors='replace')
    match=re.search(
        r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',
        text,re.S
    )
    rows=[match.group(1).strip()] if match else []
    rows += [line for line in text.splitlines() if line.startswith('{')]
    for row in rows:
        try:
            data=json.loads(row)
            if isinstance(data,dict): return data
        except json.JSONDecodeError:
            pass
    return {}

def num(value):
    try: return int(value or 0)
    except (ValueError,TypeError): return 0

def risky_text(prefix):
    result=set()
    for entry in payload(prefix+'_static_text_misses_offset_000000.log').get('entries',[]):
        if any(num(entry.get(field)) > 0 for field in ('misses','modified','runtime','unknown')):
            result.add(str(entry.get('pc','')).upper())
    return result

before_watch=payload('before_pc_watch_dump.log')
after_watch=payload('after_pc_watch_dump.log')
watch_entries={str(e.get('target','')).upper():e for e in after_watch.get('entries',[])}
before_risky=risky_text('before')
after_risky=risky_text('after')

trace_rows={}
trace_ras={}
unexpected_ras={}
trace_ok={}
ring_complete=True
for label,(target,allowed_ras) in targets.items():
    trace=payload('after_fntrace_'+label+'.log')
    total=num(trace.get('total'))
    available=num(trace.get('available'))
    if total > available or total > trace_max:
        ring_complete=False
    rows=[
        entry for entry in trace.get('entries',[])
        if str(entry.get('target','')).upper()==target
    ]
    ras=collections.Counter(str(entry.get('ra','')).upper() for entry in rows)
    unexpected=set(ras)-allowed_ras
    trace_rows[label]=rows
    trace_ras[label]=ras
    unexpected_ras[label]=unexpected
    trace_ok[label]=len(rows)>0 and not unexpected

native_ok={}
interp_hits={}
for label,(target,_) in targets.items():
    entry=watch_entries.get(target,{})
    native=num(entry.get('native_hits'))
    interpreted=num(entry.get('interpreted_hits'))
    native_ok[label]=native>0 and interpreted==0
    interp_hits[label]=interpreted

bdisp=payload('before_dispatch_stats.log')
adisp=payload('after_dispatch_stats.log')
bdirty=payload('before_dirty_ram_stats.log')
adirty=payload('after_dirty_ram_stats.log')
integrity=(
    num(adirty.get('aborts'))==num(bdirty.get('aborts')) and
    num(adirty.get('native_handoffs'))==num(bdirty.get('native_handoffs')) and
    num(adirty.get('text_native_blocked'))==num(bdirty.get('text_native_blocked'))
)
miss_delta=num(adisp.get('miss_total'))-num(bdisp.get('miss_total'))
fallback={
    label: target in before_risky or target in after_risky
    for label,(target,_) in targets.items()
}
watch_shape=(
    num(after_watch.get('count'))==3 and
    set(watch_entries)=={target for target,_ in targets.values()}
)
gate=(
    watch_shape and all(native_ok.values()) and all(trace_ok.values()) and
    not any(fallback.values()) and ring_complete and integrity and miss_delta==0
)

latency=payload('after_latency.log')
phase=payload('after_phase_profile.log')
frame=latency.get('summary',{}).get('frame_period',{})
duration=payload('duration.json').get('seconds','n/d')

lines=[
    f'# Telemetria {run.name}',
    '',
    '## Resultado S1-254',
    '',
    f'- Duracao manual: {duration} s',
    f'- Alvos pc_watch exatos: {len(watch_entries)}/3',
    f'- Ring fntrace integral: {"sim" if ring_complete else "nao"}',
    '',
    '| Funcao | Hits nativos | Hits interpretados | Hits fntrace | RAs observados | RA inesperado | Fallback |',
    '| --- | ---: | ---: | ---: | --- | --- | --- |',
]
for label,(target,_) in targets.items():
    entry=watch_entries.get(target,{})
    lines.append(
        f'| {target} | {num(entry.get("native_hits"))} | '
        f'{num(entry.get("interpreted_hits"))} | {len(trace_rows[label])} | '
        f'{trace_ras[label].most_common(8)} | '
        f'{sorted(unexpected_ras[label]) or "nao"} | '
        f'{"sim" if fallback[label] else "nao"} |'
    )
lines += [
    '',
    f'- Gate tecnico das tres folhas: {"confirmado" if gate else "insuficiente"}',
    f'- Delta static_hits: {num(adisp.get("static_hits"))-num(bdisp.get("static_hits"))}',
    f'- Delta miss_total: {miss_delta}',
    '',
    '## Frametime e integridade',
    '',
    f'- P50/P95/max: {num(frame.get("p50_us"))/1000:.3f} / '
    f'{num(frame.get("p95_us"))/1000:.3f} / '
    f'{num(frame.get("max_us"))/1000:.3f} ms',
    f'- Fases: interpreter={phase.get("interp_share","n/d")}; '
    f'static={phase.get("static_share","n/d")}; GPU={phase.get("gpu_share","n/d")}',
    f'- aborts BEFORE/AFTER: {num(bdirty.get("aborts"))}/{num(adirty.get("aborts"))}',
    f'- native_handoffs BEFORE/AFTER: '
    f'{num(bdirty.get("native_handoffs"))}/{num(adirty.get("native_handoffs"))}',
    f'- text_native_blocked BEFORE/AFTER: '
    f'{num(bdirty.get("text_native_blocked"))}/{num(adirty.get("text_native_blocked"))}',
    '',
    '- O coletor nao gerou, compilou, abriu nem fechou o jogo.',
    '- A coleta nao substitui a regressao manual posterior.',
    '',
]
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

prepare() {
    validate_build
    trap cleanup EXIT
    [[ ! -e "$STATE_FILE" ]] ||
        fail "Ja existe uma coleta S1-254 pendente. Conclua com AFTER antes de preparar outra."
    make_run_dir
    metadata
    printf '\nArtefato S1-254 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"
    printf 'Precondicao: menu de modos com Expert Mode destacado, ainda sem entrar.\n'
    note "Armando pc_watch e fntrace para as tres folhas"
    arm_instrumentation
    write_state prepared
    PRESERVE_SESSION=1
    note "Preparacao concluida: entre no Expert e execute BEFORE na selecao de personagem"
}

before_phase() {
    validate_build
    trap cleanup EXIT
    read_state
    [[ "$RUN_PHASE" == prepared ]] ||
        fail "A coleta esta na fase $RUN_PHASE; execute AFTER, nao BEFORE."
    collect_before
    RUN_START_EPOCH="$(date +%s)"
    write_state before
    PRESERVE_SESSION=1
    note "BEFORE concluido. Faca uma tarefa curta e volte para a selecao do Expert"
}

after_phase() {
    validate_build
    trap cleanup EXIT
    read_state
    [[ "$RUN_PHASE" == before ]] ||
        fail "A coleta esta na fase $RUN_PHASE; execute BEFORE na selecao do Expert."
    local end seconds
    end="$(date +%s)"
    seconds=$((end-RUN_START_EPOCH))
    printf '{"seconds":%d}\n' "$seconds" >"$RUN_DIR/duration.json"
    collect_after "$seconds"
    summary
    raw "$RUN_DIR/final_pc_watch_clear.log" pc_watch_clear
    clear_state
    PRESERVE_SESSION=1
    note "Coleta concluida: $RUN_DIR"
    printf 'Resumo: %s/summary.md\nO script nao fechara o jogo.\n' "$RUN_DIR"
}

main() {
    [[ $# == 1 ]] || { usage; fail "Informe uma fase: prepare, before ou after."; }
    case "$1" in
        prepare) prepare ;;
        before) before_phase ;;
        after) after_phase ;;
        -h|--help) usage ;;
        *) usage; fail "Fase desconhecida: $1" ;;
    esac
}

main "$@"
