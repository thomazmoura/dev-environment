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
# so nothing is left behind it for the popup to fall back to. Ctrl+C on an
# empty pwsh prompt is one of those ways (see popup_line); while a command runs
# it still only interrupts the command.
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

# popup_line [pane]
# The shell the popup runs: a plain interactive pwsh here with no <pane>, or on
# <pane>'s session's remote (or container) the shell a terminal split there
# would get. Ctrl+C on an empty pwsh prompt ends it (kernel-profile.ps1), and so
# closes the popup; a remote without this dev-environment has its login shell,
# where it is exit or Ctrl+D as usual.
popup_line() {
  if [ -z "${1:-}" ]; then
    pwsh_invocation ""
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
#
# With -E the popup blocks until the shell ends and exits with the shell's own
# status: pwsh's last $LASTEXITCODE, ssh's 255 on a dropped connection. That is
# no failure of this script, but run-shell would report it anyway ("... returned
# 2") in whichever pane gets the focus back, which has nothing to do with it. So
# the status is dropped, and only what tmux itself says -- the popup could not
# open -- goes to the status line, on the client that asked for it.
if ! error="$(tmux popup "${target[@]}" "${border[@]}" \
  -d "$dir" \
  "$(printf '%q ' "$HOME/.modules/tmux/scripts/Invoke-Popup.sh") $command" 2>&1)" && [ -n "$error" ]; then
  tmux display-message "${target[@]}" "Popup shell: $error"
fi
exit 0
