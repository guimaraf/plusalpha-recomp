#!/usr/bin/env bash
# Janela isolada de 30 s para medir interpretacao restante apos OVL-002C.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002c_test.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002c-current-runtime.state"
readonly EXPECTED_EXE_SHA=5E2EF0F5451D7455BD72D5710FA24C415C83FDBE3F60D6F1229D52928BDA058E
readonly EXPECTED_RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F

PYTHON_BIN=
DEBUG_PORT=
RUNTIME_DIR=
RUNTIME_EXE=
CACHE_MANIFEST=
SESSION_DIR=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in sha256sum awk seq; do command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado."; done
    select_python
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-002C ausente. Execute compile_ovl_002c_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"; RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002c-test-runtime-*) ;; *) fail "Runtime OVL-002C invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" target)" == 0x80049568 && "$(state_value "$RUNTIME_STATE" image_body_words)" == 2074 ]] || fail "Estado OVL-002C divergente."
    for file in "$TEST_CONFIG" "$RANGES_FILE" "$RUNTIME_EXE" "$CACHE_MANIFEST"; do [[ -f "$file" ]] || fail "Arquivo ausente: $file"; done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel divergiu."
    [[ "$(sha256sum "$RANGES_FILE" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    DEBUG_PORT="$(awk '/^[[:space:]]*\[runtime\]/{ok=1;next} /^[[:space:]]*\[/{ok=0} ok&&/^[[:space:]]*debug_port[[:space:]]*=/{sub(/^[^=]*=/,"");gsub(/[[:space:]]+/,"");print;exit}' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] || fail "debug_port invalida."
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    local suffix candidate
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-002c-ddark-bombs-discovery-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; SESSION_DIR="$candidate"; return; fi
    done
    fail "Nao ha pasta livre para a coleta."
}

observe() {
    "$PYTHON_BIN" - "$DEBUG_PORT" "$SESSION_DIR" "$RANGES_FILE" "$RUNTIME_DIR" "$CACHE_MANIFEST" <<'PY'
import csv,hashlib,json,pathlib,re,socket,struct,sys,time,zlib
port=int(sys.argv[1]); session=pathlib.Path(sys.argv[2]); ranges_path=pathlib.Path(sys.argv[3])
runtime=pathlib.Path(sys.argv[4]); manifest_path=pathlib.Path(sys.argv[5])

def request(command,**arguments):
    wire=json.dumps({'id':1,'cmd':command,**arguments},separators=(',',':'))+'\n'; chunks=[]
    with socket.create_connection(('127.0.0.1',port),timeout=5.0) as sock:
        sock.settimeout(30.0); sock.sendall(wire.encode())
        while True:
            chunk=sock.recv(65536)
            if not chunk: break
            chunks.append(chunk)
    if not chunks: raise RuntimeError(f'{command}: resposta vazia')
    result=json.loads(b''.join(chunks).decode())
    if not result.get('ok'): raise RuntimeError(f'{command} rejeitado: {result}')
    return result

def paged(command,count_key,**arguments):
    offset=0; rows={}; header={}
    while True:
        page=request(command,offset=offset,limit=256,**arguments)
        if not header: header={k:v for k,v in page.items() if k!='entries'}
        for row in page.get('entries',[]):
            if row.get('pc'): rows[f'0x{int(str(row["pc"]),16):08X}']=row
        returned=int(page.get('returned',0) or 0); total=int(page.get(count_key,0) or 0); offset+=returned
        if returned==0 or offset>=total: break
        if offset>65536: raise RuntimeError(f'{command}: paginacao excedida')
    header['entries']=list(rows.values()); return header

def index(snapshot): return {f'0x{int(str(x["pc"]),16):08X}':x for x in snapshot.get('entries',[]) if x.get('pc')}
def delta(a,b,key): return max(0,int(b.get(key,0) or 0)-int(a.get(key,0) or 0))

manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
if manifest.get('track')!='OVL-002C-DDARK-BOMBS-CUMULATIVE' or int(manifest.get('image_body_words',0))!=2074:
    raise RuntimeError('manifesto conectado nao e OVL-002C')
for item in manifest.get('files',[]):
    path=runtime/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']) or hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']:
        raise RuntimeError(f'cache alterado: {item["path"]}')

probe=request('overlay_loader_status')
if not int(probe.get('active',0) or 0): raise RuntimeError('overlay cache inativo')
expected_cache=(runtime/'cache').resolve(); actual=pathlib.Path(str(probe.get('cache_dir',''))).resolve()
live={0x80049568:0x9611F1A0,0x80049808:0xCB050F22,0x80049988:0x6D2C8CD6,0x80092C2C:0x1B64D20F,0x80093E4C:0x12FF550F}
identity={'expected_cache_dir':str(expected_cache),'actual_cache_dir':str(actual),'cache_path_match':actual==expected_cache,'pcs':{}}
errors=[]
for pc,wanted in live.items():
    words=request('mem_words',addr=f'0x{pc:08X}',count=32).get('words',[])
    crc=zlib.crc32(b''.join(struct.pack('<I',int(x,16)) for x in words))&0xffffffff if len(words)==32 else -1
    candidates=request('overlay_candidates',pc=f'0x{pc:08X}').get('candidates',[])
    exact=any(int(x.get('match',0))==1 and int(x.get('state',9))==0 and int(x.get('dll',-1))>=0 and int(x.get('device_touch',1))==0 for x in candidates)
    identity['pcs'][f'0x{pc:08X}']={'crc32':f'0x{crc&0xffffffff:08X}','expected':f'0x{wanted:08X}','candidate_exact_active':exact}
    if crc!=wanted or not exact: errors.append(f'0x{pc:08X}: identidade viva divergente')
identity['errors']=errors; (session/'runtime-identity.json').write_text(json.dumps(identity,indent=2,sort_keys=True)+'\n')
if errors: raise RuntimeError('; '.join(errors))

print('\nRuntime OVL-002C confirmado. Prepare D.Dark P1 x Ryu P2; Ryu parado.',flush=True)
for remaining in range(5,0,-1): print(f'Prepare-se: {remaining}...',flush=True); time.sleep(1)
print('Mantenha ambos parados enquanto a baseline e lida...',flush=True)
before_static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
before_dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
before_diag={x:request(x) for x in ('overlay_loader_status','dirty_ram_stats','dispatch_stats')}
print('\a[CAPTURANDO] Por 30 s, repita somente bombas dos dois lados sem acertar Ryu.',flush=True)
started=time.monotonic(); time.sleep(30.0); elapsed=time.monotonic()-started
after_dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
after_static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
after_diag={x:request(x) for x in ('overlay_loader_status','dirty_ram_stats','dispatch_stats')}
print('\a\a[FIM DA CAPTURA] Pare as acoes.',flush=True)
bs,bd,ns,nd=map(index,(before_static,before_dynamic,after_static,after_dynamic)); rows=[]
native_ranges=[]
for line in ranges_path.read_text().splitlines():
    p=line.split()
    if len(p)==3 and p[0]=='R': native_ranges.append((int(p[1],16),int(p[1],16)+int(p[2],16)))
for pc in sorted(set(ns)|set(nd)):
    s0,s1=bs.get(pc,{}),ns.get(pc,{}); d0,d1=bd.get(pc,{}),nd.get(pc,{})
    static=sum(delta(s0,s1,k) for k in ('misses','modified','runtime','unknown')); entries=delta(d0,d1,'entry_hits')
    insns=delta(d0,d1,'insns'); blocks=delta(d0,d1,'hits')
    if not static and not entries and not insns: continue
    addr=int(pc,16)
    rows.append({'pc':pc,'external_entries':max(static,entries),'static_entries':static,'dynamic_entries':entries,
                 'interpreted_blocks':blocks,'interpreted_insns':insns,'entries_per_s':max(static,entries)/elapsed,
                 'insns_per_s':insns/elapsed,'covered_by_static_range':any(a<=addr<b for a,b in native_ranges)})
rows.sort(key=lambda x:(-x['interpreted_insns'],-x['external_entries'],x['pc']))
evidence=[]
for row in rows[:16]:
    pc=row['pc']; item={'pc':pc}
    try:
        words=request('mem_words',addr=pc,count=32).get('words',[]); item['words']=words
        if words: item['prefix_crc32']=f'0x{zlib.crc32(b"".join(struct.pack("<I",int(x,16)) for x in words))&0xffffffff:08X}'
        item['overlay_candidates']=request('overlay_candidates',pc=pc)
    except Exception as exc: item['error']=str(exc)
    evidence.append(item)
for name,data in [('before_static_text_misses.json',before_static),('before_overlay_interp_hot.json',before_dynamic),
                  ('after_static_text_misses.json',after_static),('after_overlay_interp_hot.json',after_dynamic),
                  ('before_diagnostics.json',before_diag),('after_diagnostics.json',after_diag),('ranking-live-evidence.json',evidence)]:
    (session/name).write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
result={'track':'OVL-002C-DDARK-BOMBS-DISCOVERY','duration_s':elapsed,'pcs':len(rows),
        'interpreted_insns':sum(x['interpreted_insns'] for x in rows),'entries':rows}
(session/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
with (session/'interpreted.csv').open('w',newline='',encoding='utf-8') as f:
    cols=list(rows[0]) if rows else ['pc','external_entries','static_entries','dynamic_entries','interpreted_blocks','interpreted_insns','entries_per_s','insns_per_s','covered_by_static_range']
    w=csv.DictWriter(f,fieldnames=cols); w.writeheader(); w.writerows(rows)
lines=['# OVL-002C - bombas isoladas','',f'- Duracao: {elapsed:.3f} s',f'- PCs interpretados: {len(rows)}',
       f'- Instrucoes interpretadas: {result["interpreted_insns"]}','','| PC | Entradas | Instrucoes | Instrucoes/s |','|---|---:|---:|---:|']
for row in rows: lines.append(f'| `{row["pc"]}` | {row["external_entries"]} | {row["interpreted_insns"]} | {row["insns_per_s"]:.1f} |')
(session/'summary.md').write_text('\n'.join(lines)+'\n')
print(f'Coleta concluida. Sessao: {session}')
PY
}

main() {
    case "${1:-}" in '') ;; -h|--help) printf 'Uso: bash tools/observer_ddark_bombs_ovl_002c.sh\n'; return ;; *) fail "Argumento desconhecido." ;; esac
    validate
    {
        printf 'track=OVL-002C-DDARK-BOMBS-DISCOVERY\nruntime_dir=%s\n' "$RUNTIME_DIR"
        printf 'prepare_seconds=5\nduration_seconds=30\nroute=D.Dark P1 x Ryu P2; cenario Ryu; apenas bombas sem acerto\n'
        printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
    observe
}

main "$@"
