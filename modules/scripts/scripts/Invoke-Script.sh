#!/usr/bin/env bash
# Runs one script from modules/scripts/library and holds the screen afterwards.
# What the pane opened by prefix+t then s actually runs (see Select-Script.sh),
# and a perfectly good way to run a library script by hand.
#
# Two things it does that `./script` does not:
#
#   * It works out how to run the file, so a library script needs no executable
#     bit and no shebang to be runnable -- committing it is enough. The
#     extension decides (.sh, .ps1, .py); anything else falls back to its
#     shebang, and then to bash.
#   * It waits for a keypress before returning. The pane closes when its command
#     ends (closing_line in modules/tmux/scripts/tmux-helpers.sh), so without
#     the pause a script that finishes in a second would take its own output
#     with it. Same pause notice_command uses, for the same reason.
#
# Usage: Invoke-Script.sh <script> [args...]
set -uo pipefail

script=${1:-}
[ -n "$script" ] || { printf 'Invoke-Script.sh: expected a script to run\n' >&2; exit 2; }
shift

if [ ! -f "$script" ]; then
  printf 'Invoke-Script.sh: no such script: %s\n' "$script" >&2
  exit 2
fi

# The extension first: it is what the author chose, and it is right even for a
# file that also carries a shebang. Only when there is nothing to go on does the
# shebang get a say -- and an extensionless script without one is bash, which is
# what a plain list of commands is.
case "$script" in
  *.sh) runner=(bash "$script") ;;
  *.ps1) runner=(pwsh -NoProfile -File "$script") ;;
  *.py) runner=(python3 "$script") ;;
  *)
    if [ "$(head -c 2 "$script")" = '#!' ]; then
      # Exec'd through its own shebang. A library script is not required to be
      # executable, so chmod rather than fail on one that is not.
      [ -x "$script" ] || chmod +x "$script" 2>/dev/null
      runner=("$script")
    else
      runner=(bash "$script")
    fi
    ;;
esac

if ! command -v "${runner[0]}" >/dev/null && [ "${runner[0]}" != "$script" ]; then
  printf 'Invoke-Script.sh: %s is not installed, needed to run %s\n' \
    "${runner[0]}" "$script" >&2
  read -rsn1 -p "Press any key to close..." _
  exit 127
fi

"${runner[@]}" "$@"
status=$?

# Only on a failure: a clean run's last line is the script's own, which is what
# you opened the pane to read.
[ "$status" -eq 0 ] || printf '\nExited with status %s\n' "$status"

printf '\n'
read -rsn1 -p "Press any key to close..." _
exit "$status"
