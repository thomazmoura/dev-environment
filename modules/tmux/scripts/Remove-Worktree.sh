#!/usr/bin/env bash
# Removes a git worktree: its registry row, its session, the folder and -- when
# it is merged -- its branch. See remove_worktree in worktree-helpers.sh for the
# order and the reasons for it.
#
# Usage: Remove-Worktree.sh [--ask] [--force] <path>
#   --ask     ask first, and hold the result on screen until a key is pressed.
#             How Close-WorktreeSession.sh runs it, in a popup on the client
#             that just lost the worktree's session.
#   --force   remove even with uncommitted changes. Only Show-Worktrees.py
#             passes it, after asking in its own pane.
#
# Without --force a dirty worktree is refused by git itself, so the question
# --ask puts is only ever about a clean one -- the hook checks before asking,
# and git checks again in case something changed while the popup was up.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"
source "$scripts/worktree-helpers.sh"

ask=""
force=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ask) ask="yes" ;;
    --force) force="yes" ;;
    --) shift; break ;;
    -*) printf 'Remove-Worktree.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done

[ $# -eq 1 ] || { printf 'usage: Remove-Worktree.sh [--ask] [--force] <path>\n' >&2; exit 2; }
path=$1

if [ -z "$ask" ]; then
  remove_worktree "$path" "$force"
  exit $?
fi

branch="$(worktree_branch "$path")"
printf 'The session for worktree %s has closed.\n' "$(basename "$path")"
printf 'It has no uncommitted changes.\n\n'
printf '  %s\n' "$path"
[ -n "$branch" ] && printf '  branch %s (deleted only if merged)\n' "$branch"
printf '\n'
read -rsn1 -p 'Remove it? [y/N] ' answer
printf '\n\n'

# Only y removes; anything else -- n, Esc, Enter, a stray key -- keeps it,
# which is what a keypress aimed at something else should do.
if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
  exit 0
fi

remove_worktree "$path" "$force"
status=$?
printf '\n'
read -rsn1 -p 'Press any key to close...' _
exit "$status"
