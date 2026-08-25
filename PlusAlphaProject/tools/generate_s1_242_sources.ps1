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

$ExpectedBaselineRangesSha256 = "19EC0080268AB487113691EB1A087751E56E9160539E81FC5A1EC536BD12DDF8"
$ExpectedBaselineFunctions = 1025
$ExpectedPostFunctions = 1028
$ExpectedSeed = "0x80137FE8"
$PriorSeeds = @("0x801102A0", "0x8013CB08")
$QuarantinedSeed = "0x8019E6D0"
$CandidateRanges = @(
    @{ Function = "F 80137FE8"; Range = "R 80137FE8 9C"; Address = "80137FE8"; Length = 0x9C; Sha256 = "A99E5F95F307F9D9D6C5AE0CB9FDD6763D18E0D04084EA2CDB06FD5682BC2FE6" },
    @{ Function = "F 80138084"; Range = "R 80138084 1F8"; Address = "80138084"; Length = 0x1F8; Sha256 = "8F11F9F1029EADC99688DF60CF0D516D466A7C9574A086244ED144E91E9F1A1E" },
    @{ Function = "F 8013827C"; Range = "R 8013827C 140"; Address = "8013827C"; Length = 0x140; Sha256 = "68D7AFE2CD95F05564257D802044BADF5E909F9C11AE3C93AEDA6B020C6A5F51" }
)
$PriorRanges = @(
    @{ Function = "F 801102A0"; Range = "R 801102A0 390" },
    @{ Function = "F 8013CB08"; Range = "R 8013CB08 84" }
)
$ExpectedCallTargets = @(
    "F 80123BF4", "F 8010C72C", "F 80125154", "F 801252A8",
    "F 8019497C", "F 80194904", "F 801948DC", "F 80194B00"
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

foreach ($required in @(
    $GameConfig, $GameExe, $SeedFile, $RangesFile, $GenerateScript, $AuditScript
)) {
    Require-File $required
}

if ((Count-ExactLine $SeedFile $ExpectedSeed) -ne 1) {
    throw "A seed $ExpectedSeed deve aparecer exatamente uma vez em $SeedFile"
}
foreach ($seed in $PriorSeeds) {
    if ((Count-ExactLine $SeedFile $seed) -ne 1) {
        throw "A seed aprovada $seed deve permanecer exatamente uma vez na lista ativa."
    }
}
if ((Count-ExactLine $SeedFile $QuarantinedSeed) -ne 0) {
    throw "A seed em quarentena $QuarantinedSeed nao pode aparecer na lista ativa."
}

foreach ($candidate in $CandidateRanges) {
    $actual = Get-ExecutableRangeSha256 `
        $GameExe ([Convert]::ToUInt32($candidate.Address, 16)) $candidate.Length
    if ($actual -ne $candidate.Sha256) {
        throw "Bytes de 0x$($candidate.Address)+0x$($candidate.Length.ToString('X')) divergentes. SHA-256: $actual"
    }
}

$AlreadyGenerated = $true
foreach ($candidate in $CandidateRanges) {
    $AlreadyGenerated = $AlreadyGenerated -and
        (Count-ExactLine $RangesFile $candidate.Function) -eq 1 -and
        (Count-ExactLine $RangesFile $candidate.Range) -eq 1
}
foreach ($prior in $PriorRanges) {
    $AlreadyGenerated = $AlreadyGenerated -and
        (Count-ExactLine $RangesFile $prior.Function) -eq 1 -and
        (Count-ExactLine $RangesFile $prior.Range) -eq 1
}
$AlreadyGenerated = $AlreadyGenerated -and
    (Count-ExactLine $RangesFile "F 8019E6D0") -eq 0

if (-not $AlreadyGenerated) {
    $BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $BaselineFunctions = @(
        Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$'
    ).Count

    if ($BaselineHash -ne $ExpectedBaselineRangesSha256) {
        throw "Ranges antes da geracao nao correspondem ao S1-241 aprovado. SHA-256: $BaselineHash"
    }
    if ($BaselineFunctions -ne $ExpectedBaselineFunctions) {
        throw "S1-241 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $BaselineFunctions"
    }
    foreach ($prior in $PriorRanges) {
        if ((Count-ExactLine $RangesFile $prior.Function) -ne 1 -or
            (Count-ExactLine $RangesFile $prior.Range) -ne 1) {
            throw "Range aprovado ausente na baseline: $($prior.Range)"
        }
    }
    foreach ($target in $ExpectedCallTargets) {
        if ((Count-ExactLine $RangesFile $target) -ne 1) {
            throw "Dependencia nativa obrigatoria ausente antes da geracao: $target"
        }
    }

    Write-Host "Baseline S1-241 confirmada. Gerando somente as fontes do jogo S1-242..."
    if ($RecompilerPath) {
        & $GenerateScript -RecompilerPath $RecompilerPath
    }
    else {
        & $GenerateScript
    }
    if ($LASTEXITCODE -ne 0) {
        throw "A geracao das fontes S1-242 falhou com codigo $LASTEXITCODE"
    }
}
else {
    Write-Host "Fontes S1-242 ja presentes; repetindo apenas os gates pos-geracao."
}

Require-File $RangesFile
foreach ($candidate in $CandidateRanges) {
    if ((Count-ExactLine $RangesFile $candidate.Function) -ne 1) {
        throw "Funcao esperada ausente ou duplicada: $($candidate.Function)"
    }
    if ((Count-ExactLine $RangesFile $candidate.Range) -ne 1) {
        throw "Range esperado ausente ou duplicado: $($candidate.Range)"
    }
}
foreach ($prior in $PriorRanges) {
    if ((Count-ExactLine $RangesFile $prior.Function) -ne 1 -or
        (Count-ExactLine $RangesFile $prior.Range) -ne 1) {
        throw "Range aprovado perdido durante a geracao: $($prior.Range)"
    }
}
if ((Count-ExactLine $RangesFile "F 8019E6D0") -ne 0) {
    throw "A funcao em quarentena $QuarantinedSeed apareceu nos ranges gerados."
}

$PostFunctions = @(
    Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$'
).Count
if ($PostFunctions -ne $ExpectedPostFunctions) {
    throw "S1-242 deveria conter $ExpectedPostFunctions funcoes; encontrado: $PostFunctions"
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
    throw "A auditoria codegen do S1-242 falhou com codigo $LASTEXITCODE"
}

$RangesHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
Write-Host ""
Write-Host "S1-242 gerado e auditado."
Write-Host "Funcoes: $PostFunctions"
Write-Host "Fechamento: 0x80137FE8, 0x80138084 e 0x8013827C (245 palavras)"
Write-Host "Cobertura esperada: 106.825/195.584 palavras (54,6185%)"
Write-Host "Ranges SHA-256: $RangesHash"
Write-Host "BIOS nao foi regenerada. Nenhum build foi iniciado por este script."
