#!/usr/bin/env bash
# Starts (or restarts/stops) paperboy.nvim's unread-count daemon, whose count
# Get-PaperboyUnread.sh shows in the status bar. Runs in a popup on prefix+M
# (modules/tmux/common.conf): `paperboy-unread start` needs a terminal, where
# it types the Exchange password when the keyring's own prompt is out of reach
# (SSH, locked screen). Extra arguments (--ask, --interval N) go to `start`.
#
# The daemon is configured by $PAPERBOY_EWS_URL and $PAPERBOY_EMAIL, which only
# the PowerShell profile sets (~/.profile.ps1): the tmux server's environment
# does not have them, so without them this runs itself again through a lean
# pwsh, like pwsh_invocation does for the Paperboy pane (tmux-helpers.sh).
set -uo pipefail

if [ -z "${PAPERBOY_EWS_URL:-}" ] && [ -z "${PAPERBOY_REEXEC:-}" ] && command -v pwsh >/dev/null; then
  PAPERBOY_REEXEC=1 PWSH_LEAN=1 exec pwsh -NoLogo -Command "& '$0' $*"
fi

# A key press before the popup closes, so what went wrong can be read
fail() {
  printf '%s\n\nPress any key to close.' "$1"
  read -rsn1
  exit 1
}

[ -n "${PAPERBOY_EWS_URL:-}" ] ||
  fail "PAPERBOY_EWS_URL and PAPERBOY_EMAIL are not set (see ~/.profile.ps1)."

# On the PATH when linked there, otherwise in the checkout lazy.nvim loads the
# plugin from (dev.path in nvim-config/lua/config/lazy.lua) or its own clone
daemon=""
for candidate in "$(command -v paperboy-unread)" \
  "$HOME/code/paperboy.nvim/bin/paperboy-unread" \
  "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/paperboy.nvim/bin/paperboy-unread"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    daemon=$candidate
    break
  fi
done
[ -n "$daemon" ] || fail "paperboy-unread not found: is paperboy.nvim installed (:Lazy)?"

# Running already: its count may be stuck on "!" or it may just be in the way.
# The pid file is removed when it exits (but a "🔒" count is kept until the
# next start, which replaces it).
pid_file="${XDG_RUNTIME_DIR:-/run/user/$UID}/paperboy/daemon.pid"
if [ -r "$pid_file" ] && kill -0 "$(<"$pid_file")" 2>/dev/null; then
  printf 'The unread-count daemon is running (pid %s).\n\n' "$(<"$pid_file")"
  printf '[r] restart   [s] stop   any other key: keep it '
  read -rsn1 answer
  printf '\n\n'
  case "$answer" in
    r | R) "$daemon" stop >/dev/null ;;
    s | S)
      "$daemon" stop
      tmux refresh-client -S
      sleep 1
      exit 0
      ;;
    *) exit 0 ;;
  esac
  # stop only sends SIGTERM: start refuses while the old one is still exiting
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -e "$pid_file" ] || break
    sleep 0.2
  done
fi

"$daemon" start "$@" || { tmux refresh-client -S; fail ""; }
tmux refresh-client -S
sleep 1
