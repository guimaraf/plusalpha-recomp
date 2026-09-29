# Run locally: prepares an isolated 309 build with synchronous DLL image preload.
[CmdletBinding()]
param(
    [string]$Msys2Root = 'C:\msys64'
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Baseline = Join-Path $ProjectRoot 'buildTele-s1-309-verification'
$BuildDir = Join-Path $ProjectRoot 'buildTele-s1-309-dll'
$UcrtBin = Join-Path $Msys2Root 'ucrt64\bin'
$CMake = Join-Path $UcrtBin 'cmake.exe'
foreach ($name in @('cmake.exe', 'gcc.exe', 'c++.exe', 'ninja.exe', 'pkg-config.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $UcrtBin $name))) {
        throw "Missing tool: $UcrtBin\$name"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $Baseline 'cache'))) {
    throw "Missing stable cache: $Baseline\cache"
}
foreach ($name in @('settings.toml', 'input.ini', 'keybinds.ini', 'overlay_captures.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Baseline $name))) {
        throw "Missing baseline file: $Baseline\$name"
    }
}
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $BuildDir 'cache'))) {
    Copy-Item -LiteralPath (Join-Path $Baseline 'cache') -Destination (Join-Path $BuildDir 'cache') -Recurse
}
foreach ($name in @('settings.toml', 'input.ini', 'keybinds.ini', 'overlay_captures.json')) {
    $dest = Join-Path $BuildDir $name
    if (-not (Test-Path -LiteralPath $dest)) {
        Copy-Item -LiteralPath (Join-Path $Baseline $name) -Destination $dest
    }
}
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'game.toml') -Destination (Join-Path $BuildDir 'game.toml')
$OldPath = $env:PATH
$OldCcacheDisable = $env:CCACHE_DISABLE
try {
    $env:PATH = "$UcrtBin;$OldPath"
    # Avoid the ccache stall observed while creating 309-verification.
    $env:CCACHE_DISABLE = '1'
    & $CMake -S $ProjectRoot -B $BuildDir -G Ninja `
        -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_DECOUPLED_LAUNCHER=OFF `
        -DPSX_DEBUG_TOOLS=ON -DPSX_STATIC_RUNTIME=ON -DPSX_LAUNCHER=ON `
        -DPSX_ENABLE_VULKAN=OFF -DPSX_OVERLAY_PRELOAD_ALL=ON `
        "-DCMAKE_C_COMPILER=$UcrtBin\gcc.exe" `
        "-DCMAKE_CXX_COMPILER=$UcrtBin\c++.exe" `
        "-DCMAKE_MAKE_PROGRAM=$UcrtBin\ninja.exe" `
        "-DPKG_CONFIG_EXECUTABLE=$UcrtBin\pkg-config.exe"
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed: $LASTEXITCODE" }
    & $CMake --build $BuildDir --target psx-runtime --parallel 4
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $LASTEXITCODE" }
    $exe = Join-Path $BuildDir 'exPlusAlpha.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw "Missing executable: $exe" }
    $dlls = @(Get-ChildItem -LiteralPath (Join-Path $BuildDir 'cache') -File -Recurse -Filter '*.dll')
    Write-Host "Ready: $exe"
    Write-Host "Cached DLLs: $($dlls.Count); preload enabled before gameplay."
    Write-Host 'For same-binary A/B, set PSX_OVERLAY_PRELOAD_ALL=0 before launch to disable full preload.'
} finally {
    $env:PATH = $OldPath
    $env:CCACHE_DISABLE = $OldCcacheDisable
}
