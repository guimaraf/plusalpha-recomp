#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-250-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly TARGET=0x8019F5CC
readonly TARGET_HI=0x8019F6A8
readonly THUNK_A0=0x8019FB4C
readonly THUNK_A0_HI=0x8019FB58
readonly THUNK_A0_RA=0x8019F688
readonly THUNK_B0=0x8019FB84
readonly THUNK_B0_HI=0x8019FB90
readonly THUNK_B0_RA=0x8019F65C
readonly SAVESTATE=0x8019FB94
readonly SAVESTATE_HI=0x8019FBD0
readonly SAVESTATE_RA=0x8019F634
readonly PAGE_SIZE=2048
readonly FN_RING_CAP=262144
readonly TRACE_MAX=4096
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.s1-250-telemetry-active.state"

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
Uso, sempre no MSYS2 UCRT64 e com a mesma execucao aberta do jogo:

  bash tools/telemetry_before_after_s1_250.sh prepare
  bash tools/telemetry_before_after_s1_250.sh before
  bash tools/telemetry_before_after_s1_250.sh after

IMPORTANTE: esta coleta usa observadores armados por variaveis de ambiente
desde o inicio do processo. Abra o jogo pelo comando PowerShell fornecido nas
instrucoes do lote S1-250; nao abra esta build com duplo clique.

Fluxo:

  1. Abra manualmente a build pelo comando PowerShell instrumentado.
  2. No menu de modos, com Bonus Barril destacado e antes de escolher Guile,
     execute "prepare". A fase valida e preserva os registros desde o boot.
  3. Escolha Guile. Assim que o cenario do Bonus estiver ativo, sem inputs,
     execute "before".
  4. Jogue o Bonus normalmente. Na tela Bonus Replay/Exit, sem inputs,
     execute "after".

O coletor nao compila, nao abre e nao fecha o jogo.
EOF
}

cleanup() {
    (( PRESERVE_SESSION == 0 )) || return
    if [[ -n "$PYTHON_BIN" && -n "$DEBUG_PORT" && -f "$RAW_TCP" ]]; then
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
    [[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v objdump >/dev/null || fail "objdump nao encontrado no UCRT64."
    command -v nm >/dev/null || fail "nm nao encontrado no UCRT64."
    command -v sha256sum >/dev/null || fail "sha256sum nao encontrado no UCRT64."
    [[ -f "$GAME_TOML" && -f "$RANGES_FILE" && -f "$RAW_TCP" && -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] || fail "Arquivos da build S1-250 de telemetria estao ausentes."
    require_range "F 8019F5CC"; require_range "R 8019F5CC DC"
    require_range "F 8019FB4C"; require_range "R 8019FB4C C"
    require_range "F 8019FB84"; require_range "R 8019FB84 C"
    require_range "F 8019FB94"; require_range "R 8019FB94 3C"
    require_range "F 8019F6A8"; require_range "R 8019F6A8 1E8"
    require_range "F 8019FB64"; require_range "R 8019FB64 C"
    ! grep -q '^F 8019FBD0$' "$RANGES_FILE" || fail "A funcao 0x8019FBD0 apareceu fora da closure."
    ! grep -q '^F 8019E6D0$' "$RANGES_FILE" || fail "A funcao em quarentena 0x8019E6D0 apareceu nos fontes."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1041 ]] || fail "A quantidade de funcoes geradas nao corresponde ao S1-250 esperado (1041)."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" || fail "A build S1-250 nao esta configurada como RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" || fail "A build S1-250 nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" || fail "A build S1-250 nao possui PSX_STATIC_RUNTIME=ON."
    local imports
    imports="$(objdump -p "$RUNTIME_EXE" | awk '/DLL Name:/ { print $3 }')"
    ! printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$' || fail "O executavel S1-250 importa uma DLL de runtime nao-sistema."
    require_symbol func_8019F5CC; require_symbol func_8019FB4C; require_symbol func_8019FB84; require_symbol func_8019FB94
    require_symbol func_8019F6A8; require_symbol func_8019FB64
    ! nm -C "$RUNTIME_EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_8019FBD0$' || fail "O executavel contem func_8019FBD0 fora da closure."
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
    except (ValueError,TypeError,json.JSONDecodeError): pass
else: print(0)
PY
}

validate_startup_instrumentation() {
    "$PYTHON_BIN" - "$RUN_DIR/prepare_fntrace_armed.log" "$RUN_DIR/prepare_fn_stats.log" <<'PY'
import json,pathlib,re,sys
def payload(path):
    text=pathlib.Path(path).read_text(encoding='utf-8',errors='replace')
    m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    rows=[m.group(1).strip()] if m else []
    rows += [x for x in text.splitlines() if x.startswith('{')]
    for row in rows:
        try:
            data=json.loads(row)
            if isinstance(data,dict): return data
        except json.JSONDecodeError: pass
    return {}
armed=payload(sys.argv[1]); stats=payload(sys.argv[2])
expected={'0X8019F5CC','0X8019FB4C','0X8019FB84','0X8019FB94'}
actual={str(x).upper() for x in armed.get('targets',[])}
errors=[]
if actual != expected: errors.append(f'PSX_FNTRACE_ARM incorreto: esperado={sorted(expected)} atual={sorted(actual)}')
if int(stats.get('active',0) or 0) != 1: errors.append('PSX_FN_FILTER nao esta ativo')
if str(stats.get('filter_lo','')).upper() != '0X8019F5CC': errors.append(f'filter_lo incorreto: {stats.get("filter_lo")}')
if str(stats.get('filter_hi','')).upper() != '0X8019F6A8': errors.append(f'filter_hi incorreto: {stats.get("filter_hi")}')
if errors:
    raise SystemExit('\n'.join(errors)+'\nFeche o jogo e abra novamente pelo comando PowerShell instrumentado do S1-250.')
print('Instrumentacao desde o boot confirmada: quatro alvos armados e filtro da raiz ativo.')
PY
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
        candidate="$PROJECT_ROOT/local/telemetry/s1-250-telemetry-$n"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi
    done
    fail "Nao ha run-id livre entre s1-250-telemetry-01 e 99."
}

write_state() {
    local phase="$1"
    umask 077
    printf 'run_dir=%s\nphase=%s\nstart_epoch=%s\n' "$RUN_DIR" "$phase" "$RUN_START_EPOCH" >"$STATE_FILE"
    RUN_PHASE="$phase"
}

read_state() {
    [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta S1-250 preparada. Execute primeiro: bash tools/telemetry_before_after_s1_250.sh prepare"
    RUN_DIR="$(awk -F= '$1 == "run_dir" { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE")"
    RUN_PHASE="$(awk -F= '$1 == "phase" { print $2; exit }' "$STATE_FILE")"
    RUN_START_EPOCH="$(awk -F= '$1 == "start_epoch" { print $2; exit }' "$STATE_FILE")"
    [[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] || fail "Estado da coleta S1-250 invalido: run_dir ausente."
    case "$RUN_DIR" in "$PROJECT_ROOT"/local/telemetry/s1-250-telemetry-*) ;; *) fail "Estado da coleta S1-250 invalido: diretorio fora de local/telemetry." ;; esac
    [[ "$RUN_PHASE" == prepared || "$RUN_PHASE" == before ]] || fail "Estado da coleta S1-250 invalido: fase '$RUN_PHASE'."
    [[ "$RUN_START_EPOCH" =~ ^[0-9]+$ ]] || fail "Estado da coleta S1-250 invalido: start_epoch."
}

clear_state() { rm -f "$STATE_FILE"; }

metadata() {
    cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-250
root_target=$TARGET
root_range=0x8019F5CC..0x8019F6A7
thunk_a0=$THUNK_A0
thunk_a0_return_address=$THUNK_A0_RA
thunk_b0=$THUNK_B0
thunk_b0_return_address=$THUNK_B0_RA
savestate=$SAVESTATE
savestate_return_address=$SAVESTATE_RA
startup_fntrace_arm=0x8019F5CC,0x8019FB4C,0x8019FB84,0x8019FB94
startup_fn_filter=0x8019F5CC:0x8019F6A8
ranges_sha256=$(sha256sum "$RANGES_FILE" | awk '{print $1}')
runtime_exe_sha256=$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')
runtime_build=buildClean-ucrt-s1-250-tele
mode=Bonus Barril
character=Guile
route=instrumentacao desde o boot; prepare no menu Bonus; BEFORE no cenario ativo sem inputs; eliminar barris; AFTER na tela Bonus Replay/Exit sem inputs
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

dump_traces() {
    local prefix="$1"
    raw "$RUN_DIR/${prefix}_fntrace_root.log" fntrace_dump target_lo="$TARGET" target_hi="$TARGET_HI" count="$TRACE_MAX"
    raw "$RUN_DIR/${prefix}_fntrace_thunk_a0.log" fntrace_dump target_lo="$THUNK_A0" target_hi="$THUNK_A0_HI" count="$TRACE_MAX"
    raw "$RUN_DIR/${prefix}_fntrace_thunk_b0.log" fntrace_dump target_lo="$THUNK_B0" target_hi="$THUNK_B0_HI" count="$TRACE_MAX"
    raw "$RUN_DIR/${prefix}_fntrace_savestate.log" fntrace_dump target_lo="$SAVESTATE" target_hi="$SAVESTATE_HI" count="$TRACE_MAX"
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
    note "Coletando BEFORE; os registros de boot serao preservados neste snapshot"
    raw "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/before_phase_profile.log" phase_profile window=1
    static_misses before
    raw "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/before_fn_stats.log" fn_stats
    dump_entries before "$(integer "$RUN_DIR/before_fn_stats.log" entry_total)"
    dump_traces before
    raw "$RUN_DIR/window_fn_clear.log" fn_clear
    raw "$RUN_DIR/window_fntrace_clear.log" fntrace_clear
}

collect_after() {
    local seconds="$1" window="$seconds"
    (( window < 1 )) && window=1; (( window > 60 )) && window=60
    note "Coletando AFTER imediatamente e congelando os traces"
    raw "$RUN_DIR/after_fn_disable.log" fn_disable
    raw "$RUN_DIR/after_fn_stats.log" fn_stats
    dump_entries after "$(integer "$RUN_DIR/after_fn_stats.log" entry_total)"
    dump_traces after
    raw "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/after_phase_profile.log" phase_profile window="$window"
    static_misses after
    raw "$RUN_DIR/after_fntrace_arm_clear.log" fntrace_arm_clear
}

summary() {
    "$PYTHON_BIN" - "$RUN_DIR" "$TARGET" "$THUNK_A0" "$THUNK_A0_RA" "$THUNK_B0" "$THUNK_B0_RA" "$SAVESTATE" "$SAVESTATE_RA" "$FN_RING_CAP" <<'PY'
import collections,json,pathlib,re,sys
run=pathlib.Path(sys.argv[1]); target=sys.argv[2].upper(); cap=int(sys.argv[9])
specs=[('thunk_a0',sys.argv[3].upper(),sys.argv[4].upper()),('thunk_b0',sys.argv[5].upper(),sys.argv[6].upper()),('savestate',sys.argv[7].upper(),sys.argv[8].upper())]
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
    try: return int(value or 0)
    except (ValueError,TypeError): return 0
def entries(prefix):
    result=[]
    for p in sorted(run.glob(prefix+'_fn_entry_page_*.log')): result += payload(p.name).get('entries',[])
    return result
def trace(prefix,name): return payload(prefix+'_fntrace_'+name+'.log').get('entries',[])
def missed(prefix): return {str(x.get('pc','')).upper() for x in payload(prefix+'_static_text_misses_offset_000000.log').get('entries',[]) if x.get('pc')}
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
bmiss,amiss=missed('before'),missed('after')
no_root_fallback=target not in bmiss and target not in amiss
root_proof=bool(all_root) and bcomplete and acomplete and bfiltered==btotal and afiltered==atotal and no_root_fallback
helper_rows={}; helper_ras={}; helper_ok={}
for name,addr,expected_ra in specs:
    rows=trace('before',name)+trace('after',name)
    ras=collections.Counter(str(e.get('ra','')).upper() for e in rows)
    helper_rows[name]=rows; helper_ras[name]=ras
    helper_ok[name]=bool(rows) and ras[expected_ra]>0 and addr not in bmiss and addr not in amiss
gate=root_proof and all(helper_ok.values())
latency=payload('after_latency.log'); phase=payload('after_phase_profile.log'); frame=latency.get('summary',{}).get('frame_period',{})
lines=[f'# Telemetria {run.name}','', '## Resultado S1-250','',
f'- Duracao manual: {payload("duration.json").get("seconds","n/d")} s',
f'- Hits fn_entry da raiz boot->BEFORE: {len(broot)}',
f'- Hits fn_entry da raiz BEFORE->AFTER: {len(aroot)}',
f'- fn_entry pre total/filtrado/capturado={btotal}/{bfiltered}/{len(bentries)}; janela={atotal}/{afiltered}/{len(aentries)}',
f'- Ring fn_entry sem perda: pre={"sim" if bcomplete else "nao"}; janela={"sim" if acomplete else "nao"}',
f'- RAs da raiz: {root_ras.most_common(8)}',
f'- Hits fntrace da raiz: {len(trace("before","root")+trace("after","root"))}',
f'- Raiz nativa alcancada sem fallback: {"confirmado" if root_proof else "insuficiente"}',
'', '## Closure direta','']
for name,addr,expected_ra in specs:
    lines.append(f'- {name} {addr}: {len(helper_rows[name])} hits; RA esperada {expected_ra}: {helper_ras[name][expected_ra]}; RAs={helper_ras[name].most_common(5)}; gate={"confirmado" if helper_ok[name] else "insuficiente"}')
lines += [f'- Gate raiz + tres auxiliares: {"confirmado" if gate else "insuficiente"}',
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
    [[ ! -e "$STATE_FILE" ]] || fail "Ja existe uma coleta S1-250 pendente. Conclua com AFTER antes de preparar outra."
    make_run_dir
    metadata
    printf '\nArtefato S1-250 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"
    printf 'Validando a instrumentacao herdada desde o boot. Nenhum ring sera limpo.\n'
    raw "$RUN_DIR/prepare_fntrace_armed.log" fntrace_armed
    raw "$RUN_DIR/prepare_fn_stats.log" fn_stats
    validate_startup_instrumentation || fail "A instrumentacao de startup do S1-250 nao foi confirmada."
    write_state prepared
    PRESERVE_SESSION=1
    note "Preparacao concluida: entre no Bonus com Guile e execute BEFORE quando o cenario estiver ativo"
}

before_phase() {
    validate_build
    trap cleanup EXIT
    read_state
    [[ "$RUN_PHASE" == prepared ]] || fail "A coleta esta na fase '$RUN_PHASE'; execute AFTER, nao BEFORE."
    printf '\nColetando BEFORE no cenario Bonus ativo, incluindo a evidencia preservada desde o boot.\n'
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
