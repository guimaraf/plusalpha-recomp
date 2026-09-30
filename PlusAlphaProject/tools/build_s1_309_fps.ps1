# Local build only. Retains the icon and validated static overlays for Show FPS testing.
[CmdletBinding()]
param([string]$Msys2Root = 'C:\msys64')
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RepositoryRoot = Split-Path $ProjectRoot -Parent
$Baseline = Join-Path $ProjectRoot 'build_s1_309_dll_complete'
$BuildDir = Join-Path $ProjectRoot 'buildTele-s1-309-fps'
$SettingsBaseline = Join-Path $ProjectRoot 'buildTele-s1-309-icon'
$StaticDir = Join-Path $Baseline 'static_overlays'
$IconPath = Join-Path $RepositoryRoot 'icon\alpha256.ico'
$UcrtBin = Join-Path $Msys2Root 'ucrt64\bin'
$UcrtCMakePath = $UcrtBin.Replace('\', '/')
$CMake = Join-Path $UcrtBin 'cmake.exe'
foreach ($name in @('cmake.exe', 'gcc.exe', 'c++.exe', 'ninja.exe', 'pkg-config.exe', 'windres.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $UcrtBin $name))) {
        throw "Missing tool: $UcrtBin\$name"
    }
}
foreach ($path in @($IconPath, (Join-Path $StaticDir 'sources.cmake'),
        (Join-Path $StaticDir 'overlays_static.c'), (Join-Path $StaticDir 'coverage.json'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing baseline input: $path" }
}
$Coverage = Get-Content -LiteralPath (Join-Path $StaticDir 'coverage.json') -Raw | ConvertFrom-Json
if ($Coverage.dlls -ne 2219 -or $Coverage.missing_entries -ne 0) {
    throw 'Expected validated S1-309 coverage: 2219 DLLs and zero missing entries.'
}
foreach ($name in @('settings.toml', 'input.ini', 'keybinds.ini', 'game.toml')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SettingsBaseline $name) -PathType Leaf)) {
        throw "Missing baseline file: $SettingsBaseline\$name"
    }
}
# This experiment must not silently fall back to a dynamic DLL cache.
$CacheDir = Join-Path $BuildDir 'cache'
if (Test-Path -LiteralPath $CacheDir) {
    $ExistingDlls = @(Get-ChildItem -LiteralPath $CacheDir -Recurse -File -Filter '*.dll')
    if ($ExistingDlls.Count) { throw 'This build requires a DLL-free cache. Existing files were preserved.' }
}
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
foreach ($name in @('settings.toml', 'input.ini', 'keybinds.ini', 'game.toml')) {
    $Destination = Join-Path $BuildDir $name
    if (-not (Test-Path -LiteralPath $Destination)) {
        Copy-Item -LiteralPath (Join-Path $SettingsBaseline $name) -Destination $Destination
    }
}
# Carry the user's existing encrypted total into this separate Windows build.
$PreviousGameTime = Join-Path $SettingsBaseline 'gametime.save'
$NewGameTime = Join-Path $BuildDir 'gametime.save'
if ((Test-Path -LiteralPath $PreviousGameTime -PathType Leaf) -and
    -not (Test-Path -LiteralPath $NewGameTime)) {
    Copy-Item -LiteralPath $PreviousGameTime -Destination $NewGameTime
}
$ConfigPath = Join-Path $BuildDir 'game.toml'
$ConfigText = [System.IO.File]::ReadAllText($ConfigPath)
if ($ConfigText -notmatch '(?m)^overlay_cache[ \t]*=[ \t]*false[ \t]*(?=\r?$)') {
    throw 'Expected overlay_cache = false in game.toml, matching the validated static build.'
}
$OldPath = $env:PATH
$OldCcache = $env:CCACHE_DISABLE
$ConfigureRecoveryArgs = @()
$CMakeCachePath = Join-Path $BuildDir 'CMakeCache.txt'
if (Test-Path -LiteralPath $CMakeCachePath) {
    $BrokenRcPath = @(Get-Content -LiteralPath $CMakeCachePath | Where-Object {
        $_.StartsWith('CMAKE_RC_COMPILER:') -and $_.Contains('\')
    })
    if ($BrokenRcPath.Count) {
        # Regenerate CMake's cached compiler files after the invalid escape error.
        # User settings and the validated static-overlay sources are preserved.
        $ConfigureRecoveryArgs = @('--fresh')
        Write-Host 'Recreating CMake configuration after the windres path escape error.'
    }
}
try {
    $env:PATH = "$UcrtBin;$OldPath"
    $env:CCACHE_DISABLE = '1'
    & $CMake @ConfigureRecoveryArgs -S $ProjectRoot -B $BuildDir -G Ninja `
        -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_DECOUPLED_LAUNCHER=OFF `
        -DPSX_DEBUG_TOOLS=ON -DPSX_STATIC_RUNTIME=ON -DPSX_LAUNCHER=ON `
        -DPSX_ENABLE_VULKAN=OFF -DPSX_OVERLAY_PRELOAD_ALL=OFF `
        "-DPSX_STATIC_OVERLAY_DIR=$StaticDir" "-DPSX_APP_ICON=$IconPath" `
        "-DCMAKE_C_COMPILER=$UcrtCMakePath/gcc.exe" "-DCMAKE_CXX_COMPILER=$UcrtCMakePath/c++.exe" `
        "-DCMAKE_RC_COMPILER:FILEPATH=$UcrtCMakePath/windres.exe" `
        "-DCMAKE_MAKE_PROGRAM=$UcrtCMakePath/ninja.exe" "-DPKG_CONFIG_EXECUTABLE=$UcrtCMakePath/pkg-config.exe"
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed: $LASTEXITCODE" }
    & $CMake --build $BuildDir --target psx-runtime --parallel 4
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $LASTEXITCODE" }
    Write-Host "Ready for Show FPS and Arcade validation: $BuildDir\exPlusAlpha.exe"
    Write-Host 'Validate Show FPS Off/On and persistence in settings.toml; then repeat the Arcade stability test.'
    Write-Host "Embedded icon: $IconPath (256x256)"
    Write-Host "Validated static coverage: $StaticDir\coverage.json"
} finally {
    $env:PATH = $OldPath
    $env:CCACHE_DISABLE = $OldCcache
}
