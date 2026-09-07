#!/usr/bin/env bash
# Shared workspace actions for the herdr popup scripts. Sourced, never run.
#
# Open-CodeWorkspace.sh (prefix+ctrl+n) builds a whole workspace and
# Select-Action.sh (prefix+shift+s) opens one tab at a time, but "open the
# NeoVim tab" has to mean the same thing in both -- building a workspace is
# just running the three open_* helpers at once. Everything both need lives
# here so the two cannot drift apart.
#
# Sourced by a caller that has already set `set -uo pipefail`; nothing here
# runs at source time.

# --- Failure reporting -------------------------------------------------------
# die is for failures before anything has been created: the popup is then the
# only surface an error can show up on, so it is held open until the user reads
# it. Callers that keep working after the popup is gone (the detached builds)
# redefine it to warn.
die() { printf '%s\n' "$*" >&2; read -rsn1 -p "Press any key to close..." _; exit 1; }

# warn is for failures once there is a workspace to look at: the user is
# already looking at it, so the message goes to a toast instead of pinning the
# popup on top of it. [ui.toast] delivery = "herdr" routes these in-app.
warn() {
  herdr notification show "herdr" --body "$*" --sound none >/dev/null 2>&1
  exit 0
}

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null || die "Required tool not found: $tool"
  done
}

# --- Reading herdr state -----------------------------------------------------
# pane_id_of reads the pane id out of a `workspace create` or `tab create`
# reply; both wrap the new tab's first pane under result.root_pane.
pane_id_of() {
  printf '%s' "$1" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])'
}

# focused_target prints "<workspace_id> <cwd>": where an action should happen.
# `workspace list` reports no cwd, so this asks `pane list`, which reports cwd,
# workspace_id and focus together -- the same source workspace_at() uses in
# Open-CodeWorkspace.sh. The cwd matters because the Run actions cd into
# sibling globs (*Testes/, *Angular) exactly as the tmux bindings do from
# #{pane_current_path}, so they need the directory the user is really in.
# Falls back to any pane of the focused workspace when no pane claims focus,
# which is what a session-modal popup can leave behind.
focused_target() {
  herdr pane list 2>/dev/null | python3 -c '
import json, sys
try:
    panes = json.load(sys.stdin)["result"]["panes"]
except Exception:
    sys.exit(0)
match = next((p for p in panes if p.get("focused")), None) or (panes[0] if panes else None)
if match is None:
    sys.exit(0)
print(match["workspace_id"], match.get("cwd") or match.get("foreground_cwd") or "")
'
}

# --- Creating tabs -----------------------------------------------------------
# new_tab publishes the new tab's pane in $tab_pane rather than echoing it:
# warn exits, and an exit from inside a $(...) would only end the substitution
# and let the caller carry on with an empty pane id.
tab_pane=""
new_tab() { # <workspace_id> <cwd> <label> <--focus|--no-focus>
  local created
  created=$(herdr tab create --workspace "$1" --cwd "$2" --label "$3" "$4") \
    || warn "Could not create the $3 tab"
  tab_pane=$(pane_id_of "$created") || warn "Could not read the $3 tab pane"
}

# --- The command lines -------------------------------------------------------
# `herdr pane run` types a line into the tab's shell and presses Enter, so each
# of these is one bash-valid command line, passed as a single argument.
#
# They are copies of what the tmux setup already runs, not new inventions:
#   NVIM_COMMAND / TERMINAL_COMMAND  the two panes Set-NeovimLayout.sh builds,
#                                    modules/tmux/scripts/Set-NeovimLayout.sh
#   TESTS_COMMAND                    bind T,  modules/wsl2/tmux.conf
#   FRONTEND_COMMAND                 bind a,  modules/wsl2/tmux.conf
#   WINSERVICE_COMMAND               bind W,  modules/wsl2/tmux.conf
#
# Every one of them ends the tab with its process: quit nvim, stop a watcher or
# exit the shell and the tab goes away, rather than leaving a dead pwsh prompt
# behind. That is why the tmux bindings' -NoExit is dropped from the editor and
# the watchers -- there it keeps a *pane* around inside a layout you still want,
# but a tab that outlives its reason to exist is just something else to close.
#
# The three watchers use `; exit` so a failed or interrupted run closes its tab
# too; the editor uses `&& exit`, so a pwsh that could not even reach nvim
# leaves the error on screen. TERMINAL_COMMAND is the one that keeps -NoExit,
# and must: its -Command is only profile setup, so without it the tab would
# open and vanish in the same breath. Exiting that pwsh still closes the tab.
NVIM_COMMAND="pwsh -Command '$HOME/.modules/neovim-lsp/Install-LanguageServerNodePackages.ps1 && nvim' && exit"
TERMINAL_COMMAND="pwsh -NoExit -Command 'psgit && psfzf && Build-DotnetProjectIfNeeded' && exit"
TESTS_COMMAND='pwsh -Command "cd \"*Testes/\" && dwt"; exit'
FRONTEND_COMMAND='pwsh -Command "cd \"*Angular\" && nvs use auto && Install-NpmIfNeeded && Start-Frontend"; exit'
WINSERVICE_COMMAND='pwsh -Command "cd \"*WinService\" && dotnet watch run"; exit'

# An agent tab is the one that cannot carry an "&& exit": `herdr agent start`
# types the agent's name into the tab's shell itself, so there is no command
# line of ours to append to. This arms the shell beforehand instead. It is
# self-disarming on purpose -- the prompt that appears right after this line
# runs it, which only rewrites PROMPT_COMMAND to "exit"; the *next* prompt is
# the one the agent's departure produces, and that one exits the shell and
# takes the tab with it. Queuing is safe: bash runs the two lines in order
# whether or not `agent start` types before this has been read.
AGENT_EXIT_ARM="PROMPT_COMMAND='PROMPT_COMMAND=exit'"

# --- The actions -------------------------------------------------------------
# Labels match the pane titles the tmux bindings set with `select-pane -T` and
# @pane_label, so prefix+t finds these tabs under the name they already have in
# the other multiplexer.
open_nvim_tab() { # <workspace_id> <cwd> <--focus|--no-focus>
  new_tab "$1" "$2" "NeoVim" "$3"
  herdr pane run "$tab_pane" "$NVIM_COMMAND" >/dev/null
}

open_terminal_tab() { # <workspace_id> <cwd> <--focus|--no-focus>
  new_tab "$1" "$2" "Terminal" "$3"
  # A tab with a plain login shell is still useful, so a missing pwsh costs the
  # profile commands rather than the tab.
  if command -v pwsh >/dev/null 2>&1; then
    herdr pane run "$tab_pane" "$TERMINAL_COMMAND" >/dev/null
  fi
}

# The three Run actions differ only in their label and command line, so they
# share one helper. Always focused: the tmux bindings they mirror leave you
# looking at the pane they just made.
run_task_tab() { # <workspace_id> <cwd> <label> <command>
  new_tab "$1" "$2" "$3" --focus
  herdr pane run "$tab_pane" "$4" >/dev/null
}

# --- Agents ------------------------------------------------------------------
# pick_agent_kind prints the chosen agent kind, or nothing if the user aborted.
# Only kinds herdr knows about that are actually executable here are offered.
pick_agent_kind() {
  local kinds available kind
  kinds=$(herdr agent 2>&1 | sed -n 's/^ *kinds: *//p' | tr '|' '\n')
  [ -n "$kinds" ] || die "Could not read the agent kind list from herdr"

  available=""
  for kind in $kinds; do
    if command -v "$kind" >/dev/null 2>&1; then
      available="${available}${kind}"$'\n'
    fi
  done
  # "NeoVim" is the no-agent choice. herdr kind names are lowercase, so the
  # capitalised spelling is both the label the picker shows and a value that
  # can never collide with a real agent kind.
  if command -v nvim >/dev/null 2>&1; then
    available="${available}NeoVim"$'\n'
  fi
  available=$(printf '%s' "$available" | sed '/^$/d')
  [ -n "$available" ] || die "No supported agent CLI or nvim found in PATH"

  if [ "$(printf '%s\n' "$available" | wc -l)" -eq 1 ]; then
    printf '%s\n' "$available"
    return 0
  fi
  printf '%s\n' "$available" | fzf --reverse --prompt="agent> " --height=100%
}

# start_agent runs an agent of <kind> in <pane>, naming it after <label>.
# `herdr agent start` only exits 0 once the agent is ready for prompts, so this
# is slow enough that callers hand it to a detached process.
start_agent() { # <pane_id> <agent_kind> <label>
  local pane="$1" kind="$2" label="$3" base live agent_name suffix start code

  # Arm the shell before the agent is in front of it, so quitting the agent
  # closes its tab the way every other action's "exit" does. See AGENT_EXIT_ARM.
  herdr pane run "$pane" "$AGENT_EXIT_ARM" >/dev/null

  # Agent names must match [a-z][a-z0-9_-]{0,31} and be unique among live agents.
  base=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')
  base=$(printf '%s' "$base" | sed 's/^[^a-z]*//; s/-*$//')
  base=${base:-project}
  base=${base:0:31}

  live=$(herdr agent list 2>/dev/null | python3 -c '
import json, sys
try:
    print("\n".join(a.get("name") or "" for a in json.load(sys.stdin)["result"]["agents"]))
except Exception:
    pass
')

  agent_name="$base"
  suffix=2
  while printf '%s\n' "$live" | grep -qx "$agent_name"; do
    agent_name="${base:0:29}-$suffix"
    suffix=$((suffix + 1))
  done

  if ! start=$(herdr agent start "$agent_name" --kind "$kind" \
      --pane "$pane" 2>&1); then
    # A first-run prompt (copilot's "Confirm folder trust") leaves the agent
    # blocked rather than idle, which herdr reports as agent_not_ready. The
    # agent is running in the pane and only needs an answer, so that is a normal
    # outcome: leave it alone for the user to reply to.
    code=$(printf '%s\n' "$start" | python3 -c '
import json, sys
for line in sys.stdin:
    try:
        print(json.loads(line)["error"]["code"])
        break
    except Exception:
        pass
')
    [ "$code" = "agent_not_ready" ] \
      || warn "The $kind agent did not start cleanly: $start"
  fi
}
