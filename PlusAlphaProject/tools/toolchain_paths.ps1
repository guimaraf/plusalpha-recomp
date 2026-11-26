# Resolucao central de toolchain (MSYS2 / Python / retcomm). Uso: dot-source
#   . (Join-Path $PSScriptRoot 'toolchain_paths.ps1')
# Ordem de precedencia (parametro explicito do usuario sempre vence, fora daqui):
#   MSYS2 : $env:PLUSALPHA_MSYS2_ROOT -> <raiz do repo>\tools\msys64 -> C:\msys64
#   Python: $env:PLUSALPHA_PYTHON     -> <raiz do repo>\tools\python\python.exe -> Get-Command python
#   retcomm: $env:PLUSALPHA_RETCOMM_ROOT -> <raiz>\tools\retcomm\cmake-clang-v1\<versao mais nova>
# -RepoRoot permite simular outra raiz (dry-run sem/com tools\).

$script:PlusAlphaDefaultRepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))

function Get-PlusAlphaRepoRoot {
    param([string]$RepoRoot = '')
    if ($RepoRoot) { return $RepoRoot }
    return $script:PlusAlphaDefaultRepoRoot
}

function Resolve-PlusAlphaMsys2Root {
    param([string]$RepoRoot = '')
    $root = Get-PlusAlphaRepoRoot $RepoRoot
    if ($env:PLUSALPHA_MSYS2_ROOT -and (Test-Path -LiteralPath $env:PLUSALPHA_MSYS2_ROOT)) {
        return $env:PLUSALPHA_MSYS2_ROOT
    }
    $portable = Join-Path $root 'tools\msys64'
    if (Test-Path -LiteralPath (Join-Path $portable 'ucrt64\bin')) { return $portable }
    return 'C:\msys64'
}

function Resolve-PlusAlphaPython {
    param([string]$RepoRoot = '')
    $root = Get-PlusAlphaRepoRoot $RepoRoot
    if ($env:PLUSALPHA_PYTHON -and (Test-Path -LiteralPath $env:PLUSALPHA_PYTHON)) {
        return $env:PLUSALPHA_PYTHON
    }
    $portable = Join-Path $root 'tools\python\python.exe'
    if (Test-Path -LiteralPath $portable) { return $portable }
    return (Get-Command python -ErrorAction Stop).Source
}

function Resolve-PlusAlphaRetcommRoot {
    param([string]$RepoRoot = '')
    $root = Get-PlusAlphaRepoRoot $RepoRoot
    if ($env:PLUSALPHA_RETCOMM_ROOT -and (Test-Path -LiteralPath $env:PLUSALPHA_RETCOMM_ROOT)) {
        return $env:PLUSALPHA_RETCOMM_ROOT
    }
    $base = Join-Path $root 'tools\retcomm\cmake-clang-v1'
    if (Test-Path -LiteralPath $base) {
        $v = Get-ChildItem -LiteralPath $base -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin\clang.exe') } |
            Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
            Select-Object -First 1
        if ($v) { return $v.FullName }
    }
    return $null
}

# O gcc do MSYS2 so funciona (cc1 precisa das DLLs) com o bin no PATH do processo.
function Add-PlusAlphaMsys2ToPath {
    param([Parameter(Mandatory)][string]$Msys2Root)
    # So ucrt64: prepender mingw64 depois a poria na frente e trocaria o gcc dos builds.
    $bin = Join-Path $Msys2Root 'ucrt64\bin'
    if ((Test-Path -LiteralPath $bin) -and (($env:PATH -split ';') -notcontains $bin)) {
        $env:PATH = "$bin;$env:PATH"
    }
}
