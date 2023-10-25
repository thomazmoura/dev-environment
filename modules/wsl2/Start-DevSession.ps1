function Create-DefaultFolders() {
  Write-Information "Setting up Code folder"
  New-Item -Force -ItemType Directory "$HOME/code"
  New-Item -Force -ItemType Directory "$HOME/.shared/"
  New-Item -Force -ItemType Directory "$HOME/code/code-scripts/"

}

function Setup-AzureDevOpsCLI {
  if($env:AZURE_DEVOPS_ORGANIZATION -and $env:AZURE_DEVOPS_PROJECT) {
    Write-Information "Azure DevOps configuration found. Setting up."
    az devops configure --defaults organization=$env:AZURE_DEVOPS_ORGANIZATION
    az devops configure --defaults project=$env:AZURE_DEVOPS_PROJECT
  } else {
    Write-Information "Azure DevOps configuration not found. Skipping."
  }
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

  $OmnisharpFolder = "$DotFilesFolder/omnisharp"
  if( !(Test-Path $OmnisharpFolder) ) {
    Write-Information "Creating Omnisharp Local Folder SymbolicLink"
    New-Item -Type SymbolicLink -Path $OmnisharpFolder -Target "$HOME/.omnisharp"
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
Setup-DotFiles
Setup-Copilot
Setup-DotNetTools

