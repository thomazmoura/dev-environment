#!/usr/bin/env bash
# The phone's ssh-agent, for as long as Termux has a session open: each key's
# passphrase is typed once while Termux is open, and is gone once its last
# session closes -- a phone left with Termux closed holds no unlocked key.
#
# Installed as $PREFIX/bin/termux-ssh-agent by Termux/termux-setup.sh, which
# also makes ~/.bashrc run it from every interactive Termux session (not from
# ssh logins into the phone) with SSH_AUTH_SOCK=~/.ssh/agent/agent.sock, and
# turns on AddKeysToAgent, so ssh adds each key the first time it unlocks it.
#
# Usage: termux-ssh-agent <shell pid>
#
# How the agent knows when the last session is gone: every session's shell
# keeps a shared lock on ~/.ssh/agent/lock -- held by a detached `tail --pid`
# rather than the shell itself, so tmux, socat and the like started from the
# shell don't inherit the lock and keep it alive. The agent runs with a
# command, `flock -x` on that lock, which gets it only once every shell is
# gone, however it went (exit, closing the tab, Termux's Exit, Android killing
# it). It then stops the agent, which removes its socket -- all while holding
# the lock, so a session opening at that moment waits and starts a new agent
# rather than finding the old one on its way out. ssh-agent also ends by
# itself when its command dies, so a killed watcher takes the agent with it.
#
# The termux-services ssh-agent service is the opposite -- an agent that
# outlives every session -- and termux-setup.sh leaves it disabled.

set -u

shell_pid="${1:-}"
if ! [[ "$shell_pid" =~ ^[0-9]+$ ]]; then
  echo "Usage: termux-ssh-agent <shell pid>" >&2
  exit 2
fi
command -v ssh-agent >/dev/null 2>&1 || exit 0

dir="$HOME/.ssh/agent"
sock="$dir/agent.sock"
lock="$dir/lock"
umask 077
mkdir -p "$dir" && chmod 700 "$dir" || exit 1

# Sessions opened together (Termux restoring several) start one agent
exec 9>"$dir/start.lock"
flock -w 10 9 || exit 1

# This session's hold on the agent, taken before looking at the agent: once it
# holds the lock, the watcher can't end the agent under this session
ready="$dir/holding.$shell_pid"
rm -f "$ready"
setsid nohup flock -s "$lock" \
  sh -c 'touch "$1"; exec tail --pid="$2" -f /dev/null' sh "$ready" "$shell_pid" \
  </dev/null >/dev/null 2>&1 9>&- &
for _ in $(seq 50); do
  [ -e "$ready" ] && break
  sleep 0.1
done
rm -f "$ready"

# 2 is "could not connect": no agent, or a socket one left behind
SSH_AUTH_SOCK="$sock" ssh-add -l >/dev/null 2>&1
[ $? -ne 2 ] && exit 0

rm -f "$sock"
# The command runs as the agent's parent, with SSH_AGENT_PID set. The wait
# keeps the lock until the agent has removed its socket.
setsid nohup ssh-agent -a "$sock" flock -x "$lock" sh -c '
    kill "$SSH_AGENT_PID" 2>/dev/null
    for _ in $(seq 20); do [ -S "$SSH_AUTH_SOCK" ] || break; sleep 0.1; done
    rm -f "$SSH_AUTH_SOCK"
  ' </dev/null >/dev/null 2>&1 9>&- &

# Ready before the shell's first ssh
for _ in $(seq 30); do
  SSH_AUTH_SOCK="$sock" ssh-add -l >/dev/null 2>&1
  [ $? -ne 2 ] && exit 0
  sleep 0.1
done
echo "termux-ssh-agent: the agent didn't start; ssh will ask for passphrases every time." >&2
exit 1
