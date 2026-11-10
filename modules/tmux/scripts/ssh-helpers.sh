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
#   @ssh_user     the user the panes log in as: the user part of @ssh_target,
#                 or what ~/.ssh/config picks when it has none (ssh_user)
#   @ssh_name     the session's name without the user in front of it (see
#                 ssh_session_name)
#   @ssh_client_terminal  the line last written to the remote's client
#                 terminal file (Sync-SshClientTerminal.sh), so a switch that
#                 changes nothing makes no ssh
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
#
# ServerAlive* because a master outlives its network: after a suspend or a VPN
# dropping it still takes requests on its socket, and every ssh through it --
# a new pane, prefix+N's connection -- hangs waiting for a host that is no
# longer there, until TCP gives up hours later. With them the master sees the
# link is gone within half a minute and exits, and the next ssh connects anew.
#
# One master carries every pane of every session on that host, and the Git and
# Agents radars' queries too, while sshd allows 10 sessions per connection by
# default (MaxSessions). A few sessions fill that: then every new pane and
# radar query gets "Session open refused by peer", and the radars call the
# sessions unreachable. The dev machine's LinuxDevEnv/sshd-setup.sh
# raises the limit.
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$HOME/.ssh/tmux-%C" -o ControlPersist=10m
          -o ServerAliveInterval=10 -o ServerAliveCountMax=3)

# Every ssh below -- and in every script that sources this -- goes through
# Invoke-Remote.sh rather than ssh itself. It is ssh for a host; for a target
# of the form docker:<container>, a session opened on a local container
# (prefix+D), it is the same call made with `docker exec`. That is the one
# place the two differ, so everything else about a session -- @ssh_target and
# the rest -- serves both.
REMOTE_SSH="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/Invoke-Remote.sh"

# is_docker_target <target>
# Whether an @ssh_target names a local container rather than a host.
is_docker_target() {
  [[ $1 == docker:* ]]
}

# The ssh key, unlocked once per machine rather than once per pane.
#
# Every machine runs one shared agent, at a fixed socket in a private directory,
# ~/.ssh/tmux-agent (Unlock-SshAgent.sh). Its own panes use it: the tmux server
# hands the socket to every pane, whichever device's client attached last
# (common.conf), and the pwsh profile points at it whatever it inherited
# (linux-profile.ps1). So do an ssh session's panes on that machine, here.
# Its own (linked) panes and the ssh sessions into it share the one key.
#
# New-SshSession.sh makes sure of the host's agent and its key in its popup
# (remote_agent_unlock), where ssh-add has a terminal to read the password
# from; the password goes from there to ssh-add and nowhere else -- not into a
# variable, an option or a file. Every pane then gets the agent's two variables
# (remote_agent_env), so the profile finds a live agent there and leaves it
# alone.
#
# Every new pane also runs remote_agent_unlock before it connects
# (Unlock-RemoteKey.sh, see ssh_command). When the key is there that is one
# quiet round trip over the master connection; when the agent has died or the
# key has expired, it is that pane that asks, once, and puts the key back in
# the shared agent for the panes after it.
#
# Closing sessions leaves the agent alone -- the host's own panes use it too.
# The agent drops the key itself after its lifetime (Unlock-SshAgent.sh).
#
# REMOTE_AGENT_DIR is expanded by the remote shell, not this one: it is always
# spliced into double quotes in a remote command.
REMOTE_AGENT_DIR='$HOME/.ssh/tmux-agent'

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

# ssh_user <target>
# The user an ssh to <target> logs in as: the part before the @, or -- for a
# bare host -- the one ssh itself would pick, ~/.ssh/config included. Nothing
# for a container, which has no user to tell sessions apart by.
ssh_user() {
  is_docker_target "$1" && return 0
  case "$1" in
    *@*) printf '%s\n' "${1%@*}" ;;
    *) ssh -G "$1" 2>/dev/null | awk '$1 == "user" { print $2; exit }' ;;
  esac
}

# ssh_session_name <name> <target> <user>
# What a session on <target> logged in as <user> is called, given <name>, its
# name without a user: <host>-<directory> from New-SshSession.sh, or a
# worktree's (session_name_for in worktree-helpers.sh).
#
# The user is left out while every open session on the host logs in as the
# same one -- the usual case, where it would be the same on every name. Once
# another user has a session on that host it is put in front, user@<name>, on
# that user's sessions and on everyone else's there, so two users' sessions on
# the same folder neither collide nor look alike. Rename-SshSessions.sh keeps
# the open sessions in step as users come and go.
#
# Dots are tmux's separators, so a user like first.last is first_last here.
ssh_session_name() {
  local name=$1 host="${2##*@}" user=$3 other other_user
  if [ -n "$user" ]; then
    while IFS=$'\t' read -r other other_user; do
      [ -n "$other" ] && ! is_docker_target "$other" && [ "${other##*@}" = "$host" ] || continue
      [ -n "$other_user" ] || other_user="$(ssh_user "$other")"
      if [ "$other_user" != "$user" ]; then
        printf '%s@%s\n' "$(printf '%s' "$user" | tr '.:' '__')" "$name"
        return 0
      fi
    done < <(tmux list-sessions -F $'#{@ssh_target}\t#{@ssh_user}' 2>/dev/null)
  fi
  printf '%s\n' "$name"
}

# open_session_named <name>
# The open session called <name>, or whose name is <name> once the user
# ssh_session_name may have put in front is left off (@ssh_name). Nothing when
# there is none.
open_session_named() {
  tmux list-sessions -F $'#{session_name}\t#{@ssh_name}' 2>/dev/null |
    awk -F '\t' -v name="$1" '$1 == name || $2 == name { print $1; exit }'
}

# remote_run <pane> <command> [no-exit] [no-pwsh]
# How the remote runs <command>, in the same three shapes pwsh_invocation has.
# A dev-environment remote gets exactly that pwsh call, pointed at the host's
# shared agent. Any other host gets its login shell -- a login shell so the
# PATH additions in its profile (nvm and the like) are there -- running the
# command, and staying afterwards for no-exit. `$SHELL` is left for the remote
# to expand.
#
# no-pwsh on a dev-environment remote goes through the login shell too, still
# pointed at the shared agent: the shell sshd runs the command in is neither
# login nor interactive, so it has none of the profile's PATH -- no
# ~/.local/bin, where nvim is -- and without pwsh nothing else adds it.
#
# Either way a dev-environment remote also gets the user session's variables
# (remote_session_env), which the shell sshd runs the command in may lack.
remote_run() {
  local pane=$1 command=$2 no_exit=${3:-} no_pwsh=${4:-}
  if ssh_is_devenv "$pane" && [ -n "$no_pwsh" ]; then
    printf '%s%sexec "$SHELL" -lc %s' "$(remote_session_env)" "$(remote_agent_env)" "$(sq "$command")"
  elif ssh_is_devenv "$pane"; then
    printf '%s%s%s' "$(remote_session_env)" "$(remote_agent_env)" "$(pwsh_invocation "$command" "$no_exit" "$no_pwsh")"
  elif [ -z "$command" ]; then
    printf 'exec "$SHELL" -l'
  elif [ -n "$no_exit" ]; then
    printf '"$SHELL" -lc %s; exec "$SHELL" -l' "$(sq "$command")"
  else
    printf 'exec "$SHELL" -lc %s' "$(sq "$command")"
  fi
}

# ssh_command <pane> <command> [no-exit] [no-pwsh]
# The line typed into a new local pane of <pane>'s session: ssh to the host,
# cd into the working directory and run the command there. The pane closes when
# the ssh ends, however it ends (see closing_line in tmux-helpers.sh).
#
# On a dev-environment remote the ssh comes after Unlock-RemoteKey.sh, which
# puts the key back in the host's shared agent when it is not there, so a pane
# repairs an agent that died or a key that expired instead of falling back to
# asking in every pane. Joined with `;`, not `&&`: a password that was not
# given leaves the pane to ask for it in its profile, as before.
#
# Also on a dev-environment remote, the remote shell -- and so every agent
# started in it, by a binding or by hand -- carries AGENT_RADAR_PANE, naming
# this machine and the local pane: the host's agent-radar reads it out of an
# agent's environment to say which of our panes that agent is in (see
# agent_radar.serve). It is a separate ssh argument, in double quotes and
# outside the %q-quoted command, so that $TMUX_PANE is expanded by the pane's
# own bash when it runs the line -- the pane does not exist yet while the line
# is being built. ssh joins its arguments with spaces, so the remote reads one
# command: `export AGENT_RADAR_PANE=<host>/%12; cd ... && ...`.
#
# On every remote, the shell also carries TMUX_CLIENT_TERMINAL: the file on the
# remote saying which terminal is attached to this tmux right now, which
# Sync-SshClientTerminal.sh keeps up to date as clients come and go. An nvim
# there has no $TMUX to ask, and a query to the terminal is answered by this
# tmux for itself (DA1 always claims Sixel), so paperboy.nvim's image previews
# read the file to pick Kitty, Sixel or half-blocks for the device actually
# looking. Its `\$HOME`, escaped once more than $TMUX_PANE above, gets past the
# pane's bash and is expanded on the remote.
ssh_command() {
  local pane=$1 command=$2 no_exit=${3:-} no_pwsh=${4:-}
  local target dir remote opt line unlock="" tag=""
  target="$(ssh_option "$pane" @ssh_target)"
  dir="$(ssh_option "$pane" @ssh_dir)"
  remote="cd $(sq "$dir") && $(remote_run "$pane" "$command" "$no_exit" "$no_pwsh")"
  line="$(printf '%q' "$REMOTE_SSH") -t"
  for opt in "${SSH_OPTS[@]}"; do
    line+=" $(printf '%q' "$opt")"
  done
  if ssh_is_devenv "$pane"; then
    unlock="$(printf '%q %q; ' "$(dirname "${BASH_SOURCE[0]}")/Unlock-RemoteKey.sh" "$target")"
    tag=" \"export AGENT_RADAR_PANE=$(hostname)/\$TMUX_PANE;\""
  fi
  tag+=" \"export TMUX_CLIENT_TERMINAL=\\\$HOME/$(ssh_client_terminal_file "$pane");\""
  printf '%s%s %q%s %q' "$unlock" "$line" "$target" "$tag" "$remote"
}

# ssh_client_terminal_file <target>
# Where, relative to the remote's home, the client terminal file of <target>'s
# session lives (see ssh_command): one per local machine and session, named by
# the session's id, which -- unlike its name -- a rename leaves alone.
ssh_client_terminal_file() {
  local id
  id="$(tmux display-message -p -t "$1" '#{session_id}')"
  printf '.cache/tmux-client/%s-%s' "$(hostname)" "${id#\$}"
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
  "$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$target" \
    "sh -c $(sq "$check")" </dev/null
}

# remote_has_notes <pane>
# has_notes (tmux-helpers.sh), asked of the session's working directory on the
# remote: true when the repository it is in -- or the directory itself, outside
# one -- has a .notes file. Exits 255 when ssh failed, as
# remote_directory_matches does, and for the same reason.
remote_has_notes() {
  local pane=$1 target dir check
  target="$(ssh_option "$pane" @ssh_target)"
  dir="$(ssh_option "$pane" @ssh_dir)"
  check="cd $(sq "$dir") && root=\"\$(git rev-parse --show-toplevel 2>/dev/null || pwd)\" && [ -f \"\$root/.notes\" ]"
  "$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$target" \
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

# remote_profile_command <pwsh-command>
# A remote command that runs <pwsh-command> in a lean pwsh with the host's
# profile loaded, for the calls that need its environment but have no pane:
# the status segments of prefix+C-k (Get-RemoteStatus.sh, Select-StatusSource.sh)
# need PAPERBOY_EWS_URL, WORKHORSE_TMUX_QUERY_ID and the PATH that finds az,
# none of which an ssh command has.
#
# The profile starts an agent and asks for the key whenever it finds no live
# one (linux-profile.ps1), and these calls have no terminal to ask on -- and
# one runs every half minute, which would leave an agent behind each time. So
# it is handed the host's shared agent like a pane is (remote_agent_env) or,
# without one, a stand-in it takes for live: /dev/null for the socket and the
# shell's own pid. Nothing here uses the agent.
#
# It also gets the user session's variables (remote_session_env).
remote_profile_command() {
  local a="$REMOTE_AGENT_DIR"
  printf 'p="$(cat "%s/agent.pid" 2>/dev/null)"; ' "$a"
  printf 'if [ -S "%s/agent.sock" ] && [ -n "$p" ] && [ -d "/proc/$p" ]; then export SSH_AUTH_SOCK="%s/agent.sock" SSH_AGENT_PID="$p"; ' \
    "$a" "$a"
  printf 'else export SSH_AUTH_SOCK=/dev/null SSH_AGENT_PID=$$; fi; '
  remote_session_env
  printf 'PWSH_LEAN=1 exec pwsh -NoLogo -Command %s' "$(sq "$1")"
}

# remote_session_env
# Put in front of a remote command, on a pane (remote_run) or not
# (remote_profile_command): sets the user session's XDG_RUNTIME_DIR and
# DBUS_SESSION_BUS_ADDRESS, as a login session would, when the command has
# none and the host has them to give. An ssh command may lack both.
#
# XDG_RUNTIME_DIR is where paperboy.nvim's daemon writes its count and
# Get-PaperboyUnread.sh reads it, so both find the same file. The bus in it is
# where systemctl/systemd-run --user reach the user's systemd (Start-Frontend,
# prefix,a, runs the frontend in a scope there), and the keyring behind it
# holds az's token (az devops login) and Paperboy's password.
remote_session_env() {
  printf '[ -n "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "/run/user/$(id -u)" ] || export XDG_RUNTIME_DIR="/run/user/$(id -u)"; '
  printf '[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ ! -S "${XDG_RUNTIME_DIR:-}/bus" ] || export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"; '
}

# remote_agent_unlock <target> [<key>]
# Makes sure the host's shared agent is running and holding the key, asking
# for the password when it is not: Unlock-SshAgent.sh, run on the host. Needs
# a terminal -- ssh-add reads the password from it -- so it runs in
# New-SshSession.sh's popup, through the master connection the popup has just
# made, and in each new pane before its own ssh (Unlock-RemoteKey.sh). -q
# because a pane runs it every time: it keeps ssh's "Shared connection ...
# closed" off the pane, and leaves the password prompt, which comes from the
# remote's ssh-add, alone.
#
# The script is sent as text rather than run from the host's ~/.modules, so a
# host whose checkout is older still gets this version.
#
# <key>, a path on the remote, replaces the default key and its condition:
# git-radar's failure popup names the key the host's git would have tried for
# one repository's remote (Show-GitFailure.sh).
#
# Exits with ssh-add's status: non-zero when the password was never given.
remote_agent_unlock() {
  local target=$1 key=${2:-} script
  script="$(cat "$(dirname "$REMOTE_SSH")/Unlock-SshAgent.sh")" || return 1
  "$REMOTE_SSH" "${SSH_OPTS[@]}" -q -t "$target" \
    "sh -c $(sq "$script") sh $(sq "$key")"
}
