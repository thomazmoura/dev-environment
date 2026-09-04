#!/usr/bin/env bash
# Fuzzy-find one of the open workspaces and focus it.
#
# Unlike Open-CodeWorkspace.sh (prefix+ctrl+n), which searches every project
# under ~/code and can build a new workspace, this only ever lists the
# workspaces that are already open: the quick hop between live spaces.
#
# Bound to prefix+/ as a popup command in modules/herdr/config.toml.

set -uo pipefail

# The popup is the only surface an error can show up on, so it is held open
# until the user reads the message. Same convention as Open-CodeWorkspace.sh.
die() { printf '%s\n' "$*" >&2; read -rsn1 -p "Press any key to close..." _; exit 1; }

for tool in herdr fzf python3; do
  command -v "$tool" >/dev/null || die "Required tool not found: $tool"
done

# Rows are "<workspace_id>\t<mark> <number>  <label>  <agent status>"; fzf shows
# and matches on the second field only, so the id rides along without cluttering
# the list. The focused workspace is marked, and the agent status is what makes
# the list worth reading: it says which space is waiting on you.
rows=$(herdr workspace list 2>/dev/null | python3 -c '
import json, sys
try:
    workspaces = json.load(sys.stdin)["result"]["workspaces"]
except Exception:
    sys.exit(0)
for workspace in workspaces:
    mark = "*" if workspace.get("focused") else " "
    status = workspace.get("agent_status") or "unknown"
    print("{}\t{} {}  {}  [{}]".format(
        workspace["workspace_id"], mark, workspace["number"],
        workspace["label"], status))
')
[ -n "$rows" ] || die "No open workspaces found"

selection=$(printf '%s\n' "$rows" \
  | fzf --reverse --prompt="space> " --height=100% \
        --delimiter=$'\t' --with-nth=2..) || exit 0
[ -n "$selection" ] || exit 0

workspace_id=${selection%%$'\t'*}
herdr workspace focus "$workspace_id" >/dev/null \
  || die "Could not focus workspace $workspace_id"
