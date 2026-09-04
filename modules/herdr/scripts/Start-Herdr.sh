#!/usr/bin/env bash
# Launch herdr, opening the first workspace on a picked project rather than on
# whatever directory the terminal happened to start in.
#
# A fresh herdr server opens one workspace rooted at its launch cwd, which from
# Ghostty is $HOME: a "~" space nobody asked for. So on a fresh session this
# runs the prefix+ctrl+n pickers first (Open-CodeWorkspace.sh --startup) and
# launches herdr from the picked project, which that script's detached build
# then adopts and fills with the agent, "NeoVim" and "Terminal" tabs.
#
# Attaching to a session that is already up skips all of it: the spaces are
# already there and prefix+/ hops between them.
#
# Run for the "herdr" row of modules/ghostty/scripts/Select-Shell.sh.

set -uo pipefail

picker="$HOME/.modules/herdr/scripts/Open-CodeWorkspace.sh"

# A live server answers workspace list; a dead one (or a stale socket file left
# behind by one) does not. That is the question that actually matters here --
# "is there a session to attach to" -- so it is the one being asked.
if ! herdr workspace list >/dev/null 2>&1 && [ -x "$picker" ]; then
  # An abort in either picker prints nothing and exits 0, which lands here as an
  # empty target: herdr then starts the ordinary way instead of not at all.
  target=$("$picker" --startup) || target=""
  [ -n "$target" ] && [ -d "$target" ] && cd "$target"
fi

# Through pwsh, as every other herdr entry point in this repo: the profile sets
# up the environment the agents and the Terminal tab expect.
exec pwsh -C herdr
