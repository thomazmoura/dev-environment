Write-Output "`n->> Installing tpm"
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm --depth 1
#
# install the plugins
~/.tmux/plugins/tpm/bin/install_plugins

