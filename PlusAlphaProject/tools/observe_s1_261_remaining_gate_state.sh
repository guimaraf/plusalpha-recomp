#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly RAW_TCP="$REPO_ROOT/psxrecomp/tools/raw_tcp.py"
readonly GAME_TOML="$PROJECT_ROOT/game.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly WATCHLIST_FILE="$PROJECT_ROOT/seeds/s1_261_remaining_gate_state_watchlist.txt"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-260-tele"
readonly CMAKE_CACHE="$BUILD_DIR/CMakeCache.txt"
readonly RUNTIME_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_RUNTIME_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly POLL_SECONDS=0.5
readonly STATE_SAMPLE_EVERY_TICKS=4
readonly PLAYER_FLAGS_ADDRESS=0x801D39E4
readonly P1_MASK=0x00010000
readonly P2_MASK=0x00020000
readonly GATE_WORD_ADDRESS=0x801F9600

PYTHON_BIN=
DEBUG_PORT=
SESSION_DIR=
ARMED=0
EVENT_NUMBER=0
POLL_TICK=0
declare -a WATCH_TARGETS=()
declare -a EVENT_TARGETS=()
declare -a STAGE_TARGETS=()
declare -a FUNCTION_TARGETS=()
declare -A TARGET_ROLES=()

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

usage() {
    cat <<'EOF'
Uso, no MSYS2 UCRT64, com a build S1-260 de telemetria aberta:

  bash tools/observe_s1_261_remaining_gate_state.sh

Use obrigatoriamente:

  buildClean-ucrt-s1-260-tele/StreetFighterEXPlusAlphaRecomp.exe

Fluxo:

  1. O script valida a build e fica pronto esperando Enter.
  2. Posicione o jogo no inicio da rota e pressione Enter.
  3. Percorra o jogo normalmente.
  4. O observador conta silenciosamente a raiz e os testes P1/P2.
  5. Ele congela quando P1/P2 alcanca o teste final do gate ou quando uma das
     cinco funcoes restantes executa.
  6. Informe uma tag curta descrevendo a tela/estado atual.
  7. Mude de contexto e pressione Enter para rearmar, ou digite q.
  8. Ctrl+C salva o snapshot e o resumo mesmo sem evento.

Os contadores de PC sao acumulativos e nao perdem eventos entre polls. Os
valores 0x801D39E4 e 0x801F9603 tambem sao amostrados a cada dois segundos,
mas as decisoes usam os PCs acumulativos para nao depender dessa amostragem.
O script nao gera fontes, nao compila e nao altera seeds principais.
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
        [[ "$role" == context || "$role" == stage || "$role" == trigger ]] ||
            fail "Papel invalido: $role"
        [[ "$target" =~ ^0[xX][0-9A-Fa-f]{8}$ ]] || fail "Endereco invalido: $target"
        normalized="0x$(printf '%s' "${target:2}" | tr '[:lower:]' '[:upper:]')"
        [[ -z "${TARGET_ROLES[$normalized]+x}" ]] || fail "Endereco duplicado: $normalized"
        WATCH_TARGETS+=("$normalized")
        TARGET_ROLES["$normalized"]="$role"
        if [[ "$role" == stage ]]; then
            STAGE_TARGETS+=("$normalized")
            EVENT_TARGETS+=("$normalized")
        elif [[ "$role" == trigger ]]; then
            FUNCTION_TARGETS+=("$normalized")
            EVENT_TARGETS+=("$normalized")
        fi
    done <"$WATCHLIST_FILE"

    local expected_all expected_events
    expected_all="0x80103384 0x80103508 0x80103534 0x80103678 0x801036A4 0x8016EA0C 0x8016EA60 0x8016EAE8 0x8016F560 0x8016FB64"
    expected_events="0x80103534 0x801036A4 0x8016EA0C 0x8016EA60 0x8016EAE8 0x8016F560 0x8016FB64"
    [[ "${WATCH_TARGETS[*]}" == "$expected_all" ]] ||
        fail "A watchlist de estado diverge dos dez PCs auditados."
    [[ "${EVENT_TARGETS[*]}" == "$expected_events" ]] ||
        fail "Os eventos da watchlist de estado estao divergentes."
}

tcp_capture() { "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@"; }
require_ok_text() { grep -q '"ok":true' <<<"$1" || fail "Resposta TCP invalida para $2."; }

validate_live_control_flow() {
    local p1 p2
    p1="$(tcp_capture mem_words addr=0x80103508 count=19)"
    p2="$(tcp_capture mem_words addr=0x80103678 count=19)"
    require_ok_text "$p1" "corpo vivo P1"
    require_ok_text "$p2" "corpo vivo P2"
    printf '%s\n%s\n' "$p1" "$p2" | "$PYTHON_BIN" -c '
import json,re,sys
text=sys.stdin.read()
parts=re.findall(r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===",text,re.S)
if len(parts)!=2: raise SystemExit(2)
rows=[json.loads(part).get("words",[]) for part in parts]
expected=[("0x00621024","0x3C02801F","0x0C05BA83"),
          ("0x00621024","0x3C02801F","0x0C05BA83")]
for words,want in zip(rows,expected):
    if len(words)!=19 or tuple(x.upper() for x in (words[0],words[11],words[18])) != tuple(x.upper() for x in want):
        raise SystemExit(3)
' || fail "Corpo vivo da raiz nao preserva os dois caminhos auditados."
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum nm awk grep sed tr sleep seq; do
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
    grep -qxF 'CMAKE_BUILD_TYPE:STRING=RelWithDebInfo' "$CMAKE_CACHE" ||
        fail "Build nao esta RelWithDebInfo."
    grep -qxF 'PSX_DEBUG_TOOLS:BOOL=ON' "$CMAKE_CACHE" || fail "PSX_DEBUG_TOOLS nao esta ativo."
    grep -qxF 'PSX_STATIC_RUNTIME:BOOL=ON' "$CMAKE_CACHE" || fail "Runtime estatico nao esta ativo."
    nm -C "$RUNTIME_EXE" | grep -Eq '[[:space:]]T[[:space:]]+func_80103BD8$' ||
        fail "O executavel nao contem a funcao S1-260 promovida."
    select_python
    read_debug_port
    load_watchlist

    local target address
    for target in 0x80103384 "${FUNCTION_TARGETS[@]}"; do
        address="${target#0x}"
        ! grep -q "^F ${address}$" "$RANGES_FILE" || fail "$target ja esta nativa."
        ! nm -C "$RUNTIME_EXE" | grep -Eq "[[:space:]]T[[:space:]]+func_${address}$" ||
            fail "$target apareceu como simbolo nativo no executavel."
    done
    validate_live_control_flow
}

extract_single_word() {
    sed -nE 's/.*"words":\["(0x[0-9A-Fa-f]{8})"\].*/\1/p' | sed -n '1p'
}

sample_state() {
    local flags_response gate_response flags_word gate_word flags_hex gate_hex flags_value gate_value
    local p1_enabled p2_enabled gate_byte
    flags_response="$(tcp_capture mem_words addr="$PLAYER_FLAGS_ADDRESS" count=1 2>/dev/null)" || return 1
    gate_response="$(tcp_capture mem_words addr="$GATE_WORD_ADDRESS" count=1 2>/dev/null)" || return 1
    grep -q '"ok":true' <<<"$flags_response" || return 1
    grep -q '"ok":true' <<<"$gate_response" || return 1
    flags_word="$(printf '%s\n' "$flags_response" | extract_single_word)"
    gate_word="$(printf '%s\n' "$gate_response" | extract_single_word)"
    [[ "$flags_word" =~ ^0x[0-9A-Fa-f]{8}$ && "$gate_word" =~ ^0x[0-9A-Fa-f]{8}$ ]] || return 1
    flags_hex="${flags_word#0x}"; gate_hex="${gate_word#0x}"
    flags_value=$((16#$flags_hex)); gate_value=$((16#$gate_hex))
    p1_enabled=$(((flags_value & P1_MASK) != 0 ? 1 : 0))
    p2_enabled=$(((flags_value & P2_MASK) != 0 ? 1 : 0))
    gate_byte=$(((gate_value >> 24) & 255))
    printf '%s,%s,%d,%d,%s,%d\n' "$(date +%s)" "$flags_word" "$p1_enabled" "$p2_enabled" \
        "$gate_word" "$gate_byte" >>"$SESSION_DIR/state_samples.csv"
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
    POLL_TICK=0
    sample_state || true
}

dump_has_event() {
    "$PYTHON_BIN" -c '
import json,re,sys
events=set(sys.argv[1:]); text=sys.stdin.read()
m=re.search(r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===",text,re.S)
if not m: raise SystemExit(2)
data=json.loads(m.group(1))
raise SystemExit(0 if any(e.get("target") in events and int(e.get("hits",0) or 0)>0
                          for e in data.get("entries",[])) else 1)
' "${EVENT_TARGETS[@]}" 2>/dev/null
}

print_hits() {
    "$PYTHON_BIN" -c '
import json,re,sys
stages=set(sys.argv[1].split()); triggers=set(sys.argv[2].split()); text=sys.stdin.read()
m=re.search(r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===",text,re.S)
if not m: raise SystemExit("payload pc_watch ausente")
for e in json.loads(m.group(1)).get("entries",[]):
    hits=int(e.get("hits",0) or 0)
    if not hits: continue
    target=e.get("target")
    role="ESTAGIO" if target in stages else ("FUNCAO" if target in triggers else "contexto")
    print("  {} [{}]: hits={}; nativos={}; interpretados={}; frames={}..{}".format(
          target,role,hits,e.get("native_hits",0),e.get("interpreted_hits",0),
          e.get("first_frame",0),e.get("last_frame",0)))
' "${STAGE_TARGETS[*]}" "${FUNCTION_TARGETS[*]}"
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
        read -r -p 'Digite a tag da tela/estado atual: ' raw_tag
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
        candidate="$PROJECT_ROOT/local/telemetry/s1-261-remaining-state-discovery-$n"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; SESSION_DIR="$candidate"; return; fi
    done
    fail "Nao ha identificador livre para uma nova sessao."
}

write_session_metadata() {
    {
        printf 'checkpoint=S1-261\n'
        printf 'runtime_build=buildClean-ucrt-s1-260-tele\n'
        printf 'purpose=locate player-state condition for remaining 604-word branch\n'
        printf 'remaining_total_words=936\nbranch_words=604\nfinal_root_words=332\n'
        printf 'poll_seconds=%s\nstate_sample_seconds=2\n' "$POLL_SECONDS"
        printf 'player_flags_address=%s\np1_mask=%s\np2_mask=%s\n' \
            "$PLAYER_FLAGS_ADDRESS" "$P1_MASK" "$P2_MASK"
        printf 'gate_byte_address=0x801F9603\n'
        printf 'watchlist=%s\nevents=%s\n' "${WATCH_TARGETS[*]}" "${EVENT_TARGETS[*]}"
        printf 'ranges_sha256=%s\n' "$(sha256sum "$RANGES_FILE" | awk '{print $1}')"
        printf 'runtime_exe_sha256=%s\n' "$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')"
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
    printf 'epoch,word_0x801D39E4,p1_bit_0x00010000,p2_bit_0x00020000,word_0x801F9600,byte_0x801F9603\n' \
        >"$SESSION_DIR/state_samples.csv"
}

capture_diagnostics() {
    local destination="$1"
    tcp_capture dispatch_stats >"$destination/dispatch_stats.log"
    tcp_capture dirty_ram_stats >"$destination/dirty_ram_stats.log"
    tcp_capture mem_words addr="$PLAYER_FLAGS_ADDRESS" count=1 >"$destination/live_801D39E4_flags.log"
    tcp_capture mem_words addr="$GATE_WORD_ADDRESS" count=2 >"$destination/live_801F9600_gate.log"
    tcp_capture mem_words addr=0x80103384 count=256 >"$destination/live_80103384_part1.log"
    tcp_capture mem_words addr=0x80103784 count=76 >"$destination/live_80103384_part2.log"
    tcp_capture mem_words addr=0x8016EA0C count=21 >"$destination/live_8016EA0C.log"
    tcp_capture mem_words addr=0x8016EA60 count=34 >"$destination/live_8016EA60.log"
    tcp_capture mem_words addr=0x8016EAE8 count=256 >"$destination/live_8016EAE8_part1.log"
    tcp_capture mem_words addr=0x8016EEE8 count=178 >"$destination/live_8016EAE8_part2.log"
    tcp_capture mem_words addr=0x8016F560 count=66 >"$destination/live_8016F560.log"
    tcp_capture mem_words addr=0x8016FB64 count=49 >"$destination/live_8016FB64.log"
}

save_event() {
    local dump="$1" stop_response="$2" tag event_id event_dir
    printf '\a\nESTADO DO PROXIMO GATE ENCONTRADO — observacao congelada.\n'
    printf '%s' "$dump" | print_hits
    tag="$(read_event_tag)"
    EVENT_NUMBER=$((EVENT_NUMBER+1)); event_id="$(printf '%03d' "$EVENT_NUMBER")"
    event_dir="$SESSION_DIR/event-${event_id}-${tag}"; mkdir "$event_dir"
    printf '%s\n' "$dump" >"$event_dir/pc_watch_dump.log"
    printf '%s\n' "$stop_response" >"$event_dir/pc_watch_stop.log"
    capture_diagnostics "$event_dir"
    printf 'event=%s\ntag=%s\ncaptured_utc=%s\n' "$event_id" "$tag" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$event_dir/metadata.txt"
    "$PYTHON_BIN" - "$event_dir" "$WATCHLIST_FILE" <<'PY'
import json,pathlib,re,sys
event=pathlib.Path(sys.argv[1]); watchlist=pathlib.Path(sys.argv[2]); roles={}
for line in watchlist.read_text(encoding='utf-8').splitlines():
    row=line.split('#',1)[0].split()
    if len(row)==2: roles[row[1].lower()]=row[0]
text=(event/'pc_watch_dump.log').read_text(encoding='utf-8',errors='replace')
m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
data=json.loads(m.group(1)) if m else {}; meta={}
for line in (event/'metadata.txt').read_text(encoding='utf-8').splitlines():
    if '=' in line:
        key,value=line.split('=',1); meta[key]=value
lines=[f'# Evento {meta.get("event","?")} - {meta.get("tag","sem-tag")}', '',
       '| PC | Papel | Hits | Nativos | Interpretados | Primeiro frame | Ultimo frame |',
       '|---|---|---:|---:|---:|---:|---:|']
for entry in data.get('entries',[]):
    hits=int(entry.get('hits',0) or 0)
    if hits:
        target=entry.get('target','?')
        lines.append(f'| {target} | {roles.get(target.lower(),"?")} | {hits} | '
                     f'{entry.get("native_hits",0)} | {entry.get("interpreted_hits",0)} | '
                     f'{entry.get("first_frame",0)} | {entry.get("last_frame",0)} |')
lines += ['', '- `stage` indica que o bit por jogador habilitou o teste final do gate.',
          '- `trigger` e uma funcao formal ainda interpretada do ramo de 604 palavras.',
          '- A tag e o contexto informado pelo usuario, nao um caller MIPS automatico.', '']
(event/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
    note "Evento salvo em $event_dir"
}

write_final_summary() {
    local reason="$1"
    "$PYTHON_BIN" - "$SESSION_DIR" "$reason" "$WATCHLIST_FILE" <<'PY'
import csv,json,pathlib,re,sys
session=pathlib.Path(sys.argv[1]); reason=sys.argv[2]; watchlist=pathlib.Path(sys.argv[3]); roles={}
for line in watchlist.read_text(encoding='utf-8').splitlines():
    row=line.split('#',1)[0].split()
    if len(row)==2: roles[row[1].lower()]=row[0]
def payload(name):
    path=session/name
    if not path.exists(): return {}
    text=path.read_text(encoding='utf-8',errors='replace')
    match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not match: return {}
    try: return json.loads(match.group(1))
    except json.JSONDecodeError: return {}
watch=payload('final_pc_watch_dump.log'); entries=watch.get('entries',[])
by_target={entry.get('target','').lower():entry for entry in entries}
stage_hits=sum(int(e.get('hits',0) or 0) for e in entries if roles.get(e.get('target','').lower())=='stage')
function_hits=sum(int(e.get('hits',0) or 0) for e in entries if roles.get(e.get('target','').lower())=='trigger')
samples=[]; state_path=session/'state_samples.csv'
if state_path.exists():
    with state_path.open(encoding='utf-8',errors='replace',newline='') as stream:
        for row in csv.DictReader(stream):
            try: samples.append((int(row['p1_bit_0x00010000']),int(row['p2_bit_0x00020000']),int(row['byte_0x801F9603'])))
            except (KeyError,TypeError,ValueError): pass
p1_samples=sum(p1 for p1,_,_ in samples); p2_samples=sum(p2 for _,p2,_ in samples)
gate_nonzero=sum(gate!=0 for _,_,gate in samples)
root_hits=int(by_target.get('0x80103384',{}).get('hits',0) or 0)
p1_test_hits=int(by_target.get('0x80103508',{}).get('hits',0) or 0)
p2_test_hits=int(by_target.get('0x80103678',{}).get('hits',0) or 0)
if function_hits:
    conclusion='ramo restante executado; rota dinamica localizada'
elif stage_hits:
    conclusion='estado por jogador alcancado, mas nenhuma funcao formal do ramo foi observada'
elif p1_test_hits or p2_test_hits:
    conclusion='testes por jogador exercitados; bits 0x00010000/0x00020000 nunca habilitaram o estagio final'
elif root_hits:
    conclusion='raiz exercitada; condicoes anteriores impediram os dois testes por jogador'
else:
    conclusion='raiz sem hits; sessao insuficiente para avaliar o gate'
events=len([p for p in session.iterdir() if p.is_dir() and p.name.startswith('event-')])
lines=[f'# Resumo final - {session.name}','',f'- Encerramento: {reason}',
       f'- Eventos salvos: {events}',f'- Frame final: {watch.get("frame","n/d")}',
       f'- Hits da raiz 0x80103384: {root_hits}',f'- Hits do teste P1 0x80103508: {p1_test_hits}',
       f'- Hits do teste P2 0x80103678: {p2_test_hits}',f'- Hits dos dois estagios finais: {stage_hits}',
       f'- Hits das cinco funcoes restantes: {function_hits}',f'- Amostras de estado: {len(samples)}',
       f'- Amostras com bit P1 ativo: {p1_samples}',f'- Amostras com bit P2 ativo: {p2_samples}',
       f'- Amostras com gate 0x801F9603 diferente de zero: {gate_nonzero}',
       f'- Conclusao: {conclusion}','','| PC | Papel | Hits | Nativos | Interpretados | Primeiro frame | Ultimo frame |',
       '|---|---|---:|---:|---:|---:|---:|']
for entry in entries:
    target=entry.get('target','?')
    lines.append(f'| {target} | {roles.get(target.lower(),"?")} | {entry.get("hits",0)} | '
                 f'{entry.get("native_hits",0)} | {entry.get("interpreted_hits",0)} | '
                 f'{entry.get("first_frame",0)} | {entry.get("last_frame",0)} |')
lines += ['', '- Contadores de PC sao acumulativos; eventos entre polls nao sao perdidos.',
          '- Amostras de memoria complementam os PCs e podem nao capturar estados muito breves.', '']
(session/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

save_final_snapshot() {
    local reason="$1" response
    [[ -n "$SESSION_DIR" && -d "$SESSION_DIR" ]] || return
    sample_state || true
    if (( ARMED == 1 )); then
        response="$(tcp_capture pc_watch_stop 2>/dev/null)" || response='ERRO: pc_watch_stop falhou'
        printf '%s\n' "$response" >"$SESSION_DIR/final_pc_watch_stop.log"
        ARMED=0
    fi
    tcp_capture pc_watch_dump >"$SESSION_DIR/final_pc_watch_dump.log" 2>&1 || true
    tcp_capture mem_words addr="$PLAYER_FLAGS_ADDRESS" count=1 >"$SESSION_DIR/final_player_flags.log" 2>&1 || true
    tcp_capture mem_words addr="$GATE_WORD_ADDRESS" count=2 >"$SESSION_DIR/final_gate_words.log" 2>&1 || true
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
    local dump stop_response choice result
    while true; do
        dump="$(tcp_capture pc_watch_dump 2>/dev/null)" || fail "Falha na consulta pc_watch_dump."
        require_ok_text "$dump" pc_watch_dump
        POLL_TICK=$((POLL_TICK+1))
        if (( POLL_TICK % STATE_SAMPLE_EVERY_TICKS == 0 )); then sample_state || true; fi
        if printf '%s' "$dump" | dump_has_event; then
            sample_state || true
            stop_response="$(tcp_capture pc_watch_stop)"; require_ok_text "$stop_response" pc_watch_stop
            ARMED=0
            dump="$(tcp_capture pc_watch_dump)"; require_ok_text "$dump" pc_watch_dump-final
            save_event "$dump" "$stop_response"
            printf '\nMude para a proxima tela/estado antes de rearmar.\n'
            read -r -p 'Pressione Enter para rearmar ou digite q para encerrar: ' choice
            [[ "${choice,,}" == q ]] && return
            arm_watchlist
            note "MONITORANDO novamente; percorra o jogo normalmente"
        else
            result=$?
            (( result == 1 )) || fail "Nao foi possivel interpretar pc_watch_dump."
        fi
        sleep "$POLL_SECONDS"
    done
}

main() {
    local choice
    case "${1:-}" in -h|--help) usage; return ;; '') ;; *) usage; fail "Este script nao recebe argumentos." ;; esac
    validate
    trap cleanup EXIT
    trap interrupt_handler INT
    make_session_dir
    write_session_metadata
    printf '\nObservador de estado do ramo restante preparado sobre S1-260-tele.\n'
    printf 'Posicione o jogo no inicio da rota desejada.\n'
    read -r -p 'Pressione Enter para iniciar ou digite q para sair: ' choice
    if [[ "${choice,,}" == q ]]; then note "Sessao encerrada sem armar: $SESSION_DIR"; return; fi
    arm_watchlist
    note "MONITORANDO os testes por jogador e o ramo restante"
    printf 'Bits: P1=%s; P2=%s em %s\n' "$P1_MASK" "$P2_MASK" "$PLAYER_FLAGS_ADDRESS"
    printf 'Estagios que pedem tag: %s\n' "${STAGE_TARGETS[*]}"
    printf 'Funcoes que pedem tag: %s\n' "${FUNCTION_TARGETS[*]}"
    printf 'Use Ctrl+C para encerrar e salvar o resumo.\n'
    monitor_loop
    save_final_snapshot normal
    note "Sessao encerrada: $SESSION_DIR"
    printf 'Resumo final: %s/summary.md\n' "$SESSION_DIR"
}

main "$@"
