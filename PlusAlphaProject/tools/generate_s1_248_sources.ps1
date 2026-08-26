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

$ExpectedBaselineRangesSha256 = "6642DB2E79435405AB52DD3B89B932B0AF58809B9A87F17140C0AF3EF96B28F7"
$ExpectedBaselineFunctions = 1034
$ExpectedPostFunctions = 1035
$ExpectedSeed = "0x801A9DC0"
$PriorSeeds = @("0x801A92B8", "0x8011D030", "0x8011D310", "0x80107A74", "0x80162D68", "0x80137FE8", "0x801102A0", "0x8013CB08")
$QuarantinedSeed = "0x8019E6D0"
$CandidateRange = @{ Function = "F 801A9DC0"; Range = "R 801A9DC0 214" }
$PriorRanges = @(
    @{ Function = "F 801A92B8"; Range = "R 801A92B8 E4" },
    @{ Function = "F 8011D030"; Range = "R 8011D030 48" },
    @{ Function = "F 8011D078"; Range = "R 8011D078 298" },
    @{ Function = "F 8011D310"; Range = "R 8011D310 6A4" },
    @{ Function = "F 80107A74"; Range = "R 80107A74 30C" },
    @{ Function = "F 80162D68"; Range = "R 80162D68 3D4" },
    @{ Function = "F 80137FE8"; Range = "R 80137FE8 9C" },
    @{ Function = "F 80138084"; Range = "R 80138084 1F8" },
    @{ Function = "F 8013827C"; Range = "R 8013827C 140" },
    @{ Function = "F 801102A0"; Range = "R 801102A0 390" },
    @{ Function = "F 8013CB08"; Range = "R 8013CB08 84" }
)
$ExpectedCallTargets = @("F 801A7ACC", "F 801A7C34", "F 8019F3E4", "F 8019F1F0", "F 801A9FD4", "F 801A76D4", "F 801A76EC", "F 801A7704")
$RawChecks = @(
    @{ Address = "801A9DC0"; Length = 0x214; Sha256 = "6DA8E69BB4A4F365C08D2A168395E11A33CF7D58A714F69702836656DF656F86" },
    @{ Address = "801A9F88"; Length = 4; Sha256 = "31B7BAB3F1622716F68DEAF682B789AC0A1942C8B5052383A358D94EFA7FD4D3" },
    @{ Address = "801A9F94"; Length = 4; Sha256 = "FB180B12043E4CE1E6B538E5EAA22E466821442145AB123E4FC05EC5A895509B" },
    @{ Address = "801A9FB4"; Length = 8; Sha256 = "439928EB71DFE02A7AA9B5605C2728F7B9BA740D006D0017CF07F9823AB526F2" },
    @{ Address = "801A9FBC"; Length = 4; Sha256 = "FF4F10E4C1AED482ADDE96F2D6C90C32A746D56ACCD85D4BC6E882327418C75E" }
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
$AlreadyGenerated = $AlreadyGenerated -and (Count-ExactLine $RangesFile "F 8019E6D0") -eq 0

if (-not $AlreadyGenerated) {
    $BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $BaselineFunctions = @(Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$').Count
    if ($BaselineHash -ne $ExpectedBaselineRangesSha256) { throw "Ranges antes da geracao nao correspondem ao S1-247 validado. SHA-256: $BaselineHash" }
    if ($BaselineFunctions -ne $ExpectedBaselineFunctions) { throw "S1-247 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $BaselineFunctions" }
    foreach ($prior in $PriorRanges) { if ((Count-ExactLine $RangesFile $prior.Function) -ne 1 -or (Count-ExactLine $RangesFile $prior.Range) -ne 1) { throw "Range aprovado ausente na baseline: $($prior.Range)" } }
    foreach ($target in $ExpectedCallTargets) { if ((Count-ExactLine $RangesFile $target) -ne 1) { throw "Dependencia nativa obrigatoria ausente antes da geracao: $target" } }
    Write-Host "Baseline S1-247 confirmada. Gerando somente as fontes do jogo S1-248..."
    if ($RecompilerPath) { & $GenerateScript -RecompilerPath $RecompilerPath } else { & $GenerateScript }
    if ($LASTEXITCODE -ne 0) { throw "A geracao das fontes S1-248 falhou com codigo $LASTEXITCODE" }
} else { Write-Host "Fontes S1-248 ja presentes; repetindo apenas os gates pos-geracao." }

if ((Count-ExactLine $RangesFile $CandidateRange.Function) -ne 1 -or (Count-ExactLine $RangesFile $CandidateRange.Range) -ne 1) { throw "Range S1-248 ausente ou duplicado: $($CandidateRange.Range)" }
if ((Count-ExactLine $RangesFile "F 8019E6D0") -ne 0) { throw "A funcao em quarentena $QuarantinedSeed apareceu nos fontes gerados." }
$PostFunctions = @(Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$').Count
if ($PostFunctions -ne $ExpectedPostFunctions) { throw "S1-248 deveria conter $ExpectedPostFunctions funcoes; encontrado: $PostFunctions" }
if (-not $PythonPath) { $PythonCommand = Get-Command python -ErrorAction SilentlyContinue; if (-not $PythonCommand) { throw "Python nao foi encontrado. Informe -PythonPath." }; $PythonPath = $PythonCommand.Source }
Write-Host "Executando auditoria codegen do jogo..."
& $PythonPath $AuditScript --config $GameConfig
if ($LASTEXITCODE -ne 0) { throw "A auditoria codegen do S1-248 falhou com codigo $LASTEXITCODE" }
$RangesHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
Write-Host ""; Write-Host "S1-248 gerado e auditado."; Write-Host "Funcoes: $PostFunctions"; Write-Host "Raiz: 0x801A9DC0 (133 palavras; um JALR guardado)"; Write-Host "Cobertura esperada: 108.064/195.584 palavras (55,2520%)"; Write-Host "Ranges SHA-256: $RangesHash"; Write-Host "BIOS nao foi regenerada. Nenhum build foi iniciado por este script."
