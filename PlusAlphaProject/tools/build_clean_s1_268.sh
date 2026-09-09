#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-268"
readonly TARGET_EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"
readonly REF_CLEAN_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-266"
readonly TELEMETRY_DIR="$PROJECT_ROOT/build-telemetry"

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
printf '        COMPILACAO DA BUILD LIMPA (CLEAN) - MICRO-LOTE S1-268         \n'
printf '  Perfil: RelWithDebInfo (-O2 -g -DNDEBUG)                            \n'
printf '  Ferramentas de Debug: PSX_DEBUG_TOOLS=OFF (Desativadas para 60 FPS) \n'
printf '  Runtime Estatico:     PSX_STATIC_RUNTIME=ON                         \n'
printf '  Launcher UI:          PSX_LAUNCHER=ON                               \n'
printf '  Diretorio Alvo:       buildClean-ucrt-s1-268                        \n'
printf '======================================================================\n'

cd "$PROJECT_ROOT"

if [[ ! -d "$BUILD_DIR" ]]; then
    printf '[1/4] Configurando diretorio de build limpo: %s...\n' "$BUILD_DIR"
    cmake -B "$BUILD_DIR" -S "$PROJECT_ROOT" -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DPSX_DEBUG_TOOLS=OFF \
        -DPSX_STATIC_RUNTIME=ON \
        -DPSX_LAUNCHER=ON
else
    printf '[1/4] Diretorio de build existente detectado. Reconfigurando...\n'
    cmake -B "$BUILD_DIR" -S "$PROJECT_ROOT" -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DPSX_DEBUG_TOOLS=OFF \
        -DPSX_STATIC_RUNTIME=ON \
        -DPSX_LAUNCHER=ON
fi

printf '[2/4] Compilando target psx-runtime com Ninja...\n'
cmake --build "$BUILD_DIR" --target psx-runtime

[[ -f "$TARGET_EXE" ]] || fail "Executavel nao foi produzido em: $TARGET_EXE"

printf '[3/4] Sincronizando e populando hierarquia de Cache de Overlays...\n'
mkdir -p "$BUILD_DIR/cache"

# Copia a hierarquia completa de cache pre-compilada compativel
if [[ -d "$REF_CLEAN_DIR/cache" ]]; then
    cp -ru "$REF_CLEAN_DIR/cache/"* "$BUILD_DIR/cache/" 2>/dev/null || cp -r "$REF_CLEAN_DIR/cache/"* "$BUILD_DIR/cache/"
    printf '    [+] Cache clonado a partir de: %s\n' "$REF_CLEAN_DIR/cache"
elif [[ -d "$TELEMETRY_DIR/cache" ]]; then
    cp -ru "$TELEMETRY_DIR/cache/"* "$BUILD_DIR/cache/" 2>/dev/null || cp -r "$TELEMETRY_DIR/cache/"* "$BUILD_DIR/cache/"
    printf '    [+] Cache clonado a partir de: %s\n' "$TELEMETRY_DIR/cache"
fi

printf '[4/4] Copiando arquivos de configuracao, UI e assets visuais...\n'
for asset_file in settings.toml keybinds.ini input.ini launcher.rml; do
    if [[ -f "$REF_CLEAN_DIR/$asset_file" ]]; then
        cp -u "$REF_CLEAN_DIR/$asset_file" "$BUILD_DIR/$asset_file" 2>/dev/null || cp "$REF_CLEAN_DIR/$asset_file" "$BUILD_DIR/$asset_file"
    elif [[ -f "$TELEMETRY_DIR/$asset_file" ]]; then
        cp -u "$TELEMETRY_DIR/$asset_file" "$BUILD_DIR/$asset_file" 2>/dev/null || cp "$TELEMETRY_DIR/$asset_file" "$BUILD_DIR/$asset_file"
    fi
done

for asset_dir in fonts img; do
    if [[ -d "$REF_CLEAN_DIR/$asset_dir" ]]; then
        cp -ru "$REF_CLEAN_DIR/$asset_dir" "$BUILD_DIR/" 2>/dev/null || cp -r "$REF_CLEAN_DIR/$asset_dir" "$BUILD_DIR/"
    elif [[ -d "$TELEMETRY_DIR/$asset_dir" ]]; then
        cp -ru "$TELEMETRY_DIR/$asset_dir" "$BUILD_DIR/" 2>/dev/null || cp -r "$TELEMETRY_DIR/$asset_dir" "$BUILD_DIR/"
    fi
done

printf '\n======================================================================\n'
printf '  [+] BUILD LIMPA S1-268 GERADA COM SUCESSO!\n'
printf '  Executavel : %s\n' "$TARGET_EXE"
printf '  Tamanho    : %s bytes\n' "$(wc -c < "$TARGET_EXE")"
printf '  Cache      : %s/cache\n' "$BUILD_DIR"
printf '======================================================================\n'
