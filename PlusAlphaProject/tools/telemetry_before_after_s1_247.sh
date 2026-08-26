#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-247-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly TARGET=0x801A92B8
readonly TARGET_HI=0x801A939C
readonly JALR_RA_1=0x801A9330
readonly JALR_RA_2=0x801A9364
readonly WATCH_MAX=1024
readonly PAGE_SIZE=2048
readonly FN_RING_CAP=262144
readonly TRACE_MAX=4096
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.s1-247-telemetry-active.state"
readonly TRACE_SPEC=$'root 0x801A92B8 0x801A92BC\ncb_801a74d0 0x801A74D0 0x801A74D4\ncb_801a74f8 0x801A74F8 0x801A74FC\ncb_801a9dc0 0x801A9DC0 0x801A9DC4\ncb_801aa448 0x801AA448 0x801AA44C'

PYTHON_BIN=
DEBUG_PORT=
RUN_DIR=
RUN_PHASE=
RUN_START_EPOCH=0
PRESERVE_SESSION=0

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64:

  bash tools/telemetry_before_after_s1_247.sh prepare
  bash tools/telemetry_before_after_s1_247.sh before
  bash tools/telemetry_before_after_s1_247.sh after

Fluxo obrigatorio, sempre na mesma execucao aberta do jogo:

  1. No menu de modos, com Bonus Barril destacado e antes de escolher Guile,
     execute "prepare". Ele apenas valida e arma a instrumentacao; nao coleta
     amostras e nao consome o relogio do Bonus.
  2. Escolha Guile e entre no Bonus Barril. Quando o cenario estiver ativo,
     sem inputs, execute "before". Essa fase captura tambem a atividade que
     ocorreu desde o menu, inclusive selecao e carregamento, e arma a janela
     exclusiva do gameplay.
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
    [[ -f "$GAME_TOML" && -f "$RANGES_FILE" && -f "$RAW_TCP" && -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] || fail "Arquivos da build S1-247 de telemetria estao ausentes."
    require_range "F 801A92B8"; require_range "R 801A92B8 E4"
    require_range "F 801A7CB4"; require_range "F 801A8E00"; require_range "F 801A8E50"; require_range "F 8019F464"
    require_range "F 8011D030"; require_range "F 8011D078"; require_range "F 8011D310"; require_range "F 80107A74"; require_range "F 80162D68"; require_range "F 80137FE8"; require_range "F 80138084"; require_range "F 8013827C"; require_range "F 801102A0"; require_range "F 8013CB08"
    ! grep -q '^F 8019E6D0$' "$RANGES_FILE" || fail "A funcao em quarentena 0x8019E6D0 apareceu nos fontes."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1034 ]] || fail "A quantidade de funcoes geradas nao corresponde ao S1-247 esperado (1034)."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" || fail "A build S1-247 nao esta configurada como RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" || fail "A build S1-247 nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" || fail "A build S1-247 nao possui PSX_STATIC_RUNTIME=ON."
    local imports
    imports="$(objdump -p "$RUNTIME_EXE" | awk '/DLL Name:/ { print $3 }')"
    ! printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$' || fail "O executavel S1-247 importa uma DLL de runtime nao-sistema."
    require_symbol func_801A92B8; require_symbol func_801A7CB4; require_symbol func_801A8E00; require_symbol func_801A8E50; require_symbol func_8019F464
    require_symbol func_8011D030; require_symbol func_8011D078; require_symbol func_8011D310; require_symbol func_80107A74; require_symbol func_80162D68; require_symbol func_80137FE8; require_symbol func_80138084; require_symbol func_8013827C; require_symbol func_801102A0; require_symbol func_8013CB08
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

static_misses() {
    local prefix="$1" output returned total dropped
    output="$RUN_DIR/$prefix"_static_text_misses_offset_000000.log
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
        candidate="$PROJECT_ROOT/local/telemetry/s1-247-telemetry-$n"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi
    done
    fail "Nao ha run-id livre entre s1-247-telemetry-01 e 99."
}

write_state() {
    local phase="$1"
    umask 077
    printf 'run_dir=%s\nphase=%s\nstart_epoch=%s\n' "$RUN_DIR" "$phase" "$RUN_START_EPOCH" >"$STATE_FILE"
    RUN_PHASE="$phase"
}

read_state() {
    [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta S1-247 preparada. Execute primeiro: bash tools/telemetry_before_after_s1_247.sh prepare"
    RUN_DIR="$(awk -F= '$1 == "run_dir" { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE")"
    RUN_PHASE="$(awk -F= '$1 == "phase" { print $2; exit }' "$STATE_FILE")"
    RUN_START_EPOCH="$(awk -F= '$1 == "start_epoch" { print $2; exit }' "$STATE_FILE")"
    [[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] || fail "Estado da coleta S1-247 invalido: run_dir ausente."
    case "$RUN_DIR" in "$PROJECT_ROOT"/local/telemetry/s1-247-telemetry-*) ;; *) fail "Estado da coleta S1-247 invalido: diretorio fora de local/telemetry." ;; esac
    [[ "$RUN_PHASE" == prepared || "$RUN_PHASE" == before ]] || fail "Estado da coleta S1-247 invalido: fase '$RUN_PHASE'."
    [[ "$RUN_START_EPOCH" =~ ^[0-9]+$ ]] || fail "Estado da coleta S1-247 invalido: start_epoch."
}

clear_state() {
    rm -f "$STATE_FILE"
}

metadata() {
    cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-247
root_target=$TARGET
root_range=0x801A92B8..0x801A939B
callback_registration_sites=0x801A8E30,0x801A8EB8
direct_callee=0x801A7CB4
jalr_sites=0x801A9328,0x801A935C
jalr_return_addresses=$JALR_RA_1,$JALR_RA_2
callback_pointer_cells=0x801BF958,0x801BF954
known_callback_targets=0x801A74D0,0x801A74F8,0x801A9DC0,0x801AA448
ranges_sha256=$(sha256sum "$RANGES_FILE" | awk '{print $1}')
runtime_exe_sha256=$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')
runtime_build=buildClean-ucrt-s1-247-tele
mode=Bonus Barril
character=Guile
route=prepare no menu Bonus antes de escolher Guile; BEFORE no cenario ativo sem inputs; eliminar barris; AFTER na tela Bonus Replay/Exit sem inputs
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

arm_fntrace() {
    local prefix="$1" label lo hi
    raw "$RUN_DIR/$prefix"_fntrace_arm_clear.log fntrace_arm_clear
    while read -r label lo hi; do raw "$RUN_DIR/$prefix"_fntrace_arm_"$label".log fntrace_arm target="$lo"; done <<<"$TRACE_SPEC"
    raw "$RUN_DIR/$prefix"_fntrace_armed.log fntrace_armed
    raw "$RUN_DIR/$prefix"_fntrace_clear.log fntrace_clear
}

dump_fntrace() {
    local prefix="$1" label lo hi
    while read -r label lo hi; do raw "$RUN_DIR/$prefix"_fntrace_"$label".log fntrace_dump target_lo="$lo" target_hi="$hi" count="$TRACE_MAX"; done <<<"$TRACE_SPEC"
}

dump_entries() {
    local prefix="$1" total="$2" start=0 end page=0 lo hi output
    if (( total == 0 )); then
        raw "$RUN_DIR/$prefix"_fn_entry_page_000.log fn_entry_dump addr_lo="$TARGET" addr_hi="$TARGET_HI" seq_lo=0x0 seq_hi=0x0 count="$PAGE_SIZE"
        return
    fi
    while (( start < total )); do
        end=$((start + PAGE_SIZE)); (( end > total )) && end="$total"
        lo="$(printf '0x%X' "$start")"; hi="$(printf '0x%X' "$end")"
        output="$RUN_DIR/$prefix"_fn_entry_page_"$(printf '%03d' "$page")".log
        raw "$output" fn_entry_dump addr_lo="$TARGET" addr_hi="$TARGET_HI" seq_lo="$lo" seq_hi="$hi" count="$PAGE_SIZE"
        start="$end"; page=$((page + 1))
        (( page <= 128 )) || fail "Paginacao fn_entry excedeu 128 paginas."
    done
}

collect_before() {
    note "Coletando BEFORE com a instrumentacao armada no menu"
    raw "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/before_phase_profile.log" phase_profile window=1
    static_misses before
    raw "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/before_fn_stats.log" fn_stats
    dump_entries before "$(integer "$RUN_DIR/before_fn_stats.log" entry_total)"
    dump_fntrace before
    raw "$RUN_DIR/before_cyc_watch.log" cyc_watch_dump
    raw "$RUN_DIR/window_cyc_watch_clear.log" cyc_watch_clear
    raw "$RUN_DIR/window_cyc_watch_arm.log" cyc_watch pc="$TARGET" n="$WATCH_MAX"
    raw "$RUN_DIR/window_fn_clear.log" fn_clear
    raw "$RUN_DIR/window_fntrace_clear.log" fntrace_clear
}

collect_after() {
    local seconds="$1" window="$seconds"
    (( window < 1 )) && window=1; (( window > 60 )) && window=60
    note "Coletando AFTER imediatamente e congelando o trace"
    raw "$RUN_DIR/after_fn_disable.log" fn_disable
    raw "$RUN_DIR/after_fn_stats.log" fn_stats
    dump_entries after "$(integer "$RUN_DIR/after_fn_stats.log" entry_total)"
    dump_fntrace after
    raw "$RUN_DIR/after_cyc_watch.log" cyc_watch_dump
    raw "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/after_phase_profile.log" phase_profile window="$window"
    static_misses after
    raw "$RUN_DIR/after_fntrace_arm_clear.log" fntrace_arm_clear
    raw "$RUN_DIR/after_cyc_watch_clear.log" cyc_watch_clear
}

summary() {
    "$PYTHON_BIN" - "$RUN_DIR" "$TARGET" "$JALR_RA_1" "$JALR_RA_2" "$WATCH_MAX" "$FN_RING_CAP" <<'PY'
import collections,json,pathlib,re,sys
run,target,ra1,ra2,watch,cap=pathlib.Path(sys.argv[1]),sys.argv[2].upper(),sys.argv[3].upper(),sys.argv[4].upper(),int(sys.argv[5]),int(sys.argv[6])
labels=['root','cb_801a74d0','cb_801a74f8','cb_801a9dc0','cb_801aa448']
def payload(name):
    p=run/name
    if not p.exists(): return {}
    t=p.read_text(encoding='utf-8',errors='replace')
    m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',t,re.S)
    rows=[m.group(1).strip()] if m else []
    rows += [x for x in t.splitlines() if x.startswith('{')]
    for row in rows:
        try:
            d=json.loads(row)
            if isinstance(d,dict): return d
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
bdisp,adisp=payload('before_dispatch_stats.log'),payload('after_dispatch_stats.log')
bdirty,adirty=payload('before_dirty_ram_stats.log'),payload('after_dirty_ram_stats.log')
bstats,stats=payload('before_fn_stats.log'),payload('after_fn_stats.log')
bentries,aentries=entries('before'),entries('after')
btotal,bfiltered=num(bstats.get('entry_total')),num(bstats.get('direct_filtered'))
total,filtered=num(stats.get('entry_total')),num(stats.get('direct_filtered'))
pre_root_entries=[e for e in bentries if str(e.get('func','')).upper()==target]
root_entries=[e for e in aentries if str(e.get('func','')).upper()==target]
def complete(entries,total):
    seqs={num(e.get('seq')) for e in entries}
    return total<=cap and len(entries)==total and len(seqs)==total and seqs==set(range(total))
bcomplete,complete_after=complete(bentries,btotal),complete(aentries,total)
root_ras=collections.Counter(str(e.get('ra','')).upper() for e in pre_root_entries+root_entries)
before_root_trace=payload('before_fntrace_root.log').get('entries',[])
after_root_trace=payload('after_fntrace_root.log').get('entries',[])
root_trace_hits=sum(1 for e in before_root_trace+after_root_trace if str(e.get('target','')).upper()==target)
callback_rows=[]; callback_ra_hits=0
for label in labels[1:]:
    rows=payload('before_fntrace_'+label+'.log').get('entries',[])+payload('after_fntrace_'+label+'.log').get('entries',[])
    ras=collections.Counter(str(e.get('ra','')).upper() for e in rows)
    expected=ras[ra1]+ras[ra2]; callback_ra_hits += expected
    callback_rows.append((label,len(rows),expected,ras.most_common(3)))
bcyc=payload('before_cyc_watch.log'); cyc=payload('after_cyc_watch.log'); latency=payload('after_latency.log'); phase=payload('after_phase_profile.log')
frame=latency.get('summary',{}).get('frame_period',{})
no_fallback=target not in missed('before') and target not in missed('after')
all_root_entries=pre_root_entries+root_entries
proof=bool(all_root_entries) and bcomplete and complete_after and bfiltered==btotal and filtered==total and root_trace_hits>0 and no_fallback
lines=[f'# Telemetria {run.name}','', '## Resultado S1-247','',
f'- Duracao manual: {payload("duration.json").get("seconds","n/d")} s',
f'- Hits fn_entry desde o prepare ate o BEFORE: {len(pre_root_entries)}',
f'- Hits fn_entry na janela BEFORE->AFTER: {len(root_entries)}',
f'- fn_entry pre: total/filtrado/capturado={btotal}/{bfiltered}/{len(bentries)}; janela: total/filtrado/capturado={total}/{filtered}/{len(aentries)}',
f'- Ring fn_entry sem perda: pre={"sim" if bcomplete else "nao"}; janela={"sim" if complete_after else "nao"}',
f'- Retornos da entrada callback: {root_ras.most_common(5)}',
f'- Hits fntrace da raiz: {root_trace_hits}',
f'- Hits cyc_watch: prepare->BEFORE={num(bcyc.get("hits"))}/{num(bcyc.get("max_hits") or watch)}; BEFORE->AFTER={num(cyc.get("hits"))}/{num(cyc.get("max_hits") or watch)}',
f'- Callback dinamico conhecido com RA de JALR confirmada: {"sim" if callback_ra_hits else "nao observado (nao reprova; callbacks sao opcionais)"}',
f'- Funcao nativa alcancada sem fallback: {"confirmado" if proof else "insuficiente"}',
f'- Delta static_hits: {num(adisp.get("static_hits"))-num(bdisp.get("static_hits"))}',
f'- Delta miss_total: {num(adisp.get("miss_total"))-num(bdisp.get("miss_total"))}',
'', '## Callbacks dinamicos conhecidos','', '| Alvo | Hits | RA 0x801A9330/0x801A9364 | RAs mais comuns |', '| --- | ---: | ---: | --- |']
for label,count,expected,ras in callback_rows: lines.append(f'| {label} | {count} | {expected} | {ras} |')
lines += ['', '## Frametime e integridade','',
f'- P50/P95/max: {num(frame.get("p50_us"))/1000:.3f} / {num(frame.get("p95_us"))/1000:.3f} / {num(frame.get("max_us"))/1000:.3f} ms',
f'- Fases: interpreter={phase.get("interp_share","n/d")}; static={phase.get("static_share","n/d")}; GPU={phase.get("gpu_share","n/d")}',
f'- aborts BEFORE/AFTER: {num(bdirty.get("aborts"))}/{num(adirty.get("aborts"))}',
f'- native_handoffs BEFORE/AFTER: {num(bdirty.get("native_handoffs"))}/{num(adirty.get("native_handoffs"))}',
f'- text_native_blocked BEFORE/AFTER: {num(bdirty.get("text_native_blocked"))}/{num(adirty.get("text_native_blocked"))}',
f'- Alvo presente em static_text_misses: {"nao" if no_fallback else "sim"}',
'', '- O coletor nao compilou, abriu nem fechou o jogo.', '']
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

prepare() {
    validate_build
    trap cleanup EXIT
    [[ ! -e "$STATE_FILE" ]] || fail "Ja existe uma coleta S1-247 pendente. Conclua com AFTER antes de preparar outra."
    make_run_dir
    metadata
    printf '\nArtefato S1-247 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"
    printf 'Precondicao: menu de modos com Bonus Barril destacado; Guile ainda nao escolhido.\n'
    note "Armando a instrumentacao no menu para capturar selecao e carregamento"
    raw "$RUN_DIR/prepare_cyc_watch_clear.log" cyc_watch_clear
    raw "$RUN_DIR/prepare_cyc_watch_arm.log" cyc_watch pc="$TARGET" n="$WATCH_MAX"
    raw "$RUN_DIR/prepare_fn_filter.log" fn_filter lo="$TARGET" hi="$TARGET_HI"
    raw "$RUN_DIR/prepare_fn_clear.log" fn_clear
    arm_fntrace prepare
    write_state prepared
    PRESERVE_SESSION=1
    note "Preparacao concluida: escolha Guile, entre no Bonus e execute o comando BEFORE quando o cenario estiver ativo"
}

before_phase() {
    validate_build
    trap cleanup EXIT
    read_state
    [[ "$RUN_PHASE" == prepared ]] || fail "A coleta esta na fase '$RUN_PHASE'; execute AFTER, nao BEFORE."
    printf '\nInstrumentacao S1-247 mantida desde o menu. Coletando BEFORE no cenario Bonus ativo.\n'
    collect_before
    RUN_START_EPOCH="$(date +%s)"
    write_state before
    PRESERVE_SESSION=1
    note "BEFORE concluido. Jogue o Bonus; na tela Replay/Exit execute o comando AFTER"
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
