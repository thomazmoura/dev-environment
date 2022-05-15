Write-Information "Setting up Code folder"
New-Item -Force -ItemType Directory "$HOME/code"

Write-Information "Setting up Storage folder"
$Storage = "$HOME/.storage"
New-Item -Force -ItemType Directory $Storage

Write-Information "Setting up Ssh folder (on .storage)"
New-Item -Force -ItemType Directory -Path "$Storage/ssh"
New-Item -Force -ItemType SymbolicLink -Path "$HOME/.ssh" -Target "$Storage/ssh"

Write-Information "Setting up Powershell history folder (on .storage)"
New-Item -Force -ItemType Directory -Path "$Storage/powershell_history"
New-Item -Force -ItemType SymbolicLink -Path "$HOME/.local/share/powershell/PSReadLine" -Target "$Storage/powershell_history"

Write-Information "Setting up hosts folder (on .storage)"
New-Item -Force -ItemType Directory -Path "$Storage/hosts"
New-Item -Force -ItemType SymbolicLink -Path "$HOME/.hosts" -Target "$Storage/hosts"

Write-Information "Setting up Azure folder (on .storage)"
if( !(Test-Path "$Storage/azure") ) {
  New-Item -Force -ItemType Directory -Path "$Storage/azure"
  Copy-Item -Recurse -Force -Path "$HOME/.azure/*" -Destination "$Storage/azure"
}
New-Item -Force -ItemType SymbolicLink -Path "$HOME/.azure" -Target "$Storage/azure"

if($env:AZURE_DEVOPS_ORGANIZATION -and $env:AZURE_DEVOPS_PROJECT) {
  Write-Information "Azure DevOps configuration found. Setting up."
  az devops configure --defaults organization=$env:AZURE_DEVOPS_ORGANIZATION project=$env:AZURE_DEVOPS_PROJECT
} else {
  Write-Information "Azure DevOps configuration not found. Skipping."
}

New-Item -Force -ItemType Directory "$HOME/.storage/dev-cert/"
New-Item -Force -ItemType Directory "$HOME/.shared/"

if( !(Test-Path $env:ASPNETCORE_Kestrel__Certificates__Default__Path) ) {
  Write-Information "ASP .NET Core localhost certificate not found on $env:ASPNETCORE_Kestrel__Certificates__Default__Path. Creating now."
  & dotnet dev-certs https -ep $env:ASPNETCORE_Kestrel__Certificates__Default__Path -p $env:ASPNETCORE_Kestrel__Certificates__Default__Password
} 

if( !(Test-Path "$HOME/.shared/aspnet-localhost.pfx") ) {
  Write-Information "ASP .NET Core localhost certificate copy not found on $HOME/.shared/aspnet-localhost.pfx. Copying now."
  Copy-Item $env:ASPNETCORE_Kestrel__Certificates__Default__Path "$HOME/.shared/aspnet-localhost.pfx"
}
