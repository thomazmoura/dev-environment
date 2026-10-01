#!/usr/bin/env bash
# Decides which optional status bar segments this machine draws, once per
# config load (tmux.conf runs it in the background, so on every reload too):
#
#   @paperboy_enabled   when $PAPERBOY_EWS_URL is set (paperboy.nvim's inbox)
#   @workhorse_enabled  when $WORKHORSE_TMUX_QUERY_ID is set (the Azure DevOps
#                       query Get-WorkhorseStatusCached.sh shows)
#
# The status formats draw each segment only while its option is set, so on a
# machine without that configuration nothing is shown and no job is started.
#
# Both variables usually come from the PowerShell profile (~/.profile.ps1),
# which the tmux server's environment does not have, so they are read through
# a lean pwsh, like Start-PaperboyUnread.sh does. A query id found only there
# is copied into tmux's global environment, where the status job reads it
# (@workhorse_from_profile remembers that, so the copy goes away with it).
set -uo pipefail

# A copy made by an earlier run is not configuration of its own
if [ "$(tmux show -gqv @workhorse_from_profile)" = 1 ]; then
  unset WORKHORSE_TMUX_QUERY_ID
fi

paperboy=${PAPERBOY_EWS_URL:-}
workhorse=${WORKHORSE_TMUX_QUERY_ID:-}

if command -v pwsh >/dev/null; then
  # The profile may print on its own: only the marked line is ours
  line=$(PWSH_LEAN=1 pwsh -NoLogo -Command \
    'Write-Output "@segments@$([bool]$env:PAPERBOY_EWS_URL)@$env:WORKHORSE_TMUX_QUERY_ID"' \
    2>/dev/null | grep '^@segments@' | tail -n 1)
  if [ -n "$line" ]; then
    IFS=@ read -r _ _ from_profile workhorse <<<"$line"
    [ "$from_profile" = True ] && paperboy=1 || paperboy=""
  fi
fi

if [ -n "$paperboy" ]; then
  tmux set -g @paperboy_enabled 1
else
  tmux set -gu @paperboy_enabled
fi

if [ -n "$workhorse" ] && [ -n "${WORKHORSE_TMUX_QUERY_ID:-}" ]; then
  tmux set -gu @workhorse_from_profile
elif [ -n "$workhorse" ]; then
  tmux set-environment -g WORKHORSE_TMUX_QUERY_ID "$workhorse"
  tmux set -g @workhorse_from_profile 1
elif [ "$(tmux show -gqv @workhorse_from_profile)" = 1 ]; then
  tmux set-environment -gu WORKHORSE_TMUX_QUERY_ID
  tmux set -gu @workhorse_from_profile
fi

if [ -n "$workhorse" ]; then
  tmux set -g @workhorse_enabled 1
else
  tmux set -gu @workhorse_enabled
fi

tmux refresh-client -S 2>/dev/null
exit 0
