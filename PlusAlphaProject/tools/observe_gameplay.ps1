param(
    [int]$Port = 0
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$ObserverPy = Join-Path $ScriptDir "observe_gameplay.py"

if (-not (Test-Path $ObserverPy)) {
    throw "Script Python ausente: $ObserverPy"
}

$PythonBin = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $PythonBin) {
    $PythonBin = (Get-Command python3 -ErrorAction SilentlyContinue).Source
}
if (-not $PythonBin) {
    throw "Python nao encontrado no PATH."
}

$env:PYTHONUNBUFFERED = "1"

if ($Port -gt 0) {
    & $PythonBin -u $ObserverPy --port=$Port
} else {
    & $PythonBin -u $ObserverPy
}
