#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-246-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"

# A auxiliar e chamada pela raiz 0x8011D030 somente quando a guarda de estado
# permite a inicializacao. O intervalo superior e exclusivo.
readonly TARGET="0x8011D078"
readonly TARGET_HI="0x8011D310"
readonly EXPECTED_CALLER_RA="0x8011D060"
readonly WATCH_MAX=8
readonly DIRECT_PAGE_SIZE=256
readonly FN_RING_CAP=262144

PYTHON_BIN=""
DEBUG_PORT=""
RUN_DIR=""

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/telemetry_helper_s1_246.sh

Nao gere fontes nem compile novamente. Abra manualmente a build S1-246 de
telemetria e pare no menu de selecao do Versus. Execute o script nesse menu.
Ele arma o trace e pausa. Entao escolha Doctrine Dark no P1, Skullomania no P2
e o cenario Skullomania. Quando a mensagem START aparecer no round 1, solte os
controles e pressione Enter no terminal: o script coleta BEFORE, aguarda novo
Enter e coleta AFTER na tela Replay/Exit apos o segundo round. O script nao
compila, nao abre e nao fecha o jogo.
EOF
}

cleanup_runtime_probes() {
    if [[ -n "$PYTHON_BIN" && -n "$DEBUG_PORT" && -f "$RAW_TCP" ]]; then
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" cyc_watch_clear >/dev/null 2>&1 || true
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" fn_disable >/dev/null 2>&1 || true
    fi
}

select_python() {
    if command -v python >/dev/null; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao foi encontrado no PATH do UCRT64."; fi
}

read_debug_port() {
    DEBUG_PORT="$(awk '/^[[:space:]]*\[runtime\][[:space:]]*$/ { ok=1; next } /^[[:space:]]*\[/ { ok=0 } ok && /^[[:space:]]*debug_port[[:space:]]*=/ { sub(/^[^=]*=/, ""); gsub(/[[:space:]]+/, ""); print; exit }' "$GAME_TOML")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida em game.toml."
}

require_range() { grep -q "^${1}$" "$RANGES_FILE" || fail "Range/função ausente: $1"; }
require_symbol() { nm -C "$RUNTIME_EXE" | grep -E "[[:space:]]T[[:space:]]+${1}$" >/dev/null || fail "O executavel S1-246 nao contem $1."; }

validate_artifact() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v objdump >/dev/null || fail "objdump nao encontrado no UCRT64."
    command -v nm >/dev/null || fail "nm nao encontrado no UCRT64."
    command -v sha256sum >/dev/null || fail "sha256sum nao encontrado no UCRT64."
    [[ -f "$GAME_TOML" && -f "$RANGES_FILE" && -f "$RAW_TCP" && -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] || fail "Arquivos da build S1-246 de telemetria estao ausentes."
    require_range "F 8011D030"; require_range "R 8011D030 48"
    require_range "F 8011D078"; require_range "R 8011D078 298"; require_range "F 8011D310"
    require_range "F 801171DC"; require_range "F 80107A74"; require_range "F 80162D68"; require_range "F 80137FE8"; require_range "F 80138084"; require_range "F 8013827C"; require_range "F 801102A0"; require_range "F 8013CB08"
    ! grep -q '^F 8019E6D0$' "$RANGES_FILE" || fail "A funcao em quarentena 0x8019E6D0 apareceu nos fontes."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == "1033" ]] || fail "A quantidade de funcoes geradas nao corresponde ao S1-246 esperado (1033)."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" || fail "A build S1-246 nao esta configurada como RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" || fail "A build S1-246 nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" || fail "A build S1-246 nao possui PSX_STATIC_RUNTIME=ON."
    local imports
    imports="$(objdump -p "$RUNTIME_EXE" | awk '/DLL Name:/ { print $3 }')"
    ! printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$' || fail "O executavel S1-246 importa uma DLL de runtime nao-sistema."
    require_symbol "func_8011D030"; require_symbol "func_8011D078"; require_symbol "func_8011D310"; require_symbol "func_801171DC"
    ! nm -C "$RUNTIME_EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_8019E6D0$' || fail "O executavel S1-246 contem o candidato em quarentena func_8019E6D0."
    select_python
    read_debug_port
}

raw_command() {
    local output="$1"
    shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 || fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" || fail "Resposta TCP invalida em $(basename "$output")."
}

json_integer() {
    "$PYTHON_BIN" - "$1" "$2" <<'PY'
import json, pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
field = sys.argv[2]
match = re.search(r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===", text, re.S)
rows = [match.group(1).strip()] if match else []
rows += [line for line in text.splitlines() if line.startswith("{")]
for row in rows:
    try:
        print(int(json.loads(row).get(field, 0) or 0))
        break
    except (json.JSONDecodeError, AttributeError, ValueError):
        pass
else:
    print(0)
PY
}

collect_static_misses() {
    local prefix="$1" output returned total dropped
    output="$RUN_DIR/${prefix}_static_text_misses_offset_000000.log"
    raw_command "$output" static_text_misses class=all min_hits=1 offset=0 limit=256
    returned="$(json_integer "$output" returned)"
    total="$(json_integer "$output" total)"
    dropped="$(json_integer "$output" dropped)"
    (( dropped == 0 && total <= 256 && returned == total )) || fail "Snapshot $prefix de static_text_misses incompleto (total=$total returned=$returned dropped=$dropped)."
}

validate_running_build() {
    local ping_file
    ping_file="$(mktemp)"
    raw_command "$ping_file" ping
    rm -f "$ping_file"
}

create_run_directory() {
    local i candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for i in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-246-helper-telemetry-$i"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi
    done
    fail "Nao ha run-id livre entre s1-246-helper-telemetry-01 e 99."
}

write_metadata() {
    local ranges_sha exe_sha
    ranges_sha="$(sha256sum "$RANGES_FILE" | awk '{print $1}')"
    exe_sha="$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')"
    cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-246-helper-directed
helper_target=$TARGET
helper_range=0x8011D078..0x8011D30F
direct_caller=0x8011D030
expected_caller_ra=$EXPECTED_CALLER_RA
helper_guard_byte=0x8001C800
fn_entry_filter=[$TARGET,$TARGET_HI)
direct_trace=fn_entry_filter_paged
fn_entry_page_size=$DIRECT_PAGE_SIZE
fn_entry_ring_capacity=$FN_RING_CAP
ranges_sha256=$ranges_sha
runtime_exe_sha256=$exe_sha
runtime_build=buildClean-ucrt-s1-246-tele
mode=Versus
characters=Doctrine Dark x Skullomania
stage=Skullomania
route=armar no menu Versus; selecionar Doctrine Dark x Skullomania; confirmar BEFORE na mensagem START do round 1 sem inputs; AFTER em Replay/Exit apos o segundo round
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

arm_trace() {
    raw_command "$RUN_DIR/before_fn_filter.log" fn_filter lo="$TARGET" hi="$TARGET_HI"
    raw_command "$RUN_DIR/before_fn_clear.log" fn_clear
    raw_command "$RUN_DIR/before_fn_stats.log" fn_stats
}

dump_fn_entries() {
    local prefix="$1" total="$2" start=0 end page=0 lo_hex hi_hex output
    if (( total == 0 )); then
        raw_command "$RUN_DIR/${prefix}_fn_entry_page_000.log" fn_entry_dump addr_lo="$TARGET" addr_hi="$TARGET_HI" seq_lo=0x0 seq_hi=0x0 count="$DIRECT_PAGE_SIZE"
        return
    fi
    while (( start < total )); do
        end=$((start + DIRECT_PAGE_SIZE)); (( end > total )) && end="$total"
        lo_hex="$(printf '0x%X' "$start")"; hi_hex="$(printf '0x%X' "$end")"
        output="$RUN_DIR/${prefix}_fn_entry_page_$(printf '%03d' "$page").log"
        raw_command "$output" fn_entry_dump addr_lo="$TARGET" addr_hi="$TARGET_HI" seq_lo="$lo_hex" seq_hi="$hi_hex" count="$DIRECT_PAGE_SIZE"
        start="$end"; page=$((page + 1))
        (( page <= 128 )) || fail "Paginacao fn_entry excedeu 128 paginas; interrompida para preservar a saude da build."
    done
}

arm_initial_trace() {
    note "Armando trace direto da auxiliar $TARGET e cyc_watch de baixa frequencia"
    raw_command "$RUN_DIR/before_cyc_watch_clear.log" cyc_watch_clear
    raw_command "$RUN_DIR/before_cyc_watch_arm.log" cyc_watch pc="$TARGET" n="$WATCH_MAX"
    arm_trace
    note "Trace armado antes da selecao; escolha a luta agora"
    read -r -p 'Na mensagem START do round 1, solte os controles e pressione Enter para coletar BEFORE... ' _
}

collect_before() {
    note "Coletando BEFORE; mantenha todos os controles soltos"
    raw_command "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw_command "$RUN_DIR/before_phase_profile.log" phase_profile window=1
    collect_static_misses before
    raw_command "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
    raw_command "$RUN_DIR/before_fn_stats_after_window.log" fn_stats
    local before_total
    before_total="$(json_integer "$RUN_DIR/before_fn_stats_after_window.log" entry_total)"
    dump_fn_entries before "$before_total"
    raw_command "$RUN_DIR/before_cyc_watch.log" cyc_watch_dump
    raw_command "$RUN_DIR/window_cyc_watch_clear.log" cyc_watch_clear
    raw_command "$RUN_DIR/window_cyc_watch_arm.log" cyc_watch pc="$TARGET" n="$WATCH_MAX"
    raw_command "$RUN_DIR/window_fn_clear.log" fn_clear
}

collect_after() {
    local seconds="$1" window="$seconds"
    (( window < 1 )) && window=1; (( window > 60 )) && window=60
    note "Coletando AFTER imediatamente e congelando o trace da auxiliar"
    raw_command "$RUN_DIR/after_fn_disable.log" fn_disable
    raw_command "$RUN_DIR/after_fn_stats.log" fn_stats
    local after_total
    after_total="$(json_integer "$RUN_DIR/after_fn_stats.log" entry_total)"
    dump_fn_entries after "$after_total"
    raw_command "$RUN_DIR/after_cyc_watch.log" cyc_watch_dump
    raw_command "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    raw_command "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw_command "$RUN_DIR/after_phase_profile.log" phase_profile window="$window"
    collect_static_misses after
    raw_command "$RUN_DIR/after_cyc_watch_clear.log" cyc_watch_clear
}

write_summary() {
    "$PYTHON_BIN" - "$RUN_DIR" "$TARGET" "$EXPECTED_CALLER_RA" "$WATCH_MAX" "$FN_RING_CAP" <<'PY'
import collections, json, pathlib, re, sys
run, target, expected, watch, ring = pathlib.Path(sys.argv[1]), sys.argv[2].upper(), sys.argv[3].upper(), int(sys.argv[4]), int(sys.argv[5])
def payload(name):
    p = run / name
    if not p.exists(): return {}
    text = p.read_text(encoding='utf-8', errors='replace')
    match = re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===', text, re.S)
    rows = [match.group(1).strip()] if match else []
    rows += [line for line in text.splitlines() if line.startswith('{')]
    for row in rows:
        try:
            value = json.loads(row)
            if isinstance(value, dict): return value
        except json.JSONDecodeError: pass
    return {}
def integer(value):
    try: return int(value or 0)
    except (ValueError, TypeError): return 0
def misses(prefix):
    return {str(x.get('pc', '')).upper() for x in payload(prefix + '_static_text_misses_offset_000000.log').get('entries', []) if x.get('pc')}
def trace_entries(prefix):
    pages, entries = [], []
    for page in sorted(run.glob(prefix + '_fn_entry_page_*.log')):
        data = payload(page.name); pages.append(data); entries.extend(data.get('entries', []))
    return pages, entries
def complete(total, entries):
    seqs = [integer(x.get('seq')) for x in entries]
    return total <= ring and len(entries) == total and len(set(seqs)) == total and set(seqs) == set(range(total))
before_stats, after_stats = payload('before_fn_stats_after_window.log'), payload('after_fn_stats.log')
before_pages, before_entries = trace_entries('before'); after_pages, after_entries = trace_entries('after')
all_entries = before_entries + after_entries
before_total, after_total = integer(before_stats.get('entry_total')), integer(after_stats.get('entry_total'))
before_ok, after_ok = complete(before_total, before_entries), complete(after_total, after_entries)
ras = collections.Counter(str(x.get('ra', '')).upper() for x in all_entries if str(x.get('func', '')).upper() == target)
hits = sum(1 for x in all_entries if str(x.get('func', '')).upper() == target)
before_hits = sum(1 for x in before_entries if str(x.get('func', '')).upper() == target)
after_hits = sum(1 for x in after_entries if str(x.get('func', '')).upper() == target)
bdisp, adisp = payload('before_dispatch_stats.log'), payload('after_dispatch_stats.log')
bdirty, adirty = payload('before_dirty_ram_stats.log'), payload('after_dirty_ram_stats.log')
cyc = payload('after_cyc_watch.log'); lat, phase = payload('after_latency.log'), payload('after_phase_profile.log')
frame = lat.get('summary', {}).get('frame_period', {})
no_fallback = target not in misses('before') and target not in misses('after')
proof = hits > 0 and before_ok and after_ok and ras[expected] == hits and no_fallback
lines = [
    f'# Telemetria direcionada {run.name}', '', '## Resultado da auxiliar S1-246', '',
    f'- Duracao manual: {payload("duration.json").get("seconds", "n/d")} s',
    f'- Hits auxiliar BEFORE/AFTER/total: {before_hits}/{after_hits}/{hits}',
    f'- Páginas fn_entry BEFORE/AFTER: {len(before_pages)}/{len(after_pages)}',
    f'- fn_entry BEFORE total/filtrado/capturado: {before_total}/{integer(before_stats.get("direct_filtered"))}/{len(before_entries)}',
    f'- fn_entry AFTER total/filtrado/capturado: {after_total}/{integer(after_stats.get("direct_filtered"))}/{len(after_entries)}',
    f'- Ring sem perda BEFORE/AFTER: {"sim" if before_ok else "nao"}/{"sim" if after_ok else "nao"}',
    f'- RA esperado {expected}: {"confirmado em todos os hits" if hits and ras[expected] == hits else "nao confirmado integralmente"}',
    f'- Retornos mais comuns: {ras.most_common(5)}',
    f'- Hits cyc_watch AFTER: {integer(cyc.get("hits"))}/{integer(cyc.get("max_hits") or watch)}',
    f'- Funcao auxiliar nativa alcancada diretamente, com RA confirmada e sem fallback: {"confirmado" if proof else "insuficiente"}',
    f'- Delta static_hits: {integer(adisp.get("static_hits")) - integer(bdisp.get("static_hits"))}',
    f'- Delta miss_total: {integer(adisp.get("miss_total")) - integer(bdisp.get("miss_total"))}', '',
    '## Frametime e integridade', '',
    f'- P50/P95/max: {integer(frame.get("p50_us"))/1000:.3f} / {integer(frame.get("p95_us"))/1000:.3f} / {integer(frame.get("max_us"))/1000:.3f} ms',
    f'- Fases: interpreter={phase.get("interp_share", "n/d")}; static={phase.get("static_share", "n/d")}; GPU={phase.get("gpu_share", "n/d")}',
    f'- aborts BEFORE/AFTER: {integer(bdirty.get("aborts"))}/{integer(adirty.get("aborts"))}',
    f'- native_handoffs BEFORE/AFTER: {integer(bdirty.get("native_handoffs"))}/{integer(adirty.get("native_handoffs"))}',
    f'- text_native_blocked BEFORE/AFTER: {integer(bdirty.get("text_native_blocked"))}/{integer(adirty.get("text_native_blocked"))}',
    f'- stack_overflows do trace: {integer(after_stats.get("stack_overflows"))} (diagnostico do observador, nao overflow do jogo)',
    f'- Auxiliar presente em static_text_misses: {"nao" if no_fallback else "sim"}', '',
    '- O coletor nao compilou, abriu nem fechou o jogo.', ''
]
(run / 'summary.md').write_text('\n'.join(lines), encoding='utf-8')
PY
}

collect_telemetry() {
    validate_running_build
    trap cleanup_runtime_probes EXIT
    create_run_directory
    write_metadata
    printf '\nArtefato S1-246 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"
    printf 'Precondicao: abra o menu Versus, mas ainda nao selecione personagens nem cenario.\n'
    arm_initial_trace
    collect_before
    local start end seconds
    start="$(date +%s)"
    printf '\nBEFORE concluido. Jogue normalmente ate a tela Replay/Exit apos o segundo round.\n'
    read -r -p 'Na tela Replay/Exit, pare os inputs e pressione Enter para coletar AFTER... ' _
    end="$(date +%s)"; seconds=$((end - start))
    printf '{"seconds":%d}\n' "$seconds" >"$RUN_DIR/duration.json"
    collect_after "$seconds"
    write_summary
    note "Coleta concluida: $RUN_DIR"
    printf 'Resumo: %s/summary.md\nO script nao fechara o jogo.\n' "$RUN_DIR"
}

main() {
    case "${1:-}" in
        "") ;;
        -h|--help) usage; return ;;
        *) usage; fail "Argumento desconhecido: $1" ;;
    esac
    validate_artifact
    collect_telemetry
}

main "$@"
