#!/usr/bin/env bash
# Paints the panes with opaque backgrounds when the client arriving is Termux,
# and gives them back to the terminal when it is anything else.
#
# Usage: Set-PaneBackground.sh <client_pid>
#   Run from the client-attached and client-session-changed hooks (see
#   modules/tmux/common.conf) with the pid of the tmux client that arrived.
#
# Why: on the PC, Ghostty and WezTerm draw a background image and
# SpotlightDimmer dims the panes that are not focused, so tmux and NeoVim stay
# transparent. Termux has neither, and there every pane looks the same unless
# tmux paints them itself.
#
# How the client is told apart: Termux can't be recognised from inside -- it
# sends the same TERM as WezTerm, and TERM_PROGRAM doesn't cross ssh -- so
# Termux sets a flag of its own in its ~/.ssh/config:
#
#   Host <this machine>
#     SetEnv LC_TERMINAL=Termux
#
# (LC_* passes the default `AcceptEnv LANG LC_*` of Ubuntu's and Debian's sshd.)
# The flag is read from the environment of the tmux client process itself, not
# from the session's: that one is only refreshed for update-environment's list,
# and would still say Termux after coming back to the PC.
#
# The styles are global, so every session follows the client that arrived last:
# PC -> phone -> PC goes transparent -> opaque -> transparent. The two looks are
# @pane_style_<mode> and @pane_active_style_<mode>, set in common.conf (and
# overridden in the Docker tmux.conf). @pane_background holds the mode for
# NeoVim, which reads it on focus (vim/lua/pane-background.lua).
set -uo pipefail

pid=${1:-}
[ -n "$pid" ] || exit 0

mode=transparent
if [ -r "/proc/$pid/environ" ] && tr '\0' '\n' < "/proc/$pid/environ" | grep -qx 'LC_TERMINAL=Termux'; then
  mode=opaque
fi

[ "$(tmux show-options -gqv @pane_background 2>/dev/null)" != "$mode" ] || exit 0

# One call, so the panes never show one style of one mode and one of the other.
# -F expands the option named in the format, which holds the style itself.
tmux set-option -g @pane_background "$mode" \; \
  set-option -gwF window-style "#{@pane_style_$mode}" \; \
  set-option -gwF window-active-style "#{@pane_active_style_$mode}"
