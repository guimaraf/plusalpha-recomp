# Executar manualmente: este script gera fontes (com -Generate) e faz build local.
# Nunca reutiliza os diretorios de build ou caches S1-309.
[CmdletBinding()]
param(
    [switch]$Generate,
    [switch]$SetupHost,
    [string]$Msys2Root = 'C:\msys64',
    [ValidateSet('SDL3', 'SDL2')]
    [string]$SdlBackend = 'SDL3',
    [ValidateRange(1, 64)]
    [int]$Jobs = 4,
    [string]$BiosPath = '',
    [string]$StaticOverlayDir = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RepositoryRoot = Split-Path $ProjectRoot -Parent
$Framework = Join-Path $RepositoryRoot 'psxrecomp'
$BuildName = if ($SetupHost) { 'build-online-setup' } else { 'build-online' }
$BuildDir = Join-Path $ProjectRoot $BuildName
$UcrtBin = Join-Path $Msys2Root 'ucrt64\bin'
$CMake = Join-Path $UcrtBin 'cmake.exe'
$Python = (Get-Command python -ErrorAction Stop).Source
if ($BiosPath) {
    if (-not $Generate) { throw '-BiosPath requer -Generate.' }
    $BiosPath = (Resolve-Path -LiteralPath $BiosPath).Path
}
if ($StaticOverlayDir) {
    $StaticOverlayDir = (Resolve-Path -LiteralPath $StaticOverlayDir).Path
}

foreach ($Name in @('cmake.exe', 'gcc.exe', 'c++.exe', 'ninja.exe', 'windres.exe', 'pkg-config.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $UcrtBin $Name) -PathType Leaf)) {
        throw "Ferramenta ausente: $UcrtBin\$Name"
    }
}
foreach ($Relative in @('psxrecomp\lib\recomp-net\CMakeLists.txt',
                         'psxrecomp\lib\retcomm-rbengine\CMakeLists.txt',
                         'recomp-ui\recomp_ui.cmake')) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot $Relative) -PathType Leaf)) {
        throw 'Dependencias ausentes. Execute git submodule update --init --recursive na raiz do repositorio.'
    }
}
if ($SetupHost -and $StaticOverlayDir) {
    throw 'O setup host nao liga overlays estaticos; use -StaticOverlayDir somente no runtime completo.'
}
$OriginalPath = $env:PATH
try {
    $env:PATH = "$UcrtBin;$OriginalPath"
    Push-Location $ProjectRoot
    try {
        if ($Generate) {
            Write-Host 'Gerando fontes atuais. Esta etapa recompila os emitters locais do framework.' -ForegroundColor Cyan
            $GenerateArgs = @((Join-Path $Framework 'psxrecomp_cli.py'), 'generate',
                '--config', (Join-Path $ProjectRoot 'game.toml'), '--project-root', $ProjectRoot,
                '--disc', (Join-Path $ProjectRoot 'disc-a\Street Fighter EX Plus Alpha (USA).cue'),
                '--force-emitters', '--force-bios')
            if ($BiosPath) {
                $GenerateArgs += @('--bios', $BiosPath)
            }
            & $Python @GenerateArgs
            if ($LASTEXITCODE -ne 0) { throw "Geracao falhou: $LASTEXITCODE" }
        }

        $ToolPath = $UcrtBin.Replace('\', '/')
        $Setup = if ($SetupHost) { 'ON' } else { 'OFF' }
        $Version = (Get-Content -LiteralPath (Join-Path $ProjectRoot 'VERSION') -Raw).Trim()
        $ConfigureArgs = @('-S', $ProjectRoot, '-B', $BuildDir, '-G', 'Ninja',
            '-DCMAKE_BUILD_TYPE=RelWithDebInfo', "-DBUILD_DECOUPLED_LAUNCHER=$Setup",
            '-DPSX_NETPLAY=ON', '-DPSX_RECOMP_UI=ON', '-DPSX_SETUP_WIZARD=ON',
            '-DPSX_DEBUG_TOOLS=ON', '-DPSX_STATIC_RUNTIME=ON', '-DRNET_ENABLE_ICE=ON',
            "-DPSX_SDL_BACKEND=$SdlBackend", "-DPSX_GAME_VERSION=$Version",
            "-DPSX_STATIC_OVERLAY_DIR=$StaticOverlayDir",
            "-DCMAKE_C_COMPILER=$ToolPath/gcc.exe", "-DCMAKE_CXX_COMPILER=$ToolPath/c++.exe",
            "-DCMAKE_RC_COMPILER:FILEPATH=$ToolPath/windres.exe",
            "-DCMAKE_MAKE_PROGRAM=$ToolPath/ninja.exe", "-DPKG_CONFIG_EXECUTABLE=$ToolPath/pkg-config.exe")
        & $CMake @ConfigureArgs
        if ($LASTEXITCODE -ne 0) { throw "Configuracao falhou: $LASTEXITCODE" }
        & $CMake --build $BuildDir --target psx-runtime --parallel $Jobs
        if ($LASTEXITCODE -ne 0) { throw "Build falhou: $LASTEXITCODE" }
        Write-Host "Executavel: $BuildDir\exPlusAlpha.exe" -ForegroundColor Green
        Write-Host 'Valide primeiro offline; depois LAN, rollback e lobby online conforme ONLINE.md.'
    } finally {
        Pop-Location
    }
} finally {
    $env:PATH = $OriginalPath
}
