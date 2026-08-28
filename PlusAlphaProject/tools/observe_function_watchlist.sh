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
readonly POLL_SECONDS=1

PYTHON_BIN=""
DEBUG_PORT=""
CAMPAIGN_DIR=""
CURRENT_SCENARIO_DIR=""
CURRENT_SCENARIO_ACTIVE=0
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
Uso, sempre no MSYS2 UCRT64, com a build S1-253 de telemetria aberta:

  bash tools/observe_function_watchlist.sh

O script carrega seeds/function_watchlist.txt uma vez e conduz varias janelas
de gameplay na mesma execucao do jogo. Para cada confronto, informe um nome
curto como ken-ryu ou skullo-ddark. Pressione ENTER no inicio do gameplay e
novamente ao terminar a janela. Digite fim para encerrar a campanha.

O segundo nome deve representar o personagem que determinou o cenario. Use
tokens simples, sem espacos: ddark, skullo, evilhokuto etc.

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
        (( (value & 3) == 0 )) || fail "Endereco nao alinhado na watchlist: $token"
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
    command -v sha256sum >/dev/null || fail "sha256sum nao encontrado no UCRT64."
    [[ -f "$GAME_TOML" ]] || fail "game.toml ausente: $GAME_TOML"
    [[ -f "$RAW_TCP" ]] || fail "Cliente TCP ausente: $RAW_TCP"
    [[ -f "$WATCHLIST" ]] || fail "Watchlist ausente: $WATCHLIST"
    [[ -f "$RANGES_FILE" ]] || fail "Manifesto gerado ausente: $RANGES_FILE"
    [[ -f "$RUNTIME_EXE" ]] ||
        fail "Build S1-253 ausente. Recompile antes de iniciar o observador."
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
        fail "Comando rejeitado pelo runtime: $* (veja $output)"
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
start_marker = "=== raw bytes"
end_marker = "=== json parse attempt ==="
start = text.find(start_marker)
if start < 0:
    raise SystemExit(f"marcador raw ausente em {raw_path}")
start = text.find("\n", start)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit(f"resposta truncada em {raw_path}")
payload = json.loads(text[start + 1:end].strip())
json_path.write_text(
    json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
}

json_integer() {
    local path="$1"
    local field="$2"
    "$PYTHON_BIN" - "$path" "$field" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(int(payload.get(sys.argv[2], 0) or 0))
PY
}

snapshot_rows() {
    local path="$1"
    "$PYTHON_BIN" - "$path" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for row in payload.get("entries", []):
    print("\t".join(str(row.get(key, 0)) for key in (
        "target", "hits", "native_hits", "interpreted_hits",
        "first_frame", "last_frame",
    )))
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
    local ranges_sha runtime_sha watchlist_sha
    ranges_sha="$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')"
    runtime_sha="$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')"
    watchlist_sha="$(sha256sum "$WATCHLIST" | awk '{print toupper($1)}')"
    {
        printf 'campaign=%s\n' "$(basename "$CAMPAIGN_DIR")"
        printf 'lot=S1-%s\n' "$LOT_NUMBER"
        printf 'runtime_build=%s\n' "$(basename "$BUILD_DIR")"
        printf 'runtime_exe_sha256=%s\n' "$runtime_sha"
        printf 'ranges_sha256=%s\n' "$ranges_sha"
        printf 'generated_functions=%s\n' "$EXPECTED_FUNCTIONS"
        printf 'watchlist=%s\n' "$WATCHLIST"
        printf 'watchlist_sha256=%s\n' "$watchlist_sha"
        printf 'watchlist_targets=%s\n' "${#TARGETS[@]}"
        printf 'debug_port=%s\n' "$DEBUG_PORT"
        printf 'poll_seconds=%s\n' "$POLL_SECONDS"
        printf 'game_launch=manual\n'
        printf 'game_shutdown=manual\n'
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$CAMPAIGN_DIR/metadata.txt"
}

arm_watchlist() {
    note "Carregando ${#TARGETS[@]} funcoes no observador multi-PC"
    raw_command "$CAMPAIGN_DIR/startup_pc_watch_clear.log" pc_watch_clear
    local target suffix
    for target in "${TARGETS[@]}"; do
        suffix="${target#0x}"
        raw_command "$CAMPAIGN_DIR/startup_pc_watch_arm_${suffix}.log" \
            pc_watch_arm target="$target"
    done
    raw_command "$CAMPAIGN_DIR/startup_pc_watch_dump.raw.log" pc_watch_dump
    extract_json "$CAMPAIGN_DIR/startup_pc_watch_dump.raw.log" \
        "$CAMPAIGN_DIR/startup_pc_watch_dump.json"
    local actual
    actual="$(json_integer "$CAMPAIGN_DIR/startup_pc_watch_dump.json" count)"
    [[ "$actual" == "${#TARGETS[@]}" ]] ||
        fail "Runtime armou $actual funcoes; esperado=${#TARGETS[@]}."
}

write_scenario_result() {
    local scenario_dir="$1"
    local scenario_id="$2"
    local started_epoch="$3"
    local ended_epoch="$4"
    "$PYTHON_BIN" - "$scenario_dir" "$scenario_id" \
        "$started_epoch" "$ended_epoch" <<'PY'
import csv
import json
import pathlib
import sys

scenario = pathlib.Path(sys.argv[1])
scenario_id = sys.argv[2]
started = int(sys.argv[3])
ended = int(sys.argv[4])
payload = json.loads((scenario / "final_pc_watch_dump.json").read_text(encoding="utf-8"))
entries = payload.get("entries", [])
observed = [row for row in entries if int(row.get("hits", 0) or 0) > 0]

with (scenario / "hits.csv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle)
    writer.writerow([
        "target", "hits", "native_hits", "interpreted_hits",
        "first_frame", "last_frame", "observed",
    ])
    for row in entries:
        hits = int(row.get("hits", 0) or 0)
        writer.writerow([
            row.get("target", ""), hits,
            int(row.get("native_hits", 0) or 0),
            int(row.get("interpreted_hits", 0) or 0),
            int(row.get("first_frame", 0) or 0),
            int(row.get("last_frame", 0) or 0),
            "yes" if hits else "no",
        ])

result = {
    "scenario_id": scenario_id,
    "directory": scenario.name,
    "started_epoch": started,
    "ended_epoch": ended,
    "duration_seconds": max(0, ended - started),
    "watch_count": len(entries),
    "observed_count": len(observed),
    "total_hits": sum(int(row.get("hits", 0) or 0) for row in entries),
    "entries": entries,
}
(scenario / "result.json").write_text(
    json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
(scenario / "duration.json").write_text(
    json.dumps({"seconds": result["duration_seconds"]}, sort_keys=True) + "\n",
    encoding="utf-8",
)

lines = [
    f"# Alcance em gameplay: {scenario_id}", "",
    f"- Duracao observada: {result['duration_seconds']} s",
    f"- Funcoes observadas: {len(observed)}/{len(entries)}",
    f"- Hits totais: {result['total_hits']}",
    "- Segundo token do identificador: personagem que determinou o cenario.",
    "",
    "| Funcao | Hits | Nativos | Interpretados | Primeiro frame | Ultimo frame |",
    "|---|---:|---:|---:|---:|---:|",
]
for row in entries:
    lines.append(
        f"| `{row.get('target', '')}` | {int(row.get('hits', 0) or 0)} | "
        f"{int(row.get('native_hits', 0) or 0)} | "
        f"{int(row.get('interpreted_hits', 0) or 0)} | "
        f"{int(row.get('first_frame', 0) or 0) or '-'} | "
        f"{int(row.get('last_frame', 0) or 0) or '-'} |"
    )
if not observed:
    lines.extend(["", "**Nenhuma funcao da watchlist foi observada nesta rota.**"])
lines.extend(["", "Esta coleta mede alcance; ela nao promove nenhuma seed.", ""])
(scenario / "summary.md").write_text("\n".join(lines), encoding="utf-8")
PY
}

update_campaign_summary() {
    "$PYTHON_BIN" - "$CAMPAIGN_DIR" <<'PY'
import csv
import json
import pathlib
import sys

campaign = pathlib.Path(sys.argv[1])
results = []
for path in sorted(campaign.glob("*/result.json")):
    try:
        results.append(json.loads(path.read_text(encoding="utf-8")))
    except Exception:
        continue
if not results:
    (campaign / "scenario-matrix.csv").write_text(
        "target,total_hits,native_hits,interpreted_hits\n", encoding="utf-8"
    )
    (campaign / "campaign-summary.md").write_text(
        f"# Campanha {campaign.name}\n\n"
        "Nenhum confronto foi concluido nesta campanha.\n",
        encoding="utf-8",
    )
    raise SystemExit(0)

targets = [str(row.get("target", "")) for row in results[0].get("entries", [])]
scenario_ids = [str(result.get("scenario_id", "")) for result in results]
matrix = {target: {} for target in targets}
mode_totals = {target: {"native": 0, "interpreted": 0} for target in targets}
for result in results:
    scenario_id = str(result.get("scenario_id", ""))
    by_target = {str(row.get("target", "")): row for row in result.get("entries", [])}
    for target in targets:
        row = by_target.get(target, {})
        matrix[target][scenario_id] = int(row.get("hits", 0) or 0)
        mode_totals[target]["native"] += int(row.get("native_hits", 0) or 0)
        mode_totals[target]["interpreted"] += int(row.get("interpreted_hits", 0) or 0)

with (campaign / "scenario-matrix.csv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle)
    writer.writerow(["target", *scenario_ids, "total_hits", "native_hits", "interpreted_hits"])
    for target in targets:
        values = [matrix[target].get(scenario, 0) for scenario in scenario_ids]
        writer.writerow([
            target, *values, sum(values),
            mode_totals[target]["native"], mode_totals[target]["interpreted"],
        ])

lines = [
    f"# Campanha {campaign.name}", "",
    f"- Cenarios concluidos: {len(results)}",
    f"- Funcoes na watchlist: {len(targets)}",
    "- A matriz completa esta em `scenario-matrix.csv`.", "",
    "## Cobertura por cenario", "",
    "| Cenario | Duracao | Funcoes encontradas | Hits totais |",
    "|---|---:|---:|---:|",
]
for result in results:
    lines.append(
        f"| `{result.get('scenario_id', '')}` | {int(result.get('duration_seconds', 0))} s | "
        f"{int(result.get('observed_count', 0))}/{int(result.get('watch_count', 0))} | "
        f"{int(result.get('total_hits', 0))} |"
    )

lines.extend([
    "", "## Melhor rota observada por funcao", "",
    "| Funcao | Cenarios com hit | Melhor cenario | Hits nessa rota | Hits totais | Execucao |",
    "|---|---:|---|---:|---:|---|",
])
for target in targets:
    rows = matrix[target]
    active = [(scenario, hits) for scenario, hits in rows.items() if hits > 0]
    best_scenario, best_hits = max(active, key=lambda item: item[1]) if active else ("-", 0)
    native = mode_totals[target]["native"]
    interpreted = mode_totals[target]["interpreted"]
    if native and interpreted:
        mode = "nativa + interpretada"
    elif native:
        mode = "nativa"
    elif interpreted:
        mode = "interpretada"
    else:
        mode = "nao observada"
    lines.append(
        f"| `{target}` | {len(active)} | `{best_scenario}` | {best_hits} | "
        f"{sum(rows.values())} | {mode} |"
    )
lines.extend(["", "Esta campanha apenas localiza rotas; nenhuma funcao e promovida automaticamente.", ""])
(campaign / "campaign-summary.md").write_text("\n".join(lines), encoding="utf-8")
PY
}

poll_and_announce() {
    local scenario_dir="$1"
    local -n announced_ref="$2"
    raw_command "$scenario_dir/poll_latest.raw.log" pc_watch_dump
    extract_json "$scenario_dir/poll_latest.raw.log" "$scenario_dir/poll_latest.json"

    local target hits native_hits interpreted_hits first_frame last_frame mode message now
    while IFS=$'\t' read -r target hits native_hits interpreted_hits first_frame last_frame; do
        ((hits > 0)) || continue
        [[ -z "${announced_ref[$target]:-}" ]] || continue
        if ((native_hits > 0 && interpreted_hits > 0)); then
            mode="nativa+interpretada"
        elif ((native_hits > 0)); then
            mode="nativa"
        else
            mode="interpretada"
        fi
        message="[ENCONTRADA] $target — hits=$hits; modo=$mode; primeiro_frame=$first_frame"
        printf '%s\n' "$message"
        printf '%s\n' "$message" >>"$scenario_dir/live.log"
        now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '{"event":"first_observed","utc":"%s","target":"%s","hits_at_poll":%s,"native_hits":%s,"interpreted_hits":%s,"first_frame":%s}\n' \
            "$now" "$target" "$hits" "$native_hits" "$interpreted_hits" "$first_frame" \
            >>"$scenario_dir/events.jsonl"
        announced_ref[$target]=1
    done < <(snapshot_rows "$scenario_dir/poll_latest.json")
}

run_scenario() {
    local scenario_id="$1"
    local scenario_dir started_epoch ended_epoch observed
    scenario_dir="$(make_unique_directory "$CAMPAIGN_DIR" "${LOT_NUMBER}-${scenario_id}")"
    CURRENT_SCENARIO_DIR="$scenario_dir"
    : >"$scenario_dir/live.log"
    : >"$scenario_dir/events.jsonl"

    printf '\nCenario: %s\n' "$scenario_id"
    printf 'Posicione a luta no primeiro frame controlavel do gameplay.\n'
    read -r -p 'Pressione ENTER para iniciar esta janela... ' _

    raw_command "$scenario_dir/start_pc_watch_reset.log" pc_watch_reset
    raw_command "$scenario_dir/start_pc_watch_dump.raw.log" pc_watch_dump
    extract_json "$scenario_dir/start_pc_watch_dump.raw.log" \
        "$scenario_dir/start_pc_watch_dump.json"
    started_epoch="$(date +%s)"
    {
        printf 'scenario_id=%s\n' "$scenario_id"
        printf 'stage_owner=second_character_in_scenario_id\n'
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'campaign=%s\n' "$(basename "$CAMPAIGN_DIR")"
        printf 'watchlist_targets=%s\n' "${#TARGETS[@]}"
    } >"$scenario_dir/metadata.txt"
    CURRENT_SCENARIO_ACTIVE=1

    printf '\n[OBSERVANDO] %s — pressione ENTER para encerrar esta janela.\n' "$scenario_id"
    declare -A announced=()
    while true; do
        if read -r -t "$POLL_SECONDS" _; then
            break
        fi
        poll_and_announce "$scenario_dir" announced
    done

    raw_command "$scenario_dir/stop_pc_watch.log" pc_watch_stop
    raw_command "$scenario_dir/final_pc_watch_dump.raw.log" pc_watch_dump
    extract_json "$scenario_dir/final_pc_watch_dump.raw.log" \
        "$scenario_dir/final_pc_watch_dump.json"
    CURRENT_SCENARIO_ACTIVE=0
    ended_epoch="$(date +%s)"
    {
        printf 'ended_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'duration_seconds=%s\n' "$((ended_epoch - started_epoch))"
    } >>"$scenario_dir/metadata.txt"

    write_scenario_result "$scenario_dir" "$scenario_id" "$started_epoch" "$ended_epoch"
    update_campaign_summary
    observed="$(json_integer "$scenario_dir/result.json" observed_count)"
    if ((observed > 0)); then
        printf '[CONCLUIDO] %s — %s/%s funcoes encontradas.\n' \
            "$(basename "$scenario_dir")" "$observed" "${#TARGETS[@]}"
    else
        printf '[SEM HITS] %s — nenhuma das %s funcoes apareceu.\n' \
            "$(basename "$scenario_dir")" "${#TARGETS[@]}"
    fi
    printf 'Resumo: %s\n' "$scenario_dir/summary.md"
    CURRENT_SCENARIO_DIR=""
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if ((CURRENT_SCENARIO_ACTIVE)) && [[ -n "$CURRENT_SCENARIO_DIR" ]]; then
        printf '\nColeta interrompida; congelando contadores em %s\n' "$CURRENT_SCENARIO_DIR" >&2
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" pc_watch_stop \
            >"$CURRENT_SCENARIO_DIR/interrupted_pc_watch_stop.log" 2>&1 || true
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" pc_watch_dump \
            >"$CURRENT_SCENARIO_DIR/interrupted_pc_watch_dump.raw.log" 2>&1 || true
        printf 'interrupted_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            >"$CURRENT_SCENARIO_DIR/interrupted.txt"
    fi
    if ((CAMPAIGN_READY)); then
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
        "s1-${LOT_NUMBER}-function-watch")"
    write_campaign_metadata
    trap cleanup EXIT
    trap 'exit 130' INT TERM

    raw_command "$CAMPAIGN_DIR/runtime_pc_watch_probe.raw.log" pc_watch_dump
    extract_json "$CAMPAIGN_DIR/runtime_pc_watch_probe.raw.log" \
        "$CAMPAIGN_DIR/runtime_pc_watch_probe.json"
    CAMPAIGN_READY=1

    # Evita que instrumentacao de uma coleta antiga interfira no frametime.
    raw_command "$CAMPAIGN_DIR/startup_fntrace_clear.log" fntrace_arm_clear
    raw_command "$CAMPAIGN_DIR/startup_cyc_watch_clear.log" cyc_watch_clear
    raw_command "$CAMPAIGN_DIR/startup_fn_disable.log" fn_disable
    arm_watchlist

    printf '\nObservador pronto. O jogo continuara aberto durante toda a campanha.\n'
    printf 'Informe confrontos como ken-ryu ou skullo-ddark; digite fim ao terminar.\n'

    local scenario_id
    while true; do
        printf '\n'
        read -r -p 'Identificador do confronto: ' scenario_id
        scenario_id="${scenario_id,,}"
        if [[ "$scenario_id" == "fim" ]]; then
            break
        fi
        [[ "$scenario_id" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || {
            printf 'Identificador invalido. Use apenas a-z, 0-9, ponto, _ ou hifen.\n' >&2
            continue
        }
        run_scenario "$scenario_id"
    done

    update_campaign_summary
    raw_command "$CAMPAIGN_DIR/final_pc_watch_clear.log" pc_watch_clear
    CAMPAIGN_READY=0
    printf '\nCampanha encerrada. O jogo nao foi fechado.\n'
    printf 'Resumo consolidado: %s\n' "$CAMPAIGN_DIR/campaign-summary.md"
    printf 'Matriz CSV: %s\n' "$CAMPAIGN_DIR/scenario-matrix.csv"
}

main "$@"
