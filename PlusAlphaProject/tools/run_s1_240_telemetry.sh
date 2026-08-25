#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly GENERATED_RANGES="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-240-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly TARGET="0x8013CB08"
readonly TARGET_HI="0x8013CB0C"

PYTHON_BIN=""
DEBUG_PORT=""
RUN_DIR=""

cleanup_runtime_probes() {
    if [[ -n "$PYTHON_BIN" && -n "$DEBUG_PORT" && -f "$RAW_TCP" ]]; then
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" cyc_watch_clear >/dev/null 2>&1 || true
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" fntrace_arm_clear >/dev/null 2>&1 || true
    fi
}

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

  bash tools/run_s1_240_telemetry.sh

  Antes de executar o script, inicie Versus com Doctrine Dark x Skullomania
  no cenario do Skullomania. Assim que o round 1 comecar, solte todos os
  controles e execute o script. Ele valida o artefato S1-240, conecta ao jogo
  ja aberto, coleta BEFORE durante o inicio do round 1 sem inputs, aguarda
  Enter e coleta AFTER na tela Replay/Exit apos o segundo round.
Ele observa diretamente a entrada nativa 0x8013CB08 por cyc_watch e fntrace.
Como a funcao e chamada indiretamente, nao existe gate de JAL chamador. O
script nao compila, abre nem fecha o jogo.
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

validate_sources() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v objdump >/dev/null 2>&1 || fail "objdump nao encontrado no UCRT64."
    command -v nm >/dev/null 2>&1 || fail "nm nao encontrado no UCRT64."
    command -v sha256sum >/dev/null 2>&1 || fail "sha256sum nao encontrado no UCRT64."
    [[ -f "$GAME_TOML" ]] || fail "game.toml ausente: $GAME_TOML"
    [[ -f "$GENERATED_RANGES" ]] || fail "Ranges gerados ausentes: $GENERATED_RANGES"
    [[ -f "$RAW_TCP" ]] || fail "Cliente TCP ausente: $RAW_TCP"
    [[ -f "$CMAKE_CACHE" ]] || fail "Cache da build S1-240 ausente: $CMAKE_CACHE"
    [[ -f "$RUNTIME_EXE" ]] || fail "Executavel S1-240 ausente: $RUNTIME_EXE"
    grep -q '^F 8013CB08$' "$GENERATED_RANGES" ||
        fail "A funcao 0x8013CB08 nao aparece nos fontes. Gere o S1-240 primeiro."
    grep -q '^R 8013CB08 84$' "$GENERATED_RANGES" ||
        fail "O range esperado 0x8013CB08+0x84 nao aparece nos fontes S1-240."
    ! grep -q '^F 8019E6D0$' "$GENERATED_RANGES" ||
        fail "A funcao em quarentena 0x8019E6D0 ainda aparece nos fontes."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$GENERATED_RANGES")" == "1024" ]] ||
        fail "A quantidade de funcoes geradas nao corresponde ao S1-240 esperado (1024)."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" ||
        fail "A build S1-240 nao esta configurada como RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" ||
        fail "A build S1-240 nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" ||
        fail "A build S1-240 nao possui PSX_STATIC_RUNTIME=ON."

    local imports
    imports="$(objdump -p "$RUNTIME_EXE" | awk '/DLL Name:/ { print $3 }')"
    if printf '%s\n' "$imports" |
       grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$'; then
        fail "O executavel S1-240 ainda importa uma DLL de runtime nao-sistema."
    fi
    nm -C "$RUNTIME_EXE" | grep -E '[[:space:]]T[[:space:]]+func_8013CB08$' >/dev/null ||
        fail "O executavel S1-240 nao contem o simbolo compilado func_8013CB08."
    if nm -C "$RUNTIME_EXE" | grep -E '[[:space:]]T[[:space:]]+func_8019E6D0$' >/dev/null; then
        fail "O executavel S1-240 ainda contem o candidato em quarentena func_8019E6D0."
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
import sys

path = pathlib.Path(sys.argv[1])
field = sys.argv[2]
for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
    if line.startswith("{"):
        print(int(json.loads(line).get(field, 0) or 0))
        break
else:
    print(0)
PY
}

collect_static_misses() {
    local prefix="$1"
    local returned
    local total
    local dropped
    local output

    # O endpoint ordena as linhas por atividade. Em jogo em execucao, uma
    # segunda pagina pode ser reordenada entre requisicoes e duplicar linhas
    # ja gravadas, omitindo outras. Uma pagina unica e uma fotografia valida
    # quando total <= 256; acima disso falhamos explicitamente em vez de
    # produzir uma descoberta incompleta.
    output="$RUN_DIR/${prefix}_static_text_misses_offset_000000.log"
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
    local index
    local candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for index in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-240-telemetry-$index"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"
            RUN_DIR="$candidate"
            return
        fi
    done
    fail "Nao ha run-id livre entre s1-240-telemetry-01 e 99."
}

write_metadata() {
    local commit="indisponivel"
    local status="indisponivel"
    local ranges_sha="indisponivel"
    local exe_sha="indisponivel"
    local exe_size="indisponivel"
    if command -v git >/dev/null 2>&1; then
        commit="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'indisponivel')"
        status="$(git -C "$REPO_ROOT" status --short 2>/dev/null | tr '\n' ';' || true)"
    fi
    ranges_sha="$(sha256sum "$GENERATED_RANGES" | awk '{print $1}')"
    exe_sha="$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')"
    exe_size="$(stat -c '%s' "$RUNTIME_EXE")"
    cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-240
commit=$commit
git_status=$status
ranges_sha256=$ranges_sha
runtime_exe=$RUNTIME_EXE
runtime_exe_sha256=$exe_sha
runtime_exe_size=$exe_size
runtime_build=buildClean-ucrt-s1-240-tele
runtime_identity=static_imports_cache_compiled_symbol_and_ping_verified
debug_port=$DEBUG_PORT
debug_tools=ON
static_runtime=ON
collection=manual_before_after_versus_direct_candidate_proof
game_launch=manual
game_shutdown=manual
target=$TARGET
target_range=0x8013CB08..0x8013CB8B
mode=Versus
characters=Doctrine Dark x Skullomania
stage=Skullomania
route=inicio do round 1 sem inputs ate a tela Replay/Exit apos o segundo round
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

collect_before() {
    note "Armando cyc_watch direto no bloco S1-240"
    raw_command "$RUN_DIR/before_cyc_watch_clear.log" cyc_watch_clear
    raw_command "$RUN_DIR/before_cyc_watch_arm.log" cyc_watch pc="$TARGET" n=1024

    note "Armando fntrace direto da entrada 0x8013CB08"
    raw_command "$RUN_DIR/before_fntrace_arm_clear.log" fntrace_arm_clear
    raw_command "$RUN_DIR/before_fntrace_arm.log" fntrace_arm target="$TARGET"
    raw_command "$RUN_DIR/before_fntrace_armed.log" fntrace_armed
    raw_command "$RUN_DIR/before_fntrace_clear.log" fntrace_clear

    note "Coletando BEFORE"
    raw_command "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw_command "$RUN_DIR/before_phase_profile.log" phase_profile window=1
    collect_static_misses before
    raw_command "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
    raw_command "$RUN_DIR/before_cyc_watch.log" cyc_watch_dump

    note "Rearmando cyc_watch para a janela manual"
    raw_command "$RUN_DIR/window_cyc_watch_clear.log" cyc_watch_clear
    raw_command "$RUN_DIR/window_cyc_watch_arm.log" cyc_watch pc="$TARGET" n=1024
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
    # Encerrar primeiro os contadores que definem o intervalo manual. As
    # amostras de frametime e fase abaixo descrevem a tela final instrumentada
    # e nao contaminam os deltas da tentativa.
    raw_command "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    raw_command "$RUN_DIR/after_cyc_watch.log" cyc_watch_dump
    raw_command "$RUN_DIR/after_fntrace.log" fntrace_dump target_lo="$TARGET" target_hi="$TARGET_HI" count=4096
    raw_command "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw_command "$RUN_DIR/after_phase_profile.log" phase_profile window="$phase_window"
    collect_static_misses after
    raw_command "$RUN_DIR/after_fntrace_armed.log" fntrace_armed
    raw_command "$RUN_DIR/after_fntrace_arm_clear.log" fntrace_arm_clear
    raw_command "$RUN_DIR/after_cyc_watch_clear.log" cyc_watch_clear
}

write_summary() {
    "$PYTHON_BIN" - "$RUN_DIR" "$TARGET" <<'PY'
import json
import pathlib
import re
import sys

run = pathlib.Path(sys.argv[1])
target = sys.argv[2]


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


def miss_entries(prefix):
    result = {}
    for path in sorted(run.glob(f"{prefix}_static_text_misses_offset_*.log")):
        for entry in payload(path).get("entries", []):
            pc = str(entry.get("pc", ""))
            if pc:
                result[pc] = entry
    return result


def miss_dropped(prefix):
    values = []
    for path in sorted(run.glob(f"{prefix}_static_text_misses_offset_*.log")):
        values.append(integer(payload(path).get("dropped")))
    return max(values, default=0)


before_dispatch = payload(run / "before_dispatch_stats.log")
after_dispatch = payload(run / "after_dispatch_stats.log")
before_dirty = payload(run / "before_dirty_ram_stats.log")
after_dirty = payload(run / "after_dirty_ram_stats.log")
after_latency = payload(run / "after_latency.log")
after_phase = payload(run / "after_phase_profile.log")
trace = payload(run / "after_fntrace.log")
before_cyc = payload(run / "before_cyc_watch.log")
window_cyc = payload(run / "after_cyc_watch.log")
before_misses = miss_entries("before")
after_misses = miss_entries("after")
before_entry = before_misses.get(target, {})
after_entry = after_misses.get(target, {})
frame = after_latency.get("summary", {}).get("frame_period", {})
before_cyc_hits = integer(before_cyc.get("hits"))
window_cyc_hits = integer(window_cyc.get("hits"))
compiled_proof = before_cyc_hits > 0 or window_cyc_hits > 0
no_candidate_fallback = target not in before_misses and target not in after_misses

deltas = {
    key: integer(after_entry.get(key)) - integer(before_entry.get(key))
    for key in ("misses", "modified", "runtime", "unknown")
}

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
    "## Candidato S1-240",
    "",
    f"- Entrada: `{target}`",
    "- Range formal: `0x8013CB08..0x8013CB8B` (132 bytes/33 palavras)",
    "- Origem de chamada: indireta; sem gate artificial de chamador",
    f"- Hits cyc_watch durante o BEFORE: {before_cyc_hits}",
    f"- Hits cyc_watch durante a janela manual: {window_cyc_hits}",
    f"- Hits fntrace auxiliares no intervalo: {integer(trace.get('emitted'))}",
    f"- Prova direta de alcance do bloco compilado: {'confirmada' if compiled_proof else 'insuficiente'}",
    f"- Execucao observada antes do inicio manual da rota: {'confirmada' if before_cyc_hits > 0 else 'nao observada'}",
    f"- Alcance sem fallback do candidato: {'confirmado' if compiled_proof and no_candidate_fallback else 'insuficiente'}",
    f"- Delta misses: {deltas['misses']:+d}",
    f"- Delta modified: {deltas['modified']:+d}",
    f"- Delta runtime: {deltas['runtime']:+d}",
    f"- Delta unknown: {deltas['unknown']:+d}",
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
    f"- dropped static_text_misses BEFORE/AFTER: {miss_dropped('before')}/{miss_dropped('after')}",
    f"- Candidato presente nos misses BEFORE: {'sim' if target in before_misses else 'nao'}",
    f"- Candidato presente nos misses AFTER: {'sim' if target in after_misses else 'nao'}",
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

    printf '\nArtefato S1-240 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"
    printf 'Precondicao: Versus Doctrine Dark x Skullomania no cenario Skullomania; round 1 ja iniciado e sem inputs.\n'
    printf 'A coleta BEFORE comeca agora e arma diretamente a entrada nativa 0x8013CB08.\n'
    collect_before

    local started_epoch
    local finished_epoch
    local measured_seconds
    started_epoch="$(date +%s)"
    printf '\nBEFORE concluido. Jogue a luta normalmente ate o fim do segundo round.\n'
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
