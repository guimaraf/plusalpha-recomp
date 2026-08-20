[CmdletBinding()]
param(
    [string]$Msys2Root = "C:\msys64",
    [string]$BuildDir,
    [ValidateSet("Debug", "RelWithDebInfo", "Release", "MinSizeRel")]
    [string]$BuildType = "RelWithDebInfo"
)

$ErrorActionPreference = "Stop"

$GameRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Msys2Root = [IO.Path]::GetFullPath($Msys2Root)
$UcrtRoot = Join-Path $Msys2Root "ucrt64"
$UcrtBin = Join-Path $UcrtRoot "bin"

if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $GameRoot "build-ucrt"
}
elseif (-not [IO.Path]::IsPathRooted($BuildDir)) {
    $BuildDir = [IO.Path]::GetFullPath((Join-Path $GameRoot $BuildDir))
}
else {
    $BuildDir = [IO.Path]::GetFullPath($BuildDir)
}

$CMake = Join-Path $UcrtBin "cmake.exe"
$Ninja = Join-Path $UcrtBin "ninja.exe"
$CCompiler = Join-Path $UcrtBin "cc.exe"
$CxxCompiler = Join-Path $UcrtBin "c++.exe"
$PkgConfig = Join-Path $UcrtBin "pkg-config.exe"
$Ccache = Join-Path $UcrtBin "ccache.exe"
$SdlPkgConfig = Join-Path $UcrtRoot "lib\pkgconfig\sdl2.pc"
$SdlStaticLibrary = Join-Path $UcrtRoot "lib\libSDL2.a"

$RequiredFiles = @(
    $CMake,
    $Ninja,
    $CCompiler,
    $CxxCompiler,
    $PkgConfig,
    $SdlPkgConfig,
    $SdlStaticLibrary
)
foreach ($RequiredFile in $RequiredFiles) {
    if (-not (Test-Path -LiteralPath $RequiredFile -PathType Leaf)) {
        throw "Dependência UCRT64 ausente: $RequiredFile"
    }
}

& $PkgConfig --exists sdl2
if ($LASTEXITCODE -ne 0) {
    throw "O pkg-config do UCRT64 não encontrou o pacote sdl2."
}
$SdlVersion = (& $PkgConfig --modversion sdl2).Trim()
if ($LASTEXITCODE -ne 0 -or -not $SdlVersion) {
    throw "Não foi possível obter a versão da SDL2 no UCRT64."
}

$CachePath = Join-Path $BuildDir "CMakeCache.txt"
if (Test-Path -LiteralPath $CachePath -PathType Leaf) {
    $CompilerLine = Select-String -Path $CachePath `
        -Pattern '^CMAKE_C_COMPILER:FILEPATH=' | Select-Object -First 1
    if ($CompilerLine) {
        $CachedCompiler = ($CompilerLine.Line -split '=', 2)[1]
        $ExpectedPrefix = $UcrtRoot.Replace('\', '/').TrimEnd('/') + '/'
        $NormalizedCompiler = $CachedCompiler.Replace('\', '/')
        if (-not $NormalizedCompiler.StartsWith(
            $ExpectedPrefix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw "O cache $BuildDir usa outra toolchain: $CachedCompiler. Use um diretório build-ucrt limpo e separado."
        }
    }
}

$ConfigureArgs = @(
    "-S", $GameRoot,
    "-B", $BuildDir,
    "-G", "Ninja",
    "-DCMAKE_BUILD_TYPE:STRING=$BuildType",
    "-DCMAKE_C_COMPILER:FILEPATH=$CCompiler",
    "-DCMAKE_CXX_COMPILER:FILEPATH=$CxxCompiler",
    "-DCMAKE_MAKE_PROGRAM:FILEPATH=$Ninja",
    "-DPKG_CONFIG_EXECUTABLE:FILEPATH=$PkgConfig",
    "-DPSX_STATIC_RUNTIME:BOOL=ON",
    "-DPSX_DEBUG_TOOLS:BOOL=ON",
    "-DPSX_LAUNCHER:BOOL=ON"
)

if (Test-Path -LiteralPath $Ccache -PathType Leaf) {
    $ConfigureArgs += "-DCMAKE_C_COMPILER_LAUNCHER:FILEPATH=$Ccache"
    $ConfigureArgs += "-DCMAKE_CXX_COMPILER_LAUNCHER:FILEPATH=$Ccache"
}

$PreviousPath = $env:PATH
$env:PATH = "$UcrtBin;$PreviousPath"
try {
    & $CMake @ConfigureArgs
    if ($LASTEXITCODE -ne 0) {
        throw "A configuração CMake UCRT64 falhou com código $LASTEXITCODE"
    }
}
finally {
    $env:PATH = $PreviousPath
}

Write-Host "Runtime configurado com MSYS2 UCRT64 e SDL2 $SdlVersion em: $BuildDir"
Write-Host "Nenhum build foi executado por este script."
