#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly WATCHLIST="$PROJECT_ROOT/seeds/function_watchlist.txt"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-253-tele"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly EXPECTED_RANGES_SHA="80DF7E6811A60B300CD5371818A2504FB571EB806B5FC755BD470A4582077068"
readonly EXPECTED_FUNCTIONS=1045
readonly LOT_NUMBER=253
readonly WATCH_CAPACITY=128
readonly SAMPLE_INTERVAL_MS=100
readonly MAX_WINDOW_SECONDS=900

PYTHON_BIN=""
DEBUG_PORT=""
CAMPAIGN_DIR=""
CURRENT_WINDOW_DIR=""
CURRENT_WINDOW_ACTIVE=0
CAMPAIGN_READY=0
declare -a TARGETS=()

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

note() {
    printf '\n==> %s\n' "$*"
}

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com a build S1-253 de telemetria aberta:

  bash tools/observe_function_watchlist_timer.sh

Informe uma tag, pressione ENTER para iniciar a rota e ENTER novamente para
encerrar. Durante a rota o script nao consulta o jogo. Digite fim para sair.

Exemplo de tag: expert-mode-complete-timer

Este script nao gera fontes, nao compila, nao abre e nao fecha o jogo.
EOF
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

load_watchlist() {
    local token normalized value
    declare -A seen=()
    while IFS= read -r token; do
        [[ "$token" =~ ^0[xX][0-9A-Fa-f]{8}$ ]] ||
            fail "Endereco invalido em function_watchlist.txt: $token"
        value=$((token))
        (( (value & 3) == 0 )) || fail "Endereco nao alinhado: $token"
        (( value >= 0x80101000 && value < 0x801C0000 )) ||
            fail "Endereco fora do texto conhecido do jogo: $token"
        printf -v normalized '0x%08X' "$value"
        [[ -z "${seen[$normalized]:-}" ]] ||
            fail "Endereco duplicado na watchlist: $normalized"
        seen[$normalized]=1
        TARGETS+=("$normalized")
    done < <(awk '{ sub(/#.*/, ""); if ($1 != "") print $1 }' "$WATCHLIST")

    ((${#TARGETS[@]} > 0)) || fail "A watchlist esta vazia."
    ((${#TARGETS[@]} <= WATCH_CAPACITY)) ||
        fail "A watchlist possui ${#TARGETS[@]} funcoes; limite=$WATCH_CAPACITY."
}

validate_environment() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] ||
        fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v sha256sum >/dev/null || fail "sha256sum nao encontrado."
    [[ -f "$GAME_TOML" ]] || fail "game.toml ausente: $GAME_TOML"
    [[ -f "$RAW_TCP" ]] || fail "Cliente TCP ausente: $RAW_TCP"
    [[ -f "$WATCHLIST" ]] || fail "Watchlist ausente: $WATCHLIST"
    [[ -f "$RANGES_FILE" ]] || fail "Manifesto ausente: $RANGES_FILE"
    [[ -f "$RUNTIME_EXE" ]] ||
        fail "Build S1-253 ausente. Recompile-a antes deste observador."
    [[ -f "$CMAKE_CACHE" ]] || fail "CMakeCache ausente na build S1-253."

    local ranges_sha function_count
    ranges_sha="$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')"
    [[ "$ranges_sha" == "$EXPECTED_RANGES_SHA" ]] ||
        fail "Manifesto nao corresponde ao S1-253: $ranges_sha"
    function_count="$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")"
    [[ "$function_count" == "$EXPECTED_FUNCTIONS" ]] ||
        fail "Manifesto possui $function_count funcoes; esperado=$EXPECTED_FUNCTIONS."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" ||
        fail "A build nao usa RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" ||
        fail "A build nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" ||
        fail "A build nao possui PSX_STATIC_RUNTIME=ON."

    select_python
    read_debug_port
    load_watchlist
}

raw_command() {
    local output="$1"
    shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 ||
        fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" ||
        fail "Comando rejeitado: $* (veja $output)"
}

# O dump pode ter varios megabytes. Esta leitura usa chunks e timeout longo,
# evitando a concatenacao byte a byte do cliente de diagnostico generico.
timer_dump_to_json() {
    local output="$1"
    "$PYTHON_BIN" - "$DEBUG_PORT" "$output" <<'PY'
import json
import pathlib
import socket
import sys

port = int(sys.argv[1])
output = pathlib.Path(sys.argv[2])
request = json.dumps({"id": 1, "cmd": "pc_watch_timer_dump"}) + "\n"
chunks = []
with socket.create_connection(("127.0.0.1", port), timeout=5.0) as sock:
    sock.settimeout(40.0)
    sock.sendall(request.encode("utf-8"))
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        chunks.append(chunk)
payload = json.loads(b"".join(chunks).decode("utf-8"))
if not payload.get("ok"):
    raise SystemExit(f"runtime rejeitou pc_watch_timer_dump: {payload}")
output.write_text(
    json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
}

extract_json() {
    local raw_path="$1"
    local json_path="$2"
    "$PYTHON_BIN" - "$raw_path" "$json_path" <<'PY'
import json
import pathlib
import sys

raw_path = pathlib.Path(sys.argv[1])
json_path = pathlib.Path(sys.argv[2])
text = raw_path.read_text(encoding="utf-8", errors="replace")
start = text.find("=== raw bytes")
start = text.find("\n", start)
end = text.find("=== json parse attempt ===", start)
if start < 0 or end < 0:
    raise SystemExit(f"resposta truncada em {raw_path}")
payload = json.loads(text[start + 1:end].strip())
json_path.write_text(
    json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
}

make_unique_directory() {
    local parent="$1"
    local base="$2"
    local candidate suffix
    for suffix in $(seq -w 1 99); do
        candidate="$parent/${base}-${suffix}"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            printf '%s\n' "$candidate"
            return
        fi
    done
    fail "Nao ha identificador livre para ${base}-01..99."
}

write_campaign_metadata() {
    {
        printf 'campaign=%s\n' "$(basename "$CAMPAIGN_DIR")"
        printf 'lot=S1-%s\n' "$LOT_NUMBER"
        printf 'runtime_build=%s\n' "$(basename "$BUILD_DIR")"
        printf 'runtime_exe_sha256=%s\n' \
            "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')"
        printf 'ranges_sha256=%s\n' "$EXPECTED_RANGES_SHA"
        printf 'generated_functions=%s\n' "$EXPECTED_FUNCTIONS"
        printf 'watchlist_sha256=%s\n' \
            "$(sha256sum "$WATCHLIST" | awk '{print toupper($1)}')"
        printf 'watchlist_targets=%s\n' "${#TARGETS[@]}"
        printf 'sample_interval_ms=%s\n' "$SAMPLE_INTERVAL_MS"
        printf 'max_window_seconds=%s\n' "$MAX_WINDOW_SECONDS"
        printf 'debug_port=%s\n' "$DEBUG_PORT"
        printf 'game_launch=manual\n'
        printf 'game_shutdown=manual\n'
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$CAMPAIGN_DIR/metadata.txt"
}

arm_watchlist() {
    note "Carregando ${#TARGETS[@]} funcoes"
    raw_command "$CAMPAIGN_DIR/startup_pc_watch_clear.log" pc_watch_clear
    local target suffix
    for target in "${TARGETS[@]}"; do
        suffix="${target#0x}"
        raw_command "$CAMPAIGN_DIR/startup_pc_watch_arm_${suffix}.log" \
            pc_watch_arm target="$target"
    done
}

write_window_result() {
    local window_dir="$1"
    local window_id="$2"
    "$PYTHON_BIN" - "$window_dir" "$window_id" <<'PY'
import csv
import json
import pathlib
import sys

directory = pathlib.Path(sys.argv[1])
window_id = sys.argv[2]
timer = json.loads((directory / "timer_dump.json").read_text(encoding="utf-8"))
aggregate = json.loads((directory / "aggregate.json").read_text(encoding="utf-8"))
targets = [str(value) for value in timer.get("targets", [])]
samples = timer.get("samples", [])
entries = {str(row.get("target")): row for row in aggregate.get("entries", [])}
if not samples:
    raise SystemExit("timeline sem amostras")

first_host = int(samples[0].get("host_ms", 0))
columns = [
    "sample", "elapsed_ms", "delta_ms", "frame", "delta_frames",
    "estimated_fps", "cycle", "delta_cycles", "total_hits", "delta_hits",
]
for target in targets:
    suffix = target.lower().removeprefix("0x")
    columns.extend([f"hits_{suffix}", f"delta_{suffix}"])

rows = []
previous = None
longest_zero_ms = 0
current_zero_ms = 0
slow_intervals = 0
peak_delta_hits = 0
for sample in samples:
    host = int(sample.get("host_ms", 0))
    frame = int(sample.get("frame", 0))
    cycle = int(sample.get("cycle", 0))
    hits = [int(value) for value in sample.get("hits", [])]
    if len(hits) != len(targets):
        raise SystemExit("numero de hits diferente do numero de targets")
    if previous is None:
        delta_ms = delta_frames = delta_cycles = delta_hits = 0
        hit_deltas = [0] * len(hits)
        fps = 0.0
    else:
        delta_ms = max(0, host - previous["host"])
        delta_frames = max(0, frame - previous["frame"])
        delta_cycles = max(0, cycle - previous["cycle"])
        hit_deltas = [max(0, value - old) for value, old in zip(hits, previous["hits"])]
        delta_hits = sum(hit_deltas)
        fps = (delta_frames * 1000.0 / delta_ms) if delta_ms else 0.0
        if delta_frames == 0:
            current_zero_ms += delta_ms
            longest_zero_ms = max(longest_zero_ms, current_zero_ms)
        else:
            current_zero_ms = 0
        if delta_ms and fps < 30.0:
            slow_intervals += 1
        peak_delta_hits = max(peak_delta_hits, delta_hits)
    row = [
        int(sample.get("sample", len(rows))), host - first_host, delta_ms,
        frame, delta_frames, f"{fps:.3f}", cycle, delta_cycles,
        sum(hits), delta_hits,
    ]
    for value, delta in zip(hits, hit_deltas):
        row.extend([value, delta])
    rows.append(row)
    previous = {"host": host, "frame": frame, "cycle": cycle, "hits": hits}

with (directory / "timeline.csv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle)
    writer.writerow(columns)
    writer.writerows(rows)

with (directory / "hits.csv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle)
    writer.writerow(["target", "hits", "native_hits", "interpreted_hits"])
    for target in targets:
        row = entries.get(target, {})
        writer.writerow([
            target, int(row.get("hits", 0) or 0),
            int(row.get("native_hits", 0) or 0),
            int(row.get("interpreted_hits", 0) or 0),
        ])

duration_ms = max(0, int(samples[-1].get("host_ms", 0)) - first_host)
frame_delta = max(0, int(samples[-1].get("frame", 0)) - int(samples[0].get("frame", 0)))
total_hits = sum(int(value) for value in samples[-1].get("hits", []))
observed = sum(1 for value in samples[-1].get("hits", []) if int(value) > 0)
result = {
    "window_id": window_id,
    "directory": directory.name,
    "duration_ms": duration_ms,
    "frame_delta": frame_delta,
    "sample_count": len(samples),
    "sample_interval_ms": int(timer.get("interval_ms", 0) or 0),
    "saturated": bool(timer.get("saturated", False)),
    "longest_zero_frame_ms": longest_zero_ms,
    "slow_intervals_below_30_fps": slow_intervals,
    "peak_hits_in_one_interval": peak_delta_hits,
    "observed_count": observed,
    "target_count": len(targets),
    "total_hits": total_hits,
}
(directory / "result.json").write_text(
    json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

lines = [
    f"# Timeline: {window_id}", "",
    f"- Duracao: {duration_ms / 1000.0:.3f} s",
    f"- Frames avancados: {frame_delta}",
    f"- Amostras: {len(samples)} a cada {result['sample_interval_ms']} ms",
    f"- Funcoes encontradas: {observed}/{len(targets)}",
    f"- Hits totais: {total_hits}",
    f"- Maior periodo amostrado sem novo frame: {longest_zero_ms} ms",
    f"- Intervalos abaixo de 30 FPS: {slow_intervals}",
    f"- Maior delta de hits em um intervalo: {peak_delta_hits}",
    f"- Buffer saturado: {'SIM' if result['saturated'] else 'nao'}", "",
    "| Funcao | Hits | Nativos | Interpretados |", "|---|---:|---:|---:|",
]
for target in targets:
    row = entries.get(target, {})
    lines.append(
        f"| `{target}` | {int(row.get('hits', 0) or 0)} | "
        f"{int(row.get('native_hits', 0) or 0)} | "
        f"{int(row.get('interpreted_hits', 0) or 0)} |"
    )
lines.extend([
    "", "A serie completa, com deltas por funcao, esta em `timeline.csv`.",
    "A coleta nao consultou TCP nem gravou em disco durante a janela.", "",
])
(directory / "summary.md").write_text("\n".join(lines), encoding="utf-8")
PY
}

update_campaign_summary() {
    "$PYTHON_BIN" - "$CAMPAIGN_DIR" <<'PY'
import json
import pathlib
import sys

campaign = pathlib.Path(sys.argv[1])
results = []
for path in sorted(campaign.glob("*/result.json")):
    results.append(json.loads(path.read_text(encoding="utf-8")))
lines = [
    f"# Campanha temporizada {campaign.name}", "",
    "| Janela | Duracao | Frames | Funcoes | Hits | Maior pausa de frame | Saturou |",
    "|---|---:|---:|---:|---:|---:|---|",
]
for result in results:
    lines.append(
        f"| `{result['window_id']}` | {result['duration_ms'] / 1000.0:.3f} s | "
        f"{result['frame_delta']} | {result['observed_count']}/{result['target_count']} | "
        f"{result['total_hits']} | {result['longest_zero_frame_ms']} ms | "
        f"{'SIM' if result['saturated'] else 'nao'} |"
    )
if not results:
    lines.extend(["", "Nenhuma janela foi concluida."])
lines.append("")
(campaign / "campaign-summary.md").write_text("\n".join(lines), encoding="utf-8")
PY
}

run_window() {
    local window_id="$1"
    local window_dir
    window_dir="$(make_unique_directory "$CAMPAIGN_DIR" "${LOT_NUMBER}-${window_id}")"
    CURRENT_WINDOW_DIR="$window_dir"
    {
        printf 'window_id=%s\n' "$window_id"
        printf 'campaign=%s\n' "$(basename "$CAMPAIGN_DIR")"
        printf 'sample_interval_ms=%s\n' "$SAMPLE_INTERVAL_MS"
        printf 'max_window_seconds=%s\n' "$MAX_WINDOW_SECONDS"
    } >"$window_dir/metadata.txt"

    printf '\nJanela: %s\n' "$window_id"
    printf 'Posicione o jogo exatamente no inicio da rota.\n'
    read -r -p 'Pressione ENTER para iniciar... ' _

    printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        >>"$window_dir/metadata.txt"
    raw_command "$window_dir/timer_start.log" pc_watch_timer_start \
        interval_ms="$SAMPLE_INTERVAL_MS" max_seconds="$MAX_WINDOW_SECONDS"
    CURRENT_WINDOW_ACTIVE=1
    printf '\n[GRAVANDO EM MEMORIA] %s\n' "$window_id"
    printf 'Nao ha consultas TCP durante esta janela.\n'
    read -r -p 'Pressione ENTER para encerrar... ' _

    raw_command "$window_dir/timer_stop.log" pc_watch_timer_stop
    CURRENT_WINDOW_ACTIVE=0
    note "Transferindo a timeline depois da janela"
    timer_dump_to_json "$window_dir/timer_dump.json"
    raw_command "$window_dir/aggregate.raw.log" pc_watch_dump
    extract_json "$window_dir/aggregate.raw.log" "$window_dir/aggregate.json"
    printf 'ended_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        >>"$window_dir/metadata.txt"
    write_window_result "$window_dir" "$window_id"
    update_campaign_summary
    raw_command "$window_dir/timer_clear.log" pc_watch_timer_clear
    printf '[CONCLUIDO] %s\n' "$(basename "$window_dir")"
    printf 'Resumo: %s\n' "$window_dir/summary.md"
    CURRENT_WINDOW_DIR=""
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if ((CURRENT_WINDOW_ACTIVE)) && [[ -n "$CURRENT_WINDOW_DIR" ]]; then
        printf '\nColeta interrompida; parando o timer.\n' >&2
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" pc_watch_timer_stop \
            >"$CURRENT_WINDOW_DIR/interrupted_timer_stop.log" 2>&1 || true
    fi
    if ((CAMPAIGN_READY)); then
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" pc_watch_timer_clear \
            >"$CAMPAIGN_DIR/exit_timer_clear.log" 2>&1 || true
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" pc_watch_clear \
            >"$CAMPAIGN_DIR/exit_pc_watch_clear.log" 2>&1 || true
    fi
    exit "$status"
}

main() {
    case "${1:-}" in
        '') ;;
        -h|--help) usage; return ;;
        *) usage; fail "Argumento desconhecido: $1" ;;
    esac

    validate_environment
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    CAMPAIGN_DIR="$(make_unique_directory "$PROJECT_ROOT/local/telemetry" \
        "s1-${LOT_NUMBER}-function-watch-timer")"
    write_campaign_metadata
    trap cleanup EXIT
    trap 'exit 130' INT TERM

    raw_command "$CAMPAIGN_DIR/runtime_timer_probe.log" pc_watch_timer_state
    CAMPAIGN_READY=1
    raw_command "$CAMPAIGN_DIR/startup_fntrace_clear.log" fntrace_arm_clear
    raw_command "$CAMPAIGN_DIR/startup_cyc_watch_clear.log" cyc_watch_clear
    raw_command "$CAMPAIGN_DIR/startup_fn_disable.log" fn_disable
    arm_watchlist

    printf '\nObservador temporizado pronto.\n'
    printf 'Digite uma tag para cada rota ou fim para encerrar.\n'
    local window_id
    while true; do
        printf '\n'
        read -r -p 'Tag da rota: ' window_id
        window_id="${window_id,,}"
        [[ "$window_id" == "fim" ]] && break
        [[ "$window_id" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || {
            printf 'Tag invalida. Use a-z, 0-9, ponto, _ ou hifen.\n' >&2
            continue
        }
        run_window "$window_id"
    done

    update_campaign_summary
    raw_command "$CAMPAIGN_DIR/final_timer_clear.log" pc_watch_timer_clear
    raw_command "$CAMPAIGN_DIR/final_pc_watch_clear.log" pc_watch_clear
    CAMPAIGN_READY=0
    printf '\nCampanha encerrada; o jogo continua aberto.\n'
    printf 'Resumo: %s\n' "$CAMPAIGN_DIR/campaign-summary.md"
}

main "$@"
