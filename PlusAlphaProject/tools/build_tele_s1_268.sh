#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildTele-s1-268"
readonly TARGET_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly REF_CLEAN_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-268"

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

validate_env() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] ||
        printf 'AVISO: Recomendado executar no MSYS2 UCRT64. MSYSTEM=%s\n' "${MSYSTEM:-indefinido}" >&2

    command -v cmake >/dev/null 2>&1 || fail "cmake nao encontrado no PATH."
    command -v ninja >/dev/null 2>&1 || fail "ninja nao encontrado no PATH."
}

validate_env

printf '======================================================================\n'
printf '     COMPILACAO DA BUILD DE TELEMETRIA - MICRO-LOTE S1-268            \n'
printf '  Alvo:                 buildTele-s1-268                              \n'
printf '  Perfil:               RelWithDebInfo (-O2 -g -DNDEBUG)              \n'
printf '  Telemetria / Debug:   PSX_DEBUG_TOOLS=ON (Off-Thread I/O Handoff)   \n'
printf '  Runtime Estatico:     PSX_STATIC_RUNTIME=ON                         \n'
printf '  Launcher UI:          PSX_LAUNCHER=ON                               \n'
printf '======================================================================\n'

cd "$PROJECT_ROOT"

printf '[1/4] Configurando diretorio de build: %s...\n' "$BUILD_DIR"
cmake -B "$BUILD_DIR" -S "$PROJECT_ROOT" -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DPSX_DEBUG_TOOLS=ON \
    -DPSX_STATIC_RUNTIME=ON \
    -DPSX_LAUNCHER=ON

printf '[2/4] Compilando target psx-runtime com Ninja...\n'
cmake --build "$BUILD_DIR" --target psx-runtime

printf '      Compilando target exPlusAlpha com Ninja...\n'
cmake --build "$BUILD_DIR" --target exPlusAlpha

[[ -f "$TARGET_EXE" ]] || fail "Executavel nao foi produzido em: $TARGET_EXE"

printf '[3/4] Sincronizando e populando hierarquia de Cache de Overlays...\n'
mkdir -p "$BUILD_DIR/cache"

if [[ -d "$REF_CLEAN_DIR/cache" ]]; then
    cp -ru "$REF_CLEAN_DIR/cache/"* "$BUILD_DIR/cache/" 2>/dev/null || cp -r "$REF_CLEAN_DIR/cache/"* "$BUILD_DIR/cache/"
    printf '    [+] Cache clonado a partir de: %s\n' "$REF_CLEAN_DIR/cache"
fi

printf '[4/4] Copiando arquivos de configuracao, UI e assets visuais...\n'
CANONICAL_ASSETS="$PROJECT_ROOT/../psxrecomp/runtime/launcher/assets"
if [[ -f "$CANONICAL_ASSETS/launcher.rml" ]]; then
    cp "$CANONICAL_ASSETS/launcher.rml" "$BUILD_DIR/launcher.rml"
    printf '    [+] launcher.rml canonico copiado (33 KB)\n'
elif [[ -f "$REF_CLEAN_DIR/launcher.rml" ]]; then
    cp "$REF_CLEAN_DIR/launcher.rml" "$BUILD_DIR/launcher.rml"
fi

for asset_dir in fonts img; do
    if [[ -d "$CANONICAL_ASSETS/$asset_dir" ]]; then
        cp -r "$CANONICAL_ASSETS/$asset_dir" "$BUILD_DIR/"
    elif [[ -d "$REF_CLEAN_DIR/$asset_dir" ]]; then
        cp -r "$REF_CLEAN_DIR/$asset_dir" "$BUILD_DIR/"
    fi
done

for proj_file in game.toml overlay_captures.json; do
    if [[ -f "$PROJECT_ROOT/$proj_file" ]]; then
        cp "$PROJECT_ROOT/$proj_file" "$BUILD_DIR/$proj_file"
    fi
done

for clean_file in settings.toml keybinds.ini input.ini game_core.dll; do
    if [[ -f "$REF_CLEAN_DIR/$clean_file" ]]; then
        cp "$REF_CLEAN_DIR/$clean_file" "$BUILD_DIR/$clean_file"
    fi
done

printf '\n======================================================================\n'
printf '  [+] BUILD TELEMETRIA S1-268 GERADA COM SUCESSO!\n'
printf '  Executavel : %s\n' "$TARGET_EXE"
printf '  Tamanho    : %s bytes\n' "$(wc -c < "$TARGET_EXE")"
printf '  Cache      : %s/cache\n' "$BUILD_DIR"
printf '======================================================================\n'
