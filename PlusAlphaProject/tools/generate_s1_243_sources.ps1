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

$ExpectedBaselineRangesSha256 = "233FB83ACDB67427E0CE6E8FBCE03CF5A461C49813D362B87DC3DAD638103F8D"
$ExpectedBaselineFunctions = 1028
$ExpectedPostFunctions = 1029
$ExpectedSeed = "0x80162D68"
$QuarantinedSeed = "0x8019E6D0"
$Candidate = @{ Function = "F 80162D68"; Range = "R 80162D68 3D4"; Address = "80162D68"; Length = 0x3D4; Sha256 = "4226575C83318D0F1490572D14CB151D72296A83F27BF9C3859976C6BDF05664" }
$PriorRanges = @(
    @{ Function = "F 80137FE8"; Range = "R 80137FE8 9C" },
    @{ Function = "F 80138084"; Range = "R 80138084 1F8" },
    @{ Function = "F 8013827C"; Range = "R 8013827C 140" },
    @{ Function = "F 801102A0"; Range = "R 801102A0 390" },
    @{ Function = "F 8013CB08"; Range = "R 8013CB08 84" }
)
$ExpectedCallTargets = @(
    "F 80115524", "F 8011618C", "F 80123A94", "F 80159E44", "F 8015A0E8",
    "F 8015A180", "F 8015AFEC", "F 8015E12C", "F 80162BE0", "F 80162D1C",
    "F 80168788", "F 8019C0B8", "F 8019C184"
)
$RawChecks = @(
    @{ Address = "80162D68"; Length = 0x3D4; Sha256 = "4226575C83318D0F1490572D14CB151D72296A83F27BF9C3859976C6BDF05664" },
    @{ Address = "801ABFE0"; Length = 0x54; Sha256 = "EFA4AAF9573DC9F310A19605E5F8D1798764BBC82D9412840EC5F87F9B9BC72E" },
    @{ Address = "801B3444"; Length = 4; Sha256 = "B0556D3711E4867589975B27EC4BA7A1344BFB8A6B418F556AFA3D5E995B0526" }
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
if ((Count-ExactLine $SeedFile $QuarantinedSeed) -ne 0) { throw "A seed em quarentena $QuarantinedSeed nao pode aparecer na lista ativa." }
foreach ($check in $RawChecks) {
    $actual = Get-ExecutableRangeSha256 $GameExe ([Convert]::ToUInt32($check.Address, 16)) $check.Length
    if ($actual -ne $check.Sha256) { throw "Bytes de 0x$($check.Address)+0x$($check.Length.ToString('X')) divergentes. SHA-256: $actual" }
}

$AlreadyGenerated = (Count-ExactLine $RangesFile $Candidate.Function) -eq 1 -and (Count-ExactLine $RangesFile $Candidate.Range) -eq 1
foreach ($prior in $PriorRanges) { $AlreadyGenerated = $AlreadyGenerated -and (Count-ExactLine $RangesFile $prior.Function) -eq 1 -and (Count-ExactLine $RangesFile $prior.Range) -eq 1 }
$AlreadyGenerated = $AlreadyGenerated -and (Count-ExactLine $RangesFile "F 8019E6D0") -eq 0

if (-not $AlreadyGenerated) {
    $BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $BaselineFunctions = @(Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$').Count
    if ($BaselineHash -ne $ExpectedBaselineRangesSha256) { throw "Ranges antes da geracao nao correspondem ao S1-242 aprovado. SHA-256: $BaselineHash" }
    if ($BaselineFunctions -ne $ExpectedBaselineFunctions) { throw "S1-242 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $BaselineFunctions" }
    foreach ($prior in $PriorRanges) { if ((Count-ExactLine $RangesFile $prior.Function) -ne 1 -or (Count-ExactLine $RangesFile $prior.Range) -ne 1) { throw "Range aprovado ausente na baseline: $($prior.Range)" } }
    foreach ($target in $ExpectedCallTargets) { if ((Count-ExactLine $RangesFile $target) -ne 1) { throw "Dependencia nativa obrigatoria ausente antes da geracao: $target" } }
    Write-Host "Baseline S1-242 confirmada. Gerando somente as fontes do jogo S1-243..."
    if ($RecompilerPath) { & $GenerateScript -RecompilerPath $RecompilerPath } else { & $GenerateScript }
    if ($LASTEXITCODE -ne 0) { throw "A geracao das fontes S1-243 falhou com codigo $LASTEXITCODE" }
} else { Write-Host "Fontes S1-243 ja presentes; repetindo apenas os gates pos-geracao." }

foreach ($item in @($Candidate) + $PriorRanges) { if ((Count-ExactLine $RangesFile $item.Function) -ne 1 -or (Count-ExactLine $RangesFile $item.Range) -ne 1) { throw "Range esperado ausente ou duplicado: $($item.Range)" } }
if ((Count-ExactLine $RangesFile "F 8019E6D0") -ne 0) { throw "A funcao em quarentena $QuarantinedSeed apareceu nos ranges gerados." }
$PostFunctions = @(Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$').Count
if ($PostFunctions -ne $ExpectedPostFunctions) { throw "S1-243 deveria conter $ExpectedPostFunctions funcoes; encontrado: $PostFunctions" }
if (-not $PythonPath) { $PythonCommand = Get-Command python -ErrorAction SilentlyContinue; if (-not $PythonCommand) { throw "Python nao foi encontrado. Informe -PythonPath." }; $PythonPath = $PythonCommand.Source }
Write-Host "Executando auditoria codegen do jogo..."
& $PythonPath $AuditScript --config $GameConfig
if ($LASTEXITCODE -ne 0) { throw "A auditoria codegen do S1-243 falhou com codigo $LASTEXITCODE" }
$RangesHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
Write-Host ""; Write-Host "S1-243 gerado e auditado."; Write-Host "Funcoes: $PostFunctions"; Write-Host "Raiz: 0x80162D68 (245 palavras)"; Write-Host "Cobertura esperada: 107.070/195.584 palavras (54,7437%)"; Write-Host "Ranges SHA-256: $RangesHash"; Write-Host "BIOS nao foi regenerada. Nenhum build foi iniciado por este script."
