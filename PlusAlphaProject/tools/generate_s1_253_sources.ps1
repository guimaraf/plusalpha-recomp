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

$ExpectedBaselineRangesSha256 = "BB5EA43C77096772D1997D52EBA01C84F9DE674D057053D0D61FD9561D6A6D25"
$ExpectedBaselineFunctions = 1042
$ExpectedPostRangesSha256 = "80DF7E6811A60B300CD5371818A2504FB571EB806B5FC755BD470A4582077068"
$ExpectedPostFunctions = 1045
$ExpectedAddedWords = 184
$ExpectedSeeds = @("0x8017D860", "0x8017DA08", "0x80191000")
$PriorSeeds = @("0x8019F5CC", "0x8019F6A8", "0x801A9DC0", "0x801A92B8", "0x8011D030", "0x8011D310", "0x80107A74", "0x80162D68", "0x80137FE8", "0x801102A0", "0x8013CB08", "0x8014C708")
$QuarantinedSeed = "0x8019E6D0"
$CandidateRanges = @(
    @{ Function = "F 8017D860"; Range = "R 8017D860 1A8"; Words = 106 },
    @{ Function = "F 8017DA08"; Range = "R 8017DA08 94"; Words = 37 },
    @{ Function = "F 80191000"; Range = "R 80191000 A4"; Words = 41 }
)
$ForbiddenFunctions = @("F 80103384", "F 8016FC28", "F 8017566C", "F 8017DA9C", "F 8018F10C", "F 80190EB8", "F 80190FAC", "F 801910A4", "F 801914C0", "F 80191C84", "F 80192D6C", "F 8019E6D0")
$RawChecks = @(
    @{ Address = "8017D860"; Length = 0x1A8; Sha256 = "43F7DA960644EFE8DC1C199749FC08D8392A28591A3FC3577B7020FB3B9F0F67" },
    @{ Address = "8017DA08"; Length = 0x94; Sha256 = "3D7FF33BBC5B4A01DFFB86A1BD3C58DC7F2EE59B2B5182D2BEBE928E6B6F1639" },
    @{ Address = "80191000"; Length = 0xA4; Sha256 = "86EA5B37A52FD2703CECF74FCF6672011A29D7E2726F166BFAA4181E8EF61368" },
    @{ Address = "8018FEEC"; Length = 0x4; Sha256 = "60415E5291FBB86BE45D43DFA3016C175284B9DA57AF9AC972B3E45A878520CD" },
    @{ Address = "80190E20"; Length = 0x4; Sha256 = "5C06045FF23732FFF42FF5C345315EEC02568E20654EE336925363DE3BA8DCD2" },
    @{ Address = "8018FEF4"; Length = 0x4; Sha256 = "356D2F5489E89FA51F96BDF3BC7994365361E6176A539AB3F2A4303D10CEB3DC" }
)

function Require-File([string]$Path) { if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Arquivo obrigatorio ausente: $Path" } }
function Count-ExactLine([string]$Path, [string]$Line) { return @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() -eq $Line }).Count }
function Get-ExecutableRangeSha256([string]$Path, [uint32]$VirtualAddress, [int]$Length) {
    $Bytes = [IO.File]::ReadAllBytes($Path); $LoadAddress = [BitConverter]::ToUInt32($Bytes, 0x18)
    $FileOffset = 0x800 + [int64]$VirtualAddress - [int64]$LoadAddress
    if ($FileOffset -lt 0 -or ($FileOffset + $Length) -gt $Bytes.Length) { throw "Intervalo 0x$($VirtualAddress.ToString('X8'))+$Length fora do executavel." }
    $Slice = New-Object byte[] $Length; [Array]::Copy($Bytes, $FileOffset, $Slice, 0, $Length)
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($Hasher.ComputeHash($Slice)).Replace("-", "") } finally { $Hasher.Dispose() }
}

foreach ($Required in @($GameConfig, $GameExe, $SeedFile, $RangesFile, $GenerateScript, $AuditScript)) { Require-File $Required }
foreach ($Seed in $ExpectedSeeds + $PriorSeeds) { if ((Count-ExactLine $SeedFile $Seed) -ne 1) { throw "A seed aprovada $Seed deve aparecer exatamente uma vez." } }
if ((Count-ExactLine $SeedFile $QuarantinedSeed) -ne 0) { throw "A seed em quarentena $QuarantinedSeed nao pode estar ativa." }
foreach ($Check in $RawChecks) {
    $Actual = Get-ExecutableRangeSha256 $GameExe ([Convert]::ToUInt32($Check.Address, 16)) $Check.Length
    if ($Actual -ne $Check.Sha256) { throw "Bytes de 0x$($Check.Address)+0x$($Check.Length.ToString('X')) divergentes. SHA-256: $Actual" }
}

$AlreadyGenerated = $true
foreach ($Candidate in $CandidateRanges) { $AlreadyGenerated = $AlreadyGenerated -and (Count-ExactLine $RangesFile $Candidate.Function) -eq 1 -and (Count-ExactLine $RangesFile $Candidate.Range) -eq 1 }
foreach ($Forbidden in $ForbiddenFunctions) { $AlreadyGenerated = $AlreadyGenerated -and (Count-ExactLine $RangesFile $Forbidden) -eq 0 }

if (-not $AlreadyGenerated) {
    $BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $BaselineFunctions = @(Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$').Count
    if ($BaselineHash -ne $ExpectedBaselineRangesSha256) { throw "Ranges antes da geracao nao correspondem ao S1-251. SHA-256: $BaselineHash" }
    if ($BaselineFunctions -ne $ExpectedBaselineFunctions) { throw "S1-251 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $BaselineFunctions" }
    foreach ($Forbidden in $ForbiddenFunctions) { if ((Count-ExactLine $RangesFile $Forbidden) -ne 0) { throw "Funcao proibida ja aparece na baseline: $Forbidden" } }
    Write-Host "Baseline S1-251 confirmada. Gerando somente as fontes do jogo S1-253..."
    if ($RecompilerPath) { & $GenerateScript -RecompilerPath $RecompilerPath } else { & $GenerateScript }
    if ($LASTEXITCODE -ne 0) { throw "A geracao das fontes S1-253 falhou com codigo $LASTEXITCODE" }
} else { Write-Host "Fontes S1-253 ja presentes; repetindo apenas os gates pos-geracao." }

foreach ($Candidate in $CandidateRanges) { if ((Count-ExactLine $RangesFile $Candidate.Function) -ne 1 -or (Count-ExactLine $RangesFile $Candidate.Range) -ne 1) { throw "Range S1-253 ausente ou duplicado: $($Candidate.Range)" } }
foreach ($Forbidden in $ForbiddenFunctions) { if ((Count-ExactLine $RangesFile $Forbidden) -ne 0) { throw "Funcao fora da closure aprovada apareceu nos fontes: $Forbidden" } }
$PostFunctions = @(Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$').Count
$PostHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
$PostWords = ($CandidateRanges | Measure-Object -Property Words -Sum).Sum
if ($PostFunctions -ne $ExpectedPostFunctions) { throw "S1-253 deveria conter $ExpectedPostFunctions funcoes; encontrado: $PostFunctions" }
if ($PostWords -ne $ExpectedAddedWords) { throw "S1-253 deveria adicionar $ExpectedAddedWords palavras; calculado: $PostWords" }
if ($PostHash -ne $ExpectedPostRangesSha256) { throw "Ranges apos a geracao divergiram da previa isolada. SHA-256: $PostHash" }
if (-not $PythonPath) { $PythonCommand = Get-Command python -ErrorAction SilentlyContinue; if (-not $PythonCommand) { throw "Python nao foi encontrado. Informe -PythonPath." }; $PythonPath = $PythonCommand.Source }
Write-Host "Executando auditoria codegen do jogo..."
& $PythonPath $AuditScript --config $GameConfig
if ($LASTEXITCODE -ne 0) { throw "A auditoria codegen do S1-253 falhou com codigo $LASTEXITCODE" }
Write-Host ""; Write-Host "S1-253 gerado e auditado."; Write-Host "Funcoes: $PostFunctions"; Write-Host "Raizes: 0x8017D860, 0x8017DA08, 0x80191000 (184 palavras)"; Write-Host "Cobertura esperada: 108.459/195.584 palavras (55,4539%)"; Write-Host "Ranges SHA-256: $PostHash"; Write-Host "BIOS e build nao foram iniciados por este script."
