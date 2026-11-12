#!/usr/bin/env bash
# The phone's ssh-agent, for as long as Termux has a session open: each key's
# passphrase is typed once while Termux is open, and is gone once its last
# session closes -- a phone left with Termux closed holds no unlocked key.
#
# Installed as $PREFIX/bin/termux-ssh-agent by Termux/termux-setup.sh, which
# also ends ~/.ssh/config with
#   Match exec "$PREFIX/bin/termux-ssh-agent ensure"
#     IdentityAgent ~/.ssh/agent/agent.sock
#     AddKeysToAgent yes
# so every ssh (tmux-link's, git's, one typed by hand) first makes sure the
# agent is up, then uses it and adds each key the first time it unlocks it.
# When ensure fails, the Match doesn't apply and ssh goes on without an agent.
#
# Usage: termux-ssh-agent ensure        start the agent unless it runs (ssh's
#                                       Match exec; exit 0 once it answers)
#        termux-ssh-agent watch <pid>   the agent's own command (internal)
#
# Started from ssh rather than from ~/.bashrc, so an agent Android killed while
# the phone slept (its phantom-process and low-memory killers do) comes back on
# the next ssh, at the cost of asking that key's passphrase once more. That is
# also why nothing runs per session: every process left running is one more
# for Android to kill.
#
# How the agent knows when the last session is gone: Termux's sessions are the
# children of its app process (com.termux). ensure finds that process, and the
# agent runs with `watch <its pid>` as its command, which polls for its
# children and stops the agent once there are none -- Exit in the
# notification, the last tab closed, Android killing the app. ssh-agent also
# ends by itself when its command dies, so a killed watcher takes the agent
# with it. Both ends hold ~/.ssh/agent/start.lock while they start or stop it.
#
# ~/.ssh/agent/log has a line for each agent started and ended, and one when an
# agent was found gone without its watcher ending it: that's Android killing it.
#
# The termux-services ssh-agent service is the opposite -- an agent that
# outlives every session -- and termux-setup.sh leaves it disabled.

set -u

dir="$HOME/.ssh/agent"
sock="$dir/agent.sock"
running="$dir/running"
log="$dir/log"

note() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$log" 2>/dev/null
}

# 2 is "could not connect": no agent, or a socket one left behind
answers() {
  SSH_AUTH_SOCK="$sock" ssh-add -l >/dev/null 2>&1
  [ $? -ne 2 ]
}

is_app() {
  local name
  name="$(tr '\0' '\n' 2>/dev/null <"/proc/$1/cmdline" | head -n 1)"
  [ "$name" = "com.termux" ]
}

# Field 4 of /proc/<pid>/stat, after the name in parentheses (which may hold
# spaces and parentheses itself)
parent_of() {
  local stat rest
  stat="$(<"/proc/$1/stat")" 2>/dev/null || return 1
  rest="${stat##*) }"
  set -- $rest
  printf '%s' "$2"
}

# The Termux app's pid: an ancestor of this ssh when it runs in a Termux
# session, else (inside the phone's own tmux, whose server left the session)
# any com.termux process of ours.
find_app() {
  local pid=$$ proc
  while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
    if is_app "$pid"; then printf '%s' "$pid"; return 0; fi
    pid="$(parent_of "$pid")" || break
  done
  for proc in /proc/[0-9]*; do
    pid="${proc#/proc/}"
    if is_app "$pid"; then printf '%s' "$pid"; return 0; fi
  done
  return 1
}

# Whether the app still runs and has a session open
has_sessions() {
  local app=$1 stat rest
  is_app "$app" || return 1
  for proc in /proc/[0-9]*/stat; do
    stat="$(<"$proc")" 2>/dev/null || continue
    rest="${stat##*) }"
    set -- $rest
    [ "$2" = "$app" ] && return 0
  done
  return 1
}

case "${1:-}" in
  ensure)
    command -v ssh-agent >/dev/null 2>&1 || exit 1
    umask 077
    mkdir -p "$dir" && chmod 700 "$dir" || exit 1
    # ssh's started together (tmux-link's) start one agent
    exec 9>"$dir/start.lock"
    flock -w 10 9 || exit 1
    answers && exit 0

    app="$(find_app)" || exit 1
    if [ -e "$running" ]; then
      note "the agent started $(cat "$running" 2>/dev/null) was gone without Termux closing (killed by Android?)"
    fi
    rm -f "$sock"
    self="$(readlink -f "${BASH_SOURCE[0]}")"
    setsid nohup ssh-agent -a "$sock" "$self" watch "$app" \
      </dev/null >/dev/null 2>&1 9>&- &
    # Ready before ssh goes on
    for _ in $(seq 30); do
      if answers; then
        date '+%F %T' >"$running"
        note "started, for the sessions of Termux (pid $app)"
        # Only the recent past is of any use
        tail -n 200 "$log" >"$log.tmp" 2>/dev/null && mv "$log.tmp" "$log"
        exit 0
      fi
      sleep 0.1
    done
    echo "termux-ssh-agent: the agent didn't start; ssh will ask for passphrases every time." >&2
    exit 1
    ;;
  watch)
    app="${2:?app pid}"
    agent="${SSH_AGENT_PID:?run by ssh-agent}"
    while :; do
      while has_sessions "$app" && kill -0 "$agent" 2>/dev/null; do sleep 10; done
      kill -0 "$agent" 2>/dev/null || exit 0
      exec 9>"$dir/start.lock"
      flock 9
      # A session that opened while this waited for the lock keeps the agent
      has_sessions "$app" || break
      exec 9>&-
    done
    kill "$agent" 2>/dev/null
    for _ in $(seq 20); do [ -S "$sock" ] || break; sleep 0.1; done
    rm -f "$sock" "$running"
    note "ended: no Termux session open"
    exit 0
    ;;
  *)
    echo "Usage: termux-ssh-agent ensure" >&2
    exit 2
    ;;
esac
