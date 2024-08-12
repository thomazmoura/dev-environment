. "$HOME/.modules/powershell/Check-Failure.ps1"

Write-Output ">>> Installing Microsoft apt repository"
New-Item -ItemType Directory -Force ~/Downloads
Set-Location ~/Downloads
Invoke-WebRequest https://packages.microsoft.com/config/debian/11/packages-microsoft-prod.deb -OutFile packages-microsoft-prod.deb
if(Get-Command sudo -ErrorAction SilentlyContinue) {
  & sudo dpkg -i packages-microsoft-prod.deb
} else {
  & dpkg -i packages-microsoft-prod.deb
}
Remove-Item packages-microsoft-prod.deb
Set-Location -

Write-Output ">>> Installing .NET Core SDK"
if(Get-Command sudo -ErrorAction SilentlyContinue) {
  & sudo apt-get update
  & sudo apt-get install -y dotnet-sdk-6.0 dotnet-sdk-8.0
} else {
  & apt-get update
  & apt-get install -y dotnet-sdk-6.0 dotnet-sdk-8.0
}

$AspNetSdkDirectories = Get-Item "/usr/lib/dotnet/shared/Microsoft.AspNetCore.App/"
if($AspNetSdkDirectories) {
  foreach ($AspNetSdkDirectory in $AspNetSdkDirectories) {
    $Directory = $AspNetSdkDirectory.Name
    $DestinationDirectory = "/usr/lib/dotnet/shared/Microsoft.AspNetCore.App/$Directory"
    if (!(Test-Path $DestinationDirectory)) {
      
      if(Get-Command sudo -ErrorAction SilentlyContinue) {
        & sudo pwsh -C "New-Item -ItemType SymbolicLink -Path $DestinationDirectory -Target $AspNetSdkDirectory.FullName"
      } else {
        & New-Item -ItemType SymbolicLink -Path $DestinationDirectory -Target $AspNetSdkDirectory.FullName
      }
    }
  }
}
$DotnetSdkDirectories = Get-Item "/usr/lib/dotnet/shared/Microsoft.NETCore.App"
if($DotnetSdkDirectories) {
  foreach ($DotnetSdkDirectory in $DotnetSdkDirectories) {
    $Directory = $DotnetSdkDirectory.Name
    $DestinationDirectory = "/usr/lib/dotnet/shared/Microsoft.NETCore.App/$Directory"
    if (!(Test-Path $DestinationDirectory)) {
      if(Get-Command sudo -ErrorAction SilentlyContinue) {
        & sudo pwsh -C "New-Item -ItemType SymbolicLink -Path $DestinationDirectory -Target $DotnetSdkDirectory.FullName"
      } else {
        New-Item -ItemType SymbolicLink -Path $DestinationDirectory -Target $DotnetSdkDirectory.FullName
      }
    }
  }
}

Throw-ExceptionOnNativeFailure

