# build_tele_s1_279.ps1
# Automacao de compilacao da build isolada de telemetria buildTele-s1-279
[CmdletBinding()]
param(
    [string]$BuildDirName = "buildTele-s1-279",
    [string]$Msys2Root = "C:\msys64"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$BuildDir = Join-Path $ProjectRoot $BuildDirName
$TargetExe = Join-Path $BuildDir "exPlusAlpha.exe"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "     COMPILACAO DA BUILD DE TELEMETRIA - MICRO-LOTE S1-279            " -ForegroundColor Cyan
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
    throw "Falha na configuracao do CMake."
}

# 2. Compilar
Write-Host "[2/4] Compilando executavel de telemetria com Ninja..." -ForegroundColor Green
& $Ninja -C $BuildDir
if ($LASTEXITCODE -ne 0) {
    throw "Falha na compilacao Ninja."
}

# 3. Copiar assets/DLLs necessarias
Write-Host "[3/4] Sincronizando DLLs de runtime necessarias..." -ForegroundColor Green
$RefDir = Join-Path $ProjectRoot "buildTele-s1-278"
if (-not (Test-Path $RefDir)) {
    $RefDir = Join-Path $ProjectRoot "buildTele-s1-277"
}
if (Test-Path $RefDir) {
    Get-ChildItem -Path $RefDir -Filter "*.dll" | ForEach-Object {
        $dest = Join-Path $BuildDir $_.Name
        if (-not (Test-Path $dest)) {
            Copy-Item -Path $_.FullName -Destination $dest -Force
        }
    }
}

# 4. Validar binario resultante
Write-Host "[4/4] Validando integridade do binario..." -ForegroundColor Green
if (-not (Test-Path $TargetExe)) {
    throw "Executavel final nao foi encontrado em: $TargetExe"
}

$exeSize = (Get-Item $TargetExe).Length / 1MB
Write-Host ("Sucesso! Executavel gerado: {0} ({1:N2} MB)" -f $TargetExe, $exeSize) -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
Write-Host " Build de Telemetria S1-279 pronta para execucao.                     " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
