#!/usr/bin/env bash
# Shows the diff of the pending changes of a repository from the git feed. Runs
# inside a tmux popup, launched by Watch-GitFeed.show_diff.
#
# Usage, as the command of a display-popup (through Invoke-Popup.sh):
#   Show-GitDiff.sh <session> <repo-root> [<ssh-target>]
#
# <ssh-target> is given for a row of an ssh session (prefix+N), whose repository
# is on that host: the diff then runs there, over `ssh -t`.
#
# Only staged changes shows `gitdfc`, only unstaged ones `gitdf` (both in
# DevHelpers), and both asks which in fzf. The flags are spelled out rather than
# calling pwsh, as Show-GitHistory.sh does for `gith`, and the same flags decide
# what counts as a change, so a whitespace-only one does not open an empty
# pager. Paged by less, which q closes; no -F, so a short diff does not close
# the popup before it can be read.
set -euo pipefail

session=${1:?session}
root=${2:?repo-root}
target=${3:-}

# Run by bash on whichever machine the repository is on, with the root as $1.
body='
hold() { read -rsn1 -p $'"'"'\n\033[2mPress any key to close...\033[0m'"'"' _ || true; }
cd "$1" || { hold; exit 1; }

flags=(--ignore-all-space --ignore-blank-lines --ignore-space-at-eol)
staged=0
unstaged=0
git diff --cached --quiet "${flags[@]}" || staged=1
git diff --quiet "${flags[@]}" || unstaged=1

if [ "$staged" -eq 1 ] && [ "$unstaged" -eq 1 ]; then
  pick=$(printf "staged changes\nunstaged changes\n" \
    | fzf --reverse --no-sort --prompt="diff> " --header="Which changes?") || exit 0
  [ "$pick" = "staged changes" ] || staged=0
elif [ "$staged" -eq 0 ] && [ "$unstaged" -eq 0 ]; then
  echo "No changes to diff (whitespace-only changes are ignored)."
  hold
  exit 0
fi

cached=()
[ "$staged" -eq 1 ] && cached=(--cached)
git -c color.ui=always diff "${cached[@]}" "${flags[@]}" | less -R
'

if [ -z "$target" ]; then
  exec bash -c "$body" bash "$root"
fi

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../tmux/scripts/ssh-helpers.sh"
exec "$REMOTE_SSH" "${SSH_OPTS[@]}" -q -t "$target" "bash -c $(sq "$body") bash $(sq "$root")"
