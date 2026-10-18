# Inicializacao manual da base de telemetria; nao compila nem gera fontes.
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$BuildDir = Join-Path $ProjectRoot "buildTele-s1-309-fps"
$GameToml = Join-Path $BuildDir "game.toml"
$CuePath = Join-Path $ProjectRoot "disc-a\Street Fighter EX Plus Alpha (USA).cue"
$ExePath = Join-Path $BuildDir "exPlusAlpha.exe"
foreach ($RequiredPath in @($ExePath, $GameToml)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Arquivo da base de telemetria ausente: $RequiredPath"
    }
}

# Mantem o diretorio de trabalho do projeto para os assets relativos do game.toml.
# O runtime ancora settings e capturas na pasta do executavel.
Push-Location $ProjectRoot
try {
    Write-Host "Base de telemetria: $BuildDir" -ForegroundColor Cyan
    Write-Host "Configuracao: $GameToml"
    if (Test-Path -LiteralPath $CuePath -PathType Leaf) {
        & $ExePath --game $GameToml --disc $CuePath
    } else {
        & $ExePath --game $GameToml
    }
}
finally {
    Pop-Location
}
