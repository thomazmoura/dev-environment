#!/bin/sh
# What `p` in the Git pane runs: fetch, then fast-forward -- or, when the branch
# has commits of its own as well as commits to pull, rebase them onto the
# upstream, but only once it is known that the rebase applies cleanly.
#
# Never run from this file. Watch-GitFeed.pull_argv (and Show-GitFailure.sh's
# retry) hand its text to git as a one-off `!` alias, `git -c alias.radar-pull=
# '!<this>' radar-pull`, so the same command line works in a local repository and
# in a remote row's over ssh -- where this checkout may be older, or absent. It
# therefore has to stay POSIX sh, and runs at the top of the work tree. Like any
# of the pane's commands it has no tty and no way to prompt: a refusal's first
# line on stderr is what the row says, and the rest is for the failure popup.
#
# The rebase is the one thing here that rewrites anything, so it is fenced:
#   - a dirty tree is refused (the replay would have nowhere to put it);
#   - local merge commits are refused (a rebase would flatten them);
#   - every local commit is first replayed in memory with `git merge-tree`,
#     which touches neither the work tree nor any ref, and one conflict is
#     enough to refuse the whole thing;
#   - and the real rebase is aborted if it stops anyway, so the branch is left
#     exactly where it was rather than mid-rebase.
# A git too old for `merge-tree --write-tree --merge-base` (before 2.40) skips
# the in-memory check and relies on the last fence alone.

fail() { printf '%s\n' "$@" >&2; exit 1; }

git fetch --quiet || exit

# Nothing to pull: the upstream is already in this branch.
git merge-base --is-ancestor '@{u}' HEAD && exit 0

# Nothing of our own: the old `pull --ff-only`.
if git merge-base --is-ancestor HEAD '@{u}'; then
  exec git merge --ff-only --quiet '@{u}'
fi

# Diverged.
git update-index -q --refresh
git diff-index --quiet HEAD -- || fail "cannot rebase: uncommitted changes" \
  "The branch has diverged from its upstream, so p would rebase it -- but not" \
  "over uncommitted changes. Commit or stash them first."
[ -z "$(git rev-list --merges '@{u}..HEAD')" ] || fail "cannot rebase: local merges" \
  "The branch has diverged from its upstream, and rebasing would flatten the" \
  "merge commits among its own. Pull it by hand."

tree=$(git rev-parse '@{u}^{tree}')
for commit in $(git rev-list --reverse '@{u}..HEAD'); do
  tree=$(git merge-tree --write-tree --name-only --merge-base="$commit^" "$tree" "$commit")
  case $? in
    0) ;;
    1)
      fail "rebase would conflict" \
        "Replaying $(git log -1 --format='%h %s' "$commit") onto the upstream conflicts in:" \
        "$(printf '%s\n' "$tree" | sed -n '2,/^$/p')" \
        "Nothing was changed. Rebase or merge it by hand."
      ;;
    *) break ;;
  esac
done

if ! out=$(git rebase --quiet '@{u}' 2>&1); then
  git rebase --abort >/dev/null 2>&1
  fail "rebase failed and was aborted" "$out"
fi
