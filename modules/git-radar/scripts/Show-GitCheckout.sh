#!/usr/bin/env bash
# Checks out another branch of a repository from the git feed, picked with fzf.
# Runs inside a tmux popup, launched by Watch-GitFeed.start_checkout.
#
# Usage, as the command of a display-popup (through Invoke-Popup.sh):
#   Show-GitCheckout.sh <session> <repo-root> [<ssh-target>]
#
# <ssh-target> is given for a row of an ssh session (prefix+N), whose repository
# is on that host: the checkout then runs there, over `ssh -t`.
#
# This is `gitco` (GitFuzzyCheckout-Branch in DevHelpers) and nothing more, so
# it behaves as it does in a terminal: changes in the work tree come along, or
# git refuses. pwsh runs lean (PWSH_LEAN=1); the profile still puts DevHelpers
# on the module path, which is where gitco autoloads from. A successful
# checkout, or an fzf left with Esc (130), closes the popup at once -- the row
# shows the new branch; anything else holds it open so git's error can be read.
set -euo pipefail

session=${1:?session}
root=${2:?repo-root}
target=${3:-}

# Run by bash on whichever machine the repository is on, with the root as $1.
body='
hold() { read -rsn1 -p $'"'"'\n\033[2mPress any key to close...\033[0m'"'"' _ || true; }
cd "$1" || { hold; exit 1; }

status=0
PWSH_LEAN=1 pwsh -NoLogo -Command "gitco; exit \$LASTEXITCODE" || status=$?
if [ "$status" -ne 0 ] && [ "$status" -ne 130 ]; then
  hold
fi

nudge="$HOME/.modules/tmux/scripts/Request-RadarSample.sh"
if [ -n "${REMOTE_ROW:-}" ] && [ -x "$nudge" ]; then
  "$nudge" git-radar >/dev/null 2>&1 || true
fi
'

printf '\033[1mcheckout\033[0m  %s\n' "$session"
printf '\033[2m%s%s\033[0m\n\n' "${target:+$target:}" "$root"

if [ -z "$target" ]; then
  exec bash -c "$body" bash "$root"
fi

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../tmux/scripts/ssh-helpers.sh"
# The host's own sampler is nudged afterwards, as Show-GitMerge.sh does.
exec "$REMOTE_SSH" "${SSH_OPTS[@]}" -q -t "$target" \
  "env REMOTE_ROW=1 bash -c $(sq "$body") bash $(sq "$root")"
