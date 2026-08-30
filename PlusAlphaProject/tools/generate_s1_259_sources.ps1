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
$SeedFile = Join-Path $ProjectRoot "seeds\entry_funcs.txt"
$RangesFile = Join-Path $ProjectRoot "generated\SLUS_005.48_full.ranges"
$GenerateScript = Join-Path $PSScriptRoot "generate_game.ps1"
$AuditScript = Join-Path $FrameworkRoot "tools\codegen_audit_game.py"
$PreviewRanges = Join-Path $ProjectRoot "local\preaudit\s1-259-preview-01\generated\SLUS_005.48_full.ranges"
$GitIgnoreFile = Join-Path $RepoRoot ".gitignore"
$BiosEmitterShaFile = Join-Path $FrameworkRoot "generated\SCPH1001.emitter.sha"

$ExpectedBaselineRangesSha256 = "B085DB02B291233F95A55B6F6F25FAACE48147BC5FF273B6518D811F98A73E1E"
$ExpectedPostRangesSha256 = "C0E7A0A37DB76E98E731D4E9CA5A0882DE02802E8CDADA5805E07C83DE15999F"
$ExpectedSeedSha256 = "0EC46DEFABB59E17D2C9C88B39C26E24B17384D6C86AB7F952AC853E4C9139DE"
$ExpectedGameExeSha256 = "4FFE98EB4F246B4D455392E537E8D9F029D34F2E95E301AEF2CB61F5E3E99820"
$ExpectedBaselineFunctions = 1057
$ExpectedPostFunctions = 1058
$ExpectedSeedCount = 537
$ExpectedAddedWords = 30
$CandidateAddress = "801939A0"
$CandidateLength = "78"
$CandidateBodySha256 = "37B07726C20B9FBADA32ADF7CC1ED776D342F0F742F1FEA3734EA48EB6A26179"

$RequiredSeeds = @(
    "0x8016FC28", "0x801930BC", "0x8018F10C", "0x8019FC6C",
    "0x8017566C", "0x801939A0"
)
$ForbiddenFunctions = @("80103384", "801912D8", "801932AC", "801932BC", "8019E6D0")
$RawChecks = @(
    @{ Address = "80193920"; Length = 0x80; Sha256 = "D36E4E0A30187B2A5E6037D84929AA5FC2F0AB7A87992027668AB33C1807DB17" },
    @{ Address = "801939A0"; Length = 0x78; Sha256 = "37B07726C20B9FBADA32ADF7CC1ED776D342F0F742F1FEA3734EA48EB6A26179" },
    @{ Address = "80193A18"; Length = 0x85C; Sha256 = "3EA02DC7B2CBAE2541FB9DECF30B49DE3509ED2B107C1AC8378B5A3D1DFD1159" },
    @{ Address = "80134EF8"; Length = 0x8; Sha256 = "B372DF68115FAB4DEA406EBF9AE96AF76A456E5B60960533F49B66D6062C54EB" }
)

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Arquivo obrigatorio ausente: $Path"
    }
}

function Count-ExactLine([string]$Path, [string]$Line) {
    return @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() -eq $Line }).Count
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

foreach ($Required in @(
    $GameConfig, $GameExe, $SeedFile, $RangesFile, $GenerateScript,
    $AuditScript, $PreviewRanges, $GitIgnoreFile, $BiosEmitterShaFile
)) { Require-File $Required }

$PreviewHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PreviewRanges).Hash
if ($PreviewHash -ne $ExpectedPostRangesSha256) {
    throw "Manifesto da previa S1-259 divergente. SHA-256: $PreviewHash"
}
$PreviewMap = Get-FunctionRanges $PreviewRanges
if ($PreviewMap.Count -ne $ExpectedPostFunctions -or
    -not $PreviewMap.ContainsKey($CandidateAddress) -or
    $PreviewMap[$CandidateAddress] -ne $CandidateLength) {
    throw "A previa S1-259 nao corresponde a uma funcao/30 palavras."
}

$SeedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SeedFile).Hash
if ($SeedHash -ne $ExpectedSeedSha256) {
    throw "Arquivo de seeds nao corresponde ao S1-259 preparado. SHA-256: $SeedHash"
}
$ActiveSeeds = @(
    Get-Content -LiteralPath $SeedFile |
        ForEach-Object { ($_ -split '#')[0].Trim().ToUpperInvariant() } |
        Where-Object { $_ -match '^0X[0-9A-F]{8}$' }
)
if ($ActiveSeeds.Count -ne $ExpectedSeedCount) {
    throw "S1-259 deveria conter $ExpectedSeedCount seeds ativas; encontrado: $($ActiveSeeds.Count)"
}
if (@($ActiveSeeds | Sort-Object -Unique).Count -ne $ActiveSeeds.Count) {
    throw "O arquivo principal contem seeds ativas duplicadas."
}
foreach ($Seed in $RequiredSeeds) {
    if ((Count-ExactLine $SeedFile $Seed) -ne 1) {
        throw "A seed aprovada $Seed deve aparecer exatamente uma vez."
    }
}
foreach ($Address in $ForbiddenFunctions) {
    if ((Count-ExactLine $SeedFile "0x$Address") -ne 0) {
        throw "A funcao fora do lote 0x$Address nao pode estar ativa nas seeds."
    }
}
$GameExeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $GameExe).Hash
if ($GameExeHash -ne $ExpectedGameExeSha256) { throw "Executavel analisado divergiu: $GameExeHash" }
foreach ($Check in $RawChecks) {
    $Actual = Get-ExecutableRangeSha256 $GameExe ([Convert]::ToUInt32($Check.Address, 16)) $Check.Length
    if ($Actual -ne $Check.Sha256) { throw "Bytes de 0x$($Check.Address) divergentes: $Actual" }
}

$ProtectedHashes = @{}
foreach ($Protected in @($GitIgnoreFile, $BiosEmitterShaFile)) {
    $ProtectedHashes[$Protected] = (Get-FileHash -Algorithm SHA256 -LiteralPath $Protected).Hash
}

try {
    $CurrentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $CurrentRanges = Get-FunctionRanges $RangesFile
    $AlreadyGenerated = $CurrentHash -eq $ExpectedPostRangesSha256 -and
        $CurrentRanges.Count -eq $ExpectedPostFunctions

    if (-not $AlreadyGenerated) {
        if ($CurrentHash -ne $ExpectedBaselineRangesSha256 -or
            $CurrentRanges.Count -ne $ExpectedBaselineFunctions) {
            throw "Fontes atuais nao correspondem a baseline S1-258. SHA-256: $CurrentHash; funcoes: $($CurrentRanges.Count)"
        }
        if ($CurrentRanges.ContainsKey($CandidateAddress)) {
            throw "A funcao S1-259 apareceu parcialmente na baseline."
        }
        foreach ($Address in $ForbiddenFunctions) {
            if ($CurrentRanges.ContainsKey($Address)) { throw "Funcao proibida ja aparece na baseline: F $Address" }
        }
        if ($ValidateOnly) {
            Write-Host "Validacao estatica S1-259 concluida sobre a baseline S1-258."
            Write-Host "Nenhuma fonte foi gerada; BIOS e build nao foram iniciados."
            return
        }
        Write-Host "Baseline S1-258 confirmada. Gerando somente as fontes do jogo S1-259..."
        if ($RecompilerPath) { & $GenerateScript -RecompilerPath $RecompilerPath }
        else { & $GenerateScript }
        if ($LASTEXITCODE -ne 0) { throw "A geracao das fontes S1-259 falhou com codigo $LASTEXITCODE" }
    }
    else {
        if ($ValidateOnly) {
            Write-Host "Validacao estatica S1-259 concluida sobre fontes S1-259 ja presentes."
            Write-Host "Nenhuma fonte foi regenerada; BIOS e build nao foram iniciados."
            return
        }
        Write-Host "Fontes S1-259 ja presentes; repetindo apenas os gates pos-geracao."
    }

    $PostRanges = Get-FunctionRanges $RangesFile
    if (-not $PostRanges.ContainsKey($CandidateAddress) -or
        $PostRanges[$CandidateAddress] -ne $CandidateLength) {
        throw "Range S1-259 ausente ou divergente: R $CandidateAddress $CandidateLength"
    }
    foreach ($Address in $ForbiddenFunctions) {
        if ($PostRanges.ContainsKey($Address)) { throw "Funcao fora do lote apareceu nos fontes: F $Address" }
    }
    $PostHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $AddedWords = [Convert]::ToInt64($CandidateLength, 16) / 4
    if ($PostRanges.Count -ne $ExpectedPostFunctions) {
        throw "S1-259 deveria conter $ExpectedPostFunctions funcoes; encontrado: $($PostRanges.Count)"
    }
    if ($AddedWords -ne $ExpectedAddedWords) { throw "Quantidade de palavras S1-259 divergente: $AddedWords" }
    if ($PostHash -ne $ExpectedPostRangesSha256) {
        throw "Ranges apos a geracao divergiram da previa isolada. SHA-256: $PostHash"
    }

    if (-not $PythonPath) {
        $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
        if (-not $PythonCommand) { throw "Python nao foi encontrado. Informe -PythonPath." }
        $PythonPath = $PythonCommand.Source
    }
    Write-Host "Executando auditoria codegen do jogo..."
    & $PythonPath $AuditScript --config $GameConfig
    if ($LASTEXITCODE -ne 0) { throw "A auditoria codegen S1-259 falhou com codigo $LASTEXITCODE" }

    Write-Host ""
    Write-Host "S1-259 gerado e auditado."
    Write-Host "Funcao adicionada: 0x801939A0"
    Write-Host "Palavras adicionadas: 30"
    Write-Host "Funcoes: $($PostRanges.Count)"
    Write-Host "Cobertura esperada: 111.327/195.584 palavras (56,9203%)"
    Write-Host "Ranges SHA-256: $PostHash"
    Write-Host "BIOS e build nao foram iniciados por este script."
}
finally {
    foreach ($Protected in $ProtectedHashes.Keys) {
        $AfterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Protected).Hash
        if ($AfterHash -ne $ProtectedHashes[$Protected]) { throw "Artefato protegido foi alterado: $Protected" }
    }
}
