#!/usr/bin/env bash
# Opens a throwaway pwsh in a popup, for a quick command that should not disturb
# the window's layout.
#
#   prefix+p  always a local pwsh, in the directory of the pane the binding
#             fired from -- even in an ssh session (prefix+N).
#   prefix+P  the shell a plain terminal split would get (prefix+%): local as
#             above, or, in an ssh session, a shell on the remote in the
#             session's working directory -- pane_command decides which,
#             exactly as it does for New-ToolPane.sh.
#
# Usage, from a run-shell -b binding:
#   New-PopupShell.sh [-l] -t <pane> -c <client>
#     -l  local even in an ssh session (prefix+p)
#
# The popup's border is drawn in the theme colour of the machine the shell runs
# on: the global theme colour for a local shell, the session's own for one on
# the remote -- violet unless @ssh_theme_colour says otherwise (see
# Set-SshTheme.sh). That is why this is a run-shell and not a `popup` binding:
# display-popup takes -S as it is, with no formats, so the colour has to be
# worked out before the popup opens. clock-mode-colour is the theme colour on
# its own, and Set-SshTheme.sh swaps it on an ssh session's windows along with
# the rest of the theme.
#
# The popup closes when the shell exits, however it exits: the line is exec'd,
# so nothing is left behind it for the popup to fall back to.
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

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

if [ -n "$local_only" ]; then
  line="$(pwsh_invocation "")"
  colour="$(tmux show-options -gwv clock-mode-colour 2>/dev/null)" || colour=""
else
  line="$(pane_command "$origin" "")"
  colour="$(tmux display-message -p -t "$origin" '#{clock-mode-colour}' 2>/dev/null)" || colour=""
fi

border=()
[ -z "$colour" ] || border=(-S "fg=$colour")
target=()
[ -z "$client" ] || target=(-c "$client")

# `popup` is the alias in common.conf, so the geometry stays the one every
# picker uses (and Invoke-Popup.sh's spotlight expects). printf %q because the
# popup's command goes through a shell.
tmux popup "${target[@]}" "${border[@]}" \
  -d "$(tmux display-message -p -t "$origin" '#{pane_current_path}')" \
  "$(printf '%q ' "$HOME/.modules/tmux/scripts/Invoke-Popup.sh" bash -c "$line")"
