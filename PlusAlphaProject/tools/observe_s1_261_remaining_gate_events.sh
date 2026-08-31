#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly RAW_TCP="$REPO_ROOT/psxrecomp/tools/raw_tcp.py"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly WATCHLIST_FILE="$PROJECT_ROOT/seeds/s1_261_remaining_gate_watchlist.txt"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-260-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_RUNTIME_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly POLL_SECONDS=0.5
readonly GATE_SAMPLE_EVERY_TICKS=4
readonly GATE_WORD_ADDRESS=0x801F9600

PYTHON_BIN=
DEBUG_PORT=
SESSION_DIR=
ARMED=0
EVENT_NUMBER=0
POLL_TICK=0
GATE_SAMPLES=0
GATE_ZERO_SEEN=0
GATE_NONZERO_SEEN=0
GATE_LAST_BYTE=-1
declare -a WATCH_TARGETS=()
declare -a TRIGGER_TARGETS=()
declare -A TARGET_ROLES=()

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

usage() {
    cat <<'EOF'
Uso, no MSYS2 UCRT64, com a build S1-260 de telemetria aberta:

  bash tools/observe_s1_261_remaining_gate_events.sh

Use obrigatoriamente:

  buildClean-ucrt-s1-260-tele/StreetFighterEXPlusAlphaRecomp.exe

Fluxo:

  1. O script valida tudo e espera Enter antes de armar.
  2. Pressione Enter e percorra telas, transicoes e modos livremente.
  3. A raiz 0x80103384 sera contada, mas nao interrompera a procura.
  4. Uma das cinco funcoes do ramo maior congelara a observacao.
  5. Informe a tag exata da tela/transicao atual.
  6. Mude de contexto e pressione Enter para rearmar, ou digite q.
  7. Ctrl+C salva o dump final e gera summary.md mesmo sem nenhum gatilho.

O polling ocorre a cada 500 ms e o byte de gate 0x801F9603 e amostrado a cada
2 segundos. O script nao gera fontes, nao compila e nao altera seeds
principais. A build Release S1-261 nao possui servidor TCP e nao pode ser usada
neste observador.
EOF
}

cleanup() {
    if (( ARMED == 1 )) && [[ -n "$PYTHON_BIN" && -n "$DEBUG_PORT" ]]; then
        "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" pc_watch_stop >/dev/null 2>&1 || true
    fi
}

select_python() {
    if command -v python >/dev/null; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no PATH do UCRT64."
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

load_watchlist() {
    local line payload role target extra normalized
    while IFS= read -r line || [[ -n "$line" ]]; do
        payload="${line%%#*}"
        payload="$(printf '%s' "$payload" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        [[ -n "$payload" ]] || continue
        read -r role target extra <<<"$payload"
        [[ -z "${extra:-}" ]] || fail "Linha invalida na watchlist: $line"
        [[ "$role" == context || "$role" == trigger ]] || fail "Papel invalido: $role"
        [[ "$target" =~ ^0[xX][0-9A-Fa-f]{8}$ ]] || fail "Endereco invalido: $target"
        normalized="0x$(printf '%s' "${target:2}" | tr '[:lower:]' '[:upper:]')"
        [[ -z "${TARGET_ROLES[$normalized]+x}" ]] || fail "Endereco duplicado: $normalized"
        WATCH_TARGETS+=("$normalized")
        TARGET_ROLES["$normalized"]="$role"
        [[ "$role" == trigger ]] && TRIGGER_TARGETS+=("$normalized")
    done <"$WATCHLIST_FILE"

    local expected_all expected_triggers
    expected_all="0x80103384 0x8016EA0C 0x8016EA60 0x8016EAE8 0x8016F560 0x8016FB64"
    expected_triggers="0x8016EA0C 0x8016EA60 0x8016EAE8 0x8016F560 0x8016FB64"
    [[ "${WATCH_TARGETS[*]}" == "$expected_all" ]] ||
        fail "A watchlist deve conter exatamente a raiz e as cinco funcoes restantes."
    [[ "${TRIGGER_TARGETS[*]}" == "$expected_triggers" ]] || fail "Gatilhos divergentes."
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum nm awk grep sed tr sleep; do
        command -v "$tool" >/dev/null || fail "$tool nao encontrado no UCRT64."
    done
    [[ -f "$RAW_TCP" && -f "$GAME_TOML" && -f "$RANGES_FILE" &&
       -f "$WATCHLIST_FILE" && -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] ||
        fail "Build S1-260 de telemetria, watchlist ou ferramentas ausentes."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] ||
        fail "Ranges atuais nao correspondem ao checkpoint S1-261/S1-260."
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_RUNTIME_SHA" ]] ||
        fail "Executavel S1-260 de telemetria divergente."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1059 ]] ||
        fail "A baseline nao possui as 1.059 funcoes esperadas."
    grep -qxF 'CMAKE_BUILD_TYPE:STRING=RelWithDebInfo' "$CMAKE_CACHE" || fail "Build nao esta RelWithDebInfo."
    grep -qxF 'PSX_DEBUG_TOOLS:BOOL=ON' "$CMAKE_CACHE" || fail "PSX_DEBUG_TOOLS nao esta ativo."
    grep -qxF 'PSX_STATIC_RUNTIME:BOOL=ON' "$CMAKE_CACHE" || fail "Runtime estatico nao esta ativo."
    nm -C "$RUNTIME_EXE" | grep -Eq '[[:space:]]T[[:space:]]+func_80103BD8$' ||
        fail "O executavel nao contem a funcao S1-260 promovida."
    select_python
    read_debug_port
    load_watchlist
    local target address
    for target in "${WATCH_TARGETS[@]}"; do
        address="${target#0x}"
        ! grep -q "^F ${address}$" "$RANGES_FILE" || fail "$target ja esta nativa."
        ! nm -C "$RUNTIME_EXE" | grep -Eq "[[:space:]]T[[:space:]]+func_${address}$" ||
            fail "$target apareceu como simbolo nativo no executavel."
    done
}

tcp_capture() { "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@"; }
require_ok_text() { grep -q '"ok":true' <<<"$1" || fail "Resposta TCP invalida para $2."; }

sample_gate() {
    local response word hex value byte
    response="$(tcp_capture mem_words addr="$GATE_WORD_ADDRESS" count=1 2>/dev/null)" || return 1
    grep -q '"ok":true' <<<"$response" || return 1
    word="$(printf '%s\n' "$response" |
        sed -nE 's/.*"words":\["(0x[0-9A-Fa-f]{8})"\].*/\1/p' | sed -n '1p')"
    [[ "$word" =~ ^0x[0-9A-Fa-f]{8}$ ]] || return 1
    hex="${word#0x}"; value=$((16#$hex)); byte=$(((value >> 24) & 255))
    GATE_SAMPLES=$((GATE_SAMPLES+1)); GATE_LAST_BYTE="$byte"
    if (( byte == 0 )); then GATE_ZERO_SEEN=1; else GATE_NONZERO_SEEN=1; fi
    printf '%s,%s,%d\n' "$(date +%s)" "$word" "$byte" >>"$SESSION_DIR/gate_samples.csv"
}

arm_watchlist() {
    local response target
    response="$(tcp_capture pc_watch_clear)"; require_ok_text "$response" pc_watch_clear
    for target in "${WATCH_TARGETS[@]}"; do
        response="$(tcp_capture pc_watch_arm target="$target")"
        require_ok_text "$response" "pc_watch_arm $target"
    done
    response="$(tcp_capture pc_watch_reset)"; require_ok_text "$response" pc_watch_reset
    ARMED=1
    sample_gate || true
}

dump_has_hits() {
    "$PYTHON_BIN" -c '
import json,re,sys
triggers=set(sys.argv[1:]); text=sys.stdin.read()
m=re.search(r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===",text,re.S)
if not m: raise SystemExit(2)
data=json.loads(m.group(1))
raise SystemExit(0 if any(e.get("target") in triggers and int(e.get("hits",0) or 0)>0
                          for e in data.get("entries",[])) else 1)
' "${TRIGGER_TARGETS[@]}" 2>/dev/null
}

print_hits() {
    "$PYTHON_BIN" -c '
import json,re,sys
triggers=set(sys.argv[1:]); text=sys.stdin.read()
m=re.search(r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===",text,re.S)
if not m: raise SystemExit("payload pc_watch ausente")
for e in json.loads(m.group(1)).get("entries",[]):
    hits=int(e.get("hits",0) or 0)
    if hits:
        role="GATILHO" if e.get("target") in triggers else "contexto"
        target=e.get("target")
        native_hits=e.get("native_hits",0)
        interpreted_hits=e.get("interpreted_hits",0)
        first_frame=e.get("first_frame",0)
        last_frame=e.get("last_frame",0)
        print(f"  {target} [{role}]: hits={hits}; nativos={native_hits}; "
              f"interpretados={interpreted_hits}; frames={first_frame}..{last_frame}")
' "${TRIGGER_TARGETS[@]}"
}

sanitize_tag() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' |
        sed -E 's/[^a-z0-9._-]+/-/g; s/^-+|-+$//g'
}

drain_pending_input() {
    local discarded
    while IFS= read -r -s -n 1 -t 0.01 discarded; do :; done
}

read_event_tag() {
    local raw_tag tag
    drain_pending_input
    while true; do
        read -r -p 'Digite a tag da tela/transicao atual: ' raw_tag
        if [[ -z "$raw_tag" || ${#raw_tag} -gt 48 || "$raw_tag" =~ [[:cntrl:]] ]]; then
            printf 'Tag invalida. Use de 1 a 48 caracteres sem teclas de controle.\n' >&2
            drain_pending_input; continue
        fi
        tag="$(sanitize_tag "$raw_tag")"
        if [[ -z "$tag" || ${#tag} -gt 48 ]]; then
            printf 'Tag invalida depois da normalizacao.\n' >&2
            drain_pending_input; continue
        fi
        printf '%s' "$tag"; return
    done
}

make_session_dir() {
    local n candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for n in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-261-remaining-gate-discovery-$n"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; SESSION_DIR="$candidate"; return; fi
    done
    fail "Nao ha identificador livre para uma nova sessao."
}

write_session_metadata() {
    {
        printf 'checkpoint=S1-261\n'
        printf 'runtime_build=buildClean-ucrt-s1-260-tele\n'
        printf 'purpose=locate routes for the remaining 604-word branch\n'
        printf 'remaining_total_words=936\n'
        printf 'branch_words=604\n'
        printf 'final_root_words=332\n'
        printf 'poll_seconds=%s\n' "$POLL_SECONDS"
        printf 'gate_sample_seconds=2\n'
        printf 'gate_byte_address=0x801F9603\n'
        printf 'watchlist=%s\n' "${WATCH_TARGETS[*]}"
        printf 'triggers=%s\n' "${TRIGGER_TARGETS[*]}"
        printf 'ranges_sha256=%s\n' "$(sha256sum "$RANGES_FILE" | awk '{print $1}')"
        printf 'runtime_exe_sha256=%s\n' "$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')"
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
    printf 'epoch,word_0x801F9600,byte_0x801F9603\n' >"$SESSION_DIR/gate_samples.csv"
}

save_event() {
    local dump="$1" stop_response="$2" tag event_id event_dir
    printf '\a\nFUNCAO DO RAMO RESTANTE ENCONTRADA — observacao congelada.\n'
    printf '%s' "$dump" | print_hits
    tag="$(read_event_tag)"
    EVENT_NUMBER=$((EVENT_NUMBER+1)); event_id="$(printf '%03d' "$EVENT_NUMBER")"
    event_dir="$SESSION_DIR/event-${event_id}-${tag}"; mkdir "$event_dir"
    printf '%s\n' "$dump" >"$event_dir/pc_watch_dump.log"
    printf '%s\n' "$stop_response" >"$event_dir/pc_watch_stop.log"
    tcp_capture dispatch_stats >"$event_dir/dispatch_stats.log"
    tcp_capture dirty_ram_stats >"$event_dir/dirty_ram_stats.log"
    tcp_capture mem_words addr="$GATE_WORD_ADDRESS" count=1 >"$event_dir/live_801F9600_gate.log"
    tcp_capture mem_words addr=0x80103384 count=256 >"$event_dir/live_80103384_part1.log"
    tcp_capture mem_words addr=0x80103784 count=76 >"$event_dir/live_80103384_part2.log"
    tcp_capture mem_words addr=0x8016EA0C count=21 >"$event_dir/live_8016EA0C.log"
    tcp_capture mem_words addr=0x8016EA60 count=34 >"$event_dir/live_8016EA60.log"
    tcp_capture mem_words addr=0x8016EAE8 count=256 >"$event_dir/live_8016EAE8_part1.log"
    tcp_capture mem_words addr=0x8016EEE8 count=178 >"$event_dir/live_8016EAE8_part2.log"
    tcp_capture mem_words addr=0x8016F560 count=66 >"$event_dir/live_8016F560.log"
    tcp_capture mem_words addr=0x8016FB64 count=49 >"$event_dir/live_8016FB64.log"
    printf 'event=%s\ntag=%s\ncaptured_utc=%s\n' "$event_id" "$tag" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$event_dir/metadata.txt"
    "$PYTHON_BIN" - "$event_dir" <<'PY'
import json,pathlib,re,sys
event=pathlib.Path(sys.argv[1]); text=(event/'pc_watch_dump.log').read_text(encoding='utf-8',errors='replace')
m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
data=json.loads(m.group(1)) if m else {}; meta={}
for line in (event/'metadata.txt').read_text(encoding='utf-8').splitlines():
    if '=' in line:
        key,value=line.split('=',1); meta[key]=value
lines=[f'# Evento {meta.get("event","?")} - {meta.get("tag","sem-tag")}', '',
       '| Funcao | Hits | Nativos | Interpretados | Primeiro frame | Ultimo frame |',
       '|---|---:|---:|---:|---:|---:|']
for e in data.get('entries',[]):
    hits=int(e.get('hits',0) or 0)
    if hits:
        lines.append(f'| {e.get("target")} | {hits} | {e.get("native_hits",0)} | '
                     f'{e.get("interpreted_hits",0)} | {e.get("first_frame",0)} | {e.get("last_frame",0)} |')
lines += ['', '- Checkpoint de referencia: S1-261; runtime de observacao: S1-260-tele.',
          '- A tag identifica o contexto informado pelo usuario; nao e caller MIPS automatico.', '']
(event/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
    note "Evento salvo em $event_dir"
}

write_final_summary() {
    local reason="$1"
    "$PYTHON_BIN" - "$SESSION_DIR" "$reason" <<'PY'
import csv,json,pathlib,re,sys
session=pathlib.Path(sys.argv[1]); reason=sys.argv[2]

def payload(name):
    path=session/name
    if not path.exists(): return {}
    text=path.read_text(encoding='utf-8',errors='replace')
    match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not match: return {}
    try: return json.loads(match.group(1))
    except json.JSONDecodeError: return {}

watch=payload('final_pc_watch_dump.log')
entries=watch.get('entries',[])
root=next((e for e in entries if e.get('target')=='0x80103384'),{})
triggers=[e for e in entries if e.get('target')!='0x80103384']
trigger_hits=sum(int(e.get('hits',0) or 0) for e in triggers)
samples=[]
gate_path=session/'gate_samples.csv'
if gate_path.exists():
    with gate_path.open(encoding='utf-8',errors='replace',newline='') as stream:
        for row in csv.DictReader(stream):
            try: samples.append(int(row.get('byte_0x801F9603','')))
            except (TypeError,ValueError): pass
zero_count=sum(value==0 for value in samples)
nonzero_count=sum(value!=0 for value in samples)
events=len([p for p in session.iterdir() if p.is_dir() and p.name.startswith('event-')])
if trigger_hits:
    conclusion='gatilho presente no snapshot final'
elif int(root.get('hits',0) or 0)>0:
    conclusion='raiz exercitada; nenhuma das cinco funcoes do ramo maior executou'
else:
    conclusion='nenhum hit da raiz; sessao sem contexto suficiente para concluir a rota'
lines=[f'# Resumo final - {session.name}','',
       f'- Encerramento: {reason}',
       f'- Eventos salvos: {events}',
       f'- Frame final do watcher: {watch.get("frame","n/d")}',
       f'- Hits da raiz 0x80103384: {root.get("hits",0)}',
       f'- Hits totais dos cinco gatilhos: {trigger_hits}',
       f'- Amostras do byte 0x801F9603: {len(samples)}',
       f'- Amostras com gate zero: {zero_count}',
       f'- Amostras com gate diferente de zero: {nonzero_count}',
       f'- Ultimo valor amostrado do gate: {samples[-1] if samples else "n/d"}',
       f'- Conclusao: {conclusion}','',
       '| Funcao | Papel | Hits | Nativos | Interpretados | Primeiro frame | Ultimo frame |',
       '|---|---|---:|---:|---:|---:|---:|']
for entry in entries:
    target=entry.get('target','?'); role='contexto' if target=='0x80103384' else 'gatilho'
    lines.append(f'| {target} | {role} | {entry.get("hits",0)} | {entry.get("native_hits",0)} | '
                 f'{entry.get("interpreted_hits",0)} | {entry.get("first_frame",0)} | '
                 f'{entry.get("last_frame",0)} |')
lines += ['', '- A amostragem do gate ocorre a cada 2 segundos; valores entre amostras nao sao inferidos.',
          '- Um hit do pc_watch e acumulativo e nao seria perdido entre polls de 500 ms.', '']
(session/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

save_final_snapshot() {
    local reason="$1" response
    [[ -n "$SESSION_DIR" && -d "$SESSION_DIR" ]] || return
    sample_gate || true
    if (( ARMED == 1 )); then
        response="$(tcp_capture pc_watch_stop 2>/dev/null)" || response='ERRO: pc_watch_stop falhou'
        printf '%s\n' "$response" >"$SESSION_DIR/final_pc_watch_stop.log"
        ARMED=0
    fi
    tcp_capture pc_watch_dump >"$SESSION_DIR/final_pc_watch_dump.log" 2>&1 || true
    tcp_capture mem_words addr="$GATE_WORD_ADDRESS" count=1 >"$SESSION_DIR/final_gate_word.log" 2>&1 || true
    tcp_capture dispatch_stats >"$SESSION_DIR/final_dispatch_stats.log" 2>&1 || true
    tcp_capture dirty_ram_stats >"$SESSION_DIR/final_dirty_ram_stats.log" 2>&1 || true
    write_final_summary "$reason" || true
}

interrupt_handler() {
    trap - INT
    printf '\n\nCtrl+C recebido; salvando snapshot final da sessao...\n'
    save_final_snapshot ctrl-c
    printf 'Resumo final: %s/summary.md\n' "$SESSION_DIR"
    exit 130
}

monitor_loop() {
    local dump stop_response choice
    while true; do
        dump="$(tcp_capture pc_watch_dump 2>/dev/null)" || fail "Falha na consulta pc_watch_dump."
        require_ok_text "$dump" pc_watch_dump
        POLL_TICK=$((POLL_TICK+1))
        if (( POLL_TICK % GATE_SAMPLE_EVERY_TICKS == 0 )); then sample_gate || true; fi
        if printf '%s' "$dump" | dump_has_hits; then
            sample_gate || true
            stop_response="$(tcp_capture pc_watch_stop)"; require_ok_text "$stop_response" pc_watch_stop
            ARMED=0
            dump="$(tcp_capture pc_watch_dump)"; require_ok_text "$dump" pc_watch_dump-final
            save_event "$dump" "$stop_response"
            printf '\nMude para a proxima tela antes de rearmar.\n'
            read -r -p 'Pressione Enter para rearmar ou digite q para encerrar: ' choice
            [[ "${choice,,}" == q ]] && return
            arm_watchlist
            note "MONITORANDO novamente; percorra o jogo normalmente"
        else
            case $? in 1) ;; *) fail "Nao foi possivel interpretar pc_watch_dump." ;; esac
        fi
        sleep "$POLL_SECONDS"
    done
}

main() {
    local choice
    case "${1:-}" in -h|--help) usage; return ;; '') ;; *) usage; fail "Este script nao recebe argumentos." ;; esac
    validate; trap cleanup EXIT; trap interrupt_handler INT; make_session_dir; write_session_metadata
    printf '\nObservador do ramo restante preparado sobre a build S1-260 de telemetria.\n'
    printf 'Posicione o jogo no inicio da rota desejada.\n'
    read -r -p 'Pressione Enter para iniciar ou digite q para sair: ' choice
    if [[ "${choice,,}" == q ]]; then note "Sessao encerrada sem armar: $SESSION_DIR"; return; fi
    arm_watchlist
    note "MONITORANDO a raiz e cinco funcoes ainda interpretadas"
    printf 'Contexto: 0x80103384\nGatilhos: %s\n' "${TRIGGER_TARGETS[*]}"
    printf 'Use Ctrl+C para interromper ou q depois de um evento para encerrar.\n'
    monitor_loop
    save_final_snapshot normal
    note "Sessao encerrada: $SESSION_DIR"
    printf 'Resumo final: %s/summary.md\n' "$SESSION_DIR"
}

main "$@"
