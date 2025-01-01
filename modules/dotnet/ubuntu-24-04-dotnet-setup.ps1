. "$HOME/.modules/powershell/Check-Failure.ps1"

Write-Output ">>> Installing Microsoft apt repository"
New-Item -ItemType Directory -Force ~/Downloads
Set-Location ~/Downloads
Invoke-WebRequest "https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb" -OutFile packages-microsoft-prod.deb
& dpkg -i packages-microsoft-prod.deb
Remove-Item packages-microsoft-prod.deb
Set-Location -

Write-Output ">>> Installing .NET Core SDK"
& sudo apt-get update
& sudo apt-get install -y dotnet-sdk-6.0 dotnet-sdk-8.0 

Throw-ExceptionOnNativeFailure

