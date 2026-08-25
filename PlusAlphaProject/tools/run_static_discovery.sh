#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly GENERATED_RANGES="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly EXPECTED_UNIQUE_WORDS=106319
readonly EXPECTED_FUNCTIONS=1023
readonly EXPECTED_RANGES_SHA256="8836ce7d5ee66fe85eacedb854063661d95d4b725a351668bf7193f5c033201f"

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

  bash tools/run_static_discovery.sh \
    --label d01-bonus-barril \
    --mode "Bonus Barril" \
    --characters "personagem usado" \
    --stage "Bonus Barril" \
    --route "do início ao resultado final" \
    --notes "observações opcionais"

O script coleta somente static_text_misses class=pristine. Ele coleta BEFORE
imediatamente, aguarda Enter e coleta AFTER. Não compila, abre ou fecha o jogo.

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

verify_baseline_ranges() {
    "$PYTHON_BIN" - "$GENERATED_RANGES" \
        "$EXPECTED_UNIQUE_WORDS" "$EXPECTED_FUNCTIONS" \
        "$EXPECTED_RANGES_SHA256" <<'PY'
import hashlib
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
expected_words = int(sys.argv[2])
expected_functions = int(sys.argv[3])
expected_sha256 = sys.argv[4].lower()
functions = 0
has_s1_239_root = False
has_s1_239_range = False

contents = path.read_bytes()
actual_sha256 = hashlib.sha256(contents).hexdigest()
for raw in contents.decode("utf-8", errors="strict").splitlines():
    fields = raw.split()
    if not fields:
        continue
    if fields[0] == "F" and len(fields) == 2:
        functions += 1
        has_s1_239_root |= fields[1].upper() == "8019CB4C"
    elif fields[0] == "R" and len(fields) == 3:
        lo = int(fields[1], 16)
        length = int(fields[2], 16)
        if lo & 3 or length & 3:
            raise SystemExit(f"range desalinhado: {raw}")
        has_s1_239_range |= lo == 0x8019CB4C and length == 0x70

errors = []
if actual_sha256 != expected_sha256:
    errors.append(f"SHA-256={actual_sha256}, esperado={expected_sha256}")
if functions != expected_functions:
    errors.append(f"funções={functions}, esperado={expected_functions}")
if not has_s1_239_root:
    errors.append("raiz F 8019CB4C ausente")
if not has_s1_239_range:
    errors.append("range R 8019CB4C 70 ausente")
if errors:
    raise SystemExit("baseline S1-239 divergente: " + "; ".join(errors))

print(
    "baseline S1-239 confirmada: "
    f"{expected_words} palavras únicas oficiais, {functions} funções, "
    f"ranges SHA-256={actual_sha256}"
)
PY
}

validate_environment() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] ||
        fail "Abra o MSYS2 UCRT64 para executar este script."
    [[ -f "$GAME_TOML" ]] || fail "game.toml ausente: $GAME_TOML"
    [[ -f "$GENERATED_RANGES" ]] || fail "Ranges gerados ausentes: $GENERATED_RANGES"
    [[ -f "$RAW_TCP" ]] || fail "Cliente TCP ausente: $RAW_TCP"
    select_python
    read_debug_port
    verify_baseline_ranges
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

collect_static_misses() {
    local prefix="$1"
    local offset=0
    local page=0
    local returned
    local dropped
    local response_class
    local output

    while :; do
        output="$RUN_DIR/${prefix}_pristine_offset_$(printf '%06d' "$offset").log"
        raw_command "$output" static_text_misses \
            class=pristine min_hits=1 offset="$offset" limit=256
        response_class="$(json_string "$output" class)"
        [[ "$response_class" == "pristine" ]] ||
            fail "Endpoint respondeu class=$response_class; pristine era esperado."
        dropped="$(json_integer "$output" dropped)"
        ((dropped == 0)) ||
            fail "Tabela de evidências saturou: dropped=$dropped. Reinicie o jogo e reduza a rota."
        returned="$(json_integer "$output" returned)"
        ((returned >= 0 && returned <= 256)) ||
            fail "Paginação inválida: returned=$returned."
        ((page < 255)) ||
            fail "Limite defensivo de paginação atingido em static_text_misses."
        if ((returned == 0)); then
            break
        fi
        offset=$((offset + returned))
        page=$((page + 1))
    done
}

create_run_directory() {
    local index
    local candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for index in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/pristine-${RUN_LABEL}-${index}"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            RUN_DIR="$candidate"
            return
        fi
    done
    fail "Não há run-id livre para pristine-${RUN_LABEL}-01..99."
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
        printf 'campaign=static_pristine_discovery\n'
        printf 'baseline=S1-239\n'
        printf 'baseline_unique_words=%d\n' "$EXPECTED_UNIQUE_WORDS"
        printf 'baseline_functions=%d\n' "$EXPECTED_FUNCTIONS"
        printf 'commit=%s\n' "$commit"
        printf 'git_status=%s\n' "$status"
        printf 'runtime_build=buildClean-ucrt-s1-239-tele\n'
        printf 'runtime_identity=debug_tcp_ping_verified_manual_executable_selection\n'
        printf 'debug_port=%s\n' "$DEBUG_PORT"
        printf 'collection=manual_before_after_pristine_only\n'
        printf 'game_launch=manual\n'
        printf 'game_shutdown=manual\n'
        printf 'mode=%s\n' "$(metadata_value "$MODE")"
        printf 'characters=%s\n' "$(metadata_value "$CHARACTERS")"
        printf 'stage=%s\n' "$(metadata_value "$STAGE")"
        printf 'route=%s\n' "$(metadata_value "$ROUTE")"
        printf 'notes=%s\n' "$(metadata_value "$NOTES")"
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$RUN_DIR/metadata.txt"
}

write_summary() {
    "$PYTHON_BIN" - "$RUN_DIR" <<'PY'
import json
import pathlib
import sys

run = pathlib.Path(sys.argv[1])


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
    path = run / "metadata.txt"
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        key, separator, value = line.partition("=")
        if separator:
            result[key] = value
    return result


def snapshot(prefix: str) -> tuple[dict[str, dict], dict, list[str]]:
    entries = {}
    top = {}
    duplicates = []
    for path in sorted(run.glob(f"{prefix}_pristine_offset_*.log")):
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


meta = metadata()
before, before_top, before_duplicates = snapshot("before")
after, after_top, after_duplicates = snapshot("after")
before_dispatch = payload(run / "before_dispatch_stats.log")
after_dispatch = payload(run / "after_dispatch_stats.log")
before_dirty = payload(run / "before_dirty_ram_stats.log")
after_dirty = payload(run / "after_dirty_ram_stats.log")
duration = payload(run / "duration.json").get("seconds", "n/d")

candidates = []
for pc in sorted(set(before) | set(after)):
    before_entry = before.get(pc, {})
    after_entry = after.get(pc, {})
    before_hits = integer(before_entry.get("misses"))
    after_hits = integer(after_entry.get("misses"))
    delta = after_hits - before_hits
    if delta > 0:
        candidates.append((
            pc,
            before_hits,
            after_hits,
            delta,
            integer(after_entry.get("modified")),
            integer(after_entry.get("runtime")),
            integer(after_entry.get("unknown")),
        ))
candidates.sort(key=lambda row: (-row[3], row[0]))

lines = [
    f"# Descoberta pristine — {run.name}",
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
    f"- PCs pristine distintos no BEFORE: {len(before)}",
    f"- PCs pristine distintos no AFTER: {len(after)}",
    f"- PCs com incremento pristine no intervalo: {len(candidates)}",
    f"- Δ observações pristine: {integer(after_top.get('static_observations')) - integer(before_top.get('static_observations'))}",
    f"- Δ static_hits: {integer(after_dispatch.get('static_hits')) - integer(before_dispatch.get('static_hits'))}",
    f"- Δ miss_total: {integer(after_dispatch.get('miss_total')) - integer(before_dispatch.get('miss_total'))}",
    f"- Δ blocks_run: {integer(after_dirty.get('blocks_run')) - integer(before_dirty.get('blocks_run'))}",
    f"- Δ insns_run: {integer(after_dirty.get('insns_run')) - integer(before_dirty.get('insns_run'))}",
    "",
    "## Candidatos observados",
    "",
]

if candidates:
    lines += [
        "| PC | BEFORE | AFTER | Δ pristine | modified total | runtime total | unknown total |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in candidates:
        pc, before_hits, after_hits, delta, modified, runtime, unknown = row
        lines.append(
            f"| `{pc}` | {before_hits} | {after_hits} | {delta} | {modified} | {runtime} | {unknown} |"
        )
else:
    lines.append("Nenhuma entrada pristine nova foi observada nesta rota.")

duplicate_union = sorted(set(before_duplicates) | set(after_duplicates))
lines += [
    "",
    "## Integridade",
    "",
    f"- dropped BEFORE/AFTER: {integer(before_top.get('dropped'))}/{integer(after_top.get('dropped'))}",
    f"- Duplicatas entre páginas: {duplicate_union or 'nenhuma'}",
    f"- Classe BEFORE/AFTER: {before_top.get('class', 'n/d')}/{after_top.get('class', 'n/d')}",
    "- Estes PCs são evidência de execução estática original, não promoção automática para seed.",
    "- Cada endereço ainda precisa de classificação como raiz, alias interior ou quarentena.",
    "- O script não abriu, compilou nem fechará o jogo.",
    "",
]

(run / "summary.md").write_text("\n".join(lines), encoding="utf-8")

candidate_lines = [
    "# PC delta_pristine before after modified_total runtime_total unknown_total"
]
candidate_lines.extend(
    f"{pc} {delta} {before_hits} {after_hits} {modified} {runtime} {unknown}"
    for pc, before_hits, after_hits, delta, modified, runtime, unknown in candidates
)
(run / "candidates.txt").write_text("\n".join(candidate_lines) + "\n", encoding="utf-8")
PY
}

collect_snapshot() {
    local prefix="$1"
    raw_command "$RUN_DIR/${prefix}_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/${prefix}_dirty_ram_stats.log" dirty_ram_stats
    collect_static_misses "$prefix"
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

    note "Coletando BEFORE pristine"
    collect_snapshot before

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

    note "Coletando AFTER pristine"
    collect_snapshot after
    write_summary

    note "Coleta concluída: $RUN_DIR"
    printf 'Resumo: %s/summary.md\n' "$RUN_DIR"
    printf 'Candidatos: %s/candidates.txt\n' "$RUN_DIR"
    printf 'O script NÃO fechará o jogo. Feche-o manualmente quando desejar.\n'
}

main() {
    parse_args "$@"
    validate_environment
    collect_discovery
}

main "$@"
