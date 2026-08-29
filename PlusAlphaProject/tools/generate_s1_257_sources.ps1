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
$PreviewRanges = Join-Path $ProjectRoot "local\preaudit\s1-257-preview-01\generated\SLUS_005.48_full.ranges"
$GitIgnoreFile = Join-Path $RepoRoot ".gitignore"
$BiosEmitterShaFile = Join-Path $FrameworkRoot "generated\SCPH1001.emitter.sha"

$ExpectedBaselineRangesSha256 = "300F1B44336410C0F0DADAF746D2973D27ABCCF4EB391A36891D827DA67057C6"
$ExpectedPostRangesSha256 = "A10B9A83A30D0CB0280F36898971A2D99F804ABC094461994B137F55B635E6CD"
$ExpectedSeedSha256 = "7F406F8D5645C323FC6344659D607D07BB2C10DFF7124F1E2B19CBF5475ED974"
$ExpectedBaselineFunctions = 1055
$ExpectedPostFunctions = 1056
$ExpectedSeedCount = 535
$ExpectedAddedWords = 30
$CandidateAddress = "8019FC6C"
$CandidateLength = "78"

$RequiredSeeds = @("0x8016FC28", "0x801930BC", "0x8018F10C", "0x8019FC6C")
$ForbiddenFunctions = @(
    "80103384", "8017566C", "8019E6D0", "8019FCE4",
    "80192128", "80193174", "8019319C", "801931C4", "80192F60"
)
$RawChecks = @(
    @{ Address = "8019FC14"; Length = 0x58; Sha256 = "248F4E027829F8E354357C6989248D5E32F52D0A40C995483B05697870CE006E" },
    @{ Address = "8019FC6C"; Length = 0x78; Sha256 = "02427D01908F1F36539549CBE3C02C69E2BA4F24F4F240A186909D3A26D926CE" },
    @{ Address = "8019FCE4"; Length = 0x2C; Sha256 = "64EAF0108FDAF088D3A5EB4899D9461F331464ECE163EF57D405755A7F400A87" }
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
    throw "Manifesto da previa S1-257 divergente. SHA-256: $PreviewHash"
}

$SeedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SeedFile).Hash
if ($SeedHash -ne $ExpectedSeedSha256) {
    throw "Arquivo de seeds nao corresponde ao S1-257 aprovado. SHA-256: $SeedHash"
}
$ActiveSeeds = @(
    Get-Content -LiteralPath $SeedFile |
        ForEach-Object { ($_ -split '#')[0].Trim().ToUpperInvariant() } |
        Where-Object { $_ -match '^0X[0-9A-F]{8}$' }
)
if ($ActiveSeeds.Count -ne $ExpectedSeedCount) {
    throw "S1-257 deveria conter $ExpectedSeedCount seeds ativas; encontrado: $($ActiveSeeds.Count)"
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

foreach ($Check in $RawChecks) {
    $Actual = Get-ExecutableRangeSha256 $GameExe ([Convert]::ToUInt32($Check.Address, 16)) $Check.Length
    if ($Actual -ne $Check.Sha256) {
        throw "Bytes de 0x$($Check.Address)+0x$($Check.Length.ToString('X')) divergentes. SHA-256: $Actual"
    }
}

$ProtectedHashes = @{}
foreach ($Protected in @($GitIgnoreFile, $BiosEmitterShaFile)) {
    $ProtectedHashes[$Protected] = (Get-FileHash -Algorithm SHA256 -LiteralPath $Protected).Hash
}

try {
    $CurrentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $CurrentRanges = Get-FunctionRanges $RangesFile
    $AlreadyGenerated = $CurrentHash -eq $ExpectedPostRangesSha256 -and $CurrentRanges.Count -eq $ExpectedPostFunctions

    if (-not $AlreadyGenerated) {
        if ($CurrentHash -ne $ExpectedBaselineRangesSha256 -or $CurrentRanges.Count -ne $ExpectedBaselineFunctions) {
            throw "Fontes atuais nao correspondem a baseline S1-256. SHA-256: $CurrentHash; funcoes: $($CurrentRanges.Count)"
        }
        if ($CurrentRanges.ContainsKey($CandidateAddress)) {
            throw "A funcao S1-257 ja apareceu parcialmente na baseline."
        }
        foreach ($Address in $ForbiddenFunctions) {
            if ($CurrentRanges.ContainsKey($Address)) { throw "Funcao proibida ja aparece na baseline: F $Address" }
        }

        if ($ValidateOnly) {
            Write-Host "Validacao estatica S1-257 concluida sobre a baseline S1-256."
            Write-Host "Nenhuma fonte foi gerada; BIOS e build nao foram iniciados."
            return
        }

        Write-Host "Baseline S1-256 confirmada. Gerando somente as fontes do jogo S1-257..."
        if ($RecompilerPath) { & $GenerateScript -RecompilerPath $RecompilerPath }
        else { & $GenerateScript }
        if ($LASTEXITCODE -ne 0) { throw "A geracao das fontes S1-257 falhou com codigo $LASTEXITCODE" }
    }
    else {
        if ($ValidateOnly) {
            Write-Host "Validacao estatica S1-257 concluida sobre fontes S1-257 ja presentes."
            Write-Host "Nenhuma fonte foi regenerada; BIOS e build nao foram iniciados."
            return
        }
        Write-Host "Fontes S1-257 ja presentes; repetindo apenas os gates pos-geracao."
    }

    $PostRanges = Get-FunctionRanges $RangesFile
    if (-not $PostRanges.ContainsKey($CandidateAddress) -or $PostRanges[$CandidateAddress] -ne $CandidateLength) {
        throw "Range S1-257 ausente ou divergente: R $CandidateAddress $CandidateLength"
    }
    foreach ($Address in $ForbiddenFunctions) {
        if ($PostRanges.ContainsKey($Address)) { throw "Funcao fora do lote apareceu nos fontes: F $Address" }
    }
    $PostHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $AddedWords = [Convert]::ToInt64($CandidateLength, 16) / 4
    if ($PostRanges.Count -ne $ExpectedPostFunctions) {
        throw "S1-257 deveria conter $ExpectedPostFunctions funcoes; encontrado: $($PostRanges.Count)"
    }
    if ($AddedWords -ne $ExpectedAddedWords) { throw "Quantidade de palavras S1-257 divergente: $AddedWords" }
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
    if ($LASTEXITCODE -ne 0) { throw "A auditoria codegen S1-257 falhou com codigo $LASTEXITCODE" }

    Write-Host ""
    Write-Host "S1-257 gerado e auditado."
    Write-Host "Funcao adicionada: 0x8019FC6C"
    Write-Host "Palavras adicionadas: 30"
    Write-Host "Funcoes: $($PostRanges.Count)"
    Write-Host "Cobertura esperada: 111.146/195.584 palavras (56,8278%)"
    Write-Host "Ranges SHA-256: $PostHash"
    Write-Host "BIOS e build nao foram iniciados por este script."
}
finally {
    foreach ($Protected in $ProtectedHashes.Keys) {
        $AfterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Protected).Hash
        if ($AfterHash -ne $ProtectedHashes[$Protected]) { throw "Artefato protegido foi alterado: $Protected" }
    }
}
