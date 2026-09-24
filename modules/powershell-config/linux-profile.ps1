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

# An agent handed down with SSH_AUTH_SOCK and SSH_AGENT_PID -- by the tmux
# server locally, or by an ssh session's pane from the host's shared agent
# (modules/tmux/scripts/ssh-helpers.sh) -- is trusted while its socket and
# process are there, without asking it for its keys: that ssh-add -L cost
# ~40ms, plus Add-SshKey's own ~50ms, on every shell start. A key that has
# left the agent since is added back by ssh itself on first use
# (AddKeysToAgent, set up by LinuxDevEnv/host-setup.sh). Add-SshKey runs --
# and autoloads from DevHelpers -- only when there is no live agent.
$SshKeyFolder = "$HOME/.ssh"
$sshAgentAlive = $env:SSH_AUTH_SOCK -and $env:SSH_AGENT_PID -and
  [IO.File]::Exists($env:SSH_AUTH_SOCK) -and [IO.Directory]::Exists("/proc/$env:SSH_AGENT_PID")
if( !$sshAgentAlive -and ![IO.File]::Exists("$HOME/.skip-ssh") -and
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
