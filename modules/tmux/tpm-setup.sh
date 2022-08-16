echo "\n->> Installing tpm"
git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm --depth 1

# install the plugins
~/.tmux/plugins/tpm/bin/install_plugins

apt update && apt install procps && rm -rf /var/lib/apt/lists/*

