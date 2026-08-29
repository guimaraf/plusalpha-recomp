#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-258-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_SHA=B085DB02B291233F95A55B6F6F25FAACE48147BC5FF273B6518D811F98A73E1E
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.s1-258-telemetry-active.state"
readonly WATCH_SPEC=$'root 0x8017566C\ninterior 0x801757E4\nresume_a 0x80175848\nresume_b 0x80175888'

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

  bash tools/telemetry_before_after_s1_258.sh prepare
  bash tools/telemetry_before_after_s1_258.sh before
  bash tools/telemetry_before_after_s1_258.sh after

Rota dirigida ao Mode Select:

  1. Abra manualmente a build S1-258 de telemetria.
  2. Na tela de titulo, antes de apertar Start, execute PREPARE.
  3. Entre no Mode Select e espere a tela estabilizar.
  4. Sem input, execute BEFORE.
  5. Percorra lentamente todas as opcoes visiveis para cima e para baixo por
     8 a 12 segundos, sem confirmar nenhuma opcao e sem sair da tela.
  6. Pare os inputs ainda no Mode Select e execute AFTER.

O script nao gera, compila, abre nem fecha o jogo. Use apenas uma janela
UCRT64 para prepare/before/after.
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
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64 para executar este script."
    for tool in objdump nm sha256sum; do
        command -v "$tool" >/dev/null || fail "$tool nao encontrado no UCRT64."
    done
    [[ -f "$GAME_TOML" && -f "$RANGES_FILE" && -f "$RAW_TCP" &&
       -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] ||
        fail "Arquivos da build S1-258 de telemetria estao ausentes."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_SHA" ]] ||
        fail "SHA-256 do manifesto nao corresponde ao S1-258 aprovado."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1057 ]] ||
        fail "A quantidade de funcoes nao corresponde ao S1-258 esperado (1057)."
    require_range 'F 8017566C'; require_range 'R 8017566C 25C'
    require_range 'F 8019FC6C'; require_range 'R 8019FC6C 78'
    ! grep -Eq '^F (80103384|8019E6D0)$' "$RANGES_FILE" ||
        fail "Uma funcao fora do micro-lote apareceu nos fontes."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" || fail "A build nao esta RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" || fail "A build nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" || fail "A build nao possui runtime estatico."
    require_symbol func_8017566C
    require_symbol func_8019FC6C
    ! nm -C "$RUNTIME_EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_(80103384|8019E6D0)$' ||
        fail "O executavel contem uma funcao proibida no S1-258."
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

static_misses() {
    local prefix="$1" output returned total dropped
    output="$RUN_DIR/${prefix}_static_text_misses.log"
    raw "$output" static_text_misses class=all min_hits=1 offset=0 limit=256
    returned="$(integer "$output" returned)"
    total="$(integer "$output" total)"
    dropped="$(integer "$output" dropped)"
    (( dropped == 0 && total <= 256 && returned == total )) ||
        fail "Snapshot $prefix de static_text_misses incompleto (total=$total returned=$returned dropped=$dropped)."
}

make_run_dir() {
    local n candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for n in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-258-telemetry-$n"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi
    done
    fail "Nao ha run-id livre entre s1-258-telemetry-01 e 99."
}

write_state() {
    umask 077
    printf 'run_dir=%s\nphase=%s\nstart_epoch=%s\n' "$RUN_DIR" "$1" "$RUN_START_EPOCH" >"$STATE_FILE"
    RUN_PHASE="$1"
}

read_state() {
    [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta S1-258 preparada. Execute primeiro prepare."
    RUN_DIR="$(awk -F= '$1=="run_dir" {print substr($0,index($0,"=")+1);exit}' "$STATE_FILE")"
    RUN_PHASE="$(awk -F= '$1=="phase" {print $2;exit}' "$STATE_FILE")"
    RUN_START_EPOCH="$(awk -F= '$1=="start_epoch" {print $2;exit}' "$STATE_FILE")"
    case "$RUN_DIR" in "$PROJECT_ROOT"/local/telemetry/s1-258-telemetry-*) ;; *) fail "Estado S1-258 invalido." ;; esac
    [[ -d "$RUN_DIR" && "$RUN_START_EPOCH" =~ ^[0-9]+$ ]] || fail "Estado S1-258 incompleto."
}

metadata() {
    cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-258
function=0x8017566C; boundary=0x8017566C..0x801758C7; words=151
jump_table=0x801AC9C0; entries=19; unique_internal_targets=9
jalr_a=0x80175840; continuation=0x80175848; cell=0x80020800
jalr_b=0x80175880; continuation=0x80175888; cell=0x800D6404
ranges_sha256=$(sha256sum "$RANGES_FILE" | awk '{print $1}')
runtime_exe_sha256=$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')
runtime_build=buildClean-ucrt-s1-258-tele
mode=Mode Select
route=PREPARE no titulo; BEFORE no Mode Select estavel; percorrer opcoes por 8 a 12 segundos; AFTER parado no Mode Select
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
    raw "$RUN_DIR/before_live_body.log" mem_words addr=0x8017566C count=151
    raw "$RUN_DIR/before_jump_table.log" mem_words addr=0x801AC9C0 count=19
    raw "$RUN_DIR/before_cell_80020800.log" mem_words addr=0x80020800 count=2
    raw "$RUN_DIR/before_cell_800D6400.log" mem_words addr=0x800D6400 count=2
    raw "$RUN_DIR/before_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/before_phase_profile.log" phase_profile window=1
    static_misses before
    raw "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/before_pc_watch_dump.log" pc_watch_dump
    raw "$RUN_DIR/window_pc_watch_reset.log" pc_watch_reset
}

collect_after() {
    local seconds="$1" window="$1"
    (( window < 1 )) && window=1
    (( window > 60 )) && window=60
    note "Congelando contadores e coletando AFTER"
    raw "$RUN_DIR/after_pc_watch_stop.log" pc_watch_stop
    raw "$RUN_DIR/after_pc_watch_dump.log" pc_watch_dump
    raw "$RUN_DIR/after_live_body.log" mem_words addr=0x8017566C count=151
    raw "$RUN_DIR/after_jump_table.log" mem_words addr=0x801AC9C0 count=19
    raw "$RUN_DIR/after_cell_80020800.log" mem_words addr=0x80020800 count=2
    raw "$RUN_DIR/after_cell_800D6400.log" mem_words addr=0x800D6400 count=2
    raw "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/after_latency.log" latency window=1024 raw=1 count=120
    raw "$RUN_DIR/after_phase_profile.log" phase_profile window="$window"
    static_misses after
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
    try: return int(v or 0)
    except (ValueError,TypeError): return 0

def words(name): return [str(x).upper() for x in payload(name).get('words',[])]
def word_hash(values):
    if len(values)!=151: return 'INVALIDO'
    return hashlib.sha256(b''.join(struct.pack('<I',int(x,16)) for x in values)).hexdigest().upper()
def miss_set(name):
    return {str(e.get('pc','')).upper() for e in payload(name).get('entries',[]) if e.get('pc')}

watch=payload('after_pc_watch_dump.log')
entries={str(e.get('target','')).upper():e for e in watch.get('entries',[])}
root=entries.get('0X8017566C',{})
interior=entries.get('0X801757E4',{})
resume_a=entries.get('0X80175848',{})
resume_b=entries.get('0X80175888',{})
shape=num(watch.get('count'))==4 and set(entries)=={
    '0X8017566C','0X801757E4','0X80175848','0X80175888'}

before_body=words('before_live_body.log'); after_body=words('after_live_body.log')
before_hash=word_hash(before_body); after_hash=word_hash(after_body)
expected_hash='5DA650C3D1A23F0C9E8359253D73D3741BE92D12BB348ECBCEB94A2FEE3014E2'
body_ok=before_hash==expected_hash and after_hash==expected_hash and before_body==after_body

expected_table=(
    ['0X801756B0','0X80175714','0X80175730','0X80175798','0X801757DC']+
    ['0X801758B4']*11+['0X801757EC','0X80175874','0X80175890']
)
before_table=words('before_jump_table.log'); after_table=words('after_jump_table.log')
table_ok=before_table==expected_table and after_table==expected_table

bdisp=payload('before_dispatch_stats.log'); adisp=payload('after_dispatch_stats.log')
bdirty=payload('before_dirty_ram_stats.log'); adirty=payload('after_dirty_ram_stats.log')
bmiss=miss_set('before_static_text_misses.log'); amiss=miss_set('after_static_text_misses.log')
protected={'0X8017566C','0X801757E4','0X80175848','0X80175888'}
protected_fallback=sorted((bmiss|amiss)&protected)
new_misses=sorted(amiss-bmiss)
aborts_stable=num(adirty.get('aborts'))==num(bdirty.get('aborts'))
blocked_stable=num(adirty.get('text_native_blocked'))==num(bdirty.get('text_native_blocked'))

root_native=num(root.get('native_hits')); root_interp=num(root.get('interpreted_hits'))
interior_interp=num(interior.get('interpreted_hits'))
resume_a_interp=num(resume_a.get('interpreted_hits')); resume_b_interp=num(resume_b.get('interpreted_hits'))
gate=(shape and root_native>0 and root_interp==0 and interior_interp==0 and
      resume_a_interp==0 and resume_b_interp==0 and body_ok and table_ok and
      not protected_fallback and aborts_stable and blocked_stable)

lat=payload('after_latency.log'); phase=payload('after_phase_profile.log')
frame=lat.get('summary',{}).get('frame_period',{})
duration=payload('duration.json').get('seconds','n/d')
lines=[
    f'# Telemetria {run.name}','', '## Resultado S1-258','',
    f'- Duracao da janela: {duration} s',
    f'- Raiz 0x8017566C: {root_native} hits nativos; {root_interp} interpretados',
    f'- Entrada interior 0x801757E4: {num(interior.get("hits"))} hits; {interior_interp} interpretados',
    f'- Retorno JALR 0x80175848: {num(resume_a.get("hits"))} hits; {resume_a_interp} interpretados',
    f'- Retorno JALR 0x80175888: {num(resume_b.get("hits"))} hits; {resume_b_interp} interpretados',
    f'- Corpo vivo BEFORE/AFTER: {before_hash} / {after_hash}; exato e estavel: {"sim" if body_ok else "nao"}',
    f'- Jump table 0x801AC9C0 exata e estavel: {"sim" if table_ok else "nao"}',
    f'- Celula 0x80020800 BEFORE/AFTER: {words("before_cell_80020800.log")} / {words("after_cell_80020800.log")}',
    f'- Celula 0x800D6404 BEFORE/AFTER: {words("before_cell_800D6400.log")} / {words("after_cell_800D6400.log")}',
    f'- Fallback protegido: {protected_fallback or "nenhum"}',
    f'- Novos PCs interpretados durante a janela: {new_misses or "nenhum"}',
    f'- Delta miss_total: {num(adisp.get("miss_total"))-num(bdisp.get("miss_total"))} (informativo; 0x80103384 ainda e globalmente interpretada)',
    f'- aborts estaveis: {"sim" if aborts_stable else "nao"}',
    f'- text_native_blocked estavel: {"sim" if blocked_stable else "nao"}', '',
    '## Frametime','',
    f'- P50/P95/max: {num(frame.get("p50_us"))/1000:.3f} / {num(frame.get("p95_us"))/1000:.3f} / {num(frame.get("max_us"))/1000:.3f} ms',
    f'- Fases: interpreter={phase.get("interp_share","n/d")}; static={phase.get("static_share","n/d")}; GPU={phase.get("gpu_share","n/d")}', '',
    f'- Gate tecnico S1-258: {"CONFIRMADO" if gate else "INSUFICIENTE"}', '',
    '- Retornos JALR zerados significam rota nao exercitada; hits interpretados reprovam o gate.',
    '- A coleta nao substitui a regressao manual das transicoes e demais modos.', ''
]
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

prepare() {
    validate_build; trap cleanup EXIT
    [[ ! -e "$STATE_FILE" ]] || fail "Ja existe uma coleta S1-258 pendente. Conclua com AFTER."
    make_run_dir; metadata; arm; RUN_START_EPOCH=0; write_state prepared; PRESERVE_SESSION=1
    printf '\nArtefato S1-258 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"
    note "PREPARE concluido. Entre no Mode Select e execute BEFORE com a tela estabilizada"
}

before_phase() {
    validate_build; trap cleanup EXIT; read_state
    [[ "$RUN_PHASE" == prepared ]] || fail "A coleta esta na fase $RUN_PHASE; execute AFTER, nao BEFORE."
    collect_before
    RUN_START_EPOCH="$(date +%s)"
    write_state before; PRESERVE_SESSION=1
    note "BEFORE concluido. Percorra as opcoes sem confirmar e execute AFTER ainda no Mode Select"
}

after_phase() {
    validate_build; trap cleanup EXIT; read_state
    [[ "$RUN_PHASE" == before ]] || fail "A coleta esta na fase $RUN_PHASE; execute BEFORE primeiro."
    local end seconds
    end="$(date +%s)"; seconds=$((end-RUN_START_EPOCH))
    printf '{"seconds":%d}\n' "$seconds" >"$RUN_DIR/duration.json"
    collect_after "$seconds"
    summary
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
