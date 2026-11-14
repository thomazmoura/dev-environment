#!/usr/bin/env bash
# The ssh and Docker sessions' theme, now every session's: Set-SessionTheme.sh.
# Kept under this name for New-SshSession.sh and the hooks an older config set.
exec "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/Set-SessionTheme.sh" "$@"
