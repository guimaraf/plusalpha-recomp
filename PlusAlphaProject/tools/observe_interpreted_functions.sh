#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-256-tele"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly EXPECTED_RANGES_SHA="300F1B44336410C0F0DADAF746D2973D27ABCCF4EB391A36891D827DA67057C6"
readonly EXPECTED_RUNTIME_SHA="B1F9A157E90EEE2A5E0A50ACF3AA24185B4C4B3236F4D94AE7E656ADCC9F0B20"
readonly EXPECTED_FUNCTIONS=1055
readonly LOT_NUMBER=256
readonly POLL_SECONDS="${DISCOVERY_POLL_SECONDS:-1}"
readonly OVERLAY_POLL_SECONDS="${DISCOVERY_OVERLAY_POLL_SECONDS:-5}"

PYTHON_BIN=""
DEBUG_PORT=""
CAMPAIGN_DIR=""
CURRENT_WINDOW_DIR=""
COLLECTOR_PID=""

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

note() {
    printf '\n==> %s\n' "$*"
}

stop_active_collector() {
    if [[ -n "$COLLECTOR_PID" ]] && kill -0 "$COLLECTOR_PID" 2>/dev/null; then
        if [[ -n "$CURRENT_WINDOW_DIR" ]]; then
            : >"$CURRENT_WINDOW_DIR/stop.requested"
        fi
        wait "$COLLECTOR_PID" 2>/dev/null || true
    fi
    COLLECTOR_PID=""
    CURRENT_WINDOW_DIR=""
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    stop_active_collector
    exit "$status"
}

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com a build S1-256 de telemetria aberta:

  bash tools/observe_interpreted_functions.sh

Digite uma tag para cada rota, pressione ENTER para iniciar e ENTER novamente
para encerrar. O terminal anuncia cada PC interpretado novo apenas uma vez.
Depois da janela, informe uma descricao opcional, como "Hadoken".

Exemplo:
  ryu-vs-ken-descoberta
  ryu-hadoken-confirmacao

Digite fim no prompt de tag para encerrar a campanha. O script nao gera fontes,
nao compila, nao abre e nao fecha o jogo.
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

raw_command() {
    local output="$1"
    shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 ||
        fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" ||
        fail "Comando rejeitado: $* (veja $output)"
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

validate_environment() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] ||
        fail "Abra o MSYS2 UCRT64 para executar este script."
    [[ "$POLL_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
        fail "DISCOVERY_POLL_SECONDS deve ser um inteiro positivo."
    [[ "$OVERLAY_POLL_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
        fail "DISCOVERY_OVERLAY_POLL_SECONDS deve ser um inteiro positivo."
    command -v sha256sum >/dev/null || fail "sha256sum nao encontrado."
    command -v awk >/dev/null || fail "awk nao encontrado."
    command -v grep >/dev/null || fail "grep nao encontrado."
    [[ -f "$GAME_TOML" ]] || fail "game.toml ausente: $GAME_TOML"
    [[ -f "$RAW_TCP" ]] || fail "Cliente TCP ausente: $RAW_TCP"
    [[ -f "$RANGES_FILE" ]] || fail "Manifesto ausente: $RANGES_FILE"
    [[ -f "$RUNTIME_EXE" ]] ||
        fail "Build S1-256 de telemetria ausente: $RUNTIME_EXE"
    [[ -f "$CMAKE_CACHE" ]] || fail "CMakeCache ausente na build S1-256."

    local ranges_sha runtime_sha function_count
    ranges_sha="$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')"
    [[ "$ranges_sha" == "$EXPECTED_RANGES_SHA" ]] ||
        fail "Manifesto nao corresponde ao S1-256: $ranges_sha"
    runtime_sha="$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')"
    [[ "$runtime_sha" == "$EXPECTED_RUNTIME_SHA" ]] ||
        fail "Executavel nao corresponde a build S1-256 validada: $runtime_sha"
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
}

write_campaign_metadata() {
    {
        printf 'campaign=%s\n' "$(basename "$CAMPAIGN_DIR")"
        printf 'lot=S1-%s\n' "$LOT_NUMBER"
        printf 'runtime_build=%s\n' "$(basename "$BUILD_DIR")"
        printf 'runtime_exe_sha256=%s\n' "$EXPECTED_RUNTIME_SHA"
        printf 'ranges_sha256=%s\n' "$EXPECTED_RANGES_SHA"
        printf 'generated_functions=%s\n' "$EXPECTED_FUNCTIONS"
        printf 'static_poll_seconds=%s\n' "$POLL_SECONDS"
        printf 'dynamic_poll_seconds=%s\n' "$OVERLAY_POLL_SECONDS"
        printf 'debug_port=%s\n' "$DEBUG_PORT"
        printf 'game_launch=manual\n'
        printf 'game_shutdown=manual\n'
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$CAMPAIGN_DIR/metadata.txt"
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
    result = json.loads(path.read_text(encoding="utf-8"))
    note_path = path.parent / "note.txt"
    result["note"] = note_path.read_text(encoding="utf-8").strip() if note_path.exists() else ""
    results.append(result)

lines = [
    f"# Descoberta de interpretados: {campaign.name}", "",
    "| Janela | Duracao | PCs interpretados | Entradas | Instrucoes | Observacao |",
    "|---|---:|---:|---:|---:|---|",
]
for result in results:
    note = result.get("note", "").replace("|", "/")
    lines.append(
        f"| `{result['window_id']}` | {result['duration_s']:.1f} s | "
        f"{result['interpreted_pc_count']} | {result['external_entries']} | "
        f"{result['interpreted_insns']} | {note} |"
    )
if not results:
    lines.extend(["", "Nenhuma janela foi concluida."])
lines.extend([
    "", "Os enderecos sao PCs de entrada observados. Boundary e closure ainda "
    "precisam de pre-auditoria antes de qualquer seed.", "",
])
(campaign / "campaign-summary.md").write_text("\n".join(lines), encoding="utf-8")

window_ids = [result["window_id"] for result in results]
all_pcs = sorted({row["pc"] for result in results for row in result.get("entries", [])})
with (campaign / "interpreted-matrix.csv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle)
    writer.writerow(["pc", *window_ids, "total_external_entries", "total_interpreted_insns"])
    for pc in all_pcs:
        by_window = []
        total_entries = 0
        total_insns = 0
        for result in results:
            row = next((item for item in result.get("entries", []) if item["pc"] == pc), None)
            entries = int(row.get("external_entries", 0)) if row else 0
            insns = int(row.get("interpreted_insns", 0)) if row else 0
            by_window.append(entries)
            total_entries += entries
            total_insns += insns
        writer.writerow([pc, *by_window, total_entries, total_insns])
PY
}

run_window() {
    local window_id="$1"
    local window_dir observation
    window_dir="$(make_unique_directory "$CAMPAIGN_DIR" "${LOT_NUMBER}-${window_id}")"
    CURRENT_WINDOW_DIR="$window_dir"
    {
        printf 'window_id=%s\n' "$window_id"
        printf 'campaign=%s\n' "$(basename "$CAMPAIGN_DIR")"
        printf 'static_poll_seconds=%s\n' "$POLL_SECONDS"
        printf 'dynamic_poll_seconds=%s\n' "$OVERLAY_POLL_SECONDS"
    } >"$window_dir/metadata.txt"

    printf '\nJanela: %s\n' "$window_id"
    printf 'Posicione o jogo exatamente no inicio da rota.\n'
    read -r -p 'Pressione ENTER para iniciar... ' _
    printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        >>"$window_dir/metadata.txt"

    "$PYTHON_BIN" - "$DEBUG_PORT" "$window_dir" "$window_id" \
        "$RANGES_FILE" "$POLL_SECONDS" "$OVERLAY_POLL_SECONDS" <<'PY' &
import csv
import json
import pathlib
import socket
import sys
import time

port = int(sys.argv[1])
directory = pathlib.Path(sys.argv[2])
window_id = sys.argv[3]
ranges_path = pathlib.Path(sys.argv[4])
static_poll = max(1, int(sys.argv[5]))
dynamic_poll = max(1, int(sys.argv[6]))
ready_path = directory / "collector.ready"
stop_path = directory / "stop.requested"


def request(command, **arguments):
    payload = {"id": 1, "cmd": command, **arguments}
    wire = json.dumps(payload, separators=(",", ":")) + "\n"
    chunks = []
    with socket.create_connection(("127.0.0.1", port), timeout=5.0) as sock:
        sock.settimeout(20.0)
        sock.sendall(wire.encode("utf-8"))
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    result = json.loads(b"".join(chunks).decode("utf-8"))
    if not result.get("ok"):
        raise RuntimeError(f"{command} rejeitado: {result}")
    return result


def paged(command, count_key, **arguments):
    offset = 0
    entries = {}
    header = None
    while True:
        page = request(command, offset=offset, limit=256, **arguments)
        if header is None:
            header = {key: value for key, value in page.items() if key != "entries"}
        for row in page.get("entries", []):
            pc = str(row.get("pc", "")).upper()
            if pc:
                entries[pc] = row
        returned = int(page.get("returned", 0) or 0)
        total = int(page.get(count_key, 0) or 0)
        offset += returned
        if returned == 0 or offset >= total:
            break
        if offset > 32768:
            raise RuntimeError(f"paginacao defensiva excedida em {command}")
    assert header is not None
    header["entries"] = list(entries.values())
    header["returned_merged"] = len(entries)
    return header


def static_snapshot():
    result = paged("static_text_misses", "total", **{"class": "all", "min_hits": 1})
    if int(result.get("dropped", 0) or 0) != 0:
        raise RuntimeError("static_text_misses perdeu entradas; coleta nao e completa")
    return result


def dynamic_snapshot():
    return paged(
        "overlay_interp_hot", "total", sort="entries", min_entries=1,
        phys_lo="0x00000000", phys_hi="0x00200000",
    )


def index(snapshot):
    return {str(row.get("pc", "")).upper(): row for row in snapshot.get("entries", [])}


def delta(value, old):
    return max(0, int(value or 0) - int(old or 0))


def static_deltas(before, after):
    old = index(before)
    rows = {}
    for pc, row in index(after).items():
        previous = old.get(pc, {})
        fields = {
            name: delta(row.get(name), previous.get(name))
            for name in ("misses", "modified", "runtime", "unknown")
        }
        fields["selected_hits"] = sum(fields.values())
        if fields["selected_hits"]:
            rows[pc] = fields
    return rows


def dynamic_deltas(before, after):
    old = index(before)
    rows = {}
    for pc, row in index(after).items():
        previous = old.get(pc, {})
        fields = {
            "entry_hits": delta(row.get("entry_hits"), previous.get("entry_hits")),
            "hits": delta(row.get("hits"), previous.get("hits")),
            "insns": delta(row.get("insns"), previous.get("insns")),
        }
        if fields["entry_hits"] or fields["hits"] or fields["insns"]:
            rows[pc] = fields
    return rows


def class_name(row, dynamic_only=False):
    names = []
    if row.get("misses", 0):
        names.append("pristine")
    if row.get("modified", 0):
        names.append("modified")
    if row.get("runtime", 0):
        names.append("runtime")
    if row.get("unknown", 0):
        names.append("unknown")
    if dynamic_only or not names:
        names.append("dynamic/ram")
    return "+".join(names)


native_entries = set()
for line in ranges_path.read_text(encoding="utf-8").splitlines():
    parts = line.split()
    if len(parts) == 2 and parts[0] == "F":
        native_entries.add("0X" + parts[1].upper())

print("\nColetando baseline dos contadores interpretados...", flush=True)
before_static = static_snapshot()
before_dynamic = dynamic_snapshot()
(directory / "before_static_text_misses.json").write_text(
    json.dumps(before_static, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
(directory / "before_overlay_interp_hot.json").write_text(
    json.dumps(before_dynamic, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

started = time.monotonic()
announced = set()
latest_static = before_static
latest_dynamic = before_dynamic
next_static = started
next_dynamic = started

print("\n[OBSERVANDO] Execute movimentos e golpes livremente.", flush=True)
print("Cada PC interpretado novo sera anunciado uma unica vez.", flush=True)
ready_path.write_text("ready\n", encoding="utf-8")

while not stop_path.exists():
    now = time.monotonic()
    try:
        if now >= next_static:
            latest_static = static_snapshot()
            for pc, row in sorted(static_deltas(before_static, latest_static).items()):
                if pc in announced:
                    continue
                announced.add(pc)
                print(
                    f"[INTERPRETADO] {pc} classe={class_name(row)} "
                    f"entradas=+{row['selected_hits']}",
                    flush=True,
                )
            next_static = time.monotonic() + static_poll
        if now >= next_dynamic:
            latest_dynamic = dynamic_snapshot()
            static_now = static_deltas(before_static, latest_static)
            for pc, row in sorted(dynamic_deltas(before_dynamic, latest_dynamic).items()):
                if pc in announced:
                    continue
                announced.add(pc)
                print(
                    f"[INTERPRETADO-RAM] {pc} entradas=+{row['entry_hits']} "
                    f"blocos=+{row['hits']} insns=+{row['insns']}",
                    flush=True,
                )
            next_dynamic = time.monotonic() + dynamic_poll
    except Exception as exc:
        print(f"[AVISO] consulta incremental falhou: {exc}", file=sys.stderr, flush=True)
        next_static = time.monotonic() + static_poll
        next_dynamic = time.monotonic() + dynamic_poll
    time.sleep(0.1)

ended = time.monotonic()
print("\nEncerrando janela e coletando snapshot final...", flush=True)
after_static = static_snapshot()
after_dynamic = dynamic_snapshot()
(directory / "after_static_text_misses.json").write_text(
    json.dumps(after_static, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
(directory / "after_overlay_interp_hot.json").write_text(
    json.dumps(after_dynamic, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

srows = static_deltas(before_static, after_static)
drows = dynamic_deltas(before_dynamic, after_dynamic)
all_pcs = sorted(set(srows) | set(drows))
entries = []
for pc in all_pcs:
    static = srows.get(pc, {})
    dynamic = drows.get(pc, {})
    static_entries = int(static.get("selected_hits", 0))
    dynamic_entries = int(dynamic.get("entry_hits", 0))
    external_entries = max(static_entries, dynamic_entries)
    interpreted_insns = int(dynamic.get("insns", 0))
    numeric = int(pc, 16)
    in_main_text = 0x80101000 <= numeric < 0x801C0000
    entries.append({
        "pc": pc,
        "classification": class_name(static, dynamic_only=not bool(static)),
        "external_entries": external_entries,
        "static_entries": static_entries,
        "dynamic_entries": dynamic_entries,
        "interpreted_blocks": int(dynamic.get("hits", 0)),
        "interpreted_insns": interpreted_insns,
        "pristine": int(static.get("misses", 0)),
        "modified": int(static.get("modified", 0)),
        "runtime": int(static.get("runtime", 0)),
        "unknown": int(static.get("unknown", 0)),
        "in_main_text": in_main_text,
        "already_generated_entry": pc in native_entries,
    })

entries.sort(key=lambda row: (-row["external_entries"], -row["interpreted_insns"], row["pc"]))
result = {
    "window_id": window_id,
    "duration_s": round(ended - started, 3),
    "interpreted_pc_count": len(entries),
    "external_entries": sum(row["external_entries"] for row in entries),
    "interpreted_insns": sum(row["interpreted_insns"] for row in entries),
    "entries": entries,
}
(directory / "result.json").write_text(
    json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

with (directory / "interpreted.csv").open("w", encoding="utf-8", newline="") as handle:
    columns = [
        "pc", "classification", "external_entries", "static_entries",
        "dynamic_entries", "interpreted_blocks", "interpreted_insns",
        "pristine", "modified", "runtime", "unknown", "in_main_text",
        "already_generated_entry",
    ]
    writer = csv.DictWriter(handle, fieldnames=columns)
    writer.writeheader()
    writer.writerows(entries)

lines = [
    f"# Interpretados: {window_id}", "",
    f"- Duracao: {result['duration_s']:.3f} s",
    f"- PCs de entrada interpretados: {len(entries)}",
    f"- Entradas externas: {result['external_entries']}",
    f"- Instrucoes atribuidas pelo contador dinamico: {result['interpreted_insns']}", "",
    "| PC | Classe | Entradas | Blocos | Instrucoes | Texto principal | Entrada ja gerada |",
    "|---|---|---:|---:|---:|---|---|",
]
for row in entries:
    lines.append(
        f"| `{row['pc']}` | {row['classification']} | {row['external_entries']} | "
        f"{row['interpreted_blocks']} | {row['interpreted_insns']} | "
        f"{'sim' if row['in_main_text'] else 'nao'} | "
        f"{'sim' if row['already_generated_entry'] else 'nao'} |"
    )
if not entries:
    lines.extend(["", "Nenhum PC interpretado novo foi observado nesta janela."])
lines.extend([
    "", "Os enderecos sao evidencias de entrada, nao seeds aprovadas. Confirmar "
    "boundary, bytes e closure antes de alterar `entry_funcs.txt`.", "",
])
(directory / "summary.md").write_text("\n".join(lines), encoding="utf-8")

print(
    f"[CONCLUIDO] {len(entries)} PC(s), "
    f"{result['external_entries']} entrada(s) interpretada(s).",
    flush=True,
)
PY

    COLLECTOR_PID=$!
    while [[ ! -f "$window_dir/collector.ready" ]]; do
        if ! kill -0 "$COLLECTOR_PID" 2>/dev/null; then
            wait "$COLLECTOR_PID" || true
            COLLECTOR_PID=""
            fail "O coletor encerrou antes de armar a janela; veja $window_dir."
        fi
        sleep 0.1
    done

    read -r -p 'Pressione ENTER para encerrar esta janela... ' _
    : >"$window_dir/stop.requested"
    if ! wait "$COLLECTOR_PID"; then
        COLLECTOR_PID=""
        fail "Falha durante a coleta; veja $window_dir."
    fi
    COLLECTOR_PID=""
    CURRENT_WINDOW_DIR=""

    printf 'ended_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        >>"$window_dir/metadata.txt"
    read -r -p 'Descricao observada (opcional; exemplo: Hadoken): ' observation
    printf '%s\n' "$observation" >"$window_dir/note.txt"
    update_campaign_summary
    printf 'Resumo: %s\n' "$window_dir/summary.md"
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
        "s1-${LOT_NUMBER}-interpreted-discovery")"
    write_campaign_metadata
    trap cleanup EXIT
    trap 'exit 130' INT TERM

    raw_command "$CAMPAIGN_DIR/runtime_dispatch_probe.log" dispatch_stats
    raw_command "$CAMPAIGN_DIR/runtime_static_probe.log" \
        static_text_misses class=all min_hits=1 offset=0 limit=1
    raw_command "$CAMPAIGN_DIR/runtime_dynamic_probe.log" \
        overlay_interp_hot sort=entries min_entries=1 offset=0 limit=1

    printf '\nObservador de funcoes interpretadas pronto.\n'
    printf 'Use uma tag por rota. Digite fim para encerrar a campanha.\n'
    printf 'O polling e apenas para descoberta; nao substitui telemetria formal.\n'

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
    printf '\nCampanha encerrada; o jogo continua aberto.\n'
    printf 'Resumo: %s\n' "$CAMPAIGN_DIR/campaign-summary.md"
    printf 'Matriz: %s\n' "$CAMPAIGN_DIR/interpreted-matrix.csv"
}

main "$@"
