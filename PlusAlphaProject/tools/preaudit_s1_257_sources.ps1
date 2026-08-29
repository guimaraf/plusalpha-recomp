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

$ExpectedBaselineRangesSha256 = "300F1B44336410C0F0DADAF746D2973D27ABCCF4EB391A36891D827DA67057C6"
$ExpectedBaselineSeedsSha256 = "D699266A1420A8E3083E799B644B3705E0F04875962DE2B54955DE2B4EA95BDD"
$ExpectedBaselineFunctions = 1055
$ExpectedBaselineCoverageWords = 111116
$ExpectedBaselineSeedCount = 534
$ExpectedPreviewFunctions = 1056
$ExpectedAddedWords = 30
$ExpectedProjectedWords = 111146
$TotalGameWords = 195584

$RootSeed = "0x8019FC6C"
$RootAddressText = "8019FC6C"
$RootLength = 0x78
$RootWords = 30
$RootBodySha256 = "02427D01908F1F36539549CBE3C02C69E2BA4F24F4F240A186909D3A26D926CE"
$InitializerAddress = [Convert]::ToUInt32("8019FC14", 16)
$InitializerLength = 0x58
$InitializerSha256 = "248F4E027829F8E354357C6989248D5E32F52D0A40C995483B05697870CE006E"
$SetterAddress = [Convert]::ToUInt32("8019FCE4", 16)
$SetterLength = 0x2C
$SetterSha256 = "64EAF0108FDAF088D3A5EB4899D9461F331464ECE163EF57D405755A7F400A87"

$ExpectedAddedRanges = [ordered]@{
    "8019FC6C" = "78"
}

$ForbiddenFunctions = @(
    "80103384", "8016A84C", "8016AE18", "8017566C",
    "8019E6D0", "8019FCE4"
)

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

function Count-ExactSeed([string[]]$Seeds, [string]$Seed) {
    return @($Seeds | Where-Object { $_ -eq $Seed.ToUpperInvariant() }).Count
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

function Get-ExecutableRangeSha256(
    [string]$Path,
    [uint32]$VirtualAddress,
    [int]$Length
) {
    return Get-BytesSha256 (Get-ExecutableRangeBytes $Path $VirtualAddress $Length)
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

function Get-MipsSites(
    [byte[]]$Bytes,
    [uint32]$StartAddress,
    [ValidateSet("jalr", "jr", "forbidden")][string]$Kind
) {
    $Sites = @()
    for ($Offset = 0; $Offset -lt $Bytes.Length; $Offset += 4) {
        $Pc = $StartAddress + [uint32]$Offset
        $Word = [BitConverter]::ToUInt32($Bytes, $Offset)
        $Opcode = $Word -shr 26
        $Function = $Word -band 0x3F
        $Match = $false
        if ($Kind -eq "jalr") {
            $Match = ($Opcode -eq 0 -and $Function -eq 0x09)
        }
        elseif ($Kind -eq "jr") {
            $Match = ($Opcode -eq 0 -and $Function -eq 0x08)
        }
        else {
            $Match = (
                $Opcode -eq 0x12 -or
                ($Opcode -eq 0 -and $Function -in 0x0C, 0x0D, 0x18, 0x19, 0x1A, 0x1B)
            )
        }
        if ($Match) {
            $Sites += $Pc.ToString("X8")
        }
    }
    return @($Sites)
}

function Get-DirectJalTargets([byte[]]$Bytes, [uint32]$StartAddress) {
    $Targets = @()
    for ($Offset = 0; $Offset -lt $Bytes.Length; $Offset += 4) {
        $Pc = $StartAddress + [uint32]$Offset
        $Word = [BitConverter]::ToUInt32($Bytes, $Offset)
        if (($Word -shr 26) -eq 0x03) {
            [uint64]$TargetValue = (
                (([uint64]$Pc + 4) -band [uint64]([Convert]::ToUInt32("F0000000", 16))) -bor
                (([uint64]($Word -band 0x03FFFFFF)) -shl 2)
            )
            $Targets += ([uint32]$TargetValue).ToString("X8")
        }
    }
    return @($Targets | Sort-Object -Unique)
}

function Get-BranchTargets([byte[]]$Bytes, [uint32]$StartAddress) {
    $Targets = @()
    for ($Offset = 0; $Offset -lt $Bytes.Length; $Offset += 4) {
        $Pc = $StartAddress + [uint32]$Offset
        $Word = [BitConverter]::ToUInt32($Bytes, $Offset)
        $Opcode = $Word -shr 26
        if ($Opcode -in 0x01, 0x04, 0x05, 0x06, 0x07) {
            [int32]$ImmediateUnsigned = $Word -band 0xFFFF
            [int32]$Immediate = $ImmediateUnsigned
            if (($ImmediateUnsigned -band 0x8000) -ne 0) {
                $Immediate -= 0x10000
            }
            [int64]$TargetValue = [int64]$Pc + 4 + ([int64]$Immediate * 4)
            $Targets += ([uint32]$TargetValue).ToString("X8")
        }
    }
    return @($Targets | Sort-Object -Unique)
}

function Get-AbsoluteJumpTargets([byte[]]$Bytes, [uint32]$StartAddress) {
    $Targets = @()
    for ($Offset = 0; $Offset -lt $Bytes.Length; $Offset += 4) {
        $Pc = $StartAddress + [uint32]$Offset
        $Word = [BitConverter]::ToUInt32($Bytes, $Offset)
        if (($Word -shr 26) -eq 0x02) {
            [uint64]$TargetValue = (
                (([uint64]$Pc + 4) -band [uint64]([Convert]::ToUInt32("F0000000", 16))) -bor
                (([uint64]($Word -band 0x03FFFFFF)) -shl 2)
            )
            $Targets += ([uint32]$TargetValue).ToString("X8")
        }
    }
    return @($Targets | Sort-Object -Unique)
}

function Assert-ExactList(
    [string[]]$Actual,
    [string[]]$Expected,
    [string]$Description
) {
    $ActualNormalized = @(
        $Actual | Where-Object { $_ } | ForEach-Object { $_.ToUpperInvariant() }
    )
    $ExpectedNormalized = @(
        $Expected | Where-Object { $_ } | ForEach-Object { $_.ToUpperInvariant() }
    )
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
        $Path = Join-Path $PreviewRoot ("s1-257-preview-{0:D2}" -f $Number)
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path | Out-Null
            return $Path
        }
    }
    throw "Nao ha preview-id livre entre s1-257-preview-01 e 99."
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
    if (-not $PythonCommand) {
        throw "Python nao foi encontrado. Informe -PythonPath."
    }
    $PythonPath = $PythonCommand.Source
}

$BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
if ($BaselineHash -ne $ExpectedBaselineRangesSha256) {
    throw "Baseline nao corresponde a S1-256. SHA-256: $BaselineHash"
}
$BaselineRanges = Get-FunctionRanges $RangesFile
if ($BaselineRanges.Count -ne $ExpectedBaselineFunctions) {
    throw "S1-256 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $($BaselineRanges.Count)"
}
$SeedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SeedFile).Hash
if ($SeedHash -ne $ExpectedBaselineSeedsSha256) {
    throw "Seeds principais nao correspondem a S1-256. SHA-256: $SeedHash"
}
$ActiveSeeds = Get-ActiveSeeds $SeedFile
if ($ActiveSeeds.Count -ne $ExpectedBaselineSeedCount) {
    throw "S1-256 deveria conter $ExpectedBaselineSeedCount seeds ativas; encontrado: $($ActiveSeeds.Count)"
}
if (@($ActiveSeeds | Sort-Object -Unique).Count -ne $ActiveSeeds.Count) {
    throw "O arquivo principal contem seeds ativas duplicadas."
}
if ((Count-ExactSeed $ActiveSeeds $RootSeed) -ne 0) {
    throw "A candidata S1-257 ja esta ativa nas seeds principais: $RootSeed"
}
if ($BaselineRanges.ContainsKey($RootAddressText)) {
    throw "A candidata S1-257 ja pertence aos ranges da baseline: F $RootAddressText"
}
foreach ($Address in $ForbiddenFunctions) {
    if ($BaselineRanges.ContainsKey($Address) -or (Count-ExactSeed $ActiveSeeds ("0x" + $Address)) -ne 0) {
        throw "Funcao que deve permanecer fora da S1-257 ja esta ativa: 0x$Address"
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
Assert-ExactList (Get-DirectJalTargets $RootBody $RootAddress) @() "Alvos JAL da raiz"
Assert-ExactList (Get-MipsSites $RootBody $RootAddress "jalr") @("8019FCB4") "Sites JALR da raiz"
Assert-ExactList (Get-MipsSites $RootBody $RootAddress "jr") @("8019FCDC") "Sites JR da raiz"
Assert-ExactList (Get-BranchTargets $RootBody $RootAddress) @("8019FCA4", "8019FCBC") "Branches da raiz"
Assert-ExactList (Get-AbsoluteJumpTargets $RootBody $RootAddress) @() "Jumps absolutos da raiz"
Assert-InternalTargets (Get-BranchTargets $RootBody $RootAddress) $RootAddress $RootLength "Branch da raiz"
if (@(Get-MipsSites $RootBody $RootAddress "forbidden").Count -ne 0) {
    throw "A raiz contem COP2, syscall, break, MULT ou DIV nao aprovados."
}

if ((Get-ExecutableRangeSha256 $GameExe $InitializerAddress $InitializerLength) -ne $InitializerSha256) {
    throw "Inicializador 0x8019FC14 divergente."
}
if ((Get-ExecutableRangeSha256 $GameExe $SetterAddress $SetterLength) -ne $SetterSha256) {
    throw "Setter 0x8019FCE4 divergente."
}

if ($ValidateOnly) {
    Write-Host "Validacao estatica S1-257 concluida."
    Write-Host "Baseline S1-256, seeds, boundary, fluxo e vizinhos do callback: OK"
    Write-Host "Evidencia runtime exigida: oito slots 0x801BEEC4 zerados em titulo e Versus."
    Write-Host "Nenhuma previa foi gerada; seeds/fontes principais, BIOS e build nao foram alterados."
    return
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
    $SeedAppend = "`r`n# Previa isolada S1-257: dispatcher da tela de titulo.`r`n"
    $SeedAppend += "# Gate exato: uma funcao e 30 palavras; nenhuma closure adicional permitida.`r`n"
    $SeedAppend += "$RootSeed`r`n"
    [IO.File]::AppendAllText($PreviewSeed, $SeedAppend, [Text.UTF8Encoding]::new($false))

    $ConfigText = Get-Content -Raw -LiteralPath $GameConfig
    $ConfigText = $ConfigText -replace '(?m)^exe\s*=.*$',
        ('exe = "{0}"' -f (Convert-ToTomlPath $GameExe))
    $ConfigText = $ConfigText -replace '(?m)^disc\s*=.*$',
        ('disc = "{0}"' -f (Convert-ToTomlPath $GameDisc))
    $ConfigText = $ConfigText -replace '(?m)^seeds\s*=.*$',
        ('seeds = "{0}"' -f (Convert-ToTomlPath $PreviewSeed))
    $ConfigText = $ConfigText -replace '(?m)^out_dir\s*=.*$',
        ('out_dir = "{0}"' -f (Convert-ToTomlPath $PreviewGenerated))
    [IO.File]::WriteAllText($PreviewConfig, $ConfigText, [Text.UTF8Encoding]::new($false))

    Write-Host "Gerando somente na area isolada: $RunDir"
    & $RecompilerPath --config $PreviewConfig | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "A geracao isolada S1-257 falhou com codigo $LASTEXITCODE"
    }
    Require-File $PreviewRanges

    $PreviewMap = Get-FunctionRanges $PreviewRanges
    if ($PreviewMap.Count -ne $ExpectedPreviewFunctions) {
        throw "S1-257 deveria conter $ExpectedPreviewFunctions funcoes; encontrado: $($PreviewMap.Count)"
    }
    foreach ($Address in $BaselineRanges.Keys) {
        if (-not $PreviewMap.ContainsKey($Address) -or $PreviewMap[$Address] -ne $BaselineRanges[$Address]) {
            throw "Range aprovado desapareceu ou mudou na previa: F $Address"
        }
    }

    $Added = @($PreviewMap.Keys | Where-Object { -not $BaselineRanges.ContainsKey($_) } | Sort-Object)
    Assert-ExactList $Added @($ExpectedAddedRanges.Keys) "Closure S1-257"
    if ($PreviewMap[$RootAddressText] -ne $ExpectedAddedRanges[$RootAddressText]) {
        throw "Range da raiz divergente. Esperado: 78; obtido: $($PreviewMap[$RootAddressText])"
    }
    [int64]$MeasuredAddedWords = [Convert]::ToInt64($PreviewMap[$RootAddressText], 16) / 4
    if ($MeasuredAddedWords -ne $ExpectedAddedWords) {
        throw "S1-257 deveria adicionar $ExpectedAddedWords palavras; medido: $MeasuredAddedWords"
    }
    foreach ($Address in $ForbiddenFunctions) {
        if ($PreviewMap.ContainsKey($Address)) {
            throw "Funcao proibida apareceu na previa: F $Address"
        }
    }

    $PreviewHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PreviewRanges).Hash
    Write-Host "Executando auditoria codegen somente na previa isolada..."
    & $PythonPath $AuditScript --config $PreviewConfig | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "A auditoria codegen da previa falhou com codigo $LASTEXITCODE"
    }

    $ProjectedPercent = [Math]::Round(100.0 * $ExpectedProjectedWords / $TotalGameWords, 4)
    $Summary = @"
# Pre-auditoria S1-257

- Baseline S1-256: $ExpectedBaselineFunctions funcoes, $ExpectedBaselineCoverageWords palavras
- Baseline ranges SHA-256: $BaselineHash
- Funcao adicionada: 0x$RootAddressText
- Boundary: 0x8019FC6C..0x8019FCE3
- Palavras adicionadas: $MeasuredAddedWords
- Funcoes projetadas: $($PreviewMap.Count)
- Cobertura projetada: $ExpectedProjectedWords/$TotalGameWords palavras ($($ProjectedPercent.ToString('F4'))%)
- Ranges SHA-256 da previa: $PreviewHash
- JAL diretos: zero
- JALR: 0x8019FCB4; retorno 0x8019FCBC
- Tabela 0x801BEEC4: oito slots zerados na tela de titulo e em Versus Ryu x Ken
- Auditoria codegen: CLEAN
- Seeds/fontes principais, BIOS e build: preservados
"@
    [IO.File]::WriteAllText(
        (Join-Path $RunDir "summary.md"),
        $Summary,
        [Text.UTF8Encoding]::new($false)
    )

    Write-Host ""
    Write-Host "Previa isolada S1-257 aprovada."
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
