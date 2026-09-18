# build_tele_s1_271.ps1
# Automacao de compilacao da build isolada de telemetria buildTele-s1-271
[CmdletBinding()]
param(
    [string]$BuildDirName = "buildTele-s1-271",
    [string]$Msys2Root = "C:\msys64"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$BuildDir = Join-Path $ProjectRoot $BuildDirName
$TargetExe = Join-Path $BuildDir "exPlusAlpha.exe"
$RefCleanDir = Join-Path $ProjectRoot "buildClean-ucrt-s1-268"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "     COMPILACAO DA BUILD DE TELEMETRIA - MICRO-LOTE S1-271            " -ForegroundColor Cyan
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
foreach ($dir in @("fonts", "img")) {
    $srcDir = Join-Path $canonicalAssets $dir
    if (Test-Path $srcDir) {
        Copy-Item -Path $srcDir -Destination $BuildDir -Recurse -Force
    } elseif (Test-Path (Join-Path $RefCleanDir $dir)) {
        Copy-Item -Path (Join-Path $RefCleanDir $dir) -Destination $BuildDir -Recurse -Force
    }
}

$projectFiles = @("game.toml", "overlay_captures.json")
foreach ($file in $projectFiles) {
    $src = Join-Path $ProjectRoot $file
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $BuildDir $file) -Force
    }
}

$cleanFiles = @("settings.toml", "keybinds.ini", "input.ini", "game_core.dll")
foreach ($file in $cleanFiles) {
    $src = Join-Path $RefCleanDir $file
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $BuildDir $file) -Force
    }
}

# 5. Criar script de inicializacao rapida local
$runBatContent = @"
@echo off
setlocal
cd /d "%~dp0"
echo ======================================================================
echo   Iniciando Street Fighter EX Plus Alpha [buildTele-s1-270]
echo   Telemetria ativa na porta TCP 4531 (observe_gameplay.py)
echo ======================================================================
if exist "..\disc-a\Street Fighter EX Plus Alpha (USA).cue" (
    "exPlusAlpha.exe" --game "game.toml" --disc "..\disc-a\Street Fighter EX Plus Alpha (USA).cue"
) else (
    "exPlusAlpha.exe" --game "game.toml"
)
"@
Set-Content -Path (Join-Path $BuildDir "run_telemetry.bat") -Value $runBatContent -Encoding ASCII
Write-Host "    [+] Script run_telemetry.bat gerado na raiz da build" -ForegroundColor Gray

$exeSize = (Get-Item $TargetExe).Length
Write-Host ""
Write-Host "======================================================================" -ForegroundColor Green
Write-Host "  [+] BUILD TELEMETRIA S1-270 (F1) GERADA COM SUCESSO!" -ForegroundColor Green
Write-Host "  Executavel : $TargetExe" -ForegroundColor White
Write-Host "  Tamanho    : $exeSize bytes" -ForegroundColor White
Write-Host "  Cache      : $cacheDir" -ForegroundColor White
Write-Host "======================================================================" -ForegroundColor Green
