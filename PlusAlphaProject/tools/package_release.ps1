# package_release.ps1
# Automacao de empacotamento da release desacoplada (Clean-Room Distribution)
[CmdletBinding()]
param(
    [string]$OutputDirName = "buildNoCopyright-s1-268",
    [string]$Msys2Root = "C:\msys64"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$OutDir = Join-Path $ProjectRoot $OutputDirName
$BuildLauncherDir = Join-Path $ProjectRoot "buildLauncher"
$LauncherExe = Join-Path $BuildLauncherDir "StreetFighterEXPlusAlpha_Launcher.exe"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "   EMPACOTAMENTO DO BUNDLE LIMPO DESACOPLADO (CLEAN-ROOM RELEASE)     " -ForegroundColor Cyan
Write-Host "  Alvo:      $OutputDirName" -ForegroundColor Yellow
Write-Host "  Origem:    $BuildLauncherDir" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan

if (-not (Test-Path $LauncherExe)) {
    throw "Executavel do launcher nao encontrado em: $LauncherExe. Execute tools\build_clean_launcher.ps1 primeiro."
}

# 1. Limpar pacote anterior
Write-Host "[1/5] Preparando diretorio de release limpo..." -ForegroundColor Green
if (Test-Path $OutDir) {
    Remove-Item -Path $OutDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutDir "compileBuild") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutDir "compileBuild\tools") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutDir "compileBuild\overlay_toolchain") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutDir "compileBuild\psxrecomp\runtime\include") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutDir "compileBuild\psxrecomp\tools") -Force | Out-Null

# 2. Copiar executavel e dependencias
Write-Host "[2/5] Copiando executavel e dependencias Win32..." -ForegroundColor Green
$targetExe = Join-Path $OutDir "StreetFighterEXPlusAlpha_Launcher.exe"
Copy-Item $LauncherExe $targetExe -Force

foreach ($dll in @("SDL2.dll", "libgcc_s_seh-1.dll", "libwinpthread-1.dll", "libstdc++-6.dll")) {
    $srcDll = Join-Path $BuildLauncherDir $dll
    if (Test-Path $srcDll) {
        Copy-Item $srcDll (Join-Path $OutDir $dll) -Force
    }
}

# Strip debug symbols
$strip = (Get-Command strip.exe -ErrorAction SilentlyContinue).Source
if (-not $strip) {
    $ucrtStrip = Join-Path $Msys2Root "ucrt64\bin\strip.exe"
    if (Test-Path $ucrtStrip) { $strip = $ucrtStrip }
}
if ($strip) {
    Write-Host "    [+] Removendo simbolos de debug (strip)..." -ForegroundColor Gray
    & $strip $targetExe
}

# 3. Copiar assets da interface e configuracoes
Write-Host "[3/5] Copiando configuracoes e assets visuais..." -ForegroundColor Green
Copy-Item (Join-Path $ProjectRoot "game.toml") (Join-Path $OutDir "game.toml") -Force
if (Test-Path (Join-Path $ProjectRoot "settings.toml")) {
    Copy-Item (Join-Path $ProjectRoot "settings.toml") (Join-Path $OutDir "settings.toml") -Force
}
if (Test-Path (Join-Path $ProjectRoot "keybinds.ini")) {
    Copy-Item (Join-Path $ProjectRoot "keybinds.ini") (Join-Path $OutDir "keybinds.ini") -Force
}
if (Test-Path (Join-Path $ProjectRoot "input.ini")) {
    Copy-Item (Join-Path $ProjectRoot "input.ini") (Join-Path $OutDir "input.ini") -Force
}

$captures = Join-Path $ProjectRoot "overlay_captures.json"
if (-not (Test-Path $captures)) {
    $captures = Join-Path $ProjectRoot "buildClean-ucrt-s1-268\overlay_captures.json"
}
if (Test-Path $captures) {
    Copy-Item $captures (Join-Path $OutDir "compileBuild\overlay_captures.json") -Force
}

Copy-Item (Join-Path $BuildLauncherDir "launcher.rml") (Join-Path $OutDir "launcher.rml") -Force
if (Test-Path (Join-Path $BuildLauncherDir "launcher.rcss")) {
    Copy-Item (Join-Path $BuildLauncherDir "launcher.rcss") (Join-Path $OutDir "launcher.rcss") -Force
}
if (Test-Path (Join-Path $BuildLauncherDir "fonts")) {
    Copy-Item (Join-Path $BuildLauncherDir "fonts") (Join-Path $OutDir "fonts") -Recurse -Force
}
if (Test-Path (Join-Path $BuildLauncherDir "img")) {
    Copy-Item (Join-Path $BuildLauncherDir "img") (Join-Path $OutDir "img") -Recurse -Force
}

# 4. Copiar toolchain e scripts em compileBuild
Write-Host "[4/5] Copiando toolchain portatil e scripts de build para compileBuild..." -ForegroundColor Green
Copy-Item (Join-Path $ProjectRoot "overlay_toolchain\*") (Join-Path $OutDir "compileBuild\overlay_toolchain") -Recurse -Force

Copy-Item (Join-Path $ProjectRoot "tools\compile_game_core.bat") (Join-Path $OutDir "compileBuild\tools\compile_game_core.bat") -Force
Copy-Item (Join-Path $ProjectRoot "tools\compile_tcc_overlays.bat") (Join-Path $OutDir "compileBuild\tools\compile_tcc_overlays.bat") -Force
Copy-Item (Join-Path $ProjectRoot "tools\game_core_vars.c") (Join-Path $OutDir "compileBuild\tools\game_core_vars.c") -Force
Copy-Item (Join-Path $ProjectRoot "tools\launcher.def") (Join-Path $OutDir "compileBuild\tools\launcher.def") -Force

$incSrc = Join-Path $ProjectRoot "..\psxrecomp\runtime\include"
Copy-Item (Join-Path $incSrc "*") (Join-Path $OutDir "compileBuild\psxrecomp\runtime\include") -Recurse -Force

$scriptSrc = Join-Path $ProjectRoot "..\psxrecomp\tools\compile_overlays.py"
Copy-Item $scriptSrc (Join-Path $OutDir "compileBuild\psxrecomp\tools\compile_overlays.py") -Force

if (Test-Path (Join-Path $ProjectRoot "seeds")) {
    Copy-Item (Join-Path $ProjectRoot "seeds") (Join-Path $OutDir "compileBuild\seeds") -Recurse -Force
    Copy-Item (Join-Path $ProjectRoot "seeds") (Join-Path $OutDir "seeds") -Recurse -Force
}

# 5. Auditoria de pureza clean-room (0 bytes protegidos)
Write-Host "[5/5] Auditando pureza Clean-Room..." -ForegroundColor Green
$isDirty = $false

foreach ($badPath in @("local", "cache", "generated", "game_core.dll")) {
    if (Test-Path (Join-Path $OutDir $badPath)) {
        Write-Host "    [ERROR] Item proibido encontrado: $badPath" -ForegroundColor Red
        $isDirty = $true
    }
}

$discExts = @("*.bin", "*.cue", "*.iso", "*.img", "*.mdf", "*.sub", "*.ccd", "*.chd")
foreach ($ext in $discExts) {
    $found = Get-ChildItem -Path $OutDir -Filter $ext -Recurse -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "    [ERROR] Arquivo de imagem de disco proibido encontrado: $($found.Name)" -ForegroundColor Red
        $isDirty = $true
    }
}

$badSources = @("SLUS_005.48_full.c", "SLUS_005.48_dispatch.c")
foreach ($src in $badSources) {
    $found = Get-ChildItem -Path $OutDir -Filter $src -Recurse -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "    [ERROR] Arquivo de codigo recompiled proibido encontrado: $($found.Name)" -ForegroundColor Red
        $isDirty = $true
    }
}

if ($isDirty) {
    Remove-Item -Path $OutDir -Recurse -Force
    throw "Auditoria Clean-Room FALHOU! O pacote continha arquivos protegidos e foi removido."
}

$exeSizeMb = [math]::Round((Get-Item $targetExe).Length / 1MB, 2)
Write-Host "======================================================================" -ForegroundColor Green
Write-Host "  PACOTE CLEAN-ROOM GERADO COM SUCESSO!" -ForegroundColor Green
Write-Host "  Diretorio:   $OutDir" -ForegroundColor White
Write-Host "  Executavel:  StreetFighterEXPlusAlpha_Launcher.exe ($exeSizeMb MB)" -ForegroundColor White
Write-Host "  Integridade: 0 bytes proprietarios Capcom/Arika/Sony" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
