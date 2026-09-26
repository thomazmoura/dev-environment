#!/usr/bin/env bash
# Merges a repository's current branch into another branch, picked with fzf,
# and comes back. Runs inside a tmux popup, launched by Watch-GitFeed.start_merge.
#
# Usage, as the command of a display-popup (through Invoke-Popup.sh):
#   Show-GitMerge.sh <session> <repo-root> [<ssh-target>]
#
# <ssh-target> is given for a row of an ssh session (prefix+N), whose repository
# is on that host: the whole thing then runs there, over `ssh -t`.
#
# This is `gitub` (GitUpdate-Branch in DevHelpers) -- checkout the target, merge
# the branch you were on, push, checkout back -- with three differences:
#   - the target is chosen with fzf instead of defaulting to homolog;
#   - it asks before touching anything, naming both branches and the push;
#   - it stops, rather than carrying on, wherever carrying on would do damage:
#     a dirty work tree is refused up front (checkout would drag the changes
#     along), the target is fast-forwarded to its upstream first (so the push
#     is not rejected for being behind), and a conflicted merge is aborted.
# Whatever happens after the first checkout, it ends back on the branch it
# started on.
set -euo pipefail

session=${1:?session}
root=${2:?repo-root}
target=${3:-}

# Run by bash on whichever machine the repository is on, with the root as $1.
body='
hold() { read -rsn1 -p $'"'"'\n\033[2mPress any key to close...\033[0m'"'"' _ || true; }
fail() { printf "\n\033[31m%s\033[0m\n" "$1"; hold; exit 1; }
cd "$1" || { hold; exit 1; }

current=$(git branch --show-current)
[ -n "$current" ] || fail "detached HEAD: no branch to merge"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  git -c color.status=always status --short --untracked-files=no
  fail "uncommitted changes: commit or stash them first"
fi

into=$(git for-each-ref --format="%(refname:short)" refs/heads refs/remotes/origin \
  | grep -v -e "^origin$" -e "/HEAD$" \
  | sed "s#^origin/##" | sort -u | grep -vxF -- "$current" \
  | fzf --prompt="merge $current into > " --height=100% --reverse) || exit 0
[ -n "$into" ] || exit 0

printf "merge  \033[1m%s\033[0m\n" "$current"
printf "into   \033[1m%s\033[0m\n" "$into"
printf "\033[2mthen push %s to origin and return to %s\033[0m\n\n" "$into" "$current"
printf "\033[1my\033[0m  merge\n"
printf "\033[2many other key  close\033[0m\n"
read -rsn1 answer || answer=""
[ "$answer" = "y" ] || exit 0
printf "\n"

back() { git checkout --quiet "$current" || printf "\033[31mcould not return to %s\033[0m\n" "$current"; }
git checkout "$into" || fail "could not check out $into"
if git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" >/dev/null 2>&1; then
  git pull --ff-only || { back; fail "$into cannot fast-forward to its upstream"; }
fi
if ! git merge --no-edit "$current"; then
  git merge --abort 2>/dev/null || true
  back
  fail "merge failed and was aborted: $into is unchanged"
fi
if ! git push --set-upstream origin "$into"; then
  back
  fail "merged locally, but the push failed"
fi
back
printf "\n\033[32mmerged %s into %s and pushed\033[0m\n" "$current" "$into"
hold

nudge="$HOME/.modules/tmux/scripts/Request-RadarSample.sh"
if [ -n "${REMOTE_ROW:-}" ] && [ -x "$nudge" ]; then
  "$nudge" git-radar >/dev/null 2>&1 || true
fi
'

printf '\033[1mmerge\033[0m  %s\n' "$session"
printf '\033[2m%s%s\033[0m\n\n' "${target:+$target:}" "$root"

if [ -z "$target" ]; then
  exec bash -c "$body" bash "$root"
fi

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../tmux/scripts/ssh-helpers.sh"
# The host's own sampler is nudged afterwards, as Show-GitCommit.sh does.
exec "$REMOTE_SSH" "${SSH_OPTS[@]}" -q -t "$target" \
  "env REMOTE_ROW=1 bash -c $(sq "$body") bash $(sq "$root")"
