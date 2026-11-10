. "$PSScriptRoot/kernel-profile.ps1"

$env:ASPNETCORE_ENVIRONMENT="Development"
$env:DOTNET_ENVIRONMENT="Development"
$env:NVS_HOME="$env:HOME/.nvs"
$env:PATH="$($env:PATH):$HOME/.local/bin:$HOME/.dotnet/tools/"

# Over ssh there is no Wayland display: wl-copy -- and the clip alias built on
# it in kernel-profile.ps1 -- goes through OSC 52 to the clipboard of the
# machine you are ssh'ing from instead (see modules/clipboard/wl-copy). In front
# of PATH, since the host's own /usr/bin/wl-copy would win otherwise.
if ($env:SSH_CONNECTION -and -not $env:WAYLAND_DISPLAY -and [IO.Directory]::Exists("$HOME/.modules/clipboard")) {
  $env:PATH = "$HOME/.modules/clipboard:$($env:PATH)"
}

# MSBuild reads any property a project does not define itself from the
# environment, so these disable analyzer execution for local builds without
# touching a single .csproj. Analyzers are the largest slice of Csc time on a
# `dotnet watch` rebuild and are redundant here twice over: the Roslyn LSP
# reports the same diagnostics live while typing, and CI builds without these
# variables set, so the full analyzer pass still gates merges.
$env:RunAnalyzers="false"
$env:RunAnalyzersDuringBuild="false"

if(!$env:ConnectionStrings__Log) {
	Set-LocalContextDatabase -DatabaseName "Log" -ContextName "Log"
}

# Every shell on this machine uses its one shared ssh-agent, at a fixed socket
# in ~/.ssh/tmux-agent (modules/tmux/scripts/Unlock-SshAgent.sh), so a key is
# typed once per machine. That agent wins over one handed down in the
# environment. A handed-down agent is whichever one the last client to attach
# to tmux brought along, or none, and a key added to it reaches no other pane.
# While the shared agent's socket and process are there it is taken as is,
# without asking it for its keys: that ssh-add -L cost ~40ms, plus Add-SshKey's
# own ~50ms, on every shell start. A key that has left the agent since is added
# back by ssh itself on first use (AddKeysToAgent, set up by
# LinuxDevEnv/host-setup.sh). Add-SshKey -- autoloaded from DevHelpers -- runs
# only when the agent is not running: it starts it and asks for the key.
$SshKeyFolder = "$HOME/.ssh"
$sshAgentDir = "$SshKeyFolder/tmux-agent"
$sshAgentPid = if ([IO.File]::Exists("$sshAgentDir/agent.sock") -and [IO.File]::Exists("$sshAgentDir/agent.pid")) {
  [IO.File]::ReadAllText("$sshAgentDir/agent.pid").Trim()
}
if ($sshAgentPid -and [IO.Directory]::Exists("/proc/$sshAgentPid")) {
  $env:SSH_AUTH_SOCK = "$sshAgentDir/agent.sock"
  $env:SSH_AGENT_PID = $sshAgentPid
}
elseif( ![IO.File]::Exists("$HOME/.skip-ssh") -and
    ($env:SSH_KEY_FILE -or ([IO.Directory]::Exists($SshKeyFolder) -and [IO.Directory]::GetFiles($SshKeyFolder, "*.pub"))) ) {
    Add-SshKey -SshKeyFolder $SshKeyFolder
}

# Aliases through the Alias provider rather than New-Alias: see kernel-profile.ps1.
if([IO.File]::ReadAllText('/etc/issue') -match 'ubuntu') {
	$null = $ExecutionContext.InvokeProvider.Item.New('Alias:\', 'bat', '', 'batcat', $true)
	$null = $ExecutionContext.InvokeProvider.Item.New('Alias:\', 'fd', '', 'fdfind', $true)
}
$null = $ExecutionContext.InvokeProvider.Item.New('Alias:\', 'nvs', '', "$env:NVS_HOME/nvs.ps1", $true)

# Only a prompt shows it: skipped by the lean profile (see kernel-profile.ps1).
# `omp` swaps in oh-my-posh for the session.
if (!$global:LeanProfile) {
  Set-NativePrompt
}
# We dot-source this so that if there's any custom functions on the code-scripts folder, they get added to the global scope
. Run-CodeFolderScripts 
Start-DevSession
