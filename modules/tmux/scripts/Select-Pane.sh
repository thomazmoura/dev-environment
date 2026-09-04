#!/usr/bin/env bash
# Flattens every pane of every session into a single fzf list and switches to the chosen one.
# The pane label comes from the @pane_label pane option set by the layout bindings, falling
# back to the window name for panes created outside them.
#
# Usage: Select-Pane.sh
#   Meant to be run from a tmux binding (see `bind t` on tmux.conf), so the tmux commands
#   below act on the client that opened it.
set -euo pipefail

current="$(tmux display-message -p '#{pane_id}')"

selection="$(
  tmux list-panes -a -F $'#{pane_id}\t#{session_name}\t#{?@pane_label,#{@pane_label},#{window_name}}\t#{pane_current_command}' \
    | awk -F'\t' -v current="$current" '
        { ids[NR] = $1; session[NR] = $2; label[NR] = $3; command[NR] = $4
          if (length($2) > sessionWidth) sessionWidth = length($2)
          if (length($3) > labelWidth) labelWidth = length($3) }
        END {
          for (line = 1; line <= NR; line++)
            printf "%s\t%-*s - %-*s - %s%s\n", ids[line], sessionWidth, session[line], \
              labelWidth, label[line], command[line], (ids[line] == current ? " *" : "")
        }' \
    | fzf --reverse --delimiter=$'\t' --with-nth=2.. --header='Switch to pane'
)" || exit 0

tmux switch-client -t "${selection%%$'\t'*}"
tmux select-window -t "${selection%%$'\t'*}"
tmux select-pane -t "${selection%%$'\t'*}"
