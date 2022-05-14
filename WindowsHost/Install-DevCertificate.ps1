param(
  [String] $PathToSharedCertificate = "$HOME/.shared/aspnet-localhost.pfx",
  [Parameter(Mandatory=$true)]
  [String] $Password
)

if( !(Test-Path $PathToSharedCertificate) ) {
  Write-Warning "No certificate was found on $PathToSharedCertificate. Cancelling"
  return;
}

Write-Information "Importing the certificate"
& dotnet dev-certs https --clean --import $PathToSharedCertificate -p $Password

Write-Information "Trusting the certificate"
& dotnet dev-certs https --trust

Write-Information "Saving the default path and password for the certificate"
[System.Environment]::SetEnvironmentVariable("ASPNETCORE_Kestrel__Certificates__Default__Path", $PathToSharedCertificate, "User")
[System.Environment]::SetEnvironmentVariable("ASPNETCORE_Kestrel__Certificates__Default__Password", $Password, "User")

