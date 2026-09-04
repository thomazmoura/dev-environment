#!/usr/bin/env bash
# Runs a picker inside a tmux popup with SpotlightDimmer's spotlight following
# the popup. Every popup binding in modules/tmux/common.conf goes through here,
# via the `popup` command alias defined in that file.
#
# Usage, as the shell-command of a display-popup binding:
#   bind / popup '$HOME/.modules/tmux/scripts/Invoke-Popup.sh <script> [args...]'
#
# Why the wrapper exists: tmux fires no hook for display-popup, and a popup is
# an overlay rather than a pane, so #{pane_*} keeps describing the pane
# underneath it. The spotlight would therefore stay on that pane and leave the
# popup sitting in the dimmed region. Only something running inside the popup
# can report its geometry, which is what SpotlightDimmer's helper does -- see
# its own header for how it recovers the geometry from `stty size`.
#
# The helper assumes a centred popup, which is why the alias spells out
# `-x C -y C` (tmux's own default) rather than leaving it implicit. Where
# SpotlightDimmer is not installed -- containers, a fresh host -- the picker
# still runs, undimmed.
set -euo pipefail

spotlight="$HOME/.config/SpotlightDimmer/tools/spotlight-dimmer-tmux-popup.sh"

if [ -x "$spotlight" ]; then
  exec "$spotlight" -- "$@"
fi
exec "$@"
