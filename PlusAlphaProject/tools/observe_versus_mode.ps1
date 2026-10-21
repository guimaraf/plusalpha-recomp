# Apenas observacao. Nao compila, pausa, encerra nem injeta input no jogo.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Label,
    [ValidateRange(1,65535)][int]$Port = 4533,
    [ValidateRange(1,3600)][int]$Seconds = 180,
    [string]$Output = '',
    [string]$GameDir = '',
    [switch]$Launch
)
$ErrorActionPreference = 'Stop'
if (-not $Output) {
    $Output = Join-Path $PSScriptRoot ('..\captures\versus-mode-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (Test-Path -LiteralPath $Output) { throw "Captura existente preservada: $Output" }
$Executable = ''
if ($GameDir) {
    $GameDir = (Resolve-Path -LiteralPath $GameDir).Path
    $Executable = Join-Path $GameDir 'exPlusAlpha.exe'
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'Executavel ausente.' }
}
if ($Launch) {
    if (-not $Executable) { throw '-Launch requer -GameDir de uma instancia dedicada.' }
    $Probe = [System.Net.Sockets.TcpClient]::new()
    try {
        try { $null = $Probe.ConnectAsync('127.0.0.1', $Port).Wait(500) } catch {}
        if ($Probe.Connected) { throw "Porta $Port ocupada; instancia existente preservada." }
    } finally { $Probe.Dispose() }
    $PreviousRanges = $env:PSX_WTRACE_BOOT_RANGES
    try {
        $env:PSX_WTRACE_BOOT_RANGES = '0x1d39b8-0x1d39d8,0x1dc9d0-0x1dca10'
        $GameProcess = Start-Process -FilePath $Executable -WorkingDirectory $GameDir -ArgumentList '--debug-port', $Port -PassThru
    } finally { $env:PSX_WTRACE_BOOT_RANGES = $PreviousRanges }
    $Deadline = [DateTime]::UtcNow.AddSeconds(45)
    $Ready = $false
    while (-not $Ready -and [DateTime]::UtcNow -lt $Deadline) {
        if ($GameProcess.HasExited) { throw 'A instancia dedicada encerrou antes de abrir o diagnostico.' }
        $Probe = [System.Net.Sockets.TcpClient]::new()
        try {
            try { $null = $Probe.ConnectAsync('127.0.0.1', $Port).Wait(300) } catch {}
            $Ready = $Probe.Connected
        } finally { $Probe.Dispose() }
        if (-not $Ready) { Start-Sleep -Milliseconds 500 }
    }
    if (-not $Ready) { throw 'Diagnostico indisponivel apos 45 s. Verifique a janela do jogo; ela foi preservada.' }
}
$CaptureArgs = @('-B', '-u', (Join-Path $PSScriptRoot 'observe_versus_mode.py'), 'capture',
    '--label', $Label, '--port', $Port, '--seconds', $Seconds, '--output', $Output)
if ($Executable) { $CaptureArgs += @('--exe', $Executable) }
& (Get-Command python -ErrorAction Stop).Source @CaptureArgs
if ($LASTEXITCODE -ne 0) { throw "Captura incompleta: codigo $LASTEXITCODE. Dados preservados em $Output" }
