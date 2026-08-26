#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-248-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly TARGET=0x801A9DC0
readonly TARGET_HI=0x801A9FD4
readonly CALLER_RA=0x801A9330
readonly JALR_PC=0x801A9FB4
readonly JALR_RA=0x801A9FBC
readonly POINTER_CELL=0x801BFC68
readonly WATCH_MAX=1024
readonly PAGE_SIZE=2048
readonly FN_RING_CAP=262144
readonly TRACE_MAX=4096
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.s1-248-telemetry-active.state"

PYTHON_BIN=
DEBUG_PORT=
RUN_DIR=
RUN_PHASE=
RUN_START_EPOCH=0
RUN_POINTER_TARGET=0x00000000
PRESERVE_SESSION=0

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/telemetry_before_after_s1_248.sh prepare
  bash tools/telemetry_before_after_s1_248.sh before
  bash tools/telemetry_before_after_s1_248.sh after

Fluxo obrigatorio, sempre na mesma execucao aberta do jogo:

  1. No menu de modos, com Bonus Barril destacado e antes de escolher Guile,
     execute "prepare". Ele valida a build, arma a raiz, o JALR e o ponteiro;
     nao coleta amostras longas e nao consome o relogio do Bonus.
  2. Escolha Guile e entre no Bonus Barril. Quando o cenario estiver ativo,
     sem inputs, execute "before". O trace anterior permanece valido desde o
     menu e uma nova janela e armada para o gameplay.
  3. Jogue o Bonus normalmente. Na tela Bonus Replay/Exit, sem inputs,
     execute "after".

O coletor nao compila, nao abre e nao fecha o jogo.
EOF
}

cleanup() {
    (( PRESERVE_SESSION == 0 )) || return
    if [[ -n "$PYTHON_BIN" && -n "$DEBUG_PORT" && -f "$RAW_TCP" ]]; then
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" cyc_watch_clear >/dev/null 2>&1 || true
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" fn_disable >/dev/null 2>&1 || true
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" fntrace_arm_clear >/dev/null 2>&1 || true
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

require_range() { grep -q "^$1$" "$RANGES_FILE" || fail "Range/funcao ausente: $1"; }
require_symbol() { nm -C "$RUNTIME_EXE" | grep -E "[[:space:]]T[[:space:]]+$1$" >/dev/null || fail "O executavel nao contem $1."; }

validate_build() {
    [[ -v MSYSTEM && "$MSYSTEM" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v objdump >/dev/null || fail "objdump nao encontrado no UCRT64."
    command -v nm >/dev/null || fail "nm nao encontrado no UCRT64."
    command -v sha256sum >/dev/null || fail "sha256sum nao encontrado no UCRT64."
    [[ -f "$GAME_TOML" && -f "$RANGES_FILE" && -f "$RAW_TCP" && -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] || fail "Arquivos da build S1-248 de telemetria estao ausentes."
    require_range "F 801A9DC0"; require_range "R 801A9DC0 214"
    require_range "F 801A92B8"; require_range "R 801A92B8 E4"
    require_range "F 801A7ACC"; require_range "F 801A7C34"; require_range "F 8019F3E4"; require_range "F 8019F1F0"
    require_range "F 801A9FD4"; require_range "F 801A76D4"; require_range "F 801A76EC"; require_range "F 801A7704"
    ! grep -q '^F 8019E6D0$' "$RANGES_FILE" || fail "A funcao em quarentena 0x8019E6D0 apareceu nos fontes."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1035 ]] || fail "A quantidade de funcoes geradas nao corresponde ao S1-248 esperado (1035)."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" || fail "A build S1-248 nao esta configurada como RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" || fail "A build S1-248 nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" || fail "A build S1-248 nao possui PSX_STATIC_RUNTIME=ON."
    local imports
    imports="$(objdump -p "$RUNTIME_EXE" | awk '/DLL Name:/ { print $3 }')"
    ! printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$' || fail "O executavel S1-248 importa uma DLL de runtime nao-sistema."
    require_symbol func_801A9DC0; require_symbol func_801A92B8
    require_symbol func_801A7ACC; require_symbol func_801A7C34; require_symbol func_8019F3E4; require_symbol func_8019F1F0
    require_symbol func_801A9FD4; require_symbol func_801A76D4; require_symbol func_801A76EC; require_symbol func_801A7704
    ! nm -C "$RUNTIME_EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_8019E6D0$' || fail "O executavel contem o candidato em quarentena func_8019E6D0."
    select_python
    read_debug_port
}

raw() {
    local output="$1"
    shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 || fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" || fail "Resposta TCP invalida em $(basename "$output")."
}

integer() {
    "$PYTHON_BIN" - "$1" "$2" <<'PY'
import json,pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace')
field=sys.argv[2]
m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
rows=[m.group(1).strip()] if m else []
rows += [x for x in text.splitlines() if x.startswith('{')]
for row in rows:
    try:
        print(int(json.loads(row).get(field,0) or 0)); break
    except (ValueError,TypeError,json.JSONDecodeError):
        pass
else: print(0)
PY
}

pointer_target() {
    "$PYTHON_BIN" - "$1" <<'PY'
import json,pathlib,re,struct,sys
text=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace')
m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
rows=[m.group(1).strip()] if m else []
rows += [x for x in text.splitlines() if x.startswith('{')]
for row in rows:
    try:
        data=json.loads(row)
        raw=bytes.fromhex(str(data.get('hex','')))
        if data.get('ok') and len(raw)==4:
            print(f'0x{struct.unpack("<I",raw)[0]:08X}'); break
    except (ValueError,TypeError,json.JSONDecodeError,struct.error):
        pass
else: print('0x00000000')
PY
}

target_hi() {
    "$PYTHON_BIN" - "$1" <<'PY'
import sys
print(f'0x{(int(sys.argv[1],16)+4)&0xffffffff:08X}')
PY
}

traceable_target() {
    [[ "$1" =~ ^0x80[01][0-9A-F]{4}[048C]$ ]]
}

static_misses() {
    local prefix="$1" output returned total dropped
    output="$RUN_DIR/${prefix}_static_text_misses_offset_000000.log"
    raw "$output" static_text_misses class=all min_hits=1 offset=0 limit=256
    returned="$(integer "$output" returned)"
    total="$(integer "$output" total)"
    dropped="$(integer "$output" dropped)"
    (( dropped == 0 && total <= 256 && returned == total )) || fail "Snapshot $prefix de static_text_misses incompleto (total=$total returned=$returned dropped=$dropped)."
}

make_run_dir() {
    local n candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for n in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-248-telemetry-$n"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi
    done
    fail "Nao ha run-id livre entre s1-248-telemetry-01 e 99."
}

write_state() {
    local phase="$1"
    umask 077
    printf 'run_dir=%s\nphase=%s\nstart_epoch=%s\npointer_target=%s\n' "$RUN_DIR" "$phase" "$RUN_START_EPOCH" "$RUN_POINTER_TARGET" >"$STATE_FILE"
    RUN_PHASE="$phase"
}

read_state() {
    [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta S1-248 preparada. Execute primeiro: bash tools/telemetry_before_after_s1_248.sh prepare"
    RUN_DIR="$(awk -F= '$1 == "run_dir" { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE")"
    RUN_PHASE="$(awk -F= '$1 == "phase" { print $2; exit }' "$STATE_FILE")"
    RUN_START_EPOCH="$(awk -F= '$1 == "start_epoch" { print $2; exit }' "$STATE_FILE")"
    RUN_POINTER_TARGET="$(awk -F= '$1 == "pointer_target" { print $2; exit }' "$STATE_FILE")"
    [[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] || fail "Estado da coleta S1-248 invalido: run_dir ausente."
    case "$RUN_DIR" in "$PROJECT_ROOT"/local/telemetry/s1-248-telemetry-*) ;; *) fail "Estado da coleta S1-248 invalido: diretorio fora de local/telemetry." ;; esac
    [[ "$RUN_PHASE" == prepared || "$RUN_PHASE" == before ]] || fail "Estado da coleta S1-248 invalido: fase '$RUN_PHASE'."
    [[ "$RUN_START_EPOCH" =~ ^[0-9]+$ ]] || fail "Estado da coleta S1-248 invalido: start_epoch."
    [[ "$RUN_POINTER_TARGET" =~ ^0x[0-9A-F]{8}$ ]] || fail "Estado da coleta S1-248 invalido: pointer_target."
}

clear_state() { rm -f "$STATE_FILE"; }

metadata() {
    cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-248
root_target=$TARGET
root_range=0x801A9DC0..0x801A9FD3
known_caller=0x801A92B8
caller_jalr=0x801A9328
caller_return_address=$CALLER_RA
jalr_site=$JALR_PC
jalr_return_address=$JALR_RA
callback_pointer_cell=$POINTER_CELL
ranges_sha256=$(sha256sum "$RANGES_FILE" | awk '{print $1}')
runtime_exe_sha256=$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')
runtime_build=buildClean-ucrt-s1-248-tele
mode=Bonus Barril
character=Guile
route=prepare no menu Bonus antes de escolher Guile; BEFORE no cenario ativo sem inputs; eliminar barris; AFTER na tela Bonus Replay/Exit sem inputs
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

arm_trace() {
    local prefix="$1" callback="$2"
    raw "$RUN_DIR/${prefix}_fntrace_arm_clear.log" fntrace_arm_clear
    raw "$RUN_DIR/${prefix}_fntrace_arm_root.log" fntrace_arm target="$TARGET"
    if traceable_target "$callback"; then raw "$RUN_DIR/${prefix}_fntrace_arm_callback.log" fntrace_arm target="$callback"; fi
    raw "$RUN_DIR/${prefix}_fntrace_armed.log" fntrace_armed
    raw "$RUN_DIR/${prefix}_fntrace_clear.log" fntrace_clear
}

dump_trace() {
    local prefix="$1" callback="$2" hi
    raw "$RUN_DIR/${prefix}_fntrace_root.log" fntrace_dump target_lo="$TARGET" target_hi="$TARGET_HI" count="$TRACE_MAX"
    if traceable_target "$callback"; then
        hi="$(target_hi "$callback")"
        raw "$RUN_DIR/${prefix}_fntrace_callback.log" fntrace_dump target_lo="$callback" target_hi="$hi" count="$TRACE_MAX"
    else
        printf '{"ok":true,"target":"%s","entries":[],"emitted":0,"note":"ponteiro nulo ou fora do texto"}\n' "$callback" >"$RUN_DIR/${prefix}_fntrace_callback.log"
    fi
}

dump_entries() {
    local prefix="$1" total="$2" start=0 end page=0 lo hi output
    if (( total == 0 )); then
        raw "$RUN_DIR/${prefix}_fn_entry_page_000.log" fn_entry_dump addr_lo="$TARGET" addr_hi="$TARGET_HI" seq_lo=0x0 seq_hi=0x0 count="$PAGE_SIZE"
        return
    fi
    while (( start < total )); do
        end=$((start + PAGE_SIZE)); (( end > total )) && end="$total"
        lo="$(printf '0x%X' "$start")"; hi="$(printf '0x%X' "$end")"
        output="$RUN_DIR/${prefix}_fn_entry_page_$(printf '%03d' "$page").log"
        raw "$output" fn_entry_dump addr_lo="$TARGET" addr_hi="$TARGET_HI" seq_lo="$lo" seq_hi="$hi" count="$PAGE_SIZE"
        start="$end"; page=$((page + 1))
        (( page <= 128 )) || fail "Paginacao fn_entry excedeu 128 paginas."
    done
}

collect_before() {
    note "Coletando BEFORE com instrumentacao armada desde o menu"
    raw "$RUN_DIR/before_pointer_cell.log" read_ram addr="$POINTER_CELL" len=4
    RUN_POINTER_TARGET="$(pointer_target "$RUN_DIR/before_pointer_cell.log")"
    raw "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/before_phase_profile.log" phase_profile window=1
    static_misses before
    raw "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/before_fn_stats.log" fn_stats
    dump_entries before "$(integer "$RUN_DIR/before_fn_stats.log" entry_total)"
    dump_trace before "$RUN_POINTER_TARGET"
    raw "$RUN_DIR/before_jalr_cyc_watch.log" cyc_watch_dump
    raw "$RUN_DIR/window_cyc_watch_clear.log" cyc_watch_clear
    raw "$RUN_DIR/window_cyc_watch_arm.log" cyc_watch pc="$JALR_PC" n="$WATCH_MAX"
    raw "$RUN_DIR/window_fn_clear.log" fn_clear
    arm_trace window "$RUN_POINTER_TARGET"
}

collect_after() {
    local seconds="$1" window="$seconds"
    (( window < 1 )) && window=1; (( window > 60 )) && window=60
    note "Coletando AFTER imediatamente e congelando os traces"
    raw "$RUN_DIR/after_fn_disable.log" fn_disable
    raw "$RUN_DIR/after_pointer_cell.log" read_ram addr="$POINTER_CELL" len=4
    raw "$RUN_DIR/after_fn_stats.log" fn_stats
    dump_entries after "$(integer "$RUN_DIR/after_fn_stats.log" entry_total)"
    dump_trace after "$RUN_POINTER_TARGET"
    raw "$RUN_DIR/after_jalr_cyc_watch.log" cyc_watch_dump
    raw "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/after_phase_profile.log" phase_profile window="$window"
    static_misses after
    raw "$RUN_DIR/after_fntrace_arm_clear.log" fntrace_arm_clear
    raw "$RUN_DIR/after_cyc_watch_clear.log" cyc_watch_clear
}

summary() {
    "$PYTHON_BIN" - "$RUN_DIR" "$TARGET" "$CALLER_RA" "$JALR_RA" "$WATCH_MAX" "$FN_RING_CAP" <<'PY'
import collections,json,pathlib,re,struct,sys
run,target,caller_ra,jalr_ra,watch,cap=pathlib.Path(sys.argv[1]),sys.argv[2].upper(),sys.argv[3].upper(),sys.argv[4].upper(),int(sys.argv[5]),int(sys.argv[6])
def payload(name):
    p=run/name
    if not p.exists(): return {}
    text=p.read_text(encoding='utf-8',errors='replace')
    m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    rows=[m.group(1).strip()] if m else []
    rows += [x for x in text.splitlines() if x.startswith('{')]
    for row in rows:
        try:
            data=json.loads(row)
            if isinstance(data,dict): return data
        except json.JSONDecodeError: pass
    return {}
def num(value):
    try:return int(value or 0)
    except (ValueError,TypeError):return 0
def entries(prefix):
    result=[]
    for p in sorted(run.glob(prefix+'_fn_entry_page_*.log')): result += payload(p.name).get('entries',[])
    return result
def missed(prefix): return {str(x.get('pc','')).upper() for x in payload(prefix+'_static_text_misses_offset_000000.log').get('entries',[]) if x.get('pc')}
def pointer(name):
    try:
        raw=bytes.fromhex(str(payload(name).get('hex','')))
        return f'0x{struct.unpack("<I",raw)[0]:08X}' if len(raw)==4 else '0x00000000'
    except (ValueError,TypeError,struct.error): return '0x00000000'
def complete(rows,total):
    seqs={num(e.get('seq')) for e in rows}
    return total<=cap and len(rows)==total and len(seqs)==total and seqs==set(range(total))
bdisp,adisp=payload('before_dispatch_stats.log'),payload('after_dispatch_stats.log')
bdirty,adirty=payload('before_dirty_ram_stats.log'),payload('after_dirty_ram_stats.log')
bstats,astats=payload('before_fn_stats.log'),payload('after_fn_stats.log')
bentries,aentries=entries('before'),entries('after')
btotal,bfiltered=num(bstats.get('entry_total')),num(bstats.get('direct_filtered'))
atotal,afiltered=num(astats.get('entry_total')),num(astats.get('direct_filtered'))
broot=[e for e in bentries if str(e.get('func','')).upper()==target]
aroot=[e for e in aentries if str(e.get('func','')).upper()==target]
all_root=broot+aroot
root_ras=collections.Counter(str(e.get('ra','')).upper() for e in all_root)
bcomplete,acomplete=complete(bentries,btotal),complete(aentries,atotal)
broot_trace=payload('before_fntrace_root.log').get('entries',[])
aroot_trace=payload('after_fntrace_root.log').get('entries',[])
root_trace_hits=sum(1 for e in broot_trace+aroot_trace if str(e.get('target','')).upper()==target)
bcallback=payload('before_fntrace_callback.log').get('entries',[])
acallback=payload('after_fntrace_callback.log').get('entries',[])
callback_rows=bcallback+acallback
callback_ras=collections.Counter(str(e.get('ra','')).upper() for e in callback_rows)
bcyc,acyc=payload('before_jalr_cyc_watch.log'),payload('after_jalr_cyc_watch.log')
bjalr,ajalr=num(bcyc.get('hits')),num(acyc.get('hits'))
before_ptr,after_ptr=pointer('before_pointer_cell.log'),pointer('after_pointer_cell.log')
bmiss,amiss=missed('before'),missed('after')
no_root_fallback=target not in bmiss and target not in amiss
jalr_return_seen=jalr_ra in bmiss or jalr_ra in amiss
root_proof=bool(all_root) and bcomplete and acomplete and bfiltered==btotal and afiltered==atotal and root_ras[caller_ra]==len(all_root) and no_root_fallback
jalr_exercised=(bjalr+ajalr)>0
gate=root_proof and jalr_exercised
latency=payload('after_latency.log'); phase=payload('after_phase_profile.log'); frame=latency.get('summary',{}).get('frame_period',{})
lines=[f'# Telemetria {run.name}','', '## Resultado S1-248','',
f'- Duracao manual: {payload("duration.json").get("seconds","n/d")} s',
f'- Hits fn_entry da raiz prepare->BEFORE: {len(broot)}',
f'- Hits fn_entry da raiz BEFORE->AFTER: {len(aroot)}',
f'- fn_entry pre total/filtrado/capturado={btotal}/{bfiltered}/{len(bentries)}; janela={atotal}/{afiltered}/{len(aentries)}',
f'- Ring fn_entry sem perda: pre={"sim" if bcomplete else "nao"}; janela={"sim" if acomplete else "nao"}',
f'- RA chamadora esperada {caller_ra}: {root_ras[caller_ra]}/{len(all_root)}; RAs={root_ras.most_common(5)}',
f'- Hits fntrace da raiz: {root_trace_hits}',
f'- Funcao nativa alcancada com RA integral e sem fallback da raiz: {"confirmado" if root_proof else "insuficiente"}',
'', '## JALR guardado','',
f'- Hits no JALR 0x801A9FB4: prepare->BEFORE={bjalr}/{num(bcyc.get("max_hits") or watch)}; BEFORE->AFTER={ajalr}/{num(acyc.get("max_hits") or watch)}',
f'- Celula 0x801BFC68 no BEFORE/AFTER: {before_ptr} / {after_ptr}',
f'- fntrace do alvo apontado no BEFORE: {len(callback_rows)} hits; RA esperada {jalr_ra}: {callback_ras[jalr_ra]}; RAs={callback_ras.most_common(5)}',
f'- Retorno {jalr_ra} no ledger de misses: {"sim (fallback CPS do alvo dinamico foi percorrido)" if jalr_return_seen else "nao observado"}',
f'- Gate raiz + JALR exercitado: {"confirmado" if gate else "insuficiente"}',
f'- Delta static_hits: {num(adisp.get("static_hits"))-num(bdisp.get("static_hits"))}',
f'- Delta miss_total: {num(adisp.get("miss_total"))-num(bdisp.get("miss_total"))}',
'', '## Frametime e integridade','',
f'- P50/P95/max: {num(frame.get("p50_us"))/1000:.3f} / {num(frame.get("p95_us"))/1000:.3f} / {num(frame.get("max_us"))/1000:.3f} ms',
f'- Fases: interpreter={phase.get("interp_share","n/d")}; static={phase.get("static_share","n/d")}; GPU={phase.get("gpu_share","n/d")}',
f'- aborts BEFORE/AFTER: {num(bdirty.get("aborts"))}/{num(adirty.get("aborts"))}',
f'- native_handoffs BEFORE/AFTER: {num(bdirty.get("native_handoffs"))}/{num(adirty.get("native_handoffs"))}',
f'- text_native_blocked BEFORE/AFTER: {num(bdirty.get("text_native_blocked"))}/{num(adirty.get("text_native_blocked"))}',
f'- Raiz presente em static_text_misses: {"nao" if no_root_fallback else "sim"}',
'', '- O coletor nao compilou, abriu nem fechou o jogo.', '']
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

prepare() {
    validate_build
    trap cleanup EXIT
    [[ ! -e "$STATE_FILE" ]] || fail "Ja existe uma coleta S1-248 pendente. Conclua com AFTER antes de preparar outra."
    make_run_dir
    metadata
    printf '\nArtefato S1-248 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"
    printf 'Precondicao: menu de modos com Bonus Barril destacado; Guile ainda nao escolhido.\n'
    note "Armando raiz, JALR e observador do ponteiro no menu"
    raw "$RUN_DIR/prepare_pointer_cell.log" read_ram addr="$POINTER_CELL" len=4
    RUN_POINTER_TARGET="$(pointer_target "$RUN_DIR/prepare_pointer_cell.log")"
    raw "$RUN_DIR/prepare_cyc_watch_clear.log" cyc_watch_clear
    raw "$RUN_DIR/prepare_cyc_watch_arm.log" cyc_watch pc="$JALR_PC" n="$WATCH_MAX"
    raw "$RUN_DIR/prepare_fn_filter.log" fn_filter lo="$TARGET" hi="$TARGET_HI"
    raw "$RUN_DIR/prepare_fn_clear.log" fn_clear
    arm_trace prepare "$RUN_POINTER_TARGET"
    write_state prepared
    PRESERVE_SESSION=1
    note "Preparacao concluida: escolha Guile, entre no Bonus e execute BEFORE quando o cenario estiver ativo"
}

before_phase() {
    validate_build
    trap cleanup EXIT
    read_state
    [[ "$RUN_PHASE" == prepared ]] || fail "A coleta esta na fase '$RUN_PHASE'; execute AFTER, nao BEFORE."
    printf '\nInstrumentacao S1-248 mantida desde o menu. Coletando BEFORE no cenario Bonus ativo.\n'
    collect_before
    RUN_START_EPOCH="$(date +%s)"
    write_state before
    PRESERVE_SESSION=1
    note "BEFORE concluido. Jogue o Bonus; na tela Replay/Exit execute AFTER"
}

after_phase() {
    validate_build
    trap cleanup EXIT
    read_state
    [[ "$RUN_PHASE" == before ]] || fail "A coleta ainda esta na fase '$RUN_PHASE'; execute BEFORE somente depois de entrar no cenario Bonus."
    local end seconds
    end="$(date +%s)"; seconds=$((end-RUN_START_EPOCH))
    printf '{"seconds":%d}\n' "$seconds" >"$RUN_DIR/duration.json"
    collect_after "$seconds"
    summary
    clear_state
    note "Coleta concluida: $RUN_DIR"
    printf 'Resumo: %s/summary.md\nO script nao fechara o jogo.\n' "$RUN_DIR"
}

main() {
    [[ $# == 1 ]] || { usage; fail "Informe uma fase: prepare, before ou after."; }
    case "$1" in
        prepare) prepare ;;
        before) before_phase ;;
        after) after_phase ;;
        -h|--help) usage ;;
        *) usage; fail "Fase desconhecida: $1" ;;
    esac
}
main "$@"
