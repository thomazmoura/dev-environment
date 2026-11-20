# Exports $CODE_FOLDER from ~/.config/dev-environment/code-folder, the setting
# steward.nvim's projects screen (:Steward projects, its Code folder section)
# writes: one line, the path. Sourced from the first line of ~/.bashrc (put
# there by LinuxDevEnv/host-setup.sh, and by DockerUbuntu/bashrc in the image),
# above its "not interactive, return" guard, so every shell sshd starts for an
# `ssh host cmd` gets it too: Debian's bash reads ~/.bashrc for those. tmux panes
# take it from the server's global environment (common.conf, code-folder.sh),
# and pwsh reads the file itself (kernel-profile.ps1).
#
# Kept to builtins (read, no $(<file)): it runs on every ssh command.

__code_folder_file="${XDG_CONFIG_HOME:-$HOME/.config}/dev-environment/code-folder"
if [ -r "$__code_folder_file" ]; then
  # read fails on a last line with no newline, but has read it all the same
  IFS= read -r __code_folder < "$__code_folder_file"
  # ~/... as steward saves it when typed so; the variable's readers want it whole
  case "$__code_folder" in "~"*) __code_folder="$HOME${__code_folder#"~"}" ;; esac
  [ -n "$__code_folder" ] && export CODE_FOLDER="$__code_folder"
fi
unset __code_folder_file __code_folder
