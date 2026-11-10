#!/bin/sh
# Makes sure this machine's shared ssh-agent is running and holding the key,
# asking for the password when it is not.
#
# Usage: Unlock-SshAgent.sh [<key>]
#   Run by Add-SshKey (DevHelpers.psm1), from the pwsh profile, when the agent
#   is not running. Also sent, as text, to an ssh session's host by
#   remote_agent_unlock (ssh-helpers.sh), for New-SshSession.sh's popup
#   (prefix+N), each new pane of the session (Unlock-RemoteKey.sh) and
#   git-radar's failure popup (Show-GitFailure.sh) -- as text so the host
#   runs this version, whatever its checkout. So: POSIX sh, nothing sourced.
#
# One agent per machine, at a fixed socket, ~/.ssh/tmux-agent/agent.sock. Every
# pane on the machine uses it: the tmux server hands its socket to every pane
# whichever device's client attached last (update-environment in
# modules/tmux/common.conf), the pwsh profile points at it whatever it
# inherited (linux-profile.ps1), and an ssh session's panes on the machine are
# pointed at it too (remote_agent_env). A key is typed once per machine, and is
# held until the agent's LIFETIME drops it; after that ssh puts it back on
# first use (AddKeysToAgent, LinuxDevEnv/host-setup.sh), asking once.
#
# The key, and the condition for adding it at all, follow linux-profile.ps1:
# the one SSH_KEY_FILE names, else the first ~/.ssh/*.pub's; a machine with
# neither, or with ~/.skip-ssh, is left alone. SSH_KEY_FILE is taken from the
# environment or, since this is sh and not the pwsh profile, from its
# `$env:SSH_KEY_FILE = ...` line in ~/.profile.ps1, where the panes read it --
# otherwise the panes would find their key missing from the agent and ask
# again. An agent that already holds the key means there is nothing to ask. A
# socket nobody answers on is what an agent that died leaves behind, and
# ssh-agent will not bind over it, so it goes.
#
# <key>, a path, replaces that default key and its condition: Add-SshKey names
# the key it was asked for, and git-radar's failure popup the key the git
# remote would have tried (Show-GitFailure.sh) -- often not id_rsa, GitHub may
# only know id_ed25519. ~/.skip-ssh, which is about panes asking on their own,
# does not apply to a key asked for by name.
#
# Panes opened together -- a layout's, or a client arriving to several new
# ones -- would each ask on their own. A lock lets the first one ask while the
# others wait, and find the key there once it has been given.
#
# Exits with ssh-add's status: non-zero when the password was never given.
LIFETIME=12h
a="$HOME/.ssh/tmux-agent"
key="${1:-}"
if [ -z "$key" ]; then
  [ -e "$HOME/.skip-ssh" ] && exit 0
  f="${SSH_KEY_FILE:-}"
  [ -n "$f" ] || f="$(sed -n "s/^[[:space:]]*\$env:SSH_KEY_FILE[[:space:]]*=//p" "$HOME/.profile.ps1" 2>/dev/null |
    tail -n 1 | tr -d "\"'[:space:]")"
  if [ -z "$f" ]; then
    for p in "$HOME"/.ssh/*.pub; do
      [ -f "$p" ] && { f="$(basename "$p" .pub)"; break; }
    done
  fi
  [ -n "$f" ] || exit 0
  key="$HOME/.ssh/$f"
  [ -f "$key" ] || exit 0
fi
command -v ssh-agent >/dev/null 2>&1 || exit 0
umask 077
mkdir -p "$a" && chmod 700 "$a" || exit 1
SSH_AUTH_SOCK="$a/agent.sock"; export SSH_AUTH_SOCK

# Without a .pub there is nothing to compare against, and the key is added.
id=""
[ -f "$key.pub" ] && id="$(cut -d" " -f1,2 "$key.pub")"
has_key() {
  [ -n "$id" ] && ssh-add -L 2>/dev/null | grep -qF "$id"
}
has_key && exit 0

if command -v flock >/dev/null 2>&1; then
  exec 9>"$a/lock"
  if ! flock -n 9; then
    printf 'Waiting for the ssh key to be unlocked in another pane (Ctrl+C to skip)...\n' >&2
    flock 9 || exit 1
  fi
  has_key && exit 0
fi

ssh-add -l >/dev/null 2>&1
if [ $? -eq 2 ]; then
  rm -f "$a/agent.sock" "$a/agent.pid"
  # 9>&-: the agent outlives this script, and would hold the lock with it.
  agent="$(ssh-agent -s -a "$a/agent.sock" -t "$LIFETIME" 9>&-)" || exit 1
  eval "$agent" >/dev/null
  echo "$SSH_AGENT_PID" > "$a/agent.pid"
fi
ssh-add "$key"
