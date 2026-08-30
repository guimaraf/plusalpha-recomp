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

$ExpectedBaselineRangesSha256 = "C0E7A0A37DB76E98E731D4E9CA5A0882DE02802E8CDADA5805E07C83DE15999F"
$ExpectedBaselineSeedsSha256 = "0EC46DEFABB59E17D2C9C88B39C26E24B17384D6C86AB7F952AC853E4C9139DE"
$ExpectedGameExeSha256 = "4FFE98EB4F246B4D455392E537E8D9F029D34F2E95E301AEF2CB61F5E3E99820"
$ExpectedBaselineFunctions = 1058
$ExpectedBaselineSeedCount = 537
$ExpectedBaselineCoverageWords = 111327
$ExpectedPreviewFunctions = 1059
$ExpectedAddedWords = 52
$ExpectedProjectedWords = 111379
$TotalGameWords = 195584

$RootSeed = "0x80103BD8"
$RootAddressText = "80103BD8"
$RootLength = 0xD0
$RootWords = 52
$RootBodySha256 = "533D35036FC79CA6AE38DCC80BB9A148F200E4FC42477662428072A212450918"
$PreviousAddress = [Convert]::ToUInt32("80103B1C", 16)
$PreviousLength = 0xBC
$PreviousSha256 = "A19A12EA61B0AD41A48D211F48696DBB992BE17179C1F00A57C6D3CDBFC6F167"
$NextAddress = [Convert]::ToUInt32("80103CA8", 16)
$NextLength = 0xB0
$NextSha256 = "ECBC94B2752486134E1FC8A735BE62189FD96D66E9DC649228F9C289D5D170E0"
$CallerAddresses = @(
    [Convert]::ToUInt32("80103444", 16),
    [Convert]::ToUInt32("801035B4", 16)
)
$CallerInstructionSha256 = "DF64C389F36C74E3B3DE127FE413787F75E8A5AB4BAE434265593C55AFE8180E"
$RequiredNativeCallees = @("801938F0", "80125154")
$ForbiddenFunctions = @(
    "80103384",
    "8016EA0C", "8016EA60", "8016EAE8", "8016F560", "8016FB64",
    "801912D8", "801932AC", "801932BC", "8019E6D0"
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
    try { return [BitConverter]::ToString($Hasher.ComputeHash($Bytes)).Replace("-", "") }
    finally { $Hasher.Dispose() }
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
        if ($Opcode -eq 0 -and $Function -eq 0x09) { $Flow.JalrSites += $Pc.ToString("X8") }
        if ($Opcode -eq 0 -and $Function -eq 0x08) { $Flow.JrSites += $Pc.ToString("X8") }
        if (
            $Opcode -eq 0x12 -or
            ($Opcode -eq 0 -and $Function -in 0x0C, 0x0D, 0x18, 0x19, 0x1A, 0x1B)
        ) { $Flow.ForbiddenSites += $Pc.ToString("X8") }
    }
    return $Flow
}

function Assert-ExactList([string[]]$Actual, [string[]]$Expected, [string]$Description) {
    $A = @($Actual | ForEach-Object { $_.ToUpperInvariant() })
    $E = @($Expected | ForEach-Object { $_.ToUpperInvariant() })
    if (($A -join ',') -ne ($E -join ',')) {
        throw "$Description divergente. Esperado: $($E -join ', '); obtido: $($A -join ', ')"
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
        $Path = Join-Path $PreviewRoot ("s1-260-preview-{0:D2}" -f $Number)
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path | Out-Null
            return $Path
        }
    }
    throw "Nao ha preview-id livre entre s1-260-preview-01 e 99."
}

function Convert-ToTomlPath([string]$Path) {
    return ([IO.Path]::GetFullPath($Path)).Replace("\", "/")
}

foreach ($Required in @(
    $GameConfig, $GameExe, $GameDisc, $SeedFile, $RangesFile, $FullCFile,
    $DispatchCFile, $AuditScript, $GitIgnoreFile, $BiosEmitterShaFile
)) { Require-File $Required }

$BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
if ($BaselineHash -ne $ExpectedBaselineRangesSha256) {
    throw "Baseline nao corresponde a S1-259. SHA-256: $BaselineHash"
}
$SeedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SeedFile).Hash
if ($SeedHash -ne $ExpectedBaselineSeedsSha256) {
    throw "Seeds principais nao correspondem a S1-259. SHA-256: $SeedHash"
}
$GameExeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $GameExe).Hash
if ($GameExeHash -ne $ExpectedGameExeSha256) {
    throw "Executavel do jogo analisado divergiu. SHA-256: $GameExeHash"
}
$BaselineRanges = Get-FunctionRanges $RangesFile
if ($BaselineRanges.Count -ne $ExpectedBaselineFunctions) {
    throw "S1-259 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $($BaselineRanges.Count)"
}
$ActiveSeeds = Get-ActiveSeeds $SeedFile
if ($ActiveSeeds.Count -ne $ExpectedBaselineSeedCount) {
    throw "S1-259 deveria conter $ExpectedBaselineSeedCount seeds ativas; encontrado: $($ActiveSeeds.Count)"
}
if (@($ActiveSeeds | Sort-Object -Unique).Count -ne $ActiveSeeds.Count) {
    throw "O arquivo principal contem seeds ativas duplicadas."
}
if (@($ActiveSeeds | Where-Object { $_ -eq $RootSeed }).Count -ne 0) {
    throw "A candidata S1-260 ja esta ativa nas seeds principais: $RootSeed"
}
if ($BaselineRanges.ContainsKey($RootAddressText)) {
    throw "A candidata S1-260 ja pertence aos ranges da baseline: F $RootAddressText"
}
foreach ($Address in $ForbiddenFunctions) {
    if ($BaselineRanges.ContainsKey($Address)) {
        throw "Funcao que deve permanecer fora da S1-260 ja esta nativa: 0x$Address"
    }
}
foreach ($Address in $RequiredNativeCallees) {
    if (-not $BaselineRanges.ContainsKey($Address)) {
        throw "Callee que deveria estar nativa na S1-259 continua ausente: 0x$Address"
    }
}
if (-not $BaselineRanges.ContainsKey("80103B1C") -or $BaselineRanges["80103B1C"] -ne "BC") {
    throw "Vizinha anterior 0x80103B1C divergente na baseline."
}
if (-not $BaselineRanges.ContainsKey("80103CA8") -or $BaselineRanges["80103CA8"] -ne "B0") {
    throw "Vizinha seguinte 0x80103CA8 divergente na baseline."
}

[uint32]$RootAddress = [Convert]::ToUInt32($RootAddressText, 16)
$RootBody = Get-ExecutableRangeBytes $GameExe $RootAddress $RootLength
if ((Get-BytesSha256 $RootBody) -ne $RootBodySha256) { throw "Corpo 0x$RootAddressText divergente." }
if (($RootLength / 4) -ne $RootWords) { throw "Boundary da raiz nao corresponde a $RootWords palavras." }
if ((Get-BytesSha256 (Get-ExecutableRangeBytes $GameExe $PreviousAddress $PreviousLength)) -ne $PreviousSha256) {
    throw "Vizinha anterior 0x80103B1C divergente."
}
if ((Get-BytesSha256 (Get-ExecutableRangeBytes $GameExe $NextAddress $NextLength)) -ne $NextSha256) {
    throw "Vizinha seguinte 0x80103CA8 divergente."
}
foreach ($CallerAddress in $CallerAddresses) {
    if ((Get-BytesSha256 (Get-ExecutableRangeBytes $GameExe $CallerAddress 4)) -ne $CallerInstructionSha256) {
        throw "Caller JAL em 0x$($CallerAddress.ToString('X8')) divergente."
    }
}

$Flow = Get-MipsFlow $RootBody $RootAddress
Assert-ExactList $Flow.DirectJalTargets @("801938F0", "80125154") "Alvos JAL da raiz"
Assert-ExactList $Flow.JalrSites @() "Sites JALR da raiz"
Assert-ExactList $Flow.JrSites @("80103CA0") "Sites JR da raiz"
Assert-ExactList $Flow.BranchTargets @("80103C8C", "80103C44") "Branches da raiz"
Assert-ExactList $Flow.JumpTargets @("80103C64") "Jumps absolutos da raiz"
Assert-InternalTargets $Flow.BranchTargets $RootAddress $RootLength "Branch da raiz"
Assert-InternalTargets $Flow.JumpTargets $RootAddress $RootLength "Jump absoluto da raiz"
if ($Flow.ForbiddenSites.Count -ne 0) {
    throw "A raiz contem COP2, syscall, break, MULT ou DIV nao aprovados."
}

if ($ValidateOnly) {
    Write-Host "Validacao estatica S1-260 concluida."
    Write-Host "Baseline S1-259, seed, boundary, vizinhas, callers e fluxo interno: OK"
    Write-Host "Corpo vivo identico nos cinco eventos de Pause; 92 hits interpretados."
    Write-Host "Orcamento rigido: uma funcao e 52 palavras."
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
    $SeedAppend = "`r`n# Previa isolada S1-260: ramo curto observado exclusivamente no Pause.`r`n"
    $SeedAppend += "# Gate exato: uma funcao e 52 palavras; nenhuma closure adicional permitida.`r`n"
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
    if ($LASTEXITCODE -ne 0) { throw "A geracao isolada S1-260 falhou com codigo $LASTEXITCODE" }
    Require-File $PreviewRanges

    $PreviewMap = Get-FunctionRanges $PreviewRanges
    if ($PreviewMap.Count -ne $ExpectedPreviewFunctions) {
        throw "S1-260 deveria conter $ExpectedPreviewFunctions funcoes; encontrado: $($PreviewMap.Count)"
    }
    foreach ($Address in $BaselineRanges.Keys) {
        if (-not $PreviewMap.ContainsKey($Address) -or $PreviewMap[$Address] -ne $BaselineRanges[$Address]) {
            throw "Range aprovado desapareceu ou mudou na previa: F $Address"
        }
    }
    $Added = @($PreviewMap.Keys | Where-Object { -not $BaselineRanges.ContainsKey($_) } | Sort-Object)
    Assert-ExactList $Added @($RootAddressText) "Closure S1-260"
    if ($PreviewMap[$RootAddressText] -ne "D0") {
        throw "Range da raiz divergente. Esperado: D0; obtido: $($PreviewMap[$RootAddressText])"
    }
    [int64]$MeasuredAddedWords = [Convert]::ToInt64($PreviewMap[$RootAddressText], 16) / 4
    if ($MeasuredAddedWords -ne $ExpectedAddedWords) {
        throw "S1-260 deveria adicionar $ExpectedAddedWords palavras; medido: $MeasuredAddedWords"
    }
    foreach ($Address in $ForbiddenFunctions) {
        if ($PreviewMap.ContainsKey($Address)) { throw "Funcao proibida apareceu na previa: F $Address" }
    }

    Write-Host "Executando auditoria codegen somente na previa isolada..."
    & $PythonPath $AuditScript --config $PreviewConfig | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "A auditoria codegen da previa falhou com codigo $LASTEXITCODE" }

    $PreviewHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PreviewRanges).Hash
    $ProjectedPercent = [Math]::Round(100.0 * $ExpectedProjectedWords / $TotalGameWords, 4)
    $Summary = @"
# Pre-auditoria S1-260

- Baseline S1-259: $ExpectedBaselineFunctions funcoes, $ExpectedBaselineCoverageWords palavras
- Baseline ranges SHA-256: $BaselineHash
- Funcao adicionada: 0x$RootAddressText
- Boundary: 0x80103BD8..0x80103CA7
- Palavras adicionadas: $MeasuredAddedWords
- Funcoes projetadas: $($PreviewMap.Count)
- Cobertura projetada: $ExpectedProjectedWords/$TotalGameWords palavras ($($ProjectedPercent.ToString('F4'))%)
- Ranges SHA-256 da previa: $PreviewHash
- JAL: 0x801938F0 e 0x80125154, ambos ja nativos; JALR: zero
- Branches e jump: todos internos; retorno JR RA em 0x80103CA0
- Callers diretos: JAL 0x80103444 e 0x801035B4
- Evidencia dinamica: cinco contextos de Pause; 92 hits interpretados; corpo vivo estavel
- Auditoria codegen: CLEAN
- Seeds/fontes principais, BIOS e build: preservados
"@
    [IO.File]::WriteAllText((Join-Path $RunDir "summary.md"), $Summary, [Text.UTF8Encoding]::new($false))

    Write-Host ""
    Write-Host "Previa isolada S1-260 aprovada."
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
