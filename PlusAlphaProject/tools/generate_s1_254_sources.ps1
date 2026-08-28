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
$PreviewRanges = Join-Path $ProjectRoot "local\preaudit\s1-254-preview-01\generated\SLUS_005.48_full.ranges"
$GitIgnoreFile = Join-Path $RepoRoot ".gitignore"
$BiosEmitterShaFile = Join-Path $FrameworkRoot "generated\SCPH1001.emitter.sha"

$ExpectedBaselineRangesSha256 = "80DF7E6811A60B300CD5371818A2504FB571EB806B5FC755BD470A4582077068"
$ExpectedBaselineFunctions = 1045
$ExpectedPostRangesSha256 = "2A1B157977603D23A886102BE01A2B7A4B12B7514F450FD893CC96E26B4C4991"
$ExpectedPostFunctions = 1048
$ExpectedAddedWords = 155
$ExpectedSeeds = @("0x8017DA9C", "0x80190EB8", "0x80190FAC")
$PriorSeeds = @(
    "0x8019F5CC", "0x8019F6A8", "0x801A9DC0", "0x801A92B8",
    "0x8011D030", "0x8011D310", "0x80107A74", "0x80162D68",
    "0x80137FE8", "0x801102A0", "0x8013CB08", "0x8014C708",
    "0x8017D860", "0x8017DA08", "0x80191000"
)
$CandidateRanges = @(
    @{ Function = "F 8017DA9C"; Range = "R 8017DA9C 124"; Words = 73 },
    @{ Function = "F 80190EB8"; Range = "R 80190EB8 F4"; Words = 61 },
    @{ Function = "F 80190FAC"; Range = "R 80190FAC 54"; Words = 21 }
)
$ForbiddenFunctions = @(
    "F 80103384", "F 8016FC28", "F 8017566C", "F 8018F10C",
    "F 801910A4", "F 801914C0", "F 80191C84", "F 80192D6C",
    "F 8019E6D0"
)
$RawChecks = @(
    @{ Address = "8017DA9C"; Length = 0x124; Sha256 = "E524079B407C7D73BA9FAB0FFD47922EAA626A2E8B1D1C3FA811C7CE33889670" },
    @{ Address = "80190EB8"; Length = 0xF4; Sha256 = "E9946F974DB4785696E82C73DC62128B8A422F5FB52241D2377ABC9E9BA08EF9" },
    @{ Address = "80190FAC"; Length = 0x54; Sha256 = "66C2068653C40574C0FF3A56627AB7DFBEB07448E6E83B4F4B5B5286AF8BE3F7" },
    @{ Address = "80190E28"; Length = 0x4; Sha256 = "071D30AE03AB44EB86C99244A03AC607FF991500E4AA2310C329097B86C53349" },
    @{ Address = "801909C8"; Length = 0x4; Sha256 = "ADC21CB5D1B43A51F08558D07893E3C86F6AA150D29D12843B69F3F28C441B42" },
    @{ Address = "80190A78"; Length = 0x4; Sha256 = "ADC21CB5D1B43A51F08558D07893E3C86F6AA150D29D12843B69F3F28C441B42" },
    @{ Address = "80190B5C"; Length = 0x4; Sha256 = "ADC21CB5D1B43A51F08558D07893E3C86F6AA150D29D12843B69F3F28C441B42" },
    @{ Address = "801909D0"; Length = 0x4; Sha256 = "EACD563BA7B783D3DC64501DC1A418639F9D53C1C14D52AC37C52DC8D4DF1360" },
    @{ Address = "80190B64"; Length = 0x4; Sha256 = "EACD563BA7B783D3DC64501DC1A418639F9D53C1C14D52AC37C52DC8D4DF1360" }
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
    throw "Manifest da previa S1-254 divergente. SHA-256: $PreviewHash"
}
foreach ($Seed in $ExpectedSeeds + $PriorSeeds) {
    if ((Count-ExactLine $SeedFile $Seed) -ne 1) {
        throw "A seed aprovada $Seed deve aparecer exatamente uma vez."
    }
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
    $AlreadyGenerated = $true
    foreach ($Candidate in $CandidateRanges) {
        $AlreadyGenerated = $AlreadyGenerated -and
            (Count-ExactLine $RangesFile $Candidate.Function) -eq 1 -and
            (Count-ExactLine $RangesFile $Candidate.Range) -eq 1
    }
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
            throw "Ranges antes da geracao nao correspondem ao S1-253. SHA-256: $BaselineHash"
        }
        if ($BaselineFunctions -ne $ExpectedBaselineFunctions) {
            throw "S1-253 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $BaselineFunctions"
        }
        foreach ($Forbidden in $ForbiddenFunctions) {
            if ((Count-ExactLine $RangesFile $Forbidden) -ne 0) {
                throw "Funcao proibida ja aparece na baseline: $Forbidden"
            }
        }
        Write-Host "Baseline S1-253 confirmada. Gerando somente as fontes do jogo S1-254..."
        if ($RecompilerPath) {
            & $GenerateScript -RecompilerPath $RecompilerPath
        }
        else {
            & $GenerateScript
        }
        if ($LASTEXITCODE -ne 0) {
            throw "A geracao das fontes S1-254 falhou com codigo $LASTEXITCODE"
        }
    }
    else {
        Write-Host "Fontes S1-254 ja presentes; repetindo apenas os gates pos-geracao."
    }

    foreach ($Candidate in $CandidateRanges) {
        if (
            (Count-ExactLine $RangesFile $Candidate.Function) -ne 1 -or
            (Count-ExactLine $RangesFile $Candidate.Range) -ne 1
        ) {
            throw "Range S1-254 ausente ou duplicado: $($Candidate.Range)"
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
    $PostWords = ($CandidateRanges | Measure-Object -Property Words -Sum).Sum
    if ($PostFunctions -ne $ExpectedPostFunctions) {
        throw "S1-254 deveria conter $ExpectedPostFunctions funcoes; encontrado: $PostFunctions"
    }
    if ($PostWords -ne $ExpectedAddedWords) {
        throw "S1-254 deveria adicionar $ExpectedAddedWords palavras; calculado: $PostWords"
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
        throw "A auditoria codegen do S1-254 falhou com codigo $LASTEXITCODE"
    }

    Write-Host ""
    Write-Host "S1-254 gerado e auditado."
    Write-Host "Funcoes: $PostFunctions"
    Write-Host "Raizes: 0x8017DA9C, 0x80190EB8, 0x80190FAC (155 palavras)"
    Write-Host "Cobertura esperada: 108.614/195.584 palavras (55,5332%)"
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
