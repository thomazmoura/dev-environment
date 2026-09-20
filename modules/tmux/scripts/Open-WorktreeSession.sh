#!/usr/bin/env bash
# Opens the session for a worktree, wherever that worktree is.
#
# Usage: Open-WorktreeSession.sh [-t user@host] [-r repo] <path>
#   -t   the host the worktree is on; looked up in the registry when not given,
#        and empty for a worktree on this machine
#   -r   the repository it came from; looked up the same way
#
# The one place that knows how a worktree's session is opened, because two
# callers want it: New-Worktree.sh, which has just made the worktree, and the
# manager's Enter (Show-Worktrees.py). A worktree on this machine is just a
# project under ~/code, so it goes to New-CodeSession.sh unchanged. One on
# another machine wants everything an ssh session has -- panes that ssh there,
# the theme colour, the shared agent -- so it goes to New-SshSession.sh's
# -t/-d path, with the name worktree-helpers.sh gives it rather than the
# <host>-<directory> that script would pick for itself.
#
# Keeping the choice here is also what lets Show-Worktrees.py stay out of it:
# it runs this for every row and never has to know which machine the row is on.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"
source "$scripts/worktree-helpers.sh"

target=""
repo=""
while getopts ":t:r:" option; do
  case "$option" in
    t) target="$OPTARG" ;;
    r) repo="$OPTARG" ;;
    *) die "Open-WorktreeSession.sh: unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

[ $# -eq 1 ] || { printf 'usage: Open-WorktreeSession.sh [-t user@host] [-r repo] <path>\n' >&2; exit 2; }
path=$1

[ -n "$target" ] || target="$(registry_target "$path")"
[ -n "$repo" ] || repo="$(registry_repo "$path")"

if [ -z "$target" ]; then
  exec "$scripts/New-CodeSession.sh" "$path"
fi

# A worktree the manager found through git rather than through the registry has
# no recorded repository; ask its host, so the session is still named after both.
[ -n "$repo" ] || repo="$(repo_root "$path" "$target")" || repo=""

exec "$scripts/New-SshSession.sh" -t "$target" -d "$path" \
  -n "$(session_name_for "$path" "$repo" "$target")"
