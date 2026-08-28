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

$ExpectedBaselineRangesSha256 = "BB5EA43C77096772D1997D52EBA01C84F9DE674D057053D0D61FD9561D6A6D25"
$ExpectedBaselineFunctions = 1042
$ExpectedPreviewFunctions = 1045
$ExpectedAddedWords = 184
$ExpectedSeed = "0x8014C708"
$RejectedSeed = "0x8016FC28"
$QuarantinedSeed = "0x8019E6D0"

$PriorSeeds = @(
    "0x8019F5CC", "0x8019F6A8", "0x801A9DC0", "0x801A92B8",
    "0x8011D030", "0x8011D310", "0x80107A74", "0x80162D68",
    "0x80137FE8", "0x801102A0", "0x8013CB08"
)

$Candidates = @(
    @{ Seed = "0x8017D860"; Function = "F 8017D860"; Range = "R 8017D860 1A8"; Words = 106; BodySha256 = "43F7DA960644EFE8DC1C199749FC08D8392A28591A3FC3577B7020FB3B9F0F67" },
    @{ Seed = "0x8017DA08"; Function = "F 8017DA08"; Range = "R 8017DA08 94"; Words = 37; BodySha256 = "3D7FF33BBC5B4A01DFFB86A1BD3C58DC7F2EE59B2B5182D2BEBE928E6B6F1639" },
    @{ Seed = "0x80191000"; Function = "F 80191000"; Range = "R 80191000 A4"; Words = 41; BodySha256 = "86EA5B37A52FD2703CECF74FCF6672011A29D7E2726F166BFAA4181E8EF61368" }
)

$ControlChecks = @(
    @{ Address = "8018FEEC"; Length = 0x4; Sha256 = "60415E5291FBB86BE45D43DFA3016C175284B9DA57AF9AC972B3E45A878520CD" },
    @{ Address = "80190E20"; Length = 0x4; Sha256 = "5C06045FF23732FFF42FF5C345315EEC02568E20654EE336925363DE3BA8DCD2" },
    @{ Address = "8018FEF4"; Length = 0x4; Sha256 = "356D2F5489E89FA51F96BDF3BC7994365361E6176A539AB3F2A4303D10CEB3DC" },
    @{ Address = "8017DA2C"; Length = 0x4; Sha256 = "FC2E5BCF1222F3E6F02DDC73950672525620ED598E097D324A0E2933040C589B" },
    @{ Address = "8017DA4C"; Length = 0x4; Sha256 = "33FA7C6B2EFAB534D16D608117DDFEEEE541D882A18306D6B36C09C6E062E0BF" }
)

$ForbiddenFunctions = @(
    "F 80103384", "F 8016FC28", "F 8017566C", "F 8017DA9C",
    "F 8018F10C", "F 80190EB8", "F 80190FAC", "F 801910A4",
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

function Get-ExecutableRangeSha256([string]$Path, [uint32]$VirtualAddress, [int]$Length) {
    $Bytes = [IO.File]::ReadAllBytes($Path)
    $LoadAddress = [BitConverter]::ToUInt32($Bytes, 0x18)
    $FileOffset = 0x800 + [int64]$VirtualAddress - [int64]$LoadAddress
    if ($FileOffset -lt 0 -or ($FileOffset + $Length) -gt $Bytes.Length) {
        throw "Intervalo 0x$($VirtualAddress.ToString('X8'))+$Length fora do executavel."
    }
    $Slice = New-Object byte[] $Length
    [Array]::Copy($Bytes, $FileOffset, $Slice, 0, $Length)
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($Hasher.ComputeHash($Slice)).Replace("-", "") }
    finally { $Hasher.Dispose() }
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
        $Candidate = Join-Path $PreviewRoot ("s1-253-preview-{0:D2}" -f $Number)
        if (-not (Test-Path -LiteralPath $Candidate)) {
            New-Item -ItemType Directory -Path $Candidate | Out-Null
            return $Candidate
        }
    }
    throw "Nao ha preview-id livre entre s1-253-preview-01 e 99."
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
    $RecompilerPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $RecompilerPath))
}
Require-File $RecompilerPath

if (-not $PythonPath) {
    $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $PythonCommand) { throw "Python nao foi encontrado. Informe -PythonPath." }
    $PythonPath = $PythonCommand.Source
}

$BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
$BaselineRanges = Get-FunctionRanges $RangesFile
if ($BaselineHash -ne $ExpectedBaselineRangesSha256) {
    throw "Baseline nao corresponde ao S1-251 aprovado. SHA-256: $BaselineHash"
}
if ($BaselineRanges.Count -ne $ExpectedBaselineFunctions) {
    throw "S1-251 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $($BaselineRanges.Count)"
}
if ((Count-ExactLine $SeedFile $ExpectedSeed) -ne 1) {
    throw "A seed S1-251 $ExpectedSeed deve aparecer exatamente uma vez."
}
foreach ($Seed in $PriorSeeds) {
    if ((Count-ExactLine $SeedFile $Seed) -ne 1) {
        throw "A seed aprovada $Seed deve aparecer exatamente uma vez."
    }
}
foreach ($Candidate in $Candidates) {
    if ((Count-ExactLine $SeedFile $Candidate.Seed) -ne 0) {
        throw "A seed candidata $($Candidate.Seed) ja esta ativa no arquivo principal."
    }
    $ActualBodyHash = Get-ExecutableRangeSha256 $GameExe ([Convert]::ToUInt32($Candidate.Seed.Substring(2), 16)) ([Convert]::ToInt32(($Candidate.Range -split ' ')[2], 16))
    if ($ActualBodyHash -ne $Candidate.BodySha256) {
        throw "Corpo $($Candidate.Seed) divergente. SHA-256: $ActualBodyHash"
    }
}
if ((Count-ExactLine $SeedFile $RejectedSeed) -ne 0) {
    throw "A seed rejeitada $RejectedSeed nao pode estar ativa."
}
if ((Count-ExactLine $SeedFile $QuarantinedSeed) -ne 0) {
    throw "A seed em quarentena $QuarantinedSeed nao pode estar ativa."
}
foreach ($Check in $ControlChecks) {
    $Actual = Get-ExecutableRangeSha256 $GameExe ([Convert]::ToUInt32($Check.Address, 16)) $Check.Length
    if ($Actual -ne $Check.Sha256) {
        throw "Estrutura de controle 0x$($Check.Address) divergente. SHA-256: $Actual"
    }
}

$MainArtifacts = @($SeedFile, $RangesFile, $FullCFile, $DispatchCFile, $GitIgnoreFile, $BiosEmitterShaFile)
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

# Previa isolada S1-253: folhas da closure rejeitada S1-252.
# Orcamento maximo: 184 palavras; nenhuma funcao adicional e permitida.
0x8017D860
0x8017DA08
0x80191000
"@
[IO.File]::AppendAllText($PreviewSeed, $SeedAppend, [Text.UTF8Encoding]::new($false))

$ConfigText = Get-Content -Raw -LiteralPath $GameConfig
$ConfigText = $ConfigText -replace '(?m)^exe\s*=.*$', ('exe = "{0}"' -f (Convert-ToTomlPath $GameExe))
$ConfigText = $ConfigText -replace '(?m)^disc\s*=.*$', ('disc = "{0}"' -f (Convert-ToTomlPath $GameDisc))
$ConfigText = $ConfigText -replace '(?m)^seeds\s*=.*$', ('seeds = "{0}"' -f (Convert-ToTomlPath $PreviewSeed))
$ConfigText = $ConfigText -replace '(?m)^out_dir\s*=.*$', ('out_dir = "{0}"' -f (Convert-ToTomlPath $PreviewGenerated))
[IO.File]::WriteAllText($PreviewConfig, $ConfigText, [Text.UTF8Encoding]::new($false))

try {
    Write-Host "Baseline S1-251 confirmada. Gerando previa S1-253 somente em: $RunDir"
    & $RecompilerPath --config $PreviewConfig
    if ($LASTEXITCODE -ne 0) {
        throw "A geracao isolada S1-253 falhou com codigo $LASTEXITCODE"
    }
    Require-File $PreviewRanges

    $PreviewMap = Get-FunctionRanges $PreviewRanges
    if ($PreviewMap.Count -ne $ExpectedPreviewFunctions) {
        throw "A previa deveria conter $ExpectedPreviewFunctions funcoes; encontrado: $($PreviewMap.Count)"
    }
    foreach ($Address in $BaselineRanges.Keys) {
        if (-not $PreviewMap.ContainsKey($Address) -or $PreviewMap[$Address] -ne $BaselineRanges[$Address]) {
            throw "Range aprovado desapareceu ou mudou na previa: F $Address"
        }
    }

    $Added = @($PreviewMap.Keys | Where-Object { -not $BaselineRanges.ContainsKey($_) } | Sort-Object)
    $ExpectedAdded = @($Candidates | ForEach-Object { $_.Seed.Substring(2) } | Sort-Object)
    if (($Added -join ',') -ne ($ExpectedAdded -join ',')) {
        throw "Closure inesperada. Esperado: $($ExpectedAdded -join ', '); obtido: $($Added -join ', ')"
    }

    $AddedWords = 0
    foreach ($Candidate in $Candidates) {
        $Address = $Candidate.Seed.Substring(2)
        $ExpectedLength = ($Candidate.Range -split ' ')[2]
        if ($PreviewMap[$Address] -ne $ExpectedLength) {
            throw "Range candidato divergente: $($Candidate.Range)"
        }
        $AddedWords += $Candidate.Words
    }
    if ($AddedWords -ne $ExpectedAddedWords) {
        throw "A closure deveria somar $ExpectedAddedWords palavras; calculado: $AddedWords"
    }
    foreach ($Forbidden in $ForbiddenFunctions) {
        if ((Count-ExactLine $PreviewRanges $Forbidden) -ne 0) {
            throw "Funcao proibida apareceu na previa: $Forbidden"
        }
    }

    Write-Host "Executando auditoria codegen somente nos fontes isolados..."
    & $PythonPath $AuditScript --config $PreviewConfig
    if ($LASTEXITCODE -ne 0) {
        throw "A auditoria codegen da previa S1-253 falhou com codigo $LASTEXITCODE"
    }

    $PreviewHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PreviewRanges).Hash
    $Summary = @"
# Pre-auditoria S1-253

- Baseline S1-251 SHA-256: $BaselineHash
- Funcoes na baseline: $ExpectedBaselineFunctions
- Funcoes na previa: $($PreviewMap.Count)
- Funcoes adicionadas: $($Added -join ', ')
- Palavras adicionadas: $AddedWords
- Ranges SHA-256 da previa: $PreviewHash
- Auditoria codegen: CLEAN
- Artefatos principais: preservados
- BIOS e build: nao iniciados
"@
    [IO.File]::WriteAllText((Join-Path $RunDir "summary.md"), $Summary, [Text.UTF8Encoding]::new($false))

    Write-Host ""
    Write-Host "Previa isolada S1-253 aprovada."
    Write-Host "Funcoes adicionadas: $($Added -join ', ')"
    Write-Host "Palavras adicionadas: $AddedWords"
    Write-Host "Funcoes totais: $($PreviewMap.Count)"
    Write-Host "Cobertura projetada: 108.459/195.584 palavras (55,4539%)"
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
