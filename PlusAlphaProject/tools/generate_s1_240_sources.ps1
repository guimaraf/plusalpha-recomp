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

$ExpectedBaselineRangesSha256 = "8836CE7D5EE66FE85EACEDB854063661D95D4B725A351668BF7193F5C033201F"
$ExpectedQuarantinedRangesSha256 = "A553E174356DCA1CFCB5EB8C3EAF7E210D2B1028B98A73E99E00968976227DA0"
$ExpectedBaselineFunctions = 1023
$ExpectedPostFunctions = 1024
$ExpectedSeed = "0x8013CB08"
$QuarantinedSeed = "0x8019E6D0"
$ExpectedFunctionLine = "F 8013CB08"
$ExpectedRangeLine = "R 8013CB08 84"
$QuarantinedFunctionLine = "F 8019E6D0"
$QuarantinedRangeLine = "R 8019E6D0 198"
$ExpectedCandidateSha256 = "E5371557634AFD2A18808B9474FA67A3F0F6C6476AF404F5F84FE34E2BE23C7D"
$ExpectedJumpTableSha256 = "9518C9E042BD04A962FB898E752E93F81F522DA312A4BF47A12FB9DCFA5C7FCD"

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
if ((Count-ExactLine $SeedFile $QuarantinedSeed) -ne 0) {
    throw "A seed em quarentena $QuarantinedSeed nao pode aparecer na lista ativa."
}

$CandidateSha256 = Get-ExecutableRangeSha256 `
    $GameExe ([Convert]::ToUInt32("8013CB08", 16)) 0x84
if ($CandidateSha256 -ne $ExpectedCandidateSha256) {
    throw "Bytes de 0x8013CB08+0x84 divergentes. SHA-256: $CandidateSha256"
}
$JumpTableSha256 = Get-ExecutableRangeSha256 `
    $GameExe ([Convert]::ToUInt32("801ABC44", 16)) 20
if ($JumpTableSha256 -ne $ExpectedJumpTableSha256) {
    throw "Tabela de salto 0x801ABC44+20 divergente. SHA-256: $JumpTableSha256"
}

$AlreadyGenerated =
    (Count-ExactLine $RangesFile $ExpectedFunctionLine) -eq 1 -and
    (Count-ExactLine $RangesFile $ExpectedRangeLine) -eq 1 -and
    (Count-ExactLine $RangesFile $QuarantinedFunctionLine) -eq 0

if (-not $AlreadyGenerated) {
    $BaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $BaselineFunctions = @(
        Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$'
    ).Count

    $IsBaseline =
        $BaselineHash -eq $ExpectedBaselineRangesSha256 -and
        $BaselineFunctions -eq $ExpectedBaselineFunctions
    $IsQuarantinedExperiment =
        $BaselineHash -eq $ExpectedQuarantinedRangesSha256 -and
        $BaselineFunctions -eq $ExpectedPostFunctions -and
        (Count-ExactLine $RangesFile $QuarantinedFunctionLine) -eq 1 -and
        (Count-ExactLine $RangesFile $QuarantinedRangeLine) -eq 1

    if (-not $IsBaseline -and -not $IsQuarantinedExperiment) {
        throw "Ranges antes da geracao nao correspondem ao S1-239 nem ao experimento S1-240 em quarentena. SHA-256: $BaselineHash; funcoes: $BaselineFunctions"
    }
    if ($IsQuarantinedExperiment) {
        Write-Host "Experimento S1-240 em quarentena confirmado; ele sera substituido pelo novo candidato."
    }

    Write-Host "Baseline S1-239 confirmada. Gerando somente as fontes do jogo S1-240..."
    if ($RecompilerPath) {
        & $GenerateScript -RecompilerPath $RecompilerPath
    }
    else {
        & $GenerateScript
    }
    if ($LASTEXITCODE -ne 0) {
        throw "A geracao das fontes S1-240 falhou com codigo $LASTEXITCODE"
    }
}
else {
    Write-Host "Fontes S1-240 ja presentes; repetindo apenas os gates pos-geracao."
}

Require-File $RangesFile
if ((Count-ExactLine $RangesFile $ExpectedFunctionLine) -ne 1) {
    throw "A funcao $ExpectedSeed nao apareceu exatamente uma vez nos ranges gerados."
}
if ((Count-ExactLine $RangesFile $ExpectedRangeLine) -ne 1) {
    throw "Range esperado ausente: $ExpectedRangeLine"
}
if ((Count-ExactLine $RangesFile $QuarantinedFunctionLine) -ne 0) {
    throw "A funcao em quarentena $QuarantinedSeed ainda aparece nos ranges gerados."
}
if ((Count-ExactLine $RangesFile $QuarantinedRangeLine) -ne 0) {
    throw "O range em quarentena ainda aparece nos fontes gerados."
}

$PostFunctions = @(
    Select-String -LiteralPath $RangesFile -Pattern '^F [0-9A-Fa-f]{8}$'
).Count
if ($PostFunctions -ne $ExpectedPostFunctions) {
    throw "S1-240 deveria conter $ExpectedPostFunctions funcoes; encontrado: $PostFunctions"
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
    throw "A auditoria codegen do S1-240 falhou com codigo $LASTEXITCODE"
}

$RangesHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
Write-Host ""
Write-Host "S1-240 gerado e auditado."
Write-Host "Funcoes: $PostFunctions"
Write-Host "Candidato: 0x8013CB08+0x84 (33 palavras)"
Write-Host "Tabela indireta: 0x801ABC44+20 bytes, hash confirmado"
Write-Host "Ranges SHA-256: $RangesHash"
Write-Host "BIOS nao foi regenerada. Nenhum build foi iniciado por este script."
