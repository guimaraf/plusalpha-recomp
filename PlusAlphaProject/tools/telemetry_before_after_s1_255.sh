#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-255-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_SHA=30BCD2340878A0C9057CA4B8A66F582A0695AF844B1E45E9409678951D76D404
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.s1-255-telemetry-active.state"
readonly WATCH_SPEC=$'root required 0x8018F10C\nstate_0 state 0x8018F1BC\nstate_1 state 0x8018FF24\nstate_2 state 0x801903AC\nstate_3 state 0x80190450\nstate_4 state 0x801909F8\nmult_a mult 0x8018FACC\nmult_b mult 0x8018FB14\nmult_c mult 0x8018FB74\nmult_d mult 0x80190530'

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

  bash tools/telemetry_before_after_s1_255.sh prepare
  bash tools/telemetry_before_after_s1_255.sh before
  bash tools/telemetry_before_after_s1_255.sh after

Fluxo direcionado do Expert Mode:

  1. Abra manualmente a build S1-255 de telemetria.
  2. No menu de modos, destaque Expert Mode sem entrar e execute PREPARE.
  3. Ainda no mesmo ponto e sem inputs, execute BEFORE.
  4. Entre no Expert, aguarde alguns segundos na selecao, escolha personagem
     e tente ou conclua tarefas de tipos diferentes. Retorne a selecao entre
     tarefas quando o fluxo permitir.
  5. Saia do Expert e volte ao menu de modos. Sem inputs, execute AFTER.

O coletor usa contadores pc_watch, sem ring finito. Uma rota mais longa e
permitida. Ele nao gera, compila, abre nem fecha o jogo.
EOF
}

cleanup() {
    (( PRESERVE_SESSION == 0 )) || return
    if [[ -n "$PYTHON_BIN" && -n "$DEBUG_PORT" && -f "$RAW_TCP" ]]; then
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" pc_watch_stop \
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
        fail "Arquivos da build S1-255 de telemetria estao ausentes."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_SHA" ]] ||
        fail "SHA-256 do manifest nao corresponde ao S1-255 aprovado."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1049 ]] ||
        fail "A quantidade de funcoes geradas nao corresponde ao S1-255 esperado (1049)."

    require_range 'F 8017D860'; require_range 'R 8017D860 1A8'
    require_range 'F 8017DA08'; require_range 'R 8017DA08 94'
    require_range 'F 80191000'; require_range 'R 80191000 A4'
    require_range 'F 8017DA9C'; require_range 'R 8017DA9C 124'
    require_range 'F 80190EB8'; require_range 'R 80190EB8 F4'
    require_range 'F 80190FAC'; require_range 'R 80190FAC 54'
    require_range 'F 8018F10C'; require_range 'R 8018F10C 1D60'
    ! grep -Eq '^F (80103384|8016FC28|8017566C|801910A4|801914C0|80191C84|80192D6C|8019E6D0)$' "$RANGES_FILE" ||
        fail "Uma funcao fora da closure S1-255 apareceu nos fontes."

    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" ||
        fail "A build S1-255 nao esta RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" ||
        fail "A build S1-255 nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" ||
        fail "A build S1-255 nao possui PSX_STATIC_RUNTIME=ON."

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
    require_symbol func_8018F10C
    ! nm -C "$RUNTIME_EXE" |
        grep -q -E '[[:space:]]T[[:space:]]+func_(80103384|8016FC28|8017566C|801910A4|801914C0|80191C84|80192D6C|8019E6D0)$' ||
        fail "O executavel contem uma funcao fora da closure S1-255."

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
        candidate="$PROJECT_ROOT/local/telemetry/s1-255-telemetry-$n"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            RUN_DIR="$candidate"
            return
        fi
    done
    fail "Nao ha run-id livre entre s1-255-telemetry-01 e 99."
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
        fail "Nao existe coleta S1-255 preparada. Execute primeiro prepare."
    RUN_DIR="$(awk -F= '$1 == "run_dir" { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE")"
    RUN_PHASE="$(awk -F= '$1 == "phase" { print $2; exit }' "$STATE_FILE")"
    RUN_START_EPOCH="$(awk -F= '$1 == "start_epoch" { print $2; exit }' "$STATE_FILE")"
    [[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] ||
        fail "Estado S1-255 invalido: run_dir ausente."
    case "$RUN_DIR" in
        "$PROJECT_ROOT"/local/telemetry/s1-255-telemetry-*) ;;
        *) fail "Estado S1-255 fora de local/telemetry." ;;
    esac
    [[ "$RUN_PHASE" == prepared || "$RUN_PHASE" == before ]] ||
        fail "Estado S1-255 invalido: fase $RUN_PHASE."
    [[ "$RUN_START_EPOCH" =~ ^[0-9]+$ ]] ||
        fail "Estado S1-255 invalido: start_epoch."
}

clear_state() { rm -f "$STATE_FILE"; }

metadata() {
    cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-255
function=0x8018F10C
range=0x8018F10C..0x80190E6B
words=1880
jump_table=0x801AE638; states=0x8018F1BC,0x8018FF24,0x801903AC,0x80190450,0x801909F8
mult_blocks=0x8018FACC,0x8018FB14,0x8018FB74,0x80190530
ranges_sha256=$(sha256sum "$RANGES_FILE" | awk '{print $1}')
runtime_exe_sha256=$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')
runtime_build=buildClean-ucrt-s1-255-tele
mode=Expert Mode
route=BEFORE no menu com Expert destacado; entrar no Expert; aguardar na selecao; escolher personagem; percorrer tarefas diferentes e retornar entre elas; sair ao menu; AFTER sem inputs
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

arm_instrumentation() {
    local label kind target suffix
    raw "$RUN_DIR/prepare_pc_watch_clear.log" pc_watch_clear
    while read -r label kind target; do
        suffix="${target#0x}"
        raw "$RUN_DIR/prepare_pc_watch_arm_${label}_${suffix}.log" \
            pc_watch_arm target="$target"
    done <<<"$WATCH_SPEC"
    raw "$RUN_DIR/prepare_pc_watch_dump.log" pc_watch_dump
}

collect_before() {
    note "Coletando BEFORE no menu com Expert Mode destacado"
    raw "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/before_phase_profile.log" phase_profile window=1
    static_misses before
    raw "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/before_pc_watch_dump.log" pc_watch_dump
    raw "$RUN_DIR/window_pc_watch_reset.log" pc_watch_reset
}

collect_after() {
    local seconds="$1" window
    window="$seconds"
    (( window < 1 )) && window=1
    (( window > 60 )) && window=60

    note "Congelando contadores e coletando AFTER"
    raw "$RUN_DIR/after_pc_watch_stop.log" pc_watch_stop
    raw "$RUN_DIR/after_pc_watch_dump.log" pc_watch_dump
    raw "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/after_phase_profile.log" phase_profile window="$window"
    static_misses after
}

summary() {
    "$PYTHON_BIN" - "$RUN_DIR" <<'PY'
import json,pathlib,re,sys

run=pathlib.Path(sys.argv[1])
targets={
    'root':('required','0X8018F10C','entrada formal'),
    'state_0':('state','0X8018F1BC','jump table estado 0'),
    'state_1':('state','0X8018FF24','jump table estado 1'),
    'state_2':('state','0X801903AC','jump table estado 2'),
    'state_3':('state','0X80190450','jump table estado 3'),
    'state_4':('state','0X801909F8','jump table estado 4'),
    'mult_a':('mult','0X8018FACC','bloco de MULT 0x8018FAE4'),
    'mult_b':('mult','0X8018FB14','bloco de MULT 0x8018FB30'),
    'mult_c':('mult','0X8018FB74','bloco de MULT 0x8018FB88'),
    'mult_d':('mult','0X80190530','bloco de MULT 0x80190540'),
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

after_watch=payload('after_pc_watch_dump.log')
watch_entries={str(e.get('target','')).upper():e for e in after_watch.get('entries',[])}
expected={target for _,target,_ in targets.values()}
watch_shape=num(after_watch.get('count'))==len(targets) and set(watch_entries)==expected

rows=[]
observed_clean=True
for label,(kind,target,description) in targets.items():
    entry=watch_entries.get(target,{})
    native=num(entry.get('native_hits'))
    interpreted=num(entry.get('interpreted_hits'))
    hits=num(entry.get('hits'))
    if hits>0 and not (native>0 and interpreted==0):
        observed_clean=False
    rows.append((label,kind,target,description,native,interpreted,hits))

root=watch_entries.get('0X8018F10C',{})
root_ok=num(root.get('native_hits'))>0 and num(root.get('interpreted_hits'))==0
states=[row for row in rows if row[1]=='state' and row[6]>0]
mults=[row for row in rows if row[1]=='mult' and row[6]>0]

before_risky=risky_text('before')
after_risky=risky_text('after')
root_fallback='0X8018F10C' in before_risky or '0X8018F10C' in after_risky

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
gate=(
    watch_shape and root_ok and len(states)>0 and observed_clean and
    not root_fallback and integrity and miss_delta==0
)

latency=payload('after_latency.log')
phase=payload('after_phase_profile.log')
frame=latency.get('summary',{}).get('frame_period',{})
duration=payload('duration.json').get('seconds','n/d')

lines=[
    f'# Telemetria {run.name}',
    '',
    '## Resultado S1-255',
    '',
    f'- Duracao manual: {duration} s',
    f'- Alvos pc_watch exatos: {len(watch_entries)}/{len(targets)}',
    f'- Estados da jump table observados: {len(states)}/5',
    f'- Blocos MULT observados: {len(mults)}/4',
    '',
    '| Ponto | Tipo | Funcao/bloco | Hits nativos | Hits interpretados | Descricao |',
    '| --- | --- | --- | ---: | ---: | --- |',
]
for label,kind,target,description,native,interpreted,_ in rows:
    lines.append(f'| {label} | {kind} | {target} | {native} | {interpreted} | {description} |')
lines += [
    '',
    f'- Entrada 0x8018F10C nativa sem interpretacao: {"sim" if root_ok else "nao"}',
    f'- Estados alcancados: {[row[2] for row in states] or "nenhum"}',
    f'- Blocos MULT alcancados: {[row[2] for row in mults] or "nenhum"}',
    f'- Entrada presente em fallback de texto: {"sim" if root_fallback else "nao"}',
    f'- Gate tecnico da S1-255: {"confirmado" if gate else "insuficiente"}',
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
    '- Estados ou blocos MULT nao observados pedem rota adicional, mas nao sao tratados como regressao automatica.',
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
        fail "Ja existe uma coleta S1-255 pendente. Conclua com AFTER antes de preparar outra."
    make_run_dir
    metadata
    printf '\nArtefato S1-255 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"
    printf 'Precondicao: menu de modos com Expert Mode destacado, ainda sem entrar.\n'
    note "Armando entrada, cinco estados da jump table e quatro blocos MULT"
    arm_instrumentation
    write_state prepared
    PRESERVE_SESSION=1
    note "Preparacao concluida: sem entrar no Expert, execute BEFORE no mesmo menu"
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
    note "BEFORE concluido. Percorra o Expert e termine de volta ao menu de modos"
}

after_phase() {
    validate_build
    trap cleanup EXIT
    read_state
    [[ "$RUN_PHASE" == before ]] ||
        fail "A coleta esta na fase $RUN_PHASE; execute BEFORE no menu primeiro."
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
