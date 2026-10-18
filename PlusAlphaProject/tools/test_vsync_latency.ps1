# Consulta apenas o jogo ja aberto; nao compila, inicia o jogo ou altera settings.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Immediate', 'VSync', 'Adaptive')]
    [string]$Mode,
    [ValidateRange(10, 600)]
    [int]$Seconds = 60,
    [ValidateRange(5, 120)]
    [int]$Warmup = 10,
    [ValidateRange(1, 100)]
    [int]$Repetition = 1,
    [string]$BuildDir = (Join-Path $PSScriptRoot '..\buildTele-s1-309-bezeus')
)

$ErrorActionPreference = 'Stop'
$Python = (Get-Command python -ErrorAction Stop).Source
$Collector = Join-Path $PSScriptRoot 'test_vsync_latency.py'
& $Python -u $Collector --mode $Mode.ToLowerInvariant() --build-dir $BuildDir `
    --seconds $Seconds --warmup $Warmup --repetition $Repetition
if ($LASTEXITCODE -ne 0) { throw "Coleta de latencia falhou: codigo $LASTEXITCODE" }
