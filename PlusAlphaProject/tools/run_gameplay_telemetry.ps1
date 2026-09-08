$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$ExePath = Join-Path $ProjectRoot "build-telemetry\StreetFighterEXPlusAlphaRecomp.exe"
$GameToml = Join-Path $ProjectRoot "game.toml"
$CuePath = Join-Path $ProjectRoot "disc-a\Street Fighter EX Plus Alpha (USA).cue"

if (-not (Test-Path $ExePath)) {
    throw "Executavel de telemetria nao encontrado em: $ExePath"
}

Push-Location $ProjectRoot
try {
    Write-Host "Iniciando Street Fighter EX Plus Alpha (Telemetria Port 4531)..." -ForegroundColor Cyan
    & $ExePath --game $GameToml --disc $CuePath
}
finally {
    Pop-Location
}
