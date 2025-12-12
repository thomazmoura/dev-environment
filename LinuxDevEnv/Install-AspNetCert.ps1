#!/usr/bin/env pwsh
param(
    [string]$CertPath = "$env:HOME/.shared/aspnet-localhost.pfx"
)

$ErrorActionPreference = "Stop"

$certName = "ASP.NET Core HTTPS development certificate"
$nssDb = "sql:$env:HOME/.pki/nssdb"
$tempCert = "/tmp/aspnet-localhost-$PID.crt"

# Validate certificate file exists
if (-not (Test-Path $CertPath)) {
    Write-Error "Certificate file not found: $CertPath"
    exit 1
}

Write-Host "Installing certificate from: $CertPath" -ForegroundColor Cyan

# Check if certificate already exists and remove it
$existingCert = certutil -d $nssDb -L 2>&1 | Select-String -Pattern $certName
if ($existingCert) {
    Write-Host "Removing existing certificate..." -ForegroundColor Yellow
    certutil -d $nssDb -D -n $certName
}

# Extract certificate from PFX (will prompt for password)
Write-Host "Extracting certificate from PFX (enter password when prompted)..." -ForegroundColor Cyan
openssl pkcs12 -in $CertPath -clcerts -nokeys -out $tempCert
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to extract certificate from PFX"
    exit 1
}

# Import into Chrome's NSS database
Write-Host "Importing certificate into Chrome's NSS database..." -ForegroundColor Cyan
certutil -d $nssDb -A -t "CT,C,C" -n $certName -i $tempCert
if ($LASTEXITCODE -ne 0) {
    Remove-Item -Path $tempCert -Force -ErrorAction SilentlyContinue
    Write-Error "Failed to import certificate into NSS database"
    exit 1
}

# Cleanup
Remove-Item -Path $tempCert -Force -ErrorAction SilentlyContinue

# Verify installation
Write-Host "`nVerifying installation..." -ForegroundColor Cyan
certutil -d $nssDb -L | Select-String -Pattern $certName

Write-Host "`nCertificate installed successfully!" -ForegroundColor Green
Write-Host "Please restart Chrome for the changes to take effect." -ForegroundColor Yellow
