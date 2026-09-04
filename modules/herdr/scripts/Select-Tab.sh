#!/usr/bin/env bash
# Fuzzy-find a tab in the focused workspace and switch to it.
#
# prefix+1..9 covers the first nine tabs by number and prefix+n/p cycle, but
# neither lets you jump straight to "Terminal" by name. This is the tab-level
# counterpart of herdr's built-in workspace picker.
#
# Bound to prefix+t as a popup command in modules/herdr/config.toml.

set -uo pipefail

# The popup is the only surface an error can show up on, so it is held open
# until the user reads the message. Same convention as Open-CodeWorkspace.sh.
die() { printf '%s\n' "$*" >&2; read -rsn1 -p "Press any key to close..." _; exit 1; }

for tool in herdr fzf python3; do
  command -v "$tool" >/dev/null || die "Required tool not found: $tool"
done

# The popup is session-modal and does not own a pane, so `pane current` is not
# something to lean on here: the focused *workspace* is asked for directly.
workspace=$(herdr workspace list 2>/dev/null | python3 -c '
import json, sys
try:
    workspaces = json.load(sys.stdin)["result"]["workspaces"]
except Exception:
    sys.exit(0)
for workspace in workspaces:
    if workspace.get("focused"):
        print(workspace["workspace_id"])
        break
')
[ -n "$workspace" ] || die "Could not tell which workspace is focused"

# Rows are "<tab_id>\t<number>  <label>"; fzf shows and matches on the second
# field only, so the id rides along without cluttering the list. The focused tab
# is marked so the picker doubles as a "where am I" readout.
rows=$(herdr tab list --workspace "$workspace" 2>/dev/null | python3 -c '
import json, sys
try:
    tabs = json.load(sys.stdin)["result"]["tabs"]
except Exception:
    sys.exit(0)
for tab in tabs:
    mark = "*" if tab.get("focused") else " "
    print("{}\t{} {}  {}".format(tab["tab_id"], mark, tab["number"], tab["label"]))
')
[ -n "$rows" ] || die "No tabs found in workspace $workspace"

selection=$(printf '%s\n' "$rows" \
  | fzf --reverse --prompt="tab> " --height=100% \
        --delimiter=$'\t' --with-nth=2..) || exit 0
[ -n "$selection" ] || exit 0

tab_id=${selection%%$'\t'*}
herdr tab focus "$tab_id" >/dev/null || die "Could not focus tab $tab_id"
