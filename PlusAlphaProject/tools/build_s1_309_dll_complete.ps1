# Local build only. Never copies binaries back into the validated installation.
[CmdletBinding()]
param([string]$Msys2Root = 'C:\msys64')
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Framework = Join-Path (Split-Path $ProjectRoot -Parent) 'psxrecomp'
$Baseline = Join-Path $ProjectRoot 'buildTele-s1-309-dll'
$BuildDir = Join-Path $ProjectRoot 'build_s1_309_dll_complete'
$StaticDir = Join-Path $BuildDir 'static_overlays'
$UcrtBin = Join-Path $Msys2Root 'ucrt64\bin'
$CMake = Join-Path $UcrtBin 'cmake.exe'
foreach ($name in @('cmake.exe', 'gcc.exe', 'c++.exe', 'ninja.exe', 'pkg-config.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $UcrtBin $name))) {
        throw "Missing tool: $UcrtBin\$name"
    }
}
foreach ($name in @('settings.toml', 'input.ini', 'keybinds.ini', 'game.toml')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Baseline $name))) {
        throw "Missing baseline file: $Baseline\$name"
    }
}
$PythonBin = (Get-Command python -ErrorAction Stop).Source
& $PythonBin (Join-Path $PSScriptRoot 'prepare_s1_309_static.py') `
    --cache (Join-Path $Baseline 'cache') --output $StaticDir --framework $Framework
if ($LASTEXITCODE -ne 0) { throw 'Static coverage preparation failed; build aborted.' }
foreach ($name in @('settings.toml', 'input.ini', 'keybinds.ini', 'game.toml')) {
    $dest = Join-Path $BuildDir $name
    if (-not (Test-Path -LiteralPath $dest)) {
        Copy-Item -LiteralPath (Join-Path $Baseline $name) -Destination $dest
    }
}
# Disable dynamic loading/capture/autocompile only in this experiment's copy.
# Static dispatch remains active and installs its own code-page watches.
$ConfigPath = Join-Path $BuildDir 'game.toml'
$ConfigText = [System.IO.File]::ReadAllText($ConfigPath)
if ($ConfigText -notmatch '(?m)^overlay_cache[ \t]*=[ \t]*(true|false)[ \t]*(?=\r?$)') {
    throw 'Expected overlay_cache setting missing from experimental game.toml.'
}
$ConfigText = $ConfigText -replace '(?m)^overlay_cache[ \t]*=[ \t]*(true|false)[ \t]*(?=\r?$)', 'overlay_cache = false'
[System.IO.File]::WriteAllText($ConfigPath, $ConfigText, [System.Text.UTF8Encoding]::new($false))
# No DLL cache is copied: a missing static entry must be visible in this test.
if (Test-Path -LiteralPath (Join-Path $BuildDir 'cache')) {
    $existing = @(Get-ChildItem -LiteralPath (Join-Path $BuildDir 'cache') -Recurse -File -Filter '*.dll')
    if ($existing.Count) { throw 'This experiment requires a DLL-free cache. Existing files were preserved.' }
}
$OldPath = $env:PATH
$OldCcache = $env:CCACHE_DISABLE
try {
    $env:PATH = "$UcrtBin;$OldPath"
    $env:CCACHE_DISABLE = '1'
    & $CMake -S $ProjectRoot -B $BuildDir -G Ninja `
        -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_DECOUPLED_LAUNCHER=OFF `
        -DPSX_DEBUG_TOOLS=ON -DPSX_STATIC_RUNTIME=ON -DPSX_LAUNCHER=ON `
        -DPSX_ENABLE_VULKAN=OFF -DPSX_OVERLAY_PRELOAD_ALL=OFF `
        "-DPSX_STATIC_OVERLAY_DIR=$StaticDir" `
        "-DCMAKE_C_COMPILER=$UcrtBin\gcc.exe" "-DCMAKE_CXX_COMPILER=$UcrtBin\c++.exe" `
        "-DCMAKE_MAKE_PROGRAM=$UcrtBin\ninja.exe" "-DPKG_CONFIG_EXECUTABLE=$UcrtBin\pkg-config.exe"
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed: $LASTEXITCODE" }
    & $CMake --build $BuildDir --target psx-runtime --parallel 4
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $LASTEXITCODE" }
    Write-Host "Ready for gameplay validation: $BuildDir\exPlusAlpha.exe"
    Write-Host "Static coverage report: $StaticDir\coverage.json"
} finally {
    $env:PATH = $OldPath
    $env:CCACHE_DISABLE = $OldCcache
}
