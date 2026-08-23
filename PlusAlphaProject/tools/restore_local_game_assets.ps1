param(
    [string]$SourceProjectRoot = "F:\GitRevised\psxPlusAlpha\PlusAlphaProject"
)

$ErrorActionPreference = "Stop"

$ExpectedExeSha1 = "D8B81E036AA53C37EF983871C187CC9D00A27156"
$TargetProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$SourceProjectRoot = (Resolve-Path -LiteralPath $SourceProjectRoot).Path

$Files = @(
    @{
        Name = "SLUS_005.48"
        Source = Join-Path $SourceProjectRoot "local\SLUS_005.48"
        Destination = Join-Path $TargetProjectRoot "local\SLUS_005.48"
    },
    @{
        Name = "Street Fighter EX Plus Alpha (USA).cue"
        Source = Join-Path $SourceProjectRoot "disc-a\Street Fighter EX Plus Alpha (USA).cue"
        Destination = Join-Path $TargetProjectRoot "disc-a\Street Fighter EX Plus Alpha (USA).cue"
    },
    @{
        Name = "Street Fighter EX Plus Alpha (USA).bin"
        Source = Join-Path $SourceProjectRoot "disc-a\Street Fighter EX Plus Alpha (USA).bin"
        Destination = Join-Path $TargetProjectRoot "disc-a\Street Fighter EX Plus Alpha (USA).bin"
    }
)

foreach ($file in $Files) {
    if (-not (Test-Path -LiteralPath $file.Source -PathType Leaf)) {
        throw "Arquivo de origem ausente: $($file.Source)"
    }
}

$SourceExeSha1 = (Get-FileHash -Algorithm SHA1 -LiteralPath $Files[0].Source).Hash
if ($SourceExeSha1 -ne $ExpectedExeSha1) {
    throw "SLUS_005.48 de origem invalido. SHA-1: $SourceExeSha1"
}

foreach ($file in $Files) {
    $destinationDir = Split-Path -Parent $file.Destination
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null

    if (Test-Path -LiteralPath $file.Destination -PathType Leaf) {
        if ($file.Name -eq "SLUS_005.48") {
            $DestinationExeSha1 = (Get-FileHash -Algorithm SHA1 -LiteralPath $file.Destination).Hash
            if ($DestinationExeSha1 -ne $ExpectedExeSha1) {
                throw "Destino ja existe e difere da imagem validada: $($file.Destination)"
            }
        }
        elseif ((Get-Item -LiteralPath $file.Destination).Length -ne
                (Get-Item -LiteralPath $file.Source).Length) {
            throw "Destino ja existe com tamanho diferente: $($file.Destination)"
        }

        Write-Host "Mantido (ja validado): $($file.Name)"
        continue
    }

    Copy-Item -LiteralPath $file.Source -Destination $file.Destination
    Write-Host "Copiado: $($file.Name)"
}

$FinalExeSha1 = (Get-FileHash -Algorithm SHA1 -LiteralPath $Files[0].Destination).Hash
if ($FinalExeSha1 -ne $ExpectedExeSha1) {
    throw "Falha ao validar o executavel copiado. SHA-1: $FinalExeSha1"
}

Write-Host "Ativos locais prontos em: $TargetProjectRoot"
Write-Host "Agora execute: .\PlusAlphaProject\tools\generate_game.ps1"
