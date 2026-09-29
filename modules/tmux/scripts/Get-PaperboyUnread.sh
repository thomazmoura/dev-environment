#!/usr/bin/env bash
# The Paperboy segment of the status bar: the inbox unread count that
# paperboy.nvim's daemon (bin/paperboy-unread, started on prefix+M by
# Start-PaperboyUnread.sh) writes to $XDG_RUNTIME_DIR/paperboy/unread every
# minute. The file holds the count, "!" after a failed request or "🔒" once
# Exchange rejected the password, and is gone while the daemon is not running,
# which shows an orange envelope with a lock: prefix+M still has to be pressed.
#
# Only bash builtins: tmux runs this on every status refresh, so reading the
# file must not cost a process of its own (no cat).

file="${XDG_RUNTIME_DIR:-/run/user/$UID}/paperboy/unread"

if [ ! -e "$file" ]; then
  printf '#[fg=#fab387]󰇮 󰌾#[fg=default] '
  exit 0
fi
read -r count <"$file" || [ -n "$count" ] || exit 0

case "$count" in
  # A dark green check when the inbox is read, red with the count when it is
  # not, and red for "!" and "🔒" as well
  0) printf '#[fg=#40a02b]󰇯 󰄬#[fg=default] ' ;;
  *) printf '#[fg=#f38ba8]󰇮 %s#[fg=default] ' "$count" ;;
esac
