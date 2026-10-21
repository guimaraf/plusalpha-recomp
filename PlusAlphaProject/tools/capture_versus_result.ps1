# Jogo ja aberto. Dez segundos de coleta; nunca compila ou injeta input.
[CmdletBinding()]
param(
    [ValidateRange(1,65535)][int]$Port = 4531,
    [ValidateSet('P1','P2','unknown')][string]$Winner = 'unknown',
    [ValidateSet('match','round')][string]$Kind = 'match',
    [string]$Output = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Output) {
    $Output = Join-Path $PSScriptRoot ('..\captures\versus-result-' + $Winner + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
}
if (Test-Path -LiteralPath $Output) { throw "Captura existente preservada: $Output" }
$Output = [System.IO.Path]::GetFullPath($Output)
$CaptureArgs = @('-B', '-u', (Join-Path $PSScriptRoot 'capture_versus_result.py'),
    '--port', $Port, '--winner', $Winner, '--kind', $Kind, '--output', $Output)
& (Get-Command python -ErrorAction Stop).Source @CaptureArgs
$CaptureExitCode = $LASTEXITCODE
$StatusPath = Join-Path $Output 'status.json'
if (Test-Path -LiteralPath $StatusPath) {
    $Status = Get-Content -LiteralPath $StatusPath -Raw | ConvertFrom-Json
    if ($Status.error) { Write-Warning ([string]$Status.error) }
    foreach ($Notice in $Status.warnings) { Write-Warning ([string]$Notice) }
}
if ($CaptureExitCode -eq 2) {
    Write-Warning 'Coleta encerrada com lacunas no historico. Os dados parciais foram preservados para analise.'
} elseif ($CaptureExitCode -ne 0) {
    Write-Warning "Falha na captura (codigo $CaptureExitCode). Consulte o relatorio acima."
}
$Archive = Get-ChildItem -LiteralPath $Output -Filter 'versus-result-*.zip' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($Archive) {
    Write-Host ('ARQUIVO PARA ANALISE: "{0}"' -f $Archive.FullName)
} else {
    Write-Host ('RELATORIO PARA ANALISE: "{0}"' -f $StatusPath)
}
$global:LASTEXITCODE = $CaptureExitCode
