#!/bin/sh
# Prints the ssh key that would get a repository's git remote to let us in,
# among the ones the agent does not hold yet -- the key to unlock when a fetch,
# pull or push was turned away. Never asks for a passphrase.
#
# Usage: Find-SshKey.sh <repo> [<remote>]
#   <remote> defaults to origin. Prints the key's path, or nothing -- and exits
#   1 -- when no key would help: an https remote, every candidate already in
#   the agent, or a server that saw the candidates and accepts none of them.
#   Compares against the agent in SSH_AUTH_SOCK.
#
# Run by git-radar's failure popup (Show-GitFailure.sh) -- here for a local
# row, and sent as text over ssh for a remote one, so the host answers with its
# own keys, config and shared agent and the two can never disagree -- and by
# the pwsh git commands that reach a remote (gitf, gitpl, gitpu; see
# Invoke-GitWithSshKey in DevHelpers.psm1). So: POSIX sh, nothing sourced.
#
# `ssh -G` answers with the identity files *this host would actually try* for
# this remote, config and defaults included -- far better than guessing at
# ~/.ssh/id_*. A candidate is one of those that exists on disk and whose
# fingerprint the agent does not already hold: a key already loaded plainly did
# not work, so re-adding it would just cost a passphrase for nothing.
#
# Of the candidates, the one printed is the first the server says it would
# accept. Being first in ssh's list is not enough: GitHub may know only a
# host's id_ed25519 while id_rsa comes first, and unlocking id_rsa would cost a
# passphrase and still fail the retry. So the probe makes one connection with
# the agent out of the way, in which ssh offers each key's public half; the
# server answers "accepts key" for the ones it knows, and BatchMode stops ssh
# there, when it would need the passphrase to go on. The accepted keys are
# picked out by fingerprint -- the one field every OpenSSH's -v prints on its
# "Offering public key" line. Only when the connection never got as far as
# offering one (an older ssh, a network hiccup) is the first candidate printed.
#
# The .pub file is fingerprinted first: reading the private key works for
# OpenSSH-format keys but is the path that could ask for a passphrase, which is
# the one thing this probe must never do.
url=$(git --no-optional-locks -C "$1" remote get-url "${2:-origin}" 2>/dev/null) || exit 1
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
found=$(printf "%s\n" "$candidates" | while read -r fp file; do
  case $accepted in *"$fp"*) printf "%s" "$file"; break ;; esac
done)
[ -n "$found" ] || exit 1
printf "%s" "$found"
