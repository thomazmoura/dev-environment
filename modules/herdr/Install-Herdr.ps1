#!/usr/bin/env pwsh

. "$HOME/.modules/powershell/Check-Failure.ps1"

# herdr is a terminal multiplexer built as a runtime for coding agents. Upstream
# documents `curl -fsSL https://herdr.dev/install.sh | sh`, but the releases
# publish plain binaries, so this pins a version and downloads it directly
# instead of piping a script into a shell.
$HerdrVersion = "v0.8.2"

$Architecture = & uname -m
$Package = switch ( $Architecture ) {
  "x86_64"  { "herdr-linux-x86_64" }
  "aarch64" { "herdr-linux-aarch64" }
  "arm64"   { "herdr-linux-aarch64" }
  default   { throw "Unsupported architecture for herdr: $Architecture" }
}

$InstalledVersion = $null
if ( Test-Path "$HOME/herdr/herdr" ) {
  # `herdr --version` prints "herdr 0.8.2" (no leading "v")
  $InstalledVersion = (& "$HOME/herdr/herdr" --version | Select-Object -First 1) -replace '^herdr\s+', ''
}

if ( ($InstalledVersion -ne $HerdrVersion.TrimStart("v")) -or ! (Test-Path "$HOME/.local/bin/herdr") ) {
  if ( $InstalledVersion ) {
    Write-Output ">>> Updating herdr from $InstalledVersion to $HerdrVersion"
  } else {
    Write-Output ">>> Installing herdr $HerdrVersion"
  }
  Set-Location $HOME

  Write-Output "=>> Removing any previous installation"
  Remove-Item -Recurse -Force "$HOME/herdr/" -ErrorAction SilentlyContinue
  New-Item -Type Directory -Force "$HOME/herdr/"

  Write-Output "=>> Ensuring the ~/.local/bin directory exists"
  New-Item -Type Directory -Force "$HOME/.local/bin/"

  Write-Output "=>> Downloading herdr's release binary ($Package)"
  Invoke-WebRequest https://github.com/herdrdev/herdr/releases/download/$HerdrVersion/$Package -OutFile "$HOME/herdr/herdr"

  Write-Output "=>> Making herdr executable"
  & chmod +x $HOME/herdr/herdr

  Write-Output "=>> Creating symbolic links"
  New-Item -Force -Type SymbolicLink -Path "$HOME/.local/bin/herdr" -Target "$HOME/herdr/herdr"
}

# Agent integrations. These are hooks the agents call on session events so herdr
# can track each agent's lifecycle state (idle / working / blocked). herdr owns
# the generated files and overwrites them on reinstall, so this is idempotent.
# Only the agents this environment actually ships are installed.
foreach ( $Integration in @("claude", "codex", "copilot", "opencode") ) {
  Write-Output "=>> Installing the herdr $Integration integration"
  & "$HOME/herdr/herdr" integration install $Integration
}

# The agent skill is the other half of the integration: the hooks let herdr read
# an agent's state, the skill lets the agent drive herdr back. The installed
# binary is the authority for its own command surface, so the skill is generated
# from it rather than vendored into this repo, keeping the two in sync.
Write-Output "=>> Installing the herdr agent skill for Claude Code"
New-Item -Type Directory -Force "$HOME/.claude/skills/herdr/"
& "$HOME/herdr/herdr" --skill | Set-Content "$HOME/.claude/skills/herdr/SKILL.md"

Throw-ExceptionOnNativeFailure
