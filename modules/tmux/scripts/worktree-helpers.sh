#!/usr/bin/env bash
# Shared helpers for the git worktree bindings. Sourced, never run.
#
# prefix+t, w (New-Worktree.sh) creates a worktree, the session-closed hook
# (Close-WorktreeSession.sh) offers to remove it again, and prefix+t, W
# (Show-Worktrees.py) lists, opens and deletes them. All three need the same
# answers to the same questions -- where is the registry, which repository does
# this directory belong to, what is this worktree's session called -- so the
# answers live here.
#
# Worktrees are created as siblings of the repository they came from:
#
#   ~/code/foo                  the repository
#   ~/code/foo.worktrees/bar    worktree "bar", on branch "bar"
#
# which keeps them under ~/code, where prefix+/ already finds them.
#
# A worktree also has a *host*. Fired from an ssh session (prefix+N), the
# bindings work on the machine that session's panes are on: the repository, the
# worktree and its branch are all over there, and only the tmux session that
# opens on it is here. Every function below therefore takes a target -- the
# session's @ssh_target, `user@host` -- which is empty for a worktree on this
# machine, and every command that touches a worktree goes through wt_git,
# wt_test or wt_sh, which run it here or there accordingly.
#
# The registry stays here either way: it is the local tmux server that owns the
# sessions and fires the hooks, so it is the local machine that has to know
# which worktrees it opened, and where.
#
# Sourced by a caller that has already set its shell options; nothing here runs
# at source time except the registry path and sourcing ssh-helpers.sh, which is
# definitions too. Sourced here rather than relied upon from tmux-helpers.sh
# because Close-WorktreeSession.sh takes only this file, and the removal path
# needs SSH_OPTS and sq.

source "$(dirname "${BASH_SOURCE[0]}")/ssh-helpers.sh"

# One row per worktree created through prefix+t, w:
#
#   <worktree path> TAB <main repository root> [TAB <user@host>]
#
# The path is what the row is about; the repository is there so the manager can
# show "this repo's worktrees" without asking git about every row; the host is
# the ssh target the first two are on, left off entirely for a worktree on this
# machine -- which is what every row written before ssh sessions could have
# worktrees looks like, and they go on meaning exactly what they meant.
# Overridable so the scripts can be exercised against a scratch file.
WORKTREE_REGISTRY="${WORKTREE_REGISTRY:-$HOME/.worktrees}"

# --- Running where the worktree is -------------------------------------------
# The three of them take the target as their first argument, so a caller reads
# as "git, over there" rather than branching on the host itself.
#
# BatchMode unless WT_SSH_INTERACTIVE is set: the session-closed hook and the
# manager pane have nowhere to type a password, and an ssh that stops to ask in
# either of them would hang holding nothing. New-Worktree.sh runs in a popup,
# which does have a terminal, and sets it.
#
# An ssh that could not reach the host at all exits 255, and callers must treat
# that as "don't know" rather than as an answer -- the same convention
# remote_directory_matches documents in ssh-helpers.sh. A worktree whose host is
# asleep is not a worktree whose folder has gone.

# wt_sh <target> <script> [args...]
# Runs a POSIX shell <script> here, or on <target>, with [args...] as $1, $2...
# Under `sh -c` rather than the remote's login shell, as remote_directory_matches
# does: on a dev-environment remote that shell is pwsh. Quoted with sq for the
# same reason -- %q can produce bash-only $'...'.
wt_sh() {
  local target=$1 script=$2
  shift 2
  if [ -z "$target" ]; then
    sh -c "$script" sh "$@"
    return
  fi
  local line a
  line="sh -c $(sq "$script") sh"
  for a in "$@"; do line+=" $(sq "$a")"; done
  if [ -n "${WT_SSH_INTERACTIVE:-}" ]; then
    "$REMOTE_SSH" "${SSH_OPTS[@]}" "$target" "$line"
  else
    "$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$target" "$line" </dev/null
  fi
}

# wt_git <target> <git-args...>
# git, run where the worktree is.
wt_git() {
  local target=$1
  shift
  if [ -z "$target" ]; then
    git "$@"
    return
  fi
  local line="git" a
  for a in "$@"; do line+=" $(sq "$a")"; done
  wt_sh "$target" "$line"
}

# wt_test <target> <test-args...>
# `test`, run where the worktree is: wt_test "$target" -d "$path". 0 yes, 1 no,
# 255 could not ask.
wt_test() {
  local target=$1
  shift
  if [ -z "$target" ]; then
    test "$@"
    return
  fi
  local line="test" a
  for a in "$@"; do line+=" $(sq "$a")"; done
  wt_sh "$target" "$line"
}

# repo_root <dir> [target]
# The root of the *main* working tree of the repository <dir> belongs to, so a
# pane that is already inside a worktree resolves to the repository it came
# from rather than to itself. --git-common-dir is the shared .git directory in
# both cases; its parent is the main working tree. Prints nothing and fails when
# <dir> is not in a repository -- or, with a target, when the host could not be
# asked. dirname is left to run here: it is string work, not a question about
# the filesystem.
repo_root() {
  local common
  common="$(wt_git "${2:-}" -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ -n "$common" ] || return 1
  dirname "$common"
}

# session_name_for <dir> [repo] [target]
# The name a session opened on <dir> is given. Pass <repo> when <dir> is a
# linked worktree of it: the session is then named after both, <repo>_<dir>
# (dev-environment_fix-radar), so worktrees of different repositories do not
# collide and each sorts next to its repository's session. Pass <target> for a
# worktree on another machine, and the host goes in front the way
# New-SshSession.sh names its own sessions (workhorse-dev-environment_fix-radar)
# -- which is also what keeps a remote worktree apart from a local one of the
# same name, so that closing one never offers to remove the other.
#
# tmux session names cannot contain dots -- they are the separator in
# session:window.pane targets -- nor, in the host part, colons. Must stay in
# step with session_name in Show-Worktrees.py.
session_name_for() {
  local name host
  name="$(basename "$1")"
  [ -n "${2:-}" ] && name="$(basename "$2")_$name"
  name="$(printf '%s' "$name" | tr '.' '_')"
  if [ -n "${3:-}" ]; then
    host="$(printf '%s' "${3##*@}" | tr '.:' '__')"
    name="$host-$name"
  fi
  printf '%s\n' "$name"
}

# session_name_for_dir <dir>
# session_name_for, working out for itself whether <dir> is the root of a
# linked worktree -- for callers that only have a local directory. A
# subdirectory of a worktree, or the main working tree, is named after itself
# alone.
session_name_for_dir() {
  local toplevel repo
  toplevel="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)"
  repo="$(repo_root "$1")" || repo=""
  if [ -n "$toplevel" ] && [ "$toplevel" != "$repo" ] &&
     [ "$(cd "$1" && pwd -P)" = "$(cd "$toplevel" && pwd -P)" ]; then
    session_name_for "$1" "$repo"
  else
    session_name_for "$1"
  fi
}

# registry_add <path> <repo> [target]
# A local worktree is written with two fields, exactly as before: the host
# column exists only for the rows that have one.
registry_add() {
  local row
  row="$(printf '%s\t%s' "$1" "$2")"
  [ -n "${3:-}" ] && row="$(printf '%s\t%s' "$row" "$3")"
  touch "$WORKTREE_REGISTRY"
  grep -qxF -- "$row" "$WORKTREE_REGISTRY" || printf '%s\n' "$row" >> "$WORKTREE_REGISTRY"
}

# registry_remove <path>
# Drops every row whose first field is exactly <path>. Through a temp file and a
# rename, so a hook and the manager removing rows at the same moment cannot
# leave a half-written registry behind.
registry_remove() {
  [ -f "$WORKTREE_REGISTRY" ] || return 0
  local tmp
  tmp="$(mktemp "$WORKTREE_REGISTRY.XXXXXX")" || return 1
  awk -F '\t' -v path="$1" '$1 != path' "$WORKTREE_REGISTRY" > "$tmp" && mv "$tmp" "$WORKTREE_REGISTRY"
}

# registry_repo <path>
# The repository recorded for <path>, or nothing if it is not registered.
registry_repo() {
  [ -f "$WORKTREE_REGISTRY" ] || return 0
  awk -F '\t' -v path="$1" '$1 == path { print $2; exit }' "$WORKTREE_REGISTRY"
}

# registry_target <path>
# The host recorded for <path>: nothing for a worktree on this machine, which
# is also what an unregistered path and a row written before the column existed
# give back.
registry_target() {
  [ -f "$WORKTREE_REGISTRY" ] || return 0
  awk -F '\t' -v path="$1" '$1 == path { print $3; exit }' "$WORKTREE_REGISTRY"
}

# registry_paths_for_session <session>
# Every registered worktree whose session would be called <session>. Usually
# none -- this is what every closing session is checked against -- and at most
# one unless two repositories share a name and a worktree name. The host is part
# of the name, so a remote worktree only ever matches its own session.
registry_paths_for_session() {
  [ -f "$WORKTREE_REGISTRY" ] || return 0
  local path repo target
  while IFS=$'\t' read -r path repo target; do
    [ -n "$path" ] || continue
    [ "$(session_name_for "$path" "$repo" "$target")" = "$1" ] && printf '%s\n' "$path"
  done < "$WORKTREE_REGISTRY"
}

# worktree_state <path> [target]
# What shape the worktree is in, in one word and -- for a remote one -- one
# round trip:
#
#   missing      the folder is not there any more
#   dirty        staged, unstaged or untracked changes. Untracked files count:
#                they are exactly the kind of work `git worktree remove --force`
#                would lose
#   clean        nothing to lose
#   unknown      the folder is there but git would not answer about it
#   unreachable  the host could not be asked, so none of the above is known
#
# The distinction between missing and unreachable is the point of this
# function: a host that is asleep must never be read as a folder that has gone,
# or closing a session would quietly prune a worktree that is still there.
# unknown is the state the old worktree_is_clean reported by failing -- a path
# that is not a repository at all -- and, like dirty, it is a reason to keep a
# worktree rather than to remove it.
worktree_state() {
  local target=${2:-} answer status=0
  answer="$(wt_sh "$target" '
[ -d "$1" ] || { echo missing; exit 0; }
changes="$(git -C "$1" status --porcelain 2>/dev/null)" || { echo unknown; exit 0; }
[ -n "$changes" ] && echo dirty || echo clean' "$1" 2>/dev/null)" || status=$?
  if [ "$status" -ne 0 ] || [ -z "$answer" ]; then
    # Only ssh can leave us with nothing to say; locally sh always answers.
    [ -n "$target" ] && { printf 'unreachable\n'; return 0; }
    printf 'unknown\n'
    return 0
  fi
  printf '%s\n' "$answer"
}

# worktree_branch <path> [target]
# The branch checked out in <path>, or nothing when HEAD is detached.
worktree_branch() {
  wt_git "${2:-}" -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null
}

# remove_worktree <path> [force] [target]
# Removes a worktree and everything that points at it, printing one line per
# thing it did. In this order:
#
#   1. The registry row. First, because killing the session at the end fires
#      the session-closed hook, and the hook must find nothing left to ask
#      about.
#   2. `git worktree remove`, which refuses a dirty worktree unless forced.
#   3. The branch, with -d: git deletes it only when it is merged, so commits
#      that exist nowhere else are never lost. An unmerged branch is kept and
#      reported.
#   4. The <repo>.worktrees folder, once it is empty.
#   5. The worktree's session, if one is open -- a session sitting in a
#      directory that no longer exists is only a trap. Last, because the caller
#      may be running *in* that session (the manager pane, opened inside the
#      worktree's own session), and killing it takes the caller with it.
#
# Steps 2 to 4 happen on the worktree's host; step 5 is always here, because the
# session is ours and only its panes are on the remote.
#
# <target> defaults to the host the registry recorded, so the callers that work
# from a registry row need not pass one; the manager passes it for a worktree it
# found through git rather than through the registry.
#
# A worktree whose folder has already gone is pruned instead of removed. A
# worktree whose *host* could not be reached is left entirely alone: nothing is
# known about it, and the registry row stays so it can be dealt with later.
remove_worktree() {
  local path=$1 force=${2:-} target=${3:-}
  local repo branch session registered state

  [ -n "$target" ] || target="$(registry_target "$path")"

  state="$(worktree_state "$path" "$target")"
  if [ "$state" = unreachable ]; then
    echo "could not reach ${target##*@}; nothing was removed"
    return 1
  fi

  repo="$(registry_repo "$path")"
  registered="$repo"
  [ -n "$repo" ] || repo="$(repo_root "$path" "$target")" || true
  branch=""
  [ "$state" != missing ] && branch="$(worktree_branch "$path" "$target")"

  registry_remove "$path"

  if [ -z "$repo" ]; then
    echo "no repository found for $path; only the registry row was removed"
  elif [ "$state" = missing ]; then
    wt_git "$target" -C "$repo" worktree prune && echo "pruned missing worktree $(basename "$path")"
  else
    if ! remove_worktree_folder "$path" "$repo" "$branch" "$force" "$target"; then
      # Put the row back: the worktree is still there, and dropping it from
      # the registry would make the manager's all-repositories view forget it.
      [ -n "$registered" ] && registry_add "$path" "$repo" "$target"
      return 1
    fi
  fi

  session="$(session_name_for "$path" "$repo" "$target")"
  if tmux has-session -t "=$session" 2>/dev/null; then
    echo "killed session $session"
    tmux kill-session -t "=$session" 2>/dev/null
  fi
  return 0
}

# remove_worktree_folder <path> <repo> <branch> [force] [target]
# Steps 2-4 of remove_worktree, on the worktree's host.
remove_worktree_folder() {
  local path=$1 repo=$2 branch=$3 force=${4:-} target=${5:-}

  local args=(worktree remove)
  [ -n "$force" ] && args+=(--force)
  wt_git "$target" -C "$repo" "${args[@]}" "$path" 2>&1 || return 1
  echo "removed worktree $(basename "$path")"

  if [ -n "$branch" ]; then
    if wt_git "$target" -C "$repo" branch -d "$branch" >/dev/null 2>&1; then
      echo "deleted branch $branch"
    else
      echo "branch $branch kept (not merged)"
    fi
  fi

  # Only our own container folder: a worktree made some other way (Claude's
  # .claude/worktrees, say) sits in a folder that is not ours to tidy.
  case "$(dirname "$path")" in
    *.worktrees) wt_sh "$target" 'rmdir "$1" 2>/dev/null || true' "$(dirname "$path")" ;;
  esac
}
