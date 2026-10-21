# Posicionamento pontual das janelas existentes; nao altera configuracao do jogo.
[CmdletBinding()]
param(
    [string]$FirstDir = 'G:\sfPlus\onlineDiag1',
    [string]$SecondDir = 'G:\sfPlus\onlineDiag2',
    [ValidateRange(0,16)][int]$Monitor = 0,
    [switch]$Swap,
    [switch]$Fit,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$LayoutArgs = @('-B', (Join-Path $PSScriptRoot 'position_netplay_windows.py'),
    '--first-exe', (Join-Path (Resolve-Path -LiteralPath $FirstDir).Path 'exPlusAlpha.exe'),
    '--second-exe', (Join-Path (Resolve-Path -LiteralPath $SecondDir).Path 'exPlusAlpha.exe'),
    '--monitor', $Monitor)
if ($Swap) { $LayoutArgs += '--swap' }
if ($Fit) { $LayoutArgs += '--fit' }
if ($DryRun) { $LayoutArgs += '--dry-run' }
& (Get-Command python -ErrorAction Stop).Source @LayoutArgs
if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel posicionar as duas janelas. Consulte a mensagem acima.' }
