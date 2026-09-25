#!/usr/bin/env bash
# Copies tmux's own prefix bindings into the `native` key table, which
# prefix+C-b switches to (see modules/tmux/common.conf).
#
# Usage: Set-NativeKeyTable.sh
#   Run from common.conf with run-shell -b: it calls back into tmux, and a
#   blocking run-shell would hold the server while it does.
#
# common.conf empties the prefix table so it holds only the custom bindings;
# this puts every default back one key further away, including the ones the
# custom set overrides (clock on t, windows on 0-9, the layout presets...).
#
# The defaults are read off a throwaway server started with no config rather
# than kept in a file here, so the table always matches the installed tmux --
# 3.4 on Ubuntu 24.04, 3.5a in the Debian image, newer elsewhere -- and the long
# display-menu definitions behind < and > never have to be copied by hand. A
# server with no session exits as soon as its commands are done.
#
# list-keys prints the bindings without their notes, and list-keys -N only the
# notes, one line per key in the same order; the two are joined back together
# here so prefix+C-b ? can list the native table as well. A line whose key
# does not match is bound without a note rather than with the wrong one.
set -uo pipefail

probe() { tmux -L "native-probe-$$" -f /dev/null start-server \; "$@"; }

bindings=$(probe list-keys -T prefix) || exit 1
notes=$(probe list-keys -N -T prefix) || exit 1

conf=$(mktemp "${TMPDIR:-/tmp}/tmux-native-keys.XXXXXX") || exit 1
trap 'rm -f "$conf"' EXIT

{
  echo 'unbind-key -a -T native'
  paste -d '\n' <(printf '%s\n' "$bindings") <(printf '%s\n' "$notes") | awk '
    NR % 2 == 1 { binding = $0; next }
    {
      # binding: bind-key [-r] -T prefix <escaped key> <command...>
      # note:    <key> <spaces> <note>
      if (!match(binding, /^bind-key +(-r +)?-T prefix +/)) next
      head = substr(binding, 1, RLENGTH); rest = substr(binding, RLENGTH + 1)
      key = rest; sub(/ .*/, "", key)
      bare = key; sub(/^\\/, "", bare)

      note_key = $0; sub(/ .*/, "", note_key)
      note = $0; sub(/^[^ ]+ +/, "", note)

      sub(/-T prefix +$/, "-T native ", head)
      if (note_key == bare) {
        gsub(/\\/, "\\\\", note); gsub(/"/, "\\\"", note); gsub(/\$/, "\\$", note)
        head = head "-N \"" note "\" "
      }
      print head rest
    }'
} > "$conf"

# Then the few bindings that replace a default there (native-overrides.conf).
tmux source-file "$conf" \; source-file "$(dirname "$0")/../native-overrides.conf"
