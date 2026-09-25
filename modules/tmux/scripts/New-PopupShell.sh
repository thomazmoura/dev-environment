#!/usr/bin/env bash
# Opens a throwaway shell in a popup, for a quick command that should not
# disturb the window's layout.
#
#   prefix+p  a local pwsh, in the directory of the pane the binding fired
#             from -- even in an ssh session (prefix+N).
#   prefix+P  a shell on a remote, whichever session the binding fires from:
#             the shell a terminal split in an ssh session would get, in that
#             session's working directory (pane_command, as for
#             New-ToolPane.sh). With no ssh session open it says so and opens
#             nothing; with one it goes there; with more it asks which, the
#             current session first when it is one of them.
#
# Usage, from a run-shell -b binding:
#   New-PopupShell.sh -l -t <pane> -c <client>   local (prefix+p)
#   New-PopupShell.sh -t <pane> -c <client>      remote (prefix+P)
#   New-PopupShell.sh --pick <session>...        inside the popup: the picker
#                                                between several ssh sessions
#
# The popup's border is drawn in the theme colour of the machine the shell runs
# on: the global theme colour for a local shell, the ssh sessions' own for a
# remote one -- violet unless @ssh_theme_colour says otherwise (see
# Set-SshTheme.sh). That is why this is a run-shell and not a `popup` binding:
# display-popup takes -S as it is, with no formats, so the colour has to be
# worked out before the popup opens. clock-mode-colour is the theme colour on
# its own, and Set-SshTheme.sh swaps it on an ssh session's windows along with
# the rest of the theme. Every ssh session has the same colour, so the popup can
# take it from any of them before the picker has chosen one.
#
# The popup closes when the shell exits, however it exits: the line is exec'd,
# so nothing is left behind it for the popup to fall back to.
set -euo pipefail

self="$(readlink -f "${BASH_SOURCE[0]}")"
source "$(dirname "$self")/tmux-helpers.sh"

# --- Inside the popup: pick one of several ssh sessions ----------------------
if [ "${1:-}" = "--pick" ]; then
  shift
  require_tools fzf
  rows=""
  for session in "$@"; do
    rows+="$session"$'\t'"$session   $(ssh_option "=$session:" @ssh_target):$(ssh_option "=$session:" @ssh_dir)"$'\n'
  done
  picked="$(printf '%s' "$rows" \
    | fzf --reverse --no-sort --delimiter=$'\t' --with-nth=2.. \
          --prompt='ssh> ' --header='Run a shell in which ssh session?')" || exit 0
  exec bash -c "$(pane_command "=${picked%%$'\t'*}:" "")"
fi

# --- From the binding: work out the shell and its colour, open the popup ----
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

if [ -n "$local_only" ]; then
  command="$(printf '%q ' bash -c "$(pwsh_invocation "")")"
  colour="$(tmux show-options -gwv clock-mode-colour 2>/dev/null)" || colour=""
else
  # Every ssh session, the current one first, so the picker starts on it.
  current="$(tmux display-message -p -t "$origin" '#{session_name}')"
  sessions=()
  [ -z "$(ssh_option "$origin" @ssh_target)" ] || sessions+=("$current")
  while IFS=$'\t' read -r session ssh_target; do
    if [ -n "$ssh_target" ] && [ "$session" != "$current" ]; then
      sessions+=("$session")
    fi
  done < <(tmux list-sessions -F $'#{session_name}\t#{@ssh_target}')

  case "${#sessions[@]}" in
    0) tmux display-message "${target[@]}" "No ssh session is open"; exit 0 ;;
    1) command="$(printf '%q ' bash -c "$(pane_command "=${sessions[0]}:" "")")" ;;
    *) command="$(printf '%q ' "$self" --pick "${sessions[@]}")" ;;
  esac
  colour="$(tmux display-message -p -t "=${sessions[0]}:" '#{clock-mode-colour}' 2>/dev/null)" || colour=""
fi

border=()
[ -z "$colour" ] || border=(-S "fg=$colour")

# `popup` is the alias in common.conf, so the geometry stays the one every
# picker uses (and Invoke-Popup.sh's spotlight expects). %q because the popup's
# command goes through a shell.
tmux popup "${target[@]}" "${border[@]}" \
  -d "$(tmux display-message -p -t "$origin" '#{pane_current_path}')" \
  "$(printf '%q ' "$HOME/.modules/tmux/scripts/Invoke-Popup.sh") $command"
