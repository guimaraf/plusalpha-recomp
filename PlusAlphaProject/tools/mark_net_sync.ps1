# Marcadores externos: nao conecta ao jogo, nao pausa e nao injeta input.
[CmdletBinding()]
param(
    [string]$CaptureDir = '',
    [ValidatePattern('^[A-Za-z0-9_-]{1,64}$')][string]$Label = '',
    [ValidateSet('begin','end','point')][string]$Edge = 'point',
    [string]$Note = ''
)
$ErrorActionPreference = 'Stop'
if (-not $CaptureDir) {
    $Captures = Join-Path $PSScriptRoot '..\captures'
    $Latest = Get-ChildItem -LiteralPath $Captures -Directory -Filter 'net-sync-*' |
        Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json')) -and
            -not (Test-Path -LiteralPath (Join-Path $_.FullName 'summary.json')) } |
        Sort-Object CreationTime -Descending | Select-Object -First 1
    if (-not $Latest) { throw 'Nenhuma captura em andamento. Informe -CaptureDir ou inicie a captura.' }
    $CaptureDir = $Latest.FullName
}
$CaptureDir = (Resolve-Path -LiteralPath $CaptureDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $CaptureDir 'manifest.json'))) {
    throw 'A pasta precisa conter manifest.json de uma captura.'
}
function Write-Marker([string]$MarkerLabel, [string]$MarkerEdge, [string]$MarkerNote) {
    if (Test-Path -LiteralPath (Join-Path $CaptureDir 'summary.json')) {
        throw 'A captura terminou. Inicie outra antes de continuar os marcadores.'
    }
    # Stopwatch uses QPC on Windows, the same clock as the SDL trace.
    $Stamp = [System.Diagnostics.Stopwatch]::GetTimestamp()
    $Data = [ordered]@{
        schema = 1
        utc = [DateTime]::UtcNow.ToString('o')
        qpc = $Stamp
        frequency = [System.Diagnostics.Stopwatch]::Frequency
        label = $MarkerLabel
        edge = $MarkerEdge
        note = $MarkerNote
        focus_note = 'Marker entered from PowerShell; focus may change around this point.'
    }
    $Line = ($Data | ConvertTo-Json -Compress) + [Environment]::NewLine
    $Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Line)
    $Path = Join-Path $CaptureDir 'markers.jsonl'
    $Stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append,
        [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try { $Stream.Write($Bytes, 0, $Bytes.Length) } finally { $Stream.Dispose() }
    Write-Host ("{0:HH:mm:ss}  {1}  {2}" -f (Get-Date), $MarkerLabel, $MarkerEdge) -ForegroundColor Green
}
Write-Host "Marcadores para: $CaptureDir"
if ($Label) {
    Write-Marker $Label $Edge $Note
    return
}
Write-Host 'Modo interativo. Cada etapa grava begin; ENTER grava end. Nenhuma tecla e enviada ao jogo.'
Write-Host 'Volte ao jogo para executar a etapa; deixe 5 s de margem por causa da troca de foco.'
$Stages = @{
    '1' = 'idle'; '2' = 'combat-p1'; '3' = 'combat-p2'; '4' = 'combat-both'
    '5' = 'drag-host'; '6' = 'drag-client'; '7' = 'focus-switch'; '8' = 'session'
}
while ($true) {
    Write-Host '1 parado | 2 combos P1 | 3 combos P2 | 4 ambos | 5 arrastar host | 6 arrastar cliente | 7 foco | 8 nova sessao | 9 sintoma | 0 sair'
    $Choice = Read-Host 'Etapa'
    if ($Choice -eq '0') { break }
    if ($Choice -eq '9') {
        $Text = Read-Host 'Sintoma observado (quem atrasou, golpe, audio etc.)'
        Write-Marker 'symptom' 'point' $Text
        continue
    }
    if (-not $Stages.ContainsKey($Choice)) { Write-Host 'Opcao invalida.'; continue }
    $Text = Read-Host 'Observacao (ex.: sala 2; host=4532; Ryu x Ken)'
    Write-Marker $Stages[$Choice] 'begin' $Text
    $null = Read-Host 'Execute a etapa no jogo e volte aqui. ENTER para marcar o fim'
    Write-Marker $Stages[$Choice] 'end' $Text
}
