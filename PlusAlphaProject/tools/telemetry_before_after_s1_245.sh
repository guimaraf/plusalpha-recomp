#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-245-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly TARGET="0x8011D310"
readonly TARGET_HI="0x8011D9B4"
readonly EXPECTED_CALLER_RA="0x8011D068"
readonly WATCH_MAX=1024
readonly DIRECT_PAGE_SIZE=2048
readonly FN_RING_CAP=262144

PYTHON_BIN=""; DEBUG_PORT=""; RUN_DIR=""
fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/telemetry_before_after_s1_245.sh

Abra manualmente a build S1-245 de telemetria. Em Versus, escolha Doctrine
Dark no P1, Skullomania no P2 e o cenario Skullomania. Quando o round 1 ficar
controlavel, solte os controles e execute o script. Ele coleta BEFORE, aguarda
Enter e coleta AFTER na tela Replay/Exit depois do segundo round. Nao compila,
nao abre e nao fecha o jogo.
EOF
}

cleanup_runtime_probes() { if [[ -n "$PYTHON_BIN" && -n "$DEBUG_PORT" && -f "$RAW_TCP" ]]; then "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" cyc_watch_clear >/dev/null 2>&1 || true; "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" fn_disable >/dev/null 2>&1 || true; fi; }
select_python() { if command -v python >/dev/null; then PYTHON_BIN="$(command -v python)"; elif command -v python3 >/dev/null; then PYTHON_BIN="$(command -v python3)"; else fail "Python nao foi encontrado no PATH do UCRT64."; fi; }
read_debug_port() { DEBUG_PORT="$(awk '/^[[:space:]]*\[runtime\][[:space:]]*$/ { ok=1; next } /^[[:space:]]*\[/ { ok=0 } ok && /^[[:space:]]*debug_port[[:space:]]*=/ { sub(/^[^=]*=/, ""); gsub(/[[:space:]]+/, ""); print; exit }' "$GAME_TOML")"; [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida em game.toml."; }
require_range() { grep -q "^${1}$" "$RANGES_FILE" || fail "Range/função ausente: $1"; }
require_symbol() { nm -C "$RUNTIME_EXE" | grep -E "[[:space:]]T[[:space:]]+${1}$" >/dev/null || fail "O executavel S1-245 nao contem $1."; }

validate_sources() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v objdump >/dev/null || fail "objdump nao encontrado no UCRT64."; command -v nm >/dev/null || fail "nm nao encontrado no UCRT64."; command -v sha256sum >/dev/null || fail "sha256sum nao encontrado no UCRT64."
    [[ -f "$GAME_TOML" && -f "$RANGES_FILE" && -f "$RAW_TCP" && -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] || fail "Arquivos da build S1-245 de telemetria estao ausentes."
    require_range "F 8011D310"; require_range "R 8011D310 6A4"; require_range "F 80107A74"; require_range "F 80162D68"; require_range "F 80137FE8"; require_range "F 80138084"; require_range "F 8013827C"; require_range "F 801102A0"; require_range "F 8013CB08"
    ! grep -q '^F 8019E6D0$' "$RANGES_FILE" || fail "A funcao em quarentena 0x8019E6D0 apareceu nos fontes."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == "1031" ]] || fail "A quantidade de funcoes geradas nao corresponde ao S1-245 esperado (1031)."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" || fail "A build S1-245 nao esta configurada como RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" || fail "A build S1-245 nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" || fail "A build S1-245 nao possui PSX_STATIC_RUNTIME=ON."
    local imports; imports="$(objdump -p "$RUNTIME_EXE" | awk '/DLL Name:/ { print $3 }')"; ! printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$' || fail "O executavel S1-245 importa uma DLL de runtime nao-sistema."
    require_symbol "func_8011D310"; require_symbol "func_80107A74"; require_symbol "func_80162D68"; require_symbol "func_80137FE8"; require_symbol "func_80138084"; require_symbol "func_8013827C"; require_symbol "func_801102A0"; require_symbol "func_8013CB08"
    ! nm -C "$RUNTIME_EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_8019E6D0$' || fail "O executavel S1-245 contem o candidato em quarentena func_8019E6D0."
    select_python; read_debug_port
}

raw_command() { local output="$1"; shift; "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 || fail "Falha na consulta TCP: $*"; grep -q '"ok":true' "$output" || fail "Resposta TCP invalida em $(basename "$output")."; }
json_integer() { "$PYTHON_BIN" - "$1" "$2" <<'PY'
import json, pathlib, re, sys
text=pathlib.Path(sys.argv[1]).read_text(encoding="utf-8",errors="replace"); field=sys.argv[2]
m=re.search(r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===",text,re.S)
items=[m.group(1).strip()] if m else []
items += [line for line in text.splitlines() if line.startswith("{")]
for item in items:
    try: print(int(json.loads(item).get(field,0) or 0)); break
    except (json.JSONDecodeError, AttributeError, ValueError): pass
else: print(0)
PY
}
collect_static_misses() {
    local prefix output returned total dropped
    prefix="$1"; output="$RUN_DIR/${prefix}_static_text_misses_offset_000000.log"
    raw_command "$output" static_text_misses class=all min_hits=1 offset=0 limit=256
    returned="$(json_integer "$output" returned)"; total="$(json_integer "$output" total)"; dropped="$(json_integer "$output" dropped)"
    (( dropped == 0 && total <= 256 && returned == total )) || fail "Snapshot $prefix de static_text_misses incompleto (total=$total returned=$returned dropped=$dropped)."
}
validate_running_build() { local ping_file; ping_file="$(mktemp)"; raw_command "$ping_file" ping; rm -f "$ping_file"; }
create_run_directory() { local i candidate; mkdir -p "$PROJECT_ROOT/local/telemetry"; for i in $(seq -w 1 99); do candidate="$PROJECT_ROOT/local/telemetry/s1-245-telemetry-$i"; if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi; done; fail "Nao ha run-id livre entre s1-245-telemetry-01 e 99."; }
write_metadata() { local ranges_sha exe_sha; ranges_sha="$(sha256sum "$RANGES_FILE" | awk '{print $1}')"; exe_sha="$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')"; cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-245
root_target=$TARGET
root_range=0x8011D310..0x8011D9B3
expected_caller_ra=$EXPECTED_CALLER_RA
direct_caller=0x8011D060
direct_trace=fn_entry_filter_paged
fn_entry_page_size=$DIRECT_PAGE_SIZE
fn_entry_ring_capacity=$FN_RING_CAP
ranges_sha256=$ranges_sha
runtime_exe_sha256=$exe_sha
runtime_build=buildClean-ucrt-s1-245-tele
mode=Versus
characters=Doctrine Dark x Skullomania
stage=Skullomania
route=round 1 sem inputs ate Replay/Exit apos o segundo round
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}
arm_direct_trace() { raw_command "$RUN_DIR/before_fn_filter.log" fn_filter lo="$TARGET" hi="$TARGET_HI"; raw_command "$RUN_DIR/before_fn_clear.log" fn_clear; raw_command "$RUN_DIR/before_fn_stats.log" fn_stats; }
dump_fn_entries() {
    local prefix="$1" total="$2" start=0 end page=0 lo_hex hi_hex output
    if (( total == 0 )); then raw_command "$RUN_DIR/${prefix}_fn_entry_page_000.log" fn_entry_dump addr_lo="$TARGET" addr_hi="$TARGET_HI" seq_lo=0x0 seq_hi=0x0 count="$DIRECT_PAGE_SIZE"; return; fi
    while (( start < total )); do
        end=$((start + DIRECT_PAGE_SIZE)); (( end > total )) && end="$total"
        lo_hex="$(printf '0x%X' "$start")"; hi_hex="$(printf '0x%X' "$end")"
        output="$RUN_DIR/${prefix}_fn_entry_page_$(printf '%03d' "$page").log"
        raw_command "$output" fn_entry_dump addr_lo="$TARGET" addr_hi="$TARGET_HI" seq_lo="$lo_hex" seq_hi="$hi_hex" count="$DIRECT_PAGE_SIZE"
        start="$end"; page=$((page + 1)); (( page <= 128 )) || fail "Paginacao fn_entry excedeu 128 paginas; interrompida para preservar a saude da build."
    done
}
collect_before() {
    note "Armando cyc_watch e trace direto paginado para $TARGET"
    raw_command "$RUN_DIR/before_cyc_watch_clear.log" cyc_watch_clear
    raw_command "$RUN_DIR/before_cyc_watch_arm.log" cyc_watch pc="$TARGET" n="$WATCH_MAX"
    arm_direct_trace
    note "Coletando BEFORE"
    raw_command "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw_command "$RUN_DIR/before_phase_profile.log" phase_profile window=1
    collect_static_misses before
    raw_command "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
    raw_command "$RUN_DIR/before_fn_stats_after_window.log" fn_stats
    local before_total; before_total="$(json_integer "$RUN_DIR/before_fn_stats_after_window.log" entry_total)"
    dump_fn_entries before "$before_total"
    raw_command "$RUN_DIR/before_cyc_watch.log" cyc_watch_dump
    raw_command "$RUN_DIR/window_cyc_watch_clear.log" cyc_watch_clear
    raw_command "$RUN_DIR/window_cyc_watch_arm.log" cyc_watch pc="$TARGET" n="$WATCH_MAX"
    raw_command "$RUN_DIR/window_fn_clear.log" fn_clear
}
collect_after() {
    local seconds="$1" window="$seconds"
    (( window < 1 )) && window=1; (( window > 60 )) && window=60
    note "Coletando AFTER imediatamente e congelando o trace direto"
    raw_command "$RUN_DIR/after_fn_disable.log" fn_disable
    raw_command "$RUN_DIR/after_fn_stats.log" fn_stats
    local after_total; after_total="$(json_integer "$RUN_DIR/after_fn_stats.log" entry_total)"
    dump_fn_entries after "$after_total"
    raw_command "$RUN_DIR/after_cyc_watch.log" cyc_watch_dump
    raw_command "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw_command "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    raw_command "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw_command "$RUN_DIR/after_phase_profile.log" phase_profile window="$window"
    collect_static_misses after
    raw_command "$RUN_DIR/after_cyc_watch_clear.log" cyc_watch_clear
}
write_summary() { "$PYTHON_BIN" - "$RUN_DIR" "$TARGET" "$EXPECTED_CALLER_RA" "$WATCH_MAX" "$FN_RING_CAP" <<'PY'
import collections,json,pathlib,re,sys
run,target,expected,watch,ring=pathlib.Path(sys.argv[1]),sys.argv[2].upper(),sys.argv[3].upper(),int(sys.argv[4]),int(sys.argv[5])
def payload(name):
    p=run/name
    if not p.exists(): return {}
    t=p.read_text(encoding='utf-8',errors='replace'); m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',t,re.S); rows=[m.group(1).strip()] if m else []; rows += [x for x in t.splitlines() if x.startswith('{')]
    for x in rows:
        try:
            o=json.loads(x)
            if isinstance(o,dict): return o
        except json.JSONDecodeError: pass
    return {}
def integer(v):
    try: return int(v or 0)
    except (ValueError,TypeError): return 0
def misses(prefix): return {str(x.get('pc','')).upper() for x in payload(prefix+'_static_text_misses_offset_000000.log').get('entries',[]) if x.get('pc')}
def trace_entries(prefix):
    result=[]; pages=[]
    for p in sorted(run.glob(prefix+'_fn_entry_page_*.log')):
        d=payload(p.name); pages.append(d); result.extend(d.get('entries',[]))
    return pages,result
bdisp,adisp=payload('before_dispatch_stats.log'),payload('after_dispatch_stats.log'); bdirty,adirty=payload('before_dirty_ram_stats.log'),payload('after_dirty_ram_stats.log'); bpages,bentries=trace_entries('before'); pages,entries=trace_entries('after'); stats=payload('after_fn_stats.log'); bcyc,cyc=payload('before_cyc_watch.log'),payload('after_cyc_watch.log'); lat,phase=payload('after_latency.log'),payload('after_phase_profile.log')
total=integer(stats.get('entry_total')); filtered=integer(stats.get('direct_filtered')); seqs=[integer(x.get('seq')) for x in entries]; unique_seqs=set(seqs); ras=collections.Counter(str(x.get('ra','')).upper() for x in entries if str(x.get('func','')).upper()==target); hits=sum(1 for x in entries if str(x.get('func','')).upper()==target); before_hits=sum(1 for x in bentries if str(x.get('func','')).upper()==target); complete=total <= ring and len(entries) == total and len(unique_seqs) == total and unique_seqs == set(range(total)); cyc_hits=integer(cyc.get('hits')); cyc_max=integer(cyc.get('max_hits') or watch); no_fallback=target not in misses('before') and target not in misses('after'); frame=lat.get('summary',{}).get('frame_period',{}); proof=total>0 and complete and filtered==total and hits==total and ras[expected]==total and no_fallback
lines=[f'# Telemetria {run.name}','', '## Resultado S1-245','',f'- Duracao manual: {payload("duration.json").get("seconds","n/d")} s',f'- Hits fn_entry BEFORE: {before_hits}',f'- Hits fn_entry na janela: {hits}',f'- Páginas fn_entry AFTER: {len(pages)}',f'- fn_entry total/filtrado/capturado: {total}/{filtered}/{len(entries)}',f'- Ring fn_entry sem perda: {"sim" if complete else "nao"}',f'- RA esperado {expected}: {"confirmado em todos os hits" if total and ras[expected] == total else "nao confirmado integralmente"}',f'- Retornos mais comuns: {ras.most_common(5)}',f'- Hits cyc_watch na janela: {cyc_hits}/{cyc_max}',f'- cyc_watch atingiu o limite de 1.024: {"sim (esperado para esta raiz quente)" if cyc_hits >= cyc_max else "nao"}',f'- Funcao nativa alcancada com RA confirmada e sem fallback: {"confirmado" if proof else "insuficiente"}',f'- Delta static_hits: {integer(adisp.get("static_hits"))-integer(bdisp.get("static_hits"))}',f'- Delta miss_total: {integer(adisp.get("miss_total"))-integer(bdisp.get("miss_total"))}','','## Frametime e integridade','',f'- P50/P95/max: {integer(frame.get("p50_us"))/1000:.3f} / {integer(frame.get("p95_us"))/1000:.3f} / {integer(frame.get("max_us"))/1000:.3f} ms',f'- Fases: interpreter={phase.get("interp_share","n/d")}; static={phase.get("static_share","n/d")}; GPU={phase.get("gpu_share","n/d")}',f'- aborts BEFORE/AFTER: {integer(bdirty.get("aborts"))}/{integer(adirty.get("aborts"))}',f'- native_handoffs BEFORE/AFTER: {integer(bdirty.get("native_handoffs"))}/{integer(adirty.get("native_handoffs"))}',f'- text_native_blocked BEFORE/AFTER: {integer(bdirty.get("text_native_blocked"))}/{integer(adirty.get("text_native_blocked"))}',f'- stack_overflows do trace: {integer(stats.get("stack_overflows"))} (diagnostico do observador, nao overflow do jogo)',f'- Alvo presente em static_text_misses: {"nao" if no_fallback else "sim"}','','- O coletor nao compilou, abriu nem fechou o jogo.','']
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}
collect_telemetry() { validate_running_build; trap cleanup_runtime_probes EXIT; create_run_directory; write_metadata; printf '\nArtefato S1-245 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"; printf 'Precondicao: Doctrine Dark P1 x Skullomania P2, cenario Skullomania; round 1 iniciado e sem inputs.\n'; collect_before; local start end seconds; start="$(date +%s)"; printf '\nBEFORE concluido. Jogue normalmente ate a tela Replay/Exit apos o segundo round.\n'; read -r -p 'Na tela Replay/Exit, pare os inputs e pressione Enter para coletar AFTER... ' _; end="$(date +%s)"; seconds=$((end-start)); printf '{"seconds":%d}\n' "$seconds" >"$RUN_DIR/duration.json"; collect_after "$seconds"; write_summary; note "Coleta concluida: $RUN_DIR"; printf 'Resumo: %s/summary.md\nO script nao fechara o jogo.\n' "$RUN_DIR"; }
main() { case "${1:-}" in "") ;; -h|--help) usage; return ;; *) usage; fail "Argumento desconhecido: $1" ;; esac; validate_sources; collect_telemetry; }
main "$@"
