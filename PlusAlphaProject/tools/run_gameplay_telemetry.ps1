$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$GameToml = Join-Path $ProjectRoot "game.toml"
$CuePath = Join-Path $ProjectRoot "disc-a\Street Fighter EX Plus Alpha (USA).cue"
$ExePath = Join-Path $ProjectRoot "buildTele-s1-283\exPlusAlpha.exe"
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-282\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-281\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-280\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-279\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-278\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-277\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-276\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-275\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-274-f2\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-274\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-273\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-272\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-271\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-270\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-269\exPlusAlpha.exe"
}
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $ProjectRoot "buildTele-s1-268\exPlusAlpha.exe"
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
