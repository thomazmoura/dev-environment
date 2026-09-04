#!/usr/bin/env bash
# Pick what a new Ghostty surface should run: herdr, tmux, bash or PowerShell.
#
# Ghostty has no session model of its own, so whatever this prints to the
# terminal is what owns it from then on. herdr is the default: it is the first
# row, so the fzf cursor already sits on it, and it is also what an aborted or
# impossible pick falls back to. That way a stray Esc still lands in the usual
# session instead of dropping the window.
#
# Wired up as `command` in modules/ghostty/config, so every surface (window and
# ctrl+shift+n tab alike) starts here.

set -uo pipefail

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
    herdr)      exec "$HOME/.modules/herdr/scripts/Start-Herdr.sh" ;;
    tmux)       exec pwsh -C vtmux ;;
    powershell) exec pwsh ;;
    bash)       exec bash ;;
  esac
}

# herdr and tmux both go through pwsh, so a missing pwsh takes all three
# PowerShell-backed rows with it and bash is the only thing left to offer.
if command -v pwsh >/dev/null 2>&1; then
  options=$'herdr\ntmux\nbash\npowershell'
else
  options="bash"
fi

# No fzf, or no terminal to draw it on (Ghostty is still wiring up the pty in
# some paths), means no picker: go straight to the default.
if [ "$options" = "bash" ] || ! command -v fzf >/dev/null 2>&1 || [ ! -t 0 ]; then
  launch "${options%%$'\n'*}"
fi

# `|| true` rather than `|| exit`: fzf exits 130 on Esc/ctrl-c and 1 on an empty
# list, and neither is a reason to close the window with nothing running.
choice=$(printf '%s\n' "$options" \
  | fzf --reverse --prompt="shell> " --height=100% --no-info) || true
choice=${choice:-herdr}

launch "$choice"

# Only reachable if $choice matched no branch, which the fzf list makes
# impossible; bash keeps the window usable instead of closing it.
exec bash
