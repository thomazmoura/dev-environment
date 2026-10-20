#!/usr/bin/env bash
# Shows the commit graph of a repository from the git feed, and searches it with
# fzf on /. Runs inside a tmux popup, launched by Watch-GitFeed.show_history.
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
#
# / in that pager is rebound (--lesskey-src, less 582+) to quit with status 47,
# ASCII "/", which this loop reads as "search": the same log goes to fzf, where
# Enter shows the commit under the cursor in less (q comes back to the list,
# query kept), ctrl-a reloads it with every branch and ctrl-b with this one,
# and Esc goes back to the graph. Each line carries its full hash after a tab,
# cut off for the pager and hidden by --with-nth in fzf; graph-only lines have
# none, so Enter does nothing on them. SHELL is bash because fzf runs reload
# and execute through it, and glog only exists for bash.
set -euo pipefail

session=${1:?session}
root=${2:?repo-root}
target=${3:-}

# Run by bash on whichever machine the repository is on, with the root as $1.
body='
hold() { read -rsn1 -p $'"'"'\n\033[2mPress any key to close...\033[0m'"'"' _ || true; }
cd "$1" || { hold; exit 1; }

export SHELL=bash
glog() {
  git log --color=always --graph --date=short --author-date-order \
    --pretty=format:"%C(yellow)%h %Cred%ad %Cblue%an%Cgreen%d %Creset%s%x09%H" "$@"
}
export -f glog

while :; do
  status=0
  glog | cut -f1 | less -R --lesskey-src=<(printf "#command\n/ quit /\n") || status=$?
  [ "$status" -eq 47 ] || exit 0
  glog | fzf --ansi --reverse --no-sort --delimiter="\t" --with-nth=1 \
    --prompt="history> " \
    --header="Enter shows the commit (q back) · ctrl-a every branch · ctrl-b this one · Esc back to the graph" \
    --bind "ctrl-a:reload(glog --all)+change-prompt(all> )" \
    --bind "ctrl-b:reload(glog)+change-prompt(history> )" \
    --bind "enter:execute([ -n {2} ] && git -c color.ui=always show {2} | less -R)" \
    || true
done
'

if [ -z "$target" ]; then
  exec bash -c "$body" bash "$root"
fi

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../tmux/scripts/ssh-helpers.sh"
exec "$REMOTE_SSH" "${SSH_OPTS[@]}" -q -t "$target" "bash -c $(sq "$body") bash $(sq "$root")"
