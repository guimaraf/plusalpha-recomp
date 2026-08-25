#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly GAME_EXE="$PROJECT_ROOT/local/SLUS_005.48"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly RUNTIME_BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-239-tele"
readonly RUNTIME_EXE="$RUNTIME_BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly CMAKE_CACHE="$RUNTIME_BUILD_DIR/CMakeCache.txt"
readonly DEFERRED_WATCHLIST="$PROJECT_ROOT/seeds/deferred_watchlist.txt"
readonly TEXT_ADDR="0x80101000"
readonly TEXT_SIZE=$((0x000BF000))
readonly EXPECTED_EXE_SHA1="d8b81e036aa53c37ef983871c187cc9d00a27156"
readonly EXPECTED_RUNTIME_SHA256="aac75b0eff540a3ece81aae90d8aba69fe4230257abf652a9588e7c4dfe0a392"
readonly EXPECTED_RUNTIME_SIZE=210148088
readonly EXPECTED_UNIQUE_WORDS=106319
readonly EXPECTED_FUNCTIONS=1023

PYTHON_BIN=""
DEBUG_PORT=""
RUN_DIR=""
RUN_LABEL=""
MODE=""
CHARACTERS=""
STAGE=""
ROUTE=""
NOTES=""

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

note() {
    printf '\n==> %s\n' "$*"
}

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64 e com a build de telemetria já aberta:

  bash tools/run_modified_discovery.sh \
    --label m02-versus-doctrine-skullomania \
    --mode "Versus" \
    --characters "Doctrine Dark x Skullomania" \
    --stage "Skullomania" \
    --route "início do round 1 até Replay/Exit após o segundo round" \
    --notes "BEFORE e AFTER sem inputs"

O script usa a build preservada S1-239 de telemetria, coleta uma fotografia
única de static_text_misses class=all e snapshots completos da janela do EXE
no BEFORE e AFTER. Compara os bytes vivos com o SLUS_005.48 original, observa
a watchlist de quarentena e gera candidates.txt/summary.md. Não compila, abre
ou fecha o jogo.

Argumentos obrigatórios:
  --label       Identificador curto: letras minúsculas, números e hífens.
  --mode        Modo ou evento jogado.
  --characters Personagens envolvidos; use "n/a" quando não se aplicar.
  --stage       Cenário; use "n/a" quando não se aplicar.
  --route       Trecho exato coberto entre BEFORE e AFTER.

Argumento opcional:
  --notes       Observações adicionais da coleta.
EOF
}

require_value() {
    local option="$1"
    local value="${2:-}"
    [[ -n "$value" ]] || fail "$option exige um valor."
}

parse_args() {
    while (($#)); do
        case "$1" in
            --label)
                require_value "$1" "${2:-}"
                RUN_LABEL="$2"
                shift 2
                ;;
            --mode)
                require_value "$1" "${2:-}"
                MODE="$2"
                shift 2
                ;;
            --characters)
                require_value "$1" "${2:-}"
                CHARACTERS="$2"
                shift 2
                ;;
            --stage)
                require_value "$1" "${2:-}"
                STAGE="$2"
                shift 2
                ;;
            --route)
                require_value "$1" "${2:-}"
                ROUTE="$2"
                shift 2
                ;;
            --notes)
                require_value "$1" "${2:-}"
                NOTES="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                usage
                fail "Argumento desconhecido: $1"
                ;;
        esac
    done

    [[ "$RUN_LABEL" =~ ^[a-z0-9][a-z0-9-]*$ ]] ||
        fail "--label deve conter apenas letras minúsculas, números e hífens."
    [[ -n "$MODE" ]] || fail "--mode é obrigatório."
    [[ -n "$CHARACTERS" ]] || fail "--characters é obrigatório."
    [[ -n "$STAGE" ]] || fail "--stage é obrigatório."
    [[ -n "$ROUTE" ]] || fail "--route é obrigatório."
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

verify_baseline() {
    "$PYTHON_BIN" - "$GAME_EXE" "$RUNTIME_EXE" \
        "$EXPECTED_EXE_SHA1" "$EXPECTED_RUNTIME_SHA256" \
        "$EXPECTED_RUNTIME_SIZE" "$EXPECTED_UNIQUE_WORDS" \
        "$EXPECTED_FUNCTIONS" "$TEXT_SIZE" <<'PY'
import hashlib
import pathlib
import sys

exe_path = pathlib.Path(sys.argv[1])
runtime_path = pathlib.Path(sys.argv[2])
expected_exe_sha1 = sys.argv[3].lower()
expected_runtime_sha256 = sys.argv[4].lower()
expected_runtime_size = int(sys.argv[5])
expected_words = int(sys.argv[6])
expected_functions = int(sys.argv[7])
text_size = int(sys.argv[8])

exe = exe_path.read_bytes()
runtime = runtime_path.read_bytes()
actual_exe_sha1 = hashlib.sha1(exe).hexdigest()
actual_runtime_sha256 = hashlib.sha256(runtime).hexdigest()

errors = []
if actual_exe_sha1 != expected_exe_sha1:
    errors.append(f"SLUS SHA-1={actual_exe_sha1}, esperado={expected_exe_sha1}")
if len(exe) < 0x800 + text_size:
    errors.append(f"SLUS curto: {len(exe)} bytes")
if actual_runtime_sha256 != expected_runtime_sha256:
    errors.append(
        f"runtime SHA-256={actual_runtime_sha256}, esperado={expected_runtime_sha256}"
    )
if len(runtime) != expected_runtime_size:
    errors.append(f"runtime size={len(runtime)}, esperado={expected_runtime_size}")
if errors:
    raise SystemExit("baseline S1-239 divergente: " + "; ".join(errors))

print(
    "baseline S1-239 confirmada: "
    f"{expected_words} palavras únicas oficiais, {expected_functions} funções, "
    f"SLUS SHA-1={actual_exe_sha1}, runtime SHA-256={actual_runtime_sha256}"
)
PY
}

validate_environment() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] ||
        fail "Abra o MSYS2 UCRT64 para executar este script."
    [[ -f "$GAME_TOML" ]] || fail "game.toml ausente: $GAME_TOML"
    [[ -f "$GAME_EXE" ]] || fail "SLUS extraído ausente: $GAME_EXE"
    [[ -f "$RAW_TCP" ]] || fail "Cliente TCP ausente: $RAW_TCP"
    [[ -f "$RUNTIME_EXE" ]] || fail "Build preservada S1-239 ausente: $RUNTIME_EXE"
    [[ -f "$CMAKE_CACHE" ]] || fail "Cache da build S1-239 ausente: $CMAKE_CACHE"
    [[ -f "$DEFERRED_WATCHLIST" ]] || fail "Watchlist ausente: $DEFERRED_WATCHLIST"
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" ||
        fail "A build S1-239 preservada não usa RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" ||
        fail "A build S1-239 preservada não possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" ||
        fail "A build S1-239 preservada não possui PSX_STATIC_RUNTIME=ON."
    select_python
    read_debug_port
    verify_baseline
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
    raise SystemExit(f"JSON ausente em {path}")
PY
}

json_string() {
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
        print(str(json.loads(line).get(field, "")))
        break
else:
    raise SystemExit(f"JSON ausente em {path}")
PY
}

collect_evidence_snapshot() {
    local prefix="$1"
    local returned
    local total
    local dropped
    local response_class
    local output

    # O endpoint ordena por atividade. Uma fotografia de página única evita
    # que mudanças ocorridas entre páginas dupliquem linhas e omitam PCs.
    output="$RUN_DIR/${prefix}_evidence_offset_000000.log"
    raw_command "$output" static_text_misses \
        class=all min_hits=1 offset=0 limit=256
    response_class="$(json_string "$output" class)"
    [[ "$response_class" == "all" ]] ||
        fail "Endpoint respondeu class=$response_class; all era esperado."
    dropped="$(json_integer "$output" dropped)"
    ((dropped == 0)) ||
        fail "Tabela de evidências saturou: dropped=$dropped. Reinicie o jogo e reduza a rota."
    returned="$(json_integer "$output" returned)"
    total="$(json_integer "$output" total)"
    ((total <= 256)) ||
        fail "A fotografia possui total=$total, acima do limite seguro de 256 entradas."
    ((returned == total)) ||
        fail "Fotografia incompleta: returned=$returned, total=$total."
}

capture_live_text() {
    local prefix="$1"
    local output_bin="$RUN_DIR/${prefix}_live_text.bin"
    local output_meta="$RUN_DIR/${prefix}_live_text.json"

    "$PYTHON_BIN" - "$DEBUG_PORT" "$TEXT_ADDR" "$TEXT_SIZE" \
        "$output_bin" "$output_meta" <<'PY'
import hashlib
import json
import pathlib
import socket
import sys

port = int(sys.argv[1])
addr = sys.argv[2]
length = int(sys.argv[3])
output_bin = pathlib.Path(sys.argv[4])
output_meta = pathlib.Path(sys.argv[5])
request = {"id": 1, "cmd": "read_ram", "addr": addr, "len": length}

buffer = bytearray()
with socket.create_connection(("127.0.0.1", port), timeout=10.0) as sock:
    sock.settimeout(60.0)
    sock.sendall((json.dumps(request) + "\n").encode("utf-8"))
    while b"\n" not in buffer:
        chunk = sock.recv(65536)
        if not chunk:
            break
        buffer.extend(chunk)

line = bytes(buffer).split(b"\n", 1)[0]
try:
    response = json.loads(line.decode("utf-8"))
except Exception as exc:
    raise SystemExit(f"resposta read_ram inválida: {exc}") from exc
if not response.get("ok"):
    raise SystemExit(f"read_ram falhou: {response}")
if int(response.get("len", -1)) != length:
    raise SystemExit(
        f"read_ram retornou len={response.get('len')}, esperado={length}"
    )
hex_data = response.get("hex", "")
if len(hex_data) != length * 2:
    raise SystemExit(
        f"read_ram retornou {len(hex_data)} dígitos hex, esperado={length * 2}"
    )
raw = bytes.fromhex(hex_data)
output_bin.write_bytes(raw)
metadata = {
    "ok": True,
    "addr": response.get("addr"),
    "len": len(raw),
    "sha256": hashlib.sha256(raw).hexdigest(),
}
output_meta.write_text(
    json.dumps(metadata, ensure_ascii=False, sort_keys=True) + "\n",
    encoding="utf-8",
)
print(
    f"snapshot {output_bin.name}: {len(raw)} bytes, "
    f"SHA-256={metadata['sha256']}"
)
PY
}

create_run_directory() {
    local index
    local candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for index in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/discovery-${RUN_LABEL}-${index}"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            RUN_DIR="$candidate"
            return
        fi
    done
    fail "Não há run-id livre para discovery-${RUN_LABEL}-01..99."
}

metadata_value() {
    printf '%s' "$1" | tr '\r\n' '  '
}

write_metadata() {
    local commit="indisponivel"
    local status="indisponivel"
    if command -v git >/dev/null 2>&1; then
        commit="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'indisponivel')"
        status="$(git -C "$REPO_ROOT" status --short 2>/dev/null | tr '\n' ';' || true)"
    fi
    {
        printf 'run_id=%s\n' "$(basename "$RUN_DIR")"
        printf 'campaign=static_pristine_modified_discovery\n'
        printf 'baseline=S1-239\n'
        printf 'baseline_unique_words=%d\n' "$EXPECTED_UNIQUE_WORDS"
        printf 'baseline_functions=%d\n' "$EXPECTED_FUNCTIONS"
        printf 'commit=%s\n' "$commit"
        printf 'git_status=%s\n' "$status"
        printf 'runtime_build=buildClean-ucrt-s1-239-tele\n'
        printf 'runtime_exe_sha256=%s\n' "$EXPECTED_RUNTIME_SHA256"
        printf 'runtime_identity=sha256_cache_and_ping_verified_manual_executable_selection\n'
        printf 'debug_port=%s\n' "$DEBUG_PORT"
        printf 'collection=manual_before_after_all_classes_with_full_text_snapshots\n'
        printf 'deferred_watchlist=%s\n' "$DEFERRED_WATCHLIST"
        printf 'game_launch=manual\n'
        printf 'game_shutdown=manual\n'
        printf 'text_addr=%s\n' "$TEXT_ADDR"
        printf 'text_size=%d\n' "$TEXT_SIZE"
        printf 'mode=%s\n' "$(metadata_value "$MODE")"
        printf 'characters=%s\n' "$(metadata_value "$CHARACTERS")"
        printf 'stage=%s\n' "$(metadata_value "$STAGE")"
        printf 'route=%s\n' "$(metadata_value "$ROUTE")"
        printf 'notes=%s\n' "$(metadata_value "$NOTES")"
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$RUN_DIR/metadata.txt"
}

write_summary() {
    "$PYTHON_BIN" - "$RUN_DIR" "$GAME_EXE" "$TEXT_ADDR" "$TEXT_SIZE" \
        "$DEFERRED_WATCHLIST" <<'PY'
import hashlib
import json
import pathlib
import sys

run = pathlib.Path(sys.argv[1])
exe_path = pathlib.Path(sys.argv[2])
text_addr = int(sys.argv[3], 16)
text_size = int(sys.argv[4])
watchlist_path = pathlib.Path(sys.argv[5])


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


def metadata() -> dict[str, str]:
    result = {}
    for line in (run / "metadata.txt").read_text(
        encoding="utf-8", errors="replace"
    ).splitlines():
        key, separator, value = line.partition("=")
        if separator:
            result[key] = value
    return result


def snapshot_entries(prefix: str) -> tuple[dict[str, dict], dict, list[str]]:
    entries = {}
    top = {}
    duplicates = []
    for path in sorted(run.glob(f"{prefix}_evidence_offset_*.log")):
        data = payload(path)
        if not top or integer(data.get("offset")) == 0:
            top = data
        for entry in data.get("entries", []):
            pc = str(entry.get("pc", "")).upper().replace("0X", "0x")
            if not pc:
                continue
            if pc in entries:
                duplicates.append(pc)
            entries[pc] = entry
    return entries, top, sorted(set(duplicates))


def differing_pages(reference: bytes, live: bytes) -> list[int]:
    pages = []
    for offset in range(0, min(len(reference), len(live)), 0x1000):
        if reference[offset:offset + 0x1000] != live[offset:offset + 0x1000]:
            pages.append(offset // 0x1000)
    return pages


def difference_count(left: bytes, right: bytes) -> int:
    common = sum(a != b for a, b in zip(left, right))
    return common + abs(len(left) - len(right))


def exact_forward(reference: bytes, live: bytes, offset: int, cap: int = 0x1000) -> int:
    limit = min(len(reference), len(live), offset + cap)
    cursor = offset
    while cursor < limit and reference[cursor] == live[cursor]:
        cursor += 1
    return cursor - offset


def exact_label(length: int) -> str:
    return "4096+" if length >= 0x1000 else str(length)


def deferred_targets(path: pathlib.Path) -> list[tuple[str, str, str]]:
    result = []
    for raw in path.read_text(encoding="utf-8", errors="strict").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 3:
            raise SystemExit(f"linha inválida na watchlist: {raw!r}")
        target, caller, state = fields
        for label, value in (("target", target), ("caller", caller)):
            if len(value) != 10 or not value.lower().startswith("0x"):
                raise SystemExit(f"{label} inválido na watchlist: {value}")
            int(value, 16)
        result.append((target.upper().replace("0X", "0x"),
                       caller.upper().replace("0X", "0x"), state))
    return result


meta = metadata()
before_entries, before_top, before_duplicates = snapshot_entries("before")
after_entries, after_top, after_duplicates = snapshot_entries("after")
watch_targets = deferred_targets(watchlist_path)
before_dispatch = payload(run / "before_dispatch_stats.log")
after_dispatch = payload(run / "after_dispatch_stats.log")
before_dirty = payload(run / "before_dirty_ram_stats.log")
after_dirty = payload(run / "after_dirty_ram_stats.log")
after_latency = payload(run / "after_latency.log")
after_phase = payload(run / "after_phase_profile.log")
duration = payload(run / "duration.json").get("seconds", "n/d")

exe = exe_path.read_bytes()
reference = exe[0x800:0x800 + text_size]
before_live = (run / "before_live_text.bin").read_bytes()
after_live = (run / "after_live_text.bin").read_bytes()
if len(reference) != text_size:
    raise SystemExit(f"payload de referência possui {len(reference)} bytes")
if len(before_live) != text_size or len(after_live) != text_size:
    raise SystemExit(
        f"snapshot incompleto: before={len(before_live)}, after={len(after_live)}"
    )

candidates = []
for pc in sorted(set(before_entries) | set(after_entries)):
    before_entry = before_entries.get(pc, {})
    after_entry = after_entries.get(pc, {})
    before_hits = integer(before_entry.get("modified"))
    after_hits = integer(after_entry.get("modified"))
    delta = after_hits - before_hits
    if delta <= 0:
        continue
    address = int(pc, 16)
    offset = address - text_addr
    if offset < 0 or offset + 4 > text_size:
        continue
    before_run = exact_forward(reference, before_live, offset)
    after_run = exact_forward(reference, after_live, offset)
    candidates.append({
        "pc": pc,
        "before": before_hits,
        "after": after_hits,
        "delta": delta,
        "entry_before": reference[offset:offset + 4] == before_live[offset:offset + 4],
        "entry_after": reference[offset:offset + 4] == after_live[offset:offset + 4],
        "exact_before": before_run,
        "exact_after": after_run,
        "changed_256": before_live[offset:offset + 256] != after_live[offset:offset + 256],
        "pristine_total": integer(after_entry.get("misses")),
        "runtime_total": integer(after_entry.get("runtime")),
        "unknown_total": integer(after_entry.get("unknown")),
    })
candidates.sort(key=lambda row: (-row["delta"], row["pc"]))

pristine_candidates = []
for pc in sorted(set(before_entries) | set(after_entries)):
    before_entry = before_entries.get(pc, {})
    after_entry = after_entries.get(pc, {})
    before_hits = integer(before_entry.get("misses"))
    after_hits = integer(after_entry.get("misses"))
    delta = after_hits - before_hits
    if delta > 0:
        pristine_candidates.append({
            "pc": pc,
            "before": before_hits,
            "after": after_hits,
            "delta": delta,
            "modified_total": integer(after_entry.get("modified")),
            "runtime_total": integer(after_entry.get("runtime")),
            "unknown_total": integer(after_entry.get("unknown")),
        })
pristine_candidates.sort(key=lambda row: (-row["delta"], row["pc"]))

before_modified_count = sum(
    integer(entry.get("modified")) > 0 for entry in before_entries.values()
)
after_modified_count = sum(
    integer(entry.get("modified")) > 0 for entry in after_entries.values()
)
before_pristine_count = sum(
    integer(entry.get("misses")) > 0 for entry in before_entries.values()
)
after_pristine_count = sum(
    integer(entry.get("misses")) > 0 for entry in after_entries.values()
)

reference_sha = hashlib.sha256(reference).hexdigest()
before_sha = hashlib.sha256(before_live).hexdigest()
after_sha = hashlib.sha256(after_live).hexdigest()
before_diff = difference_count(reference, before_live)
after_diff = difference_count(reference, after_live)
route_diff = difference_count(before_live, after_live)
before_pages = differing_pages(reference, before_live)
after_pages = differing_pages(reference, after_live)
route_pages = differing_pages(before_live, after_live)
frame = after_latency.get("summary", {}).get("frame_period", {})

lines = [
    f"# Descoberta pristine/modified — {run.name}",
    "",
    "## Rota",
    "",
    f"- Modo: {meta.get('mode', 'n/d')}",
    f"- Personagens: {meta.get('characters', 'n/d')}",
    f"- Cenário: {meta.get('stage', 'n/d')}",
    f"- Trecho: {meta.get('route', 'n/d')}",
    f"- Observações: {meta.get('notes') or 'nenhuma'}",
    f"- Duração manual: {duration} s",
    "",
    "## Resultado",
    "",
    f"- PCs modified distintos no BEFORE: {before_modified_count}",
    f"- PCs modified distintos no AFTER: {after_modified_count}",
    f"- PCs com incremento modified no intervalo: {len(candidates)}",
    f"- PCs pristine distintos no BEFORE: {before_pristine_count}",
    f"- PCs pristine distintos no AFTER: {after_pristine_count}",
    f"- PCs com incremento pristine no intervalo: {len(pristine_candidates)}",
    f"- Δ observações modified: {integer(after_top.get('modified_observations')) - integer(before_top.get('modified_observations'))}",
    f"- Δ observações pristine: {integer(after_top.get('static_observations')) - integer(before_top.get('static_observations'))}",
    f"- Δ observações runtime: {integer(after_top.get('runtime_observations')) - integer(before_top.get('runtime_observations'))}",
    f"- Δ observações unknown: {integer(after_top.get('unknown_observations')) - integer(before_top.get('unknown_observations'))}",
    f"- Δ static_hits: {integer(after_dispatch.get('static_hits')) - integer(before_dispatch.get('static_hits'))}",
    f"- Δ miss_total: {integer(after_dispatch.get('miss_total')) - integer(before_dispatch.get('miss_total'))}",
    f"- Δ blocks_run: {integer(after_dirty.get('blocks_run')) - integer(before_dirty.get('blocks_run'))}",
    f"- Δ insns_run: {integer(after_dirty.get('insns_run')) - integer(before_dirty.get('insns_run'))}",
    "",
    "## Performance da build instrumentada",
    "",
    f"- Frametime P50: {integer(frame.get('p50_us')) / 1000.0:.3f} ms",
    f"- Frametime P95: {integer(frame.get('p95_us')) / 1000.0:.3f} ms",
    f"- Frametime máximo: {integer(frame.get('max_us')) / 1000.0:.3f} ms",
    f"- Fases: interpreter={after_phase.get('interp_share', 'n/d')}; static={after_phase.get('static_share', 'n/d')}; GPU={after_phase.get('gpu_share', 'n/d')}",
    "",
    "## Snapshots da janela do EXE",
    "",
    f"- SHA-256 referência: `{reference_sha}`",
    f"- SHA-256 BEFORE: `{before_sha}`",
    f"- SHA-256 AFTER: `{after_sha}`",
    f"- Bytes diferentes da referência no BEFORE: {before_diff}",
    f"- Bytes diferentes da referência no AFTER: {after_diff}",
    f"- Bytes alterados entre BEFORE e AFTER: {route_diff}",
    f"- Páginas diferentes da referência no BEFORE: {len(before_pages)}",
    f"- Páginas diferentes da referência no AFTER: {len(after_pages)}",
    f"- Páginas alteradas durante a rota: {len(route_pages)}",
    "",
    "## Candidatos modified observados",
    "",
]

if candidates:
    lines += [
        "| PC | BEFORE | AFTER | Δ modified | entrada exata B/A | bytes exatos à frente B/A | mudou em 256 B |",
        "|---|---:|---:|---:|---|---:|---|",
    ]
    for row in candidates:
        entry_exact = (
            f"{'sim' if row['entry_before'] else 'não'}/"
            f"{'sim' if row['entry_after'] else 'não'}"
        )
        exact_runs = (
            f"{exact_label(row['exact_before'])}/"
            f"{exact_label(row['exact_after'])}"
        )
        lines.append(
            f"| `{row['pc']}` | {row['before']} | {row['after']} | "
            f"{row['delta']} | {entry_exact} | {exact_runs} | "
            f"{'sim' if row['changed_256'] else 'não'} |"
        )
else:
    lines.append("Nenhuma entrada modified aumentou nesta rota.")

lines += [
    "",
    "## Candidatos pristine observados",
    "",
]
if pristine_candidates:
    lines += [
        "| PC | BEFORE | AFTER | Δ pristine | modified total | runtime total | unknown total |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in pristine_candidates:
        lines.append(
            f"| `{row['pc']}` | {row['before']} | {row['after']} | "
            f"{row['delta']} | {row['modified_total']} | "
            f"{row['runtime_total']} | {row['unknown_total']} |"
        )
else:
    lines.append("Nenhuma entrada pristine aumentou nesta rota.")

lines += [
    "",
    "## Watchlist em quarentena",
    "",
    "| Alvo | Chamador | Estado | Δ pristine | Δ modified | Δ runtime | Δ unknown |",
    "|---|---|---|---:|---:|---:|---:|",
]
for target, caller, state in watch_targets:
    before_entry = before_entries.get(target, {})
    after_entry = after_entries.get(target, {})
    deltas = {
        key: integer(after_entry.get(key)) - integer(before_entry.get(key))
        for key in ("misses", "modified", "runtime", "unknown")
    }
    lines.append(
        f"| `{target}` | `{caller}` | {state} | {deltas['misses']:+d} | "
        f"{deltas['modified']:+d} | {deltas['runtime']:+d} | "
        f"{deltas['unknown']:+d} |"
    )

duplicate_union = sorted(set(before_duplicates) | set(after_duplicates))
lines += [
    "",
    "## Integridade",
    "",
    f"- dropped BEFORE/AFTER: {integer(before_top.get('dropped'))}/{integer(after_top.get('dropped'))}",
    f"- Duplicatas entre páginas: {duplicate_union or 'nenhuma'}",
    f"- Classe BEFORE/AFTER: {before_top.get('class', 'n/d')}/{after_top.get('class', 'n/d')}",
    f"- aborts BEFORE/AFTER: {integer(before_dirty.get('aborts'))}/{integer(after_dirty.get('aborts'))}",
    f"- text_diverged_pages BEFORE/AFTER: {integer(before_dirty.get('text_diverged_pages'))}/{integer(after_dirty.get('text_diverged_pages'))}",
    f"- text_exact_mismatches BEFORE/AFTER: {integer(before_dirty.get('text_exact_mismatches'))}/{integer(after_dirty.get('text_exact_mismatches'))}",
    "- Igualdade nos snapshots reforça a evidência, mas não promove automaticamente um PC para seed.",
    "- Cada endereço ainda precisa de boundary, caller, alias, closure e auditoria de fluxo indireto.",
    "- O script não abriu, compilou nem fechará o jogo.",
    "",
]

(run / "summary.md").write_text("\n".join(lines), encoding="utf-8")

candidate_lines = [
    "# class PC delta before after entry_exact_before entry_exact_after exact_forward_before exact_forward_after changed_256"
]
candidate_lines.extend(
    f"modified {row['pc']} {row['delta']} {row['before']} {row['after']} "
    f"{int(row['entry_before'])} {int(row['entry_after'])} "
    f"{row['exact_before']} {row['exact_after']} {int(row['changed_256'])}"
    for row in candidates
)
candidate_lines.extend(
    f"pristine {row['pc']} {row['delta']} {row['before']} {row['after']} 0 0 0 0 0"
    for row in pristine_candidates
)
(run / "candidates.txt").write_text("\n".join(candidate_lines) + "\n", encoding="utf-8")

snapshot_diff = {
    "reference_sha256": reference_sha,
    "before_sha256": before_sha,
    "after_sha256": after_sha,
    "before_diff_bytes": before_diff,
    "after_diff_bytes": after_diff,
    "route_diff_bytes": route_diff,
    "before_diff_pages": before_pages,
    "after_diff_pages": after_pages,
    "route_diff_pages": route_pages,
}
(run / "snapshot_diff.json").write_text(
    json.dumps(snapshot_diff, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
}

collect_before_snapshot() {
    collect_evidence_snapshot before
    capture_live_text before
    raw_command "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw_command "$RUN_DIR/before_phase_profile.log" phase_profile window=1

    # Os contadores-base ficam por último para excluir o custo da preparação
    # do intervalo jogado.
    raw_command "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
}

collect_after_snapshot() {
    local measured_seconds="$1"
    local phase_window="$measured_seconds"
    if ((phase_window < 1)); then
        phase_window=1
    elif ((phase_window > 60)); then
        phase_window=60
    fi

    # Encerra primeiro os contadores que definem a janela manual da luta.
    raw_command "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    collect_evidence_snapshot after
    capture_live_text after
    raw_command "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw_command "$RUN_DIR/after_phase_profile.log" phase_profile window="$phase_window"
}

collect_discovery() {
    local readiness
    if ! readiness="$("$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" ping 2>&1)" ||
       [[ "$readiness" != *'"ok":true'* ]]; then
        fail "O jogo de telemetria não respondeu na porta $DEBUG_PORT. Abra-o manualmente primeiro."
    fi

    create_run_directory
    write_metadata

    printf '\nJogo detectado na porta %s.\n' "$DEBUG_PORT"
    printf 'Rota: %s | %s | %s\n' "$MODE" "$CHARACTERS" "$STAGE"
    printf 'Trecho: %s\n' "$ROUTE"
    printf 'O comando foi iniciado no ponto inicial da rota; mantenha os inputs parados.\n'

    note "Coletando BEFORE pristine/modified, performance e snapshot do EXE"
    collect_before_snapshot

    local started_epoch
    local finished_epoch
    local measured_seconds
    started_epoch="$(date +%s)"
    printf '\nBEFORE concluído. Execute somente a rota descrita.\n'
    read -r -p 'No ponto final, pare todos os inputs e pressione Enter para coletar AFTER... ' _
    finished_epoch="$(date +%s)"
    measured_seconds=$((finished_epoch - started_epoch))
    printf '{"seconds":%d}\n' "$measured_seconds" >"$RUN_DIR/duration.json"
    printf 'measured_seconds=%d\n' "$measured_seconds" >>"$RUN_DIR/metadata.txt"

    note "Coletando AFTER pristine/modified, performance e snapshot do EXE"
    collect_after_snapshot "$measured_seconds"
    write_summary

    note "Coleta concluída: $RUN_DIR"
    printf 'Resumo: %s/summary.md\n' "$RUN_DIR"
    printf 'Candidatos: %s/candidates.txt\n' "$RUN_DIR"
    printf 'Diferenças dos snapshots: %s/snapshot_diff.json\n' "$RUN_DIR"
    printf 'O script NÃO fechará o jogo. Feche-o manualmente quando desejar.\n'
}

main() {
    parse_args "$@"
    validate_environment
    collect_discovery
}

main "$@"
