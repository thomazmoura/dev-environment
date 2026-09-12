#!/usr/bin/env bash
# Shared helpers for ssh sessions. Sourced (by tmux-helpers.sh), never run.
#
# An ssh session is a tmux session opened with prefix+N (New-SshSession.sh):
# every pane in it is an ssh to one host, started in one working directory on
# that host. The session remembers both as session options, which live in the
# tmux server for as long as the session does:
#
#   @ssh_target   user@host
#   @ssh_dir      the working directory on the remote, absolute
#   @ssh_devenv   "yes" when the remote has this dev-environment (pwsh and
#                 ~/.modules), so the panes can run the same pwsh commands they
#                 run locally; anything else gets the remote's login shell
#
# pane_command in tmux-helpers.sh reads them to decide whether a new pane runs
# its command here or over ssh.
#
# Two rounds of shell parsing sit between these functions and the remote: the
# local pane's bash reads the line typed into it, and the remote login shell
# reads the command ssh hands it. The first is quoted with %q, as everywhere in
# these scripts. The second is quoted with sq, because the remote shell is not
# necessarily bash and %q can produce bash-only $'...'.

# Every ssh shares one connection per host: the first one authenticates -- in
# New-SshSession.sh's popup, where a password prompt has a terminal to use --
# and every pane opened after it goes through that master without asking
# again, and without a handshake's worth of delay. ControlPersist keeps the
# master around for ten minutes after the last pane using it closes.
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$HOME/.ssh/tmux-%C" -o ControlPersist=10m)

# The remote's ssh key, unlocked once per host rather than once per pane.
#
# Locally the key is unlocked before tmux starts: Add-SshKey
# (modules/powershell-config/kernel-profile.ps1) puts SSH_AUTH_SOCK and
# SSH_AGENT_PID in the environment the tmux server inherits, and every pane's
# profile finds the agent there and asks nothing. A remote pane inherits
# nothing, so its profile used to start an agent of its own and ask for the
# password again, in every pane.
#
# So an ssh session runs one agent per host, at a fixed socket in a private
# directory on the remote. New-SshSession.sh starts it and adds the key in its
# popup (remote_agent_unlock), where ssh-add has a terminal to read the
# password from; the password goes from there to ssh-add and nowhere else --
# not into a variable, an option or a file. Every pane then gets the same two
# variables a local pane inherits (remote_agent_env), so the profile's
# Add-SshKey finds the key already there.
#
# Every new pane also runs remote_agent_unlock before it connects
# (Unlock-RemoteKey.sh, see ssh_command). When the key is there that is one
# quiet round trip over the master connection; when the agent has died or the
# key has expired, it is that pane that asks, once, and puts the key back in
# the shared agent for the panes after it.
#
# The key is held for no longer than the sessions that use it: the
# session-closed hook kills the agent once no session for that host is left
# (Close-SshAgent.sh), and the agent itself drops the key after
# SSH_AGENT_LIFETIME, for when tmux goes away without running the hook.
#
# REMOTE_AGENT_DIR is expanded by the remote shell, not this one: it is always
# spliced into double quotes in a remote command.
REMOTE_AGENT_DIR='$HOME/.ssh/tmux-agent'
SSH_AGENT_LIFETIME=12h

# sq <string>
# Quotes a string for a POSIX shell: wrapped in single quotes, with each
# embedded ' closed, escaped and reopened.
sq() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}

# ssh_option <target> <option>
# A session option of <target>'s session (any tmux target, a pane id
# included), or nothing when it is unset -- which, for @ssh_target, means a
# local session.
ssh_option() {
  tmux show-options -qv -t "$1" "$2" 2>/dev/null
}

# ssh_is_devenv <pane>
ssh_is_devenv() {
  [ "$(ssh_option "$1" @ssh_devenv)" = yes ]
}

# remote_run <pane> <command> [no-exit]
# How the remote runs <command>, in the same three shapes pwsh_invocation has.
# A dev-environment remote gets exactly that pwsh call, pointed at the host's
# shared agent. Any other host gets its login shell -- a login shell so the
# PATH additions in its profile (nvm and the like) are there -- running the
# command, and staying afterwards for no-exit. `$SHELL` is left for the remote
# to expand.
remote_run() {
  local pane=$1 command=$2 no_exit=${3:-}
  if ssh_is_devenv "$pane"; then
    printf '%s%s' "$(remote_agent_env)" "$(pwsh_invocation "$command" "$no_exit")"
  elif [ -z "$command" ]; then
    printf 'exec "$SHELL" -l'
  elif [ -n "$no_exit" ]; then
    printf '"$SHELL" -lc %s; exec "$SHELL" -l' "$(sq "$command")"
  else
    printf 'exec "$SHELL" -lc %s' "$(sq "$command")"
  fi
}

# ssh_command <pane> <command> [no-exit]
# The line typed into a new local pane of <pane>'s session: ssh to the host,
# cd into the working directory and run the command there. `&& exit` works as
# it does in pwsh_command -- ssh exits with the remote command's status -- so a
# command that fails keeps its pane, and its error, on screen.
#
# On a dev-environment remote the ssh comes after Unlock-RemoteKey.sh, which
# puts the key back in the host's shared agent when it is not there, so a pane
# repairs an agent that died or a key that expired instead of falling back to
# asking in every pane. Joined with `;`, not `&&`: a password that was not
# given leaves the pane to ask for it in its profile, as before.
ssh_command() {
  local pane=$1 command=$2 no_exit=${3:-}
  local target dir remote opt line="ssh -t" unlock=""
  target="$(ssh_option "$pane" @ssh_target)"
  dir="$(ssh_option "$pane" @ssh_dir)"
  remote="cd $(sq "$dir") && $(remote_run "$pane" "$command" "$no_exit")"
  for opt in "${SSH_OPTS[@]}"; do
    line+=" $(printf '%q' "$opt")"
  done
  if ssh_is_devenv "$pane"; then
    unlock="$(printf '%q %q; ' "$(dirname "${BASH_SOURCE[0]}")/Unlock-RemoteKey.sh" "$target")"
  fi
  printf '%s%s %q %q && exit' "$unlock" "$line" "$target" "$remote"
}

# remote_typed_command <pane> <command> [no-exit]
# What to type into a pane that is already a shell on the remote, as opposed
# to a local shell that still has to ssh there (prefix+v fired from a remote
# pane). On a dev-environment remote that shell is pwsh, so it gets the same
# pwsh call a new pane would; anywhere else the command is typed as it is.
remote_typed_command() {
  local pane=$1 command=$2 no_exit=${3:-}
  if ssh_is_devenv "$pane"; then
    pwsh_invocation "$command" "$no_exit"
  else
    printf '%s' "$command"
  fi
}

# remote_directory_matches <pane> <glob>
# directory_matches (tmux-helpers.sh), asked of the session's working directory
# on the remote. <glob> is left unquoted on purpose so the remote shell expands
# it; a glob that matches nothing stays literal, which is what `[ -d ]` then
# rejects. Run under sh rather than the login shell, which may not speak
# `set --`.
#
# Exits 255 when ssh itself failed, which callers treat as "don't know" rather
# than "no": a guard that cannot reach the host should not stand in for the
# pane that would have shown why. BatchMode because this runs from
# `run-shell -b`, where a password prompt would have nothing to type into --
# with the master connection up, it never needs one.
remote_directory_matches() {
  local pane=$1 glob=$2 target dir check
  target="$(ssh_option "$pane" @ssh_target)"
  dir="$(ssh_option "$pane" @ssh_dir)"
  check="cd $(sq "$dir") && set -- $glob/ && [ -d \"\$1\" ]"
  ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$target" \
    "sh -c $(sq "$check")" </dev/null
}

# --- The host's shared agent (see REMOTE_AGENT_DIR above) ---------------------

# remote_agent_env
# Put in front of a pane's pwsh call on the remote: hands it the shared agent's
# two variables when the agent's socket is there. An `if` with no else succeeds
# when its test fails, so a host without the agent still reaches the `&&`
# after it and runs the pane as before -- the profile then asks, as it always
# has.
remote_agent_env() {
  local a="$REMOTE_AGENT_DIR"
  printf 'if [ -S "%s/agent.sock" ]; then export SSH_AUTH_SOCK="%s/agent.sock" SSH_AGENT_PID="$(cat "%s/agent.pid")"; fi && ' \
    "$a" "$a" "$a"
}

# remote_agent_unlock <target>
# Makes sure the host's shared agent is running and holding the key, asking
# for the password when it is not. Needs a terminal -- ssh-add reads the
# password from it -- so it runs in New-SshSession.sh's popup, through the
# master connection the popup has just made, and in each new pane before its
# own ssh (Unlock-RemoteKey.sh). -q because a pane runs it every time: it keeps
# ssh's "Shared connection ... closed" off the pane, and leaves the password
# prompt, which comes from the remote's ssh-add, alone.
#
# Panes opened together while the key is missing each ask on their own; there
# is no lock between them. Unlocking in one pane and reopening the others is
# the way out of that.
#
# The key, and the condition for adding it at all, are linux-profile.ps1's: a
# host with no ~/.ssh/id_rsa.pub, or with ~/.skip-ssh, is left alone. An agent
# that already holds the key -- another session on this host unlocked it --
# means there is nothing to ask. A socket nobody answers on is what an agent
# that died leaves behind, and ssh-agent will not bind over it, so it goes.
#
# Exits with ssh-add's status: non-zero when the password was never given.
remote_agent_unlock() {
  local target=$1 script
  script="a=\"$REMOTE_AGENT_DIR\""'
key="$HOME/.ssh/id_rsa"
[ -f "$key.pub" ] && [ ! -e "$HOME/.skip-ssh" ] || exit 0
command -v ssh-agent >/dev/null 2>&1 || exit 0
umask 077
mkdir -p "$a" && chmod 700 "$a" || exit 1
SSH_AUTH_SOCK="$a/agent.sock"; export SSH_AUTH_SOCK
id="$(cut -d" " -f1,2 "$key.pub")"
ssh-add -L 2>/dev/null | grep -qF "$id" && exit 0
ssh-add -l >/dev/null 2>&1
if [ $? -eq 2 ]; then
  rm -f "$a/agent.sock" "$a/agent.pid"
  agent="$(ssh-agent -s -a "$a/agent.sock" -t "$1")" || exit 1
  eval "$agent" >/dev/null
  echo "$SSH_AGENT_PID" > "$a/agent.pid"
fi
ssh-add "$key"'
  ssh "${SSH_OPTS[@]}" -q -t "$target" "sh -c $(sq "$script") sh $(sq "$SSH_AGENT_LIFETIME")"
}

# remote_agent_kill <target>
# Stops the host's shared agent, and the key goes with it. Run from the
# session-closed hook, which has no terminal -- BatchMode, as in
# remote_directory_matches -- and which fires while the master connection is
# still being kept around by ControlPersist, so it needs no password.
#
# The pid file is only trusted while the socket answers: then the agent that
# wrote it is still the one running. A socket nobody answers on means the agent
# is already gone and the pid may by now be someone else's.
remote_agent_kill() {
  local target=$1 script
  script="a=\"$REMOTE_AGENT_DIR\""'
SSH_AUTH_SOCK="$a/agent.sock" ssh-add -l >/dev/null 2>&1
if [ $? -ne 2 ] && [ -f "$a/agent.pid" ]; then kill "$(cat "$a/agent.pid")"; fi
rm -f "$a/agent.sock" "$a/agent.pid"'
  ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$target" \
    "sh -c $(sq "$script")" </dev/null
}

# The hosts that may have a shared agent running, as a space-separated
# server-wide option: New-SshSession.sh adds one when it unlocks a key, and
# Close-SshAgent.sh takes it off when it kills that agent. A server option
# rather than a file, since it describes this tmux server's sessions and goes
# away with them.
agent_targets() {
  tmux show-options -gqv @ssh_agent_targets 2>/dev/null
}

# add_agent_target <target>
add_agent_target() {
  local targets
  targets="$(agent_targets)"
  case " $targets " in
    *" $1 "*) ;;
    *) tmux set-option -g @ssh_agent_targets "${targets:+$targets }$1" ;;
  esac
}
