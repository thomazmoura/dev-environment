. "$HOME/.modules/powershell/Check-Failure.ps1"

Write-Output ">>> Installing Microsoft apt repository"
# The packages-microsoft-prod helper deb ships the old Microsoft key, whose SHA1 binding
# trixie's apt (sqv) rejects since 2026-02-01. The trixie repo is also signed with the 2025 key.
$KeyPath = "/usr/share/keyrings/microsoft-2025.asc"
$SourcePath = "/etc/apt/sources.list.d/microsoft-prod.list"
$Source = "deb [arch=amd64,arm64,armhf signed-by=$KeyPath] https://packages.microsoft.com/debian/13/prod trixie main"
$TempKey = "/tmp/microsoft-2025.asc"
$TempSource = "/tmp/microsoft-prod.list"
Invoke-WebRequest https://packages.microsoft.com/keys/microsoft-2025.asc -OutFile $TempKey
Set-Content -Path $TempSource -Value $Source
foreach ($Pair in @(@($TempKey, $KeyPath), @($TempSource, $SourcePath))) {
  $From, $To = $Pair
  if( !(Test-Path $To) -or (Get-FileHash $From).Hash -ne (Get-FileHash $To).Hash ) {
    if(Get-Command sudo -ErrorAction SilentlyContinue) {
      & sudo cp $From $To
    } else {
      Copy-Item $From $To
    }
  }
  Remove-Item $From
}

Write-Output ">>> Installing .NET Core SDK"
if(Get-Command sudo -ErrorAction SilentlyContinue) {
  & sudo apt-get update
  & sudo apt-get install -y dotnet-sdk-8.0
} else {
  & apt-get update
  & apt-get install -y dotnet-sdk-8.0
}

$AspNetSdkDirectories = @(Get-ChildItem "/usr/lib/dotnet/shared/Microsoft.AspNetCore.App/" -ErrorAction SilentlyContinue)
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

$DotnetSdkDirectories = @(Get-ChildItem "/usr/lib/dotnet/shared/Microsoft.NETCore.App" -ErrorAction SilentlyContinue)
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

