#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly OBSERVER_PY="$SCRIPT_DIR/observe_boot_to_charselect.py"

fail() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

validate_env() {
    [[ "${MSYSTEM:-}" == "UCRT64" ]] ||
        printf 'AVISO: Recomendado executar no MSYS2 UCRT64. MSYSTEM=%s\n' "${MSYSTEM:-indefinido}" >&2

    if command -v python >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3)"
    else
        fail "Python nao encontrado. Instale ou configure o Python no PATH."
    fi

    [[ -f "$OBSERVER_PY" ]] || fail "Script Python ausente: $OBSERVER_PY"
}

validate_env
export PYTHONUNBUFFERED=1
exec "$PYTHON_BIN" -u "$OBSERVER_PY" "$@"
