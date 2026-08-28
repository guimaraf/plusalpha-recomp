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
$GameDisc = Join-Path $ProjectRoot "disc-a\Street Fighter EX Plus Alpha (USA).cue"
$SeedFile = Join-Path $ProjectRoot "seeds\entry_funcs.txt"
$RangesFile = Join-Path $ProjectRoot "generated\SLUS_005.48_full.ranges"
$FullCFile = Join-Path $ProjectRoot "generated\SLUS_005.48_full.c"
$DispatchCFile = Join-Path $ProjectRoot "generated\SLUS_005.48_dispatch.c"
$AuditScript = Join-Path $FrameworkRoot "tools\codegen_audit_game.py"
$GitIgnoreFile = Join-Path $RepoRoot ".gitignore"
$BiosEmitterShaFile = Join-Path $FrameworkRoot "generated\SCPH1001.emitter.sha"
$PreviewRoot = Join-Path $ProjectRoot "local\preaudit"

$ExpectedBaselineRangesSha256 = "2A1B157977603D23A886102BE01A2B7A4B12B7514F450FD893CC96E26B4C4991"
$ExpectedBaselineFunctions = 1048
$ExpectedPreviewFunctions = 1049
$ExpectedAddedWords = 1880
$RejectedRootSeed = "0x8016FC28"
$QuarantinedSeed = "0x8019E6D0"

$ExpectedBaselineSeeds = @(
    "0x8019F5CC", "0x8019F6A8", "0x801A9DC0", "0x801A92B8",
    "0x8011D030", "0x8011D310", "0x80107A74", "0x80162D68",
    "0x80137FE8", "0x801102A0", "0x8013CB08", "0x8014C708",
    "0x8017D860", "0x8017DA08", "0x80191000", "0x8017DA9C",
    "0x80190EB8", "0x80190FAC"
)

$Candidate = @{
    Seed = "0x8018F10C"
    Function = "F 8018F10C"
    Range = "R 8018F10C 1D60"
    Words = 1880
    BodySha256 = "5AE8E7FD7CA4DA21B03CE4DF7813561B77FCEDFC16F920B82614ABCE8893E2C9"
}

# Todos os 35 alvos JAL formais encontrados nos 86 call sites da candidata.
# A previa so e segura se cada alvo ja pertencer a baseline S1-254.
$DirectTargets = @(
    "8010C72C", "8012398C", "80123BA8", "80123E8C", "80123F24",
    "80125024", "801252A8", "8012CCF0", "80168348", "80168D14",
    "8017AFE0", "8017D454", "8017D678", "8017D70C", "8017D860",
    "8017DA08", "8017DA9C", "80187BDC", "80187E7C", "80190E6C",
    "80190EB8", "80190FAC", "80191000", "801938B0", "801945F8",
    "801946C8", "801948DC", "80194904", "80194990", "801949A4",
    "80194B00", "80195308", "801953A4", "801A000C", "801A75F4"
)

# A funcao seleciona um de cinco estados por JR $v0. O hash protege a tabela
# externa ao corpo; todos os cinco destinos foram auditados como internos.
$ControlChecks = @(
    @{
        Address = "801AE638"
        Length = 0x14
        Sha256 = "E9974D8B77678119E2ABCE05E125A3BB27C3683B1B8B429F00D1B582CEB6EE79"
    }
)

$ExpectedJumpTableTargets = @(
    "8018F1BC", "8018FF24", "801903AC", "80190450", "801909F8"
)

$ForbiddenFunctions = @(
    "F 80103384", "F 8016FC28", "F 8017566C", "F 801910A4",
    "F 801914C0", "F 80191C84", "F 80192D6C", "F 8019E6D0"
)

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Arquivo obrigatorio ausente: $Path"
    }
}

function Count-ExactLine([string]$Path, [string]$Line) {
    return @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() -eq $Line }).Count
}

function Get-ExecutableRangeBytes(
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
    return ,$Slice
}

function Get-ExecutableRangeSha256(
    [string]$Path,
    [uint32]$VirtualAddress,
    [int]$Length
) {
    $Slice = Get-ExecutableRangeBytes $Path $VirtualAddress $Length
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($Hasher.ComputeHash($Slice)).Replace("-", "")
    }
    finally {
        $Hasher.Dispose()
    }
}

function Get-FunctionRanges([string]$Path) {
    $Result = @{}
    foreach ($Line in Get-Content -LiteralPath $Path) {
        if ($Line -match '^R ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]+)$') {
            $Result[$Matches[1].ToUpperInvariant()] = $Matches[2].ToUpperInvariant()
        }
    }
    return $Result
}

function New-PreviewDirectory {
    New-Item -ItemType Directory -Path $PreviewRoot -Force | Out-Null
    foreach ($Number in 1..99) {
        $Path = Join-Path $PreviewRoot ("s1-255-preview-{0:D2}" -f $Number)
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path | Out-Null
            return $Path
        }
    }
    throw "Nao ha preview-id livre entre s1-255-preview-01 e 99."
}

function Convert-ToTomlPath([string]$Path) {
    return ([IO.Path]::GetFullPath($Path)).Replace("\", "/")
}

foreach ($Required in @(
    $GameConfig, $GameExe, $GameDisc, $SeedFile, $RangesFile, $FullCFile,
    $DispatchCFile, $AuditScript, $GitIgnoreFile, $BiosEmitterShaFile
)) {
    Require-File $Required
}

if (-not $RecompilerPath) {
    $RecompilerPath = Join-Path $FrameworkRoot "recompiler\build\psxrecomp-game.exe"
}
elseif (-not [IO.Path]::IsPathRooted($RecompilerPath)) {
    $RecompilerPath = [IO.Path]::GetFullPath(
        (Join-Path (Get-Location) $RecompilerPath)
    )
}
Require-File $RecompilerPath

if (-not $PythonPath) {
    $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $PythonCommand) {
        throw "Python nao foi encontrado. Informe -PythonPath."
    }
    $PythonPath = $PythonCommand.Source
}

$BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
$BaselineRanges = Get-FunctionRanges $RangesFile
if ($BaselineHash -ne $ExpectedBaselineRangesSha256) {
    throw "Baseline nao corresponde ao S1-254. SHA-256: $BaselineHash"
}
if ($BaselineRanges.Count -ne $ExpectedBaselineFunctions) {
    throw "S1-254 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $($BaselineRanges.Count)"
}
foreach ($Seed in $ExpectedBaselineSeeds) {
    if ((Count-ExactLine $SeedFile $Seed) -ne 1) {
        throw "A seed aprovada $Seed deve aparecer exatamente uma vez."
    }
}
if ((Count-ExactLine $SeedFile $Candidate.Seed) -ne 0) {
    throw "A seed candidata $($Candidate.Seed) ja esta ativa no arquivo principal."
}
if ($BaselineRanges.ContainsKey($Candidate.Seed.Substring(2))) {
    throw "A candidata $($Candidate.Seed) ja pertence aos ranges da baseline."
}
if ((Count-ExactLine $SeedFile $RejectedRootSeed) -ne 0) {
    throw "A raiz rejeitada $RejectedRootSeed nao pode estar ativa."
}
if ((Count-ExactLine $SeedFile $QuarantinedSeed) -ne 0) {
    throw "A seed em quarentena $QuarantinedSeed nao pode estar ativa."
}

$CandidateAddress = [Convert]::ToUInt32($Candidate.Seed.Substring(2), 16)
$CandidateLength = [Convert]::ToInt32(($Candidate.Range -split ' ')[2], 16)
$ActualBodyHash = Get-ExecutableRangeSha256 $GameExe $CandidateAddress $CandidateLength
if ($ActualBodyHash -ne $Candidate.BodySha256) {
    throw "Corpo $($Candidate.Seed) divergente. SHA-256: $ActualBodyHash"
}
if (($CandidateLength / 4) -ne $ExpectedAddedWords) {
    throw "Boundary da candidata nao corresponde a $ExpectedAddedWords palavras."
}

foreach ($Target in $DirectTargets) {
    if (-not $BaselineRanges.ContainsKey($Target)) {
        throw "Alvo JAL ainda nao nativo na baseline S1-254: 0x$Target"
    }
}

foreach ($Check in $ControlChecks) {
    $Address = [Convert]::ToUInt32($Check.Address, 16)
    $Actual = Get-ExecutableRangeSha256 $GameExe $Address $Check.Length
    if ($Actual -ne $Check.Sha256) {
        throw "Estrutura de controle 0x$($Check.Address) divergente. SHA-256: $Actual"
    }
}
$JumpTableBytes = Get-ExecutableRangeBytes $GameExe ([Convert]::ToUInt32("801AE638", 16)) 0x14
$JumpTableTargets = @()
foreach ($Offset in 0, 4, 8, 12, 16) {
    $JumpTableTargets += [BitConverter]::ToUInt32($JumpTableBytes, $Offset).ToString("X8")
}
if (($JumpTableTargets -join ',') -ne ($ExpectedJumpTableTargets -join ',')) {
    throw "Destinos da jump table divergentes: $($JumpTableTargets -join ', ')"
}
foreach ($Target in $JumpTableTargets) {
    $Value = [Convert]::ToUInt32($Target, 16)
    if ($Value -lt $CandidateAddress -or $Value -ge ($CandidateAddress + $CandidateLength)) {
        throw "Jump table escapou do corpo candidato: 0x$Target"
    }
}

$MainArtifacts = @(
    $SeedFile, $RangesFile, $FullCFile, $DispatchCFile,
    $GitIgnoreFile, $BiosEmitterShaFile
)
$MainHashes = @{}
foreach ($Artifact in $MainArtifacts) {
    $MainHashes[$Artifact] = (Get-FileHash -Algorithm SHA256 -LiteralPath $Artifact).Hash
}

$RunDir = New-PreviewDirectory
$PreviewSeed = Join-Path $RunDir "entry_funcs.preview.txt"
$PreviewGenerated = Join-Path $RunDir "generated"
$PreviewConfig = Join-Path $RunDir "game.preview.toml"
$PreviewRanges = Join-Path $PreviewGenerated "SLUS_005.48_full.ranges"
New-Item -ItemType Directory -Path $PreviewGenerated | Out-Null
Copy-Item -LiteralPath $SeedFile -Destination $PreviewSeed

$SeedAppend = @"

# Previa isolada S1-255: funcao principal da rota Expert Mode.
# Orcamento exato: 1.880 palavras; nenhuma closure adicional e permitida.
0x8018F10C
"@
[IO.File]::AppendAllText(
    $PreviewSeed,
    $SeedAppend,
    [Text.UTF8Encoding]::new($false)
)

$ConfigText = Get-Content -Raw -LiteralPath $GameConfig
$ConfigText = $ConfigText -replace '(?m)^exe\s*=.*$',
    ('exe = "{0}"' -f (Convert-ToTomlPath $GameExe))
$ConfigText = $ConfigText -replace '(?m)^disc\s*=.*$',
    ('disc = "{0}"' -f (Convert-ToTomlPath $GameDisc))
$ConfigText = $ConfigText -replace '(?m)^seeds\s*=.*$',
    ('seeds = "{0}"' -f (Convert-ToTomlPath $PreviewSeed))
$ConfigText = $ConfigText -replace '(?m)^out_dir\s*=.*$',
    ('out_dir = "{0}"' -f (Convert-ToTomlPath $PreviewGenerated))
[IO.File]::WriteAllText(
    $PreviewConfig,
    $ConfigText,
    [Text.UTF8Encoding]::new($false)
)

try {
    Write-Host "Baseline S1-254 confirmada. Gerando previa S1-255 somente em: $RunDir"
    & $RecompilerPath --config $PreviewConfig
    if ($LASTEXITCODE -ne 0) {
        throw "A geracao isolada S1-255 falhou com codigo $LASTEXITCODE"
    }
    Require-File $PreviewRanges

    $PreviewMap = Get-FunctionRanges $PreviewRanges
    if ($PreviewMap.Count -ne $ExpectedPreviewFunctions) {
        throw "A previa deveria conter $ExpectedPreviewFunctions funcoes; encontrado: $($PreviewMap.Count)"
    }
    foreach ($Address in $BaselineRanges.Keys) {
        if (
            -not $PreviewMap.ContainsKey($Address) -or
            $PreviewMap[$Address] -ne $BaselineRanges[$Address]
        ) {
            throw "Range aprovado desapareceu ou mudou na previa: F $Address"
        }
    }

    $Added = @(
        $PreviewMap.Keys |
            Where-Object { -not $BaselineRanges.ContainsKey($_) } |
            Sort-Object
    )
    $ExpectedAdded = @($Candidate.Seed.Substring(2))
    if (($Added -join ',') -ne ($ExpectedAdded -join ',')) {
        throw "Closure inesperada. Esperado: $($ExpectedAdded -join ', '); obtido: $($Added -join ', ')"
    }
    if ($PreviewMap[$Candidate.Seed.Substring(2)] -ne "1D60") {
        throw "Range candidato divergente: $($Candidate.Range)"
    }
    if ($Candidate.Words -ne $ExpectedAddedWords) {
        throw "A closure deveria somar $ExpectedAddedWords palavras; calculado: $($Candidate.Words)"
    }
    foreach ($Forbidden in $ForbiddenFunctions) {
        if ((Count-ExactLine $PreviewRanges $Forbidden) -ne 0) {
            throw "Funcao proibida apareceu na previa: $Forbidden"
        }
    }

    Write-Host "Executando auditoria codegen somente nos fontes isolados..."
    & $PythonPath $AuditScript --config $PreviewConfig
    if ($LASTEXITCODE -ne 0) {
        throw "A auditoria codegen da previa S1-255 falhou com codigo $LASTEXITCODE"
    }

    $PreviewHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PreviewRanges).Hash
    $Summary = @"
# Pre-auditoria S1-255

- Baseline S1-254 SHA-256: $BaselineHash
- Funcoes na baseline: $ExpectedBaselineFunctions
- Funcoes na previa: $($PreviewMap.Count)
- Funcao adicionada: $($Added -join ', ')
- Palavras adicionadas: $($Candidate.Words)
- Alvos JAL unicos ja nativos: $($DirectTargets.Count)/35
- Jump table: cinco destinos internos confirmados
- Cobertura projetada: 110.494/195.584 palavras (56,4944%)
- Ranges SHA-256 da previa: $PreviewHash
- Auditoria codegen: CLEAN
- Artefatos principais: preservados
- BIOS e build: nao iniciados
"@
    [IO.File]::WriteAllText(
        (Join-Path $RunDir "summary.md"),
        $Summary,
        [Text.UTF8Encoding]::new($false)
    )

    Write-Host ""
    Write-Host "Previa isolada S1-255 aprovada."
    Write-Host "Funcao adicionada: $($Added -join ', ')"
    Write-Host "Palavras adicionadas: $($Candidate.Words)"
    Write-Host "Funcoes totais: $($PreviewMap.Count)"
    Write-Host "Cobertura projetada: 110.494/195.584 palavras (56,4944%)"
    Write-Host "Ranges SHA-256 da previa: $PreviewHash"
    Write-Host "Resumo: $(Join-Path $RunDir 'summary.md')"
    Write-Host "Fontes principais, BIOS e build nao foram alterados."
}
finally {
    foreach ($Artifact in $MainArtifacts) {
        $AfterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Artifact).Hash
        if ($AfterHash -ne $MainHashes[$Artifact]) {
            throw "A previa alterou um artefato principal protegido: $Artifact"
        }
    }
}
