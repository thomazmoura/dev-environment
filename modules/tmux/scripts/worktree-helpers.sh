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
# which keeps them under ~/code, where prefix+C-n already finds them.
#
# Sourced by a caller that has already set its shell options; nothing here runs
# at source time except the registry path.

# One row per worktree created through prefix+t, w:
#
#   <worktree path> TAB <main repository root>
#
# The path is what the row is about; the repository is there so the manager can
# show "this repo's worktrees" without asking git about every row. Overridable
# so the scripts can be exercised against a scratch file.
WORKTREE_REGISTRY="${WORKTREE_REGISTRY:-$HOME/.worktrees}"

# repo_root <dir>
# The root of the *main* working tree of the repository <dir> belongs to, so a
# pane that is already inside a worktree resolves to the repository it came
# from rather than to itself. --git-common-dir is the shared .git directory in
# both cases; its parent is the main working tree. Prints nothing and fails when
# <dir> is not in a repository.
repo_root() {
  local common
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ -n "$common" ] || return 1
  dirname "$common"
}

# session_name_for <dir> [repo]
# The name New-CodeSession.sh gives a session opened on <dir>. Pass <repo> when
# <dir> is a linked worktree of it: the session is then named after both,
# <repo>_<dir> (dev-environment_fix-radar), so worktrees of different
# repositories do not collide and each sorts next to its repository's session.
# tmux session names cannot contain dots -- they are the separator in
# session:window.pane targets. Must stay in step with session_name in
# Show-Worktrees.py.
session_name_for() {
  local name
  name="$(basename "$1")"
  [ -n "${2:-}" ] && name="$(basename "$2")_$name"
  printf '%s\n' "$name" | tr '.' '_'
}

# session_name_for_dir <dir>
# session_name_for, working out for itself whether <dir> is the root of a
# linked worktree -- for callers that only have a directory. A subdirectory of
# a worktree, or the main working tree, is named after itself alone.
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

# registry_add <path> <repo>
registry_add() {
  local row
  row="$(printf '%s\t%s' "$1" "$2")"
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

# registry_paths_for_session <session>
# Every registered worktree whose session would be called <session>. Usually
# none -- this is what every closing session is checked against -- and at most
# one unless two repositories share a name and a worktree name.
registry_paths_for_session() {
  [ -f "$WORKTREE_REGISTRY" ] || return 0
  local path repo
  while IFS=$'\t' read -r path repo; do
    [ -n "$path" ] || continue
    [ "$(session_name_for "$path" "$repo")" = "$1" ] && printf '%s\n' "$path"
  done < "$WORKTREE_REGISTRY"
}

# worktree_is_clean <path>
# No staged, unstaged or untracked changes. Untracked files count: they are
# exactly the kind of work that `git worktree remove --force` would lose.
worktree_is_clean() {
  local status
  status="$(git -C "$1" status --porcelain 2>/dev/null)" || return 1
  [ -z "$status" ]
}

# worktree_branch <path>
# The branch checked out in <path>, or nothing when HEAD is detached.
worktree_branch() {
  git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null
}

# remove_worktree <path> [force]
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
# A worktree whose folder has already gone is pruned instead of removed.
remove_worktree() {
  local path=$1 force=${2:-}
  local repo branch session registered

  repo="$(registry_repo "$path")"
  registered="$repo"
  [ -n "$repo" ] || repo="$(repo_root "$path")" || true
  branch=""
  [ -d "$path" ] && branch="$(worktree_branch "$path")"

  registry_remove "$path"

  if [ -z "$repo" ]; then
    echo "no repository found for $path; only the registry row was removed"
  elif [ ! -d "$path" ]; then
    git -C "$repo" worktree prune && echo "pruned missing worktree $(basename "$path")"
  else
    if ! remove_worktree_folder "$path" "$repo" "$branch" "$force"; then
      # Put the row back: the worktree is still there, and dropping it from
      # the registry would make the manager's all-repositories view forget it.
      [ -n "$registered" ] && registry_add "$path" "$repo"
      return 1
    fi
  fi

  session="$(session_name_for "$path" "$repo")"
  if tmux has-session -t "=$session" 2>/dev/null; then
    echo "killed session $session"
    tmux kill-session -t "=$session" 2>/dev/null
  fi
  return 0
}

# remove_worktree_folder <path> <repo> <branch> [force]
# Steps 2-4 of remove_worktree.
remove_worktree_folder() {
  local path=$1 repo=$2 branch=$3 force=${4:-}

  local args=(worktree remove)
  [ -n "$force" ] && args+=(--force)
  git -C "$repo" "${args[@]}" "$path" 2>&1 || return 1
  echo "removed worktree $(basename "$path")"

  if [ -n "$branch" ]; then
    if git -C "$repo" branch -d "$branch" >/dev/null 2>&1; then
      echo "deleted branch $branch"
    else
      echo "branch $branch kept (not merged)"
    fi
  fi

  # Only our own container folder: a worktree made some other way (Claude's
  # .claude/worktrees, say) sits in a folder that is not ours to tidy.
  case "$(dirname "$path")" in
    *.worktrees) rmdir "$(dirname "$path")" 2>/dev/null || true ;;
  esac
}
