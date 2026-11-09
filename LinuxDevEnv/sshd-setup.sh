#!/usr/bin/env bash
set -euo pipefail

# What a dev machine's sshd needs for the ssh clients that reach its tmux
# (Termux/termux-setup.sh and the PC). Run by host-setup.sh; also safe to run
# alone (it asks for sudo).
#
# One drop-in, /etc/ssh/sshd_config.d/dev-environment.conf:
#
# StreamLocalBindUnlink yes -- the clients forward Unix sockets back here
#   (RemoteForward): the phone's clipboard and browser,
#   /tmp/termux-clipboard-<user>-{get,set}.sock and /tmp/xray-open-termux-<user>.sock
#   (Termux/termux-setup.sh), and the PC's, /tmp/xray-{richcopy,open}-<user>.sock
#   (xray.nvim's bin/xray-setup-client). sshd doesn't remove such a socket when
#   the connection ends, and by default refuses to bind over the one left
#   behind, so every connection after the first would come without them. This
#   also stands in for xray.nvim's bin/xray-setup-server.
#
# MaxSessions 64 -- an ssh session in tmux (prefix+N) sends every pane, and the
#   Git and Agents radars' queries, through one master connection per host
#   (SSH_OPTS in modules/tmux/scripts/ssh-helpers.sh). sshd allows 10 sessions
#   per connection by default, which a few ssh sessions fill: past that every
#   new pane and radar query gets "Session open refused by peer", and the
#   radars show the sessions as unreachable. A master that was already open
#   keeps the old limit: close it on the client (ssh -O exit
#   -o ControlPath=~/.ssh/tmux-%C <host>) and reopen the panes.
#
# Idempotent: writes the drop-in only when it differs, removes the one older
# versions of this script wrote, checks the config and reloads sshd. Without
# an sshd installed it says so and does nothing.

if ! command -v sshd >/dev/null 2>&1 && [ ! -x /usr/sbin/sshd ]; then
  echo "No sshd here (openssh-server): skipping its setup."
  exit 0
fi

[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

CONF=/etc/ssh/sshd_config.d/dev-environment.conf
OLD_CONF=/etc/ssh/sshd_config.d/termux-clipboard.conf
CONTENT="# Written by LinuxDevEnv/sshd-setup.sh in the dev-environment repo:
# see that script for why.
StreamLocalBindUnlink yes
MaxSessions 64"

if [ "$(cat "$CONF" 2>/dev/null)" != "$CONTENT" ]; then
  mkdir -p "$(dirname "$CONF")"
  printf '%s\n' "$CONTENT" > "$CONF"
  echo "Wrote $CONF."
fi
if [ -f "$OLD_CONF" ]; then
  rm -f "$OLD_CONF"
  echo "Removed $OLD_CONF (now part of $CONF)."
fi

sshd -t
# The first value sshd reads wins: sshd_config includes sshd_config.d at its
# top, but an earlier drop-in could still say otherwise. Captured first: grep
# -q quits at the match, and sshd's SIGPIPE would fail the pipe (pipefail).
effective="$(sshd -T)"
failed=""
for setting in 'streamlocalbindunlink yes' 'maxsessions 64'; do
  if ! grep -qix "$setting" <<<"$effective"; then
    echo "Warning: sshd doesn't have '$setting' -- another file in /etc/ssh sets" >&2
    echo "  it before $CONF does." >&2
    failed=1
  fi
done
systemctl try-reload-or-restart ssh 2>/dev/null || service ssh reload 2>/dev/null || true
[ -z "$failed" ] || exit 1
echo "OK: sshd replaces stale forwarded sockets and allows 64 sessions per connection."
