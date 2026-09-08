#!/usr/bin/env bash
# Start a new Ghostty surface in tmux, and only ask what to run if that is
# declined.
#
# Ghostty has no session model of its own, so whatever this runs is what owns
# the surface from then on. tmux is what nearly every surface is for, and a
# picker you answer the same way every time is a keystroke tax rather than a
# choice -- so tmux is not offered, it just starts. `vtmux` attaches to a live
# session if there is one and otherwise asks fzf which project to open, and
# that second question is the real fork in the road: aborting it is the signal
# that this surface was meant for something else, and only then does the shell
# picker (herdr, tmux, bash, PowerShell) appear.
#
# Wired up as `command` in modules/ghostty/config, so every surface (window and
# ctrl+shift+n tab alike) starts here.

set -uo pipefail

# fzf's code for Esc/ctrl-c, which -ExitOnCancel reuses for an aborted project
# pick (see New-VerticalTmuxSession in modules/powershell-config/linux-profile.ps1).
# Every other status means tmux actually ran, and belongs to the session that
# just ended rather than to this script.
CANCELLED=130

# The herdr row goes through Start-Herdr.sh rather than straight to `herdr`: on
# a fresh session that runs the prefix+ctrl+n project picker first, so the first
# workspace lands on a project instead of on $HOME. It still ends in
# `pwsh -C herdr`, so the pwsh check below covers it too.
#
# launch replaces this script with the chosen program: nothing here needs to
# outlive the pick, and an extra bash in the middle would swallow the exit code
# and keep the window alive one keystroke too long.
launch() {
  case "$1" in
    tmux)       exec pwsh -C vtmux ;;
    herdr)      exec "$HOME/.modules/herdr/scripts/Start-Herdr.sh" ;;
    powershell) exec pwsh ;;
    bash)       exec bash ;;
  esac
}

# herdr and tmux both go through pwsh, so a missing pwsh takes all three
# PowerShell-backed rows with it and bash is the only thing left to offer --
# including the tmux attempt below, which never gets to run.
if ! command -v pwsh >/dev/null 2>&1; then
  exec bash
fi

# The one call that cannot be exec'd: its exit status is the question being
# asked. A session that ends normally ends the surface with it, so the status is
# passed on rather than swallowed -- same outcome as the exec this replaces.
pwsh -C 'vtmux -ExitOnCancel'
status=$?
[ "$status" -eq "$CANCELLED" ] || exit "$status"

# No fzf, or no terminal to draw it on (Ghostty is still wiring up the pty in
# some paths), means the picker cannot be asked. Plain pwsh rather than the
# herdr default: herdr's own startup runs a picker too, and a picker that
# cannot draw is what got us here.
if ! command -v fzf >/dev/null 2>&1 || [ ! -t 0 ]; then
  launch powershell
fi

# `|| true` rather than `|| exit`: fzf exits 130 on Esc/ctrl-c and 1 on an empty
# list, and neither is a reason to close the window with nothing running. herdr
# is the fallback for both, and the first row so the cursor already sits on it:
# tmux has just been declined, so it is no longer the sensible default.
choice=$(printf '%s\n' herdr tmux bash powershell \
  | fzf --reverse --prompt="shell> " --height=100% --no-info) || true
choice=${choice:-herdr}

launch "$choice"

# Only reachable if $choice matched no branch, which the fzf list makes
# impossible; bash keeps the window usable instead of closing it.
exec bash
