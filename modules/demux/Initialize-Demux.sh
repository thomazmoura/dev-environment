#!/usr/bin/env bash
# Bootstraps demux inside the running tmux server. Everything here is idempotent
# and safe to repeat on every invocation. Three jobs:
#
# 1. Registering demux's tmux hooks, which is what makes the sticky sidebar
#    follow you between sessions.
# 2. Prepending demux's state summary to status-right. Deferred to here rather
#    than done in tmux.conf because TPM loads tmux-power asynchronously, and
#    tmux-power's own `set -g status-right` lands after the config file finishes
#    sourcing, clobbering anything the config prepended.
# 3. Registering its own client-attached hook, so this keeps running on every
#    attach without tmux.conf having to do it.
#
# Invoked from tmux.conf at load, from the client-attached hook it installs, and
# from the `prefix + e` binding. That last path is what makes it robust: tmux
# hooks are arrays, and `set-hook -g` ASSIGNS the array (dropping other tools'
# entries) where `set-hook -ag` appends. ~/.tmux.conf sources SpotlightDimmer's
# tmux integration, and anything sourced after this file that assigns
# client-attached silently drops demux's registration. Re-running from the
# binding self-heals that whatever the source order turns out to be.
#
set -euo pipefail

DEMUX="$HOME/.local/bin/demux"
SELF="$HOME/.modules/demux/Initialize-Demux.sh"
[ -x "$DEMUX" ] || exit 0

# Register on client-attached, appending so other tools' hooks on the same event
# survive. Probe first: -ag appends unconditionally, so re-sourcing tmux.conf
# would otherwise stack up a duplicate every time — and TPM re-sources
# ~/.tmux.conf itself, so that happens without any manual reload.
if ! tmux show-hooks -g 2>/dev/null | grep -qF "$SELF"; then
  tmux set-hook -ag client-attached "run-shell -b '$SELF'"
fi

# `demux hooks install` is what actually registers demux's full 9-hook set,
# including the client-session-changed hook that moves the sidebar pane when you
# switch sessions. The bare `demux event client_attached` bootstrap the README
# documents registers only 4 of them and leaves the sidebar stranded in the
# session where it was opened. It also writes demux's one-line managed block to
# ~/.tmux.conf the first time.
#
# It assigns client-attached with `set-hook -g` though, dropping whatever else
# was registered there (SpotlightDimmer's pane-geometry reporter, for one), so
# snapshot the event first and re-append anything the installer displaced.
# Tool-agnostic on purpose: it restores what was there, not a hard-coded list.
before="$(tmux show-options -g client-attached 2>/dev/null | sed 's/^client-attached\[[0-9]*\] //')"

"$DEMUX" hooks install --tool tmux >/dev/null 2>&1 || true

printf '%s\n' "$before" | while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  # tmux quotes values that contain shell metacharacters; strip that layer so
  # the value is re-appended exactly as it was originally set.
  case "$entry" in '"'*'"') entry=${entry#\"}; entry=${entry%\"} ;; esac
  tmux show-options -g client-attached 2>/dev/null | grep -qF -- "$entry" \
    || tmux set-hook -ag client-attached "$entry"
done

# Probe status-right for the marker rather than tracking a "did I add it?" flag:
# re-sourcing tmux.conf makes TPM reload tmux-power, which overwrites
# status-right wholesale, and a flag would then wrongly report it as present.
current="$(tmux show -gqv status-right)"
case "$current" in
  *"demux status"*) ;;
  *)
    # The literal '#(...)' must survive into the option value so tmux re-runs it
    # on every status refresh; it must not be expanded here.
    tmux set -g status-right "#($DEMUX status) $current"
    ;;
esac
