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
$PreviewRanges = Join-Path $ProjectRoot "local\preaudit\s1-258-preview-01\generated\SLUS_005.48_full.ranges"
$GitIgnoreFile = Join-Path $RepoRoot ".gitignore"
$BiosEmitterShaFile = Join-Path $FrameworkRoot "generated\SCPH1001.emitter.sha"

$ExpectedBaselineRangesSha256 = "A10B9A83A30D0CB0280F36898971A2D99F804ABC094461994B137F55B635E6CD"
$ExpectedPostRangesSha256 = "B085DB02B291233F95A55B6F6F25FAACE48147BC5FF273B6518D811F98A73E1E"
$ExpectedSeedSha256 = "5386B257D5B4A35F0299C82D5DC2F3AD5073129C784D58B9C8A3428264049D87"
$ExpectedGameExeSha256 = "4FFE98EB4F246B4D455392E537E8D9F029D34F2E95E301AEF2CB61F5E3E99820"
$ExpectedBaselineFunctions = 1056
$ExpectedPostFunctions = 1057
$ExpectedSeedCount = 536
$ExpectedAddedWords = 151
$CandidateAddress = "8017566C"
$CandidateLength = "25C"
$CandidateBodySha256 = "5DA650C3D1A23F0C9E8359253D73D3741BE92D12BB348ECBCEB94A2FEE3014E2"
$JumpTableAddress = "801AC9C0"
$JumpTableLength = 0x4C
$JumpTableSha256 = "48FAC5788B5D05A0476AD3A6A1ADF35EAF2F99649D7DB5599FAE06CA7D04419D"

$RequiredSeeds = @(
    "0x8016FC28", "0x801930BC", "0x8018F10C", "0x8019FC6C", "0x8017566C"
)
$ForbiddenFunctions = @("80103384", "8019E6D0")

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
    throw "Manifesto da previa S1-258 divergente. SHA-256: $PreviewHash"
}
$PreviewMap = Get-FunctionRanges $PreviewRanges
if ($PreviewMap.Count -ne $ExpectedPostFunctions -or
    -not $PreviewMap.ContainsKey($CandidateAddress) -or
    $PreviewMap[$CandidateAddress] -ne $CandidateLength) {
    throw "A previa S1-258 nao corresponde a uma funcao/151 palavras."
}

$SeedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SeedFile).Hash
if ($SeedHash -ne $ExpectedSeedSha256) {
    throw "Arquivo de seeds nao corresponde ao S1-258 preparado. SHA-256: $SeedHash"
}
$ActiveSeeds = @(
    Get-Content -LiteralPath $SeedFile |
        ForEach-Object { ($_ -split '#')[0].Trim().ToUpperInvariant() } |
        Where-Object { $_ -match '^0X[0-9A-F]{8}$' }
)
if ($ActiveSeeds.Count -ne $ExpectedSeedCount) {
    throw "S1-258 deveria conter $ExpectedSeedCount seeds ativas; encontrado: $($ActiveSeeds.Count)"
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
if ($GameExeHash -ne $ExpectedGameExeSha256) {
    throw "Executavel analisado divergiu. SHA-256: $GameExeHash"
}
$BodyHash = Get-ExecutableRangeSha256 $GameExe ([Convert]::ToUInt32($CandidateAddress, 16)) 0x25C
if ($BodyHash -ne $CandidateBodySha256) { throw "Corpo 0x$CandidateAddress divergente: $BodyHash" }
$TableHash = Get-ExecutableRangeSha256 $GameExe ([Convert]::ToUInt32($JumpTableAddress, 16)) $JumpTableLength
if ($TableHash -ne $JumpTableSha256) { throw "Jump table 0x$JumpTableAddress divergente: $TableHash" }

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
            throw "Fontes atuais nao correspondem a baseline S1-257. SHA-256: $CurrentHash; funcoes: $($CurrentRanges.Count)"
        }
        if ($CurrentRanges.ContainsKey($CandidateAddress)) {
            throw "A funcao S1-258 apareceu parcialmente na baseline."
        }
        foreach ($Address in $ForbiddenFunctions) {
            if ($CurrentRanges.ContainsKey($Address)) { throw "Funcao proibida ja aparece na baseline: F $Address" }
        }
        if ($ValidateOnly) {
            Write-Host "Validacao estatica S1-258 concluida sobre a baseline S1-257."
            Write-Host "Nenhuma fonte foi gerada; BIOS e build nao foram iniciados."
            return
        }
        Write-Host "Baseline S1-257 confirmada. Gerando somente as fontes do jogo S1-258..."
        if ($RecompilerPath) { & $GenerateScript -RecompilerPath $RecompilerPath }
        else { & $GenerateScript }
        if ($LASTEXITCODE -ne 0) { throw "A geracao das fontes S1-258 falhou com codigo $LASTEXITCODE" }
    }
    else {
        if ($ValidateOnly) {
            Write-Host "Validacao estatica S1-258 concluida sobre fontes S1-258 ja presentes."
            Write-Host "Nenhuma fonte foi regenerada; BIOS e build nao foram iniciados."
            return
        }
        Write-Host "Fontes S1-258 ja presentes; repetindo apenas os gates pos-geracao."
    }

    $PostRanges = Get-FunctionRanges $RangesFile
    if (-not $PostRanges.ContainsKey($CandidateAddress) -or
        $PostRanges[$CandidateAddress] -ne $CandidateLength) {
        throw "Range S1-258 ausente ou divergente: R $CandidateAddress $CandidateLength"
    }
    foreach ($Address in $ForbiddenFunctions) {
        if ($PostRanges.ContainsKey($Address)) { throw "Funcao fora do lote apareceu nos fontes: F $Address" }
    }
    $PostHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $AddedWords = [Convert]::ToInt64($CandidateLength, 16) / 4
    if ($PostRanges.Count -ne $ExpectedPostFunctions) {
        throw "S1-258 deveria conter $ExpectedPostFunctions funcoes; encontrado: $($PostRanges.Count)"
    }
    if ($AddedWords -ne $ExpectedAddedWords) { throw "Quantidade de palavras S1-258 divergente: $AddedWords" }
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
    if ($LASTEXITCODE -ne 0) { throw "A auditoria codegen S1-258 falhou com codigo $LASTEXITCODE" }

    Write-Host ""
    Write-Host "S1-258 gerado e auditado."
    Write-Host "Funcao adicionada: 0x8017566C"
    Write-Host "Palavras adicionadas: 151"
    Write-Host "Funcoes: $($PostRanges.Count)"
    Write-Host "Cobertura esperada: 111.297/195.584 palavras (56,9050%)"
    Write-Host "Ranges SHA-256: $PostHash"
    Write-Host "BIOS e build nao foram iniciados por este script."
}
finally {
    foreach ($Protected in $ProtectedHashes.Keys) {
        $AfterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Protected).Hash
        if ($AfterHash -ne $ProtectedHashes[$Protected]) { throw "Artefato protegido foi alterado: $Protected" }
    }
}
