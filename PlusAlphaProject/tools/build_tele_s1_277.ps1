# build_tele_s1_277.ps1
# Automacao de compilacao da build isolada de telemetria buildTele-s1-277
[CmdletBinding()]
param(
    [string]$BuildDirName = "buildTele-s1-277",
    [string]$Msys2Root = "C:\msys64"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$BuildDir = Join-Path $ProjectRoot $BuildDirName
$TargetExe = Join-Path $BuildDir "exPlusAlpha.exe"
$RefCleanDir = Join-Path $ProjectRoot "buildClean-ucrt-s1-268"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "     COMPILACAO DA BUILD DE TELEMETRIA - MICRO-LOTE S1-277            " -ForegroundColor Cyan
Write-Host "  Alvo:                 $BuildDirName" -ForegroundColor Yellow
Write-Host "  Perfil:               RelWithDebInfo (-O2 -g -DNDEBUG)" -ForegroundColor Yellow
Write-Host "  Telemetria / Debug:   PSX_DEBUG_TOOLS=ON (Off-Thread I/O Handoff)" -ForegroundColor Yellow
Write-Host "  Runtime Estatico:     PSX_STATIC_RUNTIME=ON" -ForegroundColor Yellow
Write-Host "  Launcher UI:          PSX_LAUNCHER=ON" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan

# Detectar toolchain MSYS2 UCRT64
$UcrtBin = Join-Path $Msys2Root "ucrt64\bin"
if (Test-Path $UcrtBin) {
    $env:PATH = "$UcrtBin;$env:PATH"
    $CCompiler = Join-Path $UcrtBin "gcc.exe"
    $CxxCompiler = Join-Path $UcrtBin "c++.exe"
    $Ninja = Join-Path $UcrtBin "ninja.exe"
    $PkgConfig = Join-Path $UcrtBin "pkg-config.exe"
    $CMake = Join-Path $UcrtBin "cmake.exe"
} else {
    $CCompiler = (Get-Command gcc.exe -ErrorAction SilentlyContinue).Source
    $CxxCompiler = (Get-Command c++.exe -ErrorAction SilentlyContinue).Source
    $Ninja = (Get-Command ninja.exe -ErrorAction SilentlyContinue).Source
    $PkgConfig = (Get-Command pkg-config.exe -ErrorAction SilentlyContinue).Source
    $CMake = (Get-Command cmake.exe -ErrorAction SilentlyContinue).Source
}

if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
}

# 1. Configurar CMake
Write-Host "[1/4] Configurando diretorio de build com CMake Ninja..." -ForegroundColor Green
$cmakeArgs = @(
    "-B", $BuildDir,
    "-S", $ProjectRoot,
    "-G", "Ninja",
    "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
    "-DPSX_DEBUG_TOOLS=ON",
    "-DPSX_STATIC_RUNTIME=ON",
    "-DPSX_LAUNCHER=ON",
    "-DCMAKE_C_COMPILER:FILEPATH=$CCompiler",
    "-DCMAKE_CXX_COMPILER:FILEPATH=$CxxCompiler",
    "-DCMAKE_MAKE_PROGRAM:FILEPATH=$Ninja",
    "-DPKG_CONFIG_EXECUTABLE:FILEPATH=$PkgConfig"
)

& $CMake @cmakeArgs
if ($LASTEXITCODE -ne 0) {
    throw "Falha na configuracao do CMake (exit code $LASTEXITCODE)"
}

# 2. Compilar psx-runtime
Write-Host "[2/4] Compilando target psx-runtime com Ninja..." -ForegroundColor Green
& $CMake --build $BuildDir --target psx-runtime
if ($LASTEXITCODE -ne 0) {
    throw "Falha na compilacao de psx-runtime com Ninja (exit code $LASTEXITCODE)"
}

if (-not (Test-Path $TargetExe)) {
    throw "Executavel nao foi produzido em: $TargetExe"
}

# 3. Sincronizar Cache de Overlays
Write-Host "[3/4] Sincronizando e populando hierarquia de Cache de Overlays..." -ForegroundColor Green
$cacheDir = Join-Path $BuildDir "cache"
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

$refCache = Join-Path $RefCleanDir "cache"
if (Test-Path $refCache) {
    Copy-Item -Path (Join-Path $refCache "*") -Destination $cacheDir -Recurse -Force
    Write-Host "    [+] Cache clonado a partir de: $refCache" -ForegroundColor Gray
}

# 4. Copiar arquivos de configuracao, UI e assets visuais
Write-Host "[4/4] Copiando arquivos de configuracao, UI e assets visuais..." -ForegroundColor Green
$canonicalLauncherRml = Join-Path $ProjectRoot "..\psxrecomp\runtime\launcher\assets\launcher.rml"
if (Test-Path $canonicalLauncherRml) {
    Copy-Item -Path $canonicalLauncherRml -Destination (Join-Path $BuildDir "launcher.rml") -Force
    Write-Host "    [+] launcher.rml canonico copiado" -ForegroundColor Gray
} elseif (Test-Path (Join-Path $RefCleanDir "launcher.rml")) {
    Copy-Item -Path (Join-Path $RefCleanDir "launcher.rml") -Destination (Join-Path $BuildDir "launcher.rml") -Force
}

$canonicalAssets = Join-Path $ProjectRoot "..\psxrecomp\runtime\launcher\assets"
if (Test-Path $canonicalAssets) {
    Copy-Item -Path (Join-Path $canonicalAssets "*") -Destination $BuildDir -Recurse -Force
    Write-Host "    [+] Assets visuais canonicos copiados" -ForegroundColor Gray
}

$refIni = Join-Path $RefCleanDir "game_controller.ini"
if (Test-Path $refIni) {
    Copy-Item -Path $refIni -Destination (Join-Path $BuildDir "game_controller.ini") -Force
}

Write-Host ""
Write-Host "[+] BUILD DE TELEMETRIA S1-277 PRONTA EM: $TargetExe" -ForegroundColor Cyan
