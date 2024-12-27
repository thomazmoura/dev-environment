param(
    [Parameter(Mandatory=$true)]
    [string]$windowsUser,
    [Parameter(Mandatory=$true)]
    [string]$pass
)

if( (Test-Path ./localhost.crt) ) {
  Write-Information "`n->> Remove the crt"
  rm ./localhost.crt
}

if( (Test-Path ./localhost.key) ) {
  Write-Information "`n->> Remove the key"
  rm ./localhost.key
}

Write-Information "`n->> Create the public/private key"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ./localhost.key -out ./localhost.crt -config ./localhost.conf

Write-Information "`n->> Trust the certificate"
cp ./localhost.crt /usr/local/share/ca-certificates || sudo cp ./localhost.crt /usr/local/share/ca-certificates 
update-ca-certificates || sudo update-ca-certificates

Write-Information "`n->> Export the certificate as PFX to import it on Windows"
openssl pkcs12 -export -out ./localhost.pfx -inkey ./localhost.key -in ./localhost.crt

Write-Information "`n->> Move the certificate to Windows"
mkdir -p /mnt/c/Users/$windowsUser/.aspnet/.ssl
mv -f ./localhost.pfx /mnt/c/Users/$windowsUser/.aspnet/.ssl

Write-Information "`n->> Clean the files"
rm *.crt
rm *.key

Write-Information "`n->> Configuring Kestrel to use the certificate"
"`$env:ASPNETCORE_Kestrel__Certificates__Default__Password='$pass'" >> $HOME/.profile.ps1
"`$env:ASPNETCORE_Kestrel__Certificates__Default__Path='/mnt/c/Users/$windowsUser/.aspnet/.ssl/localhost.pfx'" >> $HOME/.profile.ps1

