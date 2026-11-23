#!/usr/bin/env pwsh
# Opens a tmux session with the standard layout for a folder (the current one by default).
#
# Usage: New-CodeSession.ps1 [-Path <folder>]
# Hands the folder, made absolute, to modules/tmux/scripts/New-CodeSession.sh,
# the script behind prefix+/ and prefix+C-c.
param(
  [string] $Path = '.'
)

$folder = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
& "$HOME/.modules/tmux/scripts/New-CodeSession.sh" $folder
exit $LASTEXITCODE
