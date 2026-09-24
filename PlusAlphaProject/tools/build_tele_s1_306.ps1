# build_tele_s1_306.ps1
# Automacao de compilacao da build isolada de telemetria buildTele-s1-306
[CmdletBinding()]
param(
    [string]$BuildDirName = "buildTele-s1-306",
    [string]$Msys2Root = "C:\msys64"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$BuildDir = Join-Path $ProjectRoot $BuildDirName
$TargetExe = Join-Path $BuildDir "exPlusAlpha.exe"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "     COMPILACAO DA BUILD DE TELEMETRIA - MICRO-LOTE S1-306            " -ForegroundColor Cyan
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

# Preservar e propagar o cache existente de DLLs do Track 2 se disponivel
$SourceCache = Join-Path $ProjectRoot "buildTele-s1-304\cache"
$DestCache = Join-Path $BuildDir "cache"
if ((Test-Path $SourceCache) -and (-not (Test-Path $DestCache))) {
    Write-Host "[0/4] Propagando cache de overlays do Track 2 (1.943 DLLs)..." -ForegroundColor Green
    Copy-Item -Path $SourceCache -Destination $DestCache -Recurse -Force
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
    throw "Configuracao do CMake falhou com codigo $LASTEXITCODE"
}

# 2. Compilar
Write-Host "[2/4] Compilando binarios com Ninja..." -ForegroundColor Green
& $Ninja -C $BuildDir
if ($LASTEXITCODE -ne 0) {
    throw "Compilacao falhou com codigo $LASTEXITCODE"
}

# 3. Validar se o executavel foi gerado
Write-Host "[3/4] Validando binario final..." -ForegroundColor Green
if (-not (Test-Path $TargetExe)) {
    throw "Executavel exPlusAlpha.exe nao foi encontrado em $BuildDir"
}
$exeItem = Get-Item $TargetExe
$exeSizeMb = [math]::Round($exeItem.Length / 1MB, 2)
Write-Host "[OK] Executavel gerado com sucesso: $TargetExe ($exeSizeMb MB)" -ForegroundColor Green

# 4. Atualizar wrapper de telemetria
Write-Host "[4/4] Atualizando run_gameplay_telemetry.ps1 para apontar para $BuildDirName..." -ForegroundColor Green
$RunScript = Join-Path $ScriptDir "run_gameplay_telemetry.ps1"
if (Test-Path $RunScript) {
    $content = Get-Content $RunScript -Raw
    $content = $content -replace 'buildTele-s1-\d+', $BuildDirName
    Set-Content -Path $RunScript -Value $content -NoNewline
    Write-Host "[OK] run_gameplay_telemetry.ps1 atualizado." -ForegroundColor Green
}

Write-Host "======================================================================" -ForegroundColor Green
Write-Host " Build de Telemetria S1-306 concluida com SUCESSO!                    " -ForegroundColor Green
Write-Host " Binario pronto para teste: $TargetExe                                " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
