$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$GameToml = Join-Path $ProjectRoot "game.toml"
$CuePath = Join-Path $ProjectRoot "disc-a\Street Fighter EX Plus Alpha (USA).cue"
$ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308-f2\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-308\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "build-telemetry\StreetFighterEXPlusAlphaRecomp.exe"
}

if (-not (Test-Path $ExePath)) {
    throw "Executavel de telemetria nao encontrado em: $ExePath"
}

Push-Location $ProjectRoot
try {
    Write-Host "Iniciando Street Fighter EX Plus Alpha (Telemetria Port 4531)..." -ForegroundColor Cyan
    if (Test-Path $CuePath) {
        & $ExePath --game $GameToml --disc $CuePath
    } else {
        & $ExePath --game $GameToml
    }
}
finally {
    Pop-Location
}
