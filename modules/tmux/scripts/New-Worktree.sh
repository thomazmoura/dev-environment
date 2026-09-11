#!/usr/bin/env bash
# Creates a git worktree on a new branch and opens a session in it.
#
# Bound to prefix+t, w as a small popup in modules/tmux/common.conf, started in
# the pane's current path (display-popup -d). Asks for a name, then:
#
#   1. creates ~/code/<repo>.worktrees/<name> (see worktree-helpers.sh for why
#      a sibling folder) on a branch called <name>, branched from whatever the
#      pane has checked out -- or checks <name> out there if the branch already
#      exists;
#   2. records it in the registry (~/.worktrees), which is what lets closing
#      the session offer to remove it and what the manager on prefix+t, W lists;
#   3. hands over to New-CodeSession.sh, which creates the session with the
#      standard layout and switches to it from inside this popup.
#
# A branch name may contain slashes (feature/foo); the folder cannot usefully,
# so they become dashes there (feature-foo) and the branch keeps its name.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"
source "$scripts/worktree-helpers.sh"

require_tools git tmux

origin="$PWD"
repo="$(repo_root "$origin")" || die "Not inside a git repository: $origin"

printf 'New worktree for %s\n\n' "$(basename "$repo")"
read -rep 'name: ' name || exit 0
# Trim surrounding whitespace; an empty answer is a change of mind.
name="$(printf '%s' "$name" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
[ -n "$name" ] || exit 0

git check-ref-format --branch "$name" >/dev/null 2>&1 || die "Not a valid branch name: $name"

dest="$(dirname "$repo")/$(basename "$repo").worktrees/${name//\//-}"
[ -e "$dest" ] && die "Already exists: $dest"

mkdir -p "$(dirname "$dest")" || die "Could not create $(dirname "$dest")"

if git -C "$repo" show-ref --verify --quiet "refs/heads/$name"; then
  output="$(git -C "$origin" worktree add "$dest" "$name" 2>&1)"
else
  output="$(git -C "$origin" worktree add -b "$name" "$dest" 2>&1)"
fi
if [ $? -ne 0 ]; then
  rmdir "$(dirname "$dest")" 2>/dev/null
  die "$output"
fi

registry_add "$dest" "$repo"

exec "$scripts/New-CodeSession.sh" "$dest"
