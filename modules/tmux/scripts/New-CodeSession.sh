#!/usr/bin/env bash
# Opens a session for a project in the code folder (code-folder.sh: ~/code, or
# /Git on the company's machines), with the standard layout: Git, Agents and a
# picker pane (see Set-NeovimLayout.sh).
#
# Usage: New-CodeSession.sh [directory]
#        New-CodeSession.sh -d [-x columns -y rows] directory
#   no argument - fuzzy-find a project folder (prefix+/). The sessions named
#                 with prefix+$ come first, as `★ <name>  <dir>`, open or not
#                 (Set-SessionLabel.sh -l). Then this machine's project folders:
#                 the first level of the code folder plus what
#                 ~/.config/dev-environment/projects.json adds
#                 (Get-ProjectFolders.py). Each linked machine's own project
#                 folders come last, as <host>/<folder> (tmux_link.py, from the
#                 snapshot Start-TmuxLink.py keeps). In the picker Ctrl-A swaps
#                 this machine's list for every folder in the code folder, at
#                 any depth, and back; Ctrl-E edits projects.json in steward.nvim
#                 (:Steward projects) and comes back to the picker
#   directory   - use that directory directly (prefix+C-c, for the code folder)
#   -d          - detached: open the session without switching to it and print
#                 its name. How a linked machine opens a session here, over
#                 ssh, for a folder picked there -- which then moves its client
#                 over (Switch-LinkSession.sh). -x and -y are that client's
#                 size, so the layout's splits land where they will be once it
#                 is attached, as New-SshSession.sh does outside tmux.
#                 With no directory it is the picker from outside tmux, for
#                 vtmux (DevHelpers.psm1) when there is no home session to
#                 open: a linked machine's folder is opened there and its
#                 identity printed on a line before the session's name, for
#                 the caller to attach to (Connect-Tmux.sh -t). Nothing is
#                 printed when the picker is left
#
# A folder on a linked machine is opened in that machine's tmux, by this script
# run there with -d, and the client is taken to it: nothing of it lives here.
#
# Bound as popup commands in modules/tmux/common.conf. The session is created
# detached and then switched to, rather than with `new-session` attached,
# because this runs inside a popup: the popup owns the terminal until it
# closes, so the client has to be moved with switch-client the way
# Select-Pane.sh does.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"
source "$scripts/worktree-helpers.sh"
source "$scripts/link-helpers.sh"
source "$scripts/code-folder.sh"

code="$(code_folder)"

detached="" size=() columns="" rows=""
while getopts ":dx:y:" option; do
  case "$option" in
    d) detached="yes" ;;
    x) size+=(-x "$OPTARG"); columns="$OPTARG" ;;
    y) size+=(-y "$OPTARG"); rows="$OPTARG" ;;
    *) die "New-CodeSession.sh: unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

directory="${1:-}"
name=""
if [ -z "$directory" ]; then
  require_tools tmux fzf
  # A named line carries its directory and session name after tabs, which fzf
  # does not show (--with-nth=1); a project folder carries its path. A linked
  # machine's folder carries three: identity, address and path.
  # The lists are commands rather than a pipe so Ctrl-A can reload them: in
  # the environment, so the reload needs no quoting, and under bash whatever
  # $SHELL is (--with-shell).
  named="$(printf '%q ' "$scripts/Set-SessionLabel.sh" -l "" "$code")"
  linked="$(printf '%q ' "$scripts/Get-TmuxLink.py" --format=folders) 2>/dev/null"
  projects="$(printf '%q ' "$scripts/Get-ProjectFolders.py")"
  export PROJECTS_SHORT="$named; $projects; $linked"
  export PROJECTS_EVERY="$named; $projects --all; $linked"
  # shellcheck disable=SC2016 # expanded by the bash fzf runs
  swap='if [ "$FZF_PROMPT" = "all> " ]; then echo "change-prompt(project> )+reload(eval \"\$PROJECTS_SHORT\")";
    else echo "change-prompt(all> )+reload(eval \"\$PROJECTS_EVERY\")"; fi'
  while :; do
    picked="$(eval "$PROJECTS_SHORT" |
      fzf --ansi --reverse --delimiter=$'\t' --with-nth=1 --prompt='project> ' --with-shell='bash -c' \
        --expect=ctrl-e --bind="ctrl-a:transform:$swap" \
        --header="New session from ${code/#$HOME/\~}  (C-a: all folders, C-e: edit the list)")" || exit 0
    [ "${picked%%$'\n'*}" = ctrl-e ] || break
    # steward.nvim's screen for projects.json, then the picker again with
    # what was saved.
    nvim -c 'Steward projects' </dev/tty >/dev/tty
  done
  location="${picked#*$'\n'}"
  [ -n "$location" ] || exit 0
  case "$location" in
    *$'\t'*$'\t'*$'\t'*)
      IFS=$'\t' read -r _ identity address directory <<<"$location"
      if [ -n "$detached" ]; then
        # No client to move: the caller attaches to it.
        name="$(create_on_peer "$identity" "$address" "$directory" "${columns:-80}" "${rows:-24}")" || exit 1
        printf '%s\n%s\n' "$identity" "$name"
      else
        open_on_peer "$identity" "$address" "$directory"
      fi
      exit 0 ;;
    # A named session (directory, name) or a project folder (its path).
    *$'\t'*) IFS=$'\t' read -r _ directory name <<<"$location" ;;
    *) directory="$code/$location" ;;
  esac
fi

[ -d "$directory" ] || die "Not a directory: $directory"

# tmux session names cannot contain dots -- they are the separator in
# session:window.pane targets -- so a directory like Foo.Bar.Api becomes
# Foo_Bar_Api. A git worktree is prefixed with its repository's name
# (session_name_for in worktree-helpers.sh). A named entry brings the name its
# label is kept under, so the session opens as the one that was named.
[ -n "$name" ] || name="$(session_name_for_dir "$directory")"

# Re-running the binding for a project that is already open should take you
# there instead of failing on the duplicate name.
if ! tmux has-session -t "=$name" 2>/dev/null; then
  tmux new-session -s "$name" -d -c "$directory" "${size[@]}" || die "Could not create session $name"
  layout="yes"
fi

if [ -n "$detached" ]; then
  [ -n "${layout:-}" ] && "$scripts/Set-NeovimLayout.sh" -n "$name:" >/dev/null 2>&1
  printf '%s\n' "$name"
  exit 0
fi

tmux switch-client -t "=$name"
[ -n "${layout:-}" ] && "$scripts/Set-NeovimLayout.sh" -n "$name:"
exit 0
