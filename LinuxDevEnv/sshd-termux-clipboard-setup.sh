#!/usr/bin/env bash
set -euo pipefail

# Host side of the phone's clipboard for NeoVim: run this once on the dev
# machine (it asks for sudo).
#
# Termux's ssh forwards two Unix sockets back to the phone,
# /tmp/termux-clipboard-<user>-{get,set}.sock (Termux/termux-setup.sh), and
# NeoVim's "+ talks to them while Termux is the tmux client in front
# (modules/nvim-config/lua/config/termux_clipboard.lua). sshd doesn't remove
# such a socket when the connection ends, and by default refuses to bind over
# the one left behind, so every connection after the first would come without
# the clipboard. StreamLocalBindUnlink lets it replace the old socket.
#
# Idempotent: writes the drop-in only when it differs, then checks the config
# and reloads sshd.

[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

CONF=/etc/ssh/sshd_config.d/termux-clipboard.conf
CONTENT="# The phone's clipboard over ssh: see LinuxDevEnv/sshd-termux-clipboard-setup.sh
# in the dev-environment repo.
StreamLocalBindUnlink yes"

if [ "$(cat "$CONF" 2>/dev/null)" != "$CONTENT" ]; then
  mkdir -p "$(dirname "$CONF")"
  printf '%s\n' "$CONTENT" > "$CONF"
  echo "Wrote $CONF."
fi

sshd -t
# The first value sshd reads wins: sshd_config includes sshd_config.d at its
# top, but an earlier drop-in could still say otherwise
if ! sshd -T | grep -qix 'streamlocalbindunlink yes'; then
  echo "Warning: sshd still has StreamLocalBindUnlink off -- another file in" >&2
  echo "  /etc/ssh sets it before $CONF does." >&2
  exit 1
fi
systemctl try-reload-or-restart ssh
echo "OK: sshd replaces stale forwarded sockets."
