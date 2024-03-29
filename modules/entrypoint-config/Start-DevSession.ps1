function Create-DefaultFolders() {

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

  Write-Information "Setting up .NET tools folder (on .storage)"
  if((Test-Path "$HOME/.dotnet/tools") -and ! (Get-Item -Path "$HOME/.dotnet/tools").Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
    Remove-Item -Recurse -Force "$HOME/.dotnet/tools"
  }
  if( ! (Test-Path "$Storage/dotnet-tools")) {
    New-Item -Force -Type Directory -Path "$Storage/dotnet-tools"
  }
  New-Item -Force -ItemType SymbolicLink -Path "$HOME/.dotnet/tools" -Target "$Storage/dotnet-tools"

  Write-Information "Setting up Azure folder (on .storage)"
  if( !(Test-Path "$Storage/azure") ) {
    New-Item -Force -ItemType Directory -Path "$Storage/azure"
    Copy-Item -Recurse -Force -Path "$HOME/.azure/*" -Destination "$Storage/azure"
  }
  New-Item -Force -ItemType SymbolicLink -Path "$HOME/.azure" -Target "$Storage/azure"

  New-Item -Force -ItemType Directory "$HOME/.storage/dev-cert/"
  New-Item -Force -ItemType Directory "$HOME/.storage/vscode-server/"
  New-Item -Force -ItemType Directory "$HOME/.shared/"
  New-Item -Force -ItemType Directory "$HOME/code/code-scripts/"

}

function Setup-AzureDevOpsCLI {

  if($env:AZURE_DEVOPS_ORGANIZATION -and $env:AZURE_DEVOPS_PROJECT) {
    Write-Information "Azure DevOps configuration found. Setting up."
    az devops configure --defaults organization=$env:AZURE_DEVOPS_ORGANIZATION project=$env:AZURE_DEVOPS_PROJECT
  } else {
    Write-Information "Azure DevOps configuration not found. Skipping."
  }

}

function Setup-DotNetCertificate {

  if( !(Test-Path $env:ASPNETCORE_Kestrel__Certificates__Default__Path) ) {
    Write-Information "ASP .NET Core localhost certificate not found on $env:ASPNETCORE_Kestrel__Certificates__Default__Path. Creating now."
    & dotnet dev-certs https -ep $env:ASPNETCORE_Kestrel__Certificates__Default__Path -p $env:ASPNETCORE_Kestrel__Certificates__Default__Password
  } 

  if( !(Test-Path "$HOME/.shared/aspnet-localhost.pfx") ) {
    Write-Information "ASP .NET Core localhost certificate copy not found on $HOME/.shared/aspnet-localhost.pfx. Copying now."
    Copy-Item $env:ASPNETCORE_Kestrel__Certificates__Default__Path "$HOME/.shared/aspnet-localhost.pfx"
  }

}

function Setup-VSCodeServer() {
  $VSCodeServerFolder = "$HOME/.vscode-server"
  $VSCodeServerStorageFolder = "$HOME/.storage/vscode-server"
  if( Test-Path $VSCodeServerFolder ) {
    Write-Information "`n->> Moving $VSCodeServerFolder contents to $VSCodeServerStorageFolder"
    Move-Item -Force "$VSCodeServerFolder/*" $VSCodeServerStorageFolder
    Write-Information "`n->> Erasing $VSCodeServerFolder"
    Remove-Item -Recurse -Force $VSCodeServerFolder
  }

  Write-Information "`n->> Creating SymbolicLink on $VSCodeServerFolder pointing to $VSCodeServerStorageFolder"
  New-Item -ItemType SymbolicLink -Path $VSCodeServerFolder -Target $VSCodeServerStorageFolder
}

function Setup-DotFiles {

  $DotFilesFolder = "$HOME/code/dotfiles"
  if( !(Test-Path $DotFilesFolder) ) {
    Write-Information "Creating dotfiles folder"
    New-Item -Type Directory -Path $DotFilesFolder
  }

  $NeoVimLocalFolder = "$DotFilesFolder/neovim-local"
  if( !(Test-Path $NeoVimLocalFolder) ) {
    Write-Information "Creating NeoVim Local Folder SymbolicLink"
    New-Item -Type SymbolicLink -Path $NeoVimLocalFolder -Target "$HOME/.local/share/nvim/site"
  }

  $NeoVimConfigFolder = "$DotFilesFolder/neovim-config"
  if( !(Test-Path $NeoVimConfigFolder) ) {
    Write-Information "Creating NeoVim Local Folder SymbolicLink"
    New-Item -Type SymbolicLink -Path $NeoVimConfigFolder -Target "$HOME/.config/nvim"
  }

  $PowerShellConfigFolder = "$DotFilesFolder/powershell-config"
  if( !(Test-Path $PowerShellConfigFolder) ) {
    Write-Information "Creating NeoVim Local Folder SymbolicLink"
    New-Item -Type SymbolicLink -Path $PowerShellConfigFolder -Target "$HOME/.config/powershell"
  }

  $ModulesFolder = "$DotFilesFolder/modules"
  if( !(Test-Path $ModulesFolder) ) {
    Write-Information "Creating NeoVim Local Folder SymbolicLink"
    New-Item -Type SymbolicLink -Path $ModulesFolder -Target "$HOME/.modules"
  }

  $UserConfigsFolder = "$DotFilesFolder/user-configs"
  if( !(Test-Path $UserConfigsFolder) ) {
    Write-Information "Creating User Configs Local Folder SymbolicLink"
    New-Item -Type Directory -Path $UserConfigsFolder
    New-Item -Type HardLink -Path /home/developer/code/dotfiles/user-configs/omnisharp.json -Target /home/developer/omnisharp.json
  }

}

function Setup-Copilot {
  if( !(Get-Command nvs) ) {
    Write-Warning "Aborting Copilot setup because nvs is not available"
    return
  }

  if( !(Test-Path "$HOME/.nvs/node/16.*") ) {
    Write-Information "Installing Node 16"
    nvs add 16
  }

  $PathToCopilotsNode = "$HOME/.nvs/copilot-node"
  if( !(Test-Path $PathToCopilotsNode) ) {
    Write-Information "Creating copilot's node symbolic link"
    $Node16Folder = Get-Item "$HOME/.nvs/node/16.*"
      | Sort-Object Name -Descending
      | Select-Object -First 1
    $Node16Exe = "$Node16Folder/x64/bin/node"
    New-Item -Type SymbolicLink -Path $PathToCopilotsNode -Target $Node16Exe
  }
}

function Setup-DotNetTools {
  if( Test-Path "$HOME/.modules/dotnet-tools/dotnettools-setup.ps1" ) {
    . $HOME/.modules/dotnet-tools/dotnettools-setup.ps1
  }
}

Create-DefaultFolders
Setup-AzureDevOpsCLI
Setup-DotNetCertificate
Setup-DotFiles
Setup-VSCodeServer
Setup-Copilot
Setup-DotNetTools

