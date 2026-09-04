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
#
# --startup runs the same pickers before herdr itself is up, for the very first
# workspace of a session: see Start-Herdr.sh. There is no server to talk to yet,
# so instead of creating a workspace it prints the picked directory for the
# caller to launch herdr from, and adopts the workspace herdr opens there --
# when herdr opens one at all. It only honours its startup cwd if the session it
# restores from ~/.config/herdr/session.json is empty; with anything to restore
# it logs "restored session already has workspaces; ignoring startup cwd" and
# there is nothing to adopt, so the build creates the workspace itself.
#
# herdr then keeps the space it opened for itself, and closing the last space is
# what makes it open one -- so a stray "~" rooted at $HOME breeds: once
# persisted it comes back on every launch, and a non-empty restore is exactly
# what makes the startup cwd get ignored. herdr 0.8 has no flag, config key or
# HERDR_* variable to suppress it (--session <name> starts a whole second server
# instead), so the startup build closes it afterwards. Afterwards, not before:
# closing it while it is the only space just gets another one.

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
# adopt_mode fills in the workspace herdr opens by itself on launch instead of
# creating one. Set by --startup and carried into the detached build through
# --build --adopt, since by then the workspace may exist without this script
# having made it. When it turns out not to exist, the build creates it.
build_mode=""
adopt_mode=""
startup_mode=""
case "${1:-}" in
  --startup)
    startup_mode=1
    adopt_mode=1
    ;;
  --build)
    build_mode=1
    shift
    if [ "${1:-}" = "--adopt" ]; then
      # --adopt is only ever passed by the startup path, and adopt_mode is
      # cleared again if the build ends up creating the workspace, so the fact
      # that this is a session startup is recorded separately.
      adopt_mode=1
      startup_mode=1
      shift
    fi
    target="${1:-}"
    agent_kind="${2:-}"
    # Nothing is left to read a message, let alone hold a popup open for a
    # keypress, so failures toast in this mode too.
    die() { warn "$@"; }
    ;;
esac

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

# workspace_at answers "is a workspace already rooted at this directory" --
# the question both the keybinding's step 2 and the startup build's step 4 ask.
# pane list reports cwd, workspace_id, tab_id and pane_id together, so one match
# answers all of them, and it asks the real question rather than trying to match
# a mangled workspace label. Prints "<workspace> <tab> <pane> pristine|inuse",
# or nothing at all; "pristine" means one pane, no agent -- what a workspace
# herdr has only just opened on its startup cwd looks like, and what tells it
# apart from a restored one the user was already working in.
workspace_at() {
  herdr pane list 2>/dev/null | python3 -c '
import json, sys
target = sys.argv[1]
try:
    panes = json.load(sys.stdin)["result"]["panes"]
except Exception:
    sys.exit(0)
match = next((p for p in panes
              if target in (p.get("cwd"), p.get("foreground_cwd"))), None)
if match is None:
    sys.exit(0)
siblings = [p for p in panes if p.get("workspace_id") == match["workspace_id"]]
pristine = len(siblings) == 1 and not any(p.get("agent") for p in siblings)
print(match["workspace_id"], match["tab_id"], match["pane_id"],
      "pristine" if pristine else "inuse")
' "$1"
}

# stray_workspaces lists the spaces it is safe to close once the project one is
# up: rooted at $HOME, one pane, no agent, and not the one just built. That is
# the space herdr opens for itself when the last one closes, and the space that
# then gets restored on every later launch and makes it ignore the startup cwd.
# A "~" with a shell you were using, an extra tab or a running agent is not
# pristine and is left alone.
stray_workspaces() {
  herdr pane list 2>/dev/null | python3 -c '
import json, sys
home, keep = sys.argv[1], sys.argv[2]
try:
    panes = json.load(sys.stdin)["result"]["panes"]
except Exception:
    sys.exit(0)
spaces = {}
for pane in panes:
    spaces.setdefault(pane.get("workspace_id"), []).append(pane)
for workspace_id, group in spaces.items():
    if workspace_id in (None, keep) or len(group) != 1:
        continue
    pane = group[0]
    if pane.get("agent"):
        continue
    if home in (pane.get("cwd"), pane.get("foreground_cwd")):
        print(workspace_id)
' "$HOME" "$1"
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
  # Skipped at startup: there is no server yet, so there is nothing to focus.
  # The startup build asks the same question in step 4, once there is.
  existing=""
  [ -z "$startup_mode" ] && read -r existing _ _ _ <<<"$(workspace_at "$target")"

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
  # At startup the same handoff buys something else: the build waits for a server
  # that only comes up once this process has exited and the caller has exec'd
  # herdr, so it cannot run inline.
  if [ -n "$adopt_mode" ]; then
    setsid -f "$(readlink -f "${BASH_SOURCE[0]}")" --build --adopt "$target" "$agent_kind" \
      </dev/null >/dev/null 2>&1
    # The one thing on stdout, and only in startup mode: fzf drew on the tty, so
    # this reaches the caller clean, and it is what herdr gets launched from.
    printf '%s\n' "$target"
  else
    setsid -f "$(readlink -f "${BASH_SOURCE[0]}")" --build "$target" "$agent_kind" \
      </dev/null >/dev/null 2>&1
  fi
  exit 0
fi

# --- 4. Get hold of the workspace --------------------------------------------
label=$(basename "$target" | tr '.' '_')

workspace_id=""
first_tab=""
root_pane=""

if [ -n "$adopt_mode" ]; then
  # Startup: herdr is booting right now, so wait for its API socket before
  # asking it anything. 60 x 0.5s covers a cold server start; a herdr that never
  # came up has nothing to show a toast on either, hence the bare exit.
  for _ in $(seq 60); do
    herdr workspace list >/dev/null 2>&1 && break
    sleep 0.5
  done
  herdr workspace list >/dev/null 2>&1 || exit 1

  # herdr opens a workspace on its startup cwd only when it has nothing to
  # restore; otherwise $target never gets one and there is nothing to adopt (see
  # the header). The server answers only once its panes are up, so the workspace
  # is there by now if it is coming at all -- 5s of slack, then decide.
  state=""
  for _ in $(seq 10); do
    read -r workspace_id first_tab root_pane state <<<"$(workspace_at "$target")"
    [ -n "$root_pane" ] && break
    sleep 0.5
  done

  if [ -n "$root_pane" ] && [ "$state" != "pristine" ]; then
    # A restored workspace the user was already working in: it has its own tabs
    # and possibly a running agent, so it gets focused, not rebuilt -- the same
    # answer step 2 gives the keybinding.
    herdr workspace focus "$workspace_id" >/dev/null 2>&1
    exit 0
  fi

  if [ -n "$root_pane" ]; then
    # herdr labels its own workspace from the cwd, so this only normalises the
    # dots the create path also strips; failure is cosmetic, hence no die.
    herdr workspace rename "$workspace_id" "$label" >/dev/null 2>&1
  else
    # Nothing to adopt: build the workspace the same way the keybinding does.
    adopt_mode=""
  fi
fi

if [ -z "$root_pane" ]; then
  create=$(herdr workspace create --cwd "$target" --label "$label" --focus) \
    || die "Could not create the workspace"
  root_pane=$(pane_id_of "$create") \
    || die "Could not read the new workspace root pane"
  workspace_id=$(printf '%s' "$create" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["result"]["workspace"]["workspace_id"])')
  first_tab=$(printf '%s' "$create" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["result"]["tab"]["tab_id"])')
fi

# --- 4b. Close the space herdr opened for itself -----------------------------
# Only at startup, and only now that the project workspace exists and is focused:
# closing herdr's last space is what makes it spawn a replacement, so doing this
# any earlier would just recreate what it removes. Silent on failure -- a
# leftover space is cosmetic, and the user is already looking at the one that
# matters.
if [ -n "$startup_mode" ]; then
  for stray in $(stray_workspaces "$workspace_id"); do
    herdr workspace close "$stray" >/dev/null 2>&1
  done
fi

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
