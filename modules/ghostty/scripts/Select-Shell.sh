#!/usr/bin/env bash
# Start a new Ghostty surface in tmux, and in plain PowerShell if that is
# declined.
#
# Ghostty has no session model of its own, so whatever this runs is what owns
# the surface from then on. tmux is what nearly every surface is for, and a
# picker you answer the same way every time is a keystroke tax rather than a
# choice -- so tmux is not offered, it just starts. `vtmux` attaches to a live
# session if there is one and otherwise asks which project to open (prefix+/'s
# picker), and that question is the real fork in the road: aborting it is the
# signal that this surface was meant for something else, and pwsh starts
# instead.
#
# Wired up as `command` in modules/ghostty/config, so every surface (window and
# ctrl+shift+n tab alike) starts here.

set -uo pipefail

# fzf's code for Esc/ctrl-c, which -ExitOnCancel reuses for an aborted project
# pick (see New-VerticalTmuxSession in modules/powershell/Modules/DevHelpers/DevHelpers.psm1).
# Every other status means tmux actually ran, and belongs to the session that
# just ended rather than to this script.
CANCELLED=130

# tmux goes through pwsh, so without it bash is all there is.
if ! command -v pwsh >/dev/null 2>&1; then
  exec bash
fi

# The one call that cannot be exec'd: its exit status is the question being
# asked. A session that ends normally ends the surface with it, so the status is
# passed on rather than swallowed -- same outcome as an exec.
pwsh -C 'vtmux -ExitOnCancel'
status=$?
[ "$status" -eq "$CANCELLED" ] || exit "$status"

exec pwsh
