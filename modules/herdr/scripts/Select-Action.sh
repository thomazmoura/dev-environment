#!/usr/bin/env bash
# Fuzzy-find a workspace action and run it in a new tab.
#
# The herdr counterpart of the tmux bindings in modules/wsl2/tmux.conf: the
# prefix+t agent menu, and prefix+T / prefix+a / prefix+W for the .NET watch
# tests, the Angular+.NET frontend and the Windows service. Where tmux splits
# the current window, this opens a tab, because that is the unit a herdr
# workspace is built out of and the unit prefix+t can find again by name.
#
# The first three actions are the same helpers Open-CodeWorkspace.sh uses, so
# prefix+ctrl+n is exactly "Open Agent, Open NeoVim and Open Terminal at once".
# All of it lives in workspace-actions.sh.
#
# Bound to prefix+shift+s as a popup command in modules/herdr/config.toml.

set -uo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/workspace-actions.sh"

# --start-agent is the detached half of the "Open Agent" row: see the handoff
# at the end of the picker below. Nothing is left to hold a popup open for a
# keypress by then, so failures toast instead.
if [ "${1:-}" = "--start-agent" ]; then
  die() { warn "$@"; }
  workspace_id="${2:-}"
  cwd="${3:-}"
  agent_kind="${4:-}"

  new_tab "$workspace_id" "$cwd" "$agent_kind" --focus
  start_agent "$tab_pane" "$agent_kind" "$(basename "$cwd" | tr '.' '_')"
  exit 0
fi

require_tools herdr fzf python3

# Rows are "<action>\t<label>"; fzf shows and matches on the second field only,
# so the key rides along without cluttering the list. Same trick as
# Select-Tab.sh and Select-Workspace.sh.
rows=$(printf '%s\n' \
  $'agent\tOpen Agent' \
  $'nvim\tOpen NeoVim' \
  $'terminal\tOpen Terminal' \
  $'tests\tRun Tests' \
  $'frontend\tRun Frontend' \
  $'winservice\tRun Windows Service')

selection=$(printf '%s\n' "$rows" \
  | fzf --reverse --prompt="action> " --height=100% \
        --delimiter=$'\t' --with-nth=2..) || exit 0
[ -n "$selection" ] || exit 0
action=${selection%%$'\t'*}

# Every action needs somewhere to happen. The popup is session-modal and owns
# no pane, so this reads the focused pane out of the API rather than $PWD.
read -r workspace_id cwd <<<"$(focused_target)"
[ -n "$workspace_id" ] || die "Could not tell which workspace is focused"
[ -d "$cwd" ] || die "The focused pane reports no usable directory: '$cwd'"

case "$action" in
  agent)
    agent_kind=$(pick_agent_kind) || exit 0
    [ -n "$agent_kind" ] || exit 0
    if [ "$agent_kind" = "NeoVim" ]; then
      # The no-agent choice from the shared picker: the editor tab is what the
      # user is really asking for.
      open_nvim_tab "$workspace_id" "$cwd" --focus
      exit 0
    fi
    # `herdr agent start` only returns once the agent is ready for prompts, and
    # the popup lives exactly as long as this script. So the tab and the agent
    # are handed to a detached copy and this process exits: the popup closes on
    # the agent selection and the tab fills in behind it. setsid keeps the work
    # out of the popup's session so tearing down its pty does not take it along,
    # and stdio goes to /dev/null because no terminal outlives this exit.
    setsid -f "$(readlink -f "${BASH_SOURCE[0]}")" --start-agent \
      "$workspace_id" "$cwd" "$agent_kind" </dev/null >/dev/null 2>&1
    ;;
  nvim)       open_nvim_tab "$workspace_id" "$cwd" --focus ;;
  terminal)   open_terminal_tab "$workspace_id" "$cwd" --focus ;;
  tests)      run_task_tab "$workspace_id" "$cwd" ".NET Watch Test" "$TESTS_COMMAND" ;;
  frontend)   run_task_tab "$workspace_id" "$cwd" "Frontend (.NET + Angular)" "$FRONTEND_COMMAND" ;;
  winservice) run_task_tab "$workspace_id" "$cwd" ".NET Windows Service" "$WINSERVICE_COMMAND" ;;
  *)          die "Unknown action: $action" ;;
esac
