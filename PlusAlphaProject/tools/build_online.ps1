# Executar manualmente: este script gera fontes (com -Generate) e faz build local.
# Nunca reutiliza os diretorios de build ou caches S1-309.
[CmdletBinding()]
param(
    [switch]$Generate,
    [switch]$SetupHost,
    [switch]$Release,
    [string]$Msys2Root = 'C:\msys64',
    [ValidateSet('SDL3', 'SDL2')]
    [string]$SdlBackend = 'SDL3',
    [ValidateRange(1, 64)]
    [int]$Jobs = 4,
    [string]$BiosPath = '',
    [string]$RetainedOverlayDir = '',
    [ValidatePattern('^build-[A-Za-z0-9_-]+$')]
    [string]$BuildDirName = 'build-online-static',
    [string]$StaticOverlayDir = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RepositoryRoot = Split-Path $ProjectRoot -Parent
$Framework = Join-Path $RepositoryRoot 'psxrecomp'
$BuildName = if ($SetupHost) { 'build-online-setup' } else { $BuildDirName }
$BuildDir = Join-Path $ProjectRoot $BuildName
$UcrtBin = Join-Path $Msys2Root 'ucrt64\bin'
$CMake = Join-Path $UcrtBin 'cmake.exe'
$Python = (Get-Command python -ErrorAction Stop).Source
if ($Release -and $SetupHost) { throw '-Release requer o runtime completo.' }
if ($Release -and $BuildDirName -ne 'build-release-online') {
    throw '-Release requer -BuildDirName build-release-online para preservar a build de diagnostico.'
}
if (-not $BiosPath) { $BiosPath = Join-Path $RepositoryRoot 'bios\SCPH1001.BIN' }
if (-not (Test-Path -LiteralPath $BiosPath -PathType Leaf)) {
    throw 'Este port requer sua propria SCPH1001.BIN em bios\SCPH1001.BIN, ou informe -BiosPath.'
}
$BiosPath = (Resolve-Path -LiteralPath $BiosPath).Path
$ExpectedBiosSha256 = '71AF94D1E47A68C11E8FDB9F8368040601514A42A5A399CDA48C7D3BFF1E99D3'
if ((Get-FileHash -LiteralPath $BiosPath -Algorithm SHA256).Hash -ne $ExpectedBiosSha256) {
    throw 'A BIOS nao corresponde a SCPH-1001 validada para este port. O arquivo foi preservado.'
}
$FrameworkBios = Join-Path $Framework 'bios\SCPH1001.BIN'
if (-not $Generate) {
    if (-not (Test-Path -LiteralPath $FrameworkBios -PathType Leaf)) {
        throw 'BIOS retail ainda nao preparada no framework. Execute este script com -Generate.'
    }
    if ((Get-FileHash -LiteralPath $FrameworkBios -Algorithm SHA256).Hash -ne $ExpectedBiosSha256) {
        throw 'A BIOS preparada no framework difere da SCPH-1001 validada. Execute com -Generate para prepara-la novamente.'
    }
}
Write-Host "BIOS: SCPH-1001 retail ($BiosPath); backend exclusivo SCPH1001." -ForegroundColor Cyan
if (-not $SetupHost) {
    if (-not $RetainedOverlayDir) {
        $RetainedOverlayDir = Join-Path $ProjectRoot 'buildTele-s1-309-bezeus\static_overlays'
    }
    $RetainedOverlayDir = (Resolve-Path -LiteralPath $RetainedOverlayDir).Path
    if (-not $StaticOverlayDir) {
        $StaticOverlayDir = Join-Path $ProjectRoot 'generated-online\retained-overlays'
    }
    $StaticOverlayDir = [IO.Path]::GetFullPath($StaticOverlayDir)
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

        if (-not $SetupHost) {
            & $Python (Join-Path $PSScriptRoot 'check_main_coverage.py') `
                (Join-Path $ProjectRoot 'generated-online\SLUS_005.48_dispatch.c')
            if ($LASTEXITCODE -ne 0) { throw 'Cobertura do EXE incompleta. Execute novamente com -Generate.' }
            & $Python (Join-Path $PSScriptRoot 'prepare_retained_overlays.py') `
                --source $RetainedOverlayDir --output $StaticOverlayDir --framework $Framework
            if ($LASTEXITCODE -ne 0) { throw "Preparacao da cobertura retida falhou: $LASTEXITCODE" }
        }

        $ToolPath = $UcrtBin.Replace('\', '/')
        $Setup = if ($SetupHost) { 'ON' } else { 'OFF' }
        $Version = (Get-Content -LiteralPath (Join-Path $ProjectRoot 'VERSION') -Raw).Trim()
        $BuildType = if ($Release) { 'Release' } else { 'RelWithDebInfo' }
        $DebugTools = if ($Release) { 'OFF' } else { 'ON' }
        $SetupWizard = if ($Release) { 'OFF' } else { 'ON' }
        $ConfigureArgs = @('-S', $ProjectRoot, '-B', $BuildDir, '-G', 'Ninja',
            "-DCMAKE_BUILD_TYPE=$BuildType", "-DBUILD_DECOUPLED_LAUNCHER=$Setup",
            '-DPSX_NETPLAY=ON', '-DPSX_RECOMP_UI=ON', "-DPSX_SETUP_WIZARD=$SetupWizard",
            "-DPSX_DEBUG_TOOLS=$DebugTools", '-DPSX_STATIC_RUNTIME=ON', '-DRNET_ENABLE_ICE=ON',
            "-DPSX_SDL_BACKEND=$SdlBackend", "-DPSX_GAME_VERSION=$Version",
            "-DPSX_STATIC_OVERLAY_DIR=$StaticOverlayDir",
            '-DPSXRECOMP_BIOS_STEMS=SCPH1001', '-DPSXRECOMP_BIOS_STEM=SCPH1001',
            "-DPSXRECOMP_BIOS_PROFILE=$($Framework.Replace('\', '/'))/bios/SCPH1001.toml",
            '-DPSXRECOMP_SKIP_BIOS_STALE_CHECK=OFF', '-DPSXRECOMP_BIOS_STALE_FATAL=ON',
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
