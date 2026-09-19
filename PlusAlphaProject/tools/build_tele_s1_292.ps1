# build_tele_s1_292.ps1
# Automacao de compilacao da build isolada de telemetria buildTele-s1-292
[CmdletBinding()]
param(
    [string]$BuildDirName = "buildTele-s1-292",
    [string]$Msys2Root = "C:\msys64"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$BuildDir = Join-Path $ProjectRoot $BuildDirName
$TargetExe = Join-Path $BuildDir "exPlusAlpha.exe"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "     COMPILACAO DA BUILD DE TELEMETRIA - MICRO-LOTE S1-292            " -ForegroundColor Cyan
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

& $CMake $cmakeArgs
if ($LASTEXITCODE -ne 0) {
    throw "Configuracao do CMake falhou com codigo $LASTEXITCODE"
}

# 2. Compilar
Write-Host "[2/4] Compilando binario com Ninja..." -ForegroundColor Green
& $Ninja -C $BuildDir
if ($LASTEXITCODE -ne 0) {
    throw "Compilacao via Ninja falhou com codigo $LASTEXITCODE"
}

# 3. Validar se o executavel foi gerado
Write-Host "[3/4] Validando executavel gerado..." -ForegroundColor Green
if (-not (Test-Path $TargetExe)) {
    throw "Executavel esperado nao foi encontrado em: $TargetExe"
}

$exeItem = Get-Item $TargetExe
Write-Host "Executavel gerado com sucesso: $($exeItem.FullName) ($([math]::Round($exeItem.Length / 1MB, 2)) MB)" -ForegroundColor Green

# 4. Copiar dependencias de runtime caso necessario
Write-Host "[4/4] Verificando dependencias SDL2..." -ForegroundColor Green
$sdlDll = Join-Path $ProjectRoot "SDL2.dll"
if (Test-Path $sdlDll) {
    Copy-Item -Path $sdlDll -Destination $BuildDir -Force
}

Write-Host "======================================================================" -ForegroundColor Green
Write-Host " Build de telemetria S1-292 concluida e pronta para testes!           " -ForegroundColor Green
Write-Host " Executavel: $TargetExe" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Green
