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
$PreviewRanges = Join-Path $ProjectRoot "local\preaudit\s1-256-preview-02\stage2-full-batch\generated\SLUS_005.48_full.ranges"
$GitIgnoreFile = Join-Path $RepoRoot ".gitignore"
$BiosEmitterShaFile = Join-Path $FrameworkRoot "generated\SCPH1001.emitter.sha"

$ExpectedBaselineRangesSha256 = "30BCD2340878A0C9057CA4B8A66F582A0695AF844B1E45E9409678951D76D404"
$ExpectedBaselineFunctions = 1049
$ExpectedPostRangesSha256 = "300F1B44336410C0F0DADAF746D2973D27ABCCF4EB391A36891D827DA67057C6"
$ExpectedPostFunctions = 1055
$ExpectedAddedWords = 622
$ExpectedSeedSha256 = "D699266A1420A8E3083E799B644B3705E0F04875962DE2B54955DE2B4EA95BDD"
$ExpectedSeedCount = 534

$ExpectedRanges = [ordered]@{
    "8016FC28" = "9C"
    "801910A4" = "234"
    "801914C0" = "C8"
    "80191C84" = "4A4"
    "80192D6C" = "EC"
    "801930BC" = "90"
}

$RequiredSeeds = @("0x8016FC28", "0x801930BC", "0x8018F10C")
$UnselectedFunctions = @(
    "80103384", "8017566C", "8019E6D0",
    "80192128", "80193174", "8019319C", "801931C4", "80192F60"
)

$DirectTargets = @(
    "80101D18", "80101D68", "8010C72C", "8012398C", "80123BA8",
    "80123E8C", "8012CCF0", "80168D14", "8016FCC4", "80177474",
    "8018F10C", "801910A4", "801914C0", "80191C84", "80192D6C",
    "801931FC", "8019326C", "8019327C", "801938B0", "801A75F4"
)

$RawChecks = @(
    @{ Address = "8016FC28"; Length = 0x9C; Sha256 = "9E15A9FD03FA579BD376D8D0351DD0B2E48D4816FBC9664E0C0BA67FDC0DEE54" },
    @{ Address = "801910A4"; Length = 0x234; Sha256 = "477AFA262A9232017D2F42BF7FB0EB6D7696CD188D998238B4C733AE602462D9" },
    @{ Address = "801914C0"; Length = 0xC8; Sha256 = "2AD855986EA8AFCFC08E74C15336143D1DAF15DAE99DC055D54999F5B7F85D9F" },
    @{ Address = "80191C84"; Length = 0x4A4; Sha256 = "AC9ACBAD5B0796F3E368561989C56EDBC32D59CA820940AB59804FECD536ABF0" },
    @{ Address = "80192D6C"; Length = 0xEC; Sha256 = "A0C54BC35960F6F089BB31AB1594AA47A9A4CC199A3EA137652AE19476D64A38" },
    @{ Address = "801930BC"; Length = 0x90; Sha256 = "5517E77195FAC935A53239E03F694A61EB20463795186296C8516D2B6EEB34AE" },
    @{ Address = "801AC894"; Length = 0x28; Sha256 = "1AABC8F933EE1BFF755D387263142D891DD8EC0456BFB750527041A55BFD6B78" },
    @{ Address = "801AE6D8"; Length = 0x150; Sha256 = "A07A0B997FAAE6C47DDCF757160A09AE95BB24600FB88580C9FCD6A1F75780BC" },
    @{ Address = "801B8538"; Length = 0x18; Sha256 = "03C177130E6FA58E4C8726C3D3FDF08821D018C8FDDB122F01F9C97C138F9AE7" }
)

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

function Get-FunctionRanges([string]$Path) {
    $Result = @{}
    foreach ($Line in Get-Content -LiteralPath $Path) {
        if ($Line -match '^R ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]+)$') {
            $Result[$Matches[1].ToUpperInvariant()] = $Matches[2].ToUpperInvariant()
        }
    }
    return $Result
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

foreach ($Required in @(
    $GameConfig, $GameExe, $SeedFile, $RangesFile, $GenerateScript,
    $AuditScript, $PreviewRanges, $GitIgnoreFile, $BiosEmitterShaFile
)) {
    Require-File $Required
}

$PreviewHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PreviewRanges).Hash
if ($PreviewHash -ne $ExpectedPostRangesSha256) {
    throw "Manifesto da previa completa S1-256 divergente. SHA-256: $PreviewHash"
}

$SeedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SeedFile).Hash
if ($SeedHash -ne $ExpectedSeedSha256) {
    throw "Arquivo de seeds nao corresponde ao S1-256 aprovado. SHA-256: $SeedHash"
}
$ActiveSeeds = @(
    Get-Content -LiteralPath $SeedFile |
        ForEach-Object { ($_ -split '#')[0].Trim().ToUpperInvariant() } |
        Where-Object { $_ -match '^0X[0-9A-F]{8}$' }
)
if ($ActiveSeeds.Count -ne $ExpectedSeedCount) {
    throw "S1-256 deveria conter $ExpectedSeedCount seeds ativas; encontrado: $($ActiveSeeds.Count)"
}
if (@($ActiveSeeds | Sort-Object -Unique).Count -ne $ActiveSeeds.Count) {
    throw "O arquivo principal contem seeds ativas duplicadas."
}
foreach ($Seed in $RequiredSeeds) {
    if ((Count-ExactLine $SeedFile $Seed) -ne 1) {
        throw "A seed aprovada $Seed deve aparecer exatamente uma vez."
    }
}
if ((Count-ExactLine $SeedFile "0x8019E6D0") -ne 0) {
    throw "A seed em quarentena 0x8019E6D0 nao pode estar ativa."
}

foreach ($Check in $RawChecks) {
    $Address = [Convert]::ToUInt32($Check.Address, 16)
    $Actual = Get-ExecutableRangeSha256 $GameExe $Address $Check.Length
    if ($Actual -ne $Check.Sha256) {
        throw "Bytes de 0x$($Check.Address)+0x$($Check.Length.ToString('X')) divergentes. SHA-256: $Actual"
    }
}

$ProtectedHashes = @{}
foreach ($Protected in @($GitIgnoreFile, $BiosEmitterShaFile)) {
    $ProtectedHashes[$Protected] = (
        Get-FileHash -Algorithm SHA256 -LiteralPath $Protected
    ).Hash
}

try {
    $CurrentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    $CurrentRanges = Get-FunctionRanges $RangesFile
    $AlreadyGenerated = (
        $CurrentHash -eq $ExpectedPostRangesSha256 -and
        $CurrentRanges.Count -eq $ExpectedPostFunctions
    )

    if (-not $AlreadyGenerated) {
        if ($CurrentHash -ne $ExpectedBaselineRangesSha256) {
            throw "Ranges antes da geracao nao correspondem ao S1-255. SHA-256: $CurrentHash"
        }
        if ($CurrentRanges.Count -ne $ExpectedBaselineFunctions) {
            throw "S1-255 deveria conter $ExpectedBaselineFunctions funcoes; encontrado: $($CurrentRanges.Count)"
        }
        foreach ($Address in $ExpectedRanges.Keys) {
            if ($CurrentRanges.ContainsKey($Address)) {
                throw "Funcao S1-256 ja apareceu parcialmente na baseline: F $Address"
            }
        }
        foreach ($Target in $DirectTargets) {
            if (
                -not $CurrentRanges.ContainsKey($Target) -and
                -not $ExpectedRanges.Contains($Target)
            ) {
                throw "Alvo JAL ainda nao nativo nem pertencente a closure aprovada: F $Target"
            }
        }
        foreach ($Address in $UnselectedFunctions) {
            if ($CurrentRanges.ContainsKey($Address)) {
                throw "Funcao proibida ja aparece na baseline: F $Address"
            }
        }

        if ($ValidateOnly) {
            Write-Host "Validacao estatica do gerador S1-256 concluida sobre a baseline S1-255."
            Write-Host "Nenhuma fonte foi gerada; BIOS e build nao foram iniciados."
            return
        }

        Write-Host "Baseline S1-255 confirmada. Gerando somente as fontes do jogo S1-256..."
        if ($RecompilerPath) {
            & $GenerateScript -RecompilerPath $RecompilerPath
        }
        else {
            & $GenerateScript
        }
        if ($LASTEXITCODE -ne 0) {
            throw "A geracao das fontes S1-256 falhou com codigo $LASTEXITCODE"
        }
    }
    else {
        if ($ValidateOnly) {
            Write-Host "Validacao estatica do gerador S1-256 concluida sobre fontes S1-256 ja presentes."
            Write-Host "Nenhuma fonte foi regenerada; BIOS e build nao foram iniciados."
            return
        }
        Write-Host "Fontes S1-256 ja presentes; repetindo apenas os gates pos-geracao."
    }

    $PostRanges = Get-FunctionRanges $RangesFile
    foreach ($Address in $ExpectedRanges.Keys) {
        $ExpectedLength = $ExpectedRanges[$Address]
        if (-not $PostRanges.ContainsKey($Address) -or $PostRanges[$Address] -ne $ExpectedLength) {
            throw "Range S1-256 ausente ou divergente: R $Address $ExpectedLength"
        }
    }
    foreach ($Address in $UnselectedFunctions) {
        if ($PostRanges.ContainsKey($Address)) {
            throw "Funcao fora da closure aprovada apareceu nos fontes: F $Address"
        }
    }

    [int64]$PostWords = 0
    foreach ($Length in $ExpectedRanges.Values) {
        $PostWords += [Convert]::ToInt64($Length, 16) / 4
    }
    $PostHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangesFile).Hash
    if ($PostRanges.Count -ne $ExpectedPostFunctions) {
        throw "S1-256 deveria conter $ExpectedPostFunctions funcoes; encontrado: $($PostRanges.Count)"
    }
    if ($PostWords -ne $ExpectedAddedWords) {
        throw "S1-256 deveria adicionar $ExpectedAddedWords palavras; calculado: $PostWords"
    }
    if ($PostHash -ne $ExpectedPostRangesSha256) {
        throw "Ranges apos a geracao divergiram da previa isolada. SHA-256: $PostHash"
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
        throw "A auditoria codegen do S1-256 falhou com codigo $LASTEXITCODE"
    }

    Write-Host ""
    Write-Host "S1-256 gerado e auditado."
    Write-Host "Funcoes: $($PostRanges.Count)"
    Write-Host "Funcoes adicionadas: 0x8016FC28, 0x801910A4, 0x801914C0, 0x80191C84, 0x80192D6C, 0x801930BC"
    Write-Host "Palavras adicionadas: $PostWords"
    Write-Host "Cobertura esperada: 111.116/195.584 palavras (56,8124%)"
    Write-Host "Ranges SHA-256: $PostHash"
    Write-Host "BIOS e build nao foram iniciados por este script."
}
finally {
    foreach ($Protected in $ProtectedHashes.Keys) {
        $AfterHash = (
            Get-FileHash -Algorithm SHA256 -LiteralPath $Protected
        ).Hash
        if ($AfterHash -ne $ProtectedHashes[$Protected]) {
            throw "Artefato protegido foi alterado: $Protected"
        }
    }
}
