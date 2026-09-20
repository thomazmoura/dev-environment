#!/usr/bin/env bash
# Creates a git worktree on a new branch and opens a session in it.
#
# Bound to prefix+t, w as a small popup in modules/tmux/common.conf, started in
# the pane's current path (display-popup -d) and told which pane it was fired
# from (-t "#{pane_id}"). Asks for a name, then:
#
#   1. creates ~/code/<repo>.worktrees/<name> (see worktree-helpers.sh for why
#      a sibling folder) on a branch called <name>, branched from whatever the
#      pane has checked out -- or checks <name> out there if the branch already
#      exists;
#   2. records it in the registry (~/.worktrees), which is what lets closing
#      the session offer to remove it and what the manager on prefix+t, W lists;
#   3. hands over to Open-WorktreeSession.sh, which creates the session with the
#      standard layout and switches to it from inside this popup.
#
# Fired from an ssh session (prefix+N) it does all of that on the host that
# session's panes are on. The pane's current path is no use there -- it is the
# local shell's, not the remote's -- so the repository is the one at the
# session's @ssh_dir, the worktree is created beside it over ssh, and the
# session that opens on it is an ssh session of its own. That is the whole
# reason the binding passes the pane: a popup is an overlay, so nothing else
# here would know which session the keypress came from.
#
# A branch name may contain slashes (feature/foo); the folder cannot usefully,
# so they become dashes there (feature-foo) and the branch keeps its name.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"
source "$scripts/worktree-helpers.sh"

require_tools git tmux

pane=""
while getopts ":t:" option; do
  case "$option" in
    t) pane="$OPTARG" ;;
    *) die "New-Worktree.sh: unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

# Resolved defensively: display-popup's shell-command is not documented to
# expand formats, and a popup is an overlay, so tmux's idea of the current pane
# is still the one underneath it -- which is the pane we want either way.
origin_pane="$(current_pane "$pane" 2>/dev/null)"
[ -n "$origin_pane" ] || origin_pane="$(current_pane 2>/dev/null)"

target=""
[ -n "$origin_pane" ] && target="$(ssh_option "$origin_pane" @ssh_target)"

# This one runs in a popup, which has a terminal: a connection whose master has
# died can ask for a password here rather than fail with nowhere to ask. The
# hook and the manager stay in BatchMode -- see wt_sh.
export WT_SSH_INTERACTIVE=yes

if [ -n "$target" ]; then
  origin="$(ssh_option "$origin_pane" @ssh_dir)"
  [ -n "$origin" ] || die "The ssh session has no directory recorded"
  repo="$(repo_root "$origin" "$target")" ||
    die "Not inside a git repository on ${target##*@}: $origin"
else
  origin="$PWD"
  repo="$(repo_root "$origin")" || die "Not inside a git repository: $origin"
fi

printf 'New worktree for %s%s\n\n' "$(basename "$repo")" "${target:+ on ${target##*@}}"
read -rep 'name: ' name || exit 0
# Trim surrounding whitespace; an empty answer is a change of mind.
name="$(printf '%s' "$name" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
[ -n "$name" ] || exit 0

# A pure string check, so it is asked of the git here even for a remote worktree.
git check-ref-format --branch "$name" >/dev/null 2>&1 || die "Not a valid branch name: $name"

dest="$(dirname "$repo")/$(basename "$repo").worktrees/${name//\//-}"

# Everything that changes something, in one round trip -- the checks included,
# since a check answered here would be about the wrong machine. Same order and
# the same meanings as before: refuse a path that exists, make the container
# folder, ask *the repository* whether the branch exists but add the worktree
# from *the pane's* directory, so a new branch forks from what the pane has
# checked out. A failed add takes the container folder it just made with it.
create='
repo=$1 origin=$2 dest=$3 name=$4
[ -e "$dest" ] && { echo "Already exists: $dest" >&2; exit 3; }
mkdir -p "$(dirname "$dest")" || { echo "Could not create $(dirname "$dest")" >&2; exit 4; }
if git -C "$repo" show-ref --verify --quiet "refs/heads/$name"; then
  git -C "$origin" worktree add "$dest" "$name" 2>&1
else
  git -C "$origin" worktree add -b "$name" "$dest" 2>&1
fi || { status=$?; rmdir "$(dirname "$dest")" 2>/dev/null; exit "$status"; }
'

output="$(wt_sh "$target" "$create" "$repo" "$origin" "$dest" "$name" 2>&1)" ||
  die "${output:-Could not create the worktree}"

registry_add "$dest" "$repo" "$target"

host_option=()
[ -n "$target" ] && host_option=(-t "$target")
exec "$scripts/Open-WorktreeSession.sh" "${host_option[@]}" -r "$repo" "$dest"
