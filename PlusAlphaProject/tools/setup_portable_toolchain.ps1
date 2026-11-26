<#
.SYNOPSIS
  Instala (de forma reprodutivel e idempotente) o toolchain portatil em <RepoRoot>\tools\.

.DESCRIPTION
  Le PlusAlphaProject\tools\toolchain.lock.json e instala:
    msys2   : MSYS2 base + pacotes mingw-w64-* exatos (pacman -U, sem -Syu)
    python  : Python NuGet 3.13.11 + requisitos pip com versoes fixas
    retcomm : cmake-clang-v1 (clang/cmake/ninja) do RetroPorting-Toolchains
  e gera tools\env.ps1 / tools\env.sh a partir de PlusAlphaProject\tools\toolchain\env.*.in.
  Nao altera C:\msys64, o Python do sistema nem o PATH global (apenas o ambiente de processos filhos).

.PARAMETER RepoRoot   Raiz do repositorio (padrao: duas pastas acima deste script).
.PARAMETER CacheDir   Cache offline adicional (ex.: copia de tools\_dl). Quando informado, NADA e baixado.
.PARAMETER Component  msys2 | python | retcomm | all (padrao).
.PARAMETER DryRun     So confere lock, cache (sha256), instalacao atual e URLs (HEAD); nao instala nem baixa.
.PARAMETER Force      Refaz as etapas mesmo que ja estejam instaladas (re-extrai e reinstala; nao apaga pastas).
#>
param(
    [string]$RepoRoot = '',
    [string]$CacheDir = '',
    [ValidateSet('msys2', 'python', 'retcomm', 'all')]
    [string]$Component = 'all',
    [switch]$DryRun,
    [switch]$Force,
    [string]$LockFile = ''
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$ProgressPreference = 'SilentlyContinue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoRoot) { $RepoRoot = [IO.Path]::GetFullPath((Join-Path $ScriptDir '..\..')) }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
if (-not $LockFile) { $LockFile = Join-Path $ScriptDir 'toolchain.lock.json' }
$ToolsDir = Join-Path $RepoRoot 'tools'
$DlDir = Join-Path $ToolsDir '_dl'
$Msys2Dir = Join-Path $ToolsDir 'msys64'
$PythonDir = Join-Path $ToolsDir 'python'
$TplDir = Join-Path $ScriptDir 'toolchain'

$script:Problems = New-Object System.Collections.ArrayList
$script:UrlFail = New-Object System.Collections.ArrayList

function Write-Info([string]$m) { Write-Host "[toolchain] $m" -ForegroundColor Cyan }
function Write-Ok([string]$m)   { Write-Host "[toolchain] OK: $m" -ForegroundColor Green }
function Write-Warn2([string]$m){ Write-Host "[toolchain] AVISO: $m" -ForegroundColor Yellow }
function Add-Problem([string]$m){ [void]$script:Problems.Add($m); Write-Host "[toolchain] ERRO: $m" -ForegroundColor Red }

function Get-Sha256Lower([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

# Converte caminho Windows em caminho MSYS (/f/pasta/...).
function ConvertTo-MsysPath([string]$p) {
    $full = [IO.Path]::GetFullPath($p)
    $drive = $full.Substring(0, 1).ToLowerInvariant()
    return '/' + $drive + $full.Substring(2).Replace('\', '/')
}

# Executa um nativo com stdout/stderr capturados (sem o problema de ErrorRecord do PS 5.1).
function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments = @(), [hashtable]$Env = @{}, [string]$WorkDir = '', [switch]$Stream)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $quoted = @()
    foreach ($a in $Arguments) {
        if ($a -match '[\s"]') { $quoted += ('"' + ($a -replace '"', '\"') + '"') } else { $quoted += $a }
    }
    $psi.Arguments = ($quoted -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = [string]$Env[$k] }
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = New-Object System.Text.StringBuilder
    while (-not $p.StandardOutput.EndOfStream) {
        $line = $p.StandardOutput.ReadLine()
        [void]$out.AppendLine($line)
        if ($Stream) { Write-Host "    $line" }
    }
    $p.WaitForExit()
    $err = $errTask.Result
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Output = $out.ToString(); Error = $err }
}

function Test-UrlHead([string]$Url) {
    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 60
        return [pscustomobject]@{ Ok = $true; Status = [int]$r.StatusCode; Msg = '' }
    } catch {
        $st = 0
        $msg = $_.Exception.Message
        try { $st = [int]$_.Exception.Response.StatusCode } catch {}
        # Alguns servidores (ex.: API v2 do NuGet) nao aceitam HEAD; tenta GET de 1 byte (Range) como sonda.
        try {
            $q = [Net.HttpWebRequest]::Create($Url)
            $q.Method = 'GET'
            $q.Timeout = 60000
            $q.AddRange(0, 0)
            $rs = $q.GetResponse()
            $code = [int]$rs.StatusCode
            $rs.Close()
            if ($code -ge 200 -and $code -lt 400) { return [pscustomobject]@{ Ok = $true; Status = $code; Msg = 'HEAD recusado; GET Range ok' } }
        } catch {}
        return [pscustomobject]@{ Ok = $false; Status = $st; Msg = $msg }
    }
}

# Localiza um arquivo por nome em um diretorio de cache (recursivo).
function Find-InCache([string]$Dir, [string]$Name) {
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir)) { return $null }
    $direct = Join-Path $Dir $Name
    if (Test-Path -LiteralPath $direct) { return $direct }
    $f = Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.FullName }
    return $null
}

# Garante o arquivo em $DestDir com sha256 correto. Retorna o caminho (ou $null em DryRun/ausente).
# Estados (DryRun): cache-ok | cache-adicional-ok | cache-divergente | ausente
function Get-LockedFile {
    param([string]$Name, [string]$Url, [string]$Sha256, [string]$DestDir, [bool]$MayBeRemoved = $false)
    $dest = Join-Path $DestDir $Name
    $want = $Sha256.ToLowerInvariant()

    if (Test-Path -LiteralPath $dest) {
        if ((Get-Sha256Lower $dest) -eq $want) { return [pscustomobject]@{ Path = $dest; State = 'cache-ok' } }
        if ($DryRun) { return [pscustomobject]@{ Path = $dest; State = 'cache-divergente' } }
        Write-Warn2 "$Name existe em _dl com sha256 divergente; sera substituido."
        Remove-Item -LiteralPath $dest -Force
    }
    if ($CacheDir) {
        $alt = Find-InCache $CacheDir $Name
        if ($alt) {
            if ((Get-Sha256Lower $alt) -eq $want) {
                if ($DryRun) { return [pscustomobject]@{ Path = $alt; State = 'cache-adicional-ok' } }
                New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
                Copy-Item -LiteralPath $alt -Destination $dest -Force
                return [pscustomobject]@{ Path = $dest; State = 'cache-adicional-ok' }
            }
            Add-Problem "$Name em CacheDir ($alt) com sha256 divergente."
            return [pscustomobject]@{ Path = $null; State = 'cache-divergente' }
        }
    }
    if ($DryRun) { return [pscustomobject]@{ Path = $null; State = 'ausente' } }
    if ($CacheDir) {
        Add-Problem "Modo offline (-CacheDir): $Name nao encontrado em $CacheDir nem em $DestDir."
        return [pscustomobject]@{ Path = $null; State = 'ausente' }
    }
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    Write-Info "Baixando $Name ..."
    $tmp = $dest + '.part'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 1800
    } catch {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        $extra = ''
        if ($MayBeRemoved) { $extra = ' (versao antiga: pode nao estar mais no repositorio; use -CacheDir com os arquivos exatos)' }
        Add-Problem "Falha ao baixar $Name de $Url$extra : $($_.Exception.Message)"
        return [pscustomobject]@{ Path = $null; State = 'falha-download' }
    }
    $got = Get-Sha256Lower $tmp
    if ($got -ne $want) {
        Remove-Item -LiteralPath $tmp -Force
        Add-Problem "sha256 de $Name nao confere (esperado $want, obtido $got)."
        return [pscustomobject]@{ Path = $null; State = 'sha-divergente' }
    }
    Move-Item -LiteralPath $tmp -Destination $dest -Force
    return [pscustomobject]@{ Path = $dest; State = 'baixado' }
}

# ---------------------------------------------------------------- lock
if (-not (Test-Path -LiteralPath $LockFile)) { throw "Lock nao encontrado: $LockFile" }
$Lock = Get-Content -LiteralPath $LockFile -Raw | ConvertFrom-Json
if ($Lock.schema -ne 1) { throw "Schema do lock nao suportado: $($Lock.schema)" }

$doMsys2 = ($Component -eq 'all' -or $Component -eq 'msys2')
$doPython = ($Component -eq 'all' -or $Component -eq 'python')
$doRetcomm = ($Component -eq 'all' -or $Component -eq 'retcomm')

Write-Info "RepoRoot : $RepoRoot"
Write-Info "tools    : $ToolsDir"
Write-Info "Lock     : $LockFile"
if ($CacheDir) { Write-Info "CacheDir : $CacheDir (modo offline: nenhum download)" }
if ($DryRun) { Write-Info 'Modo -DryRun: nada sera baixado nem instalado.' }

# ---------------------------------------------------------------- estado atual
function Get-Msys2MissingPackages {
    $missing = @()
    $local = Join-Path $Msys2Dir 'var\lib\pacman\local'
    foreach ($p in $Lock.msys2.packages) {
        if (-not (Test-Path -LiteralPath (Join-Path $local ($p.name + '-' + $p.version)))) { $missing += $p }
    }
    return $missing
}

function Get-PythonInstalledVersion {
    $py = Join-Path $PythonDir 'python.exe'
    if (-not (Test-Path -LiteralPath $py)) { return '' }
    try {
        $r = Invoke-Native $py @('-c', 'import sys;print("%d.%d.%d" % sys.version_info[:3])')
        if ($r.ExitCode -eq 0) { return $r.Output.Trim() }
    } catch {}
    return ''
}

function Get-PipMissing {
    $py = Join-Path $PythonDir 'python.exe'
    $want = @($Lock.python.pip_resolved)
    if (-not (Test-Path -LiteralPath $py)) { return $want }
    $r = Invoke-Native $py @('-m', 'pip', 'freeze', '--disable-pip-version-check')
    $have = @{}
    if ($r.ExitCode -eq 0) {
        foreach ($l in ($r.Output -split "`r?`n")) { if ($l.Trim()) { $have[$l.Trim().ToLowerInvariant()] = $true } }
    }
    $miss = @()
    foreach ($w in $want) { if (-not $have.ContainsKey($w.ToLowerInvariant())) { $miss += $w } }
    return $miss
}

function Test-RetcommInstalled {
    $dir = Join-Path $ToolsDir ($Lock.retcomm.target_dir.Replace('/', '\'))
    $json = Join-Path $dir 'retcomm-toolchain.json'
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'bin\clang.exe'))) { return $false }
    if (-not (Test-Path -LiteralPath $json)) { return $false }
    try {
        $j = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
        return ($j.version -eq $Lock.retcomm.version)
    } catch { return $false }
}

# ---------------------------------------------------------------- DryRun: cache + URLs
function Invoke-DryRunChecks {
    $items = @()
    if ($doMsys2) {
        $items += [pscustomobject]@{ Name = $Lock.msys2.base.name; Url = $Lock.msys2.base.url; Sha = $Lock.msys2.base.sha256; Dir = $DlDir; Old = $true }
        foreach ($p in $Lock.msys2.packages) {
            $items += [pscustomobject]@{ Name = $p.file; Url = $p.url; Sha = $p.sha256; Dir = (Join-Path $DlDir 'pkgs'); Old = $true }
        }
    }
    if ($doPython) {
        $items += [pscustomobject]@{ Name = $Lock.python.file; Url = $Lock.python.url; Sha = $Lock.python.sha256; Dir = $DlDir; Old = $false }
    }
    if ($doRetcomm) {
        $items += [pscustomobject]@{ Name = $Lock.retcomm.asset; Url = $Lock.retcomm.url; Sha = $Lock.retcomm.sha256; Dir = (Join-Path $DlDir 'retcomm'); Old = $false }
    }
    $stCount = @{}
    $i = 0
    foreach ($it in $items) {
        $i++
        $st = Get-LockedFile -Name $it.Name -Url $it.Url -Sha256 $it.Sha -DestDir $it.Dir -MayBeRemoved $it.Old
        if (-not $stCount.ContainsKey($st.State)) { $stCount[$st.State] = 0 }
        $stCount[$st.State]++
        if ($st.State -eq 'cache-divergente') { Add-Problem "sha256 divergente no cache: $($it.Name)" }
        elseif ($st.State -eq 'ausente') { Write-Warn2 "ausente no cache (seria baixado): $($it.Name)" }
        $h = Test-UrlHead $it.Url
        if (-not $h.Ok) {
            [void]$script:UrlFail.Add([pscustomobject]@{ Name = $it.Name; Url = $it.Url; Status = $h.Status; Msg = $h.Msg })
        }
        if (($i % 20) -eq 0) { Write-Info "  ... $i/$($items.Count) conferidos" }
    }
    Write-Info ('Cache (sha256): ' + (($stCount.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '))
    $okUrls = $items.Count - $script:UrlFail.Count
    Write-Info "URLs (HEAD): $okUrls ok, $($script:UrlFail.Count) falha(s) de $($items.Count)"
    foreach ($f in $script:UrlFail) { Write-Warn2 "HEAD falhou ($($f.Status)): $($f.Url) - $($f.Msg)" }

    Write-Info 'Estado atual de tools\:'
    if ($doMsys2) {
        $m = @(Get-Msys2MissingPackages)
        $baseOk = Test-Path -LiteralPath (Join-Path $Msys2Dir 'usr\bin\bash.exe')
        Write-Info "  msys2  : base=$baseOk, pacotes faltando=$($m.Count) de $(@($Lock.msys2.packages).Count)"
    }
    if ($doPython) {
        $v = Get-PythonInstalledVersion
        $pm = @(Get-PipMissing)
        Write-Info "  python : versao='$v' (lock $($Lock.python.version)), pip faltando=$($pm.Count)"
    }
    if ($doRetcomm) {
        Write-Info "  retcomm: instalado=$(Test-RetcommInstalled)"
    }
}

# ---------------------------------------------------------------- MSYS2
function Install-Msys2 {
    Write-Info '== MSYS2 =='
    $bash = Join-Path $Msys2Dir 'usr\bin\bash.exe'
    $baseNeeded = $Force -or -not (Test-Path -LiteralPath $bash)
    $missing = @(Get-Msys2MissingPackages)
    if ($Force) { $missing = @($Lock.msys2.packages) }

    if (-not $baseNeeded -and $missing.Count -eq 0) {
        Write-Ok 'MSYS2 base e todos os pacotes ja instalados (nada a fazer).'
        return
    }

    if ($baseNeeded) {
        $b = Get-LockedFile -Name $Lock.msys2.base.name -Url $Lock.msys2.base.url -Sha256 $Lock.msys2.base.sha256 -DestDir $DlDir -MayBeRemoved $true
        if (-not $b.Path) { return }
        Write-Info "Extraindo MSYS2 base para $ToolsDir ..."
        New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
        $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
        if (-not (Test-Path -LiteralPath $tarExe)) { $tarExe = 'tar' }
        $r = Invoke-Native $tarExe @('-xf', $b.Path, '-C', $ToolsDir)
        if ($r.ExitCode -ne 0) { Add-Problem "tar falhou ao extrair MSYS2 base (rc $($r.ExitCode)): $($r.Error)"; return }
        if (-not (Test-Path -LiteralPath $bash)) { Add-Problem 'MSYS2 base extraido sem usr\bin\bash.exe.'; return }
        Write-Info 'Inicializando MSYS2 (primeira execucao) ...'
        $r = Invoke-Native $bash @('-lc', 'exit 0') -Env @{ MSYSTEM = 'MSYS'; MSYS2_PATH_TYPE = 'minimal' }
        if ($r.ExitCode -ne 0) { Write-Warn2 "primeira execucao do bash rc=$($r.ExitCode): $($r.Error)" }
        $missing = @(Get-Msys2MissingPackages)
        if ($Force) { $missing = @($Lock.msys2.packages) }
    }

    if ($missing.Count -eq 0) { Write-Ok 'Nenhum pacote mingw-w64 a instalar.'; return }

    Write-Info "Obtendo $($missing.Count) pacote(s) mingw-w64 ..."
    $pkgDir = Join-Path $DlDir 'pkgs'
    $files = @()
    $fail = $false
    foreach ($p in $missing) {
        $g = Get-LockedFile -Name $p.file -Url $p.url -Sha256 $p.sha256 -DestDir $pkgDir -MayBeRemoved $true
        if (-not $g.Path) { $fail = $true } else { $files += $p.file }
    }
    if ($fail) { Add-Problem 'Pacotes ausentes/invalidos; instalacao de pacotes abortada (nada foi instalado).'; return }

    # pacman.conf temporario sem checagem de assinatura: a integridade e garantida pelo sha256 do lock.
    $confSrc = Join-Path $Msys2Dir 'etc\pacman.conf'
    $confName = 'pacman.setup.conf'
    $confDst = Join-Path $Msys2Dir "etc\$confName"
    $text = [IO.File]::ReadAllText($confSrc)
    $text = [regex]::Replace($text, '(?m)^SigLevel\s*=.*$', 'SigLevel = Never')
    $text = [regex]::Replace($text, '(?m)^LocalFileSigLevel\s*=.*$', 'LocalFileSigLevel = Never')
    [IO.File]::WriteAllText($confDst, ($text -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    try {
        $needed = '--needed'
        if ($Force) { $needed = '' }
        $cmd = "cd '" + (ConvertTo-MsysPath $pkgDir) + "' && pacman -U --noconfirm $needed --config /etc/$confName " + ($files -join ' ')
        Write-Info 'Instalando pacotes com pacman -U (sem -Syu) ...'
        $r = Invoke-Native $bash @('-lc', $cmd) -Env @{ MSYSTEM = 'MSYS'; MSYS2_PATH_TYPE = 'minimal' }
        $tail = ($r.Output -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 6) -join "`n    "
        if ($tail) { Write-Host "    $tail" }
        if ($r.ExitCode -ne 0) { Add-Problem "pacman -U falhou (rc $($r.ExitCode)): $($r.Error)"; return }
    } finally {
        if (Test-Path -LiteralPath $confDst) { Remove-Item -LiteralPath $confDst -Force }
    }
    $still = @(Get-Msys2MissingPackages)
    if ($still.Count -gt 0) { Add-Problem "Pacotes ainda ausentes apos pacman: $(($still | ForEach-Object { $_.name }) -join ', ')" }
    else { Write-Ok "MSYS2: $(@($Lock.msys2.packages).Count) pacotes instalados." }
}

# ---------------------------------------------------------------- Python
function Install-Python {
    Write-Info '== Python =='
    $py = Join-Path $PythonDir 'python.exe'
    $ver = Get-PythonInstalledVersion
    $needExtract = $Force -or ($ver -ne $Lock.python.version)
    if ($needExtract) {
        $g = Get-LockedFile -Name $Lock.python.file -Url $Lock.python.url -Sha256 $Lock.python.sha256 -DestDir $DlDir
        if (-not $g.Path) { return }
        $stage = Join-Path $DlDir 'py'
        Write-Info "Extraindo Python NuGet ($($Lock.python.version)) ..."
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
        if (-not (Test-Path -LiteralPath $tarExe)) { $tarExe = 'tar' }
        $r = Invoke-Native $tarExe @('-xf', $g.Path, '-C', $stage)
        if ($r.ExitCode -ne 0) { Add-Problem "tar falhou ao extrair nupkg (rc $($r.ExitCode)): $($r.Error)"; return }
        $src = Join-Path $stage $Lock.python.extract_subdir
        if (-not (Test-Path -LiteralPath (Join-Path $src 'python.exe'))) { Add-Problem "nupkg sem $($Lock.python.extract_subdir)\python.exe"; return }
        New-Item -ItemType Directory -Force -Path $PythonDir | Out-Null
        $r = Invoke-Native 'robocopy.exe' @($src, $PythonDir, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
        if ($r.ExitCode -ge 8) { Add-Problem "robocopy falhou (rc $($r.ExitCode))."; return }
        $ver = Get-PythonInstalledVersion
        if ($ver -ne $Lock.python.version) { Add-Problem "Python instalado reporta '$ver', esperado $($Lock.python.version)."; return }
        Write-Ok "Python $ver extraido."
    } else {
        Write-Ok "Python $ver ja instalado."
    }

    $miss = @(Get-PipMissing)
    if ($Force) { $miss = @($Lock.python.pip_resolved) }
    if ($miss.Count -eq 0) { Write-Ok 'Requisitos pip ja instalados (versoes exatas).'; return }

    $r = Invoke-Native $py @('-m', 'pip', '--version')
    if ($r.ExitCode -ne 0) {
        Write-Info 'pip ausente; executando ensurepip ...'
        $r = Invoke-Native $py @('-m', 'ensurepip', '--upgrade')
        if ($r.ExitCode -ne 0) { Add-Problem "ensurepip falhou: $($r.Error)"; return }
    }
    $pipCache = Join-Path $DlDir 'pip'
    $pipEnv = @{ PYTHONUTF8 = '1'; PIP_DISABLE_PIP_VERSION_CHECK = '1' }
    $resolved = @($Lock.python.pip_resolved)
    if ($CacheDir) {
        $alt = Join-Path $CacheDir 'pip'
        if (Test-Path -LiteralPath $alt) { $pipCache = $alt }
        elseif (-not (Test-Path -LiteralPath $pipCache)) { Add-Problem "Modo offline: sem wheels em $alt nem em $pipCache."; return }
    } else {
        Write-Info 'Baixando wheels (pip download) para o cache _dl\pip ...'
        New-Item -ItemType Directory -Force -Path $pipCache | Out-Null
        $r = Invoke-Native $py (@('-m', 'pip', 'download', '--dest', $pipCache, '--only-binary=:all:') + $resolved) -Env $pipEnv
        if ($r.ExitCode -ne 0) { Add-Problem "pip download falhou: $($r.Error)"; return }
    }
    Write-Info 'Instalando requisitos pip (versoes fixas, sem rede) ...'
    $args2 = @('-m', 'pip', 'install', '--no-index', '--find-links', $pipCache, '--no-warn-script-location')
    if ($Force) { $args2 += '--force-reinstall' }
    $r = Invoke-Native $py ($args2 + $resolved) -Env $pipEnv
    if ($r.ExitCode -ne 0) { Add-Problem "pip install falhou: $($r.Error)"; return }
    $miss = @(Get-PipMissing)
    if ($miss.Count -gt 0) { Add-Problem "pip: ainda faltando $($miss -join ', ')" } else { Write-Ok 'Requisitos pip instalados.' }
}

# ---------------------------------------------------------------- retcomm
function Install-Retcomm {
    Write-Info '== retcomm cmake-clang-v1 =='
    $target = Join-Path $ToolsDir ($Lock.retcomm.target_dir.Replace('/', '\'))
    if (-not $Force -and (Test-RetcommInstalled)) {
        Write-Ok "retcomm $($Lock.retcomm.version) ja instalado."
        return
    }
    $g = Get-LockedFile -Name $Lock.retcomm.asset -Url $Lock.retcomm.url -Sha256 $Lock.retcomm.sha256 -DestDir (Join-Path $DlDir 'retcomm')
    if (-not $g.Path) { return }
    $stage = Join-Path $ToolsDir 'retcomm\_extract_tmp'
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Write-Info 'Extraindo zip (centenas de MB; pode demorar) ...'
    $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (-not (Test-Path -LiteralPath $tarExe)) { $tarExe = 'tar' }
    $r = Invoke-Native $tarExe @('-xf', $g.Path, '-C', $stage)
    if ($r.ExitCode -ne 0) { Add-Problem "tar falhou ao extrair retcomm (rc $($r.ExitCode)): $($r.Error)"; return }
    $root = $stage
    $entries = @(Get-ChildItem -LiteralPath $stage -Force)
    if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) { $root = $entries[0].FullName }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'bin\clang.exe'))) { Add-Problem 'zip do retcomm sem bin\clang.exe.'; return }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    $r = Invoke-Native 'robocopy.exe' @($root, $target, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/MT:8')
    if ($r.ExitCode -ge 8) { Add-Problem "robocopy falhou (rc $($r.ExitCode))."; return }
    Remove-Item -LiteralPath $stage -Recurse -Force
    # confere binarios principais contra o lock
    foreach ($k in $Lock.retcomm.key_binaries.PSObject.Properties) {
        $f = Join-Path $target ($k.Name.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $f)) { Add-Problem "retcomm: $($k.Name) ausente."; continue }
        if ((Get-Sha256Lower $f) -ne $k.Value) { Add-Problem "retcomm: sha256 de $($k.Name) diverge do lock." }
    }
    if (Test-RetcommInstalled) { Write-Ok "retcomm $($Lock.retcomm.version) instalado." } else { Add-Problem 'retcomm instalado mas versao nao confere.' }
}

# ---------------------------------------------------------------- env.ps1 / env.sh
function New-EnvFiles {
    Write-Info '== env.ps1 / env.sh =='
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    $map = @(
        @{ In = 'env.ps1.in'; Out = 'env.ps1'; Eol = "`r`n" },
        @{ In = 'env.sh.in';  Out = 'env.sh';  Eol = "`n" }
    )
    foreach ($m in $map) {
        $src = Join-Path $TplDir $m.In
        if (-not (Test-Path -LiteralPath $src)) { Add-Problem "Modelo ausente: $src"; continue }
        $t = [IO.File]::ReadAllText($src)
        # Modelos sao auto-localizaveis ($PSScriptRoot / dirname BASH_SOURCE); @@TOOLS_ROOT@@ e opcional.
        $t = $t.Replace('@@TOOLS_ROOT@@', $ToolsDir)
        $t = ($t -replace "`r`n", "`n") -replace "`n", $m.Eol
        [IO.File]::WriteAllText((Join-Path $ToolsDir $m.Out), $t, (New-Object System.Text.UTF8Encoding($false)))
        Write-Ok "tools\$($m.Out) gerado."
    }
}

# ---------------------------------------------------------------- smoke tests
function Invoke-SmokeTests {
    Write-Info '== Smoke tests =='
    $ucrt = Join-Path $Msys2Dir 'ucrt64\bin'
    $mingw = Join-Path $Msys2Dir 'mingw64\bin'
    $tmp = Join-Path $ToolsDir '_tmp'
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $baseEnv = @{ PYTHONUTF8 = '1'; TEMP = $tmp; TMP = $tmp }
    $results = New-Object System.Collections.ArrayList
    function Add-Result([string]$n, [bool]$ok, [string]$d) {
        [void]$results.Add([pscustomobject]@{ Teste = $n; Ok = $ok; Detalhe = $d })
        if ($ok) { Write-Ok "$n : $d" } else { Add-Problem "smoke '$n' falhou: $d" }
    }

    if ($doMsys2) {
        $c = Join-Path $tmp 'smoke.c'
        [IO.File]::WriteAllText($c, "int smoke_add(int a,int b){return a+b;}`n")
        foreach ($pair in @(@('ucrt64', $ucrt), @('mingw64', $mingw))) {
            $gcc = Join-Path $pair[1] 'gcc.exe'
            $dll = Join-Path $tmp ("smoke_" + $pair[0] + ".dll")
            if (Test-Path -LiteralPath $dll) { Remove-Item -LiteralPath $dll -Force }
            if (-not (Test-Path -LiteralPath $gcc)) { Add-Result "gcc $($pair[0])" $false 'gcc.exe ausente'; continue }
            $e = @{} + $baseEnv
            $e['PATH'] = $pair[1] + ';' + $env:PATH
            $r = Invoke-Native $gcc @('-shared', '-O1', '-o', $dll, $c) -Env $e
            $ok = ($r.ExitCode -eq 0) -and (Test-Path -LiteralPath $dll)
            $v = Invoke-Native $gcc @('--version') -Env $e
            $first = ($v.Output -split "`r?`n")[0]
            Add-Result "gcc -shared ($($pair[0]))" $ok ("rc=$($r.ExitCode) $first $($r.Error)".Trim())
        }
        $e = @{} + $baseEnv; $e['PATH'] = $ucrt + ';' + $env:PATH
        foreach ($t in @('cmake.exe', 'ninja.exe')) {
            $exe = Join-Path $ucrt $t
            if (-not (Test-Path -LiteralPath $exe)) { Add-Result "$t (msys2)" $false 'ausente'; continue }
            $r = Invoke-Native $exe @('--version') -Env $e
            Add-Result "$t --version (msys2)" ($r.ExitCode -eq 0) (($r.Output -split "`r?`n")[0])
        }
    }
    if ($doPython) {
        $py = Join-Path $PythonDir 'python.exe'
        if (Test-Path -LiteralPath $py) {
            $r = Invoke-Native $py @('-c', 'import tomllib, ssl, sys; print(sys.version.split()[0], ssl.OPENSSL_VERSION)') -Env $baseEnv
            Add-Result 'python tomllib+ssl' ($r.ExitCode -eq 0) ("$($r.Output.Trim()) $($r.Error)".Trim())
            $r = Invoke-Native $py @('-c', 'import numpy, PIL, yaml, pytest; print("numpy", numpy.__version__, "PIL", PIL.__version__, "yaml", yaml.__version__, "pytest", pytest.__version__)') -Env $baseEnv
            Add-Result 'python pacotes (numpy/PIL/yaml/pytest)' ($r.ExitCode -eq 0) ("$($r.Output.Trim()) $($r.Error)".Trim())
        } else { Add-Result 'python' $false 'python.exe ausente' }
    }
    if ($doRetcomm) {
        $rb = Join-Path $ToolsDir (($Lock.retcomm.target_dir.Replace('/', '\')) + '\bin')
        foreach ($t in @('clang.exe', 'cmake.exe', 'ninja.exe')) {
            $exe = Join-Path $rb $t
            if (-not (Test-Path -LiteralPath $exe)) { Add-Result "$t (retcomm)" $false 'ausente'; continue }
            $r = Invoke-Native $exe @('--version') -Env $baseEnv
            Add-Result "$t --version (retcomm)" ($r.ExitCode -eq 0) (($r.Output -split "`r?`n")[0])
        }
    }
}

# ---------------------------------------------------------------- principal
if ($DryRun) {
    Invoke-DryRunChecks
} else {
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $DlDir | Out-Null
    if ($doMsys2) { Install-Msys2 }
    if ($doPython) { Install-Python }
    if ($doRetcomm) { Install-Retcomm }
    New-EnvFiles
    Invoke-SmokeTests
}

Write-Host ''
if ($script:Problems.Count -gt 0) {
    Write-Host "[toolchain] CONCLUIDO COM $($script:Problems.Count) PROBLEMA(S):" -ForegroundColor Red
    foreach ($p in $script:Problems) { Write-Host "  - $p" -ForegroundColor Red }
    exit 1
}
if ($DryRun -and $script:UrlFail.Count -gt 0) {
    Write-Host "[toolchain] DryRun concluido; $($script:UrlFail.Count) URL(s) com HEAD falho (veja avisos)." -ForegroundColor Yellow
    exit 0
}
Write-Ok 'Concluido.'
exit 0
