. "$PSScriptRoot/kernel-profile.ps1"

function Import-PoshGit() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  Write-Verbose "`n->> Importing posh-git"
  Import-Module posh-git
  if ( !($?) ) {
    Write-Information "`n->> Posh-git not found. Installing"
    Install-Module posh-git
  }
	if($env:WSL_DISTRO_NAME) {
		$Label = $env:WSL_DISTRO_NAME
	} else {
		$Label = ' 🐳 '
	}
  $GitPromptSettings.DefaultPromptPrefix = '$('''+ "(🐧$Label🐧) " + '>>='') '
	$GitPromptSettings.DefaultPromptSuffix = '$('' ==>'' * ($nestedPromptLevel + 1))`n>=> '
	$GitPromptSettings.DefaultPromptAbbreviateHomeDirectory = $true
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do Posh-git demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-PsNvm() {
  Write-Verbose "`n->> Importing NVM"
  Import-Module nvm
  if ( !($?) ) {
    Write-Information "`n->> NVM module not found. Installing"
    Install-Module nvm
    Import-Module nvm
		Set-NodeVersion 16
  }
}

Write-Verbose "`n->> Setting .NET variables"
$env:ASPNETCORE_ENVIRONMENT="Development"
$env:DOTNET_ENVIRONMENT="Development"

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()
Write-Verbose "`n->> Checking if ssh key is set"
if(Test-Path ~/.ssh) {
	Add-SshKey
}
$stopwatch.Stop(); Write-Verbose "`n-->> Acréscimo de SSH demorou: $($stopwatch.ElapsedMilliseconds)"

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()
if(!$env:ConnectionStrings__Log) {
	Set-LocalContextDatabase -DatabaseName "Log" -ContextName "Log"
}
$stopwatch.Stop(); Write-Verbose "`n-->> Definição de base padrões demorou: $($stopwatch.ElapsedMilliseconds)"

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()
function New-HorizontalTmuxSession ($FirstPaneCommand="psgit", $SecondPaneCommand="") {
  $location = FuzzySearch-Location
	if($location) {
		Set-Location $location
		$currentDirectory = ($pwd.Path.Split("/") | Select -Last 1)
		& tmux new-session `; `
			rename-session $currentDirectory `; `
			split-window -h -p 20 `; `
			select-pane -t 1 `; `
			send-keys "$SecondPaneCommand" C-m `; `
			split-window -v -p 50 `; `
			select-pane -t 2 `; `
			send-keys "$FirstPaneCommand" C-m `; `
			select-pane -t 1 `; `
			select-pane -t 0 `; `
			send-keys nvim C-m
	}
	Write-Information "Cancelled by user"
}

function New-HorizontalDoubleTmuxSession  ($FirstFolder="*angular",$FirstCommand="npm start",$SecondFolder="*api",$SecondCommand="dotnet watch run") {
  $location = FuzzySearch-Location
	if($location) {
		Set-Location $location
		$currentDirectory = ($pwd.Path.Split("/") | Select -Last 1)
		tmux new-session `; `
			rename-session $currentDirectory `; `
			split-window -h -p 20 `; `
			select-pane -t 1 `; `
			send-keys "cd $FirstFolder" C-m `; `
			send-keys "$FirstCommand" C-m `; `
			select-pane -t 0 `; `
			send-keys "cd $FirstFolder" C-m `; `
			send-keys nvim C-m `; `
			new-window `; `
			split-window -h -p 20 `; `
			select-pane -t 1 `; `
			send-keys "cd $SecondFolder" C-m `; `
			send-keys "$SecondCommand" C-m `; `
			select-pane -t 0 `; `
			send-keys "cd $SecondFolder" C-m `; `
			send-keys nvim C-m `; `
			new-window `; `
			send-keys "htop" C-m `; `
			select-window -t 0
	}
	Write-Information "Cancelled by user"
}

function New-VerticalTmuxSession  ($Command = 'nvim', $SecondCommand = 'psgit') {
  $location = FuzzySearch-Location
	if($location) {
		Set-Location $location
		$currentDirectory = ($pwd.Path.Split("/") | Select -Last 1)
		tmux new-session `; `
			rename-session $currentDirectory `; `
			split-window -v -p 20 `; `
			select-pane -t 0 `; `
			send-keys "$Command" C-m `; `
			select-pane -t 1 `; `
			send-keys "$SecondCommand" C-m `; `
			select-pane -t 0 `; `
	}
	Write-Information "Cancelled by user"
}

function Enable-Bash ($enable = $true) {
	if($enable) {
		$env:SKIP_PWSH=$true
	} else {
		$env:SKIP_PWSH=$null
	}
}

function New-SudoVimSession ($File=".") {
  $NeoVimLocation = (Get-Command nvim).Source
	sudo $NeoVimLocation "$File"
}

function Get-ChildItemsSize() {
	du -hs * | sort -hr | less
}

function Get-TmuxSession ($Session=$null) {
	if($Session) {
		tmux attach-session -t $Session
	} else {
		$tmuxListSessionsResult = tmux list-sessions;
		if($tmuxListSessionsResult -is [array]) {
			$tmuxSessions = (
					($tmuxListSessionsResult |
					 Select-Object @{l="Session";e={$_.Split(':')[0]}}
					).Session
					)
				$favoredSessions = "dev-environment"
				$availableFavoredSession = $null
				foreach($favoredSession in $favoredSessions) {
					if($tmuxSessions -eq $favoredSession) {
						$availableFavoredSession = $favoredSession
					}
				}
			if($availableFavoredSession){
				tmux attach-session -t $availableFavoredSession
			} else {
				tmux attach-session -t $tmuxSessions[0].Split(':')[0]
			}
		} else {
			if($tmuxListSessionsResult) {
				tmux attach-session -t $tmuxListSessionsResult.Split(':')[0]
			}
		}
	}
}
$stopwatch.Stop(); Write-Verbose "`n-->> Definições de funcions do Linux demorou:: $($stopwatch.ElapsedMilliseconds)"

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()
if((Get-Content /etc/issue) -match 'ubuntu') { 
	New-Alias -Force bat batcat
	New-Alias -Force fd fdfind
}
$stopwatch.Stop(); Write-Verbose "`n-->> Definição de alias demorou: $($stopwatch.ElapsedMilliseconds)"

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()
New-Alias -Force htmux New-HorizontalTmuxSession
New-Alias -Force dhtmux New-HorizontalDoubleTmuxSession
New-Alias -Force vtmux New-VerticalTmuxSession
New-Alias -Force tmuxa Get-TmuxSession
New-Alias -Force duhs Get-ChildItemsSize

New-Alias -Force svim New-SudoVimSession
$stopwatch.Stop(); Write-Verbose "`n-->> Definição de aliases de linux demorou: $($stopwatch.ElapsedMilliseconds)"

