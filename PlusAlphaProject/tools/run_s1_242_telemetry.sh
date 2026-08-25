#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly GENERATED_RANGES="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-242-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly ROOT_TARGET="0x80137FE8"
readonly MIDDLE_TARGET="0x80138084"
readonly CALLEE_TARGET="0x8013827C"
readonly TRACE_HI="0x801383BC"
readonly WATCH_MAX=1024
readonly TRACE_MAX=4096

PYTHON_BIN=""
DEBUG_PORT=""
RUN_DIR=""

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

note() {
    printf '\n==> %s\n' "$*"
}

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/run_s1_242_telemetry.sh

Antes de executar, inicie Versus com Doctrine Dark no P1 e Skullomania no P2,
no cenario do Skullomania. Assim que o round 1 comecar e os personagens
estiverem controlaveis, solte todos os controles e execute o script. Ele coleta
BEFORE, aguarda Enter e coleta AFTER na tela Replay/Exit apos o segundo round.

O script observa simultaneamente 0x80137FE8, 0x80138084 e 0x8013827C por
fntrace, e a raiz por cyc_watch. Ele nao compila, abre nem fecha o jogo.
EOF
}

cleanup_runtime_probes() {
    if [[ -n "$PYTHON_BIN" && -n "$DEBUG_PORT" && -f "$RAW_TCP" ]]; then
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" cyc_watch_clear >/dev/null 2>&1 || true
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" fntrace_arm_clear >/dev/null 2>&1 || true
    fi
}

select_python() {
    if command -v python >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3)"
    else
        fail "Python nao foi encontrado no PATH do UCRT64."
    fi
}

read_debug_port() {
    DEBUG_PORT="$(awk '
        /^[[:space:]]*\[runtime\][[:space:]]*$/ { in_runtime=1; next }
        /^[[:space:]]*\[/ { in_runtime=0 }
        in_runtime && /^[[:space:]]*debug_port[[:space:]]*=/ {
            line=$0
            sub(/^[^=]*=/, "", line)
            gsub(/[[:space:]]+/, "", line)
            print line
            exit
        }
    ' "$GAME_TOML")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida em game.toml."
}

require_range() {
    local line="$1"
    grep -q "^${line}$" "$GENERATED_RANGES" || fail "Range/função ausente: $line"
}

require_symbol() {
    local symbol="$1"
    nm -C "$RUNTIME_EXE" | grep -E "[[:space:]]T[[:space:]]+${symbol}$" >/dev/null ||
        fail "O executavel S1-242 nao contem $symbol."
}

validate_sources() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v objdump >/dev/null 2>&1 || fail "objdump nao encontrado no UCRT64."
    command -v nm >/dev/null 2>&1 || fail "nm nao encontrado no UCRT64."
    command -v sha256sum >/dev/null 2>&1 || fail "sha256sum nao encontrado no UCRT64."
    [[ -f "$GAME_TOML" ]] || fail "game.toml ausente: $GAME_TOML"
    [[ -f "$GENERATED_RANGES" ]] || fail "Ranges gerados ausentes: $GENERATED_RANGES"
    [[ -f "$RAW_TCP" ]] || fail "Cliente TCP ausente: $RAW_TCP"
    [[ -f "$CMAKE_CACHE" ]] || fail "Cache da build S1-242 ausente: $CMAKE_CACHE"
    [[ -f "$RUNTIME_EXE" ]] || fail "Executavel S1-242 ausente: $RUNTIME_EXE"

    require_range "F 80137FE8"
    require_range "R 80137FE8 9C"
    require_range "F 80138084"
    require_range "R 80138084 1F8"
    require_range "F 8013827C"
    require_range "R 8013827C 140"
    require_range "F 801102A0"
    require_range "F 8013CB08"
    ! grep -q '^F 8019E6D0$' "$GENERATED_RANGES" ||
        fail "A funcao em quarentena 0x8019E6D0 apareceu nos fontes."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$GENERATED_RANGES")" == "1028" ]] ||
        fail "A quantidade de funcoes geradas nao corresponde ao S1-242 esperado (1028)."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" ||
        fail "A build S1-242 nao esta configurada como RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" ||
        fail "A build S1-242 nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" ||
        fail "A build S1-242 nao possui PSX_STATIC_RUNTIME=ON."

    local imports
    imports="$(objdump -p "$RUNTIME_EXE" | awk '/DLL Name:/ { print $3 }')"
    if printf '%s\n' "$imports" |
       grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$'; then
        fail "O executavel S1-242 importa uma DLL de runtime nao-sistema."
    fi
    require_symbol "func_80137FE8"
    require_symbol "func_80138084"
    require_symbol "func_8013827C"
    require_symbol "func_801102A0"
    require_symbol "func_8013CB08"
    if nm -C "$RUNTIME_EXE" | grep -E '[[:space:]]T[[:space:]]+func_8019E6D0$' >/dev/null; then
        fail "O executavel S1-242 contem o candidato em quarentena func_8019E6D0."
    fi

    select_python
    read_debug_port
}

raw_command() {
    local output="$1"
    shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 ||
        fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" ||
        fail "Resposta TCP invalida em $(basename "$output")."
}

json_integer() {
    local path="$1"
    local field="$2"
    "$PYTHON_BIN" - "$path" "$field" <<'PY'
import json
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
field = sys.argv[2]
match = re.search(
    r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===",
    text,
    flags=re.DOTALL,
)
if match:
    try:
        print(int(json.loads(match.group(1).strip()).get(field, 0) or 0))
        raise SystemExit
    except json.JSONDecodeError:
        pass
for line in text.splitlines():
    if line.startswith("{"):
        print(int(json.loads(line).get(field, 0) or 0))
        break
else:
    print(0)
PY
}

collect_static_misses() {
    local prefix="$1"
    local output="$RUN_DIR/${prefix}_static_text_misses_offset_000000.log"
    local returned total dropped

    raw_command "$output" static_text_misses class=all min_hits=1 offset=0 limit=256
    returned="$(json_integer "$output" returned)"
    total="$(json_integer "$output" total)"
    dropped="$(json_integer "$output" dropped)"
    ((dropped == 0)) || fail "A coleta $prefix registrou dropped=$dropped."
    ((total <= 256)) ||
        fail "A coleta $prefix possui total=$total, acima do snapshot seguro de 256 entradas."
    ((returned == total)) ||
        fail "A coleta $prefix nao retornou o snapshot completo (returned=$returned, total=$total)."
}

validate_running_build() {
    local ping_file
    ping_file="$(mktemp)"
    trap 'rm -f "$ping_file"' RETURN
    raw_command "$ping_file" ping
    rm -f "$ping_file"
    trap - RETURN
}

create_run_directory() {
    local index candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for index in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-242-telemetry-$index"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            RUN_DIR="$candidate"
            return
        fi
    done
    fail "Nao ha run-id livre entre s1-242-telemetry-01 e 99."
}

write_metadata() {
    local commit="indisponivel"
    local status="indisponivel"
    local ranges_sha exe_sha exe_size
    if command -v git >/dev/null 2>&1; then
        commit="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'indisponivel')"
        status="$(git -C "$REPO_ROOT" status --short 2>/dev/null | tr '\n' ';' || true)"
    fi
    ranges_sha="$(sha256sum "$GENERATED_RANGES" | awk '{print $1}')"
    exe_sha="$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')"
    exe_size="$(stat -c '%s' "$RUNTIME_EXE")"
    cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-242
commit=$commit
git_status=$status
ranges_sha256=$ranges_sha
runtime_exe=$RUNTIME_EXE
runtime_exe_sha256=$exe_sha
runtime_exe_size=$exe_size
runtime_build=buildClean-ucrt-s1-242-tele
runtime_identity=static_imports_cache_compiled_symbols_and_ping_verified
debug_port=$DEBUG_PORT
debug_tools=ON
static_runtime=ON
collection=manual_before_after_versus_three_function_closure
game_launch=manual
game_shutdown=manual
root_target=$ROOT_TARGET
middle_target=$MIDDLE_TARGET
callee_target=$CALLEE_TARGET
closure_range=0x80137FE8..0x801383BB
watch_max=$WATCH_MAX
trace_max=$TRACE_MAX
mode=Versus
characters=Doctrine Dark x Skullomania
stage=Skullomania
route=inicio do round 1 sem inputs ate a tela Replay/Exit apos o segundo round
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

arm_fntrace_closure() {
    local prefix="$1"
    raw_command "$RUN_DIR/${prefix}_fntrace_arm_clear.log" fntrace_arm_clear
    raw_command "$RUN_DIR/${prefix}_fntrace_arm_root.log" fntrace_arm target="$ROOT_TARGET"
    raw_command "$RUN_DIR/${prefix}_fntrace_arm_middle.log" fntrace_arm target="$MIDDLE_TARGET"
    raw_command "$RUN_DIR/${prefix}_fntrace_arm_callee.log" fntrace_arm target="$CALLEE_TARGET"
    raw_command "$RUN_DIR/${prefix}_fntrace_armed.log" fntrace_armed
    raw_command "$RUN_DIR/${prefix}_fntrace_clear.log" fntrace_clear
}

collect_before() {
    note "Armando cyc_watch na raiz 0x80137FE8 (limite real $WATCH_MAX)"
    raw_command "$RUN_DIR/before_cyc_watch_clear.log" cyc_watch_clear
    raw_command "$RUN_DIR/before_cyc_watch_arm.log" cyc_watch pc="$ROOT_TARGET" n="$WATCH_MAX"

    note "Armando fntrace nas tres entradas do fechamento S1-242"
    arm_fntrace_closure before

    note "Coletando BEFORE"
    raw_command "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw_command "$RUN_DIR/before_phase_profile.log" phase_profile window=1
    collect_static_misses before
    raw_command "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
    raw_command "$RUN_DIR/before_cyc_watch.log" cyc_watch_dump
    raw_command "$RUN_DIR/before_fntrace.log" \
        fntrace_dump target_lo="$ROOT_TARGET" target_hi="$TRACE_HI" count="$TRACE_MAX"

    note "Rearmando os contadores para a janela manual"
    raw_command "$RUN_DIR/window_cyc_watch_clear.log" cyc_watch_clear
    raw_command "$RUN_DIR/window_cyc_watch_arm.log" cyc_watch pc="$ROOT_TARGET" n="$WATCH_MAX"
    raw_command "$RUN_DIR/window_fntrace_clear.log" fntrace_clear
}

collect_after() {
    local measured_seconds="$1"
    local phase_window="$measured_seconds"
    if ((phase_window < 1)); then
        phase_window=1
    elif ((phase_window > 60)); then
        phase_window=60
    fi

    note "Coletando AFTER imediatamente"
    raw_command "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    raw_command "$RUN_DIR/after_cyc_watch.log" cyc_watch_dump
    raw_command "$RUN_DIR/after_fntrace.log" \
        fntrace_dump target_lo="$ROOT_TARGET" target_hi="$TRACE_HI" count="$TRACE_MAX"
    raw_command "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw_command "$RUN_DIR/after_phase_profile.log" phase_profile window="$phase_window"
    collect_static_misses after
    raw_command "$RUN_DIR/after_fntrace_armed.log" fntrace_armed
    raw_command "$RUN_DIR/after_fntrace_arm_clear.log" fntrace_arm_clear
    raw_command "$RUN_DIR/after_cyc_watch_clear.log" cyc_watch_clear
}

write_summary() {
    "$PYTHON_BIN" - "$RUN_DIR" "$WATCH_MAX" "$TRACE_MAX" <<'PY'
import collections
import json
import pathlib
import re
import sys

run = pathlib.Path(sys.argv[1])
watch_limit = int(sys.argv[2])
trace_limit = int(sys.argv[3])
targets = ("0x80137FE8", "0x80138084", "0x8013827C")


def payload(path):
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(
        r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===",
        text,
        flags=re.DOTALL,
    )
    if match:
        try:
            value = json.loads(match.group(1).strip())
        except json.JSONDecodeError:
            pass
        else:
            return value if isinstance(value, dict) else {}
    for line in text.splitlines():
        if line.startswith("{"):
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            return value if isinstance(value, dict) else {}
    return {}


def integer(value):
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def norm(value):
    return str(value or "").upper()


def miss_snapshot(prefix):
    top = payload(run / f"{prefix}_static_text_misses_offset_000000.log")
    entries = {
        norm(entry.get("pc")): entry
        for entry in top.get("entries", [])
        if entry.get("pc")
    }
    return top, entries


before_dispatch = payload(run / "before_dispatch_stats.log")
after_dispatch = payload(run / "after_dispatch_stats.log")
before_dirty = payload(run / "before_dirty_ram_stats.log")
after_dirty = payload(run / "after_dirty_ram_stats.log")
after_latency = payload(run / "after_latency.log")
after_phase = payload(run / "after_phase_profile.log")
before_trace = payload(run / "before_fntrace.log")
trace = payload(run / "after_fntrace.log")
before_cyc = payload(run / "before_cyc_watch.log")
window_cyc = payload(run / "after_cyc_watch.log")
before_top, before_misses = miss_snapshot("before")
after_top, after_misses = miss_snapshot("after")
frame = after_latency.get("summary", {}).get("frame_period", {})

target_norm = tuple(norm(target) for target in targets)
trace_entries = trace.get("entries", [])
before_entries = before_trace.get("entries", [])
target_counts = collections.Counter(norm(entry.get("target")) for entry in trace_entries)
before_counts = collections.Counter(norm(entry.get("target")) for entry in before_entries)
root_ra = collections.Counter(
    norm(entry.get("ra")) for entry in trace_entries
    if norm(entry.get("target")) == target_norm[0]
)
middle_ra = collections.Counter(
    norm(entry.get("ra")) for entry in trace_entries
    if norm(entry.get("target")) == target_norm[1]
)
callee_ra = collections.Counter(
    norm(entry.get("ra")) for entry in trace_entries
    if norm(entry.get("target")) == target_norm[2]
)

before_cyc_hits = integer(before_cyc.get("hits"))
window_cyc_hits = integer(window_cyc.get("hits"))
cyc_max = integer(window_cyc.get("max_hits") or watch_limit)
cyc_complete = window_cyc_hits < cyc_max
trace_emitted = integer(trace.get("emitted"))
trace_available = integer(trace.get("available"))
trace_complete = trace_emitted == trace_available and trace_emitted < trace_limit
all_reached = all(target_counts[target] > 0 for target in target_norm)
no_candidate_fallback = all(
    target not in before_misses and target not in after_misses
    for target in target_norm
)
direct_middle = middle_ra["0X80138044"] > 0
direct_callee = callee_ra["0X8013804C"] > 0
compiled_proof = window_cyc_hits > 0 and all_reached

frames = sorted({integer(entry.get("frame")) for entry in trace_entries})
frame_span = frames[-1] - frames[0] + 1 if frames else 0
consecutive = bool(frames) and frame_span == len(frames)

lines = [
    f"# Telemetria {run.name}",
    "",
    "## Intervalo",
    "",
    f"- Duracao manual: {payload(run / 'duration.json').get('seconds', 'n/d')} s",
    f"- Delta static_hits: {integer(after_dispatch.get('static_hits')) - integer(before_dispatch.get('static_hits'))}",
    f"- Delta miss_total: {integer(after_dispatch.get('miss_total')) - integer(before_dispatch.get('miss_total'))}",
    f"- Delta blocks_run: {integer(after_dirty.get('blocks_run')) - integer(before_dirty.get('blocks_run'))}",
    f"- Delta insns_run: {integer(after_dirty.get('insns_run')) - integer(before_dirty.get('insns_run'))}",
    "",
    "## Fechamento S1-242",
    "",
    "- Range formal: `0x80137FE8..0x801383BB` (980 bytes/245 palavras)",
    f"- Hits BEFORE raiz/intermediaria/final: {before_counts[target_norm[0]]}/{before_counts[target_norm[1]]}/{before_counts[target_norm[2]]}",
    f"- Hits janela raiz `0x80137FE8`: {target_counts[target_norm[0]]}",
    f"- Hits janela intermediaria `0x80138084`: {target_counts[target_norm[1]]}",
    f"- Hits janela final `0x8013827C`: {target_counts[target_norm[2]]}",
    f"- Hits cyc_watch raiz durante o BEFORE: {before_cyc_hits}",
    f"- Hits cyc_watch raiz durante a janela manual: {window_cyc_hits}",
    f"- cyc_watch sem saturacao: {'sim' if cyc_complete else 'nao'}",
    f"- Entradas fntrace emitidas/disponiveis: {trace_emitted}/{trace_available}",
    f"- fntrace sem saturacao: {'sim' if trace_complete else 'nao'}",
    f"- As tres entradas foram alcancadas: {'sim' if all_reached else 'nao'}",
    f"- Chamada raiz -> intermediaria (RA 0x80138044): {'confirmada' if direct_middle else 'nao observada'}",
    f"- Chamada raiz -> final (RA 0x8013804C): {'confirmada' if direct_callee else 'nao observada'}",
    f"- Frames unicos observados: {len(frames)}",
    f"- Faixa de frames: {frames[0] if frames else 'n/d'}..{frames[-1] if frames else 'n/d'}",
    f"- Execucao em frames consecutivos: {'sim' if consecutive else 'nao'}",
    f"- Prova direta do fechamento nativo: {'confirmada' if compiled_proof else 'insuficiente'}",
    f"- Alcance sem fallback nas tres entradas: {'confirmado' if compiled_proof and no_candidate_fallback else 'insuficiente'}",
    f"- Retornos mais comuns da raiz: {root_ra.most_common(3)}",
    "",
    "## Build instrumentada",
    "",
    f"- Frametime P50: {integer(frame.get('p50_us')) / 1000.0:.3f} ms",
    f"- Frametime P95: {integer(frame.get('p95_us')) / 1000.0:.3f} ms",
    f"- Frametime maximo: {integer(frame.get('max_us')) / 1000.0:.3f} ms",
    f"- Fases: interpreter={after_phase.get('interp_share', 'n/d')}; static={after_phase.get('static_share', 'n/d')}; GPU={after_phase.get('gpu_share', 'n/d')}",
    "",
    "## Integridade",
    "",
    f"- aborts BEFORE/AFTER: {integer(before_dirty.get('aborts'))}/{integer(after_dirty.get('aborts'))}",
    f"- native_handoffs BEFORE/AFTER: {integer(before_dirty.get('native_handoffs'))}/{integer(after_dirty.get('native_handoffs'))}",
    f"- text_native_blocked BEFORE/AFTER: {integer(before_dirty.get('text_native_blocked'))}/{integer(after_dirty.get('text_native_blocked'))}",
    f"- text_diverged_pages BEFORE/AFTER: {integer(before_dirty.get('text_diverged_pages'))}/{integer(after_dirty.get('text_diverged_pages'))}",
    f"- text_exact_mismatches BEFORE/AFTER: {integer(before_dirty.get('text_exact_mismatches'))}/{integer(after_dirty.get('text_exact_mismatches'))}",
    f"- guard_yields BEFORE/AFTER: {integer(before_dirty.get('guard_yields'))}/{integer(after_dirty.get('guard_yields'))}",
    f"- Snapshot BEFORE total/returned/dropped: {integer(before_top.get('total'))}/{integer(before_top.get('returned'))}/{integer(before_top.get('dropped'))}",
    f"- Snapshot AFTER total/returned/dropped: {integer(after_top.get('total'))}/{integer(after_top.get('returned'))}/{integer(after_top.get('dropped'))}",
    f"- Alvos candidatos presentes nos misses: {'nao' if no_candidate_fallback else 'sim'}",
    "- O script nao compilou, abriu nem fechara o jogo.",
    "",
]
(run / "summary.md").write_text("\n".join(lines), encoding="utf-8")
PY
}

collect_telemetry() {
    validate_running_build
    trap cleanup_runtime_probes EXIT
    create_run_directory
    write_metadata

    printf '\nArtefato S1-242 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"
    printf 'Precondicao: Doctrine Dark P1 x Skullomania P2, cenario Skullomania; round 1 iniciado e sem inputs.\n'
    printf 'A coleta BEFORE comeca agora e observa as tres funcoes do fechamento.\n'
    collect_before

    local started_epoch finished_epoch measured_seconds
    started_epoch="$(date +%s)"
    printf '\nBEFORE concluido. Jogue normalmente ate o fim do segundo round.\n'
    read -r -p 'Na tela Replay/Exit, pare os inputs e pressione Enter para coletar AFTER... ' _
    finished_epoch="$(date +%s)"
    measured_seconds=$((finished_epoch - started_epoch))
    printf '{"seconds":%d}\n' "$measured_seconds" >"$RUN_DIR/duration.json"
    printf 'measured_seconds=%d\n' "$measured_seconds" >>"$RUN_DIR/metadata.txt"

    collect_after "$measured_seconds"
    write_summary

    note "Coleta concluida: $RUN_DIR"
    printf 'Resumo: %s/summary.md\n' "$RUN_DIR"
    printf 'O script NAO fechara o jogo. Feche-o manualmente quando desejar.\n'
}

main() {
    case "${1:-}" in
        "") ;;
        -h|--help)
            usage
            return
            ;;
        *)
            usage
            fail "Argumento desconhecido: $1"
            ;;
    esac
    validate_sources
    collect_telemetry
}

main "$@"
