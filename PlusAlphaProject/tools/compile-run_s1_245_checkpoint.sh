#!/usr/bin/env bash
# S1-245 checkpoint limpo: Release sem telemetria.
# Este script apenas configura, compila e audita o artefato. Ele nunca abre o jogo.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly BUILD_DIR="$PROJECT_ROOT/buildClean-ucrt-s1-245"
readonly RANGES_FILE="$PROJECT_ROOT/generated/SLUS_005.48_full.ranges"
readonly EXE="$BUILD_DIR/StreetFighterEXPlusAlphaRecomp.exe"

if [[ "${MSYSTEM:-}" != "UCRT64" ]]; then
  echo "ERRO: abra o MSYS2 UCRT64 para executar este script." >&2
  exit 1
fi

for required_command in cmake ninja nm objdump nproc; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "ERRO: comando ausente no UCRT64: $required_command" >&2
    exit 1
  fi
done

if [[ ! -f "$PROJECT_ROOT/CMakeLists.txt" ]]; then
  echo "ERRO: raiz CMake invalida: $PROJECT_ROOT" >&2
  exit 1
fi

if [[ ! -f "$RANGES_FILE" ]]; then
  echo "ERRO: fontes geradas ausentes: $RANGES_FILE" >&2
  echo "Execute primeiro o gerador de fontes S1-245 no PowerShell." >&2
  exit 1
fi

for expected in \
  'F 8011D310' \
  'R 8011D310 6A4' \
  'F 80107A74' \
  'R 80107A74 30C' \
  'F 80162D68' \
  'R 80162D68 3D4'; do
  if ! grep -qxF "$expected" "$RANGES_FILE"; then
    echo "ERRO: SLUS_005.48_full.ranges nao corresponde ao lote S1-245 esperado: $expected" >&2
    exit 1
  fi
done

function_count="$(awk '$1 == "F" { count++ } END { print count + 0 }' "$RANGES_FILE")"
if [[ "$function_count" != "1031" ]]; then
  echo "ERRO: esperadas 1031 funcoes emitidas no checkpoint S1-245; obtidas $function_count." >&2
  exit 1
fi

echo "==> Configurando checkpoint limpo S1-245 (Release, PSX_DEBUG_TOOLS=OFF)"
cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DPSX_DEBUG_TOOLS=OFF \
  -DPSX_STATIC_RUNTIME=ON

echo "==> Compilando checkpoint limpo S1-245"
cmake --build "$BUILD_DIR" --parallel "$(nproc)"

if [[ ! -f "$EXE" ]]; then
  echo "ERRO: executavel nao foi produzido: $EXE" >&2
  exit 1
fi

cache="$BUILD_DIR/CMakeCache.txt"
for expected in \
  'CMAKE_BUILD_TYPE:STRING=Release' \
  'PSX_DEBUG_TOOLS:BOOL=OFF' \
  'PSX_STATIC_RUNTIME:BOOL=ON'; do
  if ! grep -qxF "$expected" "$cache"; then
    echo "ERRO: configuracao inesperada no checkpoint: $expected" >&2
    exit 1
  fi
done

for symbol in \
  func_8011D310 \
  func_80107A74 \
  func_80162D68 \
  func_80137FE8 \
  func_80138084 \
  func_8013827C \
  func_801102A0 \
  func_8013CB08; do
  if ! nm -C "$EXE" | grep -q " $symbol$"; then
    echo "ERRO: simbolo emitido ausente no executavel: $symbol" >&2
    exit 1
  fi
done

imports="$(objdump -p "$EXE" | sed -n 's/^\s*DLL Name: //p')"
for forbidden in SDL2.dll libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll; do
  if grep -qiFx "$forbidden" <<<"$imports"; then
    echo "ERRO: runtime dinamico inesperado no checkpoint: $forbidden" >&2
    exit 1
  fi
done

echo
echo "CHECKPOINT S1-245 PRONTO"
echo "  Build:        $BUILD_DIR"
echo "  Executavel:   $EXE"
echo "  Configuracao: Release, PSX_DEBUG_TOOLS=OFF, runtime estatico"
echo "  Funcoes:      $function_count"
echo
echo "Abra o executavel manualmente para a validacao de regressao."
