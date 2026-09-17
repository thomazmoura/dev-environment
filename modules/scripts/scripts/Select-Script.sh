#!/usr/bin/env bash
# Fuzzy-find one of your own scripts and run it in a pane of its own.
#
#   Show-Example.sh   bash   Prints where it ran, as a shape to copy
#
# Bound to prefix+t then s as a popup, with prefix+t then - then s opening the
# pane below instead of on the right (see modules/tmux/common.conf). Meant to be
# run from a tmux binding so the split happens in the client that opened it.
#
# The list is whatever is in modules/scripts/library -- no registry to keep in
# step, no metadata file: a script is listed because it is there, and it is
# described by its own first comment line, the way every script in this repo
# already opens. Running it is Invoke-Script.sh's job, which is also what works
# out the interpreter.
#
# Hidden files are listed too, and deliberately: .gitignore drops
# modules/scripts/library/.*, so naming a script .Something.sh is how you keep
# one to this machine without committing it. It is the same list either way --
# the dot decides what git sees, not what you can run.
#
# Structurally this is Select-Session.sh with a different action at the end:
# same hidden-value-in-column-one rows, same ctrl-r reload through --list.
#
# Usage: Select-Script.sh [-v]
#   -v      open the pane below the current one instead of to its right
#   --list  print the rows and exit; what ctrl-r reloads from
set -uo pipefail

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$here/../../tmux/scripts/tmux-helpers.sh"

library="$(readlink -f "$here/../library")"

# --list is checked before require_tools so the rows can be inspected outside
# tmux, which is how you check a new script shows up the way you meant it to.
list_rows() {
  local path name kind description width=0
  local -a paths=() names=() kinds=() descriptions=()

  while IFS= read -r path; do
    name="$(basename "$path")"
    # Hidden files are listed like any other: a dot is how you keep a script
    # local, since .gitignore drops modules/scripts/library/.* -- it is not a
    # way of hiding one from the picker. Only the two dotfiles that are plainly
    # not scripts are skipped.
    case "$name" in
      README*|.gitignore|.gitkeep) continue ;;
    esac
    case "$name" in
      *.sh) kind=bash ;;
      *.ps1) kind=pwsh ;;
      *.py) kind=python ;;
      *) kind=script ;;
    esac
    description="$(describe "$path")"

    paths+=("$path")
    names+=("$name")
    kinds+=("$kind")
    descriptions+=("$description")
    [ "${#name}" -le "$width" ] || width=${#name}
  done < <(find "$library" -maxdepth 1 \( -type f -o -type l \) | sort)

  local index
  for index in "${!paths[@]}"; do
    # \033[2m: the name is what you are choosing between, so the columns that
    # only tell you about it step back. Names are ASCII, so printf's byte
    # padding is the character padding here -- unlike the radars, which pad in
    # python because their glyphs are multi-byte.
    printf '%s\t%-*s  \033[2m%-6s  %s\033[0m\n' \
      "${paths[$index]}" "$width" "${names[$index]}" \
      "${kinds[$index]}" "${descriptions[$index]}"
  done
}

# describe <path>
# The script's first comment line, minus its # and the shebang above it. Stops
# at the first line that is neither blank nor a comment, so a file that opens
# with code rather than a header simply has no description.
describe() {
  awk '
    NR == 1 && /^#!/ { next }
    /^[[:space:]]*#/ {
      sub(/^[[:space:]]*#+[[:space:]]?/, "")
      if (length($0)) { print; exit }
      next
    }
    /^[[:space:]]*$/ { next }
    { exit }
  ' "$1"
}

if [ "${1:-}" = "--list" ]; then
  list_rows
  exit 0
fi

require_tools tmux fzf

direction=()
while getopts ":v" option; do
  case "$option" in
    v) direction=(-v) ;;
    *) die "Select-Script.sh: unknown option -$OPTARG" ;;
  esac
done

rows="$(list_rows)"
[ -n "$rows" ] || die "No scripts in $library"

# Before fzf: a popup is an overlay rather than a pane, so #{pane_id} still
# resolves to the pane underneath it -- the one the new pane should be split
# off. Resolved here anyway, while nothing else could have taken focus.
origin="$(current_pane)"

self="$(readlink -f "${BASH_SOURCE[0]}")"
selection="$(
  printf '%s\n' "$rows" \
    | fzf --ansi --reverse --delimiter=$'\t' --with-nth=2.. \
          --prompt='script> ' \
          --header=$'Run script   (ctrl-r refresh)' \
          --bind="ctrl-r:reload('$self' --list)"
)" || exit 0
[ -n "$selection" ] || exit 0

path="${selection%%$'\t'*}"

# The pane runs pwsh (pwsh_invocation), so this is a pwsh line: & is its call
# operator, and a single-quoted path is literal to it -- with '' for a quote in
# the path itself, which is pwsh's own escape.
pwsh_quote() { printf "'%s'" "${1//\'/\'\'}"; }

"$HOME/.modules/tmux/scripts/New-ToolPane.sh" "${direction[@]}" -t "$origin" \
  "$(basename "$path")" \
  "& $(pwsh_quote "$here/Invoke-Script.sh") $(pwsh_quote "$path")"
