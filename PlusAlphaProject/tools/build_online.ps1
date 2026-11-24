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
    [string]$StaticOverlayDir = '',
    # aot: overlays gerados direto do disco (aot/overlays.json); retained: retidas (fallback).
    # Sem o parametro explicito, -Release e -RetainedOverlayDir mantem as retidas.
    [ValidateSet('aot', 'retained')]
    [string]$OverlaySource = 'aot',
    # Geracao isolada por lote: fontes do EXE em -GeneratedDir (nao toca generated-online) a partir
    # de -SeedsFile. O emitter roda direto (~1 s) num staging e so os arquivos alterados sao
    # copiados, para o ninja recompilar apenas os shards que mudaram. Sem estes parametros o
    # fluxo e o de sempre (generated-online).
    [string]$GeneratedDir = '',
    [string]$SeedsFile = '',
    # Antes sempre ligados em -Generate; agora opcionais na geracao isolada.
    [switch]$ForceEmitters,
    [switch]$ForceBios
)

$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('OverlaySource') -and ($Release -or $RetainedOverlayDir)) {
    $OverlaySource = 'retained'
}
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Isolated = [bool]($GeneratedDir -or $SeedsFile)
if ($Isolated) {
    if (-not $GeneratedDir) { throw '-SeedsFile requer -GeneratedDir.' }
    if ($Release) { throw '-Release nao suporta geracao isolada (-GeneratedDir).' }
    if ($SetupHost) { throw '-SetupHost nao suporta geracao isolada (-GeneratedDir).' }
    $GeneratedDir = [IO.Path]::GetFullPath($GeneratedDir)
    if ($GeneratedDir.TrimEnd([char]92) -ieq (Join-Path $ProjectRoot 'generated-online')) {
        throw '-GeneratedDir nao pode ser generated-online (use o fluxo padrao).'
    }
    if (-not $SeedsFile) { $SeedsFile = Join-Path $ProjectRoot 'seeds\entry_funcs.txt' }
    $SeedsFile = (Resolve-Path -LiteralPath $SeedsFile).Path
    if ($OverlaySource -eq 'retained' -and -not $StaticOverlayDir) {
        throw 'Geracao isolada com overlays retidos requer -StaticOverlayDir explicito.'
    }
}
$MainDispatch = if ($Isolated) { Join-Path $GeneratedDir 'SLUS_005.48_dispatch.c' } else { Join-Path $ProjectRoot 'generated-online\SLUS_005.48_dispatch.c' }
$RepositoryRoot = Split-Path $ProjectRoot -Parent
$Framework = Join-Path $RepositoryRoot 'psxrecomp'
$BuildName = if ($SetupHost) { 'build-online-setup' } else { $BuildDirName }
$BuildDir = Join-Path $ProjectRoot $BuildName
$UcrtBin = Join-Path $Msys2Root 'ucrt64\bin'
$CMake = Join-Path $UcrtBin 'cmake.exe'
$Python = (Get-Command python -ErrorAction Stop).Source
if ($Release -and $SetupHost) { throw '-Release requer o runtime completo.' }
if ($Release -and $BuildDirName -notmatch '^build-release-online(?:-[A-Za-z0-9_-]+)?$') {
    throw '-Release requer uma pasta build-release-online ou build-release-online-N para preservar as builds de diagnostico.'
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
    if ($OverlaySource -eq 'retained') {
        if (-not $RetainedOverlayDir) {
            $RetainedOverlayDir = Join-Path $ProjectRoot 'buildTele-s1-309-bezeus\static_overlays'
        }
        $RetainedOverlayDir = (Resolve-Path -LiteralPath $RetainedOverlayDir).Path
        if (-not $StaticOverlayDir) {
            $StaticOverlayDir = Join-Path $ProjectRoot 'generated-online\retained-overlays'
        }
    } elseif (-not $StaticOverlayDir) {
        $StaticOverlayDir = Join-Path $BuildDir 'static-overlays'
    }
    $StaticOverlayDir = [IO.Path]::GetFullPath($StaticOverlayDir)
    Write-Host "Overlays: fonte $OverlaySource -> $StaticOverlayDir" -ForegroundColor Cyan
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

        if ($Isolated) {
            Write-Host "Geracao isolada: seeds $SeedsFile -> $GeneratedDir" -ForegroundColor Cyan
            $Emitter = Join-Path $Framework 'recompiler\build\psxrecomp-game.exe'
            if (-not (Test-Path -LiteralPath $Emitter -PathType Leaf)) {
                throw "Emitter ausente: $Emitter. Compile o alvo psxrecomp-game do framework."
            }
            $GenWork = Join-Path $BuildDir 'generate-work'
            $GenStage = Join-Path $GenWork 'out'
            if (Test-Path -LiteralPath $GenStage) { Remove-Item -LiteralPath $GenStage -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $GenStage | Out-Null
            $Fwd = { param($p) $p.Replace('\', '/') }
            $Toml = (Get-Content -LiteralPath (Join-Path $ProjectRoot 'game.toml') -Raw)
            $Toml = [regex]::Replace($Toml, '(?m)^exe\s*=.*$', "exe = `"$(& $Fwd (Join-Path $ProjectRoot 'local\SLUS_005.48'))`"")
            $Toml = [regex]::Replace($Toml, '(?m)^disc\s*=.*$', "disc = `"$(& $Fwd (Join-Path $ProjectRoot 'disc-a\Street Fighter EX Plus Alpha (USA).cue'))`"")
            $Toml = [regex]::Replace($Toml, '(?m)^bios_config\s*=.*$', "bios_config = `"$(& $Fwd (Join-Path $Framework 'bios\SCPH1001.toml'))`"")
            $Toml = [regex]::Replace($Toml, '(?m)^seeds\s*=.*$', "seeds = `"$(& $Fwd $SeedsFile)`"")
            $Toml = [regex]::Replace($Toml, '(?m)^out_dir\s*=\s*"generated-online"\s*$', "out_dir = `"$(& $Fwd $GenStage)`"")
            Set-Content -LiteralPath (Join-Path $GenWork 'game.toml') -Value $Toml -Encoding utf8
            $EmitterArgs = @('--config', (Join-Path $GenWork 'game.toml'))
            if ($ForceEmitters) { $EmitterArgs += '--force-emitters' }
            if ($ForceBios) { $EmitterArgs += '--force-bios' }
            & $Emitter @EmitterArgs *> (Join-Path $GenWork 'emitter.log')
            if ($LASTEXITCODE -ne 0) { throw "Emitter falhou: $LASTEXITCODE (veja $GenWork\emitter.log)" }
            # Sincroniza so o que mudou (mtime preservado => ninja recompila apenas os shards alterados)
            # e remove shards antigos que o novo lote nao gera.
            New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null
            $Changed = 0
            foreach ($f in Get-ChildItem -LiteralPath $GenStage -File) {
                $dst = Join-Path $GeneratedDir $f.Name
                if ((Test-Path -LiteralPath $dst) -and ((Get-Item -LiteralPath $dst).Length -eq $f.Length) -and
                    ((Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash)) { continue }
                Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
                $Changed++
            }
            $Stale = 0
            foreach ($f in Get-ChildItem -LiteralPath $GeneratedDir -File) {
                if (-not (Test-Path -LiteralPath (Join-Path $GenStage $f.Name))) {
                    Remove-Item -LiteralPath $f.FullName -Force; $Stale++
                }
            }
            Write-Host "Fontes gerados: $Changed arquivo(s) alterado(s), $Stale removido(s)." -ForegroundColor Cyan
        }

        if (-not $SetupHost) {
            & $Python (Join-Path $PSScriptRoot 'check_main_coverage.py') $MainDispatch
            if ($LASTEXITCODE -ne 0) { throw 'Cobertura do EXE incompleta. Execute novamente com -Generate.' }
            if ($OverlaySource -eq 'retained') {
                & $Python (Join-Path $PSScriptRoot 'prepare_retained_overlays.py') `
                    --source $RetainedOverlayDir --output $StaticOverlayDir --framework $Framework
                if ($LASTEXITCODE -ne 0) { throw "Preparacao da cobertura retida falhou: $LASTEXITCODE" }
            } else {
                # O recompilador precisa ter o mesmo --codegen-hash dos fontes do runtime; um
                # binario defasado emitiria overlays com semantica antiga (o pipeline tambem recusa).
                $Recompiler = Join-Path $Framework 'recompiler\build\psxrecomp-game.exe'
                if (-not (Test-Path -LiteralPath $Recompiler -PathType Leaf)) {
                    throw "Recompilador ausente: $Recompiler. Compile o alvo psxrecomp-game do framework."
                }
                $HashHeader = Join-Path $Framework 'runtime\include\overlay_codegen_hash.h'
                $ExpectedHash = if (Test-Path -LiteralPath $HashHeader) {
                    [regex]::Match((Get-Content -LiteralPath $HashHeader -Raw), 'PSX_OVERLAY_CODEGEN_HASH\s+0x([0-9A-Fa-f]{8})u').Groups[1].Value
                } else { '' }
                $BakedHash = ((& $Recompiler --codegen-hash) | Select-Object -First 1)
                if ($ExpectedHash -and ("$BakedHash".Trim() -ne $ExpectedHash.ToLower())) {
                    throw "Recompilador defasado: --codegen-hash $BakedHash difere de $ExpectedHash em overlay_codegen_hash.h. Recompile psxrecomp-game."
                }
                $AotWork = Join-Path $BuildDir 'aot-work'
                $AotWorkers = [Math]::Min($Jobs, 3)
                & $Python (Join-Path $Framework 'tools\aot_overlay_pipeline.py') static `
                    --profile (Join-Path $ProjectRoot 'aot\overlays.json') `
                    --game-toml (Join-Path $ProjectRoot 'game.toml') `
                    --disc (Join-Path $ProjectRoot 'disc-a\Street Fighter EX Plus Alpha (USA).cue') `
                    --recompiler $Recompiler --work-dir $AotWork --out-dir $StaticOverlayDir `
                    --gcc (Join-Path $UcrtBin 'gcc.exe') --cmake $CMake --workers $AotWorkers --cps --reuse
                if ($LASTEXITCODE -ne 0) { throw "Geracao AOT dos overlays falhou: $LASTEXITCODE" }
            }
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
            "-DPSX_STATIC_OVERLAY_DIR=$StaticOverlayDir", "-DPSX_OVERLAY_SOURCE=$OverlaySource",
            '-DPSXRECOMP_BIOS_STEMS=SCPH1001', '-DPSXRECOMP_BIOS_STEM=SCPH1001',
            "-DPSXRECOMP_BIOS_PROFILE=$($Framework.Replace('\', '/'))/bios/SCPH1001.toml",
            '-DPSXRECOMP_SKIP_BIOS_STALE_CHECK=OFF', '-DPSXRECOMP_BIOS_STALE_FATAL=ON',
            "-DCMAKE_C_COMPILER=$ToolPath/gcc.exe", "-DCMAKE_CXX_COMPILER=$ToolPath/c++.exe",
            "-DCMAKE_RC_COMPILER:FILEPATH=$ToolPath/windres.exe",
            "-DCMAKE_MAKE_PROGRAM=$ToolPath/ninja.exe", "-DPKG_CONFIG_EXECUTABLE=$ToolPath/pkg-config.exe")
        if ($Isolated) { $ConfigureArgs += "-DPSX_GENERATED_DIR=$($GeneratedDir.Replace('\', '/'))" }
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
