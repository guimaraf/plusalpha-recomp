#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly RAW_TCP="$REPO_ROOT/psxrecomp/tools/raw_tcp.py"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-259-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_SHA=C0E7A0A37DB76E98E731D4E9CA5A0882DE02802E8CDADA5805E07C83DE15999F
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.s1-259-telemetry-active.state"
readonly WATCH_SPEC=$'root 0x801939A0\nreturn 0x80134F00'

PYTHON_BIN=
DEBUG_PORT=
RUN_DIR=
RUN_PHASE=
RUN_START_EPOCH=0
PRESERVE_SESSION=0

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }
require_range() { grep -q "^$1$" "$RANGES_FILE" || fail "Range/funcao ausente: $1"; }
require_symbol() {
    nm -C "$RUNTIME_EXE" | grep -E "[[:space:]]T[[:space:]]+$1$" >/dev/null ||
        fail "O executavel nao contem $1."
}

usage() {
    cat <<'EOF'
Uso, sempre no MSYS2 UCRT64 e com a mesma execucao aberta do jogo:

  bash tools/telemetry_before_after_s1_259.sh prepare
  bash tools/telemetry_before_after_s1_259.sh before
  bash tools/telemetry_before_after_s1_259.sh after

Rota dirigida ao Mode Select:

  1. Abra manualmente a build S1-259 de telemetria.
  2. Na tela de titulo, antes de apertar Start, execute PREPARE.
  3. Entre no Mode Select e espere a tela estabilizar.
  4. Sem input, execute BEFORE.
  5. Percorra lentamente todas as opcoes visiveis por 15 a 20 segundos, sem
     confirmar nenhuma opcao e sem sair da tela.
  6. Pare os inputs ainda no Mode Select e execute AFTER.

O coletor nao gera, compila, abre nem fecha o jogo. Use uma unica janela
UCRT64 para as tres fases.
EOF
}

cleanup() {
    (( PRESERVE_SESSION == 0 )) || return
    if [[ -n "$PYTHON_BIN" && -n "$DEBUG_PORT" && -f "$RAW_TCP" ]]; then
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" pc_watch_stop >/dev/null 2>&1 || true
    fi
}

select_python() {
    if command -v python >/dev/null; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao foi encontrado no PATH do UCRT64."
    fi
}

read_debug_port() {
    DEBUG_PORT="$(awk '
        /^[[:space:]]*\[runtime\][[:space:]]*$/ { ok=1; next }
        /^[[:space:]]*\[/ { ok=0 }
        ok && /^[[:space:]]*debug_port[[:space:]]*=/ {
            sub(/^[^=]*=/, ""); gsub(/[[:space:]]+/, ""); print; exit
        }
    ' "$GAME_TOML")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida em game.toml."
}

validate_build() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in objdump nm sha256sum; do command -v "$tool" >/dev/null || fail "$tool nao encontrado."; done
    [[ -f "$RAW_TCP" && -f "$GAME_TOML" && -f "$RANGES_FILE" &&
       -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] ||
        fail "Build S1-259 de telemetria ou ferramentas ausentes."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_SHA" ]] ||
        fail "Ranges atuais nao correspondem ao S1-259 aprovado."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1058 ]] ||
        fail "A baseline nao possui as 1.058 funcoes esperadas."
    require_range 'F 801939A0'; require_range 'R 801939A0 78'
    ! grep -Eq '^F (80103384|801912D8|801932AC|801932BC|8019E6D0)$' "$RANGES_FILE" ||
        fail "Uma funcao proibida apareceu nos fontes."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" || fail "A build nao esta RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" || fail "A build nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" || fail "A build nao possui runtime estatico."
    require_symbol func_801939A0
    ! nm -C "$RUNTIME_EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_(80103384|801912D8|801932AC|801932BC|8019E6D0)$' ||
        fail "O executavel contem uma funcao proibida."
    select_python
    read_debug_port
}

raw() {
    local output="$1"; shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 ||
        fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" || fail "Resposta TCP invalida em $(basename "$output")."
}

integer() {
    "$PYTHON_BIN" - "$1" "$2" <<'PY'
import json,pathlib,re,sys
t=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace'); field=sys.argv[2]
m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',t,re.S)
rows=([m.group(1).strip()] if m else [])+[x for x in t.splitlines() if x.startswith('{')]
for row in rows:
    try: print(int(json.loads(row).get(field,0) or 0)); break
    except (ValueError,TypeError,json.JSONDecodeError): pass
else: print(0)
PY
}

observations() {
    local prefix="$1" output returned total dropped
    output="$RUN_DIR/${prefix}_observations.log"
    raw "$output" static_text_misses class=all min_hits=1 offset=0 limit=256
    returned="$(integer "$output" returned)"; total="$(integer "$output" total)"; dropped="$(integer "$output" dropped)"
    (( dropped == 0 && total <= 256 && returned == total )) ||
        fail "Snapshot $prefix incompleto (total=$total returned=$returned dropped=$dropped)."
}

make_run_dir() {
    local n candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for n in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-259-telemetry-$n"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi
    done
    fail "Nao ha run-id livre entre s1-259-telemetry-01 e 99."
}

write_state() {
    umask 077
    printf 'run_dir=%s\nphase=%s\nstart_epoch=%s\n' "$RUN_DIR" "$1" "$RUN_START_EPOCH" >"$STATE_FILE"
    RUN_PHASE="$1"
}

read_state() {
    [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta S1-259 preparada. Execute primeiro prepare."
    RUN_DIR="$(awk -F= '$1=="run_dir" {print substr($0,index($0,"=")+1);exit}' "$STATE_FILE")"
    RUN_PHASE="$(awk -F= '$1=="phase" {print $2;exit}' "$STATE_FILE")"
    RUN_START_EPOCH="$(awk -F= '$1=="start_epoch" {print $2;exit}' "$STATE_FILE")"
    case "$RUN_DIR" in "$PROJECT_ROOT"/local/telemetry/s1-259-telemetry-*) ;; *) fail "Estado S1-259 invalido." ;; esac
    [[ -d "$RUN_DIR" && "$RUN_START_EPOCH" =~ ^[0-9]+$ ]] || fail "Estado S1-259 incompleto."
}

metadata() {
    cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-259
function=0x801939A0; boundary=0x801939A0..0x80193A17; words=30
caller=JAL 0x80134EF8; delay=0x80134EFC; return=0x80134F00
ranges_sha256=$(sha256sum "$RANGES_FILE" | awk '{print $1}')
runtime_exe_sha256=$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')
runtime_build=buildClean-ucrt-s1-259-tele
mode=Mode Select
route=PREPARE no titulo; BEFORE no Mode Select; percorrer opcoes por 15 a 20 segundos; AFTER parado na mesma tela
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

arm() {
    local label target
    raw "$RUN_DIR/prepare_pc_watch_clear.log" pc_watch_clear
    while read -r label target; do
        raw "$RUN_DIR/prepare_pc_watch_arm_${label}_${target#0x}.log" pc_watch_arm target="$target"
    done <<<"$WATCH_SPEC"
    raw "$RUN_DIR/prepare_pc_watch_dump.log" pc_watch_dump
}

collect_before() {
    note "Coletando BEFORE no Mode Select estabilizado"
    raw "$RUN_DIR/before_live_body.log" mem_words addr=0x801939A0 count=30
    raw "$RUN_DIR/before_live_caller.log" mem_words addr=0x80134EF8 count=2
    raw "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/before_phase_profile.log" phase_profile window=1
    observations before
    raw "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/before_pc_watch_dump.log" pc_watch_dump
    raw "$RUN_DIR/window_pc_watch_reset.log" pc_watch_reset
}

collect_after() {
    local seconds="$1" window="$1"
    (( window < 1 )) && window=1; (( window > 60 )) && window=60
    note "Congelando contadores e coletando AFTER"
    raw "$RUN_DIR/after_pc_watch_stop.log" pc_watch_stop
    raw "$RUN_DIR/after_pc_watch_dump.log" pc_watch_dump
    raw "$RUN_DIR/after_live_body.log" mem_words addr=0x801939A0 count=30
    raw "$RUN_DIR/after_live_caller.log" mem_words addr=0x80134EF8 count=2
    raw "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/after_phase_profile.log" phase_profile window="$window"
    observations after
}

summary() {
    "$PYTHON_BIN" - "$RUN_DIR" <<'PY'
import hashlib,json,pathlib,re,struct,sys
run=pathlib.Path(sys.argv[1])
def payload(name):
    p=run/name
    if not p.exists(): return {}
    text=p.read_text(encoding='utf-8',errors='replace')
    m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    rows=([m.group(1).strip()] if m else [])+[x for x in text.splitlines() if x.startswith('{')]
    for row in rows:
        try:
            data=json.loads(row)
            if isinstance(data,dict): return data
        except json.JSONDecodeError: pass
    return {}
def num(v):
    try:return int(v or 0)
    except (ValueError,TypeError):return 0
def words(name): return [str(x).upper() for x in payload(name).get('words',[])]
def body_hash(values):
    if len(values)!=30:return 'INVALIDO'
    return hashlib.sha256(b''.join(struct.pack('<I',int(x,16)) for x in values)).hexdigest().upper()
def obs(name): return {str(e.get('pc','')).upper():e for e in payload(name).get('entries',[]) if e.get('pc')}

watch=payload('after_pc_watch_dump.log'); entries={str(e.get('target','')).upper():e for e in watch.get('entries',[])}
root=entries.get('0X801939A0',{}); ret=entries.get('0X80134F00',{})
shape=num(watch.get('count'))==2 and set(entries)=={'0X801939A0','0X80134F00'}
root_native=num(root.get('native_hits')); root_interp=num(root.get('interpreted_hits'))
return_hits=num(ret.get('hits')); return_interp=num(ret.get('interpreted_hits'))

before_body=words('before_live_body.log'); after_body=words('after_live_body.log')
before_hash=body_hash(before_body); after_hash=body_hash(after_body)
expected_hash='37B07726C20B9FBADA32ADF7CC1ED776D342F0F742F1FEA3734EA48EB6A26179'
body_ok=before_hash==expected_hash and after_hash==expected_hash and before_body==after_body
expected_caller=['0X0C064E68','0X34060003']
caller_ok=words('before_live_caller.log')==expected_caller and words('after_live_caller.log')==expected_caller

bobs=obs('before_observations.log'); aobs=obs('after_observations.log')
candidate_observation=aobs.get('0X801939A0') or bobs.get('0X801939A0')
new_observed=sorted(set(aobs)-set(bobs))
bdisp=payload('before_dispatch_stats.log'); adisp=payload('after_dispatch_stats.log')
bdirty=payload('before_dirty_ram_stats.log'); adirty=payload('after_dirty_ram_stats.log')
aborts_stable=num(adirty.get('aborts'))==num(bdirty.get('aborts'))
blocked_stable=num(adirty.get('text_native_blocked'))==num(bdirty.get('text_native_blocked'))
diverged_stable=num(adirty.get('text_diverged_pages'))==num(bdirty.get('text_diverged_pages'))
gate=(shape and root_native>0 and root_interp==0 and return_hits>0 and body_ok and caller_ok and
      candidate_observation is None and aborts_stable and blocked_stable and diverged_stable)

lat=payload('after_latency.log'); phase=payload('after_phase_profile.log'); frame=lat.get('summary',{}).get('frame_period',{})
lines=[f'# Telemetria {run.name}','', '## Resultado S1-259','',
 f'- Duracao da janela: {payload("duration.json").get("seconds","n/d")} s',
 f'- Raiz 0x801939A0: {root_native} hits nativos; {root_interp} interpretados',
 f'- Retorno 0x80134F00: {return_hits} hits; {return_interp} interpretados (esperado no caller ainda interpretado)',
 f'- Corpo vivo BEFORE/AFTER: {before_hash} / {after_hash}; exato e estavel: {"sim" if body_ok else "nao"}',
 f'- Caller JAL/delay exato e estavel: {"sim" if caller_ok else "nao"}',
 f'- Candidata presente nas observacoes do interpretador: {"sim" if candidate_observation else "nao"}',
 f'- Novos PCs observados na janela: {new_observed or "nenhum"}',
 f'- Delta miss_total: {num(adisp.get("miss_total"))-num(bdisp.get("miss_total"))}',
 f'- aborts estaveis: {"sim" if aborts_stable else "nao"}',
 f'- text_native_blocked estavel: {"sim" if blocked_stable else "nao"}',
 f'- text_diverged_pages estavel: {"sim" if diverged_stable else "nao"}','',
 '## Frametime','',
 f'- P50/P95/max: {num(frame.get("p50_us"))/1000:.3f} / {num(frame.get("p95_us"))/1000:.3f} / {num(frame.get("max_us"))/1000:.3f} ms',
 f'- Fases: interpreter={phase.get("interp_share","n/d")}; static={phase.get("static_share","n/d")}; GPU={phase.get("gpu_share","n/d")}','',
 f'- Gate tecnico S1-259: {"CONFIRMADO" if gate else "INSUFICIENTE"}','',
 '- O retorno interpretado comprova a volta ao caller; ele nao e fallback da candidata.',
 '- A coleta nao substitui a regressao manual das transicoes e demais modos.','']
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

prepare() {
    validate_build; trap cleanup EXIT
    [[ ! -e "$STATE_FILE" ]] || fail "Ja existe uma coleta S1-259 pendente. Conclua com AFTER."
    make_run_dir; metadata; arm; RUN_START_EPOCH=0; write_state prepared; PRESERVE_SESSION=1
    printf '\nArtefato S1-259 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"
    note "PREPARE concluido. Entre no Mode Select e execute BEFORE com a tela estabilizada"
}

before_phase() {
    validate_build; trap cleanup EXIT; read_state
    [[ "$RUN_PHASE" == prepared ]] || fail "A coleta esta na fase $RUN_PHASE; execute AFTER, nao BEFORE."
    collect_before; RUN_START_EPOCH="$(date +%s)"; write_state before; PRESERVE_SESSION=1
    note "BEFORE concluido. Percorra as opcoes e execute AFTER ainda no Mode Select"
}

after_phase() {
    validate_build; trap cleanup EXIT; read_state
    [[ "$RUN_PHASE" == before ]] || fail "A coleta esta na fase $RUN_PHASE; execute BEFORE primeiro."
    local end seconds
    end="$(date +%s)"; seconds=$((end-RUN_START_EPOCH)); printf '{"seconds":%d}\n' "$seconds" >"$RUN_DIR/duration.json"
    collect_after "$seconds"; summary
    raw "$RUN_DIR/final_pc_watch_clear.log" pc_watch_clear
    rm -f "$STATE_FILE"; PRESERVE_SESSION=1
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
