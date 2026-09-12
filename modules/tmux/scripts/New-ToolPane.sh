#!/usr/bin/env bash
# Opens a labelled pane running a pwsh command. The workhorse behind almost
# every pane-creating binding in modules/tmux/common.conf -- the agent menu
# (prefix+t), the Angular/.NET runners (prefix+a, A, T, W) and the plain
# terminals (prefix+% and prefix+"). In an ssh session (prefix+N) the pane runs
# the same command on the remote, in the session's working directory.
#
# Usage: New-ToolPane.sh [options] <label> <pwsh-command>
#   -t <target>   pane the split is relative to; bindings pass "#{pane_id}"
#   -v            split vertically (default: horizontally)
#   -l <size>     size of the new pane, e.g. 20%
#   -k            keep pwsh interactive after the command (pwsh -NoExit)
#   -P            print the new pane's id, so a binding that opens two panes can
#                 split the second one off the first (see prefix+A in common.conf)
#   -d <glob>     only run the command if the pane's current path contains a
#                 directory matching <glob>; otherwise the pane just explains
#                 what is missing and closes on the next keypress
#   -L            always run the command here, even in an ssh session -- for a
#                 pane about the whole machine rather than the session's
#                 directory, like the git feed (prefix+t then R), which lists
#                 the ssh sessions itself and asks their hosts
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
requires=""
local_only=""

while getopts ":t:vl:kPd:L" option; do
  case "$option" in
    t) target="$OPTARG" ;;
    v) direction="-v" ;;
    l) size=(-l "$OPTARG") ;;
    k) no_exit="yes" ;;
    P) print_id="yes" ;;
    d) requires="$OPTARG" ;;
    L) local_only="yes" ;;
    *) die "New-ToolPane.sh: unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

[ "$#" -eq 2 ] || die "New-ToolPane.sh: expected <label> <command>, got $# argument(s)"

label=$1
command=$2

origin="$(current_pane "$target")"

# The runners cd into a sibling directory by glob, and the pane inherits its
# path from the pane the binding fired in (see new_pane's split-window -c), so
# the guard has to be checked against that same path -- not against the cwd of
# this script, which run-shell leaves wherever the server was started.
#
# In an ssh session the local path means nothing: the command runs in the
# session's working directory on the remote, so that is where the glob is
# checked. An ssh that fails outright (255) skips the guard, and the pane is
# left to show the connection error instead.
if [ -n "$local_only" ]; then
  line="$(pwsh_command "$command" "$no_exit")"
else
  line="$(pane_command "$origin" "$command" "$no_exit")"
fi
if [ -n "$requires" ]; then
  remote="$(ssh_option "$origin" @ssh_target)"
  if [ -n "$remote" ]; then
    path="$remote:$(ssh_option "$origin" @ssh_dir)"
    status=0
    remote_directory_matches "$origin" "$requires" || status=$?
    [ "$status" -eq 0 ] || [ "$status" -eq 255 ] || missing="yes"
  else
    path="$(tmux display-message -p -t "$origin" '#{pane_current_path}')"
    directory_matches "$path" "$requires" || missing="yes"
  fi
  [ -z "${missing:-}" ] ||
    line="$(notice_command "There is no $requires folder in $path")"
fi

pane="$(new_pane "$origin" "$label" "$line" "$direction" "${size[@]}")"

if [ -n "$print_id" ]; then
  printf '%s\n' "$pane"
fi
