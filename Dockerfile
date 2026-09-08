ARG DockerBase
FROM $DockerBase
  
# Node installation
RUN mkdir -p /home/developer/.modules
COPY --chown=developer:developer modules/node /home/developer/.modules/node
RUN chmod +x /home/developer/.modules/node/Setup-NVS.ps1 && pwsh -NoProfile -Command /home/developer/.modules/node/Setup-NVS.ps1

# NeoVim Requirements
COPY --chown=developer:developer modules/neovim-base /home/developer/.modules/neovim-base
RUN pwsh -NoProfile -File /home/developer/.modules/neovim-base/neovim-setup.ps1

# NeoVim Plug Modules installation
RUN mkdir -p /home/developer/.local/share/nvim/site/autoload
COPY --chown=developer:developer modules/vim-autoload /home/developer/.local/share/nvim/site/autoload
COPY --chown=developer:developer modules/neovim-plug/plug.vimrc /home/developer/.modules/neovim-plug/plug.vimrc
RUN pwsh -c '/home/developer/neovim/bin/nvim -n -u /home/developer/.modules/neovim-plug/plug.vimrc -i NONE +"PlugInstall" +"qa"' || pwsh -c '/home/developer/neovim/bin/nvim -n -u /home/developer/.modules/neovim-plug/plug.vimrc -i NONE +"PlugInstall" +"qa"' 

# Azure-CLI extensions installation
COPY --chown=developer:developer modules/azure-cli-extensions /home/developer/.modules/azure-cli-extensions
RUN export PATH="$HOME/.local/bin:$PATH" && pipx install azure-cli && chmod +x /home/developer/.modules/azure-cli-extensions/azure-extensions-setup.sh && /home/developer/.modules/azure-cli-extensions/azure-extensions-setup.sh

# Delta diff installation
COPY --chown=developer:developer modules/git /home/developer/.modules/git
RUN pwsh -NoProfile -File /home/developer/.modules/git/delta-setup.ps1

# demux (tmux session dashboard, bound to prefix + e as a sticky sidebar)
COPY --chown=developer:developer modules/demux /home/developer/.modules/demux
COPY --chown=developer:developer modules/demux/demux.toml /home/developer/.config/demux/demux.toml
RUN pwsh -NoProfile -File /home/developer/.modules/demux/Install-Demux.ps1

# herdr (terminal multiplexer used as the runtime for coding agents; also
# installs the agent state hooks and the Claude Code agent skill)
COPY --chown=developer:developer modules/herdr /home/developer/.modules/herdr
COPY --chown=developer:developer modules/herdr/config.toml /home/developer/.config/herdr/config.toml
RUN pwsh -NoProfile -File /home/developer/.modules/herdr/Install-Herdr.ps1

# agent-radar (reads each coding agent's screen to say which one is waiting on
# you; bound to prefix + t then a/A, and summarised in the status bar). Nothing
# to install -- it is bash plus python3, both already present.
COPY --chown=developer:developer modules/agent-radar /home/developer/.modules/agent-radar
RUN chmod +x /home/developer/.modules/agent-radar/scripts/* /home/developer/.modules/agent-radar/hooks/*

# git-radar (one row per tmux session: branch, commits to push/pull and
# working-tree counts; bound to prefix + t then R). Same story -- bash plus
# python3, nothing to install. It shares the sampling machinery in
# modules/tmux/scripts/radar_cache.py, which the tmux COPY below brings in.
COPY --chown=developer:developer modules/git-radar /home/developer/.modules/git-radar
RUN chmod +x /home/developer/.modules/git-radar/scripts/*

# Tmux plugins installation
COPY --chown=developer:developer modules/tmux /home/developer/.modules/tmux
COPY --chown=developer:developer DockerUbuntu/tmux.conf /home/developer/.tmux.conf
ENV TMUX_PLUGIN_MANAGER_PATH /home/developer/.tmux/plugins/
RUN chmod +x /home/developer/.modules/tmux/tpm-setup.sh && /home/developer/.modules/tmux/tpm-setup.sh

# Dotnet tools instalation script
COPY --chown=developer:developer modules/dotnet-tools /home/developer/.modules/dotnet-tools

# NeoVim LSP Configuration
COPY --chown=developer:developer modules/neovim-lsp /home/developer/.modules/neovim-lsp
RUN pwsh -NoProfile -File /home/developer/.modules/neovim-lsp/Setup-NeoVimLSP.ps1

# Shell config folders and .files
RUN pwsh -c "New-Item -ItemType SymbolicLink -Path /home/developer/.vim -Target /home/developer/.local/share/nvim/site"
COPY --chown=developer:developer DockerUbuntu/bashrc /home/developer/.bashrc
COPY --chown=developer:developer DockerUbuntu/vimrc /home/developer/.config/nvim/init.vim

COPY --chown=developer:developer modules/shell /home/developer/.shell
COPY --chown=developer:developer modules/powershell-config /home/developer/.config/powershell
COPY --chown=developer:developer modules/nvim-config /home/developer/.config/nvim
COPY --chown=developer:developer modules/vim /home/developer/.local/share/nvim/site

# Container startup configuration
COPY --chown=developer:developer modules/entrypoint-config /home/developer/.modules/entrypoint

# Start the environment
ENV TERM xterm-256color
WORKDIR /home/developer/code
CMD ["/opt/microsoft/powershell/7/pwsh", "-NoProfile", "-Command", "/home/developer/.modules/entrypoint/Start-DevSession.ps1 && tail -f /dev/null"]

