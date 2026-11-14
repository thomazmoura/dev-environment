#!/usr/bin/env bash
# Where this machine keeps its projects: the folder prefix+/ (New-CodeSession.sh)
# lists, prefix+C-c opens, and common.conf hands every pane as $CODE_FOLDER.
# Sourced for code_folder, or run to print it (common.conf, at load).
#
# $CODE_FOLDER when it is set (export it in ~/.profile on a machine whose
# projects live somewhere unusual), else the first of ~/code, ~/git and /Git
# that exists, else ~. The same rule as kernel-profile.ps1 and tmux_link.py's
# code_folder(), which a peer asks over ssh -- those two, with no profile behind
# them, ask this tmux server's $CODE_FOLDER (set from this script) before guessing.
#
# Always the real path, symlinks resolved: tmux's #{pane_current_path}, git and
# /proc report the resolved directory, so a ~/code that is a link to /Git (the
# folder Kaspersky leaves alone on the company's machines) has to come out as
# /Git or no path built from it would match theirs.

code_folder() {
  local candidate
  for candidate in "${CODE_FOLDER:-}" "$HOME/code" "$HOME/git" /Git "$HOME"; do
    [ -n "$candidate" ] || continue
    candidate="${candidate/#\~/$HOME}"
    if [ -d "$candidate" ]; then
      readlink -f "$candidate"
      return 0
    fi
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  code_folder
fi
