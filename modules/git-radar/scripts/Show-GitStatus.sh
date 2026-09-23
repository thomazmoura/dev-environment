#!/usr/bin/env bash
# Shows `git status` for a repository from the git feed, and nothing else. Runs
# inside a tmux popup, launched by Watch-GitFeed.show_status.
#
# Usage, as the command of a display-popup (through Invoke-Popup.sh):
#   Show-GitStatus.sh <session> <repo-root> [<ssh-target>]
#
# <ssh-target> is given for a row of an ssh session (prefix+N), whose repository
# is on that host: the status then runs there, over `ssh -t`.
#
# Read-only on purpose: this is `c` without the question, for when you only want
# to know what the row's counters are counting. Any key closes it.
set -euo pipefail

session=${1:?session}
root=${2:?repo-root}
target=${3:-}

# Run by bash on whichever machine the repository is on, with the root as $1.
body='
cd "$1" && git -c color.status=always status
read -rsn1 -p $'"'"'\n\033[2mPress any key to close...\033[0m'"'"' _ || true
'

printf '\033[1mstatus\033[0m  %s\n' "$session"
printf '\033[2m%s%s\033[0m\n\n' "${target:+$target:}" "$root"

if [ -z "$target" ]; then
  exec bash -c "$body" bash "$root"
fi

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../tmux/scripts/ssh-helpers.sh"
exec ssh "${SSH_OPTS[@]}" -q -t "$target" "bash -c $(sq "$body") bash $(sq "$root")"
