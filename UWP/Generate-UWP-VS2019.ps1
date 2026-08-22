[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release", "RelWithDebInfo", "MinSizeRel")]
    [string]$Configuration = "Release",

    [string]$WindowsSdkVersion = "10.0",

    [switch]$Build,
    [switch]$Package,
    [switch]$Open
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$SdlVersion = "2.30.2"
$Generator = "Visual Studio 16 2019"
$Architecture = "x64"

$ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$GameSource = Join-Path $ProjectRoot "PlusAlphaProject"
$BuildRoot = Join-Path $ProjectRoot "UWP-Build"
$DependencyRoot = Join-Path $BuildRoot "_deps"
$DownloadRoot = Join-Path $BuildRoot "_downloads"

$SdlArchive = Join-Path $DownloadRoot "release-$SdlVersion.zip"
$SdlSource = Join-Path $DependencyRoot "SDL-release-$SdlVersion"
$SdlBuild = Join-Path $DependencyRoot "sdl2-build"
$SdlInstall = Join-Path $DependencyRoot "sdl2-install"
$SdlConfig = Join-Path $SdlInstall "cmake\SDL2Config.cmake"
$SdlInstallStamp = Join-Path $SdlInstall ".installed-$Configuration"
$PackageRoot = Join-Path $BuildRoot "AppPackages"

function Invoke-CMake {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host "cmake $($Arguments -join ' ')" -ForegroundColor DarkGray
    & cmake @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "CMake terminou com o código $LASTEXITCODE."
    }
}

function Assert-RequiredTools {
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
        throw "CMake não foi encontrado no PATH. Instale o componente CMake do Visual Studio 2019 ou adicione-o ao PATH."
    }

    $cmakeHelp = (& cmake --help 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível consultar os geradores disponíveis do CMake."
    }
    if ($cmakeHelp -notmatch [regex]::Escape($Generator)) {
        throw "O gerador '$Generator' não está disponível. Confirme a instalação do Visual Studio 2019 com Desenvolvimento para UWP e ferramentas C++."
    }

    if (-not (Test-Path (Join-Path $GameSource "CMakeLists.txt"))) {
        throw "Projeto não encontrado em: $GameSource"
    }
}

function Assert-CompatibleBuildDirectory {
    $cachePath = Join-Path $BuildRoot "CMakeCache.txt"
    if (-not (Test-Path $cachePath)) {
        return
    }

    $cache = Get-Content -Raw $cachePath
    if ($cache -notmatch "CMAKE_GENERATOR:INTERNAL=Visual Studio 16 2019") {
        throw "UWP-Build já pertence a outro gerador. Remova manualmente '$BuildRoot' e execute o script novamente."
    }
    if ($cache -notmatch "(?m)^CMAKE_SYSTEM_NAME:[^=]+=WindowsStore\r?$") {
        throw "UWP-Build não é uma configuração WindowsStore. Remova manualmente '$BuildRoot' e execute o script novamente."
    }
}

function Install-Sdl2Uwp {
    New-Item -ItemType Directory -Path $DownloadRoot, $DependencyRoot -Force | Out-Null

    if (-not (Test-Path (Join-Path $SdlSource "CMakeLists.txt"))) {
        if (-not (Test-Path $SdlArchive)) {
            $uri = "https://github.com/libsdl-org/SDL/archive/refs/tags/release-$SdlVersion.zip"
            Write-Host "Baixando SDL2 $SdlVersion..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $uri -OutFile $SdlArchive
        }

        Write-Host "Extraindo SDL2 em UWP-Build/_deps..." -ForegroundColor Cyan
        Expand-Archive -LiteralPath $SdlArchive -DestinationPath $DependencyRoot -Force
    }

    if (-not (Test-Path (Join-Path $SdlSource "CMakeLists.txt"))) {
        throw "O código-fonte SDL2 não foi encontrado após a extração: $SdlSource"
    }

    if (-not (Test-Path $SdlInstallStamp) -or -not (Test-Path $SdlConfig)) {
        Write-Host "Preparando SDL2 WindowsStore ($Configuration)..." -ForegroundColor Cyan
        Invoke-CMake -Arguments @(
            "-S", $SdlSource,
            "-B", $SdlBuild,
            "-G", $Generator,
            "-A", $Architecture,
            "-DCMAKE_SYSTEM_NAME=WindowsStore",
            "-DCMAKE_SYSTEM_VERSION=$WindowsSdkVersion",
            "-DCMAKE_INSTALL_PREFIX=$SdlInstall",
            "-DSDL_SHARED=OFF",
            "-DSDL_STATIC=ON",
            "-DSDL_TEST=OFF"
        )
        Invoke-CMake -Arguments @(
            "--build", $SdlBuild,
            "--config", $Configuration,
            "--target", "install",
            "--parallel"
        )
        New-Item -ItemType File -Path $SdlInstallStamp -Force | Out-Null
    }

    if (-not (Test-Path $SdlConfig)) {
        throw "SDL2Config.cmake não foi instalado em: $SdlConfig"
    }
}

function Generate-GameSolution {
    New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
    Assert-CompatibleBuildDirectory

    Write-Host "Gerando solução UWP do jogo..." -ForegroundColor Cyan
    Invoke-CMake -Arguments @(
        "-S", $GameSource,
        "-B", $BuildRoot,
        "-G", $Generator,
        "-A", $Architecture,
        "-DCMAKE_SYSTEM_NAME=WindowsStore",
        "-DCMAKE_SYSTEM_VERSION=$WindowsSdkVersion",
        "-DSDL2_DIR=$([IO.Path]::GetDirectoryName($SdlConfig))",
        "-DPSX_LAUNCHER=OFF",
        "-DPSX_DEBUG_TOOLS=OFF",
        "-DPSX_ENABLE_VULKAN=OFF"
    )
}

function Build-Game {
    $arguments = @(
        "--build", $BuildRoot,
        "--config", $Configuration,
        "--target", "psx-runtime",
        "--parallel"
    )

    if ($Package) {
        New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null
        $arguments += @(
            "--",
            "/p:AppxBundle=Never",
            "/p:AppxPackageSigningEnabled=false",
            "/p:AppxPackageDir=$PackageRoot\"
        )
    }

    Write-Host "Compilando o projeto UWP ($Configuration)..." -ForegroundColor Cyan
    Invoke-CMake -Arguments $arguments
}

Assert-RequiredTools
Install-Sdl2Uwp
Generate-GameSolution

if ($Build -or $Package) {
    Build-Game
}

$solution = Get-ChildItem -LiteralPath $BuildRoot -Filter "*.sln" -File |
    Select-Object -First 1
if (-not $solution) {
    throw "A solução Visual Studio não foi gerada em: $BuildRoot"
}

Write-Host ""
Write-Host "Projeto UWP gerado com sucesso." -ForegroundColor Green
Write-Host "Solução: $($solution.FullName)"
if (-not ($Build -or $Package)) {
    Write-Host "O jogo não foi compilado; abra a solução no Visual Studio 2019 para continuar."
}
if ($Package) {
    Write-Host "Pacotes: $PackageRoot"
}

if ($Open) {
    Start-Process -FilePath $solution.FullName
}
