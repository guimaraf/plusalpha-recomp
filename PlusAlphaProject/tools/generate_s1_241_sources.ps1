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

$ExpectedBaselineRangesSha256 = "8C00112C2E7CA409A7BAABCD73889E8D6C957EF2B1407A691F757AC3919B816F"
$ExpectedBaselineFunctions = 1024
$ExpectedPostFunctions = 1025
$ExpectedSeed = "0x801102A0"
$PriorSeed = "0x8013CB08"
$QuarantinedSeed = "0x8019E6D0"
$ExpectedFunctionLine = "F 801102A0"
$ExpectedRangeLine = "R 801102A0 390"
$PriorFunctionLine = "F 8013CB08"
$PriorRangeLine = "R 8013CB08 84"
$QuarantinedFunctionLine = "F 8019E6D0"
$ExpectedCandidateSha256 = "A0F347D22E0D4CC9145E22CC5B8368A14AF1CC3563A5EC9268202CAB2E7FE6ED"
$ExpectedCallTargets = @("F 8019CA30", "F 8010C72C", "F 80110E58")

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Arquivo obrigatorio ausente: $Path"
    }
}

function Count-ExactLine([string]$Path, [string]$Line) {
    return @(
        Get-Content -LiteralPath $Path |
            Where-Object { $_.Trim() -eq $Line }
    ).Count
}

function Get-ExecutableRangeSha256(
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
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($Hasher.ComputeHash($Slice)).Replace("-", "")
    }
    finally {
        $Hasher.Dispose()
    }
}

foreach ($required in @(
    $GameConfig,
    $GameExe,
    $SeedFile,
    $RangesFile,
    $GenerateScript,
    $AuditScript
)) {
    Require-File $required
}

if ((Count-ExactLine $SeedFile $ExpectedSeed) -ne 1) {
    throw "A seed $ExpectedSeed deve aparecer exatamente uma vez em $SeedFile"
}
if ((Count-ExactLine $SeedFile $PriorSeed) -ne 1) {
    throw "A seed aprovada $PriorSeed deve permanecer exatamente uma vez na lista ativa."
}
if ((Count-ExactLine $SeedFile $QuarantinedSeed) -ne 0) {
    throw "A seed em quarentena $QuarantinedSeed nao pode aparecer na lista ativa."
}

$CandidateSha256 = Get-ExecutableRangeSha256 `
    $GameExe ([Convert]::ToUInt32("801102A0", 16)) 0x390
if ($CandidateSha256 -ne $ExpectedCandidateSha256) {
    throw "Bytes de 0x801102A0+0x390 divergentes. SHA-256: $CandidateSha256"
}

$AlreadyGenerated =
    (Count-ExactLine $RangesFile $ExpectedFunctionLine) -eq 1 -and
    (Count-ExactLine $RangesFile $ExpectedRangeLine) -eq 1 -and
    (Count-ExactLine $RangesFile $PriorFunctionLine) -eq 1 -and
    (Count-ExactLine $RangesFile $QuarantinedFunctionLine) -eq 0

if (-not $AlreadyGenerated) {
    $BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $BaselineFunctions = @(
        Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$'
    ).Count

    if ($BaselineHash -ne $ExpectedBaselineRangesSha256) {
        throw "Ranges antes da geracao nao correspondem ao S1-240 aprovado. SHA-256: $BaselineHash"
    }
    if ($BaselineFunctions -ne $ExpectedBaselineFunctions) {
        throw "S1-240 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $BaselineFunctions"
    }
    if ((Count-ExactLine $RangesFile $PriorFunctionLine) -ne 1 -or
        (Count-ExactLine $RangesFile $PriorRangeLine) -ne 1) {
        throw "O range aprovado S1-240 nao esta presente na baseline de geracao."
    }
    foreach ($target in $ExpectedCallTargets) {
        if ((Count-ExactLine $RangesFile $target) -ne 1) {
            throw "Dependencia nativa obrigatoria ausente antes da geracao: $target"
        }
    }

    Write-Host "Baseline S1-240 confirmada. Gerando somente as fontes do jogo S1-241..."
    if ($RecompilerPath) {
        & $GenerateScript -RecompilerPath $RecompilerPath
    }
    else {
        & $GenerateScript
    }
    if ($LASTEXITCODE -ne 0) {
        throw "A geracao das fontes S1-241 falhou com codigo $LASTEXITCODE"
    }
}
else {
    Write-Host "Fontes S1-241 ja presentes; repetindo apenas os gates pos-geracao."
}

Require-File $RangesFile
if ((Count-ExactLine $RangesFile $ExpectedFunctionLine) -ne 1) {
    throw "A funcao $ExpectedSeed nao apareceu exatamente uma vez nos ranges gerados."
}
if ((Count-ExactLine $RangesFile $ExpectedRangeLine) -ne 1) {
    throw "Range esperado ausente: $ExpectedRangeLine"
}
if ((Count-ExactLine $RangesFile $PriorFunctionLine) -ne 1 -or
    (Count-ExactLine $RangesFile $PriorRangeLine) -ne 1) {
    throw "O range aprovado S1-240 foi perdido durante a geracao."
}
if ((Count-ExactLine $RangesFile $QuarantinedFunctionLine) -ne 0) {
    throw "A funcao em quarentena $QuarantinedSeed apareceu nos ranges gerados."
}

$PostFunctions = @(
    Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$'
).Count
if ($PostFunctions -ne $ExpectedPostFunctions) {
    throw "S1-241 deveria conter $ExpectedPostFunctions funcoes; encontrado: $PostFunctions"
}

if (-not $PythonPath) {
    $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $PythonCommand) {
        throw "Python nao foi encontrado. Informe -PythonPath."
    }
    $PythonPath = $PythonCommand.Source
}

Write-Host "Executando auditoria codegen do jogo..."
& $PythonPath $AuditScript --config $GameConfig
if ($LASTEXITCODE -ne 0) {
    throw "A auditoria codegen do S1-241 falhou com codigo $LASTEXITCODE"
}

$RangesHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
Write-Host ""
Write-Host "S1-241 gerado e auditado."
Write-Host "Funcoes: $PostFunctions"
Write-Host "Candidato: 0x801102A0+0x390 (228 palavras)"
Write-Host "Cobertura esperada: 106.580/195.584 palavras (54,4932%)"
Write-Host "Ranges SHA-256: $RangesHash"
Write-Host "BIOS nao foi regenerada. Nenhum build foi iniciado por este script."
