#!/usr/bin/env bash
# Fuzzy-find a project under ~/code and open it as a herdr workspace.
#
# The herdr counterpart of the tmux `prefix + C-n` binding in
# modules/tmux/tmux.conf. If a workspace is already rooted at the chosen
# directory it is focused; otherwise a new one is built with three tabs:
# the agent CLI (tab labelled after the agent kind), "NeoVim" running nvim,
# and "Terminal" running pwsh. Picking "NeoVim" in the agent picker skips the
# agent tab and builds only the editor and shell tabs.
#
# Bound to prefix+ctrl+n as a popup command in modules/herdr/config.toml.

set -uo pipefail

CODE_DIR="${CODE_DIR:-$HOME/code}"

# die is for failures before the workspace exists: the popup is then the only
# surface an error can show up on, so it is held open until the user reads it.
die() { printf '%s\n' "$*" >&2; read -rsn1 -p "Press any key to close..." _; exit 1; }

# warn is for failures after the workspace exists and is focused: the user is
# already looking at it, so the message goes to a toast instead of pinning the
# popup on top of it. [ui.toast] delivery = "herdr" routes these in-app.
warn() {
  herdr notification show "Open-CodeWorkspace" --body "$*" --sound none >/dev/null 2>&1
  exit 0
}

# Steps 4-6 need no popup and take a second or two, so they are re-entered here
# in a detached process (see the handoff at the end of step 3): the popup dies
# with this process, so the sooner it exits, the sooner the popup gets out of
# the way of the workspace it just created.
build_mode=""
if [ "${1:-}" = "--build" ]; then
  build_mode=1
  target="$2"
  agent_kind="$3"
  # Nothing is left to read a message, let alone hold a popup open for a
  # keypress, so failures toast in this mode too.
  die() { warn "$@"; }
fi

for tool in herdr fd fzf python3; do
  command -v "$tool" >/dev/null || die "Required tool not found: $tool"
done
[ -d "$CODE_DIR" ] || die "Directory does not exist: $CODE_DIR"

# pane_id_of reads the pane id out of a `workspace create` or `tab create`
# reply; both wrap the new tab's first pane under result.root_pane.
pane_id_of() {
  printf '%s' "$1" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])'
}

if [ -z "$build_mode" ]; then
  # --- 1. Pick a directory ---------------------------------------------------
  # Mirrors the tmux binding, capped at 3 levels so the list stays scannable.
  selection=$(fd --type d --max-depth 3 . --base-directory "$CODE_DIR" \
    | fzf --reverse --prompt="project> " --height=100%) || exit 0
  [ -n "$selection" ] || exit 0

  target="$CODE_DIR/${selection%/}"
  [ -d "$target" ] || die "Not a directory: $target"

  # --- 2. Focus the workspace already rooted there, if any -------------------
  # pane list reports cwd and workspace_id together, so this asks the real
  # question rather than trying to match a mangled workspace label.
  existing=$(herdr pane list 2>/dev/null | python3 -c '
import json, sys
target = sys.argv[1]
try:
    panes = json.load(sys.stdin)["result"]["panes"]
except Exception:
    sys.exit(0)
for pane in panes:
    if target in (pane.get("cwd"), pane.get("foreground_cwd")):
        print(pane["workspace_id"])
        break
' "$target")

  if [ -n "$existing" ]; then
    herdr workspace focus "$existing" >/dev/null || die "Could not focus workspace $existing"
    exit 0
  fi

  # --- 3. Pick an agent ------------------------------------------------------
  # Offer only kinds herdr knows about that are actually executable here.
  kinds=$(herdr agent 2>&1 | sed -n 's/^ *kinds: *//p' | tr '|' '\n')
  [ -n "$kinds" ] || die "Could not read the agent kind list from herdr"

  available=""
  for kind in $kinds; do
    if command -v "$kind" >/dev/null 2>&1; then
      available="${available}${kind}"$'\n'
    fi
  done
  # "NeoVim" is the no-agent choice: build the editor and shell tabs only. herdr
  # kind names are lowercase, so the capitalised spelling is both the label the
  # picker shows and a value that can never collide with a real agent kind.
  if command -v nvim >/dev/null 2>&1; then
    available="${available}NeoVim"$'\n'
  fi
  available=$(printf '%s' "$available" | sed '/^$/d')
  [ -n "$available" ] || die "No supported agent CLI or nvim found in PATH"

  if [ "$(printf '%s\n' "$available" | wc -l)" -eq 1 ]; then
    agent_kind="$available"
  else
    agent_kind=$(printf '%s\n' "$available" \
      | fzf --reverse --prompt="agent> " --height=100%) || exit 0
  fi
  [ -n "$agent_kind" ] || exit 0

  # The popup lives exactly as long as this script, so the rest of the work is
  # handed to a detached session and this process exits: the popup closes on the
  # agent selection and the workspace fills in behind it. setsid keeps the build
  # out of the popup's session so tearing down its pty does not take the build
  # with it, and stdio goes to /dev/null because no terminal outlives this exit.
  setsid -f "$(readlink -f "${BASH_SOURCE[0]}")" --build "$target" "$agent_kind" \
    </dev/null >/dev/null 2>&1
  exit 0
fi

# --- 4. Create the workspace -------------------------------------------------
label=$(basename "$target" | tr '.' '_')

create=$(herdr workspace create --cwd "$target" --label "$label" --focus) \
  || die "Could not create the workspace"
root_pane=$(pane_id_of "$create") \
  || die "Could not read the new workspace root pane"
workspace_id=$(printf '%s' "$create" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["result"]["workspace"]["workspace_id"])')
first_tab=$(printf '%s' "$create" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["result"]["tab"]["tab_id"])')

# --- 5. Fill in the tabs -----------------------------------------------------
# --no-focus everywhere below leaves the focus where workspace create put it, on
# the first tab. new_tab publishes the new tab's pane in $tab_pane rather than
# echoing it: warn exits, and an exit from inside a $(...) would only end the
# substitution and let the build carry on with an empty pane id.
tab_pane=""
new_tab() {
  local created
  created=$(herdr tab create --workspace "$workspace_id" --cwd "$target" \
    --label "$1" --no-focus) || warn "Could not create the $1 tab"
  tab_pane=$(pane_id_of "$created") || warn "Could not read the $1 tab pane"
}

if [ "$agent_kind" = "NeoVim" ]; then
  # No agent: the first tab is the editor and there is no second one.
  herdr tab rename "$first_tab" "NeoVim" >/dev/null
  herdr pane run "$root_pane" "nvim" >/dev/null
else
  herdr tab rename "$first_tab" "$agent_kind" >/dev/null
  new_tab "NeoVim"
  herdr pane run "$tab_pane" "nvim" >/dev/null
fi

new_tab "Terminal"
if command -v pwsh >/dev/null 2>&1; then
  herdr pane run "$tab_pane" "pwsh" >/dev/null
fi

# --- 6. Start the agent in the first tab -------------------------------------
# Last, because `herdr agent start` only returns once the agent is ready for
# prompts: the editor and shell tabs are already in place by then.
[ "$agent_kind" = "NeoVim" ] && exit 0

# Agent names must match [a-z][a-z0-9_-]{0,31} and be unique among live agents.
# `herdr agent start` only exits 0 once the agent is ready for prompts, so an
# agent sitting on a first-run question counts as started here too (see below).
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

if ! start=$(herdr agent start "$agent_name" --kind "$agent_kind" \
    --pane "$root_pane" 2>&1); then
  # A first-run prompt (copilot's "Confirm folder trust") leaves the agent
  # blocked rather than idle, which herdr reports as agent_not_ready. The agent
  # is running in the pane and only needs an answer, so that is a normal
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
    || warn "The $agent_kind agent did not start cleanly: $start"
fi
