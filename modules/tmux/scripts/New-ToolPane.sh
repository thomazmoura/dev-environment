#!/usr/bin/env bash
# Opens a labelled pane running a pwsh command. The workhorse behind almost
# every pane-creating binding in modules/tmux/common.conf -- the agent menu
# (prefix+t), the Angular/.NET runners (prefix+a, A, T, W) and the plain
# terminals (prefix+% and prefix+").
#
# Usage: New-ToolPane.sh [options] <label> <pwsh-command>
#   -t <target>   pane the split is relative to; bindings pass "#{pane_id}"
#   -v            split vertically (default: horizontally)
#   -l <size>     size of the new pane, e.g. 20%
#   -k            keep pwsh interactive after the command (pwsh -NoExit)
#   -P            print the new pane's id, so a binding that opens two panes can
#                 split the second one off the first (see prefix+A in common.conf)
#
# Example, as used by the binding for prefix+t then C:
#   New-ToolPane.sh -t "#{pane_id}" "Claude Code" "claude --resume"
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

# Nothing here has a popup to write to: this runs from `run-shell -b`, so
# failures go to the status line.
die() { warn "$@"; }

target=""
direction="-h"
size=()
no_exit=""
print_id=""

while getopts ":t:vl:kP" option; do
  case "$option" in
    t) target="$OPTARG" ;;
    v) direction="-v" ;;
    l) size=(-l "$OPTARG") ;;
    k) no_exit="yes" ;;
    P) print_id="yes" ;;
    *) die "New-ToolPane.sh: unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

[ "$#" -eq 2 ] || die "New-ToolPane.sh: expected <label> <command>, got $# argument(s)"

label=$1
command=$2

origin="$(current_pane "$target")"
pane="$(new_pane "$origin" "$label" "$(pwsh_command "$command" "$no_exit")" "$direction" "${size[@]}")"

if [ -n "$print_id" ]; then
  printf '%s\n' "$pane"
fi
