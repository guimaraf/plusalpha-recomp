param(
    [string]$RecompilerPath,
    [string]$PythonPath
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RepoRoot = (Resolve-Path (Join-Path $ProjectRoot "..")).Path
$FrameworkRoot = Join-Path $RepoRoot "psxrecomp"
$GameConfig = Join-Path $ProjectRoot "game.toml"
$GameExe = Join-Path $ProjectRoot "local\SLUS_005.48"
$SeedFile = Join-Path $ProjectRoot "seeds\entry_funcs.txt"
$RangesFile = Join-Path $ProjectRoot "generated\SLUS_005.48_full.ranges"
$GenerateScript = Join-Path $PSScriptRoot "generate_game.ps1"
$AuditScript = Join-Path $FrameworkRoot "tools\codegen_audit_game.py"
$PreviewRanges = Join-Path $ProjectRoot "local\preaudit\s1-255-preview-01\generated\SLUS_005.48_full.ranges"
$GitIgnoreFile = Join-Path $RepoRoot ".gitignore"
$BiosEmitterShaFile = Join-Path $FrameworkRoot "generated\SCPH1001.emitter.sha"

$ExpectedBaselineRangesSha256 = "2A1B157977603D23A886102BE01A2B7A4B12B7514F450FD893CC96E26B4C4991"
$ExpectedBaselineFunctions = 1048
$ExpectedPostRangesSha256 = "30BCD2340878A0C9057CA4B8A66F582A0695AF844B1E45E9409678951D76D404"
$ExpectedPostFunctions = 1049
$ExpectedAddedWords = 1880
$ExpectedSeed = "0x8018F10C"
$CandidateFunction = "F 8018F10C"
$CandidateRange = "R 8018F10C 1D60"

$PriorSeeds = @(
    "0x8019F5CC", "0x8019F6A8", "0x801A9DC0", "0x801A92B8",
    "0x8011D030", "0x8011D310", "0x80107A74", "0x80162D68",
    "0x80137FE8", "0x801102A0", "0x8013CB08", "0x8014C708",
    "0x8017D860", "0x8017DA08", "0x80191000", "0x8017DA9C",
    "0x80190EB8", "0x80190FAC"
)

$PriorApprovedRanges = @(
    "F 8017D860", "R 8017D860 1A8",
    "F 8017DA08", "R 8017DA08 94",
    "F 80191000", "R 80191000 A4",
    "F 8017DA9C", "R 8017DA9C 124",
    "F 80190EB8", "R 80190EB8 F4",
    "F 80190FAC", "R 80190FAC 54"
)

$DirectTargets = @(
    "8010C72C", "8012398C", "80123BA8", "80123E8C", "80123F24",
    "80125024", "801252A8", "8012CCF0", "80168348", "80168D14",
    "8017AFE0", "8017D454", "8017D678", "8017D70C", "8017D860",
    "8017DA08", "8017DA9C", "80187BDC", "80187E7C", "80190E6C",
    "80190EB8", "80190FAC", "80191000", "801938B0", "801945F8",
    "801946C8", "801948DC", "80194904", "80194990", "801949A4",
    "80194B00", "80195308", "801953A4", "801A000C", "801A75F4"
)

$ForbiddenFunctions = @(
    "F 80103384", "F 8016FC28", "F 8017566C", "F 801910A4",
    "F 801914C0", "F 80191C84", "F 80192D6C", "F 8019E6D0"
)

$RawChecks = @(
    @{
        Address = "8018F10C"
        Length = 0x1D60
        Sha256 = "5AE8E7FD7CA4DA21B03CE4DF7813561B77FCEDFC16F920B82614ABCE8893E2C9"
    },
    @{
        Address = "801AE638"
        Length = 0x14
        Sha256 = "E9974D8B77678119E2ABCE05E125A3BB27C3683B1B8B429F00D1B582CEB6EE79"
    }
)

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Arquivo obrigatorio ausente: $Path"
    }
}

function Count-ExactLine([string]$Path, [string]$Line) {
    return @(
        Get-Content -LiteralPath $Path |
            Where-Object { $_.Trim() -eq $Line }
    ).Count
}

function Get-ExecutableRangeSha256(
    [string]$Path,
    [uint32]$VirtualAddress,
    [int]$Length
) {
    $Bytes = [IO.File]::ReadAllBytes($Path)
    $LoadAddress = [BitConverter]::ToUInt32($Bytes, 0x18)
    $FileOffset = 0x800 + [int64]$VirtualAddress - [int64]$LoadAddress
    if ($FileOffset -lt 0 -or ($FileOffset + $Length) -gt $Bytes.Length) {
        throw "Intervalo 0x$($VirtualAddress.ToString('X8'))+$Length fora do executavel."
    }
    $Slice = New-Object byte[] $Length
    [Array]::Copy($Bytes, $FileOffset, $Slice, 0, $Length)
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($Hasher.ComputeHash($Slice)).Replace("-", "")
    }
    finally {
        $Hasher.Dispose()
    }
}

foreach ($Required in @(
    $GameConfig, $GameExe, $SeedFile, $RangesFile, $GenerateScript,
    $AuditScript, $PreviewRanges, $GitIgnoreFile, $BiosEmitterShaFile
)) {
    Require-File $Required
}

$PreviewHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PreviewRanges).Hash
if ($PreviewHash -ne $ExpectedPostRangesSha256) {
    throw "Manifest da previa S1-255 divergente. SHA-256: $PreviewHash"
}
foreach ($Seed in @($ExpectedSeed) + $PriorSeeds) {
    if ((Count-ExactLine $SeedFile $Seed) -ne 1) {
        throw "A seed aprovada $Seed deve aparecer exatamente uma vez."
    }
}
if ((Count-ExactLine $SeedFile "0x8016FC28") -ne 0) {
    throw "A raiz rejeitada 0x8016FC28 nao pode estar ativa."
}
if ((Count-ExactLine $SeedFile "0x8019E6D0") -ne 0) {
    throw "A seed em quarentena 0x8019E6D0 nao pode estar ativa."
}
foreach ($Check in $RawChecks) {
    $Address = [Convert]::ToUInt32($Check.Address, 16)
    $Actual = Get-ExecutableRangeSha256 $GameExe $Address $Check.Length
    if ($Actual -ne $Check.Sha256) {
        throw "Bytes de 0x$($Check.Address)+0x$($Check.Length.ToString('X')) divergentes. SHA-256: $Actual"
    }
}

$ProtectedHashes = @{}
foreach ($Protected in @($GitIgnoreFile, $BiosEmitterShaFile)) {
    $ProtectedHashes[$Protected] = (
        Get-FileHash -Algorithm SHA256 -LiteralPath $Protected
    ).Hash
}

try {
    $AlreadyGenerated =
        (Count-ExactLine $RangesFile $CandidateFunction) -eq 1 -and
        (Count-ExactLine $RangesFile $CandidateRange) -eq 1
    foreach ($Forbidden in $ForbiddenFunctions) {
        $AlreadyGenerated = $AlreadyGenerated -and
            (Count-ExactLine $RangesFile $Forbidden) -eq 0
    }

    if (-not $AlreadyGenerated) {
        $BaselineHash = (
            Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile
        ).Hash
        $BaselineFunctions = @(
            Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$'
        ).Count
        if ($BaselineHash -ne $ExpectedBaselineRangesSha256) {
            throw "Ranges antes da geracao nao correspondem ao S1-254. SHA-256: $BaselineHash"
        }
        if ($BaselineFunctions -ne $ExpectedBaselineFunctions) {
            throw "S1-254 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $BaselineFunctions"
        }
        foreach ($Range in $PriorApprovedRanges) {
            if ((Count-ExactLine $RangesFile $Range) -ne 1) {
                throw "Range aprovado ausente ou duplicado na baseline: $Range"
            }
        }
        foreach ($Target in $DirectTargets) {
            if ((Count-ExactLine $RangesFile "F $Target") -ne 1) {
                throw "Alvo JAL ainda nao nativo na baseline: F $Target"
            }
        }
        foreach ($Forbidden in $ForbiddenFunctions) {
            if ((Count-ExactLine $RangesFile $Forbidden) -ne 0) {
                throw "Funcao proibida ja aparece na baseline: $Forbidden"
            }
        }

        Write-Host "Baseline S1-254 confirmada. Gerando somente as fontes do jogo S1-255..."
        if ($RecompilerPath) {
            & $GenerateScript -RecompilerPath $RecompilerPath
        }
        else {
            & $GenerateScript
        }
        if ($LASTEXITCODE -ne 0) {
            throw "A geracao das fontes S1-255 falhou com codigo $LASTEXITCODE"
        }
    }
    else {
        Write-Host "Fontes S1-255 ja presentes; repetindo apenas os gates pos-geracao."
    }

    if (
        (Count-ExactLine $RangesFile $CandidateFunction) -ne 1 -or
        (Count-ExactLine $RangesFile $CandidateRange) -ne 1
    ) {
        throw "Range S1-255 ausente ou duplicado: $CandidateRange"
    }
    foreach ($Range in $PriorApprovedRanges) {
        if ((Count-ExactLine $RangesFile $Range) -ne 1) {
            throw "Range aprovado desapareceu ou foi duplicado: $Range"
        }
    }
    foreach ($Target in $DirectTargets) {
        if ((Count-ExactLine $RangesFile "F $Target") -ne 1) {
            throw "Alvo JAL aprovado desapareceu ou foi duplicado: F $Target"
        }
    }
    foreach ($Forbidden in $ForbiddenFunctions) {
        if ((Count-ExactLine $RangesFile $Forbidden) -ne 0) {
            throw "Funcao fora da closure aprovada apareceu nos fontes: $Forbidden"
        }
    }

    $PostFunctions = @(
        Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$'
    ).Count
    $PostHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $PostWords = [Convert]::ToInt32(($CandidateRange -split ' ')[2], 16) / 4
    if ($PostFunctions -ne $ExpectedPostFunctions) {
        throw "S1-255 deveria conter $ExpectedPostFunctions funcoes; encontrado: $PostFunctions"
    }
    if ($PostWords -ne $ExpectedAddedWords) {
        throw "S1-255 deveria adicionar $ExpectedAddedWords palavras; calculado: $PostWords"
    }
    if ($PostHash -ne $ExpectedPostRangesSha256) {
        throw "Ranges apos a geracao divergiram da previa isolada. SHA-256: $PostHash"
    }

    if (-not $PythonPath) {
        $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
        if (-not $PythonCommand) {
            throw "Python nao foi encontrado. Informe -PythonPath."
        }
        $PythonPath = $PythonCommand.Source
    }
    Write-Host "Executando auditoria codegen do jogo..."
    & $PythonPath $AuditScript --config $GameConfig
    if ($LASTEXITCODE -ne 0) {
        throw "A auditoria codegen do S1-255 falhou com codigo $LASTEXITCODE"
    }

    Write-Host ""
    Write-Host "S1-255 gerado e auditado."
    Write-Host "Funcoes: $PostFunctions"
    Write-Host "Raiz: 0x8018F10C (1.880 palavras; 35 alvos JAL ja nativos)"
    Write-Host "Cobertura esperada: 110.494/195.584 palavras (56,4944%)"
    Write-Host "Ranges SHA-256: $PostHash"
    Write-Host "BIOS e build nao foram iniciados por este script."
}
finally {
    foreach ($Protected in $ProtectedHashes.Keys) {
        $AfterHash = (
            Get-FileHash -Algorithm SHA256 -LiteralPath $Protected
        ).Hash
        if ($AfterHash -ne $ProtectedHashes[$Protected]) {
            throw "Artefato protegido foi alterado: $Protected"
        }
    }
}
