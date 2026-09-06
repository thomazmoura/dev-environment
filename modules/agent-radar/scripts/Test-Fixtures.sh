#!/usr/bin/env bash
# Replays every saved fixture and asserts it still classifies the way its
# filename says it should. Run it after touching rules/*.toml or the engine.
#
# Fixtures are named  <agent>-<expected state>[-note].txt  so the expectation
# travels with the file and there is no separate manifest to keep in sync:
#
#   claude-idle-typed-text.txt      claude, must classify as idle
#   claude-working.txt              claude, must classify as working
#
# This is the cheap safety net under a technique that fails silently. Widening a
# character class to catch a new spinner glyph is a two-character edit that can
# quietly break the rule that told finished apart from working, and nothing at
# runtime would tell you -- the list would just be wrong.
#
# To add a case: put an agent into the state you care about, then
#   Show-AgentSnapshot.sh %23 > fixtures/claude-blocked-bash-permission.txt
set -uo pipefail

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fixtures="$here/../fixtures"
failures=0
total=0

for fixture in "$fixtures"/*.txt; do
  [ -e "$fixture" ] || continue
  name="$(basename "$fixture" .txt)"
  agent="${name%%-*}"
  rest="${name#*-}"
  expected="${rest%%-*}"
  total=$((total + 1))

  actual="$(
    "$here/Test-AgentRules.py" --file "$fixture" --agent "$agent" 2>/dev/null \
      | sed -n 's/.*verdict[^ ]*  \([a-z]*\) .*/\1/p'
  )"

  if [ "$actual" = "$expected" ]; then
    printf '  ok    %-40s %s\n' "$name" "$actual"
  else
    printf '  FAIL  %-40s expected %s, got %s\n' "$name" "$expected" "${actual:-<none>}"
    failures=$((failures + 1))
  fi
done

printf '\n%d fixture(s), %d failure(s)\n' "$total" "$failures"
[ "$failures" -eq 0 ]
