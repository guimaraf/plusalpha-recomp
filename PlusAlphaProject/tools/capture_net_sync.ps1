# Coleta somente leitura. -Launch abre as duas copias com o historico ativado.
[CmdletBinding()]
param(
    [switch]$Launch,
    [switch]$LaunchOnly,
    [ValidatePattern('^[A-Za-z0-9_-]{1,32}$')][string]$Label = 'T01',
    [ValidateSet('FirstThenSecond','SecondThenFirst')][string]$OpenOrder = 'FirstThenSecond',
    [string]$FirstDir = 'G:\sfPlus\onlineDiag1',
    [string]$SecondDir = 'G:\sfPlus\onlineDiag2',
    [ValidateRange(1,65535)][int]$FirstPort = 4531,
    [ValidateRange(1,65535)][int]$SecondPort = 4532,
    [ValidateRange(10,3600)][int]$Seconds = 300,
    [string]$Output = ''
)
$ErrorActionPreference = 'Stop'
if ($FirstPort -eq $SecondPort) { throw 'As portas devem ser diferentes.' }
if ($LaunchOnly -and -not $Launch) { throw '-LaunchOnly requer -Launch.' }
$Python = (Get-Command python -ErrorAction Stop).Source
if (-not $Output) {
    $Output = Join-Path $PSScriptRoot ('..\captures\net-sync-' + $Label + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (Test-Path -LiteralPath $Output) { throw "Pasta existente preservada: $Output" }
if ($Launch) {
    $FirstExe = Join-Path (Resolve-Path -LiteralPath $FirstDir).Path 'exPlusAlpha.exe'
    $SecondExe = Join-Path (Resolve-Path -LiteralPath $SecondDir).Path 'exPlusAlpha.exe'
    $FirstHash = (Get-FileHash -LiteralPath $FirstExe -Algorithm SHA256).Hash
    $SecondHash = (Get-FileHash -LiteralPath $SecondExe -Algorithm SHA256).Hash
    if ($FirstHash -ne $SecondHash) { throw 'As duas copias do executavel sao diferentes.' }
    foreach ($Port in @($FirstPort, $SecondPort)) {
        $Probe = [System.Net.Sockets.TcpClient]::new()
        try {
            $Attempt = $Probe.ConnectAsync('127.0.0.1', $Port)
            try { $null = $Attempt.Wait(500) } catch {}
            if ($Probe.Connected) { throw "Porta $Port ocupada. Feche a instancia antiga antes de iniciar este teste." }
        } finally { $Probe.Dispose() }
    }
    $OldTrace = $env:PSX_NET_SYNC_TRACE
    $OldToggles = $env:PSX_DEBUG_TOGGLES
    try {
        $env:PSX_NET_SYNC_TRACE = '1'
        $env:PSX_DEBUG_TOGGLES = '0'
        if ($OpenOrder -eq 'SecondThenFirst') {
            Start-Process -FilePath $SecondExe -WorkingDirectory $SecondDir -ArgumentList '--debug-port', $SecondPort
            Start-Process -FilePath $FirstExe -WorkingDirectory $FirstDir -ArgumentList '--debug-port', $FirstPort
        } else {
            Start-Process -FilePath $FirstExe -WorkingDirectory $FirstDir -ArgumentList '--debug-port', $FirstPort
            Start-Process -FilePath $SecondExe -WorkingDirectory $SecondDir -ArgumentList '--debug-port', $SecondPort
        }
    } finally {
        $env:PSX_NET_SYNC_TRACE = $OldTrace
        $env:PSX_DEBUG_TOGGLES = $OldToggles
    }
    Write-Host "SHA256 das duas copias: $FirstHash"
}
if ($LaunchOnly) {
    Write-Host 'Instancias abertas com historico ativo. Prepare o versus antes de iniciar test_net_sync_drag.ps1.'
    return
}
$CaptureArgs = @('-B', '-u', (Join-Path $PSScriptRoot 'capture_net_sync.py'),
    '--ports', $FirstPort, $SecondPort, '--seconds', $Seconds, '--output', $Output,
    '--label', $Label, '--open-order', $OpenOrder)
if ($Launch) { $CaptureArgs += @('--executables', $FirstExe, $SecondExe) }
Write-Host 'Aguarde a confirmacao de captura nas DUAS portas antes de criar a sala.'
Write-Host "Pasta desta captura: $Output"
Write-Host 'Em outro PowerShell, execute tools\mark_net_sync.ps1 para marcar as etapas.'
& $Python @CaptureArgs
if ($LASTEXITCODE -ne 0) { throw "Captura incompleta. Consulte os arquivos em $Output" }
