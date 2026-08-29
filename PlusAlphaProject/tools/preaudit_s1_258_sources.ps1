param(
    [string]$RecompilerPath,
    [string]$PythonPath,
    [switch]$ValidateOnly
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

$ExpectedBaselineRangesSha256 = "A10B9A83A30D0CB0280F36898971A2D99F804ABC094461994B137F55B635E6CD"
$ExpectedBaselineSeedsSha256 = "7F406F8D5645C323FC6344659D607D07BB2C10DFF7124F1E2B19CBF5475ED974"
$ExpectedGameExeSha256 = "4FFE98EB4F246B4D455392E537E8D9F029D34F2E95E301AEF2CB61F5E3E99820"
$ExpectedBaselineFunctions = 1056
$ExpectedBaselineSeedCount = 535
$ExpectedBaselineCoverageWords = 111146
$ExpectedPreviewFunctions = 1057
$ExpectedAddedWords = 151
$ExpectedProjectedWords = 111297
$TotalGameWords = 195584

$RootSeed = "0x8017566C"
$RootAddressText = "8017566C"
$RootLength = 0x25C
$RootWords = 151
$RootBodySha256 = "5DA650C3D1A23F0C9E8359253D73D3741BE92D12BB348ECBCEB94A2FEE3014E2"
$JumpTableAddress = [Convert]::ToUInt32("801AC9C0", 16)
$JumpTableLength = 19 * 4
$JumpTableSha256 = "48FAC5788B5D05A0476AD3A6A1ADF35EAF2F99649D7DB5599FAE06CA7D04419D"

$ExpectedDirectJalTargets = @(
    "80101D18", "80101D68", "8012398C", "80123E8C", "80168348",
    "8016963C", "801758C8", "80175F60", "8017733C", "80177934",
    "80191680", "801931FC", "8019326C", "8019327C", "80195308",
    "801953A4", "8019F1F0", "801A000C", "801A75F4"
)
$ExpectedJumpTableTargets = @(
    "801756B0", "80175714", "80175730", "80175798", "801757DC",
    "801758B4", "801758B4", "801758B4", "801758B4", "801758B4",
    "801758B4", "801758B4", "801758B4", "801758B4", "801758B4",
    "801758B4", "801757EC", "80175874", "80175890"
)
$ForbiddenFunctions = @("80103384", "8019E6D0")

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Arquivo obrigatorio ausente: $Path"
    }
}

function Get-ActiveSeeds([string]$Path) {
    return @(
        Get-Content -LiteralPath $Path |
            ForEach-Object { ($_ -split '#')[0].Trim() } |
            Where-Object { $_ -match '^0x[0-9A-Fa-f]{8}$' } |
            ForEach-Object { $_.ToUpperInvariant() }
    )
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

function Get-BytesSha256([byte[]]$Bytes) {
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($Hasher.ComputeHash($Bytes)).Replace("-", "")
    }
    finally {
        $Hasher.Dispose()
    }
}

function Get-MipsFlow([byte[]]$Bytes, [uint32]$StartAddress) {
    $Flow = @{
        DirectJalTargets = @()
        JalrSites = @()
        JrSites = @()
        BranchTargets = @()
        JumpTargets = @()
        ForbiddenSites = @()
    }
    for ($Offset = 0; $Offset -lt $Bytes.Length; $Offset += 4) {
        [uint32]$Pc = $StartAddress + [uint32]$Offset
        [uint32]$Word = [BitConverter]::ToUInt32($Bytes, $Offset)
        [uint32]$Opcode = $Word -shr 26
        [uint32]$Function = $Word -band 0x3F
        if ($Opcode -eq 0x03) {
            [uint64]$Target = (
                (([uint64]$Pc + 4) -band [uint64]([Convert]::ToUInt32("F0000000", 16))) -bor
                (([uint64]($Word -band 0x03FFFFFF)) -shl 2)
            )
            $Flow.DirectJalTargets += ([uint32]$Target).ToString("X8")
        }
        elseif ($Opcode -eq 0x02) {
            [uint64]$Target = (
                (([uint64]$Pc + 4) -band [uint64]([Convert]::ToUInt32("F0000000", 16))) -bor
                (([uint64]($Word -band 0x03FFFFFF)) -shl 2)
            )
            $Flow.JumpTargets += ([uint32]$Target).ToString("X8")
        }
        elseif ($Opcode -in 0x01, 0x04, 0x05, 0x06, 0x07) {
            [int32]$Immediate = $Word -band 0xFFFF
            if (($Immediate -band 0x8000) -ne 0) { $Immediate -= 0x10000 }
            [int64]$Target = [int64]$Pc + 4 + ([int64]$Immediate * 4)
            $Flow.BranchTargets += ([uint32]$Target).ToString("X8")
        }
        if ($Opcode -eq 0 -and $Function -eq 0x09) {
            $Flow.JalrSites += $Pc.ToString("X8")
        }
        if ($Opcode -eq 0 -and $Function -eq 0x08) {
            $Flow.JrSites += $Pc.ToString("X8")
        }
        if (
            $Opcode -eq 0x12 -or
            ($Opcode -eq 0 -and $Function -in 0x0C, 0x0D, 0x18, 0x19, 0x1A, 0x1B)
        ) {
            $Flow.ForbiddenSites += $Pc.ToString("X8")
        }
    }
    return $Flow
}

function Assert-ExactList([string[]]$Actual, [string[]]$Expected, [string]$Description) {
    $ActualNormalized = @($Actual | ForEach-Object { $_.ToUpperInvariant() })
    $ExpectedNormalized = @($Expected | ForEach-Object { $_.ToUpperInvariant() })
    if (($ActualNormalized -join ',') -ne ($ExpectedNormalized -join ',')) {
        throw "$Description divergente. Esperado: $($ExpectedNormalized -join ', '); obtido: $($ActualNormalized -join ', ')"
    }
}

function Assert-InternalTargets(
    [string[]]$Targets,
    [uint32]$StartAddress,
    [int]$Length,
    [string]$Description
) {
    [uint64]$EndAddress = [uint64]$StartAddress + [uint64]$Length
    foreach ($TargetText in $Targets) {
        [uint64]$Target = [Convert]::ToUInt32($TargetText, 16)
        if ($Target -lt $StartAddress -or $Target -ge $EndAddress) {
            throw "$Description escapou do corpo: 0x$TargetText"
        }
    }
}

function New-PreviewDirectory {
    New-Item -ItemType Directory -Path $PreviewRoot -Force | Out-Null
    foreach ($Number in 1..99) {
        $Path = Join-Path $PreviewRoot ("s1-258-preview-{0:D2}" -f $Number)
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path | Out-Null
            return $Path
        }
    }
    throw "Nao ha preview-id livre entre s1-258-preview-01 e 99."
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

$BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
if ($BaselineHash -ne $ExpectedBaselineRangesSha256) {
    throw "Baseline nao corresponde a S1-257. SHA-256: $BaselineHash"
}
$SeedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SeedFile).Hash
if ($SeedHash -ne $ExpectedBaselineSeedsSha256) {
    throw "Seeds principais nao correspondem a S1-257. SHA-256: $SeedHash"
}
$GameExeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $GameExe).Hash
if ($GameExeHash -ne $ExpectedGameExeSha256) {
    throw "Executavel do jogo analisado divergiu. SHA-256: $GameExeHash"
}
$BaselineRanges = Get-FunctionRanges $RangesFile
if ($BaselineRanges.Count -ne $ExpectedBaselineFunctions) {
    throw "S1-257 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $($BaselineRanges.Count)"
}
$ActiveSeeds = Get-ActiveSeeds $SeedFile
if ($ActiveSeeds.Count -ne $ExpectedBaselineSeedCount) {
    throw "S1-257 deveria conter $ExpectedBaselineSeedCount seeds ativas; encontrado: $($ActiveSeeds.Count)"
}
if (@($ActiveSeeds | Sort-Object -Unique).Count -ne $ActiveSeeds.Count) {
    throw "O arquivo principal contem seeds ativas duplicadas."
}
if (@($ActiveSeeds | Where-Object { $_ -eq $RootSeed }).Count -ne 0) {
    throw "A candidata S1-258 ja esta ativa nas seeds principais: $RootSeed"
}
if ($BaselineRanges.ContainsKey($RootAddressText)) {
    throw "A candidata S1-258 ja pertence aos ranges da baseline: F $RootAddressText"
}
foreach ($Address in $ForbiddenFunctions) {
    if ($BaselineRanges.ContainsKey($Address)) {
        throw "Funcao que deve permanecer fora da S1-258 ja esta nativa: 0x$Address"
    }
}

[uint32]$RootAddress = [Convert]::ToUInt32($RootAddressText, 16)
$RootBody = Get-ExecutableRangeBytes $GameExe $RootAddress $RootLength
if ((Get-BytesSha256 $RootBody) -ne $RootBodySha256) {
    throw "Corpo 0x$RootAddressText divergente."
}
if (($RootLength / 4) -ne $RootWords) {
    throw "Boundary 0x$RootAddressText nao corresponde a $RootWords palavras."
}
$Flow = Get-MipsFlow $RootBody $RootAddress
Assert-ExactList @($Flow.DirectJalTargets | Sort-Object -Unique) $ExpectedDirectJalTargets "Alvos JAL da raiz"
Assert-ExactList $Flow.JalrSites @("80175840", "80175880") "Sites JALR da raiz"
Assert-ExactList $Flow.JrSites @("801756A8", "801758C0") "Sites JR da raiz"
Assert-ExactList $Flow.BranchTargets @("801758B4") "Branches da raiz"
Assert-ExactList $Flow.JumpTargets @("801758B4", "801758B4", "801758B4", "801758B4", "801758B4") "Jumps absolutos da raiz"
Assert-InternalTargets $Flow.BranchTargets $RootAddress $RootLength "Branch da raiz"
Assert-InternalTargets $Flow.JumpTargets $RootAddress $RootLength "Jump absoluto da raiz"
if ($Flow.ForbiddenSites.Count -ne 0) {
    throw "A raiz contem COP2, syscall, break, MULT ou DIV nao aprovados."
}
foreach ($Target in $ExpectedDirectJalTargets) {
    if (-not $BaselineRanges.ContainsKey($Target)) {
        throw "Alvo JAL direto ainda nao e nativo na S1-257: 0x$Target"
    }
}

$JumpTableBytes = Get-ExecutableRangeBytes $GameExe $JumpTableAddress $JumpTableLength
if ((Get-BytesSha256 $JumpTableBytes) -ne $JumpTableSha256) {
    throw "Jump table 0x801AC9C0 divergente."
}
$JumpTableTargets = @()
foreach ($Offset in 0..18) {
    $JumpTableTargets += [BitConverter]::ToUInt32($JumpTableBytes, $Offset * 4).ToString("X8")
}
Assert-ExactList $JumpTableTargets $ExpectedJumpTableTargets "Jump table 0x801AC9C0"
Assert-InternalTargets $JumpTableTargets $RootAddress $RootLength "Jump table 0x801AC9C0"

if ($ValidateOnly) {
    Write-Host "Validacao estatica S1-258 concluida."
    Write-Host "Baseline S1-257, seed, boundary, 19 alvos JAL e jump table interna: OK"
    Write-Host "Orcamento rigido: uma funcao e 151 palavras."
    Write-Host "Nenhuma previa foi gerada; seeds/fontes principais, BIOS e build nao foram alterados."
    return
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

$MainArtifacts = @(
    $GameConfig, $SeedFile, $RangesFile, $FullCFile, $DispatchCFile,
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

try {
    New-Item -ItemType Directory -Path $PreviewGenerated -Force | Out-Null
    Copy-Item -LiteralPath $SeedFile -Destination $PreviewSeed
    $SeedAppend = "`r`n# Previa isolada S1-258: dispatcher permanente da tela Mode Select.`r`n"
    $SeedAppend += "# Gate exato: uma funcao e 151 palavras; nenhuma closure adicional permitida.`r`n"
    $SeedAppend += "$RootSeed`r`n"
    [IO.File]::AppendAllText($PreviewSeed, $SeedAppend, [Text.UTF8Encoding]::new($false))

    $ConfigText = Get-Content -Raw -LiteralPath $GameConfig
    $ConfigText = $ConfigText -replace '(?m)^exe\s*=.*$', ('exe = "{0}"' -f (Convert-ToTomlPath $GameExe))
    $ConfigText = $ConfigText -replace '(?m)^disc\s*=.*$', ('disc = "{0}"' -f (Convert-ToTomlPath $GameDisc))
    $ConfigText = $ConfigText -replace '(?m)^seeds\s*=.*$', ('seeds = "{0}"' -f (Convert-ToTomlPath $PreviewSeed))
    $ConfigText = $ConfigText -replace '(?m)^out_dir\s*=.*$', ('out_dir = "{0}"' -f (Convert-ToTomlPath $PreviewGenerated))
    [IO.File]::WriteAllText($PreviewConfig, $ConfigText, [Text.UTF8Encoding]::new($false))

    Write-Host "Gerando somente na area isolada: $RunDir"
    & $RecompilerPath --config $PreviewConfig | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "A geracao isolada S1-258 falhou com codigo $LASTEXITCODE"
    }
    Require-File $PreviewRanges

    $PreviewMap = Get-FunctionRanges $PreviewRanges
    if ($PreviewMap.Count -ne $ExpectedPreviewFunctions) {
        throw "S1-258 deveria conter $ExpectedPreviewFunctions funcoes; encontrado: $($PreviewMap.Count)"
    }
    foreach ($Address in $BaselineRanges.Keys) {
        if (-not $PreviewMap.ContainsKey($Address) -or $PreviewMap[$Address] -ne $BaselineRanges[$Address]) {
            throw "Range aprovado desapareceu ou mudou na previa: F $Address"
        }
    }
    $Added = @($PreviewMap.Keys | Where-Object { -not $BaselineRanges.ContainsKey($_) } | Sort-Object)
    Assert-ExactList $Added @($RootAddressText) "Closure S1-258"
    if ($PreviewMap[$RootAddressText] -ne "25C") {
        throw "Range da raiz divergente. Esperado: 25C; obtido: $($PreviewMap[$RootAddressText])"
    }
    [int64]$MeasuredAddedWords = [Convert]::ToInt64($PreviewMap[$RootAddressText], 16) / 4
    if ($MeasuredAddedWords -ne $ExpectedAddedWords) {
        throw "S1-258 deveria adicionar $ExpectedAddedWords palavras; medido: $MeasuredAddedWords"
    }
    foreach ($Address in $ForbiddenFunctions) {
        if ($PreviewMap.ContainsKey($Address)) {
            throw "Funcao proibida apareceu na previa: F $Address"
        }
    }

    Write-Host "Executando auditoria codegen somente na previa isolada..."
    & $PythonPath $AuditScript --config $PreviewConfig | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "A auditoria codegen da previa falhou com codigo $LASTEXITCODE"
    }

    $PreviewHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PreviewRanges).Hash
    $ProjectedPercent = [Math]::Round(100.0 * $ExpectedProjectedWords / $TotalGameWords, 4)
    $Summary = @"
# Pre-auditoria S1-258

- Baseline S1-257: $ExpectedBaselineFunctions funcoes, $ExpectedBaselineCoverageWords palavras
- Baseline ranges SHA-256: $BaselineHash
- Funcao adicionada: 0x$RootAddressText
- Boundary: 0x8017566C..0x801758C7
- Palavras adicionadas: $MeasuredAddedWords
- Funcoes projetadas: $($PreviewMap.Count)
- Cobertura projetada: $ExpectedProjectedWords/$TotalGameWords palavras ($($ProjectedPercent.ToString('F4'))%)
- Ranges SHA-256 da previa: $PreviewHash
- JAL diretos: 24 sites, 19 destinos distintos; todos nativos na baseline
- Jump table 0x801AC9C0: 19 entradas, nove destinos internos
- JALR dinamicos: 0x80175840 e 0x80175880
- Localizacao runtime: Mode Select, aproximadamente uma chamada interpretada por frame
- Auditoria codegen: CLEAN
- Seeds/fontes principais, BIOS e build: preservados
"@
    [IO.File]::WriteAllText((Join-Path $RunDir "summary.md"), $Summary, [Text.UTF8Encoding]::new($false))

    Write-Host ""
    Write-Host "Previa isolada S1-258 aprovada."
    Write-Host "Funcao adicionada: $RootAddressText"
    Write-Host "Palavras adicionadas: $MeasuredAddedWords"
    Write-Host "Funcoes projetadas: $($PreviewMap.Count)"
    Write-Host "Cobertura projetada: $ExpectedProjectedWords/$TotalGameWords palavras ($($ProjectedPercent.ToString('F4'))%)"
    Write-Host "Ranges SHA-256 da previa: $PreviewHash"
    Write-Host "Resumo: $(Join-Path $RunDir 'summary.md')"
    Write-Host "Seeds/fontes principais, BIOS e build nao foram alterados."
}
finally {
    foreach ($Artifact in $MainArtifacts) {
        $AfterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Artifact).Hash
        if ($AfterHash -ne $MainHashes[$Artifact]) {
            throw "A previa alterou um artefato principal protegido: $Artifact"
        }
    }
}
