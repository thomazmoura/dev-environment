#!/usr/bin/env bash
# Re-reports the focused pane's geometry to SpotlightDimmer for every attached
# tmux client, each for its own tty.
#
# Usage: Sync-SpotlightClients.sh
#   Run from the client-active, client-detached and window-resized hooks (see
#   modules/tmux/common.conf).
#
# Why: SpotlightDimmer keeps one geometry report per tmux client tty, pushed by
# its own hooks (pane, layout, attach, resize, session change), each computed for
# the client tmux considers current -- the most recently active one. With a
# second client attached (Termux on the phone), tmux's `window-size latest`
# shrinks the windows to the phone while it is in use, and every report goes to
# the phone's tty. Coming back to the PC grows the windows again, when the PC
# client becomes active or the phone detaches, but none of SpotlightDimmer's
# hooked events fires for that: the PC's report stays on a rectangle that no
# longer matches any pane.
#
# Every client is reported, not only the current one, because each keeps its own
# report and a resize changes them all. A client without pixel cell sizes
# (Termux) makes the report exit on its own, and a report for a tty that no
# terminal on the desktop shows is ignored by the daemon.
#
# A silent no-op where SpotlightDimmer is not installed (containers, a fresh
# host). Never fails, so it never breaks the hook that runs it.
set -u

report="$HOME/.config/SpotlightDimmer/tools/spotlight-dimmer-tmux-report.sh"
[ -x "$report" ] || exit 0

tmux list-clients -F '#{client_tty}' 2>/dev/null | while read -r tty; do
  [ -n "$tty" ] && "$report" --client "$tty"
done

exit 0
