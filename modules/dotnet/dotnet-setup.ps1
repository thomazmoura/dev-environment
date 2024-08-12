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

$AspNetSdkDirectories = @(Get-ChildItem "/usr/lib/dotnet/shared/Microsoft.AspNetCore.App/")
if($AspNetSdkDirectories) {
  foreach ($AspNetSdkDirectory in $AspNetSdkDirectories) {
    $Directory = $AspNetSdkDirectory.Name
    $DestinationDirectory = "/usr/share/dotnet/shared/Microsoft.AspNetCore.App/$Directory"
    if (!(Test-Path $DestinationDirectory)) {
      if(Get-Command sudo -ErrorAction SilentlyContinue) {
        Write-Verbose "Making asp .net core symbolic link"
        & sudo pwsh -C "New-Item -ItemType SymbolicLink -Path $DestinationDirectory -Target $AspNetSdkDirectory"
      } else {
        Write-Verbose "Making asp .net core symbolic link"
        & New-Item -ItemType SymbolicLink -Path $DestinationDirectory -Target $AspNetSdkDirectory
      }
    } else {
      Write-Verbose "Destination $Directory already exists"
    }
  }
} else {
  Write-Verbose "No Asp .NET Core directory found"
}

$DotnetSdkDirectories = @(Get-ChildItem "/usr/lib/dotnet/shared/Microsoft.NETCore.App")
if($DotnetSdkDirectories) {
  foreach ($DotnetSdkDirectory in $DotnetSdkDirectories) {
    $Directory = $DotnetSdkDirectory.Name
    $DestinationDirectory = "/usr/share/dotnet/shared/Microsoft.NETCore.App/$Directory"
    if (!(Test-Path $DestinationDirectory)) {
      if(Get-Command sudo -ErrorAction SilentlyContinue) {
        Write-Verbose "Making .net core symbolic link"
        & sudo pwsh -C "New-Item -ItemType SymbolicLink -Path $DestinationDirectory -Target $DotnetSdkDirectory"
      } else {
        Write-Verbose "Making asp .net core symbolic link"
        New-Item -ItemType SymbolicLink -Path $DestinationDirectory -Target $DotnetSdkDirectory
      }
    } else {
      Write-Verbose "Destination $Directory already exists"
    }
  }
} else {
  Write-Verbose "No .NET Core directory found"
}

Throw-ExceptionOnNativeFailure

