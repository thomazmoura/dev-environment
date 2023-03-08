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

# Dotnet tools instalation
COPY --chown=developer:developer modules/dotnet-tools /home/developer/.modules/dotnet-tools
RUN pwsh -NoProfile -File /home/developer/.modules/dotnet-tools/dotnettools-setup.ps1

# Azure-CLI extensions installation
COPY --chown=developer:developer modules/azure-cli-extensions /home/developer/.modules/azure-cli-extensions
RUN export PATH="$HOME/.local/bin:$PATH" && pip install azure-cli && chmod +x /home/developer/.modules/azure-cli-extensions/azure-extensions-setup.sh && /home/developer/.modules/azure-cli-extensions/azure-extensions-setup.sh

# Delta diff installation
COPY --chown=developer:developer modules/git /home/developer/.modules/git
RUN pwsh -NoProfile -File /home/developer/.modules/git/delta-setup.ps1

# Tmux plugins installation
COPY --chown=developer:developer modules/tmux /home/developer/.modules/tmux
COPY --chown=developer:developer DockerUbuntu/tmux.conf /home/developer/.tmux.conf
ENV TMUX_PLUGIN_MANAGER_PATH /home/developer/.tmux/plugins/
RUN chmod +x /home/developer/.modules/tmux/tpm-setup.sh && /home/developer/.modules/tmux/tpm-setup.sh

# NeoVim LSP Configuration
COPY --chown=developer:developer modules/neovim-lsp /home/developer/.modules/neovim-lsp
RUN pwsh -NoProfile -File /home/developer/.modules/neovim-lsp/Setup-NeoVimLSP.ps1

# Shell config folders and .files
RUN pwsh -c "New-Item -ItemType SymbolicLink -Path /home/developer/.vim -Target /home/developer/.local/share/nvim/site"
COPY --chown=developer:developer DockerUbuntu/config/powershell/profile.ps1 /home/developer/.config/powershell/Microsoft.PowerShell_profile.ps1
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

