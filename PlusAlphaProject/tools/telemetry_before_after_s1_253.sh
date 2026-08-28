#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-253-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_SHA=80DF7E6811A60B300CD5371818A2504FB571EB806B5FC755BD470A4582077068
readonly ENTRY_LO=0x8017D860
readonly ENTRY_HI=0x8017DA9C
readonly PAGE_SIZE=2048
readonly FN_RING_CAP=262144
readonly TRACE_MAX=4096
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.s1-253-telemetry-active.state"
readonly TRACE_SPEC=$'leaf_a 0x8017D860 0x8017D864\nleaf_b 0x8017DA08 0x8017DA0C\nleaf_c 0x80191000 0x80191004'

PYTHON_BIN=
DEBUG_PORT=
RUN_DIR=
RUN_PHASE=
RUN_START_EPOCH=0
PRESERVE_SESSION=0

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }
require_range() { grep -q "^$1$" "$RANGES_FILE" || fail "Range/funcao ausente: $1"; }
require_symbol() { nm -C "$RUNTIME_EXE" | grep -E "[[:space:]]T[[:space:]]+$1$" >/dev/null || fail "O executavel nao contem $1."; }

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64 e com a mesma execucao aberta do jogo:

  bash tools/telemetry_before_after_s1_253.sh prepare
  bash tools/telemetry_before_after_s1_253.sh before
  bash tools/telemetry_before_after_s1_253.sh after

Fluxo:

  1. Abra manualmente a build S1-253 de telemetria.
  2. No menu de modos, destaque Bonus Barril e execute prepare antes de
     escolher Guile.
  3. Quando o Bonus estiver ativo e o controle liberado, sem inputs, execute
     before.
  4. Jogue o Bonus normalmente. Na tela Bonus Replay/Exit, sem inputs,
     execute after.

O coletor nao gera, compila, abre nem fecha o jogo.
EOF
}

cleanup() {
    (( PRESERVE_SESSION == 0 )) || return
    if [[ -n "$PYTHON_BIN" && -n "$DEBUG_PORT" && -f "$RAW_TCP" ]]; then
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" fn_disable >/dev/null 2>&1 || true
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" fntrace_arm_clear >/dev/null 2>&1 || true
    fi
}

select_python() { if command -v python >/dev/null; then PYTHON_BIN="$(command -v python)"; elif command -v python3 >/dev/null; then PYTHON_BIN="$(command -v python3)"; else fail "Python nao foi encontrado no PATH do UCRT64."; fi; }
read_debug_port() { DEBUG_PORT="$(awk '/^[[:space:]]*\[runtime\][[:space:]]*$/ { ok=1; next } /^[[:space:]]*\[/ { ok=0 } ok && /^[[:space:]]*debug_port[[:space:]]*=/ { sub(/^[^=]*=/, ""); gsub(/[[:space:]]+/, ""); print; exit }' "$GAME_TOML")"; [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida em game.toml."; }

validate_build() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    command -v objdump >/dev/null || fail "objdump nao encontrado no UCRT64."
    command -v nm >/dev/null || fail "nm nao encontrado no UCRT64."
    command -v sha256sum >/dev/null || fail "sha256sum nao encontrado no UCRT64."
    [[ -f "$GAME_TOML" && -f "$RANGES_FILE" && -f "$RAW_TCP" && -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] || fail "Arquivos da build S1-253 de telemetria estao ausentes."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_SHA" ]] || fail "SHA-256 do manifest nao corresponde ao S1-253 aprovado."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1045 ]] || fail "A quantidade de funcoes geradas nao corresponde ao S1-253 esperado (1045)."
    require_range 'F 8017D860'; require_range 'R 8017D860 1A8'; require_range 'F 8017DA08'; require_range 'R 8017DA08 94'; require_range 'F 80191000'; require_range 'R 80191000 A4'
    ! grep -Eq '^F (80103384|8016FC28|8017566C|8017DA9C|8018F10C|80190EB8|80190FAC|801910A4|801914C0|80191C84|80192D6C|8019E6D0)$' "$RANGES_FILE" || fail "Uma funcao fora da closure S1-253 apareceu nos fontes."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" || fail "A build S1-253 nao esta RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" || fail "A build S1-253 nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" || fail "A build S1-253 nao possui PSX_STATIC_RUNTIME=ON."
    local imports; imports="$(objdump -p "$RUNTIME_EXE" | awk '/DLL Name:/ { print $3 }')"
    ! printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$' || fail "O executavel importa uma DLL de runtime nao-sistema."
    require_symbol func_8017D860; require_symbol func_8017DA08; require_symbol func_80191000
    ! nm -C "$RUNTIME_EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_(80103384|8016FC28|8017566C|8017DA9C|8018F10C|80190EB8|80190FAC|801910A4|801914C0|80191C84|80192D6C|8019E6D0)$' || fail "O executavel contem uma funcao fora da closure S1-253."
    select_python; read_debug_port
}

raw() { local output="$1"; shift; "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 || fail "Falha na consulta TCP: $*"; grep -q '"ok":true' "$output" || fail "Resposta TCP invalida em $(basename "$output")."; }
integer() { "$PYTHON_BIN" - "$1" "$2" <<'PY'
import json,pathlib,re,sys
t=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace'); f=sys.argv[2]
m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',t,re.S); rows=[m.group(1).strip()] if m else []; rows += [x for x in t.splitlines() if x.startswith('{')]
for row in rows:
    try: print(int(json.loads(row).get(f,0) or 0)); break
    except (ValueError,TypeError,json.JSONDecodeError): pass
else: print(0)
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

make_run_dir() { local n candidate; mkdir -p "$PROJECT_ROOT/local/telemetry"; for n in $(seq -w 1 99); do candidate="$PROJECT_ROOT/local/telemetry/s1-253-telemetry-$n"; if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi; done; fail "Nao ha run-id livre entre s1-253-telemetry-01 e 99."; }
write_state() { local phase="$1"; umask 077; printf 'run_dir=%s\nphase=%s\nstart_epoch=%s\n' "$RUN_DIR" "$phase" "$RUN_START_EPOCH" >"$STATE_FILE"; RUN_PHASE="$phase"; }
read_state() { [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta S1-253 preparada. Execute primeiro prepare."; RUN_DIR="$(awk -F= '$1 == "run_dir" { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE")"; RUN_PHASE="$(awk -F= '$1 == "phase" { print $2; exit }' "$STATE_FILE")"; RUN_START_EPOCH="$(awk -F= '$1 == "start_epoch" { print $2; exit }' "$STATE_FILE")"; [[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] || fail "Estado S1-253 invalido: run_dir ausente."; case "$RUN_DIR" in "$PROJECT_ROOT"/local/telemetry/s1-253-telemetry-*) ;; *) fail "Estado S1-253 fora de local/telemetry." ;; esac; [[ "$RUN_PHASE" == prepared || "$RUN_PHASE" == before ]] || fail "Estado S1-253 invalido: fase $RUN_PHASE."; [[ "$RUN_START_EPOCH" =~ ^[0-9]+$ ]] || fail "Estado S1-253 invalido: start_epoch."; }
clear_state() { rm -f "$STATE_FILE"; }

metadata() { cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-253
functions=0x8017D860,0x8017DA08,0x80191000
words=106,37,41; total=184
callers=0x8018FEEC,0x80190E20,0x8018FEF4 (todos em 0x8018F10C)
ranges_sha256=$(sha256sum "$RANGES_FILE" | awk '{print $1}')
runtime_exe_sha256=$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')
runtime_build=buildClean-ucrt-s1-253-tele
mode=Bonus Barril
character=Guile
route=prepare no menu Bonus antes de escolher Guile; BEFORE no cenario ativo sem inputs; eliminar barris; AFTER na tela Bonus Replay/Exit sem inputs
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

arm_traces() { local prefix="$1" label lo hi; raw "$RUN_DIR/${prefix}_fntrace_arm_clear.log" fntrace_arm_clear; while read -r label lo hi; do raw "$RUN_DIR/${prefix}_fntrace_arm_${label}.log" fntrace_arm target="$lo"; done <<<"$TRACE_SPEC"; raw "$RUN_DIR/${prefix}_fntrace_armed.log" fntrace_armed; raw "$RUN_DIR/${prefix}_fntrace_clear.log" fntrace_clear; }
dump_traces() { local prefix="$1" label lo hi; while read -r label lo hi; do raw "$RUN_DIR/${prefix}_fntrace_${label}.log" fntrace_dump target_lo="$lo" target_hi="$hi" count="$TRACE_MAX"; done <<<"$TRACE_SPEC"; }
dump_entries() { local prefix="$1" total="$2" start=0 end page=0 lo hi output; if (( total == 0 )); then raw "$RUN_DIR/${prefix}_fn_entry_page_000.log" fn_entry_dump addr_lo="$ENTRY_LO" addr_hi="$ENTRY_HI" seq_lo=0x0 seq_hi=0x0 count="$PAGE_SIZE"; return; fi; while (( start < total )); do end=$((start + PAGE_SIZE)); (( end > total )) && end="$total"; lo="$(printf '0x%X' "$start")"; hi="$(printf '0x%X' "$end")"; output="$RUN_DIR/${prefix}_fn_entry_page_$(printf '%03d' "$page").log"; raw "$output" fn_entry_dump addr_lo="$ENTRY_LO" addr_hi="$ENTRY_HI" seq_lo="$lo" seq_hi="$hi" count="$PAGE_SIZE"; start="$end"; page=$((page + 1)); (( page <= 128 )) || fail "Paginacao fn_entry excedeu 128 paginas."; done; }

collect_before() { note "Coletando BEFORE com a instrumentacao armada no menu"; raw "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120; raw "$RUN_DIR/before_phase_profile.log" phase_profile window=1; static_misses before; raw "$RUN_DIR/before_dispatch_stats.log" dispatch_stats; raw "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats; raw "$RUN_DIR/before_fn_stats.log" fn_stats; dump_entries before "$(integer "$RUN_DIR/before_fn_stats.log" entry_total)"; dump_traces before; raw "$RUN_DIR/window_fn_clear.log" fn_clear; raw "$RUN_DIR/window_fntrace_clear.log" fntrace_clear; }
collect_after() {
    local seconds="$1" window
    window="$seconds"
    (( window < 1 )) && window=1
    (( window > 60 )) && window=60
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

summary() { "$PYTHON_BIN" - "$RUN_DIR" "$FN_RING_CAP" "$TRACE_MAX" <<'PY'
import collections,json,pathlib,re,sys
run,cap,trace_max=pathlib.Path(sys.argv[1]),int(sys.argv[2]),int(sys.argv[3])
targets={'leaf_a':'0X8017D860','leaf_b':'0X8017DA08','leaf_c':'0X80191000'}
def payload(name):
 p=run/name
 if not p.exists(): return {}
 t=p.read_text(encoding='utf-8',errors='replace'); m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',t,re.S); rows=[m.group(1).strip()] if m else []; rows += [x for x in t.splitlines() if x.startswith('{')]
 for row in rows:
  try:
   d=json.loads(row)
   if isinstance(d,dict): return d
  except json.JSONDecodeError: pass
 return {}
def num(v):
 try:return int(v or 0)
 except (ValueError,TypeError):return 0
def entries(prefix):
 out=[]
 for p in sorted(run.glob(prefix+'_fn_entry_page_*.log')): out += payload(p.name).get('entries',[])
 return out
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
bcomplete,acomplete=complete(bentries,btotal),complete(aentries,atotal)
bmiss,amiss=missed('before'),missed('after')
rows={}; trace_ok={}; fallback={}; ras={}
for label,target in targets.items():
 r=payload('before_fntrace_'+label+'.log').get('entries',[])+payload('after_fntrace_'+label+'.log').get('entries',[])
 rows[label]=[e for e in r if str(e.get('target','')).upper()==target]
 ras[label]=collections.Counter(str(e.get('ra','')).upper() for e in rows[label])
 trace_ok[label]=len(rows[label])>0 and len(rows[label])<trace_max
 fallback[label]=target in bmiss or target in amiss
entry_by_func=collections.Counter(str(e.get('func','')).upper() for e in bentries+aentries)
integrity=(num(adirty.get('aborts'))==num(bdirty.get('aborts')) and num(adirty.get('native_handoffs'))==num(bdirty.get('native_handoffs')) and num(adirty.get('text_native_blocked'))==num(bdirty.get('text_native_blocked')))
gate=all(trace_ok.values()) and not any(fallback.values()) and bcomplete and acomplete and bfiltered==btotal and afiltered==atotal and integrity
latency,phase=payload('after_latency.log'),payload('after_phase_profile.log'); frame=latency.get('summary',{}).get('frame_period',{})
lines=[f'# Telemetria {run.name}','', '## Resultado S1-253','',f'- Duracao manual: {payload("duration.json").get("seconds","n/d")} s',f'- fn_entry menu->BEFORE: total/filtrado/capturado={btotal}/{bfiltered}/{len(bentries)}',f'- fn_entry BEFORE->AFTER: total/filtrado/capturado={atotal}/{afiltered}/{len(aentries)}',f'- Ring fn_entry sem perda: pre={"sim" if bcomplete else "nao"}; janela={"sim" if acomplete else "nao"}',f'- Entradas por funcao no intervalo contiguo: {entry_by_func}', '', '## Tres folhas nativas','', '| Funcao | Hits fntrace | Sem saturacao | RAs mais comuns | Fallback interpreter |', '| --- | ---: | --- | --- | --- |']
for label,target in targets.items(): lines.append(f'| {target} | {len(rows[label])} | {"sim" if trace_ok[label] else "nao"} | {ras[label].most_common(5)} | {"sim" if fallback[label] else "nao"} |')
lines += [f'- Gate tecnico das tres folhas: {"confirmado" if gate else "insuficiente"}',f'- Delta static_hits: {num(adisp.get("static_hits"))-num(bdisp.get("static_hits"))}',f'- Delta miss_total: {num(adisp.get("miss_total"))-num(bdisp.get("miss_total"))}','', '## Frametime e integridade','',f'- P50/P95/max: {num(frame.get("p50_us"))/1000:.3f} / {num(frame.get("p95_us"))/1000:.3f} / {num(frame.get("max_us"))/1000:.3f} ms',f'- Fases: interpreter={phase.get("interp_share","n/d")}; static={phase.get("static_share","n/d")}; GPU={phase.get("gpu_share","n/d")}',f'- aborts BEFORE/AFTER: {num(bdirty.get("aborts"))}/{num(adirty.get("aborts"))}',f'- native_handoffs BEFORE/AFTER: {num(bdirty.get("native_handoffs"))}/{num(adirty.get("native_handoffs"))}',f'- text_native_blocked BEFORE/AFTER: {num(bdirty.get("text_native_blocked"))}/{num(adirty.get("text_native_blocked"))}','', '- O coletor nao gerou, compilou, abriu nem fechou o jogo.', '']
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

prepare() { validate_build; trap cleanup EXIT; [[ ! -e "$STATE_FILE" ]] || fail "Ja existe uma coleta S1-253 pendente. Conclua com AFTER antes de preparar outra."; make_run_dir; metadata; printf '\nArtefato S1-253 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"; printf 'Precondicao: menu de modos com Bonus Barril destacado; Guile ainda nao escolhido.\n'; note "Armando as tres folhas no menu"; raw "$RUN_DIR/prepare_fn_filter.log" fn_filter lo="$ENTRY_LO" hi="$ENTRY_HI"; raw "$RUN_DIR/prepare_fn_clear.log" fn_clear; arm_traces prepare; write_state prepared; PRESERVE_SESSION=1; note "Preparacao concluida: escolha Guile e execute BEFORE quando o Bonus estiver ativo"; }
before_phase() { validate_build; trap cleanup EXIT; read_state; [[ "$RUN_PHASE" == prepared ]] || fail "A coleta esta na fase $RUN_PHASE; execute AFTER, nao BEFORE."; collect_before; RUN_START_EPOCH="$(date +%s)"; write_state before; PRESERVE_SESSION=1; note "BEFORE concluido. Jogue o Bonus; na tela Replay/Exit execute AFTER"; }
after_phase() { validate_build; trap cleanup EXIT; read_state; [[ "$RUN_PHASE" == before ]] || fail "A coleta esta na fase $RUN_PHASE; execute BEFORE dentro do Bonus."; local end seconds; end="$(date +%s)"; seconds=$((end-RUN_START_EPOCH)); printf '{"seconds":%d}\n' "$seconds" >"$RUN_DIR/duration.json"; collect_after "$seconds"; summary; clear_state; note "Coleta concluida: $RUN_DIR"; printf 'Resumo: %s/summary.md\nO script nao fechara o jogo.\n' "$RUN_DIR"; }
main() { [[ $# == 1 ]] || { usage; fail "Informe uma fase: prepare, before ou after."; }; case "$1" in prepare) prepare ;; before) before_phase ;; after) after_phase ;; -h|--help) usage ;; *) usage; fail "Fase desconhecida: $1" ;; esac; }
main "$@"
