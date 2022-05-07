Write-Information "Setting up Code folder"
New-Item -Force -ItemType Directory $HOME/code

Write-Information "Setting up Storage folder"
$Storage = $HOME/.storage
New-Item -Force -ItemType Directory $Storage

Write-Information "Setting up Ssh folder (on .storage)"
New-Item -Force -ItemType Directory -Path $Storage/ssh
New-Item -Force -ItemType SymbolicLink -Path $HOME/.ssh -Target $Storage/ssh

Write-Information "Setting up Powershell history folder (on .storage)"
New-Item -Force -ItemType Directory -Path $Storage/powershell_history
New-Item -Force -ItemType SymbolicLink -Path $HOME/.local/share/powershell/PSReadLine -Target $Storage/powershell_history

Write-Information "Setting up Azure folder (on .storage)"
if( !(Test-Path $Storage/azure) ) {
  New-Item -Force -ItemType Directory -Path $Storage/azure
  Copy-Item -Recurse -Force -Path $HOME/.azure/* -Destination $Storage/azure
}
New-Item -Force -ItemType SymbolicLink -Path $HOME/.azure -Target $Storage/azure

