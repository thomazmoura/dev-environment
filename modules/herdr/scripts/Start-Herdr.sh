#!/usr/bin/env bash
# Launch herdr, opening the first workspace on a picked project rather than on
# whatever directory the terminal happened to start in.
#
# On a fresh session this runs the prefix+ctrl+n pickers first
# (Open-CodeWorkspace.sh --startup) and launches herdr from the picked project,
# which that script's detached build then fills with the agent, "NeoVim" and
# "Terminal" tabs.
#
# Attaching to a session that is already up skips all of it: the spaces are
# already there and prefix+/ hops between them.
#
# The picker runs inside pwsh rather than here. Ghostty's `command` bypasses the
# login shell (see modules/ghostty/config), so this script's PATH is the bare
# desktop-session one: ~/.local/bin is there via ~/.profile, but everything
# ~/.bashrc adds -- ~/.opencode/bin, the nvs node bin dir -- is not, and the
# agent picker lists only the CLIs it can find. The pwsh profile rebuilds that
# PATH, and pwsh has to start anyway to run herdr, so running the picker under
# that same pwsh costs no extra profile load.
#
# Run for the "herdr" row of modules/ghostty/scripts/Select-Shell.sh.

set -uo pipefail

picker="$HOME/.modules/herdr/scripts/Open-CodeWorkspace.sh"

# A live server answers workspace list; a dead one (or a stale socket file left
# behind by one) does not. That is the question that actually matters here --
# "is there a session to attach to" -- so it is the one being asked.
if herdr workspace list >/dev/null 2>&1 || [ ! -x "$picker" ]; then
  exec pwsh -C herdr
fi

# An abort in either picker prints nothing and exits 0, which lands here as an
# empty target: herdr then starts the ordinary way instead of not at all.
# Select-Object -Last 1 because the picker's own output is the last line: the
# pwsh profile has already had its say on stdout by the time this runs.
export HERDR_STARTUP_PICKER="$picker"
exec pwsh -Command '
  $target = & $env:HERDR_STARTUP_PICKER --startup | Select-Object -Last 1
  if ($target -and (Test-Path -LiteralPath $target -PathType Container)) {
    Set-Location -LiteralPath $target
  }
  herdr
'
