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

  $SpotlightDimmerFolder = "$DotFilesFolder/spotlight-dimmer"
  if( !(Test-Path $SpotlightDimmerFolder) ) {
    Write-Information "Creating SpotlightDimmer Folder SymbolicLink"
    New-Item -Type SymbolicLink -Path $SpotlightDimmerFolder -Target "$HOME/.config/SpotlightDimmer"
  }

  # The AI agents keep their settings next to credentials, caches, logs and
  # session history, so linking their whole folder would bury the settings in
  # the <Leader>, picker. Each agent gets a folder of its own instead, holding
  # links to just the files you would edit. The instruction files are created
  # empty when missing -- that changes nothing for the agent -- because fd
  # skips a link whose target does not exist, and they are the files you most
  # want to find; the rest only show up once the agent or you create them.
  $AgentFiles = [ordered]@{
    "claude" = @(
      "$HOME/.claude/CLAUDE.md"
      "$HOME/.claude/settings.json"
      "$HOME/.claude/keybindings.json"
      "$HOME/.claude/agents"
      "$HOME/.claude/commands"
      "$HOME/.claude/skills"
    )
    "copilot" = @(
      "$HOME/.copilot/copilot-instructions.md"
      "$HOME/.copilot/config.json"
      "$HOME/.copilot/mcp-config.json"
      "$HOME/.copilot/agents"
    )
    "codex" = @(
      "$HOME/.codex/AGENTS.md"
      "$HOME/.codex/config.toml"
      "$HOME/.codex/rules"
    )
  }
  foreach( $Agent in $AgentFiles.Keys ) {
    $AgentFolder = "$DotFilesFolder/ai-$Agent"
    if( !(Test-Path $AgentFolder) ) {
      Write-Information "Creating $Agent dotfiles folder"
      New-Item -Type Directory -Path $AgentFolder | Out-Null
    }

    foreach( $Target in $AgentFiles[$Agent] ) {
      if( $Target.EndsWith(".md") -and !(Test-Path $Target) ) {
        New-Item -Force -Type File -Path $Target | Out-Null
      }

      $Link = "$AgentFolder/$(Split-Path -Leaf $Target)"
      if( !(Get-Item -Force -ErrorAction SilentlyContinue $Link) ) {
        Write-Information "Creating $Agent $(Split-Path -Leaf $Target) SymbolicLink"
        New-Item -Type SymbolicLink -Path $Link -Target $Target | Out-Null
      }
    }
  }

}

function Setup-Copilot {
  if( !(Get-Command nvs) ) {
    Write-Warning "Aborting Copilot setup because nvs is not available"
    return
  }

  if( !(Test-Path "$HOME/.nvs/node/18.*") ) {
    Write-Information "Installing Node 18"
    nvs add 18
  }

  $PathToCopilotsNode = "$HOME/.nvs/copilot-node"
  if( !(Test-Path $PathToCopilotsNode) ) {
    Write-Information "Creating copilot's node symbolic link"
    $Node18Folder = Get-Item "$HOME/.nvs/node/18.*"
      | Sort-Object Name -Descending
      | Select-Object -First 1
    $Node18Exe = "$Node18Folder/x64/bin/node"
    New-Item -Type SymbolicLink -Path $PathToCopilotsNode -Target $Node18Exe
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

