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
$SeedFile = Join-Path $ProjectRoot "seeds\entry_funcs.txt"
$RangesFile = Join-Path $ProjectRoot "generated\SLUS_005.48_full.ranges"
$GenerateScript = Join-Path $PSScriptRoot "generate_game.ps1"
$AuditScript = Join-Path $FrameworkRoot "tools\codegen_audit_game.py"

$ExpectedBaselineRangesSha256 = "D1F06458723FB6D28D2308F4C3D58E37B2F501E202C1379E3B569EA4801F66D5"
$ExpectedBaselineFunctions = 1037
$ExpectedPostFunctions = 1041
$ExpectedSeed = "0x8019F5CC"
$PriorSeeds = @("0x8019F6A8", "0x801A9DC0", "0x801A92B8", "0x8011D030", "0x8011D310", "0x80107A74", "0x80162D68", "0x80137FE8", "0x801102A0", "0x8013CB08")
$QuarantinedSeed = "0x8019E6D0"
$CandidateRanges = @(
    @{ Function = "F 8019F5CC"; Range = "R 8019F5CC DC" },
    @{ Function = "F 8019FB4C"; Range = "R 8019FB4C C" },
    @{ Function = "F 8019FB84"; Range = "R 8019FB84 C" },
    @{ Function = "F 8019FB94"; Range = "R 8019FB94 3C" }
)
$PriorRanges = @(
    @{ Function = "F 8019F6A8"; Range = "R 8019F6A8 1E8" },
    @{ Function = "F 8019FB64"; Range = "R 8019FB64 C" },
    @{ Function = "F 801A9DC0"; Range = "R 801A9DC0 214" },
    @{ Function = "F 801A92B8"; Range = "R 801A92B8 E4" }
)
$ExpectedNativeTargets = @("F 8019FB18", "F 8019F6A8", "F 8019FC14", "F 8019FD3C", "F 8019327C")
$ForbiddenFunctions = @("F 8019FBD0", "F 8019E6D0")
$RawChecks = @(
    @{ Address = "8019F5CC"; Length = 0xDC; Sha256 = "5CD2956DD81F7F1BFE041AF4D3E471F9966975967245C07C5BDFFC35CDCC3764" },
    @{ Address = "8019FB4C"; Length = 0xC; Sha256 = "D3EEFD259EB1B5F648EC00610D2DEFBF4C6E5873F47895DD3D23A322BB0CFD7F" },
    @{ Address = "8019FB84"; Length = 0xC; Sha256 = "38790D1AEB4D336DA0F746D61D8DA4152AFC210C2C260C98AC350DB6321E05CD" },
    @{ Address = "8019FB94"; Length = 0x3C; Sha256 = "278FBE40AF5AB27BE7A1302914AC62558CB96E3323353CC94C5B916AF6CA7AA4" },
    @{ Address = "8019F62C"; Length = 0x8; Sha256 = "F53E107113414E135A24BC60575C0D0194C445A5DC85693B30C08B9477835BDA" },
    @{ Address = "8019F654"; Length = 0x8; Sha256 = "688FB18A9065F6A0F5D7836EB4615F00D76F62579FD6FC31A9043DA101D82485" },
    @{ Address = "8019F680"; Length = 0x8; Sha256 = "BECD5483EE5F04C6A05E3078ADCFD54A46FFDDA3FEAB6F62A2FCBC8099678A2A" }
)

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Arquivo obrigatorio ausente: $Path" }
}

function Count-ExactLine([string]$Path, [string]$Line) {
    return @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() -eq $Line }).Count
}

function Get-ExecutableRangeSha256([string]$Path, [uint32]$VirtualAddress, [int]$Length) {
    $Bytes = [IO.File]::ReadAllBytes($Path)
    $LoadAddress = [BitConverter]::ToUInt32($Bytes, 0x18)
    $FileOffset = 0x800 + [int64]$VirtualAddress - [int64]$LoadAddress
    if ($FileOffset -lt 0 -or ($FileOffset + $Length) -gt $Bytes.Length) { throw "Intervalo 0x$($VirtualAddress.ToString('X8'))+$Length fora do executavel." }
    $Slice = New-Object byte[] $Length
    [Array]::Copy($Bytes, $FileOffset, $Slice, 0, $Length)
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($Hasher.ComputeHash($Slice)).Replace("-", "") }
    finally { $Hasher.Dispose() }
}

foreach ($required in @($GameConfig, $GameExe, $SeedFile, $RangesFile, $GenerateScript, $AuditScript)) { Require-File $required }
if ((Count-ExactLine $SeedFile $ExpectedSeed) -ne 1) { throw "A seed $ExpectedSeed deve aparecer exatamente uma vez em $SeedFile" }
foreach ($seed in $PriorSeeds) { if ((Count-ExactLine $SeedFile $seed) -ne 1) { throw "A seed aprovada $seed deve permanecer exatamente uma vez na lista ativa." } }
if ((Count-ExactLine $SeedFile $QuarantinedSeed) -ne 0) { throw "A seed em quarentena $QuarantinedSeed nao pode aparecer na lista ativa." }
foreach ($check in $RawChecks) {
    $actual = Get-ExecutableRangeSha256 $GameExe ([Convert]::ToUInt32($check.Address, 16)) $check.Length
    if ($actual -ne $check.Sha256) { throw "Bytes de 0x$($check.Address)+0x$($check.Length.ToString('X')) divergentes. SHA-256: $actual" }
}

$AlreadyGenerated = $true
foreach ($candidate in $CandidateRanges) {
    $AlreadyGenerated = $AlreadyGenerated -and (Count-ExactLine $RangesFile $candidate.Function) -eq 1 -and (Count-ExactLine $RangesFile $candidate.Range) -eq 1
}
foreach ($prior in $PriorRanges) {
    $AlreadyGenerated = $AlreadyGenerated -and (Count-ExactLine $RangesFile $prior.Function) -eq 1 -and (Count-ExactLine $RangesFile $prior.Range) -eq 1
}
foreach ($forbidden in $ForbiddenFunctions) { $AlreadyGenerated = $AlreadyGenerated -and (Count-ExactLine $RangesFile $forbidden) -eq 0 }

if (-not $AlreadyGenerated) {
    $BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $BaselineFunctions = @(Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$').Count
    if ($BaselineHash -ne $ExpectedBaselineRangesSha256) { throw "Ranges antes da geracao nao correspondem ao S1-249 validado. SHA-256: $BaselineHash" }
    if ($BaselineFunctions -ne $ExpectedBaselineFunctions) { throw "S1-249 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $BaselineFunctions" }
    foreach ($candidate in $CandidateRanges) { if ((Count-ExactLine $RangesFile $candidate.Function) -ne 0) { throw "O candidato ja aparece parcialmente na baseline: $($candidate.Function)" } }
    foreach ($prior in $PriorRanges) { if ((Count-ExactLine $RangesFile $prior.Function) -ne 1 -or (Count-ExactLine $RangesFile $prior.Range) -ne 1) { throw "Range aprovado ausente na baseline: $($prior.Range)" } }
    foreach ($target in $ExpectedNativeTargets) { if ((Count-ExactLine $RangesFile $target) -ne 1) { throw "Dependencia nativa obrigatoria ausente antes da geracao: $target" } }
    Write-Host "Baseline S1-249 confirmada. Gerando somente as fontes do jogo S1-250..."
    if ($RecompilerPath) { & $GenerateScript -RecompilerPath $RecompilerPath } else { & $GenerateScript }
    if ($LASTEXITCODE -ne 0) { throw "A geracao das fontes S1-250 falhou com codigo $LASTEXITCODE" }
} else { Write-Host "Fontes S1-250 ja presentes; repetindo apenas os gates pos-geracao." }

foreach ($candidate in $CandidateRanges) {
    if ((Count-ExactLine $RangesFile $candidate.Function) -ne 1 -or (Count-ExactLine $RangesFile $candidate.Range) -ne 1) { throw "Range S1-250 ausente ou duplicado: $($candidate.Range)" }
}
foreach ($forbidden in $ForbiddenFunctions) { if ((Count-ExactLine $RangesFile $forbidden) -ne 0) { throw "Funcao fora do micro-lote apareceu nos fontes gerados: $forbidden" } }
$PostFunctions = @(Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$').Count
if ($PostFunctions -ne $ExpectedPostFunctions) { throw "S1-250 deveria conter $ExpectedPostFunctions funcoes; encontrado: $PostFunctions" }
if (-not $PythonPath) { $PythonCommand = Get-Command python -ErrorAction SilentlyContinue; if (-not $PythonCommand) { throw "Python nao foi encontrado. Informe -PythonPath." }; $PythonPath = $PythonCommand.Source }
Write-Host "Executando auditoria codegen do jogo..."
& $PythonPath $AuditScript --config $GameConfig
if ($LASTEXITCODE -ne 0) { throw "A auditoria codegen do S1-250 falhou com codigo $LASTEXITCODE" }
$RangesHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
Write-Host ""; Write-Host "S1-250 gerado e auditado."; Write-Host "Funcoes: $PostFunctions"; Write-Host "Familia: 0x8019F5CC + 0x8019FB4C + 0x8019FB84 + 0x8019FB94 (76 palavras)"; Write-Host "Cobertura esperada: 108.265/195.584 palavras (55,3547%)"; Write-Host "Ranges SHA-256: $RangesHash"; Write-Host "BIOS nao foi regenerada. Nenhum build foi iniciado por este script."
