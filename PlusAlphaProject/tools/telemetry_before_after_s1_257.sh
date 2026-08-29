#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-257-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_SHA=A10B9A83A30D0CB0280F36898971A2D99F804ABC094461994B137F55B635E6CD
readonly STATE_FILE="$PROJECT_ROOT/local/telemetry/.s1-257-telemetry-active.state"
readonly WATCH_SPEC=$'root required 0x8019FC6C\nresume optional 0x8019FCBC\nsetter guard 0x8019FCE4'

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

  bash tools/telemetry_before_after_s1_257.sh prepare
  bash tools/telemetry_before_after_s1_257.sh before
  bash tools/telemetry_before_after_s1_257.sh after

Rota curta da tela de titulo:

  1. Abra manualmente a build S1-257 de telemetria.
  2. Durante os logos/intro imediatamente anteriores ao titulo, execute PREPARE.
  3. Assim que a tela de titulo estabilizar, sem apertar botoes, execute BEFORE.
  4. Deixe a tela parada por aproximadamente 2 segundos.
  5. Antes de a tela desaparecer, execute AFTER.

O BEFORE inicia a janela antes de suas consultas e o AFTER congela os
contadores antes de coletar dados. O script nao gera, compila, abre nem fecha
o jogo. Use apenas uma janela UCRT64.
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
    for tool in objdump nm sha256sum; do command -v "$tool" >/dev/null || fail "$tool nao encontrado no UCRT64."; done
    [[ -f "$GAME_TOML" && -f "$RANGES_FILE" && -f "$RAW_TCP" && -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] ||
        fail "Arquivos da build S1-257 de telemetria estao ausentes."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_SHA" ]] ||
        fail "SHA-256 do manifesto nao corresponde ao S1-257 aprovado."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1056 ]] ||
        fail "A quantidade de funcoes nao corresponde ao S1-257 esperado (1056)."
    require_range 'F 8019FC6C'; require_range 'R 8019FC6C 78'
    ! grep -Eq '^F (80103384|8017566C|8019E6D0|8019FCE4)$' "$RANGES_FILE" ||
        fail "Uma funcao fora do micro-lote apareceu nos fontes."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" || fail "A build nao esta RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" || fail "A build nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" || fail "A build nao possui PSX_STATIC_RUNTIME=ON."
    require_symbol func_8019FC6C
    ! nm -C "$RUNTIME_EXE" | grep -q -E '[[:space:]]T[[:space:]]+func_(80103384|8017566C|8019E6D0|8019FCE4)$' ||
        fail "O executavel contem uma funcao fora do micro-lote."
    select_python
    read_debug_port
}

raw() {
    local output="$1"; shift
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@" >"$output" 2>&1 || fail "Falha na consulta TCP: $*"
    grep -q '"ok":true' "$output" || fail "Resposta TCP invalida em $(basename "$output")."
}

make_run_dir() {
    local n candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for n in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-257-telemetry-$n"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; RUN_DIR="$candidate"; return; fi
    done
    fail "Nao ha run-id livre entre s1-257-telemetry-01 e 99."
}

write_state() {
    umask 077
    printf 'run_dir=%s\nphase=%s\nstart_epoch=%s\n' "$RUN_DIR" "$1" "$RUN_START_EPOCH" >"$STATE_FILE"
    RUN_PHASE="$1"
}

read_state() {
    [[ -f "$STATE_FILE" ]] || fail "Nao existe coleta S1-257 preparada. Execute primeiro prepare."
    RUN_DIR="$(awk -F= '$1=="run_dir" {print substr($0,index($0,"=")+1);exit}' "$STATE_FILE")"
    RUN_PHASE="$(awk -F= '$1=="phase" {print $2;exit}' "$STATE_FILE")"
    RUN_START_EPOCH="$(awk -F= '$1=="start_epoch" {print $2;exit}' "$STATE_FILE")"
    case "$RUN_DIR" in "$PROJECT_ROOT"/local/telemetry/s1-257-telemetry-*) ;; *) fail "Estado S1-257 invalido." ;; esac
    [[ -d "$RUN_DIR" && "$RUN_START_EPOCH" =~ ^[0-9]+$ ]] || fail "Estado S1-257 incompleto."
}

metadata() {
    cat >"$RUN_DIR/metadata.txt" <<EOF
run_id=$(basename "$RUN_DIR")
candidate=S1-257
function=0x8019FC6C; boundary=0x8019FC6C..0x8019FCE3; words=30
jalr=0x8019FCB4; continuation=0x8019FCBC
callback_table=0x801BEEC4..0x801BEEE0; counter=0x801BEEE4
setter_guard=0x8019FCE4
ranges_sha256=$(sha256sum "$RANGES_FILE" | awk '{print $1}')
runtime_exe_sha256=$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')
runtime_build=buildClean-ucrt-s1-257-tele
mode=tela de titulo parada
route=PREPARE durante logos; BEFORE no titulo; aproximadamente 2 segundos sem input; AFTER antes da transicao
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

arm() {
    local label kind target
    raw "$RUN_DIR/prepare_pc_watch_clear.log" pc_watch_clear
    while read -r label kind target; do
        raw "$RUN_DIR/prepare_pc_watch_arm_${label}_${target#0x}.log" pc_watch_arm target="$target"
    done <<<"$WATCH_SPEC"
    raw "$RUN_DIR/prepare_pc_watch_dump.log" pc_watch_dump
}

summary() {
    "$PYTHON_BIN" - "$RUN_DIR" <<'PY'
import json,pathlib,re,sys
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

watch=payload('after_pc_watch_dump.log')
entries={str(e.get('target','')).upper():e for e in watch.get('entries',[])}
root=entries.get('0X8019FC6C',{})
resume=entries.get('0X8019FCBC',{})
setter=entries.get('0X8019FCE4',{})
root_native=num(root.get('native_hits'))
root_interpreted=num(root.get('interpreted_hits'))
resume_native=num(resume.get('native_hits'))
resume_interpreted=num(resume.get('interpreted_hits'))
setter_hits=num(setter.get('hits'))
shape=num(watch.get('count'))==3 and set(entries)=={'0X8019FC6C','0X8019FCBC','0X8019FCE4'}

before=words('before_callback_table.log')
after=words('after_callback_table.log')
slots_zero=(len(before)==9 and len(after)==9 and all(int(x,16)==0 for x in before[:8]+after[:8]))
counter_before=int(before[8],16) if len(before)==9 else 0
counter_after=int(after[8],16) if len(after)==9 else 0
counter_grew=counter_after>counter_before

bdisp=payload('before_dispatch_stats.log'); adisp=payload('after_dispatch_stats.log')
bdirty=payload('before_dirty_ram_stats.log'); adirty=payload('after_dirty_ram_stats.log')
miss_delta=num(adisp.get('miss_total'))-num(bdisp.get('miss_total'))
aborts_stable=num(adirty.get('aborts'))==num(bdirty.get('aborts'))
blocked_stable=num(adirty.get('text_native_blocked'))==num(bdirty.get('text_native_blocked'))

miss_payload=payload('after_static_text_misses.log')
misses=miss_payload.get('entries',[])
snapshot_complete=(num(miss_payload.get('dropped'))==0 and
                   num(miss_payload.get('returned'))==num(miss_payload.get('total')) and
                   num(miss_payload.get('total'))<=256)
fallback=sorted({str(e.get('pc','')).upper() for e in misses if str(e.get('pc','')).upper() in {'0X8019FC6C','0X8019FCBC'}})
gate=(shape and root_native>0 and root_interpreted==0 and resume_interpreted==0 and setter_hits==0 and
      slots_zero and counter_grew and snapshot_complete and miss_delta==0 and aborts_stable and blocked_stable and not fallback)
duration=payload('duration.json').get('seconds','n/d')
lines=[
    f'# Telemetria {run.name}','', '## Resultado S1-257','',
    f'- Duracao da janela: {duration} s',
    f'- Raiz 0x8019FC6C: {root_native} hits nativos; {root_interpreted} interpretados',
    f'- Continuacao 0x8019FCBC: {resume_native} hits nativos; {resume_interpreted} interpretados (diagnostico opcional)',
    f'- Setter 0x8019FCE4: {setter_hits} hits (guard esperado: zero)',
    f'- Oito callbacks zerados em BEFORE e AFTER: {"sim" if slots_zero else "nao"}',
    f'- Contador 0x801BEEE4: 0x{counter_before:08X} -> 0x{counter_after:08X}; cresceu: {"sim" if counter_grew else "nao"}',
    f'- Snapshot de fallbacks completo: {"sim" if snapshot_complete else "nao"}',
    f'- Fallback protegido: {fallback or "nenhum"}',
    f'- Delta miss_total: {miss_delta}',
    f'- aborts estaveis: {"sim" if aborts_stable else "nao"}',
    f'- text_native_blocked estavel: {"sim" if blocked_stable else "nao"}',
    f'- Gate tecnico S1-257: {"CONFIRMADO" if gate else "INSUFICIENTE"}', '',
    '- A continuacao pode permanecer sem hits no pc_watch quando executada como bloco interno da funcao nativa; somente hits interpretados nela reprovam.',
    '- A coleta nao substitui a regressao manual da tela de titulo e das demais rotas.', ''
]
(run/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

prepare() {
    validate_build; trap cleanup EXIT
    [[ ! -e "$STATE_FILE" ]] || fail "Ja existe uma coleta S1-257 pendente. Conclua com AFTER."
    make_run_dir; metadata; arm; RUN_START_EPOCH=0; write_state prepared; PRESERVE_SESSION=1
    printf '\nArtefato S1-257 validado; jogo detectado na porta %s.\n' "$DEBUG_PORT"
    note "PREPARE concluido. Execute BEFORE assim que a tela de titulo estabilizar"
}

before_phase() {
    validate_build; trap cleanup EXIT; read_state
    [[ "$RUN_PHASE" == prepared ]] || fail "A coleta esta na fase $RUN_PHASE; execute AFTER, nao BEFORE."
    note "Iniciando imediatamente a janela da tela de titulo"
    raw "$RUN_DIR/window_pc_watch_reset.log" pc_watch_reset
    RUN_START_EPOCH="$(date +%s)"
    raw "$RUN_DIR/before_callback_table.log" mem_words addr=0x801BEEC4 count=9
    raw "$RUN_DIR/before_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/before_dirty_ram_stats.log" dirty_ram_stats
    write_state before; PRESERVE_SESSION=1
    note "BEFORE concluido. Aguarde cerca de 2 segundos sem input e execute AFTER antes da transicao"
}

after_phase() {
    validate_build; trap cleanup EXIT; read_state
    [[ "$RUN_PHASE" == before ]] || fail "A coleta esta na fase $RUN_PHASE; execute BEFORE primeiro."
    local end seconds
    end="$(date +%s)"; seconds=$((end-RUN_START_EPOCH))
    printf '{"seconds":%d}\n' "$seconds" >"$RUN_DIR/duration.json"
    raw "$RUN_DIR/after_pc_watch_stop.log" pc_watch_stop
    raw "$RUN_DIR/after_pc_watch_dump.log" pc_watch_dump
    raw "$RUN_DIR/after_callback_table.log" mem_words addr=0x801BEEC4 count=9
    raw "$RUN_DIR/after_dispatch_stats.log" dispatch_stats
    raw "$RUN_DIR/after_dirty_ram_stats.log" dirty_ram_stats
    raw "$RUN_DIR/after_static_text_misses.log" static_text_misses class=all min_hits=1 offset=0 limit=256
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
