#!/usr/bin/env bash
# Explains a failed fetch, pull or push from the git feed, and offers to unlock
# the key it needed. Runs inside a tmux popup, launched by
# Watch-GitFeed.show_failure.
#
# Usage, as the command of a display-popup (through Invoke-Popup.sh):
#   Show-GitFailure.sh <verb> <session> <repo-root> <message-file>
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
    if [ -n "$root" ] && ! git -C "$root" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      branch=$(git -C "$root" branch --show-current 2>/dev/null || true)
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
[ -n "$root" ] && printf '\033[2m%s\033[0m\n' "$root"
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
remote_host() {
  local url
  url=$(git --no-optional-locks -C "$root" remote get-url origin 2>/dev/null) || return 1
  case "$url" in
    ssh://*) url=${url#ssh://}; url=${url%%/*}; printf '%s' "${url##*@}" ;;
    *://*)   return 1 ;;                      # https and friends: no key to add
    *:*)     url=${url%%:*}; printf '%s' "${url##*@}" ;;
    *)       return 1 ;;
  esac
}

fingerprint() {
  # The .pub file first: reading the private key works for OpenSSH-format keys
  # but is the path that could ask for a passphrase, which is the one thing this
  # probe must never do.
  ssh-keygen -lf "$1.pub" 2>/dev/null || ssh-keygen -lf "$1" 2>/dev/null || true
}

candidate_key() {
  local host loaded file expanded fp
  host=$(remote_host) || return 1
  # A missing agent is its own problem: there is nowhere to put the key.
  loaded=$(ssh-add -l 2>/dev/null) || return 1
  while read -r _ file; do
    expanded=${file/#\~/$HOME}
    [ -f "$expanded" ] || continue
    fp=$(fingerprint "$expanded" | awk '{print $2}')
    [ -n "$fp" ] || continue
    grep -qF -- "$fp" <<<"$loaded" && continue
    printf '%s' "$expanded"
    return 0
  done < <(ssh -G "git@$host" 2>/dev/null | grep '^identityfile ')
  return 1
}

key=""
# No retry means no offer: unlocking a key to then do nothing with it would ask
# for a passphrase and give nothing back.
if [ -n "$root" ] && [ ${#retry[@]} -gt 0 ] && is_auth_failure; then
  key=$(candidate_key) || key=""
fi

if [ -z "$key" ]; then
  hold
  exit 1
fi

# --- Offer the unlock ---------------------------------------------------------
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

printf '\nretrying %s...\n' "$verb"
# Still BatchMode: if the key that was just added is not the one this remote
# wanted, the retry must fail rather than start prompting for the next one.
#
# --no-optional-locks belongs to the fetch and to nothing else (see the case
# above): it exists to keep the *sampler* from taking index.lock out from under
# an interactive git, and pull and push are that interactive git.
if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" \
    SSH_ASKPASS_REQUIRE=never \
    git -C "$root" "${retry[@]}"; then
  printf '\033[32m%sed\033[0m\n' "$verb"
  exit 0
fi

printf '\033[31mstill unable to %s\033[0m\n' "$verb"
hold
exit 1
