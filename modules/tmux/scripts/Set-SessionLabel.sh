#!/usr/bin/env bash
# Gives a tmux session a name of your own, shown in place of its real one -- in
# the status bar, the Git and Agents panes, the session, pane and agent pickers
# and agent notifications -- and kept across tmux servers the way
# Set-HomeSession.sh keeps the home mark.
#
# Usage: Set-SessionLabel.sh [session]       ask for <session>'s name, the
#                                            current session when left out
#                                            (prefix+$, and n in the Git pane)
#        Set-SessionLabel.sh -s              put the names back on every open
#                                            session (session-created and
#                                            session-renamed hooks, config load)
#        Set-SessionLabel.sh -l <target> <root>
#                                            the named entries for a picker:
#                                            the local ones when <target> is
#                                            empty (prefix+/), else those on
#                                            <target>'s host (prefix+N)
#
# The name is only a label. The session keeps its real name -- <folder>, or
# <host>-<folder> over ssh -- which is what every lookup (has-session, the home
# mark, worktrees, Rename-SshSessions.sh) goes by, so none of them had to learn
# about labels. Displays show #{@session_label} when it is set, the name
# otherwise.
#
# The names are kept in a file, one line per session, keyed by the session's
# name without the user@ that ssh_session_name may put in front of it (see
# ssh-helpers.sh): apollo-dev-environment, whoever is logged in. Each line is
#
#   <key> TAB <label> TAB <ssh target, empty for a local session> TAB <directory>
#
# The target and directory are there for -l: they let prefix+/ and prefix+N
# offer a named session that is not open, and open it under its key again.
#
# tmux reads the label from the session option @session_label, which -s copies
# out of the file. Formats (the status bar) and the radar samplers, which list
# sessions and panes anyway, get it from there at no extra cost.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"

file="${XDG_CACHE_HOME:-$HOME/.cache}/tmux/session-names"

# sync_labels
# Sets @session_label on each open session from the file, and takes it off the
# ones the file has no name for. Only where it differs: the hooks run this on
# every session opened or renamed, and an unchanged option costs a tmux call for
# nothing.
sync_labels() {
  local -A labels=()
  local key label id name have want
  if [ -f "$file" ]; then
    while IFS=$'\t' read -r key label _; do
      [ -n "$key" ] && [ -n "$label" ] && labels[$key]="$label"
    done <"$file"
  fi
  while IFS=$'\t' read -r id name have; do
    [ -n "$id" ] || continue
    key="${name#*@}"
    want="${labels[$key]-}"
    [ "$want" = "$have" ] && continue
    if [ -n "$want" ]; then
      tmux set-option -t "$id" @session_label "$want" 2>/dev/null
    else
      tmux set-option -u -t "$id" @session_label 2>/dev/null
    fi
  done < <(tmux list-sessions -F $'#{session_id}\t#{session_name}\t#{@session_label}' 2>/dev/null)
  return 0
}

# list_named <target> <root>
# The picker lines, `★ <label>  <directory>`, with the directory and the key
# after tabs for the picker to read back -- fzf shows only the first field
# (--with-nth=1). The directory is shown relative to <root>, the folder the
# picker lists. Hosts are compared without the user, as the key is.
list_named() {
  [ -f "$file" ] || return 0
  awk -F '\t' -v target="$1" -v root="$2" '
    function host(t) { sub(/^[^@]*@/, "", t); return t }
    $1 == "" || $2 == "" || $4 == "" { next }
    target == "" && $3 != "" { next }
    target != "" && ($3 == "" || host($3) != host(target)) { next }
    {
      shown = $4
      if (index(shown, root "/") == 1) shown = substr(shown, length(root) + 2)
      printf "★ %s  %s\t%s\t%s\n", $2, shown, $4, $1
    }' "$file"
}

case "${1:-}" in
  -s) sync_labels; exit 0 ;;
  -l) list_named "${2:-}" "${3:-}"; exit 0 ;;
esac

session="${1:-$(tmux display-message -p '#{session_name}')}"
tmux has-session -t "=$session" 2>/dev/null || die "No session called $session"

key="${session#*@}"
current="$(awk -F '\t' -v key="$key" '$1 == key { print $2; exit }' "$file" 2>/dev/null)"

printf 'Name for %s\n(empty for its own name again, Ctrl+C to leave it)\n\n' "$key"
read -re -i "$current" -p 'name: ' label || exit 0
# Tabs are the file's separator; surrounding blanks are never meant.
label="$(printf '%s' "$label" | tr '\t' ' ' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
[ "$label" = "$current" ] && exit 0

# Where the session is, for list_named: the remote directory of an ssh or
# Docker session, the session's own path for a local one.
target="$(tmux display-message -p -t "=$session:" '#{@ssh_target}')"
if [ -n "$target" ]; then
  dir="$(tmux display-message -p -t "=$session:" '#{@ssh_dir}')"
else
  dir="$(tmux display-message -p -t "=$session:" '#{session_path}')"
fi

# Written whole and moved into place, so a reader never sees half a file.
mkdir -p "$(dirname "$file")"
{
  if [ -f "$file" ]; then awk -F '\t' -v key="$key" '$1 != key' "$file"; fi
  if [ -n "$label" ]; then printf '%s\t%s\t%s\t%s\n' "$key" "$label" "$target" "$dir"; fi
} >"$file.tmp" && mv "$file.tmp" "$file" || die "Could not save the name to $file"

sync_labels

# The status bar would pick the label up at its next interval; every client
# redraws it now. The feeds show it on their sampler's next publication, which
# this asks for now rather than at the end of its tick.
while IFS= read -r client; do
  tmux refresh-client -S -t "$client" 2>/dev/null
done < <(tmux list-clients -F '#{client_name}' 2>/dev/null)
"$scripts/Request-RadarSample.sh" git-radar agent-radar
exit 0
