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
# A dev-environment remote gets exactly that pwsh call. Any other host gets its
# login shell -- a login shell so the PATH additions in its profile (nvm and
# the like) are there -- running the command, and staying afterwards for
# no-exit. `$SHELL` is left for the remote to expand.
remote_run() {
  local pane=$1 command=$2 no_exit=${3:-}
  if ssh_is_devenv "$pane"; then
    pwsh_invocation "$command" "$no_exit"
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
ssh_command() {
  local pane=$1 command=$2 no_exit=${3:-}
  local target dir remote opt line="ssh -t"
  target="$(ssh_option "$pane" @ssh_target)"
  dir="$(ssh_option "$pane" @ssh_dir)"
  remote="cd $(sq "$dir") && $(remote_run "$pane" "$command" "$no_exit")"
  for opt in "${SSH_OPTS[@]}"; do
    line+=" $(printf '%q' "$opt")"
  done
  printf '%s %q %q && exit' "$line" "$target" "$remote"
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
