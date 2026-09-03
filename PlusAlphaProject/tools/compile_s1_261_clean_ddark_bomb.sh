#!/usr/bin/env bash
# Compila uma build Release limpa e instala o cache OVL-002C ja aprovado.
# Nao gera fontes, BIOS ou overlays e nao abre o jogo.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-261-clean-ddark-bomb"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly CONFIG="$PROJECT_ROOT/game_s1_261_clean_ddark_bomb.toml"
readonly SOURCE_STATE="$PROJECT_ROOT/local/overlay/.ovl-002c-current-runtime.state"
readonly RANGES="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly DISPATCH="$PROJECT_ROOT/generated/SLUS_005.48_dispatch.c"
readonly AUDIT="$REPO_ROOT/psxrecomp/tools/codegen_audit_game.py"
readonly OUTPUT_MANIFEST="$BUILD_DIR/s1-261-clean-ddark-bomb-manifest.json"
readonly SOURCE_MANIFEST_SHA=9FFA51CBC427970CD7E786709578BC1996952837867AF7E0F9A14ABDD8BF996B
readonly RANGES_SHA=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly DISPATCH_SHA=7C5656D573537DF87C9CE7E980C2588E52F475F37ED40E0B69B9E99F734F127A
readonly GITIGNORE_SHA=12933E7F49A9C16A0C8BFF015F99D56BA0202059C9B3B50BF0933D418F3E6218
readonly BIOS_SHA=B17AD5560A4A8C1A289C90F0A05BABF17980FE3185EB05E13B4CE7C4A0D422EC

PYTHON_BIN=
SOURCE_RUNTIME=
SOURCE_MANIFEST=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
state_value() { awk -F= -v key="$2" '$1==key {print substr($0,index($0,"=")+1); exit}' "$1"; }
file_sha() { sha256sum "$1" | awk '{print toupper($1)}'; }

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

validate() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in cmake ninja nm objdump nproc sha256sum awk grep; do
        command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado no UCRT64."
    done
    select_python
    [[ -f "$CONFIG" && -f "$SOURCE_STATE" && -f "$RANGES" && -f "$DISPATCH" && -f "$AUDIT" ]] ||
        fail "Entradas obrigatorias ausentes."
    [[ ! -f "$OUTPUT_MANIFEST" ]] || fail "A build limpa ja esta concluida: $BUILD_DIR"
    [[ "$(file_sha "$RANGES")" == "$RANGES_SHA" ]] || fail "Ranges nao pertencem ao S1-261 aprovado."
    [[ "$(file_sha "$DISPATCH")" == "$DISPATCH_SHA" ]] || fail "Dispatch nao pertence ao S1-261 aprovado."
    [[ "$(file_sha "$REPO_ROOT/.gitignore")" == "$GITIGNORE_SHA" ]] || fail ".gitignore divergiu."
    [[ "$(file_sha "$REPO_ROOT/psxrecomp/generated/SCPH1001.emitter.sha")" == "$BIOS_SHA" ]] || fail "Emitter da BIOS divergiu."
    ! grep -Eq '^[[:space:]]*(debug_port|overlay_autocompile_cmd|overlay_autocompile_cmd_tcc)[[:space:]]*=' "$CONFIG" ||
        fail "A configuracao limpa contem telemetria ou autocompilacao."
    grep -Eq '^[[:space:]]*overlay_cache[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$CONFIG" || fail "Cache desabilitado."

    SOURCE_RUNTIME="$(state_value "$SOURCE_STATE" runtime_dir)"
    SOURCE_MANIFEST="$(state_value "$SOURCE_STATE" cache_manifest)"
    case "$SOURCE_RUNTIME" in "$PROJECT_ROOT"/local/overlay/ovl-002c-test-runtime-*) ;; *) fail "Runtime OVL-002C invalido." ;; esac
    case "$SOURCE_MANIFEST" in "$SOURCE_RUNTIME"/ovl-002c-cache-manifest.json) ;; *) fail "Manifesto OVL-002C invalido." ;; esac
    [[ "$(state_value "$SOURCE_STATE" capture_key)" == 0x00020000:0xF943B63B ]] || fail "Imagem D.Dark divergente."
    [[ "$(state_value "$SOURCE_STATE" image_body_words)" == 2074 ]] || fail "Volume OVL-002C divergente."
    [[ -f "$SOURCE_MANIFEST" && "$(file_sha "$SOURCE_MANIFEST")" == "$SOURCE_MANIFEST_SHA" ]] || fail "Manifesto OVL-002C divergiu."

    "$PYTHON_BIN" - "$SOURCE_RUNTIME" "$SOURCE_MANIFEST" <<'PY'
import hashlib,json,pathlib,socket,sys
root=pathlib.Path(sys.argv[1]); manifest=pathlib.Path(sys.argv[2]); data=json.loads(manifest.read_text(encoding='utf-8'))
if data.get('track')!='OVL-002C-DDARK-BOMBS-CUMULATIVE': raise SystemExit('track OVL-002C divergente')
if data.get('capture_keys')!=['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F','0x00020000:0xF943B63B']:
    raise SystemExit('imagens cumulativas divergentes')
for key,want in [('dll_count',50),('ranges_count',50),('unique_entries',126),('image_body_words',2074),('incremental_words',966),('prior_image_words',1108)]:
    if int(data.get(key,-1))!=want: raise SystemExit(f'{key} divergente')
if len(data.get('files',[]))!=100: raise SystemExit('inventario OVL-002C incompleto')
for row in data['files']:
    path=root/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(row['size']): raise SystemExit(f'arquivo ausente: {row["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=row['sha256']: raise SystemExit(f'hash divergente: {row["path"]}')
with socket.socket() as sock:
    sock.settimeout(0.25)
    if sock.connect_ex(('127.0.0.1',4531))==0: raise SystemExit('feche o runtime de telemetria que esta usando a porta 4531')
print('Cache aprovado OVL-002C validado: 50 DLLs, 126 entradas, 2074 palavras na imagem D.Dark.')
PY

    local funcs entries
    funcs="$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES")"
    entries="$(awk '/^static const PsxGameDispatchEntry k_psx_game_dispatch\[\] = \{/ {on=1; next} on && /^};$/ {print n+0; exit} on && /^[[:space:]]*\{/ {n++}' "$DISPATCH")"
    [[ "$funcs" == 1059 && "$entries" == 16667 ]] || fail "Contagens S1-261 divergentes: funcoes=$funcs dispatch=$entries"
    "$PYTHON_BIN" "$AUDIT" --config "$PROJECT_ROOT/game.toml"
}

build_clean() {
    printf '\n==> Configurando Release limpa, sem ferramentas de debug\n'
    cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DPSX_DEBUG_TOOLS=OFF -DPSX_STATIC_RUNTIME=ON
    printf '\n==> Compilando buildClean-ucrt-s1-261-clean-ddark-bomb\n'
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
    [[ -f "$EXE" ]] || fail "Executavel nao produzido."
    grep -qxF 'CMAKE_BUILD_TYPE:STRING=Release' "$BUILD_DIR/CMakeCache.txt" || fail "Build nao esta em Release."
    grep -qxF 'PSX_DEBUG_TOOLS:BOOL=OFF' "$BUILD_DIR/CMakeCache.txt" || fail "Ferramentas de debug permaneceram ativas."
    grep -qxF 'PSX_STATIC_RUNTIME:BOOL=ON' "$BUILD_DIR/CMakeCache.txt" || fail "Runtime nao ficou estatico."
    local imports
    imports="$(objdump -p "$EXE" | awk '/DLL Name:/ {print $3}')"
    ! printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$' ||
        fail "Executavel ainda depende de DLL de runtime."
}

install_cache() {
    [[ ! -e "$BUILD_DIR/cache" ]] || fail "Destino de cache ja existe e nao sera sobrescrito."
    "$PYTHON_BIN" - "$SOURCE_RUNTIME" "$SOURCE_MANIFEST" "$BUILD_DIR" "$CONFIG" "$EXE" "$OUTPUT_MANIFEST" <<'PY'
import datetime,hashlib,json,pathlib,shutil,sys
source,source_manifest,dest,config,exe,output=map(pathlib.Path,sys.argv[1:])
data=json.loads(source_manifest.read_text(encoding='utf-8')); copied=[]
for row in data['files']:
    src=source/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    dst=dest/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
    digest=hashlib.sha256(dst.read_bytes()).hexdigest().upper()
    if digest!=row['sha256'] or dst.stat().st_size!=int(row['size']): raise SystemExit(f'copia divergente: {row["path"]}')
    copied.append({'path':row['path'],'size':row['size'],'sha256':digest})
result={'track':'S1-261-CLEAN-DDARK-BOMB','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'configuration':'Release; PSX_DEBUG_TOOLS=OFF; PSX_STATIC_RUNTIME=ON; no runtime log',
        'exe_sha256':hashlib.sha256(exe.read_bytes()).hexdigest().upper(),
        'config_sha256':hashlib.sha256(config.read_bytes()).hexdigest().upper(),
        'source_manifest_sha256':hashlib.sha256(source_manifest.read_bytes()).hexdigest().upper(),
        'static_words':111379,'static_total_words':195584,'static_coverage_percent':56.9469,
        'cache_dll_count':50,'cache_unique_entries':126,'ddark_image_key':'0x00020000:0xF943B63B',
        'ddark_image_words':2074,'ddark_bomb_incremental_words':966,'files':copied}
output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
print('Cache OVL-002C copiado e revalidado sem modificar o runtime de telemetria.')
PY
}

main() {
    case "${1:-}" in -h|--help) printf 'Uso: bash tools/compile_s1_261_clean_ddark_bomb.sh\n'; return ;; '') ;; *) fail "Argumento desconhecido." ;; esac
    validate
    build_clean
    install_cache
    printf '\nBUILD LIMPA PRONTA\n  %s\n\nAbra com:\n  bash tools/run_s1_261_clean_ddark_bomb.sh\n' "$BUILD_DIR"
}

main "$@"
