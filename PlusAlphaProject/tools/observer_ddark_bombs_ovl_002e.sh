#!/usr/bin/env bash
# Janela isolada de 30 s para medir o residuo apos OVL-002E.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly TEST_CONFIG="$PROJECT_ROOT/game_ovl_002e_test.toml"
readonly RUNTIME_STATE="$PROJECT_ROOT/local/overlay/.ovl-002e-current-runtime.state"
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
    [[ -f "$RUNTIME_STATE" ]] || fail "Runtime OVL-002E ausente. Execute compile_ovl_002e_test_runtime.sh."
    RUNTIME_DIR="$(state_value "$RUNTIME_STATE" runtime_dir)"; RUNTIME_EXE="$(state_value "$RUNTIME_STATE" runtime_exe)"
    CACHE_MANIFEST="$(state_value "$RUNTIME_STATE" cache_manifest)"
    case "$RUNTIME_DIR" in "$PROJECT_ROOT"/local/overlay/ovl-002e-test-runtime-*) ;; *) fail "Runtime OVL-002E invalido." ;; esac
    [[ "$(state_value "$RUNTIME_STATE" target)" == 0x80044830 && "$(state_value "$RUNTIME_STATE" image_body_words)" == 2418 ]] || fail "Estado OVL-002E divergente."
    for file in "$TEST_CONFIG" "$RUNTIME_EXE" "$CACHE_MANIFEST"; do [[ -f "$file" ]] || fail "Arquivo ausente: $file"; done
    [[ "$(sha256sum "$RUNTIME_EXE" | awk '{print toupper($1)}')" == "$EXPECTED_EXE_SHA" ]] || fail "Executavel divergiu."
    [[ "$(sha256sum "$PROJECT_ROOT/generated/SLUS_005.48_full.ranges" | awk '{print toupper($1)}')" == "$EXPECTED_RANGES_SHA" ]] || fail "Ranges S1-261 divergiram."
    DEBUG_PORT="$(awk '/^[[:space:]]*\[runtime\]/{ok=1;next} /^[[:space:]]*\[/{ok=0} ok&&/^[[:space:]]*debug_port[[:space:]]*=/{sub(/^[^=]*=/,"");gsub(/[[:space:]]+/,"");print;exit}' "$TEST_CONFIG")"
    [[ "$DEBUG_PORT" == 4533 ]] || fail "debug_port divergente."
    mkdir -p "$PROJECT_ROOT/local/telemetry"
    local suffix candidate
    for suffix in $(seq -w 1 99); do
        candidate="$PROJECT_ROOT/local/telemetry/ovl-002e-ddark-bombs-discovery-$suffix"
        if [[ ! -e "$candidate" ]]; then mkdir "$candidate"; SESSION_DIR="$candidate"; return; fi
    done
    fail "Nao ha pasta livre para a coleta."
}

observe() {
    "$PYTHON_BIN" - "$DEBUG_PORT" "$SESSION_DIR" "$RUNTIME_DIR" "$CACHE_MANIFEST" <<'PY'
import csv,hashlib,json,pathlib,socket,struct,sys,time,zlib
port=int(sys.argv[1]); session=pathlib.Path(sys.argv[2]); runtime=pathlib.Path(sys.argv[3]); manifest_path=pathlib.Path(sys.argv[4])

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
        if not header: header={key:value for key,value in page.items() if key!='entries'}
        for item in page.get('entries',[]):
            if item.get('pc'): rows[f'0x{int(str(item["pc"]),16):08X}']=item
        returned=int(page.get('returned',0) or 0); total=int(page.get(count_key,0) or 0); offset+=returned
        if returned==0 or offset>=total: break
        if offset>65536: raise RuntimeError(f'{command}: paginacao excedida')
    header['entries']=list(rows.values()); return header

def index(snapshot): return {f'0x{int(str(item["pc"]),16):08X}':item for item in snapshot.get('entries',[]) if item.get('pc')}
def delta(before,after,key): return max(0,int(after.get(key,0) or 0)-int(before.get(key,0) or 0))

manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
if manifest.get('track')!='OVL-002E-DDARK-BOMB-RESIDUAL-CUMULATIVE' or int(manifest.get('image_body_words',0))!=2418:
    raise RuntimeError('manifesto conectado nao e OVL-002E')
for item in manifest.get('files',[]):
    path=runtime/pathlib.Path(*pathlib.PurePosixPath(item['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(item['size']) or hashlib.sha256(path.read_bytes()).hexdigest().upper()!=item['sha256']:
        raise RuntimeError(f'cache alterado: {item["path"]}')
probe=request('overlay_loader_status')
if not int(probe.get('active',0) or 0): raise RuntimeError('overlay cache OVL-002E inativo')
expected_cache=(runtime/'cache').resolve(); actual=pathlib.Path(str(probe.get('cache_dir',''))).resolve()
if actual!=expected_cache: raise RuntimeError(f'cache conectado divergiu: {actual}')
live={0x80044830:0x9E9CD462,0x8004485C:0x3596728A,0x800448EC:0xCD23F9BE,0x80044984:0xFE5E309A,
      0x80044A68:0xCE5EABF9,0x80044AF8:0xB9E07A5F,0x80044B8C:0xD7D51FE0,0x80047DE8:0xBEFA5EA1,
      0x80049568:0x9611F1A0,0x80049808:0xCB050F22,0x80049988:0x6D2C8CD6,0x80092C2C:0x1B64D20F,0x80093E4C:0x12FF550F}
new_group={0x80044830,0x8004485C,0x800448EC,0x80044984,0x80044A68,0x80044AF8,0x80044B8C}
identity={'expected_cache_dir':str(expected_cache),'actual_cache_dir':str(actual),'pcs':{}}; errors=[]
for pc,wanted in live.items():
    words=request('mem_words',addr=f'0x{pc:08X}',count=32).get('words',[])
    crc=zlib.crc32(b''.join(struct.pack('<I',int(item,16)) for item in words))&0xffffffff if len(words)==32 else -1
    candidates=request('overlay_candidates',pc=f'0x{pc:08X}').get('candidates',[])
    exact=any(int(item.get('match',0))==1 and int(item.get('state',9))==0 and int(item.get('dll',-1))>=0 and int(item.get('device_touch',1))==0 for item in candidates)
    identity['pcs'][f'0x{pc:08X}']={'crc32':f'0x{crc&0xffffffff:08X}','expected':f'0x{wanted:08X}','candidate_exact_active':exact}
    if crc!=wanted or not exact: errors.append(f'0x{pc:08X}: identidade viva divergente')
identity['errors']=errors; (session/'runtime-identity.json').write_text(json.dumps(identity,indent=2,sort_keys=True)+'\n')
if errors: raise RuntimeError('; '.join(errors))

request('pc_watch_clear')
for pc in live: request('pc_watch_arm',target=f'0x{pc:08X}')
request('pc_watch_reset')
print('\nRuntime OVL-002E confirmado. D.Dark P1 x Ryu P2; mantenha Ryu parado.',flush=True)
for remaining in range(5,0,-1): print(f'Prepare-se: {remaining}...',flush=True); time.sleep(1)
before_static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
before_dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
before_diag={name:request(name) for name in ('overlay_loader_status','dirty_ram_stats','dispatch_stats')}
print('\a[CAPTURANDO] Por 30 s, repita somente bombas sem acertar Ryu.',flush=True)
started=time.monotonic(); time.sleep(30.0); elapsed=time.monotonic()-started
request('pc_watch_stop')
after_dynamic=paged('overlay_interp_hot','total',sort='entries',min_entries=1,phys_lo='0x00000000',phys_hi='0x00200000')
after_static=paged('static_text_misses','total',**{'class':'all','min_hits':1})
after_diag={name:request(name) for name in ('overlay_loader_status','dirty_ram_stats','dispatch_stats')}; watch=request('pc_watch_dump')
print('\a\a[FIM DA CAPTURA] Pare as acoes.',flush=True)

before_s,before_d,after_s,after_d=map(index,(before_static,before_dynamic,after_static,after_dynamic)); rows=[]
for pc in sorted(set(after_s)|set(after_d)):
    s0,s1=before_s.get(pc,{}),after_s.get(pc,{}); d0,d1=before_d.get(pc,{}),after_d.get(pc,{})
    static=sum(delta(s0,s1,key) for key in ('misses','modified','runtime','unknown')); entries=delta(d0,d1,'entry_hits')
    insns=delta(d0,d1,'insns'); blocks=delta(d0,d1,'hits')
    if not static and not entries and not insns: continue
    rows.append({'pc':pc,'external_entries':max(static,entries),'static_entries':static,'dynamic_entries':entries,
                 'interpreted_blocks':blocks,'interpreted_insns':insns,'entries_per_s':max(static,entries)/elapsed,'insns_per_s':insns/elapsed})
rows.sort(key=lambda item:(-item['interpreted_insns'],-item['external_entries'],item['pc']))
seen={str(item.get('target','')).upper():item for item in watch.get('entries',[])}; group={}; fatal=[]
for pc in sorted(new_group):
    item=seen.get(f'0X{pc:08X}',{}); native=int(item.get('native_hits',0) or 0); interp=int(item.get('interpreted_hits',0) or 0)
    group[f'0x{pc:08X}']={'native_hits':native,'interpreted_hits':interp}
    if native<=0: fatal.append(f'0x{pc:08X} nao teve hit nativo')
    if interp: fatal.append(f'0x{pc:08X} teve {interp} hit(s) interpretado(s)')
loader={key:delta(before_diag['overlay_loader_status'],after_diag['overlay_loader_status'],key) for key in ('dispatch_native','unregistered_funcs','invalidations','stale_blocked')}
dirty={key:delta(before_diag['dirty_ram_stats'],after_diag['dirty_ram_stats'],key) for key in ('aborts','text_native_blocked','text_diverged_pages','text_exact_mismatches')}
miss=delta(before_diag['dispatch_stats'],after_diag['dispatch_stats'],'miss_total')
if loader['unregistered_funcs'] or any(dirty.values()) or miss: fatal.append('diagnostico de seguranca nao zerado')
total=sum(item['interpreted_insns'] for item in rows); baseline=4632289
result={'track':'OVL-002E-DDARK-BOMBS-DISCOVERY','duration_s':elapsed,'pcs':len(rows),'interpreted_insns':total,
        'ovl_002d_baseline_insns':baseline,'delta_vs_ovl_002d_baseline':total-baseline,'new_group':group,
        'loader_deltas':loader,'guard_deltas':dirty,'dispatch_miss_delta':miss,'technical_clean':not fatal,'errors':fatal,'entries':rows}
for name,data in [('before_static_text_misses.json',before_static),('before_overlay_interp_hot.json',before_dynamic),
                  ('after_static_text_misses.json',after_static),('after_overlay_interp_hot.json',after_dynamic),
                  ('before_diagnostics.json',before_diag),('after_diagnostics.json',after_diag),('pc-watch.json',watch),('result.json',result)]:
    (session/name).write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
with (session/'interpreted.csv').open('w',newline='',encoding='utf-8') as output:
    columns=list(rows[0]) if rows else ['pc','external_entries','static_entries','dynamic_entries','interpreted_blocks','interpreted_insns','entries_per_s','insns_per_s']
    writer=csv.DictWriter(output,fieldnames=columns); writer.writeheader(); writer.writerows(rows)
native_total=sum(item['native_hits'] for item in group.values()); interp_total=sum(item['interpreted_hits'] for item in group.values())
lines=['# OVL-002E - bombas isoladas','',f'- Duracao: {elapsed:.3f} s',f'- PCs interpretados: {len(rows)}',f'- Instrucoes interpretadas: {total}',
       f'- Delta bruto contra OVL-002D: {total-baseline:+d}',f'- Familia nova: {native_total} hits nativos / {interp_total} interpretados',
       f'- Status tecnico: {"CLEAN" if not fatal else "REVIEW"}','','| PC | Entradas | Instrucoes | Instrucoes/s |','|---|---:|---:|---:|']
for item in rows: lines.append(f'| `{item["pc"]}` | {item["external_entries"]} | {item["interpreted_insns"]} | {item["insns_per_s"]:.1f} |')
if fatal: lines += ['','## Bloqueios','']+[f'- {item}' for item in fatal]
(session/'summary.md').write_text('\n'.join(lines)+'\n')
if fatal: raise RuntimeError('; '.join(fatal))
print(f'Coleta concluida. Sessao: {session}')
PY
}

main() {
    case "${1:-}" in '') ;; -h|--help) printf 'Uso: bash tools/observer_ddark_bombs_ovl_002e.sh\n'; return ;; *) fail "Argumento desconhecido." ;; esac
    validate
    {
        printf 'track=OVL-002E-DDARK-BOMBS-DISCOVERY\nruntime_dir=%s\n' "$RUNTIME_DIR"
        printf 'prepare_seconds=5\nduration_seconds=30\nroute=D.Dark P1 x Ryu P2; cenario Ryu; somente bombas sem acerto\n'
        printf 'baseline_ovl_002d_interpreted_insns=4632289\nstarted_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$SESSION_DIR/metadata.txt"
    observe
}

main "$@"
