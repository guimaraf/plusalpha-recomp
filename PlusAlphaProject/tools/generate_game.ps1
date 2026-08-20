param(
    [string]$RecompilerPath
)

$ErrorActionPreference = "Stop"

$GameRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ConfigPath = Join-Path $GameRoot "game.toml"
$ExePath = Join-Path $GameRoot "local\SLUS_005.48"
$CuePath = Join-Path $GameRoot "disc-a\Street Fighter EX Plus Alpha (USA).cue"
$ExpectedExeSha1 = "D8B81E036AA53C37EF983871C187CC9D00A27156"

if (-not $RecompilerPath) {
    $RecompilerPath = [IO.Path]::GetFullPath((Join-Path $GameRoot `
        "..\psxrecomp\recompiler\build\psxrecomp-game.exe"))
}
elseif (-not [IO.Path]::IsPathRooted($RecompilerPath)) {
    $RecompilerPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $RecompilerPath))
}

foreach ($required in @($ConfigPath, $ExePath, $CuePath, $RecompilerPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Arquivo obrigatório ausente: $required"
    }
}

$ActualExeSha1 = (Get-FileHash -Algorithm SHA1 -LiteralPath $ExePath).Hash
if ($ActualExeSha1 -ne $ExpectedExeSha1) {
    throw "SLUS_005.48 não corresponde à imagem validada. SHA-1: $ActualExeSha1"
}

Push-Location $GameRoot
try {
    & $RecompilerPath --config $ConfigPath
    if ($LASTEXITCODE -ne 0) {
        throw "psxrecomp-game falhou com código $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$ExpectedOutputs = @(
    (Join-Path $GameRoot "generated\SLUS_005.48_full.c"),
    (Join-Path $GameRoot "generated\SLUS_005.48_dispatch.c")
)

foreach ($output in $ExpectedOutputs) {
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw "O recompilador terminou sem produzir: $output"
    }
}

Write-Host "Fontes do jogo gerados e validados em PlusAlphaProject\generated."
