[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$PackagePath,

    [string]$PfxPath,

    [Security.SecureString]$PfxPassword,

    [string]$CertificateOutputPath,

    [string]$TimestampUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$BuildRoot = Join-Path $ProjectRoot "UWP-Build"
$PackageRoot = Join-Path $BuildRoot "AppPackages"

function Resolve-SignTool {
    $fromPath = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    $kitsRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (-not (Test-Path -LiteralPath $kitsRoot -PathType Container)) {
        throw "Windows SDK nao encontrado em: $kitsRoot"
    }

    $sdkDirectories = Get-ChildItem -LiteralPath $kitsRoot -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object { [Version]$_.Name } -Descending

    foreach ($sdkDirectory in $sdkDirectories) {
        foreach ($hostArchitecture in "x64", "x86") {
            $candidate = Join-Path $sdkDirectory.FullName "$hostArchitecture\signtool.exe"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }

    throw "SignTool.exe nao foi encontrado no Windows SDK."
}

function Resolve-PackagePath {
    if ($PackagePath) {
        return [IO.Path]::GetFullPath($PackagePath)
    }

    if (-not (Test-Path -LiteralPath $PackageRoot -PathType Container)) {
        throw "Diretorio de pacotes nao encontrado: $PackageRoot"
    }

    $latestPackage = Get-ChildItem -LiteralPath $PackageRoot -Filter "*.msix" -Recurse -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latestPackage) {
        throw "Nenhum arquivo .msix foi encontrado em: $PackageRoot"
    }

    return $latestPackage.FullName
}

function Read-PackagePublisher {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $manifestEntry = $archive.GetEntry("AppxManifest.xml")
        if (-not $manifestEntry) {
            throw "AppxManifest.xml nao foi encontrado dentro de: $Path"
        }

        $reader = [IO.StreamReader]::new($manifestEntry.Open())
        try {
            [xml]$manifest = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }

        $publisher = [string]$manifest.Package.Identity.Publisher
        if ([string]::IsNullOrWhiteSpace($publisher)) {
            throw "Publisher ausente no AppxManifest.xml."
        }

        return $publisher
    }
    finally {
        $archive.Dispose()
    }
}

function ConvertTo-PlainText {
    param(
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$SecureValue
    )

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

$resolvedPackage = Resolve-PackagePath
if (-not (Test-Path -LiteralPath $resolvedPackage -PathType Leaf)) {
    throw "Pacote nao encontrado: $resolvedPackage"
}
if ([IO.Path]::GetExtension($resolvedPackage) -ine ".msix") {
    throw "O pacote precisa ter extensao .msix: $resolvedPackage"
}

if (-not $PfxPath) {
    $PfxPath = Join-Path $BuildRoot "psx-runtime_TemporaryKey.pfx"
}
$resolvedPfx = [IO.Path]::GetFullPath($PfxPath)
if (-not (Test-Path -LiteralPath $resolvedPfx -PathType Leaf)) {
    throw "Certificado PFX nao encontrado: $resolvedPfx"
}

if (-not $PfxPassword) {
    $PfxPassword = Read-Host "Senha da chave PFX" -AsSecureString
}

$plainPassword = ConvertTo-PlainText -SecureValue $PfxPassword
$certificate = $null
try {
    $flags = [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $resolvedPfx, $plainPassword, $flags)

    if (-not $certificate.HasPrivateKey) {
        throw "A PFX nao contem uma chave privada."
    }
    if ($certificate.NotBefore -gt (Get-Date)) {
        throw "O certificado ainda nao e valido. Inicio: $($certificate.NotBefore)"
    }
    if ($certificate.NotAfter -lt (Get-Date)) {
        throw "O certificado expirou em: $($certificate.NotAfter)"
    }

    $packagePublisher = Read-PackagePublisher -Path $resolvedPackage
    if (-not [string]::Equals($packagePublisher, $certificate.Subject,
                              [StringComparison]::OrdinalIgnoreCase)) {
        throw "Publisher do MSIX ('$packagePublisher') difere do Subject da PFX ('$($certificate.Subject)')."
    }

    if (-not $CertificateOutputPath) {
        $CertificateOutputPath = [IO.Path]::ChangeExtension($resolvedPackage, ".cer")
    }
    $resolvedCer = [IO.Path]::GetFullPath($CertificateOutputPath)
    $signTool = Resolve-SignTool

    Write-Host "Pacote:     $resolvedPackage" -ForegroundColor Cyan
    Write-Host "PFX:        $resolvedPfx" -ForegroundColor Cyan
    Write-Host "Publisher:  $packagePublisher" -ForegroundColor Cyan
    Write-Host "Thumbprint: $($certificate.Thumbprint)" -ForegroundColor Cyan
    Write-Host "Validade:   $($certificate.NotBefore) ate $($certificate.NotAfter)" -ForegroundColor Cyan
    Write-Host "SignTool:   $signTool" -ForegroundColor DarkGray

    if ($PSCmdlet.ShouldProcess($resolvedPackage, "Assinar pacote MSIX")) {
        $signArguments = @(
            "sign",
            "/fd", "SHA256",
            "/f", $resolvedPfx,
            "/p", $plainPassword
        )
        if ($TimestampUrl) {
            $signArguments += @("/tr", $TimestampUrl, "/td", "SHA256")
        }
        $signArguments += $resolvedPackage

        Write-Host "Assinando MSIX..." -ForegroundColor Cyan
        & $signTool @signArguments
        if ($LASTEXITCODE -ne 0) {
            throw "SignTool falhou ao assinar o pacote. Codigo: $LASTEXITCODE"
        }

        Write-Host "Verificando assinatura..." -ForegroundColor Cyan
        & $signTool verify /pa /v $resolvedPackage
        if ($LASTEXITCODE -ne 0) {
            throw "SignTool nao aprovou a assinatura. Codigo: $LASTEXITCODE"
        }

        $cerBytes = $certificate.Export(
            [Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        [IO.File]::WriteAllBytes($resolvedCer, $cerBytes)

        Write-Host ""
        Write-Host "Pacote assinado com sucesso." -ForegroundColor Green
        Write-Host "MSIX: $resolvedPackage"
        Write-Host "CER:  $resolvedCer"

        $dependency = Get-ChildItem -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($resolvedPackage)) "Dependencies\x64") `
            -Filter "Microsoft.VCLibs.x64.14.00.appx" -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($dependency) {
            Write-Host "Dependencia Xbox x64: $($dependency.FullName)"
        }
    }
}
finally {
    if ($certificate) {
        $certificate.Dispose()
    }
    $plainPassword = $null
}
