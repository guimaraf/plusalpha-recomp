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

$ExpectedBaselineRangesSha256 = "2A3D4F5FE031AB0EC2404E05B20582654BE0DD638D842C63F144B589253E464B"
$ExpectedBaselineFunctions = 1041
$ExpectedPostFunctions = 1042
$ExpectedSeed = "0x8014C708"
$PriorSeeds = @("0x8019F5CC", "0x8019F6A8", "0x801A9DC0", "0x801A92B8", "0x8011D030", "0x8011D310", "0x80107A74", "0x80162D68", "0x80137FE8", "0x801102A0", "0x8013CB08")
$QuarantinedSeed = "0x8019E6D0"
$CandidateRange = @{ Function = "F 8014C708"; Range = "R 8014C708 28" }
$PriorRanges = @(
    @{ Function = "F 8019F5CC"; Range = "R 8019F5CC DC" },
    @{ Function = "F 8019F6A8"; Range = "R 8019F6A8 1E8" },
    @{ Function = "F 8019FB4C"; Range = "R 8019FB4C C" },
    @{ Function = "F 8019FB64"; Range = "R 8019FB64 C" },
    @{ Function = "F 8019FB84"; Range = "R 8019FB84 C" },
    @{ Function = "F 8019FB94"; Range = "R 8019FB94 3C" }
)
$ForbiddenFunctions = @("F 80103384", "F 8016FC28", "F 8017566C", "F 8019E6D0")
$RawChecks = @(
    @{ Address = "8014C708"; Length = 0x28; Sha256 = "56FE1CB7A7C1A6E64EF5671B6283AE210932C01D80CFE2B0364933DC332C07A8" },
    @{ Address = "8014C718"; Length = 0x4; Sha256 = "0613F3516ABDC4F962D3DB08819240BBFF471466424E166D3477E68B7BA58181" },
    @{ Address = "801B1BB4"; Length = 0x4; Sha256 = "4DB27B9023B4CD7BC374AC28E70CDADD93897089646C79FDF35EBE839D30C816" }
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

$AlreadyGenerated = (Count-ExactLine $RangesFile $CandidateRange.Function) -eq 1 -and (Count-ExactLine $RangesFile $CandidateRange.Range) -eq 1
foreach ($prior in $PriorRanges) {
    $AlreadyGenerated = $AlreadyGenerated -and (Count-ExactLine $RangesFile $prior.Function) -eq 1 -and (Count-ExactLine $RangesFile $prior.Range) -eq 1
}
foreach ($forbidden in $ForbiddenFunctions) { $AlreadyGenerated = $AlreadyGenerated -and (Count-ExactLine $RangesFile $forbidden) -eq 0 }

if (-not $AlreadyGenerated) {
    $BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $BaselineFunctions = @(Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$').Count
    if ($BaselineHash -ne $ExpectedBaselineRangesSha256) { throw "Ranges antes da geracao nao correspondem ao checkpoint S1-250. SHA-256: $BaselineHash" }
    if ($BaselineFunctions -ne $ExpectedBaselineFunctions) { throw "S1-250 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $BaselineFunctions" }
    foreach ($prior in $PriorRanges) { if ((Count-ExactLine $RangesFile $prior.Function) -ne 1 -or (Count-ExactLine $RangesFile $prior.Range) -ne 1) { throw "Range aprovado ausente na baseline: $($prior.Range)" } }
    foreach ($forbidden in $ForbiddenFunctions) { if ((Count-ExactLine $RangesFile $forbidden) -ne 0) { throw "Funcao fora do micro-lote ja aparece na baseline: $forbidden" } }
    Write-Host "Checkpoint S1-250 confirmado. Gerando somente as fontes do jogo S1-251..."
    if ($RecompilerPath) { & $GenerateScript -RecompilerPath $RecompilerPath } else { & $GenerateScript }
    if ($LASTEXITCODE -ne 0) { throw "A geracao das fontes S1-251 falhou com codigo $LASTEXITCODE" }
} else { Write-Host "Fontes S1-251 ja presentes; repetindo apenas os gates pos-geracao." }

if ((Count-ExactLine $RangesFile $CandidateRange.Function) -ne 1 -or (Count-ExactLine $RangesFile $CandidateRange.Range) -ne 1) { throw "Range S1-251 ausente ou duplicado: $($CandidateRange.Range)" }
foreach ($forbidden in $ForbiddenFunctions) { if ((Count-ExactLine $RangesFile $forbidden) -ne 0) { throw "Funcao fora do micro-lote apareceu nos fontes gerados: $forbidden" } }
$PostFunctions = @(Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$').Count
if ($PostFunctions -ne $ExpectedPostFunctions) { throw "S1-251 deveria conter $ExpectedPostFunctions funcoes; encontrado: $PostFunctions" }
if (-not $PythonPath) { $PythonCommand = Get-Command python -ErrorAction SilentlyContinue; if (-not $PythonCommand) { throw "Python nao foi encontrado. Informe -PythonPath." }; $PythonPath = $PythonCommand.Source }
Write-Host "Executando auditoria codegen do jogo..."
& $PythonPath $AuditScript --config $GameConfig
if ($LASTEXITCODE -ne 0) { throw "A auditoria codegen do S1-251 falhou com codigo $LASTEXITCODE" }
$RangesHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
Write-Host ""; Write-Host "S1-251 gerado e auditado."; Write-Host "Funcoes: $PostFunctions"; Write-Host "Raiz: 0x8014C708 (10 palavras; um JALR dinamico)"; Write-Host "Cobertura esperada: 108.275/195.584 palavras (55,3598%)"; Write-Host "Ranges SHA-256: $RangesHash"; Write-Host "BIOS nao foi regenerada. Nenhum build foi iniciado por este script."
