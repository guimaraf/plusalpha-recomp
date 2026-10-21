# Executar manualmente. Compila em pasta separada e prepara um pacote novo.
[CmdletBinding()]
param(
    [switch]$Generate,
    [switch]$PackageOnly,
    [switch]$Incremental,
    [switch]$NoZip,
    [ValidatePattern('^build-release-online(?:-[A-Za-z0-9_-]+)?$')]
    [string]$BuildDirName = '',
    [ValidateRange(1, 64)][int]$Jobs = 2,
    [string]$Msys2Root = 'C:\msys64',
    [ValidateSet('SDL3', 'SDL2')][string]$SdlBackend = 'SDL3',
    [string]$BiosPath = '',
    [string]$RetainedOverlayDir = '',
    [string]$OutputDir = ''
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ($Generate -and $PackageOnly) { throw '-Generate nao pode ser usado com -PackageOnly.' }
if ($BiosPath -and $PackageOnly) { throw '-BiosPath nao se aplica a -PackageOnly; nenhuma compilacao ocorre nesse modo.' }
if ($Incremental -and ($PackageOnly -or -not $BuildDirName)) {
    throw '-Incremental requer -BuildDirName explicito e nao pode ser usado com -PackageOnly.'
}
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $BuildDirName) {
    # Keep the old package-only command usable; new builds always get a fresh path.
    $BuildDirName = if ($PackageOnly) { 'build-release-online' } else { "build-release-online-$Stamp" }
}
$BuildDir = Join-Path $ProjectRoot $BuildDirName
if (-not $PackageOnly -and (Test-Path -LiteralPath $BuildDir) -and -not $Incremental) {
    throw "Build existente preservada: $BuildDir. Escolha outro -BuildDirName ou use -Incremental para recompilar essa pasta intencionalmente."
}
if (-not $OutputDir) {
    $OutputDir = Join-Path $ProjectRoot ("dist\exPlusAlpha-$Stamp")
}
if (Test-Path -LiteralPath $OutputDir) { throw "Pacote existente preservado: $OutputDir. Escolha outra pasta de saida." }
$ArchivePath = "$OutputDir.zip"
if (-not $NoZip) {
    foreach ($Artifact in @($ArchivePath, "$ArchivePath.partial", "$ArchivePath.sha256")) {
        if (Test-Path -LiteralPath $Artifact) { throw "Arquivo existente preservado: $Artifact. Escolha outra pasta de saida." }
    }
}
if (-not $PackageOnly) {
    $BuildArgs = @{
        Release = $true
        BuildDirName = $BuildDirName
        StaticOverlayDir = (Join-Path $BuildDir 'static-overlays')
        Generate = $Generate
        Jobs = $Jobs
        Msys2Root = $Msys2Root
        SdlBackend = $SdlBackend
        BiosPath = $BiosPath
    }
    if ($RetainedOverlayDir) { $BuildArgs.RetainedOverlayDir = $RetainedOverlayDir }
    Write-Host "Release: $BuildDir" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'build_online.ps1') @BuildArgs
}
$Python = (Get-Command python -ErrorAction Stop).Source
$PackageArgs = @('-B', (Join-Path $PSScriptRoot 'package_release.py'),
    '--build', $BuildDir, '--output', $OutputDir,
    '--ucrt-bin', (Join-Path $Msys2Root 'ucrt64\bin'))
if (-not $NoZip) { $PackageArgs += @('--zip-path', $ArchivePath) }
& $Python @PackageArgs
if ($LASTEXITCODE -ne 0) { throw "Empacotamento falhou: $LASTEXITCODE" }
Write-Host "Launcher pronto para teste: $OutputDir\exPlusAlpha.exe" -ForegroundColor Green
Write-Host 'Release sem diagnostico: modos experimentais de input desativados; launcher e netplay habilitados.'
if (-not $NoZip) {
    Write-Host "Arquivo para enviar: $ArchivePath" -ForegroundColor Green
    Write-Host "Integridade: $ArchivePath.sha256"
}
Write-Host 'Posicionamento das janelas funciona com position_netplay_windows.ps1; o coletor TCP requer a build de diagnostico.'
