param(
    [string]$RecompilerPath,
    [string]$PythonPath
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RepoRoot = (Resolve-Path (Join-Path $ProjectRoot "..")).Path
$SeedFile = Join-Path $ProjectRoot "seeds\entry_funcs.txt"
$RangesFile = Join-Path $ProjectRoot "generated\SLUS_005.48_full.ranges"
$GenerateScript = Join-Path $PSScriptRoot "generate_game.ps1"
$ValidateS1251Script = Join-Path $PSScriptRoot "generate_s1_251_sources.ps1"
$GitIgnoreFile = Join-Path $RepoRoot ".gitignore"
$BiosEmitterShaFile = Join-Path $RepoRoot "psxrecomp\generated\SCPH1001.emitter.sha"

$ExpectedContaminatedRangesSha256 = "2F3A18F08ED029E7D5D7227E60DC6AA38367187D9D9DD9DE2DD91C4713BBA7E1"
$ExpectedContaminatedFunctions = 1054
$ExpectedRestoredRangesSha256 = "BB5EA43C77096772D1997D52EBA01C84F9DE674D057053D0D61FD9561D6A6D25"
$ExpectedRestoredFunctions = 1042
$ExpectedRejectedWords = 2805

$ApprovedSeed = "0x8014C708"
$RejectedSeed = "0x8016FC28"
$QuarantinedSeed = "0x8019E6D0"
$PriorSeeds = @(
    "0x8019F5CC", "0x8019F6A8", "0x801A9DC0", "0x801A92B8",
    "0x8011D030", "0x8011D310", "0x80107A74", "0x80162D68",
    "0x80137FE8", "0x801102A0", "0x8013CB08"
)

$ApprovedRange = @{ Function = "F 8014C708"; Range = "R 8014C708 28" }
$RejectedRanges = @(
    @{ Function = "F 8016FC28"; Range = "R 8016FC28 9C"; Words = 39 },
    @{ Function = "F 8017D860"; Range = "R 8017D860 1A8"; Words = 106 },
    @{ Function = "F 8017DA08"; Range = "R 8017DA08 94"; Words = 37 },
    @{ Function = "F 8017DA9C"; Range = "R 8017DA9C 124"; Words = 73 },
    @{ Function = "F 8018F10C"; Range = "R 8018F10C 1D60"; Words = 1880 },
    @{ Function = "F 80190EB8"; Range = "R 80190EB8 F4"; Words = 61 },
    @{ Function = "F 80190FAC"; Range = "R 80190FAC 54"; Words = 21 },
    @{ Function = "F 80191000"; Range = "R 80191000 A4"; Words = 41 },
    @{ Function = "F 801910A4"; Range = "R 801910A4 234"; Words = 141 },
    @{ Function = "F 801914C0"; Range = "R 801914C0 C8"; Words = 50 },
    @{ Function = "F 80191C84"; Range = "R 80191C84 4A4"; Words = 297 },
    @{ Function = "F 80192D6C"; Range = "R 80192D6C EC"; Words = 59 }
)

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Arquivo obrigatorio ausente: $Path"
    }
}

function Count-ExactLine([string]$Path, [string]$Line) {
    return @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() -eq $Line }).Count
}

function Count-Functions([string]$Path) {
    return @(Select-String -LiteralPath $Path -Pattern '^F [0-9A-Fa-f]{8}$').Count
}

foreach ($required in @(
    $SeedFile, $RangesFile, $GenerateScript, $ValidateS1251Script,
    $GitIgnoreFile, $BiosEmitterShaFile
)) {
    Require-File $required
}

if ((Count-ExactLine $SeedFile $ApprovedSeed) -ne 1) {
    throw "A seed aprovada $ApprovedSeed deve aparecer exatamente uma vez."
}
if ((Count-ExactLine $SeedFile $RejectedSeed) -ne 0) {
    throw "A seed rejeitada $RejectedSeed ainda esta ativa."
}
if ((Count-ExactLine $SeedFile $QuarantinedSeed) -ne 0) {
    throw "A seed em quarentena $QuarantinedSeed nao pode estar ativa."
}
foreach ($seed in $PriorSeeds) {
    if ((Count-ExactLine $SeedFile $seed) -ne 1) {
        throw "A seed aprovada $seed deve aparecer exatamente uma vez."
    }
}

$ContaminatedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
$ContaminatedFunctions = Count-Functions $RangesFile
if ($ContaminatedHash -ne $ExpectedContaminatedRangesSha256) {
    throw "Manifest atual nao corresponde ao incidente S1-252 conhecido. SHA-256: $ContaminatedHash"
}
if ($ContaminatedFunctions -ne $ExpectedContaminatedFunctions) {
    throw "Incidente S1-252 deveria conter $ExpectedContaminatedFunctions funcoes; encontrado: $ContaminatedFunctions"
}
if ((Count-ExactLine $RangesFile $ApprovedRange.Function) -ne 1 -or
    (Count-ExactLine $RangesFile $ApprovedRange.Range) -ne 1) {
    throw "Range aprovado S1-251 ausente ou duplicado."
}

$MeasuredRejectedWords = 0
foreach ($range in $RejectedRanges) {
    if ((Count-ExactLine $RangesFile $range.Function) -ne 1 -or
        (Count-ExactLine $RangesFile $range.Range) -ne 1) {
        throw "Closure rejeitada divergente: $($range.Range)"
    }
    $MeasuredRejectedWords += $range.Words
}
if ($MeasuredRejectedWords -ne $ExpectedRejectedWords) {
    throw "Closure rejeitada deveria somar $ExpectedRejectedWords palavras; calculado: $MeasuredRejectedWords"
}

$ProtectedHashes = @{}
foreach ($protected in @($GitIgnoreFile, $BiosEmitterShaFile)) {
    $ProtectedHashes[$protected] = (Get-FileHash -Algorithm SHA256 -LiteralPath $protected).Hash
}

Write-Host "Incidente S1-252 confirmado: $ContaminatedFunctions funcoes; closure rejeitada de $MeasuredRejectedWords palavras."
Write-Host "Regenerando somente os fontes do jogo para a lista de seeds S1-251..."
if ($RecompilerPath) {
    & $GenerateScript -RecompilerPath $RecompilerPath
} else {
    & $GenerateScript
}
if ($LASTEXITCODE -ne 0) {
    throw "A regeneracao dos fontes S1-251 falhou com codigo $LASTEXITCODE"
}

$RestoredHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
$RestoredFunctions = Count-Functions $RangesFile
if ($RestoredHash -ne $ExpectedRestoredRangesSha256) {
    throw "Manifest restaurado nao corresponde ao S1-251 aprovado. SHA-256: $RestoredHash"
}
if ($RestoredFunctions -ne $ExpectedRestoredFunctions) {
    throw "S1-251 restaurado deveria conter $ExpectedRestoredFunctions funcoes; encontrado: $RestoredFunctions"
}
if ((Count-ExactLine $RangesFile $ApprovedRange.Function) -ne 1 -or
    (Count-ExactLine $RangesFile $ApprovedRange.Range) -ne 1) {
    throw "Range S1-251 ausente ou duplicado depois da restauracao."
}
foreach ($range in $RejectedRanges) {
    if ((Count-ExactLine $RangesFile $range.Function) -ne 0) {
        throw "Funcao rejeitada permaneceu nos fontes restaurados: $($range.Function)"
    }
}

$ValidationArgs = @{}
if ($RecompilerPath) { $ValidationArgs.RecompilerPath = $RecompilerPath }
if ($PythonPath) { $ValidationArgs.PythonPath = $PythonPath }
& $ValidateS1251Script @ValidationArgs
if ($LASTEXITCODE -ne 0) {
    throw "A auditoria final do S1-251 falhou com codigo $LASTEXITCODE"
}

foreach ($protected in @($GitIgnoreFile, $BiosEmitterShaFile)) {
    $AfterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $protected).Hash
    if ($AfterHash -ne $ProtectedHashes[$protected]) {
        throw "Arquivo protegido foi alterado durante a restauracao: $protected"
    }
}

Write-Host ""
Write-Host "S1-251 restaurado e auditado."
Write-Host "Funcoes: $RestoredFunctions"
Write-Host "Palavras novas do S1-251: 10"
Write-Host "Cobertura: 108.275/195.584 palavras (55,3598%)"
Write-Host "Ranges SHA-256: $RestoredHash"
Write-Host "BIOS, build e jogo nao foram iniciados por este script."
