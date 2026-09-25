#!/usr/bin/env bash
# Fuzzy-find one of your own scripts and run it in a pane of its own, or in the popup.
#
#   Show-Example.sh   bash   Prints where it ran, as a shape to copy
#
# Bound to prefix+s as a popup, with prefix+- then s opening the pane below
# instead of on the right, and prefix+S running it right there
# in the picker's popup (see modules/tmux/common.conf). Meant to be run from a
# tmux binding so the split happens in the client that opened it.
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
# In an ssh session (prefix+N) the pane runs on the remote, like every other
# pane there, so the list is the remote's library, not this one: a path from
# here means nothing on the other host, and a script that is only here -- a
# hidden one, or one not pulled there yet -- could not run. The rows come from
# the remote's own copy of this script (--list), so the paths in them, and the
# Invoke-Script.sh next to them, are the remote's. A remote without this
# dev-environment has no library to offer.
#
# Usage: Select-Script.sh [-v]
#   -v                open the pane below the current one instead of to its right
#   -p                run the script in this popup instead of a new pane; the
#                     binding's -d '#{pane_current_path}' is its directory
#   --list            print the rows and exit
#   --rows-for <pane> the rows for <pane>'s machine: --list here, or over ssh in
#                     an ssh session; what ctrl-r reloads from
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

# rows_for <pane>
# BatchMode as in remote_directory_matches: the session's master connection is
# up, so it never needs a password, and a dead host fails instead of hanging
# the popup. ~ is expanded by the remote shell, to the remote's home.
rows_for() {
  local target
  target="$(ssh_option "$1" @ssh_target)"
  if [ -z "$target" ]; then
    list_rows
  elif ssh_is_devenv "$1"; then
    ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$target" \
      '~/.modules/scripts/scripts/Select-Script.sh --list' </dev/null
  else
    printf '%s has no dev-environment, so no script library\n' "${target##*@}" >&2
    return 1
  fi
}

if [ "${1:-}" = "--rows-for" ]; then
  rows_for "${2:-}"
  exit
fi

require_tools tmux fzf

direction=()
in_popup=""
while getopts ":vp" option; do
  case "$option" in
    v) direction=(-v) ;;
    p) in_popup="yes" ;;
    *) die "Select-Script.sh: unknown option -$OPTARG" ;;
  esac
done

# Before fzf: a popup is an overlay rather than a pane, so #{pane_id} still
# resolves to the pane underneath it -- the one the new pane should be split
# off. Resolved here anyway, while nothing else could have taken focus.
origin="$(current_pane)"

remote="$(ssh_option "$origin" @ssh_target)"
rows="$(rows_for "$origin")" || die "Could not list the scripts${remote:+ on ${remote##*@}}"
[ -n "$rows" ] || die "No scripts in the library${remote:+ on ${remote##*@}}"

self="$(readlink -f "${BASH_SOURCE[0]}")"
selection="$(
  printf '%s\n' "$rows" \
    | fzf --ansi --reverse --delimiter=$'\t' --with-nth=2.. \
          --prompt='script> ' \
          --header=$'Run script   (ctrl-r refresh)' \
          --bind="ctrl-r:reload('$self' --rows-for '$origin')"
)" || exit 0
[ -n "$selection" ] || exit 0

path="${selection%%$'\t'*}"

# Invoke-Script.sh beside the library the path came from, so that on a remote
# it is the remote's copy too.
runner="$(dirname "$(dirname "$path")")/scripts/Invoke-Script.sh"

# The pane runs pwsh (pwsh_invocation), so this is a pwsh line: & is its call
# operator, and a single-quoted path is literal to it -- with '' for a quote in
# the path itself, which is pwsh's own escape.
pwsh_quote() { printf "'%s'" "${1//\'/\'\'}"; }
command="& $(pwsh_quote "$runner") $(pwsh_quote "$path")"

# The same line a pane would get (pane_command, as New-PopupShell.sh uses it),
# so in an ssh session the popup runs it on the remote, in the session's
# directory. Invoke-Script.sh's keypress pause holds the popup open too.
if [ -n "$in_popup" ]; then
  exec bash -c "$(pane_command "$origin" "$command")"
fi

"$HOME/.modules/tmux/scripts/New-ToolPane.sh" "${direction[@]}" -t "$origin" \
  "$(basename "$path")" "$command"
