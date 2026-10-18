# Build local de telemetria S1-309 para validar o bezel em tela cheia 16:9.
[CmdletBinding()]
param(
    [string]$Msys2Root = 'C:\msys64',
    [ValidateRange(1, 64)]
    [int]$Jobs = 4
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RepositoryRoot = Split-Path $ProjectRoot -Parent
$Framework = Join-Path $RepositoryRoot 'psxrecomp'
$BuildDir = Join-Path $ProjectRoot 'buildTele-s1-309-bezeus'
$SettingsBaseline = Join-Path $ProjectRoot 'buildTele-s1-309-fps'
$StaticBaseline = Join-Path $ProjectRoot 'build_s1_309_dll_complete\static_overlays'
$SourceCache = Join-Path $ProjectRoot 'buildTele-s1-309\cache'
$PrepareStatic = Join-Path $PSScriptRoot 'prepare_s1_309_static.py'
$IconPath = Join-Path $RepositoryRoot 'icon\alpha256.ico'
$BezelPath = Join-Path $RepositoryRoot 'sfexp.png'
$TargetExe = Join-Path $BuildDir 'exPlusAlpha.exe'
$UcrtBin = Join-Path $Msys2Root 'ucrt64\bin'
$UcrtCMakePath = $UcrtBin.Replace('\', '/')
$CMake = Join-Path $UcrtBin 'cmake.exe'

Write-Host 'Build de telemetria S1-309 - Bezel' -ForegroundColor Cyan
Write-Host "Saida: $BuildDir"
Write-Host 'Perfil: RelWithDebInfo, debug ativo, runtime estatico e launcher ativo.'

foreach ($Name in @('cmake.exe', 'gcc.exe', 'c++.exe', 'ninja.exe', 'pkg-config.exe', 'windres.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $UcrtBin $Name) -PathType Leaf)) {
        throw "Ferramenta ausente: $UcrtBin\$Name"
    }
}
foreach ($Path in @($IconPath, $BezelPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Recurso ausente: $Path"
    }
}
foreach ($Name in @('settings.toml', 'input.ini', 'keybinds.ini', 'game.toml')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SettingsBaseline $Name) -PathType Leaf)) {
        throw "Configuracao de referencia ausente: $SettingsBaseline\$Name"
    }
}

# O perfil estatico deve permanecer sem carregamento de DLLs de overlays.
$CacheDir = Join-Path $BuildDir 'cache'
if (Test-Path -LiteralPath $CacheDir) {
    $ExistingDlls = @(Get-ChildItem -LiteralPath $CacheDir -Recurse -File -Filter '*.dll')
    if ($ExistingDlls.Count) {
        throw 'A pasta de destino possui DLLs no cache. Este perfil exige cache sem DLLs; os arquivos foram preservados.'
    }
}

$StaticDir = $StaticBaseline
if (-not (Test-Path -LiteralPath (Join-Path $StaticDir 'sources.cmake') -PathType Leaf)) {
    $StaticDir = Join-Path $BuildDir 'static_overlays'
    if (-not (Test-Path -LiteralPath (Join-Path $StaticDir 'sources.cmake') -PathType Leaf)) {
        foreach ($Path in @($PrepareStatic, (Join-Path $Framework 'tools\compile_overlays.py'))) {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                throw "Preparador de fontes ausente: $Path"
            }
        }
        if (-not (Test-Path -LiteralPath $SourceCache -PathType Container)) {
            throw "Cache S1-309 necessario para preparar os fontes estaticos: $SourceCache"
        }
        $PythonBin = (Get-Command python -ErrorAction Stop).Source
        Write-Host '[1/4] Preparando fontes estaticos a partir do cache S1-309...' -ForegroundColor Green
        & $PythonBin $PrepareStatic --cache $SourceCache --output $StaticDir --framework $Framework
        if ($LASTEXITCODE -ne 0) {
            throw "Preparacao de overlays estaticos falhou: $LASTEXITCODE"
        }
    }
}
foreach ($Name in @('sources.cmake', 'overlays_static.c', 'coverage.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $StaticDir $Name) -PathType Leaf)) {
        throw "Fonte ou relatorio estatico ausente: $StaticDir\$Name"
    }
}
$Coverage = Get-Content -LiteralPath (Join-Path $StaticDir 'coverage.json') -Raw | ConvertFrom-Json
if ($Coverage.dlls -ne 2219 -or $Coverage.missing_entries -ne 0) {
    throw 'Cobertura S1-309 esperada: 2.219 DLLs e nenhuma entrada ausente.'
}

New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
foreach ($Name in @('settings.toml', 'input.ini', 'keybinds.ini', 'game.toml', 'gametime.save')) {
    $Source = Join-Path $SettingsBaseline $Name
    $Destination = Join-Path $BuildDir $Name
    if ((Test-Path -LiteralPath $Source -PathType Leaf) -and -not (Test-Path -LiteralPath $Destination)) {
        Copy-Item -LiteralPath $Source -Destination $Destination
    }
}
$ConfigPath = Join-Path $BuildDir 'game.toml'
$ConfigText = [System.IO.File]::ReadAllText($ConfigPath)
if ($ConfigText -notmatch '(?m)^overlay_cache[ \t]*=[ \t]*false[ \t]*(?=\r?$)') {
    throw 'Esperado overlay_cache = false no game.toml desta build estatica.'
}

$ConfigureRecoveryArgs = @()
$CMakeCachePath = Join-Path $BuildDir 'CMakeCache.txt'
if (Test-Path -LiteralPath $CMakeCachePath -PathType Leaf) {
    $BrokenRcPath = @(Get-Content -LiteralPath $CMakeCachePath | Where-Object {
        $_.StartsWith('CMAKE_RC_COMPILER:') -and $_.Contains('\')
    })
    if ($BrokenRcPath.Count) {
        $ConfigureRecoveryArgs = @('--fresh')
        Write-Host 'Recriando a configuracao CMake para corrigir o caminho de windres.'
    }
}

$OldPath = $env:PATH
$OldCcache = $env:CCACHE_DISABLE
try {
    $env:PATH = "$UcrtBin;$OldPath"
    $env:CCACHE_DISABLE = '1'
    Write-Host '[2/4] Configurando CMake com Ninja...' -ForegroundColor Green
    & $CMake @ConfigureRecoveryArgs -S $ProjectRoot -B $BuildDir -G Ninja `
        -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_DECOUPLED_LAUNCHER=OFF `
        -DPSX_DEBUG_TOOLS=ON -DPSX_STATIC_RUNTIME=ON -DPSX_LAUNCHER=ON `
        -DPSX_ENABLE_VULKAN=OFF -DPSX_OVERLAY_PRELOAD_ALL=OFF `
        "-DPSX_STATIC_OVERLAY_DIR=$StaticDir" "-DPSX_APP_ICON=$IconPath" `
        "-DCMAKE_C_COMPILER=$UcrtCMakePath/gcc.exe" "-DCMAKE_CXX_COMPILER=$UcrtCMakePath/c++.exe" `
        "-DCMAKE_RC_COMPILER:FILEPATH=$UcrtCMakePath/windres.exe" `
        "-DCMAKE_MAKE_PROGRAM=$UcrtCMakePath/ninja.exe" "-DPKG_CONFIG_EXECUTABLE=$UcrtCMakePath/pkg-config.exe"
    if ($LASTEXITCODE -ne 0) { throw "Configuracao CMake falhou: $LASTEXITCODE" }

    Write-Host "[3/4] Compilando psx-runtime com $Jobs tarefas..." -ForegroundColor Green
    & $CMake --build $BuildDir --target psx-runtime --parallel $Jobs
    if ($LASTEXITCODE -ne 0) { throw "Build falhou: $LASTEXITCODE" }

    Write-Host '[4/4] Conferindo executavel, imagem e configuracao...' -ForegroundColor Green
    if (-not (Test-Path -LiteralPath $TargetExe -PathType Leaf)) {
        throw "Executavel esperado nao encontrado: $TargetExe"
    }
    Copy-Item -LiteralPath $BezelPath -Destination (Join-Path $BuildDir 'sfexp.png') -Force
    # CMake pode copiar o game.toml do projeto: recuperar a configuracao deste perfil.
    if ([System.IO.File]::ReadAllText($ConfigPath) -ne $ConfigText) {
        [System.IO.File]::WriteAllText($ConfigPath, $ConfigText, [System.Text.UTF8Encoding]::new($false))
    }
    Write-Host "Build pronta: $TargetExe" -ForegroundColor Green
    Write-Host 'Em Video, habilite Show Bezel abaixo de Show FPS. O padrao e Off.'
    Write-Host 'Valide tela cheia 16:9, Alt+Enter, persistencia e o aviso Only 16:9 resolutions.'
    Write-Host "Cobertura estatica: $StaticDir\coverage.json"
} finally {
    $env:PATH = $OldPath
    $env:CCACHE_DISABLE = $OldCcache
}
