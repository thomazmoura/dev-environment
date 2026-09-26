#!/usr/bin/env bash
# Commits everything in a repository from the git feed, after showing what that
# is and asking. Runs inside a tmux popup, launched by Watch-GitFeed.start_commit.
#
# Usage, as the command of a display-popup (through Invoke-Popup.sh):
#   Show-GitCommit.sh <session> <repo-root> [<ssh-target>]
#
# <ssh-target> is given for a row of an ssh session (prefix+N), whose repository
# is on that host: the whole thing then runs there, over `ssh -t`, so the status
# is the host's and the editor that opens is the host's.
#
# Why a popup and not the pane: the feed is a curses screen in a column 12% of
# the window wide, and a commit wants an editor -- which needs a tty of its own
# and room to write in. The popup is its own pty and takes the editor with it
# when it closes.
#
# It asks first because "stage everything" includes files you may not have meant
# to: the status is on screen, and only y goes on. Every other key closes the
# popup and leaves the work tree exactly as it was.
set -euo pipefail

session=${1:?session}
root=${2:?repo-root}
target=${3:-}

# Run by bash on whichever machine the repository is on, with the root as $1.
# EDITOR falls back to nvim because neither place this runs has read a profile:
# a popup gets the tmux server's environment, and a remote `bash -c` is not a
# login shell. git still prefers core.editor, GIT_EDITOR and VISUAL over it.
body='
hold() { read -rsn1 -p "Press any key to close..." _ || true; }
cd "$1" || { hold; exit 1; }
git -c color.status=always status || { hold; exit 1; }
printf "\n\033[1my\033[0m  stage everything and commit\n"
printf "\033[2many other key  close\033[0m\n"
read -rsn1 answer || answer=""
[ "$answer" = "y" ] || exit 0
printf "\n"
export EDITOR="${EDITOR:-nvim}"
if git add -A && git commit; then
  status=0
else
  status=$?
  printf "\n\033[31mnot committed\033[0m\n"
  hold
fi
nudge="$HOME/.modules/tmux/scripts/Request-RadarSample.sh"
if [ -n "${REMOTE_ROW:-}" ] && [ -x "$nudge" ]; then
  "$nudge" git-radar >/dev/null 2>&1 || true
fi
exit $status
'

printf '\033[1mcommit\033[0m  %s\n' "$session"
printf '\033[2m%s%s\033[0m\n\n' "${target:+$target:}" "$root"

if [ -z "$target" ]; then
  exec bash -c "$body" bash "$root"
fi

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../tmux/scripts/ssh-helpers.sh"
# The host's own sampler is nudged afterwards, as git_remote.op_argv does, so
# its snapshot -- and any feed open on the host itself -- moves with the commit.
exec "$REMOTE_SSH" "${SSH_OPTS[@]}" -q -t "$target" \
  "env REMOTE_ROW=1 bash -c $(sq "$body") bash $(sq "$root")"
