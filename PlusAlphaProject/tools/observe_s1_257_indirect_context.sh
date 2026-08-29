#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly RAW_TCP="$REPO_ROOT/psxrecomp/tools/raw_tcp.py"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-257-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_SHA=A10B9A83A30D0CB0280F36898971A2D99F804ABC094461994B137F55B635E6CD
readonly ROOT=0x8017566C
readonly RESUME_A=0x80175848
readonly RESUME_B=0x80175888
readonly INTERIOR=0x801757E4
readonly DIAGNOSTIC_DATA_ADDR=0x801BC9C0
readonly DIAGNOSTIC_DATA_COUNT=19

PYTHON_BIN=
DEBUG_PORT=
RUN_DIR=
ARMED=0

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

usage() {
    cat <<'EOF'
Uso, no MSYS2 UCRT64, com a build S1-257 de telemetria aberta:

  bash tools/observe_s1_257_indirect_context.sh [tag]

Fluxo interativo:

  1. Execute o script antes do inicio do gameplay.
  2. Informe a tag solicitada e pressione Enter.
  3. Espere a mensagem PRONTO.
  4. No primeiro frame controlavel, pressione Enter para INICIAR a coleta.
  5. Jogue por 10 a 20 segundos.
  6. Pressione Enter novamente para ENCERRAR a coleta.

O primeiro Enter depois de PRONTO executa somente o reset que abre a janela;
as consultas detalhadas acontecem com a observacao ja ativa. O encerramento
congela o pc_watch antes das consultas finais. O observador registra o corpo
vivo, o estado indireto e as celulas 0x80020800/0x800D6404. Ele nao gera
fontes, nao compila e nao altera seeds.
EOF
}

cleanup() {
    if (( ARMED == 1 )) && [[ -n "$PYTHON_BIN" && -n "$DEBUG_PORT" ]]; then
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" pc_watch_stop >/dev/null 2>&1 || true
    fi
}

raw() {
    local output="$1"; shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 ||
        fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" || fail "Resposta TCP invalida: $(basename "$output")"
}

select_python() {
    if command -v python >/dev/null; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_debug_port() {
    DEBUG_PORT="$(awk '
        /^[[:space:]]*\[runtime\][[:space:]]*$/ { ok=1; next }
        /^[[:space:]]*\[/ { ok=0 }
        ok && /^[[:space:]]*debug_port[[:space:]]*=/ {
            sub(/^[^=]*=/, ""); gsub(/[[:space:]]+/, ""); print; exit
        }
    ' "$GAME_TOML")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida em game.toml."
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum nm; do command -v "$tool" >/dev/null || fail "$tool nao encontrado."; done
    [[ -f "$RAW_TCP" && -f "$GAME_TOML" && -f "$RANGES_FILE" && -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] ||
        fail "Build S1-257 de telemetria ou ferramentas ausentes."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_SHA" ]] ||
        fail "Ranges atuais nao correspondem ao S1-257 aprovado."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1056 ]] ||
        fail "A baseline nao possui as 1.056 funcoes esperadas."
    grep -q '^F 8019FC6C$' "$RANGES_FILE" || fail "Funcao S1-257 ausente."
    ! grep -q '^F 8017566C$' "$RANGES_FILE" || fail "0x8017566C ja esta nativa; esta coleta exige baseline S1-257."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" || fail "A build nao esta RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" || fail "A build nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" || fail "A build nao possui runtime estatico."
    nm -C "$RUNTIME_EXE" | grep -E '[[:space:]]T[[:space:]]+func_8019FC6C$' >/dev/null ||
        fail "Executavel nao corresponde aos fontes S1-257."
    ! nm -C "$RUNTIME_EXE" | grep -E '[[:space:]]T[[:space:]]+func_8017566C$' >/dev/null ||
        fail "O executavel ja contem 0x8017566C nativa; use somente a build S1-257."
    select_python
    read_debug_port
}

sanitize_tag() {
    local tag="${1:-}"
    if [[ -z "$tag" ]]; then
        read -r -p 'Tag curta da coleta [bonus-guile]: ' tag
        tag="${tag:-bonus-guile}"
    fi
    tag="$(printf '%s' "$tag" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+|-+$//g')"
    [[ -n "$tag" ]] || fail "Tag invalida."
    printf '%s' "$tag"
}

make_run_dir() {
    local tag="$1" n candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for n in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-257-indirect-audit-${tag}-$n"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi
    done
    fail "Nao ha identificador livre para a tag $tag."
}

arm_targets() {
    local target suffix
    raw "$RUN_DIR/pc_watch_clear.log" pc_watch_clear
    for target in "$ROOT" "$RESUME_A" "$RESUME_B" "$INTERIOR"; do
        suffix="$(printf '%s' "${target#0x}" | tr '[:lower:]' '[:upper:]')"
        suffix="${suffix#0X}"
        [[ " ${ARMED_TARGETS[*]-} " == *" $suffix "* ]] && continue
        ARMED_TARGETS+=("$suffix")
        raw "$RUN_DIR/pc_watch_arm_${suffix}.log" pc_watch_arm target="0x$suffix"
    done
    raw "$RUN_DIR/pc_watch_initial_dump.log" pc_watch_dump
    raw "$RUN_DIR/pc_watch_reset.log" pc_watch_reset
    ARMED=1
}

write_summary() {
    "$PYTHON_BIN" - "$RUN_DIR" <<'PY'
import hashlib,json,pathlib,re,struct,sys
run=pathlib.Path(sys.argv[1])
def payload(name):
    text=(run/name).read_text(encoding='utf-8',errors='replace')
    m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    return json.loads(m.group(1)) if m else {}
def words(name): return [str(x).upper() for x in payload(name).get('words',[])]
def num(value):
    try: return int(value or 0)
    except (TypeError,ValueError): return 0
watch=payload('pc_watch_final_dump.log')
entries={str(e.get('target','')).upper():e for e in watch.get('entries',[])}
root=entries.get('0X8017566C',{})
resume_a=entries.get('0X80175848',{})
resume_b=entries.get('0X80175888',{})
interior=entries.get('0X801757E4',{})
start_dispatch=payload('start_dispatch_stats.log'); final_dispatch=payload('final_dispatch_stats.log')
start_dirty=payload('start_dirty_ram_stats.log'); final_dirty=payload('final_dirty_ram_stats.log')
start_body=words('start_live_body.log'); final_body=words('final_live_body.log')
def body_hash(values):
    if len(values)!=151: return 'INVALIDO'
    return hashlib.sha256(b''.join(struct.pack('<I',int(x,16)) for x in values)).hexdigest().upper()
start_hash=body_hash(start_body); final_hash=body_hash(final_body)
body_stable=start_body==final_body and len(start_body)==151
expected_hash='5DA650C3D1A23F0C9E8359253D73D3741BE92D12BB348ECBCEB94A2FEE3014E2'
start_state_words=words('start_state_801D39B8.log')
final_state_words=words('final_state_801D39B8.log')
def state_byte(values): return ((int(values[0],16)>>8)&0xff) if values else None
start_state=state_byte(start_state_words); final_state=state_byte(final_state_words)
miss_delta=num(final_dispatch.get('miss_total'))-num(start_dispatch.get('miss_total'))
aborts_stable=num(final_dirty.get('aborts'))==num(start_dirty.get('aborts'))
blocked_stable=num(final_dirty.get('text_native_blocked'))==num(start_dirty.get('text_native_blocked'))
root_observed=num(root.get('interpreted_hits'))>0 and num(root.get('native_hits'))==0
preaudit_evidence=(root_observed and body_stable and start_hash==expected_hash and
                   miss_delta==0 and aborts_stable and blocked_stable)
duration=payload('duration.json').get('seconds','n/d')
lines=[
    f'# Auditoria indireta {run.name}','',
    '- Baseline executada: S1-257',
    '- Candidato preparado: S1-258 / 0x8017566C',
    f'- Duracao da janela: {duration} s',
    f'- Raiz 0x8017566C: {root.get("hits",0)} hits; nativos={root.get("native_hits",0)}; interpretados={root.get("interpreted_hits",0)}',
    f'- Retorno 0x80175848: {resume_a.get("hits",0)} hits; interpretados={resume_a.get("interpreted_hits",0)}',
    f'- Retorno 0x80175888: {resume_b.get("hits",0)} hits; interpretados={resume_b.get("interpreted_hits",0)}',
    f'- Entrada interior 0x801757E4: {interior.get("hits",0)} hits; interpretados={interior.get("interpreted_hits",0)}',
    f'- Corpo vivo BEFORE/AFTER: {start_hash} / {final_hash}',
    f'- Corpo vivo estavel e igual ao executavel: {"sim" if body_stable and start_hash==expected_hash else "nao"}',
    f'- Estado 0x801D39B9 BEFORE/AFTER: {start_state} / {final_state}',
    f'- Dados 0x801BC9C0 BEFORE/AFTER: {words("start_diagnostic_data.log")} / {words("final_diagnostic_data.log")}',
    f'- 0x80020800 BEFORE/AFTER: {words("start_cell_80020800.log")} / {words("final_cell_80020800.log")}',
    f'- 0x800D6400 BEFORE/AFTER: {words("start_cell_800D6400.log")} / {words("final_cell_800D6400.log")}',
    f'- Delta miss_total: {miss_delta}',
    f'- Aborts estaveis: {"sim" if aborts_stable else "nao"}',
    f'- text_native_blocked estavel: {"sim" if blocked_stable else "nao"}',
    f'- Evidencia suficiente para decidir a pre-auditoria: {"sim" if preaudit_evidence else "nao"}', '',
    '', '- Os valores em 0x801BC9C0 sao diagnosticos e nao sao presumidos como enderecos.',
    '- Esta coleta mede o fluxo indireto; ainda nao promove a seed nem autoriza geracao principal.', ''
]
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

main() {
    case "${1:-}" in -h|--help) usage; return ;; esac
    [[ $# -le 1 ]] || { usage; fail "Use no maximo uma tag."; }
    validate
    trap cleanup EXIT
    local tag
    tag="$(sanitize_tag "${1:-}")"
    make_run_dir "$tag"
    cat >"$RUN_DIR/metadata.txt" <<EOF
baseline=S1-257
candidate=S1-258
function=0x8017566C; boundary=0x8017566C..0x801758C7; words=151
route=$tag; inicio sincronizado por Enter; 10 a 20 segundos
ranges_sha256=$(sha256sum "$RANGES_FILE" | awk '{print $1}')
runtime_exe_sha256=$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    declare -a ARMED_TARGETS=()
    arm_targets
    note "PRONTO: instrumentacao armada para a tag $tag"
    read -r -p 'No primeiro frame controlavel, pressione Enter para INICIAR... ' _
    raw "$RUN_DIR/pc_watch_start_reset.log" pc_watch_reset
    local start_epoch end_epoch seconds
    start_epoch="$(date +%s)"
    printf '\nCOLETA INICIADA. Jogue normalmente por 10 a 20 segundos.\n'
    raw "$RUN_DIR/start_live_body.log" mem_words addr="$ROOT" count=151
    raw "$RUN_DIR/start_state_801D39B8.log" mem_words addr=0x801D39B8 count=1
    raw "$RUN_DIR/start_diagnostic_data.log" mem_words addr="$DIAGNOSTIC_DATA_ADDR" count="$DIAGNOSTIC_DATA_COUNT"
    raw "$RUN_DIR/start_cell_80020800.log" mem_words addr=0x80020800 count=2
    raw "$RUN_DIR/start_cell_800D6400.log" mem_words addr=0x800D6400 count=2
    raw "$RUN_DIR/start_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/start_dirty_ram_stats.log" dirty_ram_stats
    read -r -p 'Pressione Enter para ENCERRAR a coleta ainda dentro do gameplay... ' _
    raw "$RUN_DIR/pc_watch_stop.log" pc_watch_stop; ARMED=0
    end_epoch="$(date +%s)"; seconds=$((end_epoch-start_epoch))
    printf '{"seconds":%d}\n' "$seconds" >"$RUN_DIR/duration.json"
    raw "$RUN_DIR/pc_watch_final_dump.log" pc_watch_dump
    raw "$RUN_DIR/final_live_body.log" mem_words addr="$ROOT" count=151
    raw "$RUN_DIR/final_state_801D39B8.log" mem_words addr=0x801D39B8 count=1
    raw "$RUN_DIR/final_diagnostic_data.log" mem_words addr="$DIAGNOSTIC_DATA_ADDR" count="$DIAGNOSTIC_DATA_COUNT"
    raw "$RUN_DIR/final_cell_80020800.log" mem_words addr=0x80020800 count=2
    raw "$RUN_DIR/final_cell_800D6400.log" mem_words addr=0x800D6400 count=2
    raw "$RUN_DIR/final_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/final_dirty_ram_stats.log" dirty_ram_stats
    write_summary
    raw "$RUN_DIR/pc_watch_final_clear.log" pc_watch_clear
    note "Coleta concluida: $RUN_DIR"
    printf 'Resumo: %s/summary.md\n' "$RUN_DIR"
}

main "$@"
