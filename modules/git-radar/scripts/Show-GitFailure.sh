#!/usr/bin/env bash
# Explains a failed fetch, pull or push from the git feed, and offers to unlock
# the key it needed. Runs inside a tmux popup, launched by
# Watch-GitFeed.show_failure.
#
# Usage, as the command of a display-popup (through Invoke-Popup.sh):
#   Show-GitFailure.sh <verb> <session> <repo-root> <message-file> [<ssh-target>]
#
# <ssh-target> is given for a row of an ssh session (prefix+N), whose repository
# is on that host: the retry then runs there, over ssh, and the key offered is
# the host's own -- the one the host would try for that remote, unlocked in its
# shared agent the way the session's panes unlock theirs (remote_agent_unlock in
# modules/tmux/scripts/ssh-helpers.sh).
#
# <verb> is fetch, pull or push. It names the failure in the banner and is what
# the retry below re-runs -- a passphrase is just as likely to be what stopped a
# push as a fetch, so the unlock offer belongs to all three rather than to the
# one that happened to need it first.
#
# Why a popup and not the pane: the feed's column is 12% of the window in the
# default layout, so a git error rendered on a row is truncated into nonsense.
# The popup is also the only place a passphrase may be *typed*. The feed pane is
# a curses screen, and curses repaints differentially -- anything written to that
# tty behind its back is never painted over, which is exactly how ssh's
# "Enter passphrase" prompts used to end up welded to the pane. The commands
# themselves now run with BatchMode so they can never prompt at all (see
# fetch_env in Watch-GitFeed.py); this is where the prompt is allowed to happen
# instead, because a popup is its own pty and takes its corruption with it when
# it closes.
#
# Unlocking is on demand and only ever once: nothing is added to the agent at
# login beyond whatever the shell profile already loads, and the only key
# offered here is one this host would actually have tried for this remote and
# that the agent does not already hold. So a repository whose key is already
# loaded never asks, and a second passphrase is never requested for a key that
# would not have helped.
set -euo pipefail

verb=${1:?verb}
session=${2:?session}
root=${3:-}
message_file=${4:-}
target=${5:-}

if [ -n "$target" ]; then
  source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../tmux/scripts/ssh-helpers.sh"
fi

# in_repo <git-args...>
# git in the row's repository, wherever it is. On a remote it runs under sh
# with the host's shared agent and the same no-prompt environment
# Watch-GitFeed's own ssh command gives it (git_remote.op_argv) -- which is
# harmless for the probes, and what the retry needs.
in_repo() {
  if [ -z "$target" ]; then
    git -C "$root" "$@"
    return
  fi
  local line arg
  line="GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes' SSH_ASKPASS_REQUIRE=never git -C $(sq "$root")"
  for arg in "$@"; do line+=" $(sq "$arg")"; done
  ssh "${SSH_OPTS[@]}" -o BatchMode=yes -q "$target" "sh -c $(sq "$(remote_agent_env)$line")" </dev/null
}

# The retry is the operation that failed, not always a fetch. Spelled out per
# verb rather than assembled from the argument, so this script decides what it
# is willing to run and an unexpected verb retries nothing at all.
#
# push asks about the upstream the same way Watch-GitFeed does, and for the same
# reason: the first attempt was the one that would have created it, so after an
# authentication failure there is still no upstream for a plain push to find.
retry=()
case "$verb" in
  fetch) retry=(--no-optional-locks fetch --quiet) ;;
  pull)  retry=(pull --ff-only --quiet) ;;
  push)
    if [ -n "$root" ] && ! in_repo rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      branch=$(in_repo branch --show-current 2>/dev/null || true)
      # An empty branch is a detached HEAD, and leaves retry empty: there is
      # nothing to name as the upstream, so there is nothing to offer a key for.
      if [ -n "$branch" ]; then
        retry=(push --set-upstream origin "$branch" --quiet)
      fi
    else
      retry=(push --quiet)
    fi
    ;;
esac

# The message is passed as a file, not an argument: git's stderr is multi-line
# and quoting it through display-popup's shell would be a losing game.
message=""
if [ -n "$message_file" ] && [ -r "$message_file" ]; then
  message=$(cat "$message_file")
  rm -f "$message_file"
fi

hold() { read -rsn1 -p "Press any key to close..." _ || true; }

# --- What the popup says ------------------------------------------------------
printf '\033[1;31m%s failed\033[0m  %s\n' "$verb" "$session"
[ -n "$root" ] && printf '\033[2m%s%s\033[0m\n' "${target:+$target:}" "$root"
printf '\n%s\n\n' "${message:-$verb failed}"

# --- Is this an authentication problem at all? --------------------------------
# Only these get an unlock offer. A network outage or a missing remote is not
# something another key would fix, and offering one there would train the habit
# of typing a passphrase at any error.
is_auth_failure() {
  grep -qiE 'permission denied|authentication failed|could not read (Username|Password)|no matching host key|publickey' <<<"$message"
}

# --- Which key would have helped ----------------------------------------------
# `ssh -G` answers with the identity files *this host would actually try* for
# this remote, config and defaults included -- far better than guessing at
# ~/.ssh/id_*. A candidate is one of those that exists on disk and whose
# fingerprint the agent does not already hold: a key already loaded plainly did
# not work, so re-adding it would just cost a passphrase for nothing.
#
# Of the candidates, the one offered is the first the server says it would
# accept. Being first in ssh's list is not enough: GitHub may know only a
# host's id_ed25519 while id_rsa comes first, and unlocking id_rsa would cost a
# passphrase and still fail the retry. So the probe makes one connection with
# the agent out of the way, in which ssh offers each key's public half; the
# server answers "accepts key" for the ones it knows, and BatchMode stops ssh
# there, when it would need the passphrase to go on. The accepted keys are
# picked out by fingerprint -- the one field every OpenSSH's -v prints on its
# "Offering public key" line. A server that saw the keys and accepts none of the
# candidates gets no offer at all; only when the connection never got as far as
# offering one (an older ssh, a network hiccup) is the first candidate offered,
# as before.
#
# The same question for a remote row has to be asked *on the host*: its keys,
# its ~/.ssh/config and its shared agent are all over there. So the probe is a
# POSIX sh script, run here for a local row and over ssh for a remote one, and
# the two can never disagree about which key to offer. It takes the repository
# as $1 and compares against the agent in SSH_AUTH_SOCK, and prints the key, or
# nothing when no key would help.
#
# The .pub file is fingerprinted first: reading the private key works for
# OpenSSH-format keys but is the path that could ask for a passphrase, which is
# the one thing this probe must never do. https and friends have no key to add.
key_probe='
url=$(git --no-optional-locks -C "$1" remote get-url origin 2>/dev/null) || exit 1
case $url in
  ssh://*) dest=${url#ssh://}; dest="ssh://${dest%%/*}" ;;
  *://*)   exit 1 ;;
  *:*)     dest=${url%%:*} ;;
  *)       exit 1 ;;
esac
loaded=$(ssh-add -l 2>/dev/null)
candidates=$(ssh -G "$dest" 2>/dev/null | sed -n "s/^identityfile //p" |
while IFS= read -r file; do
  case $file in "~"/*) file="$HOME/${file#"~/"}" ;; esac
  [ -f "$file" ] || continue
  fp=$({ ssh-keygen -lf "$file.pub" 2>/dev/null || ssh-keygen -lf "$file" 2>/dev/null; } | cut -d" " -f2)
  [ -n "$fp" ] || continue
  case $loaded in *"$fp"*) continue ;; esac
  printf "%s %s\n" "$fp" "$file"
done)
[ -n "$candidates" ] || exit 1
log=$(SSH_AUTH_SOCK= ssh -v -o BatchMode=yes -o IdentitiesOnly=yes \
  -o PreferredAuthentications=publickey -o ConnectTimeout=5 "$dest" true </dev/null 2>&1)
case $log in
  *"Offering public key"*) ;;
  *) printf "%s\n" "$candidates" | head -n 1 | cut -d" " -f2-; exit 0 ;;
esac
accepted=$(printf "%s\n" "$log" |
  awk "/Offering public key/ { offer = \$0 } /Server accepts key/ { print offer }")
printf "%s\n" "$candidates" | while read -r fp file; do
  case $accepted in *"$fp"*) printf "%s" "$file"; break ;; esac
done'

# A missing agent is its own problem here: there is nowhere to put the key.
candidate_key() {
  local status=0
  ssh-add -l >/dev/null 2>&1 || status=$?
  [ "$status" -ne 2 ] || return 1
  sh -c "$key_probe" sh "$root"
}

# On the host the shared agent is the one to compare against, and a missing
# one is not a problem: remote_agent_unlock starts it.
remote_candidate_key() {
  local probe="SSH_AUTH_SOCK=\"$REMOTE_AGENT_DIR/agent.sock\"; export SSH_AUTH_SOCK; $key_probe"
  ssh "${SSH_OPTS[@]}" -o BatchMode=yes -q "$target" \
    "sh -c $(sq "$probe") sh $(sq "$root")" </dev/null
}

# The retry, the same way the first attempt ran. Still BatchMode: if the key
# that was just added is not the one this remote wanted, the retry must fail
# rather than start prompting for the next one.
#
# --no-optional-locks belongs to the fetch and to nothing else (see the case
# above): it exists to keep the *sampler* from taking index.lock out from under
# an interactive git, and pull and push are that interactive git.
retry_op() {
  printf '\nretrying %s...\n' "$verb"
  if [ -n "$target" ]; then
    in_repo "${retry[@]}"
  else
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" \
      SSH_ASKPASS_REQUIRE=never \
      git -C "$root" "${retry[@]}"
  fi
}

finish() {
  if retry_op; then
    printf '\033[32m%sed\033[0m\n' "$verb"
    exit 0
  fi
  printf '\033[31mstill unable to %s\033[0m\n' "$verb"
  hold
  exit 1
}

# No retry means no offer: unlocking a key to then do nothing with it would ask
# for a passphrase and give nothing back.
if [ -z "$root" ] || [ ${#retry[@]} -eq 0 ] || ! is_auth_failure; then
  hold
  exit 1
fi

# --- A remote row: the host's key, in the host's shared agent -----------------
# A fetch on that host tries whatever its shared agent holds, and the panes only
# ever put id_rsa there. The key this remote wants may be another one entirely,
# so it is found the way a local row's is, only on the host (key_probe), and
# goes into that same shared agent. The host is recorded like Unlock-RemoteKey.sh
# records it, so an agent started here dies with the host's last session.
if [ -n "$target" ]; then
  key=$(remote_candidate_key) || key=""
  if [ -z "$key" ]; then
    hold
    exit 1
  fi
  printf '\033[1mu\033[0m  unlock %s on %s and retry\n' "$key" "$target"
  printf '\033[2many other key  close\033[0m\n'
  read -rsn1 answer || answer=""
  [ "$answer" = "u" ] || exit 1
  printf '\n'
  add_agent_target "$target"
  if ! remote_agent_unlock "$target" "$key"; then
    printf '\n\033[31mkey not added\033[0m\n'
    hold
    exit 1
  fi
  finish
fi

# --- A local row: which key would have helped, offered -------------------------
key=$(candidate_key) || key=""
if [ -z "$key" ]; then
  hold
  exit 1
fi

printf '\033[1mu\033[0m  unlock %s and retry\n' "${key/#$HOME/\~}"
printf '\033[2many other key  close\033[0m\n'
read -rsn1 answer || answer=""
[ "$answer" = "u" ] || exit 1

printf '\n'
# The prompt lands here, on the popup's own pty. Once the key is in the agent
# every later fetch -- including F over every session -- finds it there, so this
# is asked at most once per agent.
if ! ssh-add "$key"; then
  printf '\n\033[31mkey not added\033[0m\n'
  hold
  exit 1
fi

finish
