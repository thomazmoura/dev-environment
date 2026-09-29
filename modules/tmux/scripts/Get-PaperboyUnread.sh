#!/usr/bin/env bash
# The Paperboy segment of the status bar: the inbox unread count that
# paperboy.nvim's daemon (bin/paperboy-unread, started on prefix+M by
# Start-PaperboyUnread.sh) writes to $XDG_RUNTIME_DIR/paperboy/unread every
# minute. The file holds the count, "!" after a failed request or "🔒" once
# Exchange rejected the password, and is gone while the daemon is not running,
# which hides the segment.
#
# Only bash builtins: tmux runs this on every status refresh, so reading the
# file must not cost a process of its own (no cat).

file="${XDG_RUNTIME_DIR:-/run/user/$UID}/paperboy/unread"

[ -r "$file" ] || exit 0
read -r count <"$file" || [ -n "$count" ] || exit 0

case "$count" in
  # Same palette as the agent-radar segment next to it: dim when nothing is
  # unread, yellow when something is, red for "!" and "🔒"
  0) printf '#[fg=#6c7086]󰇯 0#[fg=default] ' ;;
  *[!0-9]*) printf '#[fg=#f38ba8]󰇮 %s#[fg=default] ' "$count" ;;
  *) printf '#[fg=#f9e2af]󰇮 %s#[fg=default] ' "$count" ;;
esac
