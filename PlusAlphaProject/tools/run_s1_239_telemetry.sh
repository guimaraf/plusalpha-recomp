#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly GENERATED_RANGES="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly TARGETS=(
    0x8019CB4C
    0x8019CB60
    0x8019CB78
    0x8019CB8C
    0x8019CBA0
    0x8019CBA8
)

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

  bash tools/run_s1_239_telemetry.sh
      Conecta à build de telemetria já aberta, coleta BEFORE imediatamente,
      aguarda Enter, coleta AFTER e gera summary.md. Não compila, abre ou fecha
      o jogo.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3)"
    else
        fail "Python não foi encontrado no PATH do UCRT64."
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
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port inválida em game.toml."
}

validate_environment() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    [[ -f "$GAME_TOML" ]] || fail "game.toml ausente: $GAME_TOML"
    [[ -f "$GENERATED_RANGES" ]] || fail "Ranges gerados ausentes: $GENERATED_RANGES"
    [[ -f "$RAW_TCP" ]] || fail "Cliente TCP ausente: $RAW_TCP"
    grep -q '^F 8019CB4C$' "$GENERATED_RANGES" ||
        fail "A seed 0x8019CB4C não aparece nos fontes gerados. Regenere o jogo primeiro."
    grep -q '^R 8019CB4C 70$' "$GENERATED_RANGES" ||
        fail "O range esperado 0x8019CB4C+0x70 não aparece nos fontes gerados."
    select_python
    read_debug_port
}

raw_command() {
    local output="$1"
    shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 ||
        fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" ||
        fail "Resposta TCP inválida em $(basename "$output")."
}

json_integer() {
    local path="$1"
    local field="$2"
    "$PYTHON_BIN" - "$path" "$field" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
field = sys.argv[2]
for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
    if line.startswith("{"):
        value = json.loads(line).get(field, 0)
        print(int(value or 0))
        break
else:
    print(0)
PY
}

collect_static_misses() {
    local prefix="$1"
    local offset=0
    local page=0
    local returned
    local output

    while :; do
        output="$RUN_DIR/${prefix}_static_text_misses_offset_$(printf '%06d' "$offset").log"
        raw_command "$output" static_text_misses class=all min_hits=1 offset="$offset" limit=256
        returned="$(json_integer "$output" returned)"
        ((page < 255)) || fail "Limite defensivo de paginação atingido em static_text_misses."
        if ((returned == 0)); then
            break
        fi
        offset=$((offset + returned))
        page=$((page + 1))
    done
}

collect_dispatch_checks() {
    local prefix="$1"
    local target
    local target_phys
    for target in "${TARGETS[@]}"; do
        # dispatch_check trabalha no espaco fisico; os alvos documentados estao
        # no KSEG0 virtual, usado apenas nos arquivos e no fntrace.
        target_phys="$(printf '0x%08X' $((target & 0x1FFFFFFF)))"
        raw_command "$RUN_DIR/${prefix}_dispatch_check_${target#0x}.log" \
            dispatch_check addr="$target_phys"
    done
}

collect_trace_dumps() {
    local prefix="$1"
    local target
    local target_hi
    for target in "${TARGETS[@]}"; do
        target_hi="$(printf '0x%08X' $((target + 4)))"
        raw_command "$RUN_DIR/${prefix}_fntrace_${target#0x}.log" \
            fntrace_dump target_lo="$target" target_hi="$target_hi" count=4096
    done
}

collect_before() {
    note "Armando somente as seis entradas do candidato S1-239"
    raw_command "$RUN_DIR/before_fntrace_arm_clear.log" fntrace_arm_clear
    local target
    for target in "${TARGETS[@]}"; do
        raw_command "$RUN_DIR/before_fntrace_arm_${target#0x}.log" fntrace_arm target="$target"
    done
    raw_command "$RUN_DIR/before_fntrace_armed.log" fntrace_armed
    raw_command "$RUN_DIR/before_fntrace_clear.log" fntrace_clear

    note "Coletando BEFORE"
    raw_command "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw_command "$RUN_DIR/before_phase_profile.log" phase_profile window=1
    collect_static_misses before
    collect_dispatch_checks before
    collect_trace_dumps before

    # Os contadores-base ficam por último para excluir o custo das consultas
    # anteriores do intervalo da luta.
    raw_command "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
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
    raw_command "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw_command "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    collect_trace_dumps after
    raw_command "$RUN_DIR/after_phase_profile.log" phase_profile window="$phase_window"
    collect_static_misses after
    collect_dispatch_checks after
    raw_command "$RUN_DIR/after_fntrace_armed.log" fntrace_armed
    raw_command "$RUN_DIR/after_fntrace_arm_clear.log" fntrace_arm_clear
}

create_run_directory() {
    local index
    local candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for index in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-239-telemetry-$index"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            RUN_DIR="$candidate"
            return
        fi
    done
    fail "Não há run-id livre entre s1-239-telemetry-01 e 99."
}

write_metadata() {
    local commit="indisponivel"
    local status="indisponivel"
    if command -v git >/dev/null 2>&1; then
        commit="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'indisponivel')"
        status="$(git -C "$REPO_ROOT" status --short 2>/dev/null | tr '\n' ';' || true)"
    fi
    cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-239
commit=$commit
git_status=$status
runtime_build=manual_telemetry_build
runtime_identity=debug_tcp_ping_verified
debug_port=$DEBUG_PORT
debug_tools=ON
collection=manual_before_after
game_launch=manual
game_shutdown=manual
targets=${TARGETS[*]}
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

write_summary() {
    "$PYTHON_BIN" - "$RUN_DIR" "${TARGETS[@]}" <<'PY'
import json
import pathlib
import sys

run = pathlib.Path(sys.argv[1])
targets = [value.upper().replace("0X", "0x") for value in sys.argv[2:]]


def payload(path: pathlib.Path) -> dict:
    if not path.exists():
        return {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("{"):
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            return value if isinstance(value, dict) else {}
    return {}


def integer(value) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def misses(prefix: str) -> dict[str, dict]:
    result: dict[str, dict] = {}
    for path in sorted(run.glob(f"{prefix}_static_text_misses_offset_*.log")):
        for entry in payload(path).get("entries", []):
            pc = str(entry.get("pc", "")).upper().replace("0X", "0x")
            if pc:
                result[pc] = entry
    return result


before_dispatch = payload(run / "before_dispatch_stats.log")
after_dispatch = payload(run / "after_dispatch_stats.log")
before_dirty = payload(run / "before_dirty_ram_stats.log")
after_dirty = payload(run / "after_dirty_ram_stats.log")
after_phase = payload(run / "after_phase_profile.log")
after_latency = payload(run / "after_latency.log")
before_misses = misses("before")
after_misses = misses("after")

frame = after_latency.get("summary", {}).get("frame_period", {})
lines = [
    f"# Telemetria {run.name}",
    "",
    "## Intervalo",
    "",
    f"- Duração manual: {payload(run / 'duration.json').get('seconds', 'n/d')} s",
    f"- Δ static_hits: {integer(after_dispatch.get('static_hits')) - integer(before_dispatch.get('static_hits'))}",
    f"- Δ miss_total: {integer(after_dispatch.get('miss_total')) - integer(before_dispatch.get('miss_total'))}",
    f"- Δ blocks_run: {integer(after_dirty.get('blocks_run')) - integer(before_dirty.get('blocks_run'))}",
    f"- Δ insns_run: {integer(after_dirty.get('insns_run')) - integer(before_dirty.get('insns_run'))}",
    "",
    "## Frametime da build instrumentada",
    "",
    f"- P50: {integer(frame.get('p50_us')) / 1000.0:.3f} ms",
    f"- P95: {integer(frame.get('p95_us')) / 1000.0:.3f} ms",
    "- P99: n/d (endpoint não fornece P99)",
    f"- Máximo: {integer(frame.get('max_us')) / 1000.0:.3f} ms",
    f"- Fases: interpreter={after_phase.get('interp_share', 'n/d')}; static={after_phase.get('static_share', 'n/d')}; GPU={after_phase.get('gpu_share', 'n/d')}",
    "",
    "## Entradas do candidato",
    "",
    "| Entrada | Hits fntrace no intervalo | Dispatch observado | Δ miss/fallback | Interpretação preliminar |",
    "|---|---:|---|---|---|",
]

for target in targets:
    suffix = target[2:]
    trace = payload(run / f"after_fntrace_{suffix}.log")
    check = payload(run / f"after_dispatch_check_{suffix}.log")
    before_entry = before_misses.get(target, {})
    after_entry = after_misses.get(target, {})
    emitted = integer(trace.get("emitted"))
    found = bool(check.get("found"))
    deltas = {
        key: integer(after_entry.get(key)) - integer(before_entry.get(key))
        for key in ("misses", "modified", "runtime", "unknown")
    }
    fallback_delta = sum(max(0, value) for value in deltas.values())
    miss_text = ", ".join(f"{key}={value:+d}" for key, value in deltas.items())
    if fallback_delta > 0:
        interpretation = "fallback observado no intervalo"
    elif emitted > 0:
        interpretation = "alcançada sem fallback; compatível com estático"
    elif found:
        interpretation = "vista fora do intervalo; sem prova de uso na luta"
    else:
        interpretation = "não alcançada/provada"
    lines.append(
        f"| `{target}` | {emitted} | {'sim' if found else 'não'} | {miss_text} | {interpretation} |"
    )

before_candidate_misses = [target for target in targets if target in before_misses]
after_candidate_misses = [target for target in targets if target in after_misses]
lines += [
    "",
    "## Integridade",
    "",
    f"- Entradas do candidato nos misses BEFORE: {before_candidate_misses or 'nenhuma'}",
    f"- Entradas do candidato nos misses AFTER: {after_candidate_misses or 'nenhuma'}",
    "- A telemetria prova alcance/fallback, mas não substitui a comparação de frametime entre builds limpas.",
    "- Feche o jogo manualmente após conferir que todos os arquivos foram gravados.",
    "",
]

(run / "summary.md").write_text("\n".join(lines), encoding="utf-8")
PY
}

collect_telemetry() {
    local readiness
    readiness="$(mktemp)"
    if ! "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" ping >"$readiness" 2>&1 ||
       ! grep -q '"ok":true' "$readiness"; then
        rm -f "$readiness"
        fail "O jogo de telemetria não respondeu na porta $DEBUG_PORT. Abra-o manualmente primeiro."
    fi
    rm -f "$readiness"

    create_run_directory
    write_metadata

    printf '\nJogo detectado na porta %s.\n' "$DEBUG_PORT"
    printf 'Mantenha Guile x Hokuto no cenário da Hokuto, no início da luta, sem inputs.\n'
    collect_before

    local started_epoch
    local finished_epoch
    local measured_seconds
    started_epoch="$(date +%s)"
    printf '\nBEFORE concluído. Jogue a luta completa normalmente.\n'
    read -r -p 'No replay/final da luta, pare os inputs e pressione Enter para coletar AFTER... ' _
    finished_epoch="$(date +%s)"
    measured_seconds=$((finished_epoch - started_epoch))
    printf '{"seconds":%d}\n' "$measured_seconds" >"$RUN_DIR/duration.json"
    printf 'measured_seconds=%d\n' "$measured_seconds" >>"$RUN_DIR/metadata.txt"

    collect_after "$measured_seconds"
    write_summary

    note "Coleta concluída: $RUN_DIR"
    printf 'Resumo: %s/summary.md\n' "$RUN_DIR"
    printf 'O script NÃO fechará o jogo. Feche-o manualmente quando desejar.\n'
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
    validate_environment
    collect_telemetry
}

main "$@"
