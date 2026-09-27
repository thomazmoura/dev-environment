#!/usr/bin/env bash
# Opens a throwaway shell in a popup, for a quick command that should not
# disturb the window's layout.
#
#   prefix+p  a shell on the current session's connection, in its working
#             directory: a local pwsh in the pane's directory in a local
#             session; in an ssh session (prefix+N) or a Docker one (prefix+D),
#             the shell a terminal split there would get, in the session's
#             working directory (pane_command, as for New-ToolPane.sh).
#   prefix+P  a local pwsh in the home folder, whichever session the binding
#             fires from.
#
# Usage, from a run-shell -b binding:
#   New-PopupShell.sh -t <pane> -c <client>      the session's (prefix+p)
#   New-PopupShell.sh -l -t <pane> -c <client>   local, in ~ (prefix+P)
#
# The popup's border is drawn in the theme colour of the machine the shell runs
# on: the global theme colour for a local shell, the session's own for a remote
# one -- violet unless @ssh_theme_colour says otherwise, Docker's blue for a
# container session (see Set-SshTheme.sh). That is why this is a run-shell and
# not a `popup` binding: display-popup takes -S as it is, with no formats, so
# the colour has to be worked out before the popup opens. clock-mode-colour is
# the theme colour on its own, and Set-SshTheme.sh swaps it on an ssh
# session's windows along with the rest of the theme.
#
# The popup closes when the shell exits, however it exits: the line is exec'd,
# so nothing is left behind it for the popup to fall back to. Ctrl+C at the
# pwsh prompt is one of those ways (see popup_line); while a command runs it
# still only interrupts the command.
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

# Run by the popup's pwsh once its profile has loaded (-NoExit -Command), so
# only this throwaway shell gets it: Ctrl+C at the prompt, in either vi mode,
# ends pwsh and so closes the popup, instead of a typed `exit`. Environment.Exit
# rather than typing `exit` for you, which would land in the history.
# PSReadLine only sees keys at the prompt, so a running command still gets
# Ctrl+C as an interrupt.
#
# Bound on the first idle tick, not straight away: the profile switches
# PSReadLine to vi mode then (kernel-profile.ps1), which resets every binding
# made before it. This subscribes after the profile did, so it runs after it.
# No $ anywhere, so it passes through bash's double quotes and the remote's
# single quotes unchanged.
close_on_ctrl_c='Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action { Set-PSReadLineKeyHandler -Chord Ctrl+c -ViMode Insert -ScriptBlock { [Environment]::Exit(0) }; Set-PSReadLineKeyHandler -Chord Ctrl+c -ViMode Command -ScriptBlock { [Environment]::Exit(0) } } | Out-Null'

# popup_line [pane]
# The pwsh the popup runs: here with no <pane>, or on <pane>'s session's remote
# (or container) when it is an ssh session. A remote without this
# dev-environment gets its login shell, which has no PSReadLine to hand the key
# to; there it is exit or Ctrl+D as usual.
popup_line() {
  if [ -z "${1:-}" ]; then
    pwsh_invocation "$close_on_ctrl_c" no-exit
  elif ssh_is_devenv "$1"; then
    pane_command "$1" "$close_on_ctrl_c" no-exit
  else
    pane_command "$1" ""
  fi
}

# --- Work out the shell, its colour and directory, open the popup ----------
local_only=""
origin=""
client=""
while getopts "lt:c:" opt; do
  case "$opt" in
    l) local_only="yes" ;;
    t) origin=$OPTARG ;;
    c) client=$OPTARG ;;
    *) warn "usage: New-PopupShell.sh [-l] -t <pane> -c <client>" ;;
  esac
done
origin="$(current_pane "$origin")"
target=()
[ -z "$client" ] || target=(-c "$client")

global_colour="$(tmux show-options -gwv clock-mode-colour 2>/dev/null)" || global_colour=""

if [ -n "$local_only" ]; then
  command="$(printf '%q ' bash -c "$(popup_line)")"
  colour=$global_colour
  dir=$HOME
elif [ -n "$(ssh_option "$origin" @ssh_target)" ]; then
  # The remote side cd's into @ssh_dir itself (ssh_command); the popup's own
  # directory is only where the local ssh starts.
  command="$(printf '%q ' bash -c "$(popup_line "$origin")")"
  colour="$(tmux display-message -p -t "$origin" '#{clock-mode-colour}' 2>/dev/null)" || colour=""
  dir="$(tmux display-message -p -t "$origin" '#{pane_current_path}')"
else
  command="$(printf '%q ' bash -c "$(popup_line)")"
  colour=$global_colour
  dir="$(tmux display-message -p -t "$origin" '#{pane_current_path}')"
fi

border=()
[ -z "$colour" ] || border=(-S "fg=$colour")

# `popup` is the alias in common.conf, so the geometry stays the one every
# picker uses (and Invoke-Popup.sh's spotlight expects). %q because the popup's
# command goes through a shell.
tmux popup "${target[@]}" "${border[@]}" \
  -d "$dir" \
  "$(printf '%q ' "$HOME/.modules/tmux/scripts/Invoke-Popup.sh") $command"
