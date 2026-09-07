#!/usr/bin/env bash
# Registers agent-radar's hooks with Claude Code, idempotently.
#
# agent-radar needs no installation to work -- reading the screen is the whole
# point of the design, and it covers every agent. This adds the one optional
# extra: Claude Code telling us directly when it is blocked, so a dialog whose
# shape no rule recognises still turns the pane red. See hooks/Set-AgentRadarState.sh.
#
# Editing ~/.claude/settings.json is not this repo's business to do quietly, so:
# it backs the file up first, only ever touches entries whose command mentions
# Set-AgentRadarState.sh, and prints the diff summary. Other tools' hooks on the
# same events (demux, herdr, notifications) are left exactly where they are --
# Claude runs every hook registered for an event.
#
# Usage: Install-AgentRadarHooks.sh [--uninstall] [--settings PATH]
set -uo pipefail

settings="$HOME/.claude/settings.json"
mode="install"

while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) mode="uninstall" ;;
    --settings) shift; settings="${1:?--settings needs a path}" ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

hook="$HOME/.modules/agent-radar/hooks/Set-AgentRadarState.sh"
[ -x "$hook" ] || hook="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../hooks/Set-AgentRadarState.sh"

SETTINGS="$settings" HOOK="$hook" MODE="$mode" python3 - <<'PY'
import json, os, shutil, sys
from pathlib import Path

settings = Path(os.environ["SETTINGS"])
hook = os.environ["HOOK"]
uninstall = os.environ["MODE"] == "uninstall"

# One entry per event. `clear` is deliberately spread over four events rather
# than trusting any single one: a blocked marker that outlives its dialog is the
# one failure users would never forgive, so every plausible "it is over" moment
# removes it. PreToolUse is NOT among them -- it fires *before* the permission
# prompt it would be clearing.
WANTED = {
    "Notification": "notification",
    "PostToolUse": "clear",
    "UserPromptSubmit": "clear",
    "Stop": "clear",
    "SessionEnd": "clear",
}
MARKER = "Set-AgentRadarState.sh"

try:
    document = json.loads(settings.read_text())
except FileNotFoundError:
    document = {}
except ValueError as exc:
    sys.exit(f"{settings} is not valid JSON ({exc}); refusing to touch it")

if not isinstance(document, dict):
    sys.exit(f"{settings} does not hold a JSON object; refusing to touch it")

hooks = document.setdefault("hooks", {})
if not isinstance(hooks, dict):
    sys.exit("settings.json has a `hooks` key that is not an object; refusing to touch it")

removed = added = 0

# Always strip our own entries first: that is what makes a re-run a no-op and an
# upgrade a two-line change rather than a duplicate hook.
for event, groups in list(hooks.items()):
    if not isinstance(groups, list):
        continue
    kept = []
    for group in groups:
        entries = group.get("hooks", []) if isinstance(group, dict) else []
        survivors = [
            entry for entry in entries
            if MARKER not in str(entry.get("command", ""))
        ]
        removed += len(entries) - len(survivors)
        if survivors:
            group["hooks"] = survivors
            kept.append(group)
        elif not entries:
            kept.append(group)
    hooks[event] = kept

if not uninstall:
    for event, argument in WANTED.items():
        entry = {"type": "command", "command": f'"{hook}" {argument}'}
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list):
            sys.exit(f"settings.json hooks.{event} is not a list; refusing to touch it")
        groups.append({"hooks": [entry]})
        added += 1

hooks = {event: groups for event, groups in hooks.items() if groups}
if hooks:
    document["hooks"] = hooks
else:
    document.pop("hooks", None)

if settings.exists():
    backup = settings.with_suffix(".json.bak-agent-radar")
    shutil.copy2(settings, backup)
    print(f"backed up  {backup}")

settings.parent.mkdir(parents=True, exist_ok=True)
temp = settings.with_suffix(".json.agent-radar.tmp")
temp.write_text(json.dumps(document, indent=2) + "\n")
temp.replace(settings)

print(f"removed    {removed} existing agent-radar hook(s)")
print(f"added      {added} hook(s) -> {settings}")
print("\nRestart or /hooks-reload any running Claude Code session to pick this up.")
PY
