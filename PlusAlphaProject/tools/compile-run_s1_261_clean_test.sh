#!/usr/bin/env bash
# Build limpa de estabilizacao: EXE S1-261 + cache cumulativo OVL-001A+B.
# Nao gera fontes, nao regenera BIOS, nao compila overlays e nao abre o jogo.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd -P)"
readonly FRAMEWORK_ROOT="$REPO_ROOT/psxrecomp"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-261-clean-test"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly GAME_CONFIG="$PROJECT_ROOT/game_s1_261_clean_test.toml"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly DISPATCH_FILE="$PROJECT_ROOT/generated/SLUS_005.48_dispatch.c"
readonly AUDIT_SCRIPT="$FRAMEWORK_ROOT/tools/codegen_audit_game.py"
readonly SOURCE_STATE="$PROJECT_ROOT/local/overlay/.ovl-001b-current-runtime.state"
readonly CLEAN_MANIFEST="$BUILD_DIR/s1-261-clean-test-manifest.json"
readonly SOURCE_MANIFEST_SHA256=72B3AAF484F3D024833913B41A43D518E162FD31E3420E07105915C9726E8C38
readonly EXPECTED_RANGES_SHA256=0B63B7672129C4A357100D5DE97DAB762910705FAABC4580880C291AD14DE69F
readonly EXPECTED_DISPATCH_SHA256=7C5656D573537DF87C9CE7E980C2588E52F475F37ED40E0B69B9E99F734F127A
readonly EXPECTED_FUNCTIONS=1059
readonly EXPECTED_DISPATCH_ENTRIES=16667
readonly EXPECTED_CACHE_DLLS=49
readonly EXPECTED_CACHE_ENTRIES=108
readonly EXPECTED_BODY_WORDS=5183
readonly EXPECTED_INCREMENTAL_WORDS=620
readonly EXPECTED_QUARANTINED_WORDS=130
readonly EXPECTED_GITIGNORE_SHA256=12933E7F49A9C16A0C8BFF015F99D56BA0202059C9B3B50BF0933D418F3E6218
readonly EXPECTED_BIOS_EMITTER_SHA256=B17AD5560A4A8C1A289C90F0A05BABF17980FE3185EB05E13B4CE7C4A0D422EC

PYTHON_BIN=
SOURCE_RUNTIME=
SOURCE_MANIFEST=

fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
state_value() { awk -F= -v wanted="$2" '$1==wanted {print substr($0,index($0,"=")+1); exit}' "$1"; }

usage() {
    cat <<'EOF'
Uso no MSYS2 UCRT64, com o jogo fechado:

  bash tools/compile-run_s1_261_clean_test.sh

Compila buildClean-ucrt-s1-261-clean-test em Release, sem telemetria, e copia
o cache cumulativo OVL-001A+B previamente validado. Nao gera fontes, nao
regenera BIOS, nao recompila overlays e nao abre o jogo.
EOF
}

select_python() {
    if command -v python >/dev/null 2>&1; then PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then PYTHON_BIN="$(command -v python3)"
    else fail "Python nao encontrado no UCRT64."
    fi
}

require_sha256() {
    local path="$1" expected="$2" actual
    [[ -f "$path" ]] || fail "Arquivo protegido ausente: $path"
    actual="$(sha256sum "$path" | awk '{print toupper($1)}')"
    [[ "$actual" == "$expected" ]] || fail "SHA-256 inesperado em $path: $actual"
}

validate_source_tree() {
    [[ "${MSYSTEM:-}" == UCRT64 ]] || fail "Abra o MSYS2 UCRT64."
    for tool in cmake ninja nm objdump nproc sha256sum awk grep; do
        command -v "$tool" >/dev/null 2>&1 || fail "$tool nao encontrado no UCRT64."
    done
    select_python
    [[ -f "$PROJECT_ROOT/CMakeLists.txt" && -f "$GAME_CONFIG" ]] || fail "Projeto/config limpo ausente."
    [[ -f "$RANGES_FILE" && -f "$DISPATCH_FILE" && -f "$AUDIT_SCRIPT" ]] || fail "Fontes S1-261 ausentes."
    [[ ! -f "$CLEAN_MANIFEST" ]] || fail "A build limpa ja foi concluida: $BUILD_DIR"

    require_sha256 "$PROJECT_ROOT/CMakeLists.txt" 6E9DDCFD0439F626B36245D6C6A76BD51712A6C0ECA42C802D890098C8C29E6C
    require_sha256 "$FRAMEWORK_ROOT/runtime/runtime.cmake" 58B42159D9B36CB84C3380EE3D1A239364C27F85336CBDCC1D7A8EDFC3D3246C
    require_sha256 "$FRAMEWORK_ROOT/runtime/src/main.cpp" 1A932F2CF286930A967CF4EF03595B487480B84887F6630F5D3B57472401D8B0
    require_sha256 "$FRAMEWORK_ROOT/runtime/src/overlay_loader.c" 4DBC05EAD532A54C84C1C321072B4174A6DFE1983358C3D3822B342A7A85018E
    require_sha256 "$FRAMEWORK_ROOT/runtime/src/dirty_ram_interp.c" 43575912AFAD3DB0AA72B5B1E341B3BB68A5ECFD1149F3C1246C4DCA20376A60
    require_sha256 "$FRAMEWORK_ROOT/runtime/src/overlay_backend.c" A260709B87835CAC6E4EFA267F88596FFFC30AA8318F285CE99C58F59901E8A4
    require_sha256 "$FRAMEWORK_ROOT/runtime/src/code_provider.c" D311EAD3465B8D45C885E7FC827ECDC7D416BD6E2DDB7B945B6F5F6E811E1B63
    require_sha256 "$FRAMEWORK_ROOT/runtime/src/overlay_posix.c" 4C1D2246C7DBBB33935F7A40491189D77F79FBC7F0D8CA1BFB95C310FCE014D8
    require_sha256 "$FRAMEWORK_ROOT/runtime/include/overlay_loader.h" 968BDA3D3C88A6BBC72E4F8E1F1E08E63492895A16D0A053DC571F020492E72B
    require_sha256 "$FRAMEWORK_ROOT/runtime/include/dirty_ram_interp.h" 8605A7CF071C56DDB5007DB1F96ABDE06D1C9EF24D12B632EA68EEF4CE8D7597
    require_sha256 "$RANGES_FILE" "$EXPECTED_RANGES_SHA256"
    require_sha256 "$DISPATCH_FILE" "$EXPECTED_DISPATCH_SHA256"
    require_sha256 "$REPO_ROOT/.gitignore" "$EXPECTED_GITIGNORE_SHA256"
    require_sha256 "$FRAMEWORK_ROOT/generated/SCPH1001.emitter.sha" "$EXPECTED_BIOS_EMITTER_SHA256"

    grep -Eq '^[[:space:]]*overlay_cache[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$GAME_CONFIG" ||
        fail "A configuracao limpa nao habilita overlay_cache."
    grep -Eq '^[[:space:]]*overlay_backend[[:space:]]*=[[:space:]]*"tcc"[[:space:]]*$' "$GAME_CONFIG" ||
        fail "Backend offline da configuracao limpa diverge."
    ! grep -Eq '^[[:space:]]*(debug_port|overlay_autocompile_cmd|overlay_autocompile_cmd_tcc)[[:space:]]*=' "$GAME_CONFIG" ||
        fail "A configuracao limpa contem telemetria/autocompilacao."

    local function_count dispatch_entries
    function_count="$(grep -c '^F [0-9A-Fa-f]\{8\}$' "$RANGES_FILE")"
    [[ "$function_count" == "$EXPECTED_FUNCTIONS" ]] || fail "Esperadas $EXPECTED_FUNCTIONS funcoes; obtidas $function_count."
    dispatch_entries="$(awk '
        /^static const PsxGameDispatchEntry k_psx_game_dispatch\[\] = \{/ { inside=1; next }
        inside && /^};$/ { print count+0; exit }
        inside && /^[[:space:]]*\{/ { count++ }
    ' "$DISPATCH_FILE")"
    [[ "$dispatch_entries" == "$EXPECTED_DISPATCH_ENTRIES" ]] ||
        fail "Esperadas $EXPECTED_DISPATCH_ENTRIES entradas de dispatch; obtidas $dispatch_entries."

    printf '\n==> Auditando as fontes estaticas S1-261\n'
    "$PYTHON_BIN" "$AUDIT_SCRIPT" --config "$PROJECT_ROOT/game.toml"
}

validate_overlay_cache() {
    [[ -f "$SOURCE_STATE" ]] || fail "Estado OVL-001B validado ausente: $SOURCE_STATE"
    SOURCE_RUNTIME="$(state_value "$SOURCE_STATE" runtime_dir)"
    SOURCE_MANIFEST="$(state_value "$SOURCE_STATE" cache_manifest)"
    case "$SOURCE_RUNTIME" in "$PROJECT_ROOT"/local/overlay/ovl-001b-test-runtime-*) ;; *) fail "Runtime OVL-001B de origem invalido." ;; esac
    [[ -f "$SOURCE_MANIFEST" ]] || fail "Manifesto OVL-001B de origem ausente."
    require_sha256 "$SOURCE_MANIFEST" "$SOURCE_MANIFEST_SHA256"

    "$PYTHON_BIN" - "$SOURCE_RUNTIME" "$SOURCE_MANIFEST" \
        "$EXPECTED_CACHE_DLLS" "$EXPECTED_CACHE_ENTRIES" "$EXPECTED_BODY_WORDS" \
        "$EXPECTED_INCREMENTAL_WORDS" "$EXPECTED_QUARANTINED_WORDS" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); manifest=pathlib.Path(sys.argv[2])
expected_dlls,expected_entries,body,incremental,quarantined=map(int,sys.argv[3:])
data=json.loads(manifest.read_text(encoding='utf-8'))
if data.get('track')!='OVL-001B-SAFE-CUMULATIVE': raise SystemExit('manifesto nao pertence a OVL-001B-safe cumulativa')
if data.get('capture_keys')!=['0x00020000:0xAC1FF1A4','0x00020000:0x94E6122F']: raise SystemExit('chaves A+B divergentes')
checks=(('dll_count',expected_dlls),('ranges_count',expected_dlls),('unique_entries',expected_entries),
        ('body_words',body),('incremental_words',incremental),('quarantined_words',quarantined))
for key,want in checks:
    if int(data.get(key,-1))!=want: raise SystemExit(f'{key} divergente: {data.get(key)} != {want}')
files=data.get('files',[])
if len(files)!=expected_dlls*2: raise SystemExit(f'inventario deveria conter {expected_dlls*2} arquivos; contem {len(files)}')
for row in files:
    path=root/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    if not path.is_file() or path.stat().st_size!=int(row['size']): raise SystemExit(f'cache ausente/divergente: {row["path"]}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper()!=row['sha256']: raise SystemExit(f'hash divergente: {row["path"]}')
print(f'Cache OVL A+B validado: {expected_dlls} DLLs, {expected_entries} entradas, {body} palavras cumulativas.')
PY
}

configure_and_build() {
    printf '\n==> Configurando build limpa S1-261 + OVL-001A+B\n'
    cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DPSX_DEBUG_TOOLS=OFF \
        -DPSX_STATIC_RUNTIME=ON
    printf '\n==> Compilando buildClean-ucrt-s1-261-clean-test\n'
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"
}

audit_executable() {
    [[ -f "$EXE" ]] || fail "Executavel nao produzido: $EXE"
    local cache="$BUILD_DIR/CMakeCache.txt" imports
    [[ -f "$cache" ]] || fail "CMakeCache ausente."
    grep -qxF 'CMAKE_BUILD_TYPE:STRING=Release' "$cache" || fail "Build nao esta em Release."
    grep -qxF 'PSX_DEBUG_TOOLS:BOOL=OFF' "$cache" || fail "Telemetria ainda esta habilitada."
    grep -qxF 'PSX_STATIC_RUNTIME:BOOL=ON' "$cache" || fail "Runtime estatico nao esta habilitado."
    for symbol in func_8018F10C func_8016FC28 func_8019FC6C func_8017566C func_801939A0 func_80103BD8; do
        nm -C "$EXE" | grep -Eq "[[:space:]]T[[:space:]]+$symbol$" || fail "Simbolo S1 ausente: $symbol"
    done
    imports="$(objdump -p "$EXE" | awk '/DLL Name:/ {print $3}')"
    ! printf '%s\n' "$imports" | grep -Eqi '^(SDL2\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll)$' ||
        fail "Executavel importa DLL de runtime que deveria estar estatica."
}

install_validated_cache() {
    [[ ! -e "$BUILD_DIR/cache" ]] || fail "Destino de cache ja existe; nao sera sobrescrito: $BUILD_DIR/cache"
    "$PYTHON_BIN" - "$SOURCE_RUNTIME" "$SOURCE_MANIFEST" "$BUILD_DIR" "$GAME_CONFIG" "$EXE" "$CLEAN_MANIFEST" <<'PY'
import datetime,hashlib,json,pathlib,shutil,sys
source=pathlib.Path(sys.argv[1]); source_manifest=pathlib.Path(sys.argv[2]); dest=pathlib.Path(sys.argv[3])
config=pathlib.Path(sys.argv[4]); exe=pathlib.Path(sys.argv[5]); output=pathlib.Path(sys.argv[6])
data=json.loads(source_manifest.read_text(encoding='utf-8'))
copied=[]
for row in data['files']:
    src=source/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    dst=dest/pathlib.Path(*pathlib.PurePosixPath(row['path']).parts)
    dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
    actual=hashlib.sha256(dst.read_bytes()).hexdigest().upper()
    if dst.stat().st_size!=int(row['size']) or actual!=row['sha256']: raise SystemExit(f'copia divergente: {row["path"]}')
    copied.append({'path':row['path'],'size':dst.stat().st_size,'sha256':actual})
result={
  'track':'S1-261-CLEAN-TEST-OVL-001AB','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
  'configuration':'Release; PSX_DEBUG_TOOLS=OFF; PSX_STATIC_RUNTIME=ON',
  'exe_sha256':hashlib.sha256(exe.read_bytes()).hexdigest().upper(),
  'game_config_sha256':hashlib.sha256(config.read_bytes()).hexdigest().upper(),
  'source_cache_manifest_sha256':hashlib.sha256(source_manifest.read_bytes()).hexdigest().upper(),
  'static_words':111379,'static_total_words':195584,'static_coverage_percent':56.9469,
  'overlay_variant_words':9746,'overlay_unique_body_words':int(data['body_words']),
  'overlay_incremental_over_a_words':int(data['incremental_words']),
  'overlay_quarantined_words':int(data['quarantined_words']),
  'cache_dll_count':int(data['dll_count']),'cache_unique_entries':int(data['unique_entries']),'files':copied,
}
output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
print(f'Cache copiado e revalidado: {result["cache_dll_count"]} DLLs; {result["overlay_unique_body_words"]} palavras unicas.')
PY
}

finish() {
    local exe_hash manifest_hash
    exe_hash="$(sha256sum "$EXE" | awk '{print toupper($1)}')"
    manifest_hash="$(sha256sum "$CLEAN_MANIFEST" | awk '{print toupper($1)}')"
    printf '\nBUILD LIMPA S1-261 + OVL-001A+B PRONTA PARA TESTE\n'
    printf '  Build:                    %s\n' "$BUILD_DIR"
    printf '  Executavel:               %s\n' "$EXE"
    printf '  SHA-256 EXE:              %s\n' "$exe_hash"
    printf '  Manifesto local SHA-256:  %s\n' "$manifest_hash"
    printf '  EXE estatico:             111379/195584 palavras (56,9469%%)\n'
    printf '  Overlays por variante:    9746 palavras (4563 A + 5183 B)\n'
    printf '  Corpo overlay cumulativo: 5183 palavras unicas\n'
    printf '  Configuracao:             Release, sem telemetria, sem autocompilacao\n'
    printf '\nPara abrir depois da compilacao:\n  bash tools/run_s1_261_clean_test.sh\n'
}

main() {
    case "${1:-}" in '') ;; -h|--help) usage; return ;; *) usage; fail "Argumento desconhecido: $1" ;; esac
    validate_source_tree
    validate_overlay_cache
    configure_and_build
    audit_executable
    install_validated_cache
    finish
}

main "$@"
