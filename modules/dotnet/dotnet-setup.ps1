Write-Output ">>> Installing Microsoft apt repository"
New-Item -ItemType Directory -Force ~/Downloads
Set-Location ~/Downloads
Invoke-WebRequest https://packages.microsoft.com/config/debian/11/packages-microsoft-prod.deb -OutFile packages-microsoft-prod.deb
& dpkg -i packages-microsoft-prod.deb
Remove-Item packages-microsoft-prod.deb
Set-Location -

Write-Output ">>> Installing .NET Core SDK"
& apt-get update
& apt-get install -y dotnet-sdk-2.1 dotnet-sdk-3.1 dotnet-sdk-5.0 dotnet-sdk-6.0

