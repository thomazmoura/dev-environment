#!/usr/bin/env bash
# Opens a session for a project under ~/code, with the standard layout: Git,
# Agents and a picker pane (see Set-NeovimLayout.sh).
#
# Usage: New-CodeSession.sh [directory]
#        New-CodeSession.sh -d [-x columns -y rows] directory
#   no argument - fuzzy-find a directory under ~/code (bound to prefix+/). The
#                 sessions named with prefix+$ come first, as `★ <name>  <dir>`,
#                 open or not (Set-SessionLabel.sh -l). The first level of
#                 folders on each linked machine comes last, as <host>/<folder>
#                 (tmux_link.py, from the snapshot Start-TmuxLink.py keeps)
#   directory   - use that directory directly (bound to prefix+C-c for ~/code)
#   -d          - detached: open the session without switching to it and print
#                 its name. How a linked machine opens a session here, over
#                 ssh, for a folder picked there -- which then moves its client
#                 over (Switch-LinkSession.sh). -x and -y are that client's
#                 size, so the layout's splits land where they will be once it
#                 is attached, as New-SshSession.sh does outside tmux
#
# A folder on a linked machine is opened in that machine's tmux, by this script
# run there with -d, and the client is taken to it: nothing of it lives here.
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
source "$scripts/link-helpers.sh"

code="$HOME/code"

detached="" size=()
while getopts ":dx:y:" option; do
  case "$option" in
    d) detached="yes" ;;
    x) size+=(-x "$OPTARG") ;;
    y) size+=(-y "$OPTARG") ;;
    *) die "New-CodeSession.sh: unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

directory="${1:-}"
name=""
if [ -z "$directory" ]; then
  require_tools tmux fzf fd
  # A named line carries its directory and session name after tabs, which fzf
  # does not show (--with-nth=1); fd's lines have no tab and show whole. A
  # linked machine's folder carries three: identity, address and path.
  location="$({ "$scripts/Set-SessionLabel.sh" -l "" "$code"; fd --type d . --base-directory "$code";
      "$scripts/Get-TmuxLink.py" --format=folders 2>/dev/null; } |
    fzf --ansi --reverse --delimiter=$'\t' --with-nth=1 --prompt='project> ' --header='New session from ~/code')" || exit 0
  [ -n "$location" ] || exit 0
  case "$location" in
    *$'\t'*$'\t'*$'\t'*)
      IFS=$'\t' read -r _ identity address directory <<<"$location"
      open_on_peer "$identity" "$address" "$directory"
      exit 0 ;;
    *$'\t'*) IFS=$'\t' read -r _ directory name <<<"$location" ;;
    *) directory="$code/$location" ;;
  esac
fi

[ -d "$directory" ] || die "Not a directory: $directory"

# tmux session names cannot contain dots -- they are the separator in
# session:window.pane targets -- so a directory like Foo.Bar.Api becomes
# Foo_Bar_Api. A git worktree is prefixed with its repository's name
# (session_name_for in worktree-helpers.sh). A named entry brings the name its
# label is kept under, so the session opens as the one that was named.
[ -n "$name" ] || name="$(session_name_for_dir "$directory")"

# Re-running the binding for a project that is already open should take you
# there instead of failing on the duplicate name.
if ! tmux has-session -t "=$name" 2>/dev/null; then
  tmux new-session -s "$name" -d -c "$directory" "${size[@]}" || die "Could not create session $name"
  layout="yes"
fi

if [ -n "$detached" ]; then
  [ -n "${layout:-}" ] && "$scripts/Set-NeovimLayout.sh" -n "$name:" >/dev/null 2>&1
  printf '%s\n' "$name"
  exit 0
fi

tmux switch-client -t "=$name"
[ -n "${layout:-}" ] && "$scripts/Set-NeovimLayout.sh" -n "$name:"
exit 0
