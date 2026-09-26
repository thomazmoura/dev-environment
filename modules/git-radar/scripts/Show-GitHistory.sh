#!/usr/bin/env bash
# Shows the commit graph of a repository from the git feed. Runs inside a tmux
# popup, launched by Watch-GitFeed.show_history.
#
# Usage, as the command of a display-popup (through Invoke-Popup.sh):
#   Show-GitHistory.sh <session> <repo-root> [<ssh-target>]
#
# <ssh-target> is given for a row of an ssh session (prefix+N), whose repository
# is on that host: the log then runs there, over `ssh -t`.
#
# The format is spelled out rather than calling the `git history` alias
# (GitGet-History in DevHelpers), because the alias lives in a gitconfig and
# the host being asked may not have it. Paged by less, which q closes; no -F,
# so a short history does not close the popup before it can be read.
set -euo pipefail

session=${1:?session}
root=${2:?repo-root}
target=${3:-}

# Run by bash on whichever machine the repository is on, with the root as $1.
body='
cd "$1" || { read -rsn1 -p "Press any key to close..." _ || true; exit 1; }
git log --color=always --oneline --graph --date=short --author-date-order \
  --pretty=format:"%C(yellow)%h %Cred%ad %Cblue%an%Cgreen%d %Creset%s" \
  | less -R
'

if [ -z "$target" ]; then
  exec bash -c "$body" bash "$root"
fi

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../tmux/scripts/ssh-helpers.sh"
exec "$REMOTE_SSH" "${SSH_OPTS[@]}" -q -t "$target" "bash -c $(sq "$body") bash $(sq "$root")"
