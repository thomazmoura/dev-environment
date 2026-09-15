#!/usr/bin/env bash
# Pulls this dev-environment clone and reloads the tmux config.
#
# Bound to prefix+t, u as a small popup in modules/tmux/common.conf. Closes by
# itself when everything worked; a failed pull (dirty tree, diverged branch, no
# network) holds the popup open on git's message instead.
#
# The clone is found from this script's own real path rather than from a fixed
# ~/code/dev-environment: ~/.modules is a symlink into the clone on the host and
# in WSL (LinuxDevEnv/host-setup.sh, modules/wsl2/Start-DevSession.ps1), so
# resolving it lands inside the repository wherever it was cloned. The Docker
# image copies modules/ in instead, so there is no clone to pull there.
#
# The reload is prefix+I's -- TPM's bindings/install_plugins: reload the config,
# install any plugin it now lists, reload again. That binding is not called
# as-is because it ends by printing "press ENTER to continue" into the pane
# under the popup; the same steps run here, with the install output shown in
# the popup and a status-line message at the end.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"

require_tools git tmux

repo="$(git -C "$scripts" rev-parse --show-toplevel 2>/dev/null)" \
  || die "~/.modules is not a git clone here (the Docker image copies it in) -- nothing to pull."

tpm="$HOME/.tmux/plugins/tpm"
[ -d "$tpm" ] || die "TPM not found at $tpm"

printf 'Pulling %s\n\n' "$repo"
git -C "$repo" pull --ff-only || die "
git pull failed -- nothing was reloaded."

printf '\nReloading tmux config\n'
# TPM's helpers are not written for `set -u`, hence the subshell.
(
  set +u
  source "$tpm/scripts/helpers/tmux_utils.sh"
  reload_tmux_environment
  "$tpm/scripts/install_plugins.sh"
  reload_tmux_environment
) || die "Reloading the tmux config failed."

tmux display-message "dev-environment updated to $(git -C "$repo" log -1 --format='%h %s') and tmux config reloaded"
