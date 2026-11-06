#!/usr/bin/env bash
# Draws the tmux theme: the powerline status bar and the colours of the pane
# borders, messages, copy mode and the clock, all in one theme colour on dark
# greys. (This used to be the tmux-power plugin; its look is kept.)
#
# Usage:
#   Set-Theme.sh                         the global theme, in @theme's colour
#   Set-Theme.sh -t <session> <colour>   that session and its windows in
#                                        <colour>, over the global theme
#
#   The global form runs at every config load, from the end of
#   modules/tmux/common.conf. The -t form is Set-SshTheme.sh's, which gives ssh
#   and Docker sessions a colour of their own.
#
# What the bar draws, left to right:
#   [colour] @status_left_host ▶ [grey] session:window ▶   (the window list is
#   not drawn; @status_after_windows goes after it, see wsl2/tmux.conf)
#   ... @toast @status_right_lead ◀ [grey] @status_right_inner ◀ [colour]
#   @status_right_outer
# Each of those is a user option, expanded with E: when the bar is drawn, so
# they can be set anywhere in the config, in any order, and changed later
# without running this again. Only @theme is read here: a theme name from the
# table below or a #rrggbb colour. It has to be set before common.conf is
# sourced (see the entry points).
#
# The session is drawn as its prefix+$ label when it has one (@session_label,
# see Set-SessionLabel.sh), with the active window's index after it.
#
# All the options are written in one tmux call, as arguments, so the formats
# need no escaping and the bar never shows a half-written theme.
set -uo pipefail

# The greys, darkest first: the bar, the inner segments, the borders, the text.
g0='#262626'
g2='#3a3a3a'
g3='#444444'
g4='#626262'
right_arrow=''
left_arrow=''

theme_colour() {
  case "${1,,}" in
    gold) echo '#ffb86c' ;;
    redwine) echo '#b34a47' ;;
    moon) echo '#00abab' ;;
    forest) echo '#228b22' ;;
    violet) echo '#9370db' ;;
    snow) echo '#fffafa' ;;
    coral) echo '#ff7f50' ;;
    sky) echo '#87ceeb' ;;
    everforest) echo '#a7c080' ;;
    \#*) echo "$1" ;;
    *) echo '#87ceeb' ;;
  esac
}

target=""
while getopts "t:" opt; do
  case "$opt" in
    t) target=$OPTARG ;;
    *) exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [ -n "$target" ]; then
  tc="$(theme_colour "${1:-}")"
else
  tc="$(theme_colour "$(tmux show-options -gqv @theme 2>/dev/null)")"
fi

session='#{?@session_label,#{@session_label},#S}:#I'
status_left="#[fg=$g0,bg=$tc,bold] #{E:@status_left_host} "
status_left+="#[fg=$tc,bg=$g2,none]$right_arrow#[fg=$tc,bg=$g2]  $session "
status_left+="#[fg=$g2,bg=$g0,none]$right_arrow"

# #{@toast} and not #{E:@toast}: its #[...] styles apply either way, but E:
# would also expand a #{...} in the message text (see Show-Toast.sh).
status_right='#{@toast}#{E:@status_right_lead}'
status_right+="#[fg=$g2,bg=$g0,none]$left_arrow#[fg=$tc,bg=$g2] #{E:@status_right_inner} "
status_right+="#[fg=$tc,bg=$g2,none]$left_arrow#[fg=$g0,bg=$tc] #{E:@status_right_outer} "

# The options holding the theme colour, which a session can shadow.
session_values=(
  status-left "$status_left"
  status-right "$status_right"
  message-style "fg=$tc,bg=$g0"
  message-command-style "fg=$tc,bg=$g0"
  display-panes-active-colour "$tc"
  @theme_colour "$tc"
)
window_values=(
  window-status-style "fg=$tc,bg=$g0,none"
  window-status-last-style "fg=$tc,bg=$g0,bold"
  window-status-activity-style "fg=$tc,bg=$g0,bold"
  window-status-bell-style "fg=$tc,bg=$g0,bold"
  pane-active-border-style "fg=$tc,bg=default"
  mode-style "bg=$tc,fg=$g4"
  clock-mode-colour "$tc"
)

write=()
if [ -z "$target" ]; then
  for ((i = 0; i < ${#session_values[@]}; i += 2)); do
    write+=(set-option -g "${session_values[i]}" "${session_values[i + 1]}" \;)
  done
  for ((i = 0; i < ${#window_values[@]}; i += 2)); do
    write+=(set-option -gw "${window_values[i]}" "${window_values[i + 1]}" \;)
  done

  # Only the windows' tail is drawn, after the last one: wsl2/tmux.conf's
  # Workhorse segment, where it sets @status_after_windows. A prefix+z stash
  # sets the same format on its own window (Switch-PaneZoom.sh).
  after_windows='#{?window_end_flag,#{E:@status_after_windows},}'
  write+=(
    set-option -g status on \;
    set-option -g status-interval 1 \;
    set-option -g status-style "fg=$g4,bg=$g0" \;
    set-option -g status-left-length 150 \;
    set-option -g status-right-length 150 \;
    set-option -g display-panes-colour "$g3" \;
    set-option -gw window-status-format "$after_windows" \;
    set-option -gw window-status-current-format "$after_windows" \;
    set-option -gw window-status-separator '' \;
    set-option -gw pane-border-style "fg=$g3,bg=default" \;
    set-option -gw clock-mode-style 24 \;
  )
else
  target="=$target:"
  for ((i = 0; i < ${#session_values[@]}; i += 2)); do
    write+=(set-option -t "$target" "${session_values[i]}" "${session_values[i + 1]}" \;)
  done
  # Window options can only be set per window. A prefix+z stash draws nothing
  # of the theme (see Switch-PaneZoom.sh), so it is left alone.
  while IFS='|' read -r window stash_for; do
    [ -z "$stash_for" ] || continue
    for ((i = 0; i < ${#window_values[@]}; i += 2)); do
      write+=(set-option -w -t "$window" "${window_values[i]}" "${window_values[i + 1]}" \;)
    done
  done < <(tmux list-windows -t "$target" -F '#{window_id}|#{@zoom_origin}' 2>/dev/null)
fi
unset 'write[-1]' # the last command's \;

tmux "${write[@]}" >/dev/null 2>&1
exit 0
