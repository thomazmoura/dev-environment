#!/usr/bin/env bash
# Lists the machines this tmux is linked to (tmux_link.py), with whether each
# answers and how many sessions it has, and removes the link of the one picked
# -- on both machines, as prefix+N made it.
#
# Bound to prefix+t,l as a popup command in modules/tmux/common.conf.
#
# Removing a link closes nothing: that machine's sessions go on in its own
# tmux, they are only no longer listed here, and prefix+N to it links again.
#
# Usage: Select-TmuxLink.sh [--list]
#   --list  print the rows and exit; what ctrl-r reloads from
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"
source "$scripts/link-helpers.sh"

# identity TAB address TAB <shown>: asked there and then, not of the snapshot,
# since this is where a link that does not answer is looked into.
list_rows() {
  "$link_cli" --format=peers --live |
    awk -F '\t' '{ printf "%s\t%s\t%-28s %-28s %-20s %s sessions\n", $1, $2, $1, $2, $3, $4 }'
}

if [ "${1:-}" = "--list" ]; then
  list_rows
  exit 0
fi

require_tools tmux fzf

rows="$(list_rows)"
[ -n "$rows" ] || die "No linked machines. prefix+N links one."

self="$(readlink -f "${BASH_SOURCE[0]}")"
selection="$(
  printf '%s\n' "$rows" |
    fzf --reverse --delimiter=$'\t' --with-nth=3.. \
        --prompt='unlink> ' \
        --header=$'Linked machines   (Enter removes the link, ctrl-r refresh)' \
        --bind="ctrl-r:reload('$self' --list)"
)" || exit 0
[ -n "$selection" ] || exit 0

IFS=$'\t' read -r identity address _ <<<"$selection"
link_remove "$identity" "$address"
tmux display-message "Unlinked $identity"
