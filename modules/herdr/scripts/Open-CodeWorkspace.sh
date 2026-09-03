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

die() { printf '%s\n' "$*" >&2; read -rsn1 -p "Press any key to close..." _; exit 1; }

for tool in herdr fd fzf python3; do
  command -v "$tool" >/dev/null || die "Required tool not found: $tool"
done
[ -d "$CODE_DIR" ] || die "Directory does not exist: $CODE_DIR"

# --- 1. Pick a directory -----------------------------------------------------
# Mirrors the tmux binding, capped at 3 levels so the list stays scannable.
selection=$(fd --type d --max-depth 3 . --base-directory "$CODE_DIR" \
  | fzf --reverse --prompt="project> " --height=100%) || exit 0
[ -n "$selection" ] || exit 0

target="$CODE_DIR/${selection%/}"
[ -d "$target" ] || die "Not a directory: $target"

# --- 2. Focus the workspace already rooted there, if any ---------------------
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

# --- 3. Pick an agent --------------------------------------------------------
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
  --cwd "$target" --no-focus) || die "Could not split the pane"
shell_pane=$(printf '%s' "$split" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')

if command -v pwsh >/dev/null 2>&1; then
  herdr pane run "$shell_pane" "pwsh" >/dev/null
fi

# --- 6. Start the agent in the top pane -------------------------------------
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

herdr agent start "$agent_name" --kind "$agent_kind" --pane "$root_pane" \
  || die "Workspace created, but the $agent_kind agent did not start cleanly"
