#!/usr/bin/env bash
# Offers to remove a worktree once the session that was using it has closed.
#
# Usage: Close-WorktreeSession.sh <session-name>
#   Run from the session-closed hook in modules/tmux/common.conf, for every
#   session that closes. Most are not worktree sessions, so the first thing this
#   does is look the name up in the registry and leave when it is not there.
#
# For a registered worktree:
#   - folder already gone  the row is dropped and git's record pruned; nothing
#                          left to ask about
#   - changes in it        kept, with a status-line note saying so; closing a
#                          session is not a reason to throw work away
#   - clean                asks, in a popup on the client that is still around
#                          (see Remove-Worktree.sh --ask)
#
# The question is a popup rather than tmux's own confirm-before: confirm-before
# only works from a key binding, where tmux knows which client pressed the key
# (Watch-GitFeed.py's kill() has the details). A hook has no client of its own,
# so this picks the most recently active one and points the popup at it. When no
# client is attached at all -- the last one detached, or the server is going
# away -- there is nobody to ask, and the worktree is kept. The manager on
# prefix+t, W can remove it later.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/worktree-helpers.sh"

session="${1:-}"
[ -n "$session" ] || exit 0

paths="$(registry_paths_for_session "$session")"
[ -n "$paths" ] || exit 0

# A new session may already have been opened on the same worktree (the closing
# one was a duplicate, or it was killed and reopened); that one still needs it.
tmux has-session -t "=$session" 2>/dev/null && exit 0

client="$(tmux list-clients -F '#{client_activity} #{client_name}' 2>/dev/null |
  sort -rn | head -n1 | cut -d' ' -f2-)"

while IFS= read -r path; do
  [ -n "$path" ] || continue

  if [ ! -d "$path" ]; then
    remove_worktree "$path" >/dev/null 2>&1
    continue
  fi

  if ! worktree_is_clean "$path"; then
    tmux display-message "worktree $(basename "$path") has changes -- kept" 2>/dev/null
    continue
  fi

  [ -n "$client" ] || continue

  # One popup at a time: display-popup blocks until it closes, which is what
  # makes two matching worktrees ask one after the other instead of on top of
  # each other. printf %q because the popup's command goes through a shell.
  tmux display-popup -c "$client" -E -w 70 -h 12 -x C -y C \
    "$(printf '%q --ask %q' "$scripts/Remove-Worktree.sh" "$path")" 2>/dev/null
done <<< "$paths"

exit 0
