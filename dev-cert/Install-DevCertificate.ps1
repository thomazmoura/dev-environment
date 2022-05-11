if( !($env:CERT_PASSWORD) ) {
  Write-Warning "`n->> No credential information passed. Skipping dev-certificate creation"
  return;
}

Write-Information "`n->> Create the public/private key"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ./localhost.key -out ./localhost.crt -config ./localhost.conf

Write-Information "`n->> Trust the certificate"
Copy-Item -Force ./localhost.crt /usr/local/share/ca-certificates
& update-ca-certificates

Write-Information "`n->> Export the certificate as PFX to share it on .dev-cert"
& openssl pkcs12 -export -out ./localhost.pfx -inkey ./localhost.key -in ./localhost.crt

Write-Information "`n->> Move the certificate to .dev-cert"
New-Item -Force "$HOME/.dev-cert"
Move-Item -Force -Path ./localhost.pfx -Destination "$HOME/.dev-cert/localhost.pfx"

Write-Information "`n->> Clean the files"
Remove-Item *.crt
Remove-Item *.key

Write-Information "`n->> Configuring Kestrel to use the certificate"
"`$env:ASPNETCORE_Kestrel__Certificates__Default__Password='$CERT_PASSWORD'" >> "$HOME/.storage/powershell/profile.ps1"
"`$env:ASPNETCORE_Kestrel__Certificates__Default__Path='$HOME/.dev-cert/localhost.pfx'" >> "$HOME/.storage/powershell/profile.ps1"


