#!/usr/bin/env bash
# Fuzzy-find a project under ~/code and open it as a herdr workspace.
#
# The herdr counterpart of the tmux `prefix + C-n` binding in
# modules/tmux/tmux.conf. If a workspace is already rooted at the chosen
# directory it is focused; otherwise a new one is created with an agent pane
# and a short pwsh pane below it.
#
# Bound to prefix+ctrl+n as a popup command in modules/herdr/config.toml.

set -uo pipefail

CODE_DIR="${CODE_DIR:-$HOME/code}"
# Height in rows of the pwsh pane below the agent.
SHELL_PANE_ROWS="${SHELL_PANE_ROWS:-5}"

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
  available=$(printf '%s' "$available" | sed '/^$/d')
  [ -n "$available" ] || die "No supported agent CLI found in PATH"

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
root_pane=$(printf '%s' "$create" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])') \
  || die "Could not read the new workspace root pane"

# --- 5. Split off the pwsh pane ---------------------------------------------
# --ratio sizes the *existing* pane, so the top pane keeps everything but the
# rows reserved for the shell below it.
height=$(herdr pane layout --pane "$root_pane" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["result"]["layout"]["area"]["height"])')
ratio=$(python3 -c "
height = $height
rows = min($SHELL_PANE_ROWS, max(1, height // 2))
print((height - rows) / height if height > rows else 0.5)
")

split=$(herdr pane split "$root_pane" --direction down --ratio "$ratio" \
  --cwd "$target" --no-focus) || warn "Could not split the pane"
shell_pane=$(printf '%s' "$split" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')

if command -v pwsh >/dev/null 2>&1; then
  herdr pane run "$shell_pane" "pwsh" >/dev/null
fi

# --- 6. Start the agent in the top pane -------------------------------------
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
