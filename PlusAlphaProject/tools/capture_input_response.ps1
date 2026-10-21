# Consulta a build de diagnostico ja aberta. Nao compila nem injeta input.
[CmdletBinding()]
param(
    [ValidateSet('discovery', 'measure')][string]$Mode = 'measure',
    [Parameter(Mandatory=$true)]
    [ValidateSet('square','triangle','circle','cross','l1','r1','l2','r2')][string]$Button,
    [ValidateSet(1,2)][int]$Player = 1,
    [ValidateRange(1,65535)][int]$Port = 4531,
    [string]$Profile = '',
    [string]$Output = '',
    [switch]$CollectOnly,
    [switch]$Timing
)
$ErrorActionPreference = 'Stop'
if ($Mode -eq 'measure' -and -not $Profile) {
    $Profile = Join-Path $PSScriptRoot 'input_response_ryu_p1_square.json'
}
if (-not $Output) {
    $Output = Join-Path $PSScriptRoot ('..\captures\input-response-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$CaptureArgs = @('-B', '-u', (Join-Path $PSScriptRoot 'capture_input_response.py'),
    '--mode', $Mode, '--button', $Button, '--player', $Player, '--port', $Port,
    '--warmup', 5, '--seconds', 5, '--output', $Output)
if ($CollectOnly) { $CaptureArgs += '--collect-only' }
if ($Timing) { $CaptureArgs += '--timing' }
if ($Profile) { $CaptureArgs += @('--profile', $Profile) }
& (Get-Command python -ErrorAction Stop).Source @CaptureArgs
if ($LASTEXITCODE -ne 0) { throw "Captura incompleta ou invalida: codigo $LASTEXITCODE" }
