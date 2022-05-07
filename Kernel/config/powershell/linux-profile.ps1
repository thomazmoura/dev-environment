. "$PSScriptRoot/kernel-profile.ps1"

Write-Verbose "`n->> Setting environment variables"
$env:ASPNETCORE_ENVIRONMENT="Development"
$env:DOTNET_ENVIRONMENT="Development"
$env:NVS_HOME="$env:HOME/.nvs"
$env:PATH="$($env:PATH):$HOME/.local/bin"

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()
Write-Verbose "`n->> Checking if ssh key is set"
$SshKeyFolder = "$HOME/.storage/ssh"
if(Test-Path $SshKeyFolder) {
	Add-SshKey -SshKeyFolder $SshKeyFolder -Comment "developer@docker@$env:HOSTNAME"
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

function New-VerticalTmuxSession  ($Command = 'nvim', $SecondCommand = 'psomp && psgit') {
  $location = FuzzySearch-Location
	if($location) {
		Set-Location $location
		$currentDirectory = ($pwd.Path.Split("/") | Select-Object -Last 1).Replace(".", "_")
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

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()
if((cat /etc/issue) -match 'ubuntu') { 
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
New-Alias -Force nvs "$env:NVS_HOME/nvs.ps1"
New-Alias -Force svim New-SudoVimSession

$stopwatch.Stop(); Write-Verbose "`n-->> Definição de aliases de linux demorou: $($stopwatch.ElapsedMilliseconds)"

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()
if(Get-Command nvs -ErrorAction SilentlyContinue) {
  nvs auto on
	nvs use lts
}
$stopwatch.Stop(); Write-Verbose "`n-->> Ativação do NVS demorou: $($stopwatch.ElapsedMilliseconds)"

Import-OhMyPoshOnLinux

