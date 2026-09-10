#!/usr/bin/env bash
# Asks the radar samplers to publish now instead of at the end of their tick.
#
# Usage: Request-RadarSample.sh [radar...]      (default: every radar)
#   Run from the pane-exited, pane-died and session-closed hooks (see
#   modules/tmux/common.conf). Takes no arguments there: what happened does not
#   matter, only that the world just changed in a way the next sample will see.
#
# It is a `touch` and deliberately nothing more -- each sampler polls the file's
# mtime while it sleeps, and nobody has to be listening. radar_cache.nudge_path
# has the rest of the reasoning.
#
# The path is built here rather than asked of radar_cache.cache_root, because
# starting a Python interpreter to learn the name of a directory would cost more
# than everything this script does. The two must agree; there is one test of
# that in each radar's README.
set -uo pipefail

radars=("$@")
[ ${#radars[@]} -gt 0 ] || radars=(agent-radar git-radar)

root="${XDG_CACHE_HOME:-$HOME/.cache}"

# A hook has nobody to report failure to, so every step here fails quietly: one
# radar's cache being unwritable must not stop the other being told.
for radar in "${radars[@]}"; do
  mkdir -p "$root/$radar" 2>/dev/null || continue
  touch "$root/$radar/resample" 2>/dev/null || continue
done

exit 0
