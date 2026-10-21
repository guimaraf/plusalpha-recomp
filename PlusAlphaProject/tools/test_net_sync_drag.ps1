# Monitoramento curto das duas instancias ja abertas; nao controla as janelas.
[CmdletBinding()]
param(
    [ValidateSet('Host','Client','Both')][string]$Target = 'Both',
    [ValidateSet('HostFirst','ClientFirst')][string]$Order = 'HostFirst',
    [ValidateRange(5,30)][int]$DragSeconds = 15,
    [ValidateRange(10,60)][int]$RecoverySeconds = 20,
    [ValidateRange(5,30)][int]$BaselineSeconds = 10,
    [ValidateRange(1,65535)][int]$FirstPort = 4531,
    [ValidateRange(1,65535)][int]$SecondPort = 4532,
    [string]$Output = '',
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
if ($FirstPort -eq $SecondPort) { throw 'Use duas portas diferentes.' }
if (-not $Output) {
    $Output = Join-Path $PSScriptRoot ('..\captures\net-sync-drag-' + $Target.ToLower() + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (Test-Path -LiteralPath $Output) { throw "Pasta existente preservada: $Output" }
$CaptureArgs = @('-B', '-u', (Join-Path $PSScriptRoot 'capture_net_sync.py'),
    '--ports', $FirstPort, $SecondPort, '--output', $Output, '--label', 'drag-short',
    '--drag-test', $Target.ToLower(), '--drag-order', $Order,
    '--drag-seconds', $DragSeconds, '--recovery-seconds', $RecoverySeconds,
    '--baseline-seconds', $BaselineSeconds)
if (-not $Quiet) { $CaptureArgs += '--beep' }
Write-Host 'Deixe o versus online por IP direto pronto e as janelas lado a lado.'
Write-Host 'As duas instancias serao lidas; somente voce movimenta a janela indicada.'
& (Get-Command python -ErrorAction Stop).Source @CaptureArgs
if ($LASTEXITCODE -ne 0) { throw "Teste incompleto. Preserve os arquivos em $Output" }
