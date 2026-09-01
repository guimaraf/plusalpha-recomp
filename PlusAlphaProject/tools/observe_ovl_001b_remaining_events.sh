#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly RAW_TCP="$REPO_ROOT/psxrecomp/tools/raw_tcp.py"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_001b_test.toml"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-001b-current-runtime.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_A_KEY=0x00020000:0xAC1FF1A4
readonly EXPECTED_B_KEY=0x00020000:0x94E6122F
readonly EXPECTED_CRC_8004590C=0x70559BA1
readonly EXPECTED_CRC_8004596C=0x63EB4F67
readonly POLL_SECONDS=0.5

readonly -a WATCH_TARGETS=(
    0x8004590C
    0x8004596C
)

PYTHON_BIN=
DEBUG_PORT=
RUNTIME_DIR=
RUNTIME_EXE=
CACHE_MANIFEST=
SESSION_DIR=
ARMED=0
EVENT_NUMBER=0

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com a variante OVL-001B-safe aberta:

  bash tools/observe_ovl_001b_remaining_events.sh

Fluxo:
  1. Posicione o jogo antes da primeira tela que deseja testar.
  2. Pressione Enter para iniciar o observador.
  3. Percorra telas, modos e gameplay normalmente.
  4. Quando 0x8004590C ou 0x8004596C executar, a coleta sera congelada.
  5. O CRC vivo sera classificado como B-safe exato ou variante estrangeira.
  6. Digite uma tag descrevendo personagem, golpe e contexto atual.
  7. Mude de contexto e pressione Enter para rearmar, ou digite q.

Ctrl+C encerra preservando o snapshot final. O observador nao gera fontes,
nao compila e nao modifica o cache do overlay.
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
    else fail "Python nao encontrado no UCRT64."
    fi
}

read_runtime_state() {
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-001B ausente."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"
    RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-001b-test-runtime-*) ;; *) fail "Runtime OVL-001B invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" capture_a_key)" == "$EXPECTED_A_KEY" ]] || fail "Chave OVL-001A divergente."
    [[ "$(state_value "$RUNTIME_STATE" capture_b_key)" == "$EXPECTED_B_KEY" ]] || fail "Chave OVL-001B divergente."
    [[ -d "$RUNTIME_DIR" && -f "$RUNTIME_EXE" && -f "$CACHE_MANIFEST" ]] || fail "Runtime OVL-001B incompleto."
}

read_debug_port() {
    DEBUG_PORT="$(awk '
        /^[[:space:]]*\[runtime\][[:space:]]*$/ {ok=1; next}
        /^[[:space:]]*\[/ {ok=0}
        ok && /^[[:space:]]*debug_port[[:space:]]*=/ {
            sub(/^[^=]*=/,""); gsub(/[[:space:]]+/,""); print; exit
        }
    ' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida."
}

verify_cache() {
    "$PYTHON_BIN" - "$RUNTIME_DIR" "$CACHE_MANIFEST" "${WATCH_TARGETS[@]}" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); manifest=pathlib.Path(sys.argv[2]); targets={int(x,16)&0x1fffffff for x in sys.argv[3:]}
data=json.loads(manifest.read_text(encoding='utf-8'))
if data.get('track')!='OVL-001B-SAFE-CUMULATIVE': raise SystemExit('manifesto nao pertence a OVL-001B-safe')
expected={row['path']:(str(row['sha256']).upper(),int(row['size'])) for row in data.get('files',[])}
if not expected: raise SystemExit('manifesto sem inventario de cache')
for rel,(digest,size) in expected.items():
    path=root/pathlib.Path(*pathlib.PurePosixPath(rel).parts)
    if not path.is_file() or path.stat().st_size!=size or hashlib.sha256(path.read_bytes()).hexdigest().upper()!=digest:
        raise SystemExit(f'cache divergente: {rel}')
entries=set()
for path in (root/'cache').rglob('*.ranges'):
    for line in path.read_text(encoding='utf-8',errors='replace').splitlines():
        fields=line.split()
        if fields and fields[0]=='F': entries.add(int(fields[1],16)&0x1fffffff)
missing=targets-entries
if missing: raise SystemExit('alvos ausentes do cache: '+', '.join(f'0x{x:08X}' for x in sorted(missing)))
PY
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk grep sed tr sleep seq mv; do command -v "$tool" >/dev/null || fail "$tool nao encontrado."; done
    [[ -f "$RAW_TCP" && -f "$TEST_CONFIG" ]] || fail "Ferramentas ou game_ovl_001b_test.toml ausentes."
    select_python; read_runtime_state; read_debug_port
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel OVL-001B divergente."
    verify_cache
}

tcp_capture() { "$PYTHON_BIN" "$RAW_TCP" "$DEBUG_PORT" "$@"; }
require_ok() { grep -q '"ok":true' <<<"$1" || fail "Resposta TCP invalida: $2"; }

arm_watch() {
    local response target
    response="$(tcp_capture pc_watch_clear)"; require_ok "$response" pc_watch_clear
    for target in "${WATCH_TARGETS[@]}"; do
        response="$(tcp_capture pc_watch_arm target="$target")"; require_ok "$response" "pc_watch_arm $target"
    done
    response="$(tcp_capture pc_watch_reset)"; require_ok "$response" pc_watch_reset
    ARMED=1
}

dump_has_hits() {
    "$PYTHON_BIN" -c '
import json,re,sys
text=sys.stdin.read(); m=re.search(r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===",text,re.S)
if not m: raise SystemExit(2)
data=json.loads(m.group(1))
raise SystemExit(0 if any(int(e.get("hits",0) or 0)>0 for e in data.get("entries",[])) else 1)
' 2>/dev/null
}

print_hits() {
    "$PYTHON_BIN" -c '
import json,re,sys
text=sys.stdin.read(); m=re.search(r"=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===",text,re.S)
if not m: raise SystemExit("JSON pc_watch ausente")
for e in json.loads(m.group(1)).get("entries",[]):
    if int(e.get("hits",0) or 0)>0:
        target=e.get("target"); hits=e.get("hits",0); native=e.get("native_hits",0)
        interpreted=e.get("interpreted_hits",0); first=e.get("first_frame",0); last=e.get("last_frame",0)
        print(f"  {target}: hits={hits}; nativos={native}; interpretados={interpreted}; frames={first}..{last}")
'
}

sanitize_tag() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+|-+$//g'
}

read_tag() {
    local raw_tag tag
    while true; do
        read -r -p 'Digite a tag da tela/transicao/acao atual: ' raw_tag
        if [[ -z "$raw_tag" || ${#raw_tag} -gt 48 || "$raw_tag" =~ [[:cntrl:]] ]]; then
            printf 'Tag invalida. Use de 1 a 48 caracteres.\n' >&2; continue
        fi
        tag="$(sanitize_tag "$raw_tag")"
        [[ -n "$tag" && ${#tag} -le 48 ]] || { printf 'Tag invalida depois da normalizacao.\n' >&2; continue; }
        printf '%s' "$tag"; return
    done
}

make_session_dir() {
    local n candidate
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    for n in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-001b-interior-route-discovery-$n"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; SESSION_DIR="$candidate"; return; fi
    done
    fail "Nao ha identificador livre para o observador OVL-001B."
}

write_metadata() {
    {
        printf 'track=OVL-001B-SAFE-INTERIOR-ROUTE-DISCOVERY\n'
        printf 'runtime_dir=%s\n' "$RUNTIME_DIR"
        printf 'targets=%s\n' "${WATCH_TARGETS[*]}"
        printf 'expected_crc_8004590C=%s\n' "$EXPECTED_CRC_8004590C"
        printf 'expected_crc_8004596C=%s\n' "$EXPECTED_CRC_8004596C"
        printf 'poll_seconds=%s\n' "$POLL_SECONDS"
        printf 'runtime_exe_sha256=%s\n' "$(sha256sum "$RUNTIME_EXE" | awk '{print $1}')"
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
}

classify_event() {
    "$PYTHON_BIN" - "$1" <<'PY'
import json,pathlib,re,struct,sys,zlib
event=pathlib.Path(sys.argv[1])
expected={'0x8004590C':(66,0x70559BA1),'0x8004596C':(42,0x63EB4F67)}
def raw(path):
    text=path.read_text(encoding='utf-8',errors='replace')
    match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    if not match: raise SystemExit(f'JSON bruto ausente: {path.name}')
    return json.loads(match.group(1))
watch={entry.get('target'):entry for entry in raw(event/'pc_watch_dump.log').get('entries',[])}
print('Classificacao do corpo vivo:')
for pc,(count,wanted) in expected.items():
    words=raw(event/f'live_{pc[2:]}.log').get('words',[])[:count]
    blob=b''.join(struct.pack('<I',int(word,16)) for word in words)
    live=zlib.crc32(blob)&0xffffffff if len(words)==count else None
    status='B-SAFE EXATO' if live==wanted else 'VARIANTE ESTRANGEIRA'
    entry=watch.get(pc,{})
    shown=f'0x{live:08X}' if live is not None else 'INVALIDO'
    print(f'  {pc}: CRC vivo={shown}; esperado=0x{wanted:08X}; {status}; '
          f'nativos={entry.get("native_hits",0)}; interpretados={entry.get("interpreted_hits",0)}')
PY
}

save_event() {
    local dump="$1" stop="$2" tag event_id event_dir staging_dir target suffix
    EVENT_NUMBER=$((EVENT_NUMBER+1)); event_id="$(printf '%03d' "$EVENT_NUMBER")"
    staging_dir="$SESSION_DIR/.event-${event_id}-pending"; mkdir "$staging_dir"
    printf '%s\n' "$dump" >"$staging_dir/pc_watch_dump.log"
    printf '%s\n' "$stop" >"$staging_dir/pc_watch_stop.log"
    for target in "${WATCH_TARGETS[@]}"; do
        suffix="${target#0x}"
        tcp_capture overlay_candidates pc="$target" >"$staging_dir/overlay_candidates_${suffix}.log"
    done
    tcp_capture overlay_loader_status >"$staging_dir/overlay_loader_status.log"
    tcp_capture dispatch_stats >"$staging_dir/dispatch_stats.log"
    tcp_capture dirty_ram_stats >"$staging_dir/dirty_ram_stats.log"
    tcp_capture mem_words addr=0x8004590C count=66 >"$staging_dir/live_8004590C.log"
    tcp_capture mem_words addr=0x8004596C count=42 >"$staging_dir/live_8004596C.log"
    printf '\a\nPC REUTILIZADO ENCONTRADO — observacao congelada.\n'
    printf '%s' "$dump" | print_hits
    classify_event "$staging_dir"
    tag="$(read_tag)"; event_dir="$SESSION_DIR/event-${event_id}-${tag}"
    mv "$staging_dir" "$event_dir"
    printf 'event=%s\ntag=%s\ncaptured_utc=%s\n' "$event_id" "$tag" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$event_dir/metadata.txt"
    "$PYTHON_BIN" - "$event_dir" <<'PY'
import json,pathlib,re,struct,sys,zlib
event=pathlib.Path(sys.argv[1]); text=(event/'pc_watch_dump.log').read_text(encoding='utf-8',errors='replace')
m=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
data=json.loads(m.group(1)) if m else {}; meta={}
expected={'0x8004590C':(66,0x70559BA1),'0x8004596C':(42,0x63EB4F67)}
def raw(path):
    text=path.read_text(encoding='utf-8',errors='replace')
    match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    return json.loads(match.group(1)) if match else {}
def live_crc(pc,count):
    words=raw(event/f'live_{pc[2:]}.log').get('words',[])[:count]
    if len(words)!=count: return None
    return zlib.crc32(b''.join(struct.pack('<I',int(word,16)) for word in words))&0xffffffff
for line in (event/'metadata.txt').read_text(encoding='utf-8').splitlines():
    if '=' in line: key,value=line.split('=',1); meta[key]=value
lines=[f'# Evento {meta.get("event","?")} - {meta.get("tag","sem-tag")}', '',
       '| PC | Hits | Nativos | Interpretados | CRC vivo | Classificacao |',
       '|---|---:|---:|---:|---:|---|']
for entry in data.get('entries',[]):
    pc=entry.get('target'); count,wanted=expected[pc]; crc=live_crc(pc,count)
    shown=f'`0x{crc:08X}`' if crc is not None else 'invalido'; classification='B-safe exato' if crc==wanted else 'variante estrangeira'
    lines.append(f'| `{pc}` | {entry.get("hits",0)} | {entry.get("native_hits",0)} | '
                 f'{entry.get("interpreted_hits",0)} | {shown} | {classification} |')
lines += ['', '- A tag identifica o contexto informado pelo usuario.', '- Nenhum build foi executado pelo observador.', '']
(event/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
    note "Evento salvo em $event_dir"
}

write_final_summary() {
    local reason="$1"
    "$PYTHON_BIN" - "$SESSION_DIR" "$reason" <<'PY'
import json,pathlib,re,struct,sys,zlib
session=pathlib.Path(sys.argv[1]); reason=sys.argv[2]
expected={'0x8004590C':(66,0x70559BA1),'0x8004596C':(42,0x63EB4F67)}
def raw(path):
    if not path.is_file(): return {}
    text=path.read_text(encoding='utf-8',errors='replace')
    match=re.search(r'=== raw bytes \(len=\d+\) ===\r?\n(.*?)\r?\n=== json parse attempt ===',text,re.S)
    return json.loads(match.group(1)) if match else {}
def metadata(path):
    result={}
    if path.is_file():
        for line in path.read_text(encoding='utf-8',errors='replace').splitlines():
            if '=' in line: key,value=line.split('=',1); result[key]=value
    return result
def live_crc(event,pc,count):
    words=raw(event/f'live_{pc[2:]}.log').get('words',[])[:count]
    if len(words)!=count: return None
    return zlib.crc32(b''.join(struct.pack('<I',int(word,16)) for word in words))&0xffffffff
events=sorted(path for path in session.iterdir() if path.is_dir() and path.name.startswith('event-'))
lines=[f'# Descoberta de rotas OVL-001B - {session.name}','',f'- Encerramento: {reason}',
       f'- Eventos registrados: {len(events)}','- Alvos: `0x8004590C`, `0x8004596C`','',
       '| Evento | Tag | PC | Nativos/interp. | CRC vivo | Classificacao |','|---:|---|---|---:|---:|---|']
for event in events:
    meta=metadata(event/'metadata.txt'); entries={e.get('target'):e for e in raw(event/'pc_watch_dump.log').get('entries',[])}
    for pc,(count,wanted) in expected.items():
        entry=entries.get(pc,{}); crc=live_crc(event,pc,count); shown=f'`0x{crc:08X}`' if crc is not None else 'invalido'
        classification='B-safe exato' if crc==wanted else 'variante estrangeira'
        lines.append(f'| {meta.get("event","?")} | {meta.get("tag","?")} | `{pc}` | '
                     f'{entry.get("native_hits",0)}/{entry.get("interpreted_hits",0)} | {shown} | {classification} |')
final={e.get('target'):e for e in raw(session/'final_pc_watch_dump.log').get('entries',[])}
lines += ['','## Snapshot final','',
          f'- 0x8004590C: {final.get("0x8004590C",{}).get("hits",0)} hits.',
          f'- 0x8004596C: {final.get("0x8004596C",{}).get("hits",0)} hits.','',
          'Os contadores de cada evento sao congelados antes da leitura; a tag e o contexto informado pelo usuario.','']
(session/'summary.md').write_text('\n'.join(lines),encoding='utf-8')
PY
}

save_final_snapshot() {
    local reason="$1" response
    [[ -n "$SESSION_DIR" && -d "$SESSION_DIR" ]] || return
    if (( ARMED == 1 )); then
        response="$(tcp_capture pc_watch_stop 2>/dev/null)" || response='ERRO: pc_watch_stop falhou'
        printf '%s\n' "$response" >"$SESSION_DIR/final_pc_watch_stop.log"; ARMED=0
    fi
    tcp_capture pc_watch_dump >"$SESSION_DIR/final_pc_watch_dump.log" 2>&1 || true
    tcp_capture overlay_loader_status >"$SESSION_DIR/final_overlay_loader_status.log" 2>&1 || true
    tcp_capture dirty_ram_stats >"$SESSION_DIR/final_dirty_ram_stats.log" 2>&1 || true
    printf 'ended_reason=%s\nended_utc=%s\nevents=%s\n' "$reason" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$EVENT_NUMBER" >"$SESSION_DIR/final.txt"
    write_final_summary "$reason" || true
}

interrupt_handler() {
    trap - INT
    printf '\n\nCtrl+C recebido; salvando snapshot final...\n'
    save_final_snapshot ctrl-c
    printf 'Sessao preservada em: %s\n' "$SESSION_DIR"
    exit 130
}

monitor_loop() {
    local dump stop choice
    while true; do
        dump="$(tcp_capture pc_watch_dump 2>/dev/null)" || fail "Falha na consulta pc_watch_dump."
        require_ok "$dump" pc_watch_dump
        if printf '%s' "$dump" | dump_has_hits; then
            stop="$(tcp_capture pc_watch_stop)"; require_ok "$stop" pc_watch_stop; ARMED=0
            dump="$(tcp_capture pc_watch_dump)"; require_ok "$dump" pc_watch_dump-final
            save_event "$dump" "$stop"
            printf '\nMude para o proximo contexto antes de rearmar.\n'
            read -r -p 'Pressione Enter para rearmar ou digite q para encerrar: ' choice
            [[ "${choice,,}" == q ]] && return
            arm_watch; note "MONITORANDO novamente"
        else
            case $? in 1) ;; *) fail "Nao foi possivel interpretar pc_watch_dump." ;; esac
        fi
        sleep "$POLL_SECONDS"
    done
}

main() {
    local choice
    case "${1:-}" in -h|--help) usage; return ;; '') ;; *) usage; fail "Este script nao recebe argumentos." ;; esac
    validate; trap cleanup EXIT; trap interrupt_handler INT; make_session_dir; write_metadata
    printf '\nObservador OVL-001B preparado para 0x8004590C e 0x8004596C.\n'
    printf 'Posicione o jogo antes do primeiro contexto que deseja testar.\n'
    read -r -p 'Pressione Enter para iniciar ou digite q para sair: ' choice
    if [[ "${choice,,}" == q ]]; then note "Sessao encerrada sem armar: $SESSION_DIR"; return; fi
    arm_watch
    note "MONITORANDO os dois fragmentos internos; percorra o jogo normalmente"
    printf 'Use Ctrl+C para encerrar ou q depois de um evento.\n'
    monitor_loop
    save_final_snapshot normal
    note "Sessao encerrada: $SESSION_DIR"
}

main "$@"
