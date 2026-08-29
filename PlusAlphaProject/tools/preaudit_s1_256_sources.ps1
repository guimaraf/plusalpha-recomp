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

$ExpectedBaselineRangesSha256 = "30BCD2340878A0C9057CA4B8A66F582A0695AF844B1E45E9409678951D76D404"
$ExpectedBaselineSeedsSha256 = "E7B5FECE7D17FE988E2C85DB0CF8777308DAB38D3F44F5CDA5A3749DD01872FA"
$ExpectedBaselineFunctions = 1049
$ExpectedBaselineCoverageWords = 110494
$ExpectedBaselineSeedCount = 532

$ExpectedDirectFunctions = 1054
$ExpectedDirectWords = 586
$ExpectedDirectRangesSha256 = "2F3A18F08ED029E7D5D7227E60DC6AA38367187D9D9DD9DE2DD91C4713BBA7E1"

$ExpectedFullFunctions = 1055
$ExpectedFullWords = 622
$ExpectedProjectedWords = 111116
$TotalGameWords = 195584

$RootSeed = "0x8016FC28"
$IndirectSeed = "0x801930BC"
$QuarantinedSeed = "0x8019E6D0"

$Candidates = @(
    [pscustomobject]@{
        Address = "8016FC28"
        Length = 0x9C
        Words = 39
        BodySha256 = "9E15A9FD03FA579BD376D8D0351DD0B2E48D4816FBC9664E0C0BA67FDC0DEE54"
        DirectTargets = @("8016FCC4", "80177474", "8018F10C", "80191C84")
        JalrSites = @()
        JrSites = @("8016FC58", "8016FCBC")
    },
    [pscustomobject]@{
        Address = "801910A4"
        Length = 0x234
        Words = 141
        BodySha256 = "477AFA262A9232017D2F42BF7FB0EB6D7696CD188D998238B4C733AE602462D9"
        DirectTargets = @()
        JalrSites = @()
        JrSites = @("801911C0", "801912D0")
    },
    [pscustomobject]@{
        Address = "801914C0"
        Length = 0xC8
        Words = 50
        BodySha256 = "2AD855986EA8AFCFC08E74C15336143D1DAF15DAE99DC055D54999F5B7F85D9F"
        DirectTargets = @("8010C72C")
        JalrSites = @()
        JrSites = @("80191580")
    },
    [pscustomobject]@{
        Address = "80191C84"
        Length = 0x4A4
        Words = 297
        BodySha256 = "AC9ACBAD5B0796F3E368561989C56EDBC32D59CA820940AB59804FECD536ABF0"
        DirectTargets = @(
            "80101D18", "80101D68", "8010C72C", "8012398C",
            "80123BA8", "80123E8C", "8012CCF0", "80168D14",
            "801910A4", "801914C0", "80192D6C", "801931FC",
            "8019326C", "8019327C", "801938B0", "801A75F4"
        )
        JalrSites = @("80191E68", "8019209C")
        JrSites = @("80192120")
    },
    [pscustomobject]@{
        Address = "80192D6C"
        Length = 0xEC
        Words = 59
        BodySha256 = "A0C54BC35960F6F089BB31AB1594AA47A9A4CC199A3EA137652AE19476D64A38"
        DirectTargets = @("80168D14")
        JalrSites = @()
        JrSites = @("80192E50")
    },
    [pscustomobject]@{
        Address = "801930BC"
        Length = 0x90
        Words = 36
        BodySha256 = "5517E77195FAC935A53239E03F694A61EB20463795186296C8516D2B6EEB34AE"
        DirectTargets = @(
            "80123E8C", "801931FC", "8019326C", "8019327C", "801A75F4"
        )
        JalrSites = @("80193134")
        JrSites = @("80193144")
    }
)

$ExpectedDirectRanges = [ordered]@{
    "8016FC28" = "9C"
    "801910A4" = "234"
    "801914C0" = "C8"
    "80191C84" = "4A4"
    "80192D6C" = "EC"
}

$ExpectedFullRanges = [ordered]@{
    "8016FC28" = "9C"
    "801910A4" = "234"
    "801914C0" = "C8"
    "80191C84" = "4A4"
    "80192D6C" = "EC"
    "801930BC" = "90"
}

$IndirectTableTargets = @(
    "80192128", "80193174", "801930BC",
    "8019319C", "801931C4", "80192F60"
)

$ForbiddenFunctions = @(
    "80103384", "8017566C", "8019E6D0",
    "80192128", "80193174", "8019319C", "801931C4", "80192F60"
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
            [uint32]$Target = $TargetValue
            $Targets += $Target.ToString("X8")
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
            [uint32]$Target = $TargetValue
            $Targets += $Target.ToString("X8")
        }
    }
    return @($Targets | Sort-Object -Unique)
}

function Assert-ExactList(
    [string[]]$Actual,
    [string[]]$Expected,
    [string]$Description
) {
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

function Get-UInt32Words([byte[]]$Bytes) {
    $Words = @()
    for ($Offset = 0; $Offset -lt $Bytes.Length; $Offset += 4) {
        $Words += [BitConverter]::ToUInt32($Bytes, $Offset).ToString("X8")
    }
    return @($Words)
}

function New-PreviewDirectory {
    New-Item -ItemType Directory -Path $PreviewRoot -Force | Out-Null
    foreach ($Number in 1..99) {
        $Path = Join-Path $PreviewRoot ("s1-256-preview-{0:D2}" -f $Number)
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path | Out-Null
            return $Path
        }
    }
    throw "Nao ha preview-id livre entre s1-256-preview-01 e 99."
}

function Convert-ToTomlPath([string]$Path) {
    return ([IO.Path]::GetFullPath($Path)).Replace("\", "/")
}

function Invoke-PreviewStage(
    [string]$RunDir,
    [string]$StageName,
    [string[]]$ExtraSeeds,
    [System.Collections.IDictionary]$ExpectedAddedRanges,
    [int]$ExpectedFunctions,
    [int]$ExpectedAddedWords,
    [string]$ExpectedRangesSha256
) {
    $StageDir = Join-Path $RunDir $StageName
    $PreviewSeed = Join-Path $StageDir "entry_funcs.preview.txt"
    $PreviewGenerated = Join-Path $StageDir "generated"
    $PreviewConfig = Join-Path $StageDir "game.preview.toml"
    $PreviewRanges = Join-Path $PreviewGenerated "SLUS_005.48_full.ranges"

    New-Item -ItemType Directory -Path $PreviewGenerated -Force | Out-Null
    Copy-Item -LiteralPath $SeedFile -Destination $PreviewSeed

    $SeedAppend = "`r`n# Previa isolada S1-256: $StageName.`r`n"
    $SeedAppend += "# Gate exato: $ExpectedAddedWords palavras novas; nenhuma expansao adicional e permitida.`r`n"
    foreach ($Seed in $ExtraSeeds) {
        $SeedAppend += "$Seed`r`n"
    }
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

    Write-Host ""
    Write-Host "Gerando $StageName somente na area isolada: $StageDir"
    & $RecompilerPath --config $PreviewConfig | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "A geracao isolada $StageName falhou com codigo $LASTEXITCODE"
    }
    Require-File $PreviewRanges

    $PreviewMap = Get-FunctionRanges $PreviewRanges
    if ($PreviewMap.Count -ne $ExpectedFunctions) {
        throw "$StageName deveria conter $ExpectedFunctions funcoes; encontrado: $($PreviewMap.Count)"
    }
    foreach ($Address in $BaselineRanges.Keys) {
        if (
            -not $PreviewMap.ContainsKey($Address) -or
            $PreviewMap[$Address] -ne $BaselineRanges[$Address]
        ) {
            throw "Range aprovado desapareceu ou mudou em ${StageName}: F $Address"
        }
    }

    $Added = @(
        $PreviewMap.Keys |
            Where-Object { -not $BaselineRanges.ContainsKey($_) } |
            Sort-Object
    )
    $ExpectedAdded = @($ExpectedAddedRanges.Keys | Sort-Object)
    Assert-ExactList -Actual $Added -Expected $ExpectedAdded -Description "Closure de $StageName"

    [int64]$MeasuredAddedWords = 0
    foreach ($Address in $ExpectedAdded) {
        $ExpectedLength = $ExpectedAddedRanges[$Address].ToUpperInvariant()
        if ($PreviewMap[$Address] -ne $ExpectedLength) {
            throw "Range divergente em $StageName para 0x$Address. Esperado: $ExpectedLength; obtido: $($PreviewMap[$Address])"
        }
        $MeasuredAddedWords += [Convert]::ToInt64($PreviewMap[$Address], 16) / 4
    }
    if ($MeasuredAddedWords -ne $ExpectedAddedWords) {
        throw "$StageName deveria adicionar $ExpectedAddedWords palavras; medido: $MeasuredAddedWords"
    }

    foreach ($Address in $ForbiddenFunctions) {
        if ($PreviewMap.ContainsKey($Address)) {
            throw "Funcao proibida apareceu em ${StageName}: F $Address"
        }
    }

    $PreviewHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PreviewRanges).Hash
    if ($ExpectedRangesSha256 -and $PreviewHash -ne $ExpectedRangesSha256) {
        throw "SHA-256 de $StageName divergente. Esperado: $ExpectedRangesSha256; obtido: $PreviewHash"
    }

    Write-Host "Executando auditoria codegen apenas em $StageName..."
    & $PythonPath $AuditScript --config $PreviewConfig | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "A auditoria codegen de $StageName falhou com codigo $LASTEXITCODE"
    }

    $StageSummary = @"
# Pre-auditoria S1-256 - $StageName

- Baseline S1-255 SHA-256: $BaselineHash
- Funcoes na baseline: $ExpectedBaselineFunctions
- Funcoes na previa: $($PreviewMap.Count)
- Funcoes adicionadas: $($Added -join ', ')
- Palavras adicionadas: $MeasuredAddedWords
- Ranges SHA-256: $PreviewHash
- Auditoria codegen: CLEAN
- Fontes principais, BIOS e build: nao alterados
"@
    [IO.File]::WriteAllText(
        (Join-Path $StageDir "summary.md"),
        $StageSummary,
        [Text.UTF8Encoding]::new($false)
    )

    return [pscustomobject]@{
        Name = $StageName
        Directory = $StageDir
        Added = $Added
        AddedWords = $MeasuredAddedWords
        Functions = $PreviewMap.Count
        RangesSha256 = $PreviewHash
    }
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
    throw "Baseline nao corresponde ao checkpoint S1-255. SHA-256: $BaselineHash"
}
$BaselineRanges = Get-FunctionRanges $RangesFile
if ($BaselineRanges.Count -ne $ExpectedBaselineFunctions) {
    throw "S1-255 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $($BaselineRanges.Count)"
}
$SeedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SeedFile).Hash
if ($SeedHash -ne $ExpectedBaselineSeedsSha256) {
    throw "Seeds principais nao correspondem ao checkpoint S1-255. SHA-256: $SeedHash"
}
$ActiveSeeds = Get-ActiveSeeds $SeedFile
if ($ActiveSeeds.Count -ne $ExpectedBaselineSeedCount) {
    throw "S1-255 deveria conter $ExpectedBaselineSeedCount seeds ativas; encontrado: $($ActiveSeeds.Count)"
}
if (@($ActiveSeeds | Sort-Object -Unique).Count -ne $ActiveSeeds.Count) {
    throw "O arquivo principal contem seeds ativas duplicadas."
}
foreach ($Seed in @($RootSeed, $IndirectSeed, $QuarantinedSeed)) {
    if ((Count-ExactSeed $ActiveSeeds $Seed) -ne 0) {
        throw "Seed que deve permanecer inativa apareceu no arquivo principal: $Seed"
    }
}
foreach ($Address in $ExpectedFullRanges.Keys) {
    if ($BaselineRanges.ContainsKey($Address)) {
        throw "Candidata S1-256 ja pertence aos ranges da baseline: F $Address"
    }
}

$AllowedNewTargets = @($ExpectedFullRanges.Keys)
foreach ($Candidate in $Candidates) {
    [uint32]$Address = [Convert]::ToUInt32($Candidate.Address, 16)
    $Body = Get-ExecutableRangeBytes $GameExe $Address $Candidate.Length
    $ActualBodyHash = Get-BytesSha256 $Body
    if ($ActualBodyHash -ne $Candidate.BodySha256) {
        throw "Corpo 0x$($Candidate.Address) divergente. SHA-256: $ActualBodyHash"
    }
    if (($Candidate.Length / 4) -ne $Candidate.Words) {
        throw "Boundary 0x$($Candidate.Address) nao corresponde a $($Candidate.Words) palavras."
    }

    $ActualDirectTargets = @(Get-DirectJalTargets $Body $Address)
    $ExpectedTargets = @($Candidate.DirectTargets | Sort-Object -Unique)
    Assert-ExactList -Actual $ActualDirectTargets -Expected $ExpectedTargets -Description "Alvos JAL de 0x$($Candidate.Address)"
    foreach ($Target in $ActualDirectTargets) {
        if (-not $BaselineRanges.ContainsKey($Target) -and $Target -notin $AllowedNewTargets) {
            throw "Alvo JAL fora da baseline e da closure aprovada: 0x$Target"
        }
    }

    $ActualJalrSites = @(Get-MipsSites $Body $Address "jalr")
    Assert-ExactList -Actual $ActualJalrSites -Expected $Candidate.JalrSites -Description "Sites JALR de 0x$($Candidate.Address)"
    $ActualJrSites = @(Get-MipsSites $Body $Address "jr")
    Assert-ExactList -Actual $ActualJrSites -Expected $Candidate.JrSites -Description "Sites JR de 0x$($Candidate.Address)"

    $ForbiddenSites = @(Get-MipsSites $Body $Address "forbidden")
    if ($ForbiddenSites.Count -ne 0) {
        throw "Instrucao de risco nao aprovada em 0x$($Candidate.Address): $($ForbiddenSites -join ', ')"
    }

    $AbsoluteTargets = @(Get-AbsoluteJumpTargets $Body $Address)
    Assert-InternalTargets $AbsoluteTargets $Address $Candidate.Length "Jump absoluto de 0x$($Candidate.Address)"
}

$RootTableBytes = Get-ExecutableRangeBytes $GameExe ([Convert]::ToUInt32("801AC894", 16)) 0x28
if ((Get-BytesSha256 $RootTableBytes) -ne "1AABC8F933EE1BFF755D387263142D891DD8EC0456BFB750527041A55BFD6B78") {
    throw "Jump table 0x801AC894 divergente."
}
Assert-InternalTargets (Get-UInt32Words $RootTableBytes) ([Convert]::ToUInt32("8016FC28", 16)) 0x9C "Jump table 0x801AC894"

$CharacterTableBytes = Get-ExecutableRangeBytes $GameExe ([Convert]::ToUInt32("801AE6D8", 16)) 0x150
if ((Get-BytesSha256 $CharacterTableBytes) -ne "A07A0B997FAAE6C47DDCF757160A09AE95BB24600FB88580C9FCD6A1F75780BC") {
    throw "Jump table 0x801AE6D8 divergente."
}
Assert-InternalTargets (Get-UInt32Words $CharacterTableBytes) ([Convert]::ToUInt32("801910A4", 16)) 0x234 "Jump table 0x801AE6D8"

$IndirectTableBytes = Get-ExecutableRangeBytes $GameExe ([Convert]::ToUInt32("801B8538", 16)) 0x18
if ((Get-BytesSha256 $IndirectTableBytes) -ne "03C177130E6FA58E4C8726C3D3FDF08821D018C8FDDB122F01F9C97C138F9AE7") {
    throw "Tabela indireta 0x801B8538 divergente."
}
Assert-ExactList -Actual (Get-UInt32Words $IndirectTableBytes) -Expected $IndirectTableTargets -Description "Destinos da tabela 0x801B8538"

if ($ValidateOnly) {
    Write-Host "Validacao estatica S1-256 concluida."
    Write-Host "Baseline, seeds, seis corpos, chamadas e tabelas: OK"
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
try {
    Write-Host "Baseline S1-255 e auditoria estatica confirmadas."
    Write-Host "Nenhuma seed principal sera alterada; as duas etapas usam somente: $RunDir"

    $Stage1 = Invoke-PreviewStage `
        -RunDir $RunDir `
        -StageName "stage1-direct-closure" `
        -ExtraSeeds @($RootSeed) `
        -ExpectedAddedRanges $ExpectedDirectRanges `
        -ExpectedFunctions $ExpectedDirectFunctions `
        -ExpectedAddedWords $ExpectedDirectWords `
        -ExpectedRangesSha256 $ExpectedDirectRangesSha256

    $Stage2 = Invoke-PreviewStage `
        -RunDir $RunDir `
        -StageName "stage2-full-batch" `
        -ExtraSeeds @($RootSeed, $IndirectSeed) `
        -ExpectedAddedRanges $ExpectedFullRanges `
        -ExpectedFunctions $ExpectedFullFunctions `
        -ExpectedAddedWords $ExpectedFullWords `
        -ExpectedRangesSha256 ""

    $ProjectedPercent = [Math]::Round(100.0 * $ExpectedProjectedWords / $TotalGameWords, 4)
    $Summary = @"
# Pre-auditoria S1-256

- Baseline S1-255: $ExpectedBaselineFunctions funcoes, $ExpectedBaselineCoverageWords palavras de cobertura registrada
- Baseline ranges SHA-256: $BaselineHash
- Etapa 1: cinco funcoes da closure direta, $($Stage1.AddedWords) palavras
- Etapa 1 ranges SHA-256: $($Stage1.RangesSha256)
- Etapa 2: seis funcoes no lote completo, $($Stage2.AddedWords) palavras
- Funcoes projetadas: $($Stage2.Functions)
- Cobertura projetada: $ExpectedProjectedWords/$TotalGameWords palavras ($($ProjectedPercent.ToString('F4'))%)
- Etapa 2 ranges SHA-256: $($Stage2.RangesSha256)
- Destino indireto promovido por evidencia: 0x801930BC
- Outros cinco destinos da tabela 0x801B8538: fora do lote
- Auditoria codegen das duas etapas: CLEAN
- Seeds/fontes principais, BIOS e build: preservados
"@
    [IO.File]::WriteAllText(
        (Join-Path $RunDir "summary.md"),
        $Summary,
        [Text.UTF8Encoding]::new($false)
    )

    Write-Host ""
    Write-Host "Previa isolada S1-256 aprovada."
    Write-Host "Etapa 1: $($Stage1.Added.Count) funcoes, $($Stage1.AddedWords) palavras, SHA-256 $($Stage1.RangesSha256)"
    Write-Host "Etapa 2: $($Stage2.Added.Count) funcoes, $($Stage2.AddedWords) palavras, SHA-256 $($Stage2.RangesSha256)"
    Write-Host "Funcoes projetadas: $($Stage2.Functions)"
    Write-Host "Cobertura projetada: $ExpectedProjectedWords/$TotalGameWords palavras ($($ProjectedPercent.ToString('F4'))%)"
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
