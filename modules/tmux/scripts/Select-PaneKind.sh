#!/usr/bin/env bash
# The picker pane of the default layout, and the pane opener behind prefix+e,
# prefix+E and prefix+Space.
#
# Without a kind it runs inside a pane: an fzf list of what the pane could be
# (PANE_KINDS in tmux-helpers.sh -- NeoVim, Terminal, the coding agents), and
# the pane turns into whatever is chosen. Enter straight away picks NeoVim.
# Set-NeovimLayout.sh starts it in the main pane of every new session, so a
# session opens on Git, Agents and this question rather than on a NeoVim you
# may not want.
#
# With a kind it splits a new pane off -t running that kind, the way
# New-ToolPane.sh does -- prefix+e and prefix+- then e open NeoVim that way,
# prefix+E and prefix+- then E a bare NeoVim (NORC), run by bash, not pwsh,
# and prefix+t, n a nearly bare one (vim/notes.vimrc) on the repository's .notes. The kind Picker splits off
# a new pane that asks, the way the layout's picker does -- prefix+Space and
# prefix+- then Space. A new pane is the only way to get one
# outside a new session: nothing types the picker into a pane that is already
# there.
#
# In an ssh session (prefix+N) the picker itself runs here, where fzf is, and
# the chosen tool runs on the remote like every other pane (pane_command).
#
# Usage: Select-PaneKind.sh [-t <target>] [-v] [kind]
#   -t <target>   with a kind: the pane the split is relative to; bindings pass
#                 "#{pane_id}". Without one: the pane to turn (default $TMUX_PANE)
#   -v            with a kind: split below instead of to the right
#   kind          one of PANE_KINDS, or Picker for a new pane that asks;
#                 omitted, this pane asks
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

target=""
direction="-h"
while getopts ":t:v" option; do
  case "$option" in
    t) target="$OPTARG" ;;
    v) direction="-v" ;;
    *) die "Select-PaneKind.sh: unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

kind="${1:-}"

# A kind given: a new pane of it. This runs from `run-shell -b`, so failures
# go to the status line.
if [ -n "$kind" ]; then
  origin="$(current_pane "$target")"
  # Always local, like the layout's picker: fzf runs here, and the pane hands
  # what it becomes to pane_command itself.
  if [ "$kind" = Picker ]; then
    new_pane "$origin" "Picker" "bash ~/.modules/tmux/scripts/Select-PaneKind.sh" "$direction" >/dev/null
    exit 0
  fi
  pane_kind "$origin" "$kind" || warn "Select-PaneKind.sh: unknown kind $kind"
  new_pane "$origin" "$kind" "$(pane_command "$origin" "$kind_command" "$kind_no_exit" "$kind_no_pwsh")" "$direction" >/dev/null
  exit 0
fi

# No kind: this pane asks. Esc brings the list back rather than leaving an
# empty pane in the layout's main slot; prefix+C-b x still closes it.
require_tools tmux fzf
pane="$(current_pane "${target:-${TMUX_PANE:-}}")"
while :; do
  kind="$(printf '%s\n' "${PANE_KINDS[@]}" |
    fzf --reverse --no-sort --prompt='pane> ' --header='What should this pane be?')" || continue
  [ -n "$kind" ] && pane_kind "$pane" "$kind" && break
done

label_pane "$pane" "$kind"

# The layout's role for this pane follows what it became: NeoVim takes the
# neovim role, so prefix+v and prefix+V see the editor they expect; anything
# else gives the role up, so prefix+V knows NeoVim is missing and brings it.
if [ "$(tmux display-message -p -t "$pane" '#{@layout_role}')" = picker ]; then
  if [ "$kind" = NeoVim ]; then
    tmux set -p -t "$pane" @layout_role neovim
  else
    tmux set -p -u -t "$pane" @layout_role
  fi
fi

clear
exec bash -c "$(pane_command "$pane" "$kind_command" "$kind_no_exit")"
