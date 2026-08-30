#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly RAW_TCP="$FRAMEWORK_ROOT/tools/raw_tcp.py"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly WATCHLIST_FILE="$PROJECT_ROOT/seeds/s1_259_event_watchlist.txt"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-259-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_SHA=C0E7A0A37DB76E98E731D4E9CA5A0882DE02802E8CDADA5805E07C83DE15999F
readonly EXPECTED_BODY_SHA=37B07726C20B9FBADA32ADF7CC1ED776D342F0F742F1FEA3734EA48EB6A26179
readonly POLL_SECONDS=0.5

PYTHON_BIN=
DEBUG_PORT=
SESSION_DIR=
ARMED=0
EVENT_NUMBER=0
declare -a WATCH_TARGETS=()

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

usage() {
    cat <<'EOF'
Uso, no MSYS2 UCRT64, com a build S1-259 de telemetria aberta:

  bash tools/observe_s1_259_watch_events.sh

Fluxo:

  1. Execute o observador e posicione o jogo no inicio da rota.
  2. Pressione Enter para armar e percorra menus, transicoes e modos.
  3. Quando a funcao observada executar, a janela sera congelada e o
     terminal emitira um aviso.
  4. Informe uma tag que descreva exatamente a tela/transicao atual, por
     exemplo: menu-options ou versus-select-confirm.
  5. Mude para a proxima tela; somente entao pressione Enter para rearmar.
  6. Na pergunta de rearme, digite q para encerrar de forma limpa.

O polling ocorre a cada 500 ms. Nenhum pacote de evento e gravado antes de um
hit. O script nao gera fontes, nao compila e nao altera seeds.
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
    local line target normalized
    while IFS= read -r line || [[ -n "$line" ]]; do
        target="${line%%#*}"
        target="$(printf '%s' "$target" | tr -d '[:space:]')"
        [[ -n "$target" ]] || continue
        [[ "$target" =~ ^0[xX][0-9A-Fa-f]{8}$ ]] ||
            fail "Endereco invalido na watchlist: $target"
        normalized="0x$(printf '%s' "${target:2}" | tr '[:lower:]' '[:upper:]')"
        [[ " ${WATCH_TARGETS[*]-} " != *" $normalized "* ]] ||
            fail "Endereco duplicado na watchlist: $normalized"
        WATCH_TARGETS+=("$normalized")
    done <"$WATCHLIST_FILE"
    (( ${#WATCH_TARGETS[@]} == 1 )) || fail "A watchlist S1-259 deve conter exatamente um alvo."
    [[ "${WATCH_TARGETS[0]}" == 0x801939A0 ]] || fail "O unico alvo permitido e 0x801939A0."
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum nm awk grep sed tr sleep; do
        command -v "$tool" >/dev/null || fail "$tool nao encontrado no UCRT64."
    done
    [[ -f "$RAW_TCP" && -f "$GAME_TOML" && -f "$RANGES_FILE" &&
       -f "$WATCHLIST_FILE" && -f "$CMAKE_CACHE" && -f "$RUNTIME_EXE" ]] ||
        fail "Build S1-259, watchlist ou ferramentas ausentes."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_SHA" ]] ||
        fail "Ranges atuais nao correspondem ao S1-259 aprovado."
    [[ "$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")" == 1058 ]] ||
        fail "A baseline nao possui as 1.058 funcoes esperadas."
    grep -q '^CMAKE_BUILD_TYPE:STRING=RelWithDebInfo$' "$CMAKE_CACHE" || fail "A build nao esta RelWithDebInfo."
    grep -q '^PSX_DEBUG_TOOLS:BOOL=ON$' "$CMAKE_CACHE" || fail "A build nao possui PSX_DEBUG_TOOLS=ON."
    grep -q '^PSX_STATIC_RUNTIME:BOOL=ON$' "$CMAKE_CACHE" || fail "A build nao possui runtime estatico."
    nm -C "$RUNTIME_EXE" | grep -E '[[:space:]]T[[:space:]]+func_801939A0$' >/dev/null ||
        fail "O executavel nao corresponde a baseline S1-259."
    select_python
    read_debug_port
    load_watchlist
    local target address
    for target in "${WATCH_TARGETS[@]}"; do
        address="${target#0x}"
        grep -q "^F ${address}$" "$RANGES_FILE" ||
            fail "$target nao esta nativa no manifest S1-259."
        nm -C "$RUNTIME_EXE" | grep -E "[[:space:]]T[[:space:]]+func_${address}$" >/dev/null ||
            fail "$target nao esta presente como simbolo nativo no executavel."
    done
}

tcp_capture() {
    "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@"
}

require_ok_text() {
    grep -q '"ok":true' <<<"$1" || fail "Resposta TCP invalida para $2."
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
}

dump_has_hits() {
    "$PYTHON_BIN" -c '
import json,re,sys
text=sys.stdin.read()
m=re.search(r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===",text,re.S)
if not m: raise SystemExit(2)
data=json.loads(m.group(1))
raise SystemExit(0 if any(int(e.get("hits",0) or 0)>0 for e in data.get("entries",[])) else 1)
'
}

print_hits() {
    "$PYTHON_BIN" -c '
import json,re,sys
text=sys.stdin.read()
m=re.search(r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===",text,re.S)
if not m: raise SystemExit("payload pc_watch ausente")
data=json.loads(m.group(1))
for e in data.get("entries",[]):
    hits=int(e.get("hits",0) or 0)
    if hits:
        print(f"  {e.get('"'"'target'"'"')}: hits={hits}; nativos={e.get('"'"'native_hits'"'"',0)}; "
              f"interpretados={e.get('"'"'interpreted_hits'"'"',0)}; "
              f"frames={e.get('"'"'first_frame'"'"',0)}..{e.get('"'"'last_frame'"'"',0)}")
'
}

sanitize_tag() {
    local tag="$1"
    tag="$(printf '%s' "$tag" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+|-+$//g')"
    printf '%s' "$tag"
}

drain_pending_input() {
    local discarded
    while IFS= read -r -s -n 1 -t 0.01 discarded; do :; done
}

read_event_tag() {
    local raw_tag tag
    # Teclas pressionadas no jogo podem deixar sequencias ANSI no terminal.
    # Descartamos esse buffer antes de aceitar a tag do evento.
    drain_pending_input
    while true; do
        read -r -p 'Digite a tag da tela/transicao atual: ' raw_tag
        if [[ -z "$raw_tag" || ${#raw_tag} -gt 48 || "$raw_tag" =~ [[:cntrl:]] ]]; then
            printf 'Tag invalida. Use de 1 a 48 caracteres sem teclas de controle.\n' >&2
            drain_pending_input
            continue
        fi
        tag="$(sanitize_tag "$raw_tag")"
        if [[ -z "$tag" || ${#tag} -gt 48 ]]; then
            printf 'Tag invalida depois da normalizacao; tente novamente.\n' >&2
            drain_pending_input
            continue
        fi
        printf '%s' "$tag"
        return
    done
}

make_session_dir() {
    local n candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for n in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/s1-259-watch-events-$n"
        if [[ ! -e "$candidate" ]]; then
            mkdir "$candidate"; SESSION_DIR="$candidate"; return
        fi
    done
    fail "Nao ha identificador livre para uma nova sessao."
}

write_session_metadata() {
    {
        printf 'baseline=S1-259\n'
        printf 'purpose=locate positive route for 0x801939A0\n'
        printf 'poll_seconds=%s\n' "$POLL_SECONDS"
        printf 'watchlist=%s\n' "${WATCH_TARGETS[*]}"
        printf 'expected_body_sha256=%s\n' "$EXPECTED_BODY_SHA"
        printf 'ranges_sha256=%s\n' "$(sha256sum "$RANGES_FILE" | awk '{print $1}')"
        printf 'runtime_exe_sha256=%s\n' "$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')"
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
}

save_event() {
    local dump="$1" stop_response="$2" tag event_id event_dir
    printf '\a\nEVENTO ENCONTRADO — observacao congelada.\n'
    printf '%s' "$dump" | print_hits
    tag="$(read_event_tag)"
    EVENT_NUMBER=$((EVENT_NUMBER+1))
    event_id="$(printf '%03d' "$EVENT_NUMBER")"
    event_dir="$SESSION_DIR/event-${event_id}-${tag}"
    mkdir "$event_dir"
    printf '%s\n' "$dump" >"$event_dir/pc_watch_dump.log"
    printf '%s\n' "$stop_response" >"$event_dir/pc_watch_stop.log"
    tcp_capture dispatch_stats >"$event_dir/dispatch_stats.log"
    tcp_capture dirty_ram_stats >"$event_dir/dirty_ram_stats.log"
    tcp_capture mem_words addr=0x801939A0 count=30 >"$event_dir/live_body.log"
    tcp_capture mem_words addr=0x80134EF8 count=2 >"$event_dir/live_caller.log"
    {
        printf 'event=%s\n' "$event_id"
        printf 'tag=%s\n' "$tag"
        printf 'captured_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$event_dir/metadata.txt"
    "$PYTHON_BIN" - "$event_dir" <<'PY'
import json,pathlib,re,sys
event=pathlib.Path(sys.argv[1])
text=(event/'pc_watch_dump.log').read_text(encoding='utf-8',errors='replace')
m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
data=json.loads(m.group(1)) if m else {}
meta={}
for line in (event/'metadata.txt').read_text(encoding='utf-8').splitlines():
    if '=' in line:
        key,value=line.split('=',1); meta[key]=value
lines=[f'# Evento {meta.get("event","?")} - {meta.get("tag","sem-tag")}', '',
       '| Funcao | Hits | Nativos | Interpretados | Primeiro frame | Ultimo frame |',
       '|---|---:|---:|---:|---:|---:|']
for entry in data.get('entries',[]):
    hits=int(entry.get('hits',0) or 0)
    if hits:
        lines.append(f'| {entry.get("target")} | {hits} | {entry.get("native_hits",0)} | '
                     f'{entry.get("interpreted_hits",0)} | {entry.get("first_frame",0)} | '
                     f'{entry.get("last_frame",0)} |')
lines += ['', '- Baseline executada: S1-259.',
          '- A tag identifica o contexto informado pelo usuario; nao e caller MIPS automatico.', '']
(event/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
    note "Evento salvo em $event_dir"
}

monitor_loop() {
    local dump stop_response choice
    while true; do
        dump="$(tcp_capture pc_watch_dump)" || fail "Falha na consulta pc_watch_dump."
        require_ok_text "$dump" pc_watch_dump
        if printf '%s' "$dump" | dump_has_hits; then
            stop_response="$(tcp_capture pc_watch_stop)"; require_ok_text "$stop_response" pc_watch_stop
            ARMED=0
            dump="$(tcp_capture pc_watch_dump)"; require_ok_text "$dump" pc_watch_dump-final
            save_event "$dump" "$stop_response"
            printf '\nMude para a proxima tela antes de rearmar.\n'
            read -r -p 'Pressione Enter para rearmar ou digite q para encerrar: ' choice
            if [[ "${choice,,}" == q ]]; then return; fi
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
    case "${1:-}" in
        -h|--help) usage; return ;;
        '') ;;
        *) usage; fail "Este script nao recebe argumentos." ;;
    esac
    validate
    trap cleanup EXIT
    make_session_dir
    write_session_metadata
    printf '\nObservador S1-259 preparado para 0x801939A0.\n'
    printf 'Posicione o jogo no inicio da rota desejada.\n'
    read -r -p 'Pressione Enter para iniciar ou digite q para sair: ' choice
    if [[ "${choice,,}" == q ]]; then
        note "Sessao encerrada sem armar: $SESSION_DIR"
        return
    fi
    arm_watchlist
    note "MONITORANDO ${#WATCH_TARGETS[@]} funcao na build S1-259"
    printf 'Alvo: %s\n' "${WATCH_TARGETS[*]}"
    printf 'Use Ctrl+C para interromper ou q depois de um evento para encerrar.\n'
    monitor_loop
    note "Sessao encerrada: $SESSION_DIR"
}

main "$@"
