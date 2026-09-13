#!/usr/bin/env bash
# Opens a session for a project under ~/code, with the standard NeoVim layout.
#
# Usage: New-CodeSession.sh [directory]
#   no argument - fuzzy-find a directory under ~/code (bound to prefix+C-n)
#   directory   - use that directory directly (bound to prefix+C-c for ~/code)
#
# Bound as popup commands in modules/tmux/common.conf. The session is created
# detached and then switched to, rather than with `new-session` attached,
# because this runs inside a popup: the popup owns the terminal until it
# closes, so the client has to be moved with switch-client the way
# Select-Pane.sh does.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"
source "$scripts/worktree-helpers.sh"

code="$HOME/code"

directory="${1:-}"
if [ -z "$directory" ]; then
  require_tools tmux fzf fd
  location="$(fd --type d . --base-directory "$code" | fzf --reverse --prompt='project> ' --header='New session from ~/code')" || exit 0
  [ -n "$location" ] || exit 0
  directory="$code/$location"
fi

[ -d "$directory" ] || die "Not a directory: $directory"

# tmux session names cannot contain dots -- they are the separator in
# session:window.pane targets -- so a directory like Foo.Bar.Api becomes
# Foo_Bar_Api. A git worktree is prefixed with its repository's name
# (session_name_for in worktree-helpers.sh).
name="$(session_name_for_dir "$directory")"

# Re-running the binding for a project that is already open should take you
# there instead of failing on the duplicate name.
if ! tmux has-session -t "=$name" 2>/dev/null; then
  tmux new-session -s "$name" -d -c "$directory" || die "Could not create session $name"
  layout="yes"
fi

tmux switch-client -t "=$name"
[ -n "${layout:-}" ] && "$scripts/Set-NeovimLayout.sh" "$name:"
exit 0
